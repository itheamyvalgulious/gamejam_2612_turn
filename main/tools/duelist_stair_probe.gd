extends SceneTree
## 刀客高低差复现（headless，真实流程）：
##   A 段：玩家在二楼出生点，等刀客自己走上来；
##   B 段：把玩家放到一楼，观察刀客下楼过程是否卡住 / 跨层闪现。
##
## 用法：
##   godot --headless --path main -s tools/duelist_stair_probe.gd
##   --frames=2400  总帧数（60fps 仿真）
##   --player=0,0,-2   B 段玩家的落点
##   --deck-x=20    刀客走到二楼且 x 小于该值时才切 B 段（默认等到上楼即切）
##
## 验收：SUMMARY 里 jumps=0（没有跨层闪现），且刀客能下楼接近玩家。

const Catalog = preload("res://core/level_catalog.gd")


func _init() -> void:
	_run.call_deferred()


func _arg_vec(key: String, fallback: Vector3) -> Vector3:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			var parts := a.trim_prefix("--%s=" % key).split(",")
			if parts.size() == 3:
				return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return fallback


func _arg_int(key: String, fallback: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return int(a.trim_prefix("--%s=" % key))
	return fallback


func _run() -> void:
	var session: Node = root.get_node("TurnSession")
	var idx := Catalog.index_for_id("galleria_height_test")
	var frames := _arg_int("frames", 2400)
	var ground_target := _arg_vec("player", Vector3(0, 0, -2))
	session.open_level(idx)
	while session.active_level_index() != idx or current_scene == null or current_scene.get("level") == null:
		await process_frame
	var level: Node = current_scene.get("level")
	var player: Node = current_scene.get("player")
	var nav = level.get("nav")
	while str(level.get("state")) != "fight":
		await process_frame
	session.set_game_param("rules.god_mode", true)
	var enemies: Array = level.get("enemies")
	var duelist = enemies[0]
	var rig = duelist.get("rig")
	var sq = duelist.get("sequence")
	var pat = sq.get("patrol")
	print("[probe] start duelist=%s player=%s" % [rig.global_position, player.rig.global_position])

	var stuck_events := 0
	var last: Vector3 = rig.global_position
	var stuck_at := Vector3.INF
	var stuck := 0
	var jumps := 0
	var b_start := -1
	for f in frames:
		await process_frame
		# A 段：等刀客走上二楼（y > 7），或玩家被攻击到就切 B
		if b_start < 0:
			var deck_x := _arg_int("deck-x", 999) * 1.0
			var up: bool = rig.global_position.y > 7.0 and rig.global_position.x < deck_x
			if up or f > 1200:
				b_start = f
				player.rig.global_position = ground_target
				player.rig.ground_height = ground_target.y
				print("[probe] B start f=%d duelist=%s -> player moved to %s" % [
					f, rig.global_position, ground_target])
			last = rig.global_position
			continue
		var p: Vector3 = rig.global_position
		var dy := p.y - last.y
		var dxz := Vector2(p.x - last.x, p.z - last.z).length()
		if absf(dy) > 1.0:
			jumps += 1
			print("[probe] f=%d JUMP dy=%.2f dxz=%.2f %s -> %s" % [f, dy, dxz, last, p])
		if dxz < 0.004 and absf(dy) < 0.02:
			stuck += 1
			if stuck_at == Vector3.INF:
				stuck_at = p
		else:
			if stuck > 90:
				stuck_events += 1
				print("[probe] f=%d STUCK %.1fs at %s (floor=%.2f player=%s dist=%.2f phase=%d)" % [
					f, stuck / 60.0, stuck_at, stuck_at.y, player.rig.global_position,
					stuck_at.distance_to(player.rig.global_position), int(duelist.get("phase"))])
			stuck = 0
			stuck_at = Vector3.INF
		if stuck > 0 and stuck % 30 == 0:
			print("[stall] f=%d stuck=%.1fs p=%s normal_pose=%d sprint_windup=%.2f guard=%s patrol(moving=%s motion=%d active=%s) climbing=%s seeking=%s" % [
				f, stuck / 60.0, p, len(sq.get("normal_pose")),
				float(sq.get("sprint_windup")), str(sq.get("guarding")),
				str(pat.get("moving")), int(pat.get("motion")), str(pat.get("active")),
				str(sq.get("climbing")), str(sq.get("seeking_level"))])
		if (f - b_start) % 120 == 0:
			print("[probe] f=%d p=%s player=%s phase=%d dist=%.2f wp=%s" % [
				f, p, player.rig.global_position, int(duelist.get("phase")),
				p.distance_to(player.rig.global_position),
				level.duelist_route_point(p, player.rig.global_position)])
		last = p
	print("[probe] SUMMARY jumps=%d stuck_events=%d final=%s dist=%.2f" % [
		jumps, stuck_events, rig.global_position,
		rig.global_position.distance_to(player.rig.global_position)])
	quit()
