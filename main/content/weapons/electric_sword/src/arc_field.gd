class_name ArcField
extends RefCounted

# ---------------------------------------------------------------------------
# Soft sword-shaped volume + a real-time stochastic lightning-leader model.
#
# References used for the model:
#   L. Niemeyer, L. Pietronero, H. J. Wiesmann,
#     "Fractal Dimension of Dielectric Breakdown", PRL 52, 1033 (1984).
#   "On the development of a lightning leader model for tortuous or branched
#     channels - Part I / II", J. Electrostatics 66 (2008).
#   "A stepped leader model for lightning including charge distribution in
#     branched channels", J. Appl. Phys. 116 (2014).
#   "Numerical Simulation of Stepping and Branching Processes in Negative
#     Lightning Leaders", JGR Atmospheres (2020).
#   "Dynamics of branching of negative downward lightning leaders",
#     Appl. Phys. Lett. (2017).
#   Z. Wang et al., "Quantitative modeling of streamer discharge branching in
#     air", Plasma Sources Sci. Technol. (2023).
#   F. Vera, "The tortuous behavior of lightning", arXiv:nlin/0206011.
#
# This is a real-time stochastic leader model, not a full 3D plasma solver:
# leaders take correlated/tortuous steps, branch stochastically with a
# field- and charge-dependent probability, and split charge/width among
# children. The sword-shaped density acts as the insulating boundary of the
# volume; escape leaders deliberately drop that constraint.
# ---------------------------------------------------------------------------

const TIP_Y := 2.20
const BASE_Y := 0.060

# A real sword envelope: nearly parallel for the lower half, then a long
# convex taper into a point. Keep the sheet and the arc volume on the same
# profile so they agree at every height.
const BLADE_BASE_HALF_X := 0.148
const BLADE_MID_HALF_X := 0.132
const BLADE_BASE_HALF_Z := 0.050
const BLADE_MID_HALF_Z := 0.040
const BLADE_TIP_WIDTH_START := 0.60

const INSIDE_THRESHOLD := 0.040
const MAX_GENERATION := 3
const ESCAPE_MAX_GENERATION := 4
const ESCAPE_SPATIAL_SCALE := 0.5

func blade_half_width(y: float) -> float:
	if y <= BASE_Y or y >= TIP_Y:
		return 0.0
	var t := (y - BASE_Y) / (TIP_Y - BASE_Y)
	if t < BLADE_TIP_WIDTH_START:
		return lerpf(BLADE_BASE_HALF_X, BLADE_MID_HALF_X, t / BLADE_TIP_WIDTH_START)
	var v := (t - BLADE_TIP_WIDTH_START) / (1.0 - BLADE_TIP_WIDTH_START)
	return BLADE_MID_HALF_X * pow(1.0 - v, 0.78)

func blade_half_thickness(y: float) -> float:
	if y <= BASE_Y or y >= TIP_Y:
		return 0.0
	var t := (y - BASE_Y) / (TIP_Y - BASE_Y)
	if t < BLADE_TIP_WIDTH_START:
		return lerpf(BLADE_BASE_HALF_Z, BLADE_MID_HALF_Z, t / BLADE_TIP_WIDTH_START)
	var v := (t - BLADE_TIP_WIDTH_START) / (1.0 - BLADE_TIP_WIDTH_START)
	return BLADE_MID_HALF_Z * pow(1.0 - v, 0.82)

func blade_density(p: Vector3) -> float:
	var w := blade_half_width(p.y)
	var th := blade_half_thickness(p.y)
	if w <= 0.0001 or th <= 0.0001:
		return 0.0
	var qx := absf(p.x) / w
	var qz := absf(p.z) / th
	# Flat-topped volume: the inside is nearly uniformly available; only the
	# outermost fringe fades out, so the boundary is statistical rather than
	# a drawn line.
	return exp(-pow(qx, 10.0) - pow(qz / 0.92, 8.0))

func inside_blade(p: Vector3) -> bool:
	if p.y < BASE_Y - 0.01 or p.y > TIP_Y:
		return false
	return blade_density(p) > INSIDE_THRESHOLD

func sample_points(rng: RandomNumberGenerator) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var bands := 44
	for i in range(bands):
		var t0 := float(i) / float(bands)
		var t1 := float(i + 1) / float(bands)
		var y0 := lerpf(BASE_Y + 0.008, TIP_Y - 0.015, t0)
		var y1 := lerpf(BASE_Y + 0.008, TIP_Y - 0.015, t1)
		var ym := (y0 + y1) * 0.5
		var wm := blade_half_width(ym)
		if wm < 0.003:
			continue
		var wanted := clampi(int(round(2.0 + 14.0 * (wm / BLADE_BASE_HALF_X))), 3, 16)
		var got := 0
		var attempts := 0
		while got < wanted and attempts < wanted * 22:
			attempts += 1
			var y := rng.randf_range(y0, y1)
			var w := blade_half_width(y)
			var th := blade_half_thickness(y)
			if w < 0.002 or th < 0.002:
				continue
			var p := Vector3(
				rng.randf_range(-w * 1.02, w * 1.02),
				y,
				rng.randf_range(-th * 1.04, th * 1.04)
			)
			if rng.randf() <= blade_density(p):
				points.append(p)
				got += 1
		if got < wanted:
			points.append(Vector3(0.0, (y0 + y1) * 0.5, 0.0))
	return points

# ---------------------------------------------------------------------------
# Generation entry points
# ---------------------------------------------------------------------------

func grow(rng: RandomNumberGenerator, root_scale: float = 1.0) -> Array:
	var points := sample_points(rng)
	var lower: Array[int] = []
	var middle: Array[int] = []
	var upper: Array[int] = []
	var edge_left: Array[int] = []
	var edge_right: Array[int] = []
	for i in range(points.size()):
		var p := points[i]
		if p.y < BASE_Y + 0.16:
			lower.append(i)
		elif p.y < TIP_Y - 0.34:
			middle.append(i)
		else:
			upper.append(i)
		var w := blade_half_width(p.y)
		if w > 0.01 and absf(p.x) > w * 0.62:
			if p.x < 0.0:
				edge_left.append(i)
			else:
				edge_right.append(i)

	var edges: Array = []
	var root_pool := middle if not middle.is_empty() else lower

	var main_count := maxi(2, int(round(3.0 * root_scale)))
	var volume_count := maxi(4, int(round(10.0 * root_scale)))
	var side_count := maxi(2, int(round(4.0 * root_scale)))
	var tip_count := maxi(1, int(round(2.0 * root_scale)))

	# Main leaders emerge from the generator / lower blade and are pulled
	# toward the point. They carry the highest charge and branch the most.
	for i in range(main_count):
		if lower.is_empty():
			break
		var idx := lower[rng.randi_range(0, lower.size() - 1)]
		var start := points[idx]
		start.y = maxf(start.y, BASE_Y + 0.018)
		var dir := Vector3(
			rng.randf_range(-0.30, 0.30),
			1.0,
			rng.randf_range(-0.35, 0.35)
		).normalized()
		_grow_leader(edges, start, dir, 1.0, 0, rng, true,
			rng.randi_range(16, 22), 0.14, rng.randf() * TAU)

	# A corona of shorter stochastic leaders fills the volume. These are the
	# equivalent of the streamer corona / space stems around a leader.
	for i in range(volume_count):
		if root_pool.is_empty():
			break
		var idx := root_pool[rng.randi_range(0, root_pool.size() - 1)]
		var start := points[idx]
		var dir := Vector3(
			rng.randf_range(-0.85, 0.85),
			rng.randf_range(-0.15, 1.0),
			rng.randf_range(-0.75, 0.75)
		).normalized()
		_grow_leader(edges, start, dir, rng.randf_range(0.35, 0.62), 1, rng, true,
			rng.randi_range(3, 6), 0.24, rng.randf() * TAU)

	# Random side streamers keep the silhouette filled without drawing a
	# fixed outline. New positions/directions every restrike.
	for side in range(2):
		var pool: Array[int] = edge_left if side == 0 else edge_right
		if pool.is_empty():
			continue
		var n_side := maxi(1, int(round(float(side_count) * 0.5)))
		for i in range(n_side):
			var idx := pool[rng.randi_range(0, pool.size() - 1)]
			var start := points[idx]
			var sign := -1.0 if side == 0 else 1.0
			var dir := Vector3(
				-sign * rng.randf_range(0.25, 0.8),
				rng.randf_range(0.3, 1.0),
				rng.randf_range(-0.55, 0.55)
			).normalized()
			_grow_leader(edges, start, dir, rng.randf_range(0.32, 0.55), 1, rng, true,
				rng.randi_range(3, 6), 0.22, rng.randf() * TAU)

	# Small central leaders near the point. The density taper plus the field
	# attraction makes them converge into a sharp tip.
	for i in range(tip_count):
		if upper.is_empty():
			break
		var idx := upper[rng.randi_range(0, upper.size() - 1)]
		var start := points[idx]
		start.x *= 0.30
		var dir := Vector3(
			rng.randf_range(-0.14, 0.14),
			1.0,
			rng.randf_range(-0.12, 0.12)
		).normalized()
		_grow_leader(edges, start, dir, 0.65, 1, rng, true,
			rng.randi_range(4, 7), 0.20, rng.randf() * TAU)

	_add_stray_sparks(points, rng, edges, maxi(2, int(round(5.0 * root_scale))))
	return edges

## A deliberately stable, low-jitter skeleton for the silhouette: two edge
## channels that meet in a point plus an optional hot spine. The stochastic
## leaders still supply all the character; this scaffold only keeps the
## sword readable at a glance.
func edge_scaffold(rng: RandomNumberGenerator, spine := true) -> Array:
	var edges: Array = []
	var steps := 26
	for side: float in [-1.0, 1.0]:
		var prev := Vector3(side * blade_half_width(BASE_Y + 0.012) * 0.94, BASE_Y + 0.012,
			rng.randf_range(-0.012, 0.012))
		for i in range(steps):
			var t0 := float(i) / float(steps)
			var t1 := float(i + 1) / float(steps)
			var y1 := lerpf(BASE_Y + 0.012, TIP_Y, t1)
			var w := blade_half_width(y1)
			var x := side * w * rng.randf_range(0.93, 0.99)
			var z := rng.randf_range(-0.30, 0.30) * blade_half_thickness(y1)
			var next := Vector3(x, y1, z)
			if t1 > 0.985:
				next = Vector3(0.0, TIP_Y, 0.0)
			edges.append(_make_edge(prev, next, 0.0145, 1.95,
				rng, true, rng.randf() * TAU))
			prev = next

	# Hot centre channel: shorter than the edges so the tip stays a point.
	if spine:
		var n := 15
		var p := Vector3(0.0, BASE_Y + 0.02, 0.0)
		for i in range(n):
			var y := lerpf(BASE_Y + 0.02, TIP_Y * 0.80, float(i + 1) / float(n))
			var q := Vector3(rng.randf_range(-0.004, 0.004), y, rng.randf_range(-0.004, 0.004))
			edges.append(_make_edge(p, q, 0.0085, 1.20, rng, true, rng.randf() * TAU))
			p = q

	# Sparse cross filaments give the interior some structure.
	for i in range(7):
		var y := lerpf(BASE_Y + 0.10, TIP_Y * 0.86, (float(i) + 0.5) / 7.0)
		var w := blade_half_width(y) * rng.randf_range(0.55, 0.92)
		var a := Vector3(-w, y + rng.randf_range(-0.02, 0.02), rng.randf_range(-0.01, 0.01))
		var b := Vector3(w, y + rng.randf_range(-0.02, 0.02), rng.randf_range(-0.01, 0.01))
		edges.append(_make_edge(a, b, 0.0065, 0.80, rng, false, rng.randf() * TAU))
	return edges

func grow_escape_one(rng: RandomNumberGenerator) -> Array:
	var edges: Array = []
	# Exponential size distribution: many tiny licks, a few very large trees.
	var u := rng.randf()
	var size := minf(1.8, -log(1.0 - u) * 0.26)
	size = maxf(size, 0.04)
	var y := rng.randf_range(0.16, TIP_Y - 0.04)
	var w := blade_half_width(y)
	var th := blade_half_thickness(y)
	if w < 0.004:
		return edges
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var start := Vector3(
		side * w * rng.randf_range(0.96, 1.08),
		y,
		rng.randf_range(-th, th)
	)
	var dir := Vector3(
		side * rng.randf_range(0.55, 1.0),
		rng.randf_range(-0.55, 0.95),
		rng.randf_range(-0.85, 0.85)
	).normalized()
	var steps := clampi(int(round(size / 0.13)), 1, 14)
	var charge := clampf(0.18 + 0.90 * minf(size, 1.3), 0.18, 1.35)
	var branch_p := clampf(0.06 + 0.50 * minf(size, 1.2) / 1.2, 0.05, 0.62)
	_grow_leader(edges, start, dir, charge, 0, rng, false, steps, branch_p, rng.randf() * TAU)
	return edges

# ---------------------------------------------------------------------------
# Stochastic leader growth
# ---------------------------------------------------------------------------

func _grow_leader(
	edges: Array,
	start: Vector3,
	dir: Vector3,
	charge: float,
	generation: int,
	rng: RandomNumberGenerator,
	confined: bool,
	steps: int,
	branch_prob: float,
	phase: float
) -> void:
	var p := start
	var d := dir.normalized()
	var q := clampf(charge, 0.06, 1.4)
	var max_turn := 0.40 if confined else 0.92
	var field_weight := 0.50 if confined else 0.06
	var inertia := 0.60 if confined else 0.48
	var noise_weight := 0.26 if confined else 0.52

	for step in range(steps):
		var desired := (
			d * inertia
			+ _random_unit(rng) * noise_weight
			+ (_field_dir(p) * field_weight if confined else d * field_weight)
		).normalized()
		var angle := d.angle_to(desired)
		if angle > max_turn:
			var axis := d.cross(desired)
			if axis.length_squared() < 1e-6:
				axis = Vector3.UP
			desired = d.rotated(axis.normalized(), max_turn)

		var base_step := rng.randf_range(0.042, 0.100) if confined else rng.randf_range(0.075, 0.165)
		if not confined:
			base_step *= ESCAPE_SPATIAL_SCALE
		var step_len := base_step * (0.80 + 0.45 * q)
		var np := p + desired * step_len

		if confined:
			var tries := 0
			while not inside_blade(np) and tries < 5:
				var target := Vector3(0.0, TIP_Y, p.z)
				var inward := (target - p).normalized()
				desired = (inward * 0.72 + _random_unit(rng) * 0.28).normalized()
				np = p + desired * step_len
				tries += 1
			if not inside_blade(np):
				break

		# Slight brightness/width hierarchy. Charge is not strictly conserved
		# at a fork, but children are consistently thinner and dimmer.
		var width := lerpf(0.020, 0.100, pow(clampf(q, 0.0, 1.4), 0.65))
		var energy := minf(2.15, 0.42 + 1.60 * q)
		var is_leader := q > 0.35
		edges.append(_make_edge(p, np, width, energy, rng, is_leader, phase))

		# Stochastic branching. The probability rises with charge and with
		# the local field (approximated by proximity to the point).
		if generation < (MAX_GENERATION if confined else ESCAPE_MAX_GENERATION):
			var field_boost := _local_field_boost(np) if confined else 1.0
			var bp := branch_prob * (0.42 + 0.58 * clampf(q, 0.0, 1.2)) * field_boost
			if step >= 1 and step < steps - 1 and q > 0.14 and rng.randf() < bp:
				var child_q := q * rng.randf_range(0.30, 0.52)
				var child_dir := _branch_dir(d, rng, confined)
				var child_steps := maxi(2, int(round(float(steps) * rng.randf_range(0.34, 0.62))))
				_grow_leader(edges, np, child_dir, child_q, generation + 1, rng,
					confined, child_steps, branch_prob * 0.86, phase + rng.randf_range(0.5, 2.5))
				q *= 0.982

		p = np
		d = desired
		if confined and p.y > TIP_Y - 0.02:
			break

func _field_dir(p: Vector3) -> Vector3:
	# The point is the counter-electrode. The field pulls in x/y but not in z,
	# preserving the blade's real thickness.
	var target := Vector3(0.0, TIP_Y, p.z)
	var to_target := target - p
	if to_target.length_squared() < 1e-8:
		return Vector3.UP
	var center := Vector3(-p.x * 0.65, 0.0, 0.0)
	return (to_target.normalized() * 0.40 + center * 0.08).normalized()

func _local_field_boost(p: Vector3) -> float:
	# Stronger near the point/edge where the field concentrates.
	var t := clampf(p.y / TIP_Y, 0.0, 1.0)
	return 0.78 + 0.45 * t

func _branch_dir(dir: Vector3, rng: RandomNumberGenerator, confined: bool) -> Vector3:
	var axis := _random_unit(rng)
	var perp := axis.cross(dir)
	if perp.length_squared() < 1e-6:
		perp = dir.cross(Vector3.UP)
	perp = perp.normalized()
	var angle := rng.randf_range(0.32, 0.82) if confined else rng.randf_range(0.45, 1.10)
	return (dir * cos(angle) + perp * sin(angle)).normalized()

func _random_unit(rng: RandomNumberGenerator) -> Vector3:
	var v := Vector3(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0)
	)
	if v.length_squared() < 1e-6:
		return Vector3.UP
	return v.normalized()

func _make_edge(
	a: Vector3,
	b: Vector3,
	width: float,
	energy: float,
	rng: RandomNumberGenerator,
	leader: bool,
	phase: float
) -> Dictionary:
	return {
		"a": a,
		"b": b,
		"depth": 0,
		"width": width,
		"energy": energy,
		"hue": rng.randf_range(0.0, 1.0),
		"phase": phase + rng.randf_range(0.0, 0.7),
		"leader": leader,
	}

func _add_stray_sparks(points: Array[Vector3], rng: RandomNumberGenerator, edges: Array, count: int) -> void:
	if points.size() < 8:
		return
	for i in range(count):
		var a := points[rng.randi_range(0, points.size() - 1)]
		var b := points[rng.randi_range(0, points.size() - 1)]
		var d := a.distance_to(b)
		if d < 0.03 or d > 0.16:
			continue
		edges.append(_make_edge(a, b, 0.015, 0.55, rng, false, rng.randf() * TAU))
