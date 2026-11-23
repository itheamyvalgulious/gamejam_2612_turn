extends RefCounted
## PhantomKit — extra hard-surface primitives for SHARD // PHANTOM.
##
## The kit's MeshKit covers prisms / beams / discs / plates.  Modules need
## tapered wedges, crystal shards and extruded star polygons (shuriken) with a
## planar UV layout the module shader can use for edge light.  Everything is
## emitted from pure math with flat, faceted normals.

const TAU := PI * 2.0
const MK := preload("res://scripts/kit/mesh_kit.gd")


static func _new_surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _emit_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		guide: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var g := (b - a).cross(c - a)
	if g.length_squared() < 1e-14:
		return
	if g.dot(guide) < 0.0:
		var t := b
		b = c
		c = t
		var tuv := ub
		ub = uc
		uc = tuv
		g = -g
	var n := g.normalized()
	st.set_normal(n)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(uc)
	st.add_vertex(c)
	st.set_normal(n)
	st.set_uv(ub)
	st.add_vertex(b)


static func _emit_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		guide: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_emit_tri(st, a, b, c, guide, ua, ub, uc)
	_emit_tri(st, a, c, d, guide, ua, uc, ud)


# ------------------------------------------------------------------ polygons

## Chamfered plate outline in XY.  top/bottom taper are width multipliers.
static func plate_poly(w: float, h: float, top_taper := 1.0, bottom_taper := 1.0,
		chamfer := 0.12) -> PackedVector2Array:
	var c := clampf(chamfer, 0.01, 0.30)
	var hw := w * 0.5
	var hh := h * 0.5
	var tw := hw * top_taper
	var bw := hw * bottom_taper
	var cx := minf(minf(hw, tw) * c, h * 0.25)
	var cy := minf(hh * c, w * 0.25)
	return PackedVector2Array([
		Vector2(-bw + cx, -hh), Vector2(bw - cx, -hh), Vector2(bw, -hh + cy),
		Vector2(tw, hh - cy), Vector2(tw - cx, hh), Vector2(-tw + cx, hh),
		Vector2(-tw, hh - cy), Vector2(-bw, -hh + cy),
	])


## Elongated hex crystal (pointy top and bottom).
static func shard_poly(w: float, h: float) -> PackedVector2Array:
	var hw := w * 0.5
	var hh := h * 0.5
	var sh := h * 0.30
	return PackedVector2Array([
		Vector2(-hw, -hh + sh), Vector2(0.0, -hh), Vector2(hw, -hh + sh),
		Vector2(hw * 0.72, hh - sh * 0.7), Vector2(0.0, hh),
		Vector2(-hw * 0.72, hh - sh * 0.7),
	])


## 4-blade energy shuriken outline, XY, tips at 45/135/225/315 degrees.
static func star_poly(blades: int, r_out: float, r_in: float, twist := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := blades * 2
	for i in n:
		var a := TAU * float(i) / float(n) + twist
		var r := r_out if i % 2 == 0 else r_in
		# swept-back tips: bias the angle of the outer points
		var aa := a + (0.14 if i % 2 == 0 else -0.10)
		pts.append(Vector2(cos(aa) * r, sin(aa) * r))
	return pts


static func _centroid(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / float(maxi(pts.size(), 1))


static func _inset(pts: PackedVector2Array, amount: float) -> PackedVector2Array:
	var c := _centroid(pts)
	var out := PackedVector2Array()
	for p in pts:
		var d := p - c
		var l := maxf(d.length(), 1e-5)
		out.append(c + d * maxf(0.35, (l - amount) / l))
	return out


static func _bounds_size(pts: PackedVector2Array) -> Vector2:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in pts:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	return mx - mn


## Extrude a convex / star-shaped XY polygon along Z with a chamfer bevel.
## Front caps face +Z, back caps face -Z.  Front/back UVs are planar 0..1.
static func extrude_poly(pts: PackedVector2Array, thickness: float, bevel := 0.006) -> ArrayMesh:
	var st := _new_surface()
	var n := pts.size()
	if n < 3:
		return st.commit()
	var h := thickness * 0.5
	var sz := _bounds_size(pts)
	var b := clampf(bevel, 0.0008, minf(h * 0.42, minf(sz.x, sz.y) * 0.16))
	var inner := _inset(pts, b)
	var c := _centroid(pts)
	var ci := _centroid(inner)
	var uvo := Vector2(0.5, 0.5)
	var denom := Vector2(maxf(sz.x, 1e-5), maxf(sz.y, 1e-5))
	var uv := func(p: Vector2) -> Vector2:
		return Vector2((p.x - c.x) / denom.x + 0.5, (p.y - c.y) / denom.y + 0.5)

	# front / back caps
	for i in n:
		var j := (i + 1) % n
		_emit_tri(st, Vector3(ci.x, ci.y, h), Vector3(inner[i].x, inner[i].y, h),
			Vector3(inner[j].x, inner[j].y, h), Vector3.BACK, uvo, uv.call(inner[i]), uv.call(inner[j]))
		_emit_tri(st, Vector3(ci.x, ci.y, -h), Vector3(inner[i].x, inner[i].y, -h),
			Vector3(inner[j].x, inner[j].y, -h), Vector3.FORWARD, uvo, uv.call(inner[i]), uv.call(inner[j]))

	# side bands (3 segments). Perimeter u for side UVs.
	var per := 0.0
	var acc: Array[float] = []
	for i in n:
		acc.append(per)
		per += pts[i].distance_to(pts[(i + 1) % n])
	per = maxf(per, 1e-5)
	for i in n:
		var j := (i + 1) % n
		var e := pts[j] - pts[i]
		var outward2 := Vector2(e.y, -e.x).normalized()
		var u0 := acc[i] / per
		var u1 := (acc[i] + e.length()) / per
		var rings: Array = [
			[Vector3(inner[i].x, inner[i].y, -h), Vector3(inner[j].x, inner[j].y, -h),
				Vector3(pts[j].x, pts[j].y, -h + b), Vector3(pts[i].x, pts[i].y, -h + b)],
			[Vector3(pts[i].x, pts[i].y, -h + b), Vector3(pts[j].x, pts[j].y, -h + b),
				Vector3(pts[j].x, pts[j].y, h - b), Vector3(pts[i].x, pts[i].y, h - b)],
			[Vector3(pts[i].x, pts[i].y, h - b), Vector3(pts[j].x, pts[j].y, h - b),
				Vector3(inner[j].x, inner[j].y, h), Vector3(inner[i].x, inner[i].y, h)],
		]
		var guides := [
			Vector3(outward2.x, outward2.y, -1.2).normalized(),
			Vector3(outward2.x, outward2.y, 0.0),
			Vector3(outward2.x, outward2.y, 1.2).normalized(),
		]
		var vs := [0.0, 0.34, 0.67, 1.0]
		for k in 3:
			var q: Array = rings[k]
			var g: Vector3 = guides[k]
			_emit_quad(st, q[0], q[1], q[2], q[3], g,
				Vector2(u0, vs[k]), Vector2(u1, vs[k]), Vector2(u1, vs[k + 1]), Vector2(u0, vs[k + 1]))
	return st.commit()


# --------------------------------------------------------------- module meshes

static func module_plate(w: float, h: float, t: float, top_taper := 1.0,
		bottom_taper := 1.0, chamfer := 0.14) -> ArrayMesh:
	return extrude_poly(plate_poly(w, h, top_taper, bottom_taper, chamfer), t, t * 0.28)


static func module_shard(w: float, h: float, t: float) -> ArrayMesh:
	return extrude_poly(shard_poly(w, h), t, t * 0.30)


## Star blade with a thicker hub (two stacked extrusions merged).
static func shuriken_mesh(blades: int, r_out: float, r_in: float, thickness: float) -> ArrayMesh:
	# one blade is longer than the other three: with 4 identical blades the spin
	# is invisible (90-degree symmetry), this breaks it so rotation reads clearly
	var pts := star_poly(blades, r_out, r_in)
	if pts.size() >= 8:
		pts[0] = pts[0].normalized() * (r_out * 1.24)
		pts[1] *= 1.05
		pts[pts.size() - 1] *= 1.05
	var body := extrude_poly(pts, thickness, thickness * 0.22)
	var hub := extrude_poly(star_poly(8, r_out * 0.30, r_out * 0.24, 0.2), thickness * 2.4, thickness * 0.30)
	return MK.merge([body, hub])


## Two crossed tapered quads along -Z, for micro-thruster plumes.
## UV.x across, UV.y = 0 at nozzle .. 1 at tail.
static func plume_cross(width: float, length: float) -> ArrayMesh:
	var st := _new_surface()
	var w0 := width * 0.5
	var w1 := width * 0.14
	var tip := Vector3(0.0, 0.0, -length)
	for plane in 2:
		var ax := Vector3.RIGHT if plane == 0 else Vector3.UP
		var nrm := Vector3.UP if plane == 0 else Vector3.RIGHT
		var a0 := -ax * w0
		var a1 := ax * w0
		var b0 := -ax * w1 + tip
		var b1 := ax * w1 + tip
		_emit_quad(st, a0, a1, b1, b0, nrm,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		_emit_quad(st, a1, a0, b0, b1, -nrm,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	return st.commit()


## Curved single-sided ribbon along a polyline, quads facing `facing`.
static func ribbon_strip(points: PackedVector3Array, widths: PackedFloat32Array,
		facing := Vector3.UP) -> ArrayMesh:
	var st := _new_surface()
	var n := points.size()
	if n < 2:
		return st.commit()
	var total := 0.0
	var acc: Array[float] = [0.0]
	for i in n - 1:
		total += points[i].distance_to(points[i + 1])
		acc.append(total)
	total = maxf(total, 1e-5)
	for i in n - 1:
		var a := points[i]
		var b := points[i + 1]
		var dir := (b - a).normalized()
		var side := dir.cross(facing)
		if side.length_squared() < 1e-8:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		var w0 := widths[i] * 0.5
		var w1 := widths[i + 1] * 0.5
		_emit_quad(st, a - side * w0, a + side * w0, b + side * w1, b - side * w1, facing,
			Vector2(0, acc[i] / total), Vector2(1, acc[i] / total),
			Vector2(1, acc[i + 1] / total), Vector2(0, acc[i + 1] / total))
	return st.commit()


## Thin arc plate ring on the XZ plane (assembly guide), UV.x = angle, UV.y = radius.
static func arc_band(r_in: float, r_out: float, a0: float, a1: float, seg := 48,
		y := 0.0) -> ArrayMesh:
	var st := _new_surface()
	for i in seg:
		var t0 := lerpf(a0, a1, float(i) / float(seg))
		var t1 := lerpf(a0, a1, float(i + 1) / float(seg))
		var d0 := Vector3(cos(t0), 0, sin(t0))
		var d1 := Vector3(cos(t1), 0, sin(t1))
		_emit_quad(st, d0 * r_in + Vector3(0, y, 0), d0 * r_out + Vector3(0, y, 0),
			d1 * r_out + Vector3(0, y, 0), d1 * r_in + Vector3(0, y, 0), Vector3.UP,
			Vector2(float(i) / seg, 0), Vector2(float(i) / seg, 1),
			Vector2(float(i + 1) / seg, 1), Vector2(float(i + 1) / seg, 0))
	return st.commit()