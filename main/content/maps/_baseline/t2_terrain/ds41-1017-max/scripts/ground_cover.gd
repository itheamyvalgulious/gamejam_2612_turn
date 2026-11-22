class_name GroundCover
extends Node3D

## Procedural grass, ferns, reeds and bushes.  All geometry is built here;
## the materials are pure shader math.  Instances are grouped per cell so
## frustum culling and distance ranges work.

const TreeGen := preload("res://scripts/tree_builder.gd")

var mats := {}
var meshes := {}
var cells := {}
var cell_size := 400.0
var stats := {}

func build(field: TerrainField, terrain: TerrainBuilder, materials: Dictionary) -> void:
	mats = materials
	meshes["grass"] = _grass_mesh(10, 0.75, 1.75)
	meshes["reed"] = _grass_mesh(6, 1.3, 2.7)
	meshes["fern"] = _fern_mesh()
	meshes["bush"] = _bush_mesh()

	var rng := RandomNumberGenerator.new()
	rng.seed = 1234567
	_scatter_region(field, terrain, rng, Vector2(-100.0, 720.0), 210.0, 1.7, "grass", 0.88)
	_scatter_region(field, terrain, rng, Vector2(-350.0, 620.0), 340.0, 4.0, "grass", 0.60)
	_scatter_region(field, terrain, rng, Vector2(250.0, 900.0), 420.0, 7.0, "grass", 0.40)
	_scatter_region(field, terrain, rng, Vector2(-120.0, 690.0), 170.0, 2.6, "fern", 0.8)
	_scatter_region(field, terrain, rng, Vector2(-320.0, 760.0), 280.0, 4.5, "fern", 0.5)
	_scatter_river(field, terrain, rng, 300.0, 1500.0, 3.0, "reed", 0.55)
	_scatter_river(field, terrain, rng, 150.0, 1150.0, 5.5, "bush", 0.30)
	print("[cover] ", stats)
	_emit()

func _grass_mesh(blades: int, hmin: float, hmax: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for b in blades:
		var ang := rng.randf_range(0.0, TAU)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-sin(ang), 0.0, cos(ang))
		var h := rng.randf_range(hmin, hmax)
		var lean := rng.randf_range(0.18, 0.55) * h
		var w0 := rng.randf_range(0.025, 0.055)
		var seg := 4
		var base := verts.size()
		for s in seg + 1:
			var t := float(s) / float(seg)
			var p := dir * lean * t * t + Vector3(0, h * t, 0)
			var w := w0 * (1.0 - t * 0.92)
			var n := Vector3(0, 0.55, 0).normalized() + dir * 0.3
			verts.append(p - side * w)
			verts.append(p + side * w)
			norms.append(n.normalized()); norms.append(n.normalized())
			uvs.append(Vector2(0, t)); uvs.append(Vector2(1, t))
		for s in seg:
			var a := base + s * 2
			idx.append(a); idx.append(a + 2); idx.append(a + 1)
			idx.append(a + 1); idx.append(a + 2); idx.append(a + 3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _fern_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 441
	for f in 8:
		var ang := TAU * float(f) / 8.0 + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-sin(ang), 0.0, cos(ang))
		var length := rng.randf_range(0.9, 1.6)
		var seg := 6
		var base := verts.size()
		for s in seg + 1:
			var t := float(s) / float(seg)
			var p := dir * length * t + Vector3(0, length * (0.55 * t - 0.62 * t * t), 0)
			var w := length * 0.16 * (1.0 - t * 0.75)
			var n := Vector3(0, 0.9, 0.0).normalized()
			verts.append(p - side * w)
			verts.append(p + side * w)
			norms.append(n); norms.append(n)
			uvs.append(Vector2(0, t)); uvs.append(Vector2(1, t))
		for s in seg:
			var a := base + s * 2
			idx.append(a); idx.append(a + 2); idx.append(a + 1)
			idx.append(a + 1); idx.append(a + 2); idx.append(a + 3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _bush_mesh() -> ArrayMesh:
	var tb := TreeGen.new(1717)
	var d := tb.far_blob(2.4, 2.2)
	return d.canopy

func _scatter_region(field: TerrainField, terrain: TerrainBuilder, rng: RandomNumberGenerator,
		center: Vector2, radius: float, step: float, kind: String, keep: float) -> void:
	var x := center.x - radius
	while x <= center.x + radius:
		var z := center.y - radius
		while z <= center.y + radius:
			var px := x + rng.randf_range(-step * 0.5, step * 0.5)
			var pz := z + rng.randf_range(-step * 0.5, step * 0.5)
			z += step
			if Vector2(px, pz).distance_to(center) > radius:
				continue
			var h: float = terrain.sample_height(px, pz)
			var wl := field.water_level(clampf(pz, TerrainField.POOL_Z, 1600.0))
			if h < wl + 0.6:
				continue
			var sl: float = terrain.sample_slope(px, pz)
			if sl > 0.62:
				continue
			var lake := Vector2(px + 553.0, pz + 1052.0).length()
			if lake < 245.0:
				continue
			var forest: float = smoothstep(-350.0, -100.0, pz) * smoothstep(400.0, 260.0, h)
			var p := keep * (0.45 + 0.55 * forest)
			if kind == "fern":
				p *= smoothstep(0.18, 0.55, forest + 0.2)
			if rng.randf() > p:
				continue
			var s := rng.randf_range(0.7, 1.35)
			if kind == "fern":
				s = rng.randf_range(0.8, 1.45)
			var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
			_add(kind, Transform3D(b, Vector3(px, h - 0.06, pz)), rng, px, pz)
		x += step

func _scatter_river(field: TerrainField, terrain: TerrainBuilder, rng: RandomNumberGenerator,
		z0: float, z1: float, step: float, kind: String, keep: float) -> void:
	var z := z0
	while z <= z1:
		var hw := field.river_halfwidth(z)
		var cx := field.river_x(z)
		var n := 10
		for i in n:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var off := hw * rng.randf_range(1.05, 3.6)
			var px := cx + side * off + rng.randf_range(-6.0, 6.0)
			var pz := z + rng.randf_range(-step, step)
			var h: float = terrain.sample_height(px, pz)
			var wl := field.water_level(clampf(pz, TerrainField.POOL_Z, 1600.0))
			if h < wl + 0.25:
				continue
			var sl: float = terrain.sample_slope(px, pz)
			if sl > 0.58:
				continue
			if rng.randf() > keep:
				continue
			var s := rng.randf_range(0.7, 1.4)
			var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s))
			_add(kind, Transform3D(b, Vector3(px, h - 0.06, pz)), rng, px, pz)
		z += step

func _add(kind: String, tr: Transform3D, rng: RandomNumberGenerator, px: float, pz: float) -> void:
	var key := Vector2i(int(floor((px + 1600.0) / cell_size)), int(floor((pz + 1600.0) / cell_size)))
	if not cells.has(key):
		cells[key] = {}
	if not cells[key].has(kind):
		cells[key][kind] = []
	cells[key][kind].append([tr, Color(rng.randf(), rng.randf(), rng.randf(), 1.0)])
	stats[kind] = stats.get(kind, 0) + 1

func _emit() -> void:
	for key in cells:
		for kind in cells[key]:
			var arr: Array = cells[key][kind]
			if arr.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = meshes[kind]
			mm.instance_count = arr.size()
			for i in arr.size():
				mm.set_instance_transform(i, arr[i][0])
				mm.set_instance_custom_data(i, arr[i][1])
			var mi := MultiMeshInstance3D.new()
			mi.name = "%s_%s" % [kind, key]
			mi.multimesh = mm
			mi.material_override = mats.get(kind, mats.grass)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 40.0
			if kind == "grass" or kind == "fern":
				mi.visibility_range_end = 150.0
				mi.visibility_range_end_margin = 50.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mi)