extends Node3D
## 5-second average fps + draw calls at 1600x900 with the studio scene.

func _ready() -> void:
	var st: Node = load("res://scenes/studio.tscn").instantiate()
	add_child(st)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in 90:
		await get_tree().process_frame
	# warm glow + animation running
	var t0 := Time.get_ticks_usec()
	var frames := 0
	while Time.get_ticks_usec() - t0 < 6_000_000:
		await get_tree().process_frame
		frames += 1
	var secs := float(Time.get_ticks_usec() - t0) / 1_000_000.0
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prim := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("[perf] avg_fps=%.1f frames=%d secs=%.2f draw_calls=%d primitives=%d" % [float(frames) / secs, frames, secs, dc, prim])
	get_tree().quit(0)
