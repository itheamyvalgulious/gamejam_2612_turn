extends Node3D
## QA 2 —— 三关通关流程（真 main.tscn 主循环驱动）
##
## 跑法： godot --headless --path . res://scenes/qa_flow.tscn
##
## 只通过内部接口让敌人死（e.hurt(99999)），流程推进、关卡切换、死亡重开
## 全部走产品自己的 main._process / level.step。

const Qa = preload("res://tools/qa_lib.gd")
const DT := 1.0 / 60.0

var q
var main
var player
var level


func _ready() -> void:
	Engine.max_fps = 60
	q = Qa.new("qa_flow")
	P.reset_all()
	P.set_value("rules.god_mode", true)              # 流程测试：不让怪打断
	P.set_value("rules.time_scale", 1.0)
	P.set_value("rules.banner_time", 1.0)            # 只为了缩短等待（逻辑不变）
	P.set_value("rules.death_delay", 0.8)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	player = main.player
	level = main.level

	get_tree().create_timer(150.0).timeout.connect(func():
		print("  !! 看门狗超时，强制退出")
		get_tree().quit(2))

	await _t_flow()
	await _t_death_restart()
	print("\n== qa_flow: %d checks, %d failed ==" % [q.checks, q.fails])
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


func _kill_all() -> void:
	for e in level.enemies:
		if is_instance_valid(e) and e.alive:
			e.hurt(99999.0, Vector3.UP)


func _all_hp() -> Array:
	var out: Array = []
	for e in level.enemies:
		if is_instance_valid(e):
			out.append("%s:%s/%s" % [e.kind, str(roundf(e.hp)), str(roundf(e.max_hp))])
	return out


# ------------------------------------------------------------------ 主流程
func _t_flow() -> void:
	q.section("2a 第一关 → 第二关 → 第三关 → 通关")
	q.ok(level.index == 0, "开局在第一关", "index=%d" % level.index)
	q.ok(level.enemies.size() == 1 and level.enemies[0].kind == "mob", "第一关 1 只小怪",
		"%d 个：%s" % [level.enemies.size(), str(_all_hp())])
	var ok_fight := await _until(func(): return level.state == "fight", 4.0)
	q.ok(ok_fight, "intro → fight", level.state)

	# --- 第一关清完
	_kill_all()
	await _frames(3)
	q.ok(level.state == "clear", "杀光 → 状态 clear", level.state)
	q.ok(level.alive_count() == 0, "alive_count=0", "%d" % level.alive_count())
	var ok_next := await _until(func(): return level.index == 1, 4.0)
	q.ok(ok_next, "clear 后自动进第二关", "index=%d state=%s" % [level.index, level.state])
	q.ok(level.enemies.size() == 4, "第二关 3 小怪 + 1 远程",
		"%d 个：%s" % [level.enemies.size(), str(_all_hp())])
	q.ok(level.total_enemies == 4, "HUD 用的 total_enemies 同步", "%d" % level.total_enemies)
	var mobs := 0
	var archers := 0
	for e in level.enemies:
		if e.kind == "mob":
			mobs += 1
		elif e.kind == "archer":
			archers += 1
	q.ok(mobs == 3 and archers == 1, "兵种构成正确", "mob=%d archer=%d" % [mobs, archers])

	# --- 第二关：先打掉一只的血，验证死亡重开后血是满的（在 2b 里用）
	var ok_fight2 := await _until(func(): return level.state == "fight", 4.0)
	q.ok(ok_fight2, "第二关 intro → fight", level.state)
	_kill_all()
	await _frames(3)
	q.ok(level.state == "clear", "第二关杀光 → clear", level.state)
	var ok_third := await _until(func(): return level.index == 2, 4.0)
	q.ok(ok_third, "自动进第三关", "index=%d" % level.index)
	q.ok(level.enemies.size() == 1 and level.enemies[0].kind == "boss", "第三关 1 大怪",
		str(_all_hp()))

	# --- 第三关：小怪血量应该远大于 100（boss.hp=420）
	var boss = level.enemies[0]
	q.ok(is_equal_approx(boss.hp, P.getf("boss.hp")), "大怪血量 = boss.hp 参数",
		"%.0f / %.0f" % [boss.hp, P.getf("boss.hp")])
	var ok_fight3 := await _until(func(): return level.state == "fight", 4.0)
	q.ok(ok_fight3, "第三关 intro → fight", level.state)
	_kill_all()
	await _frames(3)
	q.ok(level.state == "clear", "第三关杀光 → clear", level.state)
	var ok_fin := await _until(func(): return level.state == "finished", 4.0)
	q.ok(ok_fin, "最后一关清完 → finished", "state=%s index=%d" % [level.state, level.index])
	await _frames(30)
	q.ok(level.state == "finished", "finished 后不会自己重开/跳关",
		"state=%s index=%d" % [level.state, level.index])


# ------------------------------------------------------------------ 死亡重开
func _t_death_restart() -> void:
	q.section("2b 中途死亡 → death_delay 到点重开本关，敌人满血")
	level.start_level(1)
	await _frames(2)
	var ok_fight := await _until(func(): return level.state == "fight", 4.0)
	q.ok(ok_fight, "重进第二关并进入 fight", level.state)
	# 先打掉一只 40 血
	var victim = level.enemies[0]
	victim.hurt(40.0, Vector3.UP)
	q.ok(victim.hp < victim.max_hp, "先把一只打掉 40 血",
		"%.0f / %.0f" % [victim.hp, victim.max_hp])
	var idx_before: int = level.index
	var n_before: int = level.enemies.size()
	# 关掉无敌，让玩家死
	P.set_value("rules.god_mode", false)
	player.hurt(999.0, Vector3.UP, "QA 手动处决")
	q.ok(not player.alive, "玩家死了", player.last_cause)
	await _frames(2)
	q.ok(level.state == "dead", "主循环把关卡切到 dead", level.state)
	# 死期间不应该跳关
	q.ok(level.index == idx_before, "死亡期间关卡号不变", "%d" % level.index)
	# 立刻检查：还没到 death_delay 时不能重开
	await _frames(10)   # ~0.17 s < death_delay 0.8
	q.ok(level.state == "dead", "death_delay 未到 → 仍在 dead", level.state)
	var ok_alive := await _until(func(): return player.alive and level.state != "dead", 3.0)
	q.ok(ok_alive, "death_delay 到点后重开（玩家复活）",
		"alive=%s state=%s" % [str(player.alive), level.state])
	q.ok(level.index == idx_before, "重开的是同一关", "%d" % level.index)
	q.ok(level.enemies.size() == n_before, "敌人数量重置", "%d → %d" % [n_before, level.enemies.size()])
	var all_full := true
	for e in level.enemies:
		if not is_instance_valid(e) or not e.alive or not is_equal_approx(e.hp, e.max_hp):
			all_full = false
	q.ok(all_full, "所有敌人满血复活", str(_all_hp()))
	var spawn_d: float = player.rig.global_position.distance_to(level.arena["player_spawn"].origin)
	q.ok(spawn_d < 1.0, "玩家回到本关出生点",
		"%s（距出生点 %.2f m）" % [str(player.rig.global_position), spawn_d])
	P.set_value("rules.god_mode", true)
