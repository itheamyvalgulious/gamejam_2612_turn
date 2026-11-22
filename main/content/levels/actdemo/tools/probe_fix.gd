extends Node3D
## 临时验收探针（秒级，不跑长测试）：
##  1) 循环音 idx 漂到缓冲区外之后，混音不能再越界
##  2) 拦截箭不能被弹反、不能在玩家旁边「箭生箭」，而且必然撞掉目标

var main
var player
var level
var proj
var cam
var fails := 0

func _ok(cond: bool, label: String, detail := "") -> void:
	print(("  PASS  " if cond else "  FAIL  ") + label + (("  " + detail) if detail != "" else ""))
	if not cond:
		fails += 1

func _ready() -> void:
	Engine.max_fps = 60
	P.reset_all()
	P.set_value("rules.god_mode", true)
	P.set_value("parry.radius", 8.0)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	player = main.player
	level = main.level
	proj = main.proj
	cam = main.cam

	# ---------------- 1. 音频：漂移的循环声部
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(999, 0, 0)
	var id0: int = Snd.loop_on("arrow_whistle", n, {})
	var v = Snd._by_id[id0]
	var nbuf: int = v.n
	v.idx = 103499.0
	v.g_l = 0.7
	v.g_r = 0.7
	v.atend = 1.0
	Snd._tmp_l.resize(64)
	Snd._tmp_r.resize(64)
	Snd._render(v, 64, 0)
	_ok(is_finite(v.idx) and v.idx >= 0.0 and v.idx < float(nbuf),
		"循环音 idx 漂移后混音仍然落在缓冲区里", "idx=%.0f n=%d" % [v.idx, nbuf])
	v.idx = 103499.0
	Snd.stop(id0)
	_ok(v.n <= nbuf + int(Snd.SR * 0.03) + 2,
		"stop() 不会因为 idx 漂移把缓冲区撑爆", "n=%d（原始 %d）" % [v.n, nbuf])
	_ok(not v.loop and v.idx >= 0.0 and v.idx < float(v.n), "淡出尾巴从有效位置开始",
		"idx=%.0f n=%d" % [v.idx, v.n])

	# ---------------- 2. 拦截箭必然命中
	level.start_level(1)
	await get_tree().process_frame
	var base := Vector3(1000, 2, 0)
	proj.clear_all()
	var a: Dictionary = proj.spawn_arrow(base, Vector3(0, 0, 1), 40.0, 50.0, "player", Color.WHITE)
	var b: Dictionary = proj.spawn_interceptor(base + Vector3(0, 0, 20), a, 34.0)
	_ok(bool(b["spent"]) and bool(b["interceptor"]), "拦截箭一出生就是 spent（不可能被弹反 / 伤不到人）")
	var clash_frames := -1
	for i in 60:
		var evs: Array = proj.step(1.0 / 60.0, {"player": null, "enemies": [], "cam": cam, "arena": {}})
		if bool(a["spent"]) and bool(b["spent"]):
			clash_frames = i + 1
			break
	_ok(bool(a["spent"]) and bool(b["spent"]),
		"拦截箭必然撞上目标、两边一起报废", "%d 帧内失去力量" % clash_frames)

	# ---------------- 3. 玩家在远程怪鼻子底下狂弹反：不能再「箭生箭」
	proj.clear_all()
	var archer = null
	for e in level.enemies:
		if e != null and is_instance_valid(e) and e.kind == "archer":
			archer = e
	var fwd: Vector3 = -player.rig.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	archer.hp = 1.0e12          # 别让它被弹回去的箭打死，否则测试就提前结束了
	archer.rig.global_position = player.rig.global_position + fwd * 6.0
	var spawned0: int = proj._seq
	var max_items := 0
	var fire_t := 0.0
	var fired := 0
	for f in 180:
		await get_tree().process_frame
		player.parry_timer = 1.0
		archer.rig.global_position = player.rig.global_position + fwd * 6.0
		# 每 0.3 秒射一箭（不是每帧都射，免得自己把数量刷上去）
		fire_t += 1.0 / 60.0
		if fire_t >= 0.3:
			fire_t = 0.0
			fired += 1
			archer.fire_cd = 0.0
			archer.draw_t = 0.001
		max_items = maxi(max_items, proj.items.size())
	var spawned: int = proj._seq - spawned0
	_ok(proj.items.size() <= 192 and max_items <= 192,
		"飞行物数量有硬上限", "峰值 %d" % max_items)
	_ok(spawned <= fired * 4 + 8, "没有出现失控的连锁生成",
		"3 秒内射出 %d 支 → 总生成 %d 支（含拦截箭）" % [fired, spawned])
	print("\n== probe_fix: %s ==" % ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
