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
	build_nodes(gen)

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
	for side in [-2.6, 2.6]:
		for k in 48:
			var a := float(k) / 48.0 * TAU
			tb.box(cy + Vector3(cos(a) * R, sin(a) * R, side), Vector3(0.7, 0.7, 0.7),
				Vector2.ZERO, Color(1.0, 0.75, 0.3, 1.0), 1.0)
	tb.box(cy, Vector3(1.6, 1.6, 7.0), Vector2.ZERO, Color(0.4, 0.9, 1.0, 1.0), 1.0)
	mb.cylinder(cy + Vector3(0, 0, -3.0), 1.2, 1.2, 6.0, 8, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), cy + Vector3(0, 0, -3.0)))
	for sgn in [-1.0, 1.0]:
		_beam(mb, at + Vector3(0, 0, sgn * 10.0), cy + Vector3(0, 0, sgn * 3.0), 1.0, 1.0)
		_beam(mb, at + Vector3(0, 0, sgn * 10.0), cy + Vector3(0, 0, -sgn * 3.0), 1.0, 1.0)

func _beam(b: MeshBuf, p0: Vector3, p1: Vector3, w: float, h: float, col: Color = Color(0.35, 0.36, 0.4, 0.0)) -> void:
	var d := p1 - p0
	var ln := d.length()
	var c := (p0 + p1) * 0.5
	var xf := Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), c)
	b.box(Vector3.ZERO, Vector3(ln, h, w), Vector2.ZERO, col, 0.3, xf)

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

# ================================================================ urban nodes
## Reserve cells around landmarks so they sit in plazas / yards / boardwalks
## instead of empty lots. Called BEFORE cell subdivision.
func plan(gen: CityGen) -> void:
	_zone(gen, Vector3(60, 0, -140), 115.0, "plaza")          # twist tower plaza
	_zone(gen, Vector3(1450, 0, 1090), 185.0, "yard")        # cooling-tower yard
	var fz := infra_river_z(gen, 1180) - 150.0
	_zone(gen, Vector3(1180, 0, fz), 140.0, "plaza")         # ferris boardwalk
	for i in [8, 20]:                                        # skytrain forecourts
		var p: Vector3 = gen.node(i, 20)
		_zone(gen, p + Vector3(0, 0, 26), 62.0, "plaza")

func _zone(gen: CityGen, c: Vector3, r: float, type: String) -> void:
	for i in gen.nx:
		for j in gen.nz:
			var center: Vector3 = (gen.node(i, j) + gen.node(i + 1, j + 1)) * 0.5
			if (center - c).length() < r:
				gen.cell_override[Vector2i(i, j)] = type

## Street furniture, connections and context that turn landmarks into nodes.
func build_nodes(gen: CityGen) -> void:
	_twist_plaza(gen, Vector3(60, 0, -140))
	_cooling_yard(gen, Vector3(1450, 0, 1090))
	var fz := infra_river_z(gen, 1180) - 150.0
	_ferris_boardwalk(gen, Vector3(1180, 0, fz))
	for i in [8, 20]:
		_station_plaza(gen, gen.node(i, 20))
	_bridgeheads(gen)

func _twist_plaza(gen: CityGen, at: Vector3) -> void:
	var pb := gen.buf(gen.chunk_of(at), "prop_vc")
	var tb := gen.buf(gen.chunk_of(at), "trim")
	var sb := gen.buf(gen.chunk_of(at), "sidewalk")
	# radial paths to the four road sides
	for k in 4:
		var a := float(k) * PI * 0.5
		var dirv := Vector3(cos(a), 0, sin(a))
		var p0 := at + dirv * 30.0
		var p1 := at + dirv * 105.0
		var perp := Vector3(-dirv.z, 0, dirv.x)
		sb.quad_o(p0 - perp * 3.0, p1 - perp * 3.0, p1 + perp * 3.0, p0 + perp * 3.0,
			Vector3.UP, PackedVector2Array([Vector2(0, 0), Vector2(22.5, 0), Vector2(22.5, 1.8), Vector2(0, 1.8)]),
			Vector2(6.0, 0.0))
	# tree ring + benches + bollards
	for k in 14:
		var a := float(k) / 14.0 * TAU
		var tp := at + Vector3(cos(a), 0, sin(a)) * 42.0
		pb.cylinder(tp, 0.16, 0.12, 3.0, 5, Transform3D.IDENTITY, Vector2.ZERO, Color(0.12, 0.08, 0.05, 0.0))
		pb.cylinder(tp + Vector3(0, 2.8, 0), 2.0, 0.8, 3.0, 6, Transform3D.IDENTITY, Vector2.ZERO, Color(0.06, 0.14, 0.05, 0.0))
		var bp := at + Vector3(cos(a + 0.22), 0, sin(a + 0.22)) * 34.0
		pb.box(bp, Vector3(1.8, 0.45, 0.6), Vector2.ZERO, Color(0.3, 0.22, 0.15, 0.0), 0.5,
			Transform3D(Basis(Vector3.UP, a), bp))
	for k in 24:
		var a := float(k) / 24.0 * TAU
		var bp := at + Vector3(cos(a), 0, sin(a)) * 26.0
		pb.cylinder(bp, 0.09, 0.09, 0.9, 5, Transform3D.IDENTITY, Vector2.ZERO, Color(0.1, 0.1, 0.12, 0.0))
		tb.box(bp + Vector3(0, 0.95, 0), Vector3(0.16, 0.16, 0.16), Vector2.ZERO, Color(1.0, 0.8, 0.5, 1.0), 1.0)
	# entrance canopy toward south road
	var cp := at + Vector3(0, 0, 34.0)
	var mb := gen.buf(gen.chunk_of(at), "mech")
	for k in 4:
		mb.cylinder(cp + Vector3((float(k % 2) - 0.5) * 16.0, 0, (float(k / 2) - 0.5) * 8.0), 0.3, 0.3, 5.0, 6)
	mb.box(cp + Vector3(0, 5.2, 0), Vector3(20.0, 0.4, 10.0), Vector2.ZERO, Color(0.2, 0.22, 0.26, 0.0), 0.3)
	tb.box(cp + Vector3(0, 5.0, 4.8), Vector3(20.0, 0.2, 0.2), Vector2.ZERO, Color(0.3, 0.9, 1.0, 1.0), 1.0)

func _cooling_yard(gen: CityGen, at: Vector3) -> void:
	var mb := gen.buf(gen.chunk_of(at), "mech")
	var tb := gen.buf(gen.chunk_of(at), "trim")
	# pipe racks toward the west halls
	for pipe in 3:
		var y := 2.2 + float(pipe) * 0.7
		for k in 12:
			var x0 := at.x - 60.0 - float(k) * 16.0
			_beam(mb, Vector3(x0, y, at.z - 8.0 + float(pipe) * 8.0), Vector3(x0 - 16.0, y, at.z - 8.0 + float(pipe) * 8.0), 0.5, 0.5, Color(0.5, 0.5, 0.52, 0.0))
		for k in 7:
			var x0 := at.x - 60.0 - float(k) * 32.0
			mb.box(Vector3(x0, 1.2, at.z), Vector3(1.0, 2.6, 20.0), Vector2.ZERO, Color(0.3, 0.3, 0.33, 0.0), 0.3)
	# perimeter fence
	for k in 28:
		var a := float(k) / 28.0 * TAU
		var p0 := at + Vector3(cos(a), 0, sin(a)) * 78.0
		var a2 := float(k + 1) / 28.0 * TAU
		var p1 := at + Vector3(cos(a2), 0, sin(a2)) * 78.0
		mb.box(p0 + Vector3(0, 1.1, 0), Vector3(0.12, 2.2, 0.12), Vector2.ZERO, Color(0.2, 0.2, 0.22, 0.0), 0.5)
		_beam(mb, p0 + Vector3(0, 2.0, 0), p1 + Vector3(0, 2.0, 0), 0.06, 0.06, Color(0.2, 0.2, 0.22, 0.0))
	# hazard beacons
	for k in 4:
		var a := float(k) * PI * 0.5 + 0.4
		tb.box(at + Vector3(cos(a) * 78.0, 2.4, sin(a) * 78.0), Vector3(0.25, 0.25, 0.25), Vector2.ZERO, Color(1.0, 0.6, 0.1, 1.0), 1.0)

func _ferris_boardwalk(gen: CityGen, at: Vector3) -> void:
	var pb := gen.buf(gen.chunk_of(at), "prop_vc")
	var tb := gen.buf(gen.chunk_of(at), "trim")
	var sb := gen.buf(gen.chunk_of(at), "plain_concrete")
	# boardwalk strip along the bank
	for k in 10:
		var x0 := at.x - 90.0 + float(k) * 18.0
		sb.box(Vector3(x0 + 9.0, 0.10, at.z + 55.0), Vector3(18.0, 0.16, 14.0), Vector2.ZERO, Color(0.24, 0.17, 0.10), 0.35)
	# stalls with awnings + warm fronts
	for k in 6:
		var sp := at + Vector3(-70.0 + float(k) * 28.0, 0, 48.0)
		pb.box(sp + Vector3(0, 1.2, 0), Vector3(3.4, 2.2, 2.6), Vector2.ZERO, Color(0.35, 0.2, 0.15, 0.0), 0.4)
		pb.box(sp + Vector3(0, 2.6, 0.6), Vector3(4.0, 0.15, 3.4), Vector2.ZERO, Color.from_hsv(float(k) / 6.0, 0.7, 0.5), 0.4)
		pb.box(sp + Vector3(0, 1.5, 1.35), Vector3(2.6, 1.0, 0.06), Vector2.ZERO, Color(1.0, 0.8, 0.5, 1.0), 1.0)
	# string lights: poles + catenary bulbs
	for k in 8:
		var a := float(k) / 8.0 * TAU
		var p0 := at + Vector3(cos(a), 0, sin(a)) * 46.0
		pb.cylinder(p0, 0.08, 0.08, 4.2, 5, Transform3D.IDENTITY, Vector2.ZERO, Color(0.1, 0.1, 0.1, 0.0))
		var a2 := float(k + 1) / 8.0 * TAU
		var p1 := at + Vector3(cos(a2), 0, sin(a2)) * 46.0
		for sgm in 7:
			var t := (float(sgm) + 0.5) / 7.0
			var pp := p0.lerp(p1, t)
			var sag := sin(t * PI) * 1.1
			tb.box(pp + Vector3(0, 4.2 - sag, 0), Vector3(0.14, 0.14, 0.14), Vector2.ZERO, Color(1.0, 0.75, 0.4, 1.0), 1.0)

func _station_plaza(gen: CityGen, p: Vector3) -> void:
	var pb := gen.buf(gen.chunk_of(p), "prop_vc")
	var tb := gen.buf(gen.chunk_of(p), "trim")
	var pt := gen.buf(gen.chunk_of(p), "paint")
	var mb := gen.buf(gen.chunk_of(p), "mech")
	# crosswalk stripes across the arterial in front
	for k in 8:
		var x0 := p.x - 7.0 + float(k) * 1.8
		pt.quad_o(Vector3(x0, 0.03, p.z - 12.0), Vector3(x0 + 0.9, 0.03, p.z - 12.0),
			Vector3(x0 + 0.9, 0.03, p.z - 5.0), Vector3(x0, 0.03, p.z - 5.0), Vector3.UP,
			PackedVector2Array([Vector2(0, 0), Vector2(0.45, 0), Vector2(0.45, 3.5), Vector2(0, 3.5)]),
			Vector2.ZERO, Color(0.8, 0.8, 0.8))
	# bus shelter
	var bs := p + Vector3(18.0, 0, -8.0)
	mb.box(bs + Vector3(0, 1.2, 0), Vector3(6.0, 0.2, 2.4), Vector2.ZERO, Color(0.2, 0.22, 0.25, 0.0), 0.4)
	for k in 4:
		mb.cylinder(bs + Vector3((float(k % 2) - 0.5) * 5.4, 0, (float(k / 2) - 0.5) * 2.0), 0.08, 0.08, 2.4, 5)
	pb.box(bs + Vector3(0, 1.5, -1.1), Vector3(4.0, 1.4, 0.08), Vector2.ZERO, Color(0.4, 0.8, 1.0, 1.0), 1.0)
	# street elevator shaft up to the guideway
	mb.box(p + Vector3(-14.0, 5.0, 6.0), Vector3(3.0, 10.0, 3.0), Vector2.ZERO, Color(0.3, 0.31, 0.34, 0.0), 0.3)
	tb.box(p + Vector3(-14.0, 10.2, 6.0), Vector3(3.2, 0.2, 3.2), Vector2.ZERO, Color(0.3, 0.9, 1.0, 1.0), 1.0)
	# plaza bollard lights
	for k in 10:
		var bp := p + Vector3(-24.0 + float(k) * 5.0, 0, -16.0)
		pb.cylinder(bp, 0.08, 0.08, 0.9, 5, Transform3D.IDENTITY, Vector2.ZERO, Color(0.1, 0.1, 0.12, 0.0))
		tb.box(bp + Vector3(0, 0.95, 0), Vector3(0.15, 0.15, 0.15), Vector2.ZERO, Color(0.6, 0.85, 1.0, 1.0), 1.0)

func _bridgeheads(gen: CityGen) -> void:
	for rs in gen.road_samples:
		if rs.cls != CityGen.RC_ARTERIAL:
			continue
		var pts: PackedVector3Array = rs.pts
		for k in range(0, pts.size() - 1):
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[k + 1]
			var d0 := p0.z - gen.infra.river_center(p0.x, gen)
			var d1 := p1.z - gen.infra.river_center(p1.x, gen)
			if d0 * d1 > 0.0:
				continue
			var t := d0 / maxf(d0 - d1, 0.001)
			var cross := p0.lerp(p1, t)
			for sgn in [-1.0, 1.0]:
				var deck := cross + Vector3(0, 0, sgn * 95.0)
				var mb := gen.buf(gen.chunk_of(deck), "mech")
				var tb := gen.buf(gen.chunk_of(deck), "trim")
				var pb := gen.buf(gen.chunk_of(deck), "prop_vc")
				mb.box(deck + Vector3(0, 0.3, 0), Vector3(16.0, 0.5, 10.0), Vector2.ZERO, Color(0.2, 0.19, 0.17, 0.0), 0.35)
				for r in 6:
					var rx := deck.x - 7.0 + float(r) * 2.8
					mb.box(Vector3(rx, 1.0, deck.z - 4.6), Vector3(0.1, 1.1, 0.1), Vector2.ZERO, Color(0.15, 0.15, 0.17, 0.0), 0.5)
					mb.box(Vector3(rx, 1.0, deck.z + 4.6), Vector3(0.1, 1.1, 0.1), Vector2.ZERO, Color(0.15, 0.15, 0.17, 0.0), 0.5)
				tb.box(deck + Vector3(-7.6, 1.6, -4.6), Vector3(0.12, 0.12, 9.2), Vector2.ZERO, Color(0.4, 0.85, 1.0, 1.0), 1.0)
				tb.box(deck + Vector3(7.6, 1.6, -4.6), Vector3(0.12, 0.12, 9.2), Vector2.ZERO, Color(0.4, 0.85, 1.0, 1.0), 1.0)
				for bch in 2:
					pb.box(deck + Vector3(-4.0 + float(bch) * 8.0, 0.85, 0.0), Vector3(2.0, 0.45, 0.6), Vector2.ZERO, Color(0.3, 0.22, 0.15, 0.0), 0.5)
