class_name MeshBuf
extends RefCounted
## Fast append-only mesh builder. Internally stores plain PackedFloat32Array
## attribute streams (Godot 4.7 mesh array requirement) and commits them into
## an ArrayMesh surface. World-space, units = meters.
## Attribute contract:
##   UV  = (u meters along facade / perimeter, v = world height) for facades,
##         or surface-specific meters elsewhere.
##   UV2 = (building seed hash, floor height) for facades; free otherwise.
##   COLOR.rgb = tint, COLOR.a = encoded payload (style*16+ground_h)/255 etc.

var V := PackedVector3Array()   # position
var N := PackedVector3Array()   # normal
var T := PackedFloat32Array()   # tangent xyzw
var C := PackedColorArray()    # color rgba
var U := PackedVector2Array()  # uv
var U2 := PackedVector2Array()  # uv2
var I := PackedInt32Array()     # indices
var use_tan := false

func size() -> int:
	return V.size()

func is_empty() -> bool:
	return V.is_empty()

func tri_count() -> int:
	return int(I.size() / 3)

func vert(p: Vector3, n: Vector3, u: Vector2, u2: Vector2, c: Color,
		c0 := Vector4.ZERO) -> int:
	V.append(p)
	N.append(n)
	U.append(u)
	U2.append(u2)
	C.append(c)
	if use_tan:
		var t := Vector3.UP.cross(n)
		if t.length_squared() < 0.001:
			t = Vector3.RIGHT.cross(n)
		t = t.normalized()
		var w := -1.0 if t.cross(n).dot(Vector3.UP) < 0.0 else 1.0
		T.append(t.x); T.append(t.y); T.append(t.z); T.append(w)
	return size() - 1

func tri(a: int, b: int, c: int) -> void:
	I.append(a)
	I.append(b)
	I.append(c)

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		uvs: PackedVector2Array, u2 := Vector2.ZERO, c_col := Color.WHITE,
		c0 := Vector4.ZERO) -> void:
	var base := size()
	vert(a, n, uvs[0], u2, c_col, c0)
	vert(b, n, uvs[1], u2, c_col, c0)
	vert(c, n, uvs[2], u2, c_col, c0)
	vert(d, n, uvs[3], u2, c_col, c0)
	tri(base, base + 1, base + 2)
	tri(base, base + 2, base + 3)

## Quad with automatic winding correction so the face points along `n`.
func quad_o(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		uvs: PackedVector2Array, u2 := Vector2.ZERO, c_col := Color.WHITE,
		c0 := Vector4.ZERO) -> void:
	var geo := (b - a).cross(c - a)
	if geo.dot(n) > 0.0:
		var tmp := b
		b = d
		d = tmp
		var tu := uvs[1]
		uvs[1] = uvs[3]
		uvs[3] = tu
	quad(a, b, c, d, n, uvs, u2, c_col, c0)

func tri_o(a: Vector3, b: Vector3, c: Vector3, n: Vector3,
		uvs: PackedVector2Array, u2 := Vector2.ZERO, c_col := Color.WHITE,
		c0 := Vector4.ZERO) -> void:
	var geo := (b - a).cross(c - a)
	if geo.dot(n) > 0.0:
		var tmp := b
		b = c
		c = tmp
		var tu := uvs[1]
		uvs[1] = uvs[2]
		uvs[2] = tu
	var base := size()
	vert(a, n, uvs[0], u2, c_col, c0)
	vert(b, n, uvs[1], u2, c_col, c0)
	vert(c, n, uvs[2], u2, c_col, c0)
	tri(base, base + 1, base + 2)

## Axis-aligned or transformed box. uv in meters * uv_scale.
func box(center: Vector3, sz: Vector3, u2 := Vector2.ZERO, c_col := Color.WHITE,
		uv_scale := 0.25, xf := Transform3D.IDENTITY, c0 := Vector4.ZERO) -> void:
	var h := sz * 0.5
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0), h.x, h.y, h.z],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0), h.x, h.y, h.z],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0), h.z, h.y, h.x],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), h.z, h.y, h.x],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), h.x, h.z, h.y],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), h.x, h.z, h.y],
	]
	var b := xf.basis
	for f in faces:
		var n: Vector3 = b * f[0]
		var t: Vector3 = b * f[1]
		var bt: Vector3 = b * f[2]
		var ht: float = f[3]
		var hb: float = f[4]
		var hn: float = f[5]
		var fc: Vector3 = xf * (center + f[0] * hn)
		var pa := fc + t * ht - bt * hb
		var pb := fc + t * ht + bt * hb
		var pc := fc - t * ht + bt * hb
		var pd := fc - t * ht - bt * hb
		var uvs := PackedVector2Array([
			Vector2(ht, -hb) * uv_scale, Vector2(ht, hb) * uv_scale,
			Vector2(-ht, hb) * uv_scale, Vector2(-ht, -hb) * uv_scale])
		quad_o(pa, pb, pc, pd, n.normalized(), uvs, u2, c_col, c0)

## Cylinder / cone frustum. base_center = center of bottom cap.
func cylinder(base_center: Vector3, r_bottom: float, r_top: float, h: float,
		seg: int, xf := Transform3D.IDENTITY, u2 := Vector2.ZERO,
		c_col := Color.WHITE, cap_top := true, cap_bottom := true,
		uv_scale := 0.25, c0 := Vector4.ZERO) -> void:
	var b := xf.basis
	seg = maxi(3, seg)
	var ring_bot := PackedVector3Array()
	var ring_top := PackedVector3Array()
	var nrm_ring := PackedVector3Array()
	var slope := (r_bottom - r_top) / maxf(h, 0.001)
	for i in seg:
		var a := TAU * float(i) / float(seg)
		var dir := Vector3(cos(a), 0, sin(a))
		ring_bot.append(xf * (base_center + dir * r_bottom))
		ring_top.append(xf * (base_center + dir * r_top + Vector3.UP * h))
		var nn := (dir + Vector3.UP * slope).normalized()
		nrm_ring.append((b * nn).normalized())
	var peri := TAU * 0.5 * (r_bottom + r_top)
	for i in seg:
		var j := (i + 1) % seg
		var u0 := peri * float(i) / float(seg) * uv_scale
		var u1 := peri * float(j) / float(seg) * uv_scale
		var uvs := PackedVector2Array([
			Vector2(u0, 0), Vector2(u1, 0),
			Vector2(u1, h * uv_scale), Vector2(u0, h * uv_scale)])
		var nn := (nrm_ring[i] + nrm_ring[j]).normalized()
		quad_o(ring_bot[i], ring_bot[j], ring_top[j], ring_top[i], nn, uvs, u2, c_col, c0)
	if cap_top and r_top > 0.005:
		var ct := xf * (base_center + Vector3.UP * h)
		var nt := (b * Vector3.UP).normalized()
		for i in seg:
			var j := (i + 1) % seg
			var dj := ring_top[j] - ct
			var di := ring_top[i] - ct
			var uvs := PackedVector2Array([
				Vector2.ZERO,
				Vector2(dj.x, dj.z) * uv_scale,
				Vector2(di.x, di.z) * uv_scale])
			tri_o(ct, ring_top[j], ring_top[i], nt, uvs, u2, c_col, c0)
	if cap_bottom and r_bottom > 0.005:
		var cb := xf * base_center
		var nb := (b * Vector3.DOWN).normalized()
		for i in seg:
			var j := (i + 1) % seg
			var dj := ring_bot[j] - cb
			var di := ring_bot[i] - cb
			var uvs := PackedVector2Array([
				Vector2.ZERO,
				Vector2(dj.x, dj.z) * uv_scale,
				Vector2(di.x, di.z) * uv_scale])
			tri_o(cb, ring_bot[j], ring_bot[i], nb, uvs, u2, c_col, c0)

## Extrude a closed polygon (x,z) from y0 to y1.
## Sides get UV = (perimeter meters, world height). Top cap goes to top_buf
## (or self) with planar UVs. Bottom is omitted.
func prism(pts: PackedVector2Array, y0: float, y1: float, u2 := Vector2.ZERO,
		c_col := Color.WHITE, top_buf: MeshBuf = null, top_uv_scale := 0.25,
		side_uv_scale := 1.0, c0 := Vector4.ZERO) -> void:
	var n := pts.size()
	if n < 3 or y1 <= y0:
		return
	var centroid2 := Vector2.ZERO
	for p in pts:
		centroid2 += p
	centroid2 /= float(n)
	var centroid := Vector3(centroid2.x, 0, centroid2.y)
	var cum := PackedFloat32Array()
	cum.resize(n + 1)
	cum[0] = 0.0
	for i in n:
		cum[i + 1] = cum[i] + pts[i].distance_to(pts[(i + 1) % n])
	for i in n:
		var j := (i + 1) % n
		var a := Vector3(pts[i].x, y0, pts[i].y)
		var bq := Vector3(pts[j].x, y0, pts[j].y)
		var c := Vector3(pts[j].x, y1, pts[j].y)
		var d := Vector3(pts[i].x, y1, pts[i].y)
		var dir := bq - a
		var nn := Vector3(dir.z, 0, -dir.x).normalized()
		var mid := (a + bq) * 0.5
		if nn.dot(mid - centroid) < 0.0:
			nn = -nn
		var uvs := PackedVector2Array([
			Vector2(cum[i] * side_uv_scale, y0), Vector2(cum[j] * side_uv_scale, y0),
			Vector2(cum[j] * side_uv_scale, y1), Vector2(cum[i] * side_uv_scale, y1)])
		quad_o(a, bq, c, d, nn, uvs, u2, c_col, c0)
	var tb := top_buf if top_buf != null else self
	var ct := Vector3(centroid2.x, y1, centroid2.y)
	for i in n:
		var j := (i + 1) % n
		var pj := Vector3(pts[j].x, y1, pts[j].y)
		var pi := Vector3(pts[i].x, y1, pts[i].y)
		var uvs := PackedVector2Array([
			centroid2 * top_uv_scale,
			Vector2(pts[j].x, pts[j].y) * top_uv_scale,
			Vector2(pts[i].x, pts[i].y) * top_uv_scale])
		tb.tri_o(ct, pj, pi, Vector3.UP, uvs, u2, c_col, c0)

## Flat strip quad (ground plane), y fixed.
func ground_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, uvs: PackedVector2Array,
		u2 := Vector2.ZERO, c_col := Color.WHITE, c0 := Vector4.ZERO) -> void:
	quad_o(a, b, c, d, Vector3.UP, uvs, u2, c_col, c0)

func make_surface(mesh: ArrayMesh, material: Material) -> void:
	if V.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_COLOR] = C
	if use_tan:
		arr[Mesh.ARRAY_TANGENT] = T
	arr[Mesh.ARRAY_INDEX] = I
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
