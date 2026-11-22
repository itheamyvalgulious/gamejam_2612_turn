class_name RockBuilder
extends Node3D

## Boulders, talus, river stones and cliff spires.  All shapes are displaced
## parametric primitives; the material is a procedural rock shader.

var mat: Material
var cells := {}
var spire_trans: Array = []

func build(field: TerrainField, terrain: TerrainBuilder, material: Material) -> void:
	mat = material
	var rng := RandomNumberGenerator.new()
	rng.seed = 606060
	var variants := []
	for v in 4:
		variants.append(_boulder_mesh(6100 + v * 37, rng))
	var spires := [_spire_mesh(901), _spire_mesh(902), _spire_mesh(903)]

	# river stones
	var z := -120.0
	while z < 1560.0:
		var cx := field.river_x(z)
		var hw := field.river_halfwidth(z)
		for k in 3:
			var off := rng.randf_range(-hw * 1.4, hw * 1.4)
			var px := cx + off
			var pz := z + rng.randf_range(-6.0, 6.0)
			var h: float = terrain.sample_height(px, pz)
			var wl := field.water_level(clampf(pz, TerrainField.POOL_Z, 1600.0))
			if h > wl + 2.2:
				continue
			var s := rng.randf_range(0.5, 2.6)
			_add_rock(variants[rng.randi() % 4], px, h + s * 0.15, pz, s, rng)
		z += 7.0

	# spires at the cliff base
	for i in 34:
		var px := rng.randf_range(-780.0, 200.0)
		var edge := field.plateau_edge(px)
		var pz := edge + rng.randf_range(55.0, 140.0)
		var h: float = terrain.sample_height(px, pz)
		var sl: float = terrain.sample_slope(px, pz)
		if sl > 0.55:
			continue
		var hh := rng.randf_range(12.0, 38.0)
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).rotated(Vector3.RIGHT, rng.randf_range(-0.08, 0.08)).scaled(Vector3(hh * 0.34, hh, hh * 0.34))
		var mi := MeshInstance3D.new()
		mi.mesh = spires[i % 3]
		mi.material_override = material
		mi.transform = Transform3D(b, Vector3(px, h - hh * 0.12, pz))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)

	_emit(variants)
	print("[rock] cells=", cells.size())

func _add_rock(mesh: Mesh, px: float, py: float, pz: float, s: float, rng: RandomNumberGenerator) -> void:
	var key := Vector2i(int(floor((px + 1600.0) / 700.0)), int(floor((pz + 1600.0) / 700.0)))
	if not cells.has(key):
		cells[key] = {}
	if not cells[key].has(mesh):
		cells[key][mesh] = []
	var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).rotated(Vector3.RIGHT, rng.randf_range(-0.4, 0.4))
	var sc := Vector3(s * rng.randf_range(0.75, 1.35), s * rng.randf_range(0.55, 1.0), s * rng.randf_range(0.75, 1.35))
	b = b.scaled(sc)
	cells[key][mesh].append(Transform3D(b, Vector3(px, py, pz)))

func _emit(variants: Array) -> void:
	for key in cells:
		for mesh in cells[key]:
			var arr: Array = cells[key][mesh]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = arr.size()
			for i in arr.size():
				mm.set_instance_transform(i, arr[i])
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)

func _boulder_mesh(seed: int, rng: RandomNumberGenerator) -> ArrayMesh:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.6
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	var lat := 9
	var lon := 14
	var pts: Array = []
	for j in lat + 1:
		var row := []
		var v := float(j) / float(lat)
		var phi := v * PI
		for i in lon:
			var u := float(i) / float(lon)
			var th := u * TAU
			var p := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var d := 1.0 + 0.28 * n.get_noise_3d(p.x * 1.2, p.y * 1.2, p.z * 1.2) + 0.10 * n.get_noise_3d(p.x * 3.5, p.y * 3.5, p.z * 3.5)
			row.append(p * d)
		pts.append(row)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in lat:
		for i in lon:
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][(i + 1) % lon]
			var c: Vector3 = pts[j + 1][i]
			var d: Vector3 = pts[j + 1][(i + 1) % lon]
			for tri in [[a, c, b], [b, c, d]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var base := verts.size()
				verts.append(p0); verts.append(p1); verts.append(p2)
				norms.append(p0.normalized()); norms.append(p1.normalized()); norms.append(p2.normalized())
				uvs.append(Vector2(0, 0)); uvs.append(Vector2(1, 0)); uvs.append(Vector2(0, 1))
				idx.append(base); idx.append(base + 1); idx.append(base + 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _spire_mesh(seed: int) -> ArrayMesh:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 2.2
	n.fractal_octaves = 3
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var sides := 9
	var rings := 7
	var grid: Array = []
	for r in rings + 1:
		var row := []
		var t := float(r) / float(rings)
		var rad := 0.30 * pow(1.0 - t, 0.75) + 0.015
		for s in sides:
			var a := TAU * float(s) / float(sides)
			var rr := rad * (1.0 + 0.30 * n.get_noise_2d(cos(a) * 3.0 + t * 2.0, sin(a) * 3.0))
			row.append(Vector3(cos(a) * rr, t, sin(a) * rr))
		grid.append(row)
	for r in rings:
		for s in sides:
			var a: Vector3 = grid[r][s]
			var b: Vector3 = grid[r][(s + 1) % sides]
			var c: Vector3 = grid[r + 1][s]
			var d: Vector3 = grid[r + 1][(s + 1) % sides]
			for tri in [[a, c, b], [b, c, d]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var base := verts.size()
				verts.append(p0); verts.append(p1); verts.append(p2)
				for q in [p0, p1, p2]:
					var rad := Vector3(q.x, 0.0, q.z)
					var nn := rad.normalized() if rad.length() > 0.001 else Vector3.UP
					norms.append((nn + Vector3(0, 0.25, 0)).normalized())
				idx.append(base); idx.append(base + 1); idx.append(base + 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m