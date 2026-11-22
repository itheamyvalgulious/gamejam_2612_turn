extends Node3D
## LEVIATHAN interactive studio: arena, camera, boss, target and a purpose
## built control panel (roles, phase, cut, camera presets, live parameters).

const STAGE := preload("res://scripts/boss_stage.gd")
const BOSS_SCENE := preload("res://scenes/character.tscn")
const DUMMY := preload("res://scripts/target_dummy.gd")
const MESH := preload("res://scripts/kit/mesh_kit.gd")
const BM := preload("res://scripts/boss/boss_materials.gd")

const PANEL_W := 408
const ORANGE := Color(1.0, 0.36, 0.08)
const CYAN := Color(0.45, 0.78, 1.0)
const DIM := Color(0.58, 0.63, 0.72)

var stage
var boss
var dummy
var camera: Camera3D
var cam_pivot: Node3D
var ui_root: Control
var panel: PanelContainer

var _yaw := 30.0
var _pitch := 9.0
var _dist := 20.5
var _target := Vector3(0, 3.5, 1.5)
var _home := Vector3(30.0, 9.0, 20.5)
var _dragging := false
var _ui_visible := true
var _overlay: ColorRect
var _shot_mode := false
var _shot_index := 0
var _selected := 0

var _status_label: Label
var _info_label: Label
var _target_label: Label
var _tent_buttons: Array[Button] = []
var _auto_btn: Button
var _phase_btns: Array[Button] = []
var _slow: SpinBox
var _speed := 1.0


func _ready() -> void:
	_build_environment_stage()
	_build_camera()
	_spawn_boss()
	_spawn_target()
	_build_ui()
	_build_overlay()
	if OS.get_environment("STUDIO_SHOT") != "":
		_shot_mode = true
		ui_root.visible = false
		_overlay.visible = false
	set_process(true)
	var snap_path := OS.get_environment("STUDIO_SNAP")
	if snap_path != "":
		_auto_snap(snap_path)


func _auto_snap(path: String) -> void:
	for i in 30:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	await snap(path)
	get_tree().quit(0)


# ------------------------------------------------------------------- build

func _build_environment_stage() -> void:
	stage = STAGE.new()
	stage.name = "Stage"
	add_child(stage)
	stage.build()


func _build_camera() -> void:
	cam_pivot = Node3D.new()
	cam_pivot.name = "CamPivot"
	add_child(cam_pivot)
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.05
	camera.far = 220.0
	camera.name = "Camera"
	cam_pivot.add_child(camera)
	_update_camera()


func _spawn_boss() -> void:
	boss = BOSS_SCENE.instantiate()
	boss.name = "Boss"
	add_child(boss)
	if boss.has_signal("scene_param_changed"):
		boss.scene_param_changed.connect(_on_env_param)
		_apply_env()


func _spawn_target() -> void:
	dummy = DUMMY.new()
	dummy.name = "Target"
	add_child(dummy)
	dummy.set_target_pos(Vector3(0, 0, 13.0))
	boss.set_target_node(dummy)
	boss.set_target(dummy.chest_world(), dummy.ground_world())


func _apply_env() -> void:
	if stage == null or stage.world_env == null or boss == null:
		return
	stage.world_env.ambient_light_energy = boss.get_param("env_energy") * 0.95
	stage.world_env.tonemap_exposure = boss.get_param("env_exposure")


func _on_env_param(key: String, value: float) -> void:
	if stage == null or stage.world_env == null:
		return
	if key == "env_energy":
		stage.world_env.ambient_light_energy = value * 0.95
	elif key == "env_exposure":
		stage.world_env.tonemap_exposure = value


# ----------------------------------------------------------------- process

func _process(dt: float) -> void:
	if boss and dummy and not _shot_mode:
		boss.set_target(dummy.chest_world(), dummy.ground_world())
	if boss and not _shot_mode:
		boss.time_scale = _speed
	_update_ui()
	if _shot_mode:
		pass


# ---------------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	# title bottom-left
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 26
	box.offset_right = 720
	box.offset_top = -138
	box.offset_bottom = -26
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(box)
	var accent := ColorRect.new()
	accent.color = Color(1.0, 0.34, 0.07, 0.9)
	accent.custom_minimum_size = Vector2(58, 2)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(accent)
	var title := Label.new()
	title.text = "LEVIATHAN // ABYSSAL WARDEN"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.94, 0.95, 0.98))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "8 independent limbs · 2 attack / 5 support cap · 2 phases · code-generated"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.58, 0.63, 0.72))
	box.add_child(sub)

	# right panel
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W - 16.0
	panel.offset_right = -16.0
	panel.offset_top = 14.0
	panel.offset_bottom = -14.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.016, 0.019, 0.027, 0.94)
	sb.border_color = Color(0.30, 0.45, 0.62, 0.42)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	ui_root.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)

	# header
	var head := HBoxContainer.new()
	col.add_child(head)
	var t1 := Label.new()
	t1.text = "BOSS // CONTROL"
	t1.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30))
	t1.add_theme_font_size_override("font_size", 14)
	head.add_child(t1)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", DIM)
	_status_label.add_theme_font_size_override("font_size", 11)
	head.add_child(_status_label)

	# stats
	var stats := PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.035, 0.045, 0.060, 0.7)
	ssb.set_corner_radius_all(2)
	ssb.content_margin_left = 7
	ssb.content_margin_right = 7
	ssb.content_margin_top = 5
	ssb.content_margin_bottom = 5
	stats.add_theme_stylebox_override("panel", ssb)
	col.add_child(stats)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 11)
	_info_label.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90))
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_child(_info_label)

	col.add_child(_section("TENTACLES // SELECT"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	for i in 8:
		var b := Button.new()
		b.text = "T%d" % (i + 1)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(176, 27)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func() -> void: _select_tent(i))
		grid.add_child(b)
		_tent_buttons.append(b)

	var act := GridContainer.new()
	act.columns = 3
	act.add_theme_constant_override("h_separation", 4)
	act.add_theme_constant_override("v_separation", 4)
	col.add_child(act)
	_action_btn(act, "IDLE", func() -> void: _force("idle"))
	_action_btn(act, "SUPPORT", func() -> void: _force("support"))
	_action_btn(act, "ATTACK 1", func() -> void: _force("attack1"))
	_action_btn(act, "ATTACK 2", func() -> void: _force("attack2"))
	_action_btn(act, "ATTACK 3", func() -> void: _force("attack3"))
	_action_btn(act, "CUT LIMB", func() -> void: _cut())

	col.add_child(_section("BOSS // GLOBAL"))
	var g1 := GridContainer.new()
	g1.columns = 3
	g1.add_theme_constant_override("h_separation", 4)
	g1.add_theme_constant_override("v_separation", 4)
	col.add_child(g1)
	_auto_btn = Button.new()
	_auto_btn.text = "AUTO ROLES: ON"
	_auto_btn.toggle_mode = true
	_auto_btn.button_pressed = true
	_auto_btn.custom_minimum_size = Vector2(0, 27)
	_auto_btn.add_theme_font_size_override("font_size", 11)
	_auto_btn.toggled.connect(_on_auto)
	g1.add_child(_auto_btn)
	var p1 := Button.new()
	p1.text = "PHASE 1"
	p1.custom_minimum_size = Vector2(0, 27)
	p1.add_theme_font_size_override("font_size", 11)
	p1.pressed.connect(func() -> void: boss.set_phase_force(1))
	g1.add_child(p1)
	_phase_btns.append(p1)
	var p2 := Button.new()
	p2.text = "PHASE 2"
	p2.custom_minimum_size = Vector2(0, 27)
	p2.add_theme_font_size_override("font_size", 11)
	p2.pressed.connect(func() -> void: boss.set_phase_force(2))
	g1.add_child(p2)
	_phase_btns.append(p2)
	_action_btn(g1, "AUTO PHASE", func() -> void: boss.set_phase_force(0))
	_action_btn(g1, "RESET BOSS", func() -> void: boss.reset_boss())
	_action_btn(g1, "FIRE LASER", func() -> void: boss.fire_laser())

	col.add_child(_section("TARGET"))
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 6)
	col.add_child(tr)
	_action_btn(tr, "MOVE TARGET", func() -> void: _move_target())
	_target_label = Label.new()
	_target_label.add_theme_color_override("font_color", DIM)
	_target_label.add_theme_font_size_override("font_size", 11)
	_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(_target_label)

	col.add_child(_section("CAMERA"))
	var cg := GridContainer.new()
	cg.columns = 4
	cg.add_theme_constant_override("h_separation", 4)
	cg.add_theme_constant_override("v_separation", 4)
	col.add_child(cg)
	_cam_btn(cg, "HERO", 30, 9, 20.5, Vector3(0, 3.5, 1.5))
	_cam_btn(cg, "FRONT", 0, 5, 21, Vector3(0, 3.4, 0.5))
	_cam_btn(cg, "SIDE", 90, 7, 23, Vector3(0, 3.4, 0.5))
	_cam_btn(cg, "LOW", 18, -5, 18, Vector3(0, 2.5, 0))
	_cam_btn(cg, "EYE", 12, 7, 7.4, Vector3(0, 3.7, 1.4))
	_cam_btn(cg, "TOP", 10, 55, 30, Vector3(0, 2.2, 1.5))
	_cam_btn(cg, "ATTACK", 66, 10, 21, Vector3(0.2, 3.0, 6.8))
	_cam_btn(cg, "CORE", 6, 6, 6.5, Vector3(0, 3.6, 1.6))

	col.add_child(_section("LIVE PARAMETERS"))
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 2)
	col.add_child(pbox)
	for spec in boss.param_specs():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		pbox.add_child(row)
		var lab := Label.new()
		lab.text = str(spec["label"])
		lab.custom_minimum_size = Vector2(170, 0)
		lab.add_theme_font_size_override("font_size", 11)
		lab.add_theme_color_override("font_color", Color(0.76, 0.80, 0.87))
		row.add_child(lab)
		var spin := SpinBox.new()
		spin.min_value = float(spec["min"])
		spin.max_value = float(spec["max"])
		spin.step = float(spec["step"])
		spin.value = float(spec["value"])
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.custom_minimum_size = Vector2(90, 0)
		spin.add_theme_font_size_override("font_size", 11)
		var key := str(spec["key"])
		spin.value_changed.connect(func(v: float) -> void: boss.set_param(key, v))
		row.add_child(spin)

	col.add_child(_section("SIMULATION"))
	var sim := HBoxContainer.new()
	sim.add_theme_constant_override("separation", 6)
	col.add_child(sim)
	var sb2 := Button.new()
	sb2.text = "PAUSE"
	sb2.toggle_mode = true
	sb2.add_theme_font_size_override("font_size", 11)
	sb2.toggled.connect(func(on: bool) -> void: boss.paused = on; sb2.text = "PLAY" if on else "PAUSE")
	sim.add_child(sb2)
	var sl := Label.new()
	sl.text = "SPEED"
	sl.add_theme_color_override("font_color", DIM)
	sl.add_theme_font_size_override("font_size", 11)
	sim.add_child(sl)
	_slow = SpinBox.new()
	_slow.min_value = 0.1
	_slow.max_value = 2.0
	_slow.step = 0.05
	_slow.value = 1.0
	_slow.custom_minimum_size = Vector2(90, 0)
	_slow.add_theme_font_size_override("font_size", 11)
	_slow.value_changed.connect(func(v: float) -> void: _speed = v)
	sim.add_child(_slow)

	var hint := Label.new()
	hint.text = "LMB orbit · wheel zoom · F reset · SPACE pause · H hide UI · 1-8 limb · I/U support · J/K/L attacks · C cut · P phase"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.40, 0.45, 0.54))
	hint.add_theme_font_size_override("font_size", 10)
	col.add_child(hint)

	_update_tent_buttons()


func _section(text: String) -> Control:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 1)
	var lab := Label.new()
	lab.text = text
	lab.add_theme_color_override("font_color", CYAN)
	lab.add_theme_font_size_override("font_size", 10)
	holder.add_child(lab)
	var line := ColorRect.new()
	line.color = Color(0.20, 0.32, 0.44, 0.55)
	line.custom_minimum_size = Vector2(0, 1)
	holder.add_child(line)
	return holder


func _action_btn(host: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 27)
	b.add_theme_font_size_override("font_size", 11)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	host.add_child(b)
	return b


func _cam_btn(host: Container, text: String, yaw: float, pitch: float,
		dist: float, target: Vector3) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(86, 25)
	b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(func() -> void: set_view(yaw, pitch, dist, target))
	host.add_child(b)


func _select_tent(i: int) -> void:
	_selected = i
	_update_tent_buttons()


func _force(what: String) -> void:
	if boss.force_role(_selected, what):
		_update_tent_buttons()
	else:
		_flash_status("cannot assign %s (slot cap)" % what)


func _cut() -> void:
	if not boss.cut_tentacle(_selected):
		_flash_status("cannot cut (lock: 3 limbs min)")


func _on_auto(on: bool) -> void:
	boss.set_auto(on)
	_auto_btn.text = "AUTO ROLES: ON" if on else "AUTO ROLES: OFF"


func _move_target() -> void:
	var g: Vector3 = boss.random_target()
	dummy.set_target_pos(g)
	boss.set_target(dummy.chest_world(), dummy.ground_world())


var _flash_t := 0.0


func _flash_status(msg: String) -> void:
	_flash_t = 2.0
	_status_label.text = msg


func _update_tent_buttons() -> void:
	if boss == null:
		return
	for i in 8:
		var b := _tent_buttons[i]
		b.button_pressed = i == _selected
		var tn = boss.tents[i]
		var suffix := ""
		if not tn.alive:
			suffix = "DEAD"
		elif tn.role == "attack":
			suffix = "ATK%d" % tn.attack_kind
		else:
			suffix = tn.role.to_upper()
		b.text = "T%d  ·  %s" % [i + 1, suffix]
		if i == _selected:
			b.modulate = Color(1.15, 1.02, 0.86)
		else:
			b.modulate = Color(0.85, 0.9, 1.0) if tn.alive else Color(0.45, 0.45, 0.5)


func _update_ui() -> void:
	if boss == null or _info_label == null:
		return
	_flash_t = maxf(0.0, _flash_t - get_process_delta_time())
	var st: Dictionary = boss.status()
	if _flash_t <= 0.0:
		_status_label.text = "%d Hz  ·  %.1f m" % [Engine.get_frames_per_second(),
			_target_label_dist()]
	var laser := str(st["laser"]).to_upper()
	var phase_txt := "PHASE 1  //  SEALED OPTIC" if int(st["phase"]) == 1 else "PHASE 2  //  CORE EXPOSED"
	var clear: float = st["min_clear"]
	var clear_txt := "—" if clear > 900.0 else "%.2f m" % clear
	_info_label.text = "%s\nLIVE %d/8    SHELL %d%%    CORE %d%%\nSUPPORT %d   ATTACK %d   IDLE %d\nLASER %s   BEAM %.1f m   MIN GAP %s\nBODY %.2f m   ·   LAST %s" % [
		phase_txt, int(st["live"]), int(round(float(st["shell"]) * 100.0)),
		int(round(float(st["core"]) * 100.0)),
		int(st["support"]), int(st["attack"]), int(st["idle"]),
		laser, float(st["beam"]), clear_txt, float(st["body_h"]), str(st["last_hit"])]
	_update_tent_buttons()
	if _phase_btns.size() == 2:
		_phase_btns[0].modulate = Color(1.1, 1.0, 0.9) if boss.phase == 1 else Color(0.6, 0.6, 0.65)
		_phase_btns[1].modulate = Color(1.1, 1.0, 0.9) if boss.phase == 2 else Color(0.6, 0.6, 0.65)
	if _target_label:
		_target_label.text = "dist %.1f m  ·  XZ %.1f, %.1f" % [
			dummy.global_position.distance_to(Vector3.ZERO),
			dummy.global_position.x, dummy.global_position.z]


func _target_label_dist() -> float:
	if dummy == null:
		return 0.0
	return dummy.global_position.distance_to(Vector3.ZERO)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Grade"
	layer.layer = 2
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.material = BM.overlay()
	layer.add_child(_overlay)


# ------------------------------------------------------------------- camera

func set_view(yaw: float, pitch: float, dist: float, target: Vector3) -> void:
	_yaw = yaw
	_pitch = pitch
	_dist = dist
	_target = target
	_update_camera()


func reset_view() -> void:
	set_view(_home.x, _home.y, _home.z, Vector3(0, 3.5, 1.5))


func _update_camera() -> void:
	if cam_pivot == null:
		return
	cam_pivot.position = _target
	var y := deg_to_rad(_yaw)
	var p := deg_to_rad(_pitch)
	var offset := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * _dist
	camera.position = offset
	camera.look_at(cam_pivot.global_position, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if _shot_mode:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(5.0, _dist * 0.92)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(90.0, _dist * 1.08)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.30
		_pitch = clampf(_pitch + mm.relative.y * 0.24, -20.0, 78.0)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_F:
				reset_view()
			KEY_H:
				_ui_visible = not _ui_visible
				ui_root.visible = _ui_visible
			KEY_F12:
				_save_screenshot()
			KEY_SPACE:
				boss.paused = not boss.paused
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				var digits := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]
				_select_tent(digits.find(k.keycode))
			KEY_I:
				_force("idle")
			KEY_U:
				_force("support")
			KEY_J:
				_force("attack1")
			KEY_K:
				_force("attack2")
			KEY_L:
				_force("attack3")
			KEY_C:
				_cut()
			KEY_P:
				boss.set_phase_force(1 if boss.phase == 2 else 2)
			KEY_A:
				boss.set_auto(not boss.auto_roles)
				_auto_btn.button_pressed = boss.auto_roles
				_on_auto(boss.auto_roles)
			KEY_N:
				_move_target()
			KEY_R:
				boss.reset_boss()


func _save_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://renders/manual_%03d.png" % _shot_index
	img.save_png(path)
	_shot_index += 1
	print("[studio] saved ", ProjectSettings.globalize_path(path))


func snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[studio] saved ", path)