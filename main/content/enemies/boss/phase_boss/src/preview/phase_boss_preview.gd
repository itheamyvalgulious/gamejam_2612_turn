extends Node3D

const Motion = preload("res://src/enemies/phase_boss/phase_boss_motion.gd")
const PhaseState = preload("res://src/enemies/phase_boss/phase_boss_state.gd")
const MotionFX = preload("res://src/preview/phase_boss_motion_fx.gd")
const Model = preload("res://scenes/phase_boss/phase_boss_model.tscn")
const Vesper = preload("res://scripts/mech/mech_rig.gd")
const Kit = preload("res://scripts/mech/mesh_kit.gd")
const PreviewFloor = preload("res://gfx/preview_floor.gdshader")
const StudioSky = preload("res://gfx/studio_sky.gdshader")
const ClassicGlass = preload("res://shaders/phase_preview_glass_classic.gdshader")
const PHASE_APPEARANCES := [
	["原版 · 青紫切面", null, 0.51, "青紫切片、离体薄片和运动残光。"],
	["折射隐身", preload("res://shaders/phase_preview_refraction.gdshader"), 0.99, "背后的景物穿过轮廓时会弯折，边缘有轻微色散。"],
	["棱镜反光", preload("res://shaders/phase_preview_prism.gdshader"), 0.85, "装甲保留体积，高光随观察角度变色。"],
	["青白光流", preload("res://shaders/phase_preview_lightflow.gdshader"), 0.84, "透明机身上有流动的青白扫描线。"],
	["玻璃棱镜", preload("res://shaders/phase_preview_glass.gdshader"), 0.99, "清透外壳，光线在不规则内部截面分色。转动视角可看到局部全内反射。"],
	["玻璃棱镜 · 初版", ClassicGlass, 0.99, "蓝色透光甲片带冷白高光，彩色折边随观察角度变化。"],
	["玻璃棱镜 · 无火彩", ClassicGlass, 0.99, "蓝色透明甲片，带背景折射和冷白反光。"],
]
const FOCUS := Vector3(0, 2.45, 0.54)
const WIDE := 10.4
enum ViewMode { NORMAL, PHASED, GAZE }
enum PhaseAppearance { ORIGINAL, REFRACTION, PRISM, LIGHTFLOW, GLASS, CLASSIC_GLASS, CLASSIC_GLASS_NO_FIRE }

var model: Node3D
var reference: Node3D
var camera: Camera3D
var overlay: CanvasLayer
var _angles := Vector2(1.04, 0.13)
var _focus := FOCUS
var _zoom := WIDE
var _jaw := 0.0
var _jaw_target := 0.0
var _motion: Motion
var _fx: MotionFX
var _clip_index := 0
var _time := 0.0
var _speed := 1.0
var _playing := false
var _effects := true
var _picker: OptionButton
var _play: Button
var _timeline: HSlider
var _time_label: Label
var _state_label: Label
var _camera_hint: Label
var _view_mode := ViewMode.NORMAL
var _mode_picker: OptionButton
var _appearance_picker: OptionButton
var _appearance := PhaseAppearance.ORIGINAL
var _phase_light: OmniLight3D
var _appearance_material: ShaderMaterial
var _glass_seeds_set := false
var _phase_state := PhaseState.new()
var _look_angles := Vector2.ZERO
var _phase_clock := 0.0
var _preview_shake := 0.0


func _ready() -> void:
	_build_stage()
	model = Model.instantiate()
	add_child(model)
	_motion = Motion.new(model)
	_fx = MotionFX.new()
	add_child(_fx)
	_fx.configure(model)
	reference = Vesper.new()
	reference.auto_step = false
	reference.position = Vector3(1.45, 0.0, -8.52)
	reference.rotation.y = -1.48
	add_child(reference)
	reference.hide()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 350.0
	add_child(camera)
	camera.make_current()
	frame_view(_angles.x, _angles.y, WIDE)
	_build_controls()
	_apply_motion()


func _process(delta: float) -> void:
	_phase_clock += delta
	if _appearance == PhaseAppearance.GLASS:
		_appearance_material.set_shader_parameter("flow_time", _phase_clock)
	_preview_shake = move_toward(_preview_shake, 0.0, delta * 5.4)
	if _view_mode == ViewMode.GAZE:
		var previous_stage := _phase_state.stage
		var before_age := _phase_state.age
		_phase_state.advance(delta, _boss_in_view())
		if _effects and _phase_state.stage == PhaseState.Stage.ENTERING:
			_fx.advance_audio("phase_enter", before_age if previous_stage == _phase_state.stage else 0.0, _phase_state.age)
		if _effects and _phase_state.stage == PhaseState.Stage.PHASED:
			_fx.advance_audio("phase_roar", before_age if previous_stage == _phase_state.stage else 0.0,
				minf(_phase_state.age, Motion.ROAR_DURATION))
	if _playing:
		var before := _time
		var boosted := _view_mode == ViewMode.PHASED or (_view_mode == ViewMode.GAZE and _phase_state.stage == PhaseState.Stage.PHASED)
		var transitioning := _view_mode == ViewMode.GAZE and (
			_phase_state.stage in [PhaseState.Stage.ENTERING, PhaseState.Stage.RETURNING] or _gaze_roaring())
		if not transitioning:
			_time = minf(_time + delta * _speed * (Motion.phase_rate(_clip_code()) if boosted else 1.0), _duration())
		if _effects:
			_fx.advance_audio(_clip_code(), before, _time)
			_advance_preview_shake(_clip_code(), before, _time)
		if _time >= _duration():
			_set_playing(false)
		_apply_motion()
	elif _clip_index == 0 and not is_equal_approx(_jaw, _jaw_target):
		_jaw = move_toward(_jaw, _jaw_target, delta * 2.5)
		_apply_motion()
	elif _view_mode != ViewMode.NORMAL:
		_apply_motion()


func _advance_preview_shake(clip: String, before: float, after: float) -> void:
	for foot in Motion.sprint_footfalls(clip, before, after):
		_preview_shake = maxf(_preview_shake, Motion.SPRINT_FOOT_SHAKES[foot])
	_preview_shake = maxf(_preview_shake, Motion.impact_shake(clip, before, after))


func _boss_in_view() -> bool:
	for part: Node3D in [model.chest, model.pelvis, model.head, model.tail_fin]:
		if camera.is_position_in_frustum(part.global_position):
			return true
	for leg: Dictionary in model.legs:
		if camera.is_position_in_frustum(leg["root"].global_position):
			return true
	return false


func _gaze_roaring() -> bool:
	return _phase_state.stage == PhaseState.Stage.PHASED and _phase_state.age < Motion.ROAR_DURATION


func _clip_code() -> String:
	return Motion.CLIPS[_clip_index][0]


func _duration() -> float:
	return Motion.CLIPS[_clip_index][2]


func _set_playing(active: bool) -> void:
	_playing = active
	if not active:
		_preview_shake = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	_play.text = "暂停" if active else ("重播" if _time >= _duration() else "播放")


func _select_clip(index: int, play: bool = true) -> void:
	_clip_index = index
	_preview_shake = 0.0
	_picker.select(index)
	_time = 0.0
	_timeline.max_value = _duration()
	_fx.prepare_clip(_motion, _clip_code())
	_set_playing(play)
	_apply_motion()


func _seek(seconds: float) -> void:
	_time = clampf(seconds, 0.0, _duration())
	_set_playing(false)
	_apply_motion()


func _toggle_play() -> void:
	if not _playing and _time >= _duration():
		_time = 0.0
		_apply_motion()
	_set_playing(not _playing)


func _apply_motion() -> void:
	var sample_time := fposmod(_phase_clock, 2.8) if _view_mode == ViewMode.GAZE and _clip_index == 0 and not _playing else _time
	var pose := _motion.sample(_clip_code(), sample_time)
	if _clip_index == 0:
		pose.jaw = _jaw
	if _clip_code() not in ["charge", "phase_enter", "phase_roar", "phase_exit", "cycle", "wake_intro"]:
		if _view_mode == ViewMode.PHASED:
			pose.phase = 1.0
			pose.fin = maxf(0.90, pose.fin)
			pose.signal_name = "持续虚化"
		elif _view_mode == ViewMode.GAZE:
			match _phase_state.stage:
				PhaseState.Stage.SOLID:
					pose.phase = 0.0
					pose.charge = _phase_state.charge
					pose.signal_name = "视野充能" if pose.charge > 0.0 else "实体"
				PhaseState.Stage.ENTERING:
					_motion.enter_phase(pose, _phase_state.age)
				PhaseState.Stage.PHASED:
					pose.phase = 1.0
					pose.fin = maxf(0.90, pose.fin)
					if _gaze_roaring():
						_motion.phase_roar(pose, _phase_state.age)
					else:
						pose.signal_name = "虚化  %.1f 秒" % (PhaseState.ACTIVE_TIME - _phase_state.age)
				PhaseState.Stage.RETURNING:
					_motion.return_from_phase(pose, _phase_state.age)
	_motion.apply(pose)
	var effect_time := _phase_clock if _view_mode != ViewMode.NORMAL else _time
	if _appearance == PhaseAppearance.LIGHTFLOW:
		_appearance_material.set_shader_parameter("phase_origin", model.global_position)
		_appearance_material.set_shader_parameter("phase_axis", model.global_basis.z.normalized())
	_update_phase_light(pose.phase, effect_time)
	_fx.show_pose(pose, _effects, effect_time, _playing, _appearance_material, PHASE_APPEARANCES[_appearance][2])
	_timeline.set_value_no_signal(_time)
	_time_label.text = "%.2f / %.2f 秒" % [_time, _duration()]
	_state_label.text = pose.signal_name
	if pose.charge > 0.0:
		_state_label.text += "  %d%%" % roundi(pose.charge * 100)
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if _view_mode == ViewMode.GAZE:
			_look_angles.x = clampf(_look_angles.x - event.relative.x * 0.008, -1.50, 1.50)
			_look_angles.y = clampf(_look_angles.y - event.relative.y * 0.008, -0.95, 0.95)
		else:
			_angles.x -= event.relative.x * 0.008
			_angles.y = clampf(_angles.y + event.relative.y * 0.008, -0.015, 1.19)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(3.4, _zoom * 0.90)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(20.0, _zoom / 0.90)
		_update_camera()


func frame_view(yaw: float, pitch: float, size: float, focus := FOCUS) -> void:
	_angles = Vector2(yaw, pitch)
	_look_angles = Vector2.ZERO
	_focus = focus
	_zoom = size
	_update_camera()


func _update_camera() -> void:
	var distance := cos(_angles.y)
	var direction := Vector3(sin(_angles.x) * distance, sin(_angles.y), -cos(_angles.x) * distance)
	var target := _focus + model.position
	var extra_size := 0.0
	var clip := _clip_code()
	var clip_time := _time
	if clip == "cycle" and _time >= Motion.PHASE_FIGHT_START and _time < Motion.PHASE_FIGHT_END:
		var slot := Motion.phase_sequence_slot(_time)
		if int(slot.x) < Motion.PHASE_SEQUENCE.size():
			clip = Motion.PHASE_SEQUENCE[int(slot.x)][0]
			clip_time = slot.y
	if clip == "pounce" and _zoom >= 7.0:
		var runway := smoothstep(0.12, 0.36, clip_time) * (1.0 - smoothstep(0.76, 1.20, clip_time))
		target.z -= runway * 3.5
		extra_size = runway * 3.65
	elif clip == "high_pounce" or clip == "run_pounce":
		var local := _time - (Motion.RUN_IN if clip == "run_pounce" else 0.0)
		target.y -= model.position.y * 0.52
		if _zoom >= 7.0:
			var runway := smoothstep(0.06, 0.30, local) * (1.0 - smoothstep(0.58, 1.49, local))
			var flight := smoothstep(Motion.LEAP_TAKEOFF, 0.89, local) * (1.0 - smoothstep(1.40, 1.83, local))
			target.z -= runway * 9.3
			extra_size = maxf(runway * 12.4, flight * 3.15)
	elif clip == "back_cannon" and _zoom >= 7.0:
		var deployed := smoothstep(Motion.CANNON_OPEN, Motion.CANNON_CHARGE, clip_time) * (1.0 - smoothstep(Motion.CANNON_RELEASE, Motion.CANNON_STOW, clip_time))
		var shot := smoothstep(Motion.CANNON_LOCK - 0.20, Motion.CANNON_FIRE, clip_time) * (1.0 - smoothstep(Motion.CANNON_RELEASE, Motion.CANNON_STOW, clip_time))
		target.y += deployed * 0.49
		target.z -= shot * 4.3 * absf(sin(_angles.x))
		extra_size = deployed * 0.75 + shot * 3.6
	elif (clip == "tail" or clip == "tail_left") and _zoom >= 7.0 and _clip_code() != "cycle":
		target.z += 1.65
		extra_size = maxf(0.0, 13.0 - _zoom)
	camera.position = target + direction * 27.0
	camera.look_at(target)
	if _view_mode == ViewMode.GAZE:
		camera.rotate_object_local(Vector3.UP, _look_angles.x)
		camera.rotate_object_local(Vector3.RIGHT, _look_angles.y)
	camera.size = _zoom + extra_size
	var shake := _preview_shake if _playing and _effects else 0.0
	camera.h_offset = sin(_phase_clock * 97.0) * shake * 0.10
	camera.v_offset = cos(_phase_clock * 111.0) * shake * 0.14


func _build_controls() -> void:
	overlay = CanvasLayer.new()
	add_child(overlay)
	var ui := Control.new()
	overlay.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = "折相"
	label.position = Vector2(34, 24)
	label.add_theme_font_size_override("font_size", 36)
	ui.add_child(label)
	_camera_hint = Label.new()
	_camera_hint.text = "左键拖动 · 滚轮缩放"
	_camera_hint.position = Vector2(36, 79)
	_camera_hint.modulate = Color("bbc8ce")
	ui.add_child(_camera_hint)
	var controls := HBoxContainer.new()
	ui.add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_top = -66
	controls.offset_bottom = -25
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 10)
	for view: Array in [["斜前方", 1.04, 0.13, WIDE], ["侧面", PI * 0.5, 0.18, 11.6], ["背面", 2.29, 0.29, WIDE], ["正面", 0.0, 0.12, 8.3]]:
		var button := Button.new()
		button.text = view[0]
		button.custom_minimum_size.x = 87
		controls.add_child(button)
		var yaw: float = view[1]
		var pitch: float = view[2]
		var size: float = view[3]
		button.pressed.connect(func() -> void: frame_view(yaw, pitch, size))
	var head_view := Button.new()
	head_view.text = "头部特写"
	head_view.custom_minimum_size.x = 107
	controls.add_child(head_view)
	head_view.pressed.connect(func() -> void: frame_view(0.82, 0.13, 4.8, Vector3(0, 2.59, -6.42)))
	var jaws := CheckButton.new()
	jaws.text = "张颚"
	controls.add_child(jaws)
	jaws.toggled.connect(func(active: bool) -> void:
		_select_clip(0, false)
		_jaw_target = 1.0 if active else 0.0)
	var scale_check := CheckButton.new()
	scale_check.text = "主角比例对照"
	controls.add_child(scale_check)
	scale_check.toggled.connect(func(active: bool) -> void:
		reference.visible = active
		if active:
			frame_view(1.31, 0.15, 12.6, Vector3(0, 2.96, -0.75)))

	_build_playback_controls(ui)
	_build_appearance_picker(ui)


func _build_appearance_picker(ui: Control) -> void:
	var row := HBoxContainer.new()
	ui.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.offset_left = -306
	row.offset_right = -30
	row.offset_top = 27
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "虚化外观"
	label.modulate = Color("bbc8ce")
	row.add_child(label)
	_appearance_picker = OptionButton.new()
	_appearance_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in PHASE_APPEARANCES.size():
		var option: Array = PHASE_APPEARANCES[index]
		_appearance_picker.add_item(option[0])
		_appearance_picker.get_popup().set_item_tooltip(index, option[3])
	_appearance_picker.tooltip_text = PHASE_APPEARANCES[0][3]
	_appearance_picker.item_selected.connect(_set_phase_appearance)
	row.add_child(_appearance_picker)


func _set_phase_appearance(index: int) -> void:
	_appearance = index as PhaseAppearance
	_appearance_picker.tooltip_text = PHASE_APPEARANCES[index][3]
	_appearance_material = null
	if PHASE_APPEARANCES[index][1] != null:
		_appearance_material = ShaderMaterial.new()
		_appearance_material.shader = PHASE_APPEARANCES[index][1]
		_appearance_material.render_priority = 2
		if _appearance_material.shader == ClassicGlass:
			_appearance_material.set_shader_parameter("spectral_fire", _appearance == PhaseAppearance.CLASSIC_GLASS)
	if _view_mode == ViewMode.NORMAL:
		_mode_picker.select(ViewMode.PHASED)
		_set_view_mode(ViewMode.PHASED)
	else:
		_apply_motion()
	if _appearance == PhaseAppearance.GLASS and not _glass_seeds_set:
		var parts := model.find_children("*", "MeshInstance3D", true, false)
		for i in parts.size():
			var part: MeshInstance3D = parts[i]
			part.set_instance_shader_parameter("part_seed", fposmod(float(i + 1) * 0.618033989, 1.0))
			var bounds := part.get_aabb()
			part.set_instance_shader_parameter("part_center", bounds.get_center())
			part.set_instance_shader_parameter("part_half_size", bounds.size * 0.5)
		_glass_seeds_set = true


func _build_playback_controls(ui: Control) -> void:
	var card := PanelContainer.new()
	ui.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = 30
	card.offset_right = -30
	card.offset_top = -162
	card.offset_bottom = -77
	var margin := MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12 if edge in ["left", "right"] else 7)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	stack.add_child(row)
	_picker = OptionButton.new()
	_picker.custom_minimum_size.x = 214
	for clip: Array in Motion.CLIPS:
		_picker.add_item(clip[1])
	_picker.item_selected.connect(_select_clip)
	row.add_child(_picker)
	_play = Button.new()
	_play.custom_minimum_size.x = 67
	_play.text = "播放"
	_play.pressed.connect(_toggle_play)
	row.add_child(_play)
	for step: int in [-1, 1]:
		var button := Button.new()
		button.text = "前一帧" if step < 0 else "后一帧"
		button.pressed.connect(func() -> void: _seek(_time + step / 60.0))
		row.add_child(button)
	var rate := OptionButton.new()
	for caption: String in ["1 倍速", "0.5 倍速", "0.25 倍速"]:
		rate.add_item(caption)
	rate.item_selected.connect(func(index: int) -> void: _speed = [1.0, 0.5, 0.25][index])
	row.add_child(rate)
	var effects := CheckButton.new()
	effects.text = "灯光与特效"
	effects.button_pressed = true
	effects.toggled.connect(func(active: bool) -> void:
		_effects = active
		_apply_motion())
	row.add_child(effects)
	_mode_picker = OptionButton.new()
	for caption: String in ["动作预览", "持续虚化", "视线测试"]:
		_mode_picker.add_item(caption)
	_mode_picker.item_selected.connect(_set_view_mode)
	row.add_child(_mode_picker)
	_state_label = Label.new()
	_state_label.modulate = Color("ade6ff")
	row.add_child(_state_label)
	var scrub := HBoxContainer.new()
	scrub.add_theme_constant_override("separation", 12)
	stack.add_child(scrub)
	_timeline = HSlider.new()
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.step = 0.001
	_timeline.max_value = _duration()
	_timeline.value_changed.connect(_seek)
	scrub.add_child(_timeline)
	_time_label = Label.new()
	_time_label.custom_minimum_size.x = 136
	_time_label.modulate = Color("ccd7de")
	scrub.add_child(_time_label)


func _set_view_mode(index: int) -> void:
	_view_mode = index as ViewMode
	_look_angles = Vector2.ZERO
	_phase_state = PhaseState.new()
	_camera_hint.text = "左键拖动转头 · 让折相进出画面" if _view_mode == ViewMode.GAZE else "左键拖动 · 滚轮缩放"
	if _view_mode == ViewMode.GAZE:
		_select_clip(0, false)
	else:
		_apply_motion()


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("18222e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c6d8e2")
	env.ambient_light_energy = 0.57
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.33
	env.glow_hdr_threshold = 1.48
	env.ssao_enabled = true
	env.ssao_radius = 0.60
	env.ssao_intensity = 1.05
	var sky := Sky.new()
	var panels := ShaderMaterial.new()
	panels.shader = StudioSky
	sky.sky_material = panels
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = PreviewFloor
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(650, 650)
	Kit.add(self, floor_mesh, floor_mat, Vector3(0, -0.018, 0))
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-66, -39, 0)
	key.light_energy = 1.24
	key.light_angular_distance = 4.0
	key.light_color = Color("ffebda")
	key.shadow_enabled = true
	add_child(key)
	_fill(Vector3(4, 4.7, -8.4), Color("bbf0ff"), 5.6)
	_fill(Vector3(-6.4, 7.8, 5.6), Color("acc6ff"), 6.5)
	_fill(Vector3(4.1, 6.0, 7.1), Color("ffe1ba"), 3.4)
	_phase_light = OmniLight3D.new()
	_phase_light.omni_range = 7.0
	_phase_light.omni_attenuation = 1.65
	_phase_light.hide()
	add_child(_phase_light)


func _update_phase_light(phase: float, time: float) -> void:
	_phase_light.visible = _effects and phase > 0.015 and _appearance in [PhaseAppearance.PRISM, PhaseAppearance.LIGHTFLOW]
	if not _phase_light.visible:
		return
	if _appearance == PhaseAppearance.PRISM:
		_phase_light.global_position = model.to_global(Vector3(0, 1.10, -0.82))
		_phase_light.light_color = Color("529ce9").lerp(Color("ad75e5"), 0.5 + 0.5 * sin(time * 1.4))
		_phase_light.light_energy = phase * 2.2
	else:
		var progress := fposmod(time * 0.72, 1.0)
		_phase_light.global_position = model.to_global(Vector3(0, 1.08, (progress - 0.5) / 0.071))
		_phase_light.light_color = Color("66dfff")
		_phase_light.light_energy = phase * 3.4 * sin(progress * PI)


func _fill(at: Vector3, color: Color, energy: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 18.0
	light.omni_attenuation = 1.45
	add_child(light)
