extends Node
## 刺击格挡复现：开 --repro-stab，玩家始终格挡，站刀客 pursuit_sweep 范围内
var _level
var _player
var _duelist
var _stat_blocked := 0
var _stat_hit := 0
var _stat_overhead := 0

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
	print("[stab] SUMMARY blocked=%d body_hit=%d overhead_hit=%d" % [
		_stat_blocked, _stat_hit, _stat_overhead])
	get_tree().quit()

func _test() -> void:
	var rig = _duelist.rig
	# 玩家站得略近，引诱刀客出突进/刺击而不是横扫
	_player.rig.global_position = rig.global_position + Vector3(2.2, 0.0, 0.0)
	_player.rig.global_transform = Transform3D(Basis.IDENTITY, _player.rig.global_position)
	_player.alive = true
	var Hit = preload("res://runtime/systems/galleria/core/hitgd.gd")
	var Combat = preload("res://runtime/systems/galleria/game/combat.gd")
	for i in 900:
		_player.parry_timer = 1.0  # 常开格挡
		_player.step(1.0/60.0, _level.arena, _level.enemies)
		_duelist.step(1.0/60.0, {"player": _player, "arena": _level.arena, "projectiles": null})
		var res: Dictionary = Combat.enemy_swing(_duelist, _player)
		if i in range(228, 242):
			print("[stab] f=%d reach_key=%s alt=%s" % [i, _player._reach_enemy, str(_player._reach_alt)])
		if i in range(226, 240):
			print("[stab] f=%d on=%s left=%.3f plan=%s idle=%.2f" % [
				i, _player._intercept_on, _player._plan_left,
				_player._plan_point, _player._plan_idle])
		if i in [220, 225, 228, 230, 232, 234, 236]:
			var InterceptS = preload("res://runtime/systems/galleria/game/intercept.gd")
			var thr: Dictionary = InterceptS.melee_threat(_player, _duelist, 0.33)
			print("[stab] f=%d el=%.3f hit_to=%.3f thr=%s" % [i, rig.attack_elapsed,
				rig.attack_hit_to, str(thr)])
		if rig.is_attacking and i % 2 == 0:
			var clash: Dictionary = Hit.blade_vs_blade_swept(
				_player.rig.weapon_prev_xf, _player.rig.weapon_xf,
				_player.rig.blade_discs, _player.rig.weapon_scale, _player.rig.blade_span(),
				rig.weapon_prev_xf, rig.weapon_xf, rig.blade_discs, rig.weapon_scale, rig.blade_span())
			var eb: Transform3D = rig.weapon_xf
			var es := Vector2(1e9, -1e9)
			for d in rig.blade_discs:
				es.x = minf(es.x, float(d["y"])); es.y = maxf(es.y, float(d["y"]))
			print("[stab] f=%d el=%.3f gap=%.2f hit=%s parry=%s eb0=%s eb1=%s plan=%s" % [
				i, rig.attack_elapsed, float(clash.get("gap",-1)),
				res.get("hit"), res.get("parried"),
				eb * Vector3(0, es.x, 0), eb * Vector3(0, es.y, 0),
				_player._plan_point])
		elif bool(res.get("hit", false)) or bool(res.get("parried", false)):
			var pos: Vector3 = res.get("pos", Vector3.ZERO)
			var kind := "body"
			if bool(res.get("hit", false)) and pos.y > 3.9:
				kind = "overhead"
			print("[stab] f=%d RESULT %s hit=%s parry=%s pos=%s" % [
				i, kind, res.get("hit"), res.get("parried"), pos])
			if kind == "body":
				if bool(res.get("parried", false)):
					_stat_blocked += 1
				else:
					_stat_hit += 1
			else:
				_stat_overhead += 1
