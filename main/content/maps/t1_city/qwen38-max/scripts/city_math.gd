class_name CityMath
extends RefCounted
## Geometry / math helpers shared by all generator modules.

static func hull2d(points: Array) -> Array:
	# monotone chain on Vector2; returns CCW convex hull
	var pts := points.duplicate()
	pts.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	if pts.size() < 3:
		return pts
	var cross: Callable = func(o: Vector2, a: Vector2, b: Vector2) -> float:
		return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
	var lower := []
	for p in pts:
		while lower.size() >= 2 and cross.call(lower[lower.size() - 2], lower[lower.size() - 1], p) <= 0.0:
			lower.pop_back()
		lower.append(p)
	var upper := []
	for k in range(pts.size() - 1, -1, -1):
		var p: Vector2 = pts[k]
		while upper.size() >= 2 and cross.call(upper[upper.size() - 2], upper[upper.size() - 1], p) <= 0.0:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	return lower + upper

static func line_isect(p0: Vector3, d0: Vector3, p1: Vector3, d1: Vector3) -> Vector3:
	var cr := d0.x * d1.z - d0.z * d1.x
	if absf(cr) < 1e-6:
		return p1
	var t := ((p1.x - p0.x) * d1.z - (p1.z - p0.z) * d1.x) / cr
	return p0 + d0 * t

static func poly_centroid(corners: Array) -> Vector3:
	var g := Vector3.ZERO
	for c in corners:
		g += c
	return g / float(corners.size())

static func poly_area2(corners: Array) -> float:
	# shoelace in xz
	var a := 0.0
	var n := corners.size()
	for i in n:
		var p: Vector3 = corners[i]
		var q: Vector3 = corners[(i + 1) % n]
		a += p.x * q.z - q.x * p.z
	return absf(a) * 0.5

## Inset a convex polygon: dists[i] applies to edge i -> i+1.
static func inset_poly(corners: Array, dists: Array) -> Array:
	var n := corners.size()
	var g := poly_centroid(corners)
	var lines := []
	for e in n:
		var a: Vector3 = corners[e]
		var b: Vector3 = corners[(e + 1) % n]
		var dir := b - a
		dir.y = 0
		dir = dir.normalized()
		var nn := Vector3(dir.z, 0, -dir.x)
		var mid := (a + b) * 0.5
		if nn.dot(mid - g) > 0.0:
			nn = -nn
		lines.append([a + nn * dists[e], dir])
	var out := []
	for k in n:
		var le: Array = lines[(k - 1 + n) % n]
		var lf: Array = lines[k]
		out.append(line_isect(le[0], le[1], lf[0], lf[1]))
	return out

## Recursive quad subdivision into lots of ~target area.
static func split_quad(q: Array, target: float, rng: RandomNumberGenerator,
		min_area: float = 0.0) -> Array:
	var out := []
	var stack := [q]
	while stack.size() > 0:
		var cur: Array = stack.pop_back()
		var area := poly_area2(cur)
		var e0: float = (cur[1] - cur[0]).length()
		var e1: float = (cur[2] - cur[1]).length()
		if area <= target * 1.55 or (area < target * 2.0 and (min_area <= 0.0 or area * 0.45 > min_area)) or stack.size() > 24:
			out.append(cur)
			continue
		var t := rng.randf_range(0.42, 0.58)
		if e0 >= e1:
			var m1: Vector3 = cur[0].lerp(cur[1], t)
			var m2: Vector3 = cur[3].lerp(cur[2], t)
			stack.append([cur[0], m1, m2, cur[3]])
			stack.append([m1, cur[1], cur[2], m2])
		else:
			var m1b: Vector3 = cur[1].lerp(cur[2], t)
			var m2b: Vector3 = cur[0].lerp(cur[3], t)
			stack.append([cur[0], cur[1], m1b, m2b])
			stack.append([m2b, m1b, cur[2], cur[3]])
	return out

static func catmull_rom(pts: PackedVector3Array, samples_per_seg: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.size() < 2:
		return pts
	var ext := PackedVector3Array()
	ext.append(pts[0] * 2.0 - pts[1])
	for p in pts:
		ext.append(p)
	ext.append(pts[pts.size() - 1] * 2.0 - pts[pts.size() - 2])
	for i in range(1, ext.size() - 2):
		var p0: Vector3 = ext[i - 1]
		var p1: Vector3 = ext[i]
		var p2: Vector3 = ext[i + 1]
		var p3: Vector3 = ext[i + 2]
		for s in samples_per_seg:
			var t := float(s) / float(samples_per_seg)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t +
				(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
				(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[pts.size() - 1])
	return out

static func frame_from_quad(q: Array) -> Transform3D:
	# local frame: origin = centroid, +x along edge0, +z along edge1
	var c := poly_centroid(q)
	var xdir: Vector3 = (q[1] - q[0]).normalized()
	var zdir: Vector3 = (q[3] - q[0]).normalized()
	var ydir := zdir.cross(xdir).normalized()
	if ydir.y < 0:
		ydir = -ydir
		xdir = -xdir
	var b := Basis(xdir, ydir, zdir)
	return Transform3D(b, c)

static func smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
