extends Node3D
const MainScene = preload("res://main.tscn")
var game
func _ready():
	game = MainScene.instantiate()
	add_child(game)
	for i in 6: await get_tree().process_frame
	P.set_value("rules.god_mode", true)
	P.set_value("cam.mode", "third")
	game.level.start_level(2)
	for i in 20: await get_tree().process_frame
	for e in game.level.enemies:
		e.global_position = Vector3(0, 0, -55)
	game.player.rig.global_position = Vector3(0,0,20)
	game.player.rig.heading = 0.0
	game.player.rig.rotation.y = 0.0
	game.player.rig.facing_override = true
	game.cam.yaw = 0.0
	game.cam.pitch = -0.42
	P.set_value("cam.distance", 7.7)
	game.cam.snap(game.level.arena)
	game.cam.step(1.0/60.0, game.level.arena)
	game.cam.step(1.0/60.0, game.level.arena)
	for i in 20: await get_tree().process_frame
	game.hud.set_hud_visible(false)
	get_tree().paused = true
	game.fp_mask.set_active(false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img_off := get_tree().root.get_texture().get_image()
	game.fp_mask.set_active(true)
	game.fp_mask.step(game.cam.fp_proj_view(), P.getf("cam.mask_soft"))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img_on := get_tree().root.get_texture().get_image()
	var cam: Camera3D = game.cam.camera
	var pv: Projection = game.cam.fp_proj_view()
	var w := img_on.get_width()
	var h := img_on.get_height()
	print("img=", w, "x", h, " cam=", cam.global_position, " fov=", cam.fov, " near=", cam.near)
	print("vp rect=", cam.get_viewport().get_visible_rect().size, " cam proj=", cam.get_camera_projection())
	print("fp pv=", pv)
	var vr: Vector2 = cam.get_viewport().get_visible_rect().size
	var sx := vr.x / float(w)
	var sy := vr.y / float(h)
	print("scale=", sx, ",", sy)
	print("center ray=", cam.project_ray_normal(Vector2(640.0*sx, 323.0*sy)), " fwd=", -cam.global_transform.basis.z)
	# 中心竖线上的地面点：像素 → 距离 → mxy / sees
	for y in [330, 350, 380, 420, 460, 500, 540, 580, 620, 640]:
		var ray: Vector3 = cam.project_ray_normal(Vector2(640.0*sx, (float(y)+0.5)*sy))
		if ray.y >= 0.0:
			print("  y=%d ray.y=%.3f (no floor)" % [y, ray.y]); continue
		var t: float = cam.global_position.y / -ray.y
		var pt: Vector3 = cam.global_position + ray * t
		var c: Vector4 = pv * Vector4(pt.x, pt.y, pt.z, 1.0)
		var mxy: float = maxf(absf(c.x), absf(c.y)) / c.w
		print("  y=%d dist=%.1f pt=%s mxy=%.4f sees=%s" % [y, t, pt, mxy, game.cam.fp_sees_point(pt)])
	# 分类图：绿=一致，红=预测「看得见」但被涂黑，蓝=预测「看不见」却亮着
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	var body := AABB(Vector3(-2.4, -0.2, 17.6), Vector3(4.8, 5.6, 4.8))
	var stat := {}
	for y in h:
		for x in w:
			var ray: Vector3 = cam.project_ray_normal(Vector2((float(x)+0.5)*sx, (float(y)+0.5)*sy))
			if ray.y > -0.03:
				out.set_pixel(x, y, Color(0.12, 0.12, 0.12)); continue
			var t: float = cam.global_position.y / -ray.y
			var pt: Vector3 = cam.global_position + ray * t
			if absf(pt.x) > 56.0 or absf(pt.z) > 56.0:
				out.set_pixel(x, y, Color(0.2, 0.2, 0.2)); continue
			if body.intersects_segment(cam.global_position, pt):
				out.set_pixel(x, y, Color(0.35, 0.25, 0.1)); continue
			var sees: bool = game.cam.fp_sees_point(pt)
			var lum := _lum(img_on.get_pixel(x, y))
			var black := lum < 0.03
			var key := ("in" if sees else "out") + ("_black" if black else "_lit")
			stat[key] = int(stat.get(key, 0)) + 1
			if sees == black:
				out.set_pixel(x, y, Color(1.0, 0.1, 0.1) if sees else Color(0.1, 0.2, 1.0))
			else:
				out.set_pixel(x, y, Color(0.1, 0.45, 0.15))
	out.save_png("res://shots/dbg_class.png")
	print("stats=", stat)
	print("saved dbg_class.png")
	get_tree().quit()

func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
