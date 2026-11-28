extends SceneTree
## 验证玩家位置到导航目标点的同层投影与边缘/贴墙/栏杆/障碍顶追踪（DISPLAY=:10 真 GPU GUI 实测）。

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


func _find_duelist(lv: Node) -> Node:
	for m in lv.enemies:
		if is_instance_valid(m) and m.get("kind") == "duelist":
			return m
	return null


func _check_projection(lv: Node) -> int:
	var fails := 0
	var cases := [
		{"name": "2F back wall center", "pos": Vector3(0.0, 8.0, 28.5), "y": 8.0, "max_xz": 3.0, "no_air": true},
		{"name": "2F back wall left", "pos": Vector3(-10.0, 8.0, 28.5), "y": 8.0, "max_xz": 3.0, "no_air": true},
		{"name": "2F back wall right", "pos": Vector3(20.0, 8.0, 28.5), "y": 8.0, "max_xz": 3.0, "no_air": true},
		{"name": "2F front rail left", "pos": Vector3(-11.0, 8.0, 17.8), "y": 8.0, "max_xz": 3.0, "no_air": true},
		{"name": "2F front rail right", "pos": Vector3(11.0, 8.0, 17.8), "y": 8.0, "max_xz": 3.0, "no_air": true},
		{"name": "2F front rail east", "pos": Vector3(20.0, 8.0, 18.6), "y": 8.0, "max_xz": 3.0, "no_air": true},
		{"name": "2F left rail", "pos": Vector3(-13.4, 8.0, 23.0), "y": 8.0, "max_xz": 3.0, "no_air": true},
		{"name": "2F right rail", "pos": Vector3(31.5, 8.0, 23.0), "y": 8.0, "max_xz": 3.0, "no_air": true},
		{"name": "2F open center ledge", "pos": Vector3(0.0, 8.0, 17.2), "y": 8.0, "max_xz": 3.0, "no_air": true},
		{"name": "2F open ledge left", "pos": Vector3(-6.5, 8.0, 17.5), "y": 8.0, "max_xz": 3.0, "no_air": true},
		{"name": "2F open ledge right", "pos": Vector3(6.5, 8.0, 17.5), "y": 8.0, "max_xz": 3.0, "no_air": true},
		{"name": "1F wall east", "pos": Vector3(35.0, 0.0, -20.0), "y": 0.0, "max_xz": 3.0, "no_air": false},
		{"name": "1F wall west", "pos": Vector3(-35.0, 0.0, 0.0), "y": 0.0, "max_xz": 3.0, "no_air": false},
		{"name": "1F wall north", "pos": Vector3(0.0, 0.0, -31.0), "y": 0.0, "max_xz": 3.0, "no_air": false},
		{"name": "1F wall south", "pos": Vector3(0.0, 0.0, 31.0), "y": 0.0, "max_xz": 3.0, "no_air": false},
		{"name": "1F hug pillar", "pos": Vector3(-19.5, 0.0, -7.0), "y": 0.0, "max_xz": 3.0, "no_air": false},
		{"name": "1F hug cabinet", "pos": Vector3(-11.0, 0.0, -2.5), "y": 0.0, "max_xz": 3.0, "no_air": false},
		{"name": "1F hug stair base", "pos": Vector3(25.3, 0.0, 0.0), "y": 0.0, "max_xz": 3.0, "no_air": false},
		{"name": "1F top of cabinet", "pos": Vector3(-11.0, 2.8, -5.0), "y": 0.0, "max_xz": 5.0, "no_air": false},
	]
	for c in cases:
		var pos: Vector3 = c["pos"]
		var proj: Vector3 = lv.duelist_nav_goal(pos)
		var phys_ok: bool = lv._nav_phys_clear(proj, 1.75, false)
		var y_ok := absf(proj.y - float(c["y"])) <= 0.65
		var xz_dist := (proj - pos).slide(Vector3.UP).length()
		var dist_ok := xz_dist <= float(c["max_xz"])
		var air_ok := true
		if bool(c["no_air"]):
			air_ok = not lv.nav._is_air_region_at(proj) and proj.z >= 16.9
		var ok := phys_ok and y_ok and dist_ok and air_ok
		print("[PROJ] %-22s -> %s xz=%.2f phys=%s air_ok=%s (%s)" % [
			c["name"], str(proj), xz_dist, str(phys_ok), str(air_ok), "PASS" if ok else "FAIL"])
		if not ok:
			fails += 1
	return fails


func _sim_chase(lv: Node, pl: Node, duelist: Node, label: String,
		duelist_start: Vector3, player_pos: Vector3,
		require_min_y: float, require_end_min_y: float, max_frames: int) -> bool:
	pl.reset(Transform3D(Basis.IDENTITY, player_pos))
	pl.rig.ground_height = player_pos.y
	lv.player_previous = player_pos
	duelist._on_respawn()
	duelist.rig.global_position = duelist_start
	duelist._airborne = false
	duelist._fall_speed = 0.0
	duelist._fall_horiz = Vector3.ZERO
	duelist._player_floor = player_pos
	duelist.phase = duelist.Phase.MELEE
	duelist.sequence.time = duelist.sequence.END + 1.0
	duelist.sequence.dash = {}
	duelist.sequence.return_pose = {}
	duelist.sequence.normal_pose = {}
	duelist.sequence.patrol.begin(duelist.rig, 0.0)
	var prev_y: float = duelist.rig.global_position.y
	var min_y: float = prev_y
	var max_dy := 0.0
	var min_xz := 1e9
	var can_strike := false
	for _f in max_frames:
		await process_frame
		var gp: Vector3 = duelist.rig.global_position
		max_dy = maxf(max_dy, absf(gp.y - prev_y))
		prev_y = gp.y
		min_y = minf(min_y, gp.y)
		var xz := (gp - player_pos).slide(Vector3.UP).length()
		min_xz = minf(min_xz, xz)
		if xz <= 4.5 and lv.duelist_can_strike(gp, player_pos):
			can_strike = true
			break
	var end_y: float = duelist.rig.global_position.y
	var ok := max_dy < 1.25 and min_y >= require_min_y and end_y >= require_end_min_y and min_xz <= 4.5 and can_strike
	print("[SIM] %-28s end=%s min_y=%.2f min_xz=%.2f max_dy=%.3f strike=%s (%s)" % [
		label, str(duelist.rig.global_position), min_y, min_xz, max_dy, str(can_strike), "PASS" if ok else "FAIL"])
	return ok


func _run() -> void:
	var ctx := await _open_wait(9)
	var lv: Node = ctx["level"]
	var pl: Node = ctx["player"]
	var duelist := _find_duelist(lv)
	if duelist == null:
		print("FAIL: no duelist")
		quit(1)
		return
	_session().set_game_param("rules.god_mode", true)
	var fails := _check_projection(lv)

	var sims := [
		["2F->2F back wall", Vector3(0.0, 8.0, 24.0), Vector3(0.0, 8.0, 28.5), 7.5, 7.5, 420],
		["2F->2F front rail", Vector3(0.0, 8.0, 24.0), Vector3(11.0, 8.0, 17.8), 7.5, 7.5, 420],
		["2F->2F right rail", Vector3(0.0, 8.0, 24.0), Vector3(31.5, 8.0, 23.0), 7.5, 7.5, 600],
		["1F->2F front rail", Vector3(2.0, 0.0, -1.0), Vector3(11.0, 8.0, 17.8), -0.5, 7.5, 900],
		["2F->1F west wall", Vector3(0.0, 8.0, 24.0), Vector3(-34.8, 0.0, 5.0), -0.5, -0.5, 720],
		["2F->1F hug cabinet", Vector3(0.0, 8.0, 24.0), Vector3(-11.0, 0.0, -2.5), -0.5, -0.5, 720],
	]
	for s in sims:
		if not await _sim_chase(lv, pl, duelist, s[0], s[1], s[2], s[3], s[4], s[5]):
			fails += 1

	print("==== verify_nav_goal_mapping: %s ====" % ("OK" if fails == 0 else "FAIL %d" % fails))
	quit(0 if fails == 0 else 1)
