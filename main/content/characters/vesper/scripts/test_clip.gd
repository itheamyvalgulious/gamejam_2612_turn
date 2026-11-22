extends Node3D

## Clipping / range QA.  Renders attack keys from front and side at high res so
## hilt/torso intersections and arm range can be inspected visually.

const RenderPath = preload("res://scripts/render_path.gd")
const Rig = preload("res://scripts/mech/mech_rig.gd")
const MAT = preload("res://scripts/mech/materials.gd")
var rig
var cam

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.28, 0.31, 0.36)
	sm.sky_horizon_color = Color(0.55, 0.58, 0.63)
	sm.ground_horizon_color = Color(0.30, 0.32, 0.35)
	sm.ground_bottom_color = Color(0.16, 0.17, 0.19)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.22, 0.23, 0.25)
	fm.roughness = 0.7
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	fl.mesh = pm
	fl.material_override = fm
	add_child(fl)
	(MAT.blade_core() as ShaderMaterial).set_shader_parameter("energy", 1.2)
	(MAT.blade_glow() as ShaderMaterial).set_shader_parameter("strength", 0.35)
	rig = Rig.new()
	add_child(rig)
	rig.auto_step = false
	rig.set_process(false)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.2
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 40.0
	add_child(key)
	key.look_at_from_position(Vector3(-5, 9, -7), Vector3(0, 1.7, 0), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.74, 1.0)
	fill.light_energy = 0.9
	add_child(fill)
	fill.look_at_from_position(Vector3(7, 4, 1), Vector3(0, 1.4, 0), Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.85, 0.7)
	rim.light_energy = 1.2
	add_child(rim)
	rim.look_at_from_position(Vector3(1, 5, 8), Vector3(0, 1.6, 0), Vector3.UP)
	cam = Camera3D.new()
	cam.fov = 36.0
	add_child(cam)
	await get_tree().process_frame
	await get_tree().process_frame

	await _shot("idle_front", 0.4, Vector3(3.4, 1.9, -5.2), 1.35)
	await _shot("idle_side", 0.0, Vector3(4.8, 1.95, -1.2), 1.25)
	rig.request_light_attack()
	await _shot("rift_windup", 0.20, Vector3(4.2, 1.95, -2.7), 1.30)
	await _shot("rift_strike", 0.16, Vector3(4.2, 1.95, -2.7), 1.30)
	await _shot("rift_follow", 0.20, Vector3(4.2, 1.95, -2.7), 1.30)
	await _step(0.5)
	rig.reset_demo(Vector3.ZERO, 0.0)
	rig.request_heavy_attack()
	await _shot("heavy_raise", 0.50, Vector3(4.2, 1.95, -2.7), 1.40)
	await _shot("heavy_slam", 0.13, Vector3(4.2, 1.95, -2.7), 1.10)
	await _step(1.0)
	rig.reset_demo(Vector3.ZERO, 0.0)
	rig.request_spin_attack()
	await _shot("spin", 0.60, Vector3(4.8, 1.9, -1.6), 1.30)
	await _step(1.2)
	rig.reset_demo(Vector3.ZERO, 0.0)
	rig.request_jump()
	await _shot("air", 0.55, Vector3(4.2, 1.9, -2.7), 1.55)
	await _shot("land", 0.45, Vector3(4.2, 1.9, -2.7), 1.00)
	print("CLIP QA DONE")
	get_tree().quit()


func _step(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		rig.advance(1.0 / 60.0)
		t += 1.0 / 60.0


func _shot(name: String, advance: float, offset: Vector3, look_h: float) -> void:
	if advance > 0.0:
		await _step(advance)
	cam.position = rig.position + offset
	cam.look_at(rig.position + Vector3(0, look_h, 0))
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(RenderPath.file("clip_%s.png" % name))
	print("CLIP ", name)