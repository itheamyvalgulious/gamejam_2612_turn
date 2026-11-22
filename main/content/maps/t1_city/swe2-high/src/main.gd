extends Node3D

## NEON REACH — pure-procedural cyberpunk city, 4 km × 2.5 km.
## CLI:  godot --path . -- --shot=<name|all>   writes PNGs to shots/ and exits.

const CityLayout = preload("res://src/city.gd")
const GroundPlan = preload("res://src/ground.gd")

var city: RefCounted
var hf: RefCounted
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var shot_mode := false
var shot_names: Array = []
var _intr: Node3D


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	city = CityLayout.new(7311)
	city.build()
	hf = GroundPlan.new()
	hf.setup(city.river_pts, 7311)
	_build_env()

	var strts: Node3D = load("res://src/streets.gd").new()
	strts.name = "Streets"
	add_child(strts)
	strts.build(city, hf)

	var bld: Node3D = load("res://src/buildings.gd").new()
	bld.name = "Buildings"
	add_child(bld)
	bld.build(city, hf.h)

	var lm: Node3D = load("res://src/landmarks.gd").new()
	lm.name = "Landmarks"
	add_child(lm)
	lm.build(city, hf)

	var intr: Node3D = load("res://src/interior.gd").new()
	intr.name = "Interior"
	add_child(intr)
	intr.build(hf)
	_intr = intr

	var sl: Node3D = load("res://src/streetlife.gd").new()
	sl.name = "Streetlife"
	add_child(sl)
	sl.build(city, hf)

	print("CITY BUILT: %d ms  lots=%d blocks=%d" %
		[Time.get_ticks_msec() - t0, city.lots.size(), city.blocks.size()])

	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 58.0
	cam.near = 0.2
	cam.far = 9000.0
	add_child(cam)
	cam.current = true

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot="):
			shot_mode = true
			var v := a.substr(7)
			shot_names = presets().keys() if v == "all" else v.split(",")
	if "--noshadow" in args:
		sun.shadow_enabled = false
	if "--white" in args:
		# white-room diagnostic: flat sky, neutral sun, no glow/fog —
		# whatever survives is pure albedo + geometry
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.55, 0.58, 0.65)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1, 1, 1)
		env.ambient_light_energy = 0.8
		env.tonemap_exposure = 1.0
		env.glow_enabled = false
		env.fog_enabled = false
		sun.light_color = Color(1, 1, 1)
		sun.light_energy = 1.3
		sun.look_at_from_position(Vector3.ZERO,
			-Vector3(0.5, 0.8, -0.4).normalized(), Vector3.UP)
	if shot_mode:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		await _run_shots()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _build_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	# night sky: gradient dome — deep indigo overhead falling to a warm
	# sodium city-glow at the horizon, not a flat black wall
	var sky := Sky.new()
	var skym := ProceduralSkyMaterial.new()
	skym.sky_top_color = Color(0.008, 0.012, 0.035)
	skym.sky_horizon_color = Color(0.16, 0.10, 0.07)
	skym.ground_bottom_color = Color(0.01, 0.008, 0.015)
	skym.ground_horizon_color = Color(0.16, 0.10, 0.07)
	skym.sky_curve = 0.10
	skym.ground_curve = 0.08
	sky.sky_material = skym
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.40, 0.52)
	env.ambient_light_energy = 0.78
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.45
	env.glow_enabled = true
	env.glow_intensity = 0.30
	env.glow_strength = 0.75
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	# warm distance fog — far towers sink into the city's light haze
	# instead of clipping into black
	env.fog_light_color = Color(0.16, 0.12, 0.09)
	env.fog_light_energy = 0.55
	env.fog_density = 0.00014
	# height fog off — its per-pixel density integration was the source
	# of the speckled grain on every surface
	env.fog_height = 0.0
	env.fog_height_density = 0.0
	env.ssao_enabled = false
	we.environment = env
	add_child(we)

	# weak moonlight — neon is the real key
	sun = DirectionalLight3D.new()
	sun.light_color = Color(0.70, 0.74, 0.95)
	sun.light_energy = 2.6
	sun.shadow_enabled = "--noshadow" not in OS.get_cmdline_user_args()
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 2500.0
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO,
		Vector3(0.4, -0.6, -0.3).normalized(), Vector3.UP)
	# cool fill from the opposite quadrant so the moonlit and shaded
	# faces separate — buildings keep volume instead of reading flat
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.35, 0.45, 0.75)
	fill.light_energy = 0.5
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO,
		Vector3(-0.5, -0.4, 0.55).normalized(), Vector3.UP)


func presets() -> Dictionary:
	# "ph"/"th" = height above ground h()
	return {
		# shallow angle over the city — facades, not just roofs
		"skyline":    {"p": Vector3(-1800, 260, 1500), "t": Vector3(400, 160, -300), "f": 50},
		# on the avenue pavement (offset ~17 m off the centreline) looking
		# down-corridor — shopfront wall on the right, carriageway left,
		# towers closing the vanishing point
		"street":     {"p": Vector3(-626, 0, 548), "ph": 1.8, "t": Vector3(-540, 0, 490), "th": 16.0, "f": 64},
		"close_wall": {"p": Vector3(-622, 0, 431), "ph": 1.8, "t": Vector3(-622, 0, 404), "th": 16.0, "f": 58},
		"interior":   {"p": Vector3(19.0, 0, 24.0), "ry": 1.75, "t": Vector3(14, 0, 12.5), "rty": 1.55, "f": 55},
		"interior2":  {"p": Vector3(985.0, 0, 731.0), "ry2": 1.6, "t": Vector3(983, 0, 722.5), "rty2": 1.4, "f": 58},
		"twist":      {"p": Vector3(-340, 60, -60), "t": Vector3(-80, 90, -140), "f": 50},
		"cooling":    {"p": Vector3(1500, 30, -800), "t": Vector3(1700, 60, -950), "f": 52},
		"wheel":      {"p": Vector3(-1310, 20, 1030), "t": Vector3(-1400, 55, 1100), "f": 55},
		"rail":       {"p": Vector3(-620, 80, 280), "t": Vector3(-300, 40, 120), "f": 55},
		"bridge":     {"p": Vector3(600, 45, -500), "t": Vector3(430, 20, -810), "f": 55},
		"plan":       {"p": Vector3(0, 2400, 0), "t": Vector3(0, 0, 0), "f": 60},
	}


func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://shots"))
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for name in shot_names:
		var p: Dictionary = presets().get(name, {})
		if p.is_empty():
			continue
		var pos: Vector3 = p["p"]
		var tgt: Vector3 = p["t"]
		if p.has("ph"):
			pos.y = hf.h(pos.x, pos.z) + p["ph"]
		if p.has("th"):
			tgt.y = hf.h(tgt.x, tgt.z) + p["th"]
		if p.has("ry"):
			pos.y = _intr.floor_y + p["ry"]
		if p.has("rty"):
			tgt.y = _intr.floor_y + p["rty"]
		if p.has("ry2"):
			pos.y = _intr.floor_y2 + p["ry2"]
		if p.has("rty2"):
			tgt.y = _intr.floor_y2 + p["rty2"]
		cam.fov = p["f"]
		cam.look_at_from_position(pos, tgt, Vector3.UP)
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://shots/%s.png" % name)
		img.save_png(path)
		print("saved ", path)
	get_tree().quit()
