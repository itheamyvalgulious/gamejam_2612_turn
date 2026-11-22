extends Node3D
## V2 detail gallery: close-up visual acceptance renders.
##   DISPLAY=:10 godot --path . res://scenes/v2_details.tscn
## Writes renders/v2/detail_*.png

const RenderPath = preload("res://scripts/render_path.gd")
const Rig = preload("res://scripts/mech/mech_rig.gd")

var rig
var cam
var out_dir: String


func _ready() -> void:
	out_dir = RenderPath.dir().path_join("v2")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1600, 900)

	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.26, 0.34)
	sm.sky_horizon_color = Color(0.48, 0.54, 0.68)
	sm.ground_horizon_color = Color(0.20, 0.23, 0.30)
	sm.ground_bottom_color = Color(0.08, 0.09, 0.12)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.90
	env.glow_enabled = true
	env.glow_intensity = 0.34
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 2.10
	env.glow_strength = 0.90
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.10, 0.12, 0.16)
	fm.metallic = 0.2
	fm.roughness = 0.55
	floor_mesh.material_override = fm
	add_child(floor_mesh)

	rig = Rig.new()
	rig.auto_step = false
	rig.set_process(false)
	add_child(rig)

	var key := DirectionalLight3D.new()
	key.light_color = Color(0.88, 0.94, 1.0)
	key.light_energy = 2.4
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 20.0
	add_child(key)
	key.look_at_from_position(Vector3(-4, 6, -5), Vector3(0, 1.1, 0), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.78, 0.86, 1.0)
	fill.light_energy = 1.05
	add_child(fill)
	fill.look_at_from_position(Vector3(5, 3, 2), Vector3(0, 1.2, 0), Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.80, 0.89, 1.0)
	rim.light_energy = 1.55
	add_child(rim)
	rim.look_at_from_position(Vector3(0, 3, 6), Vector3(0, 1.4, 0), Vector3.UP)

	cam = Camera3D.new()
	cam.fov = 34.0
	add_child(cam)
	for i in 120:
		rig.advance(1.0 / 60.0)
	await get_tree().process_frame

	await _shot("full_front", Vector3(2.8, 1.55, -4.6), Vector3(0, 1.05, 0), 38.0)
	await _shot("full_side", Vector3(4.8, 1.65, 0.3), Vector3(0, 1.05, 0), 38.0)
	await _shot("legs_pelvis", Vector3(1.65, 0.72, -1.75), Vector3(0.0, 0.56, 0.0), 36.0)
	await _shot("head", Vector3(0.52, 2.02, -0.78), Vector3(0, 1.94, -0.02), 30.0)
	await _shot("head_side", Vector3(0.86, 1.96, 0.14), Vector3(0, 1.88, 0.03), 30.0)
	await _shot("head_left", Vector3(-0.56, 2.02, -0.75), Vector3(0, 1.94, -0.02), 30.0)
	await _shot("chest", Vector3(0.85, 1.70, -1.25), Vector3(0, 1.55, -0.04), 33.0)
	await _shot("sword_hilt", Vector3(1.10, 1.45, -0.95), Vector3(0, 1.32, -0.20), 34.0)
	await _shot("back_thruster", Vector3(0.0, 1.80, 1.55), Vector3(0, 1.48, 0.02), 34.0)
	await _shot("hair_back", Vector3(0.72, 2.02, 0.86), Vector3(0, 1.80, 0.04), 32.0)

	# action beats
	rig.reset_demo(Vector3.ZERO, 0.0)
	rig.request_side_attack(1.0)
	await _advance_attack(0.36)
	await _shot("side_thrust", Vector3(0.6, 1.75, -4.2), Vector3(0, 1.2, 0.1), 40.0)
	rig.reset_demo(Vector3.ZERO, 0.0)
	rig.request_back_attack()
	await _advance_attack(0.40)
	await _shot("back_thrust", Vector3(3.8, 1.7, 0.8), Vector3(0, 1.2, 0.35), 40.0)
	rig.reset_demo(Vector3.ZERO, 0.0)
	rig.request_heavy_attack()
	await _advance_attack(0.58)
	await _shot("heavy_hit", Vector3(2.8, 1.65, -3.8), Vector3(0, 1.0, 0), 40.0)
	rig.reset_demo(Vector3.ZERO, 0.0)
	rig.request_spin_attack()
	await _advance_attack(0.70)
	await _shot("spin", Vector3(0.0, 1.7, -4.6), Vector3(0, 1.15, 0), 44.0)
	rig.reset_demo(Vector3.ZERO, 0.0)
	rig.request_jump()
	for i in 8:
		rig.advance(1.0 / 60.0)
	await _shot("jump_crouch", Vector3(2.8, 1.55, -3.8), Vector3(0, 0.95, 0), 38.0)
	for i in 24:
		rig.advance(1.0 / 60.0)
	await _shot("airborne", Vector3(2.8, 2.4, -4.2), Vector3(0, 1.6, 0), 40.0)

	# back dash (dual thrusters swiveled forward — 3/4 side view clearly showing pods & forward jets)
	rig.reset_demo(Vector3.ZERO, 0.0)
	for i in 12:
		rig.advance(1.0 / 60.0)
	rig.request_dash(Vector3(0, 0, 1))
	for i in 11:
		rig.advance(1.0 / 60.0)
	await _shot("dash_back", Vector3(2.35, 1.50, -0.75), Vector3(rig.global_position.x, 1.25, rig.global_position.z), 35.0)

	# brisk locomotion hair drape (verify zero scalp exposure & flowing ends)
	rig.reset_demo(Vector3.ZERO, 0.0)
	rig.move_command = Vector3(0, 0, -6.5)
	for i in 45:
		if i == 25:
			rig.heading += 0.65
			rig.rotation.y = rig.heading
		rig.advance(1.0 / 60.0)
		await get_tree().process_frame
	var hp: Vector3 = rig.head.global_position
	await _shot("hair_move", hp + Vector3(0.75, 0.15, 0.72), hp + Vector3(0, -0.10, 0), 34.0)

	print("V2 DETAILS DONE -> ", out_dir)
	get_tree().quit()


func _advance_attack(t: float) -> void:
	var guard := 0
	while rig.is_attacking and rig.attack_time < t and guard < 240:
		rig.advance(1.0 / 60.0)
		guard += 1
	await get_tree().process_frame
	await get_tree().process_frame


func _shot(shot_name: String, pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.fov = fov
	cam.look_at(look, Vector3.UP)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("detail_%s.png" % shot_name))
	print("DETAIL ", shot_name)