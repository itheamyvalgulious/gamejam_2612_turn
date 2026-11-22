class_name PropsGen
extends RefCounted
## Street-level life: streetlights + light pools, ground traffic, flying cars,
## trees, pedestrians, traffic signals, neon signage & holo billboards.

func generate(gen: CityGen) -> void:
	_streetlights(gen)
	_vehicles(gen)
	_flying(gen)
	_trees(gen)
	_peds(gen)
	_signals(gen)
	_signs(gen)
	_street_furniture(gen)

func _mm(root: Node3D, mesh: ArrayMesh, xfs: Array, name: String) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = xfs.size()
	mm.mesh = mesh
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.name = name
	root.add_child(mi)

# ---------------------------------------------------------------- streetlights

func _lamp_mesh() -> ArrayMesh:
	var b := MeshBuf.new()
	var dark := Color(0.08, 0.08, 0.09, 0.0)
	b.cylinder(Vector3.ZERO, 0.09, 0.07, 8.0, 6, Transform3D.IDENTITY, Vector2.ZERO, dark)
	b.box(Vector3(0, 7.9, 0.8), Vector3(0.12, 0.12, 1.7), Vector2.ZERO, dark, 0.5)
	b.box(Vector3(0, 7.8, 1.6), Vector3(0.35, 0.18, 0.8), Vector2.ZERO, Color(1.0, 0.78, 0.5, 1.0), 0.5)
	var m := ArrayMesh.new()
	b.make_surface(m, null)
	return m

func _streetlights(gen: CityGen) -> void:
	var xfs := []
	var pb := MeshBuf.new()
	for rs in gen.road_samples:
		var pts: PackedVector3Array = rs.pts
		var cls: int = rs.cls
		var hw := gen.half_width(cls)
		var sw := gen.sw_width(cls)
		for k in range(0, pts.size() - 1):
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[k + 1]
			var seg := p1 - p0
			var ln := seg.length()
			var tang := seg / maxf(ln, 0.001)
			var perp := Vector3(-tang.z, 0, tang.x)
			var n := int(ln / 36.0)
			for s in n + 1:
				var t := float(s) / float(maxi(n, 1))
				var p := p0.lerp(p1, t)
				for side in [-1.0, 1.0]:
					var side_f := float(side)
					var base := p + perp * side_f * (hw + sw * 0.55)
					if (base - gen.focus).length() > gen.R_MID:
						continue
					var ang := atan2(-(-perp * side_f).z, (-perp * side_f).x)
					xfs.append(Transform3D(Basis(Vector3.UP, ang), base + Vector3(0, 0.16, 0)))
					# light pool on carriageway
					var pc := p + perp * side_f * hw * 0.45 + Vector3(0, 0.035, 0)
					var r := 9.0
					var q0 := pc - tang * r - perp * r
					var q1 := pc + tang * r - perp * r
					var q2 := pc + tang * r + perp * r
					var q3 := pc - tang * r + perp * r
					pb.quad_o(q0, q1, q2, q3, Vector3.UP, PackedVector2Array([
						Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
	var mesh := _lamp_mesh()
	# material assigned via surface override below
	mesh.surface_set_material(0, gen.mats["prop_vc"])
	_mm(gen._root, mesh, xfs, "streetlights")
	_flush_buf(gen, pb, "pool")

func _flush_buf(gen: CityGen, b: MeshBuf, mat: String) -> void:
	if b.is_empty():
		return
	var mesh := ArrayMesh.new()
	b.make_surface(mesh, gen.mats[mat])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "props_" + mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gen._root.add_child(mi)

# ---------------------------------------------------------------- vehicles

func _car_mesh() -> ArrayMesh:
	var b := MeshBuf.new()
	var body := Color(0.25, 0.27, 0.32, 0.0)
	b.box(Vector3(0, 0.65, 0), Vector3(4.4, 1.1, 1.85), Vector2.ZERO, body, 0.5)
	b.box(Vector3(-0.3, 1.45, 0), Vector3(2.3, 0.75, 1.65), Vector2.ZERO, Color(0.05, 0.06, 0.08, 0.0), 0.5)
	# headlights / taillights
	b.box(Vector3(2.21, 0.75, 0.55), Vector3(0.06, 0.22, 0.4), Vector2.ZERO, Color(1.0, 0.95, 0.8, 1.0), 1.0)
	b.box(Vector3(2.21, 0.75, -0.55), Vector3(0.06, 0.22, 0.4), Vector2.ZERO, Color(1.0, 0.95, 0.8, 1.0), 1.0)
	b.box(Vector3(-2.21, 0.8, 0.6), Vector3(0.06, 0.18, 0.35), Vector2.ZERO, Color(1.0, 0.08, 0.05, 1.0), 1.0)
	b.box(Vector3(-2.21, 0.8, -0.6), Vector3(0.06, 0.18, 0.35), Vector2.ZERO, Color(1.0, 0.08, 0.05, 1.0), 1.0)
	var m := ArrayMesh.new()
	b.make_surface(m, null)
	return m

func _vehicles(gen: CityGen) -> void:
	var rng := gen.rng
	var xfs := []
	for rs in gen.road_samples:
		var pts: PackedVector3Array = rs.pts
		var cls: int = rs.cls
		var hw := gen.half_width(cls)
		for k in range(0, pts.size() - 1):
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[k + 1]
			var seg := p1 - p0
			var ln := seg.length()
			var tang := seg / maxf(ln, 0.001)
			var perp := Vector3(-tang.z, 0, tang.x)
			var lanes := [3.2, -3.2] if cls == 1 else [2.6, -2.6]
			if cls == 1:
				lanes.append(6.4)
				lanes.append(-6.4)
			for lane in lanes:
				var lane_f := float(lane)
				var spacing := 26.0 + rng.randf() * 30.0
				var count := int(ln / spacing)
				for c in count + 1:
					if rng.randf() < 0.35:
						continue
					var t := clampf((float(c) * spacing + rng.randf() * 8.0) / maxf(ln, 1.0), 0.02, 0.98)
					var p := p0.lerp(p1, t) + perp * lane_f
					if (p - gen.focus).length() > gen.R_MID:
						continue
					var dirv := tang if lane_f > 0 else -tang
					var ang := atan2(-dirv.z, dirv.x)
					xfs.append(Transform3D(Basis(Vector3.UP, ang), p + Vector3(0, 0.05, 0)))
	var mesh := _car_mesh()
	mesh.surface_set_material(0, gen.mats["prop_vc"])
	_mm(gen._root, mesh, xfs, "cars")

# ---------------------------------------------------------------- flying cars

func _flying(gen: CityGen) -> void:
	var rng := gen.rng
	var b := MeshBuf.new()
	b.box(Vector3.ZERO, Vector3(5.5, 1.0, 1.7), Vector2.ZERO, Color(0.12, 0.13, 0.17, 0.0), 0.5)
	b.box(Vector3(0.4, 0.7, 0), Vector3(2.0, 0.6, 1.4), Vector2.ZERO, Color(0.05, 0.06, 0.09, 0.0), 0.5)
	b.box(Vector3(0, -0.55, 0), Vector3(4.0, 0.12, 1.2), Vector2.ZERO, Color(0.3, 0.9, 1.0, 1.0), 1.0)
	b.box(Vector3(-2.9, 0, 0), Vector3(0.3, 0.35, 1.3), Vector2.ZERO, Color(1.0, 0.3, 0.15, 1.0), 1.0)
	b.box(Vector3(2.9, 0, 0.5), Vector3(0.2, 0.2, 0.3), Vector2.ZERO, Color(1.0, 1.0, 0.9, 1.0), 1.0)
	b.box(Vector3(2.9, 0, -0.5), Vector3(0.2, 0.2, 0.3), Vector2.ZERO, Color(1.0, 1.0, 0.9, 1.0), 1.0)
	var mesh := ArrayMesh.new()
	b.make_surface(mesh, gen.mats["prop_vc"])
	var xfs := []
	for lane in 5:
		var y := 60.0 + float(lane) * 22.0
		var z0 := -900.0 + float(lane) * 350.0 + rng.randf_range(-80, 80)
		var x0 := -1750.0
		var dirv := 1.0 if lane % 2 == 0 else -1.0
		var count := 14
		for c in count:
			var x := x0 + dirv * (float(c) * 260.0 + rng.randf() * 160.0)
			if dirv < 0:
				x = -x
			var z := z0 + sin(x * 0.0016 + float(lane)) * 220.0
			var p := Vector3(x, y + sin(x * 0.01) * 3.0, z)
			var tang := Vector3(dirv, 0, cos(x * 0.0016 + float(lane)) * 0.35).normalized()
			var ang := atan2(-tang.z, tang.x)
			xfs.append(Transform3D(Basis(Vector3.UP, ang), p))
	_mm(gen._root, mesh, xfs, "flycars")

# ---------------------------------------------------------------- trees

func _tree_mesh() -> ArrayMesh:
	var b := MeshBuf.new()
	var bark := Color(0.12, 0.08, 0.05, 0.0)
	var leaf := Color(0.06, 0.14, 0.05, 0.0)
	b.cylinder(Vector3.ZERO, 0.14, 0.1, 2.6, 5, Transform3D.IDENTITY, Vector2.ZERO, bark)
	b.cylinder(Vector3(0, 2.4, 0), 1.7, 0.9, 2.6, 6, Transform3D.IDENTITY, Vector2.ZERO, leaf)
	b.cylinder(Vector3(0, 4.2, 0), 1.1, 0.2, 1.8, 6, Transform3D.IDENTITY, Vector2.ZERO, leaf)
	var m := ArrayMesh.new()
	b.make_surface(m, null)
	return m

func _trees(gen: CityGen) -> void:
	var rng := gen.rng
	var xfs := []
	for ci in gen.cell_info:
		var dtype: int = ci.dtype
		var center: Vector3 = ci.center
		if (center - gen.focus).length() > gen.R_MID:
			continue
		var density: float = Districts.params(dtype).trees
		if density <= 0.05:
			continue
		var inner: Array = ci.inner
		var area := CityMath.poly_area2(inner)
		var count := int(area / (900.0 / density))
		count = mini(count, 60)
		for k in count:
			var u := rng.randf()
			var v := rng.randf()
			var p := _bilinear(inner, u, v)
			var s := rng.randf_range(0.8, 1.5)
			xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, 0).scaled(Vector3(s, s, s)), p))
	var mesh := _tree_mesh()
	mesh.surface_set_material(0, gen.mats["prop_vc"])
	_mm(gen._root, mesh, xfs, "trees")

func _bilinear(q: Array, u: float, v: float) -> Vector3:
	var a: Vector3 = q[0]
	var b: Vector3 = q[1]
	var c: Vector3 = q[2]
	var d: Vector3 = q[3]
	return a.lerp(b, u).lerp(d.lerp(c, u), v)

# ---------------------------------------------------------------- pedestrians

func _peds(gen: CityGen) -> void:
	var rng := gen.rng
	var b := MeshBuf.new()
	b.box(Vector3(0, 0.75, 0), Vector3(0.38, 1.35, 0.26), Vector2.ZERO, Color(0.1, 0.1, 0.13, 0.0), 1.0)
	b.box(Vector3(0, 1.55, 0), Vector3(0.2, 0.24, 0.22), Vector2.ZERO, Color(0.35, 0.25, 0.2, 0.0), 1.0)
	b.box(Vector3(0.24, 1.05, 0.1), Vector3(0.05, 0.12, 0.08), Vector2.ZERO, Color(0.5, 0.8, 1.0, 1.0), 1.0)
	var mesh := ArrayMesh.new()
	b.make_surface(mesh, gen.mats["prop_vc"])
	var xfs := []
	for rs in gen.road_samples:
		var pts: PackedVector3Array = rs.pts
		var hw := gen.half_width(rs.cls)
		var sw := gen.sw_width(rs.cls)
		for k in range(0, pts.size() - 1):
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[k + 1]
			var seg := p1 - p0
			var ln := seg.length()
			var tang := seg / maxf(ln, 0.001)
			var perp := Vector3(-tang.z, 0, tang.x)
			var n := int(ln / 16.0)
			for s in n + 1:
				if rng.randf() < 0.35:
					continue
				var t := float(s) / float(maxi(n, 1))
				var p := p0.lerp(p1, t)
				var side: float = 1.0 if rng.randf() < 0.5 else -1.0
				var base := p + perp * side * (hw + sw * rng.randf_range(0.2, 0.8))
				if (base - gen.focus).length() > gen.R_DETAIL:
					continue
				xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), base + Vector3(0, 0.16, 0)))
	_mm(gen._root, mesh, xfs, "peds")

# ---------------------------------------------------------------- signals

func _signals(gen: CityGen) -> void:
	var b := MeshBuf.new()
	var dark := Color(0.06, 0.06, 0.07, 0.0)
	b.cylinder(Vector3.ZERO, 0.08, 0.08, 5.5, 5, Transform3D.IDENTITY, Vector2.ZERO, dark)
	b.box(Vector3(0, 5.2, 0.6), Vector3(0.1, 0.1, 1.2), Vector2.ZERO, dark, 0.5)
	b.box(Vector3(0, 5.0, 1.3), Vector3(0.25, 0.7, 0.3), Vector2.ZERO, dark, 0.5)
	b.box(Vector3(0.14, 5.2, 1.3), Vector3(0.03, 0.14, 0.14), Vector2.ZERO, Color(1.0, 0.1, 0.1, 1.0), 1.0)
	b.box(Vector3(0.14, 4.8, 1.3), Vector3(0.03, 0.14, 0.14), Vector2.ZERO, Color(0.1, 1.0, 0.2, 1.0), 1.0)
	var mesh := ArrayMesh.new()
	b.make_surface(mesh, gen.mats["prop_vc"])
	var xfs := []
	for i in range(4, gen.nx, 4):
		for j in range(4, gen.nz, 4):
			var p: Vector3 = gen.node(i, j)
			if (p - gen.focus).length() > gen.R_MID:
				continue
			for q in 4:
				var ang := float(q) * PI * 0.5 + 0.785
				xfs.append(Transform3D(Basis(Vector3.UP, ang), p + Vector3(
					cos(ang) * 11.0, 0.16, -sin(ang) * 11.0)))
	_mm(gen._root, mesh, xfs, "signals")

# ---------------------------------------------------------------- signage

func _signs(gen: CityGen) -> void:
	var rng := gen.rng
	var sb := MeshBuf.new()
	var hb := MeshBuf.new()
	for st in gen.sign_targets:
		var dtype: int = st.dtype
		var tier: int = st.tier
		if tier > 1:
			continue
		var neon: float = Districts.params(dtype).neon
		var pos: Vector3 = st.pos
		var h: float = st.h
		var dirs: Array = st.dirs
		if dirs.is_empty():
			continue
		var d: Dictionary = dirs[rng.randi_range(0, dirs.size() - 1)]
		var n: Vector3 = d.n
		var fpos: Vector3 = d.pos
		var flen: float = d.len
		var tang := Vector3(-n.z, 0, n.x)
		# vertical blade sign
		if rng.randf() < neon * 0.9 and h > 10.0:
			var y := clampf(h * rng.randf_range(0.2, 0.55), 6.0, 70.0)
			var bh := rng.randf_range(4.0, 9.0)
			var a := fpos + n * 0.4 + Vector3(0, y, 0)
			var bq := fpos + n * 2.6 + Vector3(0, y, 0)
			var seedf := rng.randf() * 500.0
			sb.quad_o(a, bq, bq + Vector3(0, bh, 0), a + Vector3(0, bh, 0), tang,
				PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]),
				Vector2(seedf, 0.0))
		# rooftop sign
		if rng.randf() < neon * 0.5 and h > 14.0:
			var w := clampf(flen * 0.6, 4.0, 16.0)
			var y2 := h + 1.0
			var hh := rng.randf_range(2.5, 5.0)
			var a := fpos + n * 0.5 + tang * (-w * 0.5) + Vector3(0, y2, 0)
			var seedf := rng.randf() * 500.0
			sb.quad_o(a, a + tang * w, a + tang * w + Vector3(0, hh, 0), a + Vector3(0, hh, 0),
				n, PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]),
				Vector2(seedf, 1.0))
		# holo billboard on tall downtown towers
		if dtype == Districts.D.DOWNTOWN and h > 60.0 and rng.randf() < 0.5:
			var w := clampf(flen * 0.7, 8.0, 22.0)
			var hh := w * 0.62
			var y3 := h * rng.randf_range(0.45, 0.7)
			var a := fpos + n * 0.7 + tang * (-w * 0.5) + Vector3(0, y3, 0)
			var seedf := rng.randf() * 500.0
			hb.quad_o(a, a + tang * w, a + tang * w + Vector3(0, hh, 0), a + Vector3(0, hh, 0),
				n, PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]),
				Vector2(seedf, 0.0))
	_flush_buf(gen, sb, "sign")
	_flush_buf(gen, hb, "holo")

# ---------------------------------------------------------------- street furniture
func _street_furniture(gen: CityGen) -> void:
	var rng := gen.rng
	var fb := MeshBuf.new()   # dark metal / props
	var tb := MeshBuf.new()   # emissive
	# guard rails along arterials + bins + poles/wires on locals
	for rs in gen.road_samples:
		var pts: PackedVector3Array = rs.pts
		var cls: int = rs.cls
		var hw := gen.half_width(cls)
		var sw := gen.sw_width(cls)
		for k in range(0, pts.size() - 1):
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[k + 1]
			var seg := p1 - p0
			var ln := seg.length()
			var tang := seg / maxf(ln, 0.001)
			var perp := Vector3(-tang.z, 0, tang.x)
			var mid := (p0 + p1) * 0.5
			if cls == CityGen.RC_ARTERIAL and (mid - gen.focus).length() < gen.R_DETAIL:
				for side in [-1.0, 1.0]:
					var side_f := float(side)
					var off := (hw + sw * 0.35) * side_f
					# posts + double rail
					var npost := int(ln / 2.0)
					for q in npost + 1:
						var pp := p0.lerp(p1, float(q) / float(maxi(npost, 1))) + perp * off
						fb.box(pp + Vector3(0, 0.55, 0), Vector3(0.08, 1.1, 0.08), Vector2.ZERO, Color(0.12, 0.12, 0.14, 0.0), 0.5)
					for rh in [0.55, 0.95]:
						fb.box(mid + perp * off + Vector3(0, rh, 0), Vector3(ln, 0.06, 0.10), Vector2.ZERO,
							Color(0.14, 0.14, 0.16, 0.0), 0.5,
							Transform3D(Basis(Vector3.UP, atan2(-tang.z, tang.x)), mid + perp * off + Vector3(0, rh, 0)))
			if (mid - gen.focus).length() < gen.R_DETAIL:
				# trash bin + kiosk chance per segment
				if rng.randf() < 0.5:
					var bt := rng.randf_range(0.15, 0.85)
					var bp := p0.lerp(p1, bt) + perp * (hw + sw * 0.7) * (1.0 if rng.randf() < 0.5 else -1.0)
					fb.box(bp + Vector3(0, 0.62, 0), Vector3(0.62, 1.15, 0.62), Vector2.ZERO, Color(0.06, 0.12, 0.07, 0.0), 0.5)
					fb.box(bp + Vector3(0, 1.24, 0), Vector3(0.66, 0.08, 0.66), Vector2.ZERO, Color(0.1, 0.1, 0.1, 0.0), 0.5)
				if cls == CityGen.RC_ARTERIAL and rng.randf() < 0.35:
					var kp := mid + perp * (hw + sw + 1.6) * (1.0 if rng.randf() < 0.5 else -1.0)
					var ka := rng.randf() * TAU
					var kx := Transform3D(Basis(Vector3.UP, ka), kp)
					fb.box(Vector3(0, 1.2, 0), Vector3(2.6, 2.4, 2.0), Vector2.ZERO, Color(0.25, 0.1, 0.08, 0.0), 0.4, kx)
					fb.box(Vector3(0, 2.55, 0.2), Vector3(3.0, 0.12, 2.6), Vector2.ZERO, Color(0.1, 0.1, 0.12, 0.0), 0.4, kx)
					tb.box(Vector3(0, 1.5, 1.02), Vector3(1.8, 1.2, 0.05), Vector2.ZERO, Color(1.0, 0.85, 0.6, 1.0), 1.0, kx)
					tb.box(Vector3(1.32, 1.4, 0), Vector3(0.05, 1.4, 1.4), Vector2.ZERO, Color(0.4, 0.8, 1.0, 1.0), 1.0, kx)
			# utility poles + catenary wires on local roads
			if cls == CityGen.RC_LOCAL and (mid - gen.focus).length() < gen.R_DETAIL:
				var pa := p0 + perp * (hw + sw * 0.8)
				var pbq := p1 + perp * (hw + sw * 0.8)
				fb.cylinder(pa, 0.09, 0.07, 7.0, 5, Transform3D.IDENTITY, Vector2.ZERO, Color(0.08, 0.07, 0.06, 0.0))
				fb.box(pa + Vector3(0, 6.7, 0), Vector3(0.1, 0.1, 1.6), Vector2.ZERO, Color(0.08, 0.07, 0.06, 0.0), 0.5)
				for wseg in 6:
					var t0 := float(wseg) / 6.0
					var t1 := float(wseg + 1) / 6.0
					var w0 := pa.lerp(pbq, t0) + Vector3(0, 6.6 - sin(t0 * PI) * 0.55, 0)
					var w1 := pa.lerp(pbq, t1) + Vector3(0, 6.6 - sin(t1 * PI) * 0.55, 0)
					var wd := w1 - w0
					var wl := wd.length()
					fb.box((w0 + w1) * 0.5, Vector3(wl, 0.035, 0.035), Vector2.ZERO, Color(0.05, 0.05, 0.05, 0.0), 1.0,
						Transform3D(Basis(Vector3.UP, atan2(-wd.z, wd.x)), (w0 + w1) * 0.5))
	_flush_merged(gen, fb, "prop_vc")
	_flush_merged(gen, tb, "trim")

func _flush_merged(gen: CityGen, b: MeshBuf, mat: String) -> void:
	if b.is_empty():
		return
	var mesh := ArrayMesh.new()
	b.make_surface(mesh, gen.mats[mat])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "street_furniture_" + mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gen._root.add_child(mi)
