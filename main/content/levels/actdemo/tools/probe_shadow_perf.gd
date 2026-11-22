extends Node3D
## 探针：量影子系统的帧时间（A/B 交替 4 轮、每轮 200 帧，取中位数）。

const MainScene = preload("res://main.tscn")

var _samples: Array = []


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	P.set_value("rules.god_mode", true)
	P.set_value("boss.laser_trigger", "disabled")
	P.set_value("cam.mode", "third")
	game.level.start_level(2)
	await _f(90)
	var sh = game.level.shadow
	game.level.enemies[0].rig.global_position = Vector3(0, 0, 6)
	game.player.rig.global_position = Vector3(0, 0, 26)
	game.cam.yaw = 0.0
	await _f(60)
	print("[perf] casters=%d stats=%s groups=%d" % [sh.caster_count(), sh.caster_stats(), sh._groups.size()])

	# 诊断：遮罩 pass 的固定开销 vs 几何/灯光
	var cams := []
	for g in sh._groups:
		cams.append(g["cam"])
	var cfgs := [
		{"tag": "off", "on": false, "hz": 1},
		{"tag": "on@60", "on": true, "hz": 1},
		{"tag": "on@30", "on": true, "hz": 2},
		{"tag": "cull0", "on": true, "hz": 1, "cull": 0},
		{"tag": "cull0@30", "on": true, "hz": 2, "cull": 0},
		{"tag": "8x8", "on": true, "hz": 1, "small": true},
	]
	var rounds := 2
	var acc := {}
	for r in rounds:
		for c in cfgs:
			sh.set_enabled(c["on"])
			sh.set_update_every(c["hz"])
			for cam in cams:
				cam.cull_mask = 2 if not c.has("cull") else int(c["cull"])
			for g in sh._groups:
				var vp: SubViewport = g["vp"]
				vp.size = Vector2i(8, 8) if c.has("small") else Vector2i(2048, 324)
			await _f(20)
			var t := await _measure(160)
			var k: String = c["tag"]
			if not acc.has(k):
				acc[k] = []
			(acc[k] as Array).append(t)
	for cam in cams:
		cam.cull_mask = 2
	for g in sh._groups:
		g["vp"].size = Vector2i(2048, 324)
	for c in cfgs:
		var a: Array = acc[c["tag"]]
		a.sort()
		print("[perf] %-6s median=%.2f ms  runs=%s" % [c["tag"], float(a[a.size() / 2]),
			str(a.map(func(v): return "%.1f" % v))])
	sh.set_enabled(true)
	sh.set_update_every(2)
	await _f(30)
	print("[perf] refresh cpu usec=%.0f" % sh.last_build_usec())
	get_tree().quit()


func _measure(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame
