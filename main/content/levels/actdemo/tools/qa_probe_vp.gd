extends Node3D

func _ready() -> void:
	await get_tree().process_frame
	var vp := get_viewport()
	print("viewport size=", vp.get_visible_rect().size, " window size=", get_window().size,
		" screen=", DisplayServer.window_get_size())
	print("keep_aspect=", get_window().content_scale_aspect, " stretch mode=", get_window().content_scale_mode)
	print("project viewport=", ProjectSettings.get_setting("display/window/size/viewport_width"), "x",
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	get_window().size = Vector2i(1600, 900)
	await get_tree().process_frame
	await get_tree().process_frame
	print("after set: viewport=", vp.get_visible_rect().size, " window=", get_window().size)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 68.0
	cam.current = true
	print("cam fov=", cam.fov, " keep_aspect=", cam.keep_aspect, " h=", cam.get_camera_projection().get_fov())
	await get_tree().process_frame
	print("fov after in-tree=", cam.fov)
	# 手动算横屏半 FOV
	var sz: Vector2 = vp.get_visible_rect().size
	print("aspect=", sz.x / sz.y, " half_h=", rad_to_deg(atan(tan(deg_to_rad(cam.fov) * 0.5) * (sz.x / sz.y))))
	get_tree().quit(0)
