## Procedural building interiors.
##  - real floor plans: core (lifts + stairs + restrooms + utility + risers),
##    corridor, rooms with doors, per-type furnishing and lighting
##  - per-floor generation units so streaming can stay inside a frame budget
class_name Interior
extends RefCounted

const T := 0.12

enum { R_OPEN, R_CELL, R_MEET, R_PANTRY, R_SERVER, R_STORAGE, R_BATH,
	R_STAIR, R_LIFT, R_PIPE, R_CORR, R_LOBBY, R_LIVING, R_BED, R_KITCHEN,
	R_UBATH, R_HOTEL, R_CLASS, R_LAB, R_STAFF, R_RETAIL, R_HALL, R_PARK, R_HOUSEKEEP }

class Room:
	var rect := Rect2()
	var type := 0
	var seedv := 0.0

## Re-compute the floor plan without building geometry (used by the photo / debug tools).
static func plan_rooms(b: CityPlan.Bld, f: int) -> Array:
	var bb := Poly.bbox(Poly.inset(b.poly, 1.5))
	if bb.size.x < 3.2 or bb.size.y < 3.2:
		return []
	var r := H.rng(b.id * 131 + f * 977, 41 + f, 7)
	return _plan(b, bb, f, r)

## Build one floor. Returns number of rooms furnished.
static func build_floor(b: CityPlan.Bld, mb: MB, f: int) -> int:
	var fh := Builder.floor_h(b)
	var y0 := 0.16
	var y1 := 0.0
	if f == 0:
		y1 = 5.0
	else:
		y0 = 0.16 + 5.0 + (f - 1) * fh
		y1 = y0 + fh
	if y1 > b.h - 0.5:
		return 0
	var inner := Poly.inset(b.poly, 0.45)
	if inner.size() < 3:
		inner = b.poly
	var bb := Poly.bbox(Poly.inset(b.poly, 1.5))
	if bb.size.x < 3.2 or bb.size.y < 3.2:
		return 0
	var r := H.rng(b.id * 131 + f * 977, 41 + f, 7)
	# slab + ceiling + fascia
	mb.setm(M.CONCRETE, Mats.c("b8b2a6"), b.sd, 0.30)
	mb.prism(Poly.inset(inner, 0.02), y0, y0 + 0.22, true, true)
	mb.setm(M.CONCRETE, Mats.c("8a867c"), b.sd)
	var fs := Poly.inset(inner, 0.05)
	if fs.size() >= 3:
		mb.prism(fs, y0 + 0.22, y0 + 0.50, false, false)
	# ceiling plate (so every generated floor is enclosed)
	mb.setm(M.CONCRETE, Mats.c("c2bcb0"), b.sd, 0.22)
	var cbb: Rect2 = Poly.bbox(inner)
	if cbb.size.x > 1.0 and cbb.size.y > 1.0:
		mb.box(Vector3(cbb.get_center().x, y1 + 0.10, cbb.get_center().y),
			Vector3(cbb.size.x - 0.1, 0.20, cbb.size.y - 0.1))
	# floor finish per room is laid inside the plan
	var rooms := _plan(b, bb, f, r)
	for room in rooms:
		var rm: Room = room
		_furnish(b, mb, rm, y0, y1, r)
	# walls
	for room in rooms:
		var rm: Room = room
		if rm.type == R_CORR:
			continue
		_room_shell(b, mb, rm, y0, y1, r)
	# corridor finish + ceiling lights
	for room in rooms:
		var rm: Room = room
		if rm.type == R_CORR:
			mb.setm(M.FABRIC, Mats.c("33363e"), r.randf())
			mb.prism(_rect(rm.rect.grow(-0.02)), y0 + 0.22, y0 + 0.24, true, false)
			for k in maxi(1, int(rm.rect.size.y / 5.0)):
				var p: Vector2 = rm.rect.get_center()
				p.y = rm.rect.position.y + (k + 0.5) * rm.rect.size.y / maxi(1, int(rm.rect.size.y / 5.0))
				mb.setm(M.EMIT, Mats.c("ffe6c4"), r.randf(), 1.15)
				mb.box(Vector3(p.x, y1 - 0.18, p.y), Vector3(0.5, 0.05, 0.9), true, false)
	return rooms.size()

# ------------------------------------------------------------------ planning

static func _plan(b: CityPlan.Bld, bb: Rect2, f: int, r: RandomNumberGenerator) -> Array:
	var rooms: Array = []
	var ground := f == 0
	var long_x := bb.size.x >= bb.size.y
	var core_w := clampf(minf(bb.size.x, bb.size.y) * 0.32, 4.5, 8.5)
	var core := Rect2()
	if long_x:
		core = Rect2(bb.end.x - core_w, bb.position.y + 0.4, core_w - 0.4, bb.size.y - 0.8)
	else:
		core = Rect2(bb.position.x + 0.4, bb.end.y - core_w, bb.size.x - 0.8, core_w - 0.4)
	rooms.append(_mk(core, R_STAIR, r))
	# core sub-rooms: lifts, restrooms, utility, riser
	if long_x:
		var half := core.size.y * 0.5
		rooms.append(_mk(Rect2(core.position.x + 0.2, core.position.y + 0.2, core.size.x - 0.4, 1.9), R_LIFT, r))
		rooms.append(_mk(Rect2(core.position.x + 0.2, core.position.y + 2.5, core.size.x - 0.4, 1.9), R_LIFT, r))
		rooms.append(_mk(Rect2(core.position.x + 0.2, core.position.y + half, core.size.x - 0.4, minf(2.2, half - 1.0)), R_BATH, r))
		rooms.append(_mk(Rect2(core.position.x + 0.2, core.end.y - 1.6, core.size.x - 0.4, 1.3), R_PIPE, r))
		rooms.append(_mk(Rect2(core.position.x + 0.2, core.position.y + half + 2.6, core.size.x - 0.4, 1.5), R_STORAGE, r))
	else:
		rooms.append(_mk(Rect2(core.position.x + 0.2, core.position.y + 0.2, 1.9, core.size.y - 0.4), R_LIFT, r))
		rooms.append(_mk(Rect2(core.position.x + 2.5, core.position.y + 0.2, 1.9, core.size.y - 0.4), R_LIFT, r))
		rooms.append(_mk(Rect2(core.position.x + core.size.x - 2.6, core.position.y + 0.2, 2.3, core.size.y * 0.5), R_BATH, r))
		rooms.append(_mk(Rect2(core.position.x + core.size.x - 1.5, core.end.y - 1.5, 1.2, 1.2), R_PIPE, r))
	# corridor
	var corr_w := 2.2 if b.kind != CityPlan.K_APARTMENT else 1.9
	var corr := Rect2()
	if long_x:
		corr = Rect2(bb.position.x, core.position.y + core.size.y * 0.5 - corr_w * 0.5,
			core.position.x - bb.position.x, corr_w)
		rooms.append(_mk(corr, R_CORR, r))
	else:
		corr = Rect2(core.position.x + core.size.x * 0.5 - corr_w * 0.5, bb.position.y,
			corr_w, core.position.y - bb.position.y)
		rooms.append(_mk(corr, R_CORR, r))
	# usable band(s)
	if ground and (b.kind == CityPlan.K_SHOP or b.kind == CityPlan.K_MALL or b.kind == CityPlan.K_OFFICE
			or b.kind == CityPlan.K_TOWER or b.kind == CityPlan.K_HOTEL):
		rooms.append(_mk(bb, R_LOBBY, r))
		return _dedupe(rooms)
	var areas: Array = []
	if long_x:
		var corr_len: float = core.position.x - bb.position.x
		areas.append(Rect2(bb.position.x, bb.position.y, corr_len, bb.size.y * 0.5 - corr_w * 0.5 - 0.1))
		areas.append(Rect2(bb.position.x, corr.position.y + corr.size.y + 0.1, corr_len,
			bb.end.y - (corr.position.y + corr.size.y) - 0.1))
	else:
		var corr_len2: float = core.position.y - bb.position.y
		areas.append(Rect2(bb.position.x, bb.position.y, bb.size.x * 0.5 - corr_w * 0.5 - 0.1, corr_len2))
		areas.append(Rect2(corr.position.x + corr.size.x + 0.1, bb.position.y,
			bb.end.x - (corr.position.x + corr.size.x) - 0.1, corr_len2))
	for a in areas:
		var ar: Rect2 = a
		if ar.size.x < 2.4 or ar.size.y < 2.4:
			continue
		rooms += _split_area(b, ar, f, r)
	return _dedupe(rooms)

static func _split_area(b: CityPlan.Bld, ar: Rect2, f: int, r: RandomNumberGenerator) -> Array:
	var out: Array = []
	var kind := b.kind
	if kind == CityPlan.K_APARTMENT:
		out += _units(b, ar, f, r)
	elif kind == CityPlan.K_HOTEL:
		out += _hotel_rooms(b, ar, r)
	elif kind == CityPlan.K_SCHOOL:
		out += _split_grid(ar, r, 7.5, 8.5, R_CLASS, R_STAFF)
	elif kind == CityPlan.K_WAREHOUSE or kind == CityPlan.K_FACTORY:
		out.append(_mk(ar, R_HALL, r))
	elif kind == CityPlan.K_PARKING:
		out.append(_mk(ar, R_PARK, r))
	elif kind == CityPlan.K_SHOP or kind == CityPlan.K_MALL:
		out.append(_mk(ar, R_RETAIL, r))
	else:
		# office: perimeter cellular offices + open plan
		out += _split_grid(ar, r, 3.6, 4.4, R_CELL, R_MEET)
	return out

static func _units(b: CityPlan.Bld, ar: Rect2, f: int, r: RandomNumberGenerator) -> Array:
	var out: Array = []
	var horiz := ar.size.x > ar.size.y
	var n := maxi(1, int((ar.size.x if horiz else ar.size.y) / 7.5))
	for k in n:
		var rect := Rect2()
		if horiz:
			rect = Rect2(ar.position.x + k * ar.size.x / n, ar.position.y, ar.size.x / n, ar.size.y)
		else:
			rect = Rect2(ar.position.x, ar.position.y + k * ar.size.y / n, ar.size.x, ar.size.y / n)
		if rect.size.x < 2.8 or rect.size.y < 2.8:
			continue
		out.append(_mk(rect, R_LIVING, r))
		# bathroom in a corner
		var bw := minf(2.4, rect.size.x * 0.42)
		var bh := minf(2.2, rect.size.y * 0.42)
		out.append(_mk(Rect2(rect.end.x - bw - 0.2, rect.end.y - bh - 0.2, bw, bh), R_UBATH, r))
		# bedroom at the other end
		var bed := Rect2(rect.position.x + 0.2, rect.position.y + 0.2,
			maxf(2.6, rect.size.x * 0.55), maxf(2.4, rect.size.y * 0.5))
		out.append(_mk(bed, R_BED, r))
		# kitchen along a wall
		var kit := Rect2(rect.end.x - minf(2.6, rect.size.x * 0.42), rect.position.y + 0.2,
			minf(2.4, rect.size.x * 0.4), maxf(1.8, rect.size.y * 0.35))
		out.append(_mk(kit, R_KITCHEN, r))
	return out

static func _hotel_rooms(b: CityPlan.Bld, ar: Rect2, r: RandomNumberGenerator) -> Array:
	var out: Array = []
	var horiz := ar.size.x > ar.size.y
	var span := ar.size.x if horiz else ar.size.y
	var n := maxi(1, int(span / 4.4))
	for k in n:
		var rect := Rect2()
		if horiz:
			rect = Rect2(ar.position.x + k * span / n, ar.position.y, span / n, ar.size.y)
		else:
			rect = Rect2(ar.position.x, ar.position.y + k * span / n, ar.size.x, span / n)
		if rect.size.x < 2.4 or rect.size.y < 2.4:
			continue
		out.append(_mk(rect.grow(-0.05), R_HOTEL, r))
	if r.randf() < 0.5:
		out.append(_mk(Rect2(ar.end.x - 1.4, ar.position.y + 0.3, 1.2, 1.6), R_PIPE, r))
	return out

static func _split_grid(ar: Rect2, r: RandomNumberGenerator, min_w: float, min_d: float,
		main_type: int, aux_type: int) -> Array:
	var out: Array = []
	var cols := maxi(1, int(ar.size.x / (min_w + 1.2)))
	var rows := maxi(1, int(ar.size.y / (min_d + 1.0)))
	for i in cols:
		for j in rows:
			var rect := Rect2(ar.position.x + i * ar.size.x / cols, ar.position.y + j * ar.size.y / rows,
				ar.size.x / cols - 0.12, ar.size.y / rows - 0.12)
			if rect.size.x < 2.2 or rect.size.y < 2.2:
				continue
			var t := main_type
			if r.randf() < 0.14:
				t = aux_type
			out.append(_mk(rect, t, r))
	return out

static func _mk(rect: Rect2, type: int, r: RandomNumberGenerator) -> Room:
	var room := Room.new()
	room.rect = rect
	room.type = type
	room.seedv = r.randf()
	return room

static func _dedupe(rooms: Array) -> Array:
	# drop rooms that are fully inside a lobby or each other (keep the lobby)
	var out: Array = []
	for room in rooms:
		var inside := false
		for other in rooms:
			if other == room:
				continue
			if other.type != R_LOBBY and room.type == R_LOBBY:
				continue
			if other.rect.encloses(room.rect) and other.type == R_LOBBY and room.type != R_LOBBY:
				inside = true
				break
		if not inside:
			out.append(room)
	return out

static func _rect(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)])

# ------------------------------------------------------------------ shells

static func _room_shell(b: CityPlan.Bld, mb: MB, room: Room, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var rect := room.rect
	var h := y1 - y0 - 0.24
	# finish + palette per room type
	var style := 60.0
	var base := Mats.c("e8e2d4")
	var accent := false
	match room.type:
		R_BATH, R_UBATH:
			style = 62.0
			base = Mats.c("d8d2c4") if room.seedv < 0.5 else Mats.c("c8d0cc")
		R_LIVING:
			style = 60.0
			base = Mats.c("e6ddcb") if room.seedv < 0.5 else Mats.c("d8dcd2")
			accent = false
		R_BED:
			style = 60.0
			base = Mats.c("e2d8c8") if room.seedv < 0.5 else Mats.c("d4d8e0")
			accent = false
		R_HOTEL:
			style = 60.0
			base = Mats.c("d8cdb8") if room.seedv < 0.5 else Mats.c("c8ccd4")
		R_CELL, R_MEET, R_LOBBY:
			style = 60.0
			base = Mats.c("e4e2da") if room.seedv < 0.5 else Mats.c("d6d8d4")
		R_CLASS, R_LAB:
			style = 60.0
			base = Mats.c("e8e4d8") if room.seedv < 0.5 else Mats.c("d8dcd8")
		R_STAFF, R_STORAGE, R_PIPE, R_STAIR, R_LIFT:
			style = 62.0 if room.type != R_STAIR else 60.0
			base = Mats.c("cfcac0")
		R_RETAIL:
			style = 60.0
			base = Mats.c("e0dcd0")
		R_HALL:
			style = 62.0
			base = Mats.c("c8c4b8")
		R_PARK:
			style = 62.0
			base = Mats.c("b8b4ac")
	# walls: three vertical bands (floor/ceiling AO) + optional accent wall
	var door_side := r.randi() % 4
	for sidx in 4:
		var a := Vector3.ZERO
		var bv := Vector3.ZERO
		match sidx:
			0: a = Vector3(rect.position.x, 0, rect.position.y); bv = Vector3(rect.end.x, 0, rect.position.y)
			1: a = Vector3(rect.end.x, 0, rect.position.y); bv = Vector3(rect.end.x, 0, rect.end.y)
			2: a = Vector3(rect.end.x, 0, rect.end.y); bv = Vector3(rect.position.x, 0, rect.end.y)
			3: a = Vector3(rect.position.x, 0, rect.end.y); bv = Vector3(rect.position.x, 0, rect.position.y)
		var L := a.distance_to(bv)
		if L < 0.3:
			continue
		var wstyle := 60.0
		if accent and sidx == 0:
			wstyle = 63.0
		if sidx == door_side and L > 2.0:
			var dw := 0.95
			var mid := (a + bv) * 0.5
			var dir := (bv - a).normalized()
			_wall_bands(mb, a, mid - dir * dw * 0.5, y0, h, base, wstyle, room.seedv)
			_wall_bands(mb, mid + dir * dw * 0.5, bv, y0, h, base, wstyle, room.seedv)
			mb.setm(_wall_mat(wstyle), base, room.seedv, 0.02, wstyle)
			mb.box(Vector3(mid.x, y0 + 2.25 + h * 0.5 - 1.05, mid.z), Vector3(dw, h - 2.1, T))
			_door_frame(mb, mid, dir, y0, r)
		else:
			_wall_bands(mb, a, bv, y0, h, base, wstyle, room.seedv)
	# baseboard
	mb.setm(M.WOOD, Mats.c("4a3a2c"), room.seedv, 0.05)
	for s2 in 2:
		var w := rect.size.x if s2 == 0 else rect.size.y
		var p := rect.position if s2 == 0 else Vector2(rect.end.x, rect.position.y)
		mb.box(Vector3(p.x, y0 + 0.30, p.y), Vector3(w, 0.14, T * 0.7) if s2 == 0 else Vector3(T * 0.7, 0.14, w), true, true)
	# floor finish by room type
	var fm := M.FABRIC
	var fc := Mats.c("3a3d44")
	match room.type:
		R_BATH, R_UBATH:
			fm = M.TILE
			fc = Mats.c("cfc8ba")
		R_LIVING, R_BED, R_HOTEL:
			fm = M.FABRIC
			fc = Mats.c("6a5a50") if room.seedv < 0.5 else Mats.c("3a4a52")
		R_KITCHEN:
			fm = M.TILE
			fc = Mats.c("b8b2a4")
		R_CELL, R_MEET, R_OPEN, R_LOBBY:
			fm = M.FABRIC
			fc = Mats.c("2f333a")
		R_CLASS, R_LAB:
			fm = M.TILE
			fc = Mats.c("a8a496")
		R_HALL, R_STORAGE, R_STAIR, R_LIFT, R_PIPE:
			fm = M.CONCRETE
			fc = Mats.c("8a8680")
		R_RETAIL:
			fm = M.TILE
			fc = Mats.c("c8c2b4")
		R_PARK:
			fm = M.ASPHALT
			fc = Mats.c("4a4a50")
	mb.setm(fm, fc, room.seedv, 0.05)
	mb.prism(_rect(rect.grow(-0.03)), y0 + 0.22, y0 + 0.25, true, false)
	# ceiling light
	if room.type != R_CORR:
		_room_lights(mb, room, y1, r)

static func _wall_bands(mb: MB, a: Vector3, b: Vector3, y0: float, h: float, base: Color, style: float, sd: float) -> void:
	var L := a.distance_to(b)
	if L < 0.05:
		return
	var dir := (b - a) / L
	var horiz := absf(dir.x) > 0.5
	# floor AO band, main field, ceiling AO band
	for band in [[0.0, 0.26, 0.80], [0.26, 0.80, 1.0], [0.80, 1.0, 0.86]]:
		var t0: float = band[0]
		var t1: float = band[1]
		var mul: float = band[2]
		var c := (a + b) * 0.5
		var yy := y0 + (t0 + t1) * 0.5 * h
		var hh := (t1 - t0) * h
		mb.setm(_wall_mat(style), base * mul, sd, 0.02, style)
		mb.box(Vector3(c.x, yy, c.z),
			Vector3(L, hh, T) if horiz else Vector3(T, hh, L), true, true)
	# corner shadow strips
	mb.setm(_wall_mat(style), base * 0.68, sd, 0.02, style)
	mb.box(Vector3(a.x + dir.x * 0.09, y0 + h * 0.5, a.z + dir.z * 0.09),
		Vector3(0.18, h, 0.18))
	mb.box(Vector3(b.x - dir.x * 0.09, y0 + h * 0.5, b.z - dir.z * 0.09),
		Vector3(0.18, h, 0.18))

static func _wall_mat(style: float) -> int:
	if style > 61.5 and style < 62.5:
		return M.TILE
	if style > 62.5 and style < 63.5:
		return M.WOOD
	if style > 63.5 and style < 64.5:
		return M.FABRIC
	return M.CERAMIC

static func _box_wall(mb: MB, a: Vector3, b: Vector3, y0: float, h: float) -> void:
	var c := (a + b) * 0.5
	var d := b - a
	var L := d.length()
	if L < 0.05:
		return
	var dir := d / L
	var th := 0.12
	mb.box(Vector3(c.x, y0 + h * 0.5, c.z), Vector3(L, h, th) if absf(dir.x) > 0.5 else Vector3(th, h, L),
		true, false)

static func _door_frame(mb: MB, p: Vector3, dir: Vector3, y0: float, r: RandomNumberGenerator) -> void:
	var side := Vector3(-dir.z, 0, dir.x)
	mb.setm(M.METAL, Mats.c("6a6e72"), r.randf())
	for s in [-1.0, 1.0]:
		mb.box(p + side * (0.55 * s) + Vector3(0, y0 + 1.05, 0), Vector3(0.09, 2.1, 0.16))
	mb.box(p + Vector3(0, y0 + 2.12, 0), Vector3(1.2, 0.1, 0.16))
	# door panel, slightly ajar
	mb.setm(M.WOOD, Mats.c("4a3424") if r.randf() < 0.6 else Mats.c("d8d2c8"), r.randf())
	var ang := r.randf_range(0.0, 0.5)
	var b2 := Basis(Vector3.UP, ang)
	var off := b2 * (dir * 0.5)
	mb.obox(p + off + Vector3(0, y0 + 1.05, 0), Vector3(0.95, 2.05, 0.05), Basis(Vector3.UP, atan2(dir.x, dir.z) + ang))

static func _room_lights(mb: MB, room: Room, y1: float, r: RandomNumberGenerator) -> void:
	var rect := room.rect
	var cols := maxi(1, int(rect.size.x / 4.0))
	var rows := maxi(1, int(rect.size.y / 4.0))
	for i in cols:
		for j in rows:
			if r.randf() < 0.12:
				continue
			var p := Vector3(rect.position.x + (i + 0.5) * rect.size.x / cols,
				y1 - 0.16, rect.position.y + (j + 0.5) * rect.size.y / rows)
			var warm := r.randf() < 0.72
			mb.setm(M.EMIT, Mats.c("ffe2b4") if warm else Mats.c("d6e8ff"), r.randf(), 0.9)
			if room.type == R_BATH or room.type == R_UBATH or room.type == R_KITCHEN:
				mb.cyl_y(p, 0.16, 0.05, 8, true)
			elif room.type == R_CELL or room.type == R_MEET:
				mb.box(p, Vector3(1.1, 0.04, 0.16), true, false)
			else:
				mb.cyl_y(p, 0.28, 0.05, 10, true)

# ------------------------------------------------------------------ furnishings

static func _furnish(b: CityPlan.Bld, mb: MB, room: Room, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	match room.type:
		R_LOBBY: _lobby(mb, room, y0, y1, r)
		R_CELL: _office_cell(mb, room, y0, y1, r)
		R_MEET: _meeting(mb, room, y0, y1, r)
		R_OPEN: _open_office(mb, room, y0, y1, r)
		R_PANTRY: _pantry(mb, room, y0, r)
		R_SERVER: _server(mb, room, y0, r)
		R_BATH: _bathroom(mb, room, y0, r)
		R_STAIR: _stair(mb, room, y0, y1, r)
		R_LIFT: _lift(mb, room, y0, y1, r)
		R_PIPE: _pipe(mb, room, y0, y1, r)
		R_STORAGE: _storage(mb, room, y0, r)
		R_LIVING: _living(mb, room, y0, y1, r)
		R_BED: _bedroom(mb, room, y0, r)
		R_KITCHEN: _kitchen(mb, room, y0, r)
		R_UBATH: _bathroom(mb, room, y0, r)
		R_HOTEL: _hotel_room(mb, room, y0, r)
		R_CLASS: _classroom(mb, room, y0, r)
		R_LAB: _lab(mb, room, y0, r)
		R_STAFF: _staff(mb, room, y0, r)
		R_RETAIL: _retail(mb, room, y0, r)
		R_HALL: _hall(mb, room, y0, r)
		R_PARK: _parking(mb, room, y0, r)
		R_HOUSEKEEP: _storage(mb, room, y0, r)

static func _lobby(mb: MB, room: Room, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var rect := room.rect
	var c := rect.get_center()
	mb.setm(M.TILE, Mats.c("2e3138"), 0.2)
	mb.prism(_rect(rect.grow(-0.3)), y0 + 0.24, y0 + 0.26, true, false)
	# reception desk
	var dz := rect.end.y - 4.0
	mb.setm(M.WOOD, Mats.c("5a3a24"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.55, dz), Vector3(4.6, 1.1, 0.9), true, false)
	mb.setm(M.METAL, Mats.c("2a2e34"), r.randf())
	mb.box(Vector3(c.x, y0 + 1.12, dz), Vector3(5.0, 0.08, 1.1), true, false)
	mb.setm(M.SCREEN, Mats.c("3af0ff"), r.randf())
	mb.box(Vector3(c.x - 1.1, y0 + 0.95, dz - 0.1), Vector3(1.4, 0.85, 0.06))
	# waiting island
	for k in 4:
		_armchair(mb, Vector3(c.x - 3.6 + k * 2.4, y0, c.y + 1.0), r)
	_planter(mb, Vector3(rect.position.x + 1.2, y0, rect.position.y + 1.2), r)
	_planter(mb, Vector3(rect.end.x - 1.2, y0, rect.position.y + 1.2), r)
	# elevator bank on the core wall
	mb.setm(M.METAL, Mats.c("b0b6bc"), r.randf())
	for k in 3:
		mb.box(Vector3(rect.end.x - 1.0 - k * 1.7, y0 + 1.2, rect.end.y - 0.25), Vector3(1.2, 2.4, 0.1))
		mb.setm(M.EMIT, Mats.c("ffb14a"), r.randf(), 0.8)
		mb.box(Vector3(rect.end.x - 1.0 - k * 1.7, y0 + 2.62, rect.end.y - 0.3), Vector3(0.8, 0.1, 0.05))
		mb.setm(M.METAL, Mats.c("b0b6bc"), r.randf())
	# big neon sign
	mb.setm(M.EMIT, Mats.c("ff2f7a"), r.randf(), 1.8)
	mb.box(Vector3(c.x, y0 + 3.4, rect.position.y + 0.15), Vector3(6.5, 0.6, 0.08))
	# coffee cart + papers (life traces)
	mb.setm(M.METAL, Mats.c("8a9098"), r.randf())
	mb.box(Vector3(rect.position.x + 2.0, y0 + 0.5, rect.end.y - 2.0), Vector3(0.8, 1.0, 0.6))
	mb.setm(M.PLASTIC, Mats.c("e8e4dc"), r.randf())
	for k in 3:
		mb.cyl_y(Vector3(rect.position.x + 2.0 + k * 0.22, y0 + 1.04, rect.end.y - 2.0), 0.04, 0.09, 6, true)

static func _office_cell(mb: MB, room: Room, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var rect := room.rect
	var c := rect.get_center()
	var n := 1 + int(rect.size.x * rect.size.y / 26.0)
	for k in n:
		var p := Vector3(c.x + r.randf_range(-rect.size.x * 0.22, rect.size.x * 0.22), y0,
			c.y + r.randf_range(-rect.size.y * 0.22, rect.size.y * 0.22))
		_workstation(mb, p, r, r.randf() * TAU)
	if r.randf() < 0.55:
		_planter(mb, Vector3(rect.position.x + 0.7, y0, rect.end.y - 0.7), r)
	if r.randf() < 0.5:
		mb.setm(M.WOOD, Mats.c("5a3f28"), r.randf())
		mb.box(Vector3(rect.end.x - 0.75, y0 + 0.9, c.y), Vector3(0.6, 1.8, 1.6), true, false)

static func _open_office(mb: MB, room: Room, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var nodes := maxi(1, int(room.rect.size.x / 5.0))
	for i in nodes:
		var p := Vector3(room.rect.position.x + (i + 0.5) * room.rect.size.x / nodes, y0, room.rect.get_center().y)
		_workstation(mb, p, r, 0.0)

static func _meeting(mb: MB, room: Room, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var c := room.rect.get_center()
	var tw := minf(2.6, room.rect.size.x * 0.55)
	var td := minf(1.2, room.rect.size.y * 0.4)
	mb.setm(M.WOOD, Mats.c("6b4a30"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.74, c.y), Vector3(tw, 0.07, td))
	mb.setm(M.METAL, Mats.c("2a2e32"), r.randf())
	for sx in [-0.8, 0.8]:
		mb.box(Vector3(c.x + sx * tw * 0.3, y0 + 0.37, c.y), Vector3(0.07, 0.74, td * 0.7))
	var chairs := 4 + int(r.randf() * 4.0)
	for k in chairs:
		var a := TAU * float(k) / chairs
		_box_chair(mb, Vector3(c.x + cos(a) * tw * 0.7, y0, c.y + sin(a) * td * 0.9), r)
	# screen + whiteboard
	mb.setm(M.SCREEN, Mats.c("1a3050"), r.randf())
	mb.box(Vector3(c.x, y0 + 1.55, room.rect.position.y + 0.2), Vector3(1.8, 1.0, 0.06))
	mb.setm(M.PLASTIC, Mats.c("e8e6de"), r.randf())
	mb.box(Vector3(room.rect.end.x - 0.2, y0 + 1.5, c.y), Vector3(0.05, 1.1, minf(2.4, room.rect.size.y * 0.7)))
	# coffee cups
	mb.setm(M.PLASTIC, Mats.c("f0ede4"), r.randf())
	for k in 3:
		mb.cyl_y(Vector3(c.x + r.randf_range(-0.8, 0.8), y0 + 0.82, c.y + r.randf_range(-0.4, 0.4)), 0.035, 0.08, 6, true)

static func _pantry(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var c := room.rect.get_center()
	mb.setm(M.WOOD, Mats.c("7a5a3a"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.45, room.rect.position.y + 0.45), Vector3(room.rect.size.x * 0.7, 0.9, 0.6), true, false)
	mb.setm(M.METAL, Mats.c("b8bec4"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.92, room.rect.position.y + 0.45), Vector3(room.rect.size.x * 0.7, 0.05, 0.65), true, false)
	mb.box(Vector3(c.x - 0.6, y0 + 1.0, room.rect.position.y + 0.45), Vector3(0.5, 0.1, 0.45))
	mb.setm(M.CERAMIC, Mats.c("e8e8e8"), r.randf())
	mb.box(Vector3(c.x + 0.4, y0 + 1.02, room.rect.position.y + 0.45), Vector3(0.45, 0.06, 0.38))
	mb.setm(M.METAL, Mats.c("c8ced4"), r.randf())
	mb.box(Vector3(room.rect.end.x - 0.5, y0 + 0.9, c.y), Vector3(0.7, 1.8, 0.7))
	_box_chair(mb, Vector3(c.x, y0, c.y + 1.0), r)

static func _server(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var rows := maxi(1, int(room.rect.size.x / 1.3))
	for i in rows:
		var p := Vector3(room.rect.position.x + (i + 0.5) * room.rect.size.x / rows, y0, room.rect.get_center().y)
		mb.setm(M.METAL, Mats.c("2a2e34"), r.randf())
		mb.box(p + Vector3(0, 1.0, 0), Vector3(0.8, 2.0, 0.9))
		mb.setm(M.EMIT, Mats.c("2aff8f"), r.randf(), 0.5)
		for k in 4:
			mb.box(p + Vector3(0, 0.3 + k * 0.45, -0.47), Vector3(0.5, 0.05, 0.02))

static func _stair(mb: MB, room: Room, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var rect := room.rect
	var h := y1 - y0
	var steps := maxi(8, int(h / 0.18))
	var w := minf(1.4, rect.size.x * 0.4)
	var z := rect.position.y + 0.6
	mb.setm(M.CONCRETE, Mats.c("9a968c"), r.randf())
	for s in steps:
		var y := y0 + (s + 1) * h / steps
		mb.box(Vector3(rect.position.x + 0.8, y - 0.09, z + s * 0.30), Vector3(w, 0.18, 0.32), true, false)
	mb.setm(M.METAL, Mats.c("5a6068"), r.randf())
	mb.box(Vector3(rect.position.x + 0.8 + w * 0.5, y0 + h * 0.5, z + steps * 0.15), Vector3(0.05, h, 0.05))
	mb.box(Vector3(rect.position.x + 0.8 - w * 0.5, y0 + h * 0.5, z + steps * 0.15), Vector3(0.05, h, 0.05))
	# lift doors across the room
	if rect.size.x > 3.4:
		mb.setm(M.METAL, Mats.c("b0b6bc"), r.randf())
		for k in 2:
			var p := Vector3(rect.end.x - 0.2, y0 + 1.15, rect.position.y + 1.2 + k * 2.0)
			mb.box(p, Vector3(0.1, 2.3, 1.1))
			mb.setm(M.EMIT, Mats.c("ffb14a"), r.randf(), 0.7)
			mb.box(p + Vector3(-0.07, 1.35, 0), Vector3(0.04, 0.12, 0.7))
			mb.setm(M.METAL, Mats.c("b0b6bc"), r.randf())

static func _lift(mb: MB, room: Room, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	mb.setm(M.METAL, Mats.c("8a9098"), r.randf())
	mb.box(Vector3(room.rect.get_center().x, y0 + 1.15, room.rect.position.y + 0.12), Vector3(1.3, 2.3, 0.12))
	mb.setm(M.EMIT, Mats.c("ffb14a"), r.randf(), 0.9)
	mb.box(Vector3(room.rect.get_center().x, y0 + 2.55, room.rect.position.y + 0.2), Vector3(1.0, 0.1, 0.05))

static func _pipe(mb: MB, room: Room, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var h := y1 - y0
	mb.setm(M.METAL, Mats.c("7a8088"), r.randf())
	for k in 3:
		var p := Vector3(room.rect.position.x + 0.3 + k * 0.35, 0, room.rect.position.y + 0.35)
		mb.cyl_y(Vector3(p.x, y0 + h * 0.5, p.z), 0.11, h, 8, false)
	mb.setm(M.METAL, Mats.c("a04a20"), r.randf())
	mb.cyl_y(Vector3(room.rect.position.x + 0.4, y0 + h * 0.5, room.rect.position.y + 1.0), 0.07, h, 6, false)

static func _storage(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var n := maxi(1, int(room.rect.size.x / 1.6))
	for i in n:
		mb.setm(M.METAL, Mats.c("8a9098"), r.randf())
		mb.box(Vector3(room.rect.position.x + (i + 0.5) * room.rect.size.x / n, y0 + 1.0,
			room.rect.get_center().y), Vector3(0.9, 2.0, 0.6))
	mb.setm(M.PLASTIC, Mats.c("9a7a50"), r.randf())
	for k in 3:
		mb.box(Vector3(room.rect.position.x + 0.6 + k * 0.5, y0 + 0.3, room.rect.end.y - 0.6), Vector3(0.45, 0.5, 0.45))

static func _bathroom(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var rect := room.rect
	mb.setm(M.TILE, Mats.c("cfc8ba"), r.randf())
	mb.prism(_rect(rect.grow(-0.04)), y0 + 0.25, y0 + 0.27, true, false)
	var stalls := maxi(1, int(rect.size.x / 1.1))
	for k in stalls:
		var x := rect.position.x + 0.15 + (k + 0.5) * (rect.size.x - 0.3) / stalls
		mb.setm(M.PLASTIC, Mats.c("b8b2a8"), r.randf())
		mb.box(Vector3(x, y0 + 1.0, rect.position.y + 0.7), Vector3(0.06, 2.0, 1.2))
		mb.setm(M.CERAMIC, Mats.c("f0eee8"), r.randf())
		mb.box(Vector3(x, y0 + 0.32, rect.position.y + 0.55), Vector3(0.42, 0.45, 0.6))
	# sinks + mirror
	mb.setm(M.CERAMIC, Mats.c("f0eee8"), r.randf())
	mb.box(Vector3(rect.get_center().x, y0 + 0.82, rect.end.y - 0.35), Vector3(minf(2.6, rect.size.x - 0.6), 0.16, 0.45))
	mb.setm(M.METAL, Mats.c("c8ced4"), r.randf())
	for k in 2:
		mb.cyl_y(Vector3(rect.get_center().x - 0.7 + k * 1.4, y0 + 1.0, rect.end.y - 0.35), 0.03, 0.2, 6, true)
	mb.setm(M.GLASS, Color(0.4, 0.45, 0.5), r.randf())
	mb.box(Vector3(rect.get_center().x, y0 + 1.6, rect.end.y - 0.12), Vector3(minf(2.4, rect.size.x - 0.8), 0.9, 0.04))

static func _living(mb: MB, room: Room, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var rect := room.rect
	var c := rect.get_center()
	mb.setm(M.FABRIC, Mats.c("6a3a48") if r.randf() < 0.5 else Mats.c("33404a"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.26, c.y), Vector3(minf(2.8, rect.size.x * 0.6), 0.03, minf(2.0, rect.size.y * 0.5)), true, false)
	_tv_wall(mb, rect, y0, r)
	_sofa(mb, Vector3(c.x, y0, c.y + rect.size.y * 0.22), r, 0.0)
	_coffee_table(mb, Vector3(c.x, y0, c.y - rect.size.y * 0.05), r)
	if r.randf() < 0.7:
		_shelf(mb, Vector3(rect.position.x + 0.4, y0, rect.position.y + 1.2), r)
	if r.randf() < 0.6:
		_planter(mb, Vector3(rect.end.x - 0.8, y0, rect.end.y - 0.8), r)
	if r.randf() < 0.4:
		# laptop + mug on the table = life trace
		mb.setm(M.PLASTIC, Mats.c("2a2e34"), r.randf())
		mb.box(Vector3(c.x + 0.2, y0 + 0.42, c.y - rect.size.y * 0.05), Vector3(0.34, 0.02, 0.24))
		mb.setm(M.CERAMIC, Mats.c("f0eee8"), r.randf())
		mb.cyl_y(Vector3(c.x - 0.3, y0 + 0.44, c.y - rect.size.y * 0.02), 0.04, 0.1, 8, true)

static func _tv_wall(mb: MB, rect: Rect2, y0: float, r: RandomNumberGenerator) -> void:
	mb.setm(M.SCREEN, Mats.c("203a60") if r.randf() < 0.6 else Mats.c("40202a"), r.randf(), 0.8)
	mb.box(Vector3(rect.get_center().x, y0 + 1.35, rect.position.y + 0.2), Vector3(1.5, 0.85, 0.07))
	mb.setm(M.METAL, Mats.c("1a1c20"), r.randf())
	mb.box(Vector3(rect.get_center().x, y0 + 0.85, rect.position.y + 0.26), Vector3(1.2, 0.06, 0.3))

static func _bedroom(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var rect := room.rect
	var c := rect.get_center()
	var w := minf(1.7, rect.size.x * 0.55)
	var d := minf(2.1, rect.size.y * 0.62)
	_bed(mb, Vector3(c.x, y0, c.y), w, d, r)
	# wardrobe
	mb.setm(M.WOOD, Mats.c("6a4a30") if r.randf() < 0.5 else Mats.c("d8d2c4"), r.randf())
	mb.box(Vector3(rect.position.x + 0.35, y0 + 1.1, rect.end.y - 0.5), Vector3(0.55, 2.2, 1.6))
	# desk + lamp
	if r.randf() < 0.7:
		mb.setm(M.WOOD, Mats.c("8a6a48"), r.randf())
		mb.box(Vector3(rect.end.x - 1.2, y0 + 0.72, rect.position.y + 0.5), Vector3(1.4, 0.06, 0.6))
		mb.setm(M.METAL, Mats.c("2a2e32"), r.randf())
		for sx in [-0.6, 0.6]:
			mb.box(Vector3(rect.end.x - 1.2 + sx, y0 + 0.36, rect.position.y + 0.5), Vector3(0.05, 0.72, 0.5))
		mb.setm(M.EMIT, Mats.c("ffcf90"), r.randf(), 0.7)
		mb.cyl_y(Vector3(rect.end.x - 1.7, y0 + 0.86, rect.position.y + 0.45), 0.1, 0.2, 8, true)

static func _bed(mb: MB, p: Vector3, w: float, d: float, r: RandomNumberGenerator) -> void:
	# real scale: mattress top at 0.55 m, frame 0.35 m, plinth recessed
	mb.setm(M.WOOD, Mats.c("4a3424"), r.randf())
	mb.box(p + Vector3(0, 0.11, 0), Vector3(w * 0.92, 0.22, d * 0.94))
	mb.box(p + Vector3(0, 0.34, 0), Vector3(w, 0.06, d))
	mb.setm(M.FABRIC, Mats.c("e8e2d6"), r.randf())
	mb.box(p + Vector3(0, 0.47, 0), Vector3(w - 0.10, 0.20, d - 0.10))
	mb.setm(M.FABRIC, Mats.c("6a7a8a") if r.randf() < 0.5 else Mats.c("8a5a4a"), r.randf())
	mb.box(p + Vector3(0, 0.60, -d * 0.22), Vector3(w - 0.06, 0.05, d * 0.44))
	mb.setm(M.FABRIC, Mats.c("e8e2d6"), r.randf())
	mb.box(p + Vector3(0, 0.60, d * 0.24), Vector3(w - 0.22, 0.08, d * 0.22))
	mb.setm(M.CERAMIC, Mats.c("f4f0e8"), r.randf())
	mb.box(p + Vector3(-w * 0.22, 0.60, -d * 0.40), Vector3(w * 0.30, 0.09, 0.30))
	mb.box(p + Vector3(w * 0.22, 0.60, -d * 0.40), Vector3(w * 0.30, 0.09, 0.30))
	# headboard
	mb.setm(M.WOOD, Mats.c("5a4030"), r.randf())
	mb.box(p + Vector3(0, 0.55, -d * 0.5 - 0.04), Vector3(w, 0.6, 0.07))

static func _kitchen(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var rect := room.rect
	var horiz := rect.size.x > rect.size.y
	var len := rect.size.x * 0.8 if horiz else rect.size.y * 0.8
	var c := Vector3(rect.get_center().x, y0, rect.position.y + 0.35) if horiz else Vector3(rect.position.x + 0.35, y0, rect.get_center().y)
	mb.setm(M.WOOD, Mats.c("7a5a3a") if r.randf() < 0.5 else Mats.c("e0dcd2"), r.randf())
	mb.box(c + Vector3(0, 0.45, 0), Vector3(len, 0.9, 0.62) if horiz else Vector3(0.62, 0.9, len))
	mb.setm(M.METAL, Mats.c("b8bec4"), r.randf())
	mb.box(c + Vector3(0, 0.92, 0), Vector3(len + 0.06, 0.05, 0.66) if horiz else Vector3(0.66, 0.05, len + 0.06))
	mb.setm(M.CERAMIC, Mats.c("e8e8e8"), r.randf())
	mb.box(c + Vector3(-len * 0.2, 1.0, -0.02), Vector3(0.5, 0.06, 0.4) if horiz else Vector3(0.4, 0.06, 0.5))
	# hob
	mb.setm(M.PLASTIC, Mats.c("1a1c20"), r.randf())
	mb.box(c + Vector3(len * 0.22, 0.96, 0), Vector3(0.6, 0.03, 0.45) if horiz else Vector3(0.45, 0.03, 0.6))
	# fridge
	mb.setm(M.METAL, Mats.c("c8ced4"), r.randf())
	mb.box(Vector3(rect.end.x - 0.5, y0 + 0.9, rect.end.y - 0.5), Vector3(0.7, 1.8, 0.7))
	# wall cabinets
	mb.setm(M.WOOD, Mats.c("7a5a3a"), r.randf())
	mb.box(c + Vector3(0, 1.9, 0) + Vector3(0, 0, -0.15), Vector3(len * 0.8, 0.7, 0.35) if horiz else Vector3(0.35, 0.7, len * 0.8))

static func _hotel_room(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var rect := room.rect
	var c := rect.get_center()
	_bed(mb, Vector3(c.x, y0, c.y + 0.3), minf(1.8, rect.size.x * 0.7), minf(2.0, rect.size.y * 0.55), r)
	mb.setm(M.WOOD, Mats.c("4a3222"), r.randf())
	var nx := c.x + rect.size.x * 0.32
	mb.box(Vector3(nx, y0 + 0.3, c.y - rect.size.y * 0.15), Vector3(0.4, 0.6, 0.4))
	mb.setm(M.EMIT, Mats.c("ffcf90"), r.randf(), 0.8)
	mb.cyl_y(Vector3(nx, y0 + 0.7, c.y - rect.size.y * 0.15), 0.12, 0.2, 8, true)
	mb.setm(M.SCREEN, Mats.c("203a60"), r.randf())
	mb.box(Vector3(c.x, y0 + 1.35, rect.position.y + 0.25), Vector3(1.1, 0.62, 0.06))
	# suitcase + tray = life traces
	if r.randf() < 0.6:
		mb.setm(M.PLASTIC, Mats.c("40202a") if r.randf() < 0.5 else Mats.c("2a3038"), r.randf())
		mb.box(Vector3(rect.end.x - 0.8, y0 + 0.35, rect.end.y - 0.8), Vector3(0.6, 0.7, 0.4))
	mb.setm(M.CERAMIC, Mats.c("e8e4dc"), r.randf())
	mb.cyl_y(Vector3(c.x - rect.size.x * 0.28, y0 + 0.78, c.y - rect.size.y * 0.2), 0.16, 0.04, 10, true)
	# bathroom cubicle
	var bw := minf(2.0, rect.size.x * 0.45)
	mb.setm(M.WALL, Mats.c("cfc8ba"), r.randf(), 0.0, 52.0)
	mb.box(Vector3(rect.end.x - bw * 0.5, y0 + 1.2, rect.end.y - 0.1), Vector3(bw, 2.4, 0.1))
	mb.setm(M.CERAMIC, Mats.c("f0eee8"), r.randf())
	mb.box(Vector3(rect.end.x - 0.45, y0 + 0.35, rect.end.y - 0.5), Vector3(0.4, 0.5, 0.6))

static func _classroom(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var rect := room.rect
	var nx := maxi(2, int(rect.size.x / 1.7))
	var nz := maxi(2, int(rect.size.y / 1.8))
	for i in nx:
		for j in nz:
			if r.randf() < 0.1:
				continue
			var p := Vector3(rect.position.x + 0.9 + i * (rect.size.x - 1.6) / nx, y0,
				rect.position.y + 1.3 + j * (rect.size.y - 2.4) / nz)
			mb.setm(M.WOOD, Mats.c("9a7a4a"), r.randf())
			mb.box(p + Vector3(0, 0.68, 0), Vector3(1.1, 0.06, 0.55))
			mb.setm(M.METAL, Mats.c("3a3e44"), r.randf())
			mb.box(p + Vector3(0, 0.34, 0), Vector3(0.05, 0.68, 0.45))
			_box_chair(mb, p + Vector3(0, 0, 0.55), r)
	# blackboard
	mb.setm(M.PLASTIC, Mats.c("1c2a20"), r.randf())
	mb.box(Vector3(rect.get_center().x, y0 + 1.6, rect.position.y + 0.12), Vector3(minf(rect.size.x - 1.0, 3.4), 1.3, 0.07))
	mb.setm(M.WOOD, Mats.c("6a4a30"), r.randf())
	mb.box(Vector3(rect.get_center().x, y0 + 0.45, rect.position.y + 0.3), Vector3(1.7, 0.9, 0.6))
	# papers on desks
	mb.setm(M.PLASTIC, Mats.c("f0eee8"), r.randf())
	for k in 3:
		mb.box(Vector3(rect.position.x + 1.2 + r.randf() * (rect.size.x - 2.4), y0 + 0.72,
			rect.position.y + 1.6 + r.randf() * (rect.size.y - 2.8)), Vector3(0.3, 0.01, 0.22))

static func _lab(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var c := room.rect.get_center()
	mb.setm(M.CERAMIC, Mats.c("e8e4dc"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.78, c.y), Vector3(minf(3.0, room.rect.size.x * 0.7), 0.08, 0.9))
	mb.setm(M.METAL, Mats.c("3a3e44"), r.randf())
	mb.box(Vector3(c.x, y0 + 0.39, c.y), Vector3(2.6, 0.78, 0.7))
	mb.setm(M.GLASS, Color(0.3, 0.45, 0.5), r.randf())
	for k in 4:
		mb.cyl_y(Vector3(c.x - 1.0 + k * 0.65, y0 + 0.95, c.y), 0.09, 0.24, 8, true)
	mb.setm(M.SCREEN, Mats.c("2a8a6a"), r.randf())
	mb.box(Vector3(room.rect.end.x - 0.9, y0 + 1.4, room.rect.position.y + 0.4), Vector3(0.7, 0.5, 0.06))

static func _staff(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	mb.setm(M.WOOD, Mats.c("8a6a48"), r.randf())
	mb.box(Vector3(room.rect.get_center().x, y0 + 0.72, room.rect.get_center().y), Vector3(1.5, 0.06, 0.8))
	_box_chair(mb, Vector3(room.rect.get_center().x, y0, room.rect.get_center().y + 0.7), r)
	mb.setm(M.METAL, Mats.c("5a6068"), r.randf())
	mb.box(Vector3(room.rect.end.x - 0.4, y0 + 1.0, room.rect.end.y - 0.4), Vector3(0.5, 2.0, 0.5))

static func _retail(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var rows := maxi(1, int(room.rect.size.y / 3.4))
	for k in rows:
		var z := room.rect.position.y + 1.8 + (k + 0.5) * (room.rect.size.y - 3.0) / rows
		var len := room.rect.size.x * 0.6
		mb.setm(M.METAL, Mats.c("6a7076"), r.randf())
		mb.box(Vector3(room.rect.get_center().x, y0 + 0.85, z), Vector3(len, 0.08, 0.9))
		mb.box(Vector3(room.rect.get_center().x, y0 + 0.45, z), Vector3(len, 0.08, 0.9))
		for s in [-1, 1]:
			mb.box(Vector3(room.rect.get_center().x + s * len * 0.5, y0 + 0.9, z), Vector3(0.05, 1.8, 0.9))
		var n := int(len / 0.55)
		for i in n:
			if r.randf() < 0.2:
				continue
			var px := room.rect.get_center().x - len * 0.5 + 0.3 + i * 0.55
			for row in 2:
				mb.setm(M.PLASTIC, _prod(r), r.randf())
				mb.box(Vector3(px, y0 + 0.55 + row * 0.42 + 0.12, z), Vector3(0.32, 0.22, 0.5))
	mb.setm(M.WOOD, Mats.c("7a5a3a"), r.randf())
	mb.box(Vector3(room.rect.position.x + 1.0, y0 + 0.55, room.rect.position.y + 0.9), Vector3(2.0, 1.1, 1.0))

static func _hall(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var rows := maxi(1, int(room.rect.size.y / 6.0))
	for k in rows:
		var z := room.rect.position.y + 2.0 + k * 5.5
		mb.setm(M.METAL, Mats.c("c07020"), r.randf())
		for lvl in 3:
			mb.box(Vector3(room.rect.get_center().x, y0 + 0.8 + lvl * 1.5, z), Vector3(room.rect.size.x * 0.7, 0.1, 1.0))
		mb.setm(M.PLASTIC, Mats.c("9a7a50"), r.randf())
		for i in 4:
			mb.box(Vector3(room.rect.position.x + 2.0 + i * 3.0, y0 + 0.6, z), Vector3(1.0, 0.8, 0.9))

static func _parking(mb: MB, room: Room, y0: float, r: RandomNumberGenerator) -> void:
	var rows := maxi(1, int(room.rect.size.y / 6.0))
	for k in rows:
		var z := room.rect.position.y + 2.0 + k * 6.0
		var n := int(room.rect.size.x / 2.8)
		for i in n:
			var px := room.rect.position.x + 1.2 + i * 2.8
			mb.setm(M.ROADPAINT, Mats.c("d8d8d0"), r.randf())
			mb.box(Vector3(px, y0 + 0.27, z), Vector3(0.08, 0.02, 5.0), true, false)
			if r.randf() < 0.5:
				_park_car(mb, Vector3(px, y0, z + 1.0), r)

static func _park_car(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
	var cols := ["20242a", "3a3f46", "6a2028", "1a3048", "4a4a4a", "8a8a80"]
	mb.setm(M.PLASTIC, Mats.c(cols[r.randi() % cols.size()]), r.randf())
	mb.box(p + Vector3(0, 0.6, 0), Vector3(1.8, 0.55, 4.2))
	mb.box(p + Vector3(0, 1.0, -0.2), Vector3(1.6, 0.5, 2.2))
	mb.setm(M.GLASS, Color(0.12, 0.16, 0.2), r.randf())
	mb.box(p + Vector3(0, 1.02, -0.2), Vector3(1.62, 0.34, 2.0))

# ------------------------------------------------------------------ furniture kit

static func _workstation(mb: MB, p: Vector3, r: RandomNumberGenerator, rot: float) -> void:
	mb.push(Transform3D(Basis(Vector3.UP, rot), p))
	mb.setm(M.WOOD, Mats.c("a08458") if r.randf() < 0.6 else Mats.c("d8d2c4"), r.randf())
	mb.box(Vector3(0, 0.74, 0), Vector3(1.6, 0.04, 0.8))
	mb.setm(M.METAL, Mats.c("3a3e44"), r.randf())
	for sx in [-0.72, 0.72]:
		mb.box(Vector3(sx, 0.37, 0), Vector3(0.04, 0.74, 0.72))
	mb.box(Vector3(0, 0.70, -0.36), Vector3(1.5, 0.30, 0.03))
	mb.setm(M.SCREEN, Mats.c("4a90c0") if r.randf() < 0.6 else Mats.c("2a6a4a"), r.randf())
	mb.box(Vector3(0, 1.02, -0.14), Vector3(0.60, 0.34, 0.03))
	mb.setm(M.METAL, Mats.c("2a2e32"), r.randf())
	mb.box(Vector3(0, 0.86, -0.14), Vector3(0.06, 0.14, 0.06))
	mb.setm(M.PLASTIC, Mats.c("1a1c20"), r.randf())
	mb.box(Vector3(0, 0.77, 0.06), Vector3(0.42, 0.015, 0.16))
	_box_chair(mb, Vector3(0, 0, 0.78), r)
	if r.randf() < 0.45:
		mb.setm(M.FABRIC, Mats.c("4a4f58"), r.randf())
		mb.box(Vector3(0, 1.20, -0.58), Vector3(1.6, 0.85, 0.03))
	mb.setm(M.PLASTIC, Mats.c("f0eee8"), r.randf())
	if r.randf() < 0.6:
		mb.box(Vector3(0.30, 0.765, 0.08), Vector3(0.26, 0.008, 0.20))
	if r.randf() < 0.4:
		mb.cyl_y(Vector3(-0.45, 0.79, 0.06), 0.033, 0.09, 6, true)
	mb.pop()

static func _box_chair(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.PLASTIC, Mats.c("232830"), r.randf())
	mb.box(p + Vector3(0, 0.45, 0), Vector3(0.48, 0.06, 0.48))
	mb.box(p + Vector3(0, 0.72, 0.23), Vector3(0.46, 0.48, 0.05))
	mb.setm(M.METAL, Mats.c("3a3e44"), r.randf())
	mb.cyl_y(p + Vector3(0, 0.22, 0), 0.035, 0.40, 6, true)

static func _sofa(mb: MB, p: Vector3, r: RandomNumberGenerator, rot: float) -> void:
	mb.setm(M.FABRIC, Mats.c("5a2a38") if r.randf() < 0.5 else Mats.c("2a3a4a"), r.randf())
	mb.box(p + Vector3(0, 0.40, 0), Vector3(2.0, 0.22, 0.88))
	mb.box(p + Vector3(0, 0.62, 0.30), Vector3(2.0, 0.52, 0.20))
	for sx in [-0.92, 0.92]:
		mb.box(p + Vector3(sx, 0.52, 0.0), Vector3(0.16, 0.34, 0.88))
	mb.setm(M.WOOD, Mats.c("4a3222"), r.randf())
	for sx in [-0.85, 0.85]:
		for sz in [-0.32, 0.32]:
			mb.box(p + Vector3(sx, 0.14, sz), Vector3(0.08, 0.28, 0.08))

static func _coffee_table(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.WOOD, Mats.c("6a4a30"), r.randf())
	mb.box(p + Vector3(0, 0.40, 0), Vector3(1.0, 0.05, 0.6))
	mb.setm(M.METAL, Mats.c("2a2e32"), r.randf())
	for sx in [-0.3, 0.3]:
		mb.box(p + Vector3(sx, 0.20, 0), Vector3(0.04, 0.40, 0.5))

static func _shelf(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.WOOD, Mats.c("4a3020"), r.randf())
	mb.box(p + Vector3(0, 0.95, 0), Vector3(0.4, 1.9, 1.4))
	mb.setm(M.PLASTIC, _prod(r), r.randf())
	for k in 5:
		mb.box(p + Vector3(0.24, 0.35 + (k % 4) * 0.4, -0.4 + (k % 3) * 0.4), Vector3(0.25, 0.22, 0.2))

static func _armchair(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
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

static func _prod(r: RandomNumberGenerator) -> Color:
	var cols := ["d03050", "30a0d0", "d0a030", "40b060", "a040c0", "e0e0d8", "203040"]
	return Mats.c(cols[r.randi() % cols.size()])