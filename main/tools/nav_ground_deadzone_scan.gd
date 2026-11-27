extends SceneTree
## 地面移动死点扫描（headless）：
##   高低差关一楼铺网格，每个可站点朝「楼梯口」方向走 1.0u，统计原地不动的点
##   （move_slide 无法前进 = 卡住的候选位置）。
##
## 用法：godot --headless --path main -s tools/nav_ground_deadzone_scan.gd

const Catalog = preload("res://core/level_catalog.gd")
const STAIR_MOUTH := Vector3(29.0, 0.0, -10.0)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var session: Node = root.get_node("TurnSession")
	var idx := Catalog.index_for_id("galleria_height_test")
	session.open_level(idx)
	while session.active_level_index() != idx or current_scene == null or current_scene.get("level") == null:
		await process_frame
	var level: Node = current_scene.get("level")
	var nav = level.get("nav")
	while str(level.get("state")) != "fight":
		await process_frame
	var upper := {"radius": 1.18, "bottom": 1.10, "top": 4.53}
	var tested := 0
	var blocked := 0
	var worst: Array = []
	var z := -30.0
	while z <= 30.0:
		var x := -34.0
		while x <= 34.0:
			x += 1.0
			var p := Vector3(x, 0.0, z)
			var sup: float = nav.support_at(p, 0.5)
			if absf(sup) > 0.35:
				continue
			p.y = sup
			var dir := STAIR_MOUTH - p
			dir.y = 0.0
			if dir.length() < 1.5:
				continue
			dir = dir.normalized()
			tested += 1
			var q: Vector3 = nav.move_slide(p, p + dir * 1.0, 1.75, 0.45, 0.45, upper)
			var prog := Vector2(q.x - p.x, q.z - p.z).length()
			if prog < 0.25:
				blocked += 1
				if worst.size() < 25:
					worst.append("(%.1f,%.1f) prog=%.2f->%s" % [x, z, prog, q])
		z += 1.0
	print("[dz] tested=%d no_progress=%d" % [tested, blocked])
	for w in worst:
		print("[dz]   ", w)
	quit()
