extends SceneTree
const Veg := preload("res://scripts/vegetation.gd")

func _init() -> void:
	# build a rock mesh via a throwaway Vegetation-less path: replicate _make_rock
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	# sphere grid
	var seg := 12
	var rings := 8
	var r := Vector3(2.2, 1.36, 2.4)
	var grid: Array = []
	for iy in range(rings + 1):
		var phi := float(iy) / rings * PI
		var row: Array = []
		for ix in range(seg):
			var theta := float(ix) / seg * TAU
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var extra: float = rng.randf_range(-1, 1) * 0.55
			row.push_back(Vector3(dir.x * r.x, dir.y * r.y, dir.z * r.z) * (1.0 + extra))
		grid.push_back(row)
	for iy in range(rings):
		for ix in range(seg):
			var jx := (ix + 1) % seg
			var a: Vector3 = grid[iy][ix]
			var b: Vector3 = grid[iy][jx]
			var c: Vector3 = grid[iy + 1][ix]
			var d: Vector3 = grid[iy + 1][jx]
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
			st.add_vertex(b); st.add_vertex(c); st.add_vertex(d)
	st.generate_normals()
	var m := st.commit()
	var aabb := m.get_aabb()
	var arrs: Array = m.surface_get_arrays(0)
	print("rock aabb=", aabb, " verts=", (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	# render
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rock.gdshader")
	m.surface_set_material(0, mat)
	root.add_child(mi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -62, 0)
	root.add_child(sun)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.3, 0.4)
	we.environment = e
	root.add_child(we)
	# viewport capture
	var sv := SubViewport.new()
	sv.size = Vector2i(800, 600)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(sv)
	sv.add_child(root)
	var cam := Camera3D.new()
	cam.position = Vector3(6, 4, 6)
	sv.add_child(cam)
	cam.look_at_from_position(Vector3(6, 4, 6), Vector3.ZERO, Vector3.UP)
	# need a few frames
	for i in range(6):
		await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://screenshots/_rocktest.png"))
	print("rocktest saved")
	quit()
