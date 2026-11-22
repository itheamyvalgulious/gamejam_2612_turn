## Signature landmarks: twisted tower, hyperbolic cooling towers, ferris wheel,
## sky railway and a fan cable-stayed bridge. All parametric, no assets.
class_name Landmarks
extends RefCounted

# ------------------------------------------------------------------ twisted tower
static func twist(b: CityPlan.Bld, mb: MB, detail: bool) -> void:
	var h := b.h
	var base_y := 0.16
	var r0 := 34.0
	var r1 := 12.0
	var tw := deg_to_rad(124.0)
	var segs := 36 if detail else 20
	var floors := maxi(12, int(h / 4.0))
	var fy := h / floors
	var r := H.rng(b.id, 771)
	var glass := Mats.c("2f4b58")
	var mull := Mats.c("5c666e")
	for f in floors:
		var y0 := base_y + f * fy
		var y1 := y0 + fy
		var t0 := (y0 - base_y) / h
		var t1 := (y1 - base_y) / h
		var ra := lerpf(r0, r1, pow(t0, 0.82))
		var rb := lerpf(r0, r1, pow(t1, 0.82))
		var aa := tw * t0
		var ab := tw * t1
		# glass band
		mb.setm(M.GLASS, glass, b.sd + f * 0.01)
		mb.sty = 0.0
		for k in segs:
			var t_0 := TAU * float(k) / segs
			var t_1 := TAU * float(k + 1) / segs
			var p00 := Vector3(cos(t_0 + aa) * ra, y0, sin(t_0 + aa) * ra)
			var p01 := Vector3(cos(t_1 + aa) * ra, y0, sin(t_1 + aa) * ra)
			var p11 := Vector3(cos(t_1 + ab) * rb, y1, sin(t_1 + ab) * rb)
			var p10 := Vector3(cos(t_0 + ab) * rb, y1, sin(t_0 + ab) * rb)
			mb.quad_n(p00, p01, p11, p10, (p00 + p01 + p11 + p10 - Vector3(0, (y0 + y1) * 2.0, 0)).normalized())
		# spandrel ring every 4 floors (keeps the twist legible)
		if f % 4 != 0:
			continue
		mb.setm(M.METAL, mull, b.sd)
		mb.sty = 0.0
		var rs0 := ra + 0.05
		for k in segs:
			var t_0 := TAU * float(k) / segs
			var t_1 := TAU * float(k + 1) / segs
			var p00 := Vector3(cos(t_0 + aa) * rs0, y0, sin(t_0 + aa) * rs0)
			var p01 := Vector3(cos(t_1 + aa) * rs0, y0, sin(t_1 + aa) * rs0)
			mb.quad_n(p00, p01, p01 + Vector3(0, fy * 0.26, 0), p00 + Vector3(0, fy * 0.26, 0),
				(p00 + p01).normalized())
	# vertical mullions following the twist
	mb.setm(M.METAL, mull, b.sd)
	mb.sty = 0.0
	var mn := 26 if detail else 14
	for k in mn:
		var ang0 := TAU * float(k) / mn
		for s in 26:
			var t0 := float(s) / 26.0
			var t1 := float(s + 1) / 26.0
			var ra := lerpf(r0, r1, pow(t0, 0.82)) + 0.12
			var rb := lerpf(r0, r1, pow(t1, 0.82)) + 0.12
			var a0 := ang0 + tw * t0
			var a1 := ang0 + tw * t1
			var p0 := Vector3(cos(a0) * ra, base_y + t0 * h, sin(a0) * ra)
			var p1 := Vector3(cos(a1) * rb, base_y + t1 * h, sin(a1) * rb)
			var nrm := (p0 + p1 - Vector3(0, (p0.y + p1.y), 0)).normalized()
			var side := nrm.cross(Vector3.UP) * (0.55 if detail else 0.4)
			mb.quad_n(p0 - side, p0 + side, p1 + side, p1 - side, nrm)
	# crown + spire
	var top_r := r1
	mb.setm(M.METAL, Mats.c("3a4048"), b.sd)
	mb.cyl_y(Vector3(0, base_y + h + 1.6, 0), top_r + 1.2, 3.2, segs, true)
	mb.setm(M.EMIT, Mats.c("5fe6ff"), b.sd, 2.0)
	mb.cyl_y(Vector3(0, base_y + h + 2.4, 0), top_r + 1.35, 0.5, segs, false)
	mb.setm(M.METAL, Mats.c("4a5058"), b.sd)
	mb.cyl_y(Vector3(0, base_y + h + 18.0, 0), 0.8, 30.0, 8, true, 0.15)
	mb.setm(M.EMIT, Mats.c("ff3040"), b.sd, 3.0)
	mb.box(Vector3(0, base_y + h + 33.0, 0), Vector3(1.2, 1.2, 1.2))
	# podium / lobby ring
	mb.setm(M.CONCRETE, Mats.c("8a867e"), b.sd)
	mb.cyl_y(Vector3(0, 6.0, 0), r0 + 6.0, 12.0, segs, false, r0 + 2.0)
	# translate everything into world space if the building is not at the origin
	if absf(b.cx) > 0.01 or absf(b.cz) > 0.01:
		pass

# ------------------------------------------------------------------ cooling towers
static func cooling(b: CityPlan.Bld, mb: MB, detail: bool) -> void:
	var h := b.h
	var rt := 17.0
	var yt := h * 0.70
	var a := h * 0.46
	var segs := 40 if detail else 24
	var ring := 26 if detail else 12
	var prof := PackedVector2Array()
	for i in ring + 1:
		var y := h * float(i) / ring
		var r := rt * sqrt(1.0 + pow((y - yt) / a, 2.0))
		prof.append(Vector2(r, 0.0 + y))
	var cb := Mats.c("9a958c")
	mb.setm(M.CONCRETE, cb, b.sd)
	mb.revolve(prof, segs)
	# top rim
	var r_top := rt * sqrt(1.0 + pow((h - yt) / a, 2.0))
	mb.setm(M.CONCRETE, cb * 0.9, b.sd)
	mb.cyl_y(Vector3(0, h, 0), r_top + 0.5, 1.6, segs, false)
	# base legs (V columns)
	var r_base := rt * sqrt(1.0 + pow((0.0 - yt) / a, 2.0))
	mb.setm(M.CONCRETE, Mats.c("8a867e"), b.sd)
	var legs := 24 if detail else 12
	for k in legs:
		var ang := TAU * float(k) / legs
		var p0 := Vector3(cos(ang) * (r_base - 1.0), 0.0, sin(ang) * (r_base - 1.0))
		var p1 := Vector3(cos(ang) * r_base, 9.0, sin(ang) * r_base)
		mb.box_frame(p0, p1, 1.3)
	# inner dark throat
	mb.setm(M.CONCRETE, Mats.c("2a2824"), b.sd)
	mb.cyl_y(Vector3(0, 10.0, 0), r_base * 0.82, 1.0, segs, true)
	# service stairs hint
	if detail:
		mb.setm(M.METAL, Mats.c("4a4e52"), b.sd)
		for i in 12:
			var y := 12.0 + i * (h - 14.0) / 12.0
			var rr := rt * sqrt(1.0 + pow((y - yt) / a, 2.0)) + 0.4
			mb.box(Vector3(rr, y, 0.0), Vector3(1.1, 0.08, 0.7))

# ------------------------------------------------------------------ ferris wheel
static func wheel_node(pos: Vector2, radius: float) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0, pos.y)
	# static support frame
	var mb := MB.new()
	var hub_y := radius + 7.0
	mb.setm(M.METAL, Mats.c("3a4048"), 0.3)
	for s in [-1.0, 1.0]:
		var z: float = s * 3.4
		for sx in [-1.0, 1.0]:
			mb.box_frame(Vector3(sx * radius * 0.62, 0, z), Vector3(0, hub_y, 0), 1.6)
		mb.box(Vector3(0, hub_y, z), Vector3(2.2, 2.2, 1.2))
	# platform + boarding hall
	mb.setm(M.CONCRETE, Mats.c("7a766e"), 0.2)
	mb.cyl_y(Vector3(0, 0.4, 0), radius * 0.55, 0.8, 24, true)
	mb.setm(M.CONCRETE, Mats.c("8a867c"), 0.2)
	mb.box(Vector3(0, 2.2, radius * 0.62), Vector3(radius * 1.1, 4.2, 9.0))
	mb.setm(M.EMIT, Mats.c("ff4fd0"), 0.3, 2.6)
	mb.box(Vector3(0, 4.5, radius * 0.62 - 4.6), Vector3(radius * 0.9, 0.6, 0.2))
	root.add_child(mb.instance(Mats.surface, Mats.glass, false))
	# rotating wheel
	var wmb := MB.new()
	var rim := radius
	for s in [-1.0, 1.0]:
		var z: float = s * 2.6
		for i in 64:
			var a0 := TAU * float(i) / 64.0
			var a1 := TAU * float(i + 1) / 64.0
			var p0 := Vector3(cos(a0) * rim, hub_y + sin(a0) * rim, z)
			var p1 := Vector3(cos(a1) * rim, hub_y + sin(a1) * rim, z)
			mb_beam(wmb, p0, p1, 0.5, Mats.c("8a929c"))
		# spokes
		for i in 24:
			var a := TAU * float(i) / 24.0
			var p1 := Vector3(cos(a) * rim, hub_y + sin(a) * rim, z)
			mb_beam(wmb, Vector3(0, hub_y, z), p1, 0.16, Mats.c("6a7078"))
		# inner ring
		for i in 48:
			var a0 := TAU * float(i) / 48.0
			var a1 := TAU * float(i + 1) / 48.0
			mb_beam(wmb, Vector3(cos(a0) * rim * 0.55, hub_y + sin(a0) * rim * 0.55, z),
				Vector3(cos(a1) * rim * 0.55, hub_y + sin(a1) * rim * 0.55, z), 0.22, Mats.c("6a7078"))
	# gondolas
	var rr := H.rng(7, 77, 3)
	for i in 24:
		var a := TAU * float(i) / 24.0
		var p := Vector3(cos(a) * (rim - 0.8), hub_y + sin(a) * (rim - 0.8), 0)
		wmb.setm(M.EMIT, Mats.c("ffd27a") if i % 3 else Mats.c("6fe8ff"), i * 0.04, 1.2)
		wmb.box(p - Vector3(0, 1.4, 0), Vector3(1.9, 1.6, 2.6))
		wmb.setm(M.PLASTIC, Mats.c("e8e4dc") if rr.randf() < 0.5 else Mats.c("30343a"), rr.randf())
		wmb.box(p - Vector3(0, 0.9, 0), Vector3(2.0, 0.5, 2.7))
		wmb.setm(M.METAL, Mats.c("2a2e32"), rr.randf())
		wmb.box(p + Vector3(0, 0.2, 0), Vector3(0.18, 1.0, 0.18))
	var wm := wmb.instance(Mats.surface, Mats.glass, false)
	wm.name = "Wheel"
	root.add_child(wm)
	root.set_meta("wheel", wm)
	return root

static func mb_beam(mb: MB, a: Vector3, b: Vector3, t: float, col: Color) -> void:
	mb.setm(M.METAL, col, 0.3)
	mb.box_frame(a, b, t)

# ------------------------------------------------------------------ sky railway
static func skyrail_path(plan: CityPlan) -> PackedVector3Array:
	# follow the diagonal boulevard (offset to one side), smoothed
	var d := plan.diagonal
	var p := PackedVector3Array()
	var off := Vector2(7.0, 3.0)
	for i in d.size() - 1:
		var a: Vector2 = d[i]
		var b: Vector2 = d[i + 1]
		var prev: Vector2 = d[maxi(0, i - 1)]
		var next: Vector2 = d[mini(d.size() - 1, i + 2)]
		var steps := 14
		for k in steps:
			var t := float(k) / steps
			var q := 0.5 * ((2.0 * a) + (-prev + b) * t + (2.0 * prev - 5.0 * a + 4.0 * b - next) * t * t + (-prev + 3.0 * a - 3.0 * b + next) * t * t * t)
			p.append(Vector3(q.x + off.x, 16.0, q.y + off.y))
	p.append(Vector3(d[d.size() - 1].x + off.x, 16.0, d[d.size() - 1].y + off.y))
	return p

static func skyrail(plan: CityPlan, mb: MB) -> Dictionary:
	var path := skyrail_path(plan)
	var closed := path
	# guideway: box beam with side flanges
	var prof := PackedVector2Array([
		Vector2(-1.9, 0.0), Vector2(1.9, 0.0), Vector2(1.9, -0.4),
		Vector2(2.6, -0.4), Vector2(2.6, -1.1), Vector2(1.9, -1.1),
		Vector2(1.9, -1.7), Vector2(-1.9, -1.7), Vector2(-1.9, -1.1),
		Vector2(-2.6, -1.1), Vector2(-2.6, -0.4), Vector2(-1.9, -0.4),
	])
	mb.setm(M.CONCRETE, Mats.c("8c8880"), 0.3)
	mb.sweep(prof, closed, true)
	# running rail + power rail
	mb.setm(M.METAL, Mats.c("b0b6bc"), 0.2)
	mb.sweep(PackedVector2Array([Vector2(-0.6, 0.12), Vector2(-0.4, 0.12)]), closed, false)
	mb.sweep(PackedVector2Array([Vector2(0.4, 0.12), Vector2(0.6, 0.12)]), closed, false)
	# piers + station
	var acc := 0.0
	var n := closed.size()
	for i in n - 1:
		var a := closed[i]
		var b := closed[i + 1]
		var seg := a.distance_to(b)
		var prev := acc
		acc += seg
		var k: float = ceil((prev + 0.001) / 34.0)
		while k * 34.0 < acc:
			var p := a.lerp(b, (k * 34.0 - prev) / seg)
			mb.setm(M.CONCRETE, Mats.c("7e7a72"), 0.3)
			mb.box(Vector3(p.x, 7.5, p.z), Vector3(1.7, 15.0, 1.7))
			mb.box(Vector3(p.x, 14.6, p.z), Vector3(4.4, 0.8, 2.4))
			k += 1.0
	# stations
	for st in [0.16, 0.52, 0.86]:
		var idx := int(st * (n - 1))
		var p := closed[idx]
		var t := (closed[mini(n - 1, idx + 1)] - closed[maxi(0, idx - 1)]).normalized()
		var side := Vector3(-t.z, 0, t.x)
		mb.setm(M.METAL, Mats.c("8a9098"), 0.3)
		mb.box(Vector3(p.x, 18.6, p.z), Vector3(9.0, 1.0, 26.0))
		mb.setm(M.GLASS, Color(0.2, 0.3, 0.35), 0.4)
		for s in [-1.0, 1.0]:
			mb.quad(Vector3(p.x, 16.2, p.z) + side * (s * 5.0) - t * 13.0,
				Vector3(p.x, 16.2, p.z) + side * (s * 5.0) + t * 13.0,
				Vector3(p.x, 19.0, p.z) + side * (s * 5.0) + t * 13.0,
				Vector3(p.x, 16.2, p.z) + side * (s * 5.0) - t * 13.0 + Vector3(0, 3.0, 0))
		mb.setm(M.EMIT, Mats.c("59f0ff"), 0.3, 2.2)
		mb.box(Vector3(p.x, 18.0, p.z), Vector3(9.2, 0.25, 0.3))
		mb.setm(M.CONCRETE, Mats.c("6e6a62"), 0.2)
		mb.box(Vector3(p.x, 15.0, p.z), Vector3(10.0, 1.4, 28.0))
	return {"path": closed, "len": _len(closed)}

static func _len(p: PackedVector3Array) -> float:
	var t := 0.0
	for i in p.size() - 1:
		t += p[i].distance_to(p[i + 1])
	return t

static func train_mesh() -> MeshInstance3D:
	var mb := MB.new()
	mb.setm(M.PLASTIC, Mats.c("d8d4c8"), 0.3)
	mb.box(Vector3(0, 0.0, 0), Vector3(2.6, 2.2, 11.5))
	mb.setm(M.GLASS, Color(0.15, 0.22, 0.28), 0.4)
	for s in [-1.0, 1.0]:
		mb.quad(Vector3(0, 0, 0) + Vector3(s * 1.32, -0.6, -5.0),
			Vector3(0, 0, 0) + Vector3(s * 1.32, -0.6, 5.0),
			Vector3(0, 0, 0) + Vector3(s * 1.32, 0.5, 5.0),
			Vector3(0, 0, 0) + Vector3(s * 1.32, 0.5, -5.0))
	mb.setm(M.EMIT, Mats.c("5fe0ff"), 0.3, 2.2)
	mb.box(Vector3(0, -0.55, 5.6), Vector3(1.8, 0.12, 0.12))
	mb.box(Vector3(0, -0.2, 5.6), Vector3(2.4, 0.08, 0.08))
	return mb.instance(Mats.surface, Mats.glass, false)

# ------------------------------------------------------------------ fan cable bridge
static func fan_bridge(plan: CityPlan, mb: MB) -> void:
	var rx := plan.river_x(0.0)
	var hw := plan.river_w * 0.5
	# find where the diagonal crosses the canal
	var d := plan.diagonal
	var cross := Vector2(rx, 0.0)
	for i in d.size() - 1:
		var a := d[i]
		var b := d[i + 1]
		if (a.x - rx) * (b.x - rx) <= 0.0:
			var t := (rx - a.x) / (b.x - a.x)
			cross = a.lerp(b, t)
			break
	var t := Vector2(1.0, 0.45).normalized()
	# find the local diagonal direction
	for i in d.size() - 1:
		var a := d[i]
		var b := d[i + 1]
		if (a.x - rx) * (b.x - rx) <= 0.0:
			t = (b - a).normalized()
			break
	var n := Vector2(-t.y, t.x)
	var span := hw + 34.0
	var deck_y := 0.35
	# deck
	mb.setm(M.CONCRETE, Mats.c("6e6a62"), 0.3)
	mb.sweep(PackedVector2Array([Vector2(-44.0, deck_y), Vector2(44.0, deck_y),
		Vector2(44.0, deck_y - 1.2), Vector2(-44.0, deck_y - 1.2)]),
		PackedVector3Array([Vector3(cross.x - t.x * span, 0, cross.y - t.y * span),
			Vector3(cross.x, 0, cross.y),
			Vector3(cross.x + t.x * span, 0, cross.y + t.y * span)]), false)
	# railings
	mb.setm(M.METAL, Mats.c("9aa0a6"), 0.2)
	for s in [-1.0, 1.0]:
		var off: Vector2 = n * (43.0 * s)
		mb.box(Vector3(cross.x + off.x, deck_y + 0.6, cross.y + off.y),
			Vector3(0.3, 1.2, span * 2.0))
	# pylon (A-shape)
	var py := 62.0
	mb.setm(M.CONCRETE, Mats.c("a8a29a"), 0.35)
	for s in [-1.0, 1.0]:
		var base: Vector3 = Vector3(cross.x, 0, cross.y) + Vector3(n.x, 0, n.y) * (9.0 * s)
		var top := Vector3(cross.x, py, cross.y)
		mb.box_frame(base, top, 2.6)
	mb.box(Vector3(cross.x, py, cross.y), Vector3(3.0, 3.0, 3.0))
	mb.setm(M.EMIT, Mats.c("ff2f7a"), 0.4, 2.6)
	mb.box(Vector3(cross.x, py + 1.8, cross.y), Vector3(3.2, 0.4, 3.2))
	# fan cables
	mb.setm(M.METAL, Mats.c("c8ccd0"), 0.2)
	for s in [-1.0, 1.0]:
		for k in 9:
			var along: float = span * (0.14 + 0.086 * k) * s
			var deck_p := Vector3(cross.x + t.x * along, deck_y + 0.4, cross.y + t.y * along)
			var top_p: Vector3 = Vector3(cross.x, py - 2.0 - k * 1.1, cross.y) + Vector3(n.x, 0, n.y) * (1.2 * s)
			mb.tube(PackedVector3Array([top_p, deck_p]), 0.07, 4)
	# pylons at the banks
	mb.setm(M.CONCRETE, Mats.c("8a867c"), 0.3)
	for s in [-1.0, 1.0]:
		var p := Vector3(cross.x + t.x * span * s, 0, cross.y + t.y * span * s)
		mb.box(Vector3(p.x, 4.0, p.z), Vector3(3.0, 8.0, 3.0))
	# neon underglow
	mb.setm(M.EMIT, Mats.c("2fe0ff"), 0.4, 2.0)
	for s in [-1.0, 1.0]:
		var off: Vector2 = n * (43.4 * s)
		mb.quad(Vector3(cross.x + off.x - t.x * span, deck_y - 0.9, cross.y + off.y - t.y * span),
			Vector3(cross.x + off.x + t.x * span, deck_y - 0.9, cross.y + off.y + t.y * span),
			Vector3(cross.x + off.x + t.x * span, deck_y - 0.5, cross.y + off.y + t.y * span),
			Vector3(cross.x + off.x - t.x * span, deck_y - 0.5, cross.y + off.y - t.y * span))