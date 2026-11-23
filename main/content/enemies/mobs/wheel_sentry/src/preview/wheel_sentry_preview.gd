extends Node3D
## Standalone model viewer for the folded and deployed shapes.

const Model = preload("res://scenes/ranged/wheel_sentry_model.tscn")
const MeshKit = preload("res://src/vesper/mesh_kit.gd")
const Materials = preload("res://src/vesper/materials.gd")
const StudioSky = preload("res://gfx/studio_sky.gdshader")
const FOCUS := Vector3(0, 1.78, 0)
const VIEWS := [Vector2(0.78, 0.23), Vector2(1.57, 0.16), Vector2(2.56, 0.28)]

var model: Node3D
var stage_camera: Camera3D
var overlay: CanvasLayer
var _view := VIEWS[0]
var _zoom := 4.50
var _focus := FOCUS
var _deployment := 0.0
var _target_deployment := 0.0


func _ready() -> void:
	get_window().title = "Turn · 单轮巡射机甲"
	_build_stage()
	model = Model.instantiate()
	add_child(model)
	stage_camera = Camera3D.new()
	stage_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage_camera.size = _zoom
	add_child(stage_camera)
	stage_camera.make_current()
	_update_camera()
	_build_controls()


func _process(delta: float) -> void:
	if not is_equal_approx(_deployment, _target_deployment):
		_deployment = move_toward(_deployment, _target_deployment, delta * 2.0)
		model.set_deployment(_deployment)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_view.x -= event.relative.x * 0.009
		_view.y = clampf(_view.y + event.relative.y * 0.007, -0.12, 1.15)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(1.6, _zoom * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(7.5, _zoom / 0.9)
		stage_camera.size = _zoom


func frame_model(yaw: float, pitch: float, size: float, deployed: bool, focus := FOCUS) -> void:
	_target_deployment = 1.0 if deployed else 0.0
	_deployment = _target_deployment
	model.set_deployment(_deployment)
	_set_view(Vector2(yaw, pitch), focus, size)


func _set_view(view: Vector2, focus: Vector3, size: float) -> void:
	_view = view
	_focus = focus
	_zoom = size
	stage_camera.size = size
	_update_camera()


func _update_camera() -> void:
	var plane := cos(_view.y)
	var orbit := Vector3(sin(_view.x) * plane, sin(_view.y), -cos(_view.x) * plane)
	stage_camera.position = _focus + orbit * 10.0
	stage_camera.look_at(_focus)


func _build_controls() -> void:
	overlay = CanvasLayer.new()
	add_child(overlay)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(ui)
	var title := Label.new()
	title.text = "单轮巡射机甲"
	title.position = Vector2(38, 28)
	title.add_theme_font_size_override("font_size", 31)
	ui.add_child(title)
	var hint := Label.new()
	hint.text = "左键拖动 · 滚轮缩放"
	hint.position = Vector2(40, 73)
	hint.modulate = Color("c0cad9")
	ui.add_child(hint)
	var controls := HBoxContainer.new()
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_top = -71
	controls.offset_bottom = -27
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 12)
	ui.add_child(controls)
	var pose := CheckButton.new()
	pose.text = "展开射击姿态"
	pose.custom_minimum_size.x = 163
	pose.toggled.connect(func(active: bool) -> void:
		_target_deployment = 1.0 if active else 0.0)
	controls.add_child(pose)
	var labels := ["斜前方", "侧面", "背面"]
	for i in labels.size():
		var button := Button.new()
		button.text = labels[i]
		button.custom_minimum_size.x = 80
		var view: Vector2 = VIEWS[i]
		button.pressed.connect(func() -> void:
			_set_view(view, FOCUS, 4.50))
		controls.add_child(button)
	var wheel_detail := Button.new()
	wheel_detail.text = "轮组特写"
	wheel_detail.custom_minimum_size.x = 96
	wheel_detail.pressed.connect(func() -> void:
		_set_view(Vector2(0.63, 0.10), Vector3(0, 1.32, -0.15), 3.17))
	controls.add_child(wheel_detail)
	var combat_preview := Button.new()
	combat_preview.text = "实战预览"
	combat_preview.custom_minimum_size.x = 96
	combat_preview.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/ranged/wheel_sentry_combat.tscn"))
	controls.add_child(combat_preview)


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("161e2b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a9bed6")
	env.ambient_light_energy = 0.50
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.34
	env.glow_hdr_threshold = 1.55
	env.ssao_enabled = true
	env.ssao_radius = 0.47
	env.ssao_intensity = 1.25
	var sky := Sky.new()
	var panels := ShaderMaterial.new()
	panels.shader = StudioSky
	sky.sky_material = panels
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("263341")
	floor_mat.roughness = 0.86
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(200, 200)
	MeshKit.add(self, floor_mesh, floor_mat, Vector3(0, -0.015, 0))
	var contact := PlaneMesh.new()
	contact.size = Vector2(1.65, 1.06)
	var contact_shadow := MeshKit.add(self, contact, Materials.contact_shadow(),
		Vector3(0, -0.010, 0))
	contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light(Vector3(-3.7, 6.8, -4.3), Color("ffe9d6"), 5.5, true)
	_light(Vector3(4.0, 4.3, -3.2), Color("bcd5ff"), 3.6)
	_light(Vector3(0.75, 4.6, 4.3), Color("cbdcff"), 5.8)
	_light(Vector3(-3.2, 2.25, 2.8), Color("daacff"), 2.3)


func _light(at: Vector3, color: Color, energy: float, shadows := false) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.light_specular = 0.57
	lamp.omni_range = 14.0
	lamp.omni_attenuation = 1.45
	lamp.shadow_enabled = shadows
	add_child(lamp)
