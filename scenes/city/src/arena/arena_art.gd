extends RefCounted
## ArenaArt — 竞技场几何词汇表 + 三关卡调色板。
##
## 全部几何由 MB（顶点 CUSTOM0 携带材质参数）+ gfx/surface.gdshader 生成，
## 无任何外部模型/贴图。尺度单位 = 米，坐标系：+Y 上，-Z 为“面向场内”约定方向。
##
## 关键约定（与 ArenaKit.build 的冻结接口一致）：
##   inward : Vector2 —— 指向场地内侧的水平单位法线（俯视 x/z）
##   frame_basis(inward) 给出「X 沿墙宽、Y 竖直、Z 指向场内」的正交基
##   wall_quad/floor_rect 会自动修正顶点绕序，保证法线方向正确


# ------------------------------------------------------------------ 调色板
## 字段分四类：Environment（大气）、Light（光）、Tint（几何色，sRGB hex）、Weather。
## L1 冷紫 / L2 青绿霓虹 / L3 血红 + 白灯墙。
const PAL_ALLEY := {
	"amb_col": Color(0.105, 0.082, 0.175), "amb_energy": 0.42, "sky_contrib": 0.34,
	"exposure": 0.86, "contrast": 1.16, "sat": 1.06,
	"glow_intensity": 0.72, "glow_strength": 1.0, "glow_hdr": 0.95,
	"fog_col": Color(0.105, 0.055, 0.155), "fog_energy": 0.44,
	"fog_begin": 13.0, "fog_end": 118.0, "fog_curve": 1.0, "fog_density": 1.0,
	"fog_sky": 0.34, "fog_height": 12.0, "fog_height_density": 0.036,
	"ssao": 3.0,
	"sky_night": 1.0, "sky_gain": 0.44,
	"sky_zenith": Vector3(0.006, 0.010, 0.032), "sky_mid": Vector3(0.042, 0.035, 0.100),
	"sky_horizon": Vector3(0.260, 0.100, 0.170), "sky_glow": Vector3(0.300, 0.090, 0.260),
	"sky_smog": 0.72, "sky_cloud": 0.70, "sky_stars": 0.35, "moon_dir": Vector3(0.30, 0.42, -0.85),
	"key_col": Color(0.48, 0.46, 0.88), "key_energy": 0.19, "key_rot": Vector3(-20, 205, 0),
	"key_shadow": true, "shadow_dist": 140.0,
	"fill_col": Color(0.85, 0.35, 0.66), "fill_energy": 0.10,
	"wetness": 0.90,
	"rain_col": Color(0.66, 0.70, 0.98), "rain_alpha": 0.30,
	"asphalt": "454250", "concrete": "565260", "concrete_dark": "3a3843",
	"metal": "2a2d35", "metal_light": "6e7480", "rubber": "17181d", "wood": "4a3a2a",
	"wall": ["3d3750", "353043", "45404f", "2f2b3c"],
	"neon": ["ff2f7a", "c02fff", "2fd8ff", "ffb02f", "ff4a2f"],
	"warm": "ffc08a", "cool": "9ad8ff", "stripe": "d8c250", "paint": "b9b4ab",
}

const PAL_PLAZA := {
	"amb_col": Color(0.052, 0.120, 0.130), "amb_energy": 0.56, "sky_contrib": 0.34,
	"exposure": 0.82, "contrast": 1.18, "sat": 1.05,
	"glow_intensity": 0.78, "glow_strength": 1.02, "glow_hdr": 0.95,
	"fog_col": Color(0.045, 0.128, 0.140), "fog_energy": 0.50,
	"fog_begin": 40.0, "fog_end": 360.0, "fog_curve": 1.2, "fog_density": 1.0,
	"fog_sky": 0.26, "fog_height": 20.0, "fog_height_density": 0.030,
	"ssao": 2.8,
	"sky_night": 1.0, "sky_gain": 0.46,
	"sky_zenith": Vector3(0.005, 0.016, 0.024), "sky_mid": Vector3(0.022, 0.072, 0.094),
	"sky_horizon": Vector3(0.060, 0.240, 0.230), "sky_glow": Vector3(0.040, 0.300, 0.260),
	"sky_smog": 0.78, "sky_cloud": 0.85, "sky_stars": 0.22, "moon_dir": Vector3(-0.35, 0.40, 0.84),
	"key_col": Color(0.40, 0.72, 0.78), "key_energy": 0.22, "key_rot": Vector3(-26, 160, 0),
	"key_shadow": true, "shadow_dist": 200.0,
	"fill_col": Color(0.50, 0.95, 0.80), "fill_energy": 0.10,
	"wetness": 0.90,
	"rain_col": Color(0.62, 0.86, 0.95), "rain_alpha": 0.32,
	"asphalt": "3f4a4a", "concrete": "636d70", "concrete_dark": "3c4547",
	"metal": "262c30", "metal_light": "78868c", "rubber": "161a1c", "wood": "4a3a2a",
	"wall": ["39464a", "2f3a40", "44514f", "333d42"],
	"neon": ["2ff5cf", "2fd8ff", "8fff6a", "ffe32f", "ff2f7a"],
	"warm": "ffd7a0", "cool": "bafff0", "stripe": "d8c250", "paint": "c2c6c0",
}

const PAL_CHAMBER := {
	"amb_col": Color(0.105, 0.068, 0.070), "amb_energy": 0.62, "sky_contrib": 0.18,
	"exposure": 0.88, "contrast": 1.24, "sat": 0.99,
	"glow_intensity": 0.78, "glow_strength": 0.98, "glow_hdr": 1.02,
	"fog_col": Color(0.100, 0.040, 0.040), "fog_energy": 0.42,
	"fog_begin": 48.0, "fog_end": 260.0, "fog_curve": 1.1, "fog_density": 1.0,
	"fog_sky": 0.15, "fog_height": 10.0, "fog_height_density": 0.020,
	"ssao": 2.6,
	"sky_night": 1.0, "sky_gain": 0.30,
	"sky_zenith": Vector3(0.020, 0.004, 0.006), "sky_mid": Vector3(0.050, 0.010, 0.012),
	"sky_horizon": Vector3(0.120, 0.020, 0.020), "sky_glow": Vector3(0.160, 0.030, 0.030),
	"sky_smog": 0.85, "sky_cloud": 0.90, "sky_stars": 0.0, "moon_dir": Vector3(0.0, 0.95, 0.0),
	"key_col": Color(0.95, 0.55, 0.50), "key_energy": 0.10, "key_rot": Vector3(-84, 30, 0),
	"key_shadow": false, "shadow_dist": 80.0,
	"fill_col": Color(0.90, 0.35, 0.30), "fill_energy": 0.05,
	"wetness": 0.90,
	"rain_col": Color(0.95, 0.85, 0.85), "rain_alpha": 0.08,
	"asphalt": "3a3134", "concrete": "54454a", "concrete_dark": "322a2e",
	"metal": "2b2428", "metal_light": "6a5e62", "rubber": "171416", "wood": "3e2c26",
	"wall": ["876f68", "341a1c"],
	"neon": ["ff2a2a", "ff6a4a", "ffffff"],
	"warm": "ffe0c0", "cool": "e8f0ff", "stripe": "d8c250", "paint": "c8c2bc",
}

static func palette(kind: String) -> Dictionary:
	match kind:
		"plaza":
			return PAL_PLAZA
		"chamber":
			return PAL_CHAMBER
		_:
			return PAL_ALLEY


# ------------------------------------------------------------------ 基础几何
## 竖直墙面：法线朝 inward（指向场内）。a→b 顺序错会自动翻转。
static func wall_quad(mb: MB, a: Vector2, b: Vector2, y0: float, y1: float, inward: Vector2) -> void:
	if (b - a).dot(Vector2(inward.y, -inward.x)) < 0.0:
		var t := a
		a = b
		b = t
	mb.quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y),
		Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y))


## 水平地面片（法线 +Y）。r.position = (x, z)，r.size = (宽, 深)。
static func floor_rect(mb: MB, r: Rect2, y: float) -> void:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := x0 + r.size.x
	var z1 := z0 + r.size.y
	mb.quad(Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0))


## 天花板片（法线 -Y）。
static func ceil_rect(mb: MB, r: Rect2, y: float) -> void:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := x0 + r.size.x
	var z1 := z0 + r.size.y
	mb.quad(Vector3(x0, y, z1), Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1))


## 矩形体块（四壁 + 顶盖，无法线错误的棱柱）。
static func box_rect(mb: MB, r: Rect2, y0: float, y1: float, lid := true) -> void:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := x0 + r.size.x
	var z1 := z0 + r.size.y
	var poly := PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	mb.prism(poly, y0, y1, lid, false)


## 两圈同点数多边形之间的水平环带（女儿墙压顶、束带）。
static func poly_ring(mb: MB, outer: PackedVector2Array, inner: PackedVector2Array, y: float) -> void:
	var n := mini(outer.size(), inner.size())
	if n < 3:
		return
	for i in n:
		var a0 := outer[i]
		var a1 := outer[(i + 1) % n]
		var b0 := inner[i]
		var b1 := inner[(i + 1) % n]
		mb.quad(Vector3(a0.x, y, a0.y), Vector3(b0.x, y, b0.y),
			Vector3(b1.x, y, b1.y), Vector3(a1.x, y, a1.y))


static func rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(r.position.x, r.position.y),
		Vector2(r.position.x + r.size.x, r.position.y),
		Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
		Vector2(r.position.x, r.position.y + r.size.y)])


static func inset_rect(r: Rect2, d: float) -> Rect2:
	return Rect2(r.position + Vector2(d, d), r.size - Vector2(d * 2.0, d * 2.0))


## 「X 沿墙宽、Y 竖直、Z 指向场内」的正交基，与 wall_slots 的 xform 约定一致。
static func frame_basis(inward: Vector2) -> Basis:
	var iv := Vector3(inward.x, 0.0, inward.y).normalized()
	var tx := Vector3.UP.cross(iv).normalized()
	return Basis(tx, Vector3.UP, iv)


## 位置 + -Z 指向 target 的朝向（灯具 / 出生点 / 特写机位共用）。
static func facing(pos: Vector3, target: Vector3) -> Transform3D:
	var d := target - pos
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3.FORWARD
	return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), pos)


## wall_slot 数据：xform 局部 X 沿墙宽、Y 竖直、+Z 指向场内；plane 法线朝场内。
static func wall_slot(a: Vector2, b: Vector2, y0: float, y1: float, inward: Vector2) -> Dictionary:
	var c := (a + b) * 0.5
	var inner := inward.normalized()
	var xf := Transform3D(frame_basis(inner), Vector3(c.x, (y0 + y1) * 0.5, c.y))
	var n3 := Vector3(inner.x, 0.0, inner.y)
	return {
		"plane": Plane(n3, n3.dot(Vector3(c.x, 0.0, c.y))),
		"xform": xf,
		"size": Vector2(a.distance_to(b), y1 - y0),
	}


static func tint(pal: Dictionary, key: String) -> Color:
	return Mats.c(pal[key])


static func wall_col(pal: Dictionary, i: int) -> Color:
	var arr: Array = pal["wall"]
	return Mats.c(arr[posmod(i, arr.size())])


## 位置 + -Z 沿 pos→target（允许俯仰，给聚光灯用）
static func aim(pos: Vector3, target: Vector3) -> Transform3D:
	var d := target - pos
	if d.length_squared() < 1e-6:
		d = Vector3.FORWARD
	d = d.normalized()
	var z := -d
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	return Transform3D(Basis(x, y, z), pos)


static func neon_of(pal: Dictionary, i: int) -> Color:
	var arr: Array = pal["neon"]
	return Mats.c(arr[posmod(i, arr.size())])


# ------------------------------------------------------------------ 地面
## 地面基底 + 板缝 + 湿痕。all 覆盖整个场地；kerb 为可见的路缘石高度（0 = 无）。
static func ground_base(mb: MB, r: Rect2, pal: Dictionary, mat_id: int, col_key: String,
		seed := 0.0, y := 0.0) -> void:
	mb.setm(mat_id, tint(pal, col_key), seed)
	floor_rect(mb, r, y)
	# 沉降/污渍补丁：同族材质压暗，避免出现浅灰大斑
	mb.setm(mat_id, tint(pal, col_key) * 0.78, seed + 0.31)
	var rr := H.rng(int(r.position.x), int(r.position.y), 7717)
	for i in 5:
		var w := rr.randf_range(r.size.x * 0.05, r.size.x * 0.13)
		var d := rr.randf_range(r.size.y * 0.05, r.size.y * 0.13)
		var px := rr.randf_range(r.position.x + 1.0, r.position.x + r.size.x - 1.0)
		var pz := rr.randf_range(r.position.y + 1.0, r.position.y + r.size.y - 1.0)
		floor_rect(mb, Rect2(px - w * 0.5, pz - d * 0.5, w, d), y + 0.004)


## 路缘石 + 人行道台面（仅贴墙的外圈，战斗区保持平坦）
static func sidewalk(mb: MB, a: Vector2, b: Vector2, inward: Vector2, width: float,
		pal: Dictionary, seed := 0.0, rise := 0.15, mat_id := M.CONCRETE) -> void:
	if (b - a).dot(Vector2(inward.y, -inward.x)) < 0.0:
		var t := a
		a = b
		b = t
	# 台面（沿 inward 方向从墙内侧起 width 宽）
	var out_edge := a
	var in_edge := a + inward * width
	var b_out := b
	var b_in := b + inward * width
	mb.setm(mat_id, tint(pal, "concrete"), seed)
	mb.quad(Vector3(in_edge.x, rise, in_edge.y), Vector3(b_in.x, rise, b_in.y),
		Vector3(b_out.x, rise, b_out.y), Vector3(out_edge.x, rise, out_edge.y))
	mb.setm(mat_id, tint(pal, "concrete") * 1.08, seed + 0.13)
	mb.quad(Vector3(in_edge.x, 0.0, in_edge.y), Vector3(b_in.x, 0.0, b_in.y),
		Vector3(b_in.x, rise, b_in.y), Vector3(in_edge.x, rise, in_edge.y))
	# 排水沟（贴着路缘的暗槽）
	mb.setm(M.ASPHALT, tint(pal, "asphalt") * 0.7, seed + 0.5)
	var g0 := in_edge + inward * 0.05
	var g1 := b_in + inward * 0.05
	var g2 := b_in + inward * 0.45
	var g3 := in_edge + inward * 0.45
	mb.quad(Vector3(g0.x, 0.012, g0.y), Vector3(g1.x, 0.012, g1.y),
		Vector3(g2.x, 0.012, g2.y), Vector3(g3.x, 0.012, g3.y))


## 湿地水洼：独立网格（water.gdshader），镜像反射霓虹。
static func puddle(parent: Node3D, center: Vector3, radius: float, seed: int,
		mat: ShaderMaterial, y := 0.02) -> MeshInstance3D:
	var rng := H.rng(seed, 991, 17)
	var n := 18
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i in n:
		var ang := TAU * float(i) / float(n)
		var rr := radius * (0.62 + 0.55 * rng.randf())
		pts.append(Vector3(cos(ang) * rr, 0.0, sin(ang) * rr * 0.78))
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(a.x, a.z))
		st.add_vertex(a)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(b.x, b.z))
		st.add_vertex(b)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(Vector3.ZERO)
	var mi := MeshInstance3D.new()
	mi.name = "Puddle"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = center + Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(mi)
	return mi


## 地面标线（车道线、停止线、导向线）
static func paint_line(mb: MB, a: Vector2, b: Vector2, w: float, pal: Dictionary, y := 0.02) -> void:
	var d := b - a
	if d.length_squared() < 1e-6:
		return
	mb.setm(M.ROADPAINT, tint(pal, "paint"), 0.2)
	var n := Vector2(-d.y, d.x).normalized() * (w * 0.5)
	var p0 := a - n
	var p1 := a + n
	var p2 := b + n
	var p3 := b - n
	mb.quad(Vector3(p0.x, y, p0.y), Vector3(p3.x, y, p3.y),
		Vector3(p2.x, y, p2.y), Vector3(p1.x, y, p1.y))


static func paint_ring(mb: MB, c: Vector2, radius: float, width: float, pal: Dictionary,
		segs := 56, y := 0.02, col := "") -> void:
	if col == "":
		mb.setm(M.ROADPAINT, tint(pal, "paint"), 0.2)
	else:
		mb.setm(M.ROADPAINT, Mats.c(col), 0.2)
	var r0 := radius - width * 0.5
	var r1 := radius + width * 0.5
	for i in segs:
		var t0 := TAU * float(i) / float(segs)
		var t1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector2(cos(t0), sin(t0))
		var d1 := Vector2(cos(t1), sin(t1))
		var a := c + d0 * r0
		var b := c + d0 * r1
		var cc := c + d1 * r1
		var dd := c + d1 * r0
		mb.quad(Vector3(a.x, y, a.y), Vector3(dd.x, y, dd.y), Vector3(cc.x, y, cc.y), Vector3(b.x, y, b.y))


# ------------------------------------------------------------------ 立面 / 楼体
## 边界楼体：内立面沿 a→b（朝 inward），向场外延伸 depth。
## opts: ground = "service"|"arcade"|"blank"，bands = 立面束带数，signs = 是否挂招牌。
static func facade_block(mb: MB, a: Vector2, b: Vector2, inward: Vector2, depth: float,
		h: float, pal: Dictionary, rng: RandomNumberGenerator, style: float,
		col: Color, opts := {}) -> void:
	var n := inward.normalized()
	var L := a.distance_to(b)
	if L < 1.0:
		return
	var sd := rng.randf()
	var base := Vector3(a.x, 0.0, a.y)
	var th := Vector3(n.y, 0.0, -n.x)   # 沿墙方向（a→b 可能反向，下面统一）
	if (b - a).normalized().dot(Vector2(th.x, th.z)) < 0.0:
		th = -th
	var ground_h: float = opts.get("ground_h", 4.8 if opts.get("ground", "service") == "service" else 5.6)

	# --- 体量：向内立面后方挤出的矩形块
	# 体量面比内立面退后 5 cm：避免与下面的立面细节片共面导致 z-fighting（竖向条带/斑块）
	var out_a := a - n * depth
	var out_b := b - n * depth
	var shell_a := a - n * 0.05
	var shell_b := b - n * 0.05
	var quad4 := PackedVector2Array([shell_a, shell_b, out_b, out_a])
	mb.setm(M.WALL, col * 0.82, sd, 0.0, style)
	mb.prism(quad4, 0.0, h, true, false)

	# --- 内立面：勒脚 / 底层 / 主立面 / 檐口
	mb.setm(M.CONCRETE, tint(pal, "concrete_dark"), sd)
	wall_quad(mb, a, b, 0.0, 0.52, n)
	match String(opts.get("ground", "service")):
		"arcade":
			arcade_band(mb, a, b, n, 0.52, ground_h, pal, rng, sd)
		"blank":
			mb.setm(M.WALL, col * 0.7, sd, 0.0, 50.0)
			wall_quad(mb, a, b, 0.52, ground_h, n)
		_:
			service_band(mb, a, b, n, 0.52, ground_h, pal, rng, sd)
	mb.setm(M.WALL, col, sd, 0.0, style)
	wall_quad(mb, a, b, ground_h, h - 1.15, n)
	# 檐口（无窗实墙带）
	mb.setm(M.WALL, col * 0.88, sd + 0.07, 0.0, 50.0)
	wall_quad(mb, a, b, h - 1.15, h, n)
	# 两端竖向壁柱，读作分栋缝
	mb.setm(M.CONCRETE, tint(pal, "concrete") * 0.9, sd + 0.21)
	for p in [a, b]:
		var pv: Vector2 = p + n * 0.16
		mb.quad(Vector3(pv.x - th.x * 0.34, ground_h, pv.y - th.z * 0.34),
			Vector3(pv.x + th.x * 0.34, ground_h, pv.y + th.z * 0.34),
			Vector3(pv.x + th.x * 0.34, h, pv.y + th.z * 0.34),
			Vector3(pv.x - th.x * 0.34, h, pv.y - th.z * 0.34))

	# --- 立面束带：把 30 m 高的墙切成有节奏的层次
	var bands: int = opts.get("bands", 0)
	for i in bands:
		var by: float = lerpf(ground_h + 3.0, h - 3.0, float(i + 1) / float(bands + 1))
		mb.setm(M.CONCRETE, tint(pal, "concrete") * (0.85 + 0.1 * rng.randf()), sd + 0.13 * (i + 1))
		wall_quad(mb, a, b, by, by + 0.5, n)

	# --- 屋顶：女儿墙 + 杂物
	var rmin := Vector2(minf(a.x, minf(b.x, minf(out_a.x, out_b.x))),
		minf(a.y, minf(b.y, minf(out_a.y, out_b.y))))
	var rmax := Vector2(maxf(a.x, maxf(b.x, maxf(out_a.x, out_b.x))),
		maxf(a.y, maxf(b.y, maxf(out_a.y, out_b.y))))
	roof_clutter(mb, Rect2(rmin, rmax - rmin), h, pal, rng, sd, opts.get("tall", false))


## 屋顶：女儿墙圈 + 设备箱 + 水箱 + 天线，远看给天际线加毛边。
static func roof_clutter(mb: MB, r: Rect2, top: float, pal: Dictionary,
		rng: RandomNumberGenerator, sd: float, tall := false) -> void:
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	var inner := inset_rect(r, 0.45)
	var outer := rect_poly(r)
	var ip := rect_poly(inner)
	mb.setm(M.CONCRETE, tint(pal, "concrete") * 0.88, sd)
	mb.prism(ip, top, top + 0.72, false, false)
	poly_ring(mb, outer, ip, top + 0.72)
	mb.setm(M.CONCRETE, tint(pal, "concrete_dark"), sd)
	floor_rect(mb, inner, top + 0.1)
	var n := rng.randi_range(3, 6)
	for i in n:
		var w := rng.randf_range(1.2, 3.4)
		var d := rng.randf_range(1.0, 2.6)
		var hh := rng.randf_range(0.7, 2.2)
		var px := rng.randf_range(inner.position.x + 1.0, inner.position.x + inner.size.x - 1.0)
		var pz := rng.randf_range(inner.position.y + 1.0, inner.position.y + inner.size.y - 1.0)
		mb.setm(M.METAL, tint(pal, "metal_light") * rng.randf_range(0.5, 0.8), sd + 0.11 * i)
		mb.box(Vector3(px, top + 0.1 + hh * 0.5, pz), Vector3(w, hh, d))
		if rng.randf() < 0.45:
			mb.setm(M.METAL, tint(pal, "metal"), sd + 0.13 * i)
			mb.cyl_y(Vector3(px, top + 0.1 + hh + 0.14, pz), minf(w, d) * 0.34, 0.28, 10, true)
	if tall or rng.randf() < 0.5:
		mb.setm(M.METAL, tint(pal, "metal"), sd + 0.5)
		var mh := rng.randf_range(4.0, 11.0)
		var c := r.position + r.size * 0.5
		mb.cyl_y(Vector3(c.x, top + mh * 0.5, c.y), 0.13, mh, 6, true)
		mb.setm(M.EMIT, Mats.c("ff2030"), sd + 0.6, 2.2)
		mb.box(Vector3(c.x, top + mh + 0.2, c.y), Vector3(0.34, 0.34, 0.34))


## 远景楼：只做体量 + 台阶退台 + 亮窗（shader 立面），投影关闭由调用方处理。
static func skyline_tower(mb: MB, c: Vector2, w: float, d: float, h: float,
		pal: Dictionary, rng: RandomNumberGenerator, style: float, col: Color) -> void:
	var sd := rng.randf()
	var y := 0.0
	var cw := w
	var cd := d
	var segs := 1 if rng.randf() > 0.6 else 2
	for s in segs:
		var sh: float = h * (0.62 if s == 0 and segs > 1 else 1.0)
		if s > 0:
			sh = h - y
		mb.setm(M.WALL, col * (0.9 + 0.12 * s), sd + 0.09 * s, 0.0, style)
		box_rect(mb, Rect2(c.x - cw * 0.5, c.y - cd * 0.5, cw, cd), y, y + sh, true)
		# 层间束带
		if style < 9.5 and rng.randf() < 0.7:
			mb.setm(M.CONCRETE, tint(pal, "concrete_dark"), sd + 0.31)
			box_rect(mb, Rect2(c.x - cw * 0.5 - 0.15, c.y - cd * 0.5 - 0.15, cw + 0.3, cd + 0.3),
				y + sh - 0.9, y + sh - 0.3, true)
		y += sh
		cw *= 0.72
		cd *= 0.72
	if h > 90.0:
		mb.setm(M.EMIT, Mats.c("ff2a30"), sd + 0.4, 2.0)
		mb.box(Vector3(c.x, h + 0.4, c.y), Vector3(0.6, 0.5, 0.6))
		mb.setm(M.METAL, tint(pal, "metal"), sd + 0.42)
		mb.cyl_y(Vector3(c.x, h + 4.0, c.y), 0.16, 7.0, 6, true)


# ------------------------------------------------------------------ 底层带
## 后巷服务带：卷帘门 / 铁门 / 铁栏小窗 / 管线，间或一扇漏光的门。
static func service_band(mb: MB, a: Vector2, b: Vector2, n: Vector2, y0: float, y1: float,
		pal: Dictionary, rng: RandomNumberGenerator, sd: float) -> void:
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var th := Vector3(dir.x, 0.0, dir.y)
	var base := Vector3(a.x, 0.0, a.y)
	var h := y1 - y0
	# 抹灰底（无窗实墙）
	mb.setm(M.WALL, Mats.jitter(rng, tint(pal, "concrete") * 0.55, 0.05), sd, 0.0, 50.0)
	wall_quad(mb, a, b, y0, y1, n)
	var bays := maxi(1, int(round(L / 4.4)))
	var bw := L / float(bays)
	for i in bays:
		var t0 := bw * float(i)
		var c2 := base + th * (t0 + bw * 0.5)
		var kind := rng.randf()
		if kind < 0.34:
			# 卷帘门
			var dw := bw - 0.5
			mb.setm(M.METAL, tint(pal, "metal_light") * rng.randf_range(0.45, 0.62), sd + 0.03 * i)
			wall_quad(mb, Vector2(c2.x, c2.z) - Vector2(th.x, th.z) * dw * 0.5,
				Vector2(c2.x, c2.z) + Vector2(th.x, th.z) * dw * 0.5, y0 + 0.25, y0 + 3.5, n)
			# 卷帘横纹
			mb.setm(M.METAL, tint(pal, "metal"), sd + 0.05 * i)
			var yy := y0 + 0.45
			while yy < y0 + 3.4:
				mb.quad(c2 + n3(th, -dw * 0.5) + Vector3(0, yy, 0) + n3v(n, 0.03),
					c2 + n3(th, dw * 0.5) + Vector3(0, yy, 0) + n3v(n, 0.03),
					c2 + n3(th, dw * 0.5) + Vector3(0, yy + 0.06, 0) + n3v(n, 0.03),
					c2 + n3(th, -dw * 0.5) + Vector3(0, yy + 0.06, 0) + n3v(n, 0.03))
				yy += 0.34
			mb.setm(M.EMIT, Mats.c(pal["warm"]), sd + 0.07 * i, 1.5)
			mb.box(c2 + n3v(n, 0.25) + Vector3(0, y0 + 3.75, 0), Vector3(0.9, 0.1, 0.16))
		elif kind < 0.62:
			# 铁门 + 门头灯
			var dw2 := 1.35
			mb.setm(M.METAL, tint(pal, "metal"), sd + 0.11 * i)
			wall_quad(mb, Vector2(c2.x, c2.z) - Vector2(th.x, th.z) * dw2 * 0.5,
				Vector2(c2.x, c2.z) + Vector2(th.x, th.z) * dw2 * 0.5, y0 + 0.1, y0 + 2.35, n)
			mb.setm(M.EMIT, Mats.c(pal["warm"]), sd + 0.13 * i, 1.9)
			mb.box(c2 + n3v(n, 0.2) + Vector3(0, y0 + 2.65, 0), Vector3(0.55, 0.1, 0.2))
		elif kind < 0.8:
			# 铁栏小窗
			var ww := 1.1
			mb.setm(M.METAL, tint(pal, "metal"), sd + 0.17 * i)
			wall_quad(mb, Vector2(c2.x, c2.z) - Vector2(th.x, th.z) * ww * 0.5,
				Vector2(c2.x, c2.z) + Vector2(th.x, th.z) * ww * 0.5, y0 + 1.4, y0 + 2.4, n)
			mb.setm(M.EMIT, neon_of(pal, i + 1) * 0.5, sd + 0.19 * i, 0.5)
			wall_quad(mb, Vector2(c2.x, c2.z) - Vector2(th.x, th.z) * ww * 0.5,
				Vector2(c2.x, c2.z) + Vector2(th.x, th.z) * ww * 0.5, y0 + 1.4, y0 + 2.4, n)
		# 分隔柱
		mb.setm(M.CONCRETE, tint(pal, "concrete") * 0.8, sd + 0.23 * i)
		mb.box(Vector3(base.x, 0, base.z) + th * t0 + n3v(n, 0.18) + Vector3(0, (y0 + h) * 0.5, 0),
			Vector3(0.36, h, 0.36))
	# 横向线管 + 接线盒 + 分缝：近场（1.5~3 m）可读的尺度
	var pipe_col := tint(pal, "metal_light") * 0.42
	for yy in [1.2, 3.62]:
		pipe_run(mb, base + th * 0.35 + n3v(n, 0.10) + Vector3(0, yy, 0),
			base + th * (L - 0.35) + n3v(n, 0.10) + Vector3(0, yy, 0), 0.045, pipe_col, pal, sd + 0.4)
		mb.setm(M.METAL, tint(pal, "metal") * 1.3, sd + 0.42)
		var bx := maxi(2, int(L / 6.5))
		for bi in bx:
			var bp := base + th * (L * (float(bi) + 0.5) / float(bx)) + n3v(n, 0.12) + Vector3(0, yy, 0)
			mb.box(bp, Vector3(0.3, 0.4, 0.22))
	# 水平分缝（两块墙板的分界）
	mb.setm(M.CONCRETE, tint(pal, "concrete_dark") * 1.3, sd + 0.44)
	wall_quad(mb, a, b, 2.55, 2.63, n)
	# 墙脚污渍带
	mb.setm(M.SOIL, tint(pal, "concrete_dark") * 0.6, sd + 0.46)
	wall_quad(mb, a, b, 0.52, 0.86, n)

	# 墙面霓虹刀牌
	if L > 8.0 and rng.randf() < 0.85:
		var t := L * rng.randf_range(0.25, 0.75)
		var p := base + th * t + n3v(n, 0.0) + Vector3(0, y0 + rng.randf_range(1.2, 2.2), 0)
		neon_blade(mb, p, n, rng.randf_range(0.6, 1.0), rng.randf_range(2.2, 3.6),
			neon_of(pal, int(sd * 100.0)), pal, sd)


## 广场拱廊：柱列 + 橱窗 + 招牌带 + 遮阳篷 + 广告屏。
static func arcade_band(mb: MB, a: Vector2, b: Vector2, n: Vector2, y0: float, y1: float,
		pal: Dictionary, rng: RandomNumberGenerator, sd: float) -> void:
	var L := a.distance_to(b)
	if L < 2.0:
		return
	var dir := (b - a) / L
	var th := Vector3(dir.x, 0.0, dir.y)
	var base := Vector3(a.x, 0.0, a.y)
	var h := y1 - y0
	# 拱廊内侧背景墙（暖色，作为橱窗背光）
	mb.setm(M.WALL, tint(pal, "concrete") * 0.5, sd, 0.0, 50.0)
	wall_quad(mb, a + n * 1.5, b + n * 1.5, y0, y1, n)
	var cols := maxi(2, int(round(L / 5.6)))
	var cw := L / float(cols)
	for i in cols:
		var t0 := cw * float(i)
		var c2 := base + th * (t0 + cw * 0.5)
		var g0 := base + th * (t0 + 0.55)
		var g1 := base + th * (t0 + cw - 0.55)
		# 橱窗玻璃 + 背光货架
		mb.setm(M.GLASS, Color(0.18, 0.24, 0.26), sd + 0.07 * i)
		mb.sty = 2.0
		wall_quad(mb, Vector2(g0.x, g0.z) + n * 0.35, Vector2(g1.x, g1.z) + n * 0.35,
			y0 + 0.25, y1 - 1.5, n)
		mb.setm(M.EMIT, Mats.c(pal["warm"]) * 0.8, sd + 0.09 * i, 1.15)
		wall_quad(mb, Vector2(g0.x, g0.z) + n * 0.95, Vector2(g1.x, g1.z) + n * 0.95,
			y0 + 0.3, y1 - 1.9, n)
		# 货架层板
		mb.setm(M.WALL, tint(pal, "metal") * 0.9, sd + 0.11 * i, 0.0, 52.0)
		var sy := y0 + 0.95
		while sy < y1 - 2.1:
			wall_quad(mb, Vector2(g0.x, g0.z) + n * 0.7, Vector2(g1.x, g1.z) + n * 0.7, sy, sy + 0.07, n)
			sy += 0.85
		# 柱
		mb.setm(M.CONCRETE, tint(pal, "concrete") * 1.05, sd + 0.13 * i)
		mb.box(base + th * (t0 + 0.28) + n3v(n, 0.3) + Vector3(0, h * 0.5, 0),
			Vector3(0.56, h, 0.9))
		# 柱脚霓虹环
		mb.setm(M.EMIT, neon_of(pal, i), sd + 0.15 * i, 2.6)
		mb.box(base + th * (t0 + 0.28) + n3v(n, 0.3) + Vector3(0, y0 + 0.45, 0),
			Vector3(0.62, 0.08, 0.96))
		# 招牌带
		mb.setm(M.EMIT, neon_of(pal, i + 2), sd + 0.17 * i, 2.2)
		wall_quad(mb, Vector2(g0.x, g0.z) + n * 0.24, Vector2(g1.x, g1.z) + n * 0.24,
			y1 - 1.45, y1 - 0.75, n)
		# 遮阳篷
		if rng.randf() < 0.6:
			var col := Mats.c("5c2430") if rng.randf() < 0.5 else Mats.c("1f3c40")
			mb.setm(M.FABRIC, col, rng.randf())
			var aw := cw * 0.8
			var ca := base + th * (t0 + cw * 0.5)
			mb.quad_n(ca - th * (aw * 0.5) + Vector3(0, y1 - 1.5, 0) + n3v(n, 0.2),
				ca + th * (aw * 0.5) + Vector3(0, y1 - 1.5, 0) + n3v(n, 0.2),
				ca + th * (aw * 0.5) + n3v(n, 2.2) + Vector3(0, y1 - 2.1, 0),
				ca - th * (aw * 0.5) + n3v(n, 2.2) + Vector3(0, y1 - 2.1, 0), Vector3.UP)
	# 拱廊顶板（柱列上方，形成有阴影的骑楼）：底面朝下的平板
	mb.setm(M.CONCRETE, tint(pal, "concrete") * 0.8, sd + 0.3)
	var sa := a
	var sb := b
	if (b - a).dot(Vector2(n.y, -n.x)) < 0.0:
		sa = b
		sb = a
	var s0 := sa
	var s1 := sa + n * 2.6
	var s2 := sb + n * 2.6
	var s3 := sb
	mb.quad(Vector3(s0.x, y1 - 0.12, s0.y), Vector3(s3.x, y1 - 0.12, s3.y),
		Vector3(s2.x, y1 - 0.12, s2.y), Vector3(s1.x, y1 - 0.12, s1.y))
	# 顶板外沿
	mb.setm(M.CONCRETE, tint(pal, "concrete") * 0.95, sd + 0.31)
	wall_quad(mb, s1, s2, y1 - 0.42, y1 + 0.1, n)
	mb.setm(M.EMIT, Mats.c(pal["cool"]) * 0.92, sd + 0.33, 2.2)
	for i in cols:
		var c3 := base + th * (cw * (float(i) + 0.5))
		mb.box(c3 + n3v(n, 1.2) + Vector3(0, y1 - 0.32, 0), Vector3(0.5, 0.06, 0.5))
	# 顶部广告屏
	big_screen(mb, base + th * (L * 0.5) + n3v(n, 0.3) + Vector3(0, y1 + 5.0, 0), n,
		minf(L * 0.62, 11.0), 4.2, pal, rng, sd)


## 霓虹刀牌（垂直于墙、双面）
static func neon_blade(mb: MB, at: Vector3, n: Vector2, w: float, h: float,
		col: Color, pal: Dictionary, sd: float) -> void:
	var th := Vector3(n.y, 0.0, -n.x)
	var iv := Vector3(n.x, 0.0, n.y)
	var a0 := at + iv * 0.12
	var a1 := at + iv * (0.12 + w)
	var s := th * 0.07
	mb.setm(M.EMIT, col, sd, 3.0)
	var p0 := a0 - s
	var p1 := a1 - s
	mb.quad(p0, p1, p1 + Vector3(0, h, 0), p0 + Vector3(0, h, 0))
	var q0 := a0 + s
	var q1 := a1 + s
	mb.quad(q0 + Vector3(0, h, 0), q1 + Vector3(0, h, 0), q1, q0)
	# 金属框 + 吊臂
	mb.setm(M.METAL, tint(pal, "metal"), sd + 0.1)
	mb.box(at + iv * (0.12 + w * 0.5) + Vector3(0, h * 0.5, 0),
		Vector3(absf(iv.x) * w + absf(th.x) * 0.1 + 0.06, h + 0.24, absf(iv.z) * w + absf(th.z) * 0.1 + 0.06))
	mb.box_frame(at + iv * 0.05 + Vector3(0, h - 0.3, 0), at + iv * (0.12 + w * 0.6) + Vector3(0, h - 0.3, 0), 0.08)


## 大幅广告屏（animate M.SCREEN）+ 边框
static func big_screen(mb: MB, at: Vector3, n: Vector2, w: float, h: float,
		pal: Dictionary, rng: RandomNumberGenerator, sd: float) -> void:
	var th := Vector3(n.y, 0.0, -n.x)
	mb.setm(M.METAL, tint(pal, "metal"), sd)
	mb.box(at + n3v(n, -0.25), Vector3(absf(th.x) * (w + 0.6) + absf(n.x) * 0.5 + 0.05, h + 0.6,
		absf(th.z) * (w + 0.6) + absf(n.y) * 0.5 + 0.05))
	mb.setm(M.SCREEN, neon_of(pal, 2), sd + 0.13)
	wall_quad(mb, Vector2(at.x, at.z) - Vector2(th.x, th.z) * w * 0.5,
		Vector2(at.x, at.z) + Vector2(th.x, th.z) * w * 0.5, at.y - h * 0.5, at.y + h * 0.5, n)


# ------------------------------------------------------------------ 小道具
static func n3(t: Vector3, s: float) -> Vector3:
	return t * s


static func n3v(n: Vector2, s: float) -> Vector3:
	return Vector3(n.x * s, 0.0, n.y * s)


## 挂墙管线（横管 + 支架）
static func pipe_run(mb: MB, a: Vector3, b: Vector3, r: float, col: Color, pal: Dictionary,
		seed := 0.0) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.2:
		return
	var dir := d / L
	mb.setm(M.METAL, col, seed)
	var path := PackedVector3Array()
	var n := maxi(2, int(L / 1.6))
	for i in n + 1:
		path.append(a + dir * (L * float(i) / float(n)))
	mb.tube(path, r, 6, false)
	mb.setm(M.METAL, tint(pal, "metal") * 1.2, seed + 0.1)
	var steps := maxi(1, int(L / 2.4))
	for i in steps:
		var p := a + dir * (L * (float(i) + 0.5) / float(steps))
		mb.box(p, Vector3(0.1, 0.1, 0.1))


## 落水管（竖管 + 卡箍 + 弯头）
static func drainpipe(mb: MB, p: Vector3, n: Vector2, h: float, r: float, col: Color,
		pal: Dictionary, seed := 0.0) -> void:
	var iv := Vector3(n.x, 0.0, n.y)
	mb.setm(M.METAL, col, seed)
	mb.cyl_y(p + iv * 0.2 + Vector3(0, h * 0.5, 0), r, h, 8, true)
	mb.box(p + iv * 0.2 + Vector3(0, 0.12, 0), Vector3(0.3, 0.24, 0.3))
	mb.setm(M.METAL, tint(pal, "metal") * 1.3, seed + 0.13)
	var y := 1.6
	while y < h - 0.4:
		mb.box(p + iv * 0.14 + Vector3(0, y, 0), Vector3(0.16, 0.08, 0.16))
		mb.box(p + iv * 0.28 + Vector3(0, y, 0), Vector3(0.06, 0.06, 0.06))
		y += 2.4


## 外挂空调机组（带滴痕）
static func ac_unit(mb: MB, p: Vector3, n: Vector2, pal: Dictionary,
		rng: RandomNumberGenerator, seed := 0.0) -> void:
	var b := frame_basis(n)
	mb.push(Transform3D(b, p))
	mb.setm(M.METAL, tint(pal, "metal_light") * rng.randf_range(0.55, 0.75), seed)
	mb.box(Vector3(0, 0, 0.3), Vector3(0.92, 0.62, 0.6))
	mb.setm(M.METAL, tint(pal, "metal"), seed + 0.09)
	mb.box(Vector3(0.12, 0, 0.58), Vector3(0.62, 0.5, 0.05))
	mb.box(Vector3(0, -0.42, 0.36), Vector3(0.7, 0.06, 0.5))
	# 风盘
	mb.setm(M.METAL, tint(pal, "metal") * 0.7, seed + 0.13)
	mb.cyl_y(Vector3(-0.12, 0, 0.58), 0.2, 0.03, 10, true)
	# 托架
	mb.setm(M.METAL, tint(pal, "metal"), seed + 0.17)
	mb.box(Vector3(0, -0.38, 0.12), Vector3(1.0, 0.08, 0.5))
	mb.pop()


## 铁爬梯
static func ladder(mb: MB, p: Vector3, n: Vector2, h: float, pal: Dictionary, seed := 0.0) -> void:
	var b := frame_basis(n)
	mb.push(Transform3D(b, p))
	mb.setm(M.METAL, tint(pal, "metal_light") * 0.55, seed)
	var w := 0.42
	mb.box(Vector3(-w * 0.5, h * 0.5, 0.16), Vector3(0.06, h, 0.06))
	mb.box(Vector3(w * 0.5, h * 0.5, 0.16), Vector3(0.06, h, 0.06))
	var y := 0.5
	while y < h - 0.2:
		mb.box(Vector3(0, y, 0.16), Vector3(w, 0.05, 0.05))
		y += 0.34
	mb.pop()


## 室外消防梯：平台 + 栏杆 + 之字梯段
static func fire_escape(mb: MB, a: Vector2, b: Vector2, n: Vector2, y: float,
		pal: Dictionary, rng: RandomNumberGenerator, seed := 0.0) -> void:
	var L := a.distance_to(b)
	if L < 2.0:
		return
	var dir := (b - a) / L
	var th := Vector3(dir.x, 0.0, dir.y)
	var base := Vector3(a.x, y, a.y)
	var iv := Vector3(n.x, 0.0, n.y)
	mb.setm(M.METAL, tint(pal, "metal_light") * 0.5, seed)
	# 平台
	var w := minf(L, 5.0)
	var c := base + th * (L * 0.5)
	mb.box(c + iv * 0.7, Vector3(absf(th.x) * w + 0.1, 0.1, absf(th.z) * w + 0.1))
	# 栏杆
	for sy in [0.55, 1.05]:
		mb.box(c + iv * 1.28 + Vector3(0, sy, 0), Vector3(absf(th.x) * w + 0.08, 0.05, absf(th.z) * w + 0.08))
	for i in 3:
		var p := base + th * (L * (float(i) + 0.5) / 3.0) + iv * 1.28
		mb.box(p + Vector3(0, 0.55, 0), Vector3(0.05, 1.1, 0.05))
	# 斜梯段
	var st0 := base + th * 0.2 + iv * 0.9
	var st1 := base + th * (L - 0.2) + iv * 0.9
	var steps := maxi(4, int(L))
	for i in steps:
		var t := float(i) / float(steps)
		var p := st0.lerp(st1, t)
		p.y = base.y - 2.6 * (1.0 - t) + 0.1
		mb.box(p, Vector3(absf(th.x) * (L / steps) + 0.06, 0.05, absf(th.z) * (L / steps) + 0.3))
	mb.box_frame(st0 + Vector3(0, -2.5, 0), st0, 0.07)
	mb.box_frame(st1 + Vector3(0, -2.5, 0), st1, 0.07)
	# 落地爬梯
	mb.setm(M.METAL, tint(pal, "metal_light") * 0.42, seed + 0.2)
	mb.box_frame(Vector3(c.x, y - 4.0, c.z) + iv * 0.9, c + iv * 0.9, 0.09)


## 木箱 / 塑箱（可堆叠）
static func crate(mb: MB, p: Vector3, size: Vector3, yaw: float, pal: Dictionary,
		rng: RandomNumberGenerator, seed := 0.0, plastic := false) -> void:
	var b := Basis(Vector3.UP, yaw)
	mb.push(Transform3D(b, p))
	if plastic:
		mb.setm(M.PLASTIC, tint(pal, "metal_light") * rng.randf_range(0.35, 0.55), seed)
	else:
		mb.setm(M.WOOD, tint(pal, "wood") * rng.randf_range(0.7, 1.15), seed)
	mb.box(Vector3.ZERO, size)
	# 边框
	mb.setm(M.WOOD, tint(pal, "wood") * 0.6 if not plastic else tint(pal, "metal"), seed + 0.11)
	var h := size.y * 0.5
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(sx * (size.x * 0.5 - 0.04), 0, 0), Vector3(0.06, size.y, size.z + 0.03))
		mb.box(Vector3(0, 0, sx * (size.z * 0.5 - 0.04)), Vector3(size.x + 0.03, size.y, 0.06))
	mb.box(Vector3(0, h - 0.05, 0), Vector3(size.x + 0.04, 0.08, size.z + 0.04))
	mb.pop()


## 垃圾箱（掩体）：箱体 + 斜盖 + 轮 + 地面污渍
static func dumpster(mb: MB, p: Vector3, n: Vector2, pal: Dictionary,
		rng: RandomNumberGenerator, yaw := 0.0, seed := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	mb.push(Transform3D(b, p))
	var col := neon_of(pal, rng.randi()) * 0.28 + tint(pal, "metal") * 0.8
	mb.setm(M.METAL, col, seed)
	mb.box(Vector3(0, 0.95, 0), Vector3(1.9, 1.3, 1.25))
	mb.setm(M.METAL, col * 0.8, seed + 0.09)
	mb.box(Vector3(0, 1.68, -0.12), Vector3(1.94, 0.16, 1.05))
	mb.box(Vector3(0, 1.72, 0.52), Vector3(1.94, 0.1, 0.5))
	mb.setm(M.RUBBER, tint(pal, "rubber"), seed + 0.13)
	for s in [-0.72, 0.72]:
		mb.cyl_y(Vector3(s, 0.16, -0.45), 0.16, 0.12, 8, true)
		mb.cyl_y(Vector3(s, 0.16, 0.45), 0.16, 0.12, 8, true)
	mb.setm(M.METAL, tint(pal, "metal_light") * 0.6, seed + 0.2)
	mb.box(Vector3(0, 0.55, 0.66), Vector3(1.5, 0.12, 0.1))
	mb.pop()
	# 地面渗漏污渍
	mb.setm(M.SOIL, tint(pal, "concrete_dark") * 0.5, seed + 0.3)
	floor_rect(mb, Rect2(p.x - 1.6, p.z - 1.4, 3.2, 2.8), 0.008)


## 掩体柱：混凝土柱 + 底座 + 霓虹环 + 顶部郁金香灯
static func pillar(mb: MB, c: Vector2, r: float, h: float, pal: Dictionary,
		rng: RandomNumberGenerator, seed := 0.0, cap_lamp := true) -> void:
	mb.setm(M.CONCRETE, tint(pal, "concrete") * 0.95, seed)
	mb.cyl_y(Vector3(c.x, h * 0.5, c.y), r, h, 20, true)
	mb.setm(M.CONCRETE, tint(pal, "concrete") * 1.1, seed + 0.1)
	mb.box(Vector3(c.x, 0.25, c.y), Vector3(r * 2.6, 0.5, r * 2.6))
	mb.box(Vector3(c.x, h - 0.3, c.y), Vector3(r * 2.4, 0.6, r * 2.4))
	# 霓虹环带
	for i in 2:
		var y := h * (0.32 + 0.34 * float(i))
		mb.setm(M.EMIT, neon_of(pal, 0) if i == 0 else neon_of(pal, 2), seed + 0.2 + 0.1 * i, 2.4)
		mb.cyl_y(Vector3(c.x, y, c.y), r + 0.05, 0.14, 20, true)
	# 危险条纹
	mb.setm(M.ROADPAINT, tint(pal, "stripe"), seed + 0.3)
	mb.cyl_y(Vector3(c.x, 0.66, c.y), r + 0.04, 0.32, 20, true)
	if cap_lamp:
		mb.setm(M.EMIT, Mats.c(pal["cool"]) * 0.9, seed + 0.4, 2.2)
		mb.cyl_y(Vector3(c.x, h + 0.12, c.y), r * 0.62, 0.22, 16, true)


## 街头路灯：灯杆 + 悬臂 + 灯头自发光；返回灯头世界坐标（放光用）
static func street_lamp(mb: MB, p: Vector3, out_dir: Vector2, pal: Dictionary,
		rng: RandomNumberGenerator, seed := 0.0, h := 8.4) -> Vector3:
	var iv := Vector3(out_dir.x, 0.0, out_dir.y)
	mb.setm(M.METAL, tint(pal, "metal"), seed)
	mb.cyl_y(p + Vector3(0, h * 0.5, 0), 0.11, h, 8, true, 0.08)
	mb.box(p + Vector3(0, 0.2, 0), Vector3(0.42, 0.4, 0.42))
	var head := p + iv * 1.5 + Vector3(0, h - 0.25, 0)
	mb.box_frame(p + Vector3(0, h - 0.2, 0), head, 0.12)
	mb.setm(M.EMIT, Mats.c(pal["cool"]), seed + 0.2, 3.2)
	mb.box(head + Vector3(0, -0.06, 0), Vector3(absf(iv.x) * 0.9 + 0.5, 0.14, absf(iv.z) * 0.9 + 0.5))
	# 灯杆小旗
	if rng.randf() < 0.4:
		mb.setm(M.FABRIC, neon_of(pal, rng.randi()) * 0.45, rng.randf())
		mb.quad(p + iv * 0.1 + Vector3(0, 5.6, 0), p + iv * 0.7 + Vector3(0, 5.6, 0),
			p + iv * 0.7 + Vector3(0, 4.0, 0), p + iv * 0.1 + Vector3(0, 4.0, 0))
	return head


## 跨街电缆（悬链线）
static func cable(mb: MB, a: Vector3, b: Vector3, sag: float, pal: Dictionary, r := 0.035) -> void:
	var pts := PackedVector3Array()
	var n := 8
	for i in n + 1:
		var t := float(i) / float(n)
		var p := a.lerp(b, t)
		p.y -= sin(t * PI) * sag
		pts.append(p)
	mb.setm(M.RUBBER, tint(pal, "rubber"), 0.3)
	mb.tube(pts, r, 4, false)


## 电缆上挂的小灯泡串
static func bulb_string(mb: MB, a: Vector3, b: Vector3, sag: float, pal: Dictionary,
		count: int, seed := 0.0) -> void:
	cable(mb, a, b, sag, pal, 0.022)
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var p := a.lerp(b, t)
		p.y -= sin(t * PI) * sag
		mb.setm(M.EMIT, neon_of(pal, i), seed + 0.1 * i, 2.6)
		mb.sphere(p + Vector3(0, -0.16, 0), 0.09, 6, 4)


## 通风格栅（地面井盖 / 墙面风口）
static func grate(mb: MB, c: Vector2, size: Vector2, pal: Dictionary, y := 0.02,
		seed := 0.0) -> void:
	mb.setm(M.METAL, tint(pal, "metal"), seed)
	floor_rect(mb, Rect2(c.x - size.x * 0.5, c.y - size.y * 0.5, size.x, size.y), y)
	mb.setm(M.METAL, tint(pal, "metal") * 0.55, seed + 0.1)
	var bars := maxi(3, int(size.y / 0.16))
	for i in bars:
		var z := c.y - size.y * 0.5 + size.y * (float(i) + 0.5) / float(bars)
		floor_rect(mb, Rect2(c.x - size.x * 0.5 + 0.06, z - 0.03, size.x - 0.12, 0.06), y + 0.012)


## 墙面风口（蒸汽出口的可见来源）
static func wall_vent(mb: MB, p: Vector3, n: Vector2, pal: Dictionary, seed := 0.0) -> void:
	var b := frame_basis(n)
	mb.push(Transform3D(b, p))
	mb.setm(M.METAL, tint(pal, "metal_light") * 0.5, seed)
	mb.box(Vector3(0, 0, 0.14), Vector3(1.1, 0.9, 0.3))
	mb.setm(M.METAL, tint(pal, "metal") * 0.6, seed + 0.1)
	for i in 4:
		mb.box(Vector3(0, -0.3 + 0.2 * float(i), 0.32), Vector3(1.0, 0.09, 0.06))
	mb.pop()


## 长凳 / 垃圾桶 / 售货机 / 变电箱（街道家具，兼作掩体）
static func bench(mb: MB, p: Vector3, yaw: float, pal: Dictionary, seed := 0.0) -> void:
	mb.push(Transform3D(Basis(Vector3.UP, yaw), p))
	mb.setm(M.WOOD, tint(pal, "wood"), seed)
	mb.box(Vector3(0, 0.45, 0), Vector3(0.6, 0.09, 2.0))
	for s in [-0.75, 0.75]:
		mb.setm(M.METAL, tint(pal, "metal"), seed + 0.1)
		mb.box(Vector3(0, 0.22, s), Vector3(0.5, 0.44, 0.1))
	mb.pop()


static func trash_bin(mb: MB, p: Vector3, pal: Dictionary, seed := 0.0) -> void:
	mb.setm(M.METAL, tint(pal, "metal_light") * 0.4, seed)
	mb.cyl_y(p + Vector3(0, 0.5, 0), 0.32, 1.0, 10, true)
	mb.setm(M.PLASTIC, tint(pal, "metal"), seed + 0.1)
	mb.cyl_y(p + Vector3(0, 1.03, 0), 0.34, 0.09, 10, true)


static func vending(mb: MB, p: Vector3, n: Vector2, pal: Dictionary,
		rng: RandomNumberGenerator, seed := 0.0) -> void:
	var b := frame_basis(n)
	mb.push(Transform3D(b, p))
	mb.setm(M.METAL, tint(pal, "metal"), seed)
	mb.box(Vector3(0, 0.95, 0.4), Vector3(1.0, 1.9, 0.75))
	mb.setm(M.SCREEN, neon_of(pal, 3), rng.randf(), 1.4)
	mb.box(Vector3(0, 1.25, 0.79), Vector3(0.8, 1.05, 0.04))
	mb.setm(M.EMIT, neon_of(pal, 4), rng.randf(), 1.1)
	mb.box(Vector3(0, 1.92, 0.79), Vector3(0.9, 0.12, 0.04))
	mb.pop()


static func transformer_box(mb: MB, p: Vector3, yaw: float, pal: Dictionary,
		rng: RandomNumberGenerator, seed := 0.0) -> void:
	mb.push(Transform3D(Basis(Vector3.UP, yaw), p))
	mb.setm(M.METAL, tint(pal, "metal_light") * 0.35, seed)
	mb.box(Vector3(0, 0.85, 0), Vector3(1.5, 1.7, 1.0))
	mb.setm(M.METAL, tint(pal, "metal"), seed + 0.1)
	for i in 3:
		mb.box(Vector3(0, 0.4 + 0.45 * float(i), 0.53), Vector3(1.2, 0.07, 0.06))
	mb.setm(M.ROADPAINT, tint(pal, "stripe"), seed + 0.2)
	mb.box(Vector3(0, 1.5, 0), Vector3(1.56, 0.2, 1.06))
	mb.pop()


## 危险斜条纹（墙面/矮墙下沿）
static func hazard_band(mb: MB, a: Vector2, b: Vector2, n: Vector2, y0: float, y1: float,
		pal: Dictionary, seed := 0.0) -> void:
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var steps := maxi(1, int(L / 0.55))
	for i in steps:
		var t0 := L * float(i) / float(steps)
		var t1 := L * float(i + 1) / float(steps)
		var p0 := a + dir * t0
		var p1 := a + dir * t1
		var on := i % 2 == 0
		mb.setm(M.ROADPAINT, tint(pal, "stripe") * (1.1 if on else 0.32), seed + 0.05 * i)
		wall_quad(mb, p0, p1, y0, y1, n)


## 贴墙日光灯管（低成本的灯光节奏，沿小巷每 10~12 m 一根）
static func wall_tube(mb: MB, p: Vector3, n: Vector2, w: float, pal: Dictionary,
		col: Color, seed := 0.0) -> void:
	var b := frame_basis(n)
	mb.push(Transform3D(b, p))
	mb.setm(M.METAL, tint(pal, "metal"), seed)
	mb.box(Vector3(0, 0, 0.09), Vector3(w + 0.16, 0.16, 0.2))
	mb.setm(M.EMIT, col, seed + 0.1, 2.4)
	mb.box(Vector3(0, 0, 0.16), Vector3(w, 0.1, 0.09))
	mb.setm(M.METAL, tint(pal, "metal_light") * 0.5, seed + 0.2)
	mb.box(Vector3(0, 0.24, 0.22), Vector3(w + 0.1, 0.06, 0.34))
	mb.pop()


## 发光海报 / 灯箱（M.EMIT 低强度，作为墙面上的小块色）
static func poster(mb: MB, p: Vector3, n: Vector2, w: float, h: float, col: Color,
		pal: Dictionary, seed := 0.0) -> void:
	var b := frame_basis(n)
	mb.push(Transform3D(b, p))
	mb.setm(M.METAL, tint(pal, "metal"), seed)
	mb.box(Vector3(0, 0, 0.06), Vector3(w + 0.14, h + 0.14, 0.12))
	mb.setm(M.EMIT, col, seed + 0.1, 0.45)
	mb.box(Vector3(0, 0, 0.13), Vector3(w, h, 0.03))
	mb.pop()


# ------------------------------------------------------------------ 灯具
## 低位壁灯 / 脚灯（第三关）：在墙面局部坐标系里建，灯体中心 = 局部 y 0，贴墙 off 米。
## 造型是竖立的灯匣 + 上挑遮光板 + 朝场内的一条发光缝：光只往上、往场内打，
## 墙面正上方不会被压出一片白热光池（否则大怪投影上去的影子会被洗淡）。
## 返回发光点世界坐标（光晕 / 光源位置由调用方决定）。
static func wall_sconce(mb: MB, slot_xf: Transform3D, pal: Dictionary, seed := 0.0,
		off := 0.5) -> Vector3:
	var b := slot_xf.basis
	mb.push(Transform3D(b, slot_xf.origin))
	# 贴墙底板
	mb.setm(M.METAL, tint(pal, "metal"), seed)
	mb.box(Vector3(0, 0, 0.05), Vector3(0.7, 1.58, 0.10))
	# 灯匣（竖立，前脸朝场内）
	mb.setm(M.METAL, tint(pal, "metal_light") * 0.5, seed + 0.1)
	mb.box(Vector3(0, 0, off), Vector3(0.46, 1.42, 0.24))
	# 上下遮光板：上面那块外挑，把光压向场内上方
	mb.box(Vector3(0, 0.76, off + 0.12), Vector3(0.58, 0.06, 0.5))
	mb.box(Vector3(0, -0.76, off + 0.05), Vector3(0.58, 0.06, 0.38))
	# 发光缝：正面一条竖缝 + 两侧窄缝（高位不发光，避免墙面正上方过曝）
	mb.setm(M.EMIT, Mats.c("fdfbff"), seed + 0.2, 3.6)
	mb.box(Vector3(0, -0.05, off + 0.135), Vector3(0.15, 1.2, 0.04))
	mb.setm(M.EMIT, Mats.c("ffe9d8"), seed + 0.25, 1.9)
	mb.box(Vector3(0.235, -0.05, off + 0.02), Vector3(0.04, 1.1, 0.17))
	mb.box(Vector3(-0.235, -0.05, off + 0.02), Vector3(0.04, 1.1, 0.17))
	# 底座
	mb.setm(M.METAL, tint(pal, "metal") * 0.75, seed + 0.3)
	mb.box(Vector3(0, -0.84, off * 0.5), Vector3(0.52, 0.14, off + 0.16))
	mb.pop()
	return slot_xf.origin + b.z * (off + 0.14)
