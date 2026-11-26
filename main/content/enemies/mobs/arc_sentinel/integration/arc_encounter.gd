extends "res://src/game/encounter_unit.gd"

const Model = preload("res://team/arc/scripts/ch/arc_sentinel.gd")
const SCALE := 1.0 / 0.547
const EDGE_RADIUS := 0.24
const HIT_FROM := 0.30
const HIT_TO := 0.87
const ATTACK_CLIPS := ["attack1", "attack2"]
const STRIKE_HEIGHT := 0.87

var _cooldown := 0.0
var _attack := 0
var _blade_prev: Transform3D
var _blade_now: Transform3D
var _consumed := true
var _ground_move: Callable
var _support_floor: Callable
var _waypoint: Callable
var _fall_speed := 0.0


func _on_respawn() -> void:
	_fall_speed = 0.0
	_cooldown = 0.0
	_attack = 0
	_consumed = true
	if rig != null:
		rig.play_anim("idle")
		rig.rotation = Vector3(0.0, rig.rotation.y, 0.0)
		_blade_now = _blade()
		_blade_prev = _blade_now

# Intercept and damage checks share the blade profile in world units.
var blade_discs: Array = []
var weapon_scale := 1.0
var last_dt := 0.0
var is_attacking: bool:
	get:
		return _fall_speed <= 0.0 and not _consumed and rig.current_anim in ATTACK_CLIPS
var attack_elapsed: float:
	get:
		return rig.anim_time()
var attack_hit_from: float:
	get:
		return rig.anim_duration() * HIT_FROM
var attack_hit_to: float:
	get:
		return rig.anim_duration() * HIT_TO

var _blade_length := 0.0


func _ready() -> void:
	enemy_id = "arc_sentinel"
	kind = "mob"
	set_health(P.getf("mob.hp"))
	rig = Model.new()
	rig.scale = Vector3.ONE * SCALE
	add_child(rig)
	rig.set_process(false)
	_blade_now = _blade()
	_blade_prev = _blade_now
	_blade_length = rig.rig.marker_tip.global_position.distance_to(_blade_now.origin)
	for i in 7:
		blade_discs.append({"y": _blade_length * float(i) / 6.0, "r": EDGE_RADIUS})


func use_ground_routes(move: Callable, support: Callable, waypoint: Callable) -> void:
	_ground_move = move
	_support_floor = support
	_waypoint = waypoint


func hurt(amount: float, normal := Vector3.UP, knock := 0.0) -> void:
	if _ground_move.is_valid() and alive and amount > 0.0 and knock > 0.0:
		var from: Vector3 = rig.global_position
		var push := normal.slide(Vector3.UP).normalized() * knock
		rig.global_position = _ground_move.call(from, from + push)
		_blade_now = _blade()
		_blade_prev = _blade_now
		knock = 0.0
	super.hurt(amount, normal, knock)


func blocks_when_seen() -> bool:
	if _guard_broken > 0.0:
		return false
	return rig.current_anim not in ATTACK_CLIPS


func on_seen_block(source: Vector3) -> void:
	var local: Vector3 = rig.to_local(source)
	rig.set_block_threat(rad_to_deg(atan2(local.x, local.z)))
	if rig.current_anim != "block":
		rig.play_anim("block")


## Q 键打断自己挥剑时强行破防：把 block 播完 + 标记短时间不可再架。
var _guard_broken := 0.0
func break_guard(_source: Vector3) -> void:
	_guard_broken = 1.2
	if rig.current_anim == "block":
		# 快放完这一小段 block，让它自然回到 idle
		rig.set_anim_time(rig.anim_duration() * 0.92)


func hit_parts() -> Array:
	var up := Vector3.UP * SCALE
	var front: Vector3 = rig.global_basis.z.normalized() * SCALE
	var center_at: Vector3 = rig.global_position
	return [
		{"a": center_at - front * 0.37 + up * 0.3, "b": center_at + front * 0.39 + up * 0.38, "r": 0.48 * SCALE},
		{"a": center_at + up * 0.57, "b": center_at + up * 1.14, "r": 0.40 * SCALE},
	]


func step(dt: float, ctx: Dictionary) -> void:
	super.step(dt, ctx)
	last_dt = dt
	if not alive:
		finish_death(dt)
		return
	_guard_broken = maxf(0.0, _guard_broken - dt)
	_cooldown = maxf(0.0, _cooldown - dt)
	var pace := 0.0
	var grounded := _settle_on_ground(dt)
	var clip: String = rig.current_anim
	if grounded and player != null and player.alive and level.state == "fight" and clip in ["idle", "run"]:
		var center_at: Vector3 = rig.global_position
		var target: Vector3 = player.rig.global_position
		var offset := (target - center_at).slide(Vector3.UP)
		var distance := offset.length()
		var same_level := not _ground_move.is_valid() or absf(target.y - center_at.y) <= STRIKE_HEIGHT
		var clear: bool = same_level and (not level.has_method("melee_clear") \
			or level.melee_clear(center(), target + Vector3.UP * 1.4))
		var chase := target
		if _waypoint.is_valid() and (not clear or distance > 3.25):
			chase = _waypoint.call(center_at, target)
		var heading := (chase - center_at).slide(Vector3.UP)
		var desired: float = atan2(heading.x, heading.z) if heading.length_squared() > 0.0001 else rig.rotation.y
		rig.rotation.y = rotate_toward(rig.rotation.y, desired, dt * 6.0)
		if distance <= 3.25 and clear and _cooldown <= 0.0:
			_attack += 1
			swung_serial += 1
			rig.play_anim(_choose_attack(player))
			_cooldown = rig.anim_duration() + 0.43
			_consumed = false
			Snd.play_at("swing_light", center(), {"gain": 0.44})
		elif (distance > 2.65 or not same_level) and dt > 0.0:
			pace = _move_toward(center_at, target, heading, dt)
			var movement_clip := "run" if pace > 0.04 else "idle"
			if clip != movement_clip:
				rig.play_anim(movement_clip)
		elif clip != "idle":
			rig.play_anim("idle")
	rig.set_track_speed(pace / SCALE, pace / SCALE)
	_blade_prev = _blade_now
	rig._process(dt)
	_blade_now = _blade()


func _settle_on_ground(dt: float) -> bool:
	if not _support_floor.is_valid():
		return true
	var at: Vector3 = rig.global_position
	var floor_y: float = _support_floor.call(at)
	if at.y <= floor_y + 0.04:
		_fall_speed = 0.0
		return true
	# A displaced unit must land before it can chase or swing.
	_fall_speed += P.getf("jump.gravity") * dt
	at.y = maxf(floor_y, at.y - _fall_speed * dt)
	rig.global_position = at
	if at.y > floor_y:
		_consumed = true
		if rig.current_anim != "idle":
			rig.play_anim("idle")
		return false
	_fall_speed = 0.0
	return true


func _move_toward(from: Vector3, target: Vector3, heading: Vector3, dt: float) -> float:
	var pace := minf(P.getf("mob.speed"), 8.0)
	var forward: Vector3 = rig.global_basis.z.normalized()
	if _ground_move.is_valid():
		if heading.normalized().dot(forward) < 0.55:
			return 0.0
		var at: Vector3 = _ground_move.call(from, from + heading.limit_length(pace * dt))
		rig.global_position = at
		return (at - from).slide(Vector3.UP).length() / dt
	if level.has_method("navigation_direction"):
		forward = level.navigation_direction(from, target, forward)
	rig.global_position += forward * pace * dt
	return pace


func predict_weapon_xf(time: float) -> Transform3D:
	var joints: Dictionary = rig.predict_blade_pose(time)
	return _blade_transform(rig.to_global(joints["tool"]), rig.to_global(joints["tip"]))


func resolve_attack(target) -> Dictionary:
	if not is_attacking or not target.alive or attack_elapsed < attack_hit_from or attack_elapsed > attack_hit_to:
		return {"hit": false}
	var push: Vector3 = (target.rig.global_position - rig.global_position).slide(Vector3.UP).normalized()
	if P.getb("parry.melee_block"):  # 碰到刀即格挡：不再要求先举起
		var guard: Dictionary = Hit.blade_vs_blade_swept(
			target.rig.weapon_prev_xf, target.rig.weapon_xf, target.rig.blade_discs,
			target.rig.weapon_scale, target.rig.blade_span(),
			_blade_prev, _blade_now, blade_discs, weapon_scale, Vector2(0.0, _blade_length))
		if guard.get("hit", false):
			var contact: Vector3 = guard["point"]
			if not level.has_method("melee_clear") or level.melee_clear(center(), contact):
				_consumed = true
				target.on_block(push, P.getf("parry.block_knockback"))
				return {"hit": false, "parried": true, "melee": true, "pos": contact, "normal": guard["normal"], "push": push}
	var parts: Array = target.rig.hit_parts() if target.rig != null and target.rig.has_method("hit_parts") \
		else []
	var hit: Dictionary = Hit.sweep_blade_parts(_blade_prev, _blade_now, blade_discs, weapon_scale, parts) \
		if not parts.is_empty() \
		else Hit.sweep_blade(_blade_prev, _blade_now, blade_discs, weapon_scale,
			target.capsule()["a"], target.capsule()["b"], target.capsule()["r"])
	if not hit.get("hit", false):
		return {"hit": false}
	var location: Vector3 = hit.get("point", center())
	if level.has_method("melee_clear") and not level.melee_clear(center(), location):
		return {"hit": false}
	_consumed = true
	var previous: float = target.hp
	target.hurt(damage, push, "被 ARC Sentinel 击中")
	return {"hit": not target.alive or target.hp < previous, "pos": location}


## 按「现在的姿势能不能打中、会不会撞上你的刀」在两个挥击 clip 之间做选择。
## attack1 是上段劈、attack2 是侧扫：先对每个 clip 的判定窗取样几个刀位，
## 看扫掠体是贴近身体（hit_parts）还是贴近玩家刀身（blade 段）；
## 能命中且不送格挡的最好，打不中的不选，全一样就照旧交替保变化。
func _choose_attack(target) -> String:
	var parts: Array = target.rig.hit_parts() if target.rig != null and target.rig.has_method("hit_parts") \
		else []
	if parts.is_empty() or not rig.has_method("predict_blade_pose_for"):
		return "attack1" if _attack % 2 else "attack2"
	# 玩家当前刀段：起手这一瞬的静止刀身就是「他现在怎么架」。
	var pspan: Vector2 = target.rig.blade_span()
	var pb0: Vector3 = target.rig.weapon_xf * Vector3(0, pspan.x, 0)
	var pb1: Vector3 = target.rig.weapon_xf * Vector3(0, pspan.y, 0)
	const CLIPS := ["attack1", "attack2"]
	var scores: Array = []
	for clip in CLIPS:
		var dur: float = rig.anim.duration(clip)
		var t0: float = dur * HIT_FROM
		var t1: float = dur * HIT_TO
		var touch_body := false
		var touch_blade := false
		var prev_xf := Transform3D.IDENTITY
		var have_prev := false
		for i in 6:
			var e: float = lerpf(t0, t1, float(i) / 5.0)
			var joints: Dictionary = rig.predict_blade_pose_for(clip, e)
			var xf: Transform3D = _blade_transform(rig.to_global(joints["tool"]),
				rig.to_global(joints["tip"]))
			if have_prev:
				# 这一小段扫掠会不会扫到身体 / 扫到我的刀
				var hb: Dictionary = Hit.sweep_blade_parts(prev_xf, xf, blade_discs,
					weapon_scale, parts)
				if bool(hb.get("hit", false)):
					touch_body = true
				var hg: Dictionary = Hit.blade_vs_blade_swept(prev_xf, xf, blade_discs,
					weapon_scale, Vector2(0.0, _blade_length),
					target.rig.weapon_prev_xf, target.rig.weapon_xf,
					target.rig.blade_discs, target.rig.weapon_scale, pspan)
				if bool(hg.get("hit", false)):
					touch_blade = true
			prev_xf = xf
			have_prev = true
		var score := 0
		if touch_body:
			score += 2
		if touch_blade:
			score -= 3
		scores.append(score)
	var pick_idx := _attack % 2 if scores[0] == scores[1] else (0 if scores[0] > scores[1] else 1)
	return CLIPS[pick_idx]


func _blade() -> Transform3D:
	var base: Vector3 = rig.rig.marker_base.global_position
	var tip: Vector3 = rig.rig.marker_tip.global_position
	return _blade_transform(base, tip)


func _blade_transform(base: Vector3, tip: Vector3) -> Transform3D:
	var axis := (tip - base).normalized()
	var reference := Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > 0.97 else Vector3.UP
	var right := axis.cross(reference).normalized()
	return Transform3D(Basis(right, axis, right.cross(axis)), base)


func hud_alert(target: PlayerUnit) -> bool:
	return is_attacking and attack_elapsed >= attack_hit_from - 0.26 and attack_elapsed <= attack_hit_to \
		and ground_position().distance_squared_to(target.rig.global_position) < 4.25 * 4.25
