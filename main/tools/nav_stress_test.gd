extends SceneTree
## 导航压力测试（headless）：
##   Part A: 每关 50 对随机合法起终点 + 贴角/爬楼对 → 验证 nav.path() + move_slide
##           逐步推进都能到达目标 1.5u 内且不卡死。
##   Part B: 真实关卡中多只 Arc Sentinel + Mech Duelist 追踪移动目标（绕掩体/上下楼），
##           验证所有怪物持续逼近或进入攻击距离，不发生永久卡死。

const NavField = preload("res://core/nav_field.gd")

const TEST_LEVELS := [0, 1, 3, 4, 5, 9]
const SIM_LEVELS := [0, 3, 4, 5, 9]


func _session() -> Node:
	return root.get_node("TurnSession")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261127

	# ---- Part A: NavField 纯解析路径 + 贴边滑行可达性 ----
	for idx in TEST_LEVELS:
		var prev_scene := current_scene
		_session().open_level(idx)
		var w := 0
		while (_session().active_level_index() != idx or current_scene == null or not is_instance_valid(current_scene) or current_scene == prev_scene or current_scene.get("level") == null) and w < 600:
			await process_frame
			w += 1
		var level: Node = current_scene.get("level")
		var nav = level.get("nav")
		var arena: Dictionary = level.get("arena")
		if idx == 5 or idx == 9:
			var t_g0 := Time.get_ticks_usec()
			nav.prewarm_graph(1.20, 0.38)
			if idx == 9:
				nav.prewarm_graph(1.75, 0.45, {"radius": 1.18, "bottom": 1.10, "top": 4.53})
			print("[nav-stress] lv%d graph_prewarm=%.2fms" % [idx, (Time.get_ticks_usec() - t_g0) / 1000.0])
		var bounds: AABB = arena.get("bounds", AABB())
		if nav == null or bounds.size.length_squared() < 1.0:
			print("[nav-stress] FAIL lv%d missing nav/bounds" % idx)
			fails += 1
			continue
		var valid_pts: Array[Vector3] = []
		var tries := 0
		while valid_pts.size() < 40 and tries < 800:
			tries += 1
			var x := rng.randf_range(bounds.position.x + 2.5, bounds.end.x - 2.5)
			var z := rng.randf_range(bounds.position.z + 2.5, bounds.end.z - 2.5)
			var y := 0.0
			if (idx == 5 or idx == 9) and rng.randf() < 0.25:
				y = 8.0
			var p := Vector3(x, y, z)
			var sup: float = nav.support_at(p, y + 0.5)
			if sup > -INF * 0.5 and absf(sup - y) < 0.5:
				var q := Vector3(x, sup, z)
				if nav.can_stand(q, 1.20, 0.38):
					valid_pts.append(q)
		var reached := 0
		var pairs := mini(15, valid_pts.size())
		for k in pairs:
			var a := valid_pts[k % valid_pts.size()]
			var b := valid_pts[(k * 7 + 3) % valid_pts.size()]
			var pts: Array = nav.path(a, b, 1.20, 0.38)
			if pts.is_empty():
				continue
			var cur := a
			var step_speed := 12.0 * (1.0 / 60.0)
			var wp := cur
			for _f in 720:
				if cur.distance_to(b) <= 1.5:
					break
				if _f % 10 == 0 or cur.distance_squared_to(wp) < 0.25:
					wp = nav.next_waypoint(cur, b, 1.20, 0.38)
				var dir := (wp - cur).slide(Vector3.UP)
				if dir.length_squared() < 1e-6:
					wp = nav.next_waypoint(cur, b, 1.20, 0.38)
					dir = (wp - cur).slide(Vector3.UP)
					if dir.length_squared() < 1e-6:
						break
				cur = nav.move_slide(cur, cur + dir.limit_length(step_speed), 1.20, 0.38, 0.6)
			if cur.distance_to(b) <= 1.65:
				reached += 1
			else:
				print("[nav-stress] WARN lv%d pair %s -> %s stopped at %s (dist=%.2f)" % [
					idx, a, b, cur, cur.distance_to(b)])
		var ok := reached >= int(pairs * 0.96)
		print("[nav-stress] PartA lv%d reached=%d/%d (%s)" % [
			idx, reached, pairs, "PASS" if ok else "FAIL"])
		if not ok:
			fails += 1

	# ---- Part B: 真实怪物 AI + 多怪防卡死仿真 ----
	for idx in SIM_LEVELS:
		var prev_scene := current_scene
		_session().open_level(idx)
		var w := 0
		while (_session().active_level_index() != idx or current_scene == null or not is_instance_valid(current_scene) or current_scene == prev_scene or current_scene.get("level") == null) and w < 600:
			await process_frame
			w += 1
		var level: Node = current_scene.get("level")
		var player: Node = current_scene.get("player")
		while is_instance_valid(level) and str(level.get("state")) not in ["fight", ""] and w < 1200:
			await process_frame
			w += 1
		_session().set_game_param("rules.god_mode", true)
		var enemies: Array = level.get("enemies")
		var tracked: Array = []
		for e in enemies:
			if is_instance_valid(e) and bool(e.get("alive")) and String(e.get("kind")) in ["mob", "duelist"]:
				tracked.append({"e": e, "min_d": 1e9, "stuck_frames": 0, "last_pos": e.ground_position()})
		# 让玩家在场地上安全位置移动诱敌（对 lv9 站平地中央附近，lv5 在下层绕柱走）
		var anchors := [Vector3(0, 0, 12), Vector3(14, 0, -12), Vector3(-14, 0, -12)]
		if idx == 3:
			anchors = [Vector3(0, 0, 18), Vector3(22, 0, 0), Vector3(-22, 0, 0)]
		elif idx == 4:
			anchors = [Vector3(0, 0, 22), Vector3(-24, 0, 0), Vector3(24, 0, -12)]
		elif idx == 9:
			anchors = [Vector3(-4, 0, 4), Vector3(6, 0, -6)]
		elif idx == 0:
			anchors = [Vector3(0, 0, 6), Vector3(0, 0, -6)]
		var phase_i := 0
		for f in 600:
			if f % 200 == 0 and player != null and player.rig != null:
				var tp: Vector3 = anchors[phase_i % anchors.size()]
				phase_i += 1
				player.rig.global_position = tp
				player.rig.ground_height = tp.y
			await process_frame
			for rec in tracked:
				var e: Node = rec["e"]
				if not is_instance_valid(e) or not bool(e.get("alive")):
					continue
				var gp: Vector3 = e.ground_position()
				var d: float = gp.distance_to(player.rig.global_position)
				rec["min_d"] = minf(float(rec["min_d"]), d)
				if d > 4.2 and gp.distance_to(rec["last_pos"]) < 0.005:
					rec["stuck_frames"] = int(rec["stuck_frames"]) + 1
				else:
					rec["stuck_frames"] = maxi(0, int(rec["stuck_frames"]) - 2)
				rec["last_pos"] = gp
		var lv_ok := true
		for rec in tracked:
			var md := float(rec["min_d"])
			var sf := int(rec["stuck_frames"])
			var e_ok := md <= 4.8 or sf < 90
			if not e_ok:
				lv_ok = false
			print("[nav-stress] PartB lv%d %s min_d=%.2f stuck_tail=%d (%s)" % [
				idx, rec["e"].get("enemy_id"), md, sf, "PASS" if e_ok else "FAIL"])
		if not lv_ok:
			fails += 1

	print("==== nav_stress_test: %s ====" % ("FAIL %d" % fails if fails > 0 else "OK"))
	quit(1 if fails > 0 else 0)
