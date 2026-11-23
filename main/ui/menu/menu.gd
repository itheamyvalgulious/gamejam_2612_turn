extends Control

const Catalog = preload("res://core/level_catalog.gd")
const Style = preload("res://ui/turn_style.gd")
const COVER = preload("res://assets/ui/backgrounds/neon_alley.webp")

var _page: Control
var _status: Label
var _back: Button
var _picture: TextureRect
var _title: Label
var _description: Label
var _enter: Button
var _rows: Array[Button] = []
var _selected := 0

func _ready() -> void:
	theme = Style.theme()
	ThemeDB.fallback_font = theme.default_font
	_selected = TurnSession.selected_level_index
	_show_page()

func _unhandled_input(event: InputEvent) -> void:
	if _back != null and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back.pressed.emit()

func _show_page() -> void:
	if is_instance_valid(_page):
		remove_child(_page)
		_page.queue_free()
	_page = Control.new()
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_page)
	_back = null
	_status = null
	_rows.clear()
	if TurnSession.menu_page == TurnSession.MenuPage.HOME:
		_show_home()
	else:
		_show_catalog()

func _show_home() -> void:
	_add_backdrop(true)
	var column := _inset(72, 80, 64, 54)
	var title := Style.label("TURN", 133)
	var display := FontVariation.new()
	display.base_font = theme.default_font
	display.variation_embolden = 1.7
	display.spacing_glyph = -4
	title.add_theme_font_override("font", display)
	title.add_theme_color_override("font_shadow_color", Color(0.05, 0.33, 0.44, 0.55))
	title.add_theme_constant_override("shadow_offset_y", 4)
	column.add_child(title)

	var divider := ColorRect.new()
	divider.color = Style.FOCUS
	divider.custom_minimum_size = Vector2(72, 2)
	divider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(divider)

	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 278
	actions.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	actions.add_theme_constant_override("separation", 7)
	column.add_child(actions)
	var progress := TurnSession.progress
	var checkpoint := progress.resume_index()
	var level_select := Style.button("关卡选择", _go.bind(TurnSession.MenuPage.LEVELS))
	var primary: Button
	if progress.cleared_count() == Catalog.level_count():
		actions.add_child(Style.label("全部关卡已通关", 16, Style.FOCUS))
		primary = level_select
	else:
		var caption := "继续游戏" if checkpoint >= 0 else "开始游戏"
		primary = Style.button(caption, TurnSession.open_level.bind(maxi(checkpoint, 0)))
		actions.add_child(primary)
		if checkpoint >= 0:
			actions.add_child(Style.label("存档 · %s" % Catalog.get_entry(checkpoint)[0], 16, Style.MUTED))
	actions.add_child(level_select)
	primary.add_theme_stylebox_override("normal", Style.surface(Color("#173540"), Style.FOCUS))
	var settings := Style.button("设置", TurnSession.open_home_settings)
	actions.add_child(settings)
	actions.add_child(Style.button("退出游戏", get_tree().quit))
	_add_status(column)
	primary.grab_focus()

func _show_catalog() -> void:
	_add_backdrop(false)
	var column := _inset(54, 42, 54, 38)
	var header := HBoxContainer.new()
	var heading := Style.label("关卡选择", 42)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_back = Style.button("返回主菜单", _go.bind(TurnSession.MenuPage.HOME))
	header.add_child(_back)
	column.add_child(header)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	column.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 270
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)
	for index in Catalog.level_count():
		var caption := "%02d      %s" % [index + 1, Catalog.get_entry(index)[0]]
		if TurnSession.progress.is_cleared(index):
			caption += "  ·  已通关"
		var row := Style.button(caption)
		row.pressed.connect(row.grab_focus)
		row.focus_entered.connect(_select.bind(index))
		list.add_child(row)
		_rows.append(row)

	var preview := VBoxContainer.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_theme_constant_override("separation", 9)
	body.add_child(preview)
	var image_frame := Control.new()
	image_frame.clip_contents = true
	image_frame.custom_minimum_size.y = 240
	image_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_child(image_frame)
	_picture = _make_picture(COVER)
	image_frame.add_child(_picture)
	var fade := Style.shade(
		PackedColorArray([Color(0, 0, 0, 0), Color(0.015, 0.04, 0.06, 0.8)]),
		PackedFloat32Array([0.5, 1.0]), Vector2.DOWN)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image_frame.add_child(fade)
	_title = Style.label("", 38)
	_title.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_title.offset_left = 22
	_title.offset_top = -60
	image_frame.add_child(_title)
	_description = Style.label("", 19, Style.MUTED)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.y = 42
	preview.add_child(_description)
	_enter = Style.button("进入关卡", _enter_level)
	_enter.custom_minimum_size.x = 176
	_enter.size_flags_horizontal = Control.SIZE_SHRINK_END
	_enter.add_theme_stylebox_override("normal", Style.surface(Color("#173540"), Style.FOCUS))
	preview.add_child(_enter)
	for row in _rows:
		row.focus_neighbor_right = row.get_path_to(_enter)
	_add_status(column)
	_select(_selected)
	_rows[_selected].grab_focus()

func _select(index: int) -> void:
	var entry := Catalog.get_entry(index)
	_selected = index
	TurnSession.selected_level_index = index
	_title.text = entry[0]
	_description.text = Catalog.play_hint(index)
	_picture.texture = load("res://assets/ui/level_previews/%s.webp" % Catalog.level_id(index))
	_enter.focus_neighbor_left = _enter.get_path_to(_rows[index])
	for i in _rows.size():
		var style := Style.surface(Color("#142b35"), Style.FOCUS) if i == index else Style.surface(Color(Style.INK, 0.55))
		_rows[i].add_theme_stylebox_override("normal", style)

func _enter_level() -> void:
	TurnSession.open_level(_selected)

func _add_backdrop(home: bool) -> void:
	var picture := _make_picture(COVER)
	_page.add_child(picture)
	var colors := PackedColorArray([
		Color(0.022, 0.036, 0.054, 1.0),
		Color(0.022, 0.036, 0.054, 0.91 if home else 0.95),
		Color(0.022, 0.036, 0.054, 0.14 if home else 0.89),
		Color(0.022, 0.036, 0.054, 0.05 if home else 0.83),
	])
	var overlay := Style.shade(colors, PackedFloat32Array([0.0, 0.29, 0.64, 1.0]))
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.add_child(overlay)

func _make_picture(texture: Texture2D) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return picture

func _inset(left: int, top: int, right: int, bottom: int) -> VBoxContainer:
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.add_theme_constant_override("margin_left", left)
	inset.add_theme_constant_override("margin_top", top)
	inset.add_theme_constant_override("margin_right", right)
	inset.add_theme_constant_override("margin_bottom", bottom)
	_page.add_child(inset)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	inset.add_child(column)
	return column

func _go(page: int) -> void:
	TurnSession.menu_page = page
	_show_page()

func _add_status(parent: Container) -> void:
	_status = Style.label("", 16, Style.BLOCKED)
	_status.visible = TurnSession.progress_save_failed
	if _status.visible:
		_status.text = "关卡进度暂未保存，请检查存储空间后重试。"
	parent.add_child(_status)

func show_load_error() -> void:
	_status.text = "载入失败，请重试。"
	_status.show()
