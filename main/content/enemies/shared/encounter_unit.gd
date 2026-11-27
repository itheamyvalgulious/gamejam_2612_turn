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
	# Rigs con BodyColliders (arc/wheel/shard/duelist/boss) ya devuelven sus
	# cilindros por articulación. El resto conserva la cápsula genérica.
	if rig != null and rig.has_method("body_colliders"):
		return rig.body_colliders()
	return [{"a": center() - Vector3.UP * 0.9, "b": center() + Vector3.UP * 0.8, "r": 0.85}]


var _blade_contact := Vector3.ZERO
var _blade_travel := Vector3.ZERO
var _blade_normal := Vector3.UP


func hurt(amount: float, normal := Vector3.UP, knock := 0.0) -> void:
	if not alive or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	if knock > 0.0:
		rig.global_position += normal.slide(Vector3.UP).normalized() * knock
	if hp <= 0.0:
		die()


## 记录刀口信息（致命一刀的接触点/行进方向），die() 交给 DeathField 切割。
func hurt_by_blade(amount: float, normal: Vector3, knock: float,
		travel: Vector3, contact: Dictionary) -> void:
	_blade_contact = contact.get("point", contact.get("blade_point", center()))
	_blade_travel = travel
	_blade_normal = normal
	hurt(amount, normal, knock)


func die() -> void:
	if not alive:
		return
	alive = false
	_dead_t = 1.0
	Fx.death_burst(center())
	Snd.play_at("death", center(), {"gain": 0.8})
	# 新的物理死亡路径：关卡装了 DeathField 就走切割 ragdoll，
	# 否则（独立开发场景）退回纯特效死亡。
	var field: Object = level.get_meta(&"death_field") if level != null else null
	if field != null and not get_meta(&"death_done", false):
		set_meta(&"death_done", true)
		field.enemy_died(self, {"contact": _blade_contact,
			"travel": _blade_travel, "normal": _blade_normal})
	if level != null:
		level.on_enemy_died(self)


## 关卡重生时的「原地复活」：敌人节点池化复用，不 queue_free 重建。
## 基类只复位公共字段；AI/rig 内部状态由各 encounter 覆写 _on_respawn 复位。
## spawn_xf 由 level 在出生点定好后赋值，respawn 直接摆回去。
var spawn_xf := Transform3D.IDENTITY
var spawn_rig_xf := Transform3D.IDENTITY


func respawn() -> void:
	set_meta(&"death_done", false)
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
