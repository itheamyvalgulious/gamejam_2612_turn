extends Node3D
## QA 7 —— 稳定性：连续跑 3 分钟（时间倍率 2×，死亡/重开/三关循环）
##
## 跑法：
##   timeout 240 godot --headless --path . res://scenes/qa_stability.tscn > /tmp/qa_stability.log 2>&1
##   grep -c "ERROR" /tmp/qa_stability.log
##
## 采样 Performance.OBJECT_NODE_COUNT / OBJECT_ORPHAN_NODE_COUNT，判断有没有泄漏；
## 期间每 10 游戏秒手动 next_level() 一次，让三张地图反复重建（美术资源是最大的泄漏源）。

const Qa = preload("res://tools/qa_lib.gd")
const DURATION := 180.0
const SAMPLE_EVERY := 5.0

var q
var main
var player
var level
var nodes: Array = []
var orphans: Array = []
var times: Array = []
var lvls: Array = []
var next_at := 10.0
var t := 0.0
var deaths := 0
var level_builds := 0
var _last_alive := true


func _ready() -> void:
	Engine.max_fps = 60
	q = Qa.new("qa_stability")
	P.reset_all()
	P.set_value("rules.god_mode", false)          # 允许自然死亡 → 反复重建
	P.set_value("rules.time_scale", 2.0)
	P.set_value("boss.laser_trigger", "player_sees")
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	player = main.player
	level = main.level
	get_tree().create_timer(235.0).timeout.connect(func():
		print("  !! 看门狗超时")
		get_tree().quit(2))

	q.info("起始节点数", "%d ｜ orphan %d" % [
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])

	var last_sample := 0.0
	var last_idx: int = level.index
	while t < DURATION:
		await get_tree().process_frame
		t += 1.0 / 60.0
		if last_idx != level.index:
			level_builds += 1
			last_idx = level.index
		if _last_alive and not player.alive:
			deaths += 1
		_last_alive = player.alive
		if t >= next_at:
			next_at += 10.0
			main.next_level()
		if t - last_sample >= SAMPLE_EVERY:
			last_sample = t
			var nc: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			var oc: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
			nodes.append(nc)
			orphans.append(oc)
			times.append(t)
			lvls.append(level.index)
			print("SAMPLE t=%.0fs nodes=%d orphans=%d level=%d state=%s" % [
				t, nc, oc, level.index, level.state])

	var n0: int = nodes[0]
	var n1: int = nodes[nodes.size() - 1]
	var nmin: int = nodes.min()
	var nmax: int = nodes.max()
	q.section("7 稳定性 3 分钟（2× 时间倍率）")
	q.info("采样序列", "%s" % str(nodes))
	q.info("orphan 序列", "%s" % str(orphans))
	q.info("自然死亡次数 / 关卡重建次数", "%d / %d" % [deaths, level_builds])
	q.ok(n1 - n0 < 100, "首末节点数没有显著增长（< 100）",
		"首 %d → 末 %d（min %d / max %d）" % [n0, n1, nmin, nmax])
	# 按关卡分组：同一张图的节点数在多次重建后应当一致
	var by_level: Dictionary = {}
	for i in nodes.size():
		var lv: int = lvls[i]
		if not by_level.has(lv):
			by_level[lv] = []
		by_level[lv].append(int(nodes[i]))
	var all_stable := true
	for lv in by_level.keys():
		var arr: Array = by_level[lv]
		var lo: int = arr.min()
		var hi: int = arr.max()
		q.info("  第 %d 关节点数（%d 次采样）" % [int(lv) + 1, arr.size()],
			"%s ｜ min %d max %d 极差 %d" % [str(arr), lo, hi, hi - lo])
		if hi - lo > 40:
			all_stable = false
	q.ok(all_stable, "同一张图反复重建后节点数一致（每关极差 ≤ 40）", "见上方分组")
	var max_orphan: int = orphans.max()
	q.ok(max_orphan == 0, "没有孤儿节点", "max=%d" % max_orphan)
	q.ok(player != null and is_instance_valid(player), "玩家节点一直有效")
	q.ok(level.enemies.size() <= 8, "敌人数组没有无限增长", "%d" % level.enemies.size())
	print("\n== qa_stability: %d checks, %d failed ==" % [q.checks, q.fails])
	get_tree().quit(q.summary())
