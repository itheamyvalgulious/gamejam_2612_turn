class_name Geom
extends RefCounted
## SurfaceTool batching helpers. All geometry is baked in world space.
## One SurfaceTool per material key; commit_all() creates one MeshInstance3D per key.

var _tools := {}

func tool(key: String) -> SurfaceTool:
	var t: SurfaceTool = _tools.get(key)
	if t == null:
		t = SurfaceTool.new()
		t.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = t
	return t

func has_key(key: String) -> bool:
	return _tools.has(key)

func commit_all(parent: Node3D, mats: Dictionary, base_name: String = "") -> void:
	var keys := _tools.keys()
	keys.sort()
	for key in keys:
		var st: SurfaceTool = _tools[key]
		st.index()
		st.generate_normals()
		var mat: Material = mats.get(key)
		if mat == null:
			push_warning("Geom: no material for key " + str(key))
			continue
		var mesh: ArrayMesh = st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		mesh.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.name = base_name + str(key)
		mi.mesh = mesh
		parent.add_child(mi)
	_tools.clear()

func clear() -> void:
	_tools.clear()

# ---------------------------------------------------------------- primitives

## Axis-aligned (or Y-rotated) box.
func box(key: String, center: Vector3, size: Vector3, col: Color, rot_y: float = 0.0) -> void:
	var b := Basis(Vector3.UP, rot_y)
	box_basis(key, Transform3D(b, center), size, col)

## Box under arbitrary transform (used for ramps, tilted panels).
func box_basis(key: String, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var c := [
		xf * Vector3(-h.x, -h.y, -h.z), xf * Vector3(h.x, -h.y, -h.z),
		xf * Vector3(h.x, h.y, -h.z), xf * Vector3(-h.x, h.y, -h.z),
		xf * Vector3(-h.x, -h.y, h.z), xf * Vector3(h.x, -h.y, h.z),
		xf * Vector3(h.x, h.y, h.z), xf * Vector3(-h.x, h.y, h.z),
	]
	var nrm := [
		xf.basis * Vector3(0, 0, 1), xf.basis * Vector3(0, 0, -1),
		xf.basis * Vector3(1, 0, 0), xf.basis * Vector3(-1, 0, 0),
		xf.basis * Vector3(0, 1, 0), xf.basis * Vector3(0, -1, 0),
	]
	var faces := [
		[4, 5, 6, 7, 0, size.x, size.y],
		[1, 0, 3, 2, 1, size.x, size.y],
		[5, 1, 2, 6, 2, size.z, size.y],
		[0, 4, 7, 3, 3, size.z, size.y],
		[7, 6, 2, 3, 4, size.x, size.z],
		[0, 1, 5, 4, 5, size.x, size.z],
	]
	var t := tool(key)
	for f in faces:
		var n: Vector3 = nrm[f[4]]
		var w: float = f[5]
		var hh: float = f[6]
		var uvs := [Vector2(0, 0), Vector2(w, 0), Vector2(w, hh), Vector2(0, hh)]
		var tris := [[f[0], 0], [f[1], 1], [f[2], 2], [f[0], 0], [f[2], 2], [f[3], 3]]
		for k in 6:
			t.set_color(col)
			t.set_normal(n)
			t.set_uv(uvs[tris[k][1]])
			t.add_vertex(c[tris[k][0]])

## Single quad, CCW seen from the front (normal side). Auto normal if n == INF.
func quad(key: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color, n: Vector3 = Vector3.INF, uv_scale: float = 1.0) -> void:
	if n == Vector3.INF:
		n = (p1 - p0).cross(p2 - p0).normalized()
	var e1: float = p0.distance_to(p1) * uv_scale
	var e2: float = p1.distance_to(p2) * uv_scale
	var t := tool(key)
	var pts := [p0, p1, p2, p0, p2, p3]
	var uvs := [Vector2(0, 0), Vector2(e1, 0), Vector2(e1, e2), Vector2(0, 0), Vector2(e1, e2), Vector2(0, e2)]
	for k in 6:
		t.set_color(col)
		t.set_normal(n)
		t.set_uv(uvs[k])
		t.add_vertex(pts[k])

## Quad with explicit unit UVs (screens, displays). Corners: BL, BR, TR, TL.
func quad_uv(key: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color) -> void:
	var n := (p1 - p0).cross(p2 - p0).normalized()
	var t := tool(key)
	var pts := [p0, p1, p2, p0, p2, p3]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	for k in 6:
		t.set_color(col)
		t.set_normal(n)
		t.set_uv(uvs[k])
		t.add_vertex(pts[k])

## Double-sided quad (light strips, panels seen from both sides).
func quad_ds(key: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color) -> void:
	quad(key, p0, p1, p2, p3, col, (p1 - p0).cross(p2 - p0).normalized())
	quad(key, p3, p2, p1, p0, col, (p2 - p3).cross(p1 - p3).normalized())

## Cylinder / cone between two points. r_b < 0 => same as r_a.
func cylinder(key: String, a: Vector3, b: Vector3, r_a: float, col: Color, seg: int = 12, caps: bool = true, r_b: float = -1.0) -> void:
	if r_b < 0.0:
		r_b = r_a
	var d: Vector3 = b - a
	var len := d.length()
	if len < 0.0005:
		return
	var y := d / len
	var up := Vector3(0, 1, 0)
	if absf(y.dot(up)) > 0.98:
		up = Vector3(1, 0, 0)
	var x := y.cross(up).normalized()
	var z := x.cross(y)
	var t := tool(key)
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for i in seg:
		var ang := TAU * float(i) / float(seg)
		var dir := x * cos(ang) + z * sin(ang)
		ring_a.append(a + dir * r_a)
		ring_b.append(b + dir * r_b)
	for i in seg:
		var i2 := (i + 1) % seg
		var u0 := TAU * float(i) / float(seg) * r_a
		var u1 := TAU * float(i2) / float(seg) * r_a
		# side quad (outward winding)
		var n0 := (x * cos(TAU * float(i) / float(seg)) + z * sin(TAU * float(i) / float(seg))).normalized()
		var n1 := (x * cos(TAU * float(i2) / float(seg)) + z * sin(TAU * float(i2) / float(seg))).normalized()
		var nm := (n0 + n1).normalized()
		t.set_color(col); t.set_normal(n0); t.set_uv(Vector2(u0, 0)); t.add_vertex(ring_a[i])
		t.set_color(col); t.set_normal(n1); t.set_uv(Vector2(u1, 0)); t.add_vertex(ring_a[i2])
		t.set_color(col); t.set_normal(n1); t.set_uv(Vector2(u1, len)); t.add_vertex(ring_b[i2])
		t.set_color(col); t.set_normal(n0); t.set_uv(Vector2(u0, 0)); t.add_vertex(ring_a[i])
		t.set_color(col); t.set_normal(n1); t.set_uv(Vector2(u1, len)); t.add_vertex(ring_b[i2])
		t.set_color(col); t.set_normal(n0); t.set_uv(Vector2(u0, len)); t.add_vertex(ring_b[i])
	if caps:
		if r_a > 0.001:
			for i in seg:
				var i2 := (i + 1) % seg
				t.set_color(col); t.set_normal(-y); t.set_uv(Vector2(0, 0)); t.add_vertex(a)
				t.set_color(col); t.set_normal(-y); t.set_uv(Vector2(0, 0)); t.add_vertex(ring_a[i2])
				t.set_color(col); t.set_normal(-y); t.set_uv(Vector2(0, 0)); t.add_vertex(ring_a[i])
		if r_b > 0.001:
			for i in seg:
				var i2 := (i + 1) % seg
				t.set_color(col); t.set_normal(y); t.set_uv(Vector2(0, 0)); t.add_vertex(b)
				t.set_color(col); t.set_normal(y); t.set_uv(Vector2(0, 0)); t.add_vertex(ring_b[i])
				t.set_color(col); t.set_normal(y); t.set_uv(Vector2(0, 0)); t.add_vertex(ring_b[i2])

## UV sphere / ellipsoid.
func sphere(key: String, center: Vector3, radius: Vector3, col: Color, seg: int = 16, rings: int = 10,
		phi0: float = 0.0, phi1: float = TAU, th0: float = 0.0, th1: float = PI) -> void:
	var t := tool(key)
	for ri in rings:
		var t0 := lerpf(th0, th1, float(ri) / float(rings))
		var t1 := lerpf(th0, th1, float(ri + 1) / float(rings))
		for si in seg:
			var p0 := lerpf(phi0, phi1, float(si) / float(seg))
			var p1 := lerpf(phi0, phi1, float(si + 1) / float(seg))
			var a := center + _sph(p0, t0, radius)
			var b := center + _sph(p1, t0, radius)
			var c := center + _sph(p1, t1, radius)
			var d := center + _sph(p0, t1, radius)
			var na := _sphn(p0, t0); var nb := _sphn(p1, t0)
			var nc := _sphn(p1, t1); var nd := _sphn(p0, t1)
			if t0 > 0.001:
				t.set_color(col); t.set_normal(na); t.set_uv(Vector2(p0, t0)); t.add_vertex(a)
				t.set_color(col); t.set_normal(nb); t.set_uv(Vector2(p1, t0)); t.add_vertex(b)
				t.set_color(col); t.set_normal(nc); t.set_uv(Vector2(p1, t1)); t.add_vertex(c)
			if t1 < PI - 0.001:
				t.set_color(col); t.set_normal(na); t.set_uv(Vector2(p0, t0)); t.add_vertex(a)
				t.set_color(col); t.set_normal(nc); t.set_uv(Vector2(p1, t1)); t.add_vertex(c)
				t.set_color(col); t.set_normal(nd); t.set_uv(Vector2(p0, t1)); t.add_vertex(d)

func _sph(phi: float, th: float, r: Vector3) -> Vector3:
	return Vector3(r.x * sin(th) * cos(phi), r.y * cos(th), r.z * sin(th) * sin(phi))

func _sphn(phi: float, th: float) -> Vector3:
	return Vector3(sin(th) * cos(phi), cos(th), sin(th) * sin(phi)).normalized()

## Torus around Y axis (or arbitrary basis). arc in radians.
func torus(key: String, center: Vector3, basis: Basis, r_major: float, r_minor: float, col: Color,
		seg: int = 24, sides: int = 8, arc: float = TAU) -> void:
	var t := tool(key)
	for i in seg:
		var a0 := arc * float(i) / float(seg)
		var a1 := arc * float(i + 1) / float(seg)
		for j in sides:
			var b0 := TAU * float(j) / float(sides)
			var b1 := TAU * float(j + 1) / float(sides)
			var p00 := _tp(basis, center, r_major, r_minor, a0, b0)
			var p10 := _tp(basis, center, r_major, r_minor, a1, b0)
			var p11 := _tp(basis, center, r_major, r_minor, a1, b1)
			var p01 := _tp(basis, center, r_major, r_minor, a0, b1)
			var n00 := _tn(basis, r_major, r_minor, a0, b0)
			var n10 := _tn(basis, r_major, r_minor, a1, b0)
			var n11 := _tn(basis, r_major, r_minor, a1, b1)
			var n01 := _tn(basis, r_major, r_minor, a0, b1)
			t.set_color(col); t.set_normal(n00); t.set_uv(Vector2(a0 * r_major, b0 * r_minor)); t.add_vertex(p00)
			t.set_color(col); t.set_normal(n10); t.set_uv(Vector2(a1 * r_major, b0 * r_minor)); t.add_vertex(p10)
			t.set_color(col); t.set_normal(n11); t.set_uv(Vector2(a1 * r_major, b1 * r_minor)); t.add_vertex(p11)
			t.set_color(col); t.set_normal(n00); t.set_uv(Vector2(a0 * r_major, b0 * r_minor)); t.add_vertex(p00)
			t.set_color(col); t.set_normal(n11); t.set_uv(Vector2(a1 * r_major, b1 * r_minor)); t.add_vertex(p11)
			t.set_color(col); t.set_normal(n01); t.set_uv(Vector2(a0 * r_major, b1 * r_minor)); t.add_vertex(p01)

func _tp(b: Basis, c: Vector3, R: float, r: float, a: float, bb: float) -> Vector3:
	var ring := Vector3(cos(a) * R, 0, sin(a) * R)
	var local := Vector3(cos(a) * cos(bb), sin(bb), sin(a) * cos(bb)) * r
	return c + b * (ring + local)

func _tn(b: Basis, R: float, r: float, a: float, bb: float) -> Vector3:
	var local := Vector3(cos(a) * cos(bb), sin(bb), sin(a) * cos(bb))
	return (b * local).normalized()

## Rectangular strut from a to b (cross-section w × h), used for frames/ribs/posts.
func strut(key: String, a: Vector3, b: Vector3, w: float, h: float, col: Color, up_hint: Vector3 = Vector3.UP) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.0005:
		return
	var y := d / len
	var x := y.cross(up_hint)
	if x.length() < 0.01:
		x = y.cross(Vector3(1, 0, 0))
	x = x.normalized()
	var z := x.cross(y)
	box_basis(key, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, len, h), col)

## Pipe run through a list of points: cylinders + elbow spheres.
func pipe(key: String, pts: Array, r: float, col: Color, seg: int = 8) -> void:
	for i in pts.size() - 1:
		cylinder(key, pts[i], pts[i + 1], r, col, seg)
		if i > 0:
			sphere(key, pts[i], Vector3(r * 1.15, r * 1.15, r * 1.15), col, 8, 6)

## Parametric surface. fn(u,v) -> Vector3 or Vector3(NAN) to skip the quad.
func parametric(key: String, fn: Callable, u0: float, u1: float, v0: float, v1: float,
		nu: int, nv: int, col: Color, flip: bool = false) -> void:
	var t := tool(key)
	for i in nu:
		for j in nv:
			var ua := lerpf(u0, u1, float(i) / float(nu))
			var ub := lerpf(u0, u1, float(i + 1) / float(nu))
			var va := lerpf(v0, v1, float(j) / float(nv))
			var vb := lerpf(v0, v1, float(j + 1) / float(nv))
			var p00: Vector3 = fn.call(ua, va)
			var p10: Vector3 = fn.call(ub, va)
			var p11: Vector3 = fn.call(ub, vb)
			var p01: Vector3 = fn.call(ua, vb)
			if _bad(p00) or _bad(p10) or _bad(p11) or _bad(p01):
				continue
			var n00 := _pnorm(fn, ua, va, p00)
			var n10 := _pnorm(fn, ub, va, p10)
			var n11 := _pnorm(fn, ub, vb, p11)
			var n01 := _pnorm(fn, ua, vb, p01)
			var du: float = (ub - ua) * float(nu)
			var dv: float = (vb - va) * float(nv)
			if flip:
				_emit_tri(t, p00, p11, p10, col, n00, -n11, -n10, Vector2(ua, va) * 8.0, Vector2(ub, vb) * 8.0, Vector2(ub, va) * 8.0)
				_emit_tri(t, p00, p01, p11, col, n00, -n01, -n11, Vector2(ua, va) * 8.0, Vector2(ua, vb) * 8.0, Vector2(ub, vb) * 8.0)
			else:
				_emit_tri(t, p00, p10, p11, col, n00, n10, n11, Vector2(ua * du, va * dv), Vector2(ub * du, va * dv), Vector2(ub * du, vb * dv))
				_emit_tri(t, p00, p11, p01, col, n00, n11, n01, Vector2(ua * du, va * dv), Vector2(ub * du, vb * dv), Vector2(ua * du, vb * dv))

func _bad(p: Vector3) -> bool:
	return is_nan(p.x) or is_nan(p.y) or is_nan(p.z)

func _pnorm(fn: Callable, u: float, v: float, p: Vector3) -> Vector3:
	var e := 0.01
	var pu: Vector3 = fn.call(u + e, v)
	var pv: Vector3 = fn.call(u, v + e)
	if _bad(pu):
		pu = fn.call(u - e, v)
	if _bad(pv):
		pv = fn.call(u, v - e)
	if _bad(pu) or _bad(pv):
		return Vector3.UP
	return (pu - p).cross(pv - p).normalized()

func _emit_tri(t: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color,
		na: Vector3, nb: Vector3, nc: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2) -> void:
	t.set_color(col); t.set_normal(na); t.set_uv(uva); t.add_vertex(a)
	t.set_color(col); t.set_normal(nb); t.set_uv(uvb); t.add_vertex(b)
	t.set_color(col); t.set_normal(nc); t.set_uv(uvc); t.add_vertex(c)

# ------------------------------------------------------------- assemblies

## Straight flight of stairs from `start` toward horizontal `dir`.
## Each step: rise/n tall riser + tread box. Returns top position.
func stairs(key: String, start: Vector3, dir: Vector3, rise: float, run: float, width: float,
		n: int, col: Color, rail_key: String = "", rail_col: Color = Color.WHITE) -> Vector3:
	dir = Vector3(dir.x, 0, dir.z).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var sr := rise / float(n)
	var sd := run / float(n)
	for i in n:
		var base := start + dir * (sd * float(i)) + Vector3(0, sr * float(i), 0)
		# tread slab (local z = travel direction after rot_y)
		box(key, base + dir * (sd * 0.5) + Vector3(0, sr - 0.06, 0),
			Vector3(width, 0.12, sd + 0.02), col, atan2(dir.x, dir.z))
		# riser face
		box(key, base + dir * 0.03 + Vector3(0, (sr - 0.12) * 0.5, 0),
			Vector3(width, maxf(sr - 0.12, 0.05), 0.06), col, atan2(dir.x, dir.z))
	var top := start + dir * run + Vector3(0, rise, 0)
	if rail_key != "":
		railing(rail_key, [start + Vector3(0, 0.05, 0), top], 0.95, rail_col, side * (width * 0.5 - 0.06))
		railing(rail_key, [start + Vector3(0, 0.05, 0), top], 0.95, rail_col, -side * (width * 0.5 - 0.06))
	return top

## Railing along a polyline: posts + two rails + kickplate. offset shifts whole run sideways.
func railing(key: String, pts: Array, h: float, col: Color, offset: Vector3 = Vector3.ZERO) -> void:
	var a: Vector3 = pts[0] + offset
	var b: Vector3 = pts[pts.size() - 1] + offset
	var d := b - a
	var horiz := Vector3(d.x, 0, d.z)
	var len := horiz.length()
	if len < 0.05:
		return
	var dir := horiz / len
	var post_every := 1.4
	var nposts := int(ceil(len / post_every)) + 1
	for i in nposts:
		var p := a + dir * (len * float(i) / float(nposts - 1))
		cylinder(key, p, p + Vector3(0, h, 0), 0.035, col, 6)
	# rails (follow slope of a->b)
	cylinder(key, a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.045, col, 6)
	cylinder(key, a + Vector3(0, h * 0.55, 0), b + Vector3(0, h * 0.55, 0), 0.03, col, 6)
	# kickplate
	strut(key, a + Vector3(0, 0.09, 0), b + Vector3(0, 0.09, 0), 0.02, 0.18, col)

## I-beam from a to b.
func ibeam(key: String, a: Vector3, b: Vector3, hgt: float, wdt: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	var y := d / len
	var up := Vector3(0, 0, 1)
	if absf(y.dot(up)) > 0.95:
		up = Vector3(0, 1, 0)
	var x := y.cross(up).normalized()
	var z := x.cross(y)
	var xf := Transform3D(Basis(x, y, z), (a + b) * 0.5)
	var tf := maxf(wdt * 0.12, 0.02)
	box_basis(key, xf, Vector3(wdt, len, tf), col)
	box_basis(key, xf * Transform3D(Basis.IDENTITY, Vector3(wdt * 0.5 - tf * 0.5, 0, 0)), Vector3(tf, len, hgt), col)
	box_basis(key, xf * Transform3D(Basis.IDENTITY, Vector3(-(wdt * 0.5 - tf * 0.5), 0, 0)), Vector3(tf, len, hgt), col)

## Flat rectangle on floor with inset (floor trench cover, rug, marking plate).
func floor_patch(key: String, x0: float, x1: float, z0: float, z1: float, y: float, col: Color) -> void:
	quad(key, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), col, Vector3.UP)
