extends SceneTree
## Headless 弹射物格挡测试：随机主角速度 × 随机弹射物方向（120 组组合）
## 验证：god_mode=false、持续格挡时 0 命中、高弹反率、低规划耗时。

func _session() -> Node:
	return root.get_node("TurnSession")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_session().open_level(1)
	var w := 0
	while (current_scene == null or current_scene.get("level") == null) and w < 600:
		await process_frame
		w += 1
	var level: Node = current_scene.get("level")
	var player: Node = current_scene.get("player")
	var proj = level.get("projectiles")
	while str(level.get("state")) not in ["fight", ""] and w < 1200:
		await process_frame
		w += 1

	_session().set_game_param("rules.god_mode", false)
	_session().set_game_param("rules.one_hit_kill", false)
	_session().set_game_param("parry.melee_block", true)
	_session().set_game_param("parry.auto_aim", true)
	if level.get("arena") is Dictionary:
		level.arena["cover"] = []

	for e in level.get("enemies"):
		if is_instance_valid(e):
			e.alive = false
			if e.get("rig") != null:
				e.rig.visible = false

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261127
	var total := 120
	var blocked := 0
	var hits := 0
	var missed := 0
	var plan_ms_total := 0.0
	var plan_calls := 0

	for trial in total:
		proj.clear_all()
		player.reset(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)))
		player.parry_timer = 1.0
		player.rig.global_position = Vector3(0.0, 0.0, 0.0)
		player.rig.ground_height = 0.0
		await process_frame

		var p_speed := rng.randf_range(0.0, 14.0)
		var p_az := rng.randf_range(0.0, TAU)
		var v_h := Vector3(cos(p_az), 0.0, sin(p_az)) * p_speed
		var v_y := rng.randf_range(4.0, 9.0) if rng.randf() < 0.30 else 0.0
		var v_p := Vector3(v_h.x, v_y, v_h.z)

		var s_az := rng.randf_range(0.0, TAU)
		var s_el := deg_to_rad(rng.randf_range(-20.0, 42.0))
		var s_dir := Vector3(cos(s_el) * cos(s_az), sin(s_el), cos(s_el) * sin(s_az)).normalized()
		var s_speed := rng.randf_range(18.0, 40.0)
		var s_dist := rng.randf_range(7.0, 16.0)
		var t_flight := s_dist / s_speed

		var chest0: Vector3 = player.rig.global_position + Vector3(0.0, 2.2, 0.0)
		var g_fall: float = float(player.rig.grav) if v_y > 0.0 else 0.0
		var future_chest: Vector3 = chest0 + v_p * t_flight - Vector3(0.0, 0.5 * g_fall * t_flight * t_flight, 0.0)
		future_chest.y = maxf(future_chest.y, 2.2)
		var spawn_pos: Vector3 = future_chest - s_dir * s_dist
		spawn_pos.y = maxf(spawn_pos.y, 1.0)
		var aim_dir := (future_chest - spawn_pos).normalized()

		var prev_hits := int(player.parry_stats.get("hits", 0))
		var it: Dictionary = proj.spawn_arrow(spawn_pos, aim_dir, s_speed, 20.0, "enemy")
		var trial_blocked := false
		var trial_hit := false
		var cur_vy := v_y

		for _f in 90:
			player.parry_timer = 1.0
			var dt := maxf(root.get_process_delta_time(), 1.0 / 120.0)
			if v_y > 0.0 or player.rig.global_position.y > 0.0:
				cur_vy -= g_fall * dt
				var np: Vector3 = player.rig.global_position + Vector3(v_h.x, cur_vy, v_h.z) * dt
				if np.y < 0.0:
					np.y = 0.0
					cur_vy = 0.0
				player.rig.global_position = np
				player.rig.ground_height = 0.0
			else:
				player.rig.global_position += v_h * dt
			player.measured_velocity = Vector3(v_h.x, cur_vy, v_h.z)
			var t0 := Time.get_ticks_usec()
			await process_frame
			plan_ms_total += (Time.get_ticks_usec() - t0) / 1000.0
			plan_calls += 1

			if int(player.parry_stats.get("hits", 0)) > prev_hits or not player.alive:
				trial_hit = true
				break
			if String(it.get("owner", "")) == "player" or not bool(it.get("alive", true)):
				trial_blocked = true
				break

		if trial_hit:
			hits += 1
			print("[parry-proj] HIT trial=%d p_vel=%s s_dir=%s s_sp=%.1f" % [trial, v_p, aim_dir, s_speed])
		elif trial_blocked:
			blocked += 1
		else:
			missed += 1

	var rate := blocked * 100.0 / float(total)
	var avg_ms := plan_ms_total / maxf(plan_calls, 1)
	print("[parry-proj] RESULT total=%d blocked=%d hits=%d missed=%d rate=%.1f%% avg_frame=%.2fms" % [
		total, blocked, hits, missed, rate, avg_ms])
	var ok := hits == 0 and rate >= 98.0
	print("==== parry_projectile_test: %s ====" % ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)
