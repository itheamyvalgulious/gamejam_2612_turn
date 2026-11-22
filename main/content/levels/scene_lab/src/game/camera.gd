extends Node3D
class_name GameCam
## 第三人称 / 第一人称双模式相机（鼠标视角 + 墙体避让 + 抖屏）。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

var rig: Node3D
var camera: Camera3D
var yaw := 0.0
var pitch := -0.16
var first_person := false

var _pos_smooth := Vector3.ZERO
var _focus_smooth := Vector3.ZERO
var _initialized := false
var _shake_t := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Cam"
	camera.near = 0.06
	camera.far = 500.0
	camera.fov = P.getf("cam.fov")
	# 影子层（layer 2）只有墙影的投影相机会渲染；主相机看到的是角色本体
	camera.cull_mask = 0xFFFFF & ~(1 << 1)
	add_child(camera)
	camera.current = true


func set_rig(r: Node3D) -> void:
	rig = r
	yaw = r.heading if r != null else 0.0


func set_first_person(on: bool) -> void:
	first_person = on
	if rig != null and rig.has_method("set_first_person_view"):
		rig.set_first_person_view(on, P.getb("cam.first_show_weapon"))
	_initialized = false


## 立刻把相机对位到当前 rig/arena（切关 / 重开时用）：
## 否则关卡的第一帧敌人/AI 读到的还是上一关的相机位置。
func snap(arena: Dictionary) -> void:
	_initialized = false
	step(0.0, arena)


func toggle_mode() -> void:
	var next := "first" if P.gets("cam.mode") != "first" else "third"
	P.set_value("cam.mode", next)
	set_first_person(next == "first")


func look(delta_mouse: Vector2) -> void:
	if rig == null:
		return
	var sens := P.getf("cam.sensitivity")
	yaw -= delta_mouse.x * sens
	pitch = clampf(pitch - delta_mouse.y * sens, P.getf("cam.pitch_min"), P.getf("cam.pitch_max"))


## 第一人称「眼」：位置 + 朝向。第一人称分支和视野黑幕（FpVisionMask）共用这一处，
## 保证「按 Tab 看到的黑幕」就是「按 V 切过去看到的画面」，不是另算一套近似。
func fp_transform() -> Transform3D:
	if rig == null:
		return Transform3D.IDENTITY
	var eye := rig.global_position + Vector3(0, P.getf("cam.first_height"), 0) + flat_forward() * 0.30
	return Transform3D(Basis.looking_at(forward(), Vector3.UP), eye)


## 第一人称相机的投影：first_fov（竖直）+ 当前视口宽高比 + 与主相机相同的近远裁剪面
func fp_projection() -> Projection:
	if camera == null:
		return Projection.IDENTITY
	var aspect := 16.0 / 9.0
	var vp := camera.get_viewport()
	if vp != null:
		var sz: Vector2 = vp.get_visible_rect().size
		if sz.y > 1.0:
			aspect = sz.x / sz.y
	# 注意：Projection.create_perspective 的 fovy 是**度**（与 Camera3D.fov 同一单位）
	return Projection.create_perspective(P.getf("cam.first_fov"), aspect, camera.near, camera.far)


## 第一人称 proj * view：黑幕 shader 用它把「这个像素看到的世界点」投进第一人称画面
func fp_proj_view() -> Projection:
	return fp_projection() * Projection(fp_transform().affine_inverse())


## 「这个世界点在第一人称画面里吗」—— 与 gfx/fp_vision_mask.gdshader 逐字同一个判定
## （|x|,|y|,|z| ≤ w）。QA 拿它和真相机的 is_position_in_frustum() 对照。
func fp_sees_point(world: Vector3) -> bool:
	var c: Vector4 = fp_proj_view() * Vector4(world.x, world.y, world.z, 1.0)
	if c.w <= 0.0:
		return false
	return absf(c.x) <= c.w and absf(c.y) <= c.w and absf(c.z) <= c.w


func forward() -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


func flat_forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func flat_right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func step(dt: float, arena: Dictionary) -> void:
	if rig == null:
		return
	var want_fp := P.gets("cam.mode") == "first"
	if want_fp != first_person:
		set_first_person(want_fp)

	# 键盘转镜头
	if B.pressed("cam_left"):
		yaw += 1.8 * dt
	if B.pressed("cam_right"):
		yaw -= 1.8 * dt

	var base := rig.global_position
	var fwd := forward()
	var shake := 0.0
	var fxs = Fx
	if fxs != null:
		shake = fxs.shake_amount * P.getf("cam.shake_scale")

	if first_person:
		var xf := fp_transform()
		camera.global_position = xf.origin + _shake_offset(shake)
		camera.look_at(xf.origin + fwd * 8.0, Vector3.UP)
		camera.fov = P.getf("cam.first_fov")
		_pos_smooth = xf.origin
		_focus_smooth = xf.origin + fwd * 8.0
		_initialized = true
		return

	# ---------------- 第三人称
	var focus := base + Vector3(0, P.getf("cam.focus_height"), 0)
	var dist := P.getf("cam.distance")
	var want_pos := focus - fwd * dist + Vector3(0, P.getf("cam.height"), 0)
	if P.getb("cam.collision"):
		want_pos = _avoid(want_pos, focus, arena)
	# 镜头不能钻到地面以下（仰角很大时会出现）
	want_pos.y = maxf(want_pos.y, 1.2)
	# 也不能穿到天花板上面去（矮房间里会变成整屏黑）
	var ceil_h: float = float(arena.get("ceiling", 0.0))
	if ceil_h > 0.1:
		want_pos.y = minf(want_pos.y, ceil_h - 0.7)
	# 圆形场地：相机不能跑到圈外，否则只能看到墙背面的黑
	var rad: float = float(arena.get("bounds_circle", 0.0))
	if rad > 0.1:
		var flat := Vector2(want_pos.x, want_pos.z)
		var lim := rad - 0.8
		if flat.length() > lim:
			flat = flat.normalized() * lim
			want_pos.x = flat.x
			want_pos.z = flat.y
	if not _initialized:
		_pos_smooth = want_pos
		_focus_smooth = focus
		_initialized = true
	var k := 1.0 - exp(-P.getf("cam.follow_rate") * dt)
	_pos_smooth = _pos_smooth.lerp(want_pos, k)
	_focus_smooth = _focus_smooth.lerp(focus, 1.0 - exp(-18.0 * dt))
	camera.global_position = _pos_smooth + _shake_offset(shake)
	camera.look_at(_focus_smooth + _shake_offset(shake * 0.25), Vector3.UP)
	camera.fov = P.getf("cam.fov")


func _shake_offset(amount: float) -> Vector3:
	if amount <= 0.0001:
		return Vector3.ZERO
	_shake_t += 0.05
	var n := sin(_shake_t * 37.0) * 0.6 + sin(_shake_t * 73.0) * 0.4
	var n2 := cos(_shake_t * 51.0) * 0.6 + cos(_shake_t * 29.0) * 0.4
	return Vector3(n, n2, n * 0.5) * amount * 0.22


## 从焦点往相机方向做精确求交：墙面线段 + 掩体圆，取最早的交点当作最大距离
func _avoid(want: Vector3, focus: Vector3, arena: Dictionary) -> Vector3:
	if arena.is_empty():
		return want
	var walls: Array = arena.get("walls", [])
	var cover: Array = arena.get("cover", [])
	var dir := want - focus
	var seg_len := dir.length()
	if seg_len < 0.01:
		return want
	var f2 := Vector2(focus.x, focus.z)
	var w2 := Vector2(want.x, want.z)
	var max_u := 1.0
	if not arena.get("camera_open", false):
		for w in walls:
			var t := _seg_hit(f2, w2, w["a"], w["b"])
			if t >= 0.0 and t < max_u:
				max_u = t
	for c in cover:
		if not bool(c.get("cam", true)):
			continue          # 悬空掩体（二层护栏）不挡相机
		var cc: Vector3 = c["c"]
		var t2 := _circle_hit(f2, w2, Vector2(cc.x, cc.z), float(c["r"]))
		if t2 >= 0.0 and t2 < max_u:
			max_u = t2
	var used := seg_len * maxf(0.0, max_u - 0.03)
	used = clampf(used, minf(1.4, seg_len), seg_len)
	return focus + dir.normalized() * used


## 线段 a→b 与线段 p0→p1 的交点参数（沿 a→b，0..1；无交返回 -1）
func _seg_hit(a: Vector2, b: Vector2, p0: Vector2, p1: Vector2) -> float:
	var r := b - a
	var s := p1 - p0
	var den := r.x * s.y - r.y * s.x
	if absf(den) < 1e-6:
		return -1.0
	var t := ((p0 - a).x * s.y - (p0 - a).y * s.x) / den
	var u := ((p0 - a).x * r.y - (p0 - a).y * r.x) / den
	if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
		return t
	return -1.0


## 线段 a→b 与圆(c, r) 的最早进入参数（0..1；不相交返回 -1）
func _circle_hit(a: Vector2, b: Vector2, c: Vector2, r: float) -> float:
	var d := b - a
	var f := a - c
	var A := d.dot(d)
	if A < 1e-6:
		return -1.0
	var B := 2.0 * f.dot(d)
	var C := f.dot(f) - r * r
	var disc := B * B - 4.0 * A * C
	if disc < 0.0:
		return -1.0
	var t1 := (-B - sqrt(disc)) / (2.0 * A)
	var t2 := (-B + sqrt(disc)) / (2.0 * A)
	if t1 >= 0.0 and t1 <= 1.0:
		return t1
	if t2 >= 0.0 and t2 <= 1.0:
		return t2
	return -1.0
