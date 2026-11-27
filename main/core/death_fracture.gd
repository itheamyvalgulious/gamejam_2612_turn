extends RefCounted
## DeathFracture —— 击杀瞬间的刚体化 + 沿剑迹切割的预处理引擎。
##
## 与逐关的 DeathField（res://core/death_field.gd）配套：
##   * 预处理模板（enemy 首次 spawn / DeathField 预热时构建，
##     按 enemy_id + rig 结构签名缓存）：
##       - 每个"部位"（持有 MeshInstance3D 的关节节点）打包成
##         局部空间三角汤（顶点/法线/UV/材质）+ 整块用的
##         ConvexPolygonShape3D / ArrayMesh —— 全部缓存；
##       - 每部位按 X/Y/Z 三轴各预切 8 个 cell：每个 cell 一份
##         网格数据 + 盒体 AABB，外加按轴半切的两半 sub-chunk；
##         切割面在模板期就烙进网格（暗红切口端盖）。
##     → 击杀帧只做节点实例化，不做几何计算，< 1ms/帧预算。
##   * 切割：剑接触点 ± travel 构成走廊；部位按「离剑迹距离/部位尺度」
##     分档 —— 走廊内细切（cell→两半），近走廊 cell 整块成块，
##     外侧整部位一个刚体。碎块接缝处有可见切口面。
##   * ragdoll：未碎的部位（或主碎片）间按骨架父子关系连 PinJoint3D；
##     武器（weapon_root 分支）脱手成自由刚体。
##   * 冲量：主体沿剑方向微弱推进 + 碎块向外随机 1–4 u/s。
##
## 本文件不引用任何模块 autoload（P/Fx/Snd 在关卡副本里被改名，
## core 脚本拿不到），参数全部走常量。

const DEBRIS_LAYER := 1 << 8
const PUSHER_LAYER := 1 << 9
const WORLD_LAYER := 1
const CELLS := 6                    # 每轴沿最长方向的 cell 数
const FINE_LEVEL2 := 3              # 贴剑迹：每部位最多细切的 cell 数
const FINE_LEVEL1 := 1              # 近剑迹：细切的 cell 数
const NEAR_AXIS_SPREAD := 0.9       # 部位贴剑迹阈值 = 部位包围半径 × 系数
const FAR_AXIS_SPREAD := 2.3        # 中距离阈值
const CAP_INSET := 0.004            # 切口面向碎块内侧收，防相邻 z-fighting

const TRAVEL_PUSH := 0.85           # 整体沿剑方向的微弱速度分量
const CHUNK_SPEED_MIN := 1.4        # 碎块向外随机速度（u/s）
const CHUNK_SPEED_MAX := 3.9
const CHUNK_LIFT := 0.9
const SPIN_MAX := 4.6
const GRAVITY_SCALE := 1.9          # 视觉重力 ≈ 游戏手感（1u ≈ 0.55m）

static var _templates := {}
static var _geo := {}               # sig -> [重几何 parts]：同型敌人共享，跨实例复用
static var _cap_mat: StandardMaterial3D
static var _phys: PhysicsMaterial

## parts[i] 里随实例变化的字段（节点引用/父级/武器/mod 标记）；
## 其余字段（tris/uvs/mats/aabb/whole/axis_*/tri_count）全部在 _geo 中共享。
const _LIGHT_KEYS := ["node", "path", "idx_path", "mod_idx", "meshes", "parent",
	"is_weapon", "mod"]


## ================================================================ 预处理
static var _stat_builds := 0      # 冷构建次数（模板首次生成/路径失效重建）
static var _stat_build_ms := 0.0  # 冷构建累计耗时
static var _stat_binds := 0       # 热绑定次数（共享模板+按路径解析节点）


static func prepare(enemy: Node, rig: Node3D) -> Dictionary:
	var sig := _rig_signature(rig)
	if enemy != null and is_instance_valid(enemy) and enemy.has_meta(&"death_template"):
		var ct: Variant = enemy.get_meta(&"death_template")
		if ct is Dictionary and String((ct as Dictionary).get("sig", "")) == sig and _nodes_valid(ct as Dictionary, rig):
			_stat_binds += 1
			return ct as Dictionary
	var key := "%s|%s" % [String(enemy.get("enemy_id")), sig]
	var t: Dictionary = _templates.get(key, {})
	if not t.is_empty():
		var cloned := _clone_for_bind(t)
		if _bind(cloned, rig):
			cloned["sig"] = sig
			if enemy != null and is_instance_valid(enemy):
				enemy.set_meta(&"death_template", cloned)
			_stat_binds += 1
			return cloned
	var t0 := Time.get_ticks_usec()
	t = _build_template(rig, sig)
	t["key"] = key
	t["sig"] = sig
	t["build_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_templates[key] = t
	var bound := _clone_for_bind(t)
	if enemy != null and is_instance_valid(enemy):
		enemy.set_meta(&"death_template", bound)
	_stat_builds += 1
	_stat_build_ms += float(t["build_ms"])
	return bound


static func _clone_for_bind(t: Dictionary) -> Dictionary:
	var out: Dictionary = t.duplicate(false)
	var src_parts: Array = t.get("parts", [])
	var dst_parts: Array = []
	dst_parts.resize(src_parts.size())
	for i in src_parts.size():
		dst_parts[i] = (src_parts[i] as Dictionary).duplicate(false)
	out["parts"] = dst_parts
	return out


static func _nodes_valid(t: Dictionary, rig: Node3D) -> bool:
	for p: Dictionary in t.get("parts", []):
		var n: Variant = p.get("node")
		if n == null or not is_instance_valid(n):
			return false
		if not (n as Node).is_inside_tree():
			return false
	return is_instance_valid(rig)


static func _idx_path_to(root: Node, target: Node) -> Array[int]:
	var rev: Array[int] = []
	var cur: Node = target
	while cur != null and cur != root:
		rev.append(cur.get_index())
		cur = cur.get_parent()
	if cur != root:
		return []
	rev.reverse()
	return rev


## 模板跨实例共享：部位只存相对路径与 child-index 路径，逐实例重绑节点。
static func _bind(t: Dictionary, rig: Node3D) -> bool:
	for p: Dictionary in t.get("parts", []):
		var node: Node3D = null
		if bool(p.get("mod", false)):
			var f: Variant = rig.get("field")
			if f != null and is_instance_valid(f) and f.get("mods") is Array:
				var idx := int(p.get("mod_idx", -1))
				if idx >= 0 and idx < (f.mods as Array).size():
					var m: Dictionary = f.mods[idx]
					var mi: MeshInstance3D = m.get("node")
					if mi != null and is_instance_valid(mi):
						node = mi
		else:
			var path: NodePath = p.get("path", NodePath(""))
			if path == NodePath("."):
				node = rig
			elif not path.is_empty() and rig.has_node(path):
				node = rig.get_node(path) as Node3D
			else:
				var idx_path: Array = p.get("idx_path", [])
				if not idx_path.is_empty():
					var cur: Node = rig
					for ci in idx_path:
						var ii := int(ci)
						if cur == null or ii < 0 or ii >= cur.get_child_count():
							cur = null
							break
						cur = cur.get_child(ii)
					if cur is Node3D:
						node = cur as Node3D
		if node == null or not is_instance_valid(node):
			return false
		p["node"] = node
	return true


static func _rig_signature(rig: Node3D) -> String:
	if rig == null:
		return "none"
	if rig.get("_skeleton") != null:
		var skel: Skeleton3D = rig.get("_skeleton")
		var names := PackedStringArray()
		for i in skel.get_bone_count():
			names.append(skel.get_bone_name(i))
		return "skel:" + "/".join(names)
	var leaves := PackedStringArray()
	_leaf_sign(rig, leaves, 5)
	return "tree:%d|%s" % [leaves.size(), "/".join(leaves.slice(0, 48))]


static func _leaf_sign(n: Node, out: PackedStringArray, depth: int) -> void:
	var nm := String(n.name)
	# 运行时自动命名（@Node3D@12）跨实例不稳定：以类名代替，保证
	# 同型敌的签名一致、模板缓存共享。
	if nm.contains("@"):
		nm = "class:" + n.get_class()
	out.append(nm)
	if depth <= 0 or out.size() > 96:
		return
	for c in n.get_children():
		if c is Node3D:
			_leaf_sign(c, out, depth - 1)


static func _is_fx(mi: MeshInstance3D, rig: Node3D) -> bool:
	var n := String(mi.name).to_lower()
	for tag in ["trail", "_fx", "shadow", "glow", "orb", "afterimage",
			"streak", "plume", "impact", "charge", "vfx", "lamp", "light"]:
		if n.contains(tag):
			return true
	var special: Variant = rig.get("_charge")
	if special != null and special is MeshInstance3D and special == mi:
		return true
	return false


static func _build_template(rig: Node3D, sig := "") -> Dictionary:
	# ---- 部位收集：直接持有有效 MeshInstance3D 的 Node3D（骨架走 BoneAttachment）----
	var owners := {}
	var stack: Array = [rig]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in (n as Node).get_children():
			if c is Node3D:
				stack.append(c)
		var own: Array = []
		for c in (n as Node).get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null \
					and not _is_fx(c, rig):
				own.append(c)
		if not own.is_empty():
			owners[n] = own
	# 语义肢体合并：如果散碎小件过多（如 wheel_sentry 有 ~60 个装饰/盖板子节点），
	# 将深层小件折叠进深度 ≤ 2 的父级结构节点，将刚体部位数控制在 ~8-14 个。
	if owners.size() > 14:
		var collapsed := {}
		for n in owners:
			var target: Node3D = n
			var cur: Node = n
			var chain: Array = []
			while cur != null and cur != rig:
				chain.push_front(cur)
				cur = cur.get_parent()
			if chain.size() >= 2:
				target = chain[1] as Node3D
			elif chain.size() == 1:
				target = chain[0] as Node3D
			if not collapsed.has(target):
				collapsed[target] = []
			(collapsed[target] as Array).append_array(owners[n])
		owners = collapsed
	# 骨架（duelist）：BoneAttachment3D 的 meshes + 骨骼父子关系
	var bone_parents := {}
	var skel: Skeleton3D = rig.get("_skeleton")
	if skel != null:
		var by_bone := {}
		for attach: BoneAttachment3D in skel.get_children():
			by_bone[String(attach.bone_name)] = attach
			var own: Array = []
			for c in attach.get_children():
				if c is MeshInstance3D and (c as MeshInstance3D).mesh != null \
						and not _is_fx(c, rig):
					own.append(c)
			if not own.is_empty():
				owners[attach] = own
		for i in skel.get_bone_count():
			var attach: Node3D = by_bone.get(String(skel.get_bone_name(i)))
			if attach == null:
				continue
			var pi := skel.get_bone_parent(i)
			bone_parents[attach] = by_bone.get(String(skel.get_bone_name(pi))) \
				if pi >= 0 else null
	var parts: Array = []
	var index_of := {}
	for n in owners:
		index_of[n] = parts.size()
		parts.append({"node": n, "path": rig.get_path_to(n),
			"idx_path": _idx_path_to(rig, n),
			"meshes": owners[n], "parent": -1, "is_weapon": false})
	# rig 根部位：没网格也建，用来收松散网格 + 当总根。
	if not index_of.has(rig):
		index_of[rig] = parts.size()
		parts.append({"node": rig, "path": NodePath("."),
			"idx_path": [],
			"meshes": [], "parent": -1, "is_weapon": false})
	# 部位父级：骨架 → 父骨骼 attachment；普通节点 → 最近的祖先部位。
	for i in parts.size():
		var node: Node3D = parts[i]["node"]
		if node is BoneAttachment3D:
			var p: Node3D = bone_parents.get(node)
			parts[i]["parent"] = index_of.get(p, index_of[rig])
			continue
		var a := (node as Node).get_parent()
		while a != null and a != rig and not index_of.has(a):
			a = a.get_parent()
		parts[i]["parent"] = index_of.get(a, index_of[rig])
	# 武器（刀）：标记为自由刚体，不参与 ragdoll。
	var wroot: Node3D = rig.get("weapon_root")
	var wspin: Node3D = rig.get("weapon_spin")
	for i in parts.size():
		var node: Node3D = parts[i]["node"]
		var anc: Node = node
		while anc != null and anc != rig:
			if anc == wroot or anc == wspin:
				parts[i]["is_weapon"] = true
				break
			anc = anc.get_parent()
		if parts[i]["is_weapon"]:
			parts[i]["parent"] = -1
	# shard_phantom 的 module_field：每个 mod 是 top_level 浮游装甲片，
	# 天生碎片单位 —— 单独成部位，父级挂到它所骑的关节上。
	var field: Variant = rig.get("field")
	if field != null and is_instance_valid(field) and field.get("mods") is Array:
		if index_of.has(field):
			parts[index_of[field]]["meshes"] = []
		var mods: Array = field.mods
		for mi_i in mods.size():
			var m: Dictionary = mods[mi_i]
			var mi: MeshInstance3D = m.get("node")
			if mi == null or not is_instance_valid(mi) or mi.mesh == null:
				continue
			index_of[mi] = parts.size()
			var joint: Node3D = m.get("joint")
			var parent_i: int = index_of.get(joint, index_of[rig])
			# mods 节点是运行时自动命名（@...@），跨实例不稳定：
			# 存 mods 数组下标，bind 时按下标取。
			parts.append({"node": mi, "path": NodePath(""), "idx_path": [], "mod_idx": mi_i,
				"meshes": [mi], "parent": parent_i,
				"is_weapon": false, "mod": true})
	# 重几何（三角汤/cell 网格/凸包）按 rig_signature + 部位序共享：
	# 同型敌人第二只起只做树遍历建轻绑定（node/parent/is_weapon），
	# 不再有 ~140ms 的逐实例 _build_part_data。几何键 = 各部位网格资源 id，
	# 不一致（同 sig 不同网格）会整体重建 geo，保证正确性。
	var geo_parts: Array = _geo.get(sig, []) if sig != "" else []
	var geo_ok := geo_parts.size() == parts.size()
	var rebind := false
	for i in parts.size():
		if not geo_ok:
			break
		if _geo_key(parts[i]) != _geo_key(geo_parts[i]):
			geo_ok = false
		elif geo_parts[i].get("node") != parts[i]["node"]:
			rebind = true   # 同型另一只实例：换轻字段、复用重数据
	var out_parts: Array = []
	if geo_ok:
		for i in parts.size():
			var g: Dictionary = geo_parts[i]
			var lp: Dictionary = g.duplicate(false)
			for k in _LIGHT_KEYS:
				if parts[i].has(k):
					lp[k] = parts[i][k]
			out_parts.append(lp)
	else:
		for p in parts:
			_build_part_data(p)
		if sig != "":
			_geo[sig] = parts
		out_parts = parts
	return {"parts": out_parts, "geo_reused": geo_ok and sig != ""}


## 部位几何键：所属网格的类/面数/包围尺寸拼串（程序化网格每实例独立 RID，按结构几何复用）。
static func _geo_key(p: Dictionary) -> String:
	var ids := PackedStringArray()
	for mi in p.get("meshes", []):
		var m: Mesh = (mi as MeshInstance3D).mesh if is_instance_valid(mi) else null
		if m == null:
			ids.append("0")
		else:
			var sz := m.get_aabb().size
			ids.append("%s:%d:%.2f,%.2f,%.2f" % [
				m.get_class(), m.get_surface_count(), sz.x, sz.y, sz.z])
	var node: Node = p.get("node")
	var nm := String(node.name) if is_instance_valid(node) else "?"
	if nm.contains("@"):
		nm = "class:" + node.get_class()
	return "|".join(ids) + "#" + nm


## ================================================================ 部位数据
static func _build_part_data(p: Dictionary) -> void:
	if bool(p.get("mod", false)):
		var mod_mesh: Mesh = null
		var aabb_m := AABB(Vector3(-0.05, -0.05, -0.05), Vector3(0.1, 0.1, 0.1))
		for mi_m: MeshInstance3D in p["meshes"]:
			if is_instance_valid(mi_m) and mi_m.mesh != null:
				mod_mesh = mi_m.mesh
				aabb_m = mod_mesh.get_aabb()
				break
		p["tris"] = PackedVector3Array()
		p["uvs"] = PackedVector2Array()
		p["mats"] = []
		p["aabb"] = aabb_m
		p["tri_count"] = 1 if mod_mesh != null else 0
		if mod_mesh == null:
			return
		var m_box := BoxShape3D.new()
		m_box.size = aabb_m.size.max(Vector3.ONE * 0.04)
		p["whole"] = {"mesh": mod_mesh, "shape": m_box,
			"shape_pos": aabb_m.get_center(), "mass": _hull_mass(aabb_m)}
		p["axis_order"] = [0, 1, 2]
		p["axis_built"] = []
		p["axis_data"] = [null, null, null]
		return
	var node: Node3D = p["node"]
	var inv: Transform3D = node.global_transform.affine_inverse()
	var n_basis := inv.basis.orthonormalized()
	var tris := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var has_colors := false
	var mats: Array = []
	for mi: MeshInstance3D in p["meshes"]:
		if not is_instance_valid(mi):
			continue
		var to_part: Transform3D = inv * mi.global_transform
		var mi_nb := (n_basis * mi.global_transform.basis).orthonormalized()
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var tnorm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] \
				if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array else PackedVector3Array()
			var tuv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] \
				if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array else PackedVector2Array()
			var tcol: PackedColorArray = arrays[Mesh.ARRAY_COLOR] \
				if arrays[Mesh.ARRAY_COLOR] is PackedColorArray else PackedColorArray()
			var has_surf_col := not tcol.is_empty()
			if has_surf_col:
				has_colors = true
			var idx = arrays[Mesh.ARRAY_INDEX]
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var order := PackedInt32Array()
			if idx is PackedInt32Array and not idx.is_empty():
				order = idx
			else:
				for i in verts.size():
					order.append(i)
			for k in range(0, order.size(), 3):
				var va := to_part * verts[order[k]]
				var vb := to_part * verts[order[k + 1]]
				var vc := to_part * verts[order[k + 2]]
				var fn := (vb - va).cross(vc - va)
				fn = fn.normalized() if fn.length_squared() > 1e-12 else Vector3.UP
				for j in 3:
					var vi := order[k + j]
					tris.append(to_part * verts[vi])
					if vi < tnorm.size():
						var nrm := mi_nb * tnorm[vi]
						norms.append(nrm.normalized() if nrm.length_squared() > 1e-12 else fn)
					else:
						norms.append(fn)
					uvs.append(tuv[vi] if vi < tuv.size() else Vector2.ZERO)
					cols.append(tcol[vi] if has_surf_col and vi < tcol.size() else Color.WHITE)
				mats.append(mat)
	var count := tris.size() / 3
	var aabb := AABB()
	var centers := PackedVector3Array()
	centers.resize(count)
	if count > 0:
		aabb = AABB(tris[0], Vector3.ZERO)
	for i in count:
		var c := (tris[i * 3] + tris[i * 3 + 1] + tris[i * 3 + 2]) / 3.0
		centers[i] = c
		aabb = aabb.expand(c)
	p["tris"] = tris
	p["norms"] = norms
	p["uvs"] = uvs
	p["cols"] = cols if has_colors else PackedColorArray()
	p["mats"] = mats
	p["aabb"] = aabb
	p["tri_count"] = count
	if count == 0:
		return
	# 天生碎片（shard_phantom 的浮游装甲片 mod）不再预切、不重造 ArrayMesh：直接复用原 mesh + BoxShape3D。
	if bool(p.get("mod", false)):
		var mod_mesh: Mesh = null
		for mi_m: MeshInstance3D in p["meshes"]:
			if is_instance_valid(mi_m) and mi_m.mesh != null:
				mod_mesh = mi_m.mesh
				break
		var m_box := BoxShape3D.new()
		m_box.size = aabb.size.max(Vector3.ONE * 0.08)
		p["whole"] = {"mesh": mod_mesh, "shape": m_box,
			"shape_pos": aabb.get_center(), "mass": _hull_mass(aabb)}
		p["axis_order"] = [0, 1, 2]
		p["axis_built"] = []
		p["axis_data"] = [null, null, null]
		return
	# 整块：网格 + 轻量 BoxShape3D 碰撞体（避免生三角形凸包解算开销）。
	var whole_mesh := _mesh_from_soup(tris, norms, uvs, cols if has_colors else PackedColorArray(), mats)
	var box := BoxShape3D.new()
	box.size = aabb.size.max(Vector3.ONE * 0.08)
	p["whole"] = {"mesh": whole_mesh, "shape": box,
		"shape_pos": aabb.get_center(), "mass": _hull_mass(aabb)}
	# 最长轴顺序：只预切前 2 条最长轴，模板构建耗时再降 33%。
	var size := aabb.size
	var order := [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool: return size[a] > size[b])
	var built_axes := [int(order[0]), int(order[1])]
	p["axis_order"] = order
	p["axis_built"] = built_axes
	var axis_data := [null, null, null]
	for axis in built_axes:
		axis_data[axis] = _build_axis_cells(p, centers, axis)
	p["axis_data"] = axis_data


## 单轴 cell 数据：CELLS 格 × {cell, halves[2]}，每份都是可直接
## add_surface_from_arrays 的 {v, n, uv, mats} + 盒体 AABB。
static func _build_axis_cells(p: Dictionary, centers: PackedVector3Array,
		axis: int) -> Dictionary:
	var count: int = p["tri_count"]
	var tris: PackedVector3Array = p["tris"]
	var norms: PackedVector3Array = p.get("norms", PackedVector3Array())
	var uvs: PackedVector2Array = p["uvs"]
	var cols: PackedColorArray = p.get("cols", PackedColorArray())
	var mats: Array = p["mats"]
	var aabb: AABB = p["aabb"]
	var lo := aabb.position[axis]
	var span := maxf(aabb.size[axis], 1e-4)
	var buckets := []
	for i in CELLS:
		buckets.append(PackedInt32Array())
	for i in count:
		var c := clampi(int((centers[i][axis] - lo) / span * CELLS), 0, CELLS - 1)
		buckets[c].append(i)
	var cells := []
	for ci in CELLS:
		var ids: PackedInt32Array = buckets[ci]
		var c_lo := lo + span * float(ci) / CELLS
		var c_hi := lo + span * float(ci + 1) / CELLS
		var cell := {"aabb": AABB(), "mesh": null, "halves": []}
		if not ids.is_empty():
			# cell 网格：仅在内部切面补切口端盖。
			var vd := _soup_of(ids, tris, norms, uvs, cols, mats)
			_add_cap(vd, axis, c_lo + CAP_INSET, c_hi - CAP_INSET, ci > 0, ci < CELLS - 1)
			cell["mesh"] = _mesh_from_vd(vd)
			cell["aabb"] = _vd_aabb(vd)
			# 半切：按轴质心中点分两份，各自带切口盖。
			var mid := (c_lo + c_hi) * 0.5
			var halves := [PackedInt32Array(), PackedInt32Array()]
			for ti in ids:
				halves[0 if centers[ti][axis] <= mid else 1].append(ti)
			for h in 2:
				var hv: PackedInt32Array = halves[h]
				if hv.is_empty():
					continue
				var hvd := _soup_of(hv, tris, norms, uvs, cols, mats)
				var h_lo := c_lo + CAP_INSET if h == 0 else mid + CAP_INSET
				var h_hi := mid - CAP_INSET if h == 0 else c_hi - CAP_INSET
				_add_cap(hvd, axis, h_lo, h_hi, h == 1 or ci > 0, h == 0 or ci < CELLS - 1)
				cell["halves"].append({"mesh": _mesh_from_vd(hvd),
					"aabb": _vd_aabb(hvd)})
		cells.append(cell)
	return {"cells": cells, "lo": lo, "span": span}


static func _soup_of(ids: PackedInt32Array, tris: PackedVector3Array,
		norms: PackedVector3Array, uvs: PackedVector2Array,
		cols: PackedColorArray, mats: Array) -> Dictionary:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var has_col := not cols.is_empty()
	var has_norm := norms.size() == tris.size()
	var m: Array = []
	for ti in ids:
		var fn := Vector3.UP
		if not has_norm:
			var a := tris[ti * 3]
			var b := tris[ti * 3 + 1]
			var c_pt := tris[ti * 3 + 2]
			fn = (b - a).cross(c_pt - a)
			fn = fn.normalized() if fn.length_squared() > 1e-12 else Vector3.UP
		for j in 3:
			var idx := ti * 3 + j
			v.append(tris[idx])
			uv.append(uvs[idx])
			n.append(norms[idx] if has_norm else fn)
			if has_col:
				c.append(cols[idx])
		m.append(mats[ti])
	return {"v": v, "n": n, "uv": uv, "c": c, "mats": m}


## 在 axis 的内部切面（lo/hi 位置）补一对贴合局部截面的切口盖。
static func _add_cap(vd: Dictionary, axis: int, lo: float, hi: float,
		cap_lo := true, cap_hi := true) -> void:
	var v: PackedVector3Array = vd["v"]
	if v.is_empty() or (not cap_lo and not cap_hi):
		return
	var ax1 := (axis + 1) % 3
	var ax2 := (axis + 2) % 3
	var vv: PackedVector3Array = vd["v"]
	var nn: PackedVector3Array = vd["n"]
	var uu: PackedVector2Array = vd["uv"]
	var cc: PackedColorArray = vd.get("c", PackedColorArray())
	var has_col := not cc.is_empty()
	var mm: Array = vd["mats"]
	var slice_tol := maxf((hi - lo) * 0.35, 0.04)
	var cuts: Array = []
	if cap_lo:
		cuts.append([lo, 1.0])
	if cap_hi:
		cuts.append([hi, -1.0])
	for cut in cuts:
		var d: float = float(cut[0])
		var sign_n: float = float(cut[1])
		var min1 := INF
		var max1 := -INF
		var min2 := INF
		var max2 := -INF
		var near := 0
		for p in v:
			if absf(p[axis] - d) <= slice_tol:
				min1 = minf(min1, p[ax1])
				max1 = maxf(max1, p[ax1])
				min2 = minf(min2, p[ax2])
				max2 = maxf(max2, p[ax2])
				near += 1
		if near < 3:
			continue
		var s1_span := max1 - min1
		var s2_span := max2 - min2
		if s1_span < 0.02 or s2_span < 0.02:
			continue
		var inset1 := s1_span * 0.12
		var inset2 := s2_span * 0.12
		var a1 := min1 + inset1
		var b1 := max1 - inset1
		var a2 := min2 + inset2
		var b2 := max2 - inset2
		var n_dir := Vector3.ZERO
		n_dir[axis] = sign_n
		var rect := PackedVector3Array()
		for p1 in [a1, b1]:
			for p2 in [a2, b2]:
				var pt := Vector3.ZERO
				pt[axis] = d
				pt[ax1] = p1
				pt[ax2] = p2
				rect.append(pt)
		var quad := [0, 2, 3, 1] if sign_n > 0.0 else [0, 1, 3, 2]
		for tri in [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]:
			for j in tri:
				vv.append(rect[j])
				nn.append(n_dir)
				uu.append(Vector2(rect[j][ax1], rect[j][ax2]))
				if has_col:
					cc.append(Color.WHITE)
			mm.append(_cap_material())


static func _vd_aabb(vd: Dictionary) -> AABB:
	var v: PackedVector3Array = vd["v"]
	if v.is_empty():
		return AABB()
	var a := AABB(v[0], Vector3.ZERO)
	for p in v:
		a = a.expand(p)
	return a


## 三角汤 → ArrayMesh：按材质分 surface（保留原始法线/顶点色）。
static func _mesh_from_soup(tris: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, cols: PackedColorArray, mats: Array) -> ArrayMesh:
	var vd := {"v": tris, "n": norms, "uv": uvs, "c": cols, "mats": mats}
	return _mesh_from_vd(vd)


static func _mesh_from_vd(vd: Dictionary) -> ArrayMesh:
	var v: PackedVector3Array = vd["v"]
	var n: PackedVector3Array = vd["n"]
	var uv: PackedVector2Array = vd["uv"]
	var col: PackedColorArray = vd.get("c", PackedColorArray())
	var has_col := col.size() == v.size() and not col.is_empty()
	var mats: Array = vd["mats"]
	var count := v.size() / 3
	var by_mat := {}
	for i in count:
		var m: Material = mats[i] if i < mats.size() else null
		var key := m.get_instance_id() if m != null else 0
		if not by_mat.has(key):
			by_mat[key] = {"mat": m, "idx": PackedInt32Array()}
		by_mat[key]["idx"].append(i)
	var mesh := ArrayMesh.new()
	var keys := by_mat.keys()
	keys.sort()
	for key in keys:
		var g: Dictionary = by_mat[key]
		var ids: PackedInt32Array = g["idx"]
		var sv := PackedVector3Array()
		var sn := PackedVector3Array()
		var su := PackedVector2Array()
		var sc := PackedColorArray()
		for ti in ids:
			for j in 3:
				sv.append(v[ti * 3 + j])
				sn.append(n[ti * 3 + j])
				su.append(uv[ti * 3 + j])
				if has_col:
					sc.append(col[ti * 3 + j])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = sv
		arrays[Mesh.ARRAY_NORMAL] = sn
		arrays[Mesh.ARRAY_TEX_UV] = su
		if has_col:
			arrays[Mesh.ARRAY_COLOR] = sc
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var si := mesh.get_surface_count() - 1
		if g["mat"] != null:
			mesh.surface_set_material(si, g["mat"])
	return mesh


static func _hull_mass(aabb: AABB) -> float:
	return clampf(aabb.size.x * aabb.size.y * aabb.size.z * 0.35, 0.05, 14.0)


## ================================================================ 击杀
static func kill(field: Node3D, enemy: Node, rig: Node3D, info: Dictionary) -> Dictionary:
	var t_prep0 := Time.get_ticks_usec()
	var t := prepare(enemy, rig)
	var t_prep := (Time.get_ticks_usec() - t_prep0) / 1000.0
	var parts: Array = t["parts"]
	if parts.is_empty():
		return {"bodies": 0, "chunks": 0, "joints": 0}
	var contact: Vector3 = info.get("contact", rig.global_position)
	var travel: Vector3 = info.get("travel", Vector3.RIGHT)
	if travel.length_squared() < 0.001:
		travel = Vector3.RIGHT
	var axis_dir := travel.normalized()
	var trace_a := contact - axis_dir * 2.4
	var trace_b := contact + axis_dir * 2.4

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bodies := []
	var whole_map := {}                 # part_idx -> 整块/最大碎片 body
	var is_boss := String(enemy.get("enemy_id")) == "phase_boss" \
		or String(enemy.get("kind")) == "boss"
	var chunk_budget := 42 if is_boss else 28
	var chunk_spent := 0
	var out_basis := axis_dir.cross(Vector3.UP)
	if out_basis.length_squared() < 0.001:
		out_basis = axis_dir.cross(Vector3.FORWARD)
	out_basis = out_basis.normalized()

	for i in parts.size():
		var p: Dictionary = parts[i]
		var node: Node3D = p["node"]
		if not is_instance_valid(node) or p["tri_count"] <= 0:
			continue
		var center := node.to_global(p["aabb"].get_center())
		var axis_len := maxf(p["aabb"].size.length() * 0.5, 0.30)
		var d := _seg_dist(center, trace_a, trace_b)
		var level := 0
		if d <= axis_len * NEAR_AXIS_SPREAD:
			level = 2
		elif d <= axis_len * FAR_AXIS_SPREAD:
			level = 1
		var xf: Transform3D = node.global_transform
		var spend := CELLS + FINE_LEVEL2 if level == 2 \
			else (CELLS + FINE_LEVEL1 if level == 1 else 0)
		if level == 0 or chunk_spent + spend > chunk_budget or bool(p["is_weapon"]) or bool(p.get("mod", false)):
			var body: RigidBody3D = field.take_whole(p, xf)
			if body != null:
				bodies.append(body)
				whole_map[i] = body
			continue
		var axis := _best_axis(p, node, axis_dir)
		var bodies_in_part := _spawn_sliced(field, p, xf, axis, level,
			trace_a, trace_b, node)
		bodies.append_array(bodies_in_part)
		chunk_spent += bodies_in_part.size()
		if not bodies_in_part.is_empty():
			var big: RigidBody3D = bodies_in_part[0]
			var best := 0
			for b in bodies_in_part:
				var n := int(b.get_meta(&"tris", 0))
				if n > best:
					best = n
					big = b
			whole_map[i] = big

	# ragdoll 关节：整块（或主碎片）部位沿骨架链连 PinJoint3D。
	var joints := 0
	var joint_list := []
	for i in parts.size():
		var p: Dictionary = parts[i]
		if bool(p.get("mod", false)):
			continue
		var pi: int = p["parent"]
		if pi < 0 or not whole_map.has(i) or not whole_map.has(pi):
			continue
		var a: RigidBody3D = whole_map[pi]
		var b: RigidBody3D = whole_map[i]
		if a == b:
			continue
		var pin := PinJoint3D.new()
		pin.name = "J"
		pin.node_a = a.get_path()
		pin.node_b = b.get_path()
		field.add_child(pin)
		pin.global_position = (p["node"] as Node3D).global_position
		joint_list.append(pin)
		joints += 1

	# 冲量：主体沿剑方向微弱，碎块向外随机飞散。
	for body: RigidBody3D in bodies:
		var d := body.global_position - contact
		var dir := d.normalized() if d.length_squared() > 0.002 else out_basis
		var is_chunk := bool(body.get_meta(&"chunk", false))
		var speed := rng.randf_range(CHUNK_SPEED_MIN, CHUNK_SPEED_MAX) if is_chunk \
			else rng.randf_range(0.4, 1.0)
		var scatter := (dir * rng.randf_range(0.55, 1.0) \
			+ out_basis * rng.randf_range(-0.6, 0.6) \
			+ Vector3.UP * rng.randf_range(0.3, CHUNK_LIFT)).normalized()
		body.linear_velocity = travel * rng.randf_range(0.3, 0.65) + scatter * speed
		body.angular_velocity = Vector3(rng.randf_range(-SPIN_MAX, SPIN_MAX),
			rng.randf_range(-SPIN_MAX, SPIN_MAX), rng.randf_range(-SPIN_MAX, SPIN_MAX))
		if bool(body.get_meta(&"weapon", false)):
			body.linear_velocity += travel * 1.6 + Vector3.UP * 1.8
	return {"bodies": bodies.size(), "chunks": chunk_spent, "joints": joints,
		"list": bodies, "joint_list": joint_list,
		"prep_ms": t_prep,
		"template_ms": float(t.get("build_ms", 0.0)), "key": String(t.get("key", ""))}


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _best_axis(p: Dictionary, node: Node3D, travel: Vector3) -> int:
	var built: Array = p.get("axis_built", p["axis_order"])
	var best := int(built[0])
	var best_dot := -1.0
	for axis in built:
		var dir := Vector3(axis == 0, axis == 1, axis == 2)
		var w := (node.global_basis.orthonormalized() * dir).normalized()
		var d := absf(w.dot(travel))
		if d > best_dot:
			best_dot = d
			best = int(axis)
	return best


## 按 cell 离剑迹的世界距离排序：最近的 N 个细切成两半，其余整 cell。
## 返回生成的 bodies（全部是 _debris 的孩子）。
static func _spawn_sliced(field: Node3D, p: Dictionary, xf: Transform3D,
		axis: int, level: int, trace_a: Vector3, trace_b: Vector3,
		node: Node3D) -> Array:
	var data: Dictionary = (p["axis_data"] as Array)[axis]
	var cells: Array = data["cells"]
	var lo := float(data["lo"])
	var span := float(data["span"])
	var aabb: AABB = p["aabb"]
	var ax1 := (axis + 1) % 3
	var ax2 := (axis + 2) % 3
	var center := aabb.get_center()
	var cell_d := PackedFloat32Array()
	cell_d.resize(CELLS)
	for c in CELLS:
		var pt := center
		pt[axis] = lo + span * (float(c) + 0.5) / CELLS
		cell_d[c] = _seg_dist(node.to_global(pt), trace_a, trace_b)
	var order := []
	for i in CELLS:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return cell_d[a] < cell_d[b])
	var fine := {}
	var fine_n := FINE_LEVEL2 if level == 2 else FINE_LEVEL1
	for i in mini(fine_n, CELLS):
		fine[order[i]] = true
	var out: Array = []
	for c in CELLS:
		var cell: Dictionary = cells[c]
		if cell["mesh"] == null:
			continue
		if fine.has(c):
			for h in cell["halves"]:
				var body: RigidBody3D = field.take_chunk(h["mesh"], h["aabb"], xf)
				if body != null:
					out.append(body)
		else:
			var body: RigidBody3D = field.take_chunk(cell["mesh"], cell["aabb"], xf)
			if body != null:
				out.append(body)
	return out


## ================================================================ 实例化
## 所有刚体都由 DeathField 的池子供给（预热期建好的节点），这里只做
## 排队/距离分类/关节/冲量。
static func _phys_mat() -> PhysicsMaterial:
	if _phys == null:
		_phys = PhysicsMaterial.new()
		_phys.friction = 0.60
		_phys.bounce = 0.16
	return _phys


static func _cap_material() -> StandardMaterial3D:
	if _cap_mat == null:
		_cap_mat = StandardMaterial3D.new()
		_cap_mat.albedo_color = Color("1b1e24")
		_cap_mat.metallic = 0.65
		_cap_mat.roughness = 0.48
		_cap_mat.emission_enabled = false
		_cap_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _cap_mat


static func forget() -> void:
	_templates.clear()


static func stats() -> Dictionary:
	var out := {"templates": _templates.size(), "by_key": {},
		"cold_builds": _stat_builds, "cold_build_ms": _stat_build_ms,
		"hot_binds": _stat_binds}
	for k in _templates:
		var t: Dictionary = _templates[k]
		out["by_key"][k] = {"parts": (t["parts"] as Array).size(),
			"build_ms": float(t.get("build_ms", 0.0))}
	return out
