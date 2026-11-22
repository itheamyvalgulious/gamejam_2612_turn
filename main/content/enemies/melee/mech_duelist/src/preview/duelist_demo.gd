extends Node3D
## 第一人称动作演示，从踱步和低位蓄力到两刀连招和巡战。

const Arena = preload("res://src/arena/arena.gd")
const Model = preload("res://scenes/duelist/duelist_model.tscn")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const Brace = preload("res://src/enemies/duelist/duelist_ground_brace.gd")
const Lunge = preload("res://src/enemies/duelist/duelist_lunge.gd")
const ReturnCut = preload("res://src/enemies/duelist/duelist_return_cut.gd")
const Sequence = preload("res://src/enemies/duelist/duelist_sequence.gd")
const MechMaterials = preload("res://src/vesper/materials.gd")
const MouseLook = preload("res://src/game/mouse_look.gd")

const PACE_CENTER := Vector3(0, 0, 1.25)
const ATTACK_AT := Sequence.ATTACK_AT
const DEMO_END := Sequence.END
const ATTACK_RATE := Sequence.ATTACK_RATE
const SLOW_RATE := ATTACK_RATE * 0.25

var boss: Node3D
var player: PlayerUnit
var cam: GameCam
var _viewmodel: FpViewmodel
var _arena: Dictionary
var _boss_boundary: Dictionary
var _foot_shadows: Array[MeshInstance3D] = []
var _phase_label: Label
var _phase := ""
var _help_label: Label
var _mouse := MouseLook.new()
var _sequence := Sequence.new()
var _frozen := false
var _slow_motion := false
var _show_weapon := false


func _ready() -> void:
	get_window().title = "Turn · Boss 第一人称演示"
	Engine.max_fps = 60
	_arena = Arena.build("alley")
	add_child(_arena["node"])
	var world := _arena["node"].get_node("Env") as WorldEnvironment
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("a4b4cf")
	world.environment.ambient_light_energy = 0.34
	world.environment.tonemap_exposure = 1.08
	world.environment.adjustment_contrast = 1.07
	world.environment.ssao_intensity = 1.8
	var actor_cover: Array = _arena["cover"]
	_arena["cover"] = actor_cover.duplicate()
	_boss_boundary = {"c": Vector3.ZERO, "r": 0.98, "h": 6.2}
	_arena["cover"].append(_boss_boundary)
	_light(Vector3(-3.8, 6.4, 2.8), Color("fff2e4"), 6.3, true)
	_light(Vector3(4.2, 5.1, 3.7), Color("bbddff"), 4.3, false)
	_light(Vector3(0.0, 2.1, 3.1), Color("e8f4ff"), 3.2, false)
	_light(Vector3(0.0, 4.9, 9.4), Color("8598fc"), 2.8, false)
	boss = Model.instantiate() as Node3D
	add_child(boss)
	add_child(_sequence)
	_sequence.setup(boss, PACE_CENTER, actor_cover, _arena["bounds"])
	_build_foot_shadows()
	cam = GameCam.new()
	cam.follow_saved_mode = false
	cam.first_height_offset = GameCam.DUELIST_EYE_RISE
	add_child(cam)
	player = PlayerUnit.new()
	add_child(player)
	player.set_camera(cam)
	cam.set_rig(player.rig)
	_viewmodel = FpViewmodel.new()
	cam.camera.add_child(_viewmodel)
	_viewmodel.setup(player.PALETTE)
	_build_overlay()
	add_child(_mouse)
	_mouse.capture_changed.connect(_show_mouse_help)
	_show_mouse_help(false)
	Snd.set_arena(_arena)
	_reset()


func _reset() -> void:
	_frozen = false
	player.reset(Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
	cam.pitch = -0.16
	cam.set_first_person(true)
	player.rig.set_first_person_view(true, false)
	cam.snap(_arena)
	_sequence.seek(0.0, _focus())
	_refresh_boss()
	_sequence.sync_audio(_frozen, _attack_rate())
	_viewmodel.visible = _show_weapon
	_viewmodel.update(1.0 / 60.0, player)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	Snd.sync_params()
	if _mouse.can_move():
		player.step(dt, _arena)
	cam.step(dt, _arena)
	if _show_weapon:
		_viewmodel.update(dt, player)
	if not _frozen:
		_advance_boss(dt)
	_sequence.sync_audio(_frozen, _attack_rate())


func _advance_boss(dt: float) -> void:
	_sequence.advance(dt, _focus(), _attack_rate())

	_refresh_boss()


func _refresh_boss() -> void:
	var time := _sequence.time
	if time < Pace.DURATION:
		_phase = "侧身踱步"
	elif time < Pace.DURATION + Brace.CONTACT_TIME:
		_phase = "低位撑地"
	elif time < ATTACK_AT:
		_phase = "低位撑地蓄力"
	elif time < ATTACK_AT + Lunge.PALM_RELEASE:
		_phase = "出招红闪"
	elif time < Sequence.RETURN_AT:
		_phase = "第一刀 · 突进斜斩"
	elif time < Sequence.RETURN_AT + ReturnCut.TRAIL_START:
		_phase = "换重心 · 回斩预备"
	elif not _sequence.patrol.active:
		_phase = "第二刀 · 斜落回斩"
	elif not _sequence.normal_pose.is_empty():
		if _sequence.normal_time < _sequence.normal_move.WINDUP_END:
			_phase = "出刀预备 · " + _sequence.normal_move.DISPLAY_NAME
		else:
			_phase = "普通攻击 · " + _sequence.normal_move.DISPLAY_NAME
	else:
		_phase = _sequence.patrol.motion_label()
	_refresh_phase_label()
	_boss_boundary["c"] = boss.position
	for i in _foot_shadows.size():
		var ankle := boss.legs[i]["ankle"] as Node3D
		var sole := ankle.to_global(Vector3(0, -Pace.SOLE_HEIGHT, -0.10))
		var forward := -ankle.global_basis.z.slide(Vector3.UP)
		_foot_shadows[i].position = Vector3(sole.x, _arena["floor_y"] + 0.016, sole.z)
		_foot_shadows[i].rotation.y = atan2(-forward.x, -forward.z)
		_foot_shadows[i].transparency = smoothstep(0.03, 0.35, sole.y - _arena["floor_y"])


func _refresh_phase_label() -> void:
	_phase_label.text = _phase
	if _slow_motion:
		_phase_label.text += " · 慢放"
	if _frozen:
		_phase_label.text += " · 已定格"


func _focus() -> Vector3:
	var target: Vector3 = player.rig.global_position
	target.y = cam.camera.global_position.y - cam.first_height_offset
	return target


func _attack_rate() -> float:
	return SLOW_RATE if _slow_motion else ATTACK_RATE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse.is_captured():
		cam.look(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _mouse.is_captured():
		_mouse.capture()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				_mouse.release()
			KEY_F11:
				_mouse.toggle_fullscreen()
			KEY_TAB:

				_frozen = not _frozen
				if _frozen:
					_refresh_phase_label()
				else:
					_refresh_boss()
				_sequence.sync_audio(_frozen, _attack_rate())
			KEY_V:
				_slow_motion = not _slow_motion
				_refresh_phase_label()
				_sequence.sync_audio(_frozen, _attack_rate())
			KEY_R:
				_reset()
			KEY_H:
				_show_weapon = not _show_weapon
				_viewmodel.visible = _show_weapon
			KEY_G:
				_sequence.seek(Pace.DURATION + Brace.HOLD_TIME, _focus())
				_frozen = true
				_refresh_boss()
				_sequence.sync_audio(_frozen, _attack_rate())


func _light(at: Vector3, tint: Color, energy: float, shadows: bool) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = 13.0
	light.light_specular = 0.38 if shadows else 0.15
	light.shadow_enabled = shadows
	add_child(light)


func _build_foot_shadows() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.80, 1.18)
	for leg: Dictionary in boss.legs:
		var shadow := MeshInstance3D.new()
		shadow.mesh = mesh
		shadow.material_override = MechMaterials.contact_shadow()
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shadow)
		_foot_shadows.append(shadow)


func _build_overlay() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	_phase_label = Label.new()
	_phase_label.position = Vector2(29, 23)
	_phase_label.add_theme_font_size_override("font_size", 23)
	_phase_label.add_theme_color_override("font_shadow_color", Color("11232d"))
	_phase_label.add_theme_constant_override("shadow_offset_y", 2)
	_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_phase_label)
	_help_label = Label.new()
	_help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_help_label.offset_bottom = -20
	_help_label.offset_top = -46
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_label.add_theme_font_size_override("font_size", 17)
	_help_label.add_theme_color_override("font_shadow_color", Color("0c141c"))
	_help_label.add_theme_constant_override("shadow_offset_y", 2)
	_help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_help_label)


func _show_mouse_help(captured: bool) -> void:
	var mouse_help := "WASD 移动 · 鼠标转头 · Esc 释放鼠标" if captured else "点击画面控制视角"
	_help_label.text = mouse_help + "  ·  F11 全屏／窗口  ·  Tab 定格／继续  ·  G 跳到蓄力末段  ·  V 慢放  ·  H 显示主角刀  ·  R 重播"
