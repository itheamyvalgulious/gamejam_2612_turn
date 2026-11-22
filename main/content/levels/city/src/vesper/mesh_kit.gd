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

# Identical immutable parts share GPU buffers across actors and restarts.
static var _mesh_cache: Dictionary = {}


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
	var cache_key: Array = ["prism",sides,r_bottom,r_top,height,angle_offset,cap_bottom,cap_top]
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
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
	var result := st.commit()
	_mesh_cache[cache_key] = result
	return result


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
	var cache_key: Array = ["beam_x",length,h0,w0,h1,w1,chamfer]
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
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
	var result := st.commit()
	_mesh_cache[cache_key] = result
	return result


## Beveled armor slab lying in XZ, thickness along Y.
static func slab(w: float, d: float, h: float, bevel := 0.018) -> ArrayMesh:
	var cache_key: Array = ["slab",w,d,h,bevel]
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
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
	var result := st.commit()
	_mesh_cache[cache_key] = result
	return result


## Energy blade: faceted double-edged blade along +Y, UV.y = 0 at base, 1 at tip.
## The profile swells slightly past the guard, then tapers to a needle point.
static func blade(length: float, width: float, thickness: float, curve := 0.0, segments := 14) -> ArrayMesh:
	var cache_key: Array = ["blade",length,width,thickness,curve,segments]
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
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
	var result := st.commit()
	_mesh_cache[cache_key] = result
	return result


## Low-poly faceted sphere (fixed lat/long resolution, flat shaded).
static func gem(radius: float, rings := 4, sides := 8) -> ArrayMesh:
	var cache_key: Array = ["gem",radius,rings,sides]
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
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
	var result := st.commit()
	_mesh_cache[cache_key] = result
	return result


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