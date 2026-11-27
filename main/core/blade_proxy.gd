extends RefCounted
class_name BladeProxy
## 能量刀的「少顶点凸体」碰撞代理。
##
## 刀不再用「一串圆盘（y, r）」近似 —— 圆盘会夸大细刃的覆盖（刃宽方向是
## 椭圆截面，圆盘按最大半径取整），也压不住任何非回转体的形状。这里把刀身
## 网格顶点沿刀轴切成若干段，每段取该段所有切片点的凸包（分段棱柱/凸体），
## 用 GJK 最近距离做全解析命中判定：
##   - sweep（上一帧→这一帧的刚体扫掠，子采样插值）
##   - 剑挡剑（凸体对凸体的最短距离，不再有「半径和」）
##   - 飞行物线段 / 球 / 身体多段胶囊
##   - closest_gap（格挡可达性：刀面到敌刀的真实间隙）
##
## 一个 Piece = 一个凸多面体（本地坐标，刀轴 = +Y）：
##   {v, tris, planes, lo, hi, ax}；tris 的每个顶点都是网格真实点或带边界
##   切片点，保证凸包完整包住源网格，体积只会高估不会漏。
## 尺度与其他命中文件一致：世界单位（1 u = 0.547 m）。

const EPS := 1e-6
const INF_V2 := Vector2(-INF, INF)

# 刀轴（本地空间）。刀的建模约定是 +Y 轴朝刀尖。
const AXIS_Y := 1

var pieces: Array = []           # Array[Dictionary]，见 _make_piece
var span := Vector2.ZERO         # 全部 piece 的 y 范围
var axis := AXIS_Y
var source_points := PackedVector3Array()   # 参与拟合的全部切片点（校验/可视化用）


static func _axis_component(p: Vector3, axis_index: int) -> float:
	return p.y if axis_index == 1 else (p.x if axis_index == 0 else p.z)


func _init(piece_list: Array = [], axis_index := AXIS_Y) -> void:
	axis = axis_index
	for piece in piece_list:
		pieces.append(piece)
	_recompute_span()


func _recompute_span() -> void:
	if pieces.is_empty():
		span = Vector2.ZERO
		return
	var lo := INF
	var hi := -INF
	for piece in pieces:
		var ab: AABB = piece["aabb"]
		lo = minf(lo, _axis_component(ab.position, axis))
		hi = maxf(hi, _axis_component(ab.position + ab.size, axis))
	span = Vector2(lo, hi)


# ============================================================== 构造（棱柱）


## 规则 N 边形环（XZ 平面，半径 radius），用于圆柱/棱柱类刀身。
static func regular_ring(n: int, radius: float, phase := 0.0) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for i in n:
		var ang := phase + TAU * float(i) / float(n)
		ring.append(Vector2(cos(ang), sin(ang)) * radius)
	return ring


## 单一棱柱 piece：2D 凸多边形 ring（XZ）在轴区间 [a0, a1] 上拉伸出体。
static func prism(ring: PackedVector2Array, a0: float, a1: float, axis_index := AXIS_Y) -> Dictionary:
	var verts := PackedVector3Array()
	for pt in ring:
		verts.append(_lift(pt, a0, axis_index))
	for pt in ring:
		verts.append(_lift(pt, a1, axis_index))
	var tris := PackedInt32Array()
	var edges := PackedInt32Array()
	var n := ring.size()
	# 侧壁：quad (i, n+i, n+j, j)，两个三角
	for i in n:
		var j := (i + 1) % n
		tris.append_array([i, n + j, n + i])
		tris.append_array([i, j, n + j])
		edges.append_array([i, j])
		edges.append_array([n + i, n + j])
		edges.append_array([i, n + i])
	# 端盖扇形
	for i in range(1, n - 1):
		tris.append_array([0, i + 1, i])
		tris.append_array([n, n + i, n + i + 1])
		edges.append_array([0, i])
		edges.append_array([0, i + 1])
		edges.append_array([n, n + i])
		edges.append_array([n, n + i + 1])
	return _make_piece(verts, tris, edges)


## 两段环之间的直纹凸体（允许两环缩放/平移不同），面自动封口。
## r0/r1 顶点数必须一致且一一对应（同一参数化）。
static func loft(r0: PackedVector2Array, r1: PackedVector2Array, a0: float, a1: float,
		axis_index := AXIS_Y, off0 := Vector2.ZERO, off1 := Vector2.ZERO) -> Dictionary:
	var verts := PackedVector3Array()
	for pt in r0:
		verts.append(_lift(pt + off0, a0, axis_index))
	for pt in r1:
		verts.append(_lift(pt + off1, a1, axis_index))
	var n := r0.size()
	var tris := PackedInt32Array()
	var edges := PackedInt32Array()
	for i in n:
		var j := (i + 1) % n
		tris.append_array([i, n + j, n + i])
		tris.append_array([i, j, n + j])
		edges.append_array([i, j])
		edges.append_array([n + i, n + j])
		edges.append_array([i, n + i])
	for i in range(1, n - 1):
		tris.append_array([0, i + 1, i])
		tris.append_array([n, n + i, n + i + 1])
		edges.append_array([0, i])
		edges.append_array([0, i + 1])
		edges.append_array([n, n + i])
		edges.append_array([n, n + i + 1])
	return _make_piece(verts, tris, edges)


## 便捷：单个棱柱 proxy。
static func from_prism(ring: PackedVector2Array, a0: float, a1: float, axis_index := AXIS_Y) -> BladeProxy:
	return BladeProxy.new([prism(ring, a0, a1, axis_index)], axis_index)


## 便捷：两段环 loft proxy。
static func from_loft(r0: PackedVector2Array, r1: PackedVector2Array, a0: float, a1: float,
		axis_index := AXIS_Y, off0 := Vector2.ZERO, off1 := Vector2.ZERO) -> BladeProxy:
	return BladeProxy.new([loft(r0, r1, a0, a1, axis_index, off0, off1)], axis_index)


# ============================================================== 构造（拟合）


## 从真实刀网格点集拟合「尽量少顶点」的凸体组（单一点集版：沿主轴分段）。
## 每个 Piece = 该轴段内切片点的 2D 凸包沿轴拉出的棱柱。
## 更常用的是 fit_groups()（每网格一份）：单个点集把不相连的柄件一起 hull
## 会严重高估体积。
static func fit(points: PackedVector3Array, tris := PackedInt32Array(), segments := 4,
		axis_index := AXIS_Y, margin := 0.0) -> BladeProxy:
	return _fit_groups([{"points": points, "tris": tris}], segments, axis_index, margin)


## 每 MeshInstance 一组（自己的三角索引），分别拟合再合并 pieces。
## 跨越不同网格的 hull 会把间隙体积算进来 —— 分组后体积累计 ≈ 并集体积。
## 每组按自己的最长轴方向切段（横护手沿 X 摆的件不会被强行按 Y 劈成厚片）。
static func _fit_groups(groups: Array, segments: int, axis_index: int, margin: float) -> BladeProxy:
	var proxy := BladeProxy.new([], axis_index)
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var points: PackedVector3Array = g["points"]
		var tris: PackedInt32Array = g["tris"]
		proxy.source_points.append_array(points)
		var ext := Vector3.ZERO
		if points.size() > 0:
			var lo := points[0]
			var hi := points[0]
			for p in points:
				lo = lo.min(p)
				hi = hi.max(p)
			ext = hi - lo
		# 小段/小零件不切：每 ~0.10u 轴向长度一段；小件自然得到 1–2 段，
		# 弯曲长刀可吃到调用方给的大 segments 上限（弧长切片逼近曲面）。
		var fit_axis := _longest_axis(ext)
		var extent := _vec_axis(ext, fit_axis)
		var seg_i := clampi(ceili(extent / 0.10), 1, segments)
		var sub := _fit_one(points, tris, seg_i, fit_axis, margin)
		for piece in sub.pieces:
			piece["g"] = gi
			proxy.pieces.append(piece)
	proxy._recompute_span()
	return proxy


static func _vec_axis(v: Vector3, axis_index: int) -> float:
	if axis_index == 0:
		return v.x
	if axis_index == 2:
		return v.z
	return v.y


static func _longest_axis(ext: Vector3) -> int:
	if ext.x >= ext.y and ext.x >= ext.z:
		return 0
	if ext.z >= ext.y and ext.z >= ext.x:
		return 2
	return AXIS_Y


static func _fit_one(points: PackedVector3Array, tris: PackedInt32Array,
		segments: int, axis_index: int, margin: float) -> BladeProxy:
	var proxy := BladeProxy.new([], axis_index)
	if points.is_empty():
		return proxy
	var lo := INF
	var hi := -INF
	for p in points:
		var c := _axis_component(p, axis_index)
		lo = minf(lo, c)
		hi = maxf(hi, c)
	if hi - lo < EPS:
		var ring := PackedVector2Array([Vector2(-0.01, -0.01), Vector2(0.01, -0.01),
			Vector2(0.01, 0.01), Vector2(-0.01, 0.01)])
		proxy.pieces.append(prism(ring, lo - 0.01, hi + 0.01, axis_index))
		proxy._recompute_span()
		return proxy
	segments = clampi(segments, 1, 48)
	var bounds := PackedFloat32Array()
	bounds.resize(segments + 1)
	for i in segments + 1:
		bounds[i] = lerpf(lo, hi, float(i) / float(segments))
	var seg_pts: Array = []
	for i in segments:
		seg_pts.append(PackedVector3Array())
	for p in points:
		var idx := clampi(int((_axis_component(p, axis_index) - lo) / (hi - lo) * segments),
			0, segments - 1)
		seg_pts[idx].append(p)
	for t in range(0, tris.size(), 3):
		var va: Vector3 = points[tris[t]]
		var vb: Vector3 = points[tris[t + 1]]
		var vc: Vector3 = points[tris[t + 2]]
		for s in range(1, segments):
			var plane_c: float = bounds[s]
			var pa := _axis_component(va, axis_index)
			var pb := _axis_component(vb, axis_index)
			var pc := _axis_component(vc, axis_index)
			for e in [[va, pa, vb, pb], [vb, pb, vc, pc], [vc, pc, va, pa]]:
				var a: Vector3 = e[0]
				var a_c: float = e[1]
				var b: Vector3 = e[2]
				var b_c: float = e[3]
				# 半开区间判交：端点恰好在界面上也计入（u=0/1），否则
				# 「顶点环正好躺在分段边界上」会让相邻段都丢掉该轮廓。
				if (a_c < plane_c) != (b_c < plane_c):
					var u := clampf((plane_c - a_c) / (b_c - a_c), 0.0, 1.0)
					var cross_pt: Vector3 = a.lerp(b, u)
					seg_pts[s - 1].append(cross_pt)
					seg_pts[s].append(cross_pt)
	for i in segments:
		var pts: PackedVector3Array = seg_pts[i]
		if pts.is_empty():
			continue
		# 首选：该段点集的精确 3D 凸包（贴合锥度/弯面，体积累余最小）。
		# create_convex_shape(clean=true) 返回源点精确凸包顶点，理论上 0 富余
		# 地包含段内全部点，故 pad 直接用调用方 margin（默认 0）。
		var hpiece := hull3d_piece(pts, margin)
		if not hpiece.is_empty():
			proxy.pieces.append(hpiece)
			continue
		var ring := _hull2d_axis(pts, axis_index)
		if ring.size() < 3:
			var blo := Vector3(INF, INF, INF)
			var bhi := Vector3(-INF, -INF, -INF)
			for p in pts:
				blo = blo.min(p)
				bhi = bhi.max(p)
			var c := (blo + bhi) * 0.5
			var e := (bhi - blo) * 0.5 + Vector3.ONE * 0.004
			var b_ring := _box_ring_axis(c, e, axis_index)
			proxy.pieces.append(prism(b_ring,
				_axis_component(blo, axis_index) - 0.004,
				_axis_component(bhi, axis_index) + 0.004, axis_index))
			continue
		var slo := INF
		var shi := -INF
		for p in pts:
			var c := _axis_component(p, axis_index)
			slo = minf(slo, c)
			shi = maxf(shi, c)
		slo = maxf(slo - margin, lo)
		shi = minf(shi + margin, hi)
		if shi - slo < 0.004:
			var mid := (slo + shi) * 0.5
			slo = mid - 0.002
			shi = mid + 0.002
		proxy.pieces.append(prism(ring, slo, shi, axis_index))
	proxy._recompute_span()
	return proxy


## 任意朝向的部件也照主轴切：选「切片截面最扁」的轴当轴 ——
## 先按三轴截面圆的面积比估，挑最小的方向为主轴（细长件的轴）。
static func _box_ring_axis(c: Vector3, e: Vector3, axis_index: int) -> PackedVector2Array:
	if axis_index == 0:
		return PackedVector2Array([Vector2(c.y - e.y, c.z - e.z),
			Vector2(c.y + e.y, c.z - e.z), Vector2(c.y + e.y, c.z + e.z),
			Vector2(c.y - e.y, c.z + e.z)])
	if axis_index == 2:
		return PackedVector2Array([Vector2(c.x - e.x, c.y - e.y),
			Vector2(c.x + e.x, c.y - e.y), Vector2(c.x + e.x, c.y + e.y),
			Vector2(c.x - e.x, c.y + e.y)])
	return PackedVector2Array([Vector2(c.x - e.x, c.z - e.z),
		Vector2(c.x + e.x, c.z - e.z), Vector2(c.x + e.x, c.z + e.z),
		Vector2(c.x - e.x, c.z + e.z)])


## 按「网格分组」拟合：groups = [{points, tris}]，每个网格组先沿其最佳
## 切片轴（默认 +Y；细长横置件自动改用覆盖轴）分成 segments 段，
## 每段棱柱化。所有 piece 合并成一个 proxy。
static func fit_groups(groups: Array, segments := 4, axis_index := AXIS_Y,
		margin := 0.0) -> BladeProxy:
	return _fit_groups(groups, segments, axis_index, margin)


## 精确 3D 凸包 piece：借引擎 quickhull（ArrayMesh.create_convex_shape）
## 取点集凸包顶点，再枚举支撑平面把面重建出来（共面点合并成扇形三角）。
## 对弯曲/锥形刀段比「2D 环沿轴拉伸的棱柱」紧致得多——棱柱截面是并集
## 包络，3D 凸包能表达锥度和斜切面。
## 返回 {}：点数不足或体积≈0（退化），调用方回退棱柱路径。
static func hull3d_piece(points: PackedVector3Array, pad := 0.0) -> Dictionary:
	if points.size() < 4:
		return {}
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var shape := mesh.create_convex_shape(true, false)
	if shape == null or shape.points.size() < 4:
		return {}
	var hv: PackedVector3Array = shape.points
	var n := hv.size()
	var centroid := Vector3.ZERO
	for p in hv:
		centroid += p
	centroid /= float(n)
	var tris := PackedInt32Array()
	var seen := {}
	const TOL := 1e-5
	for i in n - 2:
		for j in range(i + 1, n - 1):
			for k in range(j + 1, n):
				var fn := (hv[j] - hv[i]).cross(hv[k] - hv[i])
				var fl := fn.length()
				if fl < 1e-10:
					continue
				fn /= fl
				var d0 := fn.dot(hv[i])
				var pmin := INF
				var pmax := -INF
				for p in hv:
					var pr := fn.dot(p)
					pmin = minf(pmin, pr)
					pmax = maxf(pmax, pr)
				if not (pmin >= d0 - TOL or pmax <= d0 + TOL):
					continue    # 平面两侧都有点 → 不是支撑面
				var out_n := fn if pmax <= d0 + TOL else -fn
				var fid: Array[int] = []
				for t in n:
					if absf(fn.dot(hv[t]) - d0) <= TOL * 4.0:
						fid.append(t)
				fid.sort()
				var key := ""
				for t in fid:
					key += str(t) + ","
				if seen.has(key):
					continue
				seen[key] = true
				# 共面点绕面质心按角度排序 → 凸多边形扇形三角化
				var fc := Vector3.ZERO
				for t in fid:
					fc += hv[t]
				fc /= fid.size()
				var u := (hv[fid[1]] - fc)
				u = (u - out_n * u.dot(out_n)).normalized()
				var w := out_n.cross(u)
				var order := fid.duplicate()
				order.sort_custom(func(a: int, b: int) -> bool:
					var pa := hv[a] - fc
					var pb := hv[b] - fc
					return atan2(pa.dot(w), pa.dot(u)) < atan2(pb.dot(w), pb.dot(u)))
				for t in range(1, order.size() - 1):
					tris.append_array([order[0], order[t], order[t + 1]])
	if tris.size() < 12:
		return {}
	var piece := _make_piece(hv, tris, PackedInt32Array(), pad)
	if piece_volume(piece) < 1e-9:
		return {}
	# clean=true 的 quickhull 偶会丢「差一点就是顶点」的源点，留下的面
	# 可能比真凸包缩进亚毫米 —— 逐面向外推到包住全部源点为止。
	# 只推违例面（绝大多数面 violation≤0 不动），富余近似 0。
	var planes: Array = piece["planes"]
	for i in planes.size():
		var pl: Plane = planes[i]
		var viol := 0.0
		for p in points:
			viol = maxf(viol, pl.distance_to(p))
		if viol > 0.0:
			planes[i] = Plane(pl.normal, pl.d + viol + 5e-5)
	return piece


static func _lift(pt: Vector2, a: float, axis_index: int) -> Vector3:
	if axis_index == 0:
		return Vector3(a, pt.x, pt.y)
	if axis_index == 2:
		return Vector3(pt.x, pt.y, a)
	return Vector3(pt.x, a, pt.y)


static func _project(p: Vector3, axis_index: int) -> Vector2:
	if axis_index == 0:
		return Vector2(p.y, p.z)
	if axis_index == 2:
		return Vector2(p.x, p.y)
	return Vector2(p.x, p.z)


## 点集在垂直于轴的平面上的 2D 凸包（Andrew monotone chain，逆时针）。
static func _hull2d_axis(pts: PackedVector3Array, axis_index: int) -> PackedVector2Array:
	var flat_arr: Array[Vector2] = []
	for p in pts:
		flat_arr.append(_project(p, axis_index))
	flat_arr.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x or (is_equal_approx(a.x, b.x) and a.y < b.y))
	var flat := PackedVector2Array()
	for pt in flat_arr:
		flat.append(pt)
	var dedup := PackedVector2Array()
	for pt in flat:
		if dedup.is_empty() or pt.distance_squared_to(dedup[dedup.size() - 1]) > 1e-12:
			dedup.append(pt)
	if dedup.size() < 3:
		return dedup
	var lower: Array[Vector2] = []
	for pt in dedup:
		while lower.size() >= 2 and _cross2(lower[lower.size() - 2], lower[lower.size() - 1], pt) <= 1e-10:
			lower.pop_back()
		lower.append(pt)
	var upper: Array[Vector2] = []
	for idx in range(dedup.size() - 1, -1, -1):
		var pt := dedup[idx]
		while upper.size() >= 2 and _cross2(upper[upper.size() - 2], upper[upper.size() - 1], pt) <= 1e-10:
			upper.pop_back()
		upper.append(pt)
	lower.pop_back()
	upper.pop_back()
	var ring := PackedVector2Array()
	for pt in lower:
		ring.append(pt)
	for pt in upper:
		ring.append(pt)
	return ring


static func _cross2(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


## 构造一个 piece：去重点、求包围盒、从三角面推平面（朝外）与边集。
static func _make_piece(verts: PackedVector3Array,
		tris := PackedInt32Array(), edges := PackedInt32Array(), pad := 0.0) -> Dictionary:
	var v := PackedVector3Array()
	var remap := {}
	for p in verts:
		var key := Vector3i(int(round(p.x * 4096.0)), int(round(p.y * 4096.0)), int(round(p.z * 4096.0)))
		if remap.has(key):
			continue
		remap[key] = v.size()
		v.append(p)
	# 顶点 remap 后重建索引
	var key_of := {}
	for i in verts.size():
		var key := Vector3i(int(round(verts[i].x * 4096.0)), int(round(verts[i].y * 4096.0)),
			int(round(verts[i].z * 4096.0)))
		key_of[i] = remap[key]
	var t2 := PackedInt32Array()
	for i in range(0, tris.size(), 3):
		var a: int = key_of[tris[i]]
		var b: int = key_of[tris[i + 1]]
		var c: int = key_of[tris[i + 2]]
		if a == b or b == c or a == c:
			continue
		t2.append_array([a, b, c])
	var e2 := PackedInt32Array()
	var edge_set := {}
	for i in range(0, edges.size(), 2):
		var a: int = key_of[edges[i]]
		var b: int = key_of[edges[i + 1]]
		if a == b:
			continue
		var k := mini(a, b) * 4096 + maxi(a, b)
		if edge_set.has(k):
			continue
		edge_set[k] = true
		e2.append_array([a, b])
	# 调用方没给边表时，从三角形补齐（VHACD 等只给面不给边的路径）
	for i in range(0, t2.size(), 3):
		for e in [[t2[i], t2[i + 1]], [t2[i + 1], t2[i + 2]], [t2[i + 2], t2[i]]]:
			var a: int = e[0]
			var b: int = e[1]
			var k := mini(a, b) * 4096 + maxi(a, b)
			if edge_set.has(k):
				continue
			edge_set[k] = true
			e2.append_array([a, b])
	# 包围盒与面平面
	var lo := v[0]
	var hi := v[0]
	for p in v:
		lo = lo.min(p)
		hi = hi.max(p)
	var centroid := Vector3.ZERO
	for p in v:
		centroid += p
	centroid /= float(v.size())
	var planes: Array[Plane] = []
	var plane_keys := {}
	for i in range(0, t2.size(), 3):
		var a: Vector3 = v[t2[i]]
		var b: Vector3 = v[t2[i + 1]]
		var c: Vector3 = v[t2[i + 2]]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			continue
		n = n.normalized()
		var d := n.dot(a)
		if n.dot(centroid) > d:
			n = -n
			d = -d
		d += pad      # 外扩：project_hull_vertices 裁剪后仍保证包含源网格
		var qk := Vector4i(int(round(n.x * 512.0)), int(round(n.y * 512.0)),
			int(round(n.z * 512.0)), int(round(d * 512.0)))
		if plane_keys.has(qk):
			continue
		plane_keys[qk] = true
		planes.append(Plane(n, d))
	return {"v": v, "tris": t2, "edges": e2, "planes": planes,
		"aabb": AABB(lo, hi - lo), "centroid": centroid}


## 体积（符号四面体法和）。piece 闭合时精确。
static func piece_volume(piece: Dictionary) -> float:
	var v: PackedVector3Array = piece["v"]
	var tris: PackedInt32Array = piece["tris"]
	var vol := 0.0
	for i in range(0, tris.size(), 3):
		var a: Vector3 = v[tris[i]]
		var b: Vector3 = v[tris[i + 1]]
		var c: Vector3 = v[tris[i + 2]]
		vol += a.dot(b.cross(c)) / 6.0
	return absf(vol)


func volume() -> float:
	var total := 0.0
	for piece in pieces:
		total += piece_volume(piece)
	return total


func total_vertices() -> int:
	var n := 0
	for piece in pieces:
		n += (piece["v"] as PackedVector3Array).size()
	return n


## 点在 piece 内（含边界，带微小容差）
static func contains_point(piece: Dictionary, p: Vector3) -> bool:
	for plane: Plane in piece["planes"]:
		if plane.distance_to(p) > 1e-5:
			return false
	return true


## piece 内部深度（不在内部返回 0）
static func _inside_depth(piece: Dictionary, p: Vector3) -> float:
	var min_d := INF
	for plane: Plane in piece["planes"]:
		var d := plane.distance_to(p)
		if d > 0.0:
			return 0.0
		min_d = minf(min_d, d)
	return -min_d


# ============================================================== 采样（调试/候选点）


## 轴坐标 ≥ min_axis 的 piece 顶点（供格挡候选点搜索等）。
func sample_points(min_axis := -INF) -> Array:
	var out: Array = []
	for piece in pieces:
		for p: Vector3 in piece["v"]:
			if _axis_component(p, axis) >= min_axis:
				out.append(p)
	return out


## 与 span（轴区间）相交的 piece 下标。
func _piece_indices(y_span := INF_V2) -> Array:
	var out: Array = []
	for i in pieces.size():
		var ab: AABB = pieces[i]["aabb"]
		var lo := _axis_component(ab.position, axis)
		var hi := _axis_component(ab.position + ab.size, axis)
		if hi >= y_span.x and lo <= y_span.y:
			out.append(i)
	return out


# ============================================================== 世界化缓存

class _WorldPiece:
	var verts: PackedVector3Array
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)


static func _world_verts(xf: Transform3D, piece: Dictionary) -> _WorldPiece:
	var wp := _WorldPiece.new()
	for p: Vector3 in piece["v"]:
		var w := xf * p
		wp.verts.append(w)
		wp.lo = wp.lo.min(w)
		wp.hi = wp.hi.max(w)
	return wp


static func _aabb_gap(a_lo: Vector3, a_hi: Vector3, b_lo: Vector3, b_hi: Vector3) -> float:
	var d := 0.0
	for c in 3:
		var g: float = maxf(a_lo[c] - b_hi[c], b_lo[c] - a_hi[c])
		if g > 0.0:
			d += g * g
	return sqrt(d)


# ============================================================== GJK 最近距离


static func _furthest(verts: PackedVector3Array, dir: Vector3) -> Vector3:
	var best := verts[0]
	var best_d := best.dot(dir)
	for i in range(1, verts.size()):
		var d: float = verts[i].dot(dir)
		if d > best_d:
			best_d = d
			best = verts[i]
	return best


## 单纯形上到原点最近的点 + 该特征包含的顶点掩码 + 重心权重。
## 返回 {p, keep:Array[int], w:Array[float], inside}
const _COMBOS_2_OF_2 := [[0, 1]]
const _COMBOS_2_OF_3 := [[0, 1], [0, 2], [1, 2]]
const _COMBOS_2_OF_4 := [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]
const _COMBOS_3_OF_3 := [[0, 1, 2]]
const _COMBOS_3_OF_4 := [[0, 1, 2], [0, 1, 3], [0, 2, 3], [1, 2, 3]]
const _TETRA_FACES := [[0, 1, 2, 3], [0, 1, 3, 2], [0, 2, 3, 1], [1, 2, 3, 0]]

static func _simplex_closest(sv: Array) -> Dictionary:
	var n := sv.size()
	if n == 1:
		return {"p": sv[0], "keep": [0], "w": [1.0], "inside": false}
	if n == 4:
		# 原点是否在四面体内：与对顶点在每个面同侧
		var inside := true
		for f in _TETRA_FACES:
			var va: Vector3 = sv[f[0]]
			var vb: Vector3 = sv[f[1]]
			var vc: Vector3 = sv[f[2]]
			var vd: Vector3 = sv[f[3]]
			var nrm := (vb - va).cross(vc - va)
			var side := nrm.dot(vd - va)
			var osign := nrm.dot(-va)
			if side * osign < -1e-12:
				inside = false
				break
		if inside:
			return {"p": Vector3.ZERO, "keep": [0, 1, 2, 3],
				"w": [0.25, 0.25, 0.25, 0.25], "inside": true}
	# 枚举所有真子集特征（点/边/三角），取「内部有最近点」的最近候选
	var best_p := Vector3.ZERO
	var best_keep: Array = []
	var best_w: Array = []
	var best_d := INF
	# 大小 3 的面
	var c3: Array = _COMBOS_3_OF_3 if n == 3 else (_COMBOS_3_OF_4 if n == 4 else [])
	for combo in c3:
		var r := _pt_tri_bary(sv[combo[0]], sv[combo[1]], sv[combo[2]])
		if not bool(r["inside"]):
			continue
		var d2: float = (r["p"] as Vector3).length_squared()
		if d2 < best_d:
			best_d = d2
			best_p = r["p"]
			best_keep = combo
			best_w = [r["u"], r["v"], r["w"]]
	# 大小 2 的边
	var c2: Array = _COMBOS_2_OF_2 if n == 2 else (_COMBOS_2_OF_3 if n == 3 else (_COMBOS_2_OF_4 if n == 4 else []))
	for combo in c2:
		var a: Vector3 = sv[combo[0]]
		var b: Vector3 = sv[combo[1]]
		var ab := b - a
		var t := clampf(-a.dot(ab) / maxf(ab.length_squared(), EPS), 0.0, 1.0)
		if t <= 1e-7 or t >= 1.0 - 1e-7:
			continue    # 最近点在端点，由大小1特征覆盖
		var p: Vector3 = a + ab * t
		var d2 := p.length_squared()
		if d2 < best_d:
			best_d = d2
			best_p = p
			best_keep = combo
			best_w = [1.0 - t, t]
	# 大小 1 的顶点
	for i in n:
		var d2: float = sv[i].length_squared()
		if d2 < best_d:
			best_d = d2
			best_p = sv[i]
			best_keep = [i]
			best_w = [1.0]
	return {"p": best_p, "keep": best_keep, "w": best_w, "inside": false}


static func _combos(n: int, k: int) -> Array:
	var out: Array = []
	if k == 2:
		for i in n:
			for j in range(i + 1, n):
				out.append([i, j])
	elif k == 3:
		for i in n:
			for j in range(i + 1, n):
				for m in range(j + 1, n):
					out.append([i, j, m])
	return out


## 点到三角形的最近点 + 重心坐标 + 是否严格在三角形内
static func _pt_tri_bary(a: Vector3, b: Vector3, c: Vector3) -> Dictionary:
	# 原点在三角形上的最近点（Ericson 5.1.5，重心参数一起返回）
	var ab := b - a
	var ac := c - a
	var ap := -a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return {"p": a, "u": 1.0, "v": 0.0, "w": 0.0, "inside": false}
	var bp := -b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return {"p": b, "u": 0.0, "v": 1.0, "w": 0.0, "inside": false}
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var t := d1 / (d1 - d3)
		return {"p": a + ab * t, "u": 1.0 - t, "v": t, "w": 0.0, "inside": false}
	var cp := -c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return {"p": c, "u": 0.0, "v": 0.0, "w": 1.0, "inside": false}
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var t := d2 / (d2 - d6)
		return {"p": a + ac * t, "u": 1.0 - t, "v": 0.0, "w": t, "inside": false}
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		var t := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return {"p": b + (c - b) * t, "u": 0.0, "v": 1.0 - t, "w": t, "inside": false}
	var denom := 1.0 / (va + vb + vc)
	var u := vb * denom
	var v := vc * denom
	return {"p": a + ab * u + ac * v, "u": 1.0 - u - v, "v": u, "w": v, "inside": true}


## GJK：两凸点集（世界坐标）的最近距离；也返回两边见证点。
## 距离为 0 表示相交。迭代上限 32（margin 边沿的伪收敛会烧满 48），
## 退化返回当前最好 —— 多一次误判无接触，比再叠 16 次迭代划算。
static func _gjk(va: PackedVector3Array, vb: PackedVector3Array) -> Dictionary:
	var sv: Array = []            # Minkowski 差点
	var sa: Array = []            # 对应 A 见证
	var sb: Array = []            # 对应 B 见证
	var mean_a := Vector3.ZERO
	for p in va:
		mean_a += p
	mean_a /= float(va.size())
	var mean_b := Vector3.ZERO
	for p in vb:
		mean_b += p
	mean_b /= float(vb.size())
	var dir := mean_b - mean_a
	if dir.length_squared() < 1e-12:
		dir = Vector3.RIGHT
	var pa := _furthest(va, dir)
	var pb := _furthest(vb, -dir)
	sv.append(pa - pb)
	sa.append(pa)
	sb.append(pb)
	var best_d := INF
	var best_pa := pa
	var best_pb := pb
	for iter in 32:
		var res := _simplex_closest(sv)
		var p: Vector3 = res["p"]
		# 按 keep 裁剪单纯形
		var keep: Array = res["keep"]
		var weights: Array = res["w"]
		var nsv: Array = []
		var nsa: Array = []
		var nsb: Array = []
		for i in keep.size():
			nsv.append(sv[keep[i]])
			nsa.append(sa[keep[i]])
			nsb.append(sb[keep[i]])
		sv = nsv
		sa = nsa
		sb = nsb
		# 见证点 = 单纯形内的重心组合
		var wpa := Vector3.ZERO
		var wpb := Vector3.ZERO
		for i in sa.size():
			wpa += sa[i] * float(weights[i])
			wpb += sb[i] * float(weights[i])
		var d2 := p.length_squared()
		if d2 < best_d:
			best_d = d2
			best_pa = wpa
			best_pb = wpb
		if bool(res["inside"]) or d2 < 1e-14:
			return {"d": 0.0, "pa": best_pa, "pb": best_pb}
		dir = -p
		var sdir := dir.normalized()
		var a_pt := _furthest(va, sdir)
		var b_pt := _furthest(vb, -sdir)
		var w := a_pt - b_pt
		# 下界估计：support 平面已过原点时无可再推进
		var advance := (w - p).dot(dir)
		if advance <= 1e-9 * maxf(1.0, d2):
			break
		sv.append(w)
		sa.append(a_pt)
		sb.append(b_pt)
		if sv.size() > 4:
			# 理论上 simplex_closest 已裁剪到特征；防御性截断
			var r2 := _simplex_closest(sv)
			var keep2: Array = r2["keep"]
			var tsv: Array = []
			var tsa: Array = []
			var tsb: Array = []
			for i in keep2:
				tsv.append(sv[i])
				tsa.append(sa[i])
				tsb.append(sb[i])
			sv = tsv
			sa = tsa
			sb = tsb
	return {"d": sqrt(maxf(best_d, 0.0)), "pa": best_pa, "pb": best_pb}


# ============================================================== 基础查询


## 线段（世界 a-b）与 piece（本地）+ xf 的最近距离。
## 返回 {d, pa(刀面点), pb(线段点)}；d<0 表示端点陷入 piece（深度）。
static func _dist_seg_piece(a: Vector3, b: Vector3, xf: Transform3D, piece: Dictionary) -> Dictionary:
	return _dist_seg_wverts(a, b, xf, piece, _world_verts(xf, piece))


static func _dist_seg_wverts(a: Vector3, b: Vector3, xf: Transform3D, piece: Dictionary, wverts: _WorldPiece) -> Dictionary:
	var seg := PackedVector3Array([a, b])
	var res := _gjk(seg, wverts.verts)
	var d: float = res["d"]
	if d > 0.0:
		return {"d": d, "pa": res["pb"], "pb": res["pa"], "wp": wverts}
	# 相交或陷入：看端点在 piece 内的深度
	var wa: Vector3 = a
	var wb: Vector3 = b
	# 注意：piece 平面在本地空间 —— 把世界端点逆变换回来
	var inv := xf.affine_inverse()
	var la := inv * wa
	var lb := inv * wb
	var depth := maxf(_inside_depth(piece, la), _inside_depth(piece, lb))
	return {"d": -depth, "pa": res["pb"], "pb": res["pa"], "wp": wverts}


## 整个 proxy 相对一条世界线段的最小签名距离（含 span 过滤）。
## gap = dist（凸体面到线段轴线的距离）；调用方自行减胶囊半径。
func dist_to_segment(xf: Transform3D, a: Vector3, b: Vector3,
		y_span := INF_V2) -> Dictionary:
	var best := {"d": 1e9, "pa": xf.origin, "pb": a, "t": 0.5}
	for i in _piece_indices(y_span):
		var piece: Dictionary = pieces[i]
		var res := _dist_seg_piece(a, b, xf, piece)
		if float(res["d"]) < float(best["d"]):
			best = {"d": res["d"], "pa": res["pa"], "pb": res["pb"],
				"t": _seg_t(a, b, res["pb"])}
			if float(res["d"]) < -0.05:
				break    # 已经穿透，提前结束
	return best


static func _seg_t(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	return clampf((p - a).dot(ab) / maxf(ab.length_squared(), EPS), 0.0, 1.0)


## piece 对世界点 p 的距离（0 = 表面/内部）。返回 {d, pa, inside_depth}
func _dist_point_piece(xf: Transform3D, piece: Dictionary, p: Vector3) -> Dictionary:
	var wverts := _world_verts(xf, piece)
	var single := PackedVector3Array([p])
	var res := _gjk(single, wverts.verts)
	if float(res["d"]) > 0.0:
		return {"d": res["d"], "pa": res["pb"], "inside": 0.0}
	var depth := _inside_depth(piece, xf.affine_inverse() * p)
	return {"d": -depth, "pa": res["pb"], "inside": depth}


func point_gap(xf: Transform3D, p: Vector3, y_span := INF_V2) -> Dictionary:
	var best := {"d": 1e9, "pa": xf.origin}
	for i in _piece_indices(y_span):
		var res := _dist_point_piece(xf, pieces[i], p)
		if float(res["d"]) < float(best["d"]):
			best = res
	return best


# ============================================================== 高层查询


## 两把刀当前姿态的最近间隙（凸体最短距离，无半径和）。
## span_a/b 把参与判定的 piece 限在刀轴区间；slack = 判定阈值。
static func blade_vs_blade(xf_a: Transform3D, proxy_a: BladeProxy,
		xf_b: Transform3D, proxy_b: BladeProxy, slack := 0.03,
		span_a := INF_V2, span_b := INF_V2, need_depth := false) -> Dictionary:
	if proxy_a == null or proxy_b == null or proxy_a.pieces.is_empty() or proxy_b.pieces.is_empty():
		return {"hit": false, "gap": 1e9}
	var wa: Array = []
	for i in proxy_a._piece_indices(span_a):
		wa.append(_world_verts(xf_a, proxy_a.pieces[i]))
	var wb: Array = []
	for i in proxy_b._piece_indices(span_b):
		wb.append(_world_verts(xf_b, proxy_b.pieces[i]))
	return _blade_vs_blade_precomp(xf_a, proxy_a, wa, xf_b, proxy_b, wb, slack, span_a, span_b, need_depth)


static func _blade_vs_blade_precomp(xf_a: Transform3D, proxy_a: BladeProxy, wa: Array,
		xf_b: Transform3D, proxy_b: BladeProxy, wb: Array, slack: float,
		span_a: Vector2, span_b: Vector2, need_depth := false) -> Dictionary:
	var best := {"hit": false, "gap": 1e9, "point": Vector3.ZERO, "normal": Vector3.UP}
	for wa_p in wa:
		for wb_p in wb:
			var agap := _aabb_gap(wa_p.lo, wa_p.hi, wb_p.lo, wb_p.hi)
			if agap > maxf(slack, 0.0) + 0.05 and agap > float(best["gap"]):
				continue
			var res := _gjk(wa_p.verts, wb_p.verts)
			var gap: float = res["d"]
			var pa: Vector3 = res["pa"]
			var pb: Vector3 = res["pb"]
			if gap <= 0.0 and need_depth:
				# 相交：用平面内部深度给穿透量
				var depth := 0.0
				var inv_b := xf_b.affine_inverse()
				var inv_a := xf_a.affine_inverse()
				for i in proxy_a._piece_indices(span_a):
					for wv: Vector3 in proxy_a.pieces[i]["v"]:
						depth = maxf(depth, _inside_depth_of(proxy_b, inv_b * (xf_a * wv)))
				for i in proxy_b._piece_indices(span_b):
					for wv: Vector3 in proxy_b.pieces[i]["v"]:
						depth = maxf(depth, _inside_depth_of(proxy_a, inv_a * (xf_b * wv)))
				gap = -depth
			if gap < float(best["gap"]):
				var n := pa - pb
				if n.length_squared() < EPS:
					n = xf_b.basis.y
				best = {"hit": gap <= slack, "gap": gap, "depth": -gap,
					"point": (pa + pb) * 0.5, "normal": n.normalized()}
				if bool(best["hit"]) and not need_depth:
					return best
	return best


## 扫掠版剑挡剑：两把刀这一帧各自 prev→cur，3×4 子采样。
static func blade_vs_blade_swept(prev_a: Transform3D, cur_a: Transform3D,
		proxy_a: BladeProxy, prev_b: Transform3D, cur_b: Transform3D,
		proxy_b: BladeProxy, slack := 0.03,
		span_a := INF_V2, span_b := INF_V2,
		steps_a := 3, steps_b := 4, deadline := -1) -> Dictionary:
	if proxy_a == null or proxy_b == null or proxy_a.pieces.is_empty() or proxy_b.pieces.is_empty():
		return {"hit": false, "gap": 1e9}
	var best := {"hit": false, "gap": 1e9, "point": Vector3.ZERO, "normal": Vector3.UP}
	var na := maxi(steps_a, 2)
	var nb := maxi(steps_b, 2)
	var idxs_a := proxy_a._piece_indices(span_a)
	var idxs_b := proxy_b._piece_indices(span_b)
	if idxs_a.is_empty() or idxs_b.is_empty():
		return best
	var xfs_a: Array = []
	var w_a: Array = []
	var lo_a: Array = []
	var hi_a: Array = []
	var all_a_lo := Vector3(INF, INF, INF)
	var all_a_hi := Vector3(-INF, -INF, -INF)
	for i in na:
		var xa := _lerp_xf(prev_a, cur_a, float(i) / float(na - 1))
		xfs_a.append(xa)
		var wlist: Array = []
		var slo := Vector3(INF, INF, INF)
		var shi := Vector3(-INF, -INF, -INF)
		for ia in idxs_a:
			var wp := _world_verts(xa, proxy_a.pieces[ia])
			wlist.append(wp)
			slo = slo.min(wp.lo)
			shi = shi.max(wp.hi)
		w_a.append(wlist)
		lo_a.append(slo)
		hi_a.append(shi)
		all_a_lo = all_a_lo.min(slo)
		all_a_hi = all_a_hi.max(shi)
	var xfs_b: Array = []
	var w_b: Array = []
	var lo_b: Array = []
	var hi_b: Array = []
	var all_b_lo := Vector3(INF, INF, INF)
	var all_b_hi := Vector3(-INF, -INF, -INF)
	for j in nb:
		var xb := _lerp_xf(prev_b, cur_b, float(j) / float(nb - 1))
		xfs_b.append(xb)
		var wlist: Array = []
		var slo := Vector3(INF, INF, INF)
		var shi := Vector3(-INF, -INF, -INF)
		for ib in idxs_b:
			var wpb := _world_verts(xb, proxy_b.pieces[ib])
			wlist.append(wpb)
			slo = slo.min(wpb.lo)
			shi = shi.max(wpb.hi)
		w_b.append(wlist)
		lo_b.append(slo)
		hi_b.append(shi)
		all_b_lo = all_b_lo.min(slo)
		all_b_hi = all_b_hi.max(shi)
	var broad_gap := _aabb_gap(all_a_lo, all_a_hi, all_b_lo, all_b_hi)
	if broad_gap > maxf(slack, 0.0) + 0.15:
		return {"hit": false, "gap": broad_gap, "point": Vector3.ZERO, "normal": Vector3.UP}
	# 优先检查同步时刻对，尽快命中早退
	var checked := {}
	for i in na:
		var j := int(round(float(i) * float(nb - 1) / float(na - 1)))
		checked[i * nb + j] = true
		if _aabb_gap(lo_a[i], hi_a[i], lo_b[j], hi_b[j]) > maxf(slack, 0.0) + 0.15:
			continue
		var r := _blade_vs_blade_precomp(xfs_a[i], proxy_a, w_a[i], xfs_b[j], proxy_b, w_b[j], slack, span_a, span_b, false)
		if bool(r.get("hit", false)):
			return r
		if float(r.get("gap", 1e9)) < float(best["gap"]):
			best = r
	for i in na:
		if deadline >= 0 and Time.get_ticks_usec() > deadline:
			break
		for j in nb:
			if checked.has(i * nb + j):
				continue
			if deadline >= 0 and Time.get_ticks_usec() > deadline:
				break
			if _aabb_gap(lo_a[i], hi_a[i], lo_b[j], hi_b[j]) > maxf(slack, 0.0) + 0.15:
				continue
			var r := _blade_vs_blade_precomp(xfs_a[i], proxy_a, w_a[i], xfs_b[j], proxy_b, w_b[j], slack, span_a, span_b, false)
			if bool(r.get("hit", false)):
				return r
			if float(r.get("gap", 1e9)) < float(best["gap"]):
				best = r
	return best


## 一次挥刀 vs 一颗胶囊（cap_a-cap_b 轴心，cap_r 半径）。
## 返回 {hit, depth, point, blade_point, normal, travel, t, blade_local}
static func sweep_capsule(prev: Transform3D, cur: Transform3D, proxy: BladeProxy,
		cap_a: Vector3, cap_b: Vector3, cap_r: float,
		y_span := INF_V2, steps := 3) -> Dictionary:
	var best := {"hit": false, "depth": 0.0, "gap": 1e9}
	var cap_lo := cap_a.min(cap_b) - Vector3.ONE * cap_r
	var cap_hi := cap_a.max(cap_b) + Vector3.ONE * cap_r
	var ns := maxi(steps, 1)
	for i in proxy._piece_indices(y_span):
		var piece: Dictionary = proxy.pieces[i]
		# piece 扫掠 AABB（首末姿态并集）
		var wp0 := _world_verts(prev, piece)
		var wp1 := _world_verts(cur, piece)
		var lo := wp0.lo.min(wp1.lo)
		var hi := wp0.hi.max(wp1.hi)
		if _aabb_gap(lo, hi, cap_lo, cap_hi) > maxf(float(best.get("gap", 1e9)), cap_r):
			continue
		for s in ns:
			var xf := _lerp_xf(prev, cur, float(s) / float(maxi(ns - 1, 1)))
			var res := _dist_seg_piece(cap_a, cap_b, xf, piece)
			var gap: float = float(res["d"]) - cap_r
			if gap < float(best["gap"]):
				var n: Vector3 = res["pa"] - res["pb"]
				if n.length_squared() < EPS:
					n = cur.basis.y
				var pt: Vector3 = res["pa"]
				best = {"hit": gap <= 0.0, "depth": maxf(0.0, -gap), "gap": gap,
					"point": res["pb"], "blade_point": pt,
					"normal": n.normalized(),
					"blade_local": xf.affine_inverse() * pt,
					"travel": pt - (prev * (xf.affine_inverse() * pt)),
					"t": _seg_t(cap_a, cap_b, res["pb"])}
			if gap <= -cap_r:
				break    # 深度穿透，不必再细分
	return best


## 身体多段胶囊版挥刀结算：逐判定件取最深接触（同 Hit.sweep_blade_parts）。
static func sweep_capsule_parts(prev: Transform3D, cur: Transform3D, proxy: BladeProxy,
		parts: Array, y_span := INF_V2, steps := 3) -> Dictionary:
	if proxy == null or proxy.pieces.is_empty() or parts.is_empty():
		return {"hit": false, "depth": 0.0}
	var idxs := proxy._piece_indices(y_span)
	if idxs.is_empty():
		return {"hit": false, "depth": 0.0}
	var ns := maxi(steps, 1)
	var xfs: Array[Transform3D] = []
	xfs.resize(ns)
	for s in ns:
		xfs[s] = _lerp_xf(prev, cur, float(s) / float(maxi(ns - 1, 1)))
	# 整个刀扫掠体 & 逐段各步世界顶点/AABB 一次性预计算，避免逐部位重复变换
	var blo := Vector3(INF, INF, INF)
	var bhi := Vector3(-INF, -INF, -INF)
	var piece_wverts: Array = []
	var p_lo: Array[Vector3] = []
	var p_hi: Array[Vector3] = []
	piece_wverts.resize(idxs.size())
	p_lo.resize(idxs.size())
	p_hi.resize(idxs.size())
	for k in idxs.size():
		var piece: Dictionary = proxy.pieces[idxs[k]]
		var wlist: Array = []
		wlist.resize(ns)
		var klo := Vector3(INF, INF, INF)
		var khi := Vector3(-INF, -INF, -INF)
		for s in ns:
			var wp := _world_verts(xfs[s], piece)
			wlist[s] = wp
			klo = klo.min(wp.lo)
			khi = khi.max(wp.hi)
		piece_wverts[k] = wlist
		p_lo[k] = klo
		p_hi[k] = khi
		blo = blo.min(klo)
		bhi = bhi.max(khi)
	var best := {"hit": false, "depth": 0.0}
	for p in parts:
		var pa: Vector3 = p["a"]
		var pb: Vector3 = p["b"]
		var pr: float = float(p["r"])
		var cap_lo := pa.min(pb) - Vector3.ONE * pr
		var cap_hi := pa.max(pb) + Vector3.ONE * pr
		if cap_lo.x > bhi.x or cap_hi.x < blo.x or cap_lo.y > bhi.y or cap_hi.y < blo.y or cap_lo.z > bhi.z or cap_hi.z < blo.z:
			continue
		var p_best := {"hit": false, "depth": 0.0, "gap": 1e9}
		var cutoff := 0.0 if bool(best["hit"]) else maxf(float(best.get("gap", 1e9)), 0.0)
		for k in idxs.size():
			if _aabb_gap(p_lo[k], p_hi[k], cap_lo, cap_hi) > pr + cutoff:
				continue
			var piece: Dictionary = proxy.pieces[idxs[k]]
			var wlist: Array = piece_wverts[k]
			for s in ns:
				var w: _WorldPiece = wlist[s]
				if _aabb_gap(w.lo, w.hi, cap_lo, cap_hi) > pr + minf(cutoff, maxf(float(p_best["gap"]), 0.0)):
					continue
				var xf := xfs[s]
				var res := _dist_seg_wverts(pa, pb, xf, piece, w)
				var gap: float = float(res["d"]) - pr
				if gap < float(p_best["gap"]):
					var n: Vector3 = res["pa"] - res["pb"]
					if n.length_squared() < EPS:
						n = cur.basis.y
					var pt: Vector3 = res["pa"]
					p_best = {"hit": gap <= 0.0, "depth": maxf(0.0, -gap), "gap": gap,
						"point": res["pb"], "blade_point": pt,
						"normal": n.normalized(),
						"blade_local": xf.affine_inverse() * pt,
						"travel": pt - (prev * (xf.affine_inverse() * pt)),
						"t": _seg_t(pa, pb, res["pb"])}
				if gap <= -pr:
					break
		if not bool(p_best.get("hit", false)):
			if float(p_best.get("gap", 1e9)) < float(best.get("gap", 1e9)) and not bool(best["hit"]):
				var g: float = p_best["gap"]
				best = {"hit": false, "depth": 0.0, "gap": g}
			continue
		if float(p_best["depth"]) <= float(best["depth"]) and bool(best["hit"]):
			continue
		best = p_best.duplicate()
		best["hit"] = true
		best["part"] = String(p.get("label", ""))
		best["capsule_a"] = pa
		best["capsule_b"] = pb
		best["capsule_r"] = pr
		if p.has("side"):
			best["side"] = p["side"]
	return best


## 飞行物线段 vs 静止刀身（箭/飞行物格挡）
static func segment_vs_proxy(prev: Vector3, pos: Vector3, xf: Transform3D,
		proxy: BladeProxy, radius: float, y_span := INF_V2) -> Dictionary:
	if proxy == null:
		return {"hit": false, "depth": 0.0}
	var best := 0.0
	var point := Vector3.ZERO
	for i in proxy._piece_indices(y_span):
		var res := _dist_seg_piece(prev, pos, xf, proxy.pieces[i])
		var gap: float = float(res["d"]) - radius
		var depth := -gap
		if depth > best:
			best = depth
			point = res["pa"]
	return {"hit": best > 0.0, "depth": best, "point": point}


## 飞行物线段 vs 运动中的刀身（同时把飞行物从 prev_xf→cur_xf 转换到刀的本地扫掠空间）
static func segment_vs_proxy_swept(prev_p: Vector3, cur_p: Vector3,
		prev_xf: Transform3D, cur_xf: Transform3D,
		proxy: BladeProxy, radius: float, y_span := INF_V2) -> Dictionary:
	if proxy == null or proxy.pieces.is_empty():
		return {"hit": false, "depth": 0.0}
	if prev_xf.is_equal_approx(cur_xf) or prev_xf.origin.distance_squared_to(cur_xf.origin) > 64.0:
		return segment_vs_proxy(prev_p, cur_p, cur_xf, proxy, radius, y_span)
	var eff_r := radius + 0.06
	var la := prev_xf.affine_inverse() * prev_p
	var lb := cur_xf.affine_inverse() * cur_p
	var best := 0.0
	var point := Vector3.ZERO
	var idxs := proxy._piece_indices(y_span)
	for i in idxs:
		var piece: Dictionary = proxy.pieces[i]
		var res := _dist_seg_piece(la, lb, Transform3D.IDENTITY, piece)
		var depth := eff_r - float(res["d"])
		if depth > best:
			best = depth
			point = cur_xf * (res["pa"] as Vector3)
	if best > 0.0:
		return {"hit": true, "depth": best, "point": point}
	# 子采样兜底：防止高角速度旋转导致相对线段弯曲漏判
	var mid_xf := _lerp_xf(prev_xf, cur_xf, 0.5)
	var mid_p := (prev_p + cur_p) * 0.5
	var r0 := segment_vs_proxy(prev_p, mid_p, mid_xf, proxy, eff_r, y_span)
	if bool(r0.get("hit", false)):
		return r0
	return segment_vs_proxy(mid_p, cur_p, cur_xf, proxy, eff_r, y_span)


## 静止刀身 vs 球（用刀挡箭/球的即时接触）
static func proxy_vs_sphere(xf: Transform3D, proxy: BladeProxy, center: Vector3,
		radius: float, y_span := INF_V2) -> Dictionary:
	if proxy == null:
		return {"hit": false, "depth": 0.0}
	var best := 0.0
	var point := Vector3.ZERO
	for i in proxy._piece_indices(y_span):
		var res := _dist_seg_piece(center, center, xf, proxy.pieces[i])
		var depth: float = radius - float(res["d"])
		if float(res["d"]) <= 0.0:
			depth = radius + (-float(res["d"]))
		if depth > best:
			best = depth
			point = res["pa"]
	return {"hit": best > 0.0, "depth": best, "point": point}


## 格挡可达性：两个 proxy 当前姿态的真实间隙（正=分开，负=穿透）。
static func closest_gap(xf_a: Transform3D, proxy_a: BladeProxy,
		xf_b: Transform3D, proxy_b: BladeProxy,
		span_a := INF_V2, span_b := INF_V2) -> Dictionary:
	var r := blade_vs_blade(xf_a, proxy_a, xf_b, proxy_b, 0.0, span_a, span_b)
	return {"gap": float(r.get("gap", 1e9)), "point": r.get("point", Vector3.ZERO),
		"normal": r.get("normal", Vector3.UP)}


## 刀与一颗胶囊的最小签名间隙（敌刀接近身体的度量）。
static func gap_to_capsule(xf: Transform3D, proxy: BladeProxy,
		cap_a: Vector3, cap_b: Vector3, cap_r: float,
		y_span := INF_V2) -> Dictionary:
	if proxy == null or proxy.pieces.is_empty():
		return {"gap": 1e9, "blade_pt": xf.origin, "body_pt": cap_a, "blade_local": Vector3.ZERO}
	var res := proxy.dist_to_segment(xf, cap_a, cap_b, y_span)
	var gap: float = float(res["d"]) - cap_r
	return {"gap": gap, "blade_pt": res["pa"], "body_pt": res["pb"],
		"blade_local": xf.affine_inverse() * (res["pa"] as Vector3)}


static func _lerp_xf(a: Transform3D, b: Transform3D, t: float) -> Transform3D:
	if t <= 0.0:
		return a
	if t >= 1.0:
		return b
	var qa := a.basis.get_rotation_quaternion()
	var qb := b.basis.get_rotation_quaternion()
	if qa.dot(qb) < 0.0:
		qb = Quaternion(-qb.x, -qb.y, -qb.z, -qb.w)
	var sa := a.basis.get_scale()
	var sb := b.basis.get_scale()
	return Transform3D(Basis(qa.slerp(qb, t)).scaled(sa.lerp(sb, t)),
		a.origin.lerp(b.origin, t))


static func _inside_depth_of(proxy: BladeProxy, local_p: Vector3) -> float:
	var depth := 0.0
	for piece in proxy.pieces:
		depth = maxf(depth, _inside_depth(piece, local_p))
	return depth
