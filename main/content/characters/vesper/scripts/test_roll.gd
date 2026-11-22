extends Node3D

const RenderPath = preload("res://scripts/render_path.gd")
const Rig = preload("res://scripts/mech/mech_rig.gd")
const MAT = preload("res://scripts/mech/materials.gd")
var rig
var cam
func _ready() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.30, 0.33, 0.38)
	sm.sky_horizon_color = Color(0.56, 0.58, 0.63)
	sm.ground_horizon_color = Color(0.30, 0.32, 0.35)
	sm.ground_bottom_color = Color(0.18, 0.19, 0.21)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.24, 0.25, 0.27)
	fm.roughness = 0.65
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	fl.mesh = pm
	fl.material_override = fm
	add_child(fl)
	(MAT.blade_core() as ShaderMaterial).set_shader_parameter("energy", 1.8)
	(MAT.blade_glow() as ShaderMaterial).set_shader_parameter("strength", 0.4)
	rig = Rig.new()
	add_child(rig)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.1
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
	cam.fov = 36.0
	cam.position = Vector3(4.6, 3.4, -6.4)
	add_child(cam)
	cam.look_at(Vector3(0, 3.0, 0))
	rig.auto_step = false
	rig.set_process(false)
	for i in 6:
		rig.advance(1.0 / 60.0)
	for v in [0.0, 0.8, 1.6, 2.4, 3.1]:
		rig.weapon_spin.rotation.y = v
		for i in 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(RenderPath.file("roll_%s.png" % str(v)))
	print("ROLL DONE")
	get_tree().quit()
