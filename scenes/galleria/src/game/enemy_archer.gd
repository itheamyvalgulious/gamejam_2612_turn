extends EnemyUnit
class_name EnemyArcher
## 远程怪：没有刀（模型里删掉了），保持距离、拉弓射箭。
##
## 关键机制（用户定的）：
##   · 你弹反成功的箭会原路飞回去打它；
##   · 但如果你在弹反那一瞬间**正对着它**（它在你的相机画面里），它会立刻补射
##     一支拦截箭，把你弹回的箭在空中打掉 —— 两支箭相撞后失去力量乱飞，打不到它。
##   · 所以正确打法是：用画面外的视野盲区弹反。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

var fire_cd := 0.0
var draw_t := 0.0
var strafe_dir := 1.0


func setup_archer(p_palette: Dictionary) -> void:
	setup("archer", p_palette, {"hp": P.getf("archer.hp"), "damage": P.getf("archer.arrow_damage"),
		"weapon": false, "scale": 1.0})
	fire_cd = randf_range(0.6, 1.6)


func can_counter() -> bool:
	return P.getb("archer.parry_counter")


func fire_origin() -> Vector3:
	var fwd: Vector3 = -rig.global_transform.basis.z
	return rig.global_position + Vector3(0, 3.1, 0) + fwd * 0.7


func think(dt: float) -> void:
	fire_cd = maxf(0.0, fire_cd - dt)
	var dist := dist_to_player()
	face_player(1.3)

	# ---------------- 拉弓
	if draw_t > 0.0:
		draw_t -= dt
		rig.move_command = Vector3.ZERO
		rig.guard = clampf(1.0 - draw_t / maxf(P.getf("archer.telegraph"), 0.01), 0.25, 1.0)
		if draw_t <= 0.0:
			rig.guard = 0.0
			_fire()
			fire_cd = P.getf("archer.fire_interval")
		return
	rig.guard = 0.0

	# ---------------- 走位：保持射程
	var keep := P.getf("archer.keep_dist")
	var to_p: Vector3 = player.rig.global_position - rig.global_position
	to_p.y = 0.0
	var flat: Vector3 = to_p.normalized()
	var side := Vector3(-flat.z, 0, flat.x) * strafe_dir
	if dist < keep * 0.72:
		rig.move_command = (-flat + side * 0.55).normalized() * P.getf("archer.speed")
	elif dist > keep * 1.35:
		rig.move_command = (flat + side * 0.25).normalized() * P.getf("archer.speed")
	else:
		rig.move_command = side * P.getf("archer.speed") * 0.55
	if randf() < dt * 0.4:
		strafe_dir = -strafe_dir

	# ---------------- 开火
	if fire_cd <= 0.0 and dist < P.getf("archer.aggro_range"):
		draw_t = maxf(0.05, P.getf("archer.telegraph"))


func _fire() -> void:
	if projectiles == null or player == null:
		return
	var from := fire_origin()
	var lead := P.getf("archer.aim_lead")
	var aim: Vector3 = player.rig.global_position + Vector3(0, 2.3, 0)
	var travel := from.distance_to(aim) / maxf(P.getf("archer.arrow_speed"), 1.0)
	aim += player.rig.move_command * travel * lead
	var dir: Vector3 = (aim - from).normalized()
	var it := projectiles.spawn_arrow(from, dir, P.getf("archer.arrow_speed"),
		P.getf("archer.arrow_damage"), "enemy", Color(0.75, 0.35, 1.0))
	it["source"] = self
	if Fx != null:
		Fx.spark(from, dir, 0.35)
