extends EnemyUnit
class_name EnemyBoss
## 大怪（×2 体型）：二循环 + 视线秒杀。
##
##   阶段 1：站定，向你挥刀 → 放出刀气（飞行物，可弹反）
##   阶段 2：冲撞 → 近身重击（范围 AoE）
##   全程：只要你**看见它**（它在你的相机画面里），它就会用激光秒杀你。
##         预警时长默认 0（出现即死），可以在 ~ 面板里调。
##
## 第三关的四面墙灯会把它的轮廓投影到墙上，玩家靠影子读招。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

var state := "gap"
var st_t := 0.0
var laser_cd := 1.5
var laser_warn_left := 0.0
var qi_fired := false
var phase_attacked := false
var slam_done := false
var charge_ready := 0.0
var _beam_node: Node3D
var _beam_cd := 0.0


func setup_boss(p_palette: Dictionary) -> void:
	setup("boss", p_palette, {"hp": P.getf("boss.hp"), "damage": P.getf("boss.slam_damage"),
		"scale": P.getf("boss.scale")})
	rig.face_rate = 3.2
	state = "gap"
	st_t = 0.0
	laser_cd = 0.0


func think(dt: float) -> void:
	st_t += dt
	_handle_laser(dt)
	_beam_cd = maxf(0.0, _beam_cd - dt)
	if _beam_cd <= 0.0 and _beam_node != null and is_instance_valid(_beam_node):
		_beam_node.queue_free()
		_beam_node = null

	match state:
		"gap":
			_approach_slow(dt)
			if st_t >= P.getf("boss.cycle_gap"):
				_enter("qi")
		"qi":
			_phase_qi(dt)
		"gap2":
			_approach_slow(dt)
			if st_t >= P.getf("boss.cycle_gap") * 0.6:
				_enter("charge")
		"charge":
			_phase_charge(dt)


func _enter(s: String) -> void:
	state = s
	st_t = 0.0
	qi_fired = false
	phase_attacked = false
	slam_done = false
	charge_ready = 0.0
	# 切相位时打断还在播的攻击（否则上一相的 GUILLOTINE 会把整个冲撞段锁死）
	if rig != null:
		rig.is_attacking = false
		rig.attack_name = ""
		rig.attack_elapsed = 0.0
		rig.guard = 0.0


func _approach_slow(dt: float) -> void:
	face_player(0.8)
	var d := dist_to_player()
	if d > 14.0 and player != null:
		var to_p: Vector3 = player.rig.global_position - rig.global_position
		to_p.y = 0.0
		rig.move_command = to_p.normalized() * P.getf("boss.speed")
	else:
		rig.move_command = Vector3.ZERO


## 阶段 1：原地挥刀 → 刀气
func _phase_qi(dt: float) -> void:
	face_player(1.0)
	rig.move_command = Vector3.ZERO
	var dur := P.getf("boss.phase1")
	var wind := P.getf("boss.windup")
	if not phase_attacked:
		phase_attacked = true
		var w := 0.55 * wind
		var a := 0.22 * wind
		var r := maxf(0.2, dur - w - a - 0.3)
		rig.set_timings({"boss_qi": {"duration": w + a + r, "windup": w, "active": a, "recovery": r}})
		rig.timing_key = "boss_qi"
		rig.force_attack("heavy")
		swung_serial += 1
	if not qi_fired and st_t >= 0.52 * dur:
		qi_fired = true
		_release_qi()
	if st_t >= dur:
		_enter("gap2")


func _release_qi() -> void:
	if projectiles == null or player == null:
		return
	var fwd: Vector3 = -rig.global_transform.basis.z
	var from: Vector3 = rig.global_position + Vector3(0, 3.4 * scale_factor, 0) + fwd * 3.2 * scale_factor
	var aim: Vector3 = player.rig.global_position + Vector3(0, 2.2, 0)
	var dir: Vector3 = (aim - from).normalized()
	projectiles.spawn_qi(from, dir, P.getf("boss.qi_speed"), P.getf("boss.qi_damage"),
		P.getf("boss.qi_radius"))
	if Fx != null:
		Fx.slash_arc(rig.weapon_xf, 5.0, 2.2, Color(1.0, 0.2, 0.12), 0.3)
		Fx.shake(0.8)


## 阶段 2：冲撞 → 重击
func _phase_charge(dt: float) -> void:
	face_player(1.4)
	var dur := P.getf("boss.phase2")
	var wind := 0.34 * P.getf("boss.windup")
	if st_t < wind:
		rig.move_command = Vector3.ZERO
		rig.guard = 0.6
		return
	rig.guard = 0.0
	var d := dist_to_player()
	if not slam_done and d < P.getf("boss.slam_radius") * 0.72:
		_slam()
		slam_done = true
	elif not slam_done and st_t < dur * 0.82 and player != null:
		var to_p: Vector3 = player.rig.global_position - rig.global_position
		to_p.y = 0.0
		rig.move_command = to_p.normalized() * P.getf("boss.charge_speed")
	else:
		rig.move_command = Vector3.ZERO
		if not slam_done and st_t >= dur * 0.82:
			_slam()
			slam_done = true
	if st_t >= dur:
		_enter("gap")


func _slam() -> void:
	rig.move_command = Vector3.ZERO
	rig.timing_key = "boss_slam"
	var w := 0.34
	var a := 0.16
	var r := 0.45
	rig.set_timings({"boss_slam": {"duration": w + a + r, "windup": w, "active": a, "recovery": r}})
	rig.force_attack("heavy")
	swung_serial += 1
	var radius := P.getf("boss.slam_radius")
	Snd.play_at("slam", rig.global_position, {"gain": 1.3, "prio": 3})
	if Fx != null:
		Fx.impact_ring(rig.global_position, radius, 1.8)
		Fx.shake(1.6)
	if player != null and player.alive:
		var d := Vector2(player.rig.global_position.x - rig.global_position.x,
			player.rig.global_position.z - rig.global_position.z).length()
		if d <= radius:
			player.hurt(P.getf("boss.slam_damage"), Vector3.UP, "被重击碾碎")


# ------------------------------------------------------------------ 激光
func _handle_laser(dt: float) -> void:
	laser_cd = maxf(0.0, laser_cd - dt)
	if P.gets("boss.laser_trigger") != "player_sees":
		return
	# 开场横幅（intro）期间不开火：切关/重开的第一帧相机可能还没对位，
	# 否则玩家一进第三关就被秒。横幅结束、真正进 fight 后照常「看见即死」。
	if level != null and is_instance_valid(level) and String(level.state) == "intro":
		laser_warn_left = 0.0
		laser_cd = maxf(laser_cd, 0.25)
		return
	if laser_warn_left > 0.0:
		laser_warn_left -= dt
		if laser_warn_left <= 0.0:
			_fire_laser()
		return
	if laser_cd > 0.0 or player == null or not player.alive or cam == null:
		return
	# 视线：它必须完全在你的相机画面里（零余量）
	var seen := Vision.is_visible(cam.camera, center(), mark_radius())
	if seen and P.getb("rules.vision_occlusion"):
		var ca := Vector2(cam.camera.global_position.x, cam.camera.global_position.z)
		var walls: Array = arena.get("walls", [])
		if Vision.los_blocked_2d(ca, Vector2(center().x, center().z), walls):
			seen = false
	if not seen:
		return
	var warn := P.getf("boss.laser_warn")
	laser_cd = P.getf("boss.laser_cooldown") + warn
	if warn > 0.05:
		laser_warn_left = warn
		if Fx != null:
			Fx.screen_flash(0.12, Color(1.0, 0.1, 0.1))
	else:
		_fire_laser()


func _fire_laser() -> void:
	if player == null or not player.alive:
		return
	var from: Vector3 = rig.global_position + Vector3(0, 3.6 * scale_factor, 0)
	var to: Vector3 = player.rig.global_position + Vector3(0, 2.2, 0)
	Snd.play_at("laser", from, {"gain": 1.3, "prio": 4})
	if Fx != null:
		Fx.beam(from, to, P.getf("boss.laser_width"), Color(1.0, 0.06, 0.12), 0.45)
		Fx.screen_flash(0.85, Color(0.9, 0.05, 0.05))
		Fx.shake(2.0)
	player.hurt(P.getf("boss.laser_damage"), (to - from).normalized(), "被激光蒸发")
	laser_warn_left = 0.0


func blocks_when_seen() -> bool:
	return false
