## Convex-polygon helpers used by the city planner (XZ plane, CCW, area > 0).
class_name Poly
extends RefCounted

static func area(p: PackedVector2Array) -> float:
	var a := 0.0
	var n := p.size()
	for i in n:
		var q := p[(i + 1) % n]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5

static func centroid(p: PackedVector2Array) -> Vector2:
	var a := 0.0
	var c := Vector2.ZERO
	var n := p.size()
	for i in n:
		var q := p[(i + 1) % n]
		var cr := p[i].x * q.y - q.x * p[i].y
		a += cr
		c += (p[i] + q) * cr
	if absf(a) < 1e-9:
		var m := Vector2.ZERO
		for v in p:
			m += v
		return m / maxf(1.0, float(n))
	return c / (3.0 * a)

static func ccw(p: PackedVector2Array) -> PackedVector2Array:
	if area(p) < 0.0:
		var out := PackedVector2Array()
		for i in range(p.size() - 1, -1, -1):
			out.append(p[i])
		return out
	return p

static func bbox(p: PackedVector2Array) -> Rect2:
	if p.size() == 0:
		return Rect2()
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r

## Clip to the half plane dot(x - pt, n) <= 0
static func clip(p: PackedVector2Array, pt: Vector2, n: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var m := p.size()
	if m < 3:
		return out
	for i in m:
		var a := p[i]
		var b := p[(i + 1) % m]
		var da := (a - pt).dot(n)
		var db := (b - pt).dot(n)
		if da <= 0.0:
			out.append(a)
		if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
			var t := da / (da - db)
			out.append(a + (b - a) * t)
	return out

## Split into the two half-plane pieces (may return 0, 1 or 2 polygons)
static func split(p: PackedVector2Array, pt: Vector2, n: Vector2) -> Array:
	var a := clip(p, pt, n)
	var b := clip(p, pt, -n)
	var out := []
	if a.size() >= 3 and absf(area(a)) > 12.0:
		out.append(a)
	if b.size() >= 3 and absf(area(b)) > 12.0:
		out.append(b)
	return out

## Inward offset of a convex polygon.
static func inset(p: PackedVector2Array, d: float) -> PackedVector2Array:
	var src := ccw(p)
	var n := src.size()
	if n < 3:
		return PackedVector2Array()
	var lines := []
	for i in n:
		var a := src[i]
		var b := src[(i + 1) % n]
		var e := b - a
		var l := e.length()
		if l < 1e-6:
			return PackedVector2Array()
		var inw := Vector2(-e.y, e.x) / l
		lines.append([a + inw * d, e / l])
	var out := PackedVector2Array()
	for i in n:
		var l1: Array = lines[(i + n - 1) % n]
		var l2: Array = lines[i]
		var p1: Vector2 = l1[0]
		var d1: Vector2 = l1[1]
		var p2: Vector2 = l2[0]
		var d2: Vector2 = l2[1]
		var den := d1.cross(d2)
		if absf(den) < 1e-6:
			out.append(p2)
			continue
		var t := (p2 - p1).cross(d2) / den
		out.append(p1 + d1 * t)
	# validate
	for v in out:
		if not is_finite(v.x) or not is_finite(v.y):
			return PackedVector2Array()
	if absf(area(out)) < 10.0:
		return PackedVector2Array()
	# reject self-intersecting / inverted results
	for i in out.size():
		var a := out[i]
		var b := out[(i + 1) % out.size()]
		if a.distance_to(b) < 0.05:
			return PackedVector2Array()
	return ccw(out)

static func longest_axis(p: PackedVector2Array) -> Vector2:
	var best := 0.0
	var dir := Vector2.RIGHT
	var n := p.size()
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		var l := a.distance_squared_to(b)
		if l > best:
			best = l
			dir = (b - a).normalized()
	return dir

## Recursive binary subdivision of convex polygons into street-plot sized lots.
static func subdivide(p: PackedVector2Array, rng: RandomNumberGenerator,
		min_dim: float, max_dim: float, angular: bool) -> Array:
	var out := []
	var q := [ccw(p)]
	var guard := 0
	while q.size() > 0 and guard < 3000:
		guard += 1
		var cur: PackedVector2Array = q.pop_back()
		var ar := area(cur)
		if ar < 24.0:
			continue
		var axis := longest_axis(cur)
		# extent along / across the dominant axis
		var lo := 1e20
		var hi := -1e20
		var lo2 := 1e20
		var hi2 := -1e20
		var perp := Vector2(-axis.y, axis.x)
		for v in cur:
			var a := v.dot(axis)
			var b := v.dot(perp)
			lo = minf(lo, a)
			hi = maxf(hi, a)
			lo2 = minf(lo2, b)
			hi2 = maxf(hi2, b)
		var ext := hi - lo
		var thick := hi2 - lo2
		var split_it := false
		if ext > max_dim:
			split_it = true
		elif thick < min_dim * 0.85 and ext > min_dim * 1.4:
			split_it = true
		elif ext > min_dim * 1.6 and rng.randf() < 0.5:
			split_it = true
		if not split_it or thick < 6.0:
			out.append(cur)
			continue
		var frac := rng.randf_range(0.4, 0.6)
		var pt := centroid(cur) + axis * (ext * (frac - 0.5))
		var n := axis
		if angular:
			n = axis.rotated(rng.randf_range(-0.22, 0.22))
		var parts := split(cur, pt, n)
		if parts.size() < 2:
			out.append(cur)
			continue
		for pp in parts:
			if area(pp) < 24.0:
				continue
			q.append(pp)
	return out

static func contains(p: PackedVector2Array, pt: Vector2) -> bool:
	var c := false
	var n := p.size()
	var j := n - 1
	for i in n:
		if ((p[i].y > pt.y) != (p[j].y > pt.y)) and \
				(pt.x < (p[j].x - p[i].x) * (pt.y - p[i].y) / (p[j].y - p[i].y) + p[i].x):
			c = not c
		j = i
	return c

## Approximate distance from a point to the polygon boundary.
static func edge_dist(p: PackedVector2Array, pt: Vector2) -> float:
	var best := 1e20
	var n := p.size()
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-9 else clampf((pt - a).dot(ab) / l2, 0.0, 1.0)
		var d := pt.distance_to(a + ab * t)
		if d < best:
			best = d
	return best

static func to_packed(arr: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for v in arr:
		p.append(v)
	return p