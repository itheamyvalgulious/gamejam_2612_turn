extends RefCounted
class_name Combat
## 伤害结算：刀用「真实网格体积」做扫掠判定 ——
##   玩家这一刀 vs 敌人按关节拆出的多个判定件（hit_parts：躯干/头/四肢）；
##   敌人这一刀 vs 玩家机体胶囊。
##
## 事件格式（返回给 main 播特效/抖屏/顿帧）：
##   {kind:"hit"|"block"|"kill", pos, normal, enemy, damage}
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。


## 玩家一次挥砍的结算。每次攻击对同一敌人只生效一次（用 swing_serial 去重）。
static func player_swing(player: PlayerUnit, enemies: Array, cam: GameCam, wall_segs: Array = []) -> Array:
	var events: Array = []
	var rig = player.rig
	if rig == null or not rig.in_hit_window():
		return events
	var serial: int = player.swing_serial
	for e in enemies:
		if e == null or not e.alive:
			continue
		if e.last_hit_serial == serial:
			continue
		var res: Dictionary = Hit.sweep_blade_parts(rig.weapon_prev_xf, rig.weapon_xf, rig.blade_discs,
			rig.weapon_scale, e.hit_parts())
		if not bool(res.get("hit", false)):
			continue
		e.last_hit_serial = serial
		var point: Vector3 = res.get("point", rig.global_position)
		var normal: Vector3 = res.get("normal", Vector3.UP)
		if cam != null and blocks_in_view(e, cam.camera, wall_segs):
			e.on_attack_blocked()
			events.append({"kind": "block", "pos": point, "normal": normal, "enemy": e, "damage": 0.0})
			continue
		var dmg: float = P.getf("attack.%s.damage" % player.last_attack)
		var knock: float = P.getf("attack.%s.knockback" % player.last_attack)
		var previous_hp: float = e.hp
		e.hurt(dmg, normal, knock)
		var dealt: float = previous_hp - e.hp
		if dmg > 0.0 and dealt <= 0.0:
			events.append({"kind": "block", "pos": point, "normal": normal, "enemy": e,
				"damage": 0.0, "armor": true})
		else:
			events.append({"kind": "kill" if not e.alive else "hit", "pos": point, "normal": normal,
				"enemy": e, "damage": dealt})
	return events


## 格挡与 HUD 共用同一帧的视野判定。
static func blocks_in_view(enemy: EnemyUnit, camera: Camera3D, wall_segs: Array) -> bool:
	if camera == null or not enemy.blocks_when_seen() or not enemy.is_in_view(camera):
		return false
	if P.getb("rules.vision_occlusion"):
		var eye := camera.global_position
		var target := enemy.center()
		return not Vision.los_blocked_2d(Vector2(eye.x, eye.z), Vector2(target.x, target.z), wall_segs)
	return true


## 敌人一次挥击对玩家的结算
##
## 先判「剑挡剑」：只要两把刀的真几何真的交在一起（且玩家在弹反窗口里），
## 这一刀就被架掉 —— 免伤，但人会被推开。否则才走命中判定。
static func enemy_swing(enemy, player: PlayerUnit) -> Dictionary:
	if enemy == null or not enemy.alive or not player.alive:
		return {"hit": false}
	var rig = enemy.rig
	if rig == null or not rig.in_hit_window():
		return {"hit": false}
	if enemy.swung_serial == player.hurt_serial:
		return {"hit": false}
	if P.getb("parry.melee_block") and player.is_guard_up():
		var clash: Dictionary = Hit.blade_vs_blade_swept(
			player.rig.weapon_prev_xf, player.rig.weapon_xf, player.rig.blade_discs,
			player.rig.weapon_scale, player.rig.blade_span(),
			rig.weapon_prev_xf, rig.weapon_xf, rig.blade_discs, rig.weapon_scale, rig.blade_span())
		if bool(clash.get("hit", false)):
			player.hurt_serial = enemy.swung_serial
			var push: Vector3 = player.rig.global_position - rig.global_position
			push.y = 0.0
			if push.length_squared() < 0.01:
				push = -rig.global_transform.basis.z
			push = push.normalized()
			player.on_block(push, P.getf("parry.block_knockback"))
			enemy.on_attack_parried(clash.get("normal", Vector3.UP))
			return {"hit": false, "parried": true, "melee": true,
				"pos": clash.get("point", Vector3.ZERO),
				"normal": clash.get("normal", Vector3.UP),
				"push": push}
	var cap: Dictionary = player.capsule()
	var res: Dictionary = Hit.sweep_blade(rig.weapon_prev_xf, rig.weapon_xf, rig.blade_discs,
		rig.weapon_scale, cap["a"], cap["b"], cap["r"])
	if not bool(res.get("hit", false)):
		return {"hit": false}
	player.hurt_serial = enemy.swung_serial
	var dmg: float = float(enemy.damage)
	player.hurt(dmg, res.get("normal", Vector3.UP))
	return {"hit": true, "pos": res.get("point", Vector3.ZERO),
		"normal": res.get("normal", Vector3.UP)}


## 飞行物这一帧从 prev 走到 pos，是否被刀身挡住（线段 vs 真实圆盘剖面）
static func blade_blocks(rig, prev: Vector3, pos: Vector3, radius: float) -> bool:
	if rig == null:
		return false
	var res: Dictionary = Hit.segment_vs_blade(prev, pos, rig.weapon_xf, rig.blade_discs,
		rig.weapon_scale, radius)
	return bool(res.get("hit", false))


## 刀在「举刀姿态」下是否碰到某个点
static func blade_contacts_point(rig, p: Vector3, radius: float) -> bool:
	if rig == null:
		return false
	var res: Dictionary = Hit.blade_vs_sphere(rig.weapon_xf, rig.blade_discs, rig.weapon_scale, p, radius)
	return bool(res.get("hit", false))
