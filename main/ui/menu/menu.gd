extends Control

const Catalog = preload("res://core/level_catalog.gd")
const COVER = preload("res://assets/ui/backgrounds/neon_alley.webp")
const ACCENT := Color("#71f2ea")
const INK := Color("#08121d")
const WHITE := Color("#effdff")

var _page: Control
var _column: VBoxContainer
var _status: Label
var _back: Button


func _ready() -> void:
	theme = _menu_theme()
	ThemeDB.fallback_font = theme.default_font
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
	var at_home := TurnSession.menu_page == TurnSession.MenuPage.HOME
	_add_backdrop(at_home)
	if at_home:
		_show_home()
	else:
		_show_catalog()


func _add_backdrop(at_home: bool) -> void:
	var picture := _picture(COVER)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.add_child(picture)
	var wash := Gradient.new()
	wash.colors = PackedColorArray([
		Color(0.018, 0.036, 0.06, 0.99),
		Color(0.018, 0.036, 0.06, 0.82 if at_home else 0.95),
		Color(0.018, 0.036, 0.06, 0.08 if at_home else 0.82),
		Color(0.018, 0.036, 0.06, 0.13 if at_home else 0.90),
	])
	wash.offsets = PackedFloat32Array([0.0, 0.31, 0.79, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = wash
	texture.fill_to = Vector2.RIGHT
	var shadow := _picture(texture)
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.add_child(shadow)


func _show_home() -> void:
	_frame(63, 73, 63, 62)
	var logo := _label("TURN", 116)
	var display_font := FontVariation.new()
	display_font.base_font = theme.default_font
	display_font.variation_embolden = 1.2
	logo.add_theme_font_override("font", display_font)
	logo.add_theme_color_override("font_shadow_color", Color(0.05, 0.6, 0.65, 0.35))
	logo.add_theme_constant_override("shadow_offset_y", 4)
	logo.add_theme_constant_override("shadow_offset_x", 3)
	_column.add_child(logo)
	var space := Control.new()
	space.custom_minimum_size.y = 18
	_column.add_child(space)

	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 252
	actions.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	actions.add_theme_constant_override("separation", 10)
	_column.add_child(actions)
	var start := _button("开始游戏", TurnSession.open_level.bind(0), true)
	actions.add_child(start)
	actions.add_child(_button("关卡选择", _go.bind(TurnSession.MenuPage.LEVELS)))
	actions.add_child(_button("退出游戏", get_tree().quit))
	_column.add_child(_label("F11 全屏 / 窗口", 15, Color("#a9becb")))
	start.grab_focus()


func _show_catalog() -> void:
	_frame(48, 29, 48, 29)
	_header("关卡选择", "返回主菜单", _go.bind(TurnSession.MenuPage.HOME))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for index in Catalog.level_count():
		grid.add_child(_card(index, TurnSession.open_level.bind(index)))
	grid.get_child(0).grab_focus()


func _frame(left: int, top: int, right: int, bottom: int) -> void:
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.add_theme_constant_override("margin_left", left)
	inset.add_theme_constant_override("margin_top", top)
	inset.add_theme_constant_override("margin_right", right)
	inset.add_theme_constant_override("margin_bottom", bottom)
	_page.add_child(inset)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 14)
	inset.add_child(_column)


func _header(title: String, back: String, action: Callable) -> void:
	var row := HBoxContainer.new()
	_column.add_child(row)
	var heading := _label(title, 38)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	_back = _button(back, action, true)
	_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_back)


func _card(index: int, action: Callable) -> Button:
	var entry := Catalog.get_entry(index)
	var card := Button.new()
	card.text = entry[0]
	card.add_theme_color_override("font_color", Color.TRANSPARENT)
	card.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	card.add_theme_color_override("font_focus_color", Color.TRANSPARENT)
	card.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	card.custom_minimum_size = Vector2(170, 150)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	card.tooltip_text = entry[1]
	card.pressed.connect(action)
	var picture := _picture(_art(entry[5]))
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.offset_left = 1
	picture.offset_right = -1
	picture.offset_top = 1
	picture.offset_bottom = -1
	card.add_child(picture)
	var caption := ColorRect.new()
	caption.color = Color(0.018, 0.034, 0.052, 0.94)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -40
	card.add_child(caption)
	var title := _label(entry[0], 20)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.position = Vector2(13, 4)
	caption.add_child(title)
	var outline := Panel.new()
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.add_theme_stylebox_override("panel", _surface(Color.TRANSPARENT, ACCENT))
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outline.hide()
	card.add_child(outline)
	var highlight := func() -> void:
		outline.show()
	var clear := func() -> void:
		outline.visible = card.has_focus() or card.get_global_rect().has_point(card.get_global_mouse_position())
	card.mouse_entered.connect(highlight)
	card.mouse_exited.connect(clear)
	card.focus_entered.connect(highlight)
	card.focus_exited.connect(clear)
	return card


func _picture(texture: Texture2D) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func _art(image_name: String) -> Texture2D:
	var path := "res://assets/ui/level_previews/" + image_name + ".webp"
	return load(path) as Texture2D if ResourceLoader.exists(path) else COVER


func _label(content: String, size: int, color := WHITE) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(title: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 46
	button.pressed.connect(action)
	if primary:
		for style: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(style, INK)
		button.add_theme_stylebox_override("normal", _surface(ACCENT, ACCENT))
		button.add_theme_stylebox_override("hover", _surface(Color("#d5fffc"), ACCENT))
		button.add_theme_stylebox_override("pressed", _surface(Color("#43bfb7"), ACCENT))
	return button


func _surface(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


func _menu_theme() -> Theme:
	var skin := Theme.new()
	skin.default_font = preload("res://runtime/fonts/act/ui_font.tres")
	skin.default_font_size = 19
	skin.set_color("font_color", "Button", Color("#e6f1fa"))
	skin.set_color("font_hover_color", "Button", Color.WHITE)
	skin.set_color("font_focus_color", "Button", Color.WHITE)
	skin.set_stylebox("normal", "Button", _surface(Color(0.04, 0.08, 0.12, 0.76), Color("#365361")))
	skin.set_stylebox("hover", "Button", _surface(Color("#193641"), ACCENT))
	skin.set_stylebox("pressed", "Button", _surface(Color("#102a34"), ACCENT))
	skin.set_stylebox("focus", "Button", _surface(Color.TRANSPARENT, Color("#efffff")))
	return skin


func _go(page: int) -> void:
	TurnSession.menu_page = page
	_show_page()


func _show_status(message: String) -> void:
	if _status == null:
		_status = _label("", 16, ACCENT)
		_column.add_child(_status)
	_status.text = message


func show_load_error() -> void:
	_show_status("载入失败。请重新选择一次。")
