extends RefCounted
## 多圆柱体受击判定件（requirement #2）：不再用一颗大胶囊包住整个角色，
## 而是沿骨架关节把机身拆成多个圆柱/胶囊件，拼起来的并集**完全包含**
## 所有受击网格顶点。
##
## 用法（每个 rig 在 _ready 或首次 hit_parts() 时调用一次）：
##   _body_parts = BodyColliders.build(rig, anchors, {
##       "mesh_filter": func(mi): return not _is_fx(mi),
##       "groups": [...],   # 可选：手动顶点组（模块装甲、旋翼轴等）
##   })
## 之后每帧：
##   var parts: Array = BodyColliders.world_parts(_body_parts)
## parts 里每项 = {"a","b","r","label","side","part_id"}（世界坐标），
## 供 Hit.sweep_blade_parts / sweep_sphere_parts / 弹道与拦截规划使用。
## broadphase = world_parts() 返回字典里的 AABB：先用它做粗筛。
##
## 工作原理：
##  * 顶点在**锚点（关节）局部空间**里拟合胶囊 → 关节怎么摆，胶囊跟着走，
##    对骨骼动画天然成立；不按世界位置重算，零逐帧拟合成本。
##  * 每个锚点簇：PCA 求有向包围盒 → 沿最长轴切成 1..k_max 段，
##    每段一根胶囊。细长件（四肢、臂）自动给 1 根沿骨骼轴的胶囊；
##    宽短件（躯干/头/轮毂）给 2–4 根交叠圆柱。
##  * 半径 = 簇内顶点到轴线的最大径向距离 + margin（默认 3% + 4mm），
##    段端点再向外探 min(r·0.9, len·0.5) → 数学上保证顶点不落在并集外。
##    验证器 main/tools/verify_body_parts.gd 逐顶点检查 0 违约。

const MARGIN_RATIO := 0.03          # 半径安全边：簇尺度的 3%
const MARGIN_ABS := 0.004           # 半径安全边：4 mm 绝对值
const CAP_END_EXTEND := 0.9         # 段端沿轴外探系数（×r，封顶段长一半）
const LIMB_ASPECT := 2.3            # len1/radial ≥ 此值 → 单根骨节胶囊


## spec: {"root","anchors","mesh_filter","groups","margin_ratio","margin_abs","k_max"}
static func build(spec: Dictionary) -> Dictionary:
	var root: Node3D = spec["root"]
	var anchors: Array = spec.get("anchors", [])
	var anchor_set := {}
	for n in anchors:
		if n is Node3D:
			anchor_set[n] = true
	var margin_ratio: float = spec.get("margin_ratio", MARGIN_RATIO)
	var margin_abs: float = spec.get("margin_abs", MARGIN_ABS)
	var k_max: int = spec.get("k_max", 3)
	var b_max: int = spec.get("b_max", 0)          # 0 → automático (k_max); N → tope N piezas/cluster
	var mesh_filter: Callable = spec.get("mesh_filter", Callable())
	# anchor_map: {anchor_node → merged_anchor_node}。小关节（手指/趾甲）并进
	# 父锚点共用一根胶囊，否则每个末节枢轴都要各占一件，数量会爆。
	var anchor_map: Dictionary = spec.get("anchor_map", {})

	# ---------------- 收集：每个锚点一簇局部空间顶点 ----------------
	var clusters := {}     # anchor Node3D -> {"points": PackedVector3Array}
	var inv_xf := {}       # anchor -> inverse global transform（采集时缓存）
	for n in anchors:
		if n is Node3D:
			clusters[n] = {"points": PackedVector3Array()}
			inv_xf[n] = (n as Node3D).global_transform.affine_inverse()
	var stray := PackedVector3Array()   # 不在任何锚点子树下的网格 → 归 root
	var covered: Array = []             # MIs incluidas en el ajuste (el verificador las revisa)
	var skipped: Array = []             # MIs excluidas por el filtro (FX/arma/sombra)
	var root_inv: Transform3D = root.global_transform.affine_inverse()
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = node
			if mesh_filter.is_null() or mesh_filter.call(mi):
				var anchor: Node3D = _nearest_anchor(mi, anchor_set)
				while anchor != null and anchor_map.has(anchor):
					anchor = anchor_map[anchor]
				var inv: Transform3D = inv_xf.get(anchor, root_inv)
				var target: PackedVector3Array = clusters[anchor]["points"] \
					if anchor != null else stray
				_collect_vertices(mi, inv, target)
				if anchor != null:
					clusters[anchor]["points"] = target
				else:
					stray = target
				covered.append(mi)
			else:
				skipped.append(mi)
		for c in node.get_children():
			if c is Node3D:
				stack.append(c)
	# Mallas cubiertas por los grupos manuales (módulos sueltos, etc.): el
	# verificador revisa sus vértices en mundo contra las cápsulas resultantes.
	for mi in spec.get("verify_meshes", []):
		covered.append(mi)

	# 手工顶点组（旋翼/履带/浮动装甲这类网格不直接挂在关节下的部件）。
	# 每项 {"anchor": Node3D, "points": PackedVector3Array}，points 已是锚点局部系。
	for g: Dictionary in spec.get("groups", []):
		var anchor: Node3D = g.get("anchor", root)
		var pts: PackedVector3Array = g.get("points", PackedVector3Array())
		if anchor != null and clusters.has(anchor):
			var cur: PackedVector3Array = clusters[anchor]["points"]
			cur.append_array(pts)
			clusters[anchor]["points"] = cur
		else:
			stray.append_array(pts)
	if not stray.is_empty():
		var cur: PackedVector3Array = clusters.get(root, {}).get("points", PackedVector3Array())
		cur.append_array(stray)
		if not clusters.has(root):
			clusters[root] = {"points": cur}
			inv_xf[root] = root_inv
		else:
			clusters[root]["points"] = cur

	# ---------------- presupuesto de piezas ----------------
	# Cada cluster da ≥1 cápsula; si el total supera `budget`, fusionamos el
	# cluster MÁS PEQUEÑO dentro de su anchor padre (transformando sus puntos
	# al espacio del padre). Correcto porque el subárbol del hijo es rígido
	# respecto al padre: los vértices viven en espacio padre.
	var budget: int = spec.get("budget", 0)
	var merged := {}
	if budget > 0:
		var no_merge := {}
		for n in spec.get("no_merge", []):
			if n is Node3D:
				no_merge[n] = true
		_merge_to_budget(clusters, inv_xf, anchor_set, root, budget, k_max,
			margin_ratio, margin_abs, b_max, merged, no_merge)

	# ---------------- 拟合：每簇 → 1..k_max 根胶囊 ----------------
	var parts: Array = []
	var id := 0
	for anchor in clusters:
		var pts: PackedVector3Array = clusters[anchor]["points"]
		if pts.is_empty():
			continue
		var label := _label_of(anchor)
		var fitted: Array = _fit_capsules(pts, k_max, margin_ratio, margin_abs, b_max)
		for f in fitted:
			f["anchor"] = anchor
			f["label"] = label
			f["part_id"] = id
			f["side"] = _side_of(anchor)
			id += 1
			parts.append(f)

	# 局部空间 broadphase：各簇 AABB 的并（转世界时再逐锚点变换）
	var local_aabbs: Array = []
	for anchor in clusters:
		var pts: PackedVector3Array = clusters[anchor]["points"]
		if pts.is_empty():
			continue
		var bb := AABB(pts[0], Vector3.ZERO)
		for p in pts:
			bb = bb.expand(p)
		local_aabbs.append({"anchor": anchor, "aabb": bb})
	var cluster_sizes := {}
	for anchor in clusters:
		cluster_sizes[String((anchor as Node3D).name)] = clusters[anchor]["points"].size()
	return {"parts": parts, "local_aabbs": local_aabbs, "count": parts.size(),
		"covered": covered, "skipped": skipped, "clusters": cluster_sizes,
		"merged": merged}


## 每帧采样：局部胶囊 → 世界坐标 parts + 世界 broadphase AABB。
static func world_parts(built: Dictionary) -> Dictionary:
	var out: Array = []
	out.resize(built["parts"].size())
	var bb := AABB()
	var have_bb := false
	var i := 0
	for p: Dictionary in built["parts"]:
		var anchor: Node3D = p["anchor"]
		if not is_instance_valid(anchor):
			i += 1
			continue
		var xf: Transform3D = anchor.global_transform
		var scale := maxf(xf.basis.x.length(), maxf(xf.basis.y.length(), xf.basis.z.length()))
		var a: Vector3 = xf * p["a"]
		var b: Vector3 = xf * p["b"]
		var r: float = p["r"] * scale
		var part := {"a": a, "b": b, "r": r,
			"label": p["label"], "side": p["side"], "part_id": p["part_id"]}
		out[i] = part
		# broadphase 直接并胶囊的 AABB（保守上界，无需逐顶点）
		var lo := a.min(b) - Vector3(r, r, r)
		var hi := a.max(b) + Vector3(r, r, r)
		bb = AABB(lo, hi - lo) if not have_bb else bb.merge(AABB(lo, hi - lo))
		have_bb = true
		i += 1
	return {"parts": out, "broadphase": bb}


static func broadphase(built: Dictionary) -> AABB:
	return world_parts(built)["broadphase"]


# ---------------------------------------------------------------- internals

## Repite: cuenta piezas estimadas; si > budget, funde el cluster con menos
## puntos dentro del cluster de su ancestro ancla más cercano.
static func _merge_to_budget(clusters: Dictionary, inv_xf: Dictionary,
		anchor_set: Dictionary, root: Node3D, budget: int, k_max: int,
		margin_ratio: float, margin_abs: float, b_max: int,
		merged: Dictionary, no_merge: Dictionary = {}) -> void:
	for _i in 200:
		var estimate := 0
		for anchor in clusters:
			var pts: PackedVector3Array = clusters[anchor]["points"]
			if pts.size() > 0:
				# el ajuste real: fusionar hasta que el total entre en presupuesto
				estimate += _fit_capsules(pts, k_max, margin_ratio, margin_abs, b_max).size()
		if estimate <= budget:
			return
		# cluster más pequeño con padre-ancla disponible
		var best_child: Node3D = null
		var best_parent: Node3D = null
		var best_size := 1 << 30
		for anchor in clusters:
			var pts: PackedVector3Array = clusters[anchor]["points"]
			if anchor == root or pts.is_empty() or no_merge.has(anchor):
				continue
			var parent := _parent_anchor(anchor, anchor_set)
			if parent != null and clusters.has(parent) and pts.size() < best_size:
				best_child = anchor
				best_parent = parent
				best_size = pts.size()
		if best_child == null:
			return
		# transformar puntos del hijo al espacio del padre y fusionar
		var rel: Transform3D = inv_xf[best_parent] * best_child.global_transform
		var child_pts: PackedVector3Array = clusters[best_child]["points"]
		var parent_pts: PackedVector3Array = clusters[best_parent]["points"]
		for p in child_pts:
			parent_pts.append(rel * p)
		clusters[best_parent]["points"] = parent_pts
		clusters.erase(best_child)
		merged[best_child] = best_parent


static func _parent_anchor(node: Node3D, anchor_set: Dictionary) -> Node3D:
	var n := node.get_parent()
	while n != null:
		if anchor_set.has(n):
			return n
		n = n.get_parent()
	return null


static func _nearest_anchor(mi: Node3D, anchor_set: Dictionary) -> Node3D:
	var n := mi.get_parent()
	while n != null:
		if anchor_set.has(n):
			return n
		n = n.get_parent()
	return null


static func _collect_vertices(mi: MeshInstance3D, inv: Transform3D,
		out: PackedVector3Array) -> void:
	var to_anchor: Transform3D = inv * mi.global_transform
	var faces: PackedVector3Array = mi.mesh.get_faces()
	for v in faces:
		out.append(to_anchor * v)


static func _label_of(anchor: Node3D) -> String:
	var n := String(anchor.name).to_lower()
	if n.contains("head") or n.contains("helmet") or n.contains("skull"):
		return "head"
	if n.contains("jaw"):
		return "jaw"
	if n.contains("neck") or n.contains("cervical"):
		return "neck"
	if n.contains("chest") or n.contains("thorax") or n.contains("torso") or n == "body":
		return "chest"
	if n.contains("pelvis") or n.contains("hip_yaw") or n.contains("lower"):
		return "pelvis"
	if n.contains("spine") or n.contains("lumbar"):
		return "spine"
	if n.contains("shoulder") or n.contains("clavicle") or n == "sh":
		return "upper_arm"
	if n.contains("scapula") or n.contains("pauldron") or n.contains("cap"):
		return "pauldron"
	if n.contains("elbow") or n.contains("twist") or n == "elb":
		return "forearm"
	if n.contains("wrist") or n.contains("hand") or n.contains("palm") or n == "wr":
		return "hand"
	if n.contains("finger") or n.contains("thumb") or n.contains("digit"):
		return "finger"
	if n.contains("tool") or n.contains("cannon") or n.contains("muzzle"):
		return "weapon"
	if n.contains("hip") or n.contains("thigh") or n.contains("femur"):
		return "thigh"
	if n.contains("knee") or n.contains("patella") or n.contains("shin"):
		return "shin"
	if n.contains("ankle") or n.contains("hock"):
		return "foot"
	if n.contains("toe") or n.contains("foot") or n.contains("paw") or n.contains("heel"):
		return "foot"
	if n.contains("leg") or n.contains("root"):
		return "leg"
	if n.contains("tail"):
		return "tail"
	if n.contains("wheel") or n.contains("track") or n.contains("belt"):
		return "wheel"
	if n.contains("turret") or n.contains("optic") or n.contains("eye"):
		return "turret"
	if n.contains("arm") or n.contains("rail") or n.contains("support"):
		return "limb"
	if n.contains("pack") or n.contains("nozzle"):
		return "pack"
	return n


static func _side_of(anchor: Node3D) -> float:
	var n := String(anchor.name)
	if n.ends_with("L") or n.ends_with("_L"):
		return -1.0
	if n.ends_with("R") or n.ends_with("_R"):
		return 1.0
	return 0.0


## PCA → 有向包围盒 → 沿最长轴切 K 段 → 每段一根胶囊（保证顶点全覆盖）。
static func _fit_capsules(pts: PackedVector3Array, k_max: int,
		margin_ratio: float, margin_abs: float, b_max: int = 0) -> Array:
	if pts.is_empty():
		return []
	if pts.size() == 1:
		return [{"a": pts[0], "b": pts[0], "r": margin_abs}]
	# 协方差 → 主轴
	var mean := Vector3.ZERO
	for p in pts:
		mean += p
	mean /= float(pts.size())
	var c00 := 0.0
	var c01 := 0.0
	var c02 := 0.0
	var c11 := 0.0
	var c12 := 0.0
	var c22 := 0.0
	for p in pts:
		var d := p - mean
		c00 += d.x * d.x; c01 += d.x * d.y; c02 += d.x * d.z
		c11 += d.y * d.y; c12 += d.y * d.z; c22 += d.z * d.z
	var axes := _jacobi_axes(c00, c01, c02, c11, c12, c22)
	var e1: Vector3 = axes[0]
	var e2: Vector3 = axes[1]
	var e3: Vector3 = axes[2]
	# 投影范围
	var min1 := INF; var max1 := -INF
	var min2 := INF; var max2 := -INF
	var min3 := INF; var max3 := -INF
	for p in pts:
		var d := p - mean
		var u1 := d.dot(e1); var u2 := d.dot(e2); var u3 := d.dot(e3)
		if u1 < min1: min1 = u1
		if u1 > max1: max1 = u1
		if u2 < min2: min2 = u2
		if u2 > max2: max2 = u2
		if u3 < min3: min3 = u3
		if u3 > max3: max3 = u3
	var len1: float = maxf(max1 - min1, 1e-4)
	var rad2: float = maxf(max2 - min2, 0.0) * 0.5
	var rad3: float = maxf(max3 - min3, 0.0) * 0.5
	var radial := maxf(rad2, rad3)
	var margin: float = maxf(len1 * margin_ratio, margin_abs) + radial * margin_ratio
	# 细长件 → 单胶囊沿主轴；短粗件 → k 段交叠圆柱
	var k := 1
	if len1 < radial * LIMB_ASPECT * 2.0:
		k = clampi(int(ceil(radial * 2.0 / maxf(len1, 1e-4))) + 1, 2, maxi(k_max, 2))
	k = clampi(k, 1, maxi(k_max, 1))
	if b_max > 0:
		k = mini(k, b_max)

	var parts: Array = []
	for s in k:
		var lo := min1 + len1 * float(s) / float(k)
		var hi := min1 + len1 * float(s + 1) / float(k)
		# 收集本段内顶点
		var slab := PackedVector3Array()
		for p in pts:
			var u := (p - mean).dot(e1)
			if u >= lo - 1e-6 and u <= hi + 1e-6:
				slab.append(p)
		if slab.is_empty():
			continue
		# 段内径向包围：轴心取本段顶点在 e2/e3 上的中点
		var c2 := 0.0; var c3 := 0.0
		var smin2 := INF; var smax2 := -INF
		var smin3 := INF; var smax3 := -INF
		for p in slab:
			var d := p - mean
			var u2 := d.dot(e2); var u3 := d.dot(e3)
			if u2 < smin2: smin2 = u2
			if u2 > smax2: smax2 = u2
			if u3 < smin3: smin3 = u3
			if u3 > smax3: smax3 = u3
		c2 = (smin2 + smax2) * 0.5
		c3 = (smin3 + smax3) * 0.5
		var c := mean + e1 * (lo + hi) * 0.5 + e2 * c2 + e3 * c3
		var r := 0.0
		for p in slab:
			var q := p - c
			var d_ax := q.dot(e1)
			var off := (q - e1 * d_ax).length()
			if off > r:
				r = off
		r += margin
		var half_len: float = (hi - lo) * 0.5
		var ext: float = minf(r * CAP_END_EXTEND, half_len + r * 0.25)
		var a := c - e1 * (half_len + ext)
		var b := c + e1 * (half_len + ext)
		parts.append({"a": a, "b": b, "r": r})
	return parts


## Jacobi 求 3×3 对称矩阵特征向量（按特征值降序）。
static func _jacobi_axes(c00: float, c01: float, c02: float,
		c11: float, c12: float, c22: float) -> Array:
	var m := [[c00, c01, c02], [c01, c11, c12], [c02, c12, c22]]
	var v := [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
	for sweep_i in 16:
		var off := absf(m[0][1]) + absf(m[0][2]) + absf(m[1][2])
		if off < 1e-12:
			break
		for p in 3:
			for q in range(p + 1, 3):
				var app: float = m[p][p]; var aqq: float = m[q][q]; var apq: float = m[p][q]
				if absf(apq) < 1e-14:
					continue
				var theta: float = (aqq - app) / (2.0 * apq)
				var t: float = (1.0 if theta >= 0.0 else -1.0) / (absf(theta) + sqrt(theta * theta + 1.0))
				var c: float = 1.0 / sqrt(t * t + 1.0)
				var s: float = t * c
				for k in 3:
					var mkp: float = m[k][p]; var mkq: float = m[k][q]
					m[k][p] = c * mkp - s * mkq
					m[k][q] = s * mkp + c * mkq
				for k in 3:
					var mpk: float = m[p][k]; var mqk: float = m[q][k]
					m[p][k] = c * mpk - s * mqk
					m[q][k] = s * mpk + c * mqk
				for k in 3:
					var vkp: float = v[k][p]; var vkq: float = v[k][q]
					v[k][p] = c * vkp - s * vkq
					v[k][q] = s * vkp + c * vkq
	# 排序：特征值（对角线）降序
	var order: Array = [0, 1, 2]
	for i in 2:
		for j in range(i + 1, 3):
			if m[order[j]][order[j]] > m[order[i]][order[i]]:
				var tmp: int = order[i]
				order[i] = order[j]
				order[j] = tmp
	var out := []
	for i in order:
		var e := Vector3(v[0][i], v[1][i], v[2][i])
		out.append(e.normalized() if e.length_squared() > 1e-12 else Vector3.RIGHT)
	# 保证右手系（第三个轴可能 flipped）
	out[2] = out[0].cross(out[1]).normalized()
	return out


## 手工顶点组：把「枢轴局部框 + 半尺寸」转成 8 角点，供 groups 参数使用。
static func box_corners(center: Vector3, half: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(center + Vector3(half.x * sx, half.y * sy, half.z * sz))
	return out


## 点到一组胶囊并集的最小「超出距离」（≤0 表示已被包含）。
## 验证器和调用方共用同一段距离定义，避免口径漂移。
static func violation(point: Vector3, parts: Array) -> float:
	# Dentro de la unión si ALGUNA cápsula lo contiene → el mínimo, no el máximo.
	var best := INF
	for p: Dictionary in parts:
		var a: Vector3 = p["a"]
		var b: Vector3 = p["b"]
		var ab := b - a
		var t := 0.0
		var len2 := ab.length_squared()
		if len2 > 1e-12:
			t = clampf((point - a).dot(ab) / len2, 0.0, 1.0)
		var d := point.distance_to(a + ab * t) - float(p["r"])
		if d < best:
			best = d
	return best
