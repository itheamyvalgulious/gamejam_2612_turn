extends CanvasLayer

const Style = preload("res://ui/turn_style.gd")

var _fade: ColorRect
var _card: PanelContainer
var _speaker: Label
var _line: Label
var _instruction: Label
var _fade_age := 0.0
var _line_left := 0.0


func _ready() -> void:
	layer = 43
	_fade = ColorRect.new()
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)

	var frame := MarginContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	frame.offset_top = -182
	frame.offset_bottom = -49
	frame.add_theme_constant_override("margin_left", 37)
	frame.add_theme_constant_override("margin_right", 37)
	frame.theme = Style.theme()
	add_child(frame)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	frame.add_child(column)

	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card.custom_minimum_size.x = 415
	_card.add_theme_stylebox_override("panel", Style.surface(Color("171326eb"), Color("856995"), Style.FOCUS))
	column.add_child(_card)
	var dialogue := VBoxContainer.new()
	dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue.add_theme_constant_override("separation", 2)
	_card.add_child(dialogue)
	_speaker = Style.label("NOVA", 13, Style.FOCUS)
	dialogue.add_child(_speaker)
	_line = Style.label("", 19)
	dialogue.add_child(_line)
	_instruction = Style.label("", 16, Style.BATTLE_CUE)
	_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_instruction)


func reset() -> void:
	_fade_age = 0.0
	_fade.color = Color(0.045, 0.03, 0.08, 0.64)
	_fade.show()
	_card.hide()
	_instruction.text = ""


func speak(text: String, duration: float, emergency := false) -> void:
	_speaker.text = "舰内警报" if emergency else "NOVA"
	_speaker.add_theme_color_override("font_color", Style.DANGER if emergency else Style.FOCUS)
	_line.text = text
	_line_left = duration
	_card.show()


func set_instruction(text: String) -> void:
	_instruction.text = text


func step(dt: float) -> void:
	if _fade.visible:
		_fade_age += dt
		_fade.color.a = 0.64 * (1.0 - smoothstep(0.0, 1.15, _fade_age))
		if _fade_age >= 1.15:
			_fade.hide()
	if _card.visible:
		_line_left -= dt
		if _line_left <= 0.0:
			_card.hide()
