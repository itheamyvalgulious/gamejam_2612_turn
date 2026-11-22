## Procedural building interiors: floors, partitions, furniture, fixtures.
## Generated on demand for floors near the camera (and all floors in x-ray mode).
class_name Interior
extends RefCounted

const T := 0.12   # partition thickness

static func build(b: CityPlan.Bld, mb: MB, floor_lo: int, floor_hi: int) -> int:
	var n := 0
	var fh := Builder.floor_h(b)
	for f in range(floor_lo, floor_hi + 1):
		if f < 0 or f >= b.floors:
			continue
		var y := 0.16
		if f == 0:
			# ground floor height matches the shopfront band
			_build_floor(b, mb, 0, y, y + 5.0, fh)
		else:
			var gy := 5.0 + (f - 1) * fh + 0.16
			if gy > b.h - 1.0:
				continue
			_build_floor(b, mb, f, gy, minf(gy + fh, b.h), fh)
		n += 1
	return n

static func _build_floor(b: CityPlan.Bld, mb: MB, f: int, y0: float, y1: float, fh: float) -> void:
	var inner := Poly.inset(b.poly, 0.42)
	if inner.size() < 3:
		inner = Poly.inset(b.poly, 0.1)
	if inner.size() < 3:
		return
	var bb := Poly.bbox(Poly.inset(b.poly, 1.4))
	var w := bb.size.x
	var d := bb.size.y
	if w < 3.0 or d < 3.0:
		return
	var r := H.rng(b.id * 131 + f * 977, 41)
	var c := bb.get_center()
	# floor finish
	var floor_mat := M.CONCRETE
	var fcol := Mats.c("8f8b82")
	match b.kind:
		CityPlan.K_APARTMENT:
			floor_mat = M.WOOD
			fcol = Mats.c("6a4c33")
		CityPlan.K_OFFICE, CityPlan.K_TOWER, CityPlan.K_HOTEL:
			floor_mat = M.FABRIC
			fcol = Mats.c("3a3d44")
		CityPlan.K_SHOP, CityPlan.K_MALL:
			floor_mat = M.TILE
			fcol = Mats.c("c8c2b4")
		CityPlan.K_SCHOOL:
			floor_mat = M.TILE
			fcol = Mats.c("a8a496")
		CityPlan.K_WAREHOUSE, CityPlan.K_FACTORY:
			floor_mat = M.CONCRETE
			fcol = Mats.c("6a6860")
	mb.setm(floor_mat, fcol, b.sd)
	mb.prism(Poly.inset(inner, 0.02), y0, y0 + 0.22, true, true)
	# ceiling finish (underside of the slab above)
	mb.setm(M.CONCRETE, Mats.c("b6b0a4"), b.sd)
	mb.prism(Poly.inset(inner, 0.04), y0 + 0.22, y0 + 0.24, true, false)
	# structural fascia along the perimeter (reads as a thick slab edge in cutaway)
	mb.setm(M.CONCRETE, Mats.c("8a867c"), b.sd)
	var fs := Poly.inset(inner, 0.05)
	if fs.size() >= 3:
		mb.prism(fs, y0 + 0.22, y0 + 0.55, false, false)
	# interior perimeter skin (keeps the room readable, leaves the window band open)
	if y1 - y0 > 2.4:
		_interior_skin(mb, inner, y0, y1, b)
	# ceiling only on the top-most generated floor (upper slab otherwise)
	if f >= b.floors - 1:
		mb.setm(M.CONCRETE, Mats.c("b8b4ac"), b.sd)
		mb.prism(inner, y1 - 0.1, y1 - 0.02, true, false)
	# plan
	var ground := f == 0
	if ground and (b.kind == CityPlan.K_SHOP or b.kind == CityPlan.K_MALL or b.kind == CityPlan.K_OFFICE
			or b.kind == CityPlan.K_TOWER or b.kind == CityPlan.K_HOTEL):
		_lobby(b, mb, bb, y0, y1, r)
	elif b.kind == CityPlan.K_APARTMENT:
		_apartment_floor(b, mb, bb, y0, y1, r, f)
	elif b.kind == CityPlan.K_HOTEL:
		_hotel_floor(b, mb, bb, y0, y1, r)
	elif b.kind == CityPlan.K_SHOP or b.kind == CityPlan.K_MALL:
		_retail_floor(b, mb, bb, y0, y1, r)
	elif b.kind == CityPlan.K_WAREHOUSE or b.kind == CityPlan.K_FACTORY:
		_warehouse_floor(b, mb, bb, y0, y1, r)
	elif b.kind == CityPlan.K_SCHOOL:
		_school_floor(b, mb, bb, y0, y1, r)
	elif b.kind == CityPlan.K_PARKING:
		_parking_floor(b, mb, bb, y0, y1, r)
	else:
		_office_floor(b, mb, bb, y0, y1, r)
	# ceiling light panels
	_lights(b, mb, bb, y0, y1, r)
	# core: lift shafts + stairs
	_core(b, mb, bb, y0, y1, r)

static func _interior_skin(mb: MB, poly: PackedVector2Array, y0: float, y1: float, b: CityPlan.Bld) -> void:
	var col := Mats.c("cfc9bc")
	if b.kind == CityPlan.K_OFFICE or b.kind == CityPlan.K_TOWER:
		col = Mats.c("2f3238")
	elif b.kind == CityPlan.K_WAREHOUSE or b.kind == CityPlan.K_FACTORY:
		col = Mats.c("8a8678")
	var h := y1 - y0
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var e := poly[(i + 1) % n] - a
		var L := e.length()
		if L < 0.5:
			continue
		var dir := e / L
		var inward := Vector3(-e.y, 0, e.x) / L * -1.0
		var p := Vector3(a.x, 0, a.y)
		var th := Vector3(dir.x, 0, dir.y)
		mb.setm(M.WALL, col, b.sd, 0.0, 50.0 + M.STY_PUNCHED)
		var wb := 0.9
		var wt := 2.85
		if h < 3.2:
			wt = h - 0.5
		mb.quad_n(p + th * L + Vector3(0, y0, 0), p + Vector3(0, y0, 0),
			p + Vector3(0, y0 + wb, 0), p + th * L + Vector3(0, y0 + wb, 0), inward)
		mb.quad_n(p + th * L + Vector3(0, y0 + wt, 0), p + Vector3(0, y0 + wt, 0),
			p + Vector3(0, y1 - 0.02, 0), p + th * L + Vector3(0, y1 - 0.02, 0), inward)

static func _lights(b: CityPlan.Bld, mb: MB, bb: Rect2, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var c := bb.get_center()
	var nx := maxi(1, int(bb.size.x / 5.0))
	var nz := maxi(1, int(bb.size.y / 5.0))
	for ix in nx:
		for iz in nz:
			if r.randf() < 0.15:
				continue
			var px := bb.position.x + (ix + 0.5) * bb.size.x / nx
			var pz := bb.position.y + (iz + 0.5) * bb.size.y / nz
			mb.setm(M.EMIT, Mats.c("ffe3b8") if r.randf() < 0.7 else Mats.c("cfe4ff"), r.randf(), 1.1)
			if b.kind == CityPlan.K_OFFICE or b.kind == CityPlan.K_TOWER:
				mb.box(Vector3(px, y1 - 0.16, pz), Vector3(1.4, 0.05, 0.24), true, false)
			else:
				mb.cyl_y(Vector3(px, y1 - 0.2, pz), 0.32, 0.07, 10, true)

static func _core(b: CityPlan.Bld, mb: MB, bb: Rect2, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	if b.floors < 2:
		return
	var c := bb.get_center()
	var cw := minf(6.0, bb.size.x * 0.35)
	var cd := minf(5.0, bb.size.y * 0.35)
	var core := Rect2(c.x + bb.size.x * 0.5 - cw - 0.8, c.y - cd * 0.5, cw, cd)
	# shaft walls
	mb.setm(M.CONCRETE, Mats.c("8a867e"), b.sd)
	_room_walls(mb, core, y0, y1, false, r)
	# lift doors
	mb.setm(M.METAL, Mats.c("a8aeb4"), b.sd)
	for k in 2:
		var dx := core.position.x + core.size.x * (0.28 + 0.44 * k)
		mb.box(Vector3(dx, y0 + 1.15, core.position.y - 0.06), Vector3(1.1, 2.3, 0.08), true, false)
		mb.setm(M.EMIT, Mats.c("ff9a3c"), r.randf(), 1.2)
		mb.box(Vector3(dx, y0 + 2.45, core.position.y - 0.12), Vector3(0.9, 0.12, 0.05), true, false)
		mb.setm(M.METAL, Mats.c("a8aeb4"), b.sd)
	# stair hint
	mb.setm(M.CONCRETE, Mats.c("9a968c"), b.sd)
	for k in 6:
		mb.box(Vector3(core.end.x - 1.2, y0 + 0.2 + k * 0.28, core.position.y + 1.2 + k * 0.35),
			Vector3(2.0, 0.12, 0.36), true, false)

static func _room_walls(mb: MB, rect: Rect2, y0: float, y1: float, doors := true, r: RandomNumberGenerator = null) -> void:
	var h := y1 - y0 - 0.02
	mb.setm(M.WALL, Mats.c("cfc9bc"), r.randf() if r else 0.3, 0.0, 52.0)
	var x0 := rect.position.x
	var x1 := rect.end.x
	var z0 := rect.position.y
	var z1 := rect.end.y
	# north / south walls (along x)
	for zz in [z0, z1]:
		var nx := maxi(1, int((x1 - x0) / 3.5))
		for i in nx:
			var a := x0 + (x1 - x0) * i / nx
			var b := x0 + (x1 - x0) * (i + 1) / nx
			var gap := doors and i == nx / 2
			if gap:
				mb.box(Vector3((a + b) * 0.5 - 0.6, y0 + h * 0.5, zz), Vector3(maxf(0.1, (b - a) - 1.2), h, T))
			else:
				mb.box(Vector3((a + b) * 0.5, y0 + h * 0.5, zz), Vector3(b - a, h, T))
	# east / west walls (along z)
	for xx in [x0, x1]:
		var nz := maxi(1, int((z1 - z0) / 3.5))
		for i in nz:
			var a := z0 + (z1 - z0) * i / nz
			var b := z0 + (z1 - z0) * (i + 1) / nz
			var gap := doors and i == nz / 2
			if gap:
				mb.box(Vector3(xx, y0 + h * 0.5, (a + b) * 0.5 - 0.6), Vector3(T, h, maxf(0.1, (b - a) - 1.2)))
			else:
				mb.box(Vector3(xx, y0 + h * 0.5, (a + b) * 0.5), Vector3(T, h, b - a))

# ------------------------------------------------------------------ plans

static func _lobby(b: CityPlan.Bld, mb: MB, bb: Rect2, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var c := bb.get_center()
	var gw := minf(bb.size.x - 2.0, 16.0)
	var gd := minf(bb.size.y - 2.0, 14.0)
	var room := Rect2(c.x - gw * 0.5, c.y - gd * 0.5, gw, gd)
	# marble floor
	mb.setm(M.TILE, Mats.c("2e3138"), 0.2)
	mb.prism(_rect_poly(room.grow(-0.1)), y0 + 0.06, y0 + 0.08, true, false)
	# reception desk
	var desk := Vector3(c.x, y0, c.y - gd * 0.22)
	mb.setm(M.WOOD, Mats.c("5a3a24"), r.randf())
	mb.box(desk + Vector3(0, 0.55, 0), Vector3(5.2, 1.1, 1.0), true, false)
	mb.setm(M.METAL, Mats.c("2a2e34"), r.randf())
	mb.box(desk + Vector3(0, 1.15, 0), Vector3(5.6, 0.1, 1.2), true, false)
	mb.setm(M.SCREEN, Mats.c("3af0ff"), r.randf())
	mb.box(desk + Vector3(-1.2, 0.95, -0.15), Vector3(1.5, 0.9, 0.08))
	# seating
	for k in 3:
		_armchair(mb, Vector3(c.x - 5.0 + k * 5.0, y0, c.y + gd * 0.25), r, 0.0)
	# planters
	for k in 2:
		_planter(mb, Vector3(c.x - gw * 0.35 + k * gw * 0.7, y0, c.y + gd * 0.38), r)
	# signage wall
	mb.setm(M.EMIT, Mats.c("ff2f7a"), r.randf(), 2.0)
	mb.box(Vector3(c.x, y0 + 3.1, c.y - gd * 0.46), Vector3(6.0, 0.5, 0.1))
	# elevator bank hint
	mb.setm(M.METAL, Mats.c("b0b6bc"), r.randf())
	for k in 3:
		mb.box(Vector3(c.x + 4.0 + k * 1.6, y0 + 1.2, c.y - gd * 0.47), Vector3(1.2, 2.4, 0.1), true, false)
		mb.setm(M.EMIT, Mats.c("ffb14a"), r.randf(), 1.2)
		mb.box(Vector3(c.x + 4.0 + k * 1.6, y0 + 2.6, c.y - gd * 0.5), Vector3(0.9, 0.1, 0.06))
		mb.setm(M.METAL, Mats.c("b0b6bc"), r.randf())

static func _office_floor(b: CityPlan.Bld, mb: MB, bb: Rect2, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var c := bb.get_center()
	# open plan: cubicle pods on a grid, meeting room at one corner
	var pod := 3.4
	var nx := maxi(1, int((bb.size.x - 6.0) / pod))
	var nz := maxi(1, int((bb.size.y - 6.0) / pod))
	for ix in nx:
		for iz in nz:
			if r.randf() < 0.22:
				continue
			var px := bb.position.x + 3.0 + (ix + 0.5) * (bb.size.x - 6.0) / nx
			var pz := bb.position.y + 3.0 + (iz + 0.5) * (bb.size.y - 6.0) / nz
			_workstation(mb, Vector3(px, y0, pz), r)
	# meeting room glass box
	var mw := minf(7.0, bb.size.x * 0.3)
	var md := minf(5.0, bb.size.y * 0.3)
	var mr := Rect2(bb.position.x + 1.2, bb.position.y + 1.2, mw, md)
	mb.setm(M.GLASS, Color(0.2, 0.3, 0.35), r.randf())
	var hh := y1 - y0 - 0.15
	var g0 := Vector3(mr.position.x, y0, mr.end.y)
	mb.quad_n(g0, g0 + Vector3(mw, 0, 0), g0 + Vector3(mw, hh, 0), g0 + Vector3(0, hh, 0), Vector3(0, 0, -1))
	mb.quad_n(g0 + Vector3(mw, 0, 0), g0 + Vector3(mw, 0, -md), g0 + Vector3(mw, hh, -md), g0 + Vector3(mw, hh, 0), Vector3(1, 0, 0))
	mb.setm(M.WOOD, Mats.c("6b4a30"), r.randf())
	mb.box(Vector3(mr.get_center().x, y0 + 0.72, mr.get_center().y), Vector3(2.6, 0.08, 1.1))
	for k in 4:
		_box_chair(mb, Vector3(mr.position.x + 1.0 + (k % 2) * 1.6, y0, mr.position.y + 1.0 + (k / 2) * 2.2), r)
	# copy room / kitchenette
	var kx := bb.end.x - 3.0
	var kz := bb.end.y - 3.0
	mb.setm(M.WOOD, Mats.c("7a5a3a"), r.randf())
	mb.box(Vector3(kx, y0 + 0.45, kz), Vector3(2.4, 0.9, 0.7), true, false)
	mb.setm(M.METAL, Mats.c("b8bec4"), r.randf())
	mb.box(Vector3(kx - 0.6, y0 + 0.95, kz), Vector3(0.5, 0.1, 0.5))
	mb.setm(M.PLASTIC, Mats.c("2a3038"), r.randf())
	mb.box(Vector3(kx + 0.7, y0 + 1.2, kz), Vector3(0.4, 0.5, 0.35))

static func _workstation(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.WOOD, Mats.c("8a6a48"), r.randf())
	mb.box(p + Vector3(0, 0.72, 0), Vector3(1.6, 0.06, 0.8), true, false)
	mb.setm(M.METAL, Mats.c("3a3e44"), r.randf())
	for sx in [-0.7, 0.7]:
		for sz in [-0.3, 0.3]:
			mb.box(p + Vector3(sx, 0.36, sz), Vector3(0.05, 0.72, 0.05))
	mb.setm(M.SCREEN, Mats.c("4a90c0"), r.randf())
	mb.box(p + Vector3(0, 1.02, -0.15), Vector3(0.62, 0.38, 0.04))
	mb.setm(M.METAL, Mats.c("2a2e32"), r.randf())
	mb.box(p + Vector3(0, 0.85, -0.15), Vector3(0.08, 0.14, 0.08))
	_box_chair(mb, p + Vector3(0, 0, 0.75), r)
	# partition
	if r.randf() < 0.5:
		mb.setm(M.FABRIC, Mats.c("4a4f58"), r.randf())
		mb.box(p + Vector3(0, 1.25, -0.55), Vector3(1.6, 0.9, 0.04), true, false)

static func _box_chair(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.PLASTIC, Mats.c("232830"), r.randf())
	mb.box(p + Vector3(0, 0.45, 0), Vector3(0.5, 0.08, 0.5))
	mb.box(p + Vector3(0, 0.75, 0.24), Vector3(0.5, 0.5, 0.08))
	mb.setm(M.METAL, Mats.c("3a3e44"), r.randf())
	mb.cyl_y(p + Vector3(0, 0.22, 0), 0.04, 0.42, 6, true)

static func _apartment_floor(b: CityPlan.Bld, mb: MB, bb: Rect2, y0: float, y1: float, r: RandomNumberGenerator, f: int) -> void:
	# central corridor along the long axis, units either side
	var horizontal := bb.size.x > bb.size.y
	var units := clampi(int(bb.size.x / 8.0), 2, 6) if bb.size.x > bb.size.y else clampi(int(bb.size.y / 8.0), 2, 6)
	if horizontal:
		var cor := Rect2(bb.position.x + 0.8, bb.get_center().y - 0.9, bb.size.x - 1.6, 1.8)
		_room_walls(mb, cor, y0, y1, true, r)
		var uw := (bb.size.x - 2.0) / units
		for k in units:
			var ur := Rect2(bb.position.x + 1.0 + k * uw, bb.position.y + 0.4, uw - 0.2, bb.size.y * 0.5 - 1.0)
			var ur2 := Rect2(bb.position.x + 1.0 + k * uw, cor.end.y, uw - 0.2, bb.size.y * 0.5 - 1.0)
			_apartment_unit(mb, ur, y0, y1, r, f)
			_apartment_unit(mb, ur2, y0, y1, r, f)
	else:
		var cor := Rect2(bb.get_center().x - 0.9, bb.position.y + 0.8, 1.8, bb.size.y - 1.6)
		_room_walls(mb, cor, y0, y1, true, r)
		var uh := (bb.size.y - 2.0) / units
		for k in units:
			var ur := Rect2(bb.position.x + 0.4, bb.position.y + 1.0 + k * uh, bb.size.x * 0.5 - 1.0, uh - 0.2)
			var ur2 := Rect2(cor.end.x, bb.position.y + 1.0 + k * uh, bb.size.x * 0.5 - 1.0, uh - 0.2)
			_apartment_unit(mb, ur, y0, y1, r, f)
			_apartment_unit(mb, ur2, y0, y1, r, f)

static func _apartment_unit(mb: MB, rect: Rect2, y0: float, y1: float, r: RandomNumberGenerator, f: int) -> void:
	if rect.size.x < 2.6 or rect.size.y < 2.6:
		return
	mb.setm(M.WALL, Mats.c("d8d2c4"), r.randf(), 0.0, 52.0)
	# interior partitions: bedroom + bath along the back
	var w := rect.size.x
	var d := rect.size.y
	var c := rect.get_center()
	# bath in a corner
	var bw := minf(2.4, w * 0.42)
	var bd := minf(2.2, d * 0.45)
	var bath := Rect2(rect.position.x + 0.2, rect.end.y - bd - 0.2, bw, bd)
	_room_walls(mb, bath, y0, y1, true, r)
	_bathroom(mb, bath, y0, r)
	# bedroom
	var bed := Rect2(rect.position.x + 0.3, rect.position.y + 0.3, minf(w * 0.55, 3.4), minf(d * 0.5, 3.2))
	_room_walls(mb, bed, y0, y1, true, r)
	_bedroom(mb, bed, y0, r)
	# living / kitchen in the rest
	_living(mb, rect, y0, r)
	if f % 5 == 0:
		mb.setm(M.EMIT, Mats.c("ffb060"), r.randf(), 1.4)
		mb.box(Vector3(c.x, y1 - 0.25, c.y), Vector3(0.5, 0.06, 0.5), true, false)

static func _bedroom(mb: MB, rect: Rect2, y0: float, r: RandomNumberGenerator) -> void:
	var c := rect.get_center()
	var w := minf(1.7, rect.size.x * 0.55)
	var d := minf(2.1, rect.size.y * 0.65)
	# bed
	mb.setm(M.WOOD, Mats.c("5a3c26"), r.randf())
	mb.box(Vector3(c.x - rect.size.x * 0.1, y0 + 0.25, c.y), Vector3(w, 0.5, d))
	mb.setm(M.FABRIC, Mats.c("c8c0b0"), r.randf())
	mb.box(Vector3(c.x - rect.size.x * 0.1, y0 + 0.58, c.y), Vector3(w - 0.12, 0.16, d - 0.12))
	mb.setm(M.FABRIC, Mats.c("6a7a8a"), r.randf())
	mb.box(Vector3(c.x - rect.size.x * 0.1, y0 + 0.66, c.y - d * 0.28), Vector3(w - 0.2, 0.14, d * 0.3))
	# nightstand + lamp
	mb.setm(M.WOOD, Mats.c("4a3222"), r.randf())
	mb.box(Vector3(c.x + w * 0.5 + 0.3 - rect.size.x * 0.1, y0 + 0.3, c.y - d * 0.2), Vector3(0.45, 0.6, 0.45))
	mb.setm(M.EMIT, Mats.c("ffcf90"), r.randf(), 1.2)
	mb.cyl_y(Vector3(c.x + w * 0.5 + 0.3 - rect.size.x * 0.1, y0 + 0.72, c.y - d * 0.2), 0.14, 0.22, 8, true)
	# wardrobe
	mb.setm(M.WOOD, Mats.c("6a4a30"), r.randf())
	mb.box(Vector3(rect.position.x + 0.35, y0 + 1.1, rect.end.y - 0.45), Vector3(0.55, 2.2, 1.6))

static func _bathroom(mb: MB, rect: Rect2, y0: float, r: RandomNumberGenerator) -> void:
	mb.setm(M.TILE, Mats.c("cfc8ba"), r.randf())
	mb.prism(_rect_poly(rect.grow(-0.05)), y0 + 0.06, y0 + 0.09, true, false)
	var c := rect.get_center()
	# toilet
	mb.setm(M.CERAMIC, Mats.c("f0eee8"), r.randf())
	mb.box(Vector3(rect.position.x + 0.45, y0 + 0.35, rect.position.y + 0.5), Vector3(0.42, 0.5, 0.6))
	mb.box(Vector3(rect.position.x + 0.45, y0 + 0.68, rect.position.y + 0.28), Vector3(0.42, 0.5, 0.18))
	# sink
	mb.box(Vector3(rect.end.x - 0.45, y0 + 0.82, rect.position.y + 0.42), Vector3(0.6, 0.18, 0.42))
	mb.setm(M.METAL, Mats.c("b8bec4"), r.randf())
	mb.cyl_y(Vector3(rect.end.x - 0.45, y0 + 1.0, rect.position.y + 0.42), 0.03, 0.2, 6, true)
	# shower
	mb.setm(M.GLASS, Color(0.4, 0.5, 0.55), r.randf())
	var s := Vector3(rect.end.x - 0.8, y0, rect.end.y - 0.8)
	mb.quad_n(s + Vector3(-0.9, 0, 0), s + Vector3(0.9, 0, 0), s + Vector3(0.9, 2.0, 0), s + Vector3(-0.9, 2.0, 0), Vector3(0, 0, 1))

static func _living(mb: MB, rect: Rect2, y0: float, r: RandomNumberGenerator) -> void:
	var c := rect.get_center()
	# sofa
	mb.setm(M.FABRIC, Mats.c("5a2a38") if r.randf() < 0.5 else Mats.c("2a3a4a"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.38, c.y + rect.size.y * 0.12), Vector3(2.0, 0.7, 0.85))
	mb.box(Vector3(c.x, y0 + 0.85, c.y + rect.size.y * 0.12 + 0.35), Vector3(2.0, 0.6, 0.15))
	# coffee table
	mb.setm(M.WOOD, Mats.c("6a4a30"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.36, c.y - rect.size.y * 0.1), Vector3(1.0, 0.07, 0.6))
	mb.setm(M.METAL, Mats.c("2a2e32"), r.randf())
	for sx in [-0.4, 0.4]:
		mb.box(Vector3(c.x + sx, y0 + 0.18, c.y - rect.size.y * 0.1), Vector3(0.05, 0.36, 0.5))
	# tv
	mb.setm(M.SCREEN, Mats.c("204070"), r.randf(), 1.0)
	mb.box(Vector3(c.x, y0 + 1.35, rect.position.y + 0.25), Vector3(1.5, 0.85, 0.08))
	mb.setm(M.METAL, Mats.c("1a1c20"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.85, rect.position.y + 0.3), Vector3(1.2, 0.06, 0.3))
	# kitchenette along a wall
	mb.setm(M.WOOD, Mats.c("7a5a3a"), r.randf())
	mb.box(Vector3(rect.end.x - 1.2, y0 + 0.45, rect.position.y + 1.2), Vector3(1.8, 0.9, 0.62))
	mb.setm(M.METAL, Mats.c("b8bec4"), r.randf())
	mb.box(Vector3(rect.end.x - 1.2, y0 + 0.92, rect.position.y + 1.2), Vector3(1.9, 0.05, 0.66))
	mb.setm(M.CERAMIC, Mats.c("e8e8e8"), r.randf())
	mb.box(Vector3(rect.end.x - 1.6, y0 + 0.95, rect.position.y + 1.2), Vector3(0.5, 0.06, 0.4))
	# fridge
	mb.setm(M.METAL, Mats.c("c8ced4"), r.randf())
	mb.box(Vector3(rect.end.x - 0.45, y0 + 0.9, rect.position.y + 0.5), Vector3(0.7, 1.8, 0.7))
	# rug
	mb.setm(M.FABRIC, Mats.c("6a3a48") if r.randf() < 0.5 else Mats.c("33404a"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.24, c.y + rect.size.y * 0.06), Vector3(2.6, 0.03, 1.8), true, false)
	# shelf unit
	mb.setm(M.WOOD, Mats.c("4a3020"), r.randf())
	mb.box(Vector3(rect.position.x + 0.3, y0 + 0.85, c.y - rect.size.y * 0.2), Vector3(0.45, 1.7, 1.6))
	for si in 3:
		mb.setm(M.PLASTIC, _prod_col(r), r.randf())
		mb.box(Vector3(rect.position.x + 0.3, y0 + 0.35 + si * 0.45, c.y - rect.size.y * 0.2), Vector3(0.5, 0.25, 0.25))
	# dining table
	mb.setm(M.WOOD, Mats.c("7a5a3a"), r.randf())
	mb.box(Vector3(c.x + rect.size.x * 0.22, y0 + 0.72, c.y + rect.size.y * 0.2), Vector3(1.5, 0.07, 0.9))
	mb.setm(M.METAL, Mats.c("2a2e32"), r.randf())
	for sx in [-0.6, 0.6]:
		mb.box(Vector3(c.x + rect.size.x * 0.22 + sx, y0 + 0.36, c.y + rect.size.y * 0.2), Vector3(0.06, 0.72, 0.7))
	_box_chair(mb, Vector3(c.x + rect.size.x * 0.22 - 0.9, y0, c.y + rect.size.y * 0.2), r)
	_box_chair(mb, Vector3(c.x + rect.size.x * 0.22 + 0.9, y0, c.y + rect.size.y * 0.2), r)
	_planter(mb, Vector3(rect.position.x + 0.8, y0, rect.end.y - 0.8), r)

static func _hotel_floor(b: CityPlan.Bld, mb: MB, bb: Rect2, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var horizontal := bb.size.x > bb.size.y
	var count := maxi(2, int((bb.size.x if horizontal else bb.size.y) / 4.6))
	var corridor_w := 1.9
	for k in count:
		var t := (k + 0.5) / count
		if horizontal:
			var cx := bb.position.x + t * bb.size.x
			var side := 1.0 if k % 2 == 0 else -1.0
			var rect := Rect2(cx - 1.8, bb.position.y + (0.6 if side > 0 else bb.size.y * 0.5 + 0.4), 3.6, bb.size.y * 0.5 - 1.0)
			_hotel_room(mb, rect, y0, r)
		else:
			var cz := bb.position.y + t * bb.size.y
			var rect := Rect2(bb.position.x + (0.6 if k % 2 == 0 else bb.size.x * 0.5 + 0.4), cz - 1.8, bb.size.x * 0.5 - 1.0, 3.6)
			_hotel_room(mb, rect, y0, r)
	# corridor carpet
	mb.setm(M.FABRIC, Mats.c("3a2438"), r.randf())
	mb.prism(_rect_poly(Rect2(bb.position.x + 0.5, bb.get_center().y - corridor_w * 0.5, bb.size.x - 1.0, corridor_w)), y0 + 0.07, y0 + 0.08, true, false)

static func _hotel_room(mb: MB, rect: Rect2, y0: float, r: RandomNumberGenerator) -> void:
	if rect.size.x < 2.4 or rect.size.y < 2.4:
		return
	var c := rect.get_center()
	mb.setm(M.WOOD, Mats.c("5a3c26"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.26, c.y + 0.3), Vector3(1.8, 0.52, 2.1))
	mb.setm(M.FABRIC, Mats.c("d8d0c0"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.6, c.y + 0.3), Vector3(1.7, 0.16, 2.0))
	mb.setm(M.WOOD, Mats.c("4a3222"), r.randf())
	mb.box(Vector3(c.x + rect.size.x * 0.4, y0 + 0.3, c.y - rect.size.y * 0.3), Vector3(0.4, 0.6, 0.4))
	mb.setm(M.EMIT, Mats.c("ffcf90"), r.randf(), 1.1)
	mb.cyl_y(Vector3(c.x + rect.size.x * 0.4, y0 + 0.7, c.y - rect.size.y * 0.3), 0.12, 0.2, 8, true)
	# tv
	mb.setm(M.SCREEN, Mats.c("203a60"), r.randf())
	mb.box(Vector3(c.x, y0 + 1.4, rect.position.y + 0.3), Vector3(1.1, 0.65, 0.06))

static func _retail_floor(b: CityPlan.Bld, mb: MB, bb: Rect2, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var rows := maxi(1, int((bb.size.y - 4.0) / 3.6))
	for k in rows:
		var z := bb.position.y + 2.0 + (k + 0.5) * (bb.size.y - 4.0) / rows
		var len := bb.size.x * 0.62
		mb.setm(M.METAL, Mats.c("6a7076"), r.randf())
		mb.box(Vector3(bb.get_center().x, y0 + 0.85, z), Vector3(len, 0.1, 0.9), true, false)
		mb.box(Vector3(bb.get_center().x, y0 + 0.45, z), Vector3(len, 0.1, 0.9), true, false)
		mb.box(Vector3(bb.get_center().x - len * 0.5, y0 + 0.9, z), Vector3(0.06, 1.8, 0.9))
		mb.box(Vector3(bb.get_center().x + len * 0.5, y0 + 0.9, z), Vector3(0.06, 1.8, 0.9))
		# products
		var n := int(len / 0.55)
		for i in n:
			if r.randf() < 0.2:
				continue
			var px := bb.get_center().x - len * 0.5 + 0.3 + i * 0.55
			for row in 2:
				mb.setm(M.PLASTIC, _prod_col(r), r.randf())
				mb.box(Vector3(px, y0 + 0.55 + row * 0.42 + 0.12, z), Vector3(0.32, 0.22, 0.5))
	# checkout
	mb.setm(M.WOOD, Mats.c("7a5a3a"), r.randf())
	mb.box(Vector3(bb.position.x + 1.2, y0 + 0.55, bb.position.y + 1.2), Vector3(2.0, 1.1, 1.0))
	mb.setm(M.SCREEN, Mats.c("2ad0a0"), r.randf())
	mb.box(Vector3(bb.position.x + 1.2, y0 + 1.25, bb.position.y + 1.0), Vector3(0.5, 0.4, 0.06))

static func _prod_col(r: RandomNumberGenerator) -> Color:
	var cols := ["d03050", "30a0d0", "d0a030", "40b060", "a040c0", "e0e0d8", "203040"]
	return Mats.c(cols[r.randi() % cols.size()])

static func _school_floor(b: CityPlan.Bld, mb: MB, bb: Rect2, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var rooms := maxi(2, int(bb.size.x / 8.0))
	for k in rooms:
		var rw := bb.size.x / rooms
		var rect := Rect2(bb.position.x + k * rw + 0.3, bb.position.y + 0.3, rw - 0.6, bb.size.y * 0.5 - 1.0)
		_classroom(mb, rect, y0, r)
		var rect2 := Rect2(bb.position.x + k * rw + 0.3, bb.get_center().y + 0.8, rw - 0.6, bb.size.y * 0.5 - 1.2)
		_classroom(mb, rect2, y0, r)

static func _classroom(mb: MB, rect: Rect2, y0: float, r: RandomNumberGenerator) -> void:
	if rect.size.x < 3.0 or rect.size.y < 3.0:
		return
	# desks
	var nx := maxi(2, int(rect.size.x / 1.6))
	var nz := maxi(2, int(rect.size.y / 1.7))
	for i in nx:
		for j in nz:
			if r.randf() < 0.12:
				continue
			var px := rect.position.x + 0.9 + i * (rect.size.x - 1.6) / nx
			var pz := rect.position.y + 1.2 + j * (rect.size.y - 2.2) / nz
			mb.setm(M.WOOD, Mats.c("9a7a4a"), r.randf())
			mb.box(Vector3(px, y0 + 0.68, pz), Vector3(1.1, 0.06, 0.55))
			mb.setm(M.METAL, Mats.c("3a3e44"), r.randf())
			mb.box(Vector3(px, y0 + 0.34, pz), Vector3(0.06, 0.68, 0.45))
			_box_chair(mb, Vector3(px, y0, pz + 0.55), r)
	# blackboard
	mb.setm(M.PLASTIC, Mats.c("1c2a20"), r.randf())
	mb.box(Vector3(rect.get_center().x, y0 + 1.6, rect.position.y + 0.12), Vector3(minf(rect.size.x - 1.0, 3.4), 1.3, 0.07))
	mb.setm(M.WOOD, Mats.c("6a4a30"), r.randf())
	mb.box(Vector3(rect.get_center().x, y0 + 1.5, rect.position.y + 0.2), Vector3(1.6, 0.7, 0.5))

static func _warehouse_floor(b: CityPlan.Bld, mb: MB, bb: Rect2, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var rows := maxi(2, int(bb.size.y / 7.0))
	for k in rows:
		var z := bb.position.y + 2.5 + k * (bb.size.y - 4.0) / rows
		var len := bb.size.x * 0.8
		# pallet rack
		mb.setm(M.METAL, Mats.c("c07020"), r.randf())
		for lvl in 3:
			mb.box(Vector3(bb.get_center().x, y0 + 0.8 + lvl * 1.6, z), Vector3(len, 0.12, 1.1), true, false)
		for s in [-1, 1]:
			mb.box(Vector3(bb.get_center().x + s * len * 0.5, y0 + 2.4, z), Vector3(0.12, 4.8, 1.2))
		# pallets with boxes
		var n := int(len / 1.4)
		for i in n:
			if r.randf() < 0.3:
				continue
			var px := bb.get_center().x - len * 0.5 + 0.8 + i * 1.4
			mb.setm(M.WOOD, Mats.c("6a5030"), r.randf())
			mb.box(Vector3(px, y0 + 0.18, z), Vector3(1.1, 0.16, 1.0))
			mb.setm(M.PLASTIC, Mats.c("9a7a50"), r.randf())
			mb.box(Vector3(px, y0 + 0.55, z), Vector3(0.9, 0.7, 0.85))
			if r.randf() < 0.5:
				mb.box(Vector3(px, y0 + 1.05, z), Vector3(0.7, 0.35, 0.65))
	# forklift
	var fp := Vector3(bb.position.x + 3.0, y0, bb.end.y - 3.0)
	mb.setm(M.PLASTIC, Mats.c("d0a020"), r.randf())
	mb.box(fp + Vector3(0, 0.7, 0), Vector3(1.2, 1.0, 2.0))
	mb.box(fp + Vector3(0, 1.7, 0.4), Vector3(0.9, 1.0, 0.9))
	mb.setm(M.RUBBER, Mats.c("202020"), r.randf())
	for sx in [-0.55, 0.55]:
		for sz in [-0.6, 0.6]:
			mb.cyl_y(fp + Vector3(sx, 0.35, sz), 0.32, 0.2, 8, true)

static func _parking_floor(b: CityPlan.Bld, mb: MB, bb: Rect2, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var rows := maxi(1, int(bb.size.y / 6.0))
	for k in rows:
		var z := bb.position.y + 2.0 + k * 6.0
		var n := int(bb.size.x / 2.8)
		for i in n:
			var px := bb.position.x + 1.5 + i * 2.8
			mb.setm(M.ROADPAINT, Mats.c("d8d8d0"), r.randf(), 0.1)
			mb.box(Vector3(px, y0 + 0.07, z), Vector3(0.08, 0.01, 5.0), true, false)
			if r.randf() < 0.55:
				_car(mb, Vector3(px, y0, z + 1.2), r, true)

static func _car(mb: MB, p: Vector3, r: RandomNumberGenerator, parked := false) -> void:
	var col := _car_col(r)
	mb.setm(M.PLASTIC, col, r.randf())
	mb.box(p + Vector3(0, 0.55, 0), Vector3(1.8, 0.55, 4.2))
	mb.box(p + Vector3(0, 0.95, -0.2), Vector3(1.6, 0.5, 2.2))
	mb.setm(M.GLASS, Color(0.15, 0.2, 0.25), r.randf())
	mb.box(p + Vector3(0, 1.0, -0.2), Vector3(1.62, 0.36, 2.0))
	mb.setm(M.EMIT, Mats.c("fff0d0"), r.randf(), 1.4)
	mb.box(p + Vector3(-0.55, 0.55, -2.15), Vector3(0.4, 0.16, 0.06))
	mb.box(p + Vector3(0.55, 0.55, -2.15), Vector3(0.4, 0.16, 0.06))
	mb.setm(M.EMIT, Mats.c("ff2030"), r.randf(), 1.2)
	mb.box(p + Vector3(-0.55, 0.55, 2.15), Vector3(0.4, 0.14, 0.06))
	mb.box(p + Vector3(0.55, 0.55, 2.15), Vector3(0.4, 0.14, 0.06))
	mb.setm(M.RUBBER, Mats.c("141416"), r.randf())
	for sx in [-0.85, 0.85]:
		for sz in [-1.3, 1.3]:
			mb.cyl_y(p + Vector3(sx, 0.32, sz), 0.32, 0.22, 8, true)

static func _car_col(r: RandomNumberGenerator) -> Color:
	var cols := ["20242a", "3a3f46", "6a2028", "1a3048", "4a4a4a", "8a8a80", "3a2050"]
	return Mats.c(cols[r.randi() % cols.size()])

static func _armchair(mb: MB, p: Vector3, r: RandomNumberGenerator, rot: float) -> void:
	mb.setm(M.FABRIC, Mats.c("6a4a5a") if r.randf() < 0.5 else Mats.c("3a4a5a"), r.randf())
	mb.box(p + Vector3(0, 0.4, 0), Vector3(0.9, 0.6, 0.9))
	mb.box(p + Vector3(0, 0.9, 0.35), Vector3(0.9, 0.6, 0.12))
	mb.setm(M.WOOD, Mats.c("4a3222"), r.randf())
	mb.box(p + Vector3(0, 0.15, 0), Vector3(0.95, 0.1, 0.95))

static func _planter(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.CERAMIC, Mats.c("5a5a52"), r.randf())
	mb.cyl_y(p + Vector3(0, 0.35, 0), 0.45, 0.7, 10, true)
	mb.setm(M.SOIL, Mats.c("2a2018"), r.randf())
	mb.cyl_y(p + Vector3(0, 0.72, 0), 0.4, 0.05, 10, true)
	mb.setm(M.FOLIAGE, Mats.c("2c4a22"), r.randf())
	mb.sphere(p + Vector3(0, 1.25, 0), 0.6, 8, 5, 1.2)

static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(r.position.x, r.position.y),
		Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y),
		Vector2(r.position.x, r.end.y),
	])