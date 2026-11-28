extends Node
## From the lab control to the story's playable flashback.

const DURATION := 5.20
const DARK := Color(0.021, 0.034, 0.050)

var running := false
var _time := 0.0
var _shot: Camera3D
var _overlay: CanvasLayer
var _fade: ColorRect
var _title: VBoxContainer
var _play_camera: Camera3D
var _hud: CanvasLayer
var _should_restore_hud := false
var _initial_view := Transform3D.IDENTITY
var _room: Dictionary = {}
var _button_y := 0.0
var _memory_stage := false


func reset(control: Dictionary) -> void:
	if running and is_instance_valid(_play_camera):
		_play_camera.make_current()
	if running and _should_restore_hud and is_instance_valid(_hud):
		_hud.show()
	if _overlay != null:
		_overlay.hide()
	if _shot != null and _room.has("indicator"):
		_room["indicator"].position.y = _button_y
	running = false
	_time = 0.0
	_memory_stage = false
	control["arming"].text = "待设定"
	control["arming"].modulate = Color("ebba8a")
	control["memory_label"].text = "资料索引"
	for slot: MeshInstance3D in control["memory_slots"]:
		slot.material_override = control["slot_off"]


func start(first_person: Transform3D, play_camera: Camera3D, hud: CanvasLayer,
		control: Dictionary) -> void:
	if _shot == null:
		_create_view()
	_room = control
	_button_y = _room["indicator"].position.y
	_initial_view = first_person
	_play_camera = play_camera
	_hud = hud
	_should_restore_hud = is_instance_valid(hud) and hud.visible
	if _should_restore_hud:
		hud.hide()
	_time = 0.0
	_memory_stage = false
	running = true
	_shot.global_transform = first_person
	_shot.fov = clampf(play_camera.fov, 56.0, 82.0)
	_shot.make_current()
	_fade.color = Color(DARK, 0.0)
	_title.modulate.a = 0.0
	_overlay.show()
	_room["arming"].text = "自爆已设定"
	_room["arming"].modulate = Color("ffb197")
	_room["alarm"].show()
	_room["indicator"].material_override = _room["active_material"]


func step(dt: float) -> bool:
	_time = minf(DURATION, _time + dt)
	_room["indicator"].position.y = _button_y - 0.074 * (1.0 - smoothstep(0.12, 0.86, _time))
	var settled: Vector3 = _room["film_camera"]
	var switch: Vector3 = _room["switch_aim"]
	var screen: Vector3 = _room["screen_aim"]
	var rise := smoothstep(1.10, 2.65, _time)
	var push := smoothstep(1.4, 3.7, _time)
	var position := settled + Vector3(0.55, 0.56, -1.20) * push
	var aim := switch.lerp(screen, rise)
	var composed := Transform3D(Basis.IDENTITY, position).looking_at(aim, Vector3.UP)
	_shot.global_transform = _initial_view.interpolate_with(composed, smoothstep(0.0, 0.67, _time))
	_shot.fov = lerpf(clampf(_play_camera.fov, 56.0, 82.0), 58.0, smoothstep(0.1, 2.52, _time))

	if not _memory_stage and _time >= 2.05:
		_memory_stage = true
		_room["memory_label"].text = "题解波形"
		Snd.play_at("ping", screen, {"gain": 0.43})
	var slots: Array = _room["memory_slots"]
	var active := clampi(floori((_time - 2.05) * 4.7), 0, slots.size())
	for i in active:
		slots[i].material_override = _room["slot_on"]
	if active == slots.size():
		_room["memory_label"].text = "红眼列装"
	var darkening := smoothstep(3.05, 3.97, _time)
	_fade.color = Color(DARK, darkening)
	_title.modulate.a = smoothstep(3.82, 4.22, _time)
	return _time >= DURATION


func _create_view() -> void:
	_shot = Camera3D.new()
	_shot.near = 0.12
	add_child(_shot)
	_overlay = CanvasLayer.new()
	_overlay.layer = 58
	add_child(_overlay)
	var bars := Control.new()
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bars)
	_letterbox(bars, 0.0, 0.082)
	_letterbox(bars, 0.918, 1.0)
	_fade = ColorRect.new()
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bars.add_child(_fade)
	var anchor := CenterContainer.new()
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bars.add_child(anchor)
	_title = VBoxContainer.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_constant_override("separation", 12)
	anchor.add_child(_title)
	_title.add_child(_card_text("闪回", 22, Color("95bdc3")))
	_title.add_child(_card_text("地球 · 快递柜", 43, Color("e6eeef")))


func _letterbox(parent: Control, top: float, bottom: float) -> void:
	var strip := ColorRect.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.color = Color(0.016, 0.023, 0.030)
	parent.add_child(strip)
	strip.anchor_right = 1.0
	strip.anchor_top = top
	strip.anchor_bottom = bottom


func _card_text(caption: String, size: int, tint: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", tint)
	return label
