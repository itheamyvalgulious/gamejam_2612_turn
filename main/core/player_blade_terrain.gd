extends "res://core/blade_terrain.gd"
## 玩家的刀可自由穿入地形（不对刀施加任何力/弹回/卡姿），
## 仅通过纯解析几何检测刀身与地形的交汇，在接触面留下灼烧痕迹与火花。

const BladeScorch = preload("res://core/blade_scorch.gd")

var _geometry = null
var _has_prev := false
var _prev_base := Vector3.ZERO
var _prev_tip := Vector3.ZERO
var _prev_mid := Vector3.ZERO
var _last_scorch_pos := Vector3(INF, INF, INF)
var _last_scorch_n := Vector3.ZERO
var _last_spark_ms := 0
var _last_sound_ms := 0
var _scorch: Node3D = null


func reset() -> void:
	super.reset()
	_has_prev = false
	_last_scorch_pos = Vector3(INF, INF, INF)
	_last_scorch_n = Vector3.ZERO
	if _scorch != null and is_instance_valid(_scorch):
		_scorch.call("clear")


func begin_player_step(_rig) -> void:
	pass


func _ensure_scorch(rig) -> Node3D:
	if _scorch != null and is_instance_valid(_scorch):
		return _scorch
	var scene: Node = rig.get_tree().current_scene if rig != null and rig.get_tree() != null else null
	if scene == null:
		return null
	var existing: Node = scene.get_node_or_null("BladeScorch")
	if existing != null and existing is Node3D:
		_scorch = existing as Node3D
		return _scorch
	var node := BladeScorch.new()
	node.name = "BladeScorch"
	scene.add_child(node)
	_scorch = node
	return _scorch


func advance_player(rig, dt: float, _serial: int, sound: Node, fx: Node,
		geometry = null) -> void:
	if geometry != null:
		_geometry = geometry
	var authored: Transform3D = rig.weapon_spin.global_transform
	rig.weapon_xf = authored
	rig.update_terrain_trail(dt, false)
	impact.clear()
	var span: Vector2 = rig.blade_span()
	var base: Vector3 = authored * Vector3(0.0, span.x, 0.0)
	var tip: Vector3 = authored * Vector3(0.0, span.y, 0.0)
	var mid: Vector3 = (base + tip) * 0.5
	if _geometry != null:
		var hit: Dictionary = _geometry.raycast(base, tip)
		var seg_move := tip.distance_to(_prev_tip) if _has_prev else 0.0
		if hit.is_empty() and _has_prev and seg_move > 0.04:
			hit = _geometry.raycast(_prev_tip, tip)
			if hit.is_empty():
				hit = _geometry.raycast(_prev_mid, mid)
		if not hit.is_empty():
			var point: Vector3 = hit["point"]
			var normal: Vector3 = hit["normal"]
			var tang: Vector3 = (tip - _prev_tip).slide(normal) if _has_prev else (tip - base).slide(normal)
			if tang.length_squared() < 1e-4:
				tang = (tip - base).slide(normal)
			if point.distance_squared_to(_last_scorch_pos) >= 0.15 * 0.15 or normal.dot(_last_scorch_n) < 0.85:
				var scorch := _ensure_scorch(rig)
				if scorch != null:
					scorch.call("add_mark", point, normal, tang, clampf(seg_move * 1.4, 0.30, 0.75), 0.14)
				_last_scorch_pos = point
				_last_scorch_n = normal
			var now_ms := Time.get_ticks_msec()
			if fx != null and now_ms - _last_spark_ms >= 60:
				_last_spark_ms = now_ms
				fx.spark(point, normal, 0.42)
			if sound != null and now_ms - _last_sound_ms >= 180:
				_last_sound_ms = now_ms
				sound.play_at("clang", point, {"gain": 0.28})
	_prev_base = base
	_prev_tip = tip
	_prev_mid = mid
	_has_prev = true


func allows_hit(_rig, _contact: Dictionary) -> bool:
	return true
