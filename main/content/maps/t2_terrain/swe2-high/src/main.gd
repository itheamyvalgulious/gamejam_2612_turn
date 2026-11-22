extends Node3D

const TerrainChunks = preload("res://src/terrain.gd")

## VALE OF THREE SEASONS — pure-procedural 10 km² fantasy terrain.
## 4096×2560 m heightfield · snow plateau (N) / ridged massif + gorge +
## waterfall (mid) / jungle basin + lake (S).
## CLI:  godot --path . -- --shot=<name|all>   writes PNGs to shots/ and exits.

var hf: HeightField
var terr: TerrainChunks
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var fly: Node
var water: Node3D
var veg: Node3D
var shot_mode := false
var shot_names: Array = []
var build_ms := 0
var _flat := false
var _geom_args: Array = []


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	hf = HeightField.new()
	_build_env()

	terr = TerrainChunks.new()
	terr.name = "Terrain"
	var tmat := ShaderMaterial.new()
	tmat.shader = load("res://gfx/terrain.gdshader")
	terr.setup(hf, tmat)
	var cli := OS.get_cmdline_user_args()
	if "--noskirt" in cli:
		terr.no_skirt = true
	for a in cli:
		if a.begins_with("--lod="):
			terr.force_lod = int(a.substr(6))
		if a.begins_with("--ring="):
			terr.force_ring = int(a.substr(7))
	add_child(terr)

	# optional subsystems (built by sibling workers — guard so the project
	# still runs while files are absent)
	if ResourceLoader.exists("res://src/water.gd"):
		water = load("res://src/water.gd").new()
		water.name = "Water"
		add_child(water)
		water.build(hf)
	if ResourceLoader.exists("res://src/veg.gd"):
		veg = load("res://src/veg.gd").new()
		veg.name = "Veg"
		add_child(veg)
		veg.build(hf)

	build_ms = Time.get_ticks_msec() - t0
	print("VALE BUILT: %d ms (heightfield + env)" % build_ms)

	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 60.0
	cam.near = 0.3
	cam.far = 9000.0
	add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(-900, 700, 1100),
		Vector3(200, 60, 200), Vector3.UP)

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot="):
			shot_mode = true
			var v := a.substr(7)
			shot_names = presets().keys() if v == "all" else v.split(",")
	if "--white" in args:
		# total neutral: grey sky, white ambient, white overhead sun —
		# whatever colour survives this is pure albedo/geometry
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.5, 0.55, 0.65)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1, 1, 1)
		env.ambient_light_energy = 0.4
		env.fog_enabled = false
		env.adjustment_enabled = false
		env.tonemap_exposure = 1.0
		sun.light_color = Color(1, 1, 1)
		sun.light_energy = 1.2
		sun.look_at_from_position(Vector3.ZERO,
			Vector3(0.2, -1.0, -0.3), Vector3.UP)
	if "--day" in args:
		# neutral lighting debug: white sun, no fog, no tonemapping colour
		sun.light_color = Color(1, 1, 1)
		sun.light_energy = 1.4
		sun.look_at_from_position(Vector3.ZERO,
			-Vector3(0.5, 0.7, -0.5).normalized(), Vector3.UP)
		env.fog_enabled = false
		env.adjustment_enabled = false
		env.tonemap_exposure = 1.0
		env.ambient_light_energy = 0.45
		env.ambient_light_sky_contribution = 0.3
	if "--flat" in args:
		_flat = true
		env.ambient_light_energy = 1.2
		env.glow_enabled = false
		sun.light_energy = 0.5
	_geom_args = args
	_apply_geom_flags(args)
	await _finish_ready(args)

func _apply_geom_flags(args: Array) -> void:
	var geom: Array = []
	var gk: Array = [self]
	while gk.size() > 0:
		var gn: Node = gk.pop_back()
		if (gn is MeshInstance3D or gn is MultiMeshInstance3D
				or gn is GPUParticles3D):
			geom.append(gn)
		for gc in gn.get_children():
			gk.append(gc)
	for a in args:
		var a_str: String = a
		var want_hide: bool = a_str.begins_with("--hide=")
		var want_only: bool = a_str.begins_with("--only=")
		if not (want_hide or want_only):
			continue
		var pat: String = a_str.substr(7)
		for c in geom:
			var s := ""
			var p: Node = c
			while p != null:
				s += "/" + p.name
				p = p.get_parent()
			var hit := s.contains(pat)
			if want_hide and hit:
				c.visible = false
				c.set_meta("hidden", true)
			if want_only:
				c.visible = hit
				if not hit:
					c.set_meta("hidden", true)


func _finish_ready(args: Array) -> void:
	var geom: Array = []
	var gk: Array = [self]
	while gk.size() > 0:
		var gn: Node = gk.pop_back()
		if (gn is MeshInstance3D or gn is MultiMeshInstance3D
				or gn is GPUParticles3D):
			geom.append(gn)
		for gc in gn.get_children():
			gk.append(gc)
	if "--dump" in args:
		for c in geom:
			var aabb := AABB()
			if c is MeshInstance3D:
				aabb = (c as MeshInstance3D).get_aabb()
			elif c is MultiMeshInstance3D:
				aabb = (c as MultiMeshInstance3D).multimesh.mesh.get_aabb()
			var gp := (c as Node3D).global_position
			print("GEO %-36s aabb=%s at=%s" % [c.name, aabb, gp])
	if shot_mode:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		await _run_shots()
	else:
		fly = load("res://src/flycam.gd").new()
		fly.cam = cam
		add_child(fly)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _build_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://gfx/sky.gdshader")
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.66, 0.78)
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 4.0
	env.glow_enabled = true
	env.glow_intensity = 0.30
	env.glow_strength = 0.8
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.72, 0.80)
	env.fog_light_energy = 0.4
	env.fog_sun_scatter = 0.35
	env.fog_density = 0.0
	env.fog_aerial_perspective = 0.12
	env.fog_height = 24.0
	env.fog_height_density = 0.0004
	env.fog_sky_affect = 0.2
	env.ssao_enabled = true
	env.ssao_radius = 3.0
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.0
	we.environment = env
	add_child(we)

	# low warm sun from the west — long shadows for the dusk mood
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.86)
	sun.light_energy = 1.5
	sun.shadow_enabled = "--noshadow" not in OS.get_cmdline_user_args()
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 4500.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.2
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_pancake_size = 400.0
	add_child(sun)
	# dusk sun low in the SW sky (light travels NE + down) so the faces
	# the south-side cameras actually see are lit, not silhouettes
	sun.look_at_from_position(Vector3.ZERO,
		Vector3(0.5, -0.35, -0.55).normalized(), Vector3.UP)

	# cool sky fill so shadows keep ambient blue instead of going black
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.62, 0.80)
	fill.light_energy = 1.2
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO,
		Vector3(0.3, -1.0, -0.2), Vector3.UP)


func _process(dt: float) -> void:
	if shot_mode or cam == null:
		return
	terr.update(cam.global_position)
	terr.build_some(3)
	if water and water.has_method("update"):
		water.update(dt, cam.global_position)
	if veg and veg.has_method("update"):
		veg.update(dt, cam.global_position)
	if _flat:
		_apply_flat()
	if _geom_args.size() > 0:
		_apply_geom_flags(_geom_args)


func _input(ev: InputEvent) -> void:
	if shot_mode:
		return
	if ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_ESCAPE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				_teleport(ev.keycode - KEY_1)
	elif ev is InputEventMouseButton and ev.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _teleport(i: int) -> void:
	var spots := [
		[Vector3(-700, 260, -980), Vector3(-200, 110, -1100)],  # snow plateau
		[Vector3(-60, 90, -260), Vector3(90, 45, -40)],         # gorge head
		[Vector3(60, 34, 200), Vector3(130, 30, 165)],          # falls front
		[Vector3(240, 40, 560), Vector3(360, 12, 720)],         # jungle delta
		[Vector3(430, 30, 900), Vector3(520, 4, 980)],          # lake shore
	]
	if i < spots.size() and fly != null:
		fly.teleport(spots[i][0], spots[i][1])


func presets() -> Dictionary:
	# "ph"/"th" = height above terrain surface at that x/z (auto ground-lock)
	return {
		"ext_overview": {"p": Vector3(-1250, 950, 1250), "t": Vector3(150, 60, 150), "f": 50},
		"ext_plan": {"p": Vector3(0, 2600, 40), "t": Vector3(0, 0, 40), "f": 60},
		"ext_ridge": {"p": Vector3(-400, 480, 420), "t": Vector3(100, 150, 60), "f": 52},
		"ext_snowfield": {"p": Vector3(-820, 320, -840), "t": Vector3(-300, 110, -1080), "f": 58},
		"ext_gorge": {"p": Vector3(-40, 0, 330), "ph": 170.0, "t": Vector3(95, 0, -30), "th": 20.0, "f": 55},
		"ext_falls": {"p": Vector3(120, 0, 320), "ph": 50.0, "t": Vector3(135, 0, 200), "th": 25.0, "f": 58},
		"ext_jungle": {"p": Vector3(230, 0, 700), "ph": 45.0, "t": Vector3(400, 0, 930), "th": 10.0, "f": 58},
		"ext_lake": {"p": Vector3(290, 0, 860), "ph": 32.0, "t": Vector3(500, 2, 985), "f": 60},
		"in_snow": {"p": Vector3(-600, 0, -930), "ph": 7.0, "t": Vector3(-470, 0, -1030), "th": 4.0, "f": 62},
		# canyon look-down: high above the gorge mouth, face south along
		# the river — no interior vantage (walls are 300 m + fins)
		"in_gorge": {"p": Vector3(-160, 420, 430), "t": Vector3(120, 40, 130), "f": 62},
		# falls face-on from the plunge basin side
		"in_falls_base": {"p": Vector3(135, 0, 330), "ph": 55.0, "t": Vector3(133, 0, 183), "th": 28.0, "f": 58},
		"in_jungle_floor": {"p": Vector3(160, 0, 660), "ph": 2.8, "t": Vector3(148, 0, 640), "th": 11.0, "f": 64},
		"in_riverbank": {"p": Vector3(430, 0, 850), "ph": 2.6, "t": Vector3(485, 0, 925), "th": 3.5, "f": 62},
		"det_strata": {"p": Vector3(60, 0, -60), "ph": 80.0, "t": Vector3(130, 0, 30), "th": 35.0, "f": 45},
		"det_canopy": {"p": Vector3(300, 0, 680), "ph": 16.0, "t": Vector3(365, 0, 775), "th": 10.0, "f": 55},
		"dbg_grid": {"p": Vector3(380, 0, 830), "ph": 25.0, "t": Vector3(520, 0, 960), "th": 4.0, "f": 50},
	}


func _apply_flat() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.62, 0.65)
	m.roughness = 0.85
	for c in terr.get_children():
		(c as MeshInstance3D).material_override = m


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
		# "ph"/"th" = height above terrain surface for that x/z
		if p.has("ph"):
			pos.y = hf.h(pos.x, pos.z) + p["ph"]
		if p.has("th"):
			tgt.y = hf.h(tgt.x, tgt.z) + p["th"]
		# never park the lens inside rock
		pos.y = maxf(pos.y, hf.h(pos.x, pos.z) + 1.5)
		cam.fov = p["f"]
		cam.look_at_from_position(pos, tgt, Vector3.UP)
		# stream every chunk this shot needs before exposing the frame
		terr.update(p["p"])
		while terr._queue.size() > 0:
			terr.build_some(64)
		# shot mode skips _process, so push veg/water LOD updates manually
		if water and water.has_method("update"):
			water.update(0.016, cam.global_position)
		if veg and veg.has_method("update"):
			veg.update(0.016, cam.global_position)
		if _flat:
			_apply_flat()
		if _geom_args.size() > 0:
			_apply_geom_flags(_geom_args)
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://shots/%s.png" % name)
		img.save_png(path)
		print("saved ", path)
	get_tree().quit()
