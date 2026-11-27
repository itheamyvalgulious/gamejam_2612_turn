extends SceneTree
## 能量刀凸体代理的离线校验工具（无头可跑）。
##
## 用法：
##   python3 main/tools/prepare_game.py
##   godot --headless --path main -s res://tools/blade_proxy_check.gd [-- --samples=80000]
##
## 口径（比 ray-parity 更稳）：源网格可能是开放/非流形（能量刃是两张合页的壳）。
## 指标：
##   coverage：源网格顶点 + 每三角 4 个插值点，到 proxy 的有符号间隙最大值
##             ≤ 1e-3（GJK 到凸体的距离，负=已包含）。这是硬性线：漏一点 → FAIL。
##   miss    ：源表面采样点中在 proxy 外的比例（proxy 欠逼近 → 漏判风险）。
##   excess  ：proxy 内距源表面 > δ 的体积分率 / 源体积（proxy 过胀程度）。
##             上界验收（≤5% 理想 ≤3%）；开放壳的「源体积」按 δ 邻域近似，
##             故以 coverage + excess 双指标验收，注释里说明原因。
## 分两组报告：blade = 刀身（blade_span 内的 piece/顶点），hilt = 护手/柄。

const PlayerRig = preload("res://runtime/characters/vesper/design/integration/campaign_rig.gd")
const DuelistRig = preload("res://runtime/enemies/mobs/mech_duelist/design/src/enemies/duelist/duelist_combat_rig.gd")
const ArcModel = preload("res://runtime/enemies/mobs/arc_sentinel/design/scripts/ch/arc_sentinel.gd")
const ARC_SCALE := 1.0 / 0.547
const ARC_EDGE_RADIUS := 0.24
const DUELIST_SWEEP_END := 0.22 + 2.42 + 0.85
const DUELIST_BLADE_END := 0.22 + 2.42
const DELTA := 0.006              # 开放壳「源实体」半厚近似（世界单位）

var _args := {}
var _failures := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", false, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var samples := int(_args.get("samples", "60000"))
	print("[blade-check] samples=%d delta=%.4f" % [samples, DELTA])
	await process_frame
	if int(_args.get("duelist-segments", "0")) > 0:
		await _check_duelist(samples)
	else:
		await _check_player(samples)
		await _check_duelist(samples)
		await _check_arc(samples)
	if _failures == 0:
		print("[blade-check] ALL PASS")
	else:
		print("[blade-check] %d FAILURE(S)" % _failures)
	quit()


# ---------------------------------------------------------------- 玩家能量刀


func _check_player(samples: int) -> void:
	var rig: Node3D = PlayerRig.new()
	rig.auto_step = false
	rig.set_process(false)
	rig.scale = Vector3.ONE * ARC_SCALE
	root.add_child(rig)
	await process_frame
	var groups := _spin_groups(rig.weapon_spin)
	var blade_span: Vector2 = rig.blade_span()
	# 分组报告：blade = 质心落在 blade_span 内的网格；pieces 用拟合时打的 "g" 标签对应
	var blade_idx: Array[int] = []
	var hilt_idx: Array[int] = []
	for gi in groups.size():
		var bbox := _group_bbox(groups[gi]["points"])
		var mid_y := (bbox.position.y + bbox.size.y * 0.5)
		if mid_y >= blade_span.x - 0.02:
			blade_idx.append(gi)
		else:
			hilt_idx.append(gi)
	var blade_groups := _pick(groups, blade_idx)
	var hilt_groups := _pick(groups, hilt_idx)
	_report("vesper blade", blade_groups,
		BladeProxy.new(_pieces_of(rig.blade_proxy.pieces, blade_idx)), samples)
	_report("vesper hilt", hilt_groups,
		BladeProxy.new(_pieces_of(rig.blade_proxy.pieces, hilt_idx)), samples / 4)
	rig.queue_free()


static func _pick(groups: Array, idx: Array[int]) -> Array:
	var out: Array = []
	for i in idx:
		out.append(groups[i])
	return out


static func _pieces_of(pieces: Array, idx: Array[int]) -> Array:
	var out: Array = []
	for piece in pieces:
		if idx.has(int(piece.get("g", -1))):
			out.append(piece)
	return out


func _spin_groups(spin: Node3D) -> Array:
	var groups: Array = []
	for child in spin.get_children():
		if child is not MeshInstance3D or child.name in [&"BladeGlow1", &"BladeAura"]:
			continue
		var part := child as MeshInstance3D
		var points := PackedVector3Array()
		var tris := PackedInt32Array()
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var base := points.size()
			for v in verts:
				points.append(part.transform * v)
			if idx.is_empty():
				for i in verts.size():
					tris.append(base + i)
			else:
				for i in idx:
					tris.append(base + i)
		groups.append({"points": points, "tris": tris})
	return groups


func _group_bbox(pts: PackedVector3Array) -> AABB:
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return box


# ---------------------------------------------------------------- 决斗士刀


func _check_duelist(samples: int) -> void:
	var rig: Node3D = DuelistRig.new()
	rig.set_process(false)
	root.add_child(rig)
	await process_frame
	var groups := _duelist_groups(rig)
	var seg_override := int(_args.get("duelist-segments", "0"))
	var metal: BladeProxy
	if seg_override > 0:
		# 段数扫描模式：不读 rig 的 proxy，直接对源网格组重新拟合
		metal = BladeProxy.fit_groups(groups, seg_override)
	else:
		var opening: BladeProxy = rig.blade_proxy   # _opening_clock 默认 true
		var pieces_metal: Array = []
		var sweep_v := 0
		for piece in opening.pieces:
			if int(piece.get("g", -1)) >= 0:
				pieces_metal.append(piece)
			else:
				sweep_v += (piece["v"] as PackedVector3Array).size()
		metal = BladeProxy.new(pieces_metal)
		print("[blade-check] duelist opening pieces=%d total_verts=%d sweep_verts=%d"
			% [opening.pieces.size(), opening.total_vertices(), sweep_v])
	_report("duelist metal blade", groups, metal, samples)
	rig.queue_free()


func _duelist_groups(rig: Node3D) -> Array:
	var groups: Array = []
	var mount: Node3D = rig.find_child("ResonatingBlade", true, false)
	for child in mount.get_children():
		if child is not MeshInstance3D or child.name in [&"BladeInlay", &"EnergizedEdge"]:
			continue
		var part := child as MeshInstance3D
		if part.mesh.get_surface_count() < 2:
			continue
		var points := PackedVector3Array()
		var tris := PackedInt32Array()
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var base := points.size()
			for v in verts:
				points.append(part.transform * v)
			if idx.is_empty():
				for i in verts.size():
					tris.append(base + i)
			else:
				for i in idx:
					tris.append(base + i)
		groups.append({"points": points, "tris": tris})
	return groups


# ---------------------------------------------------------------- ARC 哨兵刀


func _check_arc(samples: int) -> void:
	var model: Node3D = ArcModel.new()
	model.scale = Vector3.ONE * ARC_SCALE
	root.add_child(model)
	await process_frame
	var length: float = model.rig.marker_tip.global_position.distance_to(model.rig.marker_base.global_position)
	# 与 arc_encounter 同款：24 棱柱外切于刃缘圆柱（r/cos(π/24) 外接半径）
	var proxy := BladeProxy.from_prism(
		BladeProxy.regular_ring(24, ARC_EDGE_RADIUS / cos(PI / 24.0)), 0.0, length)
	# 源 = 有盖圆柱面（等离体没有网格；旧 disc 几何 = r=0.24 圆柱）
	var SEG := 64
	var pts := PackedVector3Array()
	var tris := PackedInt32Array()
	for s in SEG + 1:
		var y := length * float(s) / float(SEG)
		for i in 16:
			var ang := TAU * float(i) / 16.0
			pts.append(Vector3(cos(ang) * ARC_EDGE_RADIUS, y, sin(ang) * ARC_EDGE_RADIUS))
	# 底/顶盖中心点
	var bot_c := pts.size()
	pts.append(Vector3.ZERO)
	var top_c := pts.size()
	pts.append(Vector3(0, length, 0))
	for s in SEG:
		for i in 16:
			var j := (i + 1) % 16
			var a := s * 16 + i
			var b := s * 16 + j
			var c := (s + 1) * 16 + j
			var d := (s + 1) * 16 + i
			tris.append_array([a, b, c, a, c, d])
	for i in 16:
		var j := (i + 1) % 16
		tris.append_array([bot_c, j, i])
		var hi := SEG * 16
		tris.append_array([top_c, hi + i, hi + j])
	_report("arc sentinel edge", [{"points": pts, "tris": tris}], proxy, samples)
	model.queue_free()


# ---------------------------------------------------------------- 报告


func _report(label: String, groups: Array, proxy: BladeProxy, samples: int) -> void:
	var src_pts := PackedVector3Array()
	var src_tris := PackedInt32Array()
	for g in groups:
		var base := src_pts.size()
		src_pts.append_array(g["points"])
		for i in g["tris"]:
			src_tris.append(base + i)
	if src_pts.is_empty() or proxy.pieces.is_empty():
		print("[blade-check] %s: EMPTY (src=%d pts, pieces=%d) → FAIL" % [label, src_pts.size(), proxy.pieces.size()])
		_failures += 1
		return
	var closed := _is_closed(src_pts, src_tris)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	# ---- 1) 覆盖率：顶点 + 每三角内部点，到 proxy 的最大有符号间隙
	var max_gap := -1e9
	var missed := 0
	for i in src_pts.size():
		var g := _proxy_gap(proxy, src_pts[i])
		max_gap = maxf(max_gap, g)
		if g > 0.001:
			missed += 1
	for i in range(0, src_tris.size(), 3):
		var a: Vector3 = src_pts[src_tris[i]]
		var b: Vector3 = src_pts[src_tris[i + 1]]
		var c: Vector3 = src_pts[src_tris[i + 2]]
		for uv in [[0.5, 0.25], [0.25, 0.5], [0.25, 0.25], [1.0 / 3.0, 1.0 / 3.0]]:
			var p: Vector3 = a + (b - a) * float(uv[0]) + (c - a) * float(uv[1])
			var g := _proxy_gap(proxy, p)
			max_gap = maxf(max_gap, g)
			if g > 0.001:
				missed += 1
	# ---- 2) 体积近似：源表面等权采样 → 点在 proxy 内（miss）；
	#         proxy 体积内均匀点 → 离源实体 > δ（excess）。
	var surf_samples := _surface_samples(src_pts, src_tris, 4000, rng)
	var miss := 0
	for p in surf_samples:
		# 与覆盖率同一容差：proxy 面穿过源壳时采样点恰在面上，gap≈±1e-9
		if _proxy_gap(proxy, p) > 0.001:
			miss += 1
	var miss_pct := float(miss) / float(surf_samples.size()) * 100.0
	var bbox := AABB(src_pts[0], Vector3.ZERO)
	for p in src_pts:
		bbox = bbox.expand(p)
	bbox = bbox.grow(0.02)
	var cell: float = bbox.size.x * bbox.size.y * bbox.size.z
	var inside_src := 0
	var inside_proxy := 0
	var excess := 0
	for i in samples:
		var p := Vector3(
			rng.randf_range(bbox.position.x, bbox.position.x + bbox.size.x),
			rng.randf_range(bbox.position.y, bbox.position.y + bbox.size.y),
			rng.randf_range(bbox.position.z, bbox.position.z + bbox.size.z))
		var src_in := (_in_mesh(src_pts, src_tris, p) if closed
			else _near_surface(src_pts, src_tris, p, DELTA))
		var proxy_in := _in_proxy(proxy, p)
		if src_in:
			inside_src += 1
		if proxy_in:
			inside_proxy += 1
			if not src_in:
				excess += 1
	var src_vol := cell * float(inside_src) / float(samples)
	var proxy_vol := cell * float(inside_proxy) / float(samples)
	var excess_pct := float(excess) / float(maxi(inside_src, 1)) * 100.0
	var ok := missed == 0 and max_gap <= 0.001 and miss_pct <= 5.0 and excess_pct <= 50.0
	var verdict := "OK" if ok else "FAIL"
	if not ok:
		_failures += 1
	print("[blade-check] %s (%s): src_vol≈%.4f proxy_vol=%.4f miss=%.2f%% excess=%.2f%% max_gap=%.4f pieces=%d verts=%d → %s"
		% [label, "closed" if closed else "open+δ", src_vol, proxy_vol,
			miss_pct, excess_pct, max_gap,
			proxy.pieces.size(), proxy.total_vertices(), verdict])


## 闭合网格的点内测试：射线奇偶（交点按 t 去重，顶点/边穿越不重复计）
func _in_mesh(pts: PackedVector3Array, tris: PackedInt32Array, p: Vector3) -> bool:
	var dir := Vector3(1.0, 0.0713, 0.0377).normalized()
	var ts: Array[float] = []
	for i in range(0, tris.size(), 3):
		var t := _ray_tri_t(p, dir, pts[tris[i]], pts[tris[i + 1]], pts[tris[i + 2]])
		if t > 0.0:
			ts.append(t)
	if ts.is_empty():
		return false
	ts.sort()
	var hits := 0
	var last_t := -1.0
	for t in ts:
		if t - last_t > 1e-4 * maxf(1.0, t):
			hits += 1
			last_t = t
	return hits % 2 == 1


static func _ray_tri_t(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var pvec := d.cross(e2)
	var det := e1.dot(pvec)
	if absf(det) < 1e-9:
		return -1.0
	var inv := 1.0 / det
	var tvec := o - a
	var u := tvec.dot(pvec) * inv
	if u < -1e-9 or u > 1.0 + 1e-9:
		return -1.0
	var qvec := tvec.cross(e1)
	var v := d.dot(qvec) * inv
	if v < -1e-9 or u + v > 1.0 + 1e-9:
		return -1.0
	var t := e2.dot(qvec) * inv
	return t if t > 1e-7 else -1.0


## 每条无向边是否都被两个三角形共享（按位置去重顶点后的索引计数）
func _is_closed(pts: PackedVector3Array, tris: PackedInt32Array) -> bool:
	var keys := {}
	var remap := {}
	for i in pts.size():
		var p := pts[i]
		var k := Vector3i(int(round(p.x * 8192.0)), int(round(p.y * 8192.0)), int(round(p.z * 8192.0)))
		if not remap.has(k):
			remap[k] = i
		keys[i] = remap[k]
	var edge_count := {}
	for i in range(0, tris.size(), 3):
		for e in [[tris[i], tris[i + 1]], [tris[i + 1], tris[i + 2]], [tris[i + 2], tris[i]]]:
			var a: int = keys[e[0]]
			var b: int = keys[e[1]]
			var k := mini(a, b) * 100003 + maxi(a, b)
			edge_count[k] = edge_count.get(k, 0) + 1
	for k in edge_count:
		if edge_count[k] < 2:
			return false
	return true


## 源表面等面积权采样（薄壳用；对闭合网格也成立）
func _surface_samples(pts: PackedVector3Array, tris: PackedInt32Array,
		n: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var out := PackedVector3Array()
	var areas := PackedFloat32Array()
	var total := 0.0
	for i in range(0, tris.size(), 3):
		var a: Vector3 = pts[tris[i]]
		var area: float = (pts[tris[i + 1]] - a).cross(pts[tris[i + 2]] - a).length() * 0.5
		areas.append(area)
		total += area
	for i in n:
		var pick := rng.randf() * total
		var acc := 0.0
		var ti := 0
		for j in areas.size():
			acc += areas[j]
			if acc >= pick:
				ti = j
				break
		var a: Vector3 = pts[tris[ti * 3]]
		var b: Vector3 = pts[tris[ti * 3 + 1]]
		var c: Vector3 = pts[tris[ti * 3 + 2]]
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		out.append(a + (b - a) * u + (c - a) * v)
	return out


func _near_surface(pts: PackedVector3Array, tris: PackedInt32Array,
		p: Vector3, delta: float) -> bool:
	for i in range(0, tris.size(), 3):
		var q := Geometry3D.get_closest_point_to_segment_uncapped(p,
			pts[tris[i]], pts[tris[i + 1]])
		if p.distance_squared_to(q) <= delta * delta:
			return true
		q = Geometry3D.get_closest_point_to_segment_uncapped(p,
			pts[tris[i + 1]], pts[tris[i + 2]])
		if p.distance_squared_to(q) <= delta * delta:
			return true
		q = Geometry3D.get_closest_point_to_segment_uncapped(p,
			pts[tris[i + 2]], pts[tris[i]])
		if p.distance_squared_to(q) <= delta * delta:
			return true
		# 面心最近点
		q = _pt_tri(p, pts[tris[i]], pts[tris[i + 1]], pts[tris[i + 2]])
		if p.distance_squared_to(q) <= delta * delta:
			return true
	return false


static func _pt_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	var v := vb * denom
	var w := vc * denom
	return a + ab * v + ac * w


## 有符号间隙：到 proxy 表面的距离（内部 ≤0）
func _proxy_gap(proxy: BladeProxy, p: Vector3) -> float:
	var best := 1e9
	for piece in proxy.pieces:
		var ab: AABB = piece["aabb"]
		if p.x < ab.position.x - best or p.y < ab.position.y - best or p.z < ab.position.z - best:
			continue
		if p.x > ab.position.x + ab.size.x + best or p.y > ab.position.y + ab.size.y + best \
				or p.z > ab.position.z + ab.size.z + best:
			continue
		var d := _piece_gap(piece, p)
		best = minf(best, d)
		if best <= 0.0:
			return best
	return best


static func _piece_gap(piece: Dictionary, p: Vector3) -> float:
	var margin := INF
	var verts: PackedVector3Array = piece["v"]
	var tris: PackedInt32Array = piece["tris"]
	for plane: Plane in piece["planes"]:
		var d := plane.distance_to(p)
		if d > 0.0:
			# 外部点：margin 作废，去算到三角面的真实距离
			margin = -1.0
			break
		margin = minf(margin, -d)
	if margin >= 0.0:
		return -margin        # 内部：负值（浅入深度）
	var min_d := INF
	for i in range(0, tris.size(), 3):
		var q := _pt_tri(p, verts[tris[i]], verts[tris[i + 1]], verts[tris[i + 2]])
		min_d = minf(min_d, p.distance_to(q))
	return min_d


func _in_proxy(proxy: BladeProxy, p: Vector3) -> bool:
	return _proxy_gap(proxy, p) <= 0.0
