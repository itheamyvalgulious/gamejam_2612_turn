extends RefCounted
## MeshKit — procedural hard-surface mesh factory.
##
## Everything is emitted from pure math (no imported meshes / textures).
## Vocabulary follows the art direction: only spherical arcs and flat planes.
##   arc_shell() : spherical shell patch (domes, bands, hull segments)
##   dome()      : spherical cap with radial UVs (lenses, shield skin)
##   disc()      : beveled flat cylinder (lens barrels, joints)
##   ring()      : beveled flat annulus (shield rings, collars)
##   plate()     : beveled slab, flat faces (armor plates)
##   beam()      : chamfered octagonal beam along +X (limbs, struts)
##   katana()    : curved katana volume with lens cross-section
##   ribbon_cross(): two perpendicular ribbons along a polyline (lightning)
##
## Winding convention (Godot): front faces are clockwise seen from outside.
## We pick the triangle order so cross(b-a, c-a) points into the surface while
## the supplied normal points outward.

const TAU := PI * 2.0


# ---------------------------------------------------------------- primitives

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
		var tmp := b
		b = c
		c = tmp
		var tmpuv := ub
		ub = uc
		uc = tmpuv
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


static func _emit_tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var g := (b - a).cross(c - a)
	if g.length_squared() < 1e-14:
		return
	var guide := (na + nb + nc)
	if g.dot(guide) < 0.0:
		var tb := b
		b = c
		c = tb
		var tn := nb
		nb = nc
		nc = tn
		var tuv := ub
		ub = uc
		uc = tuv
	st.set_normal(na)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(nc)
	st.set_uv(uc)
	st.add_vertex(c)
	st.set_normal(nb)
	st.set_uv(ub)
	st.add_vertex(b)


static func _emit_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		guide: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_emit_tri(st, a, b, c, guide, ua, ub, uc)
	_emit_tri(st, a, c, d, guide, ua, uc, ud)


static func _emit_quad_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_emit_tri_n(st, a, b, c, na, nb, nc, ua, ub, uc)
	_emit_tri_n(st, a, c, d, na, nc, nd, ua, uc, ud)


# ------------------------------------------------------------------- shapes

## Chamfered tapered prism along +Y (hex bolts, spikes, barrels).
static func prism(sides: int, r_bottom: float, r_top: float, height: float,
		angle_offset := 0.0) -> ArrayMesh:
	var st := _new_surface()
	var y0 := -height * 0.5
	var y1 := height * 0.5
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in sides:
		var a := angle_offset + TAU * float(i) / float(sides)
		bottom.append(Vector3(cos(a) * r_bottom, y0, sin(a) * r_bottom))
		top.append(Vector3(cos(a) * r_top, y1, sin(a) * r_top))
	for i in sides:
		var j := (i + 1) % sides
		var mid := angle_offset + TAU * (float(i) + 0.5) / float(sides)
		var guide := Vector3(cos(mid), (r_bottom - r_top) / maxf(height, 0.0001), sin(mid)).normalized()
		var u0 := float(i) / float(sides)
		var u1 := float(i + 1) / float(sides)
		_emit_quad(st, bottom[i], bottom[j], top[j], top[i], guide,
			Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1))
	if r_bottom > 1e-5:
		var bc := Vector3(0, y0, 0)
		for i in sides:
			var j := (i + 1) % sides
			_emit_tri(st, bc, bottom[i], bottom[j], Vector3.DOWN,
				Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
	if r_top > 1e-5:
		var tc := Vector3(0, y1, 0)
		for i in sides:
			var j := (i + 1) % sides
			_emit_tri(st, tc, top[i], top[j], Vector3.UP,
				Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0))
	return st.commit()


## Faceted sphere. smooth=false gives flat-shaded facets.
static func sphere(radius: float, rings := 16, sides := 24, smooth := true) -> ArrayMesh:
	return arc_shell(radius, 0.0, 0.0, PI, 0.0, TAU, rings, sides, smooth, false)


## Spherical shell patch.
## theta: polar angle 0..PI (0 = +Y pole), phi: azimuth 0..TAU around +Y.
## thickness > 0 builds an inner surface + rims. smooth controls shading.
static func arc_shell(radius: float, thickness: float,
		theta0: float, theta1: float, phi0: float, phi1: float,
		seg_v := 12, seg_u := 24, smooth := true, rims := true) -> ArrayMesh:
	var st := _new_surface()
	var r_in := maxf(radius - thickness, 0.0005)
	var full_u := absf((phi1 - phi0) - TAU) < 0.001
	var v_pole_lo := theta0 <= 0.0001
	var v_pole_hi := theta1 >= PI - 0.0001

	var ring: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	var positions: Array = []  # [seg_v+1][seg_u+1] of Vector3
	for v in seg_v + 1:
		var tv := float(v) / float(seg_v)
		var th := lerpf(theta0, theta1, tv)
		var row_p: Array[Vector3] = []
		var row_n: Array[Vector3] = []
		for u in seg_u + 1:
			var tu := float(u) / float(seg_u)
			var ph := lerpf(phi0, phi1, tu)
			var n := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			row_p.append(n * radius)
			row_n.append(n)
		positions.append(row_p)
		ring.append(Vector3.ZERO)
		nrm.append(Vector3.ZERO)

	# outer surface
	for v in seg_v:
		var row0: Array[Vector3] = positions[v]
		var row1: Array[Vector3] = positions[v + 1]
		for u in seg_u:
			var a := row0[u]
			var b := row0[u + 1]
			var c := row1[u + 1]
			var d := row1[u]
			var na := a.normalized()
			var nb := b.normalized()
			var nc := c.normalized()
			var nd := d.normalized()
			var ua := Vector2(float(u) / float(seg_u), float(v) / float(seg_v))
			var ub := Vector2(float(u + 1) / float(seg_u), float(v) / float(seg_v))
			var uc := Vector2(float(u + 1) / float(seg_u), float(v + 1) / float(seg_v))
			var ud := Vector2(float(u) / float(seg_u), float(v + 1) / float(seg_v))
			if smooth:
				_emit_quad_n(st, a, b, c, d, na, nb, nc, nd, ua, ub, uc, ud)
			else:
				var g := (na + nb + nc + nd)
				_emit_quad(st, a, b, c, d, g.normalized(), ua, ub, uc, ud)

	# inner surface (reversed guide via negative normals)
	if thickness > 0.0001:
		for v in seg_v:
			var row0: Array[Vector3] = positions[v]
			var row1: Array[Vector3] = positions[v + 1]
			for u in seg_u:
				var a := row0[u].normalized() * r_in
				var b := row0[u + 1].normalized() * r_in
				var c := row1[u + 1].normalized() * r_in
				var d := row1[u].normalized() * r_in
				var na := -a.normalized()
				var nb := -b.normalized()
				var nc := -c.normalized()
				var nd := -d.normalized()
				var ua := Vector2(float(u) / float(seg_u), float(v) / float(seg_v))
				var ub := Vector2(float(u + 1) / float(seg_u), float(v) / float(seg_v))
				var uc := Vector2(float(u + 1) / float(seg_u), float(v + 1) / float(seg_v))
				var ud := Vector2(float(u) / float(seg_u), float(v + 1) / float(seg_v))
				_emit_quad_n(st, a, b, c, d, na, nb, nc, nd, ua, ub, uc, ud)

		# rims (only on open boundaries)
		if rims and not full_u:
			for side in [0, 1]:
				for v in seg_v:
					var tu0 := float(v) / float(seg_v)
					var tu1 := float(v + 1) / float(seg_v)
					var th0 := lerpf(theta0, theta1, tu0)
					var th1 := lerpf(theta0, theta1, tu1)
					var ph := phi0 if side == 0 else phi1
					var n0 := Vector3(sin(th0) * cos(ph), cos(th0), sin(th0) * sin(ph))
					var n1 := Vector3(sin(th1) * cos(ph), cos(th1), sin(th1) * sin(ph))
					var outward := Vector3(-sin(ph), 0.0, cos(ph)) * (1.0 if side == 0 else -1.0)
					var o0 := n0 * radius
					var o1 := n1 * radius
					var i0 := n0 * r_in
					var i1 := n1 * r_in
					_emit_quad(st, o0, o1, i1, i0, outward,
						Vector2(0, tu0), Vector2(0, tu1), Vector2(1, tu1), Vector2(1, tu0))
		if rims and not v_pole_lo:
			for u in seg_u:
				var ph0 := lerpf(phi0, phi1, float(u) / float(seg_u))
				var ph1 := lerpf(phi0, phi1, float(u + 1) / float(seg_u))
				var n0 := Vector3(sin(theta0) * cos(ph0), cos(theta0), sin(theta0) * sin(ph0))
				var n1 := Vector3(sin(theta0) * cos(ph1), cos(theta0), sin(theta0) * sin(ph1))
				var outward := -Vector3(sin(theta0) * cos(ph0), cos(theta0), sin(theta0) * sin(ph0)).normalized()
				_emit_quad(st, n0 * radius, n1 * radius, n1 * r_in, n0 * r_in, outward,
					Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		if rims and not v_pole_hi:
			for u in seg_u:
				var ph0 := lerpf(phi0, phi1, float(u) / float(seg_u))
				var ph1 := lerpf(phi0, phi1, float(u + 1) / float(seg_u))
				var n0 := Vector3(sin(theta1) * cos(ph0), cos(theta1), sin(theta1) * sin(ph0))
				var n1 := Vector3(sin(theta1) * cos(ph1), cos(theta1), sin(theta1) * sin(ph1))
				var outward := Vector3(sin(theta1) * cos(ph0), cos(theta1), sin(theta1) * sin(ph0)).normalized()
				_emit_quad(st, n0 * radius, n1 * radius, n1 * r_in, n0 * r_in, outward,
					Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	return st.commit()


## Spherical cap (dome / lens skin) with radial UVs.
## Faces +Y, base radius `radius`, height `bulge`. UV = 0.5 + pos.xz / (2*radius).
static func dome(radius: float, bulge: float, sides := 32, rings := 10, smooth := true) -> ArrayMesh:
	var st := _new_surface()
	var rr := maxf(radius, 0.0001)
	# Sagitta s -> sphere radius R = (r^2 + s^2) / (2s)
	var Rs := (radius * radius + bulge * bulge) / (2.0 * maxf(bulge, 0.0001))
	var t_max := acos(clampf(1.0 - bulge / Rs, -1.0, 1.0))
	var pts: Array = []
	for v in rings + 1:
		var tv := float(v) / float(rings)
		var th := t_max * tv
		var row: Array[Vector3] = []
		for u in sides + 1:
			var ph := TAU * float(u) / float(sides)
			row.append(Vector3(sin(th) * cos(ph) * Rs, Rs * cos(th) - (Rs - bulge), sin(th) * sin(ph) * Rs))
		pts.append(row)
	var uvs: Array = []
	for v in rings + 1:
		var tv := float(v) / float(rings)
		var th := t_max * tv
		var row: Array[Vector2] = []
		if v == 0:
			for u in sides + 1:
				row.append(Vector2(0.5, 0.5))
		else:
			for u in sides + 1:
				var ph := TAU * float(u) / float(sides)
				row.append(Vector2(0.5 + 0.5 * (sin(th) * cos(ph) * Rs / radius),
					0.5 + 0.5 * (sin(th) * sin(ph) * Rs / radius)))
		uvs.append(row)

	var n0 := Vector3.UP
	for v in rings:
		var r0: Array[Vector3] = pts[v]
		var r1: Array[Vector3] = pts[v + 1]
		var u0: Array[Vector2] = uvs[v]
		var u1: Array[Vector2] = uvs[v + 1]
		var c0 := Vector3(0, bulge - Rs, 0)
		for u in sides:
			var a := r0[u]
			var b := r0[u + 1]
			var c := r1[u + 1]
			var d := r1[u]
			var na := (a - c0).normalized() if v > 0 else n0
			var nb := (b - c0).normalized() if v > 0 else n0
			var nc := (c - c0).normalized()
			var nd := (d - c0).normalized()
			if smooth:
				_emit_quad_n(st, a, b, c, d, na, nb, nc, nd, u0[u], u0[u + 1], u1[u + 1], u1[u])
			else:
				_emit_quad(st, a, b, c, d, (na + nb + nc + nd).normalized(),
					u0[u], u0[u + 1], u1[u + 1], u1[u])
	return st.commit()


## Beveled flat disc along Y. UVs are radial (0.5,0.5) at center.
static func disc(radius: float, thickness: float, sides := 32, bevel := 0.0) -> ArrayMesh:
	var st := _new_surface()
	var h := thickness * 0.5
	var b := clampf(bevel, 0.0, minf(h * 0.9, radius * 0.4))
	var r := maxf(radius, 0.0001)
	var levels := [
		Vector2(-h, r - b), Vector2(-h + b, r), Vector2(h - b, r), Vector2(h, r - b),
	]
	var loops: Array[PackedVector3Array] = []
	for lv in levels:
		var loop := PackedVector3Array()
		for i in sides:
			var a := TAU * float(i) / float(sides)
			loop.append(Vector3(cos(a) * lv.y, lv.x, sin(a) * lv.y))
		loops.append(loop)
	for l in 3:
		for i in sides:
			var j := (i + 1) % sides
			var a := loops[l][i]
			var bb := loops[l][j]
			var c := loops[l + 1][j]
			var d := loops[l + 1][i]
			var radial := Vector3(a.x + c.x, 0.0, a.z + c.z)
			var guide := radial + Vector3(0, (levels[l + 1].x - levels[l].x) * 4.0, 0)
			_emit_quad(st, a, bb, c, d, guide.normalized(),
				Vector2(0.5 + 0.5 * a.x / r, 0.5 + 0.5 * a.z / r),
				Vector2(0.5 + 0.5 * bb.x / r, 0.5 + 0.5 * bb.z / r),
				Vector2(0.5 + 0.5 * c.x / r, 0.5 + 0.5 * c.z / r),
				Vector2(0.5 + 0.5 * d.x / r, 0.5 + 0.5 * d.z / r))
	for i in sides:
		var j := (i + 1) % sides
		var a := loops[0][i]
		var bb := loops[0][j]
		var c := loops[3][i]
		var d := loops[3][j]
		_emit_tri(st, Vector3(0, -h, 0), a, bb, Vector3.DOWN,
			Vector2(0.5, 0.5), Vector2(0.5 + 0.5 * a.x / r, 0.5 + 0.5 * a.z / r),
			Vector2(0.5 + 0.5 * bb.x / r, 0.5 + 0.5 * bb.z / r))
		_emit_tri(st, Vector3(0, h, 0), c, d, Vector3.UP,
			Vector2(0.5, 0.5), Vector2(0.5 + 0.5 * c.x / r, 0.5 + 0.5 * c.z / r),
			Vector2(0.5 + 0.5 * d.x / r, 0.5 + 0.5 * d.z / r))
	return st.commit()


## Beveled flat annulus (washer) along Y.
static func ring(r_in: float, r_out: float, thickness: float, sides := 40, bevel := 0.0) -> ArrayMesh:
	var st := _new_surface()
	var h := thickness * 0.5
	var b := clampf(bevel, 0.0, minf(h * 0.9, (r_out - r_in) * 0.4))
	var levels := [
		Vector3(-h, r_out - b, 0), Vector3(-h + b, r_out, 0), Vector3(h - b, r_out, 0), Vector3(h, r_out - b, 0),
	]
	# outer wall
	var outer: Array[PackedVector3Array] = []
	var inner: Array[PackedVector3Array] = []
	for lv in levels:
		var lo := PackedVector3Array()
		var li := PackedVector3Array()
		for i in sides:
			var a := TAU * float(i) / float(sides)
			lo.append(Vector3(cos(a) * lv.y, lv.x, sin(a) * lv.y))
			li.append(Vector3(cos(a) * r_in, lv.x, sin(a) * r_in))
		outer.append(lo)
		inner.append(li)
	for l in 3:
		for i in sides:
			var j := (i + 1) % sides
			var a := outer[l][i]
			var bb := outer[l][j]
			var c := outer[l + 1][j]
			var d := outer[l + 1][i]
			var radial := Vector3(a.x + c.x, 0, a.z + c.z)
			_emit_quad(st, a, bb, c, d, (radial + Vector3(0, (levels[l + 1].x - levels[l].x) * 4, 0)).normalized(),
				Vector2(float(i) / sides, 0), Vector2(float(i + 1) / sides, 0),
				Vector2(float(i + 1) / sides, 1), Vector2(float(i) / sides, 1))
	# top / bottom annulus
	for i in sides:
		var j := (i + 1) % sides
		var ot0 := outer[0][i]
		var ot1 := outer[0][j]
		var it0 := inner[0][i]
		var it1 := inner[0][j]
		_emit_quad(st, ot0, ot1, it1, it0, Vector3.DOWN,
			Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0))
		var ob0 := outer[3][i]
		var ob1 := outer[3][j]
		var ib0 := inner[3][i]
		var ib1 := inner[3][j]
		_emit_quad(st, ob0, ob1, ib1, ib0, Vector3.UP,
			Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0))
	# inner wall
	for i in sides:
		var j := (i + 1) % sides
		var a := inner[0][i]
		var bb := inner[0][j]
		var c := inner[3][j]
		var d := inner[3][i]
		var radial := -(Vector3(a.x + c.x, 0, a.z + c.z))
		_emit_quad(st, a, bb, c, d, radial.normalized(),
			Vector2(float(i) / sides, 0), Vector2(float(i + 1) / sides, 0),
			Vector2(float(i + 1) / sides, 1), Vector2(float(i) / sides, 1))
	return st.commit()


## Beveled slab lying in XY, thickness along Z. Flat faces.
static func plate(w: float, h: float, t: float, bevel := 0.012) -> ArrayMesh:
	var st := _new_surface()
	var b := clampf(bevel, 0.001, minf(t * 0.45, minf(w, h) * 0.22))
	var zs := [-t * 0.5, -t * 0.5 + b, t * 0.5 - b, t * 0.5]
	var ws := [maxf(w - 2 * b, 0.01), w, w, maxf(w - 2 * b, 0.01)]
	var hs := [maxf(h - 2 * b, 0.01), h, h, maxf(h - 2 * b, 0.01)]
	var loops: Array[PackedVector3Array] = []
	for l in 4:
		var loop := PackedVector3Array()
		loop.append(Vector3(-ws[l] * 0.5, -hs[l] * 0.5, zs[l]))
		loop.append(Vector3(ws[l] * 0.5, -hs[l] * 0.5, zs[l]))
		loop.append(Vector3(ws[l] * 0.5, hs[l] * 0.5, zs[l]))
		loop.append(Vector3(-ws[l] * 0.5, hs[l] * 0.5, zs[l]))
		loops.append(loop)
	for l in 3:
		for i in 4:
			var j := (i + 1) % 4
			var a := loops[l][i]
			var bb := loops[l][j]
			var c := loops[l + 1][j]
			var d := loops[l + 1][i]
			var mid := (a + bb + c + d) * 0.25
			var dz := -b if l == 0 else (b if l == 2 else 0.0)
			var guide := Vector3(mid.x, mid.y, dz)
			_emit_quad(st, a, bb, c, d, guide.normalized(),
				Vector2(float(i) / 4, float(l) / 3), Vector2(float(i + 1) / 4, float(l) / 3),
				Vector2(float(i + 1) / 4, float(l + 1) / 3), Vector2(float(i) / 4, float(l + 1) / 3))
	for i in 4:
		var j := (i + 1) % 4
		_emit_tri(st, Vector3(0, 0, zs[0]), loops[0][i], loops[0][j], Vector3.FORWARD,
			Vector2(0.5, 0.5), Vector2(loops[0][i].x / w + 0.5, loops[0][i].y / h + 0.5),
			Vector2(loops[0][j].x / w + 0.5, loops[0][j].y / h + 0.5))
		_emit_tri(st, Vector3(0, 0, zs[3]), loops[3][i], loops[3][j], Vector3.BACK,
			Vector2(0.5, 0.5), Vector2(loops[3][i].x / w + 0.5, loops[3][i].y / h + 0.5),
			Vector2(loops[3][j].x / w + 0.5, loops[3][j].y / h + 0.5))
	return st.commit()


## Chamfered octagonal beam along +X, pivoting at x=0, tapered.
## h = vertical (Y), w = lateral (Z).
static func beam(length: float, h0: float, w0: float, h1: float, w1: float,
		chamfer := 0.36, cap0 := true, cap1 := true) -> ArrayMesh:
	var st := _new_surface()
	var xs := [0.0, minf(0.02, length * 0.04), maxf(length - 0.02, length * 0.96), length]
	var hs := [h0 * 0.80, h0, h1, h1 * 0.80]
	var ws := [w0 * 0.80, w0, w1, w1 * 0.80]
	var rings: Array[PackedVector3Array] = []
	for r in 4:
		var ring_pts := PackedVector3Array()
		var pts := _octa_ring(ws[r], hs[r], chamfer)
		for p in pts:
			ring_pts.append(Vector3(xs[r], p.x, p.y))
		rings.append(ring_pts)
	for r in 3:
		for i in 8:
			var j := (i + 1) % 8
			var a := rings[r][i]
			var b := rings[r][j]
			var c := rings[r + 1][j]
			var d := rings[r + 1][i]
			var mid_y := (a.y + c.y) * 0.5
			var mid_z := (a.z + c.z) * 0.5
			var guide := Vector3(0.0, mid_y, mid_z)
			if guide.length_squared() < 1e-8:
				guide = Vector3.UP
			_emit_quad(st, a, b, c, d, guide.normalized(),
				Vector2(float(i) / 8.0, float(r) / 3.0), Vector2(float(i + 1) / 8.0, float(r) / 3.0),
				Vector2(float(i + 1) / 8.0, float(r + 1) / 3.0), Vector2(float(i) / 8.0, float(r + 1) / 3.0))
	if cap0:
		for i in 8:
			var j := (i + 1) % 8
			_emit_tri(st, Vector3(0, 0, 0), rings[0][i], rings[0][j], Vector3.LEFT,
				Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
	if cap1:
		for i in 8:
			var j := (i + 1) % 8
			_emit_tri(st, Vector3(length, 0, 0), rings[3][i], rings[3][j], Vector3.RIGHT,
				Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
	return st.commit()


static func _octa_ring(w: float, h: float, chamfer: float) -> Array[Vector2]:
	var c := clampf(chamfer, 0.02, 0.48)
	return [
		Vector2(h * 0.5, w * c), Vector2(h * 0.5, -w * c),
		Vector2(h * (0.5 - c), -w * 0.5), Vector2(-h * (0.5 - c), -w * 0.5),
		Vector2(-h * 0.5, -w * c), Vector2(-h * 0.5, w * c),
		Vector2(-h * (0.5 - c), w * 0.5), Vector2(h * (0.5 - c), w * 0.5),
	]


## Curved katana volume along +Y. Edge faces +X, thickness along Z.
## UV.x = across width, UV.y = 0 base .. 1 tip.
static func katana(length: float, width: float, thickness: float,
		sori := 0.06, seg := 20, edge_bias := 0.55) -> ArrayMesh:
	var st := _new_surface()
	# 6-point lens cross-section: +X is the cutting edge.
	var profile := [
		Vector2(1.0, 0.0), Vector2(0.62, 0.72), Vector2(-0.72, 0.86),
		Vector2(-1.0, 0.0), Vector2(-0.72, -0.86), Vector2(0.62, -0.72),
	]
	var rings: Array[PackedVector3Array] = []
	var ts: Array[float] = []
	var center_x: Array[float] = []
	for s in seg + 1:
		var t := float(s) / float(seg)
		ts.append(t)
		var env := 0.0
		if t < 0.10:
			env = lerpf(0.55, 1.0, smoothstep(0.0, 0.10, t))
		elif t < 0.94:
			env = 1.0
		else:
			env = pow(maxf(0.0, 1.0 - (t - 0.94) / 0.06), 0.55)
		env = maxf(env, 0.03)
		var cx := -sori * pow(t, 1.7)
		center_x.append(cx)
		var ring_pts := PackedVector3Array()
		for p in profile:
			ring_pts.append(Vector3(cx + p.x * width * 0.5 * env, t * length,
				p.y * thickness * 0.5 * env))
		rings.append(ring_pts)
	for s in seg:
		for i in 6:
			var j := (i + 1) % 6
			var a := rings[s][i]
			var b := rings[s][j]
			var c := rings[s + 1][j]
			var d := rings[s + 1][i]
			var guide := (a + b + c + d) * 0.25 - Vector3((center_x[s] + center_x[s + 1]) * 0.5, 0, 0)
			if guide.length_squared() < 1e-10:
				guide = Vector3.UP
			_emit_quad(st, a, b, c, d, guide.normalized(),
				Vector2(float(i) / 6.0, ts[s]), Vector2(float(i + 1) / 6.0, ts[s]),
				Vector2(float(i + 1) / 6.0, ts[s + 1]), Vector2(float(i) / 6.0, ts[s + 1]))
	# base cap
	for i in 6:
		var j := (i + 1) % 6
		_emit_tri(st, Vector3(center_x[0], 0, 0), rings[0][i], rings[0][j], Vector3.DOWN,
			Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
	return st.commit()


## Ribbons along a polyline; two perpendicular strips for volumetric lightning.
static func ribbon_cross(points: PackedVector3Array, width: float, hint := Vector3.UP,
		width_taper := true) -> ArrayMesh:
	var st := _new_surface()
	if points.size() < 2:
		return st.commit()
	var n := points.size()
	var total := 0.0
	var acc: Array[float] = [0.0]
	for i in n - 1:
		total += points[i].distance_to(points[i + 1])
		acc.append(total)
	if total < 1e-5:
		return st.commit()
	for strip in 2:
		var h := hint if strip == 0 else hint.cross(Vector3(0, 0, 1))
		if h.length_squared() < 1e-8:
			h = Vector3.RIGHT
		for i in n - 1:
			var a := points[i]
			var b := points[i + 1]
			var dir := (b - a).normalized()
			var side := dir.cross(h)
			if side.length_squared() < 1e-8:
				continue
			side = side.normalized()
			var w0 := width
			var w1 := width
			if width_taper:
				var t0 := acc[i] / total
				var t1 := acc[i + 1] / total
				w0 = width * lerpf(1.0, 0.25, t0)
				w1 = width * lerpf(1.0, 0.25, t1)
			var a0 := a - side * w0
			var a1 := a + side * w0
			var b0 := b - side * w1
			var b1 := b + side * w1
			_emit_quad(st, a0, a1, b1, b0, h,
				Vector2(0, acc[i] / total), Vector2(1, acc[i] / total),
				Vector2(1, acc[i + 1] / total), Vector2(0, acc[i + 1] / total))
	return st.commit()


## Flat ribbon along a polyline (single strip, oriented toward `facing`).
static func ribbon(points: PackedVector3Array, width: float, facing := Vector3.UP,
		uv_v_scale := 1.0) -> ArrayMesh:
	var st := _new_surface()
	if points.size() < 2:
		return st.commit()
	var total := 0.0
	var acc: Array[float] = [0.0]
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
		acc.append(total)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var dir := (b - a).normalized()
		var side := dir.cross(facing)
		if side.length_squared() < 1e-8:
			continue
		side = side.normalized() * width * 0.5
		_emit_quad(st, a - side, a + side, b + side, b - side, facing,
			Vector2(0, acc[i] * uv_v_scale), Vector2(1, acc[i] * uv_v_scale),
			Vector2(1, acc[i + 1] * uv_v_scale), Vector2(0, acc[i + 1] * uv_v_scale))
	return st.commit()


## Merge several ArrayMeshes into one (single surface).
static func merge(meshes: Array) -> ArrayMesh:
	var st := _new_surface()
	for m in meshes:
		if m is ArrayMesh:
			var arr: Array = m.surface_get_arrays(0)
			if arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
				st.append_from(m, 0, Transform3D.IDENTITY)
	return st.commit()


# ------------------------------------------------------------------ helpers

static func add(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO,
		rot_deg := Vector3.ZERO, scl := Vector3.ONE, node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	if node_name != "":
		mi.name = node_name
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos: Vector3, node_name := "") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	if node_name != "":
		n.name = node_name
	parent.add_child(n)
	return n


static func bolt(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> void:
	add(parent, prism(6, radius, radius * 0.82, height), mat, pos)


## Polyline arc between two points with randomized perpendicular offsets.
static func arc_points(a: Vector3, b: Vector3, segments: int, amplitude: float,
		seed_value: int, normal_hint := Vector3.UP) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts := PackedVector3Array()
	var dir := (b - a).normalized()
	var side := dir.cross(normal_hint)
	if side.length_squared() < 1e-8:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(dir).normalized()
	for i in segments + 1:
		var t := float(i) / float(segments)
		var envelope := sin(t * PI)
		var off := side * rng.randf_range(-amplitude, amplitude) * envelope \
			+ up * rng.randf_range(-amplitude, amplitude) * envelope
		pts.append(a.lerp(b, t) + off)
	return pts