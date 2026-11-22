class_name WaterBody
extends Node3D
## Procedural water: subdivided river ribbon whose UV.x runs ALONG the channel
## (flow-aligned advection + geometric waves in the shader), a lake grid, cascade
## mist billboards at the two waterfall lips, and reef rocks in the rapids.

const TerrainGen := preload("res://scripts/terrain_gen.gd")

var data: TerrainGen
var material: ShaderMaterial
var mist_mat: ShaderMaterial
var rock_mat: Material

const LAKE_Y := TerrainGen.RIVER_WL_S + 1.0
const FALLS := [Vector2(1140.0, 1162.0), Vector2(1740.0, 1758.0)]

func setup(d: TerrainGen) -> void:
	data = d
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	mist_mat = ShaderMaterial.new()
	mist_mat.shader = load("res://shaders/mist.gdshader")
	rock_mat = ShaderMaterial.new()
	rock_mat.shader = load("res://shaders/rock.gdshader")
	_build_river()
	_build_lake()
	_build_falls()

func _mtn_mask(z: float) -> float:
	return 1.0 - TerrainGen.smoothstep(TerrainGen.MTN_HALF * 0.55, TerrainGen.MTN_HALF, absf(z - TerrainGen.MTN_CENTER))

func _half_w(z: float) -> float:
	return lerpf(55.0, 42.0, _mtn_mask(z))

func _slope_along(z: float) -> float:
	var a := data.river_wl(z - 8.0)
	var b := data.river_wl(z + 8.0)
	return (a - b) / 16.0

# ------------------------------------------------------------------ river ribbon
func _build_river() -> void:
	var step := 8.0
	var across := 7
	var n := int(TerrainGen.WORLD_Z / step) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var s := 0.0
	var prev_c := data.river_x(0.0)
	for j in range(n):
		var z := clampf(j * step, 0.0, TerrainGen.WORLD_Z)
		var cx := data.river_x(z)
		if j > 0:
			s += Vector2(cx - prev_c, step).length()
		prev_c = cx
		var wl := data.river_wl(z)
		var hw := _half_w(z)
		var sl := _slope_along(z)
		var sp := clampf(1.0 + sl * 6.0, 0.7, 3.0)
		var rap := TerrainGen.smoothstep(0.04, 0.22, sl)
		for i in range(across):
			var t := float(i) / float(across - 1)
			var x := cx + (t - 0.5) * 2.0 * hw
			verts.push_back(Vector3(x, wl + 0.5, z))
			norms.push_back(Vector3.UP)
			uvs.push_back(Vector2(s, t))
			cols.push_back(Color(sp, rap, 0.0, 1.0))
	var idxs := PackedInt32Array()
	for j in range(n - 1):
		for i in range(across - 1):
			var a := j * across + i
			var b := a + 1
			var c := a + across
			var d2 := c + 1
			idxs.push_back(a); idxs.push_back(b); idxs.push_back(c)
			idxs.push_back(b); idxs.push_back(d2); idxs.push_back(c)
	var mi := _mesh_from(verts, norms, uvs, cols, idxs, material)
	mi.name = "river"
	add_child(mi)
	_build_reefs()

# ------------------------------------------------------------------ reef rocks in rapids
func _build_reefs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	for f in FALLS:
		for k in range(7):
			var z := lerpf(f.x - 50.0, f.y + 90.0, rng.randf())
			var cx := data.river_x(z)
			var hw := _half_w(z)
			var x := cx + rng.randf_range(-0.55, 0.55) * hw
			var wl := data.river_wl(z)
			var r := rng.randf_range(1.2, 3.0)
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = r
			sm.height = r * 1.3
			sm.radial_segments = 7
			sm.rings = 4
			sm.material = rock_mat
			mi.mesh = sm
			mi.position = Vector3(x, wl - r * 0.25, z)
			mi.rotation_degrees = Vector3(rng.randf_range(0, 40), rng.randf_range(0, 360), rng.randf_range(0, 40))
			mi.scale = Vector3(1.0, rng.randf_range(0.6, 0.9), rng.randf_range(0.8, 1.3))
			add_child(mi)

# ------------------------------------------------------------------ lake grid
func _build_lake() -> void:
	var nx := 40
	var nz := 25
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for j in range(nz + 1):
		for i in range(nx + 1):
			var x := float(i) / nx * TerrainGen.WORLD_X
			var z := float(j) / nz * TerrainGen.WORLD_Z
			verts.push_back(Vector3(x, LAKE_Y, z))
			norms.push_back(Vector3.UP)
			uvs.push_back(Vector2(x * 0.35, z * 0.35))
			cols.push_back(Color(0.35, 0.0, 0.0, 1.0))
	var idxs := PackedInt32Array()
	for j in range(nz):
		for i in range(nx):
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d2 := c + 1
			idxs.push_back(a); idxs.push_back(b); idxs.push_back(c)
			idxs.push_back(b); idxs.push_back(d2); idxs.push_back(c)
	var mi := _mesh_from(verts, norms, uvs, cols, idxs, material)
	mi.name = "lake"
	add_child(mi)

# ------------------------------------------------------------------ waterfall mist
func _build_falls() -> void:
	var rng_fall := RandomNumberGenerator.new()
	rng_fall.seed = 4242
	for f in FALLS:
		var zb: float = f.y + 10.0
		var cx := data.river_x(zb)
		var wl := data.river_wl(zb)
		var hw := _half_w(zb)
		for k in range(2):
			var sm := SphereMesh.new()
			sm.radius = hw * (0.7 + 0.3 * float(k))
			sm.height = 6.0 + 3.0 * float(k)
			sm.radial_segments = 12
			sm.rings = 6
			sm.material = mist_mat
			var mi := MeshInstance3D.new()
			mi.mesh = sm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(cx + rng_fall.randf_range(-6, 6), wl + 1.5 + 1.5 * float(k), zb + rng_fall.randf_range(-4, 6))
			add_child(mi)

# ------------------------------------------------------------------ helper
func _mesh_from(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, c: PackedColorArray, idx: PackedInt32Array, mat: Material) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi
