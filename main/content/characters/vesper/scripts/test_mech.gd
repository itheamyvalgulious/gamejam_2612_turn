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
	sky_mat.sky_top_color = Color(0.012, 0.018, 0.030)
	sky_mat.sky_horizon_color = Color(0.065, 0.078, 0.100)
	sky_mat.ground_horizon_color = Color(0.030, 0.036, 0.048)
	sky_mat.ground_bottom_color = Color(0.005, 0.006, 0.009)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.065, 0.09)
	env.fog_light_energy = 0.4
	env.fog_density = 0.008
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var floor_mat: ShaderMaterial = MAT.floor()
	floor_mat.set_shader_parameter("line_color", Color(0.38, 0.60, 1.0))
	floor_mat.set_shader_parameter("grid_glow", 0.22)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(90, 90)
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.material_override = floor_mat
	add_child(floor)

	(MAT.blade_core() as ShaderMaterial).set_shader_parameter("energy", 1.6)
	(MAT.blade_glow() as ShaderMaterial).set_shader_parameter("strength", 0.55)

	rig = Rig.new()
	add_child(rig)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.90, 0.82)
	key.light_energy = 3.0
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 40.0
	add_child(key)
	key.look_at_from_position(Vector3(-5, 9, -8), Vector3(0, 1.7, 0), Vector3.UP)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.35, 0.58, 1.0)
	fill.light_energy = 1.1
	add_child(fill)
	fill.look_at_from_position(Vector3(8, 4, -2), Vector3(0, 1.4, 0), Vector3.UP)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.62, 0.38)
	rim.light_energy = 2.0
	add_child(rim)
	rim.look_at_from_position(Vector3(2, 6, 9), Vector3(0, 1.6, 0), Vector3.UP)

	cam = Camera3D.new()
	cam.fov = 42.0
	add_child(cam)

	for i in 6:
		rig.advance(1.0 / 60.0)

	var shots := [
		{"name": "front34", "pos": Vector3(4.3, 2.9, -6.0), "look": Vector3(0, 2.1, 0)},
		{"name": "side", "pos": Vector3(6.8, 2.8, 0.2), "look": Vector3(0, 2.0, 0)},
		{"name": "back34", "pos": Vector3(-4.4, 3.1, 6.0), "look": Vector3(0, 2.1, 0)},
		{"name": "front", "pos": Vector3(0.2, 2.7, -7.0), "look": Vector3(0, 2.1, 0)},
	]
	for shot in shots:
		cam.position = shot["pos"]
		cam.look_at(shot["look"])
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(RenderPath.file("check_%s.png" % shot["name"]))
	print("RENDERED")
	get_tree().quit()