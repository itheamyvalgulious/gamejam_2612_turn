extends RefCounted
## HeadShape — procedural anime少女脸型 + 头皮基底 + 半透明黑面壳几何。
##
## 全部在 head 局部坐标系下生成（单位：真实米，head.scale = 1.0，torso.scale = 0.82
## 已在常量中补偿，因此局部 1.0 = 世界 0.82 m；此处局部高约 0.255 -> 世界约 0.209 m）。
## 朝向约定（与 VESPER 全身一致）：
##   -Z = 正面（脸朝向）
##   +Z = 后脑勺
##   +Y = 头顶
##   +X = 角色左侧（摄像头在 +X 侧，绿色指示灯在 -X 侧）

const TAU := PI * 2.0

# 局部 Y 从下巴 (-0.112) 到头顶 (+0.142)，总高 0.254（世界 0.208 m，约为旧版 0.49 m 的 42%，远小于 2/3）
const Y_BOTTOM := -0.112
const Y_TOP := 0.142

const P_Y := [
	-0.112, -0.108, -0.102, -0.094, -0.084, -0.072,
	-0.058, -0.042, -0.024, -0.004, 0.018, 0.040,
	0.062, 0.082, 0.100, 0.116, 0.128, 0.137, 0.142,
]
# 半宽：下巴尖窄 -> 下颌柔和展开 -> 颧骨饱满 -> 颅顶圆润收拢
const P_W := [
	0.004, 0.014, 0.026, 0.039, 0.052, 0.064,
	0.074, 0.082, 0.088, 0.092, 0.093, 0.091,
	0.087, 0.080, 0.070, 0.055, 0.037, 0.017, 0.002,
]
# 前深（朝 -Z 方向的距离）：下巴微翘 -> 脸颊柔和弧度 -> 额头饱满
const P_F := [
	0.018, 0.036, 0.055, 0.070, 0.082, 0.091,
	0.097, 0.101, 0.103, 0.104, 0.102, 0.098,
	0.091, 0.082, 0.070, 0.054, 0.036, 0.017, 0.002,
]
# 后深（朝 +Z 方向的距离）：脖颈上方内收 -> 后脑勺饱满圆润
const P_B := [
	0.012, 0.022, 0.036, 0.052, 0.068, 0.082,
	0.094, 0.104, 0.111, 0.115, 0.116, 0.113,
	0.106, 0.096, 0.082, 0.064, 0.043, 0.020, 0.002,
]

const EX := 1.15

# 少女面部起伏高斯核（中心在 -Z 正面）
static var BLOBS := [
	# 少女苹果肌 / 脸颊饱满度
	[Vector3(0.052, -0.032, -0.082), Vector3(0.034, 0.030, 0.028), 0.0065],
	[Vector3(-0.052, -0.032, -0.082), Vector3(0.034, 0.030, 0.028), 0.0065],
	# 精致下巴微凸
	[Vector3(0.0, -0.095, -0.066), Vector3(0.018, 0.016, 0.018), 0.0055],
	# 眼窝区域柔和内凹（让面壳内部的光学腔体更有立体感）
	[Vector3(0.0, 0.002, -0.098), Vector3(0.070, 0.064, 0.036), -0.0065],
	[Vector3(-0.052, -0.030, -0.088), Vector3(0.030, 0.024, 0.022), -0.0045],
	# 额弓微凸
	[Vector3(0.0, 0.036, -0.098), Vector3(0.052, 0.018, 0.020), 0.0032],
	# 太阳穴柔和内收
	[Vector3(0.080, 0.022, -0.045), Vector3(0.018, 0.025, 0.022), -0.0025],
	[Vector3(-0.080, 0.022, -0.045), Vector3(0.018, 0.025, 0.022), -0.0025],
]

static var _slopes: Array = []


static func _init_profile() -> void:
	if not _slopes.is_empty():
		return
	for arr in [P_W, P_F, P_B]:
		var n := P_Y.size()
		var m := []
		m.resize(n)
		for i in n:
			m[i] = 0.0
		var d := []
		d.resize(n - 1)
		for i in n - 1:
			d[i] = (arr[i + 1] - arr[i]) / (P_Y[i + 1] - P_Y[i])
		m[0] = d[0]
		m[n - 1] = d[n - 2]
		for i in range(1, n - 1):
			if d[i - 1] * d[i] <= 0.0:
				m[i] = 0.0
			else:
				var h0: float = P_Y[i] - P_Y[i - 1]
				var h1: float = P_Y[i + 1] - P_Y[i]
				var w1 := 2.0 * h1 + h0
				var w2 := h1 + 2.0 * h0
				m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
		_slopes.append(m)


static func _pchip(arr: Array, m: Array, y: float) -> float:
	var n := P_Y.size()
	if y <= P_Y[0]:
		return arr[0]
	if y >= P_Y[n - 1]:
		return arr[n - 1]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if P_Y[mid] <= y:
			lo = mid
		else:
			hi = mid
	var h: float = P_Y[hi] - P_Y[lo]
	var t: float = (y - float(P_Y[lo])) / h
	var t2 := t * t
	var t3 := t2 * t
	var h00 := 2.0 * t3 - 3.0 * t2 + 1.0
	var h10 := t3 - 2.0 * t2 + t
	var h01 := -2.0 * t3 + 3.0 * t2
	var h11 := t3 - t2
	return h00 * arr[lo] + h10 * h * m[lo] + h01 * arr[hi] + h11 * h * m[hi]


## 返回高度 y 处的 (半宽 W, 前深 F, 后深 B)
static func profile(y: float) -> Vector3:
	_init_profile()
	var w := _pchip(P_W, _slopes[0], y)
	var f := _pchip(P_F, _slopes[1], y)
	var b := _pchip(P_B, _slopes[2], y)
	return Vector3(maxf(w, 0.0005), maxf(f, 0.0005), maxf(b, 0.0005))


## phi 约定：phi = 0 为正后方 (+Z)，phi = PI / -PI 为正前方 (-Z)，phi = PI/2 为 +X
static func base_point(y: float, phi: float) -> Vector3:
	var pr := profile(y)
	var sx := sin(phi)
	var cz := cos(phi)
	var ax := pow(absf(sx), EX)
	var az := pow(absf(cz), EX)
	var x := pr.x * signf(sx) * ax
	# cz < 0 是正面 (-Z)，使用 pr.y (front depth)；cz >= 0 是背面 (+Z)，使用 pr.z (back depth)
	var z := (pr.z if cz >= 0.0 else pr.y) * signf(cz) * az
	return Vector3(x, y, z)


static func base_normal(y: float, phi: float) -> Vector3:
	var e := 0.002
	var dy := 0.002
	var p0 := base_point(y, phi)
	var pu := base_point(y, phi + e)
	var pv := base_point(y + dy, phi)
	# phi 增加时从 +Z 转到 +X 再到 -Z，(pu - p0) x (pv - p0) 指向外侧
	var n := (pu - p0).cross(pv - p0)
	var radial := Vector3(sin(phi), 0.0, cos(phi))
	if n.length_squared() < 1e-14:
		return radial.normalized()
	n = n.normalized()
	if n.dot(radial) < 0.0:
		n = -n
	return n


static func blob_disp(p: Vector3) -> float:
	var d := 0.0
	for b in BLOBS:
		var c: Vector3 = b[0]
		var s: Vector3 = b[1]
		var a: float = b[2]
		var qx := (p.x - c.x) / s.x
		var qy := (p.y - c.y) / s.y
		var qz := (p.z - c.z) / s.z
		var q := qx * qx + qy * qy + qz * qz
		if q > 12.0:
			continue
		d += a * exp(-0.5 * q)
	return d


static func surface_point(y: float, phi: float, scale := 1.0, offset := 0.0) -> Vector3:
	var p := base_point(y, phi)
	var n := base_normal(y, phi)
	return (p + n * blob_disp(p)) * scale + n * offset


static func surface_normal(y: float, phi: float) -> Vector3:
	var e := 0.0025
	var dy := 0.0025
	var p0 := surface_point(y, phi)
	var pu := surface_point(y, phi + e)
	var pv := surface_point(clampf(y + dy, Y_BOTTOM, Y_TOP), phi)
	var n := (pu - p0).cross(pv - p0)
	var bn := base_normal(y, phi)
	if n.length_squared() < 1e-14:
		return bn
	n = n.normalized()
	if n.dot(bn) < 0.0:
		n = -n
	return n


## 保证任意点 p 被推到少女头颅曲面外侧至少 clear 米
static func push_outside_head(p: Vector3, clear: float) -> Vector3:
	if p.y > Y_TOP - 0.012:
		var center := Vector3(0.0, 0.025, 0.005)
		var rx := 0.095 + clear
		var ry := 0.122 + clear
		var rz := 0.114 + clear
		var q := Vector3((p.x - center.x) / rx, (p.y - center.y) / ry, (p.z - center.z) / rz)
		var l := q.length()
		if l < 1.0 and l > 1e-6:
			q /= l
			return Vector3(center.x + q.x * rx, center.y + q.y * ry, center.z + q.z * rz)
		return p
	if p.y < Y_BOTTOM:
		return p
	var phi := atan2(p.x, p.z)
	var s := surface_point(p.y, phi)
	var rs := Vector2(s.x, s.z).length()
	var rp := Vector2(p.x, p.z).length()
	var want := rs + clear
	if rp < want:
		if rp < 1e-6:
			return Vector3(0.0, p.y, want)
		var k := want / rp
		return Vector3(p.x * k, p.y, p.z * k)
	return p


static func _emit_grid_mesh(rows: Array, norms: Array, uvs: Array, wrap_cols: bool,
		holes: Array = []) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_count := rows.size()
	var c_count: int = rows[0].size()
	var stride := c_count
	for r in r_count:
		for c in c_count:
			st.set_normal(norms[r][c])
			st.set_uv(uvs[r][c])
			st.add_vertex(rows[r][c])
	var quads_c := c_count if wrap_cols else c_count - 1
	for r in r_count - 1:
		for c in quads_c:
			var c1 := (c + 1) % c_count if wrap_cols else c + 1
			var i0 := r * stride + c
			var i1 := r * stride + c1
			var i2 := (r + 1) * stride + c1
			var i3 := (r + 1) * stride + c
			var p0: Vector3 = rows[r][c]
			var p1: Vector3 = rows[r][c1]
			var p2: Vector3 = rows[r + 1][c1]
			var p3: Vector3 = rows[r + 1][c]
			var qc := (p0 + p1 + p2 + p3) * 0.25
			var skip := false
			for h in holes:
				if qc.distance_to(h["center"]) < float(h["radius"]):
					skip = true
					break
			if skip:
				continue
			var guide: Vector3 = (norms[r][c] + norms[r][c1] + norms[r + 1][c1] + norms[r + 1][c])
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
	return st.commit()


## 内部深色少女脸基底（带摄像头与指示灯凹孔）
static func build_inner_skull(holes: Array = [], scale := 0.96, offset := 0.0) -> ArrayMesh:
	# 高分辨率内壳：腔口开孔边缘更圆滑，不会出现锯齿状黑边
	var r_steps := 72
	var c_steps := 112
	var rows := []
	var norms := []
	var uvs := []
	for r in r_steps + 1:
		var v := float(r) / float(r_steps)
		var y := lerpf(Y_BOTTOM + 0.002, Y_TOP - 0.002, v)
		var prow := []
		var nrow := []
		var urow := []
		for c in c_steps:
			var u := float(c) / float(c_steps)
			var phi := TAU * u
			prow.append(surface_point(y, phi, scale, offset))
			nrow.append(surface_normal(y, phi))
			urow.append(Vector2(u, v))
		rows.append(prow)
		norms.append(nrow)
		uvs.append(urow)
	return _emit_grid_mesh(rows, norms, uvs, true, holes)


## 前半张脸的半透明黑壳（少女脸型贴合面罩，只覆盖正前半部，从下巴到额头）
static func build_front_visor(offset := 0.0032) -> ArrayMesh:
	# 更高分辨率：玻璃高光/边缘不会再出现方块状锯齿
	var r_steps := 72
	var c_steps := 96
	var rows := []
	var norms := []
	var uvs := []
	# 正前方是 phi = PI (即 180°)。前半张脸取 phi in [PI - 1.50, PI + 1.50]（约 172° 弧度）
	var phi0 := PI - 1.50
	var phi1 := PI + 1.50
	for r in r_steps + 1:
		var v := float(r) / float(r_steps)
		var y := lerpf(Y_BOTTOM + 0.003, 0.082, v)
		var prow := []
		var nrow := []
		var urow := []
		for c in c_steps + 1:
			var u := float(c) / float(c_steps)
			var phi := lerpf(phi0, phi1, u)
			# 边缘微微内收贴合脸颊与下颌
			var edge_fade := sin(u * PI) * sin(clampf(v * 1.15, 0.05, 0.98) * PI)
			var cur_off := lerpf(0.0006, offset, pow(maxf(edge_fade, 0.0), 0.45))
			prow.append(surface_point(y, phi, 1.0, cur_off))
			nrow.append(surface_normal(y, phi))
			urow.append(Vector2(u, v))
		rows.append(prow)
		norms.append(nrow)
		uvs.append(urow)
	return _emit_grid_mesh(rows, norms, uvs, false)


## 参数化女性机甲上身曲面放样（腰 y=0.04 到领口 y=0.58，与直面装甲板无缝拼接）
static func build_feminine_torso_shell() -> Dictionary:
	# [y, 半宽 W, 前深 F (-Z), 后深 B (+Z), 截面超椭圆指数]
	var prof := [
		[0.035, 0.222, 0.165, 0.171, 1.30], # 腰座底部（衔接 pelvis，半径取上身/下身平均值）
		[0.085, 0.180, 0.144, 0.150, 1.25], # 下腰收窄
		[0.145, 0.120, 0.108, 0.113, 1.18], # 纤细蜂腰最窄处
		[0.215, 0.129, 0.113, 0.113, 1.20], # 下肋展开
		[0.285, 0.142, 0.118, 0.112, 1.25], # 胸下围托线
		[0.360, 0.168, 0.146, 0.124, 1.32], # 柔和立体胸甲曲线（一体成型，无贴球）
		[0.425, 0.174, 0.150, 0.128, 1.35], # 胸线顶点
		[0.485, 0.164, 0.122, 0.118, 1.28], # 上胸斜坡与锁骨平台
		[0.535, 0.132, 0.095, 0.096, 1.20], # 肩颈收口
		[0.575, 0.088, 0.072, 0.074, 1.12], # 领口环
	]
	var r_steps := 40
	var c_steps := 64
	var rows := []
	var norms := []
	var uvs := []

	for r in r_steps + 1:
		var v := float(r) / float(r_steps)
		var f_idx := v * float(prof.size() - 1)
		var i0 := clampi(int(floor(f_idx)), 0, prof.size() - 2)
		var u_t := f_idx - float(i0)
		var u_s := u_t * u_t * (3.0 - 2.0 * u_t)
		var p0: Array = prof[i0]
		var p1: Array = prof[i0 + 1]
		var y := lerpf(float(p0[0]), float(p1[0]), u_t)
		var w := lerpf(float(p0[1]), float(p1[1]), u_s)
		var fd := lerpf(float(p0[2]), float(p1[2]), u_s)
		var bd := lerpf(float(p0[3]), float(p1[3]), u_s)
		var ex := lerpf(float(p0[4]), float(p1[4]), u_s)

		var prow := []
		var urow := []
		for c in c_steps:
			var u := float(c) / float(c_steps)
			var phi := TAU * u # 0 = +Z (背), PI = -Z (前胸)
			var sx := sin(phi)
			var cz := cos(phi)
			var x := w * signf(sx) * pow(absf(sx), ex)
			var z := (bd if cz >= 0.0 else fd) * signf(cz) * pow(absf(cz), ex)

			# 在前胸 (cz < 0, y in 0.28..0.48) 加入柔和的一体化胸甲双峰雕塑起伏与中缝微凹，
			# 以及腹部马甲线微雕塑，全部在同一张连续参数曲面上完成
			if cz < 0.0:
				var bust_y := exp(-pow((y - 0.395) / 0.075, 2.0))
				var bust_x := exp(-pow((absf(x) - 0.072) / 0.062, 2.0))
				var sternum := exp(-pow(x / 0.024, 2.0)) * bust_y
				z -= 0.022 * bust_y * bust_x - 0.009 * sternum
				# 腹部中线装甲折棱
				var waist_y := exp(-pow((y - 0.18) / 0.09, 2.0))
				var ridge := maxf(0.0, 1.0 - absf(x) / 0.048) * waist_y
				z -= 0.008 * ridge
			else:
				# 背部脊椎装甲凹槽
				var spine := exp(-pow(x / 0.028, 2.0)) * smoothstep(0.08, 0.25, y) * (1.0 - smoothstep(0.45, 0.56, y))
				z -= 0.008 * spine

			prow.append(Vector3(x, y, z))
			urow.append(Vector2(u, v))
		rows.append(prow)
		uvs.append(urow)

	for r in r_steps + 1:
		var nrow := []
		var r0 := maxi(r - 1, 0)
		var r1 := mini(r + 1, r_steps)
		for c in c_steps:
			var c0 := (c - 1 + c_steps) % c_steps
			var c1 := (c + 1) % c_steps
			var du: Vector3 = rows[r][c1] - rows[r][c0]
			var dv: Vector3 = rows[r1][c] - rows[r0][c]
			var n := du.cross(dv).normalized()
			var radial := Vector3(rows[r][c].x, 0.0, rows[r][c].z)
			if n.dot(radial) < 0.0:
				n = -n
			nrow.append(n)
		norms.append(nrow)

	# 分离为两套材质网格：
	# 1. white_cuirass: 上胸甲 + 背甲 + 腰侧外甲（冷白主装甲）
	# 2. blue_bodysuit: 纤细蜂腰段与胸下束带、胸骨中缝（深海军蓝副装甲）
	var st_white := SurfaceTool.new()
	st_white.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_blue := SurfaceTool.new()
	st_blue.begin(Mesh.PRIMITIVE_TRIANGLES)

	for r in r_steps:
		var v_mid := (float(r) + 0.5) / float(r_steps)
		var y_mid := lerpf(0.035, 0.575, v_mid)
		for c in c_steps:
			var c1 := (c + 1) % c_steps
			var phi_mid := TAU * (float(c) + 0.5) / float(c_steps)
			var front_ang := absf(wrapf(phi_mid - PI, -PI, PI)) # 0 = 正前胸

			# 判定该面片属于冷白胸甲 (white) 还是深海蓝紧身腰甲/中缝 (blue)
			var is_white := true
			# 腰腹段整体回到冷白主装甲：旧版前白后深蓝的硬边界太生硬
			if y_mid >= 0.075 and y_mid <= 0.295:
				is_white = true
			# 上胸正中胸骨装甲缝与领口下沿为深海军蓝
			elif y_mid > 0.295 and y_mid < 0.49 and front_ang < 0.14:
				is_white = false
			elif y_mid >= 0.525:
				is_white = false

			var st := st_white if is_white else st_blue
			var p0: Vector3 = rows[r][c]
			var p1: Vector3 = rows[r][c1]
			var p2: Vector3 = rows[r + 1][c1]
			var p3: Vector3 = rows[r + 1][c]
			var n0: Vector3 = norms[r][c]
			var n1: Vector3 = norms[r][c1]
			var n2: Vector3 = norms[r + 1][c1]
			var n3: Vector3 = norms[r + 1][c]
			var uv0: Vector2 = uvs[r][c]
			var uv1: Vector2 = uvs[r][c1]
			var uv2: Vector2 = uvs[r + 1][c1]
			var uv3: Vector2 = uvs[r + 1][c]

			var guide := n0 + n1 + n2 + n3
			var g := (p1 - p0).cross(p2 - p0)
			if g.dot(guide) > 0.0:
				st.set_normal(n0); st.set_uv(uv0); st.add_vertex(p0)
				st.set_normal(n2); st.set_uv(uv2); st.add_vertex(p2)
				st.set_normal(n1); st.set_uv(uv1); st.add_vertex(p1)
				st.set_normal(n0); st.set_uv(uv0); st.add_vertex(p0)
				st.set_normal(n3); st.set_uv(uv3); st.add_vertex(p3)
				st.set_normal(n2); st.set_uv(uv2); st.add_vertex(p2)
			else:
				st.set_normal(n0); st.set_uv(uv0); st.add_vertex(p0)
				st.set_normal(n1); st.set_uv(uv1); st.add_vertex(p1)
				st.set_normal(n2); st.set_uv(uv2); st.add_vertex(p2)
				st.set_normal(n0); st.set_uv(uv0); st.add_vertex(p0)
				st.set_normal(n2); st.set_uv(uv2); st.add_vertex(p2)
				st.set_normal(n3); st.set_uv(uv3); st.add_vertex(p3)

	return {
		"white": st_white.commit(),
		"blue": st_blue.commit(),
	}


## 浓密头皮发壳（覆盖整个头顶、后脑勺、鬓角上方，与前额刘海和长发无缝融为一体）
## 发射与发流方向一致的 ARRAY_TANGENT，确保头皮基底也参与 Kajiya-Kay 各向异性高光。
static func build_scalp_hair_base() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_steps := 38
	var c_steps := 72
	var rows := []
	var norms := []
	var cols := []
	var uvs := []

	var c_root := Color(0.88, 0.91, 0.96, 1.0)
	var c_crown := Color(0.92, 0.94, 0.97, 1.0)

	for r in r_steps + 1:
		var v := float(r) / float(r_steps) # v=0 为发际线底部，v=1 为头顶百会穴
		var prow := []
		var nrow := []
		var crow := []
		var urow := []
		for c in c_steps:
			var u := float(c) / float(c_steps)
			var phi := TAU * u # 0 = +Z (后脑), PI = -Z (正前脸)
			var front_ang := absf(wrapf(phi - PI, -PI, PI))
			var deg := rad_to_deg(front_ang)

			var ymin := 0.074
			if deg > 40.0:
				ymin = lerpf(0.074, -0.036, smoothstep(40.0, 88.0, deg))
			if deg > 88.0:
				ymin = lerpf(-0.036, -0.088, smoothstep(88.0, 142.0, deg))

			var y := lerpf(ymin, Y_TOP - 0.0005, v)
			var nrm := surface_normal(y, phi)
			var edge_t := smoothstep(0.0, 0.22, v)
			var thick := lerpf(0.0020, 0.0042, edge_t)
			var p := surface_point(y, phi, 1.0, thick)
			if r == r_steps:
				p = Vector3(0.0, Y_TOP + 0.0042, 0.0)
				nrm = Vector3.UP
			prow.append(p)
			nrow.append(nrm)
			# UV.x 展开在 [0, 1]，UV.y 从发旋 (0) 流向发际线 (1)
			urow.append(Vector2(u, 1.0 - v))
			crow.append(c_crown.lerp(c_root, 1.0 - v))
		rows.append(prow)
		norms.append(nrow)
		cols.append(crow)
		uvs.append(urow)

	for r in r_steps + 1:
		var r_down := maxi(r - 1, 0)
		var r_up := mini(r + 1, r_steps)
		for c in c_steps:
			var tang: Vector3 = rows[r_down][c] - rows[r_up][c]
			if tang.length_squared() < 1e-10:
				tang = Vector3.DOWN
			tang = tang.normalized()
			st.set_normal(norms[r][c])
			st.set_tangent(Plane(tang.x, tang.y, tang.z, 1.0))
			st.set_color(cols[r][c])
			st.set_uv(uvs[r][c])
			st.set_uv2(Vector2(float(c) / float(c_steps), 0.5))
			st.add_vertex(rows[r][c])

	for r in r_steps:
		for c in c_steps:
			var c1 := (c + 1) % c_steps
			var i0 := r * c_steps + c
			var i1 := r * c_steps + c1
			var i2 := (r + 1) * c_steps + c1
			var i3 := (r + 1) * c_steps + c
			var p0: Vector3 = rows[r][c]
			var p1: Vector3 = rows[r][c1]
			var p2: Vector3 = rows[r + 1][c1]
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
	return st.commit()


## 头腔后内衬：只覆盖头的后半圈（phi 约 1.35..4.93），前端敞开给面罩。
## 漆黑色、不反光，保证从面罩外面透过玻璃只看到悬浮的恒星，看不到后脑壳、
## 脖子或任何内部零件；外侧仍然是头发。
static func build_cavity_liner(scale := 0.965, offset := 0.0) -> ArrayMesh:
	var r_steps := 40
	var c_steps := 96
	var rows := []
	var norms := []
	var uvs := []
	var phi0 := -1.55
	var phi1 := 1.55
	for r in r_steps + 1:
		var v := float(r) / float(r_steps)
		var y := lerpf(Y_BOTTOM + 0.002, Y_TOP - 0.002, v)
		var prow := []
		var nrow := []
		var urow := []
		for c in c_steps + 1:
			var u := float(c) / float(c_steps)
			var phi := lerpf(phi0, phi1, u)
			prow.append(surface_point(y, phi, scale, offset))
			# inward-facing normals: this is a cavity wall seen from inside
			nrow.append(-surface_normal(y, phi))
			urow.append(Vector2(u, v))
		rows.append(prow)
		norms.append(nrow)
		uvs.append(urow)
	return _emit_grid_mesh(rows, norms, uvs, false)
