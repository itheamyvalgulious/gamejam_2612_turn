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
static func player_swing(player: PlayerUnit, enemies: Array, cam: GameCam, wall_segs: Array,
		replay, dt: float) -> Array:
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
		if rig.global_position.distance_squared_to(e.center()) > 9.0 * 9.0:
			continue
		var res: Dictionary = Hit.sweep_blade_parts(rig.weapon_prev_xf, rig.weapon_xf, rig.blade_proxy,
			e.hit_parts())
		if not bool(res.get("hit", false)) or not player.blade_terrain.allows_hit(rig, res):
			continue
		e.last_hit_serial = serial
		var point: Vector3 = res.get("point", rig.global_position)
		var normal: Vector3 = res.get("normal", Vector3.UP)
		# —— 视野格挡：只要它在你画面里，这一刀就 100% 被挡
		var seen: bool = cam != null and (e.is_in_view(cam.camera) if e.has_method("is_in_view")
			else Vision.is_visible(cam.camera, e.center(), e.mark_radius()))
		if seen and P.getb("rules.vision_occlusion") and cam != null:
			var ca := Vector2(cam.camera.global_position.x, cam.camera.global_position.z)
			var ec: Vector3 = e.center()
			if Vision.los_blocked_2d(ca, Vector2(ec.x, ec.z), wall_segs):
				seen = false
		if e.blocks_when_seen() and seen:
			if e.has_method("on_seen_block"):
				e.on_seen_block(rig.global_position)
			elif e.has_method("on_attack_blocked"):
				e.on_attack_blocked()
			events.append({"kind": "block", "pos": point, "normal": normal, "enemy": e, "damage": 0.0})
			continue
		var dmg: float = P.getf("attack.%s.damage" % player.last_attack)
		var knock: float = P.getf("attack.%s.knockback" % player.last_attack)
		var travel: Vector3 = res.get("travel", Vector3.ZERO)
		var entry := {}
		if e.has_method("hurt_by_blade"):
			if dmg >= e.hp:
				var lvl_ref: Variant = e.get("level")
				var use_death_field := lvl_ref is Node and (lvl_ref as Node).get_meta(&"death_field", null) != null
				if not use_death_field:
					entry = Hit.blade_entry(replay.blade_samples(rig, dt), res, rig.blade_proxy)
				if entry.is_empty():
					var cut := travel.normalized()
					var inward := -normal
					entry["force"] = inward if cut.dot(normal) >= 0.0 else cut.lerp(inward, 0.58).normalized()
				res.merge(entry, true)
			e.hurt_by_blade(dmg, normal, knock, travel, res)
		else:
			e.hurt(dmg, normal, knock)
		var event := {"kind": "kill" if not e.alive else "hit", "pos": point, "normal": normal,
			"enemy": e, "damage": dmg, "contact": res.get("blade_point", point),
			"contact_fraction": res.get("t", 1.0), "travel": travel}
		event.merge(entry, true)
		events.append(event)
	return events


## 敌人一次挥击对玩家的结算
##
## 先判「剑挡剑」：只要两把刀的真几何真的交在一起（且玩家在弹反窗口里），
## 这一刀就被架掉 —— 免伤，但人会被推开。否则才走命中判定。
static func enemy_swing(enemy, player: PlayerUnit, terrain_clear := Callable()) -> Dictionary:
	if enemy == null or not enemy.alive or not player.alive:
		return {"hit": false}
	if enemy.has_method("resolve_attack"):
		return enemy.resolve_attack(player)
	var rig = enemy.rig
	if rig == null or not rig.has_method("in_hit_window") or not rig.in_hit_window():
		return {"hit": false}
	var eid: int = enemy.get_instance_id()
	var serials = player.get("hurt_serials")
	if serials is Dictionary and int(serials.get(eid, -1)) == enemy.swung_serial:
		return {"hit": false}
	elif not (serials is Dictionary) and enemy.swung_serial == player.hurt_serial:
		return {"hit": false}
	if rig.global_position.distance_squared_to(player.rig.global_position) > 10.0 * 10.0:
		return {"hit": false}
	# 碰到刀即格挡：不要求先举起；格挡成功立刻消耗这一刀。
	if P.getb("parry.melee_block"):
		var _cl0 := Time.get_ticks_usec()
		var clash: Dictionary = Hit.blade_vs_blade_swept(
			player.rig.weapon_prev_xf, player.rig.weapon_xf, player.rig.blade_proxy,
			rig.weapon_prev_xf, rig.weapon_xf, rig.blade_proxy, 0.05,
			player.rig.blade_span(), rig.blade_span(), 3, 4, -1)
		if player.get("parry_stats") is Dictionary:
			player.parry_stats["ms_clash"] = maxf(
				float(player.parry_stats.get("ms_clash", 0.0)),
				(Time.get_ticks_usec() - _cl0) / 1000.0)
		if bool(clash.get("hit", false)) and _blade_path_is_clear(rig, clash, terrain_clear):
			if serials is Dictionary:
				serials[eid] = enemy.swung_serial
			player.hurt_serial = enemy.swung_serial
			var push: Vector3 = player.rig.global_position - rig.global_position
			push.y = 0.0
			if push.length_squared() < 0.01:
				push = -rig.global_transform.basis.z
			push = push.normalized()
			player.on_block(push, P.getf("parry.block_knockback"))
			if enemy.has_method("on_attack_parried"):
				enemy.on_attack_parried(clash.get("normal", Vector3.UP))
			return {"hit": false, "parried": true, "melee": true,
				"pos": clash.get("point", Vector3.ZERO),
				"normal": clash.get("normal", Vector3.UP),
				"push": push}
	# 受击判定走机体原件分段（骨盆/胸/头/肩/四肢），不再用单颗大胶囊：
	# 高过头顶的横斩不会蹭到空气判定，贴腿扫过来的刀也打得到。
	var res: Dictionary = Hit.sweep_blade_parts(rig.weapon_prev_xf, rig.weapon_xf, rig.blade_proxy,
			player.rig.hit_parts())
	if not bool(res.get("hit", false)) or not _blade_path_is_clear(rig, res, terrain_clear):
		return {"hit": false}
	if serials is Dictionary:
		serials[eid] = enemy.swung_serial
	player.hurt_serial = enemy.swung_serial
	var dmg: float = float(enemy.damage)
	player.hurt(dmg, res.get("normal", Vector3.UP))
	return {"hit": true, "pos": res.get("point", Vector3.ZERO),
		"normal": res.get("normal", Vector3.UP)}


static func _blade_path_is_clear(rig, contact: Dictionary, clear: Callable) -> bool:
	if not clear.is_valid():
		return true
	var at: float = contact.get("t", 1.0)
	var hilt: Vector3 = rig.weapon_prev_xf.origin.lerp(rig.weapon_xf.origin, at)
	return clear.call(hilt, contact.get("blade_point", contact["point"])) and clear.call(hilt, contact["point"])


## 飞行物这一帧从 prev 走到 pos，是否被刀身挡住（线段 vs 真实圆盘剖面）
static func blade_blocks(rig, prev: Vector3, pos: Vector3, radius: float) -> bool:
	if rig == null:
		return false
	if rig.get("weapon_prev_xf") is Transform3D and not rig.weapon_prev_xf.is_equal_approx(Transform3D.IDENTITY):
		var res: Dictionary = Hit.segment_vs_blade_swept(prev, pos, rig.weapon_prev_xf, rig.weapon_xf, rig.blade_proxy, radius)
		return bool(res.get("hit", false))
	var res: Dictionary = Hit.segment_vs_blade(prev, pos, rig.weapon_xf, rig.blade_proxy, radius)
	return bool(res.get("hit", false))


## 刀在「举刀姿态」下是否碰到某个点
static func blade_contacts_point(rig, p: Vector3, radius: float) -> bool:
	if rig == null:
		return false
	var res: Dictionary = Hit.blade_vs_sphere(rig.weapon_xf, rig.blade_proxy, p, radius)
	return bool(res.get("hit", false))
