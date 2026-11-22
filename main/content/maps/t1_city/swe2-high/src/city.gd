extends RefCounted

## NEON REACH — procedural city plan over 4 km × 2.5 km.
## Road graph is a warped grid + diagonal avenues; each block becomes a
## list of building lots the builder turns into meshes.

const X0 := -2000.0
const X1 := 2000.0
const Z0 := -1250.0
const Z1 := 1250.0

var rng := RandomNumberGenerator.new()

# main avenues: coarse warp so the grid reads hand-planned, not machined
var warp_seed := 7311
var diag_a: PackedVector2Array        # NE-SW diagonal avenue
var diag_b: PackedVector2Array        # W-E arc towards the waterfront
var river_pts: PackedVector2Array     # canal through the north half

var blocks: Array = []                # {poly,zone,roads}
var roads_major: Array = []           # PackedVector2Array polylines
var roads_minor: Array = []
var lots: Array = []                  # {poly,zone,frontage}

enum Zone { RES, CBD, SCH, IND, PARK, WATER }


func _init(seed: int = 7311) -> void:
	rng.seed = seed
	warp_seed = seed


func _h2(x: int, z: int, salt: int) -> float:
	var s := sin(float(x) * 127.1 + float(z) * 311.7 + float(salt) * 17.13) * 43758.5453
	return s - floor(s)


func build() -> void:
	_river()
	_avenues()
	_grid_blocks()
	_subdivide_lots()


# ---------------------------------------------------------------- river -----
func _river() -> void:
	# canal: enters NE, arcs across the city, exits SW through the harbour
	var pts := PackedVector2Array()
	var n := 60
	for i in range(n + 1):
		var t := float(i) / float(n)
		var x := lerpf(2100.0, -1900.0, t)
		var z := -600.0 - 320.0 * sin(t * PI * 1.15) + 260.0 * t
		z += sin(t * 21.0 + 3.7) * 40.0
		pts.append(Vector2(x, z))
	river_pts = pts


func river_dist(p: Vector2) -> float:
	var d := 1e9
	for i in river_pts.size():
		d = minf(d, p.distance_to(river_pts[i]))
	return d


# ------------------------------------------------------------- avenues -----
func _avenues() -> void:
	# diagonal A: from south harbour up to NE industrial
	var a := PackedVector2Array()
	for i in 40:
		var t := float(i) / 39.0
		a.append(Vector2(lerpf(-1500.0, 1800.0, t),
			lerpf(900.0, -700.0, t) + sin(t * 9.0) * 90.0))
	# diagonal B: gentle arc linking CBD to school district
	var b := PackedVector2Array()
	for i in 40:
		var t := float(i) / 39.0
		b.append(Vector2(lerpf(-1900.0, 1100.0, t),
			lerpf(-200.0, 1050.0, t) - sin(t * PI) * 160.0))
	diag_a = a
	diag_b = b
	roads_major.append(a)
	roads_major.append(b)


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _poly_dist(p: Vector2, poly: PackedVector2Array) -> float:
	var d := 1e9
	for i in range(poly.size() - 1):
		d = minf(d, _seg_dist(p, poly[i], poly[i + 1]))
	return d


# ---------------------------------------------------------------- blocks ---
func _warp(p: Vector2) -> Vector2:
	# ±25 m of low-frequency warp keeps the grid organic
	var w := Vector2(
		sin(p.y * 0.004 + warp_seed * 0.01) * 22.0,
		cos(p.x * 0.003 + warp_seed * 0.02) * 20.0)
	return p + w


func zone_at(p: Vector2) -> int:
	# CBD spine along diag_a middle; harbour/industrial north of river,
	# residential SW, schools SE
	if river_dist(p) < 70.0:
		return Zone.WATER
	if p.y < river_at(p.x) - 80.0:
		return Zone.IND
	var dcbd := _poly_dist(p, diag_a)
	var r := sqrt(p.x * p.x + p.y * p.y)
	if dcbd < 160.0 and r < 900.0:
		return Zone.CBD
	if p.x > 400.0 and p.y > 300.0:
		return Zone.SCH
	if _h2(int(p.x / 500.0), int(p.y / 500.0), 5) < 0.08:
		return Zone.PARK
	return Zone.RES


func river_at(x: float) -> float:
	# rough lookup of river z for a given x (only used for zoning)
	var best := 0.0
	var bx := 1e9
	for i in river_pts.size():
		if absf(river_pts[i].x - x) < bx:
			bx = absf(river_pts[i].x - x)
			best = river_pts[i].y
	return best


func _grid_blocks() -> void:
	# 190 m superblocks — tighter urban fabric, more blocks = denser city
	var step := 190.0
	var nx := int((X1 - X0) / step)
	var nz := int((Z1 - Z0) / step)
	for ix in nx:
		for iz in nz:
			var cx := X0 + (ix + 0.5) * step
			var cz := Z0 + (iz + 0.5) * step
			var c := _warp(Vector2(cx, cz))
			if river_dist(c) < 55.0:
				continue
			# avenues carve through blocks — narrower cut so buildings
			# still wall the corridor edge
			if _poly_dist(c, diag_a) < 32.0 or _poly_dist(c, diag_b) < 28.0:
				continue
			var zone := zone_at(c)
			var poly := _block_poly(c, step * 0.92, zone)
			blocks.append({"poly": poly, "zone": zone, "c": c})
	# minor streets run along the block-grid lines, not the lot outline —
	# tracing the rotated parcel edge drew a giant pale ramp across lots
	for ix in range(nx + 1):
		var x := X0 + ix * step
		var p := PackedVector2Array()
		for iz in range(nz + 1):
			var z := Z0 + iz * step
			p.append(_warp(Vector2(x, z)))
		roads_minor.append(p)
	for iz in range(nz + 1):
		var z := Z0 + iz * step
		var p := PackedVector2Array()
		for ix in range(nx + 1):
			var x := X0 + ix * step
			p.append(_warp(Vector2(x, z)))
		roads_minor.append(p)


func _block_poly(c: Vector2, size: float, zone: int) -> PackedVector2Array:
	# 4–6-sided lot polygon; CBD keeps right angles, others get trimmed
	# corners so buildings interlock like hand-laid parcels
	var poly := PackedVector2Array()
	var n := 4 if zone == Zone.CBD else 4 + int(_h2(int(c.x), int(c.y), 3) * 3.0)
	var h := size * 0.5
	var jitter := 0.06 * h if zone != Zone.CBD else 0.02 * h
	for i in n:
		var a := TAU * float(i) / float(n) + PI * 0.25
		var r := h * (1.0 + (_h2(int(c.x) + i * 7, int(c.y), 9) - 0.5) * jitter * 0.06)
		poly.append(Vector2(c.x + cos(a) * r, c.y + sin(a) * r))
	return poly


# ----------------------------------------------------------------- lots ----
func _subdivide_lots() -> void:
	for b in blocks:
		var poly: PackedVector2Array = b["poly"]
		var zone: int = b["zone"]
		var c: Vector2 = b["c"]
		if zone == Zone.WATER or zone == Zone.PARK:
			continue
		var n: int
		match zone:
			Zone.CBD: n = 2 + int(_h2(int(c.x), int(c.y), 21) * 4.0)
			Zone.IND: n = 2 + int(_h2(int(c.x), int(c.y), 22) * 3.0)
			Zone.SCH: n = 2 + int(_h2(int(c.x), int(c.y), 23) * 3.0)
			_:        n = 4 + int(_h2(int(c.x), int(c.y), 24) * 6.0)
		# tile the block into a sub-grid: each lot is an axis-aligned
		# parcel with a slight jitter — rows of real buildings, not a
		# scatter of rotated hexagons
		var cols_n := int(ceil(sqrt(float(n))))
		var rows_n := int(ceil(float(n) / float(cols_n)))
		var mn := poly[0]
		var mx := poly[0]
		for v in poly:
			mn.x = minf(mn.x, v.x); mn.y = minf(mn.y, v.y)
			mx.x = maxf(mx.x, v.x); mx.y = maxf(mx.y, v.y)
		var bw := mx.x - mn.x
		var bd := mx.y - mn.y
		var gap := 6.0
		var cw := (bw - gap * (cols_n + 1)) / float(cols_n)
		var cd := (bd - gap * (rows_n + 1)) / float(rows_n)
		var li := 0
		for r in rows_n:
			for cidx in cols_n:
				if li >= n:
					break
				var lx := mn.x + gap + cidx * (cw + gap)
				var lz := mn.y + gap + r * (cd + gap)
				var jw := cw * (0.9 + _h2(int(c.x) + li, int(c.y), 25) * 0.2)
				var jd := cd * (0.9 + _h2(int(c.x), int(c.y) + li, 26) * 0.2)
				var sub := PackedVector2Array([
					Vector2(lx, lz), Vector2(lx + jw, lz),
					Vector2(lx + jw, lz + jd), Vector2(lx, lz + jd)])
				# a lot never straddles an avenue — drop parcels whose
				# centre or far edge reaches into the carriageway
				var lc := Vector2(lx + jw * 0.5, lz + jd * 0.5)
				var reach := maxf(jw, jd) * 0.62
				if _poly_dist(lc, diag_a) < 18.0 + reach:
					continue
				if _poly_dist(lc, diag_b) < 16.0 + reach:
					continue
				lots.append({"poly": sub, "zone": zone,
					"seed": int(_h2(int(c.x) + li * 31, int(c.y) + li * 17, 27) * 1e7)})
				li += 1
	# street wall: line BOTH sides of each avenue with a row of
	# shopfront blocks so the corridor reads as a walled street, not
	# a bare clearing — these are extra lots, not shifts
	for av in [diag_a, diag_b]:
		for i in range(av.size() - 1):
			var p0: Vector2 = av[i]
			var p1: Vector2 = av[i + 1]
			var dir2 := (p1 - p0).normalized()
			var n2 := Vector2(-dir2.y, dir2.x)
			for side in [-1.0, 1.0]:
				for j in 3:
					var t := (float(j) + _h2(i * 7 + j, int(side * 3), 41)) / 3.0
					# face sits on the pavement back-edge: kerb 11 +
					# walk 3 + half-depth → centre ~18–20 m off centreline
					var px: float = p0.x + (p1.x - p0.x) * t + n2.x * 18.0 * side
					var pz: float = p0.y + (p1.y - p0.y) * t + n2.y * 18.0 * side
					# building footprint: narrow wedge facing the avenue
					var fw: float = 9.0 + _h2(i * 3 + j, int(side), 43) * 9.0
					var fd: float = 7.0 + _h2(i * 5 + j, int(side), 47) * 7.0
					var sub := PackedVector2Array([
						Vector2(px - dir2.x * fw - n2.x * fd * side,
							pz - dir2.y * fw - n2.y * fd * side),
						Vector2(px + dir2.x * fw - n2.x * fd * side,
							pz + dir2.y * fw - n2.y * fd * side),
						Vector2(px + dir2.x * fw + n2.x * fd * side,
							pz + dir2.y * fw + n2.y * fd * side),
						Vector2(px - dir2.x * fw + n2.x * fd * side,
							pz - dir2.y * fw + n2.y * fd * side)])
					lots.append({"poly": sub,
						"zone": Zone.RES if _h2(i, j, 51) < 0.6 else Zone.CBD,
						"seed": int(_h2(i * 11 + j, int(side * 7), 53) * 1e7)})
