extends SceneTree
## Headless 近战平地持续格挡测试（god_mode=false）：
##   1. 平地 vs Arc Sentinel（≥30s）→ 0 破防、存活
##   2. Level 9 坠击中庭·高低差 下层平地 vs Mech Duelist（≥35s）→ 0 破防、存活

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


func _run() -> void:
	var fails := 0

	# ---- Scenario A: 平地 vs Arc Sentinel (lv1, 30s) ----
	var ctx_a := await _open_wait(1)
	var lv_a: Node = ctx_a["level"]
	var pl_a: Node = ctx_a["player"]
	_session().set_game_param("rules.god_mode", false)
	_session().set_game_param("rules.one_hit_kill", false)
	_session().set_game_param("parry.melee_block", true)
	_session().set_game_param("parry.auto_aim", true)
	var arc: Node = null
	for e in lv_a.get("enemies"):
		if is_instance_valid(e) and String(e.get("enemy_id")) == "arc_sentinel" and arc == null:
			arc = e
		elif is_instance_valid(e):
			e.alive = false
			if e.get("rig") != null:
				e.rig.visible = false
	pl_a.reset(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 4.0)))
	if arc != null and arc.get("rig") != null:
		arc.rig.global_position = Vector3(0.0, 0.0, 0.0)
	for _f in 1800:
		pl_a.parry_timer = 1.0
		await process_frame
		if not pl_a.alive or int(pl_a.parry_stats.get("hits", 0)) > 0:
			print("[parry-melee] ArcHIT frame=%d anim=%s t=%.3f dist=%.2f guard=%s label=%s" % [
				_f, str(arc.rig.current_anim), float(arc.attack_elapsed),
				arc.rig.global_position.distance_to(pl_a.rig.global_position),
				str(pl_a.is_guard_up()), str(pl_a.parry_plan_label())])
			break
	var sw_a := int(pl_a.parry_stats.get("swings", 0))
	var bl_a := int(pl_a.parry_stats.get("blocks", 0))
	var hi_a := int(pl_a.parry_stats.get("hits", 0))
	var ok_a: bool = bool(pl_a.alive) and hi_a == 0 and sw_a >= 6 and bl_a >= 6
	print("[parry-melee] ArcSentinel swings=%d blocks=%d hits=%d alive=%s stats=%s (%s)" % [
		sw_a, bl_a, hi_a, str(pl_a.alive), str(pl_a.parry_stats), "PASS" if ok_a else "FAIL"])
	if not ok_a:
		fails += 1

	# ---- Scenario B: 平地 vs Mech Duelist (lv9 lower floor, 35s) ----
	var ctx_b := await _open_wait(9)
	var lv_b: Node = ctx_b["level"]
	var pl_b: Node = ctx_b["player"]
	_session().set_game_param("rules.god_mode", false)
	_session().set_game_param("rules.one_hit_kill", false)
	_session().set_game_param("parry.melee_block", true)
	_session().set_game_param("parry.auto_aim", true)
	var duelist: Node = null
	for e in lv_b.get("enemies"):
		if is_instance_valid(e) and String(e.get("kind")) == "duelist" and duelist == null:
			duelist = e
		elif is_instance_valid(e):
			e.alive = false
			if e.get("rig") != null:
				e.rig.visible = false
	pl_b.reset(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 6.0)))
	pl_b.rig.ground_height = 0.0
	if duelist != null and duelist.get("rig") != null:
		duelist.rig.global_position = Vector3(0.0, 0.0, 0.0)
	for _f in 2100:
		pl_b.parry_timer = 1.0
		await process_frame
		if not pl_b.alive or int(pl_b.parry_stats.get("hits", 0)) > 0:
			print("[parry-melee] DuelistHIT frame=%d swung=%d t=%.3f from=%.3f to=%.3f dist=%.2f guard=%s label=%s strike_act=%s" % [
				_f, int(duelist.swung_serial), float(duelist.rig.attack_elapsed),
				float(duelist.rig.attack_hit_from), float(duelist.rig.attack_hit_to),
				duelist.rig.global_position.distance_to(pl_b.rig.global_position),
				str(pl_b.is_guard_up()), str(pl_b.parry_plan_label()), str(pl_b.rig.strike_active())])
			break
	var sw_b := int(pl_b.parry_stats.get("swings", 0))
	var bl_b := int(pl_b.parry_stats.get("blocks", 0))
	var hi_b := int(pl_b.parry_stats.get("hits", 0))
	var ok_b: bool = bool(pl_b.alive) and hi_b == 0 and sw_b >= 6 and bl_b >= 6
	print("[parry-melee] MechDuelist swings=%d blocks=%d hits=%d alive=%s stats=%s (%s)" % [
		sw_b, bl_b, hi_b, str(pl_b.alive), str(pl_b.parry_stats), "PASS" if ok_b else "FAIL"])
	if not ok_b:
		fails += 1

	print("==== parry_melee_test: %s ====" % ("OK" if fails == 0 else "FAIL %d" % fails))
	quit(0 if fails == 0 else 1)
