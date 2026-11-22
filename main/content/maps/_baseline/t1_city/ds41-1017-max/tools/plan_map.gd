extends SceneTree

const SIZE := 1200

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var plan := CityPlan.new()
	plan.generate(1337)
	print("plan gen ms=", Time.get_ticks_msec() - t0, " blocks=", plan.blocks.size(), " blds=", plan.blds.size(), " lots=", plan.lot_count)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.10, 0.115))
	var sc := float(SIZE) / (CityPlan.HALF * 2.0)
	# canal as a continuous band
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var rp0 := PackedVector2Array()
	for v in plan.river_pts:
		rp0.append(Vector2(v.x, v.y))
	for i in rp0.size():
		var a := rp0[maxi(0, i - 1)]
		var b := rp0[mini(rp0.size() - 1, i + 1)]
		var t := (b - a).normalized()
		var nn := Vector2(-t.y, t.x) * plan.river_w * 0.5
		left.append(rp0[i] + nn)
		right.append(rp0[i] - nn)
	right.reverse()
	var wpoly := left + right
	_fill(img, wpoly, sc, Color(0.05, 0.13, 0.22))
	# land blocks
	var dc := {
		0: Color(0.34, 0.19, 0.28), 1: Color(0.38, 0.26, 0.17),
		2: Color(0.18, 0.30, 0.20), 3: Color(0.20, 0.24, 0.38),
		4: Color(0.31, 0.29, 0.15), 5: Color(0.13, 0.29, 0.34),
		6: Color(0.26, 0.26, 0.27), 7: Color(0.10, 0.24, 0.13),
	}
	for b in plan.blocks:
		if b.water:
			_fill(img, b.poly, sc, Color(0.05, 0.16, 0.26))
			continue
		var c: Color = dc.get(b.district, Color(0.3, 0.3, 0.3))
		_fill(img, b.poly, sc, c)
	# buildings
	for b in plan.blds:
		var t := clampf(b.h / 260.0, 0.0, 1.0)
		var col := Color(0.10, 0.10, 0.13).lerp(Color(1.0, 0.72, 0.35), t)
		if b.kind == CityPlan.K_WAREHOUSE or b.kind == CityPlan.K_FACTORY:
			col = Color(0.16, 0.17, 0.15).lerp(Color(0.45, 0.42, 0.3), t)
		_fill(img, b.poly, sc, col)
	# roads as thin lines are already gaps; draw highway + monorail
	_draw_path(img, plan.diagonal, sc, Color(0.22, 0.22, 0.24), 3)
	# river centerline for reference
	var rp := PackedVector2Array()
	for v in plan.river_pts:
		rp.append(Vector2(v.x, v.y))
	_draw_path(img, rp, sc, Color(0.25, 0.45, 0.6), 1)
	img.save_png("res://docs/_plan.png")
	print("map saved ", Time.get_ticks_msec(), "ms")
	print("kinds=", plan.count_by_kind())
	# district block counts
	var dcount := {}
	for b in plan.blocks:
		dcount[b.district] = dcount.get(b.district, 0) + 1
	print("blocks by district=", dcount)
	quit()

func _fill(img: Image, poly: PackedVector2Array, sc: float, col: Color) -> void:
	var n := poly.size()
	if n < 3:
		return
	var miny := 1e9
	var maxy := -1e9
	for v in poly:
		miny = minf(miny, v.y)
		maxy = maxf(maxy, v.y)
	var y0 := int((miny + CityPlan.HALF) * sc)
	var y1 := int((maxy + CityPlan.HALF) * sc)
	for py in range(maxi(0, y0), mini(SIZE, y1 + 1)):
		var wy := (py + 0.5) / sc - CityPlan.HALF
		var xs := []
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			if (a.y <= wy and b.y > wy) or (b.y <= wy and a.y > wy):
				var t := (wy - a.y) / (b.y - a.y)
				xs.append(a.x + (b.x - a.x) * t)
		if xs.size() < 2:
			continue
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var xa := int((xs[k] + CityPlan.HALF) * sc)
			var xb := int((xs[k + 1] + CityPlan.HALF) * sc)
			img.fill_rect(Rect2i(xa, py, maxi(1, xb - xa), 1), col)

func _draw_path(img: Image, path: PackedVector2Array, sc: float, col: Color, w: int) -> void:
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var steps := int(a.distance_to(b) * sc)
		for k in steps + 1:
			var t := float(k) / maxf(1.0, steps)
			var p := a.lerp(b, t)
			var ix := int((p.x + CityPlan.HALF) * sc)
			var iy := int((p.y + CityPlan.HALF) * sc)
			img.fill_rect(Rect2i(ix, iy, w, w), col)