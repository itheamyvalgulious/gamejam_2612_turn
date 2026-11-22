extends Node3D
## Automated screenshot runner: builds the city then tours a camera list,
## saving PNGs to res://shots/. Run: DISPLAY=:0 godot --path . res://scenes/shots.tscn -- --seed=7

var _cam: Camera3D
var _sv: SubViewport

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			out["seed"] = int(a.trim_prefix("--seed="))
		elif a.begins_with("--focus="):
			var parts := a.trim_prefix("--focus=").split(",")
			if parts.size() == 2:
				out["focus"] = Vector3(float(parts[0]), 0, float(parts[1]))
		elif a.begins_with("--only="):
			out["only"] = a.trim_prefix("--only=").split(",")
		elif a == "--day":
			out["day"] = true
		elif a == "--nofog":
			out["nofog"] = true
		elif a == "--noglow":
			out["noglow"] = true
		elif a == "--nomsaa":
			out["nomsaa"] = true
	return out

func _ready() -> void:
	var args := _parse_args()
	var t0 := Time.get_ticks_msec()
	var gen := CityGen.new()
	gen.params = args
	gen.build(self)
	print("[shots] city built in %.1fs buildings=%d tris=%d" % [
		(Time.get_ticks_msec() - t0) / 1000.0, gen.stat_buildings, gen.stat_tris])

	_sv = SubViewport.new()
	_sv.size = Vector2i(1920, 1080)
	_sv.msaa_3d = Viewport.MSAA_DISABLED if args.has("nomsaa") else Viewport.MSAA_4X
	_sv.disable_3d = false
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	_cam = Camera3D.new()
	_cam.far = 16000.0
	_cam.fov = 60.0
	_sv.add_child(_cam)
	_cam.current = true
	if args.has("noglow"):
		for c in get_children():
			if c is WorldEnvironment:
				c.environment.glow_enabled = false
	if args.has("nofog"):
		for c in get_children():
			if c is WorldEnvironment:
				c.environment.fog_enabled = false
	if args.has("day"):
		for c in get_children():
			if c is DirectionalLight3D:
				c.light_energy = 4.0
				c.light_color = Color(1, 1, 1)
			if c is WorldEnvironment:
				c.environment.fog_enabled = false
				c.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
				c.environment.ambient_light_energy = 1.0

	var only: Array = args.get("only", [])
	var shots: Array = _shot_list()
	for s in shots:
		if only.size() > 0 and not only.has(s.name):
			continue
		_cam.fov = s.get("fov", 60.0)
		_cam.position = s.pos
		_cam.look_at(s.target, Vector3.UP)
		var wait := int(s.get("frames", 14))
		for k in wait:
			await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := _sv.get_texture().get_image()
		var path := "res://shots/%s.png" % s.name
		img.save_png(path)
		print("[shots] saved ", path)
	print("[shots] done")
	get_tree().quit()

func _shot_list() -> Array:
	return [
		{"name": "a01_skyline_high", "pos": Vector3(-1500, 1500, 2300), "target": Vector3(0, 150, 0), "fov": 55},
		{"name": "a02_downtown_oblique", "pos": Vector3(-750, 520, 1150), "target": Vector3(0, 160, -100), "fov": 58},
		{"name": "a03_street_canyon", "pos": Vector3(14, 9, 380), "target": Vector3(0, 55, -250), "fov": 70},
		{"name": "a04_city_edge", "pos": Vector3(1500, 260, 1900), "target": Vector3(-300, 120, -400), "fov": 55},
		{"name": "a05_river_bridges", "pos": Vector3(350, 240, 2150), "target": Vector3(0, 30, 850), "fov": 58},
		{"name": "a06_elevated", "pos": Vector3(-900, 90, 350), "target": Vector3(400, 40, 0), "fov": 65},
		{"name": "a07_glass_interior", "pos": Vector3(320, 70, 240), "target": Vector3(60, 80, -80), "fov": 58},
		{"name": "a08_harbor_ferris", "pos": Vector3(900, 120, 1500), "target": Vector3(1250, 45, 700), "fov": 60},
		{"name": "a09_topdown", "pos": Vector3(0, 2600, 40), "target": Vector3(0, 0, 20), "fov": 60},
		{"name": "a10_school_park", "pos": Vector3(300, 60, 780), "target": Vector3(480, 20, 620), "fov": 62},
	]
