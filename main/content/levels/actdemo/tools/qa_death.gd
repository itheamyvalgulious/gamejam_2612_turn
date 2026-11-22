extends Node3D
## QA 3 —— 一击必死：箭 / 刀 / 重击各致死一次，且只死一次
##
## 跑法： godot --headless --path . res://scenes/qa_death.tscn
##
## 全部跑在真 main.tscn 上：死亡 → level.state=dead → death_delay → 重开本关，
## 都走产品自己的流程。

const Qa = preload("res://tools/qa_lib.gd")
const DT := 1.0 / 60.0

var q
var main
var player
var level
var proj


func _ready() -> void:
	Engine.max_fps = 60
	q = Qa.new("qa_death")
	P.reset_all()
	P.set_value("rules.god_mode", false)
	P.set_value("rules.one_hit_kill", true)
	P.set_value("boss.laser_trigger", "disabled")
	P.set_value("rules.death_delay", 0.8)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	player = main.player
	level = main.level
	proj = main.proj
	get_tree().create_timer(150.0).timeout.connect(func(): get_tree().quit(2))

	await _t_arrow()
	await _t_melee()
	await _t_slam()
	await _t_zero_damage()
	await _t_no_double_death()
	await _t_hp_mode()
	print("\n== qa_death: %d checks, %d failed ==" % [q.checks, q.fails])
	get_tree().quit(q.summary())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _until(cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while t < max_s:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
		t += DT
	return bool(cond.call())


func _fresh_level(idx: int) -> void:
	level.start_level(idx)
	P.set_value("rules.god_mode", false)
	P.set_value("rules.one_hit_kill", true)
	await _frames(1)
	await _until(func(): return level.state == "fight", 4.0)


func _reset_and_wait_restart(idx: int) -> void:
	var ok := await _until(func(): return player.alive and level.state != "dead", 3.0)
	q.ok(ok, "死亡后按 death_delay 自动重开（第 %d 关）" % (idx + 1),
		"alive=%s state=%s index=%d" % [str(player.alive), level.state, level.index])


# ------------------------------------------------------------------ 箭
func _t_arrow() -> void:
	q.section("3a 被箭射中 → 死")
	await _fresh_level(0)
	var p: Vector3 = player.rig.global_position
	var from: Vector3 = p + Vector3(0, 3.1, 0) + Vector3(0, 0, -10.0)
	var it: Dictionary = proj.spawn_arrow(from, (p + Vector3(0, 2.3, 0) - from).normalized(),
		30.0, 999.0, "enemy", Color(0.75, 0.35, 1.0))
	var died := await _until(func(): return not player.alive, 2.0)
	q.ok(died, "静止站着被箭命中 → 玩家死亡", "cause=%s" % player.last_cause)
	q.ok(player.last_cause == "被箭射穿", "死因正确", player.last_cause)
	await _frames(2)
	q.ok(level.state == "dead", "关卡状态 = dead", level.state)
	var arrows_after: int = proj.items.size()
	q.ok(arrows_after <= 1, "命中的箭被回收", "剩余飞行物 %d" % arrows_after)
	await _reset_and_wait_restart(0)


# ------------------------------------------------------------------ 刀
func _t_melee() -> void:
	q.section("3b 被小怪的刀砍中 → 死")
	await _fresh_level(0)
	var mob = level.enemies[0]
	var fwd: Vector3 = -player.rig.global_transform.basis.z
	mob.global_position = player.rig.global_position + fwd * 4.0
	mob.rig.move_command = Vector3.ZERO
	var died := await _until(func(): return not player.alive, 8.0)
	q.ok(died, "贴身小怪挥刀命中 → 玩家死亡", "cause=%s" % player.last_cause)
	q.ok(player.last_cause == "被斩中", "死因正确", player.last_cause)
	await _reset_and_wait_restart(0)


# ------------------------------------------------------------------ 重击
func _t_slam() -> void:
	q.section("3c 被大怪重击碾中（半径内）→ 死")
	await _fresh_level(2)
	var boss = level.enemies[0]
	# 站到大怪身边 5 m（< slam_radius 9）
	boss.global_position = player.rig.global_position + Vector3(0, 0, -8.0)
	player.rig.global_position = boss.global_position + Vector3(0, 0, 5.0)
	# 跳过刀气阶段，直接让它进冲撞/重击（不改伤害逻辑，只挪状态机进度）
	# 用 _enter() 而不是直接改 state：它会顺手打断还没播完的攻击动画，
	# 否则上一段的挥砍扫掠会横跨这次瞬移，打出一次假命中
	boss._enter("gap2")
	var died := await _until(func(): return not player.alive, 8.0)
	q.ok(died, "站在重击半径内 → 玩家死亡", "cause=%s" % player.last_cause)
	q.ok(player.last_cause == "被重击碾碎", "死因正确", player.last_cause)
	await _reset_and_wait_restart(2)


# ------------------------------------------------------------------ 零伤害
func _t_zero_damage() -> void:
	q.section("3f 0 点伤害的攻击不该秒杀")
	P.set_value("rules.god_mode", false)
	P.set_value("rules.one_hit_kill", true)
	await _fresh_level(0)
	q.ok(player.alive, "前置：玩家活着")
	player.hurt(0.0, Vector3.UP, "零伤害")
	q.ok(player.alive, "hurt(0) 不应该让玩家死",
		"alive=%s cause=%s（伤害为 0 仍判定死亡 → 参数调到 0 也照样秒人）" % [
			str(player.alive), player.last_cause])
	if not player.alive:
		await _reset_and_wait_restart(0)


# ------------------------------------------------------------------ 只死一次
func _t_no_double_death() -> void:
	q.section("3d 只死一次：死亡后的重复伤害不产生第二次死亡")
	# 目前玩家已经在大怪关重开（活着）
	q.ok(player.alive, "当前活着", "state=%s" % level.state)
	P.set_value("rules.god_mode", false)
	player.hurt(999.0, Vector3.UP, "第一次")
	var cause1: String = player.last_cause
	await _frames(3)
	var state_after_first: String = level.state
	# 连打三下，换不同的死因
	player.hurt(999.0, Vector3.UP, "第二次")
	player.hurt(1.0, Vector3.UP, "第三次")
	await _frames(2)
	q.ok(not player.alive, "玩家仍是死亡状态")
	q.ok(player.last_cause == cause1, "死因不被后续伤害覆盖（hurt 提前 return）",
		"first=%s now=%s" % [cause1, player.last_cause])
	q.ok(state_after_first == "dead" and level.state == "dead", "关卡只进入 dead 一次（没有重置计时）",
		"state=%s" % level.state)
	await _reset_and_wait_restart(level.index)


# ------------------------------------------------------------------ 血量模式（新加的开关）
func _t_hp_mode() -> void:
	q.section("3e rules.one_hit_kill=false 时应该是扣血而不是秒杀")
	P.set_value("rules.god_mode", false)
	P.set_value("rules.one_hit_kill", false)
	player.reset(level.arena["player_spawn"])
	await _frames(1)
	var hp0: float = player.hp
	player.hurt(999.0, Vector3.UP, "非致命一击")
	q.ok(player.alive, "关掉一击必死后，一次伤害不致死",
		"alive=%s hp=%.1f/%.1f" % [str(player.alive), player.hp, hp0])
	q.ok(player.hp < hp0, "血量确实下降", "%.1f → %.1f" % [hp0, player.hp])
	var hp1: float = player.hp
	player.hurt(999.0, Vector3.UP, "无敌帧内再打")
	q.ok(is_equal_approx(player.hp, hp1), "受击无敌时间内不再掉血",
		"%.1f → %.1f（invuln=%.2f）" % [hp1, player.hp, P.getf("rules.invuln_time")])
	P.set_value("rules.one_hit_kill", true)
