extends Control

const Catalog = preload("res://core/level_catalog.gd")
const Style = preload("res://ui/turn_style.gd")
const Wordmark = preload("res://ui/menu/wordmark.gd")
const COVER = preload("res://assets/ui/level_previews/rain_plaza.webp")

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
	if "--bench" in OS.get_cmdline_user_args():
		var bench := preload("res://tools/bench.gd").new()
		bench.name = "BenchDriver"
		get_tree().root.add_child.call_deferred(bench)
	if "--play-bench" in OS.get_cmdline_user_args():
		var play_bench := preload("res://tools/play_bench.gd").new()
		play_bench.name = "PlayBenchDriver"
		get_tree().root.add_child.call_deferred(play_bench)
	if "--repro" in OS.get_cmdline_user_args():
		var repro = load("res://tools/repro.gd").new()
		repro.name = "ReproDriver"
		get_tree().root.add_child.call_deferred(repro)
	if "--repro-stab" in OS.get_cmdline_user_args():
		var repro_stab = load("res://tools/repro_stab.gd").new()
		repro_stab.name = "ReproStab"
		get_tree().root.add_child.call_deferred(repro_stab)
	if "--repro3" in OS.get_cmdline_user_args():
		var repro3 = load("res://tools/repro3.gd").new()
		repro3.name = "Repro3"
		get_tree().root.add_child.call_deferred(repro3)
	if "--repro2" in OS.get_cmdline_user_args():
		var repro2 = load("res://tools/repro2.gd").new()
		repro2.name = "Repro2"
		get_tree().root.add_child.call_deferred(repro2)
	theme = Style.theme()
	ThemeDB.fallback_font = theme.default_font
	_selected = TurnSession.selected_level_index
	_show_page()
	_signal_startup_ready()


func _signal_startup_ready() -> void:
	var ready_file := OS.get_environment("TURN_STARTUP_READY_FILE")
	if ready_file.is_empty():
		return
	OS.unset_environment("TURN_STARTUP_READY_FILE")
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	var file := FileAccess.open(ready_file, FileAccess.WRITE)
	if file != null:
		file.store_8(1)

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
	var column := _inset(79, 84, 58, 58)
	column.add_child(Wordmark.new())
	var divider := Style.shade(
		PackedColorArray([Style.FOCUS, Color("#a671cc"), Color("#a671cc00")]),
		PackedFloat32Array([0.0, 0.38, 1.0]))
	divider.custom_minimum_size = Vector2(300, 2)
	divider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(divider)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(space)

	var actions := Control.new()
	actions.custom_minimum_size = Vector2(440, 232)
	actions.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(actions)
	var progress := TurnSession.progress
	var checkpoint := progress.resume_index()
	var level_select := Style.button("关卡选择", _go.bind(TurnSession.MenuPage.LEVELS))
	var primary: Button
	var checkpoint_text := ""
	if progress.cleared_count() == Catalog.level_count():
		primary = level_select
		checkpoint_text = "全部关卡已通关"
	else:
		var caption := "继续游戏" if checkpoint >= 0 else "开始游戏"
		primary = Style.button(caption, TurnSession.open_level.bind(maxi(checkpoint, 0)))
		if checkpoint >= 0:
			checkpoint_text = "存档 · %s" % Catalog.get_entry(checkpoint)[0]
	_place_action(actions, primary, Rect2(0, 0, 359, 68))
	if primary != level_select:
		_place_action(actions, level_select, Rect2(28, 105, 203, 49))
	primary.add_theme_font_size_override("font_size", 23)
	primary.add_theme_stylebox_override("normal", Style.primary_surface())
	if not checkpoint_text.is_empty():
		var checkpoint_label := Style.label(checkpoint_text, 15, Style.MUTED)
		checkpoint_label.position = Vector2(27, 73)
		actions.add_child(checkpoint_label)
	var settings := Style.button("设置", TurnSession.open_home_settings)
	var exit := Style.button("退出游戏", get_tree().quit)
	var settings_box := Rect2(244, 117, 130, 49) if primary != level_select else Rect2(28, 105, 154, 49)
	_place_action(actions, settings, settings_box)
	_place_action(actions, exit, Rect2(56, 174, 155, 47))
	primary.focus_neighbor_bottom = primary.get_path_to(settings if primary == level_select else level_select)
	if primary != level_select:
		level_select.focus_neighbor_top = level_select.get_path_to(primary)
		level_select.focus_neighbor_right = level_select.get_path_to(settings)
		settings.focus_neighbor_left = settings.get_path_to(level_select)
		level_select.focus_neighbor_bottom = level_select.get_path_to(exit)
	_add_status(column)
	primary.grab_focus()

func _place_action(parent: Control, action: Button, bounds: Rect2) -> void:
	action.position = bounds.position
	action.size = bounds.size
	parent.add_child(action)

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
		PackedColorArray([Color("#15102100"), Color("#151021ed")]),
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
	_enter.add_theme_stylebox_override("normal", Style.primary_surface())
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
	_picture.texture = load("res://assets/ui/level_previews/%s.webp" % Catalog.preview_id(index))
	_enter.focus_neighbor_left = _enter.get_path_to(_rows[index])
	for i in _rows.size():
		var style := Style.active_surface() if i == index else Style.surface()
		_rows[i].add_theme_stylebox_override("normal", style)

func _enter_level() -> void:
	TurnSession.open_level(_selected)

func _add_backdrop(home: bool) -> void:
	var picture := _make_picture(COVER)
	_page.add_child(picture)
	var colors := PackedColorArray([
		Color("#221231d9") if home else Color("#13101fec"),
		Color("#28193991") if home else Color("#171122e8"),
		Color("#21193612") if home else Color("#171122d9"),
		Color("#130f270f") if home else Color("#151023ce"),
	])
	var overlay := Style.shade(colors, PackedFloat32Array([0.0, 0.29, 0.64, 1.0]))
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.add_child(overlay)
	if home:
		var floor := Style.shade(
			PackedColorArray([Color("#100d2200"), Color("#100d2299"), Color("#100d22ed")]),
			PackedFloat32Array([0.37, 0.72, 1.0]), Vector2.DOWN)
		floor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_page.add_child(floor)
		var edge_marks := Control.new()
		edge_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		edge_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page.add_child(edge_marks)
		edge_marks.draw.connect(func() -> void:
			edge_marks.draw_line(Vector2(79, 46), Vector2(92, 46), Color("#efa4e5aa"), 2.0)
			edge_marks.draw_line(Vector2(99, 46), Vector2(133, 46), Color("#b88bd194"), 1.0)
			var corner := edge_marks.size - Vector2(43, 38)
			edge_marks.draw_polyline(PackedVector2Array([
				corner - Vector2(87, 0), corner - Vector2(22, 0), corner - Vector2(0, 18),
				corner - Vector2(0, 73),
			]), Color("#b18cd18e"), 1.0, true))

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
