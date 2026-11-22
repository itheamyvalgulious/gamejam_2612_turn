extends Node3D
## 探针：验收新的「影子幕布」——四面墙每帧都有影子、玩家也有、真几何。
##   DISPLAY=:0 godot --path . res://scenes/probe_wall_shadow.tscn

const MainScene = preload("res://main.tscn")

var game
var cam: Camera3D
var shot = preload("res://tools/shot.gd").new()

var _fails: Array = []


func _ready() -> void:
	game = MainScene.instantiate()
	add_child(game)
	await _f(4)
	P.set_value("rules.god_mode", true)
	P.set_value("boss.laser_trigger", "disabled")
	game.level.start_level(2)
	await _f(8)
	var sh = game.level.shadow
	print("[ws] node=%s enabled=%s slots=%d" % [str(sh), sh.enabled, sh._slots.size()])
	print("[ws] casters=%d stats=%s" % [sh.caster_count(), sh.caster_stats()])
	var rep: Dictionary = sh.debug_report()
	print("[ws] report lamps=%d casters=%d" % [rep["lamps"], rep["casters"]])
	for s in rep["slots"]:
		print("[ws]   slot%d screen=%s mask=%s cam=%s" % [s["slot"], s["screen"], s["mask"], s["cam"]])

	# 两个角色摆到场地里
	game.player.rig.global_position = Vector3(0, 0, 30)
	game.player.rig.heading = PI
	game.player.rig.rotation.y = PI
	var boss = game.level.enemies[0]
	boss.rig.global_position = Vector3(0, 0, 10)
	boss.rig.heading = PI
	boss.rig.rotation.y = PI
	await _f(6)
	sh.refresh()
	await _f(3)

	var cov := []
	for i in 4:
		cov.append(sh.mask_coverage(i))
	print("[ws] coverage (boss z=10, player z=30) = ", cov)
	_check(cov.all(func(c): return c > 0.002), "四面墙都投出了剪影 %s" % str(cov))

	# 玩家单独在最角落：四面墙也应该有他
	boss.rig.global_position = Vector3(-50, 0, -50)
	game.player.rig.global_position = Vector3(55, 0, 55)
	await _f(6)
	sh.refresh()
	await _f(3)
	cov = []
	for i in 4:
		cov.append(sh.mask_coverage(i))
	print("[ws] coverage (player@corner) = ", cov)
	_check(cov.all(func(c): return c > 0.0002), "角落里的玩家在四面墙上都有剪影 %s" % str(cov))

	# 投影位置检查：把一个人放到 (x=20, z=20)，北墙（slot 0, z=-60）的影子
	# 横向应该在 x=20 附近，纵向脚在地面 y=0
	boss.rig.global_position = Vector3(20, 0, 20)
	game.player.rig.global_position = Vector3(-40, 0, -40)
	await _f(6)
	sh.refresh()
	await _f(2)
	var uv = sh.mask_uv_of(0, Vector3(20, 4, 0))
	print("[ws] wall0 uv of (20, 4) = ", uv, " mask=", sh._groups[0]["vp"].size)
	var a_hit: float = sh.mask_alpha_at(0, Vector3(20, 4, 0))
	var a_miss: float = sh.mask_alpha_at(0, Vector3(-40, 12, 0))
	print("[ws] wall0 alpha at boss x=20 = %.2f / empty x=-40 = %.2f" % [a_hit, a_miss])
	_check(a_hit > 0.5, "boss 在 (20,4) 时墙 0 对应 texel 有剪影（%.2f）" % a_hit)
	_check(a_miss < 0.1, "墙 0 空处没有剪影（%.2f）" % a_miss)

	# 截图：三个机位看南墙（slot 1）
	await _snaps(sh)
	# 再截一张全景
	_fails = _fails.filter(func(x): return x != "")
	print("[ws] ===== %s =====" % ("PASS" if _fails.is_empty() else "FAIL %s" % str(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _snaps(sh) -> void:
	cam = Camera3D.new()
	cam.cull_mask = 0xFFFFF & ~2
	cam.fov = 60
	cam.near = 0.1
	cam.far = 600
	add_child(cam)
	cam.current = true
	var boss = game.level.enemies[0]
	game.player.rig.global_position = Vector3(-8, 0, 22)
	boss.rig.global_position = Vector3(4, 0, 18)
	boss.rig.heading = PI
	boss.rig.rotation.y = PI
	game.player.rig.heading = PI * 0.9
	game.player.rig.rotation.y = PI * 0.9
	await _f(6)
	sh.refresh()
	await _f(3)
	# 看北墙（boss 侧后方）
	var views := [
		{"tag": "south_wall", "pos": Vector3(0, 7, 20), "look": Vector3(0, 7, 60)},
		{"tag": "north_wall_side", "pos": Vector3(44, 8, 24), "look": Vector3(-20, 8, -58)},
		{"tag": "west_wall", "pos": Vector3(40, 9, 40), "look": Vector3(-60, 8, -10)},
		{"tag": "scale15", "pos": Vector3(44, 8, 24), "look": Vector3(-20, 8, -58)},
	]
	for v in views:
		if String(v["tag"]) == "scale15":
			sh.set_caster_scale(1.5)
			sh.refresh()
			await _f(3)
			print("[ws] caster_scale=1.5 coverage=", [sh.mask_coverage(0), sh.mask_coverage(1)])
		cam.look_at_from_position(v["pos"], v["look"], Vector3.UP)
		await _f(4)
		await RenderingServer.frame_post_draw
		await shot.capture(self, "res://shots/ws_%s.png" % v["tag"], 4)
	sh.set_caster_scale(1.0)
	sh.refresh()
	await _f(2)
	# 性能：主视角 + 4 个遮罩视口的总 draw call / primitives
	await RenderingServer.frame_post_draw
	print("[ws] perf draw_calls=%d primitives=%d fps=%.0f" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		Performance.get_monitor(Performance.TIME_FPS)])


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("[ws]   OK  ", msg)
	else:
		print("[ws]   FAIL ", msg)
		_fails.append(msg)
