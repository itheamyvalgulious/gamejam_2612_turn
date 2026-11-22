extends Node3D
const Rig = preload("res://scripts/mech/mech_rig.gd")
var rig
var cam
func _ready() -> void:
	get_window().size = Vector2i(1280, 800)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22,0.26,0.34)
	sm.sky_horizon_color = Color(0.48,0.54,0.68)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var fm := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(30,30); fm.mesh = pm
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.10,0.12,0.16); mat.roughness=0.6
	fm.material_override = mat; add_child(fm)
	rig = Rig.new(); rig.auto_step = false; rig.set_process(false); add_child(rig)
	var key := DirectionalLight3D.new(); key.light_energy = 2.4; key.shadow_enabled = true
	add_child(key); key.look_at_from_position(Vector3(-4,6,-5), Vector3(0,1.1,0), Vector3.UP)
	var fill := DirectionalLight3D.new(); fill.light_energy = 1.0; fill.light_color = Color(0.4,0.62,1.0)
	add_child(fill); fill.look_at_from_position(Vector3(5,3,2), Vector3(0,1.2,0), Vector3.UP)
	cam = Camera3D.new(); cam.fov = 40.0; add_child(cam)
	var clip := int(OS.get_environment("CLIP")) if OS.get_environment("CLIP") != "" else 1
	var at := float(OS.get_environment("AT")) if OS.get_environment("AT") != "" else 0.52
	rig.reset_demo(Vector3.ZERO, 0.0)
	match clip:
		0: pass
		1: rig.request_front_attack(1)
		2: rig.request_front_attack(2)
		3: rig.request_side_attack(1.0)
		4: rig.request_side_attack(-1.0)
		5: rig.request_back_attack()
		6: rig.request_heavy_attack()
		7: rig.request_spin_attack()
	var guard := 0
	while rig.is_attacking and rig.attack_time < at and guard < 400:
		rig.advance(1.0/120.0); guard += 1
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shots := [["front", Vector3(1.6,1.55,-3.4)],["left", Vector3(-3.0,1.7,-2.2)],["right", Vector3(3.2,1.6,-1.2)],["top", Vector3(0.4,3.2,-2.6)],["head", Vector3(0.9,1.95,-1.25)],["headside", Vector3(1.5,1.9,0.4)]]
	for sh in shots:
		cam.position = sh[1]
		cam.look_at(Vector3(0,1.75,-0.05) if sh[0].begins_with("head") else Vector3(0,1.35,-0.2), Vector3.UP)
		for i in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://renders/tmp/c%d_%.2f_%s.png" % [clip, at, sh[0]])
	print("SHOT DONE")
	get_tree().quit()
