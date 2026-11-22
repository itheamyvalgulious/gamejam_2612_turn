## Elevated expressway ring: swept deck, piers, barriers, light poles, neon.
class_name Infra
extends RefCounted

const DECK_Y := 13.6
const HALF_W := 12.5

static func ring_path(radius: float, corner: float, samples: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var corners := [
		Vector2(radius - corner, radius - corner),
		Vector2(-radius + corner, radius - corner),
		Vector2(-radius + corner, -radius + corner),
		Vector2(radius - corner, -radius + corner),
	]
	for ci in 4:
		var c: Vector2 = corners[ci]
		var a0 := 0.0
		match ci:
			0: a0 = 0.0
			1: a0 = PI * 0.5
			2: a0 = PI
			3: a0 = PI * 1.5
		for k in samples:
			var a := a0 + (PI * 0.5) * float(k) / samples
			var p := c + Vector2(cos(a), sin(a)) * corner
			pts.append(Vector3(p.x, DECK_Y, p.y))
	return pts

static func route(radius: float) -> Dictionary:
	var pts := ring_path(radius, 55.0, 10)
	var closed := PackedVector3Array(pts)
	closed.append(pts[0])
	return {"pts": closed, "len": _len(closed), "loop": true}

static func build(plan: CityPlan, mb: MB, radius := 1280.0) -> Dictionary:
	var path := ring_path(radius, 55.0, 10)
	var closed := PackedVector3Array(path)
	closed.append(path[0])
	var prof := PackedVector2Array([
		Vector2(-HALF_W, 0), Vector2(HALF_W, 0), Vector2(HALF_W, -1.4),
		Vector2(HALF_W - 0.6, -1.4), Vector2(HALF_W - 0.6, -0.1),
		Vector2(-HALF_W + 0.6, -0.1), Vector2(-HALF_W + 0.6, -1.4), Vector2(-HALF_W, -1.4),
	])
	mb.setm(M.CONCRETE, Mats.c("6e6a62"), 0.4)
	mb.sweep(prof, closed, false)
	mb.setm(M.CONCRETE, Mats.c("8a867c"), 0.3)
	for side in [-1.0, 1.0]:
		var bp := PackedVector2Array([
			Vector2(side * (HALF_W - 0.9), 0.1), Vector2(side * (HALF_W - 0.4), 0.1),
			Vector2(side * (HALF_W - 0.55), 1.0), Vector2(side * (HALF_W - 0.9), 1.0),
		])
		mb.sweep(bp, closed, false)
	mb.setm(M.EMIT, Mats.c("2fe0ff"), 0.5, 1.6)
	for side in [-1.0, 1.0]:
		var gp := PackedVector2Array([
			Vector2(side * (HALF_W + 0.02), -0.2), Vector2(side * (HALF_W + 0.02), -0.9),
		])
		mb.sweep(gp, closed, false)
	var acc := 0.0
	var n := closed.size()
	for i in n - 1:
		var a := closed[i]
		var b := closed[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		var prev_acc := acc
		acc += seg
		var k: float = ceil((prev_acc + 0.001) / 34.0)
		while k * 34.0 < acc:
			var tt: float = (k * 34.0 - prev_acc) / seg
			_pier(mb, a.lerp(b, tt))
			k += 1.0
		var k2: float = ceil((prev_acc + 0.001) / 46.0)
		while k2 * 46.0 < acc:
			var tt2: float = (k2 * 46.0 - prev_acc) / seg
			_pole(mb, a.lerp(b, tt2), (b - a).normalized())
			k2 += 1.0
	return {"pts": closed, "len": _len(closed), "loop": true}

static func _len(p: PackedVector3Array) -> float:
	var t := 0.0
	for i in p.size() - 1:
		t += p[i].distance_to(p[i + 1])
	return t

static func _pier(mb: MB, p: Vector3) -> void:
	mb.setm(M.CONCRETE, Mats.c("7a766c"), 0.35)
	var prof := PackedVector2Array([
		Vector2(-1.1, 0.0), Vector2(1.1, 0.0), Vector2(0.7, DECK_Y - 1.2), Vector2(-0.7, DECK_Y - 1.2),
	])
	var pts := PackedVector3Array([Vector3(p.x, 0, p.z), Vector3(p.x, DECK_Y - 1.2, p.z)])
	mb.sweep(prof, pts, false)
	mb.box(Vector3(p.x, DECK_Y - 1.5, p.z), Vector3(HALF_W * 1.6, 1.1, 2.4))

static func _pole(mb: MB, p: Vector3, dir: Vector3) -> void:
	var side := Vector3(-dir.z, 0, dir.x)
	mb.setm(M.METAL, Mats.c("3a3e44"), 0.2)
	var base := p + side * (HALF_W - 0.6)
	mb.cyl_y(base + Vector3(0, 5.5, 0), 0.09, 5.5, 6, true)
	mb.setm(M.EMIT, Mats.c("ffd9a0"), 0.4, 2.6)
	mb.box(base + Vector3(0, 8.2, 0), Vector3(0.7, 0.14, 0.4))