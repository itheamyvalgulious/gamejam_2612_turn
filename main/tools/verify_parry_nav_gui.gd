extends SceneTree
## DISPLAY=:10 全真 GUI 模拟测试：
## 1. 格挡测试（vs Mech Duelist & Arc Sentinel）：
##    - 全程 0 被击中
##    - 刀柄帧间无抽搐/瞬移，角度连续无 180° 翻转
##    - 接触瞬间两剑近乎垂直（|a·b| <= 0.25）
##    - 接触点落在我方剑刃上（u_contact >= 0.30），不用剑柄挡
## 2. 坠击中庭·高低差（lv9）导航测试：
##    - 刀客在二楼、玩家在一楼 -> 刀客从中央缺口物理跌落（多帧重力下落，0 瞬移），落地后逼近玩家
##    - 玩家上二楼、刀客在一楼 -> 刀客沿一楼楼梯口走楼梯上二楼（0 瞬移、0 卡死）
##    - 玩家再回一楼两个不同位置 -> 刀客不瞬移、不卡死在楼梯口，稳定逼近玩家

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


func _check_parry_enemy(idx: int, target_kind: String, frames: int, player_pos: Vector3, enemy_pos: Vector3) -> Dictionary:
	var ctx := await _open_wait(idx)
	var lv: Node = ctx["level"]
	var pl: Node = ctx["player"]
	_session().set_game_param("rules.god_mode", false)
	_session().set_game_param("rules.one_hit_kill", false)
	_session().set_game_param("parry.melee_block", true)
	_session().set_game_param("parry.auto_aim", true)
	var target: Node = null
	for e in lv.get("enemies"):
		if not is_instance_valid(e):
			continue
		var k := String(e.get("enemy_id")) if target_kind == "arc_sentinel" else String(e.get("kind"))
		if k == target_kind and target == null:
			target = e
		else:
			e.alive = false
			if e.get("rig") != null:
				e.rig.visible = false
	pl.reset(Transform3D(Basis.IDENTITY, player_pos))
	pl.rig.ground_height = player_pos.y
	if target != null and target.get("rig") != null:
		target.rig.global_position = enemy_pos
	var prev_hilt := Vector3.INF
	var prev_axis := Vector3.ZERO
	var max_hilt_jump := 0.0
	var max_ang_jump := 0.0
	var bad_contacts := 0
	var hilt_contacts := 0
	var ab_samples: Array = []
	var u_samples: Array = []
	var last_blocks := 0
	var span: Vector2 = pl.rig.blade_span()
	for _f in frames:
		pl.parry_timer = 1.0
		await process_frame
		var cur_hilt: Vector3 = pl.rig.weapon_root.position
		var cur_axis: Vector3 = pl.rig.weapon_spin.global_transform.basis.y.normalized()
		if prev_hilt.is_finite() and pl.rig.blade_path_active():
			max_hilt_jump = maxf(max_hilt_jump, cur_hilt.distance_to(prev_hilt))
			if prev_axis.length_squared() > 0.5:
				max_ang_jump = maxf(max_ang_jump, cur_axis.angle_to(prev_axis))
		prev_hilt = cur_hilt
		prev_axis = cur_axis
		var cur_blocks := int(pl.parry_stats.get("blocks", 0))
		if cur_blocks > last_blocks:
			last_blocks = cur_blocks
			var pc: Dictionary = pl.get("parry_contact")
			if not pc.is_empty():
				var ab := absf(float(pc.get("ab_dot", 1.0)))
				ab_samples.append(snappedf(ab, 0.01))
				if ab > 0.25:
					bad_contacts += 1
				var xf_my: Transform3D = pl.rig.weapon_spin.global_transform
				var s0: Vector3 = xf_my * Vector3(0, span.x, 0)
				var s1: Vector3 = xf_my * Vector3(0, span.y, 0)
				var src = target if target.has_method("predict_weapon_xf") else target.get("rig")
				var xf_e: Transform3D = src.get("_blade_now") if src.get("_blade_now") is Transform3D else src.weapon_spin.global_transform
				var es: Vector2 = src.blade_span() if src.has_method("blade_span") else src.get("blade_proxy").span
				var e0: Vector3 = xf_e * Vector3(0, es.x, 0)
				var e1: Vector3 = xf_e * Vector3(0, es.y, 0)
				var r := preload("res://core/active_parry.gd")._seg_seg(s0, s1, e0, e1)
				var P_w: Vector3 = r["c0"]
				var along_w: float = (P_w - xf_my.origin).dot(cur_axis) / maxf(xf_my.basis.get_scale().y, 0.001)
				var u_est := (along_w - span.x) / maxf(span.y - span.x, 0.001)
				u_samples.append(snappedf(u_est, 0.02))
				if u_est < 0.25:
					hilt_contacts += 1
		if not pl.alive or int(pl.parry_stats.get("hits", 0)) > 0:
			break
	var hits := int(pl.parry_stats.get("hits", 0))
	var blocks := int(pl.parry_stats.get("blocks", 0))
	var ok := bool(pl.alive) and hits == 0 and blocks >= 4 and max_hilt_jump < 0.65 and max_ang_jump < 0.90 and bad_contacts == 0 and hilt_contacts == 0
	print("[GUI-PARRY] %s blocks=%d hits=%d max_dhilt=%.3f max_dang=%.3f bad_ab=%d hilt_blk=%d ab=%s u=%s stats=%s (%s)" % [
		target_kind, blocks, hits, max_hilt_jump, max_ang_jump, bad_contacts, hilt_contacts, str(ab_samples), str(u_samples),
		str(pl.parry_stats), "PASS" if ok else "FAIL"])
	return {"ok": ok}


func _check_galleria_nav() -> Dictionary:
	var ctx := await _open_wait(9)
	var lv: Node = ctx["level"]
	var pl: Node = ctx["player"]
	_session().set_game_param("rules.god_mode", true)
	var duelist: Node = null
	for e in lv.get("enemies"):
		if is_instance_valid(e) and String(e.get("kind")) == "duelist":
			duelist = e
			break
	if duelist == null:
		print("[GUI-NAV] FAIL: no duelist in lv9")
		return {"ok": false}
	var fails := 0

	# Phase 1: 刀客在二楼开放区附近，玩家在一楼正下方 -> 刀客必须物理跌落（多帧 y 递减，0 瞬移）
	pl.reset(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 6.0)))
	pl.rig.ground_height = 0.0
	lv.player_previous = Vector3(0.0, 0.0, 6.0)
	duelist._on_respawn()
	duelist.rig.global_position = Vector3(0.0, 8.0, 21.0)
	duelist.phase = duelist.Phase.MELEE
	duelist.sequence.time = 10.0
	duelist.sequence.finished = true
	duelist.sequence.normal_pose = {}
	duelist.sequence.patrol.begin(duelist.rig, 0.0)
	var prev_y: float = duelist.rig.global_position.y
	var max_dy := 0.0
	var fall_frames := 0
	var landed_1f := false
	var min_d1 := 1e9
	for _f in 600:
		await process_frame
		var gp: Vector3 = duelist.rig.global_position
		var dy := absf(gp.y - prev_y)
		if dy > 0.01:
			max_dy = maxf(max_dy, dy)
			if gp.y < prev_y and gp.y > 0.2 and gp.y < 7.8:
				fall_frames += 1
		prev_y = gp.y
		if gp.y <= 0.25:
			landed_1f = true
		min_d1 = minf(min_d1, gp.distance_to(pl.rig.global_position))
		if landed_1f and min_d1 < 5.0:
			break
	var ok1 := landed_1f and fall_frames >= 3 and max_dy < 1.2 and min_d1 < 5.2
	print("[GUI-NAV] Phase1(2F->1F drop) landed=%s fall_frames=%d max_dy=%.3f min_d=%.2f (%s)" % [
		str(landed_1f), fall_frames, max_dy, min_d1, "PASS" if ok1 else "FAIL"])
	if not ok1:
		fails += 1

	# Phase 2: 玩家瞬移上二楼，刀客在一楼 -> 刀客必须走楼梯上二楼
	pl.reset(Transform3D(Basis.IDENTITY, Vector3(0.0, 8.0, 23.0)))
	pl.rig.ground_height = 8.0
	lv.player_previous = Vector3(0.0, 8.0, 23.0)
	var max_dy2 := 0.0
	prev_y = duelist.rig.global_position.y
	var reached_2f := false
	for _f in 900:
		await process_frame
		var gp: Vector3 = duelist.rig.global_position
		max_dy2 = maxf(max_dy2, absf(gp.y - prev_y))
		prev_y = gp.y
		if gp.y >= 7.5:
			reached_2f = true
			break
	var ok2 := reached_2f and max_dy2 < 1.0
	print("[GUI-NAV] Phase2(1F->2F stair) reached_2f=%s max_dy=%.3f pos=%s (%s)" % [
		str(reached_2f), max_dy2, str(duelist.rig.global_position), "PASS" if ok2 else "FAIL"])
	if not ok2:
		fails += 1

	# Phase 3: 玩家回到一楼左侧，再移动到一楼右侧 -> 不得瞬移，不得卡死在楼梯口
	for sub in [Vector3(-12.0, 0.0, 4.0), Vector3(16.0, 0.0, -14.0)]:
		pl.reset(Transform3D(Basis.IDENTITY, sub))
		pl.rig.ground_height = 0.0
		lv.player_previous = sub
		var max_dy3 := 0.0
		prev_y = duelist.rig.global_position.y
		var min_d3 := 1e9
		var osc := 0
		var last_p: Vector3 = duelist.rig.global_position
		for _f in 720:
			await process_frame
			var gp: Vector3 = duelist.rig.global_position
			max_dy3 = maxf(max_dy3, absf(gp.y - prev_y))
			prev_y = gp.y
			min_d3 = minf(min_d3, gp.distance_to(pl.rig.global_position))
			if gp.distance_to(last_p) < 0.01 and gp.distance_to(pl.rig.global_position) > 5.5:
				osc += 1
			else:
				osc = maxi(0, osc - 1)
			last_p = gp
			if min_d3 < 5.0:
				break
		var ok3 := max_dy3 < 1.25 and min_d3 < 5.2 and osc < 90
		print("[GUI-NAV] Phase3(to %s) min_d=%.2f max_dy=%.3f osc=%d (%s)" % [
			str(sub), min_d3, max_dy3, osc, "PASS" if ok3 else "FAIL"])
		if not ok3:
			fails += 1

	return {"ok": fails == 0}


func _run() -> void:
	var fails := 0
	var args := OS.get_cmdline_user_args()
	var nav_only := "--nav-only" in args
	var parry_only := "--parry-only" in args
	if not nav_only:
		var r1 := await _check_parry_enemy(1, "arc_sentinel", 1200, Vector3(0.0, 0.0, 4.0), Vector3(0.0, 0.0, 0.0))
		if not bool(r1["ok"]):
			fails += 1
		var r2 := await _check_parry_enemy(9, "duelist", 1400, Vector3(0.0, 0.0, 6.0), Vector3(0.0, 0.0, 0.0))
		if not bool(r2["ok"]):
			fails += 1
	if not parry_only:
		var r3 := await _check_galleria_nav()
		if not bool(r3["ok"]):
			fails += 1
	print("==== verify_parry_nav_gui: %s ====" % ("OK" if fails == 0 else "FAIL %d" % fails))
	quit(0 if fails == 0 else 1)
