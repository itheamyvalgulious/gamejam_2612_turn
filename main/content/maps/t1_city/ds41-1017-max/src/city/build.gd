## Building geometry generator.
##   shell()  : whole-city LOD, merged per chunk (extruded footprint + trim + signs)
##   mid()    : per-chunk mid LOD, adds rooftop clutter and street-level bands
##   full()   : detailed LOD, real window openings for low floors, shopfronts,
##              balconies, fins, cornices, rooftop equipment, neon.
class_name Builder
extends RefCounted

static var plan: CityPlan

const WALL_COLS := ["8f8778", "9c9282", "7f7b74", "b3a894", "6e6b66", "a39584",
	"8a7e6e", "b8b0a0", "77736e", "9a8f80", "c2b8a4", "5e5a56", "a89a86", "d0c6b2",
	"6a625a", "b0a08a"]
const BRICK_COLS := ["7c4a36", "8a5740", "6d4130", "96634a", "5f3a2e", "a06b50"]
const METAL_COLS := ["8b939e", "6d747d", "9aa1a6", "5c636c", "7d848a"]
const TILE_COLS := ["4a5058", "3e444c", "565c64"]
const ROOF_COLS := ["3a3a38", "33343a", "42423c", "3c3a34", "2e3034"]
const GLASS_TINT := Color(0.14, 0.20, 0.24)

static func setup(p: CityPlan) -> void:
	plan = p

static func wall_col(b: CityPlan.Bld) -> Color:
	var r := H.rng(int(b.sd * 99991), b.id)
	if b.style == M.STY_BRICK:
		return Mats.jitter(r, Mats.c(BRICK_COLS[r.randi() % BRICK_COLS.size()]), 0.05)
	if b.style == M.STY_CURTAIN:
		var glass_cols := ["5a6a72", "4a5a62", "6a5a4a", "3a4a54", "5a4a52", "46545c"]
		return Mats.jitter(r, Mats.c(glass_cols[r.randi() % glass_cols.size()]), 0.05)
	if b.style == M.STY_FINS:
		var fin_cols := ["8b939e", "6d747d", "9aa1a6", "5c636c", "7d848a", "a89a86"]
		return Mats.jitter(r, Mats.c(fin_cols[r.randi() % fin_cols.size()]), 0.05)
	return Mats.jitter(r, Mats.c(WALL_COLS[r.randi() % WALL_COLS.size()]), 0.06)

static func roof_col(b: CityPlan.Bld) -> Color:
	var r := H.rng(b.id, 551)
	return Mats.jitter(r, Mats.c(ROOF_COLS[r.randi() % ROOF_COLS.size()]), 0.06)

static func floor_h(b: CityPlan.Bld) -> float:
	var v := 0.88 + 0.24 * H.f(b.id, 71)
	match b.kind:
		CityPlan.K_WAREHOUSE, CityPlan.K_FACTORY:
			return 6.0
		CityPlan.K_MALL:
			return 5.6
		CityPlan.K_OFFICE, CityPlan.K_TOWER:
			return 3.9 * v
		_:
			return 3.25 * v

static func bay_w(b: CityPlan.Bld) -> float:
	var v := 0.82 + 0.36 * H.f(b.id, 83)
	match b.style:
		M.STY_CURTAIN:
			return 1.62 * v
		M.STY_FINS:
			return 2.1 * v
		M.STY_RIBBON:
			return 2.8 * v
		M.STY_BRICK:
			return 3.3 * v
		M.STY_INDUSTRIAL:
			return 6.0 * v
		M.STY_SHOPFRONT:
			return 4.2 * v
		_:
			return 2.7 * v

## Stepped massing: returns [{poly, y0, y1}] with setbacks for tall buildings.
static func sections(b: CityPlan.Bld) -> Array:
	var out := []
	var base_y := 0.16
	var poly := b.poly
	if b.podium > 0.0 and b.h > b.podium + 12.0:
		out.append({"poly": poly, "y0": base_y, "y1": b.podium})
		var shaft := Poly.inset(poly, maxf(2.0, minf(6.0, b.tower_scale * 6.0)))
		if shaft.size() >= 3:
			poly = shaft
		var t0 := b.podium
		var cuts := [0.0]
		if b.h > 160.0:
			cuts = [0.55, 0.82]
		elif b.h > 90.0:
			cuts = [0.68]
		var prev := t0
		for c in cuts:
			var yy: float = b.podium + (b.h - t0) * c
			out.append({"poly": poly, "y0": prev, "y1": yy})
			var np := Poly.inset(poly, 2.5)
			if np.size() >= 3:
				poly = np
			prev = yy
		out.append({"poly": poly, "y0": prev, "y1": b.h})
	elif b.h > 58.0:
		var cut: float = b.h * (0.58 + 0.18 * H.f(b.id, 17))
		out.append({"poly": poly, "y0": base_y, "y1": cut})
		var np2 := Poly.inset(poly, 2.2 + 2.0 * H.f(b.id, 29))
		if np2.size() >= 3:
			poly = np2
		if b.h > 130.0:
			var cut2: float = cut + (b.h - cut) * 0.62
			out.append({"poly": poly, "y0": cut, "y1": cut2})
			var np3 := Poly.inset(poly, 2.0)
			if np3.size() >= 3:
				poly = np3
			out.append({"poly": poly, "y0": cut2, "y1": b.h})
		else:
			out.append({"poly": poly, "y0": cut, "y1": b.h})
	else:
		out.append({"poly": poly, "y0": base_y, "y1": b.h})
	return out

# ---------------------------------------------------------------- LANDMARKS

## detail: 0 far, 1 mid, 2 near, 3 full. Returns true when handled.
static func _landmark(b: CityPlan.Bld, mb: MB, detail: int) -> bool:
	match b.kind:
		CityPlan.K_TWIST:
			mb.push(Transform3D(Basis(), Vector3(b.cx, 0, b.cz)))
			Landmarks.twist(b, mb, detail >= 2)
			mb.pop()
			return true
		CityPlan.K_COOLING:
			mb.push(Transform3D(Basis(), Vector3(b.cx, 0, b.cz)))
			Landmarks.cooling(b, mb, detail >= 2)
			mb.pop()
			return true
		CityPlan.K_WHEEL:
			# the ferris wheel is a live rotating node owned by the world
			return true
	return false

# ---------------------------------------------------------------- FAR LOD

## Cheap whole-city silhouette: one extruded prism per building.
static func far(b: CityPlan.Bld, mb: MB) -> void:
	if _landmark(b, mb, 0):
		return
	var wc := wall_col(b)
	mb.setm(M.WALL, wc, b.sd, 0.0, b.style)
	var secs := sections(b)
	for sec in secs:
		mb.prism(sec["poly"], sec["y0"], sec["y1"], true, false)
	# roof cap in a dark roofing material (never the facade colour)
	mb.setm(M.CONCRETE, roof_col(b) * 0.75, b.sd)
	mb.prism(secs[secs.size() - 1]["poly"], b.h, b.h + 0.05, true, false)
	if b.h > 55.0:
		var r := H.rng(b.id, 21)
		var bb := Poly.bbox(b.poly)
		var s := clampf(minf(bb.size.x, bb.size.y) * 0.3, 1.5, 7.0)
		mb.box(Vector3(b.cx, b.h + s * 0.4, b.cz), Vector3(s, s * 0.8, s * 0.8))

# ---------------------------------------------------------------- SHELL LOD

static func shell(b: CityPlan.Bld, mb: MB) -> void:
	if _landmark(b, mb, 1):
		return
	var wc := wall_col(b)
	var rc := roof_col(b)
	var style := b.style
	var top := b.h
	var secs := sections(b)
	for si in secs.size():
		var sec: Dictionary = secs[si]
		var pc: Color = wc if si == 0 else wc * (0.94 + 0.1 * si)
		mb.setm(M.WALL, pc, b.sd, 0.0, style)
		mb.prism(sec["poly"], sec["y0"], sec["y1"], false, false)
		# ledge at each setback
		if si < secs.size() - 1:
			mb.setm(M.CONCRETE, Mats.jitter(H.rng(b.id, si + 3), Mats.c("9a968c"), 0.05), b.sd)
			var ledge := Poly.inset(sec["poly"], 0.3)
			if ledge.size() >= 3:
				mb.prism(ledge, sec["y1"] - 0.1, sec["y1"] + 0.5, true, false)
	# roof cap in a dark roofing material
	var tpoly: PackedVector2Array = secs[secs.size() - 1]["poly"]
	mb.setm(M.CONCRETE, roof_col(b) * 0.8, b.sd)
	mb.prism(tpoly, b.h, b.h + 0.06, true, false)
	# parapet ring (never a filled lid)
	mb.setm(M.CONCRETE, Mats.jitter(H.rng(b.id, 3), Mats.c("8a8880"), 0.05), b.sd)
	var pr := Poly.inset(tpoly, 0.35)
	if pr.size() >= 3:
		mb.prism(pr, top, top + 0.75, false, false)
		_ring(mb, tpoly, pr, top + 0.75)
	# rooftop mass
	mb.setm(M.CONCRETE, rc, b.sd)
	var c := Vector2(b.cx, b.cz)
	var bb := Poly.bbox(b.poly)
	var r := H.rng(b.id, 77)
	var sz := minf(bb.size.x, bb.size.y)
	var rw := clampf(sz * 0.28, 1.5, 6.0)
	var rh := clampf(b.h * 0.012, 0.8, 4.5)
	mb.box(Vector3(c.x + r.randf_range(-2, 2), top + 0.2 + rh * 0.5, c.y + r.randf_range(-2, 2)),
		Vector3(rw, rh, rw * r.randf_range(0.6, 1.4)))
	if b.h > 110.0:
		# antenna / spire
		mb.setm(M.METAL, Mats.c("5a6068"))
		var sp := clampf(b.h * 0.1, 6.0, 34.0)
		mb.box(Vector3(c.x, top + sp * 0.5, c.y), Vector3(0.7, sp, 0.7))
		mb.setm(M.EMIT, Mats.c("ff2a2a"), 0.5, 2.0)
		mb.box(Vector3(c.x, top + sp, c.y), Vector3(0.9, 0.6, 0.9))
	# shell-level signs
	if b.kind == CityPlan.K_MALL or b.kind == CityPlan.K_SHOP or b.style >= 0:
		_shell_sign(b, mb, c, bb, wc)

static func _shell_sign(b: CityPlan.Bld, mb: MB, c: Vector2, bb: Rect2, wc: Color) -> void:
	var r := H.rng(b.id, 991)
	if b.h < 12.0:
		return
	if b.district != CityPlan.COMMERCIAL and b.district != CityPlan.CBD and r.randf() > 0.25:
		return
	var dirs := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	var d: Vector2 = dirs[r.randi() % 4]
	var half := 0.0
	if absf(d.x) > 0.5:
		half = bb.size.x * 0.5
	else:
		half = bb.size.y * 0.5
	var y := 6.0 + r.randf() * minf(18.0, b.h * 0.4)
	var p := c + d * (half + 0.2)
	var w := r.randf_range(2.0, 4.5)
	var hh := r.randf_range(4.0, 12.0)
	if b.h < y + hh:
		hh = maxf(2.0, b.h - y - 1.0)
	var col := _neon(r)
	mb.setm(M.EMIT, col, r.randf(), 2.2)
	var side := Vector2(-d.y, d.x)
	# double-sided vertical sign blade
	var a := Vector3(p.x, y, p.y)
	var bs := Vector3(side.x, 0, side.y) * w * 0.5
	mb.quad(a - bs, a + bs, a + bs + Vector3(0, hh, 0), a - bs + Vector3(0, hh, 0))
	mb.quad(a + bs, a - bs, a - bs + Vector3(0, hh, 0), a + bs + Vector3(0, hh, 0))
	mb.setm(M.METAL, Mats.c("2a2c30"))
	mb.box(Vector3(p.x, y + hh * 0.5, p.y), Vector3(0.18, hh, 0.18))

static func _neon(r: RandomNumberGenerator) -> Color:
	var cols := ["ff2f7a", "2ff5ff", "ffb02f", "8f2fff", "2fff8f", "ff4a2f", "4aa8ff", "ffe32f"]
	return Mats.c(cols[r.randi() % cols.size()])

# ---------------------------------------------------------------- MID LOD

static func mid(b: CityPlan.Bld, mb: MB) -> void:
	if _landmark(b, mb, 2):
		return
	shell(b, mb)
	var r := H.rng(b.id, 131)
	var top := b.h
	var bb := Poly.bbox(b.poly)
	var c := Vector2(b.cx, b.cz)
	# rooftop clutter cluster
	var n := 3 + r.randi() % 6
	for i in n:
		var px := c.x + r.randf_range(-bb.size.x * 0.36, bb.size.x * 0.36)
		var pz := c.y + r.randf_range(-bb.size.y * 0.36, bb.size.y * 0.36)
		var s := r.randf_range(1.0, 3.4)
		mb.setm(M.METAL, Mats.c("8a9096") if r.randf() < 0.6 else Mats.c("4a4e52"), b.sd)
		mb.box(Vector3(px, top + s * 0.5 + 0.2, pz), Vector3(s, s * r.randf_range(0.5, 1.3), s * r.randf_range(0.6, 1.5)))
		if r.randf() < 0.5:
			mb.setm(M.METAL, Mats.c("2a2e32"), b.sd)
			mb.cyl_y(Vector3(px, top + s + 0.24, pz), s * 0.28, 0.05, 8, true)
	# roof membrane patches / gravel / puddles
	mb.setm(M.SOIL, Mats.c("3a362e"), b.sd)
	for i in 4:
		var px2 := c.x + r.randf_range(-bb.size.x * 0.34, bb.size.x * 0.34)
		var pz2 := c.y + r.randf_range(-bb.size.y * 0.34, bb.size.y * 0.34)
		var s2 := r.randf_range(2.0, 5.0)
		mb.box(Vector3(px2, top + 0.16, pz2), Vector3(s2, 0.04, s2 * r.randf_range(0.5, 1.2)), true, false)
	# parapet ring
	mb.setm(M.CONCRETE, Mats.c("9a958c"), b.sd)
	var pr2 := Poly.inset(b.poly, 0.4)
	if pr2.size() >= 3:
		mb.prism(pr2, top + 0.02, top + 0.8, false, false)
	# stair / lift overrun
	if r.randf() < 0.7:
		mb.setm(M.CONCRETE, Mats.c("8e8a82"), b.sd)
		var s3 := minf(4.5, minf(bb.size.x, bb.size.y) * 0.3)
		mb.box(Vector3(c.x + r.randf_range(-2, 2), top + s3 * 0.45, c.y + r.randf_range(-2, 2)),
			Vector3(s3, s3 * 0.9, s3))
	# antenna mast
	if b.h > 40.0:
		mb.setm(M.METAL, Mats.c("5a6068"), b.sd)
		var mh := clampf(b.h * 0.06, 3.0, 16.0)
		mb.cyl_y(Vector3(c.x, top + mh * 0.5, c.y), 0.12, mh, 5, true)
		mb.setm(M.EMIT, Mats.c("ff2030"), 0.4, 2.0)
		mb.box(Vector3(c.x, top + mh, c.y), Vector3(0.3, 0.3, 0.3))
	# water tank on residential
	if b.kind == CityPlan.K_APARTMENT and r.randf() < 0.55:
		mb.setm(M.WOOD, Mats.c("5a4530"), b.sd)
		var tankp := Vector3(c.x + r.randf_range(-3, 3), top + 3.0, c.y + r.randf_range(-3, 3))
		mb.cyl_y(tankp, 1.6, 2.4, 12, true)
		mb.setm(M.METAL, Mats.c("4a4e52"))
		mb.box(Vector3(tankp.x, top + 1.1, tankp.z), Vector3(2.0, 2.2, 2.0), false, false)
	# helipad on tall towers
	if b.h > 150.0 and r.randf() < 0.4:
		mb.setm(M.CONCRETE, Mats.c("3e4246"))
		mb.cyl_y(Vector3(c.x, top + 0.55, c.y), minf(bb.size.x, bb.size.y) * 0.32, 0.5, 20, true)
		mb.setm(M.ROADPAINT, Mats.c("d8d8d0"), 0.3, 0.2)
		mb.cyl_y(Vector3(c.x, top + 0.83, c.y), 0.5, 0.02, 8, true)
		mb.box(Vector3(c.x, top + 0.83, c.y + 0.0), Vector3(0.4, 0.03, 9.0))
		mb.box(Vector3(c.x, top + 0.83, c.y + 0.0), Vector3(9.0, 0.03, 0.4))

# ---------------------------------------------------------------- FULL LOD

static func full(b: CityPlan.Bld, mb: MB) -> void:
	if _landmark(b, mb, 3):
		return
	var top := b.h
	var fh := floor_h(b)
	var wc := wall_col(b)
	var style := b.style
	var secs := sections(b)
	var detail_top := 26.0
	if b.kind == CityPlan.K_WAREHOUSE or b.kind == CityPlan.K_FACTORY or b.kind == CityPlan.K_MALL:
		detail_top = top
	var y_ground := 5.0
	if b.kind == CityPlan.K_WAREHOUSE or b.kind == CityPlan.K_FACTORY:
		y_ground = 7.5
	if b.kind == CityPlan.K_MALL:
		y_ground = 7.0
	var first_poly: PackedVector2Array = secs[0]["poly"]
	for si in secs.size():
		var sec: Dictionary = secs[si]
		var poly: PackedVector2Array = sec["poly"]
		var sy0: float = sec["y0"]
		var sy1: float = sec["y1"]
		var sec_wc: Color = wc if si == 0 else wc * (0.94 + 0.1 * si)
		var y := sy0
		if si == 0:
			_ground_floor(b, mb, poly, sy0, minf(sy0 + y_ground, sy1), wc, style)
			y = minf(sy0 + y_ground, sy1)
		var lim := minf(sy1, detail_top)
		while y < lim - 0.35:
			var yy := minf(y + fh, lim)
			_facade_floor(b, mb, poly, y, yy, sec_wc, style)
			y = yy
		if sy1 > y + 0.25:
			mb.setm(M.WALL, sec_wc, b.sd, 0.0, style)
			mb.prism(poly, y, sy1, false, false)
			var core := Poly.inset(poly, 0.9)
			if core.size() >= 3:
				mb.setm(M.CONCRETE, Mats.c("181a1e"), b.sd)
				mb.prism(core, y, sy1 - 0.2, true, false)
		if si < secs.size() - 1:
			# setback ledge / cornice
			mb.setm(M.CONCRETE, Mats.jitter(H.rng(b.id, si + 11), Mats.c("a29c90"), 0.05), b.sd)
			var ledge := Poly.inset(poly, 0.28)
			if ledge.size() >= 3:
				mb.prism(ledge, sy1 - 0.12, sy1 + 0.55, true, false)
	# parapet
	var tpoly: PackedVector2Array = secs[secs.size() - 1]["poly"]
	mb.setm(M.CONCRETE, Mats.jitter(H.rng(b.id, 9), Mats.c("94918a"), 0.06), b.sd)
	var pr := Poly.inset(tpoly, 0.25)
	if pr.size() >= 3:
		mb.prism(pr, top, top + 0.85, false, false)
		_ring(mb, tpoly, pr, top + 0.85)
		mb.prism(Poly.inset(tpoly, 0.05), top - 0.12, top + 0.14, false, false)
	_roof(b, mb, tpoly, top)
	_details(b, mb, first_poly, top, wc, y_ground)
	if (b.kind == CityPlan.K_APARTMENT or b.kind == CityPlan.K_OFFICE) and b.h > 12.0 \
			and H.f(b.id, 41) < 0.28 and b.style != M.STY_CURTAIN:
		_fire_escape(b, mb, first_poly, fh, y_ground)

## Encode the glass "style" (alpha class) in the style slot of the material params.
static func sty_glass(mb: MB, v: float) -> void:
	mb.sty = v

static func _facade_floor(b: CityPlan.Bld, mb: MB, poly: PackedVector2Array,
		y0: float, y1: float, wc: Color, style: float) -> void:
	var fh := y1 - y0
	if fh < 0.6:
		return
	var bay := maxf(bay_w(b), 1.1)
	var n := poly.size()
	var r := H.rng(b.id, int(y0 * 10.0))
	# floor character: 0 normal, 1 blank wall, 2 ribbon glazing
	var fmode := H.f(b.id, int(y0 * 7.0), 13) * 10.0
	var blank := fmode < 1.6
	var ribbon := fmode > 9.2
	# wall base + top spandrel bands
	var wall_style := 50.0 + style
	for i in n:
		var a := poly[i]
		var e := poly[(i + 1) % n] - a
		var L := e.length()
		if L < 0.5:
			continue
		var dir := e / L
		var outward := Vector3(e.y, 0, -e.x) / L
		var nb := maxi(1, int(round(L / bay)))
		var bw := L / nb
		var base := Vector3(a.x, 0, a.y)
		var th := Vector3(dir.x, 0, dir.y)
		# spandrel below window
		mb.setm(M.WALL, wc, b.sd, 0.0, wall_style)
		mb.quad(base + Vector3(0, y0, 0), base + th * L + Vector3(0, y0, 0),
			base + th * L + Vector3(0, y0 + 0.85, 0), base + Vector3(0, y0 + 0.85, 0))
		# solid band above window
		var wy1 := y0 + fh - 0.45
		mb.quad(base + Vector3(0, wy1, 0), base + th * L + Vector3(0, wy1, 0),
			base + th * L + Vector3(0, y1, 0), base + Vector3(0, y1, 0))
		if blank:
			mb.setm(M.WALL, wc, b.sd, 0.0, wall_style)
			mb.quad(base + Vector3(0, y0 + 0.85, 0), base + th * L + Vector3(0, y0 + 0.85, 0),
				base + th * L + Vector3(0, y0 + fh - 0.45, 0), base + Vector3(0, y0 + fh - 0.45, 0))
			continue
		if ribbon:
			mb.setm(M.GLASS, GLASS_TINT, b.sd + H.f(b.id, int(y0)) * 0.2)
			sty_glass(mb, 1.0)
			var rg0 := base + Vector3(0, y0 + 0.85, 0) + outward * -0.24
			var rg1 := base + th * L + Vector3(0, y0 + 0.85, 0) + outward * -0.24
			mb.quad_n(rg0, rg1, rg1 + Vector3(0, fh - 1.3, 0), rg0 + Vector3(0, fh - 1.3, 0), outward)
			mb.setm(M.WALL, wc, b.sd, 0.0, wall_style)
			mb.quad(base + Vector3(0, y0 + 0.85, 0), base + th * L + Vector3(0, y0 + 0.85, 0),
				base + th * L + Vector3(0, y0 + 0.85, 0) + outward * -0.24, base + Vector3(0, y0 + 0.85, 0) + outward * -0.24)
			continue
		# windows per bay
		for k in nb:
			var off := bw * (k + 0.5)
			var c := base + th * off
			var ww := minf(bw - 0.5, 2.4)
			if style == M.STY_CURTAIN:
				ww = bw - 0.16
			elif style == M.STY_INDUSTRIAL:
				ww = bw - 0.9
			var wh := maxf(0.7, wy1 - (y0 + 0.85))
			var half := th * (ww * 0.5)
			if style == M.STY_CURTAIN:
				# flush glass, no recess
				mb.setm(M.GLASS, GLASS_TINT, b.sd + H.f(b.id, k, int(y0)) * 0.3)
				sty_glass(mb, 1.0)
				var g0 := c - half + Vector3(0, y0 + 0.85, 0) + outward * 0.06
				var g1 := c + half + Vector3(0, y0 + 0.85, 0) + outward * 0.06
				mb.quad_n(g0, g1, g1 + Vector3(0, wh, 0), g0 + Vector3(0, wh, 0), outward)
				mb.setm(M.METAL, Mats.c("4a5058"), b.sd)
				mb.box(c - outward * 0.02 + Vector3(0, y0 + 0.85 + wh * 0.5, 0),
					Vector3(0.1, wh, 0.1))
			else:
				var inset := outward * -0.26
				var g0 := c - half + Vector3(0, y0 + 0.9, 0) + inset
				var g1 := c + half + Vector3(0, y0 + 0.9, 0) + inset
				mb.setm(M.GLASS, GLASS_TINT, b.sd + H.f(b.id, k, int(y0)) * 0.3)
				sty_glass(mb, 1.0)
				mb.quad_n(g0, g1, g1 + Vector3(0, wh, 0), g0 + Vector3(0, wh, 0), outward)
				mb.setm(M.WALL, wc * 1.04, b.sd, 0.0, wall_style)
				var o0 := c - half + Vector3(0, y0 + 0.9, 0)
				var o1 := c + half + Vector3(0, y0 + 0.9, 0)
				mb.quad(o0, g0, g0 + Vector3(0, wh, 0), o0 + Vector3(0, wh, 0))
				mb.quad(g1, o1, o1 + Vector3(0, wh, 0), g1 + Vector3(0, wh, 0))
				mb.quad(o0, o1, g1, g0)
				mb.quad(g0 + Vector3(0, wh, 0), g1 + Vector3(0, wh, 0), o1 + Vector3(0, wh, 0), o0 + Vector3(0, wh, 0))
				# sill + lintel
				mb.setm(M.CONCRETE, Mats.c("a8a49a"), b.sd)
				mb.box(c + outward * 0.08 + Vector3(0, y0 + 0.88, 0), Vector3(0.3, 0.09, ww), true, false)
				if style == M.STY_PUNCHED or style == M.STY_BRICK:
					mb.box(c + outward * 0.10 + Vector3(0, y0 + 0.95 + wh + 0.06, 0), Vector3(0.26, 0.12, ww + 0.25), true, false)
				# external split AC unit under some windows
				if H.f(b.id, k, int(y0 * 3.0)) > 0.88 and (style == M.STY_PUNCHED or style == M.STY_BRICK):
					mb.setm(M.METAL, Mats.c("b8bcb8"), H.f(b.id, k, 5))
					var acp := c + outward * 0.34 + Vector3(0, y0 + 0.55, 0)
					mb.box(acp, Vector3(0.62, 0.45, 0.7), true, true)
					mb.setm(M.METAL, Mats.c("4a4e50"), H.f(b.id, k, 6))
					mb.cyl_y(acp + outward * 0.24, 0.19, 0.03, 10, true)
					mb.setm(M.METAL, Mats.c("6a6e70"), H.f(b.id, k, 7))
					mb.box(c + outward * 0.04 + Vector3(0, y0 + 0.35, 0), Vector3(0.08, 0.1, ww * 0.8))
		# mullion pilasters between bays
		mb.setm(M.WALL, wc * 1.05, b.sd, 0.0, wall_style)
		for k in nb + 1:
			var off := bw * k
			if off > L - 0.02:
				continue
			var c := base + th * off
			var pw := 0.42 if style != M.STY_CURTAIN else 0.1
			mb.box(c + outward * 0.06 + Vector3(0, (y0 + y1) * 0.5, 0),
				Vector3(pw, fh, pw), true, false)
	# residential balconies
	if b.kind == CityPlan.K_APARTMENT and style != M.STY_CURTAIN and fmod(y0, fh * 2.0) < 0.5:
		_balconies(b, mb, poly, y0, wc)

static func _balconies(b: CityPlan.Bld, mb: MB, poly: PackedVector2Array, y: float, wc: Color) -> void:
	var r := H.rng(b.id, int(y * 3.0) + 17)
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var e := poly[(i + 1) % n] - a
		var L := e.length()
		if L < 3.0 or r.randf() > 0.5:
			continue
		var dir := e / L
		var outward := Vector3(e.y, 0, -e.x) / L
		var count := maxi(1, int(L / 4.5))
		for k in count:
			var off := L * (k + 0.5) / count
			var c := Vector3(a.x, 0, a.y) + Vector3(dir.x, 0, dir.y) * off
			var w := 2.2
			mb.setm(M.CONCRETE, Mats.c("8e8a80"), r.randf())
			mb.box(c + outward * 0.55 + Vector3(0, y + 0.08, 0), Vector3(w, 0.16, 1.2), true, false)
			# railing
			mb.setm(M.METAL, Mats.c("2e3238"), r.randf())
			mb.box(c + outward * 1.1 + Vector3(0, y + 0.55, 0), Vector3(w, 0.05, 0.05))
			var side := Vector3(dir.x, 0, dir.y) * (w * 0.5)
			mb.box(c + outward * 1.1 + side + Vector3(0, y + 0.55, 0), Vector3(0.05, 0.05, 1.1))
			# potted plant sometimes
			if r.randf() < 0.4:
				mb.setm(M.SOIL, Mats.c("3a2a1e"), r.randf())
				mb.box(c + outward * 0.7 + Vector3(0, y + 0.35, 0), Vector3(0.5, 0.4, 0.5))
				mb.setm(M.FOLIAGE, Mats.c("2f4a26"), r.randf())
				mb.sphere(c + outward * 0.7 + Vector3(0, y + 0.85, 0), 0.45, 7, 5)

## Street-level storefront / entrance band.
static func _ground_floor(b: CityPlan.Bld, mb: MB, poly: PackedVector2Array,
		y0: float, y1: float, wc: Color, style: float) -> void:
	var h := y1 - y0
	var n := poly.size()
	var r := H.rng(b.id, 313)
	var wall_style := 50.0 + style
	var shop := b.kind == CityPlan.K_SHOP or b.kind == CityPlan.K_MALL or b.kind == CityPlan.K_OFFICE or b.kind == CityPlan.K_HOTEL or b.kind == CityPlan.K_TOWER
	var industrial := b.kind == CityPlan.K_WAREHOUSE or b.kind == CityPlan.K_FACTORY
	for i in n:
		var a := poly[i]
		var e := poly[(i + 1) % n] - a
		var L := e.length()
		if L < 0.6:
			continue
		var dir := e / L
		var outward := Vector3(e.y, 0, -e.x) / L
		var base := Vector3(a.x, y0, a.y)
		var th := Vector3(dir.x, 0, dir.y)
		var street := _street_edge(Vector3(a.x, 0, a.y) + th * (L * 0.5))
		# solid base plinth
		mb.setm(M.CONCRETE, Mats.c("6d6a62"), b.sd)
		mb.quad(base, base + th * L, base + th * L + Vector3(0, 0.55, 0), base + Vector3(0, 0.55, 0))
		# fascia band at top
		mb.setm(M.WALL, wc * 0.9, b.sd, 0.0, wall_style)
		mb.quad(base + Vector3(0, h - 1.0, 0), base + th * L + Vector3(0, h - 1.0, 0),
			base + th * L + Vector3(0, h, 0), base + Vector3(0, h, 0))
		if industrial:
			# corrugated metal + roller doors
			mb.setm(M.WALL, Mats.c("7d7a70"), b.sd, 0.0, 50.0 + M.STY_INDUSTRIAL)
			mb.quad(base + Vector3(0, 0.55, 0), base + th * L + Vector3(0, 0.55, 0),
				base + th * L + Vector3(0, h - 1.0, 0), base + Vector3(0, h - 1.0, 0))
			var doors := maxi(1, int(L / 9.0))
			for k in doors:
				var c := base + th * (L * (k + 0.5) / doors)
				mb.setm(M.METAL, Mats.c("5c6068"), r.randf())
				var dw := 5.0
				var dh := minf(4.6, h - 1.6)
				mb.quad(c - th * (dw * 0.5) + Vector3(0, 0.55, 0), c + th * (dw * 0.5) + Vector3(0, 0.55, 0),
					c + th * (dw * 0.5) + Vector3(0, 0.55 + dh, 0), c - th * (dw * 0.5) + Vector3(0, 0.55 + dh, 0))
				mb.setm(M.EMIT, Mats.c("ffcc44"), r.randf(), 1.2)
				mb.box(c + Vector3(0, 0.55 + dh + 0.15, 0) + outward * 0.15, Vector3(1.0, 0.12, 0.15))
		else:
			# shopfront glazing with columns
			var cols := maxi(2, int(L / 5.2))
			var gw := (L - 0.9) / cols
			for k in cols:
				var c := base + th * (0.45 + gw * (k + 0.5))
				if H.f(b.id, k, 91) < 0.18:
					# closed roller shutter
					mb.setm(M.METAL, Mats.c("7a8086"), H.f(b.id, k, 92))
					var sh0 := c - th * (gw * 0.5 - 0.12) + Vector3(0, 0.55, 0)
					var sh1 := c + th * (gw * 0.5 - 0.12) + Vector3(0, 0.55, 0)
					mb.quad_n(sh0, sh1, sh1 + Vector3(0, h - 1.85, 0), sh0 + Vector3(0, h - 1.85, 0), outward)
					mb.setm(M.METAL, Mats.c("4a4e52"), H.f(b.id, k, 93))
					mb.box(c + outward * 0.12 + Vector3(0, 0.55, 0), Vector3(gw - 0.2, 0.12, 0.12))
					continue
				mb.setm(M.GLASS, GLASS_TINT, b.sd + k * 0.07)
				sty_glass(mb, 2.0)
				var g0 := c - th * (gw * 0.5 - 0.22) + Vector3(0, 0.55, 0)
				var g1 := c + th * (gw * 0.5 - 0.22) + Vector3(0, 0.55, 0)
				mb.quad_n(g0, g1, g1 + Vector3(0, h - 1.85, 0), g0 + Vector3(0, h - 1.85, 0), outward)
				# lit shop interior backing (visible through the glass at street level)
				var glow := _shop_glow(r)
				var bk := outward * -1.15
				var gw2 := h - 1.85
				mb.setm(M.EMIT, glow, r.randf(), 0.42)
				mb.quad_n(g0 + bk, g1 + bk, g1 + bk + Vector3(0, gw2 * 0.55, 0), g0 + bk + Vector3(0, gw2 * 0.55, 0), outward)
				mb.setm(M.EMIT, glow * 0.55, r.randf(), 0.26)
				mb.quad_n(g0 + bk + Vector3(0, gw2 * 0.55, 0), g1 + bk + Vector3(0, gw2 * 0.55, 0),
					g1 + bk + Vector3(0, gw2, 0), g0 + bk + Vector3(0, gw2, 0), outward)
				# shelving rows + products
				for si in 3:
					var sy := 0.75 + si * 0.75
					if sy > gw2 - 0.4:
						break
					mb.setm(M.WALL, Mats.c("3a3236"), r.randf(), 0.0, 52.0)
					mb.quad_n(g0 + bk + outward * 0.06 + Vector3(0, sy, 0), g1 + bk + outward * 0.06 + Vector3(0, sy, 0),
						g1 + bk + outward * 0.06 + Vector3(0, sy + 0.06, 0), g0 + bk + outward * 0.06 + Vector3(0, sy + 0.06, 0), outward)
					var nprod := 7
					for pi in nprod:
						var pp2 := g0.lerp(g1, (pi + 0.5) / nprod) + bk + outward * 0.18
						mb.setm(M.PLASTIC, _product(r), r.randf(), 0.25)
						mb.box(pp2 + Vector3(0, sy + 0.2, 0), Vector3(0.22, 0.28, 0.22))
				# counter
				mb.setm(M.WOOD, Mats.c("4a3424"), r.randf())
				var cp := g0.lerp(g1, 0.72) + bk + outward * 0.5
				mb.box(cp + Vector3(0, 0.55, 0), Vector3(1.6, 1.1, 0.7))
				# pendant lamps
				mb.setm(M.EMIT, Mats.c("ffcf9a"), r.randf(), 1.8)
				for li in 3:
					var lpp := g0.lerp(g1, 0.2 + 0.3 * li) + outward * -0.85
					mb.cyl_y(lpp + Vector3(0, gw2 - 0.15, 0), 0.22, 0.12, 8, true)
				# vertical neon blade above the shopfront
				if street and r.randf() < 0.7:
					var bp2 := g0.lerp(g1, 0.15) + outward * 0.55
					mb.setm(M.EMIT, _neon(r), r.randf(), 3.2)
					var hh2 := minf(4.2, h - 1.6)
					mb.quad(bp2 + Vector3(0, 1.4, 0) - th * 0.12, bp2 + Vector3(0, 1.4, 0) + th * 0.12,
						bp2 + Vector3(0, 1.4 + hh2, 0) + th * 0.12, bp2 + Vector3(0, 1.4 + hh2, 0) - th * 0.12)
					mb.quad(bp2 + Vector3(0, 1.4, 0) + th * 0.12, bp2 + Vector3(0, 1.4, 0) - th * 0.12,
						bp2 + Vector3(0, 1.4 + hh2, 0) - th * 0.12, bp2 + Vector3(0, 1.4 + hh2, 0) + th * 0.12)
			# columns
			mb.setm(M.WALL, wc * 0.95, b.sd, 0.0, wall_style)
			for k in cols + 1:
				var c := base + th * (0.45 + gw * k) - th * (gw * 0.5 - 0.22) * 0.0
				var cc := base + th * (0.45 + gw * k)
				mb.box(cc + outward * 0.1 + Vector3(0, (0.55 + h - 1.0) * 0.5, 0),
					Vector3(0.45, h - 1.55, 0.45), true, false)
			# signage band above the shopfront
			if street:
				mb.setm(M.EMIT, _neon(r), b.sd, 1.6)
				var yb := h - 1.0
				var sw := minf(L * 0.7, 6.0)
				var c2 := base + th * (L * 0.5)
				mb.quad(c2 - th * (sw * 0.5) + Vector3(0, yb - 0.55, 0) + outward * 0.12,
					c2 + th * (sw * 0.5) + Vector3(0, yb - 0.55, 0) + outward * 0.12,
					c2 + th * (sw * 0.5) + Vector3(0, yb - 0.05, 0) + outward * 0.12,
					c2 - th * (sw * 0.5) + Vector3(0, yb - 0.05, 0) + outward * 0.12)
			# awning
			if street and r.randf() < 0.55 and b.kind != CityPlan.K_TOWER:
				mb.setm(M.FABRIC, Mats.c("6a2a3a") if r.randf() < 0.5 else Mats.c("2a4a5a"), r.randf())
				var c3 := base + th * (L * 0.5)
				var aw := minf(L * 0.8, 8.0)
				mb.quad_n(c3 - th * (aw * 0.5) + Vector3(0, h - 1.05, 0),
					c3 + th * (aw * 0.5) + Vector3(0, h - 1.05, 0),
					c3 + th * (aw * 0.5) + outward * 1.5 + Vector3(0, h - 1.55, 0),
					c3 - th * (aw * 0.5) + outward * 1.5 + Vector3(0, h - 1.55, 0), Vector3.UP)
		# door for non-shop ground floors
		if not shop and not industrial and street:
			var c4 := base + th * (L * 0.5)
			mb.setm(M.METAL, Mats.c("3a3e44"), r.randf())
			mb.quad(c4 - th * 1.1 + Vector3(0, 0.55, 0), c4 + th * 1.1 + Vector3(0, 0.55, 0),
				c4 + th * 1.1 + Vector3(0, 3.0, 0), c4 - th * 1.1 + Vector3(0, 3.0, 0))
			mb.setm(M.EMIT, Mats.c("ffd9a0"), r.randf(), 1.4)
			mb.box(c4 + outward * 0.2 + Vector3(0, 3.35, 0), Vector3(1.6, 0.1, 0.16))

static func _product(r: RandomNumberGenerator) -> Color:
	var cols := ["c03040", "30a0c0", "d0a030", "40b060", "a040c0", "e0e0d8", "204050"]
	return Mats.c(cols[r.randi() % cols.size()])

static func _shop_glow(r: RandomNumberGenerator) -> Color:
	var cols := ["ffb877", "ffd9a8", "ff9f5a", "d8f0ff", "ffd070", "ffb0d0"]
	return Mats.c(cols[r.randi() % cols.size()])

## Steel fire escape on one facade: platforms, rails, zig-zag stairs.
static func _fire_escape(b: CityPlan.Bld, mb: MB, poly: PackedVector2Array, fh: float, y_ground: float) -> void:
	var n := poly.size()
	if n < 3:
		return
	var i := b.id % n
	var a := poly[i]
	var c := poly[(i + 1) % n]
	var L := a.distance_to(c)
	if L < 6.0:
		return
	var dir := (c - a) / L
	var out := Vector2(dir.y, -dir.x)
	if out.dot(Vector2(b.cx, b.cz) - (a + c) * 0.5) < 0.0:
		out = -out
	var th := Vector3(dir.x, 0, dir.y)
	var ov := Vector3(out.x, 0, out.y)
	var base := Vector3(a.x, 0, a.y) + th * (L * 0.5)
	var w := 3.0
	var y := y_ground + fh
	var prev := base + ov * 0.9 + Vector3(0, y, 0)
	while y < b.h - 3.0:
		var p := base + ov * 0.9 + Vector3(0, y, 0)
		# platform + rail
		mb.setm(M.METAL, Mats.c("3a3e42"), b.sd)
		mb.box(p, Vector3(w, 0.08, 1.6))
		mb.box(p + ov * 0.74 + Vector3(0, 0.55, 0), Vector3(w, 0.05, 0.05))
		mb.box(p + ov * 0.74 + Vector3(0, 0.28, 0), Vector3(w, 0.04, 0.04))
		for sgn in [-1.0, 1.0]:
			mb.box(p + th * (w * 0.5 * sgn) + ov * 0.74 + Vector3(0, 0.55, 0), Vector3(0.05, 1.1, 0.05))
			mb.box(p + th * (w * 0.5 * sgn) + Vector3(0, 0.55, 0), Vector3(0.05, 1.1, 1.5))
		# diagonal stair to the previous platform
		if y > y_ground + fh + 0.1:
			mb.setm(M.METAL, Mats.c("4a4e52"), b.sd)
			mb.box_frame(prev + Vector3(0, 0.2, 0) + th * (w * 0.3), p + th * (w * 0.3), 0.08)
		prev = p
		y += fh * 2.0

static func _street_edge(p: Vector3) -> bool:
	if plan == null:
		return true
	var v := Vector2(p.x, p.z)
	for i in plan.xlines.size():
		var x: float = plan.xlines[i]["p"]
		var w: float = plan.xlines[i]["w"]
		if absf(v.x - x) - w * 0.5 < 9.0 and absf(v.y) < CityPlan.HALF:
			return true
	for i in plan.zlines.size():
		var z: float = plan.zlines[i]["p"]
		var w: float = plan.zlines[i]["w"]
		if absf(v.y - z) - w * 0.5 < 9.0 and absf(v.x) < CityPlan.HALF:
			return true
	return false

## Roof plate + parapet interior + mechanical clutter.
## Flat ring between an outer and an inset polygon at height y.
static func _ring(mb: MB, outer: PackedVector2Array, inner: PackedVector2Array, y: float) -> void:
	if outer.size() != inner.size():
		return
	var n := outer.size()
	for i in n:
		var a0 := outer[i]
		var b0 := outer[(i + 1) % n]
		var a1 := inner[i]
		var b1 := inner[(i + 1) % n]
		mb.quad(Vector3(a0.x, y, a0.y), Vector3(b0.x, y, b0.y),
			Vector3(b1.x, y, b1.y), Vector3(a1.x, y, a1.y))

static func _roof(b: CityPlan.Bld, mb: MB, poly: PackedVector2Array, top: float) -> void:
	var rc := roof_col(b)
	mb.setm(M.CONCRETE, rc, b.sd)
	var r := H.rng(b.id, 771)
	var c := Vector2(b.cx, b.cz)
	var bb := Poly.bbox(poly)
	# main deck
	mb.prism(poly, top, top + 0.12, true, false)
	# gravel / membrane patches
	var n := 3 + r.randi() % 5
	for i in n:
		var px := c.x + r.randf_range(-bb.size.x * 0.36, bb.size.x * 0.36)
		var pz := c.y + r.randf_range(-bb.size.y * 0.36, bb.size.y * 0.36)
		mb.setm(M.SOIL, Mats.c("3c3830"), r.randf())
		var s := r.randf_range(1.2, 4.0)
		mb.box(Vector3(px, top + 0.16, pz), Vector3(s, 0.06, s), true, false)
	# HVAC units
	var units := 2 + r.randi() % 6
	for i in units:
		var px := c.x + r.randf_range(-bb.size.x * 0.3, bb.size.x * 0.3)
		var pz := c.y + r.randf_range(-bb.size.y * 0.3, bb.size.y * 0.3)
		var s := r.randf_range(0.9, 2.8)
		var hh := r.randf_range(0.5, 1.6)
		mb.setm(M.METAL, Mats.c("9aa0a6"), r.randf())
		mb.box(Vector3(px, top + 0.12 + hh * 0.5, pz), Vector3(s, hh, s * r.randf_range(0.6, 1.4)))
		# fan disc
		mb.setm(M.METAL, Mats.c("2e3238"), r.randf())
		mb.cyl_y(Vector3(px, top + 0.12 + hh + 0.02, pz), s * 0.3, 0.04, 10, true)
	# vents / pipes
	if r.randf() < 0.7:
		mb.setm(M.METAL, Mats.c("6a7078"), b.sd)
		var px := c.x + r.randf_range(-bb.size.x * 0.3, bb.size.x * 0.3)
		var pz := c.y + r.randf_range(-bb.size.y * 0.3, bb.size.y * 0.3)
		mb.cyl_y(Vector3(px, top + 1.2, pz), 0.28, 2.4, 8, true)

## Extra street-level details for tall buildings: entrances, bollards, planters.
static func _details(b: CityPlan.Bld, mb: MB, poly: PackedVector2Array, top: float,
		wc: Color, y_ground: float) -> void:
	var r := H.rng(b.id, 5531)
	var n := poly.size()
	# rooftop screen for malls / shops
	if (b.kind == CityPlan.K_MALL or b.kind == CityPlan.K_SHOP) and r.randf() < 0.8:
		var dirs := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
		var d: Vector2 = dirs[r.randi() % 4]
		var c := Vector3(b.cx, 0, b.cz)
		var bb := Poly.bbox(poly)
		var half := bb.size.x * 0.5 if absf(d.x) > 0.5 else bb.size.y * 0.5
		var p := c + Vector3(d.x, 0, d.y) * (half + 0.3)
		mb.setm(M.SCREEN, Mats.c("ff5fbf"), r.randf(), 1.0)
		var side := Vector3(-d.y, 0, d.x) * 6.0
		mb.quad(p - side + Vector3(0, top - 8.0, 0), p + side + Vector3(0, top - 8.0, 0),
			p + side + Vector3(0, top - 1.0, 0), p - side + Vector3(0, top - 1.0, 0))
	# base planters and bollards
	var c2 := Vector3(b.cx, 0, b.cz)
	var per := 0
	for i in n:
		var a := Vector3(poly[i].x, 0, poly[i].y)
		var bb2 := Vector3(poly[(i + 1) % n].x, 0, poly[(i + 1) % n].y)
		var L := a.distance_to(bb2)
		if L < 4.0 or per > 2:
			continue
		per += 1
		var out := (bb2 - a).normalized().cross(Vector3.UP).normalized()
		for k in 3:
			var p := a.lerp(bb2, 0.2 + 0.3 * k)
			mb.setm(M.METAL, Mats.c("2e3238"), r.randf())
			mb.cyl_y(p + out * 1.0 + Vector3(0, 0.55, 0), 0.09, 0.8, 6, true)
		mb.setm(M.SOIL, Mats.c("332a20"), r.randf())
		mb.box(a.lerp(bb2, 0.5) + out * 1.0 + Vector3(0, 0.5, 0), Vector3(1.4, 0.7, 1.4))
		mb.setm(M.FOLIAGE, Mats.c("2c4522"), r.randf())
		mb.sphere(a.lerp(bb2, 0.5) + out * 1.0 + Vector3(0, 1.5, 0), 0.9, 8, 6)