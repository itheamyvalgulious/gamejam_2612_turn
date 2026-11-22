class_name MeshKit
extends RefCounted

## Low-level procedural mesh accumulator.
##
## The whole ship is assembled from this kit: chamfered boxes, lathes, swept
## tubes, extruded profiles and parametric surfaces. Geometry is batched per
## material so every room ends up as a handful of draw calls.
##
## Conventions
##  * CCW/CW: Godot renders clockwise winding as front facing. `quad()` takes
##    the four corners in any cyclic order plus a normal hint and fixes winding.
##  * UVs are in metres so procedural shaders get constant texel density.
##  * Vertex colour = (part seed, normalised height, part kind, wear).
##  * All coordinates are ship-space (X starboard, Y up, Z stern->bow negative).

const UNIT_UV_PREFIX := ["screen", "emit", "route", "holo", "glass", "plant", "hud"]

var mats: Dictionary = {}          # key -> Material
var _keys: Array = []
var _v: Dictionary = {}
var _n: Dictionary = {}
var _t: Dictionary = {}
var _t2: Dictionary = {}
var _c: Dictionary = {}
var _i: Dictionary = {}

var rng := RandomNumberGenerator.new()
var tri_count := 0
var total_tris := 0

# per-part state
var part_seed := 0.5
var part_kind := 0.0
var wear := 1.0
var height_lo := -1000.0
var height_hi := 1000.0
var uv_offset := Vector2.ZERO

# transform stack
var _xf := Transform3D.IDENTITY
var _xf_stack: Array = []


func _init(seed_value: int = 20261115) -> void:
	rng.seed = seed_value


# ---------------------------------------------------------------- materials --
func material(key: String, m: Material) -> void:
	if not mats.has(key):
		mats[key] = m
		_keys.append(key)
		_v[key] = PackedVector3Array()
		_n[key] = PackedVector3Array()
		_t[key] = PackedVector2Array()
		_t2[key] = PackedVector2Array()
		_c[key] = PackedColorArray()
		_i[key] = PackedInt32Array()


func has_material(key: String) -> bool:
	return mats.has(key)


func begin_part(seed_value: float = -1.0, kind: float = 0.0) -> void:
	part_seed = seed_value if seed_value >= 0.0 else rng.randf()
	part_kind = kind
	wear = 1.0


func set_height_range(lo: float, hi: float) -> void:
	height_lo = lo
	height_hi = hi


# --------------------------------------------------------------- transforms --
func push_xf(t: Transform3D) -> void:
	_xf_stack.append(_xf)
	_xf = _xf * t


func pop_xf() -> void:
	if _xf_stack.size() > 0:
		_xf = _xf_stack.pop_back()


func set_xf(t: Transform3D) -> void:
	_xf = t


func xf() -> Transform3D:
	return _xf


func at(origin: Vector3) -> Transform3D:
	return Transform3D(_xf.basis, origin)


func local(p: Vector3) -> Vector3:
	return _xf * p


# ------------------------------------------------------------------ vertices --
func _color_for(p: Vector3) -> Color:
	var g := 0.5
	if height_hi > height_lo:
		g = clampf((p.y - height_lo) / (height_hi - height_lo), 0.0, 1.0)
	return Color(part_seed, g, part_kind, wear)


func vert(key: String, p: Vector3, n: Vector3, uv: Vector2) -> void:
	if not mats.has(key):
		push_error("MeshKit: material '%s' not registered" % key)
		return
	var wp := _xf * p
	var wn := (_xf.basis * n).normalized()
	_v[key].append(wp)
	_n[key].append(wn)
	_t[key].append(uv + uv_offset)
	_t2[key].append(Vector2(part_seed, part_kind))
	_c[key].append(_color_for(wp))


func tri(key: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	# ensure clockwise winding as seen from the normal direction
	var nn: Vector3 = (b - a).cross(c - a)
	if nn.dot(n) > 0.0:
		var tb := b
		b = c
		c = tb
		var tub := ub
		ub = uc
		uc = tub
	var base: int = _v[key].size() if mats.has(key) else 0
	vert(key, a, n, ua)
	vert(key, b, n, ub)
	vert(key, c, n, uc)
	_i[key].append(base)
	_i[key].append(base + 1)
	_i[key].append(base + 2)
	tri_count += 1


func tri_n(key: String, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	# caller guarantees clockwise winding
	var base: int = _v[key].size() if mats.has(key) else 0
	vert(key, a, na, ua)
	vert(key, b, nb, ub)
	vert(key, c, nc, uc)
	_i[key].append(base)
	_i[key].append(base + 1)
	_i[key].append(base + 2)
	tri_count += 1


## Metric planar UV from the dominant axis of the normal.
func metric_uv(p: Vector3, n: Vector3) -> Vector2:
	var an := Vector3(absf(n.x), absf(n.y), absf(n.z))
	if an.x >= an.y and an.x >= an.z:
		return Vector2(p.z, p.y)
	elif an.y >= an.z:
		return Vector2(p.x, p.z)
	return Vector2(p.x, p.y)


func needs_unit_uv(key: String) -> bool:
	for p in UNIT_UV_PREFIX:
		if key.begins_with(p):
			return true
	return false


func quad(key: String, pts: Array, n: Vector3, uvs: Array = []) -> void:
	var nn: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
	if uvs.size() != 4:
		if needs_unit_uv(key):
			uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		else:
			uvs = [metric_uv(pts[0], n), metric_uv(pts[1], n), metric_uv(pts[2], n), metric_uv(pts[3], n)]
	if nn.dot(n) > 0.0:
		var p1 = pts[1]
		pts[1] = pts[3]
		pts[3] = p1
		var u1 = uvs[1]
		uvs[1] = uvs[3]
		uvs[3] = u1
	var base: int = _v[key].size() if mats.has(key) else 0
	for k in 4:
		vert(key, pts[k], n, uvs[k])
	_i[key].append(base)
	_i[key].append(base + 1)
	_i[key].append(base + 2)
	_i[key].append(base)
	_i[key].append(base + 2)
	_i[key].append(base + 3)
	tri_count += 2


## Quad with per-vertex normals. Winding is corrected automatically against
## the average supplied normal so every helper can ignore orientation.
func quad_n(key: String, pts: Array, norms: Array, uvs: Array) -> void:
	var navg: Vector3 = (norms[0] + norms[1] + norms[2] + norms[3]).normalized()
	var g: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
	if g.dot(navg) > 0.0:
		var tp = pts[1]; pts[1] = pts[3]; pts[3] = tp
		var tn = norms[1]; norms[1] = norms[3]; norms[3] = tn
		var tu = uvs[1]; uvs[1] = uvs[3]; uvs[3] = tu
	var base: int = _v[key].size() if mats.has(key) else 0
	for k in 4:
		vert(key, pts[k], norms[k], uvs[k])
	_i[key].append(base)
	_i[key].append(base + 1)
	_i[key].append(base + 2)
	_i[key].append(base)
	_i[key].append(base + 2)
	_i[key].append(base + 3)
	tri_count += 2


func poly(key: String, pts: Array, n: Vector3) -> void:
	# fan triangulation around the polygon centroid
	for k in range(1, pts.size() - 1):
		tri(key, pts[0], pts[k], pts[k + 1], n,
			metric_uv(pts[0], n), metric_uv(pts[k], n), metric_uv(pts[k + 1], n))


# --------------------------------------------------------------------- box ----
func box(key: String, size: Vector3, origin: Vector3 = Vector3.ZERO) -> void:
	var h := size * 0.5
	var p := [
		origin + Vector3(-h.x, -h.y, -h.z),
		origin + Vector3(h.x, -h.y, -h.z),
		origin + Vector3(h.x, h.y, -h.z),
		origin + Vector3(-h.x, h.y, -h.z),
		origin + Vector3(-h.x, -h.y, h.z),
		origin + Vector3(h.x, -h.y, h.z),
		origin + Vector3(h.x, h.y, h.z),
		origin + Vector3(-h.x, h.y, h.z),
	]
	quad(key, [p[1], p[2], p[6], p[5]], Vector3.RIGHT)
	quad(key, [p[0], p[4], p[7], p[3]], Vector3.LEFT)
	quad(key, [p[3], p[7], p[6], p[2]], Vector3.UP)
	quad(key, [p[0], p[1], p[5], p[4]], Vector3.DOWN)
	quad(key, [p[4], p[5], p[6], p[7]], Vector3.BACK)
	quad(key, [p[0], p[3], p[2], p[1]], Vector3.FORWARD)


## Box with all 12 edges chamfered (24 verts / 26 faces). Reads as machined
## hardware instead of a stretched cube.
func box_bevel(key: String, size: Vector3, origin: Vector3 = Vector3.ZERO, bevel: float = 0.02) -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.98)
	var axis := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var harr := [h.x, h.y, h.z]
	# 6 inset faces
	for a in 3:
		for s in [-1.0, 1.0]:
			var n: Vector3 = axis[a] * s
			var ua: int = (a + 1) % 3
			var ub: int = (a + 2) % 3
			var cs := []
			var uvs := []
			var ccorner := [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]
			for cc in ccorner:
				var pt := Vector3.ZERO
				pt[a] = s * harr[a]
				pt[ua] = cc.x * (harr[ua] - b)
				pt[ub] = cc.y * (harr[ub] - b)
				cs.append(origin + pt)
				uvs.append(metric_uv(origin + pt, n))
			quad(key, cs, n, uvs)
	# 12 chamfer strips
	for a in 3:
		for bb in range(a + 1, 3):
			for sa in [-1.0, 1.0]:
				for sb in [-1.0, 1.0]:
					var n := Vector3.ZERO
					n[a] = sa
					n[bb] = sb
					n = n.normalized()
					var free: int = 3 - a - bb
					var pts := []
					for sc in [-1.0, 1.0]:
						var p1 := origin
						var p2 := origin
						p1[a] = sa * (harr[a] - b)
						p1[bb] = sb * harr[bb]
						p2[a] = sa * harr[a]
						p2[bb] = sb * (harr[bb] - b)
						p1[free] = sc * harr[free]
						p2[free] = sc * harr[free]
						pts.append([p1, p2])
					var corners := [pts[0][0], pts[1][0], pts[1][1], pts[0][1]]
					quad(key, corners, n)
	# 8 corner triangles
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var n := Vector3(sx, sy, sz).normalized()
				var v1 := origin + Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b))
				var v2 := origin + Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b))
				var v3 := origin + Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)
				tri(key, v1, v2, v3, n, metric_uv(v1, n), metric_uv(v2, n), metric_uv(v3, n))


## Thin plate, mostly used for panels and trims.
func plate(key: String, size: Vector3, origin: Vector3 = Vector3.ZERO) -> void:
	box(key, size, origin)


# --------------------------------------------------------------- cylinders ---
func cyl(key: String, r0: float, r1: float, h: float, segs: int,
		origin: Vector3 = Vector3.ZERO, caps: bool = true, y0: float = 0.0) -> void:
	var step := TAU / float(segs)
	var slope := (r0 - r1) / maxf(h, 0.0001)
	for i in segs:
		var a0 := i * step
		var a1 := (i + 1) * step
		var n0 := Vector3(cos(a0), slope, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), slope, sin(a1)).normalized()
		var p00 := origin + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p01 := origin + Vector3(cos(a0) * r1, y0 + h, sin(a0) * r1)
		var p10 := origin + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var p11 := origin + Vector3(cos(a1) * r1, y0 + h, sin(a1) * r1)
		var rmid := (r0 + r1) * 0.5
		quad_n(key, [p00, p10, p11, p01], [n0, n1, n1, n0],
			[Vector2(a0 * rmid, 0.0), Vector2(a1 * rmid, 0.0),
			 Vector2(a1 * rmid, h), Vector2(a0 * rmid, h)])
	if caps:
		if r1 > 0.001:
			var ring := []
			for i in segs:
				var a := i * step
				ring.append(origin + Vector3(cos(a) * r1, y0 + h, sin(a) * r1))
			poly(key, ring, Vector3.UP)
		if r0 > 0.001:
			var ring2 := []
			for i in segs:
				var a := i * step
				ring2.append(origin + Vector3(cos(a) * r0, y0, sin(a) * r0))
			poly(key, ring2, Vector3.DOWN)


## Revolve a (radius, height) profile around the local Y axis.
func lathe(key: String, profile: Array, segs: int, origin: Vector3 = Vector3.ZERO,
		angle: float = TAU, offset_angle: float = 0.0, caps: bool = true,
		flip: bool = false) -> void:
	var step := angle / float(segs)
	# profile normals from segment tangents
	var pn: Array = []
	for k in profile.size():
		var nsum := Vector2.ZERO
		if k > 0:
			var d0: Vector2 = (profile[k] - profile[k - 1])
			nsum += Vector2(d0.y, -d0.x).normalized()
		if k < profile.size() - 1:
			var d1: Vector2 = (profile[k + 1] - profile[k])
			nsum += Vector2(d1.y, -d1.x).normalized()
		pn.append(nsum.normalized() if nsum.length() > 0.0001 else Vector2.UP)
	var vdist := 0.0
	for k in profile.size() - 1:
		var p0: Vector2 = profile[k]
		var p1: Vector2 = profile[k + 1]
		var nr0: Vector2 = pn[k]
		var nr1: Vector2 = pn[k + 1]
		var seglen := p0.distance_to(p1)
		var u0 := 0.0
		for i in segs:
			var a0 := offset_angle + i * step
			var a1 := offset_angle + (i + 1) * step
			var q00 := origin + Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var q01 := origin + Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var q10 := origin + Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var q11 := origin + Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var n00 := Vector3(cos(a0) * nr0.x, nr0.y, sin(a0) * nr0.x).normalized()
			var n01 := Vector3(cos(a0) * nr1.x, nr1.y, sin(a0) * nr1.x).normalized()
			var n10 := Vector3(cos(a1) * nr0.x, nr0.y, sin(a1) * nr0.x).normalized()
			var n11 := Vector3(cos(a1) * nr1.x, nr1.y, sin(a1) * nr1.x).normalized()
			if flip:
				n00 = -n00; n01 = -n01; n10 = -n10; n11 = -n11
			var uu0 := (a0 - offset_angle) * maxf(p0.x, 0.01)
			var uu1 := (a1 - offset_angle) * maxf(p0.x, 0.01)
			quad_n(key, [q00, q10, q11, q01], [n00, n10, n11, n01],
				[Vector2(uu0, vdist), Vector2(uu1, vdist),
				 Vector2(uu1, vdist + seglen), Vector2(uu0, vdist + seglen)])
		vdist += seglen
	# close caps if profile endpoints are off-axis
	if caps and profile[0].x > 0.001 and absf(profile[0].y - profile[1].y) > 0.0001:
		var ring := []
		for i in segs:
			var a := offset_angle + i * step
			ring.append(origin + Vector3(cos(a) * profile[0].x, profile[0].y, sin(a) * profile[0].x))
		poly(key, ring, Vector3.DOWN)
	if caps and profile[profile.size() - 1].x > 0.001 and absf(profile[profile.size() - 1].y - profile[profile.size() - 2].y) > 0.0001:
		var ring2 := []
		for i in segs:
			var a := offset_angle + i * step
			ring2.append(origin + Vector3(cos(a) * profile[-1].x, profile[-1].y, sin(a) * profile[-1].x))
		poly(key, ring2, Vector3.UP)


func torus(key: String, major: float, minor: float, segs_major: int, segs_minor: int,
		origin: Vector3 = Vector3.ZERO) -> void:
	var fm := TAU / float(segs_major)
	var fn := TAU / float(segs_minor)
	for i in segs_major:
		var a0 := i * fm
		var a1 := (i + 1) * fm
		for j in segs_minor:
			var b0 := j * fn
			var b1 := (j + 1) * fn
			var p := func(a: float, b: float) -> Vector3:
				var rr := major + minor * cos(b)
				return origin + Vector3(cos(a) * rr, minor * sin(b), sin(a) * rr)
			var n := func(a: float, b: float) -> Vector3:
				return Vector3(cos(a) * cos(b), sin(b), sin(a) * cos(b))
			quad_n(key, [p.call(a0, b0), p.call(a1, b0), p.call(a1, b1), p.call(a0, b1)],
				[n.call(a0, b0), n.call(a1, b0), n.call(a1, b1), n.call(a0, b1)],
				[Vector2(a0 * major, b0 * minor), Vector2(a1 * major, b0 * minor),
				 Vector2(a1 * major, b1 * minor), Vector2(a0 * major, b1 * minor)])


func sphere(key: String, radius: float, segs: int, origin: Vector3 = Vector3.ZERO) -> void:
	var profile := []
	for i in range(1, 12):
		var a := PI * float(i) / 12.0
		profile.append(Vector2(sin(a) * radius, -cos(a) * radius))
	lathe(key, profile, segs, origin)


# ------------------------------------------------------------------- tube ----
## Sweep a circle along a polyline using parallel-transport frames.
func tube(key: String, points: Array, radius: float, segs: int, caps: bool = true) -> void:
	if points.size() < 2:
		return
	var frames := []
	var prev_n := Vector3.ZERO
	for i in points.size():
		var t: Vector3
		if i == 0:
			t = (points[1] - points[0]).normalized()
		elif i == points.size() - 1:
			t = (points[i] - points[i - 1]).normalized()
		else:
			t = (points[i + 1] - points[i - 1]).normalized()
		var n: Vector3
		if i == 0:
			var arb := Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT
			n = t.cross(arb).normalized()
		else:
			n = (prev_n - t * prev_n.dot(t)).normalized()
			if n.length() < 0.01:
				n = t.cross(Vector3.UP).normalized()
		var b := t.cross(n).normalized()
		frames.append([n, b, t])
		prev_n = n
	var step := TAU / float(segs)
	var total := 0.0
	for i in points.size() - 1:
		var p0: Vector3 = points[i]
		var p1: Vector3 = points[i + 1]
		var seglen := p0.distance_to(p1)
		var f0: Array = frames[i]
		var f1: Array = frames[i + 1]
		for j in segs:
			var a0 := j * step
			var a1 := (j + 1) * step
			var n0: Vector3 = f0[0] * cos(a0) + f0[1] * sin(a0)
			var n1: Vector3 = f0[0] * cos(a1) + f0[1] * sin(a1)
			var n2: Vector3 = f1[0] * cos(a1) + f1[1] * sin(a1)
			var n3: Vector3 = f1[0] * cos(a0) + f1[1] * sin(a0)
			var q00: Vector3 = p0 + n0 * radius
			var q10: Vector3 = p0 + n1 * radius
			var q11: Vector3 = p1 + n2 * radius
			var q01: Vector3 = p1 + n3 * radius
			quad_n(key, [q00, q10, q11, q01], [n0, n1, n2, n3],
				[Vector2(a0 * radius, total), Vector2(a1 * radius, total),
				 Vector2(a1 * radius, total + seglen), Vector2(a0 * radius, total + seglen)])
		total += seglen
	if caps:
		var f_first: Array = frames[0]
		var c0: Vector3 = points[0]
		var ring := []
		for j in segs:
			var a := j * step
			ring.append(c0 + (f_first[0] * cos(a) + f_first[1] * sin(a)) * radius)
		poly(key, ring, -f_first[2])
		var f_last: Array = frames[-1]
		var c1: Vector3 = points[-1]
		var ring2 := []
		for j in segs:
			var a := j * step
			ring2.append(c1 + (f_last[0] * cos(a) + f_last[1] * sin(a)) * radius)
		poly(key, ring2, f_last[2])


# ------------------------------------------------------------------ prism ----
## Extrude a 2D profile (local XY) along local Z.
func prism(key: String, profile: Array, depth: float, origin: Vector3 = Vector3.ZERO) -> void:
	var hz := depth * 0.5
	for i in profile.size():
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[(i + 1) % profile.size()]
		var p0 := origin + Vector3(a.x, a.y, -hz)
		var p1 := origin + Vector3(b.x, b.y, -hz)
		var p2 := origin + Vector3(b.x, b.y, hz)
		var p3 := origin + Vector3(a.x, a.y, hz)
		var n := Vector3(b.y - a.y, -(b.x - a.x), 0.0).normalized()
		quad(key, [p0, p1, p2, p3], n,
			[Vector2(0.0, 0.0), Vector2(a.distance_to(b), 0.0),
			 Vector2(a.distance_to(b), depth), Vector2(0.0, depth)])
	# caps
	var front := []
	var back := []
	for i in profile.size():
		front.append(origin + Vector3(profile[i].x, profile[i].y, hz))
		back.append(origin + Vector3(profile[i].x, profile[i].y, -hz))
	poly(key, front, Vector3.BACK)
	poly(key, back, Vector3.FORWARD)


# ------------------------------------------------------ parametric surface ---
## Evaluate f(u, v) on a regular grid with analytic (finite difference) normals.
func param(key: String, f: Callable, u0: float, u1: float, nu: int,
		v0: float, v1: float, nv: int, uv_scale: Vector2 = Vector2.ONE,
		flip: bool = false) -> void:
	var eps_u := (u1 - u0) * 0.001
	var eps_v := (v1 - v0) * 0.001
	for i in nu:
		var ua := lerpf(u0, u1, float(i) / nu)
		var ub := lerpf(u0, u1, float(i + 1) / nu)
		for j in nv:
			var va := lerpf(v0, v1, float(j) / nv)
			var vb := lerpf(v0, v1, float(j + 1) / nv)
			var p00: Vector3 = f.call(ua, va)
			var p10: Vector3 = f.call(ub, va)
			var p11: Vector3 = f.call(ub, vb)
			var p01: Vector3 = f.call(ua, vb)
			var du: Vector3 = f.call(ua + eps_u, va) - f.call(ua - eps_u, va)
			var dv: Vector3 = f.call(ua, va + eps_v) - f.call(ua, va - eps_v)
			var n: Vector3 = dv.cross(du).normalized()
			if flip:
				n = -n
			var uv00 := Vector2(ua * uv_scale.x, va * uv_scale.y)
			var uv10 := Vector2(ub * uv_scale.x, va * uv_scale.y)
			var uv11 := Vector2(ub * uv_scale.x, vb * uv_scale.y)
			var uv01 := Vector2(ua * uv_scale.x, vb * uv_scale.y)
			# per-vertex normals sampled at the corners for smooth shading
			var n00 := _normal_at(f, ua, va, eps_u, eps_v)
			var n10 := _normal_at(f, ub, va, eps_u, eps_v)
			var n11 := _normal_at(f, ub, vb, eps_u, eps_v)
			var n01 := _normal_at(f, ua, vb, eps_u, eps_v)
			if flip:
				n00 = -n00
				n10 = -n10
				n11 = -n11
				n01 = -n01
			quad_n(key, [p00, p10, p11, p01], [n00, n10, n11, n01],
				[uv00, uv10, uv11, uv01])


func _normal_at(f: Callable, u: float, v: float, eu: float, ev: float) -> Vector3:
	var du: Vector3 = f.call(u + eu, v) - f.call(u - eu, v)
	var dv: Vector3 = f.call(u, v + ev) - f.call(u, v - ev)
	var n := dv.cross(du).normalized()
	return n


# ------------------------------------------------------------------ commit ---
func commit(parent: Node3D, node_name: String, cast_shadow: bool = true, layers: int = 1) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	for key in _keys:
		if _i[key].size() == 0:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _v[key]
		arrays[Mesh.ARRAY_NORMAL] = _n[key]
		arrays[Mesh.ARRAY_TEX_UV] = _t[key]
		arrays[Mesh.ARRAY_TEX_UV2] = _t2[key]
		arrays[Mesh.ARRAY_COLOR] = _c[key]
		arrays[Mesh.ARRAY_INDEX] = _i[key]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mats[key])
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [node_name, key]
		mi.mesh = mesh
		mi.layers = layers
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	parent.add_child(root)
	total_tris += tri_count
	_clear_geometry()
	return root


func _clear_geometry() -> void:
	for key in _keys:
		_v[key] = PackedVector3Array()
		_n[key] = PackedVector3Array()
		_t[key] = PackedVector2Array()
		_t2[key] = PackedVector2Array()
		_c[key] = PackedColorArray()
		_i[key] = PackedInt32Array()
	tri_count = 0


func triangle_total() -> int:
	return total_tris + tri_count