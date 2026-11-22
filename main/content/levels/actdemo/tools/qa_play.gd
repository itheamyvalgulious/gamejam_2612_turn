extends Node3D
## QA 8 —— 真玩一遍：第一关能不能被打通
##
## 跑法： godot --headless --path . res://scenes/qa_play.tscn
##
## 8a 对照：正对着小怪挥砍 → 必须被挡
## 8b 走位 + 转镜头 + A+左键（左斩）→ 打画面外的它
## 8c 不干预观察：小怪能不能自己走到玩家身边
##
## 无敌开着（只验证攻击/AI 机制），相机转向走 cam.look()（headless 下没有
## MOUSE_MODE_CAPTURED，不能注入 MouseMotion）。

const Qa = preload("res://tools/qa_lib.gd")
const DT := 1.0 / 60.0

var q
var main
var player
var level
var cam


func _ready() -> void:
	Engine.max_fps = 60
	get_window().size = Vector2i(1600, 900)   # headless 默认是 1600×1600，这里恢复 16:9 的真实取景
	q = Qa.new("qa_play")
	P.reset_all()
	P.set_value("rules.god_mode", true)
	P.set_value("move.facing_mode", "camera")
	P.set_value("rules.banner_time", 1.0)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	player = main.player
	level = main.level
	cam = main.cam
	get_tree().create_timer(150.0).timeout.connect(func(): get_tree().quit(2))
	await _t_approach()
	await _t_center_control()
	await _t_side_kill()
	await _t_first_person_compare()
	await _t_boss_visibility()
	await _t_can_it_reach()
	print("\n== qa_play: %d checks, %d failed ==" % [q.checks, q.fails])
	get_tree().quit(q.summary())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _mob():
	for e in level.enemies:
		if is_instance_valid(e) and e.alive and e.kind == "mob":
			return e
	return null


func _angle_to(e) -> float:
	var d: Vector3 = e.rig.global_position - player.rig.global_position
	return atan2(-d.x, -d.z)


func _turn_to(target_yaw: float) -> void:
	var sens: float = P.getf("cam.sensitivity")
	for i in 10:
		var err: float = wrapf(target_yaw - cam.yaw, -PI, PI)
		if absf(err) < deg_to_rad(1.0):
			break
		cam.look(Vector2(-err / sens, 0.0))     # yaw -= dx*sens
		cam.step(DT, level.arena)
		await get_tree().process_frame


func _key(code: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _click() -> void:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = true
	m.position = Vector2(800, 450)
	Input.parse_input_event(m)
	await _frames(2)
	var m2 := InputEventMouseButton.new()
	m2.button_index = MOUSE_BUTTON_LEFT
	m2.pressed = false
	m2.position = Vector2(800, 450)
	Input.parse_input_event(m2)


## 屏幕几何：小怪中心偏离相机光轴多少度、它的包围球张角、横向半 FOV
func _cam_geo(e) -> String:
	var c: Camera3D = cam.camera
	var axis: Vector3 = -c.global_transform.basis.z
	var to: Vector3 = e.center() - c.global_position
	var off: float = rad_to_deg(axis.angle_to(to))
	var rad: float = rad_to_deg(atan(e.mark_radius() / maxf(to.length(), 0.01)))
	var vp: Vector2 = c.get_viewport().get_visible_rect().size
	var half_h: float = rad_to_deg(atan(tan(deg_to_rad(c.fov) * 0.5) * (vp.x / vp.y)))
	return "cam_off=%.0f° sphere=±%.0f° half_h_fov=%.0f° cam_dist=%.1f" % [
		off, rad, half_h, c.global_position.distance_to(player.rig.global_position)]


func _attack_left() -> void:
	_key(KEY_A, true)
	await _frames(1)
	await _click()
	_key(KEY_A, false)


func _wait_attack_done() -> void:
	var guard := 0
	while player.rig.is_attacking and guard < 120:
		await get_tree().process_frame
		guard += 1


# ------------------------------------------------------------------ 走到怪身边
func _t_approach() -> void:
	q.section("8a 走位：第一关小怪不会过来，只能自己走过去")
	var mob = _mob()
	q.ok(mob != null, "第一关有活的小怪")
	if mob == null:
		return
	var t := 0.0
	var d0: float = mob.dist_to_player()
	while mob.dist_to_player() > 5.5 and t < 45.0:
		await _turn_to(_angle_to(mob))
		_key(KEY_W, true)
		await _frames(4)
		_key(KEY_W, false)
		t += 0.1
		if not is_instance_valid(mob) or not mob.alive:
			break
	q.info("开局距离 → 走到", "%.1f m → %.1f m（%.1f s）" % [d0, mob.dist_to_player(), t])
	q.ok(mob.dist_to_player() < 6.5, "玩家能走到小怪身边", "%.1f m" % mob.dist_to_player())


func _t_center_control() -> void:
	q.section("8b 对照：镜头正对着小怪时，刀一定被挡")
	var mob = _mob()
	if mob == null:
		return
	await _turn_to(_angle_to(mob))
	await _frames(2)
	var vis: bool = Vision.is_visible(cam.camera, mob.center(), mob.mark_radius())
	var hp0: float = mob.hp
	player._attack_from_input(Vector2.ZERO)
	await _wait_attack_done()
	q.ok(vis and is_equal_approx(mob.hp, hp0), "正对（可见）→ 0 伤害",
		"可见=%s  hp %.0f → %.0f" % [str(vis), hp0, mob.hp])


# ------------------------------------------------------------------ 侧斩
func _t_side_kill() -> void:
	q.section("8c 真按键：拉开距离 → 转开镜头 → A + 左键（左斩）打画面外的它")
	var mob = _mob()
	if mob == null:
		q.ok(false, "小怪已经不在了")
		return
	var attempts := 0
	var dmg_attempts := 0
	var blocked_attempts := 0
	var miss_attempts := 0
	var budget := 30.0
	while is_instance_valid(mob) and mob.alive and attempts < 8 and budget > 0.0:
		# 1) 面向反方向跑开，把距离拉回 ~6 m（玩家跑 9.5，小怪 5.2）
		var retreat := 0
		while mob.dist_to_player() < 6.0 and retreat < 60:
			await _turn_to(_angle_to(mob) + PI)
			_key(KEY_W, true)
			await _frames(3)
			_key(KEY_W, false)
			retreat += 1
			budget -= 0.1
		# 2) 转开 90°，让小怪在刀弧上、同时远离画面中心
		await _turn_to(_angle_to(mob) - PI * 0.5)
		var guard := 0
		while absf(wrapf(player.rig.heading - cam.yaw, -PI, PI)) > deg_to_rad(8.0) and guard < 90:
			await get_tree().process_frame
			guard += 1
		var vis: bool = Vision.is_visible(cam.camera, mob.center(), mob.mark_radius())
		var d: float = mob.dist_to_player()
		var hp0: float = mob.hp
		attempts += 1
		await _attack_left()
		await _wait_attack_done()
		budget -= 1.2
		var dealt: bool = mob.hp < hp0 - 0.01 or not mob.alive
		if dealt:
			dmg_attempts += 1
		elif vis:
			blocked_attempts += 1
		else:
			miss_attempts += 1
		q.info("#%d" % attempts, "d=%.1fm vis=%s hp %.0f→%.0f %s ｜ %s" % [
			d, str(vis), hp0, mob.hp, "HIT" if dealt else ("BLOCK" if vis else "MISS(out of reach)"),
			_cam_geo(mob)])
		await _frames(6)
	q.ok(is_instance_valid(mob) and not mob.alive, "能用侧斩把小怪打死",
		"%d 次尝试，剩余 hp=%.0f" % [attempts, mob.hp if is_instance_valid(mob) else 0.0])
	q.ok(dmg_attempts >= 1, "画面外的侧斩能造成伤害", "%d 次命中 / %d 次落空" % [dmg_attempts, miss_attempts])
	q.ok(blocked_attempts == 0, "已经转开镜头后不应该再被格挡", "被挡 %d 次" % blocked_attempts)


# ------------------------------------------------------------------ 第一人称对照
func _t_first_person_compare() -> void:
	q.section("8e 同样打法换成第一人称（V）—— 核心机制到底需不需要第一人称")
	level.start_level(0)
	await _frames(2)
	P.set_value("cam.mode", "first")
	await _frames(6)
	var mob = _mob()
	if mob == null:
		q.ok(false, "小怪不存在")
		return
	q.ok(cam.first_person, "已切到第一人称", "first_person=%s" % str(cam.first_person))
	# 走过去
	var t := 0.0
	while mob.dist_to_player() > 5.0 and t < 40.0:
		await _turn_to(_angle_to(mob))
		_key(KEY_W, true)
		await _frames(4)
		_key(KEY_W, false)
		t += 0.1
	# 拉开到 ~5 m（第一人称不用怕贴太近，但保持刀能够到）
	var attempts := 0
	var dmg := 0
	while is_instance_valid(mob) and mob.alive and attempts < 6:
		var retreat := 0
		while mob.dist_to_player() < 4.6 and retreat < 40:
			await _turn_to(_angle_to(mob) + PI)
			_key(KEY_W, true)
			await _frames(3)
			_key(KEY_W, false)
			retreat += 1
		await _turn_to(_angle_to(mob) - PI * 0.5)
		var guard := 0
		while absf(wrapf(player.rig.heading - cam.yaw, -PI, PI)) > deg_to_rad(8.0) and guard < 90:
			await get_tree().process_frame
			guard += 1
		var vis: bool = Vision.is_visible(cam.camera, mob.center(), mob.mark_radius())
		var hp0: float = mob.hp
		attempts += 1
		await _attack_left()
		await _wait_attack_done()
		var dealt: bool = mob.hp < hp0 - 0.01 or not mob.alive
		if dealt:
			dmg += 1
		q.info("#%d" % attempts, "d=%.1fm vis=%s hp %.0f→%.0f %s ｜ %s" % [
			mob.dist_to_player(), str(vis), hp0, mob.hp,
			"HIT" if dealt else "BLOCK/MISS", _cam_geo(mob)])
	q.ok(dmg >= 1, "第一人称下同一套操作能打出伤害", "%d/%d 次命中" % [dmg, attempts])
	q.ok(is_instance_valid(mob) and not mob.alive, "第一人称下能打死",
		"剩余 hp=%.0f" % (mob.hp if is_instance_valid(mob) else 0.0))
	P.set_value("cam.mode", "third")


# ------------------------------------------------------------------ 大怪能不能被「看不见」
func _t_boss_visibility() -> void:
	q.section("8f 第三关：第三人称/第一人称下，「不看着大怪」到底可不可能")
	P.set_value("boss.laser_trigger", "disabled")
	level.start_level(2)
	await _frames(2)
	var boss = level.enemies[0]
	q.ok(boss.kind == "boss", "拿到大怪")
	# 把大怪摆在玩家正前方 22 m
	player.rig.global_position = Vector3(0, 0, 20)
	boss.rig.global_position = Vector3(0, 0, -2)
	await _frames(2)
	P.set_value("cam.mode", "third")
	await _frames(6)
	for deg in [0.0, 90.0, 135.0, 180.0]:
		await _turn_to(deg_to_rad(deg))
		await _frames(12)
		var vis: bool = Vision.is_visible(cam.camera, boss.center(), boss.mark_radius())
		q.info("第三人称 转 %.0f°" % deg, "visible=%s ｜ %s" % [str(vis), _cam_geo(boss)])
		if deg == 180.0:
			q.ok(not vis, "第三人称：背对大怪 180° 时不该被看见（激光才不会秒你）",
				"visible=%s ｜ %s" % [str(vis), _cam_geo(boss)])
	P.set_value("cam.mode", "first")
	await _frames(8)
	await _turn_to(deg_to_rad(180.0))
	await _frames(12)
	var vis_fp: bool = Vision.is_visible(cam.camera, boss.center(), boss.mark_radius())
	q.info("第一人称 转 180°", "visible=%s ｜ %s" % [str(vis_fp), _cam_geo(boss)])
	q.ok(not vis_fp, "第一人称：背对 180° 看不见大怪", "visible=%s" % str(vis_fp))
	P.set_value("cam.mode", "third")


# ------------------------------------------------------------------ 小怪能不能走过来
func _t_can_it_reach() -> void:
	q.section("8d 不干预 20 s：小怪会走到玩家身边吗")
	level.start_level(0)
	await _frames(2)
	var mob = _mob()
	var t := 0.0
	var dmin := 1e9
	var last := 0.0
	var trace: Array = []
	while t < 20.0:
		await get_tree().process_frame
		t += DT
		if int(t * 2.0) != int((t - DT) * 2.0):
			dmin = minf(dmin, mob.dist_to_player())
			if dmin == mob.dist_to_player() or trace.size() < 6:
				pass
			trace.append("%.0fs:%.0fm" % [t, mob.dist_to_player()])
	# 被夹住时小怪卡在哪
	var enemy_node_global: Vector3 = mob.global_position
	var rig_local: Vector3 = mob.rig.position
	var rig_global: Vector3 = mob.rig.global_position
	var b: AABB = level.arena["bounds"]
	q.info("小怪节点 global / rig 局部 / rig 全局", "%s / %s / %s" % [
		str(enemy_node_global), str(rig_local), str(rig_global)])
	q.info("场地 bounds", "pos %s size %s" % [str(b.position), str(b.size)])
	q.info("20 s 距离轨迹", " ".join(trace))
	q.info("玩家位置", str(player.rig.global_position))
	q.ok(dmin < P.getf("mob.attack_range"), "小怪能进入挥刀距离（%.1f m）" % P.getf("mob.attack_range"),
		"最近 %.1f m（停在 %s；rig 局部被夹在 ±%.0f）" % [
			dmin, str(rig_global), (b.size.z * 0.5 - 3.0)])
