extends Node3D
## Frame-rate probe for the studio scene at 1600x900.
const STUDIO := preload("res://scenes/studio.tscn")

func _ready() -> void:
	var studio = STUDIO.instantiate()
	add_child(studio)
	get_window().size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in 90:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var n := 0
	var dsum := 0
	var psum := 0
	var mn := 999.0
	while Time.get_ticks_usec() - t0 < 3000000:
		await get_tree().process_frame
		n += 1
		var fps := Engine.get_frames_per_second()
		mn = minf(mn, fps)
		dsum += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		psum += int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var secs := float(Time.get_ticks_usec() - t0) / 1000000.0
	print("PERF frames %d in %.2fs -> %.1f fps avg (min %d)  draw calls %d  prims %d" % [
		n, secs, float(n) / secs, int(mn), int(float(dsum) / float(maxi(n, 1))),
		int(float(psum) / float(maxi(n, 1)))])
	get_tree().quit()
