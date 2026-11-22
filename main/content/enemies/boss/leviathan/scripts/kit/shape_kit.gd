extends RefCounted
## ShapeKit — extra procedural hard-surface primitives on top of MeshKit.
##
## The base kit builds along fixed axes (+Y / +X / Z). This adds arbitrary-axis
## chamfered beams and lofts, plus a transform-aware stacker so many primitives
## can be merged into one surface per material (keeps draw calls low).
##
## Same art direction: spherical arcs + flat planes, all flat/chamfered.

const TAU := PI * 2.0


# ------------------------------------------------------------------ profiles

## Chamfered rectangle, 8 points CCW in the (side, up) plane. w = full width,
## h = full height, c = chamfer as a fraction of the half extent.
static func octa(w: float, h: float, c := 0.30) -> Array[Vector2]:
	var W := maxf(w, 0.0005) * 0.5
	var H := maxf(h, 0.0005) * 0.5
	c = clampf(c, 0.02, 0.48)
	return [
		Vector2(W * (1.0 - c), H),
		Vector2(W, H * (1.0 - c)),
		Vector2(W, -H * (1.0 - c)),
		Vector2(W * (1.0 - c), -H),
		Vector2(-W * (1.0 - c), -H),
		Vector2(-W, -H * (1.0 - c)),
		Vector2(-W, H * (1.0 - c)),
		Vector2(-W * (1.0 - c), H),
	]


## Oriented basis whose +Y is `dir`, with X as close to `side_hint` as possible.
static func basis_y(dir: Vector3, side_hint := Vector3.RIGHT) -> Basis:
	var y := dir.normalized()
	var x := side_hint - y * side_hint.dot(y)
	if x.length_squared() < 1e-6:
		x = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
		if x.length_squared() < 1e-6:
			x = Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func xf(pos: Vector3, dir: Vector3, side_hint := Vector3.RIGHT) -> Transform3D:
	return Transform3D(basis_y(dir, side_hint), pos)


# -------------------------------------------------------------------- beams

## Chamfered, tapered octagonal beam between two arbitrary points.
## w = lateral width, h = perpendicular height. Bevels both end caps.
static func beam(p0: Vector3, p1: Vector3, w0: float, h0: float, w1: float, h1: float,
		chamfer := 0.30, up_hint := Vector3.UP, bevel := 0.0,
		cap0 := true, cap1 := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d := p1 - p0
	var L := d.length()
	if L < 1e-5:
		return st.commit()
	var dir := d / L
	var up := up_hint
	if absf(up.dot(dir)) > 0.985:
		up = Vector3.FORWARD if absf(Vector3.FORWARD.dot(dir)) < 0.9 else Vector3.RIGHT
	var side := up.cross(dir).normalized()
	var up2 := dir.cross(side).normalized()

	var b := clampf(bevel, 0.0, L * 0.22)
	# (distance along, width scale, height scale)
	var secs := [
		Vector3(0.0, 0.86, 0.86),
		Vector3(b, 1.0, 1.0),
		Vector3(L - b, 1.0, 1.0),
		Vector3(L, 0.86, 0.86),
	]
	if b < 0.0008:
		secs = [Vector3(0.0, 1.0, 1.0), Vector3(L, 1.0, 1.0)]

	var rings: Array = []
	for s in secs:
		var sv: Vector3 = s
		var t: float = sv.x / L
		var w: float = lerpf(w0, w1, t) * sv.y
		var h: float = lerpf(h0, h1, t) * sv.z
		var prof := octa(w, h, chamfer)
		var pts: Array[Vector3] = []
		var base: Vector3 = p0 + dir * sv.x
		for pv in prof:
			pts.append(base + side * pv.x + up2 * pv.y)
		rings.append(pts)

	for r in rings.size() - 1:
		var a_ring: Array[Vector3] = rings[r]
		var b_ring: Array[Vector3] = rings[r + 1]
		for i in 8:
			var j := (i + 1) % 8
			var mid := (a_ring[i] + a_ring[j] + b_ring[j] + b_ring[i]) * 0.25 - (p0 + p1) * 0.5
			var guide := mid - dir * mid.dot(dir)
			if guide.length_squared() < 1e-9:
				guide = side
			_quad(st, a_ring[i], a_ring[j], b_ring[j], b_ring[i], guide.normalized(),
				Vector2(float(i) / 8.0, float(r)), Vector2(float(i + 1) / 8.0, float(r)),
				Vector2(float(i + 1) / 8.0, float(r + 1)), Vector2(float(i) / 8.0, float(r + 1)))

	if cap0:
		var r0: Array[Vector3] = rings[0]
		for i in 8:
			var j := (i + 1) % 8
			_tri(st, p0 + dir * secs[0].x, r0[i], r0[j], -dir,
				Vector2(0.5, 0.5), Vector2(float(i) / 8.0, 0.0), Vector2(float(i + 1) / 8.0, 0.0))
	if cap1:
		var rl: Array[Vector3] = rings[rings.size() - 1]
		var tip: Vector3 = p0 + dir * secs[secs.size() - 1].x
		for i in 8:
			var j := (i + 1) % 8
			_tri(st, tip, rl[i], rl[j], dir,
				Vector2(0.5, 1.0), Vector2(float(i) / 8.0, 1.0), Vector2(float(i + 1) / 8.0, 1.0))
	return st.commit()


## Vertical loft through a list of octagonal sections.
## sections: [{ "y": float, "w": float, "d": float, "c": float (optional) }]
static func loft(sections: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if sections.size() < 2:
		return st.commit()
	var rings: Array = []
	for s in sections:
		var y: float = s["y"]
		var w: float = s["w"]
		var d: float = s["d"]
		var c: float = s.get("c", 0.30)
		var prof := octa(w, d, c)
		var pts: Array[Vector3] = []
		for pv in prof:
			pts.append(Vector3(pv.x, y, pv.y))
		rings.append(pts)
	for r in rings.size() - 1:
		var ra: Array[Vector3] = rings[r]
		var rb: Array[Vector3] = rings[r + 1]
		for i in 8:
			var j := (i + 1) % 8
			var mid := (ra[i] + ra[j] + rb[j] + rb[i]) * 0.25
			var guide := Vector3(mid.x, 0.0, mid.z)
			if guide.length_squared() < 1e-9:
				guide = Vector3.RIGHT
			_quad(st, ra[i], ra[j], rb[j], rb[i], guide.normalized(),
				Vector2(float(i) / 8.0, float(r)), Vector2(float(i + 1) / 8.0, float(r)),
				Vector2(float(i + 1) / 8.0, float(r + 1)), Vector2(float(i) / 8.0, float(r + 1)))
	var first: Array[Vector3] = rings[0]
	var last: Array[Vector3] = rings[rings.size() - 1]
	var y0: float = sections[0]["y"]
	var y1: float = sections[sections.size() - 1]["y"]
	for i in 8:
		var j := (i + 1) % 8
		_tri(st, Vector3(0, y0, 0), first[i], first[j], Vector3.DOWN,
			Vector2(0.5, 0.5), Vector2(0.5 + first[i].x, 0.5 + first[i].z),
			Vector2(0.5 + first[j].x, 0.5 + first[j].z))
		_tri(st, Vector3(0, y1, 0), last[i], last[j], Vector3.UP,
			Vector2(0.5, 0.5), Vector2(0.5 + last[i].x, 0.5 + last[i].z),
			Vector2(0.5 + last[j].x, 0.5 + last[j].z))
	return st.commit()


## Tapered four-sided spike along +Y from the origin (claw / talon / spur).
static func spike(length: float, base_w: float, base_h: float, bend := 0.0,
		sides := 4) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var steps := 4
	for i in steps + 1:
		var t := float(i) / float(steps)
		var w := base_w * pow(1.0 - t, 0.72)
		var h := base_h * pow(1.0 - t, 0.72)
		var y := t * length
		var z := bend * t * t
		var prof := octa(maxf(w, 0.0008), maxf(h, 0.0008), 0.32 if sides == 8 else 0.30)
		var pts: Array[Vector3] = []
		for pv in prof:
			pts.append(Vector3(pv.x, y, pv.y + z))
		rings.append(pts)
	for r in rings.size() - 1:
		var ra: Array[Vector3] = rings[r]
		var rb: Array[Vector3] = rings[r + 1]
		for i in 8:
			var j := (i + 1) % 8
			var mid := (ra[i] + ra[j] + rb[j] + rb[i]) * 0.25
			var guide := Vector3(mid.x, 0.0, mid.z)
			if guide.length_squared() < 1e-9:
				guide = Vector3.RIGHT
			_quad(st, ra[i], ra[j], rb[j], rb[i], guide.normalized(),
				Vector2(float(i) / 8.0, float(r)), Vector2(float(i + 1) / 8.0, float(r)),
				Vector2(float(i + 1) / 8.0, float(r + 1)), Vector2(float(i) / 8.0, float(r + 1)))
	var first: Array[Vector3] = rings[0]
	for i in 8:
		var j := (i + 1) % 8
		_tri(st, Vector3.ZERO, first[i], first[j], Vector3.DOWN,
			Vector2(0.5, 0.5), Vector2(0.5 + first[i].x, 0.5 + first[i].z),
			Vector2(0.5 + first[j].x, 0.5 + first[j].z))
	return st.commit()


# ------------------------------------------------------------------ stacking

## Append `mesh` transformed by `xf` into `st`, preserving normals and UVs.
static func stack(st: SurfaceTool, mesh: Mesh, t: Transform3D) -> void:
	if mesh == null:
		return
	var arr: Array = mesh.surface_get_arrays(0)
	if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
		return
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var nrm_basis := t.basis.inverse().transposed()
	var count := idx.size() if idx.size() > 0 else verts.size()
	for i in count:
		var vi: int = idx[i] if idx.size() > 0 else i
		var n := Vector3.UP
		if vi < norms.size():
			n = (nrm_basis * norms[vi]).normalized()
		var uv := Vector2.ZERO
		if vi < uvs.size():
			uv = uvs[vi]
		st.set_normal(n)
		st.set_uv(uv)
		st.add_vertex(t * verts[vi])


## Build one ArrayMesh per material from a list of {mesh, mat, xf} entries.
## Returns Array of Dictionary {mat, mesh}.
static func bake(parts: Array) -> Array:
	var groups: Dictionary = {}
	for p in parts:
		var mat: Material = p["mat"]
		var key := mat.get_instance_id()
		if not groups.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[key] = {"mat": mat, "st": st}
		var xf: Transform3D = p.get("xf", Transform3D.IDENTITY)
		stack(groups[key]["st"], p["mesh"], xf)
	var out: Array = []
	for k in groups:
		var g: Dictionary = groups[k]
		var mesh := (g["st"] as SurfaceTool).commit()
		if mesh.get_surface_count() > 0:
			out.append({"mat": g["mat"], "mesh": mesh})
	return out


## Merge raw ArrayMeshes (already in local space) into one surface.
static func merge_meshes(meshes: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for m in meshes:
		stack(st, m, Transform3D.IDENTITY)
	return st.commit()


# ------------------------------------------------------------------ helpers

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, guide: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var g := (b - a).cross(c - a)
	if g.length_squared() < 1e-14:
		return
	if g.dot(guide) < 0.0:
		var tmp := b
		b = c
		c = tmp
		var tu := ub
		ub = uc
		uc = tu
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


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		guide: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_tri(st, a, b, c, guide, ua, ub, uc)
	_tri(st, a, c, d, guide, ua, uc, ud)

## Katana plasma envelope along +Y with real sori and a long kissaki.
## UV.x = 0 at the cutting edge, 0.5 at the spine. UV.y = 0 base .. 1 tip.
static func katana_blade(length: float, width: float, thickness: float,
		sori: float, seg := 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := [
		Vector2(1.00, 0.00), Vector2(0.58, 0.64), Vector2(-0.50, 0.80),
		Vector2(-1.00, 0.00), Vector2(-0.50, -0.80), Vector2(0.58, -0.64),
	]
	var rings: Array = []
	var cx: Array[float] = []
	for s in seg + 1:
		var t := float(s) / float(seg)
		# width envelope: narrow habaki, full body, long kissaki
		var w_env := 1.0
		if t < 0.055:
			w_env = lerpf(0.80, 1.0, smoothstep(0.0, 0.055, t))
		if t > 0.865:
			var u := (t - 0.865) / 0.135
			w_env = pow(maxf(0.0, 1.0 - u), 0.62)
		var th_env := lerpf(1.0, 0.36, smoothstep(0.0, 0.94, t))
		if t > 0.94:
			th_env *= pow(maxf(0.0, 1.0 - (t - 0.94) / 0.06), 0.7)
		var centre := -sori * pow(t, 1.28)
		cx.append(centre)
		var pts: Array[Vector3] = []
		for pv in profile:
			pts.append(Vector3(centre + pv.x * width * 0.5 * w_env, t * length,
				pv.y * thickness * 0.5 * maxf(th_env, 0.02)))
		rings.append(pts)
	for s in seg:
		for i in 6:
			var j := (i + 1) % 6
			var a: Vector3 = rings[s][i]
			var b: Vector3 = rings[s][j]
			var c: Vector3 = rings[s + 1][j]
			var d: Vector3 = rings[s + 1][i]
			var mid := (a + b + c + d) * 0.25
			var guide := mid - Vector3((cx[s] + cx[s + 1]) * 0.5, mid.y, 0.0)
			if guide.length_squared() < 1e-10:
				guide = Vector3.UP
			var v0 := float(s) / float(seg)
			var v1 := float(s + 1) / float(seg)
			_quad(st, a, b, c, d, guide.normalized(),
				Vector2(float(i) / 6.0, v0), Vector2(float(i + 1) / 6.0, v0),
				Vector2(float(i + 1) / 6.0, v1), Vector2(float(i) / 6.0, v1))
	# base cap
	var r0: Array[Vector3] = rings[0]
	for i in 6:
		var j := (i + 1) % 6
		_tri(st, Vector3(cx[0], 0, 0), r0[i], r0[j], Vector3.DOWN,
			Vector2(0.5, 0.5), Vector2(float(i) / 6.0, 0.0), Vector2(float(i + 1) / 6.0, 0.0))
	return st.commit()
