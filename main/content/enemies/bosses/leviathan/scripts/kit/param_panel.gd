extends PanelContainer
class_name ParamPanel
## Generic tuning UI. Reads the character's spec dictionaries and builds live
## numeric entry rows (SpinBox: type a value or drag-stepped).
##
## Character contract (see README_kit.md):
##   anim_names() -> PackedStringArray
##   play_anim(name)
##   set_playing(bool) / is_playing() -> bool
##   anim_time() -> float
##   set_anim_time(t)
##   anim_duration() -> float
##   set_anim_speed(v) / anim_speed() -> float
##   set_loop(bool) / is_looping() -> bool
##   param_specs() -> Array[Dictionary]  {group,key,label,min,max,step,value}
##   set_param(key, value) / get_param(key) -> float  (optional but expected)
##   joint_specs() -> Array[Dictionary]  {group,key,label,min,max,step,value}
##   set_joint(key, value) / get_joint(key) -> float
##   rig_debug() -> Dictionary

signal anim_requested(name: String)

const PANEL_W := 392
const GOLD := Color(0.98, 0.70, 0.30)
const CYAN := Color(0.55, 0.78, 1.0)
const DIM := Color(0.62, 0.66, 0.74)

var character: Node
var _tabs: TabContainer
var _anim_buttons: GridContainer
var _param_box: VBoxContainer
var _joint_box: VBoxContainer
var _info_label: RichTextLabel
var _play_btn: Button
var _time_slider: HSlider
var _time_label: Label
var _speed_box: SpinBox
var _loop_check: CheckBox
var _scrubbing := false
var _status: Label
var _spec_rows: Array = []   # [{spec, box}]
var _joint_rows: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, 0)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -PANEL_W - 18.0
	offset_right = -18.0
	offset_top = 18.0
	offset_bottom = -18.0
	add_theme_font_size_override("font_size", 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.018, 0.021, 0.030, 0.93)
	sb.border_color = Color(0.24, 0.42, 0.60, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	_build()
	refresh()


# ------------------------------------------------------------------- layout

func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "TUNING // LIVE"
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 13)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_status = Label.new()
	_status.add_theme_color_override("font_color", DIM)
	_status.add_theme_font_size_override("font_size", 11)
	head.add_child(_status)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 12)
	root.add_child(_tabs)

	# --- animation tab
	var anim_scroll := ScrollContainer.new()
	anim_scroll.name = "ANIM"
	anim_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(anim_scroll)
	var anim_col := VBoxContainer.new()
	anim_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anim_col.add_theme_constant_override("separation", 4)
	anim_scroll.add_child(anim_col)
	_anim_buttons = GridContainer.new()
	_anim_buttons.columns = 2
	_anim_buttons.add_theme_constant_override("h_separation", 4)
	_anim_buttons.add_theme_constant_override("v_separation", 4)
	anim_col.add_child(_anim_buttons)
	var sep := HSeparator.new()
	anim_col.add_child(sep)
	var anim_params := VBoxContainer.new()
	anim_params.name = "param_holder"
	anim_params.add_theme_constant_override("separation", 2)
	anim_col.add_child(anim_params)

	# --- params tab
	var p_scroll := ScrollContainer.new()
	p_scroll.name = "PARAMS"
	p_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(p_scroll)
	_param_box = VBoxContainer.new()
	_param_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_param_box.add_theme_constant_override("separation", 2)
	p_scroll.add_child(_param_box)

	# --- joints tab
	var j_scroll := ScrollContainer.new()
	j_scroll.name = "JOINTS"
	j_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(j_scroll)
	_joint_box = VBoxContainer.new()
	_joint_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_joint_box.add_theme_constant_override("separation", 2)
	j_scroll.add_child(_joint_box)

	# --- info tab
	var i_scroll := ScrollContainer.new()
	i_scroll.name = "INFO"
	i_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(i_scroll)
	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = false
	_info_label.fit_content = true
	_info_label.custom_minimum_size = Vector2(PANEL_W - 46, 0)
	_info_label.add_theme_font_size_override("normal_font_size", 11)
	_info_label.add_theme_color_override("default_color", Color(0.72, 0.80, 0.90))
	i_scroll.add_child(_info_label)

	# --- transport
	var transport := VBoxContainer.new()
	transport.add_theme_constant_override("separation", 3)
	root.add_child(transport)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	transport.add_child(row)
	_play_btn = Button.new()
	_play_btn.text = "PAUSE"
	_play_btn.custom_minimum_size = Vector2(62, 0)
	_play_btn.pressed.connect(_on_play_pressed)
	row.add_child(_play_btn)
	_time_label = Label.new()
	_time_label.custom_minimum_size = Vector2(84, 0)
	_time_label.clip_text = true
	_time_label.text = "0.00 / 0.00"
	_time_label.add_theme_color_override("font_color", DIM)
	row.add_child(_time_label)
	var jump := Control.new()
	jump.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(jump)
	var s_label := Label.new()
	s_label.text = "SPEED"
	s_label.add_theme_color_override("font_color", DIM)
	row.add_child(s_label)
	_speed_box = SpinBox.new()
	_speed_box.min_value = 0.02
	_speed_box.max_value = 4.0
	_speed_box.step = 0.01
	_speed_box.value = 1.0
	_speed_box.custom_minimum_size = Vector2(64, 0)
	_speed_box.value_changed.connect(_on_speed_changed)
	row.add_child(_speed_box)
	_loop_check = CheckBox.new()
	_loop_check.text = "LOOP"
	_loop_check.button_pressed = true
	_loop_check.custom_minimum_size = Vector2(54, 0)
	_loop_check.toggled.connect(_on_loop_toggled)
	row.add_child(_loop_check)
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = 1.0
	_time_slider.step = 0.001
	_time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_slider.value_changed.connect(_on_scrub)
	_time_slider.drag_started.connect(func() -> void: _scrubbing = true)
	_time_slider.drag_ended.connect(func(_v: bool) -> void: _scrubbing = false)
	transport.add_child(_time_slider)

	var hint := Label.new()
	hint.text = "LMB orbit · wheel zoom · F reset · SPACE play · H hide UI"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.custom_minimum_size = Vector2(0, 0)
	hint.add_theme_color_override("font_color", Color(0.42, 0.47, 0.56))
	hint.add_theme_font_size_override("font_size", 10)
	root.add_child(hint)


func bind(node: Node) -> void:
	character = node
	refresh()


func refresh() -> void:
	if character == null or not is_instance_valid(character):
		return
	_build_anim_buttons()
	_build_specs()
	_build_joints()
	_speed_box.set_value_no_signal(character.anim_speed() if character.has_method("anim_speed") else 1.0)
	_sync_loop()
	_update_status()


func _build_anim_buttons() -> void:
	for c in _anim_buttons.get_children():
		c.queue_free()
	var names: PackedStringArray = character.anim_names()
	for i in names.size():
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, names[i].to_upper()]
		b.tooltip_text = "Play '%s'" % names[i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 26)
		var nm := names[i]
		b.pressed.connect(func() -> void: _request_anim(nm))
		_anim_buttons.add_child(b)


func _build_specs() -> void:
	for c in _param_box.get_children():
		c.queue_free()
	_spec_rows.clear()
	var specs: Array = character.param_specs() if character.has_method("param_specs") else []
	_add_spec_groups(_param_box, specs, false)


func _build_joints() -> void:
	for c in _joint_box.get_children():
		c.queue_free()
	_joint_rows.clear()
	var specs: Array = character.joint_specs() if character.has_method("joint_specs") else []
	_add_spec_groups(_joint_box, specs, true)


func _add_spec_groups(host: VBoxContainer, specs: Array, is_joint: bool) -> void:
	var groups: Array = []
	for s in specs:
		var g: String = s.get("group", "GENERAL")
		if not groups.has(g):
			groups.append(g)
	for gi in groups.size():
		var gname: String = groups[gi]
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 1)
		host.add_child(section)
		var header := Button.new()
		header.text = ("-  " if gi < 2 else "+  ") + gname.to_upper()
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.toggle_mode = true
		header.button_pressed = gi < 2
		header.add_theme_font_size_override("font_size", 11)
		header.add_theme_color_override("font_color", CYAN)
		section.add_child(header)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 1)
		body.visible = gi < 2
		section.add_child(body)
		header.toggled.connect(func(on: bool) -> void:
			body.visible = on
			header.text = ("-  " if on else "+  ") + gname.to_upper()
		)
		for s in specs:
			if s.get("group", "GENERAL") != gname:
				continue
			var row := _make_row(s, is_joint)
			body.add_child(row)


func _make_row(spec: Dictionary, is_joint: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lab := Label.new()
	lab.text = str(spec.get("label", spec.get("key", "?")))
	lab.custom_minimum_size = Vector2(132, 0)
	lab.clip_text = true
	lab.size_flags_horizontal = Control.SIZE_FILL
	lab.add_theme_font_size_override("font_size", 11)
	lab.add_theme_color_override("font_color", Color(0.76, 0.80, 0.87))
	lab.tooltip_text = str(spec.get("key", ""))
	row.add_child(lab)
	var box := SpinBox.new()
	box.min_value = float(spec.get("min", 0.0))
	box.max_value = float(spec.get("max", 100.0))
	box.step = float(spec.get("step", 0.001))
	box.value = float(spec.get("value", 0.0))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(96, 0)
	box.select_all_on_focus = true
	var key := str(spec.get("key", ""))
	box.value_changed.connect(func(v: float) -> void:
		if character == null:
			return
		if is_joint:
			if character.has_method("set_joint"):
				character.set_joint(key, v)
		else:
			if character.has_method("set_param"):
				character.set_param(key, v)
	)
	row.add_child(box)
	var rec := {"spec": spec, "box": box}
	if is_joint:
		_joint_rows.append(rec)
	else:
		_spec_rows.append(rec)
	return row


# --------------------------------------------------------------- transport

func _request_anim(name: String) -> void:
	if character == null:
		return
	character.play_anim(name)
	anim_requested.emit(name)
	var d: float = character.anim_duration() if character.has_method("anim_duration") else 1.0
	_time_slider.max_value = maxf(d, 0.001)
	_time_slider.set_value_no_signal(0.0)
	_sync_loop()
	if not character.is_playing():
		character.set_playing(true)


func _on_play_pressed() -> void:
	if character == null:
		return
	character.set_playing(not character.is_playing())
	_play_btn.text = "PAUSE" if character.is_playing() else "PLAY"


func _on_speed_changed(v: float) -> void:
	if character != null and character.has_method("set_anim_speed"):
		character.set_anim_speed(v)


func _on_loop_toggled(on: bool) -> void:
	if character != null and character.has_method("set_loop"):
		character.set_loop(on)


func _on_scrub(v: float) -> void:
	if character != null and character.has_method("set_anim_time"):
		character.set_anim_time(v)


func _sync_loop() -> void:
	if character != null and character.has_method("is_looping"):
		_loop_check.set_pressed_no_signal(character.is_looping())


# ------------------------------------------------------------------- update

func _process(_dt: float) -> void:
	if character == null or not is_instance_valid(character):
		return
	_update_status()
	var d: float = character.anim_duration() if character.has_method("anim_duration") else 1.0
	if not is_equal_approx(_time_slider.max_value, d):
		_time_slider.max_value = maxf(d, 0.001)
	if not _scrubbing:
		var t: float = character.anim_time() if character.has_method("anim_time") else 0.0
		_time_slider.set_value_no_signal(t)
	_time_label.text = "%4.2f/%4.2f" % [
		character.anim_time() if character.has_method("anim_time") else 0.0, d]
	_play_btn.text = "PAUSE" if character.is_playing() else "PLAY"
	if _info_label != null:
		_info_label.text = _debug_text()


func _update_status() -> void:
	if _status == null:
		return
	_status.text = "%d Hz" % Engine.get_frames_per_second()


func _debug_text() -> String:
	var lines: PackedStringArray = []
	lines.append("FPS            %d" % Engine.get_frames_per_second())
	lines.append("DRAW CALLS     %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	lines.append("PRIMITIVES     %d" % prims)
	lines.append("ANIM           %s" % character.get("current_anim"))
	if character.has_method("rig_debug"):
		var d: Dictionary = character.rig_debug()
		for k in d:
			lines.append("%-14s %s" % [str(k).to_upper(), str(d[k])])
	return "\n".join(lines)