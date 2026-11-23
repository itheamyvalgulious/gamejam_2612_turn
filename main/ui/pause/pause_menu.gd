extends CanvasLayer

signal resume_requested
signal restart_requested
signal exit_requested
signal setting_changed(key: String, value: Variant)

enum Page { PAUSE, SETTINGS, HELP, CONFIRM }
enum Section { DISPLAY, AUDIO, CONTROLS }

const Style = preload("res://ui/turn_style.gd")
const TEXT := Style.TEXT
const MUTED := Style.MUTED
const FOCUS := Style.FOCUS
const PANEL_WIDTH := 494
const BIND_LABELS := {
	"attack_light": "轻击 / 方向斩",
	"parry": "格挡 / 弹反",
	"cam_mode": "切换第一 / 第三人称",
	"fp_mask": "第一人称视野遮罩",
	"pause": "暂停",
	"restart": "重新开始本关",
}
const ADVANCED_ACTIONS := ["tuning", "next_level", "hud_toggle", "audio_test", "replay_toggle"]

var level_title := ""
var level_hint := ""
var battle_active := false
var params: Node
var binds: Node
var home_settings := false
var options: Dictionary = {}

var _page := Page.PAUSE
var _section := Section.DISPLAY
var _confirm_exit := false
var _advanced_controls := false
var _capturing := ""
var _bind_buttons: Dictionary = {}
var _root: Control
var _sheet: VBoxContainer
var _body: VBoxContainer
var _status: Label
var _fullscreen: CheckButton
var _focus: Control
var _scroll: ScrollContainer


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS if home_settings else Node.PROCESS_MODE_WHEN_PAUSED
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = Style.theme()
	add_child(_root)
	_add_background()
	if home_settings:
		_page = Page.SETTINGS
	_show_page()


func _add_background() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color("#120c264f")
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(scrim)

	var texture := Style.shade(
		PackedColorArray([Color("#160f24fa"), Color("#191325f2"), Color("#26163700")]),
		PackedFloat32Array([0.0, 0.61, 1.0]))
	texture.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	texture.offset_right = PANEL_WIDTH + 168
	_root.add_child(texture)


func back() -> void:
	if _page == Page.SETTINGS and _capturing != "":
		_cancel_binding()
	elif _page == Page.PAUSE or home_settings:
		resume_requested.emit()
	else:
		_show(Page.PAUSE)


func request_exit() -> void:
	_request_transition(true)


func show_frame(frame: Image) -> void:
	if frame != null and not frame.is_empty():
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(frame)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_root.add_child(picture)
		_root.move_child(picture, 0)
	show()
	_focus.grab_focus()


func sync_window_mode(fullscreen: bool) -> void:
	if is_instance_valid(_fullscreen):
		_fullscreen.set_pressed_no_signal(fullscreen)


func show_error(message: String) -> void:
	_set_status(message)


func _show(page: Page) -> void:
	_page = page
	_show_page()


func _show_page() -> void:
	if is_instance_valid(_sheet):
		_root.remove_child(_sheet)
		_sheet.queue_free()
	_capturing = ""
	_bind_buttons.clear()
	_fullscreen = null
	_focus = null
	_sheet = VBoxContainer.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_sheet.offset_left = 48
	_sheet.offset_right = PANEL_WIDTH
	_sheet.offset_top = 48
	_sheet.offset_bottom = -34
	_sheet.add_theme_constant_override("separation", 12)
	_root.add_child(_sheet)

	var title: String = ["已暂停", "设置", "操作说明", "离开本关" if _confirm_exit else "重新开始本关"][_page]
	_sheet.add_child(_label(title, 42))
	if not level_title.is_empty():
		_sheet.add_child(_label(level_title, 18, MUTED))

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_sheet.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)

	match _page:
		Page.PAUSE:
			_pause_actions()
		Page.SETTINGS:
			_settings()
		Page.HELP:
			_help()
		Page.CONFIRM:
			_confirm()

	_status = _label("", 15, FOCUS)
	_status.visible = false
	_sheet.add_child(_status)
	if _page in [Page.SETTINGS, Page.HELP]:
		var back_button := _add_action(_sheet, "返回主菜单" if home_settings else "返回暂停菜单", back)
		if _focus == null:
			_focus = back_button
	_sheet.add_child(_label("Esc    " + ("返回战斗" if _page == Page.PAUSE else "返回"), 14, MUTED))
	_focus.grab_focus()


func _pause_actions() -> void:
	_focus = _add_action(_body, "继续游戏", resume_requested.emit)
	_focus.custom_minimum_size.y = 58
	_focus.add_theme_stylebox_override("normal", Style.primary_surface())
	_focus.add_theme_font_size_override("font_size", 22)
	_add_action(_body, "重新开始本关", _request_transition.bind(false))
	var utilities := HBoxContainer.new()
	utilities.add_theme_constant_override("separation", 11)
	_body.add_child(utilities)
	_add_action(utilities, "设置", _open_settings).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_action(utilities, "操作说明", _show.bind(Page.HELP)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gap := Control.new()
	gap.custom_minimum_size.y = 9
	_body.add_child(gap)
	_add_action(_body, "返回关卡选择", request_exit)


func _request_transition(exiting: bool) -> void:
	_confirm_exit = exiting
	if battle_active:
		_show(Page.CONFIRM)
	else:
		_accept_transition()


func _confirm() -> void:
	_body.add_child(_label("本次战斗进度将清空。", 18, MUTED))
	_add_action(_body, "返回关卡选择" if _confirm_exit else "重新开始", _accept_transition)
	_focus = _add_action(_body, "取消", back)


func _accept_transition() -> void:
	if _confirm_exit:
		exit_requested.emit()
	else:
		restart_requested.emit()


func _open_settings() -> void:
	_section = Section.DISPLAY
	_advanced_controls = false
	_show(Page.SETTINGS)


func _select_section(section: Section) -> void:
	_section = section
	_show_page()


func _settings() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	_body.add_child(tabs)
	for section in [Section.DISPLAY, Section.AUDIO, Section.CONTROLS]:
		var tab := _add_action(tabs, ["画面", "声音", "控制"][section], _select_section.bind(section))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if section == _section:
			tab.add_theme_color_override("font_color", FOCUS)
			tab.add_theme_stylebox_override("normal", Style.active_surface())
			_focus = tab
	match _section:
		Section.DISPLAY:
			_fullscreen = _toggle("全屏", get_window().mode in [Window.MODE_FULLSCREEN,
				Window.MODE_EXCLUSIVE_FULLSCREEN], "display.fullscreen")
			_slider("镜头震动", "cam.shake_scale", 0.0, 4.0, 0.05, 100.0)
		Section.AUDIO:
			_slider("总音量", "audio.master", 0.0, 1.5, 0.01, 100.0)
			_toggle("空间音效", bool(_option("audio.spatial", true)), "audio.spatial")
		Section.CONTROLS:
			_slider("鼠标灵敏度", "cam.sensitivity", 0.0002, 0.02, 0.0001, 0.0)
			_binding_rows()


func _slider(title: String, key: String, low: float, high: float, step_size: float, percent: float) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	_body.add_child(section)
	var header := HBoxContainer.new()
	section.add_child(header)
	var name_label := _label(title, 18)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var value := _label("", 16, FOCUS)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(value)
	var label_value := func(v: float) -> void:
		if percent > 0.0:
			value.text = "%d%%" % roundi(v * percent)
		else:
			value.text = "%.1f×" % (v / 0.0022)
	var slider := HSlider.new()
	slider.custom_minimum_size.y = 34
	slider.min_value = low
	slider.max_value = high
	slider.step = step_size
	slider.value = float(_option(key, 0.0022 if key == "cam.sensitivity" else 1.0))
	label_value.call(slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		label_value.call(v)
		options[key] = v
		setting_changed.emit(key, v)
	)
	section.add_child(slider)


func _toggle(title: String, enabled: bool, key: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.button_pressed = enabled
	toggle.custom_minimum_size.y = 40
	toggle.toggled.connect(func(value: bool) -> void:
		options[key] = value
		setting_changed.emit(key, value)
	)
	_body.add_child(toggle)
	return toggle


func _binding_rows() -> void:
	_body.add_child(_label("按键绑定", 20))
	for action: Dictionary in binds.actions():
		var id: String = action["id"]
		if id in ADVANCED_ACTIONS and not _advanced_controls:
			continue
		var row := HBoxContainer.new()
		_body.add_child(row)
		var label := _label(BIND_LABELS.get(id, action["label"]), 16)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var key := _add_action(row, binds.event_text(id), _start_binding.bind(id))
		key.custom_minimum_size.x = 125
		key.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bind_buttons[id] = key
	var extra := _add_action(_body, "收起调试按键" if _advanced_controls else "显示调试按键", _toggle_advanced)
	extra.name = "AdvancedBindings"
	_add_action(_body, "恢复默认按键", _reset_bindings)


func _toggle_advanced() -> void:
	_advanced_controls = not _advanced_controls
	_show_page()
	var control := _body.get_node("AdvancedBindings") as Control
	control.grab_focus()


func _start_binding(id: String) -> void:
	_capturing = id
	_bind_buttons[id].text = "按下新键"
	_set_status("按下新键，Esc 取消")


func _cancel_binding() -> void:
	_capturing = ""
	_refresh_bindings()
	_set_status("已取消改键")


func _reset_bindings() -> void:
	binds.reset_all()
	_refresh_bindings()
	_set_status("已恢复默认按键")


func _refresh_bindings() -> void:
	for id: String in _bind_buttons:
		_bind_buttons[id].text = binds.event_text(id)


func _input(event: InputEvent) -> void:
	if _capturing == "":
		return
	if not event is InputEventKey and not event is InputEventMouseButton:
		return
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey:
		var key: Key = event.keycode if event.keycode != 0 else event.physical_keycode
		if key == KEY_ESCAPE:
			_cancel_binding()
			return
		if key in [KEY_F1, KEY_F11]:
			_set_status("F1 和 F11 用作系统快捷键")
			return
	elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		return
	var previous: String = binds.rebind(_capturing, event)
	_capturing = ""
	_refresh_bindings()
	if previous.is_empty():
		_set_status("按键已更新")
	else:
		var moved := previous
		for action: Dictionary in binds.actions():
			if action["id"] == previous:
				moved = BIND_LABELS.get(previous, action["label"])
				break
		_set_status("按键已更新，「%s」原按键已解除" % moved)


func _help() -> void:
	_help_row("移动", ["move_forward", "move_left", "move_back", "move_right"])
	_help_row("跳跃 / 冲刺", ["jump", "dash"])
	_help_row("攻击", ["attack_light"])
	_help_row("格挡 / 弹反", ["parry"])
	_help_row("切换视角", ["cam_mode"])
	if not level_hint.is_empty():
		var spacer := Control.new()
		spacer.custom_minimum_size.y = 10
		_body.add_child(spacer)
		_body.add_child(_label(level_hint, 18, MUTED))


func _help_row(title: String, actions: Array[String]) -> void:
	var row := HBoxContainer.new()
	_body.add_child(row)
	row.custom_minimum_size.y = 38
	var label := _label(title, 18)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var keys: PackedStringArray = []
	for id in actions:
		keys.append(binds.event_text(id))
	var binding := _label("  /  ".join(keys), 16, FOCUS)
	binding.autowrap_mode = TextServer.AUTOWRAP_OFF
	binding.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(binding)


func _set_status(message: String) -> void:
	_status.text = message
	_status.visible = not message.is_empty()


func _label(text: String, size: int, color := TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _add_action(parent: Container, title: String, callback: Callable) -> Button:
	var button := Style.button(title, callback)
	button.custom_minimum_size.y = 43
	parent.add_child(button)
	return button


func _option(key: String, fallback: Variant) -> Variant:
	if params != null:
		return params.getb(key) if fallback is bool else params.getf(key)
	return options.get(key, fallback)
