class_name WaterBody
extends Node3D
## Procedural water: a southern lake plane plus a river ribbon that follows the
## carved valley downhill from the snowfield to the lake. Shader does waves/foam/depth.

const TerrainGen := preload("res://scripts/terrain_gen.gd")

var data: TerrainGen
var material: ShaderMaterial

const LAKE_Y := TerrainGen.RIVER_WL_S + 1.0

func setup(d: TerrainGen) -> void:
	data = d
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	_build_lake()
	_build_river()

func _build_lake() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(TerrainGen.WORLD_X, TerrainGen.WORLD_Z)
	pm.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = Vector3(TerrainGen.WORLD_X * 0.5, LAKE_Y, TerrainGen.WORLD_Z * 0.5)
	add_child(mi)

func _mtn_mask(z: float) -> float:
	return 1.0 - TerrainGen.smoothstep(TerrainGen.MTN_HALF * 0.55, TerrainGen.MTN_HALF, absf(z - TerrainGen.MTN_CENTER))

func _build_river() -> void:
	var step := 20.0
	var n := int(TerrainGen.WORLD_Z / step) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * 2)
	norms.resize(n * 2)
	for j in range(n):
		var z := clampf(j * step, 0.0, TerrainGen.WORLD_Z)
		var x := data.river_x(z)
		var wl := data.river_wl(z)
		var g := _mtn_mask(z)
		var half_w := lerpf(55.0, 45.0, g)
		# widen slightly where the valley is wide (plains) so banks meet water
		verts[j * 2] = Vector3(x - half_w, wl + 0.5, z)
		verts[j * 2 + 1] = Vector3(x + half_w, wl + 0.5, z)
		norms[j * 2] = Vector3.UP
		norms[j * 2 + 1] = Vector3.UP
	var idxs := PackedInt32Array()
	idxs.resize((n - 1) * 6)
	var p := 0
	for j in range(n - 1):
		var a := j * 2
		var b := a + 1
		var c := a + 2
		var d2 := a + 3
		idxs[p] = a; idxs[p + 1] = b; idxs[p + 2] = c
		idxs[p + 3] = b; idxs[p + 4] = d2; idxs[p + 5] = c
		p += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
