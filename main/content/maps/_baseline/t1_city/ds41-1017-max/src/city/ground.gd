## Street level: asphalt, block slabs, kerbs, canal, quays, bridges, lane paint.
class_name Ground
extends RefCounted

const PAVE_H := 0.16
const ROAD_Y := 0.0

static func build(plan: CityPlan, mb: MB) -> void:
	build_asphalt(plan, mb)
	build_blocks(plan, mb)
	build_canal(plan, mb)
	build_markings(plan, mb)
	build_bridges(plan, mb)

static func build_asphalt(plan: CityPlan, mb: MB) -> void:
	var rx := plan.river_x(0.0)
	var l := rx - plan.river_w * 0.5 + 0.5
	var r := rx + plan.river_w * 0.5 - 0.5
	mb.setm(M.ASPHALT, Mats.c("565650"), 0.3)
	# west and east carriageways (canal gap in the middle)
	mb.quad(Vector3(-CityPlan.HALF - 70, 0, -CityPlan.HALF - 70),
		Vector3(-CityPlan.HALF - 70, 0, CityPlan.HALF + 70),
		Vector3(l, 0, CityPlan.HALF + 70),
		Vector3(l, 0, -CityPlan.HALF - 70))
	mb.quad(Vector3(r, 0, -CityPlan.HALF - 70),
		Vector3(r, 0, CityPlan.HALF + 70),
		Vector3(CityPlan.HALF + 70, 0, CityPlan.HALF + 70),
		Vector3(CityPlan.HALF + 70, 0, -CityPlan.HALF - 70))

static func build_blocks(plan: CityPlan, mb: MB) -> void:
	for blk in plan.blocks:
		if blk.water:
			continue
		var poly: PackedVector2Array = blk.poly
		if poly.size() < 3:
			continue
		var r := H.rng(int(Poly.centroid(poly).x), int(Poly.centroid(poly).y), 3)
		if blk.park:
			mb.setm(M.SOIL, Mats.c("2e3320"), r.randf())
			mb.prism(poly, 0, PAVE_H, true, false)
			# park ground cover + paths
			mb.setm(M.FOLIAGE, Mats.c("25400f"), 0.4)
			var pp := Poly.inset(poly, 0.4)
			if pp.size() >= 3:
				mb.prism(pp, PAVE_H, PAVE_H + 0.02, true, false)
		else:
			mb.setm(M.CONCRETE, Mats.c("787670"), r.randf())
			mb.prism(poly, 0, PAVE_H, true, false)
		# kerb: 45-degree chamfer ring between the outer edge and a raised inner lip
		mb.setm(M.CONCRETE, Mats.c("b8b4a8"), 0.2)
		var e := Poly.inset(poly, 0.30)
		if e.size() >= 3 and e.size() == poly.size():
			var nn := poly.size()
			for si in nn:
				var a0 := poly[si]
				var b0 := poly[(si + 1) % nn]
				var a1 := e[si]
				var b1 := e[(si + 1) % nn]
				mb.quad(Vector3(a0.x, PAVE_H, a0.y), Vector3(b0.x, PAVE_H, b0.y),
					Vector3(b1.x, PAVE_H + 0.05, b1.y), Vector3(a1.x, PAVE_H + 0.05, a1.y))
			mb.setm(M.CONCRETE, Mats.c("8e8a80"), 0.25)
			mb.prism(e, PAVE_H + 0.05, PAVE_H + 0.07, false, false)
			# grime band along the kerb
			mb.setm(M.SOIL, Mats.c("2c2a24"), 0.3)
			var gi := Poly.inset(poly, 0.9)
			if gi.size() >= 3:
				mb.prism(gi, PAVE_H + 0.051, PAVE_H + 0.055, false, false)


static func build_canal(plan: CityPlan, mb: MB) -> void:
	var rx := plan.river_x(0.0)
	var hw := plan.river_w * 0.5
	var z0 := -CityPlan.HALF - 80.0
	var z1 := CityPlan.HALF + 80.0
	# quay walls
	mb.setm(M.CONCRETE, Mats.c("6e6a62"), 0.4)
	mb.quad(Vector3(rx - hw, -3.2, z1), Vector3(rx - hw, PAVE_H, z1),
		Vector3(rx - hw, PAVE_H, z0), Vector3(rx - hw, -3.2, z0))
	mb.quad(Vector3(rx + hw, PAVE_H, z1), Vector3(rx + hw, -3.2, z1),
		Vector3(rx + hw, -3.2, z0), Vector3(rx + hw, PAVE_H, z0))
	# quay coping
	mb.setm(M.CONCRETE, Mats.c("9a968c"), 0.2)
	mb.box(Vector3(rx - hw, PAVE_H + 0.08, 0), Vector3(1.4, 0.18, z1 - z0), true, false)
	mb.box(Vector3(rx + hw, PAVE_H + 0.08, 0), Vector3(1.4, 0.18, z1 - z0), true, false)
	# railings
	for side in [-1.0, 1.0]:
		var x: float = rx + side * hw
		mb.setm(M.METAL, Mats.c("2b2f34"), 0.3)
		mb.box(Vector3(x + side * 0.6, PAVE_H + 0.95, 0), Vector3(0.07, 0.07, z1 - z0), true, false)
		mb.box(Vector3(x + side * 0.6, PAVE_H + 0.5, 0), Vector3(0.05, 0.05, z1 - z0), true, false)
		var z := z0
		while z < z1:
			mb.box(Vector3(x + side * 0.6, PAVE_H + 0.5, z), Vector3(0.06, 1.0, 0.06), true, false)
			z += 3.0

static func build_markings(plan: CityPlan, mb: MB) -> void:
	var paint_w := Mats.c("d8d6cc")
	var paint_y := Mats.c("d8c04a")
	var zs: Array = []
	for i in plan.zlines.size():
		zs.append(plan.zlines[i])
	var xs: Array = []
	for i in plan.xlines.size():
		xs.append(plan.xlines[i])
	# vertical roads
	for i in plan.xlines.size():
		var x: float = plan.xlines[i]["p"]
		var w: float = plan.xlines[i]["w"]
		var cls: int = 3 if w > 30.0 else (2 if w > 18.0 else 1)
		_road_line(mb, plan, true, x, w, cls, zs, paint_w, paint_y)
	# horizontal roads
	for i in plan.zlines.size():
		var z: float = plan.zlines[i]["p"]
		var w: float = plan.zlines[i]["w"]
		var cls: int = 3 if w > 30.0 else (2 if w > 18.0 else 1)
		_road_line(mb, plan, false, z, w, cls, xs, paint_w, paint_y)
	# tyre wear bands on the wheel paths of every carriageway
	mb.setm(M.ASPHALT, Mats.c("2e2e34"), 0.4)
	for i in plan.xlines.size():
		var x: float = plan.xlines[i]["p"]
		var w: float = plan.xlines[i]["w"]
		if w < 18.0:
			continue
		for off in [-w * 0.32, -w * 0.18, w * 0.18, w * 0.32]:
			mb.quad(Vector3(x + off - 0.30, 0.006, -CityPlan.HALF), Vector3(x + off + 0.30, 0.006, -CityPlan.HALF),
				Vector3(x + off + 0.30, 0.006, CityPlan.HALF), Vector3(x + off - 0.30, 0.006, CityPlan.HALF))
	for i in plan.zlines.size():
		var z: float = plan.zlines[i]["p"]
		var w: float = plan.zlines[i]["w"]
		if w < 18.0:
			continue
		for off in [-w * 0.32, -w * 0.18, w * 0.18, w * 0.32]:
			mb.quad(Vector3(-CityPlan.HALF, 0.006, z + off - 0.30), Vector3(CityPlan.HALF, 0.006, z + off - 0.30),
				Vector3(CityPlan.HALF, 0.006, z + off + 0.30), Vector3(-CityPlan.HALF, 0.006, z + off + 0.30))
	# drain grates + manholes
	var r := H.rng(31, 77, 9)
	for i in plan.xlines.size():
		var x2: float = plan.xlines[i]["p"]
		var w2: float = plan.xlines[i]["w"]
		var t := -CityPlan.HALF + 20.0
		while t < CityPlan.HALF:
			mb.setm(M.METAL, Mats.c("3a3e42"), r.randf())
			mb.box(Vector3(x2 + w2 * 0.5 - 0.6, 0.005, t), Vector3(0.9, 0.02, 0.5), true, false)
			mb.setm(M.METAL, Mats.c("2a2e32"), r.randf())
			mb.cyl_y(Vector3(x2 + r.randf_range(-2.0, 2.0), 0.004, t + 9.0), 0.38, 0.02, 10, true)
			t += r.randf_range(26.0, 44.0)
	# faint warm glow line along every street (reads as illuminated road grid from the air)
	mb.setm(M.EMIT, Mats.c("ffb070"), 0.2, 0.55)
	for i in plan.xlines.size():
		var x: float = plan.xlines[i]["p"]
		mb.quad(Vector3(x - 0.5, 0.02, -CityPlan.HALF), Vector3(x + 0.5, 0.02, -CityPlan.HALF),
			Vector3(x + 0.5, 0.02, CityPlan.HALF), Vector3(x - 0.5, 0.02, CityPlan.HALF))
	for i in plan.zlines.size():
		var z: float = plan.zlines[i]["p"]
		mb.quad(Vector3(-CityPlan.HALF, 0.02, z - 0.5), Vector3(CityPlan.HALF, 0.02, z - 0.5),
			Vector3(CityPlan.HALF, 0.02, z + 0.5), Vector3(-CityPlan.HALF, 0.02, z + 0.5))
	# diagonal boulevard: centre dashes only
	var d := plan.diagonal
	mb.setm(M.ROADPAINT, paint_w, 0.1)
	for i in d.size() - 1:
		var a := d[i]
		var b := d[i + 1]
		var L := a.distance_to(b)
		var t := 0.0
		while t < L:
			var p0 := a.lerp(b, t / L)
			var p1 := a.lerp(b, minf(L, t + 4.0) / L)
			var side := (b - a).normalized().orthogonal() * 0.09
			mb.quad(Vector3(p0.x - side.x, 0.012, p0.y - side.y),
				Vector3(p1.x - side.x, 0.012, p1.y - side.y),
				Vector3(p1.x + side.x, 0.012, p1.y + side.y),
				Vector3(p0.x + side.x, 0.012, p0.y + side.y))
			t += 10.0

static func _road_line(mb: MB, plan: CityPlan, vertical: bool, pos: float, w: float,
		cls: int, crosses: Array, paint_w: Color, paint_y: Color) -> void:
	var half := w * 0.5
	var y := 0.012
	# collect crossing limits along the road
	var limits: Array = []
	for c in crosses:
		var p: float = c["p"]
		var cw: float = c["w"]
		limits.append([p - cw * 0.5 - 0.5, p + cw * 0.5 + 0.5, cw])
	limits.sort_custom(func(a, b): return a[0] < b[0])
	var from := -CityPlan.HALF
	var segs: Array = []
	for l in limits:
		if l[0] > from + 3.0:
			segs.append([from, l[0]])
		from = maxf(from, l[1])
	if from < CityPlan.HALF - 3.0:
		segs.append([from, CityPlan.HALF])
	# markings per segment
	for s in segs:
		var a0: float = s[0]
		var a1: float = s[1]
		var L := a1 - a0
		if L < 4.0:
			continue
		if cls >= 2:
			mb.setm(M.ROADPAINT, paint_y, 0.1)
			for off in [-0.22, 0.22]:
				_strip(mb, vertical, pos + off, 0.12, a0, a1, y)
		else:
			mb.setm(M.ROADPAINT, paint_w, 0.1)
			var t := a0 + 1.0
			while t < a1 - 3.0:
				_strip(mb, vertical, pos, 0.14, t, minf(a1, t + 3.0), y)
				t += 9.0
		# lane dividers
		mb.setm(M.ROADPAINT, paint_w, 0.1)
		if w > 30.0:
			for off in [-8.5, 8.5]:
				var t2 := a0 + 1.0
				while t2 < a1 - 3.0:
					_strip(mb, vertical, pos + off, 0.1, t2, minf(a1, t2 + 3.0), y)
					t2 += 9.0
			# edge lines
			for off in [-half + 0.5, half - 0.5]:
				_strip(mb, vertical, pos + off, 0.1, a0, a1, y, true)
		elif w > 18.0:
			for off in [-4.0, 4.0]:
				var t2 := a0 + 1.0
				while t2 < a1 - 3.0:
					_strip(mb, vertical, pos + off, 0.1, t2, minf(a1, t2 + 3.0), y)
					t2 += 9.0
			for off in [-half + 0.45, half - 0.45]:
				_strip(mb, vertical, pos + off, 0.09, a0, a1, y)
		else:
			for off in [-half + 0.4, half - 0.4]:
				_strip(mb, vertical, pos + off, 0.08, a0, a1, y)
	# crosswalks + stop bars at both ends of each crossing
	for l in limits:
		var p: float = l[0]
		var cw: float = l[2]
		var band := cw * 0.5 + 3.4
		for sgn in [-1.0, 1.0]:
			var zc: float = (l[0] + l[1]) * 0.5 + sgn * band
			_crosswalk(mb, vertical, pos, w, zc, paint_w, y)
			# stop line just before the crossing
			mb.setm(M.ROADPAINT, paint_w, 0.1)
			var zs2: float = zc + sgn * 1.6
			if vertical:
				mb.quad(Vector3(pos - half + 0.5, y, zs2), Vector3(pos + half - 0.5, y, zs2),
					Vector3(pos + half - 0.5, y, zs2 + 0.45), Vector3(pos - half + 0.5, y, zs2 + 0.45))
			else:
				mb.quad(Vector3(zs2, y, pos - half + 0.5), Vector3(zs2, y, pos + half - 0.5),
					Vector3(zs2 + 0.45, y, pos + half - 0.5), Vector3(zs2 + 0.45, y, pos - half + 0.5))

static func _crosswalk(mb: MB, vertical: bool, pos: float, w: float, at: float,
		col: Color, y: float) -> void:
	mb.setm(M.ROADPAINT, col, 0.1)
	var half := w * 0.5 - 0.6
	var n := 7
	var span := 0.48
	var gap := 0.55
	var total := n * (span + gap)
	var start := -total * 0.5
	for k in n:
		var o := start + k * (span + gap)
		if vertical:
			mb.quad(Vector3(pos - half, y, at + o), Vector3(pos + half, y, at + o),
				Vector3(pos + half, y, at + o + span), Vector3(pos - half, y, at + o + span))
		else:
			mb.quad(Vector3(at + o, y, pos - half), Vector3(at + o + span, y, pos - half),
				Vector3(at + o + span, y, pos + half), Vector3(at + o, y, pos + half))

static func _strip(mb: MB, vertical: bool, pos: float, w: float, a: float, b: float,
		y: float, solid := false) -> void:
	var hw := w * 0.5
	if b <= a:
		return
	if vertical:
		mb.quad(Vector3(pos - hw, y, a), Vector3(pos + hw, y, a),
			Vector3(pos + hw, y, b), Vector3(pos - hw, y, b))
	else:
		mb.quad(Vector3(a, y, pos - hw), Vector3(b, y, pos - hw),
			Vector3(b, y, pos + hw), Vector3(a, y, pos + hw))

static func build_bridges(plan: CityPlan, mb: MB) -> void:
	var rx := plan.river_x(0.0)
	var hw := plan.river_w * 0.5
	for i in plan.xlines.size():
		var x: float = plan.xlines[i]["p"]
		var w: float = plan.xlines[i]["w"]
		var cls: int = 3 if w > 30.0 else (2 if w > 18.0 else 1)
		if cls < 2:
			continue
		if absf(x - rx) > hw + 30.0:
			continue
		_bridge(mb, x, w, rx, hw)

static func _bridge(mb: MB, x: float, w: float, rx: float, hw: float) -> void:
	var z0 := -CityPlan.HALF
	var z1 := CityPlan.HALF
	var deck_y := 0.05
	# deck
	mb.setm(M.CONCRETE, Mats.c("6c6860"), 0.3)
	mb.box(Vector3(x, deck_y - 0.45, 0), Vector3(w, 0.9, hw * 2.0 + 6.0), true, false)
	# railings
	mb.setm(M.METAL, Mats.c("8e959c"), 0.2)
	for side in [-1.0, 1.0]:
		var px: float = x + side * (w * 0.5 - 0.3)
		mb.box(Vector3(px, deck_y + 0.6, 0), Vector3(0.16, 1.1, hw * 2.0 + 5.0), true, false)
	# pylons
	mb.setm(M.CONCRETE, Mats.c("9a958a"), 0.4)
	for side in [-1.0, 1.0]:
		for k in 2:
			var px: float = x + side * (w * 0.5 - 1.0)
			var pz := (k * 2 - 1) * (hw - 4.0)
			mb.box(Vector3(px, deck_y + 5.0, pz), Vector3(1.4, 10.0, 1.4), true, false)
	# cables
	mb.setm(M.METAL, Mats.c("3a3e44"), 0.2)
	for side in [-1.0, 1.0]:
		var px: float = x + side * (w * 0.5 - 1.0)
		for k in 2:
			var pz := (k * 2 - 1) * (hw - 4.0)
			for j in 6:
				var t := float(j) / 5.0
				var zz := lerpf(pz, (k * 2 - 1) * (hw + 2.0), t)
				var yy := deck_y + 9.0 - pow(t, 1.4) * 8.0
				mb.tube(PackedVector3Array([Vector3(px, deck_y + 9.5, pz), Vector3(px, yy, zz)]), 0.05, 4)
	# neon underglow strip
	mb.setm(M.EMIT, Mats.c("26f0ff"), 0.4, 2.4)
	for side in [-1.0, 1.0]:
		mb.quad(Vector3(x + side * (w * 0.5 + 0.05), deck_y - 0.55, -hw - 4.0),
			Vector3(x + side * (w * 0.5 + 0.05), deck_y - 0.55, hw + 4.0),
			Vector3(x + side * (w * 0.5 + 0.05), deck_y - 0.9, hw + 4.0),
			Vector3(x + side * (w * 0.5 + 0.05), deck_y - 0.9, -hw - 4.0))