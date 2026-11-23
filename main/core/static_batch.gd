extends RefCounted
class_name TurnStaticBatch
## 关卡静态几何运行时合批。
##
## 每关的竞技场由上千个 MeshInstance3D 组成（程序化生成，一个面片一个节点），
## Forward+ 要为每个实例剔除 + 提交一个 draw call，GPU 端实测 1100–2100 次绘制。
## 本类做两档合并，画面零损失（几何、材质、变换原样保留）：
##
##   1) 同 mesh + 同材质实例  →  MultiMeshInstance3D（1 次绘制画 N 份）
##   2) 其余静态面片          →  按「表面材质 + 属性格式」合并成大 ArrayMesh
##
## 只收集 arena 根节点下的静态叶子。以下一律跳过：
##   · 挂脚本的节点（行为节点）、灯光/相机/粒子/Navigation 等非网格
##   · MeshInstance3D 的「组节点」（有非 MeshInstance 子节点 —— rig 关节靠父子变换动）
##   · ImmediateMesh / 带骨骼蒙皮的 mesh、material_overlay、不可见节点
## 名字含 fx/vfx/trail/shadow/mask/mirror/halo 的子树也跳过（特效常变）。
##
## 本项目碰撞判定走 hitgd.gd 解析几何（墙段/掩体圆/胶囊），与视觉网格无关，
## 所以合并视觉网格不会影响判定。可用 --no-batch 关闭。

const IMMUTABLE_FLAGS := Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 \
	| Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3

static var _dbg := {}


static func apply(root: Node3D, verbose := false) -> Dictionary:
	if "--no-batch" in OS.get_cmdline_user_args():
		return {}
	var t0 := Time.get_ticks_usec()
	var list: Array[MeshInstance3D] = []
	_dbg = {}
	_collect(root, list)
	var stats := {"instances": list.size()}
	print("[batch] %s: %d candidates, skipped=%s" % [root.name, list.size(), str(_dbg)])
	if list.size() < 4:
		return stats

	# ---------- pass 1: identical (mesh, material_override) -> MultiMesh
	var by_pair := {}
	for mi in list:
		var ov = mi.material_override
		var key := "%d|%d|%d|%d|%d" % [
			mi.mesh.get_instance_id(),
			ov.get_instance_id() if ov != null else 0,
			mi.cast_shadow, mi.layers, mi.gi_mode]
		if not by_pair.has(key):
			by_pair[key] = []
		by_pair[key].append(mi)

	var used := {}
	var root_inv := root.global_transform.affine_inverse()
	var made_mm := 0
	for key in by_pair:
		var group: Array = by_pair[key]
		if group.size() < 3:
			continue
		var first: MeshInstance3D = group[0]
		if first.mesh == null or first.mesh.get_surface_count() != 1:
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "BatchMM"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.use_custom_data = false
		mm.mesh = first.mesh
		mm.instance_count = group.size()
		mmi.multimesh = mm
		mmi.cast_shadow = first.cast_shadow
		mmi.layers = first.layers
		mmi.gi_mode = first.gi_mode
		mmi.material_override = first.material_override
		mmi.top_level = true
		root.add_child(mmi)
		mmi.global_transform = root.global_transform
		for i in group.size():
			var src: MeshInstance3D = group[i]
			mm.set_instance_transform(i, root_inv * src.global_transform)
			used[src] = true
		made_mm += 1
	stats["multimesh_groups"] = made_mm

	# ---------- pass 2: merge leftovers by (surface material, vertex format)
	var by_mat := {}
	for mi in list:
		if used.has(mi):
			continue
		var mesh: Mesh = mi.mesh
		var n := mesh.get_surface_count()
		for s in n:
			var arrs: Array = []
			if mesh is ArrayMesh:
				if (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				arrs = mesh.surface_get_arrays(s)
			elif mesh is PrimitiveMesh:
				# PrimitiveMesh 没有逐面 API：整转数组（单面）
				if s != 0:
					continue
				arrs = (mesh as PrimitiveMesh).get_mesh_arrays()
			else:
				continue
			if arrs[Mesh.ARRAY_VERTEX] == null or (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
				continue
			var fmt: int = (mesh.surface_get_format(s) if mesh is ArrayMesh else 0) & ~IMMUTABLE_FLAGS
			var mat = mi.material_override
			if mat == null:
				mat = mesh.surface_get_material(s) if mesh is ArrayMesh else (mesh as PrimitiveMesh).material
			var key := "%d|%d|%d|%d" % [
				mat.get_instance_id() if mat != null else 0,
				fmt, mi.cast_shadow, mi.layers]
			if not by_mat.has(key):
				by_mat[key] = {"mat": mat, "mi": mi, "parts": []}
			by_mat[key]["parts"].append({"mi": mi, "s": s})

	var made_merge := 0
	for key in by_mat:
		var g: Dictionary = by_mat[key]
		var parts: Array = g["parts"]
		if parts.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in parts:
			var src_mi: MeshInstance3D = part["mi"]
			var si: int = part["s"]
			var xf := root_inv * src_mi.global_transform
			st.append_from(src_mi.mesh, si, xf)
		var am: ArrayMesh = st.commit()
		if am == null or am.get_surface_count() == 0:
			continue
		var out := MeshInstance3D.new()
		out.name = "BatchMerge"
		out.mesh = am
		out.material_override = g["mat"]
		var ref: MeshInstance3D = g["mi"]
		out.cast_shadow = ref.cast_shadow
		out.layers = ref.layers
		out.gi_mode = ref.gi_mode
		out.top_level = true
		root.add_child(out)
		out.global_transform = root.global_transform
		for part in parts:
			used[part["mi"]] = true
		made_merge += 1
	stats["merged_groups"] = made_merge

	# ---------- pass 3: split giant meshes into spatial chunks so the
	# camera pass and each shadow split can frustum-cull them.
	# The arena art is committed as one or two huge ArrayMeshes (600k+ tris);
	# as a single AABB it can never be culled, so every pass re-rasterizes all
	# of it. Chunking keeps identical geometry/materials but restores culling.
	var split_chunks := 0
	var giant: Array[MeshInstance3D] = []
	_collect_giants(root, giant)
	for gi in giant:
		split_chunks += _split_instance(gi, root)
	stats["split_chunks"] = split_chunks

	# ---------- drop originals
	var removed := 0
	for mi in used.keys():
		if is_instance_valid(mi):
			mi.queue_free()
			removed += 1
	stats["batched_nodes"] = removed
	stats["usec"] = Time.get_ticks_usec() - t0
	if verbose or true:
		print("[batch] %s: %d candidates -> %d multimesh + %d merged groups, %d nodes, %.0fms" % [
			root.name, stats["instances"], made_mm, made_merge, removed,
			stats["usec"] / 1000.0])
	return stats


const SPLIT_MIN_TRIS := 40000
const SPLIT_CELL := 10.0


static func _collect_giants(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			var tris := 0
			if mi.mesh != null:
				for s in mi.mesh.get_surface_count():
					var arrs := mi.mesh.surface_get_arrays(s)
					var idx = arrs[Mesh.ARRAY_INDEX]
					var vcount := (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
					tris += (idx.size() if idx != null and idx.size() > 0 else vcount) / 3
			if tris >= SPLIT_MIN_TRIS and not String(mi.name).begins_with("BatchChunk"):
				out.append(mi)

			continue
		if _skip_subtree(child):
			continue
		_collect_giants(child, out)


static func _split_instance(mi: MeshInstance3D, root: Node3D) -> int:
	var mesh: Mesh = mi.mesh
	var out_chunks := 0
	var root_inv := root.global_transform.affine_inverse()
	var base_xf := root_inv * mi.global_transform
	var parent := mi.get_parent()
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var vcount := verts.size()
		if vcount < 3:
			continue
		var idx = src[Mesh.ARRAY_INDEX]
		var has_idx: bool = idx != null and idx.size() > 0
		var tricount: int = (idx.size() if has_idx else vcount) / 3
		if tricount < SPLIT_MIN_TRIS / 4:
			continue
		# bucket triangles by XZ cell of centroid; key packed into int64 for one sort
		var cell_keys := PackedInt64Array()
		cell_keys.resize(tricount)
		var used_cells := {}
		for t in tricount:
			var a: int; var b: int; var c: int
			if has_idx:
				a = idx[t * 3]; b = idx[t * 3 + 1]; c = idx[t * 3 + 2]
			else:
				a = t * 3; b = t * 3 + 1; c = t * 3 + 2
			var p := (verts[a] + verts[b] + verts[c]) / 3.0
			var ck: int = (int(floor(p.x / SPLIT_CELL)) + 4096) * 8192 + int(floor(p.z / SPLIT_CELL)) + 4096
			cell_keys[t] = (ck << 20) | t
			used_cells[ck] = true
		if used_cells.size() < 2:
			continue
		cell_keys.sort()
		var mat: Material = mi.material_override
		if mat == null:
			mat = mesh.surface_get_material(s)
		var remap := PackedInt32Array()
		remap.resize(vcount)
		remap.fill(-1)
		var prev_order := PackedInt32Array()
		var run_start := 0
		var prev_ck: int = cell_keys[0] >> 20
		for r in tricount + 1:
			var ck: int = -1
			if r < tricount:
				ck = cell_keys[r] >> 20
			if r == tricount or ck != prev_ck:
				var run_len := r - run_start
				if run_len > 0:
					for v in prev_order:
						remap[v] = -1
					var order := PackedInt32Array()
					var new_idx := PackedInt32Array()
					new_idx.resize(run_len * 3)
					for j in run_len:
						var t: int = cell_keys[run_start + j] & 0xFFFFF
						for k in 3:
							var v: int = idx[t * 3 + k] if has_idx else t * 3 + k
							var nv: int = remap[v]
							if nv < 0:
								nv = order.size()
								remap[v] = nv
								order.push_back(v)
							new_idx[j * 3 + k] = nv
					_make_chunk(mi, parent, root, base_xf, src, order, new_idx, vcount, mat)
					out_chunks += 1
					prev_order = order
				run_start = r
				prev_ck = ck
	if out_chunks > 0:
		mi.queue_free()
	return out_chunks


static func _make_chunk(mi: MeshInstance3D, parent: Node, root: Node3D,
		base_xf: Transform3D, src: Array, order: PackedInt32Array,
		new_idx: PackedInt32Array, vcount: int, mat: Material) -> void:
	# rebuild every vertex attribute array with the compaction
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	for ai in Mesh.ARRAY_MAX:
		if ai == Mesh.ARRAY_INDEX:
			continue
		var sarr = src[ai]
		if sarr == null:
			continue
		arrays[ai] = _remap_array(sarr, order, vcount)
	arrays[Mesh.ARRAY_INDEX] = new_idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var nmi := MeshInstance3D.new()
	nmi.name = "BatchChunk"
	nmi.mesh = am
	nmi.material_override = mat
	nmi.cast_shadow = mi.cast_shadow
	nmi.layers = mi.layers
	nmi.gi_mode = mi.gi_mode
	nmi.top_level = true
	parent.add_child(nmi)
	nmi.global_transform = root.global_transform * base_xf


## Copy the elements at indices `order` out of a source array whose element
## count equals `vcount` (or is a multiple of it for packed-stride attributes
## like CUSTOM0 byte data).
static func _remap_array(sarr, order: PackedInt32Array, vcount: int):
	if sarr is PackedVector3Array:
		var out := PackedVector3Array()
		out.resize(order.size())
		for i in order.size(): out[i] = sarr[order[i]]
		return out
	if sarr is PackedVector2Array:
		var out := PackedVector2Array()
		out.resize(order.size())
		for i in order.size(): out[i] = sarr[order[i]]
		return out
	if sarr is PackedColorArray:
		var out := PackedColorArray()
		out.resize(order.size())
		for i in order.size(): out[i] = sarr[order[i]]
		return out
	if sarr is PackedFloat32Array:
		var stride: int = sarr.size() / maxi(1, vcount)
		var out := PackedFloat32Array()
		out.resize(order.size() * stride)
		for i in order.size():
			for k in stride: out[i * stride + k] = sarr[order[i] * stride + k]
		return out
	if sarr is PackedFloat64Array:
		var out := PackedFloat64Array()
		out.resize(order.size())
		for i in order.size(): out[i] = sarr[order[i]]
		return out
	if sarr is PackedInt32Array:
		var stride: int = sarr.size() / maxi(1, vcount)
		var out := PackedInt32Array()
		out.resize(order.size() * stride)
		for i in order.size():
			for k in stride: out[i * stride + k] = sarr[order[i] * stride + k]
		return out
	if sarr is PackedInt64Array:
		var out := PackedInt64Array()
		out.resize(order.size())
		for i in order.size(): out[i] = sarr[order[i]]
		return out
	if sarr is PackedByteArray:
		var stride: int = sarr.size() / maxi(1, vcount)
		var out := PackedByteArray()
		out.resize(order.size() * stride)
		for i in order.size():
			for k in stride: out[i * stride + k] = sarr[order[i] * stride + k]
		return out
	if sarr is PackedVector4Array:
		var out := PackedVector4Array()
		out.resize(order.size())
		for i in order.size(): out[i] = sarr[order[i]]
		return out
	return null


static func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			if _mesh_instance_ok(mi):
				out.append(mi)
			continue
		if _skip_subtree(child):
			continue
		_collect(child, out)


static func _skip_subtree(n: Node) -> bool:
	var why := ""
	if n is Light3D or n is Camera3D or n is GPUParticles3D or n is CPUParticles3D \
			or n is SubViewport or n is NavigationRegion3D:
		why = "type:" + n.get_class()
	elif n.get_script() != null:
		why = "script"
	else:
		var name := String(n.name).to_lower()
		for tag in ["fx", "vfx", "trail", "shadow", "mask", "mirror", "halo",
				"rig", "mech", "weapon", "blade", "anim", "ui", "hud", "beam",
				"muzzle", "warning", "marker", "decal"]:
			if name.find(tag) >= 0:
				why = "name:" + tag
				break
	if why != "":
		_dbg[why] = int(_dbg.get(why, 0)) + 1
		return true
	return false


static func _mesh_instance_ok(mi: MeshInstance3D) -> bool:
	var why := ""
	if not mi.visible or mi.mesh == null:
		why = "mi:invisible_or_null"
	elif mi.mesh is ImmediateMesh:
		why = "mi:immediate"
	elif mi.mesh.get_surface_count() <= 0:
		why = "mi:empty"
	elif not mi.skeleton.is_empty():
		why = "mi:skeleton"
	elif mi.material_overlay != null:
		why = "mi:overlay"
	elif mi.transparency > 0.001:
		why = "mi:transparency"
	else:
		for c in mi.get_children():
			if not (c is MeshInstance3D):
				why = "mi:group_parent"
				break
	if why != "":
		_dbg[why] = int(_dbg.get(why, 0)) + 1
		return false
	return true
