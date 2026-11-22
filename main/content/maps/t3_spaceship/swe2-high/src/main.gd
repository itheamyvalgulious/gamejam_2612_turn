extends Node3D

const GeoKit = preload("res://src/kit.gd")
const ShipMats = preload("res://src/mats.gd")
const ShipLayout = preload("res://src/layout.gd")
const HullGen = preload("res://src/hull.gd")
const StructGen = preload("res://src/struct.gd")
const PropGen = preload("res://src/props.gd")
const ZoneGen = preload("res://src/zones.gd")

## ISV MERIDIAN — pure-procedural starship host.
## Builds hull + interior from code (no textures, no external assets),
## sets up environment/lighting, fly camera and still-shot capture.
## CLI:  godot --path . -- --shot=<name|all>   writes PNGs to shots/ and exits.

var kit: GeoKit
var mats: ShipMats
var lay: ShipLayout
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var hull_node: Node3D
var interior_node: Node3D
var fly: Node
var shot_mode := false
var shot_names: Array = []
var build_ms := 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	mats = ShipMats.new()
	kit = GeoKit.new(20261116)
	mats.register(kit)
	lay = ShipLayout.new()

	_build_env()

	var ship := Node3D.new()
	ship.name = "Ship"
	add_child(ship)
	var hull := HullGen.new(kit)
	hull.build_exterior(ship)
	hull_node = ship.get_node("Hull")
	# inner pressure shell: backs every window/gap so voids show dark
	# structure instead of raw starfield through floor/wall seams
	hull.build_inner_shell(ship)

	var st := StructGen.new(kit, lay)
	var pr := PropGen.new(kit)
	var lights_root := Node3D.new()
	lights_root.name = "Lights"
	add_child(lights_root)
	var zones: RefCounted = ZoneGen.new(kit, st, pr, lay, lights_root)
	zones.build(self)

	# emissive surfaces must not cast the big blob shadows
	var no_shad := ["u_light", "u_light_c", "u_light_r", "u_light_o", "u_segm",
		"u_chev", "u_chev2", "plasma", "plasma_o", "holo", "holo_o",
		"screen_a", "screen_b", "screen_c", "glass"]
	var st0: Array = [self]
	while st0.size() > 0:
		var n: Node = st0.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var kill := false
			for kk in no_shad:
				if mi.name.ends_with("_" + kk):
					kill = true
					break
			if kill:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for c in n.get_children():
			st0.append(c)

	build_ms = Time.get_ticks_msec() - t0
	print("MERIDIAN BUILT: %d ms, %d tris, route %.0f m" %
		[build_ms, kit.total_tris, lay.route_len()])

	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(60, 20, 200), Vector3(0, -2, 40), Vector3.UP)

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot="):
			shot_mode = true
			var v := a.substr(7)
			shot_names = presets().keys() if v == "all" else v.split(",")
	if "--flat" in args:
		_debug_flat()
	if "--norm" in args:
		var nm := ShaderMaterial.new()
		nm.shader = load("res://gfx/debug_norm.gdshader")
		_apply_mat_override(nm)
	if "--nohull" in args:
		hull_node.visible = false
	if "--noshell" in args:
		var ish := ship.get_node_or_null("InnerShell")
		if ish:
			ish.visible = false
	if "--nolight" in args:
		get_node("Lights").visible = false
	if "--noao" in args:
		env.ssao_enabled = false
		env.ssil_enabled = false
	if "--dump" in args:
		var zseen := {}
		var int_node := get_node("Interior")
		for mi in int_node.get_children():
			var mi2 := mi as MeshInstance3D
			var vs: PackedVector3Array = mi2.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := Vector3(-1e9, -1e9, -1e9)
			var cnt := 0
			for v in vs:
				if mi2.name.ends_with("_metal_a") and absf(v.x) < 2.2 \
						and v.y > 0.6 and v.y < 1.5:
					var zi := int(v.z * 2.0) * 64 + int(v.y * 4.0) * 8 + int(v.x * 2.0 + 8)
					if not zseen.has(zi):
						zseen[zi] = true
						print("  MDV %s %.2f %.2f %.2f" % [mi2.name, v.x, v.y, v.z])
				if absf(v.x) < 2.0 and v.y > 0.3 and v.y < 3.0 \
						and v.z > -10 and v.z < 8:
					cnt += 1
					lo = lo.min(v); hi = hi.max(v)
			if cnt > 0:
				print("KEY %-24s n=%-7d lo=%s hi=%s" % [mi2.name, cnt, lo, hi])
	for a in args:
		if a.begins_with("--mark="):
			var mk := a.substr(7)
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(1, 0, 1)
			mm.emission_enabled = true
			mm.emission = Color(1, 0, 1)
			var stk3: Array = [self]
			while stk3.size() > 0:
				var n3: Node = stk3.pop_back()
				if n3 is MeshInstance3D and (n3 as MeshInstance3D).name.ends_with("_" + mk):
					(n3 as MeshInstance3D).set_surface_override_material(0, mm)
				for c3 in n3.get_children():
					stk3.append(c3)
	for a in args:
		if a.begins_with("--only="):
			var pat := a.substr(7)
			var stk2: Array = [self]
			while stk2.size() > 0:
				var n2: Node = stk2.pop_back()
				if n2 is MeshInstance3D:
					(n2 as MeshInstance3D).visible = (n2 as MeshInstance3D).name.contains(pat)
				for c2 in n2.get_children():
					stk2.append(c2)
	for a in args:
		if a.begins_with("--hide="):
			var hp := a.substr(7)
			var stk4: Array = [self]
			while stk4.size() > 0:
				var n4: Node = stk4.pop_back()
				if n4 is MeshInstance3D and (n4 as MeshInstance3D).name.contains(hp):
					(n4 as MeshInstance3D).visible = false
				for c4 in n4.get_children():
					stk4.append(c4)
	if "--graywall" in args:
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.4, 0.4, 0.42)
		gm.roughness = 0.8
		for key in ["wall_a", "wall_b", "wall_c", "ceil"]:
			mats.table[key] = gm
		var stk: Array = [self]
		while stk.size() > 0:
			var n: Node = stk.pop_back()
			if n is MeshInstance3D:
				var nm := (n as MeshInstance3D).name
				for key in ["wall_a", "wall_b", "wall_c", "ceil"]:
					if nm.ends_with("_" + key):
						(n as MeshInstance3D).set_surface_override_material(0, gm)
			for c in n.get_children():
				stk.append(c)

	if shot_mode:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		await _run_shots()
	else:
		fly = load("res://src/flycam.gd").new()
		fly.cam = cam
		fly.main = self
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
	env.ambient_light_color = Color(0.38, 0.42, 0.50)
	env.ambient_light_energy = 0.30
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.82
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 0.75
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.4
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.8
	env.ssao_light_affect = 0.3
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.45
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.02
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.85)
	sun.light_energy = 3.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_max_distance = 500.0
	sun.light_cull_mask = 2
	add_child(sun)
	var sd := Vector3(0.55, 0.4, 0.72).normalized()
	sun.look_at_from_position(Vector3.ZERO, -sd, Vector3.UP)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.45, 0.55, 0.9)
	rim.light_energy = 2.4
	rim.light_cull_mask = 2
	add_child(rim)
	rim.look_at_from_position(Vector3.ZERO, sd * Vector3(-1, 0.3, -1), Vector3.UP)
	# faint blue keel fill so the underside never reads as void
	var keel := DirectionalLight3D.new()
	keel.light_color = Color(0.35, 0.45, 0.75)
	keel.light_energy = 0.8
	keel.light_cull_mask = 2
	add_child(keel)
	keel.look_at_from_position(Vector3.ZERO, Vector3(0.3, 1.0, -0.5), Vector3.UP)


func _process(_dt: float) -> void:
	# auto-hide hull while inside
	if hull_node == null or cam == null or shot_mode:
		return
	var p := cam.global_position
	var inside := absf(p.x) < 32.0 and p.y > -16.5 and p.y < 14.0 and p.z > -150.0 and p.z < 150.0
	hull_node.visible = not inside


func _input(ev: InputEvent) -> void:
	if shot_mode:
		return
	if ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_ESCAPE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			KEY_V:
				hull_node.visible = not hull_node.visible
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				_teleport(ev.keycode - KEY_1)
	elif ev is InputEventMouseButton and ev.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _teleport(i: int) -> void:
	var spots := [
		[Vector3(0, -11.5, 144), Vector3(0, -8, 132)],       # engine
		[Vector3(0, -11.0, 115), Vector3(0, -6, 108)],       # reactor
		[Vector3(0, -7.5, 99), Vector3(0, -7, 92)],          # fuel
		[Vector3(0, -7.5, 86), Vector3(0, -7, 70)],          # machine
		[Vector3(0, -7.5, 64), Vector3(4, -6, 48)],          # cargo
		[Vector3(0, 0.5, 33), Vector3(0, 2.5, 21)],          # atrium
		[Vector3(0, 0.5, 6), Vector3(0, 1, -30)],            # habitat
		[Vector3(0, 8.5, -72), Vector3(0, 8, -100)],         # command
		[Vector3(0, 8.8, -107), Vector3(0, 8, -128)],        # bridge
	]
	if i < spots.size() and fly != null:
		fly.teleport(spots[i][0], spots[i][1])


func presets() -> Dictionary:
	return {
		"ext_hero": {"p": Vector3(150, 40, 210), "t": Vector3(0, -2, 20), "f": 45},
		"ext_bow": {"p": Vector3(70, 25, -230), "t": Vector3(0, 0, -110), "f": 48},
		"ext_stern": {"p": Vector3(-55, 30, 240), "t": Vector3(0, -4, 150), "f": 50},
		"ext_side": {"p": Vector3(230, 15, 10), "t": Vector3(0, -2, 0), "f": 40},
		"ext_top": {"p": Vector3(30, 220, 60), "t": Vector3(0, 0, 0), "f": 45},
		"ext_detail": {"p": Vector3(80, 18, 120), "t": Vector3(0, -2, 60), "f": 40},
		"in_engine": {"p": Vector3(0, -11.5, 145), "t": Vector3(0, -7, 128), "f": 78},
		"in_engine2": {"p": Vector3(-14, -5, 120), "t": Vector3(4, -8, 140), "f": 72},
		"in_reactor": {"p": Vector3(0, -6.9, 110.6), "t": Vector3(0, -6.4, 106.5), "f": 72},
		"in_reactor2": {"p": Vector3(-9.5, -6.0, 112.0), "t": Vector3(0, -6.5, 108), "f": 72},
		"in_fuel": {"p": Vector3(0, -7.2, 99), "t": Vector3(0, -7, 91), "f": 76},
		"in_machine": {"p": Vector3(0, -7.2, 87), "t": Vector3(0, -7.5, 70), "f": 78},
		"in_cargo": {"p": Vector3(0, -7.0, 65), "t": Vector3(5, -6.5, 42), "f": 80},
		"in_cargo2": {"p": Vector3(-11, -3, 60), "t": Vector3(8, -6, 40), "f": 74},
		"in_ramp": {"p": Vector3(6, -5.6, 53), "t": Vector3(6, -2.0, 36), "f": 74},
		"in_atrium": {"p": Vector3(0, 0.8, 33), "t": Vector3(0, 4.0, 20), "f": 82},
		"in_atrium2": {"p": Vector3(-9, 4.2, 30), "t": Vector3(6, 1.5, 16), "f": 76},
		"in_habitat": {"p": Vector3(0.0, 1.6, -7.0), "t": Vector3(0.0, 1.0, -36), "f": 66},
		"dbg_hab_far": {"p": Vector3(0, 1.4, -36), "t": Vector3(0, 1.4, 4), "f": 80},
		"dbg_gate": {"p": Vector3(0, 1.4, -30), "t": Vector3(0, 1.2, -56), "f": 65},
		"dbg_rail": {"p": Vector3(0.4, 1.5, -9.5), "t": Vector3(0, 1.0, -13), "f": 70},
		"dbg_cable1": {"p": Vector3(0, 1.5, -13), "t": Vector3(-3, 1.3, -13), "f": 55},
		"dbg_cable2": {"p": Vector3(0, 0.7, -20), "t": Vector3(-3, 0.9, -14), "f": 60},
		"dbg_pillar2": {"p": Vector3(0, 4.5, -12), "t": Vector3(0, 3.5, 2), "f": 70},
		"in_room": {"p": Vector3(-6.2, 1.6, -7.6), "t": Vector3(-11.5, 0.4, -11.6), "f": 80},
		"in_lobby": {"p": Vector3(0, 1.5, -38.5), "t": Vector3(0, 0.5, -46), "f": 76},
		"in_stair": {"p": Vector3(0, 0.5, -49), "t": Vector3(0, 6.5, -68), "f": 74},
		"in_command": {"p": Vector3(0, 8.8, -72), "t": Vector3(0, 8.2, -100), "f": 78},
		"in_bridge": {"p": Vector3(0, 9.2, -104), "t": Vector3(0, 8.2, -128), "f": 82},
		"in_bridge2": {"p": Vector3(-6, 9.5, -112), "t": Vector3(5, 8.0, -128), "f": 70},
		"det_console": {"p": Vector3(-2, 8.6, -121), "t": Vector3(0, 7.6, -126), "f": 55},
		"det_wall": {"p": Vector3(-1.5, -7.3, 80), "t": Vector3(-2.9, -7.5, 77), "f": 55},
		"det_crate": {"p": Vector3(-9, -7.4, 44), "t": Vector3(-11, -8.2, 42), "f": 58},
		"det_floor": {"p": Vector3(0, -7.6, 60), "t": Vector3(1.5, -8.9, 57), "f": 55},
		"det_pipe": {"p": Vector3(-13, -7.0, 96), "t": Vector3(-9, -6.0, 92), "f": 58},
		"det_door": {"p": Vector3(-1.5, 0.6, -13), "t": Vector3(-3.0, 0.8, -13.5), "f": 55},
		"dbg_hab_top": {"p": Vector3(0, 9.5, -6), "t": Vector3(0, 0, -24), "f": 60},
		"dbg_hab_side": {"p": Vector3(-1.2, 1.2, -10), "t": Vector3(-8, 1, -16), "f": 70},
		"dbg_ceil": {"p": Vector3(0, 0.5, -8), "t": Vector3(0, 6, -16), "f": 70},
		"dbg_door": {"p": Vector3(0, 1.0, -13.0), "t": Vector3(-3.0, 1.0, -13.5), "f": 65},
		"dbg_grid": {"p": Vector3(0, 2.2, -4.0), "t": Vector3(-1.0, 1.8, -14.0), "f": 60},
		"dbg_grid2": {"p": Vector3(-2.0, 1.5, -8.0), "t": Vector3(-2.0, 1.5, -16.0), "f": 70},
		"dbg_grid3": {"p": Vector3(0, 1.2, -9.0), "t": Vector3(0, 1.5, -22.0), "f": 65},
		"dbg_grid4": {"p": Vector3(0, 1.2, -28.0), "t": Vector3(0, 1.5, -36.0), "f": 65},
		"dbg_cage": {"p": Vector3(2.2, 1.6, -4.0), "t": Vector3(-1.5, 1.2, -12.0), "f": 75},
		"dbg_cage2": {"p": Vector3(0, 3.0, -6.0), "t": Vector3(0, 1.0, -18.0), "f": 70},
		"dbg_side": {"p": Vector3(2.8, 1.8, -0.5), "t": Vector3(0, 0.8, -0.5), "f": 80},
		"dbg_front": {"p": Vector3(0, 1.5, 1.5), "t": Vector3(0, 1.0, -2.0), "f": 80},
	}


func _apply_mat_override(m: Material) -> void:
	var stack := [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			n.material_override = m
		for c in n.get_children():
			stack.append(c)


func _debug_flat() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.62, 0.65)
	m.roughness = 0.85
	_apply_mat_override(m)
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.glow_enabled = false
	env.ambient_light_energy = 1.0
	env.ambient_light_color = Color(0.85, 0.85, 0.85)
	sun.light_energy = 0.4
	sun.shadow_enabled = false


func _run_shots() -> void:
	for i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	for name in shot_names:
		var p: Dictionary = presets().get(name, {})
		if p.is_empty():
			continue
		cam.fov = p["f"]
		cam.look_at_from_position(p["p"], p["t"], Vector3.UP)
		hull_node.visible = name.begins_with("ext")
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://shots/%s.png" % name)
		img.save_png(path)
		print("saved ", path)
	get_tree().quit()

static func _topz(h: Dictionary) -> String:
	var keys = h.keys()
	keys.sort_custom(func(a, b): return h[a] > h[b])
	var out := ""
	for i in mini(8, keys.size()):
		out += "%s:%d " % [keys[i], h[keys[i]]]
	return out

