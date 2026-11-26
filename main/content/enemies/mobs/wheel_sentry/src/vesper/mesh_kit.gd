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


# ------------------------------------------------------------------ merge ---
## 砍 draw call 的锚点式静态合并：
##   - blocked 里的 Node3D = 「锚点」（会被代码驱动的 pivot / 会被单独拆走的
##     装甲板）：把它子树里所有静态 MeshInstance3D 叶子合并到它自己身上。
##   - blocked 里的 MeshInstance3D 或带 no_merge meta 的叶子 = 原样保留。
##   - 不在任何锚点下的叶子合并到 root。
##   - 每组先做「几何指纹相同 → MultiMesh」的 instancing，再按材质拼单 surface。
## 返回合并掉的 MeshInstance 数量。
static func merge_leaf_meshes(root: Node3D, blocked: Array = []) -> int:
	var anchors := {}
	for n in blocked:
		if n == null:
			continue
		if n is MeshInstance3D:
			n.set_meta("no_merge", true)
		elif n is Node3D:
			anchors[n] = true
			n.set_meta("no_merge", true)
	var buckets := {}
	_collect(root, Transform3D.IDENTITY, root, anchors, buckets)
	var saved := 0
	for anchor in buckets:
		saved += _emit_bucket(anchor, buckets[anchor])
	for n in blocked:
		if n != null and is_instance_valid(n) and n.has_meta("no_merge"):
			n.remove_meta("no_merge")
	return saved


## DFS：anchor=当前生效锚点，xf=相对锚点的累计变换。
## 遇到 no_merge 的 Node3D（子锚点）则以其为新锚点重算变换。
## 遇到 no_merge 的叶子或普通叶子则记录/跳过。
static func _collect(node: Node, xf: Transform3D, anchor: Node3D,
		anchors: Dictionary, buckets: Dictionary) -> void:
	for child in node.get_children():
		var is_node3d := child is Node3D
		if child.has_meta("no_merge"):
			if is_node3d and anchors.has(child) and not (child is MeshInstance3D):
				_collect(child, Transform3D.IDENTITY, child, anchors, buckets)
			continue
		if child is MeshInstance3D and child.get_child_count() == 0:
			var bag: Array = buckets.get(anchor, [])
			bag.append({"mi": child, "xf": xf * child.transform})
			buckets[anchor] = bag
		elif is_node3d:
			_collect(child, xf * (child as Node3D).transform, anchor, anchors, buckets)


static func _leaf_key(mi: MeshInstance3D) -> String:
	return "%d|%d|%d|%d" % [mi.cast_shadow, mi.layers,
		1 if mi.visible else 0, mi.gi_mode]


static func _eff_material(mi: MeshInstance3D, s: int) -> Material:
	var m: Material = mi.get_surface_override_material(s)
	if m == null:
		m = mi.material_override
	if m == null:
		m = mi.mesh.surface_get_material(s)
	return m


static func _mesh_mat_sig(mi: MeshInstance3D) -> String:
	var sig := ""
	for s in mi.mesh.get_surface_count():
		sig += _mat_content_sig(_eff_material(mi, s)) + ";"
	return sig


## 材质按内容签名而不是实例 id：builder 里 .duplicate() 出来的同参材质
## 进同一组（否则每组都只有 1 个成员，等于没合）。
static func _mat_content_sig(m: Material) -> String:
	if m == null:
		return "null"
	if m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		return "std|%s|%s|%s|%.2f|%.2f|%d|%d|%.2f|%d|%s" % [
			sm.albedo_color, sm.emission, sm.emission_enabled,
			sm.metallic, sm.roughness, int(sm.transparency),
			int(sm.shading_mode), sm.emission_energy_multiplier,
			int(sm.cull_mode), str(sm.vertex_color_use_as_albedo)]
	if m is ShaderMaterial:
		var sh := m as ShaderMaterial
		return "shd|%s" % (sh.shader.resource_path if sh.shader else "null")
	return str(m)


static func _mesh_fp(mesh: Mesh) -> String:
	var fp := ""
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts = arrays[Mesh.ARRAY_VERTEX]
		var idxs = arrays[Mesh.ARRAY_INDEX]
		var n: int = verts.size() if verts is PackedVector3Array else 0
		var m: int = idxs.size() if idxs is PackedInt32Array else 0
		var bb := ""
		if n > 0:
			var aabb := AABB(verts[0], Vector3.ZERO)
			for v in verts:
				aabb = aabb.expand(v)
			bb = "%v|%v" % [aabb.position, aabb.size]
		fp += "%d|%d|%s;" % [n, m, bb]
	return fp


## 把一个锚点收来的 member 列表（{"mi","xf"}）实例化/合并发射。
static func _emit_bucket(anchor: Node3D, members: Array) -> int:
	var instanced := {}
	# 阶段 A：同几何指纹 → MultiMesh
	var by_mesh := {}
	for e in members:
		var mi: MeshInstance3D = e["mi"]
		var key := "%s|%s|%s" % [_mesh_fp(mi.mesh), _mesh_mat_sig(mi), _leaf_key(mi)]
		var g: Array = by_mesh.get(key, [])
		g.append(e)
		by_mesh[key] = g
	for key in by_mesh:
		var g: Array = by_mesh[key]
		if g.size() < 2:
			continue
		var ref: MeshInstance3D = g[0]["mi"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ref.mesh
		mm.instance_count = g.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Inst%d" % g.size()
		mmi.multimesh = mm
		mmi.cast_shadow = ref.cast_shadow
		mmi.layers = ref.layers
		mmi.visible = ref.visible
		mmi.gi_mode = ref.gi_mode
		anchor.add_child(mmi)
		for i in g.size():
			mm.set_instance_transform(i, g[i]["xf"])
		for e in g:
			instanced[e["mi"]] = true
	# 阶段 B：按材质拼单 surface
	var groups := {}
	for e in members:
		var mi: MeshInstance3D = e["mi"]
		if instanced.has(mi):
			continue
		for s in mi.mesh.get_surface_count():
			var m := _eff_material(mi, s)
			var st := SurfaceTool.new()
			st.create_from(mi.mesh, s)
			var src := st.commit()
			if src == null or src.get_surface_count() == 0:
				continue
			var arrays := src.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var norms = arrays[Mesh.ARRAY_NORMAL]
			var uvs = arrays[Mesh.ARRAY_TEX_UV]
			var cols = arrays[Mesh.ARRAY_COLOR]
			var idxs = arrays[Mesh.ARRAY_INDEX]
			var fmt := "%d%d%d" % [
				1 if norms is PackedVector3Array and norms.size() == verts.size() else 0,
				1 if uvs is PackedVector2Array and uvs.size() == verts.size() else 0,
				1 if cols is PackedColorArray and cols.size() == verts.size() else 0]
			var key := "%s|%s|%s" % [_mat_content_sig(m), _leaf_key(mi), fmt]
			var g: Dictionary = groups.get(key, {"mat": m, "members": [], "flags": mi})
			g["members"].append({"mi": mi, "xf": e["xf"], "verts": verts,
				"norms": norms, "uvs": uvs, "cols": cols, "idxs": idxs})
			groups[key] = g
	var saved := 0
	var to_remove := {}
	# 一个锚点只产出一个 MeshInstance3D：所有材质组作为它的多个
	# surface 共用一个 draw-宿主，draw 数 = 1（每 surface 一个 pass 不变，
	# 但少了一层实例与包围盒管理，也更利于 crowd 后续整锚点收编）。
	var bucket_mmi: MeshInstance3D = null
	for key in groups:
		var g: Dictionary = groups[key]
		var gmem: Array = g["members"]
		var flags: MeshInstance3D = g["flags"]
		var uniq := {}
		for e in gmem:
			uniq[e["mi"]] = true
		if uniq.size() < 2:
			continue
		for mi in uniq:
			to_remove[mi] = true
		var v_out := PackedVector3Array()
		var n_out := PackedVector3Array()
		var t_out := PackedVector2Array()
		var c_out := PackedColorArray()
		var i_out := PackedInt32Array()
		for e in gmem:
			var xf: Transform3D = e["xf"]
			var nm := xf.basis.inverse().transposed()
			var base := v_out.size()
			var verts: PackedVector3Array = e["verts"]
			var norms = e["norms"]
			var uvs = e["uvs"]
			var cols = e["cols"]
			var has_n: bool = norms is PackedVector3Array and norms.size() == verts.size()
			var has_t: bool = uvs is PackedVector2Array and uvs.size() == verts.size()
			var has_c: bool = cols is PackedColorArray and cols.size() == verts.size()
			for i in verts.size():
				v_out.append(xf * verts[i])
				if has_n:
					n_out.append((nm * norms[i]).normalized())
				if has_t:
					t_out.append(uvs[i])
				if has_c:
					c_out.append(cols[i])
			var idxs = e["idxs"]
			if idxs is PackedInt32Array and idxs.size() > 0:
				for ix in idxs:
					i_out.append(base + ix)
			else:
				for i in verts.size():
					i_out.append(base + i)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v_out
		if n_out.size() == v_out.size():
			arrays[Mesh.ARRAY_NORMAL] = n_out
		if t_out.size() == v_out.size():
			arrays[Mesh.ARRAY_TEX_UV] = t_out
		if c_out.size() == v_out.size():
			arrays[Mesh.ARRAY_COLOR] = c_out
		arrays[Mesh.ARRAY_INDEX] = i_out
		if bucket_mmi == null:
			bucket_mmi = MeshInstance3D.new()
			bucket_mmi.name = "Merged"
			bucket_mmi.mesh = ArrayMesh.new()
			bucket_mmi.cast_shadow = flags.cast_shadow
			bucket_mmi.layers = flags.layers
			bucket_mmi.visible = flags.visible
			bucket_mmi.gi_mode = flags.gi_mode
			anchor.add_child(bucket_mmi)
		var surf_idx: int = bucket_mmi.mesh.get_surface_count()
		bucket_mmi.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if g["mat"] != null:
			bucket_mmi.mesh.surface_set_material(surf_idx, g["mat"])
		saved += uniq.size() - 1
	for mi in instanced:
		if is_instance_valid(mi) and mi.get_parent() != null:
			mi.get_parent().remove_child(mi)
			mi.queue_free()
	for mi in to_remove:
		if is_instance_valid(mi) and mi.get_parent() != null:
			mi.get_parent().remove_child(mi)
			mi.queue_free()
	return saved


## 顶点焊接：把空间距离 < eps 的顶点合并。对 ring/sphere/shell 这类
## 「按段数生成、相邻环顶点几乎重合」的网格能砍 30%~60% 顶点。
## 只动几何不动材质/UV 语义。eps 取 AABB 对角线的 1.5e-4，兼顾客差。
static func weld_mesh(mesh: Mesh, eps := 0.0) -> Mesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array) or verts.is_empty():
			out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays)
			if mesh.surface_get_material(s) != null:
				out.surface_set_material(s, mesh.surface_get_material(s))
			continue
		var e2: float = eps if eps > 0.0 else _weld_eps(verts)
		var remap := PackedInt32Array()
		remap.resize(verts.size())
		var seen := {}
		var kept := PackedVector3Array()
		var kept_norms := PackedVector3Array()
		var kept_uvs := PackedVector2Array()
		var kept_cols := PackedColorArray()
		var norms = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var cols = arrays[Mesh.ARRAY_COLOR]
		for i in verts.size():
			var v := verts[i]
			var key := "%d,%d,%d" % [int(v.x / e2), int(v.y / e2), int(v.z / e2)]
			if seen.has(key):
				remap[i] = seen[key]
				continue
			var ni := kept.size()
			seen[key] = ni
			remap[i] = ni
			kept.append(v)
			if norms is PackedVector3Array and norms.size() == verts.size():
				kept_norms.append(norms[i])
			if uvs is PackedVector2Array and uvs.size() == verts.size():
				kept_uvs.append(uvs[i])
			if cols is PackedColorArray and cols.size() == verts.size():
				kept_cols.append(cols[i])
		var idxs = arrays[Mesh.ARRAY_INDEX]
		var new_idx := PackedInt32Array()
		if idxs is PackedInt32Array and idxs.size() > 0:
			for ix in idxs:
				new_idx.append(remap[ix])
		else:
			for i in verts.size():
				new_idx.append(remap[i])
		var a2 := []
		a2.resize(Mesh.ARRAY_MAX)
		a2[Mesh.ARRAY_VERTEX] = kept
		if kept_norms.size() == kept.size():
			a2[Mesh.ARRAY_NORMAL] = kept_norms
		if kept_uvs.size() == kept.size():
			a2[Mesh.ARRAY_TEX_UV] = kept_uvs
		if kept_cols.size() == kept.size():
			a2[Mesh.ARRAY_COLOR] = kept_cols
		a2[Mesh.ARRAY_INDEX] = new_idx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
		if mesh.surface_get_material(s) != null:
			out.surface_set_material(s, mesh.surface_get_material(s))
	return out


static func _weld_eps(verts: PackedVector3Array) -> float:
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	return maxf(0.0002, aabb.size.length() * 1.2e-4)
