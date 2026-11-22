extends Node3D
## 竞技场自测：依次 build 三关卡 → 玩家视角截图 + chamber 俯瞰图 + 数据断言 + 性能采样。
##
## 运行：DISPLAY=:0 godot --path . res://scenes/test_arena.tscn
## 输出：res://shots/arena_alley.png / arena_plaza.png / arena_chamber.png / arena_chamber_top.png

const Arena := preload("res://src/arena/arena.gd")
const Shot := preload("res://tools/shot.gd")
const WallShadow := preload("res://src/fx/wall_shadow.gd")

var _fails := 0
var _cam: Camera3D
var _shot: Shot
var _only := ""
var _cam_override: Array[Vector3] = []
var _soak := 0.0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.split("=")[1]
		if a.begins_with("--soak="):
			_soak = float(a.split("=")[1])
		if a.begins_with("--cam="):
			# --cam=x,y,z,tx,ty,tz  调试机位覆盖
			var parts := a.split("=")[1].split(",")
			if parts.size() == 6:
				_cam_override = [Vector3(float(parts[0]), float(parts[1]), float(parts[2])),
					Vector3(float(parts[3]), float(parts[4]), float(parts[5]))]
	_shot = Shot.new()
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.06
	_cam.far = 600.0
	add_child(_cam)
	_cam.current = true
	await _run()
	if _soak > 0.0:
		print("--- soak %.0f s（观察运行期日志）---" % _soak)
		await get_tree().create_timer(_soak).timeout
	print("=== 自测结束：失败项 %d ===" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	# 1) 窄巷：站在巷中偏西，西墙 11 m、巷尾 45 m 外
	if not _skip("alley"):
		await _level("alley", Vector3(-9.0, 3.5, 17.0), Vector3(-13.0, 4.4, -6.0),
			"res://shots/arena_alley.png")
	# 2) 广场：站西侧，西墙 11 m，正对广场中央与掩体柱
	if not _skip("plaza"):
		await _level("plaza", Vector3(-31.0, 3.5, 25.0), Vector3(-22.0, 4.6, -6.0),
			"res://shots/arena_plaza.png")
	# 3) 灯墙厅：贴西墙 10 m，看北墙与壁灯
	if not _skip("chamber"):
		await _level("chamber", Vector3(8.5, 3.5, 23.0), Vector3(-2.0, 5.6, -12.0),
			"res://shots/arena_chamber.png", true, true)
	# 4) 灯墙厅俯瞰
	if _only == "":
		await _level("chamber", Vector3(0.0, 14.5, 25.0), Vector3(0.0, 4.0, -18.0),
			"res://shots/arena_chamber_top.png", false)


## --only=xxx 时只跑该关卡的玩家视角（调试用，不跑俯瞰）
func _skip(kind: String) -> bool:
	return _only != "" and _only != kind


## 建造一个关卡 → 截图 → 断言 → 性能采样 → 拆掉。
## probe = true 时同时跑数据断言（三个关卡各跑一次）。
func _level(kind: String, cam_pos: Vector3, cam_target: Vector3, path: String,
		probe := true, shadow_probe := false) -> void:
	print("\n---------------- %s ----------------" % kind)
	var t0 := Time.get_ticks_msec()
	var data := Arena.build(kind)
	var build_ms := Time.get_ticks_msec() - t0
	var root: Node3D = data["node"]
	add_child(root)
	if _cam_override.size() == 2:
		cam_pos = _cam_override[0]
		cam_target = _cam_override[1]
	_cam.global_position = cam_pos
	var up := Vector3.UP
	if absf((cam_target - cam_pos).normalized().dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	_cam.look_at(cam_target, up)
	# 交付图要求：场地中央站着 8.4 m 盒子代理 + 墙上有影子 → 出图前就挂上
	var ws: Node3D = null
	if shadow_probe:
		ws = await _mount_shadow(root, data)
	await _shot.capture(self, path, 36)

	# 三角形数（几何本身，静态统计）+ 逐帧 primitives + fps
	var tris := _tri_count(root)
	var fps := await _measure_fps(150)
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	print("构建 %d ms | 三角形 %d | RENDER_TOTAL_PRIMITIVES_IN_FRAME %d | draw_calls %d | fps %.1f (1280x720, vsync off)"
		% [build_ms, tris, int(prims), int(draws), fps])
	if probe:
		_probe(kind, data)
	if shadow_probe and ws != null:
		await _shadow_report(root, data, ws)
	root.queue_free()
	await get_tree().process_frame


## 挂上「8.4 m 盒子代理（可见）+ WallShadow」，返回 WallShadow 节点。
func _mount_shadow(root: Node3D, d: Dictionary) -> Node3D:
	print("\n---- wall_shadow 探针：8.4 m 盒子代理 @ 大怪出生点 %s ----"
		% (d["spawns"][0] as Transform3D).origin)
	var box := BoxMesh.new()
	box.size = Vector3(2.6, 8.4, 2.0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.085, 0.022, 0.020)     # 红黑剪影，靠冷补光勾出轮廓
	pm.roughness = 0.62
	pm.metallic = 0.12
	box.material = pm
	var sp: Transform3D = d["spawns"][0]
	var proxy_xf := Transform3D(sp.basis, sp.origin + Vector3(0, 4.2, 0))
	var bmi := MeshInstance3D.new()
	bmi.name = "BossProxy"
	bmi.mesh = box
	bmi.transform = proxy_xf
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(bmi)
	var parts := [{"xf": proxy_xf, "mesh": box}]
	var ws: Node3D = WallShadow.new()
	root.add_child(ws)
	ws.setup(d["wall_slots"], {"intensity": 0.70, "softness": 0.4, "lamp_mode": "auto"})
	ws.set_lamps(d["lamps"])
	ws.set_source(func() -> Array: return parts)
	ws.refresh()
	await get_tree().process_frame
	ws.refresh()
	return ws


## 量影子 y 范围（墙面局部坐标）+ 画面最亮/最暗灰度 + 影子与墙面的亮度差。
func _shadow_report(root: Node3D, d: Dictionary, ws: Node3D) -> void:
	var rep: Dictionary = ws.debug_report()
	var all_ok := true
	for sd in rep["slots"]:
		var mn: Vector2 = sd["min"]
		var mx: Vector2 = sd["max"]
		var ok: bool = int(sd["tris"]) > 0 and mx.y > 4.0 and mn.y < -8.0
		all_ok = all_ok and ok
		print("  wall %d  lamp %d  tris %4d  y %+.2f .. %+.2f m（世界 %.2f .. %.2f m）  x %+.2f .. %+.2f  %s"
			% [int(sd["slot"]), int(sd["lamp"]), int(sd["tris"]), mn.y, mx.y,
				mn.y + 9.5, mx.y + 9.5, mn.x, mx.x, "OK" if ok else "FAIL"])
	print("  lamps=%d slots=%d  decim=%.2f  build=%.2f ms" % [int(rep["lamps"]),
		(rep["slots"] as Array).size(), float(rep["decim"]), float(rep["usec"]) / 1000.0])
	_check(all_ok, "四面墙影子：顶部 > +4 m 且底部 < -8 m（墙面局部坐标）")

	var img := await _grab()
	var st := _luma_stats(img)
	print("  画面灰度 0-255：最亮 %.0f @ (%d,%d)   最暗 %.0f @ (%d,%d)   平均 %.1f   p5 %.0f   p95 %.0f"
		% [st["max"], st["max_x"], st["max_y"], st["min"], st["min_x"], st["min_y"],
			st["mean"], st["p5"], st["p95"]])
	_check(st["max"] > 170.0, "画面有高光（最亮 %.0f）" % st["max"])
	_check(st["p95"] < 252.0, "高光没被大面积烧白（p95 %.0f < 252）" % st["p95"])
	_check(st["min"] < 80.0, "暗部有真正的黑（最暗 %.0f）" % st["min"])

	var rect := _shadow_screen_rect(rep, d, img.get_size())
	var lum_on := _mean_lum(img, rect)
	ws.set_enabled(false)
	await get_tree().process_frame
	var img2 := await _grab()
	var lum_off := _mean_lum(img2, rect)
	ws.set_enabled(true)
	var drop := 0.0 if lum_off <= 0.001 else (1.0 - lum_on / lum_off) * 100.0
	print("  影子区域 %s 平均灰度：有影 %.1f → 无影 %.1f（差 %.0f%%）"
		% [rect, lum_on * 255.0, lum_off * 255.0, drop])
	_check(drop > 32.0, "影子与相邻墙面亮度差 %.0f%% > 32%%" % drop)

	# ④ 机甲过曝检查：临时放一个 4.2 m 高一米机替代体（哑光灰 0.5），量它最亮像素
	var mech_box := BoxMesh.new()
	mech_box.size = Vector3(1.8, 4.2, 1.8)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.5, 0.47, 0.42)
	mm.roughness = 0.85
	mech_box.material = mm
	var stand := MeshInstance3D.new()
	stand.mesh = mech_box
	stand.transform = Transform3D(Basis(), Vector3(3.0, 2.1, 4.0))
	root.add_child(stand)
	await get_tree().process_frame
	var img3 := await _grab()
	var r3 := _box_screen_rect(stand)
	if r3.size.x > 4.0 and r3.size.y > 4.0:
		var st3 := _luma_stats(img3)
		var m3 := _rect_luma(img3, r3)
		print("  机甲替代体（哑光灰 0.5，4.2 m，场地中央偏右）：其画面区域最亮 %.0f / 平均 %.0f / 整帧最亮 %.0f"
			% [m3.x, m3.y, st3["max"]])
		_check(m3.x < 250.0, "机甲替代体最亮 %.0f < 250（不再烧白）" % m3.x)
	stand.queue_free()


## 0-255 灰度统计（含最亮/最暗位置与 p5/p95）
func _luma_stats(img: Image) -> Dictionary:
	var hist := PackedInt32Array()
	hist.resize(256)
	hist.fill(0)
	var mx := -1.0
	var mn := 999.0
	var mxi := Vector2i.ZERO
	var mni := Vector2i.ZERO
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			var v := (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0
			hist[clampi(int(v), 0, 255)] += 1
			sum += v
			n += 1
			if v > mx:
				mx = v
				mxi = Vector2i(x, y)
			if v < mn:
				mn = v
				mni = Vector2i(x, y)
	var p5 := 0.0
	var p95 := 0.0
	var target5 := int(float(n) * 0.05)
	var target95 := int(float(n) * 0.95)
	var acc := 0
	for i in 256:
		acc += hist[i]
		if acc >= target5 and p5 == 0.0:
			p5 = float(i)
		if acc >= target95:
			p95 = float(i)
			break
	return {"max": mx, "min": mn, "mean": sum / float(maxi(n, 1)), "p5": p5, "p95": p95,
		"max_x": mxi.x, "max_y": mxi.y, "min_x": mni.x, "min_y": mni.y}


## 某个 MeshInstance3D 的 AABB 在画面里的矩形（截图坐标系）
func _box_screen_rect(mi: MeshInstance3D) -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var img_size := get_viewport().get_texture().get_image().get_size()
	var sc := Vector2(img_size.x / vp.x, img_size.y / vp.y)
	var r := Rect2()
	var first := true
	for i in 8:
		var c := Vector3(
			(-1.0 if (i & 1) == 0 else 1.0) * 0.9,
			0.0 if (i & 2) == 0 else 4.2,
			(-1.0 if (i & 4) == 0 else 1.0) * 0.9)
		var w: Vector3 = mi.global_transform * c
		if _cam.is_position_behind(w):
			return Rect2()
		var sp := _cam.unproject_position(w) * sc
		if first:
			r = Rect2(sp, Vector2.ZERO)
			first = false
		else:
			r = r.expand(sp)
	return r.grow(-2.0)


## 区域内 (最亮, 平均) 灰度
func _rect_luma(img: Image, r: Rect2) -> Vector2:
	var mx := 0.0
	var sum := 0.0
	var n := 0
	var x0 := clampi(int(r.position.x), 0, img.get_width() - 1)
	var y0 := clampi(int(r.position.y), 0, img.get_height() - 1)
	var x1 := clampi(int(r.end.x), 1, img.get_width())
	var y1 := clampi(int(r.end.y), 1, img.get_height())
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var c := img.get_pixel(x, y)
			var v := (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0
			mx = maxf(mx, v)
			sum += v
			n += 1
	return Vector2(mx, sum / float(maxi(n, 1)))


## 画面里影子占的矩形（取 4 面墙里投影面积最大的一块，保护性裁剪到画面内）
func _shadow_screen_rect(rep: Dictionary, d: Dictionary, img_size: Vector2) -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var sc := Vector2(img_size.x / vp.x, img_size.y / vp.y)
	var best := Rect2(img_size * 0.5, Vector2(8, 8))
	var best_area := 0.0
	for sd in rep["slots"]:
		if int(sd["tris"]) <= 0:
			continue
		var xf: Transform3D = d["wall_slots"][int(sd["slot"])]["xform"]
		var mn: Vector2 = sd["min"]
		var mx: Vector2 = sd["max"]
		var r := Rect2()
		var first := true
		var bad := false
		for p in [Vector3(mn.x, mn.y, 0.03), Vector3(mx.x, mn.y, 0.03),
				Vector3(mx.x, mx.y, 0.03), Vector3(mn.x, mx.y, 0.03)]:
			var w: Vector3 = xf * p
			if _cam.is_position_behind(w):
				bad = true
				break
			var s2 := _cam.unproject_position(w) * sc
			if first:
				r = Rect2(s2, Vector2.ZERO)
				first = false
			else:
				r = r.expand(s2)
		if bad:
			continue
		if not Rect2(Vector2.ZERO, img_size).encloses(r):
			continue                       # 只量完整落在画面里的那块影子
		if r.get_area() > best_area:
			best_area = r.get_area()
			best = r
	return best


func _mean_lum(img: Image, r: Rect2) -> float:
	var x0 := clampi(int(r.position.x), 0, img.get_width() - 1)
	var y0 := clampi(int(r.position.y), 0, img.get_height() - 1)
	var x1 := clampi(int(r.end.x), 1, img.get_width())
	var y1 := clampi(int(r.end.y), 1, img.get_height())
	var sum := 0.0
	var n := 0
	var step := maxi(1, int(minf(x1 - x0, y1 - y0) / 40.0))
	for y in range(y0, y1, step):
		for x in range(x0, x1, step):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / float(maxi(n, 1))


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _measure_fps(frames: int) -> float:
	# 先跑一段热身（shader 编译 / 粒子填充），再采样
	for i in 40:
		await get_tree().process_frame
	for i in frames:
		await get_tree().process_frame
	return Engine.get_frames_per_second()


func _tri_count(n: Node) -> int:
	var total := 0
	if n is MeshInstance3D:
		var m: Mesh = (n as MeshInstance3D).mesh
		if m is ArrayMesh:
			for s in m.get_surface_count():
				total += m.surface_get_array_index_len(s) / 3
	for c in n.get_children():
		total += _tri_count(c)
	return total


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  [OK]  " + msg)
	else:
		_fails += 1
		print("  [FAIL] " + msg)


# ------------------------------------------------------------------ 数据断言
func _probe(kind: String, d: Dictionary) -> void:
	print("kind=%s name_cn=%s floor_y=%s bounds=%s" % [d["kind"], d["name_cn"], d["floor_y"], d["bounds"]])
	print("walls=%d cover=%d wall_slots=%d lamps=%d spawns=%d"
		% [d["walls"].size(), d["cover"].size(), d["wall_slots"].size(), d["lamps"].size(), d["spawns"].size()])
	var b: AABB = d["bounds"]
	# 出生点必须在可玩区内，且 -Z 朝向场地中心
	for i in d["spawns"].size():
		var xf: Transform3D = d["spawns"][i]
		_check(_inside(b, xf.origin), "spawns[%d] %s 在 bounds 内" % [i, xf.origin])
		var to_c := Vector3(-xf.origin.x, 0, -xf.origin.z)
		if to_c.length() > 0.5:
			_check((-xf.basis.z).normalized().dot(to_c.normalized()) > 0.999,
				"spawns[%d] -Z 面朝场地中心 (dot=%.4f)" % [i, (-xf.basis.z).normalized().dot(to_c.normalized())])
	var ps: Transform3D = d["player_spawn"]
	_check(_inside(b, ps.origin), "player_spawn %s 在 bounds 内" % ps.origin)
	var tp: Vector3 = ps.origin + (-ps.basis.z) * 10.0
	_check(_inside(b, tp), "player_spawn -Z 指向场内 (%s)" % tp)
	# 掩体：半径必须已含 1.2 m 避让球
	for i in d["cover"].size():
		var c: Dictionary = d["cover"][i]
		_check(float(c["r"]) > Arena.BALL and float(c["h"]) > 0.0,
			"cover[%d] r=%.2f h=%.2f（含 1.2 m 避让球）" % [i, c["r"], c["h"]])
	# 墙段
	for i in d["walls"].size():
		var w: Dictionary = d["walls"][i]
		var mid: Vector2 = ((w["a"] as Vector2) + (w["b"] as Vector2)) * 0.5
		var inward: Vector2 = w["n"]
		_check(inward.dot(Vector2.ZERO - mid) > 0.0, "walls[%d] 法线指向场内 (n=%s)" % [i, inward])
	# wall_slots：局部 +Z 必须指向场内，且 plane 法线与之一致
	for i in d["wall_slots"].size():
		var s: Dictionary = d["wall_slots"][i]
		var xf: Transform3D = s["xform"]
		var pl: Plane = s["plane"]
		var sz: Vector2 = s["size"]
		var z_axis: Vector3 = xf.basis.z.normalized()
		_check(z_axis.dot(pl.normal) > 0.999, "wall_slots[%d] 局部 +Z · plane 法线 = %.4f" % [i, z_axis.dot(pl.normal)])
		_check(pl.distance_to(Vector3.ZERO + Vector3(0, xf.origin.y, 0)) > 0.0,
			"wall_slots[%d] 场地中心在平面内侧 (d=%.2f)" % [i, pl.distance_to(Vector3(0, xf.origin.y, 0))])
		# xform 的 4 个角必须落在平面上，且局部 X 覆盖 size.x
		var ok_plane := true
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var p: Vector3 = xf * Vector3(sz.x * 0.5 * sx, sz.y * 0.5 * sy, 0.0)
				if absf(pl.distance_to(p)) > 1e-3:
					ok_plane = false
		_check(ok_plane, "wall_slots[%d] 四角贴合墙面 size=%s" % [i, sz])
		# 局部 Y 与世界上方向一致（Y 竖直、X 沿墙宽）
		_check(xf.basis.y.dot(Vector3.UP) > 0.999, "wall_slots[%d] 局部 +Y 竖直" % i)
	# chamber 专项：lamps 与 wall_slots 各 4 个且一一对应
	if kind == "chamber":
		_check(d["lamps"].size() == 4, "chamber lamps == 4 (实际 %d)" % d["lamps"].size())
		_check(d["wall_slots"].size() == 4, "chamber wall_slots == 4 (实际 %d)" % d["wall_slots"].size())
		for i in d["lamps"].size():
			var lxf: Transform3D = d["lamps"][i]
			var s2: Dictionary = d["wall_slots"][i]
			var sxf: Transform3D = s2["xform"]
			var pl2: Plane = s2["plane"]
			var inward_l := -lxf.basis.z.normalized()
			_check(inward_l.dot(pl2.normal) > 0.999,
				"lamps[%d] -Z 指向场内（与 wall_slots[%d] 法线一致，dot=%.4f）" % [i, i, inward_l.dot(pl2.normal)])
			# 同一面墙：灯到该墙平面的距离应远小于到其它墙的距离
			var dist := pl2.distance_to(lxf.origin)
			var best := 1e9
			for j in d["wall_slots"].size():
				var pl3: Plane = d["wall_slots"][j]["plane"]
				best = minf(best, absf(pl3.distance_to(lxf.origin)))
			_check(dist > 0.5 and dist < 2.5 and absf(dist - best) < 1e-3,
				"lamps[%d] 挂在 wall_slots[%d] 上（离墙 %.2f m）" % [i, i, dist])
			# 灯高：低位壁灯 1.6~2.0 m（这样 8.4 m 大怪的影子才能整身投到对面墙上）
			_check(lxf.origin.y > 1.4 and lxf.origin.y < 2.2, "lamps[%d] 高度 %.2f m ≈ 低位壁灯" % [i, lxf.origin.y])
			# 灯具与墙面的水平距离（凸出量）很小 → 墙面依然平整
			var out_of_wall := (lxf.origin - Vector3(sxf.origin.x, lxf.origin.y, sxf.origin.z)).length()
			_check(out_of_wall > 0.25 and out_of_wall < 0.9, "lamps[%d] 贴墙 %.2f m（0.3~0.8）" % [i, out_of_wall])


func _inside(b: AABB, p: Vector3) -> bool:
	return p.x > b.position.x and p.x < b.position.x + b.size.x \
		and p.z > b.position.z and p.z < b.position.z + b.size.z
