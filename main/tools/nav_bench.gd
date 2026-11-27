extends SceneTree
## 导航热点微基准（headless，纯 CPU）：
##   坠击中庭里 4 只哨兵从一楼追高台上的玩家，反复量 sentinel_waypoint()
##   的单次耗时（真实追击中起终点每帧都在动，这里每轮位移避开路径缓存）。
##
## 用法：
##   godot --headless --path main -s tools/nav_bench.gd
##   godot --headless --path main -s tools/nav_bench.gd -- --dump=/tmp/nav.txt
##
## 验收参考：优化前 ~42ms/次（A* 线性开表 + 从尾端回扫路点），
## 现在 ~2–4ms/次；单帧最多 2 只哨兵重算（见 arc_encounter 的同帧预算）。

const Catalog = preload("res://core/level_catalog.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var session: Node = root.get_node("TurnSession")
	var idx := Catalog.index_for_id("galleria")
	var goal := Vector3(0, 8, 25)
	var dump := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dump="):
			dump = a.trim_prefix("--dump=")
	session.open_level(idx)
	while session.active_level_index() != idx or current_scene == null or current_scene.get("level") == null:
		await process_frame
	var level: Node = current_scene.get("level")
	var nav = level.get("nav")
	if nav == null:
		print("[nav-bench] FAIL nav missing")
		quit(1)
		return
	# 一楼四个出生点 + 掩体后两侧 + 高台，覆盖直走/绕柱/爬楼三类查询。
	var starts: Array[Vector3] = [Vector3(0, 0, 10), Vector3(-6, 0, 5), Vector3(7, 0, 2),
		Vector3(0, 0, -12), Vector3(12, 0, -8), Vector3(-14, 0, 12), Vector3(3, 0, 18),
		Vector3(-3, 8, 20)]
	var lines := PackedStringArray()
	var worst := 0.0
	var total := 0.0
	var path_ms := 0.0
	var n := 0
	for round_i in 6:
		for s in starts:
			var from := s + Vector3(0.37 * round_i, 0, 0.29 * round_i)
			var g := goal - Vector3(0, 0, 0.61 * round_i)
			var t0 := Time.get_ticks_usec()
			var pts: Array = nav.path(from, g, 1.2, 0.38)
			var t1 := Time.get_ticks_usec()
			var wp: Vector3 = level.sentinel_waypoint(from, g)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			path_ms += (t1 - t0) / 1000.0
			worst = maxf(worst, ms)
			total += ms
			n += 1
			lines.append("%s -> %s : wp=%s pts=%s" % [from, g, wp, pts])
	print("[nav-bench] calls=%d avg=%.2fms max=%.2fms (path avg=%.2fms)" % [
		n, total / n, worst, path_ms / n])
	if dump != "":
		var f := FileAccess.open(dump, FileAccess.WRITE)
		f.store_string("\n".join(lines))
	quit()
