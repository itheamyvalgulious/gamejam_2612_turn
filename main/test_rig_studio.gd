extends SceneTree
## Studio render of the campaign rig at the in-game unit scale, for visual
## comparison of the hair fix.  Usage:
##   DISPLAY=:10 godot --path main -s test_rig_studio.gd -- --out /tmp/opencode/turn_hair

const Rig = preload("res://runtime/characters/vesper/design/integration/campaign_rig.gd")
const UNIT := 1.0 / 0.547


func _init() -> void:
	var out_dir := "/tmp/opencode/turn_hair"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var world := Node3D.new()
	root.add_child(world)

	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.34, 0.37, 0.42)
	sky_mat.sky_horizon_color = Color(0.58, 0.60, 0.65)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.24, 0.25, 0.27)
	floor.material_override = fm
	world.add_child(floor)

	var rig := Rig.new()
	rig.auto_step = false
	rig.set_process(false)
	rig.scale = Vector3.ONE * UNIT
	world.add_child(rig)

	var key := DirectionalLight3D.new()
	key.light_energy = 2.0
	key.shadow_enabled = true
	world.add_child(key)
	key.look_at_from_position(Vector3(-9, 16, -13), Vector3(0, 3, 0), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.74, 1.0)
	fill.light_energy = 0.8
	world.add_child(fill)
	fill.look_at_from_position(Vector3(13, 7, 2), Vector3(0, 2.5, 0), Vector3.UP)

	var cam := Camera3D.new()
	cam.fov = 38.0
	world.add_child(cam)

	await process_frame
	for i in 90:
		rig.advance(1.0 / 60.0)
		await process_frame

	var head_y: float = rig.head.global_position.y
	var shots := [
		{"name": "back", "pos": Vector3(-4.6, head_y + 2.2, 8.6), "look": Vector3(0, head_y - 0.4, 0)},
		{"name": "front3q", "pos": Vector3(5.4, head_y + 1.8, -8.0), "look": Vector3(0, head_y - 0.4, 0)},
	]
	for shot in shots:
		cam.position = shot["pos"]
		cam.look_at(shot["look"], Vector3.UP)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out_dir.path_join(shot["name"] + ".png"))
	print("RENDERED -> ", out_dir)
	quit()
