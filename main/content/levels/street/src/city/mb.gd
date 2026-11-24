## MB — procedural mesh builder.
##
## Accumulates flat-shaded triangles with per-vertex procedural surface params:
##   UV     : surface coordinates in METERS (auto-projected per face)
##   COLOR  : linear-space tint
##   CUSTOM0: (material_id, style, seed, emissive_strength)
##
## Geometry is split into 2 surfaces at commit: opaque (uber shader) and glass.
class_name MB
extends RefCounted

class Sub:
	var P := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var U := PackedVector2Array()
	var A := PackedByteArray()
	var I := PackedInt32Array()

	func vcount() -> int:
		return P.size()


var xf := Transform3D.IDENTITY
var _xf_stack: Array[Transform3D] = []

var tint := Color(1, 1, 1)
var mat: int = 0
var sty: float = 0.0
var sd: float = 0.0
var em: float = 0.0
var uvs: float = 1.0

var _subs: Array = [Sub.new(), Sub.new()]
var _cur: Sub = _subs[0]

func _init() -> void:
	_cur = _subs[0]

func setm(m: int, t: Color, s: float = 0.0, e: float = 0.0, style: float = 0.0) -> MB:
	mat = m
	tint = t
	sd = s
	em = e
	sty = style
	return self

func tinted(t: Color) -> MB:
	tint = t
	return self

func push(t: Transform3D) -> void:
	_xf_stack.append(xf)
	xf = xf * t

func pop() -> void:
	if _xf_stack.size() > 0:
		xf = _xf_stack.pop_back()

func reset_xf() -> void:
	xf = Transform3D.IDENTITY
	_xf_stack.clear()

func vert(local: Vector3, nrm: Vector3) -> void:
	var wp: Vector3 = xf * local
	var wn: Vector3 = (xf.basis * nrm).normalized()
	var uv: Vector2
	if absf(wn.y) > 0.72:
		uv = Vector2(wp.x, wp.z)
	else:
		var t := Vector3(wn.z, 0.0, -wn.x)
		if t.length_squared() < 1e-12:
			t = Vector3.RIGHT
		t = t.normalized()
		uv = Vector2(wp.dot(t), wp.y)
	uv *= uvs
	_cur.P.append(wp)
	_cur.N.append(wn)
	_cur.C.append(tint)
	_cur.U.append(uv)
	_cur.A.append(mat & 0xFF)
	_cur.A.append(int(sty) & 0xFF)
	_cur.A.append(clampi(int(sd * 255.0), 0, 255))
	_cur.A.append(clampi(int(em * 50.0), 0, 255))

func vert_uv(local: Vector3, nrm: Vector3, uv: Vector2) -> void:
	var wp: Vector3 = xf * local
	var wn: Vector3 = (xf.basis * nrm).normalized()
	_cur.P.append(wp)
	_cur.N.append(wn)
	_cur.C.append(tint)
	_cur.U.append(uv)
	_cur.A.append(mat & 0xFF)
	_cur.A.append(int(sty) & 0xFF)
	_cur.A.append(clampi(int(sd * 255.0), 0, 255))
	_cur.A.append(clampi(int(em * 50.0), 0, 255))

func _begin() -> void:
	_cur = _subs[1] if mat == M.GLASS else _subs[0]

func tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	var l := n.length()
	if l < 1e-10:
		return
	n /= l
	_begin()
	var i := _cur.vcount()
	vert(a, n)
	vert(b, n)
	vert(c, n)
	_cur.I.append(i)
	_cur.I.append(i + 2)
	_cur.I.append(i + 1)

func tri_n(a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	_begin()
	var i := _cur.vcount()
	vert(a, n)
	vert(b, n)
	vert(c, n)
	_cur.I.append(i)
	_cur.I.append(i + 2)
	_cur.I.append(i + 1)

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(d - a)
	var l := n.length()
	if l < 1e-10:
		# degenerate, still try second diagonal
		n = (c - a).cross(d - b)
		l = n.length()
		if l < 1e-10:
			return
	n /= l
	quad_n(a, b, c, d, n)

func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_begin()
	var i := _cur.vcount()
	vert(a, n)
	vert(b, n)
	vert(c, n)
	vert(d, n)
	_cur.I.append(i)
	_cur.I.append(i + 2)
	_cur.I.append(i + 1)
	_cur.I.append(i)
	_cur.I.append(i + 3)
	_cur.I.append(i + 2)

func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2) -> void:
	var n := (b - a).cross(d - a)
	var l := n.length()
	if l < 1e-10:
		return
	n /= l
	_begin()
	var i := _cur.vcount()
	vert_uv(a, n, uva)
	vert_uv(b, n, uvb)
	vert_uv(c, n, uvc)
	vert_uv(d, n, uvd)
	_cur.I.append(i)
	_cur.I.append(i + 2)
	_cur.I.append(i + 1)
	_cur.I.append(i)
	_cur.I.append(i + 3)
	_cur.I.append(i + 2)

# ---------------------------------------------------------------- primitives

func box(center: Vector3, size: Vector3, top := true, bottom := true,
		px := true, nx := true, pz := true, nz := true) -> void:
	var h := size * 0.5
	var x0 := center.x - h.x
	var x1 := center.x + h.x
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	var z0 := center.z - h.z
	var z1 := center.z + h.z
	if px:
		quad(Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1))
	if nx:
		quad(Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x0, y0, z0))
	if top:
		quad(Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0))
	if bottom:
		quad(Vector3(x0, y0, z1), Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1))
	if pz:
		quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1))
	if nz:
		quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0))

## Oriented box: basis must be orthonormal.
func obox(center: Vector3, size: Vector3, basis: Basis, top := true) -> void:
	var h := size * 0.5
	var c := [
		center + basis * Vector3(-h.x, -h.y, -h.z),
		center + basis * Vector3(h.x, -h.y, -h.z),
		center + basis * Vector3(h.x, -h.y, h.z),
		center + basis * Vector3(-h.x, -h.y, h.z),
		center + basis * Vector3(-h.x, h.y, -h.z),
		center + basis * Vector3(h.x, h.y, -h.z),
		center + basis * Vector3(h.x, h.y, h.z),
		center + basis * Vector3(-h.x, h.y, h.z),
	]
	quad(c[1], c[5], c[6], c[2])
	quad(c[3], c[7], c[4], c[0])
	if top:
		quad(c[4], c[7], c[6], c[5])
	quad(c[4], c[5], c[1], c[0])
	quad(c[3], c[2], c[6], c[7])
	quad(c[0], c[1], c[2], c[3])

func box_frame(a: Vector3, b: Vector3, thickness: float) -> void:
	# square beam between two points
	var d := b - a
	var l := d.length()
	if l < 1e-5:
		return
	var n := d / l
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
	var t1 := n.cross(up).normalized()
	var t2 := n.cross(t1).normalized()
	var bs := Basis(t1, t2, n)
	var c := (a + b) * 0.5
	obox(c, Vector3(thickness, thickness, l), bs)

func prism(poly: PackedVector2Array, y0: float, y1: float, cap_top := true,
		cap_bottom := false, side_mask := -1) -> void:
	if poly.size() < 3:
		return
	var p := _ccw(poly)
	var n := p.size()
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		if side_mask >= 0 and not (side_mask & (1 << i)):
			continue
		var e := b - a
		var ln := e.length()
		if ln < 1e-6:
			continue
		var n2 := Vector2(e.y, -e.x) / ln
		quad(Vector3(a.x, y0, a.y), Vector3(a.x, y1, a.y),
			Vector3(b.x, y1, b.y), Vector3(b.x, y0, b.y))
	# normals are auto-computed from winding; ensure outward via ccw + order above
	if cap_top:
		var tris := _ear(p)
		for t in tris:
			var a := p[t[0]]
			var b := p[t[1]]
			var c := p[t[2]]
			tri_n(Vector3(a.x, y1, a.y), Vector3(c.x, y1, c.y), Vector3(b.x, y1, b.y), Vector3.UP)
	if cap_bottom:
		var tris2 := _ear(p)
		for t in tris2:
			var a := p[t[0]]
			var b := p[t[1]]
			var c := p[t[2]]
			tri_n(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(c.x, y0, c.y), Vector3.DOWN)

## Extrude a polygon with per-vertex top height (allows sloped roofs).
func prism_h(poly: PackedVector2Array, y0: float, heights: PackedFloat32Array,
		cap_top := true, cap_bottom := false) -> void:
	if poly.size() < 3:
		return
	var p := _ccw(poly)
	var n := p.size()
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		var ha := heights[i]
		var hb := heights[(i + 1) % n]
		quad(Vector3(a.x, y0, a.y), Vector3(a.x, y0 + ha, a.y),
			Vector3(b.x, y0 + hb, b.y), Vector3(b.x, y0, b.y))
	if cap_top:
		var tris := _ear(p)
		for t in tris:
			var a := p[t[0]]
			var b := p[t[1]]
			var c := p[t[2]]
			tri(Vector3(a.x, y0 + heights[t[0]], a.y),
				Vector3(c.x, y0 + heights[t[2]], c.y),
				Vector3(b.x, y0 + heights[t[1]], b.y))
	if cap_bottom:
		var tris2 := _ear(p)
		for t in tris2:
			var a := p[t[0]]
			var b := p[t[1]]
			var c := p[t[2]]
			tri_n(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(c.x, y0, c.y), Vector3.DOWN)

func cyl_y(center: Vector3, r: float, h: float, segs: int, caps := true,
		r_top := -1.0, a0 := 0.0, a1 := TAU) -> void:
	if r_top < 0.0:
		r_top = r
	var y0 := center.y - h * 0.5
	var y1 := center.y + h * 0.5
	for i in segs:
		var t0 := a0 + (a1 - a0) * float(i) / segs
		var t1 := a0 + (a1 - a0) * float(i + 1) / segs
		var d0 := Vector3(cos(t0), 0, sin(t0))
		var d1 := Vector3(cos(t1), 0, sin(t1))
		var p00 := center + d0 * r
		var p01 := center + d1 * r
		var p10 := center + d1 * r_top
		var p11 := center + d0 * r_top
		p00.y = y0
		p01.y = y0
		p10.y = y1
		p11.y = y1
		# smooth-ish normal: radial
		_begin()
		var idx := _cur.vcount()
		var n0 := (d0 + d1).normalized() if r == r_top else (d0 + d1).normalized()
		vert(p00, n0)
		vert(p01, n0)
		vert(p10, n0)
		vert(p11, n0)
		_cur.I.append(idx)
		_cur.I.append(idx + 2)
		_cur.I.append(idx + 1)
		_cur.I.append(idx)
		_cur.I.append(idx + 3)
		_cur.I.append(idx + 2)
	if caps:
		# top
		_begin()
		var tc := _cur.vcount()
		vert(center + Vector3(0, h * 0.5, 0), Vector3.UP)
		for i in segs:
			var t0 := a0 + (a1 - a0) * float(i) / segs
			var d0 := Vector3(cos(t0), 0, sin(t0)) * r_top
			var p0 := center + d0
			p0.y = y1
			vert(p0, Vector3.UP)
		for i in segs:
			_cur.I.append(tc)
			_cur.I.append(tc + 1 + (i + 1) % segs)
			_cur.I.append(tc + 1 + i)
		_begin()
		var bc := _cur.vcount()
		vert(center + Vector3(0, -h * 0.5, 0), Vector3.DOWN)
		for i in segs:
			var t0 := a0 + (a1 - a0) * float(i) / segs
			var d0 := Vector3(cos(t0), 0, sin(t0)) * r
			var p0 := center + d0
			p0.y = y0
			vert(p0, Vector3.DOWN)
		for i in segs:
			_cur.I.append(bc)
			_cur.I.append(bc + 1 + i)
			_cur.I.append(bc + 1 + (i + 1) % segs)

func sphere(center: Vector3, r: float, segs := 12, rings := 8, squash := 1.0) -> void:
	for j in rings:
		var v0 := float(j) / rings
		var v1 := float(j + 1) / rings
		for i in segs:
			var u0 := float(i) / segs
			var u1 := float(i + 1) / segs
			var p00 := _sph(center, r, u0, v0, squash)
			var p01 := _sph(center, r, u1, v0, squash)
			var p11 := _sph(center, r, u1, v1, squash)
			var p10 := _sph(center, r, u0, v1, squash)
			var n00 := (p00 - center) / r
			var n01 := (p01 - center) / r
			var n11 := (p11 - center) / r
			var n10 := (p10 - center) / r
			_begin()
			var idx := _cur.vcount()
			vert(p00, n00)
			vert(p01, n01)
			vert(p11, n11)
			vert(p10, n10)
			_cur.I.append(idx)
			_cur.I.append(idx + 2)
			_cur.I.append(idx + 1)
			_cur.I.append(idx)
			_cur.I.append(idx + 3)
			_cur.I.append(idx + 2)

func _sph(c: Vector3, r: float, u: float, v: float, squash: float) -> Vector3:
	var phi := u * TAU
	var theta := v * PI
	return c + Vector3(sin(theta) * cos(phi), cos(theta) * squash, sin(theta) * sin(phi)) * r

func dome(center: Vector3, r: float, segs := 16, rings := 6, squash := 0.6) -> void:
	for j in rings:
		var v0 := float(j) / rings * 0.5
		var v1 := float(j + 1) / rings * 0.5
		for i in segs:
			var u0 := float(i) / segs
			var u1 := float(i + 1) / segs
			var p00 := _sph(center, r, u0, v0, squash)
			var p01 := _sph(center, r, u1, v0, squash)
			var p11 := _sph(center, r, u1, v1, squash)
			var p10 := _sph(center, r, u0, v1, squash)
			_begin()
			var idx := _cur.vcount()
			vert(p00, (p00 - center).normalized())
			vert(p01, (p01 - center).normalized())
			vert(p11, (p11 - center).normalized())
			vert(p10, (p10 - center).normalized())
			_cur.I.append(idx)
			_cur.I.append(idx + 2)
			_cur.I.append(idx + 1)
			_cur.I.append(idx)
			_cur.I.append(idx + 3)
			_cur.I.append(idx + 2)

## Revolve a 2D profile (x = radius, y = height) around Y.
func revolve(profile: PackedVector2Array, segs := 16) -> void:
	for j in profile.size() - 1:
		var a := profile[j]
		var b := profile[j + 1]
		var e := b - a
		var nl := Vector2(e.y, -e.x).normalized()
		for i in segs:
			var t0 := float(i) / segs * TAU
			var t1 := float(i + 1) / segs * TAU
			var d0 := Vector3(cos(t0), 0, sin(t0))
			var d1 := Vector3(cos(t1), 0, sin(t1))
			var p00 := d0 * a.x + Vector3(0, a.y, 0)
			var p01 := d1 * a.x + Vector3(0, a.y, 0)
			var p11 := d1 * b.x + Vector3(0, b.y, 0)
			var p10 := d0 * b.x + Vector3(0, b.y, 0)
			var n0 := (d0 * nl.x + Vector3(0, nl.y, 0)).normalized()
			var n1 := (d1 * nl.x + Vector3(0, nl.y, 0)).normalized()
			_begin()
			var idx := _cur.vcount()
			vert(p00, n0)
			vert(p01, n1)
			vert(p11, n1)
			vert(p10, n0)
			_cur.I.append(idx)
			_cur.I.append(idx + 2)
			_cur.I.append(idx + 1)
			_cur.I.append(idx)
			_cur.I.append(idx + 3)
			_cur.I.append(idx + 2)

## Swept profile along a polyline. profile is (right, up) offsets in metres.
func sweep(profile: PackedVector2Array, path: PackedVector3Array, cap := true) -> void:
	var n := path.size()
	if n < 2 or profile.size() < 2:
		return
	var rings: Array[PackedVector3Array] = []
	for i in n:
		var t: Vector3
		if i == 0:
			t = (path[1] - path[0])
		elif i == n - 1:
			t = (path[n - 1] - path[n - 2])
		else:
			t = (path[i + 1] - path[i - 1])
		if t.length_squared() < 1e-10:
			t = Vector3.FORWARD
		t = t.normalized()
		var up := Vector3.UP if absf(t.y) < 0.9 else Vector3.FORWARD
		var right := t.cross(up).normalized()
		var up2 := right.cross(t).normalized()
		var ring := PackedVector3Array()
		for k in profile.size():
			ring.append(path[i] + right * profile[k].x + up2 * profile[k].y)
		rings.append(ring)
	for i in n - 1:
		var ra := rings[i]
		var rb := rings[i + 1]
		for k in profile.size() - 1:
			quad(ra[k], rb[k], rb[k + 1], ra[k + 1])
		# profile is CCW: flip if necessary by comparing normal against up at first segment
	if cap:
		# end caps
		var a0 := rings[0]
		var a1 := rings[n - 1]
		for k in range(1, profile.size() - 1):
			tri(a0[0], a0[k + 1], a0[k])
			tri(a1[0], a1[k], a1[k + 1])

func tube(path: PackedVector3Array, r: float, segs := 8, caps := true) -> void:
	var n := path.size()
	if n < 2:
		return
	var frames: Array = []
	for i in n:
		var t: Vector3
		if i == 0:
			t = path[1] - path[0]
		elif i == n - 1:
			t = path[n - 1] - path[n - 2]
		else:
			t = path[i + 1] - path[i - 1]
		t = t.normalized()
		var up := Vector3.UP if absf(t.y) < 0.9 else Vector3.FORWARD
		var right := t.cross(up).normalized()
		var up2 := right.cross(t).normalized()
		frames.append([right, up2])
	for i in n - 1:
		var pa := path[i]
		var pb := path[i + 1]
		var fa: Array = frames[i]
		var fb: Array = frames[i + 1]
		var ra: Vector3 = fa[0]
		var ua: Vector3 = fa[1]
		var rb: Vector3 = fb[0]
		var ub: Vector3 = fb[1]
		for s in segs:
			var t0 := float(s) / segs * TAU
			var t1 := float(s + 1) / segs * TAU
			var d0 := Vector3(cos(t0), 0, sin(t0))
			var d1 := Vector3(cos(t1), 0, sin(t1))
			var n0a := (ra * d0.x + ua * d0.y).normalized()
			var n0b := (ra * d1.x + ua * d1.y).normalized()
			var n1a := (rb * d0.x + ub * d0.y).normalized()
			var n1b := (rb * d1.x + ub * d1.y).normalized()
			quad_n(pa + n0a * r, pb + n1a * r, pb + n1b * r, pa + n0b * r,
				(n0a + n1a + n0b + n1b).normalized())
	if caps:
		pass

## Flat ribbon on the ground following a polyline (road markings, curbs, cracks).
func ribbon(path: PackedVector3Array, width: float, y := 0.02) -> void:
	var n := path.size()
	if n < 2:
		return
	for i in n - 1:
		var a := path[i]
		var b := path[i + 1]
		var d := b - a
		d.y = 0.0
		if d.length_squared() < 1e-9:
			continue
		d = d.normalized()
		var side := Vector3(-d.z, 0, d.x) * (width * 0.5)
		var p0 := a - side
		var p1 := a + side
		var p2 := b + side
		var p3 := b - side
		p0.y = y
		p1.y = y
		p2.y = y
		p3.y = y
		quad(p0, p1, p2, p3)

## Vertical ribbon facing outward (fences, banners, guard rails).
func wall_ribbon(path: PackedVector3Array, y0: float, y1: float) -> void:
	var n := path.size()
	for i in n - 1:
		var a := path[i]
		var b := path[i + 1]
		var d := b - a
		d.y = 0
		if d.length_squared() < 1e-8:
			continue
		d = d.normalized()
		var side := Vector2(-d.z, d.x)
		_begin()
		var idx := _cur.vcount()
		var nrm := Vector3(side.x, 0, side.y)
		vert(Vector3(a.x, y0, a.z), nrm)
		vert(Vector3(b.x, y0, b.z), nrm)
		vert(Vector3(b.x, y1, b.z), nrm)
		vert(Vector3(a.x, y1, a.z), nrm)
		_cur.I.append(idx)
		_cur.I.append(idx + 2)
		_cur.I.append(idx + 1)
		_cur.I.append(idx)
		_cur.I.append(idx + 3)
		_cur.I.append(idx + 2)

func torus(center: Vector3, R: float, r: float, segs := 16, rsegs := 8) -> void:
	for i in segs:
		var t0 := float(i) / segs * TAU
		var t1 := float(i + 1) / segs * TAU
		for j in rsegs:
			var u0 := float(j) / rsegs * TAU
			var u1 := float(j + 1) / rsegs * TAU
			var p00 := _tor(center, R, r, t0, u0)
			var p01 := _tor(center, R, r, t0, u1)
			var p11 := _tor(center, R, r, t1, u1)
			var p10 := _tor(center, R, r, t1, u0)
			var c0 := Vector3(cos(t0), 0, sin(t0))
			var c1 := Vector3(cos(t1), 0, sin(t1))
			var n00 := (p00 - center - c0 * R).normalized()
			var n01 := (p01 - center - c0 * R).normalized()
			var n11 := (p11 - center - c1 * R).normalized()
			var n10 := (p10 - center - c1 * R).normalized()
			_begin()
			var idx := _cur.vcount()
			vert(p00, n00)
			vert(p01, n01)
			vert(p11, n11)
			vert(p10, n10)
			_cur.I.append(idx)
			_cur.I.append(idx + 2)
			_cur.I.append(idx + 1)
			_cur.I.append(idx)
			_cur.I.append(idx + 3)
			_cur.I.append(idx + 2)

func _tor(c: Vector3, R: float, r: float, t: float, u: float) -> Vector3:
	var d := Vector3(cos(t), 0, sin(t))
	return c + d * (R + r * cos(u)) + Vector3(0, r * sin(u), 0)

# ---------------------------------------------------------------- helpers

func _ccw(poly: PackedVector2Array) -> PackedVector2Array:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	if a < 0.0:
		var out := PackedVector2Array()
		for i in range(n - 1, -1, -1):
			out.append(poly[i])
		return out
	return poly

func _ear(poly: PackedVector2Array) -> Array:
	var n := poly.size()
	var idx: Array[int] = []
	for i in n:
		idx.append(i)
	var tris: Array = []
	var guard := 0
	while idx.size() > 3 and guard < 200:
		guard += 1
		var clipped := false
		for k in idx.size():
			var i0: int = idx[(k + idx.size() - 1) % idx.size()]
			var i1: int = idx[k]
			var i2: int = idx[(k + 1) % idx.size()]
			var a := poly[i0]
			var b := poly[i1]
			var c := poly[i2]
			var cr := (b - a).cross(c - b)
			if cr <= 1e-9:
				continue
			var has := false
			for j in idx:
				if j == i0 or j == i1 or j == i2:
					continue
				if _pt_in_tri(poly[j], a, b, c):
					has = true
					break
			if has:
				continue
			tris.append([i0, i1, i2])
			idx.remove_at(k)
			clipped = true
			break
		if not clipped:
			break
	if idx.size() == 3:
		tris.append([idx[0], idx[1], idx[2]])
	elif idx.size() > 3:
		for k in range(1, idx.size() - 1):
			tris.append([idx[0], idx[k], idx[k + 1]])
	return tris

func _pt_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (b - a).cross(p - a)
	var d2 := (c - b).cross(p - b)
	var d3 := (a - c).cross(p - c)
	var has_neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_neg and has_pos)

func tri_count() -> int:
	return _subs[0].I.size() / 3 + _subs[1].I.size() / 3

func is_empty() -> bool:
	return _subs[0].P.is_empty() and _subs[1].P.is_empty()

static func _make_arrays(s: Sub) -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	if s.P.is_empty():
		return arr
	arr[Mesh.ARRAY_VERTEX] = s.P
	arr[Mesh.ARRAY_NORMAL] = s.N
	arr[Mesh.ARRAY_COLOR] = s.C
	arr[Mesh.ARRAY_TEX_UV] = s.U
	arr[Mesh.ARRAY_CUSTOM0] = s.A
	arr[Mesh.ARRAY_INDEX] = s.I
	return arr

func commit(opaque_mat: Material, glass_mat: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var a0 := _make_arrays(_subs[0])
	if not _subs[0].P.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a0)
		mesh.surface_set_material(mesh.get_surface_count() - 1, opaque_mat)
	var a1 := _make_arrays(_subs[1])
	if not _subs[1].P.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a1)
		mesh.surface_set_material(mesh.get_surface_count() - 1, glass_mat)
	return mesh

func instance(opaque_mat: Material, glass_mat: Material, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = commit(opaque_mat, glass_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi