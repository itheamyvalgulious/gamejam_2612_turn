extends Node

var _level
var _player
var _cam
var _duelist
var _report := []

func _ready() -> void:
	_run.call_deferred()

func _log(s: String) -> void:
	print("[repro] " + s)
	_report.append(s)

func _run() -> void:
	TurnSession.open_level(9)
	while TurnSession.active_level_index() != 9 or get_tree().current_scene == null:
		await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	_level = get_tree().current_scene.get("level")
	_player = get_tree().current_scene.get("player")
	_cam = get_tree().current_scene.get("cam")
	for e in _level.enemies:
		if e.kind == "duelist":
			_duelist = e
	if _duelist != null:
		await _test_parry()
	_summary()
	get_tree().quit()

func _test_parry() -> void:
	_log("--- duelist parry test ---")
	var rig = _duelist.rig
	# teleport the player right in front of the duelist so it opens a close move
	_player.rig.global_position = rig.global_position + Vector3(2.6, 0.0, 0.4)
	_player.rig.global_transform = Transform3D(Basis.IDENTITY, _player.rig.global_position)
	_player.alive = true
	var InterceptS = preload("res://runtime/systems/galleria/game/intercept.gd")
	var Combat = preload("res://runtime/systems/galleria/game/combat.gd")
	var Hit = preload("res://runtime/systems/galleria/core/hitgd.gd")
	var blocked := 0
	var hit := 0
	var threat_empty := 0
	var guard_on := 0
	var saw_attack := false
	for i in 900:
		# pin the parry window open like a real player holding the key
		_player.parry_timer = 1.0
		_player.step(1.0/60.0, _level.arena, _level.enemies)
		_duelist.step(1.0 / 60.0, {"player": _player, "arena": _level.arena, "projectiles": get_tree().current_scene.get("proj")})
		var res: Dictionary = Combat.enemy_swing(_duelist, _player)
		if rig.is_attacking and i % 4 == 0:
			var thr2: Dictionary = InterceptS.melee_threat(_player, _duelist, 0.33)
			var eb2: Transform3D = rig.weapon_xf
			var mind := 1e9
			if not thr2.is_empty() and bool(thr2.get("ok", false)):
				var tp: Vector3 = thr2["point"]
				for d in rig.blade_discs:
					mind = minf(mind, (eb2 * Vector3(0, float(d["y"]), 0)).distance_to(tp))
			var axl := ""
			if not thr2.is_empty() and bool(thr2.get("ok", false)):
				var pr = _player.rig
				var fb: Vector3 = pr.body.to_local(thr2["point"])
				var yaw2: float = clampf(atan2(-fb.x, -fb.z) * 0.9, -2.8, 2.8)
				var tq: Transform3D = pr._torso_transform(Vector3(pr.torso.rotation.x, yaw2, pr.torso.rotation.z))
				var tt := tq.affine_inverse()
				var pl: Vector3 = tt * thr2["point"]
				for ax in [thr2["axis"], Vector3.UP, Vector3.FORWARD]:
					var up: Vector3 = (tt.basis * ax).normalized()
					var sp: Vector2 = pr.blade_span() * pr.weapon_root.scale.y
					var al: float = clampf((pl - Vector3(pr.BASE_POSE["wpx"], pr.BASE_POSE["wpy"], pr.BASE_POSE["wpz"])).dot(up), sp.x, sp.y)
					var want: Vector3 = pl - up * al
					var got: Vector3 = pr._reachable_hilt(want, up)
					axl += " want=%s got=%s | " % [str(want), str(got)]
			_log("  f=%d el=%.3f thr_ok=%s pt=%s eta=%.3f pt_to_blade=%.3f plan_pt=%s miss=%.3f axmiss=[%s]"
				% [i, rig.attack_elapsed, str(bool(thr2.get("ok",false))), str(thr2.get("point")),
					float(thr2.get("eta",-1)), mind, str(_player._plan_point), _player.rig.last_intercept_miss, axl])
		if rig.is_attacking:
			saw_attack = true
		if _player.is_guard_up():
			guard_on += 1
		else:
			var t: Dictionary = InterceptS.melee_threat(_player, _duelist, 0.33)
			if rig.is_attacking and not bool(t.get("ok", false)):
				threat_empty += 1
		if bool(res.get("hit", false)):
			hit += 1
			var pb: Transform3D = _player.rig.weapon_xf
			var pbp: Transform3D = _player.rig.weapon_prev_xf
			var eb: Transform3D = _duelist.rig.weapon_xf
			var ebp: Transform3D = _duelist.rig.weapon_prev_xf
			var clash: Dictionary = Hit.blade_vs_blade_swept(pb, pb,
				_player.rig.blade_discs, _player.rig.weapon_scale, _player.rig.blade_span(),
				eb, eb, _duelist.rig.blade_discs, _duelist.rig.weapon_scale, _duelist.rig.blade_span())
			var pred: Transform3D = rig.predict_weapon_xf(rig.attack_elapsed)
			var live: Transform3D = rig.weapon_spin.global_transform
			var pred_err := (pred.origin - live.origin).length()
			var thr: Dictionary = InterceptS.melee_threat(_player, _duelist, 0.33)
			_log("t=%.3f HIT %s guard=%s clash_gap=%.3f pred_err=%.3f thr_pt=%s thr_eta=%.3f span=%s"
				% [i / 60.0, str(res), _player.is_guard_up(), float(clash.get("gap", 999)),
					pred_err, str(thr.get("point")), float(thr.get("eta", -9)), str(rig.blade_span())])
			for yy in [0.28, 0.55, 0.9, 1.3, 1.88]:
				var lp: Vector3 = pb * Vector3(0, yy, 0)
				var le: Vector3 = eb * Vector3(0, yy, 0)
				var lpp: Vector3 = pbp * Vector3(0, yy, 0)
				var lpe: Vector3 = ebp * Vector3(0, yy, 0)
				_log("  y=%.2f player=%s->%s  enemy=%s->%s" % [yy, lpp, lp, lpe, le])
		elif bool(res.get("parried", false)):
			blocked += 1
		if i % 90 == 0:
			_log("t=%.1f move=%s elapsed=%.3f attacking=%s guard=%s hits=%d blocked=%d"
				% [i / 60.0,
				_duelist.sequence.normal_move.DISPLAY_NAME if not _duelist.sequence.normal_pose.is_empty() else "none",
				rig.attack_elapsed, rig.is_attacking, _player.is_guard_up(), hit, blocked])
	_log("RESULT: guard_frames=%d hits=%d blocked=%d threat_empty=%d saw_attack=%s"
		% [guard_on, hit, blocked, threat_empty, saw_attack])

func _summary() -> void:
	print("[repro] ========== SUMMARY ==========")
	for s in _report: print("  " + s)
