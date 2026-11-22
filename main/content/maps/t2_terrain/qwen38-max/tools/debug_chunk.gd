extends SceneTree
const TG := preload("res://scripts/terrain_gen.gd")
const TL := preload("res://scripts/terrain_lod.gd")

func _init() -> void:
	var d := TG.new()
	d.generate()
	var node := TL.new()
	# reach into private builder via a temporary root
	var root := Node3D.new()
	root.add_child(node)
	# build via public path: setup then force update at a point, then inspect a chunk mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	node.setup(d, mat)
	node.update(Vector3(2000, 100, 2000), true)   # center -> that chunk LOD0, far chunks LOD3
	# inspect chunk at camera (LOD0) and a far chunk (LOD3)
	for cname in ["chunk_8_8", "chunk_0_0"]:
		var mi := node.get_node(cname) as MeshInstance3D
		var m := mi.mesh as ArrayMesh
		if m == null:
			print(cname, ": NO MESH")
			continue
		var arrs: Array = m.surface_get_arrays(0)
		var va := arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var ia := arrs[Mesh.ARRAY_INDEX] as PackedInt32Array
		var na := arrs[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var ca := arrs[Mesh.ARRAY_COLOR] as PackedColorArray
		var nverts: int = va.size()
		var nidx: int = ia.size()
		var nnorm: int = na.size()
		var ncol: int = ca.size()
		print(cname, " verts=", nverts, " idx=", nidx, " norm=", nnorm, " col=", ncol, " aabb=", m.get_aabb())
		var nan := 0
		var miny := 1e9
		var maxy := -1e9
		for v in va:
			if not is_finite(v.y):
				nan += 1
			miny = minf(miny, v.y)
			maxy = maxf(maxy, v.y)
		var maxidx := 0
		for i2 in ia:
			maxidx = maxi(maxidx, i2)
		print("   y[", miny, ",", maxy, "] nan=", nan, " maxidx=", maxidx, " (verts=", nverts, ")")
	quit()
