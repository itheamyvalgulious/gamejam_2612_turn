class_name BuildingGen
extends RefCounted
## Procedural building assembler: footprint shapes, tiered setbacks, podiums,
## style-specific facade furniture (fins / balconies / cornices), roof
## machinery, neon trim. Geometry is merged into chunk buffers of `gen`.

const ST_GLASS := 0
const ST_CORP := 1
const ST_APT := 2
const ST_BRICK := 3
const ST_IND := 4
const ST_SCHOOL := 5
const ST_MEGA := 6
const ST_LUX := 7

const TINTS := [
	Color(0.30, 0.36, 0.44),  # glass blue-grey
	Color(0.42, 0.40, 0.38),  # corporate stone
	Color(0.46, 0.42, 0.38),  # apartment stucco
	Color(0.40, 0.24, 0.20),  # brick
	Color(0.34, 0.36, 0.38),  # industrial metal
	Color(0.48, 0.40, 0.32),  # school brick
	Color(0.28, 0.30, 0.36),  # mega dark
	Color(0.20, 0.20, 0.24),  # luxury dark glass
]

func generate(gen: CityGen, lot: Array, dtype: int) -> void:
	var rng: RandomNumberGenerator = gen.rng
	var P: Dictionary = Districts.params(dtype)
	if P.styles.is_empty():
		return
	var center: Vector3 = CityMath.poly_centroid(lot)
	var dist_f := (center - gen.focus).length()
	var tier := 0 if dist_f < gen.R_DETAIL else (1 if dist_f < gen.R_MID else 2)

	var frame := CityMath.frame_from_quad(lot)
	var w: float = (lot[1] - lot[0]).length() - 2.0
	var d: float = (lot[3] - lot[0]).length() - 2.0
	if w < 7.0 or d < 7.0:
		return
	var style: int = P.styles[rng.randi_range(0, P.styles.size() - 1)]
	var h := clampf(lerpf(P.hmin, P.hmax, pow(rng.randf(), 1.35)) *
			(0.8 + 0.45 * gen.noise_field.get_noise_2d(center.x * 0.9, center.z * 0.9)),
			maxf(P.hmin * 0.6, 5.0), P.hmax * 1.15)
	var fh := 3.1 + rng.randf() * 0.7
	if style == ST_IND:
		fh = 5.5 + rng.randf() * 3.0
	elif style == ST_GLASS or style == ST_LUX:
		fh = 3.6 + rng.randf() * 0.8
	var gh := 4.6 if dtype != Districts.D.INDUSTRIAL else 6.0  # ground floor height
	var seedf := rng.randf() * 997.0

	var fp := _shape_poly(w, d, rng, style)
	var peri := _perimeter(fp)
	var u2 := Vector2(seedf, fh)
	var tint: Color = TINTS[style]
	tint = tint.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.08)
	var col := Color(tint.r, tint.g, tint.b, (float(style) * 16.0 + gh) / 255.0)

	var facade_mat := "facade"
	var use_glass := (style == ST_GLASS or style == ST_LUX) and dist_f < gen.R_GLASS
	if use_glass:
		facade_mat = "glass"

	var ck := gen.chunk_of(center)
	var fb := gen.buf(ck, facade_mat)
	var rb := gen.buf(ck, "roof")

	# ---- tiers: podium + setbacks
	var tiers := []
	var podium_h := 0.0
	if rng.randf() < P.podium and h > 30.0:
		podium_h = floorf(rng.randf_range(10.0, 20.0) / fh) * fh
		tiers.append([0.0, podium_h, 0.0])
	var y := podium_h
	var inset := 0.0
	var tower_inset := rng.randf_range(3.0, 7.0) if podium_h > 0.0 else 0.0
	if podium_h > 0.0:
		tiers.append([podium_h, h * rng.randf_range(0.55, 0.8), tower_inset])
		inset = tower_inset
		y = tiers[1][1]
	if h > 90.0 and rng.randf() < 0.75:
		var y2 := h * rng.randf_range(0.72, 0.88)
		inset += rng.randf_range(1.5, 4.0)
		tiers.append([y, y2, inset])
		y = y2
	tiers.append([y, h, inset])

	var top_poly := fp
	for t in tiers:
		var y0: float = t[0]
		var y1: float = t[1]
		var ins: float = t[2]
		var poly := _inset2d(fp, ins) if ins > 0.01 else fp
		top_poly = poly
		var wp := _to_world(poly, frame)
		fb.prism(wp, y0, y1, u2, col, rb, 0.25, 1.0)
		if tier < 2 and y0 > 0.5:
			# terrace parapet on the setback roof
			var mb := gen.buf(ck, "mech")
			_parapet(mb, _to_world(_inset2d(_prev_poly(tiers, t, fp), 0.0), frame), y0, 0.35, 1.1)

	# ---- style furniture
	if tier < 2:
		_style_furniture(gen, ck, fp, frame, h, fh, style, seedf, rng, tier)

	# ---- roof props
	if tier < 2:
		_roof_props(gen, ck, top_poly, frame, h, rng, style, seedf)

	# ---- neon trim (cyberpunk edge lighting)
	if tier < 2 and rng.randf() < P.neon * 0.8:
		_neon_trim(gen, ck, fp, frame, h, rng, seedf)

	# ---- record for signage / interiors
	var dirs := _facade_dirs(fp, frame)
	gen.sign_targets.append({"pos": center, "h": h, "dirs": dirs, "style": style,
		"seed": seedf, "dtype": dtype, "tier": tier, "w": w, "d": d})
	if use_glass:
		gen.interior_targets.append({"poly": _to_world(top_poly, frame), "fp": _to_world(fp, frame),
			"h": h, "fh": fh, "gh": gh, "seed": seedf, "frame": frame})
	gen.stat_buildings += 1

func _prev_poly(tiers: Array, t: Array, fp: Array) -> Array:
	var ins: float = t[2]
	return _inset2d(fp, ins) if ins > 0.01 else fp

func _perimeter(poly: Array) -> float:
	var p := 0.0
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		p += a.distance_to(b)
	return p

func _inset2d(poly: Array, dist: float) -> Array:
	var n := poly.size()
	var g := Vector2.ZERO
	for p in poly:
		g += p
	g /= float(n)
	var lines := []
	for e in n:
		var a: Vector2 = poly[e]
		var b: Vector2 = poly[(e + 1) % n]
		var dir := (b - a).normalized()
		var nn := Vector2(dir.y, -dir.x)
		var mid := (a + b) * 0.5
		if nn.dot(mid - g) > 0.0:
			nn = -nn
		lines.append([a + nn * dist, dir])
	var out := []
	for k in n:
		var le: Array = lines[(k - 1 + n) % n]
		var lf: Array = lines[k]
		var p0: Vector2 = le[0]
		var d0: Vector2 = le[1]
		var p1: Vector2 = lf[0]
		var d1: Vector2 = lf[1]
		var cr := d0.x * d1.y - d0.y * d1.x
		if absf(cr) < 1e-6:
			out.append(p1)
		else:
			var t := ((p1.x - p0.x) * d1.y - (p1.y - p0.y) * d1.x) / cr
			out.append(p0 + d0 * t)
	return out

func _to_world(poly: Array, frame: Transform3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		var wp: Vector3 = frame * Vector3(p.x, 0, p.y)
		out.append(Vector2(wp.x, wp.z))
	return out

func _shape_poly(w: float, d: float, rng: RandomNumberGenerator, style: int) -> Array:
	var hw := w * 0.5
	var hd := d * 0.5
	var r := rng.randf()
	var base := [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]
	if style == ST_IND:
		return base
	if r < 0.45:
		return base
	elif r < 0.62:
		# chamfered corner
		var c := rng.randf_range(0.15, 0.35) * minf(w, d)
		var k := rng.randi_range(0, 3)
		var out := []
		for i in 4:
			if i == k:
				var p: Vector2 = base[i]
				var prev: Vector2 = base[(i + 3) % 4]
				var nxt: Vector2 = base[(i + 1) % 4]
				out.append(p.lerp(prev, c / p.distance_to(prev)))
				out.append(p.lerp(nxt, c / p.distance_to(nxt)))
			else:
				out.append(base[i])
		return out
	elif r < 0.82:
		# L shape: cut a corner rectangle
		var cw := rng.randf_range(0.3, 0.45) * w
		var cd := rng.randf_range(0.3, 0.45) * d
		var sx := 1.0 if rng.randf() < 0.5 else -1.0
		var sz := 1.0 if rng.randf() < 0.5 else -1.0
		var x0 := hw * sx
		var z0 := hd * sz
		return [
			Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd),
			Vector2(x0 - cw * sx, hd), Vector2(x0 - cw * sx, z0 - cd * sz),
			Vector2(-hw, z0 - cd * sz)] if sx > 0 and sz > 0 else _rot_poly([
			Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd),
			Vector2(hw - cw, hd), Vector2(hw - cw, hd - cd), Vector2(-hw, hd - cd)], rng)
	else:
		# U / courtyard notch on one side
		var nw := rng.randf_range(0.25, 0.4) * w
		var nd := rng.randf_range(0.3, 0.45) * d
		return [
			Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd),
			Vector2(nw * 0.5, hd), Vector2(nw * 0.5, hd - nd),
			Vector2(-nw * 0.5, hd - nd), Vector2(-nw * 0.5, hd), Vector2(-hw, hd)]

func _rot_poly(poly: Array, rng: RandomNumberGenerator) -> Array:
	var k := rng.randi_range(0, 3)
	var out := []
	for i in poly.size():
		out.append(poly[(i + k) % poly.size()])
	return out

func _facade_dirs(fp: Array, frame: Transform3D) -> Array:
	var out := []
	var n := fp.size()
	for i in range(0, n, maxi(1, int(n / 4))):
		var a: Vector2 = fp[i]
		var b: Vector2 = fp[(i + 1) % n]
		var dir := (b - a).normalized()
		var nn := Vector2(dir.y, -dir.x)
		var mid := (a + b) * 0.5
		var wp: Vector3 = frame * Vector3(mid.x, 0, mid.y)
		var wn: Vector3 = (frame.basis * Vector3(nn.x, 0, nn.y)).normalized()
		out.append({"pos": wp, "n": wn, "len": a.distance_to(b)})
	return out

# ---------------------------------------------------------------- furniture

func _style_furniture(gen: CityGen, ck: Vector2i, fp: Array, frame: Transform3D, h: float,
		fh: float, style: int, seedf: float, rng: RandomNumberGenerator, tier: int) -> void:
	var mb := gen.buf(ck, "mech")
	var tb := gen.buf(ck, "trim")
	match style:
		ST_APT:
			# balconies: slab + railing per floor on the two long facades
			var nf := int(h / fh)
			var edges := _long_edges(fp)
			for e in edges:
				var a: Vector2 = e[0]
				var b: Vector2 = e[1]
				var dir := (b - a).normalized()
				var nn := Vector2(dir.y, -dir.x)
				var g2 := _poly_cent2(fp)
				var mid := (a + b) * 0.5
				if nn.dot(mid - g2) < 0.0:
					nn = -nn
				var ln := a.distance_to(b) * 0.82
				var cmid := (a + b) * 0.5 + nn * 0.7
				for f in range(1, nf):
					var y := float(f) * fh
					if y > h - 2.0:
						break
					var c := frame * Vector3(cmid.x, y, cmid.y)
					var xf := Transform3D(Basis(Vector3.UP, atan2(-(frame.basis * Vector3(nn.x, 0, nn.y)).z,
						(frame.basis * Vector3(nn.x, 0, nn.y)).x)), c)
					mb.box(Vector3.ZERO, Vector3(ln, 0.22, 1.5), Vector2.ZERO, Color(0.5, 0.5, 0.5), 0.4, xf)
					mb.box(Vector3.UP * 0.6, Vector3(ln, 1.0, 0.08), Vector2.ZERO, Color(0.3, 0.32, 0.35), 0.4, xf * Transform3D(Basis(), Vector3(0, 0, 0.7)))
		ST_CORP, ST_MEGA:
			# vertical fins every ~4 m on two facades
			var edges := _long_edges(fp)
			for e in edges:
				var a: Vector2 = e[0]
				var b: Vector2 = e[1]
				var ln := a.distance_to(b)
				var dir := (b - a).normalized()
				var nn := Vector2(dir.y, -dir.x)
				var g2 := _poly_cent2(fp)
				var mid := (a + b) * 0.5
				if nn.dot(mid - g2) < 0.0:
					nn = -nn
				var nf := int(ln / 4.2)
				for k in nf + 1:
					var t := float(k) / float(maxi(nf, 1))
					var p2 := a.lerp(b, t) + nn * 0.25
					var c := frame * Vector3(p2.x, h * 0.5, p2.y)
					mb.box(c, Vector3(0.35, h, 0.5), Vector2.ZERO, Color(0.45, 0.45, 0.48), 0.3)
		ST_BRICK, ST_SCHOOL:
			# cornice bands
			for yy in [h - 0.6, fh * 1.0]:
				_parapet(mb, _to_world(fp, frame), yy, 0.3, 0.9)
		ST_IND:
			# ribbed pilasters + big door
			var edges := _long_edges(fp)
			for e in edges:
				var a: Vector2 = e[0]
				var b: Vector2 = e[1]
				var ln := a.distance_to(b)
				var dir := (b - a).normalized()
				var nn := Vector2(dir.y, -dir.x)
				var g2 := _poly_cent2(fp)
				var mid := (a + b) * 0.5
				if nn.dot(mid - g2) < 0.0:
					nn = -nn
				var nf := int(ln / 6.0)
				for k in nf + 1:
					var t := float(k) / float(maxi(nf, 1))
					var p2 := a.lerp(b, t) + nn * 0.2
					var c := frame * Vector3(p2.x, h * 0.5, p2.y)
					mb.box(c, Vector3(0.5, h, 0.6), Vector2.ZERO, Color(0.4, 0.42, 0.45), 0.3)

func _long_edges(fp: Array) -> Array:
	var edges := []
	var n := fp.size()
	for i in n:
		edges.append([fp[i], fp[(i + 1) % n]])
	edges.sort_custom(func(a, b): return a[0].distance_to(a[1]) > b[0].distance_to(b[1]))
	return edges.slice(0, 2)

func _poly_cent2(fp: Array) -> Vector2:
	var g := Vector2.ZERO
	for p in fp:
		g += p
	return g / float(fp.size())

func _parapet(b: MeshBuf, wp: PackedVector2Array, y: float, thick: float, hgt: float) -> void:
	var n := wp.size()
	for i in n:
		var a := Vector3(wp[i].x, y, wp[i].y)
		var bq := Vector3(wp[(i + 1) % n].x, y, wp[(i + 1) % n].y)
		var dir := bq - a
		var ln := dir.length()
		dir = dir.normalized()
		var c := (a + bq) * 0.5 + Vector3.UP * hgt * 0.5
		var xf := Transform3D(Basis(Vector3.UP, atan2(-dir.z, dir.x)), c)
		b.box(Vector3.ZERO, Vector3(ln, hgt, thick), Vector2.ZERO, Color(0.4, 0.4, 0.42), 0.4, xf)

func _roof_props(gen: CityGen, ck: Vector2i, poly: Array, frame: Transform3D, h: float,
		rng: RandomNumberGenerator, style: int, seedf: float) -> void:
	var mb := gen.buf(ck, "mech")
	var bb := gen.buf(ck, "beacon")
	var g2 := _poly_cent2(poly)
	var c2 := frame * Vector3(g2.x, 0, g2.y)
	_parapet(mb, _to_world(poly, frame), h, 0.3, 1.2)
	if style == ST_IND:
		# sawtooth / vents
		for k in rng.randi_range(2, 5):
			var off := Vector3(rng.randf_range(-6, 6), h + 1.2, rng.randf_range(-6, 6))
			mb.box(c2 + off, Vector3(2.2, 2.4, 2.2), Vector2.ZERO, Color(0.4, 0.42, 0.44), 0.4)
		if rng.randf() < 0.6:
			mb.cylinder(c2 + Vector3(rng.randf_range(-5, 5), h, rng.randf_range(-5, 5)),
				1.2, 1.0, rng.randf_range(20.0, 55.0), 10)
			bb.box(c2 + Vector3(0, h + 56.0, 0), Vector3(0.7, 0.7, 0.7))
		return
	if rng.randf() < 0.85:
		var mw := rng.randf_range(4.0, 10.0)
		mb.box(c2 + Vector3(rng.randf_range(-4, 4), h + mw * 0.3, rng.randf_range(-4, 4)),
			Vector3(mw, mw * 0.55, mw * 0.7), Vector2.ZERO, Color(0.3, 0.31, 0.34), 0.3)
	for k in rng.randi_range(1, 4):
		mb.box(c2 + Vector3(rng.randf_range(-8, 8), h + 0.5, rng.randf_range(-8, 8)),
			Vector3(1.6, 1.0, 1.2), Vector2.ZERO, Color(0.45, 0.46, 0.5), 0.5)
	if h > 40.0 and rng.randf() < 0.65:
		mb.cylinder(c2 + Vector3(rng.randf_range(-5, 5), h, rng.randf_range(-5, 5)),
			1.7, 1.5, 4.2, 10, Transform3D.IDENTITY, Vector2.ZERO, Color(0.35, 0.33, 0.3))
	if h > 70.0 and rng.randf() < 0.7:
		var mh := rng.randf_range(6.0, 22.0)
		mb.cylinder(c2 + Vector3(0, h, 0), 0.25, 0.12, mh, 6)
		bb.box(c2 + Vector3(0, h + mh + 0.3, 0), Vector3(0.6, 0.6, 0.6))
	if h > 130.0 and rng.randf() < 0.5:
		# helipad disc
		mb.cylinder(c2 + Vector3(rng.randf_range(-6, 6), h + 0.15, rng.randf_range(-6, 6)),
			9.0, 9.0, 0.3, 18, Transform3D.IDENTITY, Vector2.ZERO, Color(0.15, 0.15, 0.17))
	if rng.randf() < 0.4:
		# solar panels
		for k in rng.randi_range(2, 6):
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * 0.6 - 0.3) *
				Basis(Vector3.RIGHT, -0.5), c2 + Vector3(rng.randf_range(-7, 7), h + 0.7, rng.randf_range(-7, 7)))
			mb.box(Vector3.ZERO, Vector3(2.4, 0.08, 1.5), Vector2.ZERO, Color(0.05, 0.06, 0.12), 0.5, xf)

func _neon_trim(gen: CityGen, ck: Vector2i, fp: Array, frame: Transform3D, h: float,
		rng: RandomNumberGenerator, seedf: float) -> void:
	var tb := gen.buf(ck, "trim")
	var hue := rng.randf()
	var accent := Color.from_hsv(hue, 0.85, 1.0)
	var n := fp.size()
	var k0 := rng.randi_range(0, n - 1)
	for rep in rng.randi_range(1, 2):
		var k := (k0 + rep * int(n / 2)) % n
		var a: Vector2 = fp[k]
		var p := frame * Vector3(a.x, 0, a.y)
		var hh := h * rng.randf_range(0.5, 1.0)
		tb.box(p + Vector3.UP * hh * 0.5, Vector3(0.18, hh, 0.18), Vector2.ZERO, accent, 1.0)
	if rng.randf() < 0.5:
		# roofline strip
		var g2 := _poly_cent2(fp)
		var c2 := frame * Vector3(g2.x, 0, g2.y)
		var wp := _to_world(fp, frame)
		var i := rng.randi_range(0, n - 1)
		var a := Vector3(wp[i].x, h + 0.4, wp[i].y)
		var bq := Vector3(wp[(i + 1) % n].x, h + 0.4, wp[(i + 1) % n].y)
		var dir := bq - a
		var ln := dir.length()
		var xf := Transform3D(Basis(Vector3.UP, atan2(-dir.z, dir.x)), (a + bq) * 0.5)
		tb.box(Vector3.ZERO, Vector3(ln, 0.25, 0.25), Vector2.ZERO, accent, 1.0, xf)
