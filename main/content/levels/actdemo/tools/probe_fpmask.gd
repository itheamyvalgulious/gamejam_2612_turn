extends Node3D
## 探针：第三人称「第一人称视野黑幕」（Tab）—— 出图 + 逐像素验收。
##
##   DISPLAY=:0 godot --path . res://scenes/probe_fpmask.tscn
##
## 验收做法（不是「看着差不多」）：
##   1. 换成一块**解析地面**（1600×1600、无光照、无雾、纯灰）+ 隐藏机体，
##      这样「这个像素看到的世界点」可以精确算出来：TP 相机射线 ∩ 平面 y=0。
##   2. 冻结模拟，各截一张「关 / 开」黑幕的图。
##   3. 逐像素：用和 shader 同一个式子（GameCam.fp_sees_point）判断该点是否在第一人称
##      画面里 —— 视锥内必须亮着，视锥外必须被涂黑。
##   4. 边界逐像素：一行一行找「黑 → 亮」的过渡像素，和解析边界（mxy = 1）比，误差 ≤ 2 px。

const MainScene = preload("res://main.tscn")
const Qa = preload("res://tools/qa_lib.gd")
const Shot = preload("res://tools/shot.gd")

const PLANE_MAT := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque;
void fragment() { ALBEDO = vec3(0.55, 0.58, 0.62); }
"""

var q
var game
var shot = Shot.new()


func _ready() -> void:
	q = Qa.new("probe_fpmask")
	game = MainScene.instantiate()
	add_child(game)
	await _f(4)
	P.set_value("rules.god_mode", true)
	P.set_value("cam.mode", "third")
	await _shots_l1()
	await _shots_l3()
	await _t_plane()
	q.summary()
	get_tree().quit()


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(path: String) -> void:
	await _f(6)
	await shot.capture(self, path, 2)


func _set_mask(on: bool, immediate := false) -> void:
	game._fp_mask_on = on
	if immediate:
		game.fp_mask.set_active(on and not game.cam.first_person)
		if on:
			game.fp_mask.step(game.cam.fp_proj_view(), P.getf("cam.mask_soft"))


func _place(pos: Vector3, yaw: float, dist := 8.2) -> void:
	game.player.rig.global_position = pos
	game.player.rig.heading = yaw
	game.player.rig.rotation.y = yaw
	game.player.rig.facing_override = true
	game.cam.yaw = yaw
	P.set_value("cam.distance", dist)
	game.cam.snap(game.level.arena)


# ------------------------------------------------------------------ 出图
func _shots_l1() -> void:
	q.section("出图：窄巷（第三人称）")
	game.level.start_level(0)
	await _f(30)
	var sp: Transform3D = game.level.arena["player_spawn"]
	_place(sp.origin, sp.basis.get_euler().y, 7.8)
	game.cam.pitch = -0.02
	await _f(40)
	_set_mask(false)
	await _snap("res://shots/fp_mask_L1_off.png")
	_set_mask(true)
	await _snap("res://shots/fp_mask_L1_on.png")
	# 同机位第一人称：这张就是「答案」，黑幕里留下的内容必须和它一致
	P.set_value("cam.mode", "first")
	await _f(10)
	await _snap("res://shots/fp_mask_L1_fp.png")
	P.set_value("cam.mode", "third")
	await _f(10)
	_set_mask(false)
	q.info("l1 shots", "fp_mask_L1_off / _on / _fp")


func _shots_l3() -> void:
	q.section("出图：灯墙厅（第三人称）")
	game.level.start_level(2)
	await _f(30)
	for e in game.level.enemies:
		e.global_position = Vector3(0, 0, -30)
	_place(Vector3(0, 0, 24), 0.0, 8.6)
	game.cam.pitch = -0.16
	await _f(40)
	_set_mask(true)
	await _snap("res://shots/fp_mask_L3_on.png")
	_set_mask(false)
	await _f(6)


# ------------------------------------------------------------------ 逐像素
func _t_plane() -> void:
	q.section("逐像素：黑幕 == 第一人称视锥（解析地面）")
	game.level.start_level(2)
	await _f(30)
	# 只留一块解析地面：关掉关卡美术 / 影子幕布 / 所有角色，免得任何遮挡让「这个像素看到什么」变得不确定
	game.level.arena_node.visible = false
	if game.level.shadow != null:
		game.level.shadow.set_enabled(false)
	for e in game.level.enemies:
		e.rig.visible = false
	game.player.rig.visible = false
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600, 1600)
	plane.mesh = pm
	var sh := Shader.new()
	sh.code = PLANE_MAT
	var mat := ShaderMaterial.new()
	mat.shader = sh
	plane.material_override = mat
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plane.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(plane)
	game.hud.set_hud_visible(false)

	_place(Vector3.ZERO, 0.0, 7.7)
	game.cam.pitch = -0.40
	game.cam.step(1.0 / 60.0, game.level.arena)
	game.cam.step(1.0 / 60.0, game.level.arena)
	await _f(20)

	# 冻结模拟：两张图的世界完全一样，只有黑幕开关不同
	get_tree().paused = true
	_set_mask(false, true)
	await _f(3)
	var img_off := await _grab()
	_set_mask(true, true)
	await _f(3)
	var img_on := await _grab()
	get_tree().paused = false
	if img_off == null or img_on == null:
		q.ok(false, "截图读回失败")
		return

	var cam: Camera3D = game.cam.camera
	var w := img_on.get_width()
	var h := img_on.get_height()
	# 像素 → 相机屏幕坐标：窗口是 1280×646，逻辑视口是 1783×900（stretch canvas_items + expand），
	# project_ray_normal() 吃的是**视口**坐标，不是截图里的像素坐标。两者宽高比相同，按比例换算即可。
	var vr: Vector2 = cam.get_viewport().get_visible_rect().size
	var scale := Vector2(vr.x / float(w), vr.y / float(h))
	var body := AABB(Vector3(-2.6, -0.2, -2.6), Vector3(5.2, 5.8, 5.2))

	var checked := 0
	var bad := 0
	var ins := 0
	var first_bad := ""
	var lo_in := 9.0
	var lo_out := 9.0
	var hi_out := 0.0
	var lo_off := 9.0
	var bad_in := 0
	var bad_out := 0
	var bad_near := 0
	var dbg := Image.create(w, h, false, Image.FORMAT_RGB8)
	dbg.fill(Color(0.15, 0.15, 0.15))
	for y in range(0, h, 3):
		for x in range(0, w, 3):
			var hit: Variant = _floor_of(cam, Vector2((float(x) + 0.5) * scale.x, (float(y) + 0.5) * scale.y), body)
			if hit == null:
				continue
			var pt: Vector3 = hit
			var mxy := _mxy(pt)
			if absf(mxy - 1.0) < 0.03:      # 边界附近留白（AA / 柔化 / 像素中心误差）
				continue
			var sees: bool = game.cam.fp_sees_point(pt)
			var lum_on := _lum(img_on.get_pixel(x, y))
			var lum_off := _lum(img_off.get_pixel(x, y))
			lo_off = minf(lo_off, lum_off)
			checked += 1
			dbg.set_pixel(x, y, Color(0.1, 0.4, 0.15) if sees else Color(0.05, 0.2, 0.45))
			if sees:
				ins += 1
				lo_in = minf(lo_in, lum_on)
				# 第一人称看得见 → 不许变黑
				if lum_on < 0.02 or (lum_off - lum_on) > 0.08:
					bad += 1
					bad_in += 1
					if absf(mxy - 1.0) < 0.06:
						bad_near += 1
					dbg.set_pixel(x, y, Color(1.0, 0.15, 0.1))
					if first_bad == "":
						first_bad = "inside  m=%.3f on=%.3f off=%.3f (px %d,%d)" % [mxy, lum_on, lum_off, x, y]
			else:
				lo_out = minf(lo_out, lum_on)
				hi_out = maxf(hi_out, lum_on)
				# 第一人称看不见 → 必须被涂黑
				if lum_on > 0.06:
					bad += 1
					bad_out += 1
					if absf(mxy - 1.0) < 0.06:
						bad_near += 1
					dbg.set_pixel(x, y, Color(1.0, 0.9, 0.1))
					if first_bad == "":
						first_bad = "outside m=%.3f on=%.3f off=%.3f (px %d,%d)" % [mxy, lum_on, lum_off, x, y]
	q.info("采样", "%d 个地面像素（%dx%d），视锥内 %d / 视锥外 %d" % [checked, w, h, ins, checked - ins])
	q.info("亮度", "视锥内最暗 %.3f · 视锥外最亮 %.3f · 未开黑幕最暗 %.3f" % [lo_in, hi_out, lo_off])
	q.ok(checked > 2000 and ins > 300 and checked - ins > 300, "两类采样点都够多", str(checked))
	q.info("mismatch 细分", "视锥内被涂黑 %d / 视锥外没涂黑 %d / 其中 |m-1|<0.06 的 %d" % [bad_in, bad_out, bad_near])
	dbg.save_png("res://shots/dbg_fpmask_class.png")
	q.ok(bad == 0, "逐像素分类与第一人称视锥一致", "mismatch=%d/%d  %s" % [bad, checked, first_bad])

	await _t_edge(cam, img_on, w, h, scale, body)


## 边界：一行一行找「黑 → 亮」的过渡像素，和解析边界（mxy = 1）比
func _t_edge(cam: Camera3D, img: Image, w: int, h: int, scale: Vector2, body: AABB) -> void:
	var rows := 0
	var worst := 0
	var sums := 0.0
	var detail := ""
	for y in range(0, h, 17):
		var py := float(y) + 0.5
		var pred := -1
		var act := -1
		for x in w:
			var hit: Variant = _floor_of(cam, Vector2((float(x) + 0.5) * scale.x, py * scale.y), body)
			if hit == null:
				continue
			if game.cam.fp_sees_point(hit):
				if pred < 0:
					pred = x
			elif pred >= 0:
				pred = -2
				break
		if pred < 0:
			continue
		for x in w:
			var hit: Variant = _floor_of(cam, Vector2((float(x) + 0.5) * scale.x, py * scale.y), body)
			if hit == null or not game.cam.fp_sees_point(hit):
				continue
			# 找到解析边界之后再找渲染里的第一列「亮」像素
			if _lum(img.get_pixel(x, y)) > 0.15:
				act = x
				break
		if act < 0:
			continue
		rows += 1
		var d := absi(act - pred)
		sums += float(d)
		if d > worst:
			worst = d
			detail = "y=%d 解析 x=%d 实际 x=%d" % [y, pred, act]
	q.info("边界行", "%d 行，平均偏差 %.2f px，最大 %d px（%s）" % [rows, sums / maxf(1.0, float(rows)), worst, detail])
	q.ok(rows > 8, "边界行样本足够", str(rows))
	q.ok(worst <= 2, "黑幕边界就是 mxy = 1（零余量）", "max %d px" % worst)


## 屏幕上这个像素看到的世界点（解析地面 y=0）；不是地面 / 被机体挡住 / 太远 → null
func _floor_of(cam: Camera3D, screen: Vector2, body: AABB) -> Variant:
	var ray: Vector3 = cam.project_ray_normal(screen)
	if ray.y > -0.02:
		return null
	var t: float = cam.global_position.y / -ray.y
	if t > 240.0:
		return null
	var pt: Vector3 = cam.global_position + ray * t
	if body.intersects_segment(cam.global_position, pt):
		return null
	return pt


func _mxy(pt: Vector3) -> float:
	var c: Vector4 = game.cam.fp_proj_view() * Vector4(pt.x, pt.y, pt.z, 1.0)
	if c.w <= 0.0:
		return -1.0
	return maxf(absf(c.x), absf(c.y)) / c.w


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_tree().root.get_texture().get_image()


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
