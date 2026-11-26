extends RefCounted
## MeshKit — tiny procedural mesh factory.
##
## Every triangle is emitted with a hand-computed flat normal, so the mech reads
## as hard-surface, faceted machinery rather than smooth primitives.  All meshes
## are built from pure math: no imported meshes, textures or models.
##
## Winding convention (Godot): front faces are clockwise when seen from outside.
## We pick the order per triangle so that cross(b-a, c-a) points *into* the
## surface while the supplied normal points outward.

const TAU := PI * 2.0


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
	# Godot wants clockwise (outward normal opposite the geometric cross).
	# The current order has g along the guide, so flip once for rendering.
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


## Faceted tapered prism, axis along +Y, centered on origin.
## r_top = 0 produces a pointed cone.
static func prism(sides: int, r_bottom: float, r_top: float, height: float,
		angle_offset := 0.0, cap_bottom := true, cap_top := true) -> ArrayMesh:
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
	if cap_bottom and r_bottom > 1e-5:
		var bc := Vector3(0, y0, 0)
		for i in sides:
			var j := (i + 1) % sides
			_emit_tri(st, bc, bottom[i], bottom[j], Vector3.DOWN, Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
	if cap_top and r_top > 1e-5:
		var tc := Vector3(0, y1, 0)
		for i in sides:
			var j := (i + 1) % sides
			_emit_tri(st, tc, top[i], top[j], Vector3.UP, Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0))
	return st.commit()


## Octagonal cross-section ring for beams/plates. Returns [y, z] offsets
## (cross-section lives in the YZ plane for beams along X).
static func _octa_ring(w: float, h: float, chamfer: float) -> Array[Vector2]:
	var c := clampf(chamfer, 0.02, 0.48)
	return [
		Vector2(h * 0.5, w * c),
		Vector2(h * 0.5, -w * c),
		Vector2(h * (0.5 - c), -w * 0.5),
		Vector2(-h * (0.5 - c), -w * 0.5),
		Vector2(-h * 0.5, -w * c),
		Vector2(-h * 0.5, w * c),
		Vector2(-h * (0.5 - c), w * 0.5),
		Vector2(h * (0.5 - c), w * 0.5),
	]


## Chamfered tapered limb armor along +X, pivoting at x = 0.
## w = lateral (Z) width, h = vertical (Y) thickness.
static func beam_x(length: float, h0: float, w0: float, h1: float, w1: float,
		chamfer := 0.36) -> ArrayMesh:
	var st := _new_surface()
	# Slightly inset rings at both ends make the caps read as machined bevels.
	var xs := [0.0, minf(0.055, length * 0.06), maxf(length - 0.055, length * 0.94), length]
	var hs := [h0 * 0.82, h0, h1, h1 * 0.82]
	var ws := [w0 * 0.82, w0, w1, w1 * 0.82]
	var rings: Array[PackedVector3Array] = []
	for r in 4:
		var ring := PackedVector3Array()
		var pts := _octa_ring(ws[r], hs[r], chamfer)
		for p in pts:
			ring.append(Vector3(xs[r], p.x, p.y))
		rings.append(ring)
	for r in 3:
		var ra := rings[r]
		var rb := rings[r + 1]
		for i in 8:
			var j := (i + 1) % 8
			var mid_y := (ra[i].y + rb[j].y) * 0.5
			var mid_z := (ra[i].z + rb[j].z) * 0.5
			var guide := Vector3(0.0, mid_y, mid_z).normalized()
			if guide.length_squared() < 0.5:
				guide = Vector3.UP
			var u0 := float(i) / 8.0
			var u1 := float(i + 1) / 8.0
			_emit_quad(st, ra[i], ra[j], rb[j], rb[i], guide,
				Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1))
	# caps
	for i in 8:
		var j := (i + 1) % 8
		_emit_tri(st, Vector3(0, 0, 0), rings[0][i], rings[0][j], Vector3.LEFT,
			Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
		_emit_tri(st, Vector3(length, 0, 0), rings[3][i], rings[3][j], Vector3.RIGHT,
			Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
	return st.commit()


## Beveled armor slab lying in XZ, thickness along Y.
static func slab(w: float, d: float, h: float, bevel := 0.018) -> ArrayMesh:
	var st := _new_surface()
	var b := clampf(bevel, 0.001, minf(h * 0.45, minf(w, d) * 0.3))
	var rings := [
		{"y": -h * 0.5, "s": Vector2(maxf(w - 2.0 * b, 0.01), maxf(d - 2.0 * b, 0.01))},
		{"y": -h * 0.5 + b, "s": Vector2(w, d)},
		{"y": h * 0.5 - b, "s": Vector2(w, d)},
		{"y": h * 0.5, "s": Vector2(maxf(w - 2.0 * b, 0.01), maxf(d - 2.0 * b, 0.01))},
	]
	var octa := [
		Vector2(1.0, 0.55), Vector2(0.55, 1.0), Vector2(-0.55, 1.0), Vector2(-1.0, 0.55),
		Vector2(-1.0, -0.55), Vector2(-0.55, -1.0), Vector2(0.55, -1.0), Vector2(1.0, -0.55),
	]
	var loops: Array[PackedVector3Array] = []
	for r in 4:
		var loop := PackedVector3Array()
		var s: Vector2 = rings[r]["s"]
		var y: float = rings[r]["y"]
		for p in octa:
			loop.append(Vector3(p.x * s.x * 0.5, y, p.y * s.y * 0.5))
		loops.append(loop)
	for r in 3:
		var y0: float = rings[r]["y"]
		var y1: float = rings[r + 1]["y"]
		for i in 8:
			var j := (i + 1) % 8
			var a := loops[r][i]
			var bb := loops[r][j]
			var c := loops[r + 1][j]
			var dd := loops[r + 1][i]
			var guide := Vector3(a.x + bb.x + c.x + dd.x, (y1 - y0) * 2.0, a.z + bb.z + c.z + dd.z)
			if guide.length_squared() < 1e-8:
				guide = Vector3.UP
			_emit_quad(st, a, bb, c, dd, guide.normalized(),
				Vector2(float(i) / 8.0, 0), Vector2(float(i + 1) / 8.0, 0),
				Vector2(float(i + 1) / 8.0, 1), Vector2(float(i) / 8.0, 1))
	for i in 8:
		var j := (i + 1) % 8
		_emit_tri(st, Vector3(0, rings[0]["y"], 0), loops[0][i], loops[0][j], Vector3.DOWN,
			Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
		_emit_tri(st, Vector3(0, rings[3]["y"], 0), loops[3][i], loops[3][j], Vector3.UP,
			Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
	return st.commit()


## Energy blade: faceted double-edged blade along +Y, UV.y = 0 at base, 1 at tip.
## The profile swells slightly past the guard, then tapers to a needle point.
static func blade(length: float, width: float, thickness: float, curve := 0.0, segments := 14) -> ArrayMesh:
	var st := _new_surface()
	# 6-sided lens cross-section (x = edge-to-edge, z = flat-to-flat).
	var profile := [
		Vector2(0.0, 1.0), Vector2(1.0, 0.42), Vector2(1.0, -0.42),
		Vector2(0.0, -1.0), Vector2(-1.0, -0.42), Vector2(-1.0, 0.42),
	]
	var rings: Array[PackedVector3Array] = []
	var ts: Array[float] = []
	for s in segments + 1:
		var t := float(s) / float(segments)
		ts.append(t)
		# width envelope: pinch at guard, maximum at 22%, long taper to the point
		var env := 0.0
		if t < 0.22:
			env = lerpf(0.62, 1.0, smoothstep(0.0, 0.22, t))
		else:
			env = pow(maxf(0.0, 1.0 - (t - 0.22) / 0.78), 0.72)
		env = maxf(env, 0.02)
		var xoff := curve * pow(t, 1.6)
		var ring := PackedVector3Array()
		for p in profile:
			ring.append(Vector3(p.x * width * 0.5 * env + xoff, t * length, p.y * thickness * 0.5 * env))
		rings.append(ring)
	for s in segments:
		for i in 6:
			var j := (i + 1) % 6
			var a := rings[s][i]
			var b := rings[s][j]
			var c := rings[s + 1][j]
			var d := rings[s + 1][i]
			var guide := Vector3(a.x + b.x + c.x + d.x - 4.0 * curve * pow(ts[s], 1.6), 0.0, a.z + b.z + c.z + d.z)
			if guide.length_squared() < 1e-8:
				guide = Vector3.UP
			_emit_quad(st, a, b, c, d, guide.normalized(),
				Vector2(float(i) / 6.0, ts[s]), Vector2(float(i + 1) / 6.0, ts[s]),
				Vector2(float(i + 1) / 6.0, ts[s + 1]), Vector2(float(i) / 6.0, ts[s + 1]))
	# base cap
	for i in 6:
		var j := (i + 1) % 6
		_emit_tri(st, Vector3(0, 0, 0), rings[0][i], rings[0][j], Vector3.DOWN,
			Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
	return st.commit()


## Low-poly faceted sphere (fixed lat/long resolution, flat shaded).
static func gem(radius: float, rings := 4, sides := 8) -> ArrayMesh:
	var st := _new_surface()
	var loops: Array[PackedVector3Array] = []
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		var loop := PackedVector3Array()
		for i in sides:
			var a := TAU * float(i) / float(sides)
			loop.append(Vector3(sin(phi) * cos(a) * radius, cos(phi) * radius, sin(phi) * sin(a) * radius))
		loops.append(loop)
	for r in rings:
		for i in sides:
			var j := (i + 1) % sides
			var guide := loops[r][i] + loops[r][j] + loops[r + 1][j] + loops[r + 1][i]
			if guide.length_squared() < 1e-8:
				continue
			_emit_quad(st, loops[r][i], loops[r][j], loops[r + 1][j], loops[r + 1][i], guide.normalized(),
				Vector2(float(i) / sides, float(r) / rings), Vector2(float(i + 1) / sides, float(r) / rings),
				Vector2(float(i + 1) / sides, float(r + 1) / rings), Vector2(float(i) / sides, float(r + 1) / rings))
	return st.commit()


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


## Axis-aligned bolt/stud.
static func bolt(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> void:
	var mesh := prism(6, radius, radius * 0.82, height)
	add(parent, mesh, mat, pos)

## Flat greatsword blade along +Y (UV.y = 0 at guard, 1 at tip).
## Hexagonal cross-section: two wide flat faces + narrow cutting bevels.
## `taper` 0..1 controls where the long taper to the point begins.
static func flat_blade(length: float, width: float, thickness: float,
		taper := 0.24, segments := 18) -> ArrayMesh:
	var st := _new_surface()
	var profile := [
		Vector2(-1.0, 0.0),
		Vector2(-0.18, 1.0),
		Vector2(0.18, 1.0),
		Vector2(1.0, 0.0),
		Vector2(0.18, -1.0),
		Vector2(-0.18, -1.0),
	]
	var rings: Array[PackedVector3Array] = []
	var ts: Array[float] = []
	for s in segments + 1:
		var t := float(s) / float(segments)
		ts.append(t)
		# Greatsword profile: broad parallel edges for most of the blade, then
		# a short spear-point.  `taper` marks where the point starts (0..1).
		var env := 0.0
		if t < 0.06:
			env = lerpf(0.70, 1.0, smoothstep(0.0, 0.06, t))
		elif t < taper:
			env = 1.0
		else:
			env = pow(maxf(0.0, 1.0 - (t - taper) / maxf(1.0 - taper, 0.001)), 0.72)
		env = maxf(env, 0.015)
		# near the tip keep the silhouette sharp: width collapses faster than thickness
		var wenv := env
		var tenv := minf(1.0, env * 1.25)
		var ring := PackedVector3Array()
		for p in profile:
			ring.append(Vector3(p.x * width * 0.5 * wenv, t * length,
				p.y * thickness * 0.5 * tenv))
		rings.append(ring)
	for s in segments:
		for i in 6:
			var j := (i + 1) % 6
			var a := rings[s][i]
			var b := rings[s][j]
			var c := rings[s + 1][j]
			var d := rings[s + 1][i]
			var guide := Vector3(a.x + b.x + c.x + d.x, 0.0, a.z + b.z + c.z + d.z)
			if guide.length_squared() < 1e-10:
				guide = Vector3.UP
			_emit_quad(st, a, b, c, d, guide.normalized(),
				Vector2(float(i) / 6.0, ts[s]), Vector2(float(i + 1) / 6.0, ts[s]),
				Vector2(float(i + 1) / 6.0, ts[s + 1]), Vector2(float(i) / 6.0, ts[s + 1]))
	# guard cap
	for i in 6:
		var j := (i + 1) % 6
		_emit_tri(st, Vector3.ZERO, rings[0][i], rings[0][j], Vector3.DOWN,
			Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
	return st.commit()


## Hemisphere with its flat base at y=0 and its pole at +Y.
## Used for recessed optical domes; flat-shaded like the rest of the kit.
static func dome(radius: float, rings := 6, sides := 20, cap := true) -> ArrayMesh:
	var st := _new_surface()
	var loops: Array[PackedVector3Array] = []
	for r in rings + 1:
		var phi := (PI * 0.5) * float(r) / float(rings)
		var loop := PackedVector3Array()
		var rr := sin(phi) * radius
		var yy := cos(phi) * radius
		for i in sides:
			var a := TAU * float(i) / float(sides)
			loop.append(Vector3(cos(a) * rr, yy, sin(a) * rr))
		loops.append(loop)
	for r in rings:
		for i in sides:
			var j := (i + 1) % sides
			var guide := loops[r][i] + loops[r][j] + loops[r + 1][j] + loops[r + 1][i]
			if guide.length_squared() < 1e-10:
				continue
			_emit_quad(st, loops[r][i], loops[r][j], loops[r + 1][j], loops[r + 1][i],
				guide.normalized(),
				Vector2(float(i) / float(sides), float(r) / float(rings)),
				Vector2(float(i + 1) / float(sides), float(r) / float(rings)),
				Vector2(float(i + 1) / float(sides), float(r + 1) / float(rings)),
				Vector2(float(i) / float(sides), float(r + 1) / float(rings)))
	# base cap (optional: an open dome has no dark backing disc)
	if cap:
		for i in sides:
			var j := (i + 1) % sides
			_emit_tri(st, Vector3(0, 0, 0), loops[rings][i], loops[rings][j], Vector3.DOWN,
				Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
	return st.commit()


## Smooth parametric ellipsoid / ellipsoid patch with analytic normals.
## theta runs polar from +Y (0) to -Y (PI); use theta0..theta1 for domes.
## This is the curved-surface counterpart to the faceted prism/gem kit.
static func ellipsoid(radii: Vector3, rings := 24, sides := 40,
		theta0 := 0.0, theta1 := PI, holes: Array = [],
		phi0 := 0.0, phi1 := TAU) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	var norms: Array[Vector3] = []
	var wrap_phi := absf((phi1 - phi0) - TAU) < 0.001
	var phi_count := sides if wrap_phi else sides + 1
	for i in rings + 1:
		var th := lerpf(theta0, theta1, float(i) / float(rings))
		for j in phi_count:
			var ph := lerpf(phi0, phi1, float(j) / float(sides))
			var p := Vector3(sin(th) * cos(ph) * radii.x,
					cos(th) * radii.y,
					sin(th) * sin(ph) * radii.z)
			var n := Vector3(p.x / maxf(radii.x * radii.x, 1e-6),
					p.y / maxf(radii.y * radii.y, 1e-6),
					p.z / maxf(radii.z * radii.z, 1e-6)).normalized()
			verts.append(p)
			norms.append(n)
			st.set_normal(n)
			st.set_uv(Vector2(float(j) / float(sides), float(i) / float(rings)))
			st.add_vertex(p)
	var stride := sides if wrap_phi else sides + 1
	for i in rings:
		for j in sides:
			var j2 := (j + 1) % stride if wrap_phi else j + 1
			var a := i * stride + j
			var b := (i + 1) * stride + j
			var c := (i + 1) * stride + j2
			var d := i * stride + j2
			# optional openings (optical sockets) in the curved shell
			var qc := (verts[a] + verts[b] + verts[c] + verts[d]) * 0.25
			var skip := false
			for h in holes:
				if qc.distance_to(h["center"]) < float(h["radius"]):
					skip = true
					break
			if skip:
				continue
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(a)
			st.add_index(d)
			st.add_index(c)
	return st.commit()


# ==============================================================================
# Smooth parametric curved surfaces (loft, solid-thickness shell, lathe, blade)
# ==============================================================================

static func _emit_smooth_grid(st: SurfaceTool, rows: Array, norms: Array, uvs: Array,
		wrap_cols: bool, base_idx := 0) -> int:
	var r_count := rows.size()
	var c_count: int = rows[0].size()
	for r in r_count:
		for c in c_count:
			st.set_normal(norms[r][c])
			st.set_uv(uvs[r][c])
			st.add_vertex(rows[r][c])
	var quads_c := c_count if wrap_cols else c_count - 1
	for r in r_count - 1:
		for c in quads_c:
			var c1 := (c + 1) % c_count if wrap_cols else c + 1
			var i0 := base_idx + r * c_count + c
			var i1 := base_idx + r * c_count + c1
			var i2 := base_idx + (r + 1) * c_count + c1
			var i3 := base_idx + (r + 1) * c_count + c
			var p0: Vector3 = rows[r][c]
			var p1: Vector3 = rows[r][c1]
			var p2: Vector3 = rows[r + 1][c1]
			var p3: Vector3 = rows[r + 1][c]
			var guide: Vector3 = norms[r][c] + norms[r][c1] + norms[r + 1][c1] + norms[r + 1][c]
			var g := (p1 - p0).cross(p2 - p0)
			if g.dot(guide) > 0.0:
				st.add_index(i0)
				st.add_index(i2)
				st.add_index(i1)
				st.add_index(i0)
				st.add_index(i3)
				st.add_index(i2)
			else:
				st.add_index(i0)
				st.add_index(i1)
				st.add_index(i2)
				st.add_index(i0)
				st.add_index(i2)
				st.add_index(i3)
	return base_idx + r_count * c_count


static func _emit_cap_fan(st: SurfaceTool, center: Vector3, ring: Array,
		nrm: Vector3, base_idx: int) -> int:
	var n := ring.size()
	st.set_normal(nrm)
	st.set_uv(Vector2(0.5, 0.5))
	st.add_vertex(center)
	for i in n:
		var a := TAU * float(i) / float(n)
		st.set_normal(nrm)
		st.set_uv(Vector2(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)))
		st.add_vertex(ring[i])
	for i in n:
		var j := (i + 1) % n
		var p1: Vector3 = ring[i]
		var p2: Vector3 = ring[j]
		var g := (p1 - center).cross(p2 - center)
		if g.dot(nrm) > 0.0:
			st.add_index(base_idx)
			st.add_index(base_idx + 1 + j)
			st.add_index(base_idx + 1 + i)
		else:
			st.add_index(base_idx)
			st.add_index(base_idx + 1 + i)
			st.add_index(base_idx + 1 + j)
	return base_idx + 1 + n


static func _eval_station(stations: Array, u: float) -> Array:
	var n := stations.size()
	if u <= float(stations[0][0]):
		return stations[0]
	if u >= float(stations[n - 1][0]):
		return stations[n - 1]
	for i in n - 1:
		var t0 := float(stations[i][0])
		var t1 := float(stations[i + 1][0])
		if u <= t1:
			var uu := clampf((u - t0) / maxf(t1 - t0, 1e-6), 0.0, 1.0)
			var s := uu * uu * (3.0 - 2.0 * uu)
			var a: Array = stations[i]
			var b: Array = stations[i + 1]
			return [
				u,
				lerpf(float(a[1]), float(b[1]), s),
				lerpf(float(a[2]), float(b[2]), s),
				lerpf(float(a[3]), float(b[3]), s),
				lerpf(float(a[4]), float(b[4]), s),
				lerpf(float(a[5]), float(b[5]), s),
				lerpf(float(a[6]), float(b[6]), s),
			]
	return stations[n - 1]


static func _sample_station_ts(stations: Array, substeps: int) -> Array[float]:
	var ts: Array[float] = []
	var steps := maxi(substeps, 1)
	for i in stations.size() - 1:
		var t0 := float(stations[i][0])
		var t1 := float(stations[i + 1][0])
		for k in steps:
			ts.append(lerpf(t0, t1, float(k) / float(steps)))
	ts.append(float(stations[stations.size() - 1][0]))
	return ts


static func _super_section(a: float, ry_pos: float, ry_neg: float, rz: float,
		exp_val: float, y_off: float, z_off: float) -> Vector2:
	var cy := cos(a)
	var sz := sin(a)
	var ry := ry_pos if cy >= 0.0 else ry_neg
	var y := y_off + signf(cy) * pow(absf(cy), exp_val) * ry
	var z := z_off + signf(sz) * pow(absf(sz), exp_val) * rz
	return Vector2(y, z)


## Smooth parametric lofted limb body along +X (pivoting at x = 0).
## Each station: [t, ry_pos, ry_neg, rz, exp_val, y_off, z_off].
static func loft_x(length: float, stations: Array, sides := 24, substeps := 3,
		cap_start := true, cap_end := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ts := _sample_station_ts(stations, substeps)
	var r_count := ts.size()
	var rows := []
	var centers: Array[Vector3] = []
	var uvs := []
	for r in r_count:
		var t := ts[r]
		var s := _eval_station(stations, t)
		var ry_pos := float(s[1])
		var ry_neg := float(s[2])
		var rz := float(s[3])
		var ex := float(s[4])
		var yo := float(s[5])
		var zo := float(s[6])
		var x := t * length
		centers.append(Vector3(x, yo, zo))
		var prow := []
		var urow := []
		for c in sides:
			var u := float(c) / float(sides)
			var yz := _super_section(TAU * u, ry_pos, ry_neg, rz, ex, yo, zo)
			prow.append(Vector3(x, yz.x, yz.y))
			urow.append(Vector2(u, t))
		rows.append(prow)
		uvs.append(urow)
	var norms := []
	for r in r_count:
		var nrow := []
		var r0 := maxi(r - 1, 0)
		var r1 := mini(r + 1, r_count - 1)
		for c in sides:
			var c0 := (c - 1 + sides) % sides
			var c1 := (c + 1) % sides
			var du: Vector3 = rows[r][c1] - rows[r][c0]
			var dv: Vector3 = rows[r1][c] - rows[r0][c]
			var n := du.cross(dv)
			var radial: Vector3 = rows[r][c] - centers[r]
			radial.x = 0.0
			if n.length_squared() < 1e-12:
				n = radial if radial.length_squared() > 1e-12 else Vector3.UP
			n = n.normalized()
			if n.dot(radial) < 0.0:
				n = -n
			nrow.append(n)
		norms.append(nrow)
	var base := _emit_smooth_grid(st, rows, norms, uvs, true, 0)
	if cap_start:
		base = _emit_cap_fan(st, centers[0], rows[0], Vector3.LEFT, base)
	if cap_end:
		_emit_cap_fan(st, centers[r_count - 1], rows[r_count - 1], Vector3.RIGHT, base)
	return st.commit()


## Solid-thickness curved armor cowling along +X spanning angle phi0..phi1
## (0 = +Y top, +/-PI/2 = +/-Z sides, PI = -Y bottom).
static func shell_x(length: float, stations: Array, phi0: float, phi1: float,
		thickness: float, sides := 18, substeps := 3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ts := _sample_station_ts(stations, substeps)
	var r_count := ts.size()
	var c_count := sides + 1
	var out_rows := []
	var in_rows := []
	var centers: Array[Vector3] = []
	var th_local: Array[float] = []
	var uvs := []
	for r in r_count:
		var t := ts[r]
		var s := _eval_station(stations, t)
		var ry_pos := float(s[1])
		var ry_neg := float(s[2])
		var rz := float(s[3])
		var ex := float(s[4])
		var yo := float(s[5])
		var zo := float(s[6])
		var x := t * length
		centers.append(Vector3(x, yo, zo))
		th_local.append(minf(thickness, minf(minf(ry_pos, ry_neg), rz) * 0.55))
		var prow := []
		var urow := []
		for c in c_count:
			var u := float(c) / float(sides)
			var a := lerpf(phi0, phi1, u)
			var yz := _super_section(a, ry_pos, ry_neg, rz, ex, yo, zo)
			prow.append(Vector3(x, yz.x, yz.y))
			urow.append(Vector2(u, t))
		out_rows.append(prow)
		uvs.append(urow)
	var out_norms := []
	var in_norms := []
	for r in r_count:
		var onrow := []
		var inrow := []
		var irow := []
		var r0 := maxi(r - 1, 0)
		var r1 := mini(r + 1, r_count - 1)
		for c in c_count:
			var c0 := maxi(c - 1, 0)
			var c1 := mini(c + 1, c_count - 1)
			var du: Vector3 = out_rows[r][c1] - out_rows[r][c0]
			var dv: Vector3 = out_rows[r1][c] - out_rows[r0][c]
			var n := du.cross(dv)
			var radial: Vector3 = out_rows[r][c] - centers[r]
			radial.x = 0.0
			if n.length_squared() < 1e-12:
				n = radial if radial.length_squared() > 1e-12 else Vector3.UP
			n = n.normalized()
			if n.dot(radial) < 0.0:
				n = -n
			onrow.append(n)
			inrow.append(-n)
			irow.append(out_rows[r][c] - n * th_local[r])
		out_norms.append(onrow)
		in_norms.append(inrow)
		in_rows.append(irow)
	var base := _emit_smooth_grid(st, out_rows, out_norms, uvs, false, 0)
	base = _emit_smooth_grid(st, in_rows, in_norms, uvs, false, base)
	# Stitch perimeter strips with crisp rim normals
	for edge_c in [0, c_count - 1]:
		var erows := []
		var enorms := []
		var euvs := []
		for r in r_count:
			var p_out: Vector3 = out_rows[r][edge_c]
			var p_in: Vector3 = in_rows[r][edge_c]
			var tang: Vector3
			if edge_c == 0:
				tang = (out_rows[r][0] - out_rows[r][1]).normalized()
			else:
				tang = (out_rows[r][edge_c] - out_rows[r][edge_c - 1]).normalized()
			erows.append([p_out, p_in])
			enorms.append([tang, tang])
			euvs.append([Vector2(0.0, ts[r]), Vector2(1.0, ts[r])])
		base = _emit_smooth_grid(st, erows, enorms, euvs, false, base)
	for cap_spec in [[0, Vector3.LEFT], [r_count - 1, Vector3.RIGHT]]:
		var rr: int = int(cap_spec[0])
		var nrm: Vector3 = cap_spec[1]
		var crows := [[], []]
		var cnorms := [[], []]
		var cuvs := [[], []]
		for c in c_count:
			var u := float(c) / float(sides)
			crows[0].append(out_rows[rr][c])
			crows[1].append(in_rows[rr][c])
			cnorms[0].append(nrm)
			cnorms[1].append(nrm)
			cuvs[0].append(Vector2(u, 0.0))
			cuvs[1].append(Vector2(u, 1.0))
		base = _emit_smooth_grid(st, crows, cnorms, cuvs, false, base)
	return st.commit()


## Interpolated Z half-width (rz) at distance `d` along +X for a loft_x / shell_x
## station array. Used to plant forearm lamps flush on the curved armor skin.
static func loft_half_w(d: float, length: float, stations: Array) -> float:
	var u := clampf(d / maxf(length, 1e-5), 0.0, 1.0)
	var s := _eval_station(stations, u)
	return float(s[3])


## Smooth surface of revolution along axis ("x", "y", or "z").
## profile_cr: array of [coord, radius] pairs.
static func smooth_lathe(profile_cr: Array, sides := 28, axis := "y",
		cap_start := true, cap_end := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_count := profile_cr.size()
	var rows := []
	var centers: Array[Vector3] = []
	var uvs := []
	for r in r_count:
		var coord := float(profile_cr[r][0])
		var rad := maxf(float(profile_cr[r][1]), 0.0)
		var c_pt := Vector3(coord, 0, 0) if axis == "x" else (Vector3(0, 0, coord) if axis == "z" else Vector3(0, coord, 0))
		centers.append(c_pt)
		var prow := []
		var urow := []
		for c in sides:
			var u := float(c) / float(sides)
			var a := TAU * u
			var ca := cos(a) * rad
			var sa := sin(a) * rad
			var pt: Vector3
			if axis == "x":
				pt = Vector3(coord, ca, sa)
			elif axis == "z":
				pt = Vector3(ca, sa, coord)
			else:
				pt = Vector3(ca, coord, sa)
			prow.append(pt)
			urow.append(Vector2(u, float(r) / float(maxi(r_count - 1, 1))))
		rows.append(prow)
		uvs.append(urow)
	var norms := []
	for r in r_count:
		var nrow := []
		var r0 := maxi(r - 1, 0)
		var r1 := mini(r + 1, r_count - 1)
		for c in sides:
			var c0 := (c - 1 + sides) % sides
			var c1 := (c + 1) % sides
			var du: Vector3 = rows[r][c1] - rows[r][c0]
			var dv: Vector3 = rows[r1][c] - rows[r0][c]
			var radial: Vector3 = rows[r][c] - centers[r]
			var n := du.cross(dv)
			if n.length_squared() < 1e-12:
				if radial.length_squared() > 1e-12:
					n = radial
				else:
					var ax_v := Vector3.RIGHT if axis == "x" else (Vector3.BACK if axis == "z" else Vector3.UP)
					n = -ax_v if r == 0 else ax_v
			n = n.normalized()
			if radial.length_squared() > 1e-10 and n.dot(radial) < 0.0:
				n = -n
			nrow.append(n)
		norms.append(nrow)
	var base := _emit_smooth_grid(st, rows, norms, uvs, true, 0)
	var ax_dir := Vector3.RIGHT if axis == "x" else (Vector3.BACK if axis == "z" else Vector3.UP)
	if cap_start and float(profile_cr[0][1]) > 1e-4:
		base = _emit_cap_fan(st, centers[0], rows[0], -ax_dir, base)
	if cap_end and float(profile_cr[r_count - 1][1]) > 1e-4:
		_emit_cap_fan(st, centers[r_count - 1], rows[r_count - 1], ax_dir, base)
	return st.commit()


## Compact double-curved aerodynamic shoulder shell with real rim thickness.
static func pauldron_shell(rx: float, ry: float, rz: float, thickness: float,
		sweep_z := 0.02, rings := 14, sides := 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var out_rows := []
	var in_rows := []
	var uvs := []
	for r in rings + 1:
		var v := float(r) / float(rings)
		var theta := lerpf(0.02, PI * 0.54, v)
		var st_h := sin(theta)
		var ct_h := cos(theta)
		var prow := []
		var urow := []
		for c in sides:
			var u := float(c) / float(sides)
			var phi := TAU * u
			var x := cos(phi) * st_h * rx
			var z := sin(phi) * st_h * rz + pow(st_h, 1.5) * sweep_z
			var y := ct_h * ry - pow(st_h, 2.0) * ry * 0.14
			prow.append(Vector3(x, y, z))
			urow.append(Vector2(u, v))
		out_rows.append(prow)
		uvs.append(urow)
	var out_norms := []
	var in_norms := []
	for r in rings + 1:
		var onrow := []
		var inrow := []
		var irow := []
		var r0 := maxi(r - 1, 0)
		var r1 := mini(r + 1, rings)
		for c in sides:
			var c0 := (c - 1 + sides) % sides
			var c1 := (c + 1) % sides
			var du: Vector3 = out_rows[r][c1] - out_rows[r][c0]
			var dv: Vector3 = out_rows[r1][c] - out_rows[r0][c]
			var n := du.cross(dv)
			var guide: Vector3 = out_rows[r][c] + Vector3(0.0, ry * 0.35, 0.0)
			if n.length_squared() < 1e-12:
				n = Vector3.UP
			n = n.normalized()
			if n.dot(guide) < 0.0:
				n = -n
			onrow.append(n)
			inrow.append(-n)
			irow.append(out_rows[r][c] - n * thickness)
		out_norms.append(onrow)
		in_norms.append(inrow)
		in_rows.append(irow)
	var base := _emit_smooth_grid(st, out_rows, out_norms, uvs, true, 0)
	base = _emit_smooth_grid(st, in_rows, in_norms, uvs, true, base)
	# Cap apex hole (r=0) and stitch outer-to-inner perimeter rim (r=rings)
	base = _emit_cap_fan(st, Vector3(0.0, ry, 0.0), out_rows[0], Vector3.UP, base)
	base = _emit_cap_fan(st, Vector3(0.0, ry - thickness, 0.0), in_rows[0], Vector3.DOWN, base)
	var rim_rows := [[], []]
	var rim_norms := [[], []]
	var rim_uvs := [[], []]
	for c in sides:
		var u := float(c) / float(sides)
		var p_out: Vector3 = out_rows[rings][c]
		var p_in: Vector3 = in_rows[rings][c]
		var p_prev: Vector3 = out_rows[rings - 1][c]
		var rim_n: Vector3 = (p_out - p_prev).normalized()
		rim_rows[0].append(p_out)
		rim_rows[1].append(p_in)
		rim_norms[0].append(rim_n)
		rim_norms[1].append(rim_n)
		rim_uvs[0].append(Vector2(u, 0.0))
		rim_uvs[1].append(Vector2(u, 1.0))
	_emit_smooth_grid(st, rim_rows, rim_norms, rim_uvs, true, base)
	return st.commit()


## Smooth lenticular double-edged plasma blade along +Y.
## UV.y runs guard (0) -> tip (1), and UV.x runs 0..1 symmetrically from -X edge
## through 0.5 center spine to +X edge on BOTH front (+Z) and back (-Z) faces.
static func energy_blade(length: float, width: float, thickness: float,
		taper := 0.78, segments := 28) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ux_pts := [0.0, 0.25, 0.50, 0.75, 1.0]
	var px_pts := [-1.0, -0.52, 0.0, 0.52, 1.0]
	var pz_pts := [0.0, 0.64, 1.0, 0.64, 0.0]
	var base_idx := 0
	for fs in [1.0, -1.0]:
		var face_sign: float = float(fs)
		var rows := []
		var norms := []
		var uvs := []
		for s in segments + 1:
			var t := float(s) / float(segments)
			var env := 0.0
			if t < 0.07:
				env = lerpf(0.72, 1.0, smoothstep(0.0, 0.07, t))
			elif t < taper:
				env = 1.0
			else:
				env = pow(maxf(0.0, 1.0 - (t - taper) / maxf(1.0 - taper, 0.001)), 0.74)
			env = maxf(env, 0.012)
			var wenv := env
			var tenv := minf(1.0, env * 1.25)
			var prow := []
			var nrow := []
			var urow := []
			for k in 5:
				var px: float = float(px_pts[k]) * width * 0.5 * wenv
				var pz: float = float(pz_pts[k]) * thickness * 0.5 * tenv * face_sign
				prow.append(Vector3(px, t * length, pz))
				var nx: float = float(px_pts[k]) * 0.42
				var nz: float = face_sign * 0.90
				nrow.append(Vector3(nx, 0.0, nz).normalized())
				urow.append(Vector2(float(ux_pts[k]), t))
			rows.append(prow)
			norms.append(nrow)
			uvs.append(urow)
		base_idx = _emit_smooth_grid(st, rows, norms, uvs, false, base_idx)
	return st.commit()
