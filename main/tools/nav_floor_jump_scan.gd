extends SceneTree
## 刀客导航「跳层」扫描（headless）：
##   在二楼平台边缘/护栏附近铺网格，对每个点跑 duelist_ground_move(小位移)，
##   找出「XZ 几乎没动、Y 却跳了 >1」的点——那是 depenetrate 把角色推出楼板
##   掉到一层（表现为同位置楼层闪现）。
##
## 用法：godot --headless --path main -s tools/nav_floor_jump_scan.gd

const Catalog = preload("res://core/level_catalog.gd")


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
	var jumps := 0
	var cases := 0
	var samples := 0
	# 二楼平台：x∈[-14,14] z∈[17,29]（主台）、x∈[14,32] z∈[18,29]（侧台）
	var z := 16.4
	while z <= 29.2:
		var x := -15.0
		while x <= 33.0:
			x += 0.4
			samples += 1
			var p := Vector3(x, 8.0, z)
			# 只在楼板附近（支撑高度接近 8）测：站在台上的人
			var sup: float = nav.support_at(p, 8.6)
			if sup < 7.5:
				continue
			var q: Vector3 = nav.move_slide(p, p + Vector3(0.6, 0, 0.35), 1.75, 0.45, 0.45,
				{"radius": 1.18, "bottom": 1.10, "top": 4.53})
			var dy := q.y - p.y
			var dxz := Vector2(q.x - p.x, q.z - p.z).length()
			if absf(dy) > 1.0 and dxz < 6.0:
				jumps += 1
				if jumps <= 25:
					print("[scan] JUMP p=(%.2f, %.2f, %.2f) sup=%.2f -> q=(%.2f, %.2f, %.2f) dy=%.2f dxz=%.2f" % [
						p.x, p.y, p.z, sup, q.x, q.y, q.z, dy, dxz])
			cases += 1
		z += 0.4
	print("[scan] samples=%d standable=%d jumps=%d" % [samples, cases, jumps])
	quit()
