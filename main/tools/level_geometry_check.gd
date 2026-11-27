extends SceneTree
## LevelGeometry 离线校验：合成盒/矮墙 + 真实 arena 的刀-地形扫掠（无头可跑）。
##
## 用法：
##   python3 main/tools/prepare_game.py
##   godot --headless --path main -s res://tools/level_geometry_check.gd
##
## 覆盖：
##   * segment_clear / raycast / point_clear 穿墙、越矮墙、过柱；
##   * sweep_blade：刀扫进墙面停在表面前、法线朝外；矮墙上方不误判；
##     绕固定柄转 90° 的弧扫也能接住薄墙；
##   * BladeTerrain.advance 端到端（胶囊回退路径）触发 impact/recovery；
##   * 真 arena（窄巷边界墙 / 中庭踏面与高台 / 实验舱中央罐）。

const LevelGeometry = preload("res://core/level_geometry.gd")
const BladeTerrain = preload("res://core/blade_terrain.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[geo-check] synthetic")
	_synthetic()
	print("[geo-check] real arenas")
	_real_arenas()
	if _failures == 0:
		print("[geo-check] ALL PASS")
	else:
		print("[geo-check] %d FAILURE(S)" % _failures)
	quit(1 if _failures else 0)


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _close(a: float, b: float, tol := 0.05) -> bool:
	return absf(a - b) <= tol


func _synthetic() -> void:
	var arena := {
		"floor_y": 0.0,
		"solids": [AABB(Vector3(-30, -0.6, -30), Vector3(60, 0.6, 60))],
		"walls": [
			{"a": Vector2(-8, -10), "b": Vector2(-8, 10), "h": 12.0, "n": Vector2(1, 0)},
			{"a": Vector2(0, -10), "b": Vector2(0, 10), "h": 1.0, "n": Vector2(-1, 0)},
			{"a": Vector2(1.5, -4), "b": Vector2(1.5, -2), "h": 8.0, "n": Vector2(-1, 0)},
		],
		"cover": [{"c": Vector3(6, 0, 0), "r": 0.8 + 1.2, "h": 2.0}],
	}
	var geo = LevelGeometry.build(arena)

	# --- 线段净空 ---
	_expect(not geo.segment_clear(Vector3(-12, 1.5, 0), Vector3(-4, 1.5, 0)),
		"segment through full wall blocked")
	_expect(geo.segment_clear(Vector3(-12, 1.5, 0), Vector3(-12, 1.5, 5)),
		"segment parallel to wall clear")
	_expect(geo.segment_clear(Vector3(-3, 2.0, 0), Vector3(3, 2.0, 0)),
		"segment above low wall (h=1.0) clear")
	_expect(not geo.segment_clear(Vector3(-3, 0.5, 0), Vector3(3, 0.5, 0)),
		"segment through low wall blocked")
	_expect(not geo.segment_clear(Vector3(4, 1.0, 0), Vector3(8, 1.0, 0)),
		"segment through cover pillar blocked")
	_expect(geo.segment_clear(Vector3(4, 2.5, 0), Vector3(8, 2.5, 0)),
		"segment above cover pillar clear")

	# --- 点净空 ---
	_expect(not geo.point_clear(Vector3(-8, 5, 0)), "point inside wall rejected")
	_expect(geo.point_clear(Vector3(0, 1.5, 0)), "point above low wall clear")
	_expect(not geo.point_clear(Vector3(0, 0.4, 0)), "point inside low wall rejected")
	_expect(not geo.point_clear(Vector3(6, 1.0, 0)), "point inside cover rejected")

	# --- 射线（从场地内向外打内侧面：x=-8 处，法线 +x 指向场内）---
	var hit: Dictionary = geo.raycast(Vector3(-6, 1.5, 0), Vector3(-12, 1.5, 0))
	_expect(not hit.is_empty(), "raycast hits wall")
	if not hit.is_empty():
		print("    raycast -> ", hit)
		_expect(_close((hit["point"] as Vector3).x, -8.0, 0.10), "raycast point on wall face")
		_expect(_close((hit["normal"] as Vector3).x, 1.0, 0.05), "raycast normal faces back")
	_expect(geo.raycast(Vector3(-12, 1.5, 0), Vector3(-12, 1.5, 5)).is_empty(),
		"raycast parallel misses")

	# --- 平移扫掠：竖刀从场内推向高墙内侧面（x=-8 面，法线 +x） ---
	var pieces := [{"v": BladeTerrain._capsule_piece(Vector2(0.2, 1.4), Vector3.ONE)}]
	var radius := BladeTerrain.CAPSULE_RADIUS
	var prev := Transform3D(Basis.IDENTITY, Vector3(-4, 1.5, 0))
	var cur := Transform3D(Basis.IDENTITY, Vector3(-11, 1.5, 0))
	var res: Dictionary = geo.sweep_blade(prev, cur, pieces, radius, 1.4, cur.origin - prev.origin)
	_expect(res.has("point"), "sweep into tall wall stops")
	if res.has("point"):
		var pose: Transform3D = res["pose"]
		_expect(pose.origin.x > -8.1, "pose stopped before wall face")
		_expect(pose.origin.x < -7.4, "pose not over-rejected")
		_expect(_close((res["normal"] as Vector3).x, 1.0, 0.15),
			"contact normal faces blade side")
		_expect(geo.contact_at(LevelGeometry._world_pieces(pose, pieces), radius).is_empty()
			or geo.contact_at(LevelGeometry._world_pieces(pose, pieces), radius)["gap"] > -0.05,
			"rest pose nearly clear of wall")

	# --- 矮墙上方掠过：不应误判 ---
	prev = Transform3D(Basis.IDENTITY, Vector3(-3, 1.5, 0))
	cur = Transform3D(Basis.IDENTITY, Vector3(3, 1.5, 0))
	res = geo.sweep_blade(prev, cur, pieces, radius, 1.4, cur.origin - prev.origin)
	_expect(not res.has("point"), "sweep above low wall passes")

	# --- 矮墙体内：停住 ---
	prev = Transform3D(Basis.IDENTITY, Vector3(-3, 0.45, 0))
	cur = Transform3D(Basis.IDENTITY, Vector3(3, 0.45, 0))
	res = geo.sweep_blade(prev, cur, pieces, radius, 1.4, cur.origin - prev.origin)
	_expect(res.has("point"), "sweep into low wall body stops")

	# --- 绕柄旋转扫掠：刀尖弧线接住薄墙（x=1.5, z∈[-4,-2]，h=8） ---
	var long_pieces := [{"v": BladeTerrain._capsule_piece(Vector2(0.0, 2.2), Vector3.ONE)}]
	prev = Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -3))
	cur = Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(0, 1.5, -3))
	res = geo.sweep_blade(prev, cur, long_pieces, radius, 2.2)
	_expect(res.has("point"), "rotating sweep catches thin wall")
	if res.has("point"):
		_expect(_close((res["point"] as Vector3).x, 1.5, 0.15),
			"rotating contact lands on wall face")

	# --- cover 圆柱：推刀停在柱面 ---
	prev = Transform3D(Basis.IDENTITY, Vector3(3.5, 1.0, 0))
	cur = Transform3D(Basis.IDENTITY, Vector3(8.0, 1.0, 0))
	res = geo.sweep_blade(prev, cur, pieces, radius, 1.4, cur.origin - prev.origin)
	_expect(res.has("point"), "sweep into cover pillar stops")
	if res.has("point"):
		_expect(_close((res["point"] as Vector3).x, 6.0 - 0.86, 0.35),
			"cover contact near physical radius")

	# --- advance 端到端（胶囊回退）：柄从 -7.5 推向 -9.5，刃体跨 x=-8 墙 ---
	var bt: RefCounted = BladeTerrain.new()
	var authored := Transform3D(Basis.IDENTITY, Vector3(-7.5, 1.5, 0))
	bt.advance(geo, authored, Vector2(0.2, 1.4), Vector3(-7.0, 1.2, 0), 0.016, -1)
	var pushed := Transform3D(Basis.IDENTITY, Vector3(-9.5, 1.5, 0))
	var pose: Transform3D = bt.advance(geo, pushed, Vector2(0.2, 1.4), Vector3(-7.0, 1.2, 0), 0.016, 3)
	_expect(not bt.impact.is_empty(), "advance produces wall impact")
	_expect(bt.recovering, "advance enters recovery")
	_expect(pose.origin.x > -8.1, "advance clamps hilt before wall")
	if not bt.impact.is_empty():
		_expect(_close((bt.impact["normal"] as Vector3).x, 1.0, 0.2),
			"advance impact normal outward")


func _safe_build(script, args: Array) -> Dictionary:
	if script == null or not script is GDScript:
		return {}
	var arena = script.callv("build", args)
	return arena if arena is Dictionary else {}


func _real_arenas() -> void:
	# 窄巷：边界墙挡线段、横推停墙。
	var arena: Dictionary = _safe_build(
		load("res://runtime/levels/act/arena/arena.gd"), ["alley", Vector3.ZERO])
	if not arena.is_empty():
		var geo = LevelGeometry.build(arena)
		var st: Dictionary = geo.stats()
		print("  alley obstacles=%d walls=%d cover=%d" % [
			st["obstacles"], st["walls"], st["cover"]])
		_expect(st["walls"] > 0, "alley walls imported")
		_expect(not geo.segment_clear(Vector3(0, 1.5, 0), Vector3(-25, 1.5, 0)),
			"alley west boundary blocks segment")
		_expect(geo.segment_clear(Vector3(0, 1.5, 0), Vector3(0, 1.5, 10)),
			"alley interior segment clear")
		var bt: RefCounted = BladeTerrain.new()
		bt.advance(geo, Transform3D(Basis.IDENTITY, Vector3(-17, 1.5, 0)),
			Vector2(0.2, 1.4), Vector3(-16, 1.2, 0), 0.016, -1)
		var pose: Transform3D = bt.advance(geo, Transform3D(Basis.IDENTITY, Vector3(-22, 1.5, 0)),
			Vector2(0.2, 1.4), Vector3(-16, 1.2, 0), 0.016, 5)
		_expect(not bt.impact.is_empty() or bt.recovering or pose.origin.x > -22.0,
			"alley blade sweep stops at wall")
		arena["node"].queue_free()
	else:
		print("  skip: act arena script missing (run prepare_game.py)")

	# 中庭（高低差）：高台甲板与踏面都是障碍。
	arena = _safe_build(load("res://runtime/levels/galleria/encounter/arena.gd"), [true])
	if not arena.is_empty():
		var geo = LevelGeometry.build(arena)
		var st: Dictionary = geo.stats()
		print("  galleria obstacles=%d solids=%d walls=%d" % [
			st["obstacles"], st["solids"], st["walls"]])
		_expect(st["solids"] > 20, "galleria solids imported")
		_expect(not geo.segment_clear(Vector3(0, 8.3, 23), Vector3(0, 0.5, 23)),
			"galleria deck blocks downward segment")
		_expect(geo.segment_clear(Vector3(0, 8.3, 23), Vector3(0, 8.9, 23)),
			"galleria above deck clear")
		_expect(not geo.point_clear(Vector3(29, 1.0, -6), 0.0),
			"galleria stair tread interior rejected")
		# 刀尖从上向下戳进踏面（Basis.RIGHT,PI 把 +Y 翻到 -Y）→ 停住。
		var bt: RefCounted = BladeTerrain.new()
		bt.advance(geo, Transform3D(Basis.IDENTITY, Vector3(29, 4.6, -2)),
			Vector2(0.2, 2.6), Vector3(29, 4.6, -2), 0.016, -1)
		var pose: Transform3D = bt.advance(geo,
			Transform3D(Basis(Vector3.RIGHT, PI), Vector3(29, 4.6, -2)),
			Vector2(0.2, 2.6), Vector3(29, 4.6, -2), 0.016, 7)
		_expect(not bt.impact.is_empty() or bt.recovering,
			"galleria stair stab produces impact/recovery")
		arena["node"].queue_free()
	else:
		print("  skip: galleria arena script missing")

	# 实验舱：中央玻璃罐圆柱挡刀。
	arena = _safe_build(load("res://runtime/levels/panopticon/arena/panopticon_arena.gd"),
		[Vector3.ZERO])
	if not arena.is_empty():
		var geo = LevelGeometry.build(arena)
		var st: Dictionary = geo.stats()
		print("  panopticon obstacles=%d cover=%d" % [st["obstacles"], st["cover"]])
		_expect(not geo.segment_clear(Vector3(-12, 1.0, 0), Vector3(12, 1.0, 0)),
			"panopticon center tank blocks segment")
		var hit: Dictionary = geo.raycast(Vector3(-12, 1.0, 0), Vector3(12, 1.0, 0))
		_expect(not hit.is_empty(), "panopticon raycast hits tank")
		if not hit.is_empty():
			_expect((hit["point"] as Vector3).x < -1.0,
				"panopticon tank surface before center")
		arena["node"].queue_free()
	else:
		print("  skip: panopticon arena script missing")
