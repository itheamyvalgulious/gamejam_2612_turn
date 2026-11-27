extends Node
## Headless performance benchmark driver.
##
## Spawned by ui/menu/menu.gd when "--bench" is present in cmdline user args.
## Lives directly under the scene tree root so it survives TurnSession scene
## switches (the level scenes are freed on switch; root children are not).
##
## Usage:  godot --headless --path main -- --bench [--levels=0,1,2]
##         [--warmup=3] [--measure=15] [--restarts=4] [--soak=0]
##         [--report=/tmp/turn_bench.json]
##
## What it measures per level (CPU side only — headless has no GPU cost):
##   frame wall-time (min/median/p95/p99/max, count >16.7 / >33 / >100 ms)
##   spikes tagged by nearby gameplay events (hit / kill / death / phase change)
##   node / object / memory counters before and after N level restarts
##   wall-time of the restart call itself (arena + enemies rebuilt synchronously)

const Catalog = preload("res://core/level_catalog.gd")

var _args := {}
var _report := {}
var _frames: Array = []          # {ms, tag}
var _events: Array = []          # {t, tag}
var _tag := ""
var _measuring := false
var _t := 0.0
var _attack_cd := 0.0
var _move_cd := 0.0
var _move_dir := 0
var _parry_cd := 0.0
var _prev_alive_count := -1
var _prev_player_alive := true
var _prev_phase_stage := -1
var _done := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", false, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _ready() -> void:
	if _args.has("vsync_off"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("[bench] driver ready, args: ", _args)
	_run_all.call_deferred()


func _process(_delta: float) -> void:
	if not _measuring:
		return
	var ms := _delta * 1000.0
	_frames.append({"ms": ms, "tag": _tag,
		"gpu": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"cpu": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0})
	_tag = ""
	_t += _delta
	_detect_events()


func _detect_events() -> void:
	var level = _level()
	var player = _player()
	if level == null:
		return
	var alive_count := 0
	var enemies: Array = level.get("enemies") if level.get("enemies") != null else []
	for e in enemies:
		if is_instance_valid(e) and e.get("alive"):
			alive_count += 1
	if _prev_alive_count >= 0 and alive_count < _prev_alive_count:
		_mark("kill")
	_prev_alive_count = alive_count
	if player != null:
		var pa: bool = player.get("alive")
		if _prev_player_alive and not pa:
			_mark("player_death")
		_prev_player_alive = pa
	# boss phase transitions (shadow_chamber)
	for e in enemies:
		if is_instance_valid(e) and e.get("controller") != null:
			var st: int = int(e.controller.phase.stage)
			if _prev_phase_stage >= 0 and st != _prev_phase_stage:
				_mark("phase_%d" % st)
			_prev_phase_stage = st


func _mark(tag: String) -> void:
	_events.append({"t": _t, "tag": tag})
	_tag = tag
	# also tag the previous frame — the spike usually shows up there
	if not _frames.is_empty():
		_frames[-1]["tag"] = tag


func _level():
	var cur := get_tree().current_scene
	return cur.get("level") if cur != null else null


func _player():
	var cur := get_tree().current_scene
	return cur.get("player") if cur != null else null


func _cam():
	var cur := get_tree().current_scene
	return cur.get("cam") if cur != null else null


func _counts() -> Dictionary:
	var lights := 0
	var meshes := 0
	var parts := 0
	for n in get_tree().root.find_children("*", "", true, false):
		if n is Light3D:
			lights += 1
		elif n is MeshInstance3D:
			meshes += 1
		elif n is GPUParticles3D or n is CPUParticles3D:
			parts += 1
	var alive_n := 0
	var lvl = _level()
	if lvl != null and lvl.get("enemies") != null:
		for e in lvl.get("enemies"):
			if is_instance_valid(e) and e.get("alive"):
				alive_n += 1
	return {
		"enemies_alive": alive_n,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"mem_static_mb": OS.get_static_memory_usage() / 1048576.0,
		"lights": lights,
		"mesh_instances": meshes,
		"particles": parts,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"render_objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
	}


func _stats(frames: Array) -> Dictionary:
	if frames.is_empty():
		return {}
	var ms: Array = []
	var gpus: Array = []
	var cpus: Array = []
	for f in frames:
		ms.append(f["ms"])
		if f.has("gpu"):
			gpus.append(f["gpu"])
		if f.has("cpu"):
			cpus.append(f["cpu"])
	ms.sort()
	gpus.sort()
	cpus.sort()
	var n := ms.size()
	var sum := 0.0
	for v in ms:
		sum += v
	var tags := {}
	for f in frames:
		var t := String(f["tag"])
		if t == "":
			continue
		tags[t] = int(tags.get(t, 0)) + 1
	var over := {"16.7ms": 0, "33ms": 0, "100ms": 0}
	for v in ms:
		if v > 100.0: over["100ms"] += 1
		elif v > 33.0: over["33ms"] += 1
		elif v > 16.7: over["16.7ms"] += 1
	# worst frames with tags
	var worst: Array = []
	var idx: Array = range(n)
	# take top 8 by ms
	var copy := frames.duplicate()
	copy.sort_custom(func(a, b): return a["ms"] > b["ms"])
	for i in mini(8, copy.size()):
		worst.append({"ms": snappedf(copy[i]["ms"], 0.01), "tag": copy[i]["tag"]})
	return {
		"frames": n,
		"gpu_p50_ms": snappedf(gpus[n / 2], 3) if not gpus.is_empty() else 0.0,
		"gpu_p95_ms": snappedf(gpus[int(n * 0.95)], 3) if not gpus.is_empty() else 0.0,
		"gpu_max_ms": snappedf(gpus[n - 1], 3) if not gpus.is_empty() else 0.0,
		"cpu_p50_ms": snappedf(cpus[n / 2], 3) if not cpus.is_empty() else 0.0,
		"cpu_p95_ms": snappedf(cpus[int(n * 0.95)], 3) if not cpus.is_empty() else 0.0,
		"cpu_max_ms": snappedf(cpus[n - 1], 3) if not cpus.is_empty() else 0.0,
		"seconds": snappedf(sum / 1000.0, 1),
		"avg_ms": snappedf(sum / n, 3),
		"fps_equiv": snappedf(1000.0 / (sum / n), 1),
		"p50_ms": snappedf(ms[n / 2], 3),
		"p95_ms": snappedf(ms[int(n * 0.95)], 3),
		"p99_ms": snappedf(ms[int(n * 0.99)], 3),
		"max_ms": snappedf(ms[n - 1], 2),
		"over_budget": over,
		"event_frames": tags,
		"worst": worst,
	}


func _press(action: String) -> void:
	Input.action_press(action)


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right",
			"attack_light", "attack_heavy", "attack_spin", "parry", "dash", "jump"]:
		Input.action_release(a)


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	Input.action_release(action)


## Drive the player: drift toward enemies, attack, occasionally parry.
func _combat_input(dt: float) -> void:
	var player = _player()
	var level = _level()
	if player == null or level == null or not player.get("alive"):
		_release_all()
		return
	var enemies: Array = level.get("enemies") if level.get("enemies") != null else []
	var prig = player.get("rig")
	if prig == null:
		return
	var target = null
	var best := 1e9
	for e in enemies:
		if not is_instance_valid(e) or not e.get("alive"):
			continue
		var d: float = prig.global_position.distance_to(e.global_position)
		if d < best:
			best = d
			target = e
	_attack_cd -= dt
	_move_cd -= dt
	_parry_cd -= dt
	# point camera at nearest enemy so "seen block" & boss gaze charge work
	if target != null:
		var cam = _cam()
		if cam != null:
			var to: Vector3 = target.global_position - prig.global_position
			cam.yaw = atan2(-to.x, -to.z)
		# stay glued to the fight: teleport within reach if too far (bench only)
		if best > 9.0:
			prig.global_position = target.global_position + Vector3(3.0, 0, 0)
		# approach
		_release_all()
		_press("move_forward")
		# attack when close
		if best < 7.0 and _attack_cd <= 0.0:
			Input.action_press("attack_light")
			await get_tree().process_frame
			Input.action_release("attack_light")
			_attack_cd = 0.45
		elif _parry_cd <= 0.0:
			Input.action_press("parry")
			await get_tree().process_frame
			Input.action_release("parry")
			_parry_cd = 1.1
	elif _move_cd <= 0.0:
		_release_all()
		_move_dir = (_move_dir + 1) % 4
		_press(["move_forward", "move_right", "move_back", "move_left"][_move_dir])
		_move_cd = 2.0


func _run_all() -> void:
	var levels_arg := String(_args.get("levels", ""))
	var indices: Array = []
	if levels_arg.is_empty():
		for i in 10:
			indices.append(i)
	else:
		for s in levels_arg.split(","):
			if s.strip_edges().is_valid_int():
				indices.append(int(s))
	var warmup := float(_args.get("warmup", "3"))
	var measure := float(_args.get("measure", "15"))
	var restarts := int(_args.get("restarts", "4"))
	var soak := float(_args.get("soak", "0"))

	for index in indices:
		print("[bench] level %d %s: loading" % [index, Catalog.get_entry(index)[0]])
		var t0 := Time.get_ticks_msec()
		TurnSession.open_level(index)
		# wait until the level scene is current and its level node exists
		while TurnSession.active_level_index() != index or _level() == null:
			await get_tree().process_frame
		print("[bench] level %d loaded in %d ms" % [index, Time.get_ticks_msec() - t0])
		if _args.has("dump"):
			_dump_mesh_groups()
		var ablate := String(_args.get("ablate", ""))
		if ablate != "":
			await get_tree().process_frame
			await get_tree().process_frame
			_ablate(ablate)
		if _args.has("low_fx"):
			for wn in get_tree().root.find_children("*", "WorldEnvironment", true, false):
				var env: Environment = (wn as WorldEnvironment).environment
				env.ssao_enabled = false
				env.ssr_enabled = false
				env.ssil_enabled = false
				env.glow_enabled = false
				env.volumetric_fog_enabled = false
				env.sdfgi_enabled = false
				print("[bench] low_fx: post effects disabled on ", wn.name)
		var entry := {"load_ms": Time.get_ticks_msec() - t0, "counts_start": _counts()}

		# wait until fight begins (state becomes "fight" or settle 1.5 s)
		var wait := 0.0
		while wait < 8.0:
			var st: String = str(_level().get("state"))
			if st == "fight" or st == "":
				break
			await get_tree().process_frame
			wait += get_process_delta_time()
		var st0: String = str(_level().get("state"))
		# room levels may not use states — just wait a bit
		if st0 != "fight":
			for i in 90:
				await get_tree().process_frame

		# warmup
		var tw := 0.0
		while tw < warmup:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			_combat_input(dt)
			tw += dt

		# measure
		_frames.clear()
		_events.clear()
		_prev_alive_count = -1
		_prev_phase_stage = -1
		_measuring = true
		_t = 0.0
		var tm := 0.0
		while tm < measure:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			_combat_input(dt)
			tm += dt
		_measuring = false
		entry["measure"] = _stats(_frames)
		entry["events"] = _events.duplicate()
		entry["counts_end"] = _counts()
		entry["render"] = {
			"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			"texture_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
			"buffer_mem_mb": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		}

		# restarts: measure restart wall time + counters each round
		var rest: Array = []
		var cur := get_tree().current_scene
		if cur != null and cur.has_method("restart_level"):
			for r in restarts:
				var c0 := _counts()
				var rt0 := Time.get_ticks_msec()
				cur.restart_level()
				var rt := Time.get_ticks_msec() - rt0
				await get_tree().process_frame
				var c1 := _counts()
				rest.append({"restart_ms": rt, "counts_before": c0, "counts_after": c1})
		entry["restarts"] = rest
		entry["counts_final"] = _counts()
		_report[Catalog.get_entry(index)[0]] = entry
		print("[bench] level %d done: avg=%.2fms p99=%.2fms max=%.1fms" %
			[index, entry["measure"].get("avg_ms", 0), entry["measure"].get("p99_ms", 0),
			entry["measure"].get("max_ms", 0)])

	# Optional soak on the last loaded level.
	if soak > 0.0:
		var idx: int = indices[-1]
		_frames.clear()
		_measuring = true
		var ts := 0.0
		var marks: Array = []
		var last_mark := 0.0
		while ts < soak:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			_combat_input(dt)
			ts += dt
			if ts - last_mark >= 30.0:
				last_mark = ts
				marks.append({"t": ts, "counts": _counts(),
					"recent_avg_ms": _recent_avg(300)})
		_measuring = false
		_report["_soak"] = {"level": Catalog.get_entry(idx)[0], "stats": _stats(_frames), "marks": marks}

	var path := String(_args.get("report", "/tmp/opencode/turn_bench.json"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(_report, "  "))
	f.close()
	print("[bench] report written to ", path)
	print("[bench] DONE")
	_done = true
	get_tree().quit()


func _ablate(what: String) -> void:
	var scene := get_tree().current_scene
	var level = _level()
	match what:
		"noshadow":
			for n in scene.find_children("*", "Light3D", true, false):
				(n as Light3D).shadow_enabled = false
		"shadowdist":
			for n in scene.find_children("*", "DirectionalLight3D", true, false):
				(n as DirectionalLight3D).directional_shadow_max_distance = 45.0
		"shadowdist25":
			for n in scene.find_children("*", "DirectionalLight3D", true, false):
				(n as DirectionalLight3D).directional_shadow_max_distance = 25.0
		"noenemy":
			for e in (level.get("enemies") if level else []):
				if is_instance_valid(e) and e.rig != null:
					e.rig.visible = false
			var p = _player()
			if p != null and p.get("rig") != null:
				# keep player; test enemy only
				pass
		"noenemyshadow":
			var level2 = _level()
			var rigs: Array = []
			if level2 != null:
				for e in (level2.get("enemies") if level2.get("enemies") != null else []):
					if is_instance_valid(e) and e.get("rig") != null:
						rigs.append(e.rig)
			var p2 = _player()
			if p2 != null and p2.get("rig") != null:
				rigs.append(p2.rig)
			for r in rigs:
				for n in r.find_children("*", "MeshInstance3D", true, false):
					(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"noarena":
			var an = level.get("arena_node") if level else null
			if an != null:
				an.visible = false
		"nosubvp":
			for n in scene.find_children("*", "SubViewport", true, false):
				(n as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
		"nolights":
			for n in scene.find_children("*", "Light3D", true, false):
				(n as Light3D).visible = false
		"noomni":
			for n in scene.find_children("*", "Light3D", true, false):
				if not (n is DirectionalLight3D):
					(n as Light3D).visible = false
		"noparticles":
			for n in scene.find_children("*", "GPUParticles3D", true, false):
				(n as GPUParticles3D).emitting = false
				n.visible = false
		"all_off":
			pass
	print("[bench] ablate: ", what)


func _dump_mesh_groups() -> void:
	var groups := {}
	var scene := get_tree().current_scene
	var level = _level()
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		# group by direct child of `level` (arena / each enemy) when possible
		var top: Node = n
		var parent_chain: Node = n
		while parent_chain.get_parent() != null and parent_chain.get_parent() != scene:
			top = parent_chain
			parent_chain = parent_chain.get_parent()
		var key := str(top.name)
		if level != null and is_instance_valid(level) and top == level:
			# one level deeper: which child of level
			var c: Node = n
			while c.get_parent() != null and c.get_parent() != level:
				c = c.get_parent()
			key = "Level/" + str(c.name)
		groups[key] = int(groups.get(key, 0)) + 1
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a] > groups[b])
	for k in keys:
		print("[mesh] %-44s %d" % [k, groups[k]])


func _recent_avg(n: int) -> float:
	var take := mini(n, _frames.size())
	if take <= 0:
		return 0.0
	var sum := 0.0
	for i in range(_frames.size() - take, _frames.size()):
		sum += _frames[i]["ms"]
	return sum / take
