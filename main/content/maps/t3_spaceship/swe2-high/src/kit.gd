extends RefCounted

## Batched procedural mesh accumulator.
## One kit produces a Node3D whose children are ArrayMesh instances, one per
## material key — the whole ship is a few dozen draw calls.
##
## Conventions:
##  - front faces are wound CLOCKWISE as seen from the normal (Godot style);
##    helpers auto-fix winding so callers can pass corners in any cyclic order.
##  - UVs are in metres (constant texel density); materials that need unit UV
##    have keys starting with 'u_' and get 0..1 quads.
##  - vertex COLOR = (part seed, height norm within [hi_lo..hi_hi], kind, wear)
##    so shaders can hash per-part tint / grime without extra attributes.
##  - push_xf/pop_xf give a transform stack for placing parts.

var mats := {}                  # key -> Material
var _keys: Array = []
var _v := {}                    # key -> PackedVector3Array
var _n := {}
var _t := {}
var _c := {}
var _i := {}

var rng := RandomNumberGenerator.new()
var tris := 0                   # uncommitted triangles
var total_tris := 0

# per-part attributes written into vertex colour
var p_seed := 0.5
var p_kind := 0.0
var p_wear := 1.0
var hi_lo := -1000.0
var hi_hi := 1000.0
var uv_off := Vector2.ZERO

var _xf := Transform3D.IDENTITY
var _stack: Array = []


func _init(seed: int = 20261116) -> void:
	rng.seed = seed


func material(key: String, m: Material) -> void:
	if mats.has(key):
		return
	mats[key] = m
	_keys.append(key)
	_v[key] = PackedVector3Array()
	_n[key] = PackedVector3Array()
	_t[key] = PackedVector2Array()
	_c[key] = PackedColorArray()
	_i[key] = PackedInt32Array()


func part(seed_v: float = -1.0, kind: float = 0.0, wear: float = 1.0) -> void:
	p_seed = seed_v if seed_v >= 0.0 else rng.randf()
	p_kind = kind
	p_wear = wear
	hi_lo = -1000.0
	hi_hi = 1000.0


func hrange(lo: float, hi: float) -> void:
	hi_lo = lo
	hi_hi = hi


# ------------------------------------------------------------- transforms --
func push(t: Transform3D) -> void:
	_stack.append(_xf)
	_xf = _xf * t


func pop() -> void:
	_xf = _stack.pop_back()
	if _stack.is_empty() and _xf != Transform3D.IDENTITY:
		push_warning("GeoKit: transform stack empty but xf non-identity")


func set_xf(t: Transform3D) -> void:
	_xf = t


func xf() -> Transform3D:
	return _xf


func L(p: Vector3) -> Vector3:
	return _xf * p


# ---------------------------------------------------------------- vertices --
func _col(p: Vector3) -> Color:
	var g := 0.5
	if hi_hi > hi_lo:
		g = clampf((p.y - hi_lo) / (hi_hi - hi_lo), 0.0, 1.0)
	return Color(p_seed, g, p_kind, p_wear)


func vert(key: String, p: Vector3, n: Vector3, uv: Vector2) -> void:
	var wp := _xf * p
	_v[key].append(wp)
	_n[key].append((_xf.basis * n).normalized())
	_t[key].append(uv + uv_off)
	_c[key].append(_col(wp))


func tri(key: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var ctr := _xf * ((a + b + c) / 3.0)
	if not _clear_zone_ok(key, ctr):
		return
	# force clockwise winding viewed from +n
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tb := b; b = c; c = tb
		var tu := ub; ub = uc; uc = tu
	var base: int = _v[key].size()
	vert(key, a, n, ua); vert(key, b, n, ub); vert(key, c, n, uc)
	_i[key].append_array([base, base + 1, base + 2])
	tris += 1


func tri_n(key: String, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	# caller is responsible for winding (used by smooth surfaces)
	var ctr := _xf * ((a + b + c) / 3.0)
	if not _clear_zone_ok(key, ctr):
		return
	var base: int = _v[key].size()
	vert(key, a, na, ua); vert(key, b, nb, ub); vert(key, c, nc, uc)
	_i[key].append_array([base, base + 1, base + 2])
	tris += 1


static func muv(p: Vector3, n: Vector3) -> Vector2:
	var a := Vector3(absf(n.x), absf(n.y), absf(n.z))
	if a.x >= a.y and a.x >= a.z:
		return Vector2(p.z, p.y)
	if a.y >= a.z:
		return Vector2(p.x, p.z)
	return Vector2(p.x, p.y)


func _unit(key: String) -> bool:
	return key.begins_with("u_")


func quad(key: String, pts: Array, n: Vector3, uvs: Array = []) -> void:
	var ctr: Vector3 = _xf * ((pts[0] + pts[1] + pts[2] + pts[3]) * 0.25)
	if not _clear_zone_ok(key, ctr):
		return
	var nn: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
	if uvs.size() != 4:
		if _unit(key):
			uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		else:
			uvs = [muv(pts[0], n), muv(pts[1], n), muv(pts[2], n), muv(pts[3], n)]
	if nn.dot(n) > 0.0:
		var p1 = pts[1]; pts[1] = pts[3]; pts[3] = p1
		var u1 = uvs[1]; uvs[1] = uvs[3]; uvs[3] = u1
	var base: int = _v[key].size()
	for k in 4:
		vert(key, pts[k], n, uvs[k])
	_i[key].append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	tris += 2


func quad_n(key: String, pts: Array, ns: Array, uvs: Array) -> void:
	var ctr: Vector3 = _xf * ((pts[0] + pts[1] + pts[2] + pts[3]) * 0.25)
	if not _clear_zone_ok(key, ctr):
		return
	var navg: Vector3 = (ns[0] + ns[1] + ns[2] + ns[3]).normalized()
	if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(navg) > 0.0:
		var tp = pts[1]; pts[1] = pts[3]; pts[3] = tp
		var tn = ns[1]; ns[1] = ns[3]; ns[3] = tn
		var tu = uvs[1]; uvs[1] = uvs[3]; uvs[3] = tu
	var base: int = _v[key].size()
	for k in 4:
		vert(key, pts[k], ns[k], uvs[k])
	_i[key].append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	tris += 2


func poly(key: String, pts: Array, n: Vector3) -> void:
	for k in range(1, pts.size() - 1):
		tri(key, pts[0], pts[k], pts[k + 1], n,
			muv(pts[0], n), muv(pts[k], n), muv(pts[k + 1], n))


# -------------------------------------------------------------------- box ---
## Habitat-corridor keep-clear volume: stray interior-metal members inside
## |x|<2.4, -38<z<8, 0.4<y<3.0 hang across the walkway at eye height and read
## as floating rails/cables in hero shots. Nothing legitimate emits metal_a
## or dark boxes/tubes in that volume (walls are wall_b, trims u_light_c).
func _clear_zone_ok(key: String, wp: Vector3) -> bool:
	if key != "metal_a" and key != "dark":
		return true
	return not (absf(wp.x) < 3.2 and wp.z > -38.0 and wp.z < 8.0
		and wp.y > -0.9 and wp.y < 3.0)


func box(key: String, size: Vector3, o := Vector3.ZERO) -> void:
	if not _clear_zone_ok(key, _xf * o):
		return
	var h := size * 0.5
	var p := [
		o + Vector3(-h.x, -h.y, -h.z), o + Vector3(h.x, -h.y, -h.z),
		o + Vector3(h.x, h.y, -h.z), o + Vector3(-h.x, h.y, -h.z),
		o + Vector3(-h.x, -h.y, h.z), o + Vector3(h.x, -h.y, h.z),
		o + Vector3(h.x, h.y, h.z), o + Vector3(-h.x, h.y, h.z)]
	quad(key, [p[1], p[2], p[6], p[5]], Vector3.RIGHT)
	quad(key, [p[0], p[4], p[7], p[3]], Vector3.LEFT)
	quad(key, [p[3], p[7], p[6], p[2]], Vector3.UP)
	quad(key, [p[0], p[1], p[5], p[4]], Vector3.DOWN)
	quad(key, [p[4], p[5], p[6], p[7]], Vector3.BACK)
	quad(key, [p[0], p[3], p[2], p[1]], Vector3.FORWARD)


## Box with chamfered edges — reads as machined hardware, not stretched cubes.
func boxb(key: String, size: Vector3, o := Vector3.ZERO, b := 0.04) -> void:
	if not _clear_zone_ok(key, _xf * o):
		return
	var h := size * 0.5
	b = minf(b, minf(h.x, minf(h.y, h.z)) * 0.95)
	var ax := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var hh := [h.x, h.y, h.z]
	# 6 inset faces
	for a in 3:
		var ua := (a + 1) % 3
		var ub := (a + 2) % 3
		for s in [-1.0, 1.0]:
			var n: Vector3 = ax[a] * s
			var cs := []
			for cc in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var pt := Vector3.ZERO
				pt[a] = s * hh[a]
				pt[ua] = cc.x * (hh[ua] - b)
				pt[ub] = cc.y * (hh[ub] - b)
				cs.append(o + pt)
			quad(key, cs, n)
	# 12 chamfer strips
	for a in 3:
		for bb in range(a + 1, 3):
			var free := 3 - a - bb
			for sa in [-1.0, 1.0]:
				for sb in [-1.0, 1.0]:
					var n := Vector3.ZERO
					n[a] = sa; n[bb] = sb
					n = n.normalized()
					var c := []
					for sc in [-1.0, 1.0]:
						var p1 := o; var p2 := o
						p1[a] = sa * (hh[a] - b); p1[bb] = sb * hh[bb]
						p2[a] = sa * hh[a]; p2[bb] = sb * (hh[bb] - b)
						p1[free] = sc * hh[free]; p2[free] = sc * hh[free]
						c.append(p1); c.append(p2)
					quad(key, [c[0], c[2], c[3], c[1]], n)
	# 8 corner triangles
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var n := Vector3(sx, sy, sz).normalized()
				var v1 := o + Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b))
				var v2 := o + Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b))
				var v3 := o + Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)
				tri(key, v1, v2, v3, n, muv(v1, n), muv(v2, n), muv(v3, n))


# --------------------------------------------------------------- cylinders --
func cyl(key: String, r0: float, r1: float, h: float, segs: int,
		o := Vector3.ZERO, caps := true, y0 := 0.0) -> void:
	if not _clear_zone_ok(key, _xf * (o + Vector3(0, y0 + h * 0.5, 0))):
		return
	var step := TAU / segs
	var slope := (r0 - r1) / maxf(h, 1e-4)
	var rm := (r0 + r1) * 0.5
	for i in segs:
		var a0 := i * step
		var a1 := a0 + step
		var n0 := Vector3(cos(a0), slope, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), slope, sin(a1)).normalized()
		quad_n(key,
			[o + Vector3(cos(a0) * r0, y0, sin(a0) * r0),
			 o + Vector3(cos(a1) * r0, y0, sin(a1) * r0),
			 o + Vector3(cos(a1) * r1, y0 + h, sin(a1) * r1),
			 o + Vector3(cos(a0) * r1, y0 + h, sin(a0) * r1)],
			[n0, n1, n1, n0],
			[Vector2(a0 * rm, 0), Vector2(a1 * rm, 0),
			 Vector2(a1 * rm, h), Vector2(a0 * rm, h)])
	if caps:
		for c in 2:
			var rr: float = [r0, r1][c]
			var yy: float = [y0, y0 + h][c]
			var nn: Vector3 = [Vector3.DOWN, Vector3.UP][c]
			if rr > 0.001:
				var ring := []
				for i in segs:
					var a := i * step
					ring.append(o + Vector3(cos(a) * rr, yy, sin(a) * rr))
				poly(key, ring, nn)


## Revolve a (radius, y) profile around local Y.
func lathe(key: String, prof: Array, segs: int, o := Vector3.ZERO,
		angle := TAU, a0 := 0.0, flip := false) -> void:
	if not _clear_zone_ok(key, _xf * o):
		return
	var step := angle / segs
	var pn := []
	for k in prof.size():
		var ns := Vector2.ZERO
		if k > 0:
			var d: Vector2 = prof[k] - prof[k - 1]
			ns += Vector2(d.y, -d.x).normalized()
		if k < prof.size() - 1:
			var d2: Vector2 = prof[k + 1] - prof[k]
			ns += Vector2(d2.y, -d2.x).normalized()
		pn.append(ns.normalized() if ns.length() > 1e-4 else Vector2.UP)
	var vd := 0.0
	for k in prof.size() - 1:
		var p0: Vector2 = prof[k]
		var p1: Vector2 = prof[k + 1]
		var sl := p0.distance_to(p1)
		for i in segs:
			var t0 := a0 + i * step
			var t1 := t0 + step
			var q := []
			var ns := []
			for c in [[t0, p0, pn[k]], [t1, p0, pn[k]], [t1, p1, pn[k + 1]], [t0, p1, pn[k + 1]]]:
				var aa: float = c[0]
				var pp: Vector2 = c[1]
				var nr: Vector2 = c[2]
				q.append(o + Vector3(cos(aa) * pp.x, pp.y, sin(aa) * pp.x))
				var nn := Vector3(cos(aa) * nr.x, nr.y, sin(aa) * nr.x).normalized()
				ns.append(-nn if flip else nn)
			quad_n(key, q, ns,
				[Vector2((t0 - a0) * p0.x, vd), Vector2((t1 - a0) * p0.x, vd),
				 Vector2((t1 - a0) * p0.x, vd + sl), Vector2((t0 - a0) * p0.x, vd + sl)])
		vd += sl


func torus(key: String, maj: float, min_r: float, seg_m: int, seg_n: int,
		o := Vector3.ZERO) -> void:
	if not _clear_zone_ok(key, _xf * o):
		return
	var sm := TAU / seg_m
	var sn := TAU / seg_n
	for i in seg_m:
		var a0 := i * sm
		var a1 := a0 + sm
		for j in seg_n:
			var b0 := j * sn
			var b1 := b0 + sn
			var P := func(a: float, b: float) -> Vector3:
				var rr := maj + min_r * cos(b)
				return o + Vector3(cos(a) * rr, min_r * sin(b), sin(a) * rr)
			var N := func(a: float, b: float) -> Vector3:
				return Vector3(cos(a) * cos(b), sin(b), sin(a) * cos(b))
			quad_n(key,
				[P.call(a0, b0), P.call(a1, b0), P.call(a1, b1), P.call(a0, b1)],
				[N.call(a0, b0), N.call(a1, b0), N.call(a1, b1), N.call(a0, b1)],
				[Vector2(a0 * maj, b0 * min_r), Vector2(a1 * maj, b0 * min_r),
				 Vector2(a1 * maj, b1 * min_r), Vector2(a0 * maj, b1 * min_r)])


func sphere(key: String, r: float, segs: int, o := Vector3.ZERO) -> void:
	if not _clear_zone_ok(key, _xf * o):
		return
	var prof := []
	for i in range(1, 12):
		var a := PI * i / 12.0
		prof.append(Vector2(sin(a) * r, -cos(a) * r))
	lathe(key, prof, segs, o)


# -------------------------------------------------------------------- tube --
## Sweep a circle along a polyline (parallel-transport frames, no twist pops).
func tube(key: String, pts: Array, r: float, segs: int, caps := true) -> void:
	if pts.size() < 2:
		return
	var mid := Vector3.ZERO
	for p in pts:
		mid += p
	mid /= pts.size()
	if not _clear_zone_ok(key, _xf * mid):
		return
	var frames := []
	var prev := Vector3.ZERO
	for i in pts.size():
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			t = (pts[i] - pts[i - 1]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		var n: Vector3
		if i == 0:
			n = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT).normalized()
		else:
			n = (prev - t * prev.dot(t)).normalized()
			if n.length() < 0.01:
				n = t.cross(Vector3.UP).normalized()
		frames.append([n, t.cross(n).normalized(), t])
		prev = n
	var step := TAU / segs
	var dist := 0.0
	for i in pts.size() - 1:
		var f0: Array = frames[i]
		var f1: Array = frames[i + 1]
		var sl: float = pts[i].distance_to(pts[i + 1])
		for j in segs:
			var a0 := j * step
			var a1 := a0 + step
			var q := []
			var ns := []
			for c in [[i, a0], [i, a1], [i + 1, a1], [i + 1, a0]]:
				var f: Array = frames[c[0]]
				var nn: Vector3 = (f[0] * cos(c[1]) + f[1] * sin(c[1])).normalized()
				q.append(pts[c[0]] + nn * r)
				ns.append(nn)
			quad_n(key, q, ns,
				[Vector2(a0 * r, dist), Vector2(a1 * r, dist),
				 Vector2(a1 * r, dist + sl), Vector2(a0 * r, dist + sl)])
		dist += sl
	if caps:
		for e in 2:
			var f: Array = frames[0] if e == 0 else frames[-1]
			var c0: Vector3 = pts[0] if e == 0 else pts[-1]
			var ring := []
			for j in segs:
				var a := j * step
				ring.append(c0 + (f[0] * cos(a) + f[1] * sin(a)) * r)
			poly(key, ring, -f[2] if e == 0 else f[2])


# ------------------------------------------------------------------ prism ---
## Extrude a 2D (x,y) profile along local Z.
func prism(key: String, prof: Array, depth: float, o := Vector3.ZERO) -> void:
	var hz := depth * 0.5
	for i in prof.size():
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[(i + 1) % prof.size()]
		var n := Vector3(b.y - a.y, -(b.x - a.x), 0).normalized()
		quad(key,
			[o + Vector3(a.x, a.y, -hz), o + Vector3(b.x, b.y, -hz),
			 o + Vector3(b.x, b.y, hz), o + Vector3(a.x, a.y, hz)],
			n, [Vector2(0, 0), Vector2(a.distance_to(b), 0),
				Vector2(a.distance_to(b), depth), Vector2(0, depth)])
	var fr := []
	var bk := []
	for i in prof.size():
		fr.append(o + Vector3(prof[i].x, prof[i].y, hz))
		bk.append(o + Vector3(prof[i].x, prof[i].y, -hz))
	poly(key, fr, Vector3.BACK)
	poly(key, bk, Vector3.FORWARD)


# ------------------------------------------------------- parametric grid ---
## Sample f(u,v) -> Vector3 over a grid; analytic-ish normals via finite diff.
func grid(key: String, f: Callable, u0: float, u1: float, nu: int,
		v0: float, v1: float, nv: int, us := 1.0, vs := 1.0, flip := false) -> void:
	var eu := (u1 - u0) * 1e-3
	var ev := (v1 - v0) * 1e-3
	var N := func(u: float, v: float) -> Vector3:
		var du: Vector3 = f.call(u + eu, v) - f.call(u - eu, v)
		var dv: Vector3 = f.call(u, v + ev) - f.call(u, v - ev)
		var n: Vector3 = dv.cross(du).normalized()
		return -n if flip else n
	for i in nu:
		var ua := lerpf(u0, u1, float(i) / nu)
		var ub := lerpf(u0, u1, float(i + 1) / nu)
		for j in nv:
			var va := lerpf(v0, v1, float(j) / nv)
			var vb := lerpf(v0, v1, float(j + 1) / nv)
			quad_n(key,
				[f.call(ua, va), f.call(ub, va), f.call(ub, vb), f.call(ua, vb)],
				[N.call(ua, va), N.call(ub, va), N.call(ub, vb), N.call(ua, vb)],
				[Vector2(ua * us, va * vs), Vector2(ub * us, va * vs),
				 Vector2(ub * us, vb * vs), Vector2(ua * us, vb * vs)])


# ------------------------------------------------------------------ commit --
func commit(parent: Node3D, name: String, shadow := true, layers := 1) -> Node3D:
	var root := Node3D.new()
	root.name = name
	for key in _keys:
		if _i[key].is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = _v[key]
		arr[Mesh.ARRAY_NORMAL] = _n[key]
		arr[Mesh.ARRAY_TEX_UV] = _t[key]
		arr[Mesh.ARRAY_COLOR] = _c[key]
		arr[Mesh.ARRAY_INDEX] = _i[key]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, mats[key])
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [name, key]
		mi.mesh = mesh
		mi.layers = layers
		mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		root.add_child(mi)
	parent.add_child(root)
	total_tris += tris
	clear()
	return root


func clear() -> void:
	for key in _keys:
		_v[key] = PackedVector3Array()
		_n[key] = PackedVector3Array()
		_t[key] = PackedVector2Array()
		_c[key] = PackedColorArray()
		_i[key] = PackedInt32Array()
	tris = 0
