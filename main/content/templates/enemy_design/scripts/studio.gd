extends Node3D
class_name Studio
## Studio stage: environment, lights, camera orbit, tuning UI, screenshot hooks.
## The character itself lives in scenes/character.tscn and implements the
## contract in README_kit.md. This file is generic: do not put character art here.

const CHARACTER_SCENE := "res://scenes/character.tscn"
const PANEL_SCRIPT := preload("res://scripts/kit/param_panel.gd")
const OVERLAY_SHADER := preload("res://shaders/screen_overlay.gdshader")
const MESH := preload("res://scripts/kit/mesh_kit.gd")
const MAT := preload("res://scripts/kit/mat_lib.gd")

var character: Node3D
var camera: Camera3D
var cam_pivot: Node3D
var panel: ParamPanel
var ui_root: Control
var title_label: Label

var _yaw := 34.0
var _pitch := 11.0
var _dist := 6.3
var _target := Vector3(0.0, 1.05, 0.0)
var _home := Vector3(34.0, 11.0, 6.3)
var _dragging := false
var _auto_orbit := false
var _ui_visible := true
var _overlay: ColorRect
var _shot_mode := false
var _shot_index := 0


func _ready() -> void:
	_build_environment()
	_build_stage()
	_build_camera()
	_spawn_character()
	_build_ui()
	_build_overlay()
	if OS.get_environment("STUDIO_SHOT") != "":
		_shot_mode = true
		ui_root.visible = false
		if _overlay:
			_overlay.visible = false
	if OS.get_environment("STUDIO_ANIM") != "":
		var an := OS.get_environment("STUDIO_ANIM")
		if character and an in character.anim_names():
			character.play_anim(an)
			if OS.get_environment("STUDIO_TIME") != "":
				character.set_playing(false)
				character.set_anim_time(float(OS.get_environment("STUDIO_TIME")))
	set_process(true)
	var snap_path := OS.get_environment("STUDIO_SNAP")
	if snap_path != "":
		_auto_snap(snap_path)


func _auto_snap(path: String) -> void:
	for i in 24:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	await snap(path)
	get_tree().quit(0)


# --------------------------------------------------------------- environment

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.010, 0.012, 0.022)
	sky_mat.sky_horizon_color = Color(0.052, 0.048, 0.070)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.004, 0.004, 0.006)
	sky_mat.ground_horizon_color = Color(0.030, 0.028, 0.042)
	sky_mat.ground_curve = 0.08
	sky_mat.sun_angle_max = 6.0
	sky_mat.sun_curve = 0.08
	sky_mat.sky_energy_multiplier = 0.75
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.42
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.58
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 0.90
	env.glow_hdr_scale = 2.0
	env.ssao_enabled = true
	env.ssao_radius = 0.85
	env.ssao_intensity = 1.55
	env.ssao_power = 1.4
	env.ssao_light_affect = 0.18
	env.fog_enabled = true
	env.fog_light_color = Color(0.030, 0.034, 0.052)
	env.fog_light_energy = 0.55
	env.fog_density = 0.010
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.01
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.02
	we.environment = env
	add_child(we)


func _build_stage() -> void:
	# ground
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(54.0, 54.0)
	floor_mi.mesh = plane
	floor_mi.material_override = MAT.floor()
	floor_mi.name = "Ground"
	add_child(floor_mi)

	# raised inner plate
	var disc := MESH.disc(4.35, 0.09, 96, 0.025)
	MESH.add(self, disc, MAT.armor_black_soft(), Vector3(0, 0.002, 0), Vector3.ZERO,
		Vector3.ONE, "StagePlate")

	# pylons for depth / scale
	var pylon_mat := MAT.armor_black()
	var strip_mat := MAT.emissive(Color(1.0, 0.30, 0.07), 3.4)
	for i in 7:
		var ang := TAU * float(i) / 7.0 + 0.22
		var radius := 13.5 + 1.2 * float(i % 2)
		var h := 5.5 + float((i * 37) % 5)
		var pos := Vector3(cos(ang) * radius, h * 0.5, sin(ang) * radius)
		var mi := MESH.add(self, MESH.plate(0.62 + 0.12 * float(i % 3), h, 0.34, 0.02), pylon_mat,
			pos, Vector3(0, 90.0 - rad_to_deg(ang), 0), Vector3.ONE, "Pylon%d" % i)
		MESH.add(mi, MESH.plate(0.05, h * 0.70, 0.012, 0.003), strip_mat,
			Vector3(0, 0.0, 0.18), Vector3.ZERO, Vector3.ONE, "Strip")

	# perimeter monoliths: kill the infinite-grid horizon, frame the stage
	for i in 18:
		var a2 := TAU * float(i) / 18.0 + 0.10
		var h2 := 10.0 + 3.0 * float((i * 5) % 4)
		var pos2 := Vector3(cos(a2) * 24.0, h2 * 0.5 - 0.4, sin(a2) * 24.0)
		MESH.add(self, MESH.plate(3.0, h2, 0.5, 0.03), MAT.armor_black(),
			pos2, Vector3(0, 90.0 - rad_to_deg(a2), 0), Vector3.ONE, "Monolith%d" % i)
		if i % 3 == 0:
			MESH.add(self, MESH.plate(0.06, h2 * 0.55, 0.02, 0.004),
				MAT.emissive(Color(0.55, 0.30, 1.0), 2.2),
				pos2 + Vector3(-sin(a2) * 0.27, 0, cos(a2) * 0.27),
				Vector3(0, 90.0 - rad_to_deg(a2), 0), Vector3.ONE, "MonolithGlow%d" % i)

	# distant light bars
	for i in 5:
		var a := -1.15 + float(i) * 0.55
		var bar := MESH.add(self, MESH.plate(0.10, 6.2, 0.10, 0.01),
			MAT.emissive(Color(0.55, 0.32, 1.0) if i % 2 == 0 else Color(1.0, 0.36, 0.10), 2.6),
			Vector3(cos(a) * 21.0, 3.4, -absf(sin(a)) * 21.0 - 6.0), Vector3(0, a * 50.0, 0),
			Vector3.ONE, "Bar%d" % i)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# haze motes
	var p := GPUParticles3D.new()
	p.amount = 110
	p.lifetime = 12.0
	p.preprocess = 6.0
	p.position = Vector3(0, 2.6, 0)
	p.visibility_aabb = AABB(Vector3(-9, -3, -9), Vector3(18, 9, 18))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(7.0, 3.0, 7.0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.09
	pm.gravity = Vector3(0.01, 0.006, 0.0)
	pm.scale_min = 0.4
	pm.scale_max = 1.4
	pm.color = Color(0.55, 0.62, 0.85, 0.20)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var dust_mat := MAT.dust(Color(0.55, 0.66, 1.0, 0.16))
	quad.material = dust_mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)

	# lights
	var key := SpotLight3D.new()
	key.position = Vector3(3.4, 5.6, 4.4)
	key.look_at_from_position(key.position, Vector3(0, 1.45, 0), Vector3.UP)
	key.light_color = Color(1.0, 0.93, 0.86)
	key.light_energy = 15.0
	key.spot_range = 22.0
	key.spot_angle = 26.0
	key.spot_angle_attenuation = 1.1
	key.shadow_enabled = true
	key.shadow_bias = 0.02
	key.shadow_blur = 1.2
	key.name = "KeySpot"
	add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-4.2, 2.6, 3.2)
	fill.light_color = Color(0.44, 0.62, 1.0)
	fill.light_energy = 1.2
	fill.omni_range = 10.0
	fill.name = "Fill"
	add_child(fill)

	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.6, 3.0, -4.4)
	rim.light_color = Color(0.86, 0.28, 1.0)
	rim.light_energy = 1.3
	rim.omni_range = 13.0
	rim.name = "RimMagenta"
	add_child(rim)

	var back := SpotLight3D.new()
	back.position = Vector3(-1.1, 3.8, -5.4)
	back.look_at_from_position(back.position, Vector3(0, 1.25, 0), Vector3.UP)
	back.light_color = Color(0.42, 0.70, 1.0)
	back.light_energy = 4.5
	back.spot_range = 20.0
	back.spot_angle = 17.0
	back.spot_angle_attenuation = 1.4
	back.shadow_enabled = false
	back.name = "BackRim"
	add_child(back)

	var rim2 := OmniLight3D.new()
	rim2.position = Vector3(3.4, 1.9, -3.6)
	rim2.light_color = Color(0.24, 0.68, 1.0)
	rim2.light_energy = 1.0
	rim2.omni_range = 12.0
	rim2.name = "RimCyan"
	add_child(rim2)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 28, 0)
	sun.light_color = Color(0.62, 0.70, 0.95)
	sun.light_energy = 0.35
	sun.shadow_enabled = false
	sun.name = "Sun"
	add_child(sun)


func _build_camera() -> void:
	cam_pivot = Node3D.new()
	cam_pivot.name = "CamPivot"
	add_child(cam_pivot)
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.03
	camera.far = 120.0
	camera.name = "Camera"
	cam_pivot.add_child(camera)
	_update_camera()


func _spawn_character() -> void:
	if not ResourceLoader.exists(CHARACTER_SCENE):
		var l0 := Label3D.new()
		l0.text = "scenes/character.tscn MISSING"
		l0.font_size = 48
		l0.position = Vector3(0, 2.35, 0)
		l0.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l0.modulate = Color(1, 0.3, 0.3)
		add_child(l0)
		# 2 m scale reference so the stage can be judged before the rig exists
		MESH.add(self, MESH.beam(2.0, 0.06, 0.06, 0.06, 0.06, 0.3), MAT.emissive(Color(0.2, 0.8, 1.0), 1.2),
			Vector3(-0.5, 0, 0), Vector3(0, 0, 90))
		MESH.add(self, MESH.disc(0.5, 0.04, 40, 0.01), MAT.trim_dark(), Vector3(0, 0.02, 0))
		return
	var ps: PackedScene = load(CHARACTER_SCENE)
	if ps == null:
		var l := Label3D.new()
		l.text = "scenes/character.tscn MISSING"
		l.font_size = 64
		l.modulate = Color(1, 0.3, 0.3)
		add_child(l)
		return
	character = ps.instantiate()
	character.name = "Character"
	add_child(character)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	# title block, bottom-left
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 26
	box.offset_right = 700
	box.offset_top = -124
	box.offset_bottom = -26
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(box)
	var accent := ColorRect.new()
	accent.color = Color(1.0, 0.38, 0.10, 0.85)
	accent.custom_minimum_size = Vector2(52, 2)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(accent)
	title_label = Label.new()
	title_label.text = str(ProjectSettings.get_setting("application/config/name", "PROCEDURAL ENEMY"))
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	box.add_child(title_label)
	var sub := Label.new()
	sub.text = "procedural rig · joint-driven · live tuning"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.55, 0.60, 0.70))
	box.add_child(sub)

	panel = PANEL_SCRIPT.new()
	ui_root.add_child(panel)
	if character:
		panel.bind(character)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Grade"
	layer.layer = 2
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = OVERLAY_SHADER
	_overlay.material = m
	layer.add_child(_overlay)


# ------------------------------------------------------------------ camera

func set_view(yaw: float, pitch: float, dist: float, target: Vector3) -> void:
	_yaw = yaw
	_pitch = pitch
	_dist = dist
	_target = target
	_update_camera()


func reset_view() -> void:
	set_view(_home.x, _home.y, _home.z, Vector3(0, 1.05, 0))


func _update_camera() -> void:
	if cam_pivot == null:
		return
	cam_pivot.position = _target
	var y := deg_to_rad(_yaw)
	var p := deg_to_rad(_pitch)
	var offset := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * _dist
	camera.position = offset
	camera.look_at_from_position(offset, Vector3.ZERO, Vector3.UP)


func _process(dt: float) -> void:
	if _auto_orbit and not _shot_mode:
		_yaw += dt * 12.0
		_update_camera()
	if _shot_mode:
		pass


func _unhandled_input(event: InputEvent) -> void:
	if _shot_mode:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(2.0, _dist * 0.92)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(24.0, _dist * 1.08)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.32
		_pitch = clampf(_pitch + mm.relative.y * 0.26, -18.0, 72.0)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_F:
				reset_view()
			KEY_H:
				_toggle_ui()
			KEY_F12:
				_save_screenshot()
			KEY_SPACE:
				if character and character.has_method("set_playing"):
					character.set_playing(not character.is_playing())


func _toggle_ui() -> void:
	_ui_visible = not _ui_visible
	ui_root.visible = _ui_visible


func _save_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://renders/manual_%03d.png" % _shot_index
	img.save_png(path)
	_shot_index += 1
	print("[studio] saved ", ProjectSettings.globalize_path(path))


func snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[studio] saved ", path)