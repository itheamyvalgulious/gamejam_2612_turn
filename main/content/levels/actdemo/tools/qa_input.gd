extends Node3D
## QA 1 —— 真按键链路（Input.parse_input_event → B → player.step → rig）
##
## 跑法： godot --headless --path . res://scenes/qa_input.tscn
##
## 用真实的 main.tscn（主循环、autoload P/B、60fps），只从外部注入
## InputEventKey / InputEventMouseButton，不调用玩家内部接口。

const Qa = preload("res://tools/qa_lib.gd")

var q
var main
var player
var level
var cam

var _mv_samples: Array = []
var _just_samples: Array = []
var _watch := false


func _ready() -> void:
	process_priority = -100     # 同一帧里比 main 先跑
	Engine.max_fps = 60
	q = Qa.new("qa_input")
	P.reset_all()
	P.set_value("rules.god_mode", true)     # 本测试只关心输入链路
	P.set_value("move.facing_mode", "camera")
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	player = main.player
	level = main.level
	cam = main.cam
	q.info("main 就绪", "level=%d enemies=%d state=%s" % [level.index, level.enemies.size(), level.state])
	q.info("mouse_mode（headless 无窗口）", str(int(Input.mouse_mode)))

	await _t_move()
	await _t_directions()
	await _t_accel_param()
	await _t_decel_param()
	await _t_attack()
	print("\n== qa_input: %d checks, %d failed ==" % [q.checks, q.fails])
	get_tree().quit(q.summary())


func _process(_dt: float) -> void:
	if _watch:
		_mv_samples.append(B.move_vector())
		_just_samples.append(B.just("attack_light"))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _key(code: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _mouse(btn: int, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = Vector2(800, 450)
	Input.parse_input_event(e)


func _wait_idle() -> void:
	var guard := 0
	while (player.rig.is_attacking or player.rig.jump_state != "GROUND") and guard < 240:
		await get_tree().process_frame
		guard += 1


## 按住 W n 帧后松开，返回松开点与「完全停下」点
func _hold_w(n: int) -> Dictionary:
	var p0: Vector3 = player.rig.global_position
	_watch = true
	_mv_samples.clear()
	_key(KEY_W, true)
	await _frames(n)
	_key(KEY_W, false)
	var p1: Vector3 = player.rig.global_position
	var guard := 0
	while player.rig.speed > 0.05 and guard < 120:
		await get_tree().process_frame
		guard += 1
	_watch = false
	var p2: Vector3 = player.rig.global_position
	return {"travel": Vector2(p1.x - p0.x, p1.z - p0.z).length(),
		"slide": Vector2(p2.x - p1.x, p2.z - p1.z).length(),
		"speed": player.rig.speed, "peak_mv": _max_mv(),
		"frames_pressed": _count_true_pressed()}


func _max_mv() -> float:
	var m := 0.0
	for v in _mv_samples:
		m = maxf(m, (v as Vector2).length())
	return m


func _count_true_pressed() -> int:
	var n := 0
	for v in _mv_samples:
		if (v as Vector2).length() > 0.9:
			n += 1
	return n


# ------------------------------------------------------------------ 1) 移动
func _t_move() -> void:
	q.section("1a 真按键移动：按住 W 半秒")
	q.ok(not main._menus_open(), "没有菜单挡着输入")
	var yaw0: float = cam.yaw
	var r := await _hold_w(30)
	q.ok(B.move_vector().length() < 0.2, "松开 W 后 move_vector 归零", str(B.move_vector()))
	q.ok(float(r["peak_mv"]) > 0.9, "按住 W 时 B.move_vector() 拿到输入",
		"峰值 %.2f（期望 ≈1）" % float(r["peak_mv"]))
	q.ok(int(r["frames_pressed"]) >= 28, "B.move_vector 在按住期间保持",
		"%d/30 帧" % int(r["frames_pressed"]))
	q.ok(float(r["travel"]) > 1.0, "玩家真的移动了（> 1 m）",
		"0.5 s 位移 %.2f m" % float(r["travel"]))
	var p0: Vector3 = player.rig.global_position
	# 方向：再走一小段测朝向（用当前位移近似）
	var fwd := Vector2(-sin(yaw0), -cos(yaw0))
	var r2 := await _hold_w(10)
	var moved_z: float = -(player.rig.global_position.z - p0.z)
	q.ok(moved_z > 0.2, "W 沿相机前方走（世界 -Z）",
		"Δz=%.2f  cam_yaw=%.2f°" % [moved_z, rad_to_deg(yaw0)])
	q.info("松开后的滑行距离（默认参数）", "%.2f m" % float(r["slide"]))


# ------------------------------------------------------------------ 方向
func _t_directions() -> void:
	q.section("1e 默认 move.facing_mode=camera：A / D / S 到底往哪走")
	P.set_value("move.facing_mode", "camera")
	await _frames(20)
	var yaw: float = cam.yaw
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var cases := [
		[KEY_S, "S（后退）", -fwd],
		[KEY_A, "A（左移）", -right],
		[KEY_D, "D（右移）", right],
	]
	for c in cases:
		await _frames(20)
		var p0: Vector3 = player.rig.global_position
		_key(int(c[0]), true)
		await _frames(28)
		_key(int(c[0]), false)
		await _frames(6)
		var p1: Vector3 = player.rig.global_position
		var d := Vector2(p1.x - p0.x, p1.z - p0.z)
		var want: Vector2 = c[2]
		var dot := 0.0 if d.length() < 0.05 else d.normalized().dot(want)
		q.info(String(c[1]), "位移 %s ｜ 期望 %s ｜ dot=%.2f" % [str(d), str(want), dot])
		q.ok(dot > 0.85, "按 %s 朝预期方向走" % String(c[1]),
			"实测方向 dot=%.2f（<0 表示完全走反）" % dot)
	# movement 模式做对照
	q.info("同上，改成 move.facing_mode=movement 做对照", "")
	P.set_value("move.facing_mode", "movement")
	for c in cases:
		await _frames(20)
		var p0: Vector3 = player.rig.global_position
		_key(int(c[0]), true)
		await _frames(28)
		_key(int(c[0]), false)
		await _frames(6)
		var p1: Vector3 = player.rig.global_position
		var d := Vector2(p1.x - p0.x, p1.z - p0.z)
		var dot := 0.0 if d.length() < 0.05 else d.normalized().dot(c[2])
		q.ok(dot > 0.85, "[movement 模式] 按 %s 朝预期方向走" % String(c[1]),
			"dot=%.2f" % dot)
	P.set_value("move.facing_mode", "camera")


# ------------------------------------------------------------------ 参数是否真的生效
func _t_accel_param() -> void:
	q.section("1c 参数生效性：move.accel")
	var a := await _measure_speed_after(15, 24.0)
	var b := await _measure_speed_after(15, 1.0)
	q.ok(absf(a - b) > 0.3, "move.accel 影响起步加速度",
		"accel=24 → %.2f m/s ；accel=1 → %.2f m/s（实测差值 %.2f）" % [a, b, absf(a - b)])
	P.set_value("move.accel", 24.0)


func _measure_speed_after(frames: int, accel: float) -> float:
	P.set_value("move.accel", accel)
	await _frames(30)     # 站稳
	_key(KEY_W, true)
	await _frames(frames)
	var s: float = player.rig.speed
	_key(KEY_W, false)
	await _frames(40)
	return s


func _t_decel_param() -> void:
	q.section("1d 参数生效性：move.decel")
	var a := await _measure_slide_after_release(34.0)
	var b := await _measure_slide_after_release(200.0)
	q.ok(absf(a - b) > 0.2, "move.decel 影响松开后的滑行距离",
		"decel=34 → %.2f m ；decel=200 → %.2f m" % [a, b])
	P.set_value("move.decel", 34.0)


func _measure_slide_after_release(_decel: float) -> float:
	P.set_value("move.decel", _decel)
	await _frames(30)
	_key(KEY_W, true)
	await _frames(30)
	_key(KEY_W, false)
	var p1: Vector3 = player.rig.global_position
	var guard := 0
	while player.rig.speed > 0.05 and guard < 120:
		await get_tree().process_frame
		guard += 1
	var p2: Vector3 = player.rig.global_position
	await _frames(10)
	return Vector2(p2.x - p1.x, p2.z - p1.z).length()


# ------------------------------------------------------------------ 2) 攻击
func _t_attack() -> void:
	q.section("1b 真鼠标左键：出招")
	await _wait_idle()
	q.ok(not player.rig.is_attacking, "出招前处于空闲", "jump=%s" % player.rig.jump_state)

	# 注入左键按下；事件在下一帧被 Input 消化，主循环就在那一帧出招
	_just_samples.clear()
	_watch = true
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _frames(3)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	_watch = false
	var just_frames: Array = []
	for i in _just_samples.size():
		if bool(_just_samples[i]):
			just_frames.append(i)
	q.ok(just_frames.size() >= 1, "parse_input_event(左键) → B.just('attack_light') 为真",
		"命中帧 %s（每帧采样）" % str(just_frames))
	q.ok(player.rig.is_attacking, "主循环真的触发了出招（player.rig.is_attacking）",
		"attack_name=%s  last_attack=%s" % [player.rig.attack_name, player.last_attack])
	q.ok(player.last_attack == "slash_fwd", "没按方向键 → 正前斩", player.last_attack)
	q.info("攻击参数", "windup=%.2f active=%.2f duration=%.2f" % [
		player.rig.attack_hit_from, player.rig.attack_hit_to - player.rig.attack_hit_from,
		player.rig.attack_total])

	# 按住左键不松手：不应像半自动那样连击
	await _wait_idle()
	var n_before: int = player.swing_serial
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _frames(40)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	q.info("按住左键 0.66 s 的挥砍次数", "%d（want 1：按住不连发）" % (player.swing_serial - n_before))

	# 组合键
	await _wait_idle()
	_key(KEY_S, true)
	await _frames(3)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _frames(4)
	_mouse(MOUSE_BUTTON_LEFT, false)
	_key(KEY_S, false)
	q.ok(player.last_attack == "slash_back", "S + 左键 → 回身斩", player.last_attack)
	q.info("回身斩 yaw", "%.3f rad（期望 π）" % player.rig.attack_yaw)
	# 行为断言：出招期间玩家位移几乎为 0（只有前冲）
	var pa: Vector3 = player.rig.global_position
	await _frames(4)
	var pb: Vector3 = player.rig.global_position
	q.info("出招期间位移（4 帧）", "%.2f m" % Vector2(pb.x - pa.x, pb.z - pa.z).length())
