extends Node3D

func _quad(arr_mode: int) -> ArrayMesh:
	var V := PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 6, 0), Vector3(0, 6, 0)])
	var N := PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	var I := PackedInt32Array([0, 2, 1, 0, 3, 2])
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	if arr_mode >= 1:
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	if arr_mode >= 2:
		arr[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	if arr_mode >= 3:
		arr[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = I
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

func _ready() -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/_test.gdshader")
	for k in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = _quad(k)
		mi.material_override = m
		mi.position = Vector3(-9.0 + float(k) * 6.0, 2, 0)
		add_child(mi)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	we.environment = env
	add_child(we)
	var l := DirectionalLight3D.new()
	l.light_energy = 2.0
	l.rotation_degrees = Vector3(-42, 28, 0)
	add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 5, 24)
	cam.look_at(Vector3(0, 5, 0), Vector3.UP)
	for k in 8:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/_dbg2.png")
	for k in 4:
		print("[dbg] mode", k, " px=", img.get_pixel(int(640 + (-9.0 + float(k) * 6.0) * 26.6), 323))
	get_tree().quit()
