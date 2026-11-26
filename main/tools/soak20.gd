extends Node
## --soak20 [--soak-level=N]：在坠击中庭(默认5)里额外 spawn 20 个怪
## （14 arc_sentinel + 6 wheel_sentry），预热 3s 后测 8s 帧时。
func _ready() -> void:
	_run.call_deferred()

var _frames: Array = []

func _run() -> void:
	var lv_idx := 5
	var args := OS.get_cmdline_user_args()
	for a in args:
		if String(a).begins_with("--soak-level="):
			lv_idx = int(String(a).split("=")[1])
	TurnSession.open_level(lv_idx)
	while TurnSession.active_level_index() != lv_idx or get_tree().current_scene == null:
		await get_tree().process_frame
	for i in 40:
		await get_tree().process_frame
	var lv: Node = get_tree().current_scene.get_node_or_null("Level")
	if lv == null or not lv.has_method("use_ground_routes") and not lv.has_method("sentry_ground_move"):
		lv = get_tree().current_scene.get_node_or_null("Level")
	var SentinelScr = load("res://runtime/enemies/mobs/arc_sentinel/encounters/galleria/arc_encounter.gd")
	var SentryScr = load("res://runtime/enemies/mobs/wheel_sentry/encounters/galleria/wheel_encounter.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n_sent := 0
	var n_arch := 0
	for i in 20:
		var e
		var is_archer := (i % 10) >= 7
		if is_archer:
			e = SentryScr.new()
			n_arch += 1
		else:
			e = SentinelScr.new()
			n_sent += 1
		lv.add_child(e)
		e.level = lv
		var pos := Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-22, 18))
		if is_archer:
			e.global_position = pos
			e.setup_sentry(PI, 0.95 + float(n_arch) * 0.35)
		else:
			e.global_position = pos
			e.use_ground_routes(lv.sentinel_ground_move, lv.sentinel_support_floor, lv.sentinel_waypoint)
		e.spawn_xf = e.global_transform
		if e.rig != null:
			e.spawn_rig_xf = e.rig.transform
		lv.enemies.append(e)
	print("[soak] enemies=%d (+%d sent +%d arch)" % [lv.enemies.size(), n_sent, n_arch])
	for i in 180:
		await get_tree().process_frame
	_frames.clear()
	var t := 0.0
	while t < 8.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		_frames.append(dt * 1000.0)
		t += dt
	_frames.sort()
	var n := _frames.size()
	var avg := 0.0
	for v in _frames:
		avg += v
	avg /= n
	print("[soak] avg=%.1fms p50=%.1f p99=%.1f max=%.1f draw=%d fps=%.0f" % [
		avg, _frames[n / 2], _frames[int(n * 0.99)], _frames[n - 1],
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		1000.0 / avg])
	get_tree().quit()
