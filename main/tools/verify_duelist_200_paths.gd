extends SceneTree
## 实测刀客在「坠击中庭 · 高低差」（lv9）中随机 200 条路径的物理实际行走可达性：
## 覆盖 1F->1F、2F->2F、2F->1F（从缺口物理重力跌落）、1F->2F（沿楼梯攀爬），
## 逐帧用 duelist_route_point + duelist_ground_move + 物理重力跌落实际走到目标。

func _session() -> Node:
	return root.get_node("TurnSession")


func _init() -> void:
	_run.call_deferred()


func _open_wait(idx: int) -> Dictionary:
	var prev := current_scene
	_session().open_level(idx)
	var w := 0
	while (_session().active_level_index() != idx or current_scene == null or not is_instance_valid(current_scene) or current_scene == prev or current_scene.get("level") == null) and w < 600:
		await process_frame
		w += 1
	var level: Node = current_scene.get("level")
	var player: Node = current_scene.get("player")
	while is_instance_valid(level) and str(level.get("state")) not in ["fight", ""] and w < 1200:
		await process_frame
		w += 1
	return {"level": level, "player": player}


func _sample_valid_points(lv: Node, rng: RandomNumberGenerator, count_1f: int, count_2f: int) -> Dictionary:
	var pts_1f: Array[Vector3] = []
	var pts_2f: Array[Vector3] = []
	var tries := 0
	while (pts_1f.size() < count_1f or pts_2f.size() < count_2f) and tries < 8000:
		tries += 1
		var want_2f := pts_2f.size() < count_2f and (pts_1f.size() >= count_1f or rng.randf() < 0.35)
		var x := rng.randf_range(-11.0, 29.5) if want_2f else rng.randf_range(-33.0, 33.0)
		var z := rng.randf_range(17.5, 26.8) if want_2f else rng.randf_range(-29.0, 29.0)
		var y := 8.0 if want_2f else 0.0
		var p := Vector3(x, y, z)
		if not lv._nav_phys_clear(p, 1.75, false):
			continue
		var ri: int = lv.nav.region_at(p)
		if ri < 0 or absf(float(lv.nav.regions[ri]["y0"]) - p.y) > 0.5:
			continue
		if want_2f:
			pts_2f.append(p)
		else:
			pts_1f.append(p)
	return {"1f": pts_1f, "2f": pts_2f}


func _walk_physical(lv: Node, start: Vector3, goal: Vector3) -> Dictionary:
	var pos := start
	var dt := 1.0 / 60.0
	var speed := 14.0
	var fall_v := 0.0
	var airborne := false
	var fall_horiz := Vector3.ZERO
	var max_dy := 0.0
	var wp := pos
	for f in 900:
		if pos.distance_to(goal) <= 2.3:
			return {"ok": true, "dist": pos.distance_to(goal), "max_dy": max_dy, "frames": f}
		var fy: float = lv.floor_at(pos, pos.y + 0.55)
		if pos.y > fy + 0.55:
			if not airborne:
				airborne = true
				fall_v = 0.0
				var hdir := (wp - pos).slide(Vector3.UP)
				fall_horiz = hdir.normalized() * 3.5 if hdir.length_squared() > 0.01 else Vector3.ZERO
			fall_v += 18.28 * dt
			var next := pos + fall_horiz * dt
			next.y = maxf(fy, pos.y - fall_v * dt)
			if not lv.position_clear(Vector3(next.x, pos.y, next.z), 1.75, false):
				next.x = pos.x
				next.z = pos.z
				fall_horiz = Vector3.ZERO
			max_dy = maxf(max_dy, absf(next.y - pos.y))
			pos = next
			continue
		if airborne:
			pos.y = fy
			airborne = false
			fall_v = 0.0
			fall_horiz = Vector3.ZERO
		if f % 8 == 0 or pos.distance_squared_to(wp) < 0.36:
			wp = lv.duelist_route_point(pos, goal, true)
		var dir := (wp - pos).slide(Vector3.UP)
		if dir.length_squared() < 1e-6:
			wp = lv.duelist_route_point(pos, goal, false)
			dir = (wp - pos).slide(Vector3.UP)
			if dir.length_squared() < 1e-6:
				break
		var next_pos: Vector3 = lv.duelist_ground_move(pos, pos + dir.limit_length(speed * dt))
		max_dy = maxf(max_dy, absf(next_pos.y - pos.y))
		pos = next_pos
	return {"ok": pos.distance_to(goal) <= 2.5, "dist": pos.distance_to(goal), "max_dy": max_dy, "end": pos}


func _run() -> void:
	var ctx := await _open_wait(9)
	var lv: Node = ctx["level"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261128
	var pool := _sample_valid_points(lv, rng, 120, 80)
	var pts_1f: Array[Vector3] = pool["1f"]
	var pts_2f: Array[Vector3] = pool["2f"]
	print("[200-PATHS] sampled 1F=%d 2F=%d" % [pts_1f.size(), pts_2f.size()])
	var cats := {
		"1F->1F": {"total": 80, "pass": 0},
		"2F->2F": {"total": 40, "pass": 0},
		"2F->1F": {"total": 40, "pass": 0},
		"1F->2F": {"total": 40, "pass": 0},
	}
	var total_pass := 0
	var teleports := 0
	for cat in ["1F->1F", "2F->2F", "2F->1F", "1F->2F"]:
		var n := int(cats[cat]["total"])
		for i in n:
			var a: Vector3
			var b: Vector3
			if cat == "1F->1F":
				a = pts_1f[i % pts_1f.size()]
				b = pts_1f[(i * 7 + 13) % pts_1f.size()]
			elif cat == "2F->2F":
				a = pts_2f[i % pts_2f.size()]
				b = pts_2f[(i * 5 + 9) % pts_2f.size()]
			elif cat == "2F->1F":
				a = pts_2f[i % pts_2f.size()]
				b = pts_1f[(i * 11 + 3) % pts_1f.size()]
			else:
				a = pts_1f[i % pts_1f.size()]
				b = pts_2f[(i * 13 + 5) % pts_2f.size()]
			var res := _walk_physical(lv, a, b)
			if float(res["max_dy"]) > 1.2:
				teleports += 1
			if bool(res["ok"]) and float(res["max_dy"]) <= 1.2:
				cats[cat]["pass"] = int(cats[cat]["pass"]) + 1
				total_pass += 1
			else:
				print("[200-PATHS] FAIL %s #%d %s -> %s dist=%.2f max_dy=%.3f end=%s" % [
					cat, i, str(a), str(b), float(res["dist"]), float(res["max_dy"]), str(res.get("end", Vector3.ZERO))])
	for cat in ["1F->1F", "2F->2F", "2F->1F", "1F->2F"]:
		print("[200-PATHS] %s: %d/%d" % [cat, int(cats[cat]["pass"]), int(cats[cat]["total"])])
	var ok := total_pass >= 198 and teleports == 0
	print("==== verify_duelist_200_paths: %d/200 teleports=%d (%s) ====" % [
		total_pass, teleports, "OK" if ok else "FAIL"])
	quit(0 if ok else 1)
