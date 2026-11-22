## Street furniture, lamps, trees, kiosks, cables, traffic signals.
class_name Props
extends RefCounted

static func chunk(plan: CityPlan, mb: MB, c: Vector2i, detail: bool, lamps: Array = []) -> void:
	var r := H.rng(c.x * 7919 + 13, c.y * 104729 + 7, 5)
	var x0 := -CityPlan.HALF + c.x * CityPlan.CELL
	var z0 := -CityPlan.HALF + c.y * CityPlan.CELL
	var x1 := x0 + CityPlan.CELL
	var z1 := z0 + CityPlan.CELL
	# street lamps along road edges
	var xs: Array = []
	var zs: Array = []
	for i in plan.xlines.size():
		var px: float = plan.xlines[i]["p"]
		if px > x0 - 40.0 and px < x1 + 40.0:
			xs.append(plan.xlines[i])
	for i in plan.zlines.size():
		var pz: float = plan.zlines[i]["p"]
		if pz > z0 - 40.0 and pz < z1 + 40.0:
			zs.append(plan.zlines[i])
	for xl in xs:
		var px: float = xl["p"]
		var w: float = xl["w"]
		var t := z0 + 6.0
		while t < z1 - 2.0:
			var side := 1.0 if int(t * 0.05) % 2 == 0 else -1.0
			var lp := Vector3(px + side * (w * 0.5 + 1.4), Ground.PAVE_H, t)
			_lamp(mb, lp, Vector3(-side, 0, 0), r)
			lamps.append(lp + Vector3(-side * 1.2, 7.7, 0))
			t += 30.0
	for zl in zs:
		var pz: float = zl["p"]
		var w: float = zl["w"]
		var t := x0 + 10.0
		while t < x1 - 2.0:
			var side := 1.0 if int(t * 0.05) % 2 == 0 else -1.0
			var lp2 := Vector3(t, Ground.PAVE_H, pz + side * (w * 0.5 + 1.4))
			_lamp(mb, lp2, Vector3(0, 0, -side), r)
			lamps.append(lp2 + Vector3(0, 7.7, -side * 1.2))
			t += 30.0
	# block-edge trees, bins, planters, kiosks
	for blk in plan.blocks:
		if blk.water:
			continue
		var bc := Poly.centroid(blk.poly)
		if bc.x < x0 or bc.x >= x1 or bc.y < z0 or bc.y >= z1:
			continue
		_block_props(plan, mb, blk, r, detail)
	# overhead cables + traffic signals at intersections
	for xl in xs:
		var px: float = xl["p"]
		var w: float = xl["w"]
		var t := z0 + 18.0
		while t < z1 - 6.0:
			if r.randf() < 0.55:
				var h := r.randf_range(8.0, 15.0)
				cable(mb, Vector3(px - w * 0.5 - 3.0, h, t), Vector3(px + w * 0.5 + 3.0, h + r.randf_range(-1.5, 1.5), t + r.randf_range(-2, 2)), r.randf_range(0.8, 2.2))
				if r.randf() < 0.5:
					mb.setm(M.EMIT, _col(r), r.randf(), 2.6)
					mb.cyl_y(Vector3(px + (r.randf() - 0.5) * w, h - 0.9, t), 0.16, 0.28, 8, true)
			t += r.randf_range(22.0, 46.0)
	for zl in zs:
		var pz: float = zl["p"]
		var w2: float = zl["w"]
		var t2 := x0 + 18.0
		while t2 < x1 - 6.0:
			if r.randf() < 0.55:
				var h2 := r.randf_range(8.0, 15.0)
				cable(mb, Vector3(t2, h2, pz - w2 * 0.5 - 3.0), Vector3(t2 + r.randf_range(-2, 2), h2 + r.randf_range(-1.5, 1.5), pz + w2 * 0.5 + 3.0), r.randf_range(0.8, 2.2))
			t2 += r.randf_range(22.0, 46.0)

static func _block_props(plan: CityPlan, mb: MB, blk: CityPlan.Block, r: RandomNumberGenerator, detail: bool) -> void:
	var poly := blk.poly
	var c := Poly.centroid(poly)
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var L := a.distance_to(b)
		if L < 6.0:
			continue
		var dir := (b - a) / L
		var out := Vector2(-dir.y, dir.x)  # inward? computed below against centroid
		if out.dot(c - (a + b) * 0.5) < 0.0:
			out = -out
		# place on the ring, 1.4 m inside
		var p := a + dir * 2.0 + out * 1.5
		var t := 3.0
		while t < L - 2.0:
			var q := a + dir * t + out * 1.4
			var roll := r.randf()
			var street := _near_road(plan, q)
			if street and blk.district == CityPlan.RESIDENTIAL and roll < 0.72:
				_tree(mb, Vector3(q.x, Ground.PAVE_H, q.y), r)
			elif street and roll < 0.42:
				_bin(mb, Vector3(q.x, Ground.PAVE_H, q.y), r)
			elif street and roll < 0.55 and detail:
				_bench(mb, Vector3(q.x, Ground.PAVE_H, q.y), Vector3(dir.x, 0, dir.y), r)
			elif street and roll < 0.63:
				_planter_box(mb, Vector3(q.x, Ground.PAVE_H, q.y), r)
			elif street and roll < 0.70:
				_vending(mb, Vector3(q.x, Ground.PAVE_H, q.y), Vector3(-out.x, 0, -out.y), r)
			t += 9.0
		if detail and blk.district == CityPlan.COMMERCIAL and L > 12.0 and r.randf() < 0.5:
			var q2 := a + dir * (L * r.randf_range(0.3, 0.7)) + out * 2.2
			_kiosk(mb, Vector3(q2.x, Ground.PAVE_H, q2.y), r)

static func _near_road(plan: CityPlan, p: Vector2) -> bool:
	for i in plan.xlines.size():
		var x: float = plan.xlines[i]["p"]
		var w: float = plan.xlines[i]["w"]
		if absf(p.x - x) < w * 0.5 + 7.0:
			return true
	for i in plan.zlines.size():
		var z: float = plan.zlines[i]["p"]
		var w: float = plan.zlines[i]["w"]
		if absf(p.y - z) < w * 0.5 + 7.0:
			return true
	return false

static func _lamp(mb: MB, p: Vector3, dir: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.METAL, Mats.c("2c3036"), 0.2)
	mb.cyl_y(p + Vector3(0, 4.2, 0), 0.09, 8.4, 6, true)
	var head := p + dir * 1.45 + Vector3(0, 8.1, 0)
	mb.box_frame(p + Vector3(0, 8.0, 0), head, 0.14)
	mb.setm(M.EMIT, Mats.c("cfe4ff"), 0.4, 3.4)
	mb.box(head + Vector3(0, -0.08, 0), Vector3(0.75, 0.12, 0.42))
	# lamp post banner
	if r.randf() < 0.35:
		mb.setm(M.FABRIC, Mats.c("a02040") if r.randf() < 0.5 else Mats.c("2050a0"), r.randf())
		mb.quad(p + Vector3(0.08, 6.0, 0.4), p + Vector3(0.08, 6.0, -0.4),
			p + Vector3(0.08, 4.0, -0.4), p + Vector3(0.08, 4.0, 0.4))

static func _tree(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.WOOD, Mats.c("3a2c20"), r.randf())
	var h := r.randf_range(2.2, 3.4)
	mb.cyl_y(p + Vector3(0, h * 0.5, 0), 0.14, h, 6, true)
	mb.setm(M.FOLIAGE, Mats.c("2b4a1c") if r.randf() < 0.7 else Mats.c("3a5220"), r.randf())
	var s := r.randf_range(1.3, 2.1)
	mb.sphere(p + Vector3(0, h + s * 0.55, 0), s, 8, 5, 0.85)
	mb.sphere(p + Vector3(r.randf_range(-0.6, 0.6), h + s * 0.3, r.randf_range(-0.6, 0.6)), s * 0.7, 7, 4, 0.8)

static func _bin(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.METAL, Mats.c("3a4044"), r.randf())
	mb.cyl_y(p + Vector3(0, 0.5, 0), 0.3, 1.0, 8, true)
	mb.setm(M.PLASTIC, Mats.c("20303a"), r.randf())
	mb.cyl_y(p + Vector3(0, 1.03, 0), 0.32, 0.08, 8, true)

static func _bench(mb: MB, p: Vector3, dir: Vector3, r: RandomNumberGenerator) -> void:
	var side := Vector3(dir.z, 0, -dir.x) * 1.4
	mb.setm(M.WOOD, Mats.c("5a4028"), r.randf())
	mb.box(p + Vector3(0, 0.45, 0), Vector3(0.55, 0.08, 2.0), true, false)
	mb.setm(M.METAL, Mats.c("2a2e32"), r.randf())
	for s in [-0.8, 0.8]:
		mb.box(p + side * s * 0.5 + Vector3(0, 0.22, 0), Vector3(0.1, 0.44, 0.1))

static func _planter_box(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.CONCRETE, Mats.c("6a6862"), r.randf())
	mb.box(p + Vector3(0, 0.35, 0), Vector3(1.2, 0.7, 1.2))
	mb.setm(M.SOIL, Mats.c("2a2018"), r.randf())
	mb.box(p + Vector3(0, 0.72, 0), Vector3(1.05, 0.05, 1.05))
	mb.setm(M.FOLIAGE, Mats.c("2b4a1c"), r.randf())
	mb.sphere(p + Vector3(0, 1.15, 0), 0.62, 7, 5, 0.9)

static func _vending(mb: MB, p: Vector3, dir: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.METAL, Mats.c("2a3038"), r.randf())
	mb.box(p + Vector3(0, 0.95, 0), Vector3(1.0, 1.9, 0.7))
	mb.setm(M.SCREEN, _col(r), r.randf(), 1.2)
	mb.quad(p + dir * 0.36 + Vector3(-0.38, 0.6, 0), p + dir * 0.36 + Vector3(0.38, 0.6, 0),
		p + dir * 0.36 + Vector3(0.38, 1.7, 0), p + dir * 0.36 + Vector3(-0.38, 1.7, 0))

static func _kiosk(mb: MB, p: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.METAL, Mats.c("4a5058"), r.randf())
	mb.box(p + Vector3(0, 1.2, 0), Vector3(2.4, 2.4, 1.6))
	mb.setm(M.EMIT, _col(r), r.randf(), 1.2)
	mb.box(p + Vector3(0, 2.5, 0), Vector3(2.6, 0.35, 1.8), true, false)
	mb.setm(M.GLASS, Color(0.3, 0.4, 0.45), r.randf())
	mb.quad(p + Vector3(-0.9, 0.6, 0.81), p + Vector3(0.9, 0.6, 0.81),
		p + Vector3(0.9, 1.9, 0.81), p + Vector3(-0.9, 1.9, 0.81))

static func _col(r: RandomNumberGenerator) -> Color:
	var cols := ["ff2f7a", "2ff5ff", "ffb02f", "8f2fff", "2fff8f", "ff4a2f", "4aa8ff", "ffe32f"]
	return Mats.c(cols[r.randi() % cols.size()])

## Overhead cable between two points with catenary sag.
static func cable(mb: MB, a: Vector3, b: Vector3, sag := 1.2) -> void:
	var pts := PackedVector3Array()
	var n := 7
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(b, t)
		p.y -= sin(t * PI) * sag
		pts.append(p)
	mb.setm(M.RUBBER, Mats.c("16181a"))
	mb.tube(pts, 0.035, 4)

static func traffic_light(mb: MB, p: Vector3, dir: Vector3, r: RandomNumberGenerator) -> void:
	mb.setm(M.METAL, Mats.c("2c3036"), 0.1)
	mb.cyl_y(p + Vector3(0, 3.0, 0), 0.1, 6.0, 6, true)
	var arm := p + dir * 4.0 + Vector3(0, 5.6, 0)
	mb.box_frame(p + Vector3(0, 5.6, 0), arm, 0.13)
	mb.setm(M.METAL, Mats.c("1c2024"))
	mb.box(arm + Vector3(0, -0.5, 0), Vector3(0.4, 1.1, 0.4))
	var on := r.randi() % 3
	mb.setm(M.EMIT, [Mats.c("ff2020"), Mats.c("ffb020"), Mats.c("30ff60")][on], r.randf(), 3.0)
	mb.box(arm + Vector3(0, -0.5 + (1 - on) * 0.3, 0.22), Vector3(0.22, 0.22, 0.06))