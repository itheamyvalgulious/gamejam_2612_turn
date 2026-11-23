extends CanvasLayer

const Style = preload("res://ui/turn_style.gd")
const TRACK_WIDTH := 286.0
const PULSE_WIDTH := 74.0

var level_title := ""
var _pulse: Control
var _clock := 0.30


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	var background := Style.shade(
		PackedColorArray([Style.INK, Color("#221536"), Color("#171325")]),
		PackedFloat32Array([0.0, 0.62, 1.0]), Vector2(1.0, 0.65))
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.theme = Style.theme()
	background.add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 13)
	center.add_child(column)
	var title := Style.label(level_title, 38)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var status := Style.label("正在载入关卡", 16, Style.MUTED)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status)

	var track := ColorRect.new()
	track.color = Color("#4b3658")
	track.clip_contents = true
	track.custom_minimum_size = Vector2(TRACK_WIDTH, 3)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(track)
	_pulse = Style.shade(
		PackedColorArray([Color(Style.FOCUS, 0.0), Style.FOCUS, Color(Style.FOCUS, 0.0)]),
		PackedFloat32Array([0.0, 0.55, 1.0]))
	_pulse.size = Vector2(PULSE_WIDTH, 3)
	track.add_child(_pulse)


func _process(delta: float) -> void:
	_clock = fposmod(_clock + delta, 1.1)
	_pulse.position.x = lerpf(-PULSE_WIDTH, _pulse.get_parent_control().size.x, _clock / 1.1)
