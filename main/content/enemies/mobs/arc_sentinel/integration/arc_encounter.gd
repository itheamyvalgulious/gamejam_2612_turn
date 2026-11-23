extends "res://src/game/encounter_unit.gd"

const Model = preload("res://team/arc/scripts/ch/arc_sentinel.gd")
const SCALE := 1.0 / 0.547
const EDGE_RADIUS := 0.24
const HIT_FROM := 0.30
const HIT_TO := 0.87
const ATTACK_CLIPS := ["attack1", "attack2"]

var _cooldown := 0.0
var _attack := 0
var _blade_prev: Transform3D
var _blade_now: Transform3D
var _consumed := true

# Intercept and damage checks share the blade profile in world units.
var blade_discs: Array = []
var weapon_scale := 1.0
var last_dt := 0.0
var is_attacking: bool:
	get:
		return not _consumed and rig.current_anim in ATTACK_CLIPS
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


func blocks_when_seen() -> bool:
	return rig.current_anim not in ATTACK_CLIPS


func on_seen_block(source: Vector3) -> void:
	var local: Vector3 = rig.to_local(source)
	rig.set_block_threat(rad_to_deg(atan2(local.x, local.z)))
	if rig.current_anim != "block":
		rig.play_anim("block")


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
	_cooldown = maxf(0.0, _cooldown - dt)
	var pace := 0.0
	var clip: String = rig.current_anim
	if player != null and player.alive and level.state == "fight" and clip in ["idle", "run"]:
		var center_at: Vector3 = rig.global_position
		var to: Vector3 = (player.rig.global_position - center_at).slide(Vector3.UP)
		var distance := to.length()
		var desired: float = atan2(to.x, to.z) if distance > 0.01 else rig.rotation.y
		rig.rotation.y = rotate_toward(rig.rotation.y, desired, dt * 6.0)
		var clear: bool = not level.has_method("melee_clear") or level.melee_clear(center(), player.rig.global_position + Vector3.UP * 1.4)
		if distance <= 3.25 and clear and _cooldown <= 0.0:
			_attack += 1
			swung_serial += 1
			rig.play_anim("attack1" if _attack % 2 else "attack2")
			_cooldown = rig.anim_duration() + 0.43
			_consumed = false
			Snd.play_at("swing_light", center(), {"gain": 0.44})
		elif distance > 2.65:
			var direction: Vector3 = rig.global_basis.z.normalized()
			if level.has_method("navigation_direction"):
				direction = level.navigation_direction(center_at, player.rig.global_position, direction)
			pace = minf(P.getf("mob.speed"), 8.0)
			rig.global_position += direction * pace * dt
			if clip != "run":
				rig.play_anim("run")
		elif clip != "idle":
			rig.play_anim("idle")
	rig.set_track_speed(pace / SCALE, pace / SCALE)
	_blade_prev = _blade_now
	rig._process(dt)
	_blade_now = _blade()


func predict_weapon_xf(time: float) -> Transform3D:
	var joints: Dictionary = rig.predict_blade_pose(time)
	return _blade_transform(rig.to_global(joints["tool"]), rig.to_global(joints["tip"]))


func resolve_attack(target) -> Dictionary:
	if not is_attacking or not target.alive or attack_elapsed < attack_hit_from or attack_elapsed > attack_hit_to:
		return {"hit": false}
	var push: Vector3 = (target.rig.global_position - rig.global_position).slide(Vector3.UP).normalized()
	if target.is_guard_up() and P.getb("parry.melee_block"):
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
	var cap: Dictionary = target.capsule()
	var hit: Dictionary = Hit.sweep_blade(_blade_prev, _blade_now, blade_discs, weapon_scale, cap["a"], cap["b"], cap["r"])
	if not hit.get("hit", false):
		return {"hit": false}
	var location: Vector3 = hit.get("point", center())
	if level.has_method("melee_clear") and not level.melee_clear(center(), location):
		return {"hit": false}
	_consumed = true
	var previous: float = target.hp
	target.hurt(damage, push, "被 ARC Sentinel 击中")
	return {"hit": not target.alive or target.hp < previous, "pos": location}


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
