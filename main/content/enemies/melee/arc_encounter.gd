extends "res://src/game/encounter_unit.gd"

const Model = preload("res://team/arc/scripts/ch/arc_sentinel.gd")
const SCALE := 1.0 / 0.547
const EDGE_RADIUS := 0.24

var _cooldown := 0.0
var _attack := 0
var _blade_prev: Transform3D
var _blade_now: Transform3D
var _window := false
var _consumed := true


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


func blocks_when_seen() -> bool:
	return rig.current_anim != "attack1" and rig.current_anim != "attack2"


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
	clip = rig.current_anim
	var time: float = rig.anim_time()
	_window = clip in ["attack1", "attack2"] and time >= rig.anim_duration() * 0.30 and time <= rig.anim_duration() * 0.87


func resolve_attack(target) -> Dictionary:
	if not _window or _consumed or not target.alive:
		return {"hit": false}
	var cap: Dictionary = target.capsule()
	var blade_length: float = rig.rig.marker_tip.global_position.distance_to(_blade_now.origin)
	var discs := []
	for i in 7:
		discs.append({"y": blade_length * float(i) / 6.0, "r": EDGE_RADIUS})
	var hit: Dictionary = Hit.sweep_blade(_blade_prev, _blade_now, discs, 1.0, cap["a"], cap["b"], cap["r"])
	if not hit.get("hit", false):
		return {"hit": false}
	var location: Vector3 = hit.get("point", center())
	if level.has_method("melee_clear") and not level.melee_clear(center(), location):
		return {"hit": false}
	_consumed = true
	var push: Vector3 = (target.rig.global_position - rig.global_position).slide(Vector3.UP).normalized()
	if target.is_guard_up() and P.getb("parry.melee_block"):
		var guard: Dictionary = Hit.blade_vs_blade_swept(
			target.rig.weapon_prev_xf, target.rig.weapon_xf, target.rig.blade_discs,
			target.rig.weapon_scale, target.rig.blade_span(),
			_blade_prev, _blade_now, discs, 1.0, Vector2(0.0, blade_length))
		if guard.get("hit", false):
			target.on_block(push, P.getf("parry.block_knockback"))
			return {"hit": false, "parried": true, "melee": true, "pos": location, "normal": -push, "push": push}
	var previous: float = target.hp
	target.hurt(damage, push, "被 ARC Sentinel 击中")
	return {"hit": not target.alive or target.hp < previous, "pos": location}


func _blade() -> Transform3D:
	var base: Vector3 = rig.rig.marker_base.global_position
	var tip: Vector3 = rig.rig.marker_tip.global_position
	var axis := (tip - base).normalized()
	var reference := Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > 0.97 else Vector3.UP
	var right := axis.cross(reference).normalized()
	return Transform3D(Basis(right, axis, right.cross(axis)), base)
