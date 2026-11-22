extends Node3D

var rig
var kind := "mob"
var enemy_id := ""
var hp := 100.0
var max_hp := 100.0
var alive := true
var damage := 999.0
var scale_factor := 1.0
var level
var player: PlayerUnit
var projectiles: Projectiles
var arena: Dictionary = {}
var last_hit_serial := -1
var swung_serial := 0
var _dead_t := 0.0


func set_health(value: float) -> void:
	max_hp = value
	hp = value


func blocks_when_seen() -> bool:
	return false


func ground_position() -> Vector3:
	return rig.global_position


func center() -> Vector3:
	return rig.global_position + Vector3.UP * 1.4


func mark_radius() -> float:
	return 1.65


func hit_parts() -> Array:
	return [{"a": center() - Vector3.UP * 0.9, "b": center() + Vector3.UP * 0.8, "r": 0.85}]


func hurt(amount: float, normal := Vector3.UP, knock := 0.0) -> void:
	if not alive or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	if knock > 0.0:
		rig.global_position += normal.slide(Vector3.UP).normalized() * knock
	if hp <= 0.0:
		die()


func die() -> void:
	if not alive:
		return
	alive = false
	_dead_t = 1.0
	Fx.death_burst(center())
	Snd.play_at("death", center(), {"gain": 0.8})
	if level != null:
		level.on_enemy_died(self)


func finish_death(dt: float) -> void:
	_dead_t = maxf(0.0, _dead_t - dt)
	visible = _dead_t > 0.0


func step(_dt: float, ctx: Dictionary) -> void:
	player = ctx.get("player")
	projectiles = ctx.get("projectiles")
	arena = ctx.get("arena", {})
