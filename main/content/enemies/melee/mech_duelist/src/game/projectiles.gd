extends Node3D
class_name Projectiles
## 飞行物：箭矢 / 刀气。全部走真实体积碰撞。
##
## - 玩家在弹反判定区间内用刀碰到 → 原路返回（速度倍率可调）
## - 返回途中如果远程怪「正对着你」（= 它在你画面里）→ 它补射一支拦截箭；
##   拦截箭只追那把剑，必然在空中把它撞掉（两边一起报废），本身不能被弹反、也伤不到人
## - 两条飞行物也可以互撞
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

var items: Array = []
var _seq := 0
var _ctx: Dictionary = {}

## 同时存在的飞行物硬上限：任何连锁异常都不许把节点/材质 RID 吃光
const MAX_ITEMS := 192


func clear_all() -> void:
	for it in items:
		if is_instance_valid(it["node"]):
			it["node"].queue_free()
	items.clear()


func _add(node: Node3D, pos: Vector3, vel: Vector3, radius: float, damage: float,
		kind: String, owner_tag: String) -> Dictionary:
	if items.size() >= MAX_ITEMS:
		var oldest: Dictionary = items[0]
		items.remove_at(0)
		_kill(oldest)
	add_child(node)
	node.global_position = pos
	_seq += 1
	var it := {
		"id": _seq, "node": node, "pos": pos, "prev": pos, "vel": vel, "radius": radius,
		"damage": damage, "kind": kind, "owner": owner_tag, "life": 5.0, "alive": true,
		"spent": false, "speed0": vel.length(),
	}
	items.append(it)
	return it


func spawn_arrow(pos: Vector3, dir: Vector3, speed: float, damage: float,
		owner_tag := "enemy", color := Color(1.0, 0.35, 0.85)) -> Dictionary:
	var node := MeshInstance3D.new()
	node.mesh = Fx.arrow_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.3)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.4
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var it := _add(node, pos, dir.normalized() * speed, 0.16, damage, "arrow", owner_tag)
	it["snd"] = Snd.loop_on("arrow_whistle", node, {"gain": 0.85, "prio": 3})
	return it


func spawn_qi(pos: Vector3, dir: Vector3, speed: float, damage: float, radius: float) -> Dictionary:
	var node := MeshInstance3D.new()
	node.mesh = Fx.qi_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.18, 0.10, 0.95)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var it := _add(node, pos, dir.normalized() * speed, radius, damage, "qi", "enemy")
	it["snd"] = Snd.loop_on("qi_loop", node, {"gain": 0.9, "prio": 2})
	Snd.play_at("qi", pos, {"gain": 1.0})
	return it


## 远程怪补射的拦截箭：瞄准「弹回箭」的预测位置。
##
## 它只有一个使命：在空中撞掉弹回来的那把剑，两边一起报废。
## 所以一出生就是 `spent` —— 伤不到人、不能被弹反、也不会触发下一次补射；
## 之后每帧朝目标当前位置修正航向，保证必然撞上；目标没了就当场消失。
func spawn_interceptor(from: Vector3, target_it: Dictionary, speed: float) -> Dictionary:
	var tpos: Vector3 = target_it["pos"]
	var tvel: Vector3 = target_it["vel"]
	var d := tpos - from
	var tof := d.length() / maxf(speed, 1.0)
	var aim := tpos + tvel * tof * 0.85
	var dir: Vector3 = (aim - from).normalized()
	var it := spawn_arrow(from, dir, speed, 0.0, "enemy", Color(0.55, 0.85, 1.0))
	it["interceptor"] = true
	it["spent"] = true
	it["target"] = target_it
	return it


func step(dt: float, ctx: Dictionary) -> Array:
	var events: Array = []
	var player: PlayerUnit = ctx.get("player")
	var enemies: Array = ctx.get("enemies", [])
	var cam: GameCam = ctx.get("cam")
	var arena: Dictionary = ctx.get("arena", {})
	var wall_segs: Array = arena.get("walls", [])
	_ctx = ctx

	for it in items:
		if not bool(it["alive"]):
			continue
		# ---------------- 拦截箭：只干一件事 —— 撞掉弹反回来的那把剑
		if bool(it.get("interceptor", false)):
			var tgt = it.get("target")
			if tgt == null or not bool(tgt["alive"]) or bool(tgt["spent"]):
				_kill(it)        # 目标已经没了 → 拦截箭也失去意义，别飞向玩家
				continue
			var to_t: Vector3 = (tgt["pos"] as Vector3) - (it["pos"] as Vector3)
			var gap := to_t.length()
			if gap < maxf(float(it["radius"]) * 3.0, 0.9):
				_clash(it, tgt, {"normal": to_t.normalized(), "point": it["pos"]})
				events.append({"kind": "clash", "pos": it["pos"]})
				continue
			if gap > 0.0001:
				it["vel"] = to_t / gap * maxf(float(it["speed0"]), 1.0)
		var node: Node3D = it["node"]
		it["prev"] = it["pos"]
		var prev: Vector3 = it["pos"]
		var pos: Vector3 = prev + (it["vel"] as Vector3) * dt
		it["pos"] = pos
		it["life"] = float(it["life"]) - dt
		if float(it["life"]) <= 0.0:
			_kill(it)
			continue
		if is_instance_valid(node):
			node.global_position = pos
			var v: Vector3 = it["vel"]
			if v.length() > 0.05:
				if String(it["kind"]) == "qi":
					node.rotate_y(dt * 9.0)
				else:
					node.look_at(pos + v, Vector3.UP)

		# ---------------- 与玩家的刀相交 → 弹反
		# 刀的位置由弹反的「拦截规划」决定（player._plan_intercept 会把刀送到
		# 飞行物的必经之路上），所以这里只认真实刀身几何：刀真的在，才弹得回去。
		if String(it["owner"]) == "enemy" and not bool(it["spent"]) and player != null and player.alive:
			if player.is_guard_up() and Combat.blade_blocks(player.rig, prev, pos, float(it["radius"])):
				_reflect(it, player, events)
				continue

		# ---------------- 命中玩家
		if String(it["owner"]) == "enemy" and not bool(it["spent"]) and player != null and player.alive:
			var cap: Dictionary = player.capsule()
			var res: Dictionary = Hit.sweep_sphere(prev, pos, float(it["radius"]), cap["a"], cap["b"], cap["r"])
			if bool(res.get("hit", false)):
				player.hurt(float(it["damage"]), res.get("normal", Vector3.UP),
					"被箭射穿" if String(it["kind"]) == "arrow" else "被刀气切开")
				events.append({"kind": "player_hit", "pos": pos, "it": it})
				_kill(it)
				continue

		# ---------------- 弹回后命中敌人
		if String(it["owner"]) == "player" and not bool(it["spent"]):
			var hit_any := false
			for e in enemies:
				if e == null or not e.alive:
					continue
				var r2: Dictionary = Hit.sweep_sphere_parts(prev, pos, float(it["radius"]),
					e.hit_parts())
				if bool(r2.get("hit", false)):
					e.hurt(float(it["damage"]), r2.get("normal", Vector3.UP))
					events.append({"kind": "enemy_hit", "pos": pos, "it": it, "enemy": e})
					hit_any = true
					break
			if hit_any:
				_kill(it)
				continue

		# ---------------- 撞墙 / 落地
		if pos.y < 0.04 or _hits_wall(prev, pos, wall_segs):
			events.append({"kind": "wall", "pos": pos, "it": it})
			_kill(it)
			continue

	# ---------------- 飞行物互撞（弹回的箭 vs 拦截箭）
	_pairwise(events)

	# 清理
	var kept: Array = []
	for it in items:
		if bool(it["alive"]):
			kept.append(it)
	items = kept
	return events


func _pairwise(events: Array) -> void:
	for i in items.size():
		var a: Dictionary = items[i]
		if not bool(a["alive"]):
			continue
		for j in range(i + 1, items.size()):
			var b: Dictionary = items[j]
			if not bool(b["alive"]):
				continue
			if bool(a["spent"]) and bool(b["spent"]):
				continue
			var res: Dictionary = Hit.sphere_pair(a["prev"], a["pos"], float(a["radius"]) * 1.8,
				b["prev"], b["pos"], float(b["radius"]) * 1.8)
			if bool(res.get("hit", false)):
				_clash(a, b, res)
				events.append({"kind": "clash", "pos": res.get("point", a["pos"])})


## 双箭相撞：失去力量、乱飞、不再能造成伤害
func _clash(a: Dictionary, b: Dictionary, res: Dictionary) -> void:
	var n: Vector3 = res.get("normal", Vector3.RIGHT)
	for it in [a, b]:
		it["spent"] = true
		var v: Vector3 = it["vel"]
		var side := v.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		it["vel"] = (n * randf_range(2.0, 5.0) + side * randf_range(-4.0, 4.0)
			+ Vector3(randf_range(-2.0, 2.0), randf_range(1.0, 4.0), randf_range(-2.0, 2.0)))
		it["life"] = minf(float(it["life"]), 0.9)
		if Fx != null:
			Fx.spark(it["pos"], n, 0.7)


func _reflect(it: Dictionary, player: PlayerUnit, events: Array) -> void:
	var v: Vector3 = it["vel"]
	var mult := P.getf("parry.reflect_speed")
	it["vel"] = -v.normalized() * v.length() * mult
	it["owner"] = "player"
	it["life"] = maxf(float(it["life"]), 4.0)
	var node: Node3D = it["node"]
	if is_instance_valid(node) and node is MeshInstance3D:
		var mat: StandardMaterial3D = (node as MeshInstance3D).material_override
		if mat != null:
			mat.emission = Color(1.0, 0.75, 0.2)
			mat.albedo_color = Color(1.0, 0.6, 0.15, 1.0)
	events.append({"kind": "parry", "pos": it["pos"], "it": it})
	if Fx != null:
		Fx.clang(it["pos"], -v.normalized())
		Fx.screen_flash(0.10, Color(0.6, 0.95, 1.0))
	# 拦截箭自己不能被弹反，也不该再引发补射（否则就是「箭生箭」的死循环）
	if bool(it.get("interceptor", false)) or bool(it["spent"]):
		return
	# 远程怪补射拦截箭：只要弹反瞬间它在你画面里
	var ctx_archers: Array = _ctx.get("archers", [])
	var cam: GameCam = _ctx.get("cam")
	for a in ctx_archers:
		if a != null and a.alive and a.can_counter() and cam != null \
				and Vision.is_visible(cam.camera, a.center(), a.mark_radius()):
			var arrow := spawn_interceptor(a.fire_origin(), it, P.getf("archer.counter_speed"))
			events.append({"kind": "counter", "pos": a.fire_origin(), "it": arrow})
			break


func _hits_wall(a: Vector3, b: Vector3, segs: Array) -> bool:
	var pa := Vector2(a.x, a.z)
	var pb := Vector2(b.x, b.z)
	for w in segs:
		if Vision._segments_cross(pa, pb, w["a"], w["b"]):
			return true
	return false


func _kill(it: Dictionary) -> void:
	it["alive"] = false
	if it.has("snd"):
		Snd.stop(int(it["snd"]))
	if String(it["kind"]) == "arrow" and not bool(it["spent"]):
		Snd.play_at("arrow_hit", it["pos"], {"gain": 0.7})
	if is_instance_valid(it["node"]):
		it["node"].queue_free()
