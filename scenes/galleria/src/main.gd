extends Node3D
## 主循环：装配一切，跑固定步长的战斗模拟。
##
## 手感参数全部来自 P（~ 面板实时改）；按键全部来自 B（Esc 面板重绑）。

const GameHudScene = preload("res://src/game/hud.gd")
const FpViewmodelScene = preload("res://src/game/fp_viewmodel.gd")
const FpMaskScene = preload("res://src/game/fp_mask.gd")
const ReplayScene = preload("res://src/game/replay.gd")
const Tuning = preload("res://src/ui/tuning.gd")
const BindsPanel = preload("res://src/ui/binds_panel.gd")

var player: PlayerUnit
var cam: GameCam
var level: LevelUnit
var proj: Projectiles
var hud
var tuning
var binds

var hitstop := 0.0
var fp_vm
var fp_mask
var _fp_mask_on := false
var replay
var _cam_mode_before := ""
var _block_banner_cd := 0.0
var _open_frame := -1
var _last_state := ""


func _ready() -> void:
	set_process(false)
	var interface_font: Font = load("res://assets/fonts/ui_font.tres")
	if interface_font != null:
		ThemeDB.fallback_font = interface_font
	get_window().title = ProjectSettings.get_setting("application/config/name")
	proj = Projectiles.new()
	proj.name = "Projectiles"
	add_child(proj)

	cam = GameCam.new()
	cam.name = "Camera"
	add_child(cam)

	player = PlayerUnit.new()
	player.name = "Player"
	add_child(player)
	player.set_camera(cam)
	player.projectiles = proj
	cam.set_rig(player.rig)
	cam.pitch = -0.16
	cam.set_first_person(P.gets("cam.mode") == "first")

	level = preload("res://src/encounter/level.gd").new()
	level.name = "Level"
	add_child(level)
	level.setup(player, proj, cam)

	hud = GameHudScene.new()
	hud.name = "Hud"
	add_child(hud)

	tuning = Tuning.new()
	tuning.name = "Tuning"
	add_child(tuning)

	binds = BindsPanel.new()
	binds.name = "Binds"
	add_child(binds)

	level.on_level_changed = func(i: int, name_cn: String, hint: String) -> void:
		hud.set_level(i, name_cn, hint)
		hud.show_banner(level.arena["name_cn"], level.arena["hint"], 5.0)
		hud.clear_death()
	hud.set_hint("左键攻击 · 配合 A/D/S 出方向斩 · 右键弹反 · V 视角 · Tab 第一人称视野 · ~ 参数 · Esc 暂停")

	fp_vm = FpViewmodelScene.new()
	fp_vm.name = "FpViewmodel"
	cam.camera.add_child(fp_vm)
	fp_vm.setup(player.PALETTE)
	fp_vm.visible = false

	# 第三人称「第一人称视野黑幕」（Tab）：挂在相机下，和第一人称手持模型同一位置
	fp_mask = FpMaskScene.new()
	fp_mask.name = "FpVisionMask"
	cam.camera.add_child(fp_mask)

	replay = ReplayScene.new()
	replay.name = "Replay"
	add_child(replay)
	replay.setup(player, level, proj)

	level.start_level(0)
	set_process(true)
	Snd.set_arena(level.arena)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _menus_open() -> bool:
	return (tuning != null and tuning.is_open()) or (binds != null and binds.is_open())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _menus_open() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
	if _menus_open():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_close_menus()
			return
		if binds.is_open():
			binds.handle_input(event)
		else:
			tuning.handle_input(event)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam.look(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_open_pause()


func _close_menus() -> void:
	tuning.close()
	binds.close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 关键：同一帧里 Esc 既关菜单又会被 B.just("pause") 轮询到，导致"关不掉"
	# 把本帧标记成"刚关闭"，跳过这一帧的热键轮询
	_open_frame = Engine.get_process_frames() + 1


func _open_pause() -> void:
	binds.open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_open_frame = Engine.get_process_frames() + 1


func _process(delta: float) -> void:
	var frames := Engine.get_process_frames()
	if not _menus_open() and frames != _open_frame:
		if B.just("tuning"):
			tuning.open()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_open_frame = frames + 1
		if B.just("pause"):
			_open_pause()
		if B.just("cam_mode"):
			cam.toggle_mode()
		if B.just("fp_mask"):
			_fp_mask_on = not _fp_mask_on
			if cam.first_person and _fp_mask_on:
				hud.show_banner("第一人称视野黑幕", "你已经就在第一人称画面里 —— 按 V 切第三人称再看", 1.8)
		if B.just("restart"):
			restart_level()
		if B.just("next_level"):
			next_level()
		if B.just("hud_toggle"):
			hud.set_hud_visible(not hud.visible)

	_block_banner_cd = maxf(0.0, _block_banner_cd - delta)
	if _menus_open():
		# 面板里的"继续游戏"按钮不经过 _close_menus，这里兜底：无菜单就锁鼠标
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and get_window().has_focus():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	Snd.sync_params()
	if B.just("audio_test"):
		Snd.test_surround()
	if B.just("replay_toggle"):
		if replay.active:
			replay.stop()
			P.set_value("cam.mode", _cam_mode_before)
		else:
			_cam_mode_before = P.gets("cam.mode")
			P.set_value("cam.mode", "third")
			replay.start()
			hud.set_state("回放中")

	var dt := minf(delta, 0.05) * P.getf("rules.time_scale")
	if Fx != null:
		Fx.time_scale = 1.0
	if hitstop > 0.0:
		hitstop = maxf(0.0, hitstop - delta)
		if P.getb("rules.hitstop"):
			dt *= 0.06
			if Fx != null:
				Fx.time_scale = 0.06

	# ---------------- 回放模式：不模拟，只写回录下来的变换
	if replay.active:
		replay.step(dt)
		cam.step(dt, level.arena)
		level.constrain_camera()
		fp_vm.visible = false
		_update_fp_mask()
		var evs := ""
		for ev in replay.cur_events:
			evs += "  [%s]" % String(ev["k"])
		hud.set_state("回放 %.0f%% · Del 退出 · 橙十字=刀身判定圆盘  青圈=敌人判定件  绿/红叉=命中/被格挡%s"
			% [replay.progress() * 100.0, evs])
		hud.set_first_person(false)
		return

	# ---------------- 模拟
	var ctx := level.context()
	if player.alive:
		level.prepare_player()
		player.step(dt, level.arena, level.enemies)
		level.constrain_player()
	level.step(dt, ctx)
	var p_events := Combat.player_swing(player, level.combat_targets(), cam, level.arena.get("walls", []))
	for ev in p_events:
		_on_combat_event(ev)
	for e in level.enemies:
		if is_instance_valid(e) and e.alive and level.melee_clear(e.center(), player.rig.global_position + Vector3(0, 2.3, 0)):
			var r := Combat.enemy_swing(e, player)
			if bool(r.get("hit", false)):
				Snd.play_at("hit", r.get("pos", Vector3.ZERO), {"gain": 1.1})
				if Fx != null:
					Fx.screen_flash(0.3, Color(0.9, 0.1, 0.1))
				hitstop = maxf(hitstop, 0.04)
			elif bool(r.get("parried", false)):
				_on_melee_parry(r)
	replay.record()
	var proj_events := proj.step(dt, ctx)
	for ev in proj_events:
		_on_projectile_event(ev)

	# 死亡
	if not player.alive and level.state != "dead" and level.state != "finished":
		level.on_player_died()
		hud.flash_death(player.last_cause if player.last_cause != "" else "你死了")
		hud.show_banner("", "", 0.01)
	elif level.state == "clear" and _last_state != "clear":
		hud.show_banner("本关通过", "区域已肃清", 1.4)
	elif level.state == "finished" and _last_state != "finished":
		hud.show_banner("全部通关", "按 R 重开本关", 6.0)
	_last_state = level.state

	# ---------------- 相机 / HUD
	cam.step(dt, level.arena)
	level.constrain_camera()
	fp_vm.visible = cam.first_person
	if cam.first_person:
		fp_vm.update(dt, player)
	_update_fp_mask()
	hud.set_enemy_count(level.alive_count(), level.total_enemies)
	hud.set_first_person(cam.first_person)
	hud.set_markers(level.build_markers())
	var blocking := 0
	for e in level.enemies:
		if is_instance_valid(e) and e.alive and e.blocks_when_seen() \
				and Vision.is_visible(cam.camera, e.center(), e.mark_radius()):
			blocking += 1
	if player.is_parrying():
		var tag := player.parry_plan_label()
		hud.set_state("弹反窗口 %.0f%%%s" % [player.parry_progress() * 100.0,
			(" · 架刀：" + tag) if tag != "" else ""])
	elif player.is_guard_up():
		hud.set_state("刀还架着（收势中）· 架刀：%s" % player.parry_plan_label())
	elif blocking > 0:
		hud.set_state("⚠ 画面里 %d 个敌人在格挡 —— 转开视线 / 按 V" % blocking)
	elif player.rig.is_attacking:
		hud.set_state("出刀中 · %s" % player.rig.attack_name)
	else:
		hud.set_state("")


## 第三人称「第一人称视野黑幕」：Tab 开关，第一人称下自动关掉
## （那里的画面本身就是答案，黑幕没有意义）。Replay 里也生效：回放查视野正好用得上。
func _update_fp_mask() -> void:
	var on: bool = _fp_mask_on and not cam.first_person
	fp_mask.set_active(on)
	if on:
		fp_mask.step(cam.fp_proj_view(), P.getf("cam.mask_soft"))
	hud.set_fp_mask(on)


func _on_combat_event(ev: Dictionary) -> void:
	var pos: Vector3 = ev.get("pos", Vector3.ZERO)
	replay.note_event(String(ev["kind"]), pos)
	match String(ev["kind"]):
		"block":
			# 被格挡 = 它在你画面里。反馈要醒目到不可能忽略：
			Snd.play_at("clang", pos, {"gain": 1.6, "prio": 4})
			if Fx != null:
				Fx.clang(pos, ev.get("normal", Vector3.UP))
				Fx.impact_ring(pos, 3.4, 1.6)
				Fx.screen_flash(0.22, Color(0.45, 0.9, 1.0))
				Fx.shake(0.7)
			hud.flash_block()
			if _block_banner_cd <= 0.0:
				_block_banner_cd = 1.2
				var side: String = "左"
				var ve = ev.get("enemy")
				if ve != null and is_instance_valid(ve) and cam != null:
					var to: Vector3 = ve.center() - player.rig.global_position
					var right: Vector3 = cam.flat_right()
					side = "右" if to.dot(right) > 0.0 else "左"
				hud.show_banner("被格挡", "它在你画面里 —— 朝边缘箭头的方向转身，再用%s斩（%s键）" % [side, "D" if side == "右" else "A"], 1.0)
		"hit", "kill":
			Snd.play_at("hit", pos, {"gain": 0.9})
			if Fx != null:
				Fx.spark(pos, ev.get("normal", Vector3.UP), 1.2)
			hitstop = maxf(hitstop, P.getf("attack.%s.hitstop" % player.last_attack))
			if String(ev["kind"]) == "kill":
				if Fx != null:
					Fx.shake(0.9)


## 架住敌人一刀：免伤 + 被击退，给足反馈（击退本身在 Combat 里就生效了）
func _on_melee_parry(r: Dictionary) -> void:
	var pos: Vector3 = r.get("pos", Vector3.ZERO)
	replay.note_event("parry", pos)
	hitstop = maxf(hitstop, P.getf("parry.block_hitstop"))
	Snd.play_at("parry", pos, {"gain": 1.25, "prio": 4})
	if Fx != null:
		Fx.clang(pos, r.get("normal", Vector3.UP))
		Fx.impact_ring(pos, 2.8, 1.3)
		Fx.screen_flash(0.16, Color(0.55, 0.95, 1.0))
		Fx.shake(0.8)
	hud.flash_parry()


func _on_projectile_event(ev: Dictionary) -> void:
	match String(ev["kind"]):
		"parry":
			Snd.play_at("parry", ev.get("pos", Vector3.ZERO), {"gain": 1.1})
			hud.set_state("弹反成功！")
		"counter":
			hud.set_state("它补射了一箭拦截！")
		"clash":
			Snd.play_at("clang", ev.get("pos", Vector3.ZERO), {"gain": 0.7})
			if Fx != null:
				Fx.spark(ev.get("pos", Vector3.ZERO), Vector3.UP, 1.4)
		"wall":
			if Fx != null:
				Fx.spark(ev.get("pos", Vector3.ZERO), Vector3.UP, 0.5)
		"player_hit":
			if not player.alive:
				hud.flash_death(player.last_cause if player.last_cause != "" else "你被击中")
		"enemy_hit":
			if Fx != null:
				Fx.spark(ev.get("pos", Vector3.ZERO), Vector3.UP, 1.0)


func restart_level() -> void:
	level.start_level(level.index)
	hitstop = 0.0


func next_level() -> void:
	restart_level()
