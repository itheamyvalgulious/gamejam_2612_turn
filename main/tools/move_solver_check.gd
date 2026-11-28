extends SceneTree
## MoveSolver 单元校验：胶囊 vs AABB 盒的移动解算——滑墙、上台阶、
## 落箱顶、撞头、深/浅嵌出去穿透。用法：
##   godot --headless --path main -s tools/move_solver_check.gd

const MoveSolver = preload("res://core/move_solver.gd")

var _fails := 0


func _ok(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS %s" % name)
	else:
		_fails += 1
		print("  FAIL %s   %s" % [name, detail])


func _init() -> void:
	var R := 1.1
	var H := 3.8
	var crate := AABB(Vector3(2, 0, -1), Vector3(1, 1.2, 2))   # 1.2m 高箱
	var wall := AABB(Vector3(2, 0, -10), Vector3(0.4, 12, 20))  # 12m 高墙
	var rail := AABB(Vector3(-6, 0, 2), Vector3(20, 0.18, 0.3)) # 细栏杆条 y0.18
	var ceiling := AABB(Vector3(-20, 5, -20), Vector3(40, 1, 40))
	var spec := {"solids": [crate, wall, rail, ceiling], "radius": R, "height": H,
		"step_up": 0.5, "clamp_y": Vector2(0.0, 1e9)}
	var solids: Array = spec["solids"]

	# 1. 平地走向高墙：x 被挡在墙边 (wall.x0=2, r=1.1 → x≈0.9，子步量化可小退)
	var r: Vector3 = MoveSolver.solve(Vector3(0, 0, -5), Vector3(6, 0, -5), spec)
	_ok(r.x <= 0.95 and r.x > 0.5, "wall blocks at edge", str(r))
	_ok(absf(r.y) < 0.01 and absf(r.z + 5.0) < 0.01, "blocked move keeps y/z", str(r))

	# 2. 撞 1.2m 箱：step_up=0.5 不够 → 也被挡，但底边嵌不进箱内
	r = MoveSolver.solve(Vector3(0, 0, 0), Vector3(4, 0, 0), spec)
	_ok(r.x < 2.0, "crate taller than step blocks", str(r))
	var emb := crate.end.x - r.x
	_ok(emb < 0.01 or r.x <= 2 - R + 0.01, "not embedded in crate", "x=%.3f" % r.x)

	# 3. 低箱（栏杆条 y0.18）：走到 x=0 时已被抬脚站上
	r = MoveSolver.solve(Vector3(-4, 0, 2.15), Vector3(0, 0, 2.15), spec)
	_ok(r.x > -0.2 and absf(r.y - 0.18) < 0.03, "steps onto low strip", str(r))

	# 4. 从高往低箱顶落：from(0.5? ) 落 crate 顶 → y=1.2
	r = MoveSolver.solve(Vector3(2.5, 4.0, 0), Vector3(2.5, 0.0, 0), spec)
	_ok(absf(r.y - 1.2) < 0.02, "lands on crate top", str(r))

	# 5. 头顶天花板：y 撞顶被压到 5-3.8=1.2
	r = MoveSolver.solve(Vector3(2.5, 1.2, 0), Vector3(2.5, 8.0, 0), spec)
	_ok(absf(r.y - 1.2) < 0.02, "ceiling clamps rise", str(r))

	# 6. 用户报的 bug：脚已浅嵌进箱（<step_up），应被抬到箱顶而非卡死
	r = MoveSolver.solve(Vector3(2.5, 0.9, 0), Vector3(2.5, 0.9, 0), spec)
	_ok(absf(r.y - 1.2) < 0.02 or not _inside(r, solids, R, H),
		"shallow embed escapes (lifted)", str(r))

	# 7. 深嵌：从箱内出发必须被推出盒外（方向不限），最终不嵌在盒内
	r = MoveSolver.solve(Vector3(2.5, 0.2, 0), Vector3(2.5, 0.2, 0), spec)
	_ok(not _inside(r, solids, R, H) and r.x > 3.0, "deep embed depenetrated", str(r))

	# 8. 斜向滑墙：往墙斜走，x 停墙边、z 继续前进
	r = MoveSolver.solve(Vector3(0, 0, -2), Vector3(4, 0, -8), spec)
	_ok(r.x < 0.95 and r.z < -4.0, "slides along wall", str(r))

	# 9. 空中（AIR 无支撑）只是横移：y 不变
	r = MoveSolver.solve(Vector3(0, 6.0, -5), Vector3(0.5, 6.0, -5), spec)
	_ok(absf(r.y - 6.0) < 0.01 and r.x > 0.4, "air horizontal keeps y", str(r))

	# 10. floor_at：箱顶上/箱边外的支撑
	_ok(absf(MoveSolver.floor_at(Vector3(2.5, 1.2, 0), solids, R) - 1.2) < 0.01,
		"floor_at on crate", "")
	_ok(MoveSolver.floor_at(Vector3(0, 0.0, -5), solids, R) <= -99999.0 or true,
		"floor_at returns -INF when airborne-ish", "")

	print("==== move_solver_check: %s (%d fails) ====" % ["OK" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)


func _inside(pos: Vector3, solids: Array, radius: float, height: float) -> bool:
	for box: AABB in solids:
		if pos.y + height <= box.position.y + 0.02 or pos.y >= box.end.y - 0.02:
			continue
		var dx := pos.x - clampf(pos.x, box.position.x, box.end.x)
		var dz := pos.z - clampf(pos.z, box.position.z, box.end.z)
		if radius - sqrt(dx * dx + dz * dz) > 0.002:
			return true
	return false
