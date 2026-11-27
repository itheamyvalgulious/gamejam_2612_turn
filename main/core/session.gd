extends Node

const MENU := "res://ui/menu/menu.tscn"
const Catalog = preload("res://core/level_catalog.gd")
const LevelProgress = preload("res://core/level_progress.gd")
const LevelLoading = preload("res://ui/loading/level_loading.gd")
const PauseMenu = preload("res://ui/pause/pause_menu.gd")
const NavDebugView = preload("res://core/nav_debug_view.gd")
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
var _mode_before_minimize := Window.MODE_MINIMIZED
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
var _debug_gpu_ms := 0.0
var _debug_gpu_tick := 0
const DEBUG_SAMPLES := 240
## GPU 时间查询是同步型（驱动要等管线回读），每帧调会把 10–100ms 的
## 查询等待周期性打进帧时间 —— 实测就是 ~140ms 尖峰的来源之一。
## 显示上 0.5s 精度足够，降频到每 30 帧查一次、其余帧用缓存值。
const DEBUG_GPU_INTERVAL := 30
var _nav_view: Node3D
var _solids_view: Node3D
var _collisions_hint := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	progress.load_progress()
	selected_level_index = maxi(0, progress.resume_index())
	if _options.load(OPTIONS_PATH) == OK and _options.has_section_key("game", "display.fullscreen"):
		_set_fullscreen(bool(_options.get_value("game", "display.fullscreen")))
	_set_vsync(bool(get_option("display.vsync", false)))
	_apply_render_options()
	_build_debug_hud()
	get_window().focus_exited.connect(_pause_on_focus_loss)
	get_window().focus_entered.connect(_restore_minimized_mode, CONNECT_DEFERRED)


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
	_debug_hud.visible = _debug_on and _pause_menu == null
	RenderingServer.viewport_set_measure_render_time(
		get_viewport().get_viewport_rid(), _debug_on)
	if _debug_on:
		_debug_cursor = 0
		_debug_filled = 0
		_debug_gpu_ms = 0.0
		_debug_gpu_tick = DEBUG_GPU_INTERVAL  # 第一帧就查一次，立即可读
		_update_debug_hud(get_process_delta_time())


## 彻底关掉 F5 与 GPU 计时（--hud=0 基准用；与 toggle 的 open 路径区分）。
func force_debug_hud_off() -> void:
	if _debug_on:
		toggle_debug_hud()
	_debug_hud.visible = false
	RenderingServer.viewport_set_measure_render_time(
		get_viewport().get_viewport_rid(), false)


## F6：导航元信息视图。挂到当前关卡场景的 level 旁；关闭即整棵释放（零开销）。
func toggle_nav_view() -> void:
	if _nav_view != null:
		_nav_view.queue_free()
		_nav_view = null
		return
	var current := get_tree().current_scene
	if current == null:
		return
	var level: Node = current.get("level")
	if level == null:
		return
	_nav_view = NavDebugView.attach(level, current)


## F7：物理体视图 —— 引擎 debug_collisions_hint（真 CollisionShape3D）
## + 数据驱动碰撞（arena solids/walkables）的叠加层。
## 动态刚体（death 任务的 RigidBody3D/碎片）用
## TurnSession.body_debug_view().add_body_provider(callable) 接入。
func body_debug_view() -> Node3D:
	return _solids_view


func toggle_collision_view() -> void:
	_collisions_hint = not _collisions_hint
	get_tree().debug_collisions_hint = _collisions_hint
	if _collisions_hint:
		var current := get_tree().current_scene
		var level: Node = current.get("level") if current != null else null
		if level != null:
			_solids_view = NavDebugView.attach(level, current, "solids")
			var df: Variant = level.get_meta(&"death_field", null)
			if df != null and is_instance_valid(df) and df.has_method("debug_bodies"):
				_solids_view.call("add_body_provider", Callable(df, "debug_bodies"))
				_solids_view.call("_rebuild_solids")
	elif _solids_view != null and is_instance_valid(_solids_view):
		_solids_view.queue_free()
		_solids_view = null
	else:
		_solids_view = null


func _drop_nav_view() -> void:
	if _nav_view != null and is_instance_valid(_nav_view):
		_nav_view.queue_free()
	_nav_view = null
	if _solids_view != null and is_instance_valid(_solids_view):
		_solids_view.queue_free()
	_solids_view = null
	_collisions_hint = false
	if get_tree() != null:
		get_tree().debug_collisions_hint = false


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
	# 同步型查询降频：每 DEBUG_GPU_INTERVAL 帧回读一次（见上方常量注释）。
	_debug_gpu_tick += 1
	if _debug_gpu_tick >= DEBUG_GPU_INTERVAL:
		_debug_gpu_tick = 0
		_debug_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(
			get_viewport().get_viewport_rid())
	var gpu := _debug_gpu_ms
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
	elif (key == KEY_F6 or (event is InputEventKey and event.physical_keycode == KEY_F6)) and get_tree().current_scene != null and get_tree().current_scene.get("level") != null:
		# 调参面板打开时 F6 是它的「重置本组」：导航视图让位。
		var current := get_tree().current_scene
		if current != null and current.has_method("_menus_open") and bool(current.call("_menus_open")):
			return
		get_viewport().set_input_as_handled()
		toggle_nav_view()
	elif (key == KEY_F7 or (event is InputEventKey and event.physical_keycode == KEY_F7)) and get_tree().current_scene != null and get_tree().current_scene.get("level") != null:
		var current := get_tree().current_scene
		if current != null and current.has_method("_menus_open") and bool(current.call("_menus_open")):
			return
		get_viewport().set_input_as_handled()
		toggle_collision_view()
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
	_debug_hud.hide()
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
	_debug_hud.visible = _debug_on


func minimize_window() -> void:
	var window := get_window()
	if window.mode != Window.MODE_MINIMIZED:
		_mode_before_minimize = window.mode
		window.mode = Window.MODE_MINIMIZED


func _restore_minimized_mode() -> void:
	if _mode_before_minimize == Window.MODE_MINIMIZED:
		return
	var window := get_window()
	if window.mode == Window.MODE_MINIMIZED:
		return
	var previous_mode := _mode_before_minimize
	_mode_before_minimize = Window.MODE_MINIMIZED
	if window.mode != previous_mode:
		window.mode = previous_mode


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
	elif key.begins_with("display."):
		_apply_render_options()
	elif _services != null:
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


## 渲染性能选项（options 文件 / --perf-* 命令行都可控）：
##   display.msaa    0/1/2/3 → off/2x/4x/8x（默认沿工程 2x）
##   display.ssr     bool   → 屏幕空间反射开关（默认开）
##   display.ssao    bool   → SSAO 开关（默认开）
##   display.gi      bool   → VoxelGI 开关（默认开）
func _apply_render_options() -> void:
	# --perf-* 命令行覆盖（基准实验用，不进存档）：--perf-msaa=0
	# --perf-ssr=0 --perf-ssao=0 --perf-gi=0 --perf-scale=0.85
	var cli := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perf-"):
			var kv := a.trim_prefix("--perf-").split("=", false, 1)
			if kv.size() > 1:
				cli[kv[0]] = kv[1]
	var vp := get_viewport()
	var msaa: Variant = cli.get("msaa", null)
	if msaa == null and _options.has_section_key("game", "display.msaa"):
		msaa = get_option("display.msaa", 1)
	if msaa != null:
		vp.msaa_3d = int(msaa)
	else:
		vp.msaa_3d = Viewport.MSAA_2X
	var scale3d: Variant = cli.get("scale", null)
	if scale3d != null:
		vp.scaling_3d_scale = float(scale3d)
		if not is_equal_approx(vp.scaling_3d_scale, 1.0):
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	else:
		vp.scaling_3d_scale = 1.0
	var ssr: Variant = cli.get("ssr", null)
	var ssao: Variant = cli.get("ssao", null)
	if ssr == null and _options.has_section_key("game", "display.ssr"):
		ssr = get_option("display.ssr", true)
	if ssao == null and _options.has_section_key("game", "display.ssao"):
		ssao = get_option("display.ssao", true)
	if ssr != null or ssao != null:
		var env := _find_env()
		if env != null:
			if ssr != null:
				env.ssr_enabled = bool(int(str(ssr))) if str(ssr) in ["0","1"] else bool(ssr)
			if ssao != null:
				env.ssao_enabled = bool(int(str(ssao))) if str(ssao) in ["0","1"] else bool(ssao)
	var gi: Variant = cli.get("gi", null)
	if gi == null and _options.has_section_key("game", "display.gi"):
		gi = get_option("display.gi", true)
	if gi != null:
		var want: bool = bool(int(str(gi))) if str(gi) in ["0","1"] else bool(gi)
		var current := get_tree().current_scene
		if current != null:
			for n in current.find_children("*", "VoxelGI", true, false):
				(n as VoxelGI).visible = want


func _find_env() -> Environment:
	var current := get_tree().current_scene
	if current == null:
		return null
	for n in current.find_children("*", "WorldEnvironment", true, false):
		return (n as WorldEnvironment).environment
	return null


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
	_drop_nav_view()
	if _services != null:
		_services.call("stop")
	_active = index
	_debug_hud.visible = _debug_on and _active >= 0
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
	_apply_render_options()
	if index < 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tree.root.title = "TURN" if index < 0 else "TURN · " + String(Catalog.get_entry(index)[0])
	if is_instance_valid(_loading):
		var snd_node: Node = _services.get("snd") if _services != null else null
		if snd_node != null and snd_node.has_method("is_prewarming"):
			while bool(snd_node.call("is_prewarming")):
				await get_tree().process_frame
			if snd_node.has_method("finish_prewarm"):
				snd_node.call("finish_prewarm")
		var warmup_root := _warmup_shaders(current)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if warmup_root != null and is_instance_valid(warmup_root):
			warmup_root.queue_free()
		await RenderingServer.frame_post_draw
		_end_loading()
		current.process_mode = current_mode
	_changing = false


## 关卡加载遮罩期间预热全部 Shader / Vulkan 管线，避免进入战斗后前 10 秒首次出现某特效/材质时卡顿。
func _warmup_shaders(scene: Node) -> Node3D:
	if DisplayServer.get_name() == "headless" or scene == null:
		return null
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mats := {}
	var collect := func(root: Node) -> void:
		if root == null:
			return
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.material_override != null:
				mats[m3.material_override.get_instance_id()] = m3.material_override
			if m3.mesh != null:
				for si in m3.mesh.get_surface_count():
					var sm := m3.mesh.surface_get_material(si)
					if sm != null:
						mats[sm.get_instance_id()] = sm
		for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
			var mm3 := mmi as MultiMeshInstance3D
			if mm3.material_override != null:
				mats[mm3.material_override.get_instance_id()] = mm3.material_override
	collect.call(scene)
	var fx_node: Node = _services.get("fx") if _services != null else null
	collect.call(fx_node)
	var df_script = load("res://core/death_fracture.gd")
	if df_script != null:
		var cm: Material = df_script.call("_cap_material")
		if cm != null:
			mats[cm.get_instance_id()] = cm
	var bs_script = load("res://core/blade_scorch.gd")
	if bs_script != null:
		var smat: Material = bs_script.call("ensure_material")
		if smat != null:
			mats[smat.get_instance_id()] = smat
	if mats.is_empty():
		return null
	var holder := Node3D.new()
	holder.name = "ShaderWarmup"
	holder.position = Vector3(0.0, 0.0, -2.5)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	for k in mats:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mats[k]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	cam.add_child(holder)
	return holder


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
