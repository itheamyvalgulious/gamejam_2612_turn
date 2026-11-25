extends Node
var _level
var _player
var _duelist
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	TurnSession.open_level(9)
	while TurnSession.active_level_index() != 9 or get_tree().current_scene == null:
		await get_tree().process_frame
	for i in 30: await get_tree().process_frame
	_level = get_tree().current_scene.get("level")
	_player = get_tree().current_scene.get("player")
	for e in _level.enemies:
		if e.kind == "duelist": _duelist = e
	await _test()
	get_tree().quit()

func _test() -> void:
	var rig = _duelist.rig
	_player.rig.global_position = rig.global_position + Vector3(2.6, 0.0, 0.4)
	_player.rig.global_transform = Transform3D(Basis.IDENTITY, _player.rig.global_position)
	_player.alive = true
	var Hit = preload("res://runtime/systems/galleria/core/hitgd.gd")
	var InterceptS = preload("res://runtime/systems/galleria/game/intercept.gd")
	var Combat = preload("res://runtime/systems/galleria/game/combat.gd")
	for i in 400:
		_player.parry_timer = 1.0
		_player.step(1.0/60.0, _level.arena, _level.enemies)
		_duelist.step(1.0/60.0, {"player": _player, "arena": _level.arena, "projectiles": null})
		var res: Dictionary = Combat.enemy_swing(_duelist, _player)
		if i in [230, 235]:
			var thr9: Dictionary = InterceptS.melee_threat(_player, _duelist, 0.33)
			print("[repro] f=%d thr9=%s alive=%s/%s is_att=%s discs=%d el=%.3f to=%.3f" % [
				i, str(thr9), _player.alive, _duelist.alive, rig.is_attacking,
				rig.blade_discs.size(), rig.attack_elapsed, rig.attack_hit_to])
			var thr2: Dictionary = InterceptS.melee_threat(_player, _duelist, 0.33)
			print("[repro] f=%d thr=" % i, thr2, " miss=%.3f" % _player.rig.blade_reach_miss(
				thr2.get("point", Vector3.ZERO), thr2.get("axis", Vector3.UP),
				thr2.get("normal", Vector3.UP), 0.9),
				" fb=", str(_player._fallback_lock))
		if i == 200:
			var cap2: Dictionary = _player.capsule()
			var ws2: float = rig.weapon_scale
			for k in 12:
				var ek: float = lerpf(rig.attack_hit_from, rig.attack_hit_to, float(k)/11.0)
				var xf2: Transform3D = rig.predict_weapon_xf(ek)
				for d in rig.blade_discs:
					var dp: Vector3 = xf2 * Vector3(0, float(d["y"]), 0)
					var dd := _p2seg(dp, cap2["a"], cap2["b"]) - float(d["r"])*ws2 - float(cap2["r"])
					if dd <= 0.0:
						print("[repro] e_contact=%.3f (k=%d y=%.2f dd=%.2f)" % [ek, k, float(d["y"]), dd])
						break
			var InterceptS2 = preload("res://runtime/systems/galleria/game/intercept.gd")
			var thr: Dictionary = InterceptS2.melee_threat(_player, _duelist, 0.33)
			print("[repro] thr=", thr, " miss=%.3f" % _player.rig.blade_reach_miss(
				thr.get("point", Vector3.ZERO), thr.get("axis", Vector3.UP),
				thr.get("normal", Vector3.UP), 0.9),
				" fallback=", str(_player._fallback_lock))
		if rig.is_attacking or bool(res.get("parried", false)) or (i > 190 and i < 235):
			var clash: Dictionary = Hit.blade_vs_blade_swept(
				_player.rig.weapon_prev_xf, _player.rig.weapon_xf,
				_player.rig.blade_discs, _player.rig.weapon_scale, _player.rig.blade_span(),
				rig.weapon_prev_xf, rig.weapon_xf, rig.blade_discs, rig.weapon_scale, rig.blade_span())
			var pb: Transform3D = _player.rig.weapon_xf
			var eb: Transform3D = rig.weapon_xf
			var espan := Vector2(1e9, -1e9)
			for d in rig.blade_discs:
				espan.x = minf(espan.x, float(d["y"])); espan.y = maxf(espan.y, float(d["y"]))
			var ep0: Vector3 = eb * Vector3(0, espan.x, 0)
			var ep1: Vector3 = eb * Vector3(0, espan.y, 0)
			print("[repro] f=%d el=%.3f plan_pt=%s myb=[%s|%s] eb=[%s|%s] clash_gap=%.2f hit=%s parry=%s" % [
				i, rig.attack_elapsed, _player._plan_point,
				pb * Vector3(0, _player.rig.blade_span().x, 0),
				pb * Vector3(0, _player.rig.blade_span().y, 0),
				ep0, ep1,
				float(clash.get("gap", -1)), res.get("hit"), res.get("parried")])

static func _p2seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p-a).dot(ab)/maxf(ab.length_squared(),1e-6),0.0,1.0)
	return (p-(a+ab*t)).length()
