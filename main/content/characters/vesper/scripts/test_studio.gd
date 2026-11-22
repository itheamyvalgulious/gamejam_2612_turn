extends Node3D

const RenderPath = preload("res://scripts/render_path.gd")

const Rig = preload("res://scripts/mech/mech_rig.gd")
const MAT = preload("res://scripts/mech/materials.gd")

var rig
var cam: Camera3D


func _ready() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.34, 0.37, 0.42)
	sky_mat.sky_horizon_color = Color(0.58, 0.60, 0.65)
	sky_mat.ground_horizon_color = Color(0.30, 0.32, 0.35)
	sky_mat.ground_bottom_color = Color(0.18, 0.19, 0.21)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.24, 0.25, 0.27)
	floor_mat.metallic = 0.1
	floor_mat.roughness = 0.62
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(90, 90)
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.material_override = floor_mat
	add_child(floor)

	(MAT.blade_core() as ShaderMaterial).set_shader_parameter("energy", 1.3)
	(MAT.blade_glow() as ShaderMaterial).set_shader_parameter("strength", 0.35)
	rig = Rig.new()
	add_child(rig)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.96, 0.90)
	key.light_energy = 2.0
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 40.0
	add_child(key)
	key.look_at_from_position(Vector3(-5, 9, -7), Vector3(0, 1.7, 0), Vector3.UP)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.74, 1.0)
	fill.light_energy = 0.8
	add_child(fill)
	fill.look_at_from_position(Vector3(7, 4, 1), Vector3(0, 1.4, 0), Vector3.UP)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.85, 0.7)
	rim.light_energy = 1.3
	add_child(rim)
	rim.look_at_from_position(Vector3(1, 5, 8), Vector3(0, 1.6, 0), Vector3.UP)

	cam = Camera3D.new()
	cam.fov = 38.0
	add_child(cam)

	for i in 6:
		rig.advance(1.0 / 60.0)

	var shots := [
		{"name": "studio_front", "pos": Vector3(5.4, 3.2, -7.6), "look": Vector3(0, 2.15, 0)},
		{"name": "studio_side", "pos": Vector3(8.2, 3.0, 0.0), "look": Vector3(0, 2.0, 0)},
		{"name": "studio_back", "pos": Vector3(-5.0, 3.4, 7.4), "look": Vector3(0, 2.15, 0)},
		{"name": "studio_low", "pos": Vector3(4.4, 1.4, -7.0), "look": Vector3(0, 2.3, 0)},
	]
	for shot in shots:
		cam.position = shot["pos"]
		cam.look_at(shot["look"])
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(RenderPath.file("%s.png" % shot["name"]))
	print("RENDERED")
	get_tree().quit()