extends SceneTree
## Verifies: loop wraps for idle/walk, set_loop(false) clamps, loop-seam module
## delta, and the shuriken clears after the attack clip.

func _initialize() -> void:
	var ch = load("res://scenes/character.tscn").instantiate()
	root.add_child(ch)
	ch.set_process(false)
	for i in 4:
		await process_frame
	# ---- loop seam (modules), at t=0 vs t=dur
	for anim in ["idle", "walk"]:
		ch.play_anim(anim)
		ch.set_playing(false)
		var d: float = ch.anim_duration()
		ch.set_anim_time(0.0)
		ch.field.update_assembled(ch.P["module_breath"], 0.0, d)
		var a: Array = []
		for m in ch.field.mods:
			a.append(m["node"].global_position)
		ch.set_anim_time(d)
		ch.field.update_assembled(ch.P["module_breath"], d, d)
		var mx := 0.0
		for i in ch.field.mods.size():
			mx = maxf(mx, a[i].distance_to(ch.field.mods[i]["node"].global_position))
		print("[loop] %s seam_module_delta=%.6f m" % [anim, mx])
	# ---- idle soak 10 s: wraps
	ch.play_anim("idle")
	ch.set_playing(true)
	ch.set_loop(true)
	var prev: float = ch.anim_time()
	var wraps := 0
	var tmin := 1e9
	var tmax := -1e9
	for i in 600:
		ch._process(1.0 / 60.0)
		var t: float = ch.anim_time()
		if t < prev:
			wraps += 1
		prev = t
		tmin = minf(tmin, t)
		tmax = maxf(tmax, t)
	print("[loop] idle_10s wraps=%d t_range=[%.3f,%.3f] dur=%.3f" % [wraps, tmin, tmax, ch.anim_duration()])
	# ---- walk soak 10 s: wraps
	ch.play_anim("walk")
	ch.set_playing(true)
	prev = ch.anim_time()
	wraps = 0
	for i in 600:
		ch._process(1.0 / 60.0)
		var t: float = ch.anim_time()
		if t < prev:
			wraps += 1
		prev = t
	print("[loop] walk_10s wraps=%d dur=%.3f t=%.3f" % [wraps, ch.anim_duration(), ch.anim_time()])
	# ---- set_loop(false) must clamp
	ch.play_anim("idle")
	ch.set_playing(true)
	ch.set_loop(false)
	for i in 500:
		ch._process(1.0 / 60.0)
	print("[loop] idle_noloop_8s3 t=%.3f dur=%.3f (must equal dur)" % [ch.anim_time(), ch.anim_duration()])
	# ---- loop flag per clip
	ch.play_anim("attack")
	print("[loop] loop_flag idle=%s attack=%s" % [ch.is_looping(), ch.is_looping()])
	ch.play_anim("idle")
	print("[loop] loop_flag after idle=%s" % ch.is_looping())
	ch.play_anim("attack")
	print("[loop] loop_flag after attack=%s" % ch.is_looping())
	# ---- shuriken after the attack
	ch.play_anim("attack")
	ch.set_playing(true)
	var mid_active := false
	for i in 600:
		ch._process(1.0 / 60.0)
		if i == 80:
			mid_active = ch.shurikens[0].active
	var vis := 0
	for s in ch.shurikens:
		if s.active or s.visible:
			vis += 1
	print("[shot] attack_10s mid_active=%s final_visible=%d shot_age=%.3f clip_t=%.3f dur=%.3f" % [mid_active, vis, ch._shot_age, ch.anim_time(), ch.anim_duration()])
	quit(0)
