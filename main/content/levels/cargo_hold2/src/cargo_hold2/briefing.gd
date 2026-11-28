extends CanvasLayer

const Style = preload("res://ui/turn_style.gd")

var _fade: ColorRect
var _card: PanelContainer
var _speaker: Label
var _line: Label
var _instruction: Label
var _interaction: Label
var _fade_age := 0.0
var _line_left := 0.0
var _queued_lines: Array[String] = []
var _queued_times: Array[float] = []


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
	_fit_dialogue()
	get_viewport().size_changed.connect(_fit_dialogue)
	_card.add_theme_stylebox_override("panel", Style.surface(Color("171326eb"), Color("856995"), Style.FOCUS))
	column.add_child(_card)
	var dialogue := VBoxContainer.new()
	dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue.add_theme_constant_override("separation", 2)
	_card.add_child(dialogue)
	_speaker = Style.label("NOVA", 13, Style.FOCUS)
	dialogue.add_child(_speaker)
	_line = Style.label("", 19)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue.add_child(_line)
	_instruction = Style.label("", 18, Style.BATTLE_CUE)
	_instruction.add_theme_color_override("font_outline_color", Color("171326"))
	_instruction.add_theme_constant_override("outline_size", 4)
	_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_instruction)
	_instruction.hide()
	var interaction_area := CenterContainer.new()
	interaction_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_area.anchor_right = 1.0
	interaction_area.anchor_top = 0.79
	interaction_area.anchor_bottom = 0.86
	interaction_area.theme = frame.theme
	add_child(interaction_area)
	_interaction = Style.label("", 20, Color("e4e5e8"))
	_interaction.add_theme_color_override("font_outline_color", Color("1b1d21"))
	_interaction.add_theme_constant_override("outline_size", 4)
	_interaction.hide()
	interaction_area.add_child(_interaction)


func _fit_dialogue() -> void:
	_card.custom_minimum_size.x = clampf(get_viewport().get_visible_rect().size.x * 0.62, 330.0, 850.0)


func reset() -> void:
	_fade_age = 0.0
	_fade.color = Color(0.045, 0.03, 0.08, 0.64)
	_fade.show()
	_card.hide()
	_queued_lines.clear()
	_queued_times.clear()
	_line_left = 0.0
	set_instruction("")
	set_interaction("")


func speak(text: String, duration: float, emergency := false) -> void:
	_speaker.text = "舰内警报" if emergency else "NOVA"
	_speaker.add_theme_color_override("font_color", Style.DANGER if emergency else Style.FOCUS)
	_queued_lines.clear()
	_queued_times.clear()
	# Newlines identify the authored turns. A period followed by a space is a sentence boundary.
	var sentences := text.replace(". ", ".\n").split("\n", false)
	var weight := 0.0
	for sentence in sentences:
		weight += float(maxi(sentence.length(), 10))
	for sentence in sentences:
		_queued_lines.append(sentence)
		_queued_times.append(duration * float(maxi(sentence.length(), 10)) / weight)
	_show_next_line()


func _show_next_line() -> void:
	if _queued_lines.is_empty():
		_card.hide()
		_instruction.visible = not _instruction.text.is_empty()
		return
	_line.text = _queued_lines.pop_front()
	_line_left = _queued_times.pop_front()
	_card.show()
	_instruction.hide()


func set_instruction(text: String) -> void:
	_instruction.text = text
	_instruction.visible = not _card.visible and not text.is_empty()


func step(dt: float) -> void:
	if _fade.visible:
		_fade_age += dt
		_fade.color.a = 0.64 * (1.0 - smoothstep(0.0, 1.15, _fade_age))
		if _fade_age >= 1.15:
			_fade.hide()
	if _card.visible:
		_line_left -= dt
		if _line_left <= 0.0:
			_show_next_line()

func set_interaction(text: String) -> void:
	_interaction.text = text
	_interaction.visible = not text.is_empty()
