class_name LandmarksGen
extends RefCounted
## Parametric landmark structures: twisted tower, spire, dome arena,
## hyperboloid cooling towers, ferris wheel, arcology megastructure.

func generate(gen: CityGen) -> void:
	_twist_tower(gen, Vector3(60, 0, -140))
	_spire(gen, Vector3(240, 0, 120))
	_dome(gen, Vector3(470, 0, 630))
	_hyperboloids(gen, Vector3(1450, 0, 1090))
	_ferris(gen, Vector3(1180, 0, infra_river_z(gen, 1180) - 160.0))
	_arcology(gen, Vector3(-260, 0, -380))

func infra_river_z(gen: CityGen, x: float) -> float:
	return gen.infra.river_center(x, gen)

func _meta(seedf: float, fh: float, style: float, gh: float) -> Vector2:
	return Vector2(seedf, fh)

func _col(style: int, gh: float) -> Color:
	return Color(0.3, 0.34, 0.42, (float(style) * 16.0 + gh) / 255.0)

# ---- twisted tower: rotating square prism stack (parametric)
func _twist_tower(gen: CityGen, at: Vector3) -> void:
	var fb := gen.buf(gen.chunk_of(at), "glass")
	var rb := gen.buf(gen.chunk_of(at), "roof")
	var mb := gen.buf(gen.chunk_of(at), "mech")
	var tiers := 46
	var th := 4.0
	var sd := 431.5
	for i in tiers:
		var t := float(i) / float(tiers)
		var ang := t * 1.05  # ~60 deg total twist
		var sz := lerpf(30.0, 21.0, t)
		var y0 := float(i) * th
		var pts := PackedVector2Array()
		for k in 4:
			var a := ang + float(k) * PI * 0.5 + PI * 0.25
			pts.append(Vector2(at.x + cos(a) * sz, at.z + sin(a) * sz))
		fb.prism(pts, y0, y0 + th, Vector2(sd, th), _col(0, 4.2), rb, 0.25, 1.0)
	var top := float(tiers) * th
	mb.cylinder(at + Vector3(0, top, 0), 0.5, 0.2, 30.0, 8)
	var bb := gen.buf(gen.chunk_of(at), "beacon")
	bb.box(at + Vector3(0, top + 30.5, 0), Vector3(1.0, 1.0, 1.0), Vector2.ZERO, Color(1, 0.15, 0.1, 1), 1.0)
	# crown ring
	var tb := gen.buf(gen.chunk_of(at), "trim")
	for k in 12:
		var a := float(k) / 12.0 * TAU
		tb.box(at + Vector3(cos(a) * 20.0, top - 1.0, sin(a) * 20.0),
			Vector3(1.0, 1.0, 1.0), Vector2.ZERO, Color(0.3, 0.9, 1.0, 1.0), 1.0)

# ---- spire: tapered octagon + mast
func _spire(gen: CityGen, at: Vector3) -> void:
	var fb := gen.buf(gen.chunk_of(at), "glass")
	var rb := gen.buf(gen.chunk_of(at), "roof")
	var mb := gen.buf(gen.chunk_of(at), "mech")
	var tiers := 40
	var th := 7.5
	var sd := 777.2
	for i in tiers:
		var t := float(i) / float(tiers)
		var r := lerpf(24.0, 7.0, pow(t, 0.8))
		var y0 := float(i) * th
		var pts := PackedVector2Array()
		for k in 8:
			var a := float(k) / 8.0 * TAU + t * 0.2
			pts.append(Vector2(at.x + cos(a) * r, at.z + sin(a) * r))
		fb.prism(pts, y0, y0 + th, Vector2(sd, th), _col(7, 4.0), rb, 0.25, 1.0)
	var top := float(tiers) * th
	mb.cylinder(at + Vector3(0, top, 0), 0.7, 0.15, 70.0, 8)
	var bb := gen.buf(gen.chunk_of(at), "beacon")
	bb.box(at + Vector3(0, top + 70.5, 0), Vector3(1.2, 1.2, 1.2), Vector2.ZERO, Color(1, 0.15, 0.1, 1), 1.0)
	var tb := gen.buf(gen.chunk_of(at), "trim")
	for i in 6:
		var y := 40.0 + float(i) * 45.0
		var r := lerpf(24.0, 7.0, pow(y / top, 0.8)) + 0.3
		for k in 8:
			var a := float(k) / 8.0 * TAU
			tb.box(at + Vector3(cos(a) * r, y, sin(a) * r), Vector3(0.5, 0.5, 0.5),
				Vector2.ZERO, Color(0.9, 0.3, 1.0, 1.0), 1.0)

# ---- dome arena: spherical cap shell
func _dome(gen: CityGen, at: Vector3) -> void:
	var b := MeshBuf.new()
	var seg := 24
	var rings := 10
	var R := 48.0
	var H := 30.0
	for s in seg:
		var a0 := TAU * float(s) / float(seg)
		var a1 := TAU * float(s + 1) / float(seg)
		for r in rings:
			var t0 := float(r) / float(rings)
			var t1 := float(r + 1) / float(rings)
			var y0 := sin(t0 * PI * 0.5) * H
			var y1 := sin(t1 * PI * 0.5) * H
			var r0 := cos(t0 * PI * 0.5) * R
			var r1 := cos(t1 * PI * 0.5) * R
			var p00 := at + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := at + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := at + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var p10 := at + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var nn := (p00 - at).normalized()
			b.quad_o(p00, p01, p11, p10, nn, PackedVector2Array([
				Vector2(a0 * R, y0) * 0.1, Vector2(a0 * R, y1) * 0.1,
				Vector2(a1 * R, y1) * 0.1, Vector2(a1 * R, y0) * 0.1]))
	var m := ArrayMesh.new()
	b.make_surface(m, gen.mats["mech"])
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = "dome_arena"
	gen._root.add_child(mi)
	var tb := gen.buf(gen.chunk_of(at), "trim")
	for k in 28:
		var a := float(k) / 28.0 * TAU
		tb.box(at + Vector3(cos(a) * (R + 0.5), 1.5, sin(a) * (R + 0.5)),
			Vector3(0.4, 3.0, 0.4), Vector2.ZERO, Color(0.2, 0.9, 1.0, 1.0), 1.0)
	for k in 36:
		var a := float(k) / 36.0 * TAU
		var rr := cos(0.42 * PI * 0.5) * R
		var yy := sin(0.42 * PI * 0.5) * H
		tb.box(at + Vector3(cos(a) * (rr + 0.4), yy, sin(a) * (rr + 0.4)),
			Vector3(0.5, 0.5, 0.5), Vector2.ZERO, Color(1.0, 0.55, 0.2, 1.0), 1.0)
	var bb := gen.buf(gen.chunk_of(at), "beacon")
	bb.box(at + Vector3(0, H + 2.0, 0), Vector3(1.0, 1.0, 1.0), Vector2.ZERO, Color(0.3, 1.0, 0.4, 1.0), 1.0)

# ---- hyperboloid cooling towers: cosh profile revolution
func _hyperboloids(gen: CityGen, at: Vector3) -> void:
	for tower in 2:
		var off := Vector3(float(tower) * 90.0 - 45.0, 0, 20.0)
		var b := MeshBuf.new()
		var seg := 20
		var rings := 14
		var H := 75.0
		var rmin := 16.0
		var yc := H * 0.62
		var aa := 26.0
		for s in seg:
			var a0 := TAU * float(s) / float(seg)
			var a1 := TAU * float(s + 1) / float(seg)
			for r in rings:
				var y0 := H * float(r) / float(rings)
				var y1 := H * float(r + 1) / float(rings)
				var r0 := rmin * cosh((y0 - yc) / aa)
				var r1 := rmin * cosh((y1 - yc) / aa)
				var p00 := at + off + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
				var p01 := at + off + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
				var p11 := at + off + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
				var p10 := at + off + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
				var nn := (Vector3(cos(a0), 0.35, sin(a0))).normalized()
				b.quad_o(p00, p01, p11, p10, nn, PackedVector2Array([
					Vector2(a0 * rmin, y0) * 0.15, Vector2(a0 * rmin, y1) * 0.15,
					Vector2(a1 * rmin, y1) * 0.15, Vector2(a1 * rmin, y0) * 0.15]))
		var m := ArrayMesh.new()
		b.make_surface(m, gen.mats["plain_concrete"])
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.name = "cooling_tower_%d" % tower
		gen._root.add_child(mi)

# ---- ferris wheel
func _ferris(gen: CityGen, at: Vector3) -> void:
	var mb := gen.buf(gen.chunk_of(at), "mech")
	var tb := gen.buf(gen.chunk_of(at), "trim")
	var R := 42.0
	var cy := at + Vector3(0, R + 8.0, 0)
	var spokes := 18
	for k in spokes:
		var a := float(k) / float(spokes) * TAU
		var rim := cy + Vector3(cos(a) * R, sin(a) * R, 0)
		var a2 := float(k + 1) / float(spokes) * TAU
		var rim2 := cy + Vector3(cos(a2) * R, sin(a2) * R, 0)
		_beam(mb, rim, rim2, 0.5, 0.5)
		_beam(mb, cy, rim, 0.35, 0.35)
		mb.box(rim + Vector3(0, -1.5, 0), Vector3(2.4, 3.0, 2.4), Vector2.ZERO, Color(0.5, 0.2, 0.3, 0.0), 0.4)
		tb.box(rim, Vector3(0.6, 0.6, 0.6), Vector2.ZERO, Color.from_hsv(float(k) / float(spokes), 0.8, 1.0), 1.0)
	mb.cylinder(cy + Vector3(0, 0, -3.0), 1.2, 1.2, 6.0, 8, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), cy + Vector3(0, 0, -3.0)))
	for sgn in [-1.0, 1.0]:
		_beam(mb, at + Vector3(0, 0, sgn * 10.0), cy + Vector3(0, 0, sgn * 3.0), 1.0, 1.0)
		_beam(mb, at + Vector3(0, 0, sgn * 10.0), cy + Vector3(0, 0, -sgn * 3.0), 1.0, 1.0)

func _beam(b: MeshBuf, p0: Vector3, p1: Vector3, w: float, h: float) -> void:
	var d := p1 - p0
	var ln := d.length()
	var c := (p0 + p1) * 0.5
	var xf := Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), c)
	b.box(Vector3.ZERO, Vector3(ln, h, w), Vector2.ZERO, Color(0.35, 0.36, 0.4, 0.0), 0.3, xf)

# ---- arcology: podium + 3 towers + skybridges
func _arcology(gen: CityGen, at: Vector3) -> void:
	var fb := gen.buf(gen.chunk_of(at), "facade")
	var gb := gen.buf(gen.chunk_of(at), "glass")
	var rb := gen.buf(gen.chunk_of(at), "roof")
	var mb := gen.buf(gen.chunk_of(at), "mech")
	var tb := gen.buf(gen.chunk_of(at), "trim")
	var pod := PackedVector2Array([
		Vector2(at.x - 80, at.z - 55), Vector2(at.x + 80, at.z - 55),
		Vector2(at.x + 80, at.z + 55), Vector2(at.x - 80, at.z + 55)])
	fb.prism(pod, 0.0, 32.0, Vector2(91.0, 4.5), _col(6, 5.0), rb, 0.25, 1.0)
	var towers := [Vector3(-40, 0, -15), Vector3(10, 0, 10), Vector3(50, 0, -20)]
	var heights := [110.0, 150.0, 125.0]
	for i in 3:
		var tp: Vector3 = towers[i]
		var h: float = heights[i]
		var pts := PackedVector2Array([
			Vector2(at.x + tp.x - 18, at.z + tp.z - 14), Vector2(at.x + tp.x + 18, at.z + tp.z - 14),
			Vector2(at.x + tp.x + 18, at.z + tp.z + 14), Vector2(at.x + tp.x - 18, at.z + tp.z + 14)])
		gb.prism(pts, 32.0, 32.0 + h, Vector2(131.0 + float(i) * 7.0, 3.8), _col(0, 4.2), rb, 0.25, 1.0)
		tb.box(at + tp + Vector3(0, 32.0 + h + 0.5, 0), Vector3(36.0, 0.5, 0.5), Vector2.ZERO, Color(0.3, 0.9, 1.0, 1.0), 1.0)
	# skybridges
	for i in 2:
		var p0: Vector3 = at + towers[i] + Vector3(0, 70.0 + float(i) * 18.0, 0)
		var p1: Vector3 = at + towers[i + 1] + Vector3(0, 70.0 + float(i) * 18.0, 0)
		mb.cylinder(p0, 3.0, 3.0, (p1 - p0).length(), 10,
			Transform3D(Basis(Vector3.UP, atan2(-(p1 - p0).z, (p1 - p0).x)) * Basis(Vector3.RIGHT, -PI * 0.5), p0))
		tb.box((p0 + p1) * 0.5, Vector3((p1 - p0).length(), 0.4, 0.4), Vector2.ZERO, Color(1.0, 0.5, 0.2, 1.0), 1.0,
			Transform3D(Basis(Vector3.UP, atan2(-(p1 - p0).z, (p1 - p0).x)), (p0 + p1) * 0.5))
