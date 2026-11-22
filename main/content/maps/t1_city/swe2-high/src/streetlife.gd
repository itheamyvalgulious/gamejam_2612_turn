extends Node3D

## Street furniture: lamp poles along the major avenues — a thin mast
## and a glowing head. One MultiMesh for poles, one for heads.

var _hf: RefCounted


func _h(i: int, salt: int) -> float:
	var s := sin(float(i) * 127.1 + float(salt) * 13.7) * 43758.5453
	return s - floor(s)


func build(city: RefCounted, hf: RefCounted) -> void:
	_hf = hf
	var pole_mm := MultiMesh.new()
	pole_mm.transform_format = MultiMesh.TRANSFORM_3D
	pole_mm.use_colors = true
	var head_mm := MultiMesh.new()
	head_mm.transform_format = MultiMesh.TRANSFORM_3D
	head_mm.use_colors = true

	var pole_mesh := _box(Vector3(0.14, 7.2, 0.14))
	var head_mesh := _box(Vector3(1.4, 0.22, 0.42))

	var pt: Array = []
	var pc: Array = []
	var ht: Array = []
	var hc: Array = []
	var idx := 0
	for r in city.roads_major:
		var pts: PackedVector2Array = r
		for i in range(pts.size() - 1):
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var seg := p1 - p0
			var len := seg.length()
			if len < 20.0:
				continue
			var dir := seg / len
			var n := Vector2(-dir.y, dir.x)
			# a lamp every ~45 m, alternating kerb side
			var count := int(len / 45.0)
			for k in count:
				var t := (float(k) + 0.5) / float(count)
				var side := 1.0 if (idx + k) % 2 == 0 else -1.0
				var px := p0.x + dir.x * len * t + n.x * 12.0 * side
				var pz := p0.y + dir.y * len * t + n.y * 12.0 * side
				var gy: float = _hf.h(px, pz)
				if gy < -2.0:
					continue    # never in the canal
				var yaw := atan2(dir.x, dir.y)
				pt.append(Transform3D(
					Basis.from_euler(Vector3(0, yaw, 0)),
					Vector3(px, gy + 3.6, pz)))
				pc.append(Color(0.16, 0.17, 0.2))
				ht.append(Transform3D(
					Basis.from_euler(Vector3(0, yaw, 0)),
					Vector3(px, gy + 7.2, pz)))
				hc.append(Color(1.0, 0.78, 0.42))
			idx += count

	pole_mm.instance_count = pt.size()
	pole_mm.mesh = pole_mesh
	head_mm.instance_count = ht.size()
	head_mm.mesh = head_mesh
	for i in pt.size():
		pole_mm.set_instance_transform(i, pt[i])
		pole_mm.set_instance_color(i, pc[i])
	for i in ht.size():
		head_mm.set_instance_transform(i, ht[i])
		head_mm.set_instance_color(i, hc[i])

	# ---- vehicles: low-poly cars parked + a few moving on the avenue --
	var car_mm := MultiMesh.new()
	car_mm.transform_format = MultiMesh.TRANSFORM_3D
	car_mm.use_colors = true
	var car_mesh := _car_body()
	var ct: Array = []
	var cc: Array = []
	var car_cols := [
		Color(0.55, 0.1, 0.12), Color(0.12, 0.2, 0.5), Color(0.75, 0.72, 0.68),
		Color(0.2, 0.2, 0.22), Color(0.7, 0.55, 0.15), Color(0.15, 0.4, 0.3)]
	for r in city.roads_major:
		var pts: PackedVector2Array = r
		for i in range(pts.size() - 1):
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var seg := p1 - p0
			var len := seg.length()
			if len < 30.0:
				continue
			var dir := seg / len
			var n := Vector2(-dir.y, dir.x)
			var count := int(len / 90.0)
			for k in count:
				var t := _h(i * 7 + k, 5)
				var side := 1.0 if (k % 2 == 0) else -1.0
				var lane := 2.8 if side > 0 else -2.8   # right lane each dir
				var px := p0.x + dir.x * len * t + n.x * lane
				var pz := p0.y + dir.y * len * t + n.y * lane
				var gy: float = _hf.h(px, pz)
				if gy < -2.0:
					continue
				var yaw := atan2(dir.x, dir.y) + (PI if side < 0 else 0.0)
				ct.append(Transform3D(
					Basis.from_euler(Vector3(0, yaw, 0)),
					Vector3(px, gy + 0.75, pz)))
				cc.append(car_cols[int(_h(i + k * 3, 9) * 6.0)])
	car_mm.instance_count = ct.size()
	car_mm.mesh = car_mesh
	for i in ct.size():
		car_mm.set_instance_transform(i, ct[i])
		car_mm.set_instance_color(i, cc[i])
	var cmi := MultiMeshInstance3D.new()
	cmi.name = "Cars"
	cmi.multimesh = car_mm
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.35
	cm.metallic = 0.6
	cmi.material_override = cm
	add_child(cmi)

	# ---- signals at avenue junctions: red pole + three lights --------
	var sig_mm := MultiMesh.new()
	sig_mm.transform_format = MultiMesh.TRANSFORM_3D
	sig_mm.use_colors = true
	var sig_mesh := _signal()
	var st2: Array = []
	var sc: Array = []
	for r in city.roads_major:
		var pts: PackedVector2Array = r
		for i in range(0, pts.size() - 1, 8):
			var p0: Vector2 = pts[i]
			var gy: float = _hf.h(p0.x, p0.y)
			if gy < -2.0:
				continue
			for s in [-1.0, 1.0]:
				var p1: Vector2 = pts[i + 1]
				var dir := (p1 - p0).normalized()
				var n := Vector2(-dir.y, dir.x)
				var px: float = p0.x + n.x * 15.5 * s
				var pz: float = p0.y + n.y * 15.5 * s
				st2.append(Transform3D(
					Basis.from_euler(Vector3(0, atan2(dir.x, dir.y), 0)),
					Vector3(px, gy, pz)))
				sc.append(Color(1.0, 0.9, 0.6))
	sig_mm.instance_count = st2.size()
	sig_mm.mesh = sig_mesh
	for i in st2.size():
		sig_mm.set_instance_transform(i, st2[i])
		sig_mm.set_instance_color(i, sc[i])
	var smi := MultiMeshInstance3D.new()
	smi.name = "Signals"
	smi.multimesh = sig_mm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://gfx/landmark.gdshader")
	smi.material_override = sm
	add_child(smi)

	# light pools — a soft warm disc on the pavement under every lamp;
	# real streetlight is the ONLY thing that makes a night road read
	var pool_mm := MultiMesh.new()
	pool_mm.transform_format = MultiMesh.TRANSFORM_3D
	pool_mm.use_colors = true
	var pool_mesh := _light_pool()
	var pool_t: Array = []
	var pool_c: Array = []
	# pool list walks the avenue the same way the lamps do — one warm
	# disc under every pole, offset to the carriageway side
	for r in city.roads_major:
		var pts: PackedVector2Array = r
		for i in range(pts.size() - 1):
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var seg := p1 - p0
			var len := seg.length()
			var dir := seg / len
			var n := Vector2(-dir.y, dir.x)
			var count := int(len / 45.0)
			for k in count:
				var t := (float(k) + 0.5) / float(maxi(count, 1))
				# pools alternate sides with the lamps (pole ±14.5 m)
				var side := 1.0 if (i + k) % 2 == 0 else -1.0
				var px: float = p0.x + seg.x * t + n.x * 10.5 * side
				var pz: float = p0.y + seg.y * t + n.y * 10.5 * side
				var gy: float = _hf.h(px, pz)
				if gy < -2.0:
					continue
				# y above the carriageway lift (+0.12) and lane dashes
				# (+0.16) or the pool disappears under the road quad
				pool_t.append(Transform3D(Basis.IDENTITY,
					Vector3(px, gy + 0.20, pz)))
				pool_c.append(Color(1.0, 0.82, 0.5))
	pool_mm.instance_count = pool_t.size()
	pool_mm.mesh = pool_mesh
	for i in pool_t.size():
		pool_mm.set_instance_transform(i, pool_t[i])
		pool_mm.set_instance_color(i, pool_c[i])
	var plmi := MultiMeshInstance3D.new()
	plmi.name = "LightPools"
	plmi.multimesh = pool_mm
	var plm := StandardMaterial3D.new()
	plm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plm.vertex_color_use_as_albedo = true
	plm.albedo_color = Color(1, 1, 1, 1)
	plmi.material_override = plm
	add_child(plmi)

	var pmi := MultiMeshInstance3D.new()
	pmi.name = "LampPoles"
	pmi.multimesh = pole_mm
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.roughness = 0.6
	pm.metallic = 0.5
	pmi.material_override = pm
	add_child(pmi)

	var hmi := MultiMeshInstance3D.new()
	hmi.name = "LampHeads"
	hmi.multimesh = head_mm
	var hm := StandardMaterial3D.new()
	hm.vertex_color_use_as_albedo = true
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.72, 0.35)
	hm.emission_energy_multiplier = 3.0
	hmi.material_override = hm
	add_child(hmi)


func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


func _light_pool() -> ArrayMesh:
	# radial-fade disc — vertex alpha falls to 0 at the rim via a
	# second ring; simple two-ring fan is enough at 8 m radius
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r1 := 2.0
	var r2 := 7.5
	var segs := 10
	# centre fan (full alpha)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		st.set_color(Color(1, 1, 1, 0.55))
		st.add_vertex(Vector3(0, 0, 0))
		st.add_vertex(Vector3(cos(a1) * r1, 0, sin(a1) * r1))
		st.add_vertex(Vector3(cos(a0) * r1, 0, sin(a0) * r1))
	# rim ring (fade to 0)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		st.set_color(Color(1, 1, 1, 0.55))
		st.add_vertex(Vector3(cos(a0) * r1, 0, sin(a0) * r1))
		st.add_vertex(Vector3(cos(a1) * r1, 0, sin(a1) * r1))
		st.set_color(Color(1, 1, 1, 0.0))
		st.add_vertex(Vector3(cos(a1) * r2, 0, sin(a1) * r2))
		st.set_color(Color(1, 1, 1, 0.55))
		st.add_vertex(Vector3(cos(a0) * r1, 0, sin(a0) * r1))
		st.set_color(Color(1, 1, 1, 0.0))
		st.add_vertex(Vector3(cos(a1) * r2, 0, sin(a1) * r2))
		st.add_vertex(Vector3(cos(a0) * r2, 0, sin(a0) * r2))
	return st.commit()


func _car_body() -> ArrayMesh:
	# two-box car: body slab + cabin slab — readable at 3 m
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [
		[Vector3(0, 0, 0), Vector3(4.6, 0.65, 1.85)],          # body
		[Vector3(-0.2, 0.65, 0.05), Vector3(2.6, 0.75, 1.65)], # cabin
	]
	for p in parts:
		_add_box(st, p[0], p[1])
	return st.commit()


func _signal() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(st, Vector3(0, 0, 0), Vector3(0.18, 5.5, 0.18))     # pole
	_add_box(st, Vector3(0, 4.0, 0), Vector3(0.5, 1.4, 0.28))    # head
	return st.commit()


func _add_box(st: SurfaceTool, mn: Vector3, sz: Vector3) -> void:
	var c := mn + sz * 0.5
	var hx := sz.x / 2; var hy := sz.y / 2; var hz := sz.z / 2
	var f := [
		[Vector3(c.x - hx, c.y - hy, c.z - hz), Vector3(c.x + hx, c.y - hy, c.z - hz),
		 Vector3(c.x + hx, c.y + hy, c.z - hz), Vector3(c.x - hx, c.y + hy, c.z - hz)],
		[Vector3(c.x + hx, c.y - hy, c.z + hz), Vector3(c.x - hx, c.y - hy, c.z + hz),
		 Vector3(c.x - hx, c.y + hy, c.z + hz), Vector3(c.x + hx, c.y + hy, c.z + hz)],
		[Vector3(c.x - hx, c.y - hy, c.z + hz), Vector3(c.x - hx, c.y - hy, c.z - hz),
		 Vector3(c.x - hx, c.y + hy, c.z - hz), Vector3(c.x - hx, c.y + hy, c.z + hz)],
		[Vector3(c.x + hx, c.y - hy, c.z - hz), Vector3(c.x + hx, c.y - hy, c.z + hz),
		 Vector3(c.x + hx, c.y + hy, c.z + hz), Vector3(c.x + hx, c.y + hy, c.z - hz)],
		[Vector3(c.x - hx, c.y + hy, c.z - hz), Vector3(c.x + hx, c.y + hy, c.z - hz),
		 Vector3(c.x + hx, c.y + hy, c.z + hz), Vector3(c.x - hx, c.y + hy, c.z + hz)],
		[Vector3(c.x - hx, c.y - hy, c.z + hz), Vector3(c.x + hx, c.y - hy, c.z + hz),
		 Vector3(c.x + hx, c.y - hy, c.z - hz), Vector3(c.x - hx, c.y - hy, c.z - hz)],
	]
	for q in f:
		var n: Vector3 = (q[1] - q[0]).cross(q[2] - q[0]).normalized()
		st.set_normal(n)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(q[0]); st.add_vertex(q[1]); st.add_vertex(q[2])
		st.add_vertex(q[0]); st.add_vertex(q[2]); st.add_vertex(q[3])
