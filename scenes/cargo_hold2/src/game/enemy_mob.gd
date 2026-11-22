extends EnemyUnit
class_name EnemyMob
## 小怪：走向你 → 近了就挥刀。
##
## 核心机制（用户定的）：**它在你相机画面里时，你的攻击 100% 被它格挡**。
## 跟它的朝向、跟它是否看得见你都没关系——惩罚的是「你看得见它」这件事。
## 所以想杀掉它只能：侧斩 / 回身斩 / 回旋斩，用屏幕外的刀弧打。

var attack_cd := 0.0


func setup_mob(p_palette: Dictionary) -> void:
	var sc := P.getf("mob.damage_scale")
	setup("mob", p_palette, {"hp": P.getf("mob.hp"), "damage": P.getf("mob.damage"), "scale": sc})


func blocks_when_seen() -> bool:
	return P.getb("mob.block_when_visible")


func think(dt: float) -> void:
	attack_cd = maxf(0.0, attack_cd - dt)
	var dist := dist_to_player()
	face_player()
	if dist > P.getf("mob.aggro_range"):
		rig.move_command = Vector3.ZERO
		return
	if rig.is_attacking:
		rig.move_command = Vector3.ZERO
		return

	var w := P.getf("mob.windup")
	var a := P.getf("mob.active")
	var r := P.getf("mob.recovery")
	rig.set_timings({"mob": {"duration": w + a + r, "windup": w, "active": a, "recovery": r}})

	var reach := P.getf("mob.attack_range")
	var stop_at := P.getf("mob.chase_stop")
	if dist > reach:
		var to_p: Vector3 = player.rig.global_position - rig.global_position
		to_p.y = 0.0
		rig.move_command = to_p.normalized() * P.getf("mob.speed")
		if dist < stop_at + 1.5:
			rig.move_command *= 0.45
	elif attack_cd <= 0.0:
		rig.move_command = Vector3.ZERO
		rig.timing_key = "mob"
		swung_serial += 1
		rig.force_attack("light")
		attack_cd = w + a + r + 0.30
	else:
		rig.move_command = Vector3.ZERO
