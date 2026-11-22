extends Node3D

## Procedural starship generator + host scene.
## Boots the pure-geometry ship, lighting, camera rig, HUD and the guided tour.
## CLI:  godot --path . -- --shot=<preset>   render one still and exit

const SHIP_SEED := 20261115
const BAKE_VERSION := 1

var cfg: ShipConfig
var lib: MatLib
var kit: MeshKit
var hull: Node3D
var interior: Node3D
var details: Node3D
var lights_root: Node3D
var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var cam: Camera3D
var hud: Node = null
var fly: Node = null
var tour: Node = null
var build_ms := 0

var shot_mode := false
var shot_names: Array = []
var quality := "balanced"
var hull_visible_override := -1


func set_hull_visible(v: bool) -> void:
	if hull != null:
		hull.visible = v


func _process(_dt: float) -> void:
	if hull == null or shot_mode:
		return
	if hull_visible_override == 1:
		set_hull_visible(true)
		return
	if hull_visible_override == 0:
		set_hull_visible(false)
		return
	var p := cam.global_position
	var inside := false
	if p.z < -120.0:
		inside = p.z > -150.0 and absf(p.x) < 8.6 and p.y > 9.0 and p.y < 19.0
	else:
		inside = absf(p.x) < 33.0 and p.y > -21.5 and p.y < 22.0 and p.z > -150.0 and p.z < 149.0
	set_hull_visible(not inside)


func cycle_quality() -> void:
	var order := ["low", "balanced", "high", "cine"]
	var i := order.find(quality)
	quality = order[(i + 1) % order.size()]
	apply_quality()


func toggle_hull() -> void:
	var cur := hull.visible if hull != null else true
	hull_visible_override = 0 if cur else 1
	set_hull_visible(not cur)


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	cfg = ShipConfig.new()
	lib = MatLib.new(SHIP_SEED)
	kit = MeshKit.new(SHIP_SEED)

	for key in lib.table.keys():
		kit.material(key, lib.m(key))

	# extra hull lettering material key
	kit.material("hull_light_text", lib.m("metal_dark"))

	_build_environment()
	_build_ship()
	_boost_interior_lights()
	_setup_camera()

	build_ms = Time.get_ticks_msec() - t0
	print("SHIP BUILT in %d ms, %d triangles" % [build_ms, kit.triangle_total()])
	print("route length: %.1f m" % cfg.route_length())

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--quality="):
			quality = a.substr(10)
		if a == "--low":
			quality = "low"
		if a == "--cine":
			quality = "cine"
		if a.begins_with("--shot="):
			shot_mode = true
			var v := a.substr(7)
			shot_names = shot_presets().keys() if v == "all" else v.split(",")
		if a == "--shots":
			shot_mode = true
			shot_names = shot_presets().keys()

	if "--flat" in args:
		_apply_flat_debug()
	if "--lit" in args:
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.6, 0.6, 0.6)
		lm.roughness = 0.7
		lm.metallic = 0.0
		var st3: Array = [self]
		while st3.size() > 0:
			var nn: Node = st3.pop_back()
			if nn is MeshInstance3D:
				nn.material_override = lm
			for cc in nn.get_children():
				st3.append(cc)
		env.ambient_light_energy = 0.04
		print("lit debug applied")
	if "--aabb" in args:
		var st5: Array = [self]
		while st5.size() > 0:
			var nn: Node = st5.pop_back()
			if nn is MeshInstance3D:
				var mi := nn as MeshInstance3D
				var aabb: AABB = mi.get_aabb()
				if mi.layers == 2 and aabb.position.z < -120.0 and aabb.position.z + aabb.size.z > -150.0:
					print("LAYER2 ", mi.name, " aabb=", aabb, " parent=", mi.get_parent().name)
			for cc in nn.get_children():
				st5.append(cc)
	if "--nohull" in args:
		var st4: Array = [self]
		while st4.size() > 0:
			var nn: Node = st4.pop_back()
			if nn is MeshInstance3D and (nn as MeshInstance3D).layers == 2:
				nn.visible = false
			for cc in nn.get_children():
				st4.append(cc)
	if "--noglow" in args:
		env.glow_enabled = false
	if "--noshadow" in args:
		sun.shadow_enabled = false
		print("sun basis z=", sun.global_transform.basis.z, " energy=", sun.light_energy, " shadow=", sun.shadow_enabled)
	if "--norm" in args:
		var nm := ShaderMaterial.new()
		nm.shader = load("res://shaders/debug_normal.gdshader")
		var st2: Array = [self]
		while st2.size() > 0:
			var n: Node = st2.pop_back()
			if n is MeshInstance3D:
				n.material_override = nm
			for c in n.get_children():
				st2.append(c)

	if "--bench" in args:
		shot_mode = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		await _run_bench()
		return

	if shot_mode or "--uishot" in args:
		quality = "cine"
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		apply_quality()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if shot_mode:
		await _run_shots()
	else:
		_setup_interactive()
		if "--uishot" in args:
			await _run_ui_shots()


func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm: ShaderMaterial = lib.sky_material(Vector3(-0.30, 0.17, -0.94), Vector3(0.50, 0.55, 0.67))
	sm.set_shader_parameter("planet_radius", 17.0)
	sm.set_shader_parameter("planet_dist", 120.0)
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.44, 0.56)
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0

	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.4
	env.ssao_power = 2.0
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.25
	env.ssao_ao_channel_affect = 0.6

	env.ssil_enabled = true
	env.ssil_radius = 5.0
	env.ssil_intensity = 1.6
	env.ssil_normal_rejection = 0.6

	env.ssr_enabled = false
	env.ssr_max_steps = 40
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.4

	env.volumetric_fog_enabled = false
	env.volumetric_fog_density = 0.0028
	env.volumetric_fog_albedo = Color(0.72, 0.78, 0.88)
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_gi_inject = 0.4
	env.volumetric_fog_ambient_inject = 0.35

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05

	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.94, 0.86)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 420.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.15
	sun.directional_shadow_split_3 = 0.4
	sun.light_cull_mask = 2      # exterior shell only; interiors have their own lamps
	add_child(sun)
	var sd := Vector3(0.50, 0.55, 0.67).normalized()
	sun.look_at_from_position(Vector3.ZERO, -sd, Vector3.UP)

	# starlight fill from the opposite side so space shadows stay readable
	var fill := DirectionalLight3D.new()
	fill.name = "StarFill"
	fill.light_color = Color(0.42, 0.55, 0.85)
	fill.light_energy = 0.32
	fill.shadow_enabled = false
	fill.light_cull_mask = 2
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, sd, Vector3.UP)


func _build_ship() -> void:
	var args := OS.get_cmdline_user_args()
	var bake_mode := "--bake" in args
	var use_baked := false
	if not bake_mode and not ("--nobake" in args):
		use_baked = _load_baked()
	if use_baked:
		print("BAKED SCENES LOADED")
		return
	var ship := Node3D.new()
	ship.name = "Ship"
	add_child(ship)

	lights_root = Node3D.new()
	lights_root.name = "Lights"
	add_child(lights_root)

	var hb := HullBuilder.new(kit, cfg)
	hb.details = details
	hb.build(ship)
	hull = ship

	interior = Node3D.new()
	interior.name = "Interior"
	add_child(interior)
	var ib := InteriorBuilder.new(kit, lib, cfg, lights_root)
	ib.build(interior)
	if bake_mode:
		_save_baked(ship, interior)
		get_tree().quit()


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_set_owner_recursive(c, owner_node)


func _load_baked() -> bool:
	var path := "res://baked/manifest.json"
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", -1)) != BAKE_VERSION:
		return false
	var ship_ps: PackedScene = load(data.get("hull", ""))
	if ship_ps == null:
		return false
	hull = ship_ps.instantiate()
	hull.name = "Ship"
	add_child(hull)
	lights_root = Node3D.new()
	lights_root.name = "Lights"
	add_child(lights_root)
	interior = Node3D.new()
	interior.name = "Interior"
	add_child(interior)
	var zones: Dictionary = data.get("zones", {})
	for key in zones:
		var zps: PackedScene = load(zones[key])
		if zps == null:
			continue
		var zn: Node3D = zps.instantiate()
		interior.add_child(zn)
	return true


func _save_baked(ship: Node3D, interior_node: Node3D) -> void:
	var dir := ProjectSettings.globalize_path("res://baked")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".res") or f.ends_with(".tscn") or f == "manifest.json":
			DirAccess.remove_absolute(dir.path_join(f))
	var zones := {}
	for z in interior_node.get_children():
		if z.has_meta("zone_key"):
			var key: String = z.get_meta("zone_key")
			var path := "res://baked/%s.res" % key
			_set_owner_recursive(z, z)
			var ps := PackedScene.new()
			ps.pack(z)
			ResourceSaver.save(ps, path)
			zones[key] = path
	_set_owner_recursive(ship, ship)
	var hull_ps := PackedScene.new()
	hull_ps.pack(ship)
	ResourceSaver.save(hull_ps, "res://baked/hull.res")
	var manifest := {"version": BAKE_VERSION, "hull": "res://baked/hull.res", "zones": zones}
	var f := FileAccess.open("res://baked/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	print("BAKED %d zones -> res://baked/" % zones.size())


func _boost_interior_lights() -> void:
	if interior == null:
		return
	for z in interior.get_children():
		for c in z.get_children():
			if c is OmniLight3D:
				(c as OmniLight3D).light_energy *= 1.45


func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 68.0
	cam.near = 0.05
	cam.far = 6000.0
	add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(42, 14, 196), Vector3(0, -2, 60), Vector3.UP)


func _setup_interactive() -> void:
	apply_quality()
	cam.global_position = Vector3(8.5, -18.6, 147.0)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var FlyCam := load("res://scripts/fly_camera.gd")
	fly = FlyCam.new()
	fly.name = "FlyCamera"
	fly.camera = cam
	fly.main = self
	add_child(fly)
	var HUD := load("res://scripts/hud.gd")
	hud = HUD.new()
	hud.name = "HUD"
	hud.cfg = cfg
	hud.main = self
	add_child(hud)
	var Streamer := load("res://scripts/streamer.gd")
	var st: Node = Streamer.new()
	st.name = "Streamer"
	st.main = self
	add_child(st)
	var Tour := load("res://scripts/tour.gd")
	tour = Tour.new()
	tour.name = "Tour"
	tour.main = self
	tour.cfg = cfg
	tour.camera = cam
	add_child(tour)


func route_progress() -> float:
	var p := cam.global_position
	var total := 0.0
	var best := 1e18
	var best_along := 0.0
	var acc := 0.0
	var route: Array = cfg.route
	for i in range(route.size() - 1):
		var a: Vector3 = route[i]
		var b: Vector3 = route[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		var t: float = clampf((p - a).dot(b - a) / (seg * seg), 0.0, 1.0)
		var q := a.lerp(b, t)
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			best_along = acc + seg * t
		acc += seg
		total = acc
	return clampf(best_along / maxf(total, 1.0), 0.0, 1.0)


func jump_home() -> void:
	if tour and tour.is_running():
		tour.toggle()
	fly.teleport(Vector3(8.5, -18.6, 147.0), Vector3(-2.0, -5.0, 126.0))


func jump_to(idx: int) -> void:
	var spots := [
		[Vector3(7.6, -19.1, 142.0), Vector3(0.0, -8.0, 126.0)],
		[Vector3(0.0, -8.4, 76.0), Vector3(0.0, -8.6, 48.0)],
		[Vector3(0.0, 1.2, -26.5), Vector3(0.0, 6.2, -41.0)],
		[Vector3(-6.0, -0.9, -61.0), Vector3(4.0, 6.0, -84.0)],
		[Vector3(0.0, 5.6, -94.0), Vector3(0.0, 7.4, -112.0)],
		[Vector3(0.0, 13.9, -126.3), Vector3(0.0, 13.0, -145.0)],
		[Vector3(16.0, 5.4, -46.0), Vector3(24.0, 5.4, -36.0)],
		[Vector3(-10.0, -10.2, -61.0), Vector3(2.0, -8.6, -78.0)],
		[Vector3(0.0, 13.2, -32.0), Vector3(0.0, 13.4, -51.0)],
	]
	if idx < 0 or idx >= spots.size():
		return
	if tour and tour.is_running():
		tour.toggle()
	fly.teleport(spots[idx][0], spots[idx][1])
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func apply_quality() -> void:
	match quality:
		"low":
			env.ssao_enabled = false
			env.ssil_enabled = false
			env.ssr_enabled = false
			env.glow_enabled = true
			get_viewport().scaling_3d_scale = 0.85
			get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		"balanced":
			env.ssao_enabled = true
			env.ssao_intensity = 1.7
			env.ssil_enabled = false
			env.ssr_enabled = false
			env.glow_enabled = true
			get_viewport().scaling_3d_scale = 1.0
		"high":
			env.ssao_enabled = true
			env.ssao_intensity = 2.2
			env.ssil_enabled = true
			env.ssr_enabled = false
			env.glow_enabled = true
			get_viewport().scaling_3d_scale = 1.0
		"cine":
			env.ssao_enabled = true
			env.ssao_intensity = 2.4
			env.ssil_enabled = true
			env.ssil_intensity = 1.5
			env.ssr_enabled = true
			env.glow_enabled = true
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.0038
			env.volumetric_fog_ambient_inject = 0.12
			env.volumetric_fog_gi_inject = 0.4
			get_viewport().scaling_3d_scale = 1.0
	print("QUALITY: ", quality)


func _run_bench() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	cam.look_at_from_position(Vector3(8.5, -18.5, 147.2), Vector3(-2.0, -3.0, 124.0), Vector3.UP)
	cam.fov = 88
	set_hull_visible(false)
	for i in 40:
		await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var frames := 240
	for i in frames:
		await get_tree().process_frame
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	print("BENCH: %d frames in %.2fs = %.1f fps, %d triangles" %
		[frames, dt, frames / maxf(dt, 0.001), kit.triangle_total()])
	get_tree().quit()


func _run_ui_shots() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	hud.map_on = false
	hud.tour_active = false
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var e1 := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/ui_hud.png"))
	print("ui_hud save=", e1)
	hud.map_on = true
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var e2 := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/ui_map.png"))
	print("ui_map save=", e2)
	hud.map_on = false
	# tour frame
	tour.toggle()
	tour.snap_to(226.0)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var e3 := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/ui_tour.png"))
	print("ui_tour save=", e3, " tour_dist=", tour.dist, " pos=", cam.global_position)
	tour.running = false
	get_tree().quit()


# ---------------------------------------------------------------- presets ---
func shot_presets() -> Dictionary:
	return {
		"ext_hero": {"pos": Vector3(168, 58, 232), "target": Vector3(-6, 0, 6), "fov": 46},
		"ext_bow": {"pos": Vector3(104, 34, -244), "target": Vector3(0, 4, -96), "fov": 44},
		"ext_stern": {"pos": Vector3(-74, 44, 300), "target": Vector3(0, -2, 96), "fov": 48},
		"ext_side": {"pos": Vector3(320, 26, 10), "target": Vector3(0, 0, 0), "fov": 40},
		"ext_top": {"pos": Vector3(60, 250, 90), "target": Vector3(0, 0, 0), "fov": 42},
		"ext_bridge": {"pos": Vector3(26, 9, -178), "target": Vector3(0, 7, -140), "fov": 44},
		"ext_close": {"pos": Vector3(118, 22, 96), "target": Vector3(0, 0, 52), "fov": 40},
		"in_engine": {"pos": Vector3(8.5, -18.5, 147.2), "target": Vector3(-2.0, -3.0, 124.0), "fov": 88},
		"in_cargo": {"pos": Vector3(3.0, -8.3, 76.0), "target": Vector3(-3.0, -8.0, 48.0), "fov": 74},
		"in_corridor": {"pos": Vector3(0.0, -10.2, 34.0), "target": Vector3(0.0, -10.4, 14.0), "fov": 76},
		"in_spine": {"pos": Vector3(0.0, -2.2, 4.0), "target": Vector3(0.0, -2.6, -22.0), "fov": 76},
		"in_reactor": {"pos": Vector3(0.0, 1.6, -25.5), "target": Vector3(0.0, 6.2, -41.0), "fov": 80},
		"in_atrium": {"pos": Vector3(-7.0, -0.6, -60.5), "target": Vector3(5.0, 6.5, -86.0), "fov": 84},
		"in_atrium_up": {"pos": Vector3(0.0, -2.4, -68.0), "target": Vector3(0.0, 17.5, -82.0), "fov": 86},
		"in_hydro": {"pos": Vector3(0.0, 5.6, -94.0), "target": Vector3(2.0, 7.0, -114.0), "fov": 76},
		"in_bridge": {"pos": Vector3(0.0, 14.5, -129.0), "target": Vector3(0.0, 13.0, -145.5), "fov": 80},
		"in_quarters": {"pos": Vector3(21.5, 5.7, -47.0), "target": Vector3(21.5, 4.6, -31.0), "fov": 92},
		"in_medbay": {"pos": Vector3(-21.5, 5.5, -47.0), "target": Vector3(-21.5, 4.6, -31.0), "fov": 92},
		"in_observation": {"pos": Vector3(0.0, 13.4, -31.0), "target": Vector3(0.0, 13.0, -53.0), "fov": 90},
		"in_hangar": {"pos": Vector3(0.0, -9.5, -59.0), "target": Vector3(-2.0, -8.4, -84.0), "fov": 88},
		"in_machine": {"pos": Vector3(0.0, -9.7, -31.5), "target": Vector3(0.0, -8.6, -54.0), "fov": 88},
		"det_bunk": {"pos": Vector3(23.0, 5.25, -40.4), "target": Vector3(27.4, 4.55, -42.6), "fov": 62},
		"det_pipe": {"pos": Vector3(-1.4, -9.9, 27.0), "target": Vector3(-2.9, -9.0, 22.5), "fov": 58},
		"det_cargo": {"pos": Vector3(-12.6, -9.5, 55.0), "target": Vector3(-16.4, -9.9, 51.0), "fov": 62},
		"det_bridge": {"pos": Vector3(1.5, 13.1, -136.0), "target": Vector3(0.0, 13.1, -141.5), "fov": 60},
		"det_wall": {"pos": Vector3(1.3, -9.7, 8.0), "target": Vector3(2.9, -9.8, 6.0), "fov": 55},
		"in_officers": {"pos": Vector3(0.0, 13.5, -9.5), "target": Vector3(0.0, 12.7, -27.0), "fov": 90},
	}


func _apply_flat_debug() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.63, 0.65)
	m.roughness = 0.8
	m.metallic = 0.0
	var stack: Array = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			n.material_override = m
		for c in n.get_children():
			stack.append(c)
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.glow_enabled = false
	env.volumetric_fog_enabled = false
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.9)
	env.ambient_light_energy = 1.1
	sun.light_energy = 0.45
	sun.shadow_enabled = false


func apply_shot(name: String) -> void:
	var p: Dictionary = shot_presets().get(name, {})
	if p.is_empty():
		return
	cam.fov = p["fov"]
	cam.look_at_from_position(p["pos"], p["target"], Vector3.UP)


func _run_shots() -> void:
	# give the renderer time to compile shaders / converge GI
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	for name in shot_names:
		if not shot_presets().has(name):
			continue
		apply_shot(name)
		set_hull_visible(name.begins_with("ext"))
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://screenshots/%s.png" % name)
		img.save_png(path)
		print("saved ", path)
	get_tree().quit()