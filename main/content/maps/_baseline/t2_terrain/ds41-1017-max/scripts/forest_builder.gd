class_name ForestBuilder
extends Node3D

## Scatters ~5k procedurally built trees over the warm basin.
## Detailed leaf-card trees near the forest viewpoint; cheap canopy blobs further out.

const TreeFactory := preload("res://scripts/tree_builder.gd")

var tree_meshes := {}
var mats := {}
var cells := {}
var cell_size := 800.0
var detail_centers := [Vector2(-120.0, 720.0), Vector2(-160.0, 330.0), Vector2(-260.0, -110.0), Vector2(-500.0, 900.0)]
var detail_radii := [430.0, 360.0, 320.0, 300.0]
var detail_center := Vector2(-120.0, 720.0)
var detail_radius := 430.0
var counts := {}

func build(field: TerrainField, terrain: TerrainBuilder, materials: Dictionary) -> void:
	mats = materials
	var tb := TreeFactory.new(90210)
	tree_meshes["emergent"] = tb.emergent(52.0, true)
	tree_meshes["broadleaf"] = tb.broadleaf(31.0, 1.15, 23.0, true)
	tree_meshes["under"] = tb.broadleaf(12.0, 0.45, 9.0, false)
	tree_meshes["palm"] = tb.palm(19.0, true)
	tree_meshes["conifer"] = tb.conifer(26.0, true)
	tree_meshes["far"] = tb.far_blob(32.0, 24.0)

	for k in tree_meshes:
		var d: Dictionary = tree_meshes[k]
		d.bark.surface_set_material(0, mats.bark)
		var cmat: Material = mats.leaves
		if k == "palm":
			cmat = mats.palm
		elif k == "conifer":
			cmat = mats.needles
		elif k == "far":
			cmat = mats.far
		d.canopy.surface_set_material(0, cmat)

	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var clusters := FastNoiseLite.new()
	clusters.seed = 8811
	clusters.frequency = 0.0026
	clusters.fractal_type = FastNoiseLite.FRACTAL_FBM
	clusters.fractal_octaves = 3

	var step := 17.0
	var total := 0
	var x := -1585.0
	while x <= 1585.0:
		var z := -1585.0
		while z <= 1585.0:
			var px := x + rng.randf_range(-8.0, 8.0)
			var pz := z + rng.randf_range(-8.0, 8.0)
			z += step
			var h: float = terrain.sample_height(px, pz)
			if h < 4.0 or h > 492.0:
				continue
			var sl: float = terrain.sample_slope(px, pz)
			if sl > 0.48:
				continue
			var warm: float = smoothstep(-370.0, -120.0, pz)
			var low: float = smoothstep(390.0, 245.0, h)
			var flat: float = smoothstep(0.64, 0.32, sl)
			var forest: float = warm * low * flat
			if forest < 0.05:
				continue
			var dr: float = field.river_dist(px, pz)
			var hw: float = field.river_halfwidth(pz)
			if dr < hw * 1.7:
				continue
			var lake_d := Vector2(px + 553.0, pz + 1052.0).length()
			if lake_d < 265.0:
				continue
			var cl: float = 0.5 + 0.5 * clusters.get_noise_2d(px, pz)
			var keep: float = forest * (0.38 + 0.58 * cl)
			for ci in detail_centers.size():
				if Vector2(px, pz).distance_to(detail_centers[ci]) < detail_radii[ci]:
					keep = maxf(keep, forest * 0.90)
					break
			if rng.randf() > keep:
				continue

			if h > 380.0 and sl > 0.30:
				continue
			var kind := "broadleaf"
			if h > 315.0 and rng.randf() < 0.60:
				kind = "conifer"
			elif h < 245.0 and dr < hw * 6.0 and rng.randf() < 0.26:
				kind = "palm"
			else:
				var r := rng.randf()
				if r < 0.07:
					kind = "emergent"
				elif r < 0.70:
					kind = "broadleaf"
				else:
					kind = "under"
			var detail := false
			for ci in detail_centers.size():
				if Vector2(px, pz).distance_to(detail_centers[ci]) < detail_radii[ci]:
					detail = true
					break
			var lod := kind
			if not detail and (kind == "broadleaf" or kind == "emergent" or kind == "under"):
				lod = "far"
			var s := rng.randf_range(0.85, 1.30)
			if kind == "emergent":
				s = rng.randf_range(0.9, 1.3)
			elif kind == "under":
				s = rng.randf_range(0.7, 1.15)
			elif kind == "palm":
				s = rng.randf_range(0.8, 1.2)

			var key := Vector2i(int(floor((px + 1600.0) / cell_size)), int(floor((pz + 1600.0) / cell_size)))
			if not cells.has(key):
				cells[key] = {}
			if not cells[key].has(lod):
				cells[key][lod] = []
			var sy := rng.randf_range(0.82, 1.32)
			var sxz := rng.randf_range(0.88, 1.14)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s * sxz, s * sy, s * sxz))
			var tr := Transform3D(basis, Vector3(px, h - 0.35, pz))
			var tint := rng.randf()
			var phase := rng.randf()
			cells[key][lod].append([tr, Color(tint, phase, rng.randf(), 1.0)])
			counts[kind] = counts.get(kind, 0) + 1
			total += 1
		x += step
	print("[forest] ", total, " trees ", counts)
	_emit()

func _emit() -> void:
	for key in cells:
		for lod in cells[key]:
			var arr: Array = cells[key][lod]
			if arr.is_empty():
				continue
			if lod == "far":
				var sparse: Array = []
				var stride := 4
				var i := 0
				while i < arr.size():
					sparse.append(arr[i])
					i += stride
				if not sparse.is_empty():
					var df: Dictionary = tree_meshes["far"]
					_add_mm(df.canopy, mats.far, sparse, "canopy_far_%s" % key)
				continue
			var d: Dictionary = tree_meshes[lod]
			_add_mm(d.bark, mats.bark, arr, "bark_%s_%s" % [lod, key])
			var cmat: Material = mats.leaves
			if lod == "palm":
				cmat = mats.palm
			elif lod == "conifer":
				cmat = mats.needles
			elif lod == "far":
				cmat = mats.far
			_add_mm(d.canopy, cmat, arr, "canopy_%s_%s" % [lod, key])

func _add_mm(mesh: Mesh, mat: Material, arr: Array, nm: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = arr.size()
	for i in arr.size():
		mm.set_instance_transform(i, arr[i][0])
		mm.set_instance_custom_data(i, arr[i][1])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.extra_cull_margin = 80.0
	add_child(mi)