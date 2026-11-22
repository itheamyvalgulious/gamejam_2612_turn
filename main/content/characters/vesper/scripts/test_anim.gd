extends Node3D

## Animation QA harness: renders key poses and measures the two-hand grip error.

const RenderPath = preload("res://scripts/render_path.gd")
const Rig = preload("res://scripts/mech/mech_rig.gd")
const MAT = preload("res://scripts/mech/materials.gd")
var rig
var cam
var shots := 0

func _ready() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.17, 0.19, 0.23)
	sm.sky_horizon_color = Color(0.34, 0.36, 0.40)
	sm.ground_horizon_color = Color(0.16, 0.17, 0.19)
	sm.ground_bottom_color = Color(0.08, 0.09, 0.10)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.20, 0.21, 0.23)
	fm.roughness = 0.65
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	fl.mesh = pm
	fl.material_override = fm
	add_child(fl)
	(MAT.blade_core() as ShaderMaterial).set_shader_parameter("energy", 1.6)
	(MAT.blade_glow() as ShaderMaterial).set_shader_parameter("strength", 0.35)
	rig = Rig.new()
	add_child(rig)
	var key := DirectionalLight3D.new()
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
	rim.light_energy = 1.4
	add_child(rim)
	rim.look_at_from_position(Vector3(1, 5, 8), Vector3(0, 1.6, 0), Vector3.UP)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	rig.auto_step = false
	rig.set_process(false)
	for i in 4:
		rig.advance(1.0 / 60.0)
	await get_tree().process_frame

	await shot("anim_idle", 0.8)
	# walk / run: drive the rig, then snap it back to origin for framing
	rig.move_command = Vector3(0, 0, -3.0)
	await sim(1.2)
	await shot("anim_walk", 0.0, true)
	rig.move_command = Vector3(0, 0, -8.4)
	await sim(1.4)
	await shot("anim_run", 0.0, true)
	rig.move_command = Vector3.ZERO
	await sim(0.6)

	# light attack: windup / strike / follow-through
	rig.request_light_attack()
	await sim(0.22)
	await shot("atk_light_windup", 0.02)
	await sim(0.14)
	await shot("atk_light_hit", 0.02)
	await sim(0.20)
	await shot("atk_light_follow", 0.02)
	await sim(0.6)

	# heavy: overhead apex / impact
	rig.request_heavy_attack()
	await sim(0.44)
	await shot("atk_heavy_apex", 0.02)
	await sim(0.20)
	await shot("atk_heavy_impact", 0.02)
	await sim(1.0)

	# spin: mid rotation
	rig.request_spin_attack()
	await sim(0.55)
	await shot("atk_spin_mid", 0.02)
	await sim(1.2)

	print("ANIM QA DONE shots=%d grip_error=%.4f" % [shots, _grip_error()])
	get_tree().quit()


func sim(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		rig.advance(1.0 / 60.0)
		t += 1.0 / 60.0
	# allow the trail/particles one frame
	await get_tree().process_frame


func shot(name: String, after: float, face_origin := false) -> void:
	if after > 0.0:
		await sim(after)
	if face_origin:
		rig.position = Vector3.ZERO
		rig.heading = 0.0
		rig.rotation.y = 0.0
		rig.move_command = Vector3.ZERO
	var origin: Vector3 = rig.global_position
	var yaw: float = rig.rotation.y
	var off := Vector3(3.3, 1.65, -4.8).rotated(Vector3.UP, yaw)
	cam.position = origin + off
	cam.look_at(origin + Vector3(0, 1.10, 0))
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(RenderPath.file("%s.png" % name))
	shots += 1
	print("%s  grip=%.4f  dist=%.2f" % [name, _grip_error(), rig.global_position.length()])


func _grip_error() -> float:
	var err := 0.0
	for i in 2:
		var signv := 1.0 if i == 0 else -1.0
		var local_grip = rig.weapon_root.transform * Vector3(0, 0.10 * signv, 0)
		var target: Vector3 = rig.torso.global_transform * local_grip
		var wrist: Node3D = rig.arms[i]["wrist"]
		err = maxf(err, target.distance_to(wrist.global_position))
	return err