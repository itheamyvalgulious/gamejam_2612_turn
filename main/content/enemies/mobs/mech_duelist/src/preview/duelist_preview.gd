extends Node3D
## 单独的建模展台，可环绕观察站姿和持刀步态。

const Model = preload("res://scenes/duelist/duelist_model.tscn")
const DisplayPose = preload("res://src/enemies/duelist/duelist_display_pose.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const Brace = preload("res://src/enemies/duelist/duelist_ground_brace.gd")
const Charge = preload("res://src/enemies/duelist/duelist_charge.gd")
const PlayerPalette = preload("res://src/vesper/material_palette.gd")
const PlayerRig = preload("res://src/vesper/mech_rig.gd")
const MeshKit = preload("res://src/vesper/mesh_kit.gd")
const FONT = preload("res://assets/fonts/DroidSansFallbackFull.ttf")
const STUDIO_REFLECTIONS = preload("res://gfx/duelist_studio_sky.gdshader")
const VIEWS := {
	"全身": [Vector3(0.63, 3.03, -0.29), -0.45, 0.13, 7.58],
	"背面": [Vector3(0.48, 3.02, 0), 2.59, 0.16, 7.58],
	"上半身": [Vector3(-0.07, 4.59, -0.42), -0.36, 0.11, 3.27],
	"刀身": [Vector3(1.88, 2.97, -1.01), -0.47, 0.35, 3.53],
}
const PACING_VIEWS := {
	"全身": [Vector3(0, 2.86, 0), 1.62, 0.18, 8.52],
	"背面": [Vector3(0.42, 2.26, 0), 2.59, 0.16, 7.58],
	"上半身": [Vector3(-0.06, 3.39, -0.36), 1.73, 0.11, 3.27],
	"刀身": [Vector3(0.76, 1.15, -0.63), 1.19, 0.17, 3.89],
}
const BRACE_VIEW := [Vector3(0, 3.08, 0.21), -0.96, 0.12, 7.67]

var _camera: Camera3D
var _target := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _zoom := 5.5
var _focus := Vector3.ZERO
var _angles := Vector2.ZERO
var _dragging := false
var _view_buttons: Dictionary = {}
var _active_view := "全身"
var _model: Node3D
var _pacing := false
var _pace_time := 0.0
var _bracing := false
var _brace_time := 0.0
var _pace_button: Button
var _brace_button: Button
var _pace_player: Node3D
var _deck: Node3D
var _floor: MeshInstance3D


func _ready() -> void:
	get_window().title = "Turn · 人形机甲模型预览"
	Engine.max_fps = 60
	_build_stage()
	_model = Model.instantiate() as Node3D
	add_child(_model)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.05
	_camera.far = 80.0
	add_child(_camera)
	_camera.make_current()
	_select_view("全身")
	_focus = _target
	_angles = Vector2(_yaw, _pitch)
	_camera.size = _zoom
	_update_camera()
	_build_controls()


func _process(delta: float) -> void:
	if _pacing and _pace_time < Pace.DURATION:
		_pace_time = minf(_pace_time + delta, Pace.DURATION)
		_apply_pace()
		if _pace_time >= Pace.DURATION:
			_pace_button.text = "重播踱步"
			_pace_button.set_pressed_no_signal(false)
	elif _bracing:
		_brace_time = fposmod(_brace_time + delta, Brace.DURATION)
		var age := _brace_time - Brace.CONTACT_TIME
		Brace.apply(_model, Brace.depth_at(_brace_time), false, Vector3.INF, Charge.load_at(age))
		_model.set_charge_state(age)
	var blend := 1.0 - exp(-13.0 * delta)
	_focus = _focus.lerp(_view_focus(), blend)
	_angles.x = lerp_angle(_angles.x, _yaw, blend)
	_angles.y = lerpf(_angles.y, _pitch, blend)
	_camera.size = lerpf(_camera.size, _zoom, blend)
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom = maxf(1.25, _zoom * 0.89)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom = minf(9.0, _zoom / 0.89)
	elif event is InputEventMouseMotion and _dragging:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_dragging = false
			return
		_yaw -= event.relative.x * 0.007
		_pitch = clampf(_pitch + event.relative.y * 0.006, -0.28, 1.30)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: _select_view("全身")
			KEY_2: _select_view("背面")
			KEY_3: _select_view("上半身")
			KEY_4: _select_view("刀身")


func _select_view(key: String) -> void:
	_active_view = key
	var view: Array = PACING_VIEWS.get(key, VIEWS[key]) if _pacing else VIEWS[key]
	if _bracing and key == "全身":
		view = BRACE_VIEW
	_target = view[0]
	_yaw = view[1]
	_pitch = view[2]
	_zoom = view[3]
	for view_name: String in _view_buttons:
		_view_buttons[view_name].set_pressed_no_signal(view_name == key)


func _update_camera() -> void:
	var flat := cos(_angles.y)
	var offset := Vector3(sin(_angles.x) * flat, sin(_angles.y), -cos(_angles.x) * flat)
	_camera.position = _focus + offset * 11.0
	_camera.look_at(_focus)


func _view_focus() -> Vector3:
	if not _pacing:
		return _target
	if _active_view == "全身":
		return _model.position.lerp(_pace_player.position, 0.47) + _target
	return _model.transform * _target


func _build_stage() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("25303d")
	var sky := Sky.new()
	var reflection_panels := ShaderMaterial.new()
	reflection_panels.shader = STUDIO_REFLECTIONS
	sky.sky_material = reflection_panels
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d0deea")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.98
	env.ssao_enabled = true
	env.ssao_radius = 0.68
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.36
	env.glow_bloom = 0.035
	env.glow_hdr_threshold = 1.65
	world.environment = env
	add_child(world)
	var floor_mat := _material(Color("1d2630"), 0.20, 0.79)
	var deck_mat := _material(Color("25313b"), 0.4, 0.72)
	var dark_mat := _material(Color("404e59"), 0.36, 0.60)
	var marker_mat := _material(Color("75858f"), 0.40, 0.57)
	var ground := PlaneMesh.new()
	ground.size = Vector2(550, 550)
	_floor = MeshKit.add(self, ground, floor_mat, Vector3(0, -0.182, 0))
	_deck = MeshKit.pivot(self, Vector3.ZERO, "DisplayDeck")
	MeshKit.add(_deck, MeshKit.prism(48, 3.02, 2.98, 0.18), deck_mat, Vector3(0, -0.09, 0))
	for i in range(8):
		var at := TAU * float(i) / 8.0
		var radial := Vector3(sin(at), 0, cos(at))
		var marker := MeshKit.slab(0.53, 0.038, 0.01, 0.003)
		MeshKit.add(_deck, marker, marker_mat if i % 2 == 0 else dark_mat,
			radial * 2.79 + Vector3(0, 0.003, 0), Vector3(0, rad_to_deg(at), 0))
	_light(Vector3(-4.2, 7.0, -4.1), Color("fff3e4"), 4.7, true)
	_light(Vector3(4.3, 4.8, -3.2), Color("b3d7ef"), 3.1)
	_light(Vector3(1.6, 5.4, 4.5), Color("e6eef7"), 4.25)
	_light(Vector3(-3.5, 3.1, 4.4), Color("d2b2c4"), 2.65)


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _light(at: Vector3, color: Color, energy: float, shadows := false) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.light_specular = 0.52
	lamp.omni_range = 15.0
	lamp.omni_attenuation = 1.30
	lamp.shadow_enabled = shadows
	add_child(lamp)


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var title := Label.new()
	title.text = "Turn  /  人形机甲"
	title.position = Vector2(37, 33)
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 31)
	ui.add_child(title)
	var help := Label.new()
	help.text = "左键拖动旋转 · 滚轮缩放"
	help.position = Vector2(39, 80)
	help.add_theme_font_override("font", FONT)
	help.add_theme_font_size_override("font_size", 17)
	help.modulate = Color("abbfcc")
	ui.add_child(help)
	var buttons := HBoxContainer.new()
	buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	buttons.offset_top = -77
	buttons.offset_bottom = -31
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_theme_constant_override("separation", 12)
	ui.add_child(buttons)
	var group := ButtonGroup.new()
	for label: String in VIEWS:
		var button := Button.new()
		button.text = label
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = label == "全身"
		button.custom_minimum_size = Vector2(102, 44)
		button.add_theme_font_override("font", FONT)
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_stylebox_override("normal", _button_style(Color("202c39"), Color("465c6b")))
		button.add_theme_stylebox_override("hover", _button_style(Color("29404a"), Color("73c5c0")))
		button.add_theme_stylebox_override("pressed", _button_style(Color("264742"), Color("69ddcc")))
		button.pressed.connect(_select_view.bind(label))
		buttons.add_child(button)
		_view_buttons[label] = button
	_pace_button = _motion_button(buttons, "侧身踱步", _toggle_pace)
	_brace_button = _motion_button(buttons, "低位撑地", _toggle_brace)


func _motion_button(container: HBoxContainer, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(122, 44)
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", _button_style(Color("202c39"), Color("465c6b")))
	button.add_theme_stylebox_override("hover", _button_style(Color("29404a"), Color("73c5c0")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("264742"), Color("69ddcc")))
	button.toggled.connect(action)
	container.add_child(button)
	return button


func _toggle_pace(playing: bool) -> void:
	_pacing = playing
	_model.set_charge_state(-1.0)
	_pace_time = 0.0
	_pace_button.text = "侧身踱步"
	if _pacing:
		_bracing = false
		_brace_button.set_pressed_no_signal(false)
		if _pace_player == null:
			_pace_player = add_pace_player(self)
		_pace_player.show()
		_deck.hide()
		_floor.position.y = -0.002
		_apply_pace()
		_select_view("全身")
		_focus = _view_focus()
	else:
		_reset_pace_stage()
		DisplayPose.apply(_model)
		_select_view(_active_view)


func _toggle_brace(playing: bool) -> void:
	_bracing = playing
	_model.set_charge_state(-1.0)
	_brace_time = 0.0
	if _bracing:
		_pacing = false
		_pace_button.text = "侧身踱步"
		_pace_button.set_pressed_no_signal(false)
		_reset_pace_stage()
		_select_view("全身")
	else:
		DisplayPose.apply(_model)
		_select_view(_active_view)


static func add_pace_player(stage: Node3D) -> Node3D:
	var hero := PlayerRig.new()
	hero.name = "PlayerReference"
	hero.auto_step = false
	hero.has_weapon = false
	hero.palette = PlayerPalette.HERO
	stage.add_child(hero)
	hero.advance(1.0 / 60.0)
	hero.offhand = 1.0
	hero.preview_weapon_pose({"wpx": 0.52, "wpy": -0.48, "wpz": -0.88, "wrz": -0.47})
	return hero


func _apply_pace() -> void:
	var head := _pace_player.get("head") as Node3D
	var eye_height := head.global_position.y - _pace_player.global_position.y + 0.17
	Pace.apply(_model, _pace_time, _pace_player.position, eye_height)
	_pace_player.look_at(_model.global_position)


func _reset_pace_stage() -> void:
	if _pace_player != null:
		_pace_player.hide()
	_deck.show()
	_floor.position.y = -0.182
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO


func _button_style(fill: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	return box
