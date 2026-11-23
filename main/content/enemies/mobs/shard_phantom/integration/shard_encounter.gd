extends "res://src/game/encounter_unit.gd"

const Model = preload("res://team/shard/scripts/character.gd")
const SCALE := 1.0 / 0.547

var anchor_index := 0
var _destination := -1
var _phase_t := 0.0
var _phase_cd := 0.65
var _attack_cd := 1.1
var _shot_pending := false
var _rebase_pending := false


func _ready() -> void:
	enemy_id = "shard_phantom"
	kind = "phase"
	set_health(P.getf("mob.hp"))
	rig = Model.new()
	rig.scale = Vector3.ONE * SCALE
	rig.encounter_projectile = true
	add_child(rig)
	rig.set_process(false)


func hurt(amount: float, normal := Vector3.UP, _knock := 0.0) -> void:
	if _destination < 0 and rig.is_assembled():
		super.hurt(amount, normal, 0.0)


func ground_position() -> Vector3:
	var body: Vector3 = rig.rig.global_position
	return Vector3(body.x, rig.global_position.y, body.z)


func center() -> Vector3:
	return ground_position() + Vector3.UP * 1.6


func hit_parts() -> Array:
	return super.hit_parts() if _destination < 0 and rig.is_assembled() else []


func step(dt: float, ctx: Dictionary) -> void:
	super.step(dt, ctx)
	if not alive:
		finish_death(dt)
		return
	_phase_cd = maxf(0.0, _phase_cd - dt)
	_attack_cd = maxf(0.0, _attack_cd - dt)
	if _destination >= 0:
		_phase_t -= dt
		if _phase_t <= 0.0:
			anchor_index = _destination
			_destination = -1
			rig.reform()
			_rebase_pending = true
			_phase_cd = 2.6
		rig._process(dt)
		return
	if _rebase_pending and rig.is_assembled():
		rig.rebase_encounter()
		_rebase_pending = false
	if rig.current_anim == "attack" and not _shot_pending and rig.anim_time() >= rig.anim_duration() - 0.001:
		rig.play_anim("idle")
	if player != null and player.alive and level.state == "fight" and rig.is_assembled():
		var at: Vector3 = player.rig.global_position
		rig.encounter_target = at + Vector3.UP * 1.8
		var direction: Vector3 = (at - ground_position()).slide(Vector3.UP)
		if direction.length_squared() > 0.01:
			rig.rotation.y = rotate_toward(rig.rotation.y, atan2(direction.x, direction.z), dt * 5.5)
		if rig.current_anim != "attack":
			var next := -1
			if _phase_cd <= 0.0 and level.phase_visible(self):
				next = level.choose_phase_point(self)
			if next >= 0:
				_destination = next
				_shot_pending = false
				rig.disperse_to(arena["anchors"][next])
				_phase_t = rig.anim_duration() * 0.86
				Snd.play_at("ping", center(), {"gain": 0.45})
			elif _attack_cd <= 0.0 and direction.length() < 24.0 and level.melee_clear(center(), at + Vector3.UP * 1.8):
				rig.play_anim("attack")
				_attack_cd = 2.0
				_shot_pending = true
		elif _shot_pending and rig.anim_time() >= float(rig._attack_moments()[2]):
			_shot_pending = false
			var muzzle: Transform3D = rig._compute_muzzle(float(rig._attack_moments()[2]))
			var origin: Vector3 = muzzle.origin
			var aim := at + Vector3.UP * 1.8
			if level.melee_clear(origin, aim):
				projectiles.spawn_shard(origin, (aim - origin).normalized(), P.getf("archer.arrow_speed") * 0.7, P.getf("archer.arrow_damage"))
				Snd.play_at("swing_light", origin, {"gain": 0.44})
	rig._process(dt)


func hud_alert(target: PlayerUnit) -> bool:
	if not _shot_pending or rig.current_anim != "attack":
		return false
	var aim: Vector3 = target.rig.global_position + Vector3.UP * 1.8
	return float(rig._attack_moments()[2]) - rig.anim_time() <= 0.28 and level.melee_clear(center(), aim)
