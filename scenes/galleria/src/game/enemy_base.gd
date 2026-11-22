extends Node3D
class_name EnemyUnit
## 敌人基类：同一个四足机甲建模 + 各自配色，三种行为由子类 think() 决定。
##
## 共性：真实刀体积碰撞、一击必杀伤害、受击闪白、视野感知（由 Combat 判定）、
## 远处自动降频（rules.enemy_lod）。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const Rig = preload("res://src/vesper/mech_rig.gd")

var rig
var kind := "mob"
var palette: Dictionary = {}
var hp := 100.0
var max_hp := 100.0
var alive := true
var damage := 999.0          # 一击必杀
var scale_factor := 1.0
var player: PlayerUnit
var cam: GameCam
var arena: Dictionary = {}
var projectiles: Projectiles
var level                      # LevelUnit

var last_hit_serial := -1      # 玩家第几次挥砍打过我（去重）
var swung_serial := 0          # 我第几次挥砍（玩家受击去重）
var hit_flash := 0.0
var _lod_acc := 0.0
var _lod_dt := 1.0 / 60.0
var _mats_flash: Array = []
var _dead_t := 0.0
var _was_in_window := false


func setup(p_kind: String, p_palette: Dictionary, opts := {}) -> void:
	kind = p_kind
	palette = p_palette
	scale_factor = float(opts.get("scale", 1.0))
	rig = Rig.new()
	rig.name = "Mech"
	rig.auto_step = false
	rig.set_process(false)
	rig.palette = p_palette
	rig.has_weapon = bool(opts.get("weapon", true))
	add_child(rig)
	rig.footstep.connect(_on_footstep)
	if scale_factor != 1.0:
		rig.scale = Vector3(scale_factor, scale_factor, scale_factor)
	max_hp = float(opts.get("hp", 100.0))
	hp = max_hp
	damage = float(opts.get("damage", 999.0))
	rig.facing_override = true
	if bool(opts.get("no_vfx", false)):
		rig.vfx_enabled = false


## 受击判定件：由建模 rig 的真实关节位姿生成（骨盆/胸口/背包/头/肩甲/四肢）。
## 玩家挥砍、弹回的飞行物都逐件做几何判定 —— 打腿、打手、打肩甲都算命中。
## 注意：敌人没有「一个躯干胶囊」这种兜底判定，全部命中都走这里。
func hit_parts() -> Array:
	if rig == null:
		return []
	return rig.hit_parts()


func center() -> Vector3:
	return rig.global_position + Vector3(0, 2.3 * scale_factor, 0)


## 视野判定用的包围球半径（要盖住整个机体，避免"露一角就该算看见"）
func mark_radius() -> float:
	return 2.6 * scale_factor


func blocks_when_seen() -> bool:
	return false


func fire_origin() -> Vector3:
	return rig.global_position + Vector3(0, 3.0 * scale_factor, 0)


func can_counter() -> bool:
	return false


func dist_to_player() -> float:
	if player == null:
		return 999.0
	var a: Vector3 = rig.global_position
	var b: Vector3 = player.rig.global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


var turn_speed := 7.0


func face_player(strength := 1.0) -> void:
	if player == null:
		return
	rig.facing_override = true
	var target: Vector3 = player.rig.global_position
	rig.face_target(target)
	rig.face_rate = turn_speed * strength


func hurt(amount: float, normal := Vector3.UP, knock := 0.0) -> void:
	if not alive or amount <= 0.0:
		return
	hp -= amount
	if knock > 0.0:
		var n := normal
		n.y = 0.0
		if n.length() > 0.01:
			rig.position += n.normalized() * knock
	hit_flash = 0.22
	if Fx != null:
		Fx.spark(rig.global_position + Vector3(0, 2.2 * scale_factor, 0), normal, 1.0)
		Fx.shake(0.35)
	if hp <= 0.0:
		die()


func die() -> void:
	if not alive:
		return
	alive = false
	_dead_t = 1.2
	rig.vfx_enabled = true
	Snd.play_at("death", rig.global_position + Vector3(0, 2.0 * scale_factor, 0),
		{"gain": 1.2 if kind == "boss" else 0.8})
	if Fx != null:
		Fx.death_burst(rig.global_position + Vector3(0, 2.0 * scale_factor, 0))
	if level != null:
		level.on_enemy_died(self)


func step(dt: float, ctx: Dictionary) -> void:
	if rig == null:
		return
	player = ctx.get("player")
	cam = ctx.get("cam")
	arena = ctx.get("arena", {})
	projectiles = ctx.get("projectiles")
	if not alive:
		_dead_t = maxf(0.0, _dead_t - dt)
		rig.vfx_enabled = false
		if _dead_t <= 0.0 and visible:
			visible = false
			rig.visible = false
		return

	# 远处降频（省 CPU）
	var lod_step := dt
	if P.getb("rules.enemy_lod") and cam != null:
		var d := cam.camera.global_position.distance_to(rig.global_position)
		if d > 55.0:
			_lod_acc += dt
			if _lod_acc < 1.0 / 20.0:
				return
			lod_step = _lod_acc
			_lod_acc = 0.0
	_sync_params()
	think(lod_step)
	rig.advance(lod_step)
	var in_win: bool = rig.in_hit_window()
	if in_win and not _was_in_window:
		var blade: Vector3 = rig.weapon_xf * Vector3(0, 1.4, 0)
		Snd.play_at("swing_heavy" if kind == "boss" else "swing_light", blade,
			{"gain": 0.75 if kind == "boss" else 0.55})
	_was_in_window = in_win
	hit_flash = maxf(0.0, hit_flash - lod_step)
	_apply_flash()


func _on_footstep(pos: Vector3, strength: float) -> void:
	Snd.play_at("step", pos, {"gain": (1.6 if kind == "boss" else 1.0) * (0.55 + 0.45 * strength)})


func _sync_params() -> void:
	rig.jump_vel = P.jump_velocity()
	rig.grav = P.getf("jump.gravity")


func _apply_flash() -> void:
	if hit_flash > 0.0:
		var k := clampf(hit_flash / 0.22, 0.0, 1.0)
		for m in _flash_mats():
			if m is StandardMaterial3D:
				(m as StandardMaterial3D).emission_energy_multiplier = 3.0 + 14.0 * k
	elif not _mats_flash.is_empty():
		for m in _mats_flash:
			if is_instance_valid(m) and m is StandardMaterial3D:
				(m as StandardMaterial3D).emission_energy_multiplier = 1.0
		_mats_flash.clear()


func _flash_mats() -> Array:
	if _mats_flash.is_empty():
		_collect_flash(rig)
	return _mats_flash


func _collect_flash(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var m = (c as MeshInstance3D).material_override
			if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
				_mats_flash.append(m)
		if c is Node3D:
			_collect_flash(c)


## 子类实现
func think(_dt: float) -> void:
	pass
