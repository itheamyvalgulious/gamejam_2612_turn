class_name InfraGen
extends RefCounted
## Elevated highways + interchange, skytrain line & stations, river with
## quays / bridges / harbor cranes. All parametric geometry.

const RIVER_Z0 := 980.0
const RIVER_Z1 := 820.0

# ---------------------------------------------------------------- river field

func river_center(x: float, gen: CityGen) -> float:
	return (lerpf(RIVER_Z0, RIVER_Z1, (x + 1900.0) / 3800.0) +
		sin(x * 0.0016) * 170.0 +
		gen.noise_field.get_noise_2d(x * 0.35 + 400.0, -311.0) * 90.0)

func river_half_width(x: float, gen: CityGen) -> float:
	return 55.0 + gen.noise_bend.get_noise_2d(x * 0.5 + 77.0, 140.0) * 22.0

func dist_to_river(p: Vector3, gen: CityGen) -> float:
	var best := 1e9
	var x := -1900.0
	while x < 1900.0:
		var d := absf(p.z - river_center(x, gen)) + absf(p.x - x) * 0.35
		if d < best:
			best = d
		x += 60.0
	return best

func build_river(gen: CityGen) -> void:
	var wb := MeshBuf.new()
	var qb := MeshBuf.new()
	var x := -1950.0
	var prev_l: Vector3 = Vector3.ZERO
	var prev_r: Vector3 = Vector3.ZERO
	var first := true
	while x < 1950.0:
		var z := river_center(x, gen)
		var hw := river_half_width(x, gen)
		var tang := Vector3(1, 0, (river_center(x + 10.0, gen) - z) / 10.0).normalized()
		var perp := Vector3(-tang.z, 0, tang.x)
		var c := Vector3(x, 0.12, z)
		var l := c - perp * hw
		var r := c + perp * hw
		if not first:
			wb.quad_o(prev_l, prev_r, r, l, Vector3.UP, PackedVector2Array([
				Vector2(x - 10.0, -1) * 0.02, Vector2(x - 10.0, 1) * 0.02,
				Vector2(x, 1) * 0.02, Vector2(x, -1) * 0.02]))
			# quay walls + promenade within mid radius
			if absf(x) < gen.R_MID + 400.0:
				_quay_segment(gen, qb, prev_l, l, 0.0, 0.7, -1.0)
				_quay_segment(gen, qb, prev_r, r, 0.0, 0.7, 1.0)
		prev_l = l
		prev_r = r
		first = false
		x += 25.0
	_flush(gen, wb, "water")
	_flush(gen, qb, "sidewalk")
	_bridges(gen)
	_harbor(gen)

func _quay_segment(gen: CityGen, b: MeshBuf, a: Vector3, bq: Vector3,
		y0: float, y1: float, side: float) -> void:
	var dir := bq - a
	var ln := dir.length()
	dir = dir.normalized()
	var nrm := Vector3(dir.z, 0, -dir.x) * side
	# vertical wall
	b.quad_o(a + Vector3.UP * y0, bq + Vector3.UP * y0, bq + Vector3.UP * y1, a + Vector3.UP * y1,
		-nrm, PackedVector2Array([Vector2(0, 0), Vector2(ln, 0), Vector2(ln, y1 - y0), Vector2(0, y1 - y0)]))
	# promenade strip
	var inn := nrm * 7.0
	b.quad_o(a + Vector3.UP * y1 + inn, bq + Vector3.UP * y1 + inn,
		bq + Vector3.UP * y1, a + Vector3.UP * y1, Vector3.UP,
			PackedVector2Array([Vector2(0, 0), Vector2(ln * 0.2, 0), Vector2(ln * 0.2, 1.4), Vector2(0, 1.4)]))

func _bridges(gen: CityGen) -> void:
	# find road segments crossing the river
	for rs in gen.road_samples:
		var pts: PackedVector3Array = rs.pts
		for k in range(0, pts.size() - 1):
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[k + 1]
			var d0 := p0.z - river_center(p0.x, gen)
			var d1 := p1.z - river_center(p1.x, gen)
			if d0 * d1 > 0.0:
				continue
			var t := d0 / maxf(d0 - d1, 0.001)
			var cross := p0.lerp(p1, t)
			if rs.cls == CityGen.RC_ARTERIAL:
				_cable_bridge(gen, cross, (p1 - p0).normalized())
			else:
				_girder_bridge(gen, cross, (p1 - p0).normalized())

func _beam(b: MeshBuf, p0: Vector3, p1: Vector3, w: float, h: float,
		col := Color(0.3, 0.31, 0.34, 0.0)) -> void:
	var d := p1 - p0
	var ln := d.length()
	var c := (p0 + p1) * 0.5
	var xf := Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), c)
	b.box(Vector3.ZERO, Vector3(ln, h, w), Vector2.ZERO, col, 0.3, xf)

func _cable_bridge(gen: CityGen, at: Vector3, dirv: Vector3) -> void:
	var mb := gen.buf(gen.chunk_of(at), "mech")
	var tb := gen.buf(gen.chunk_of(at), "trim")
	var rb := gen.buf(gen.chunk_of(at), "road")
	var perp := Vector3(-dirv.z, 0, dirv.x)
	var deck_y := 9.0
	var span := 150.0
	# deck
	for s in 8:
		var t0 := -span + float(s) * span * 0.25
		var t1 := t0 + span * 0.25
		var a := at + dirv * t0
		var bq := at + dirv * t1
		rb.quad_o(a - perp * 10.0 + Vector3(0, deck_y, 0), bq - perp * 10.0 + Vector3(0, deck_y, 0),
			bq + perp * 10.0 + Vector3(0, deck_y, 0), a + perp * 10.0 + Vector3(0, deck_y, 0),
			Vector3.UP, PackedVector2Array([Vector2(t0, -1), Vector2(t1, -1), Vector2(t1, 1), Vector2(t0, 1)]))
		mb.box((a + bq) * 0.5 + Vector3(0, deck_y - 1.2, 0), Vector3(span * 0.25, 2.0, 20.0),
			Vector2.ZERO, Color(0.22, 0.23, 0.26, 0.0), 0.25,
			Transform3D(Basis(Vector3.UP, atan2(-dirv.z, dirv.x)), (a + bq) * 0.5 + Vector3(0, deck_y - 1.2, 0)))
	# deck lamps
	var lb := gen.buf(gen.chunk_of(at), "trim")
	for kk in 10:
		var tt2 := -span + float(kk) * span * 0.22
		for sgn2 in [-1.0, 1.0]:
			lb.box(at + dirv * tt2 + perp * sgn2 * 9.5 + Vector3(0, deck_y + 1.6, 0),
				Vector3(0.15, 1.2, 0.15), Vector2.ZERO, Color(0.5, 0.5, 0.45, 0.0), 1.0)
			lb.box(at + dirv * tt2 + perp * sgn2 * 9.5 + Vector3(0, deck_y + 2.3, 0),
				Vector3(0.3, 0.25, 0.3), Vector2.ZERO, Color(1.0, 0.85, 0.6, 1.0), 1.0)
	# pylons (H shape) + cables
	for sgn in [-1.0, 1.0]:
		var sgn_f := float(sgn)
		var base := at + perp * sgn_f * 12.0
		var top := base + Vector3(0, 52.0, 0)
		mb.box(base + Vector3(0, 26.0, 0), Vector3(3.0, 52.0, 4.0), Vector2.ZERO, Color(0.5, 0.5, 0.52, 0.0), 0.3)
		for c in 6:
			var tt := (float(c) + 1.0) * 22.0
			for ds in [-1.0, 1.0]:
				var ds_f := float(ds)
				var anchor := at + dirv * (tt * ds_f) + perp * sgn_f * 9.0 + Vector3(0, deck_y + 0.5, 0)
				_beam(mb, top + Vector3(0, -2.0, 0), anchor, 0.35, 0.35, Color(0.6, 0.6, 0.62, 0.0))
		tb.box(top + Vector3(0, 1.0, 0), Vector3(1.0, 1.0, 1.0), Vector2.ZERO, Color(1.0, 0.2, 0.15, 1.0), 1.0)
	# crossbeam
	_beam(mb, at + perp * -12.0 + Vector3(0, 40.0, 0), at + perp * 12.0 + Vector3(0, 40.0, 0), 3.0, 3.0)
	# railings + edge light strips
	var tb2 := gen.buf(gen.chunk_of(at), "trim")
	for sgn in [-1.0, 1.0]:
		_beam(mb, at - dirv * span + perp * sgn * 10.0 + Vector3(0, deck_y + 0.6, 0),
			at + dirv * span + perp * sgn * 10.0 + Vector3(0, deck_y + 0.6, 0), 0.25, 1.2)
		_beam(tb2, at - dirv * span + perp * sgn * 10.0 + Vector3(0, deck_y + 1.25, 0),
			at + dirv * span + perp * sgn * 10.0 + Vector3(0, deck_y + 1.25, 0), 0.12, 0.12,
			Color(0.4, 0.85, 1.0, 1.0))

func _girder_bridge(gen: CityGen, at: Vector3, dirv: Vector3) -> void:
	var mb := gen.buf(gen.chunk_of(at), "mech")
	var rb := gen.buf(gen.chunk_of(at), "road")
	var perp := Vector3(-dirv.z, 0, dirv.x)
	var deck_y := 6.5
	var span := 90.0
	for s in 6:
		var t0 := -span + float(s) * span / 3.0
		var t1 := t0 + span / 3.0
		var a := at + dirv * t0
		var bq := at + dirv * t1
		rb.quad_o(a - perp * 7.0 + Vector3(0, deck_y, 0), bq - perp * 7.0 + Vector3(0, deck_y, 0),
			bq + perp * 7.0 + Vector3(0, deck_y, 0), a + perp * 7.0 + Vector3(0, deck_y, 0),
			Vector3.UP, PackedVector2Array([Vector2(t0, -1), Vector2(t1, -1), Vector2(t1, 1), Vector2(t0, 1)]))
		_beam(mb, (a + bq) * 0.5 + Vector3(0, deck_y - 1.0, 0), (a + bq) * 0.5 + Vector3(0, deck_y - 1.0, 0.001), 0.1, 0.1)
		mb.box((a + bq) * 0.5 + Vector3(0, deck_y - 1.0, 0), Vector3(span / 3.0, 1.8, 14.0),
			Vector2.ZERO, Color(0.2, 0.21, 0.24, 0.0), 0.25,
			Transform3D(Basis(Vector3.UP, atan2(-dirv.z, dirv.x)), (a + bq) * 0.5 + Vector3(0, deck_y - 1.0, 0)))
	var tb3 := gen.buf(gen.chunk_of(at), "trim")
	for sgn in [-1.0, 1.0]:
		_beam(mb, at - dirv * span + perp * sgn * 7.0 + Vector3(0, deck_y + 0.6, 0),
			at + dirv * span + perp * sgn * 7.0 + Vector3(0, deck_y + 0.6, 0), 0.2, 1.1)
		_beam(tb3, at - dirv * span + perp * sgn * 7.0 + Vector3(0, deck_y + 1.2, 0),
			at + dirv * span + perp * sgn * 7.0 + Vector3(0, deck_y + 1.2, 0), 0.1, 0.1,
			Color(1.0, 0.6, 0.2, 1.0))

func _harbor(gen: CityGen) -> void:
	# gantry cranes + container stacks near the industrial river bank
	var rng := gen.rng
	var mb := gen.buf(Vector2i(3, 3), "mech")
	var cb := gen.buf(Vector2i(3, 3), "trim")
	for k in 3:
		var x := 1250.0 + float(k) * 160.0
		var z := river_center(x, gen) - river_half_width(x, gen) - 45.0
		var base := Vector3(x, 0, z)
		var hgt := 38.0
		for lx in [-8.0, 8.0]:
			for lz in [-6.0, 6.0]:
				mb.box(base + Vector3(lx, hgt * 0.5, lz), Vector3(1.4, hgt, 1.4), Vector2.ZERO, Color(0.55, 0.2, 0.1, 0.0), 0.3)
		mb.box(base + Vector3(0, hgt, 0), Vector3(20.0, 2.0, 16.0), Vector2.ZERO, Color(0.55, 0.2, 0.1, 0.0), 0.3)
		_beam(mb, base + Vector3(0, hgt + 1.0, 0), base + Vector3(-55.0, hgt - 6.0, 0), 1.6, 1.6, Color(0.55, 0.2, 0.1, 0.0))
		cb.box(base + Vector3(0, hgt + 2.5, 0), Vector3(1.0, 1.0, 1.0), Vector2.ZERO, Color(1.0, 0.3, 0.1, 1.0), 1.0)
	# containers
	for k in 40:
		var x := 1150.0 + rng.randf() * 500.0
		var z := river_center(x, gen) - river_half_width(x, gen) - 30.0 - rng.randf() * 90.0
		var col := Color.from_hsv(rng.randf(), 0.7, 0.45)
		mb.box(Vector3(x, 1.3 + floorf(rng.randf() * 3.0) * 2.6, z),
			Vector3(6.0, 2.6, 2.4), Vector2.ZERO, Color(col.r, col.g, col.b, 0.0), 0.3,
			Transform3D(Basis(Vector3.UP, 0.0 if rng.randf() < 0.5 else PI * 0.5), Vector3(x, 1.3 + floorf(rng.randf() * 3.0) * 2.6, z)))

# ---------------------------------------------------------------- elevated highway

func build_elevated(gen: CityGen) -> void:
	var j_h := 12
	var i_v := 16
	_corridor(gen, j_h, 0, 12.0)
	_corridor(gen, i_v, 1, 19.0)
	_interchange(gen, gen.node(i_v, j_h))
	# ramps
	_ramp(gen, gen.node(4, j_h), 0, 12.0, -1)
	_ramp(gen, gen.node(24, j_h), 0, 12.0, 1)
	_ramp(gen, gen.node(i_v, 4), 1, 19.0, -1)
	_ramp(gen, gen.node(i_v, 20), 1, 19.0, 1)

func _corridor(gen: CityGen, idx: int, axis: int, y: float) -> void:
	var mb := gen.buf(Vector2i(axis * 7 - 5, 5 - axis * 3), "mech")
	var rb := gen.buf(Vector2i(axis * 7 - 5, 6 - axis * 3), "road")
	var tb := gen.buf(Vector2i(axis * 7 - 5, 7 - axis * 3), "trim")
	var n := gen.nx if axis == 0 else gen.nz
	var prev: Vector3 = Vector3.ZERO
	for k in n + 1:
		var p: Vector3 = gen.node(k, idx) if axis == 0 else gen.node(idx, k)
		if k > 0:
			var d := p - prev
			var ln := d.length()
			var c := (p + prev) * 0.5
			var xf := Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), c + Vector3(0, y - 1.4, 0))
			mb.box(Vector3.ZERO, Vector3(ln + 2.0, 2.2, 24.0), Vector2.ZERO, Color(0.16, 0.16, 0.19, 0.0), 0.2, xf)
			rb.quad_o(prev - Vector3(12, -y, 0) * 0 - _perp(d) * 11.0 + Vector3(0, y + 0.05, 0),
				p - _perp(d) * 11.0 + Vector3(0, y + 0.05, 0),
				p + _perp(d) * 11.0 + Vector3(0, y + 0.05, 0),
				prev + _perp(d) * 11.0 + Vector3(0, y + 0.05, 0),
				Vector3.UP, PackedVector2Array([Vector2(0, -1), Vector2(ln, -1), Vector2(ln, 1), Vector2(0, 1)]))
			for sgn in [-1.0, 1.0]:
				_beam(mb, prev + _perp(d) * sgn * 12.0 + Vector3(0, y + 0.7, 0),
					p + _perp(d) * sgn * 12.0 + Vector3(0, y + 0.7, 0), 0.4, 1.4, Color(0.2, 0.2, 0.23, 0.0))
				# under-deck neon
				tb.quad_o(prev + _perp(d) * sgn * 11.5 + Vector3(0, y - 2.4, 0),
					p + _perp(d) * sgn * 11.5 + Vector3(0, y - 2.4, 0),
					p + _perp(d) * sgn * 10.5 + Vector3(0, y - 2.4, 0),
					prev + _perp(d) * sgn * 10.5 + Vector3(0, y - 2.4, 0),
					Vector3.DOWN, PackedVector2Array([Vector2(0, 0), Vector2(ln, 0), Vector2(ln, 1), Vector2(0, 1)]),
					Vector2.ZERO, Color(0.3, 0.7, 1.0, 1.0))
			# pillars
			var steps := int(ln / 30.0)
			for s in steps + 1:
				var pp := prev.lerp(p, float(s) / float(maxi(steps, 1)))
				mb.box(pp + Vector3(0, (y - 2.5) * 0.5, 0), Vector3(3.0, y - 2.5, 5.0),
					Vector2.ZERO, Color(0.18, 0.18, 0.2, 0.0), 0.25)
				mb.box(pp + Vector3(0, y - 2.8, 0), Vector3(4.0, 1.2, 22.0),
					Vector2.ZERO, Color(0.18, 0.18, 0.2, 0.0), 0.25,
					Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), pp + Vector3(0, y - 2.8, 0)))
		prev = p

func _perp(d: Vector3) -> Vector3:
	return Vector3(-d.z, 0, d.x).normalized()

func _ramp(gen: CityGen, at: Vector3, axis: int, y: float, sgn: int) -> void:
	var mb := gen.buf(gen.chunk_of(at), "mech")
	var rb := gen.buf(gen.chunk_of(at), "road")
	var pts := PackedVector3Array()
	var steps := 14
	for s in steps + 1:
		var t := float(s) / float(steps)
		var along := (float(sgn) if axis == 0 else 0.0)
		var px := at.x + (t * 130.0 * float(sgn) if axis == 0 else 0.0) + (0.0 if axis == 0 else 0.0)
		var pz := at.z + (0.0 if axis == 0 else t * 130.0 * float(sgn))
		var side := sin(t * PI * 0.5) * 46.0
		if axis == 0:
			pz += side
		else:
			px += side
		pts.append(Vector3(px, y * (1.0 - t * t), pz))
	for k in range(0, steps):
		var a := pts[k]
		var bq := pts[k + 1]
		var d := bq - a
		var ln := d.length()
		var pp := _perp(d)
		rb.quad_o(a - pp * 4.5, bq - pp * 4.5, bq + pp * 4.5, a + pp * 4.5, Vector3.UP,
			PackedVector2Array([Vector2(0, -1), Vector2(ln, -1), Vector2(ln, 1), Vector2(0, 1)]))
		mb.box((a + bq) * 0.5 + Vector3(0, -1.0, 0), Vector3(ln + 1.0, 1.6, 10.0), Vector2.ZERO,
			Color(0.16, 0.16, 0.19, 0.0), 0.2,
			Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), (a + bq) * 0.5 + Vector3(0, -1.0, 0)))
		if k % 3 == 0:
			mb.box((a + bq) * 0.5 + Vector3(0, a.y * 0.5 - 1.5, 0), Vector3(2.2, a.y - 1.0, 3.0),
				Vector2.ZERO, Color(0.18, 0.18, 0.2, 0.0), 0.25)

func _interchange(gen: CityGen, at: Vector3) -> void:
	# connector loops between the two decks
	var mb := gen.buf(gen.chunk_of(at), "mech")
	var rb := gen.buf(gen.chunk_of(at), "road")
	for q in 4:
		var ang0 := float(q) * PI * 0.5 + 0.3
		var pts := PackedVector3Array()
		var steps := 12
		for s in steps + 1:
			var t := float(s) / float(steps)
			var ang := ang0 + t * PI * 0.55
			var r := 70.0 + t * 30.0
			var y := lerpf(12.5, 18.5, t) if q % 2 == 0 else lerpf(18.5, 12.5, t)
			pts.append(at + Vector3(cos(ang) * r, y, sin(ang) * r))
		for k in range(0, steps):
			var a := pts[k]
			var bq := pts[k + 1]
			var d := bq - a
			var ln := d.length()
			var pp := _perp(d)
			rb.quad_o(a - pp * 4.0, bq - pp * 4.0, bq + pp * 4.0, a + pp * 4.0, Vector3.UP,
				PackedVector2Array([Vector2(0, -1), Vector2(ln, -1), Vector2(ln, 1), Vector2(0, 1)]))
			if k % 4 == 0:
				mb.box((a + bq) * 0.5 + Vector3(0, a.y * 0.5 - 1.2, 0), Vector3(2.0, a.y - 1.0, 2.6),
					Vector2.ZERO, Color(0.18, 0.18, 0.2, 0.0), 0.25)

# ---------------------------------------------------------------- skytrain

func build_skytrain(gen: CityGen) -> void:
	var j_s := 20
	var y := 9.0
	var mb := gen.buf(Vector2i(-3, 9), "mech")
	var tb := gen.buf(Vector2i(-3, 8), "trim")
	var prev: Vector3 = Vector3.ZERO
	var station_at := [8, 20]
	for k in gen.nx + 1:
		var p: Vector3 = gen.node(k, j_s)
		if k > 0:
			var d := p - prev
			var ln := d.length()
			var c := (p + prev) * 0.5
			var xf := Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), c + Vector3(0, y - 0.8, 0))
			mb.box(Vector3.ZERO, Vector3(ln + 1.0, 1.4, 6.0), Vector2.ZERO, Color(0.3, 0.31, 0.35, 0.0), 0.25, xf)
			var steps := int(ln / 24.0)
			for s in steps + 1:
				var pp := prev.lerp(p, float(s) / float(maxi(steps, 1)))
				mb.cylinder(pp + Vector3(0, 0.2, 0), 0.9, 0.7, y - 1.2, 6, Transform3D.IDENTITY, Vector2.ZERO, Color(0.25, 0.26, 0.3, 0.0))
			tb.quad_o(prev + Vector3(0, y + 0.15, 0) - _perp(d) * 3.0, p + Vector3(0, y + 0.15, 0) - _perp(d) * 3.0,
				p + Vector3(0, y + 0.15, 0) + _perp(d) * 3.0, prev + Vector3(0, y + 0.15, 0) + _perp(d) * 3.0,
				Vector3.UP, PackedVector2Array([Vector2(0, 0), Vector2(ln, 0), Vector2(ln, 1), Vector2(0, 1)]),
				Vector2.ZERO, Color(0.4, 0.9, 1.0, 0.6))
		if k in station_at:
			_station(gen, p, y)
		prev = p
	_train(gen, gen.node(14, j_s), y)

func _station(gen: CityGen, at: Vector3, y: float) -> void:
	var mb := gen.buf(gen.chunk_of(at), "mech")
	var tb := gen.buf(gen.chunk_of(at), "trim")
	mb.box(at + Vector3(0, y + 0.6, 10.0), Vector3(56.0, 0.8, 7.0), Vector2.ZERO, Color(0.35, 0.36, 0.4, 0.0), 0.3)
	mb.box(at + Vector3(0, y + 0.6, -10.0), Vector3(56.0, 0.8, 7.0), Vector2.ZERO, Color(0.35, 0.36, 0.4, 0.0), 0.3)
	# arched canopy: parametric half-cylinder
	var bb := MeshBuf.new()
	var seg := 10
	var rings := 8
	for s in seg:
		var a0 := PI * float(s) / float(seg)
		var a1 := PI * float(s + 1) / float(seg)
		for r in rings:
			var x0 := -28.0 + 56.0 * float(r) / float(rings)
			var x1 := -28.0 + 56.0 * float(r + 1) / float(rings)
			var p00 := Vector3(x0, y + 4.0 + cos(a0) * 0.0 + sin(a0) * 5.0, 14.0 * -cos(a0))
			var p01 := Vector3(x0, y + 4.0 + sin(a1) * 5.0, 14.0 * -cos(a1))
			var p11 := Vector3(x1, y + 4.0 + sin(a1) * 5.0, 14.0 * -cos(a1))
			var p10 := Vector3(x1, y + 4.0 + sin(a0) * 5.0, 14.0 * -cos(a0))
			bb.quad_o(at + p00, at + p01, at + p11, at + p10, Vector3.UP,
				PackedVector2Array([Vector2(x0, a0) * 0.1, Vector2(x0, a1) * 0.1,
					Vector2(x1, a1) * 0.1, Vector2(x1, a0) * 0.1]))
	var m := ArrayMesh.new()
	bb.make_surface(m, gen.mats["mech"])
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = "station_canopy"
	gen._root.add_child(mi)
	tb.box(at + Vector3(0, y + 3.4, 13.5), Vector3(56.0, 0.25, 0.25), Vector2.ZERO, Color(0.3, 0.9, 1.0, 1.0), 1.0)
	tb.box(at + Vector3(0, y + 3.4, -13.5), Vector3(56.0, 0.25, 0.25), Vector2.ZERO, Color(0.3, 0.9, 1.0, 1.0), 1.0)

func _train(gen: CityGen, at: Vector3, y: float) -> void:
	var b := MeshBuf.new()
	for c in 4:
		var x := float(c) * 19.0 - 28.0
		b.box(Vector3(x, y + 2.2, 0), Vector3(17.0, 3.2, 3.0), Vector2.ZERO, Color(0.7, 0.72, 0.75, 0.0), 0.3)
		b.box(Vector3(x, y + 2.6, 1.52), Vector3(14.0, 1.1, 0.06), Vector2.ZERO, Color(0.8, 0.95, 1.0, 1.0), 1.0)
		b.box(Vector3(x, y + 2.6, -1.52), Vector3(14.0, 1.1, 0.06), Vector2.ZERO, Color(0.8, 0.95, 1.0, 1.0), 1.0)
		b.box(Vector3(x + 8.6, y + 1.6, 0), Vector3(0.1, 0.5, 2.6), Vector2.ZERO, Color(1.0, 1.0, 0.9, 1.0), 1.0)
	var m := ArrayMesh.new()
	b.make_surface(m, gen.mats["prop_vc"])
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = "skytrain"
	gen._root.add_child(mi)

func _flush(gen: CityGen, b: MeshBuf, mat: String) -> void:
	if b.is_empty():
		return
	var mesh := ArrayMesh.new()
	b.make_surface(mesh, gen.mats[mat])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "infra_" + mat
	gen._root.add_child(mi)
