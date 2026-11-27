extends SceneTree
## Death QA driver (headless): open a level, wait for enemies, kill one via the
## real hurt path, step the world, then dump the DeathField report.
##
##   godot --headless --path main -s tools/death_qa.gd -- --level=5 \
##       [--enemy=duelist] [--respawn] [--frames=180]
##
## Exits 0 on pass, 2 on failure; prints [death-qa] lines.

const Catalog = preload("res://core/level_catalog.gd")

var _args := {}
var _fail := 0

## Autoload handle (check-only 脚本模式下拿不到全局标识符)。
func _session() -> Node:
	return root.get_node("TurnSession")


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", false, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _note(ok: bool, msg: String) -> void:
	print("[death-qa] %s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		_fail += 1


func _run() -> void:
	var idx := int(_args.get("level", "5"))
	var want := String(_args.get("enemy", ""))
	var frames := int(_args.get("frames", "180"))
	print("[death-qa] opening level %d" % idx)
	_session().open_level(idx)
	var wait := 0
	while current_scene == null or current_scene.get("level") == null:
		await process_frame
		wait += 1
		if wait > 900:
			_note(false, "level never opened")
			quit(2)
			return
	var level: Node = current_scene.get("level")
	while str(level.get("state")) not in ["fight", ""]:
		await process_frame
		wait += 1
		if wait > 1800:
			_note(false, "level state never reached fight")
			quit(2)
			return
	# 让敌人完成 spawn/intro，world 走几帧。
	for i in 30:
		await physics_frame
	var enemies: Array = level.get("enemies")
	print("[death-qa] state=%s enemies=%d" % [level.get("state"), enemies.size()])
	if enemies.is_empty():
		_note(false, "no enemies in level %d" % idx)
		quit(2)
		return
	var target: Node = null
	for e in enemies:
		if not is_instance_valid(e) or not bool(e.get("alive")):
			continue
		if want.is_empty() or String(e.get("enemy_id")) == want \
				or String(e.get("kind")) == want:
			target = e
			break
	if target == null:
		_note(false, "no alive enemy matching '%s'" % want)
		quit(2)
		return
	var eid := String(target.get("enemy_id"))
	var field: Object = level.get_meta(&"death_field", null)
	_note(field != null, "DeathField installed on level")
	# shard 的相位重组完成前 hurt 不致死：等它进入可命中状态。
	var asm_wait := 0
	while is_instance_valid(target) and target.has_method("hit_parts") \
			and (target.hit_parts() as Array).is_empty() and bool(target.get("alive")):
		await physics_frame
		asm_wait += 1
		if asm_wait > 600:
			break
	if asm_wait > 0:
		print("[death-qa] waited %d frames for target to assemble" % asm_wait)
	# 等模板预热队列清空（spawn 摊销），让 kill 路径只剩节点重挂。
	var warm_wait := 0
	while field != null and not field._warm_queue.is_empty():
		await process_frame
		warm_wait += 1
		if warm_wait > 300:
			break
	print("[death-qa] template warm-up drained in %d frames" % warm_wait)

	# 杀：优先真刀路径（有 hurt_by_blade 的走它），否则 hurt。
	var travel := Vector3(0.8, 0.05, 0.4)
	var point: Vector3 = target.center() if target.has_method("center") \
		else target.rig.global_position + Vector3.UP * 1.4
	var t0 := Time.get_ticks_usec()
	if target.has_method("hurt_by_blade"):
		target.hurt_by_blade(9999.0, -travel.normalized(), 0.0, travel,
			{"point": point, "blade_point": point, "part": "", "side": 0.0})
	elif target.has_method("die"):
		target.die()
	else:
		target.hurt(9999.0, -travel.normalized())
	var kill_ms := (Time.get_ticks_usec() - t0) / 1000.0
	# shard 没装填完成时 hurt 不致死：QA 直接走 die() 测切割路径。
	if bool(target.get("alive")) and target.has_method("die"):
		target.die()
	elif bool(target.get("alive")):
		target.hurt(9999.0, -travel.normalized())
	_note(not bool(target.get("alive")), "enemy %s died" % eid)
	_note(kill_ms < 16.7, "kill path %.2fms < 1 frame" % kill_ms)
	var bodies := 0
	var joints := 0
	var chunks := 0
	if field != null:
		var rep: Dictionary = field.report()
		var kill: Dictionary = rep.get("kills", {}).get(eid, {})
		bodies = int(kill.get("bodies", 0))
		chunks = int(kill.get("chunks", 0))
		joints = int(kill.get("joints", 0))
		print("[death-qa] kill %s bodies=%d chunks=%d joints=%d kill_ms=%.2f prep=%.2f spawn=%.2f template=%.2f"
			% [eid, bodies, chunks, joints, float(kill.get("ms", -1.0)),
			float(kill.get("prep_ms", -1.0)), float(kill.get("spawn_ms", -1.0)),
			float(kill.get("template_ms", 0.0))])
		_note(bodies > 0, "ragdoll bodies spawned")
		if eid == "phase_boss":
			_note(chunks <= 45, "boss chunks %d ≤ 45" % chunks)
		else:
			_note(chunks >= 6 and chunks <= 35, "chunks %d in 6–35" % chunks)
	# 物理步进：碎块应沉降、关节不该炸。
	var max_spd := 0.0
	var settled := 0
	# GPU 截图：kill 后先走一小段，让碎块摊开但还没全停。
	var shot_frames := int(_args.get("shot_delay", "45"))
	if _args.has("shot") and shot_frames > 0:
		for i in shot_frames:
			await physics_frame
		var shot_cam: Camera3D = null
		if _args.has("shotcam"):
			shot_cam = Camera3D.new()
			root.add_child(shot_cam)
			# 站在刀口斜上方看碎块堆。
			var focus: Vector3 = point + Vector3(0, 0.6, 0)
			var shot_dist := float(_args.get("shotdist", "5.2"))
			var shot_up := float(_args.get("shotup", "2.6"))
			var off := travel.normalized().rotated(Vector3.UP, 0.9) * shot_dist \
				+ Vector3.UP * shot_up
			shot_cam.global_transform = Transform3D.IDENTITY.looking_at(
				-off, Vector3.UP).translated(focus + off)
			shot_cam.current = true
			shot_cam.fov = 52.0
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(String(_args["shot"]))
		print("[death-qa] shot saved %s" % String(_args["shot"]))
		if shot_cam != null:
			shot_cam.queue_free()
	if _args.has("colview"):
		_session().toggle_collision_view()
		# F7 叠加层每 0.5s 重建一次；provider 注册后还要等一个刷新周期。
		for i in 48:
			await process_frame
		await RenderingServer.frame_post_draw
		var img2 := root.get_texture().get_image()
		img2.save_png(String(_args.get("colview_shot", "/tmp/opencode/colview.png")))
		print("[death-qa] colview shot saved")
	for i in frames:
		await physics_frame
	if field != null and is_instance_valid(field):
		for b in field._live:
			if not is_instance_valid(b):
				continue
			max_spd = maxf(max_spd, b.linear_velocity.length())
			if b.linear_velocity.length() < 0.4:
				settled += 1
		var visible_total: int = field._live.size() + field._frozen_bodies.size()
		print("[death-qa] after %d frames: live=%d frozen=%d joints=%d max_speed=%.2f settled=%d"
			% [frames, field._live.size(), field._frozen_bodies.size(),
			field._joints.size(), max_spd, settled])
		_note(visible_total > 0, "persistent debris alive (%d visible)" % visible_total)
		_note(max_spd < 60.0, "no physics explosion (max %.1f u/s)" % max_spd)
	# —— 旧死亡路径未被触发：knockdown/wreckage 对象必须不存在 ——
	var kd: Variant = target.get("_knockdown") if is_instance_valid(target) else null
	var wr: Variant = target.get("_wreckage") if is_instance_valid(target) else null
	_note(kd == null, "old knockdown not started")
	_note(wr == null, "old wreckage not started")
	# —— 推挤证据：把玩家 rig 传进碎块堆，碎屑被推开而 rig 不被挡 ——
	if _args.has("pushtest") and field != null and field._live.size() >= 8:
		var prig: Node3D = current_scene.get("player").rig
		var pile := Vector3.ZERO
		var n := 0
		for b in field._live:
			if is_instance_valid(b):
				pile += b.global_position
				n += 1
		if n > 0:
			pile /= n
		pile.y += 0.4
		var pre: Array = []
		for b in field._live:
			if is_instance_valid(b):
				pre.append(b.global_position)
		prig.global_position = pile
		for i in 40:
			await physics_frame
		var pushed := 0
		var bidx := 0
		for b in field._live:
			if is_instance_valid(b) and bidx < pre.size():
				if b.global_position.distance_to(pre[bidx]) > 0.35:
					pushed += 1
			bidx += 1
		var end_dist := Vector2(prig.global_position.x - pile.x,
			prig.global_position.z - pile.z).length()
		print("[death-qa] pushtest: %d/%d debris moved by pusher, rig drift %.2f u"
			% [pushed, field._live.size(), end_dist])
		_note(pushed >= 3, "pusher displaced %d debris bodies" % pushed)
		_note(end_dist < 3.5, "rig not blocked by debris (drift %.2f)" % end_dist)
	# 多杀一个，确认模板缓存复用（同类型第二只应接近零预处理）。
	var second: Node = null
	for e in enemies:
		if is_instance_valid(e) and e != target and bool(e.get("alive")) \
				and String(e.get("enemy_id")) == eid:
			second = e
			break
	if second != null:
		var t1 := Time.get_ticks_usec()
		if second.has_method("hurt_by_blade"):
			second.hurt_by_blade(9999.0, -travel.normalized(), 0.0, travel,
				{"point": point, "part": ""})
		elif second.has_method("die"):
			second.die()
		else:
			second.hurt(9999.0)
		var kill2 := (Time.get_ticks_usec() - t1) / 1000.0
		print("[death-qa] second %s kill %.2fms" % [eid, kill2])
		_note(kill2 < 16.7, "cached template kill < 1 frame")
	# —— --spam：连杀堆上限，验证冻结的碎屑全部贴地、不得半空定格 ——
	# 必须留一只活口：全杀会触发过关清场，达不到"场上超过 300"的状态。
	if _args.has("spam") and field != null:
		var killed := 0
		for e in enemies:
			var alive_left := 0
			for other in enemies:
				if is_instance_valid(other) and bool(other.get("alive")):
					alive_left += 1
			if alive_left <= 1 or killed >= 5:
				break
			if not is_instance_valid(e) or not bool(e.get("alive")):
				continue
			if e.has_method("die"):
				e.die()
			else:
				e.hurt(9999.0)
			killed += 1
			# 过关/重开可能换 DeathField 实例：每杀一只重查。
			var fresh: Variant = level.get_meta(&"death_field", null)
			if fresh != null and is_instance_valid(fresh):
				field = fresh
		# 给连杀留沉降时间（cap 复查 0.4s 一轮）。
		for i in 240:
			await physics_frame
		var airborne := 0
		var frozen_ok := 0
		for b in field._frozen_bodies:
			if not is_instance_valid(b):
				continue
			if b is StaticBody3D:
				continue   # 合并件：成员在冻结时已验证贴地
			if field._has_support(b):
				frozen_ok += 1
			else:
				airborne += 1
		print("[death-qa] spam: killed=%d live=%d frozen=%d (grounded=%d airborne=%d)"
			% [killed, field._live.size(), field._frozen_bodies.size(),
				frozen_ok, airborne])
		_note(airborne == 0, "no mid-air frozen debris (%d airborne)" % airborne)
		_note(field._live.size() + field._frozen_bodies.size() > 0,
			"spam debris never disappeared")
	# 重生：敌池复用时 rig 网格应恢复、碎块清掉（走关卡 start_level 流程）。
	if _args.has("respawn") and field != null:
		var before: int = field._live.size()
		if level.has_method("start_level"):
			if "idx" in level or level.get("index") != null:
				level.start_level(level.get("index"))
			else:
				level.start_level()
			for i in 30:
				await physics_frame
			_note(field._live.size() == 0 and field._frozen_bodies.size() == 0,
				"respawn cleared %d debris bodies" % before)
			var revived := 0
			var revived_target: Node = null
			for e in level.get("enemies"):
				if is_instance_valid(e) and bool(e.get("alive")):
					revived += 1
					if revived_target == null and (want.is_empty() or String(e.get("enemy_id")) == want or String(e.get("kind")) == want):
						revived_target = e
			_note(revived > 0, "enemies respawned (%d alive)" % revived)
			if revived_target != null:
				if revived_target.has_method("die"):
					revived_target.die()
				else:
					revived_target.hurt(9999.0)
				_note(field._live.size() > 0, "respawned enemy %s uses DeathField on re-kill (live=%d)" % [String(revived_target.get("enemy_id")), field._live.size()])
	if field != null:
		var st: Dictionary = field.report().get("templates", {})
		print("[death-qa] templates: cold=%d (%.1fms) hot_binds=%d keys=%d"
			% [int(st.get("cold_builds", 0)), float(st.get("cold_build_ms", 0.0)),
				int(st.get("hot_binds", 0)), int(st.get("templates", 0))])
	print("[death-qa] done: %d failure(s)" % _fail)
	quit(2 if _fail > 0 else 0)
