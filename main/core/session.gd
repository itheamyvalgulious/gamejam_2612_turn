extends Node

const MENU := "res://ui/menu/menu.tscn"
const Catalog = preload("res://core/level_catalog.gd")
const LevelProgress = preload("res://core/level_progress.gd")
const LevelLoading = preload("res://ui/loading/level_loading.gd")
const PauseMenu = preload("res://ui/pause/pause_menu.gd")
const OPTIONS_PATH := "user://turn_options.cfg"

enum MenuPage { HOME, LEVELS }

var menu_page := MenuPage.HOME
var selected_level_index := 0
var progress := LevelProgress.new()
var progress_save_failed := false
var _active := -1
var _changing := false
var _services: Script
var _arguments := PackedStringArray()
var _options := ConfigFile.new()
var _pause_menu: PauseMenu
var _hud_was_visible := true
var _resume_mouse := false
var _home_settings: PauseMenu
var _home_focus: Control
var _loading: LevelLoading
var _debug_hud: CanvasLayer
var _debug_panel: PanelContainer
var _debug_label: Label
var _debug_on := false
var _debug_samples := PackedFloat32Array()
var _debug_cursor := 0
var _debug_filled := 0
const DEBUG_SAMPLES := 240


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	progress.load_progress()
	selected_level_index = maxi(0, progress.resume_index())
	if _options.load(OPTIONS_PATH) == OK and _options.has_section_key("game", "display.fullscreen"):
		_set_fullscreen(bool(_options.get_value("game", "display.fullscreen")))
	_set_vsync(bool(get_option("display.vsync", false)))
	_build_debug_hud()
	get_window().focus_exited.connect(_pause_on_focus_loss)


func _build_debug_hud() -> void:
	_debug_hud = CanvasLayer.new()
	_debug_hud.name = "DebugHud"
	_debug_hud.layer = 90
	_debug_hud.process_mode = Node.PROCESS_MODE_ALWAYS
	_debug_hud.visible = false
	add_child(_debug_hud)
	_debug_panel = PanelContainer.new()
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.025, 0.04, 0.84)
	style.border_color = Color(0.34, 0.94, 1.0, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	_debug_panel.add_theme_stylebox_override("panel", style)
	_debug_hud.add_child(_debug_panel)
	_debug_panel.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_debug_label = Label.new()
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font = load("res://runtime/fonts/act/ui_font.tres")
	if font != null:
		_debug_label.add_theme_font_override("font", font)
	_debug_label.add_theme_font_size_override("font_size", 15)
	_debug_label.add_theme_color_override("font_color", Color(0.84, 0.96, 1.0))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	_debug_panel.add_child(_debug_label)
	_debug_samples.resize(DEBUG_SAMPLES)


func toggle_debug_hud() -> void:
	_debug_on = not _debug_on
	_debug_hud.visible = _debug_on
	if _debug_on:
		_debug_cursor = 0
		_debug_filled = 0
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		_update_debug_hud(get_process_delta_time())


func _update_debug_hud(delta: float) -> void:
	if not _debug_on:
		return
	var ms := delta * 1000.0
	_debug_samples[_debug_cursor] = ms
	_debug_cursor = (_debug_cursor + 1) % DEBUG_SAMPLES
	_debug_filled = mini(_debug_filled + 1, DEBUG_SAMPLES)
	var count := mini(_debug_filled, 60)
	var average := 0.0
	for i in count:
		average += _debug_samples[(_debug_cursor - 1 - i + DEBUG_SAMPLES * 2) % DEBUG_SAMPLES]
	average /= float(maxi(count, 1))
	var sorted: Array[float] = []
	for i in _debug_filled:
		sorted.append(_debug_samples[i])
	sorted.sort()
	var p95 := sorted[mini(int(float(sorted.size()) * 0.95), sorted.size() - 1)] if not sorted.is_empty() else ms
	# 该接口返回毫秒（不是文档里写的秒），直接显示。
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(
		get_viewport().get_viewport_rid())
	var cpu := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objects := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var enemies := ""
	var current := get_tree().current_scene
	if is_instance_valid(current):
		var level: Node = current.get("level")
		if level != null and level.get("enemies") != null:
			var alive := 0
			var total := 0
			for e in level.get("enemies"):
				if is_instance_valid(e):
					total += 1
					if bool(e.get("alive")):
						alive += 1
			if total > 0:
				enemies = " · 敌 %d/%d" % [alive, total]
	_debug_label.text = "帧时 %.2f ms  (%.0f FPS)\n60帧均 %.2f · p95 %.2f · 最大 %.2f\nGPU %.2f ms · CPU %.2f ms · 物理 %.2f ms\ndraws %d · prims %s · objs %d\nnodes %d%s" % [
		ms, 1000.0 / maxf(ms, 0.001), average, p95, sorted[sorted.size() - 1] if not sorted.is_empty() else ms,
		gpu, cpu, physics, draws, _compact(prims), objects, nodes, enemies]


func open_home_settings() -> void:
	if _home_settings != null or _active >= 0 or _changing:
		return
	_home_focus = get_viewport().gui_get_focus_owner()
	var panel := PauseMenu.new()
	panel.home_settings = true
	panel.options = {}
	if _options.has_section("game"):
		for key in _options.get_section_keys("game"):
			panel.options[key] = _options.get_value("game", key)
	panel.binds = preload("res://runtime/systems/act/core/binds.gd").new()
	panel.add_child(panel.binds)
	panel.resume_requested.connect(_close_home_settings)
	panel.setting_changed.connect(_set_option)
	_home_settings = panel
	add_child(panel)


func _close_home_settings() -> void:
	_home_settings.hide()
	_home_settings.queue_free()
	_home_settings = null
	InputMap.load_from_project_settings()
	if is_instance_valid(_home_focus):
		_home_focus.grab_focus()


func binding_label(action: String) -> String:
	return _services.get("b").event_text(action) if _services != null else "—"


func open_level(index: int) -> void:
	if _home_settings != null or _changing or index < 0 or index >= Catalog.level_count():
		return
	_changing = true
	_switch.call_deferred(index)


func return_to_menu() -> void:
	if _changing or _active < 0:
		return
	_changing = true
	_switch.call_deferred(-1)


func level_arguments() -> PackedStringArray:
	var result := OS.get_cmdline_user_args()
	result.append_array(_arguments)
	return result


func active_level_index() -> int:
	return _active


func advance_level() -> void:
	if _active < 0 or _changing:
		return
	var current := get_tree().current_scene
	var level: Node = current.get("level")
	var player: Node = current.get("player")
	if level.get("state") in ["clear", "finished"] or (level.get("total_enemies") == 0 and player.get("alive")):
		record_level_clear()
	if _active == Catalog.level_count() - 1:
		return_to_menu()
	else:
		open_level(_active + 1)


func record_level_clear() -> void:
	if _active >= 0:
		_update_save_status(progress.complete(_active))


func _update_save_status(result: Error) -> void:
	progress_save_failed = result != OK
	if progress_save_failed:
		push_warning("TURN could not write the level progress: " + error_string(result))


func _input(event: InputEvent) -> void:
	if is_instance_valid(_loading):
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed() or event.is_echo():
		return
	var key: Key = KEY_NONE
	if event is InputEventKey:
		key = event.keycode if event.keycode != 0 else event.physical_keycode
	if key == KEY_F11:
		get_viewport().set_input_as_handled()
		_set_option("display.fullscreen", not _is_fullscreen())
	elif key == KEY_ESCAPE and _home_settings != null:
		get_viewport().set_input_as_handled()
		_home_settings.back()
	elif key == KEY_F5 and _active >= 0:
		var current := get_tree().current_scene
		if current != null and current.has_method("_menus_open") and bool(current.call("_menus_open")):
			return
		get_viewport().set_input_as_handled()
		toggle_debug_hud()
	elif key == KEY_F1 and _active >= 0:
		get_viewport().set_input_as_handled()
		if _pause_menu != null:
			_pause_menu.request_exit()
		else:
			return_to_menu()
	elif _active >= 0 and not _changing and (key == KEY_ESCAPE or event.is_action_pressed("pause")):
		if _pause_menu != null:
			get_viewport().set_input_as_handled()
			_pause_menu.back()
		else:
			var current := get_tree().current_scene
			if current != null and not bool(current.call("_menus_open")):
				get_viewport().set_input_as_handled()
				_open_pause()


func _pause_on_focus_loss() -> void:
	# 自动基准需要无人值守连续跑，焦点丢失不打断模拟。
	if DisplayServer.get_name() != "headless" and "--play-bench" not in OS.get_cmdline_user_args():
		_open_pause(true)


func _open_pause(from_focus_loss := false) -> void:
	if _pause_menu != null or _changing or _active < 0:
		return
	var current := get_tree().current_scene
	if current == null or bool(current.call("_menus_open")):
		return
	var hud: CanvasLayer = current.get("hud")
	var level: Node = current.get("level")
	var entry := Catalog.get_entry(_active)
	_hud_was_visible = hud.visible
	_resume_mouse = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or from_focus_loss
	current.call("_release_mouse")
	hud.hide()

	var overlay := PauseMenu.new()
	overlay.name = "PauseMenu"
	overlay.level_title = String(entry[0])
	overlay.level_hint = Catalog.play_hint(_active)
	overlay.battle_active = int(level.get("total_enemies")) > 0 and level.get("state") in ["fight", "clear"]
	overlay.params = _services.get("p")
	overlay.binds = _services.get("b")
	overlay.resume_requested.connect(func() -> void: _resume_level.call_deferred())
	overlay.restart_requested.connect(func() -> void: _restart_paused_level.call_deferred())
	overlay.exit_requested.connect(return_to_menu)
	overlay.setting_changed.connect(_set_option)
	_pause_menu = overlay
	get_tree().paused = true
	var capture_frame := DisplayServer.get_name() != "headless"
	overlay.visible = not capture_frame
	add_child(overlay)
	if capture_frame:
		_show_paused_frame(overlay)


func _show_paused_frame(overlay: PauseMenu) -> void:
	# Capture one frame with the combat HUD hidden and before the pause layer is drawn.
	await RenderingServer.frame_post_draw
	if is_instance_valid(overlay) and overlay == _pause_menu:
		overlay.show_frame(get_viewport().get_texture().get_image())


func _resume_level() -> void:
	if _pause_menu == null or _changing:
		return
	var current := get_tree().current_scene
	_close_pause()
	if _resume_mouse and current != null:
		current.call("_capture_mouse")


func _restart_paused_level() -> void:
	if _pause_menu == null or _changing:
		return
	var current := get_tree().current_scene
	current.call("restart_level")
	_resume_level()


func _close_pause() -> void:
	if _pause_menu == null:
		return
	_pause_menu.hide()
	_pause_menu.queue_free()
	_pause_menu = null
	var current := get_tree().current_scene
	if is_instance_valid(current):
		var hud: CanvasLayer = current.get("hud")
		hud.visible = _hud_was_visible
	get_tree().paused = false


func _is_fullscreen() -> bool:
	return get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]


func _set_fullscreen(enabled: bool) -> void:
	get_window().mode = Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED
	if _pause_menu != null:
		_pause_menu.sync_window_mode(enabled)
	if _home_settings != null:
		_home_settings.sync_window_mode(enabled)


## 关卡运行期的调试参数（如 rules.god_mode），不写入存档。
func set_game_param(key: String, value: Variant) -> void:
	if _services != null:
		_services.get("p").set_value(key, value)



func _set_option(key: String, value: Variant) -> void:
	if key == "display.fullscreen":
		_set_fullscreen(bool(value))
	elif key == "display.vsync":
		_set_vsync(bool(value))
	elif _services != null and not key.begins_with("display."):
		_services.get("p").set_value(key, value)
	_options.set_value("game", key, value)
	var error := _options.save(OPTIONS_PATH)
	var panel := _pause_menu if _pause_menu != null else _home_settings
	if error != OK and panel != null:
		panel.show_error("设置暂未保存")


func get_option(key: String, fallback: Variant = null) -> Variant:
	return _options.get_value("game", key, fallback)


func _set_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)


func _apply_level_options() -> void:
	var parameters: Node = _services.get("p")
	for key in ["audio.master", "audio.spatial", "cam.shake_scale", "cam.sensitivity"]:
		if _options.has_section_key("game", key):
			parameters.set_value(key, _options.get_value("game", key))


func _process(delta: float) -> void:
	_update_debug_hud(delta)
	if _changing or _active < 0 or get_tree().paused:
		return
	var current := get_tree().current_scene
	if is_instance_valid(current):
		var level: Node = current.get("level")
		if level != null and level.get("state") == "finished":
			advance_level()


func _compact(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return str(value)


func _switch(index: int) -> void:
	var scene_path := MENU
	var services_path := ""
	var tree := get_tree()
	var old := tree.current_scene
	var old_mode := Node.PROCESS_MODE_INHERIT if old == null else old.process_mode
	var recapture := false
	if index >= 0:
		var entry := Catalog.get_entry(index)
		var episode := String(entry[2])
		var entry_scene := String(entry[3])
		scene_path = "res://runtime/levels/%s/%s" % [episode, "main.tscn" if entry_scene.is_empty() else entry_scene]
		services_path = "res://runtime/systems/%s/services.gd" % Catalog.services_for(index)
		if DisplayServer.get_name() != "headless":
			if is_instance_valid(old):
				old.process_mode = Node.PROCESS_MODE_DISABLED
				if _active >= 0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					recapture = true
					old.call("_release_mouse")
			_loading = LevelLoading.new()
			_loading.level_title = entry[0]
			add_child(_loading)
			await RenderingServer.frame_post_draw

	var packed := await _load_scene(scene_path)
	var next_services := load(services_path) as Script if not services_path.is_empty() else null
	if packed == null or (index >= 0 and next_services == null):
		_end_loading()
		if is_instance_valid(old):
			old.process_mode = old_mode
			if recapture:
				old.call("_capture_mouse")
		_switch_failed(scene_path)
		return

	_close_pause()
	tree.current_scene = null
	if is_instance_valid(old):
		old.free()
	if _services != null:
		_services.call("stop")
	_active = index
	_arguments.clear()
	InputMap.load_from_project_settings()

	_services = next_services
	if index >= 0:
		menu_page = MenuPage.LEVELS
		selected_level_index = index
		_arguments = PackedStringArray(Catalog.get_entry(index)[4])
		if DisplayServer.get_name() == "headless":
			_arguments.append("--no-mouse-capture")
		_services.call("start", tree.root)
		_apply_level_options()
	var current := packed.instantiate()
	_update_save_status(progress.visit(index) if index >= 0 else progress.flush())
	var current_mode := current.process_mode
	if is_instance_valid(_loading):
		current.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(current)
	tree.current_scene = current
	if index < 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tree.root.title = "TURN" if index < 0 else "TURN · " + String(Catalog.get_entry(index)[0])
	if is_instance_valid(_loading):
		await RenderingServer.frame_post_draw
		_end_loading()
		current.process_mode = current_mode
	_changing = false


func _load_scene(path: String) -> PackedScene:
	if not is_instance_valid(_loading):
		return load(path) as PackedScene
	if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
		return null
	var status := ResourceLoader.load_threaded_get_status(path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(path)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		return null
	return ResourceLoader.load_threaded_get(path) as PackedScene


func _end_loading() -> void:
	if is_instance_valid(_loading):
		_loading.hide()
		_loading.queue_free()
		_loading = null


func _switch_failed(path: String) -> void:
	_changing = false
	push_error("Unable to load " + path)
	if _pause_menu != null:
		_pause_menu.show_error("载入失败，请重试")
		return
	var current := get_tree().current_scene
	if current != null and current.has_method("show_load_error"):
		current.call("show_load_error")
