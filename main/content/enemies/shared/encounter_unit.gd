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


## 关卡重生时的「原地复活」：敌人节点池化复用，不 queue_free 重建。
## 基类只复位公共字段；AI/rig 内部状态由各 encounter 覆写 _on_respawn 复位。
## spawn_xf 由 level 在出生点定好后赋值，respawn 直接摆回去。
var spawn_xf := Transform3D.IDENTITY
var spawn_rig_xf := Transform3D.IDENTITY


func respawn() -> void:
	alive = true
	hp = max_hp
	_dead_t = 0.0
	visible = true
	last_hit_serial = -1
	swung_serial = 0
	if spawn_xf != Transform3D.IDENTITY:
		global_transform = spawn_xf
	if rig != null and spawn_rig_xf != Transform3D.IDENTITY:
		rig.transform = spawn_rig_xf
	_on_respawn()


func _on_respawn() -> void:
	pass


func finish_death(dt: float) -> void:
	_dead_t = maxf(0.0, _dead_t - dt)
	visible = _dead_t > 0.0


func step(_dt: float, ctx: Dictionary) -> void:
	player = ctx.get("player")
	projectiles = ctx.get("projectiles")
	arena = ctx.get("arena", {})
