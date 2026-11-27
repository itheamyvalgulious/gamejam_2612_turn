extends Node
## True-play GPU benchmark.
##
## 与 bench.gd 的区别：不传送玩家、不隐藏任何东西。通过和真人相同的 Input
## 动作从出生点走进中庭、接近并攻击最近的敌人，所有敌人保持活跃；用真 GPU
## 在 DISPLAY=:10 上渲染整帧，逐帧记录墙钟耗时。
##
## Usage:
##   DISPLAY=:10 godot --path main -- --play-bench --level=1 \
##       --warmup=8 --measure=30 --report=/tmp/opencode/play_bench.json
##
## 可选诊断（只用于定位，不用于验收）：
##   --ablate=enemies|arena|lights|shadows|gi|probe|player|particles
##   --hud=0        测量时不打开 F5 调试 HUD
##   --screenshot=/path.png

const Catalog = preload("res://core/level_catalog.gd")

var _args := {}
var _frames: Array = []
var _events: Array = []
var _phase := "idle"
var _t := 0.0
var _nav_prof := false
var _nav_acc := 0.0
var _since_report := 0.0
var _measure := 20.0
var _warmup := 6.0
var _attack_cd := 0.0
var _jump_cd := 0.0
var _stuck := 0.0
var _last_pos := Vector3.ZERO
var _snapshots: Array = []
var _level_index := Catalog.index_for_id("galleria")
var _player
var _level
var _cam
var _hud_toggled := false
var _idle := false
var _parry_always := false
var _parry_contact_dir := ""
var _parry_contact_seq := -1
var _parry_contact_idx := 0
var _parry_shots := ""
var _parry_shot_idx := 0
var _parry_shot_t := 0.0
var _last_start_usec := 0
var _last_mid_usec := 0
var _last_tail_usec := 0
var _gpu_ms := 0.0
var _gpu_tick := 0
var _gpu_query := true
## GPU 回读是同步查询（驱动等管线），每帧调会周期性把等待打进帧时间。
## 降频到每 30 帧查一次；--gpu-timing=0 完全关闭（报告里 gpu_* 为 0）。
const GPU_QUERY_INTERVAL := 30
var _tail: Node
var _mid: Node


class TailProbe:
	extends Node
	var driver


	func _process(_delta: float) -> void:
		driver._last_tail_usec = Time.get_ticks_usec()


class MidProbe:
	extends Node
	var driver


	func _process(_delta: float) -> void:
		driver._last_mid_usec = Time.get_ticks_usec()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", false, 1)
			if kv.is_empty():
				continue
			_args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _ready() -> void:
	print("[play-bench] ready, args: ", _args)
	process_priority = -10000
	_mid = MidProbe.new()
	_mid.driver = self
	_mid.process_priority = -1
	add_child(_mid)
	_tail = TailProbe.new()
	_tail.driver = self
	_tail.process_priority = 10000
	add_child(_tail)
	_run.call_deferred()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _phase != "warmup" and _phase != "measure":
		return
	if _phase == "measure":
		var ms := delta * 1000.0
		var proc_ms := (_last_tail_usec - _last_start_usec) / 1000.0 if _last_tail_usec > 0 else 0.0
		var gap_ms := (now - _last_tail_usec) / 1000.0 if _last_tail_usec > 0 else 0.0
		var driver_ms := (_last_mid_usec - _last_start_usec) / 1000.0 if _last_mid_usec > 0 else 0.0
		var game_ms := (_last_tail_usec - _last_mid_usec) / 1000.0 if _last_tail_usec > 0 else 0.0
		_gpu_tick += 1
		if _gpu_query and _gpu_tick >= GPU_QUERY_INTERVAL:
			_gpu_tick = 0
			_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(
				get_viewport().get_viewport_rid())
		_frames.append({"ms": ms,
			"process": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"physics": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			"proc": proc_ms,
			"game": game_ms,
			"driver": driver_ms,
			"gap": gap_ms,
			"gpu": _gpu_ms,
			"setup": RenderingServer.get_frame_setup_time_cpu() * 1000.0})
		_last_start_usec = now
		_t += delta
		_since_report += delta
		# 尖峰捕获：>38ms 帧记录分解，定位卡顿来源。
		if ms > 38.0:
			var df = _level.get_node_or_null("DeathField") if _level != null else null
			var dfs: String = df.prof_dump() if df != null and df.has_method("prof_dump") else ""
			var nav = _level.get("nav") if _level != null else null
			var navs: String = nav.prof_dump() if nav != null and nav.has_method("prof_dump") else ""
			var mons := PackedStringArray()
			for m in [Performance.TIME_PHYSICS_PROCESS,
					Performance.TIME_NAVIGATION_PROCESS,
					Performance.PHYSICS_2D_ACTIVE_OBJECTS,
					Performance.PHYSICS_3D_ACTIVE_OBJECTS,
					Performance.PHYSICS_3D_COLLISION_PAIRS,
					Performance.PHYSICS_3D_ISLAND_COUNT,
					Performance.MEMORY_STATIC,
					Performance.MEMORY_MESSAGE_BUFFER_MAX]:
				mons.append("%s=%s" % [m, Performance.get_monitor(m)])
			print("[play-bench] SPIKE t=%.2f ms=%.0f node=%.1f game=%.1f gap=%.1f gpu=%.1f setup=%.1f | death{%s} | nav{%s} | %s" % [
				_t, ms, proc_ms, game_ms, gap_ms, _gpu_ms,
				RenderingServer.get_frame_setup_time_cpu() * 1000.0, dfs, navs,
				", ".join(mons)])
		# 接触帧定格截图：on_block 当帧写入 parry_contact，下一帧抓到刚渲染
		# 出来的画面（架住火花/HUD 都在）。
		if _parry_contact_dir != "" and _player != null:
			var pc: Dictionary = _player.get("parry_contact")
			if not pc.is_empty() and int(pc.get("seq", -1)) != _parry_contact_seq:
				_parry_contact_seq = int(pc.get("seq", -1))
				_capture_contact(pc)
		if _parry_shots != "":
			_parry_shot_t += delta
			if _parry_shot_t >= 2.6:
				_parry_shot_t = 0.0
				_parry_shot_idx += 1
				var im: Image = get_viewport().get_texture().get_image()
				im.save_png("%s/shot_%02d.png" % [_parry_shots, _parry_shot_idx])
		if _since_report >= 5.0:
			_since_report = 0.0
			_snapshot("t+%.0f" % _t)
			print("[play-bench] t+%.0fs frames=%d p50=%.1fms" % [
				_t, _frames.size(), _recent_p50()])
		# --nav-profile：每秒打印 nav_field 打点并清零（nav.prof_dump 自带 clear）。
		if _nav_prof:
			_nav_acc += delta
			if _nav_acc >= 1.0:
				_nav_acc = 0.0
				var nav = _level.get("nav") if _level != null else null
				if nav != null and nav.has_method("prof_dump"):
					print("[nav-prof] %.2fs | %s" % [_t, nav.prof_dump()])
	_drive(delta)


## 接触帧定格：发现 parry_contact 更新后等一帧（这一帧才渲染出「架住」
## 画面），截图 + 打数值，再睡 150ms 让人能看出定格。
func _capture_contact(pc: Dictionary) -> void:
	_parry_contact_idx += 1
	var idx := _parry_contact_idx
	var nums := pc.duplicate()
	await get_tree().process_frame
	var im: Image = get_viewport().get_texture().get_image()
	var path := "%s/contact_%02d.png" % [_parry_contact_dir, idx]
	im.save_png(path)
	print("[play-bench] CONTACT #%d %s | a·b=%.3f e·n=%.3f v×a deg=%.1f v_meas=%.1f v·e=%.1f pos_err=%.2f t_err=%.2f %s/%s tk=%s tracked=%s valid=%s" % [
		idx, path, nums.get("ab_dot", 0.0), nums.get("en_dot", 0.0),
		nums.get("va_deg", 0.0), nums.get("v_meas", 0.0), nums.get("ve_dot", 0.0),
		nums.get("pos_err", 0.0), nums.get("t_err", 0.0),
		nums.get("kind", "?"), nums.get("phase", "?"),
		nums.get("tk", false),
		nums.get("tracked", false), nums.get("valid", false)])
	OS.delay_msec(150)


func _run() -> void:
	if _args.has("level"):
		_level_index = int(_args["level"])
	_warmup = float(_args.get("warmup", "6"))
	_measure = float(_args.get("measure", "20"))
	_idle = _args.has("idle")
	_nav_prof = "--nav-profile" in OS.get_cmdline_user_args()
	_parry_always = _args.has("parry-always")
	_parry_contact_dir = String(_args.get("parry-contact", ""))
	if _parry_contact_dir != "":
		DirAccess.make_dir_recursive_absolute(_parry_contact_dir)
	_parry_shots = String(_args.get("parry-shots", ""))
	if _parry_shots != "":
		DirAccess.make_dir_recursive_absolute(_parry_shots)
	print("[play-bench] opening level %d %s" % [_level_index, Catalog.get_entry(_level_index)[0]])
	TurnSession.open_level(_level_index)
	while TurnSession.active_level_index() != _level_index:
		await get_tree().process_frame
	while get_tree().current_scene == null or get_tree().current_scene.get("level") == null:
		await get_tree().process_frame
	_level = get_tree().current_scene.get("level")
	_player = get_tree().current_scene.get("player")
	_cam = get_tree().current_scene.get("cam")
	# 无敌：默认开启，除非传 --no-god-mode。
	TurnSession.set_game_param("rules.god_mode", not _args.has("no-god-mode"))
	while str(_level.get("state")) != "fight" and str(_level.get("state")) != "":
		await get_tree().process_frame
	_gpu_query = _args.get("gpu-timing", "1") != "0"
	if not _gpu_query:
		_gpu_ms = 0.0
	if _args.get("hud", "1") != "0":
		TurnSession.toggle_debug_hud()
		_hud_toggled = true
	else:
		# --hud=0：连 F5 及其 GPU 计时查询一并关死，保证干净测量。
		TurnSession.force_debug_hud_off()
	# GPU 回读计数独立于 HUD：hud=0 时也能要 gpu_* 数据（30 帧一次）。
	if _gpu_query:
		RenderingServer.viewport_set_measure_render_time(
			get_viewport().get_viewport_rid(), true)
	if _args.has("ablate"):
		await get_tree().process_frame
		await get_tree().process_frame
		for part in String(_args["ablate"]).split(",", false):
			_ablate(part)
	if _args.has("inspect"):
		_inspect_rigs()
	_snapshot("start")
	var arena: Dictionary = _level.get("arena")
	print("[play-bench] warmup %.1fs (真实输入、无传送), enemies=%d, solids=%d walkables=%d" %
		[_warmup, (_level.get("enemies") as Array).size(),
		(arena.get("solids", []) as Array).size(), (arena.get("walkables", []) as Array).size()])
	_phase = "warmup"
	var tw := 0.0
	while tw < _warmup:
		await get_tree().process_frame
		tw += get_process_delta_time()
	_frames.clear()
	_events.clear()
	_t = 0.0
	_snapshot("measure-start")
	_phase = "measure"
	print("[play-bench] measuring %.1fs ..." % _measure)
	while _phase == "measure" and _t < _measure:
		await get_tree().process_frame
	_phase = "done"
	_release_all()
	var stats := _stats()
	if _parry_always or _args.has("parry-stats"):
		var ps: Dictionary = _player.get("parry_stats") if _player != null else {}
		stats["parry"] = ps
		var sw: int = ps.get("swings", 0)
		var bl: int = ps.get("blocks", 0)
		print("[play-bench] PARRY swings=%d blocks=%d hits=%d rate=%.1f%% strikes=%d fallback=%d | rej self=%d joints=%d reach=%d spin=%d | active_valid=%d active_invalid=%d | contact_d=%s" % [
			sw, bl, ps.get("hits", 0),
			(bl * 100.0 / maxf(sw, 1)), ps.get("strikes", 0), ps.get("fallback", 0),
			ps.get("rej_self", 0), ps.get("rej_joints", 0), ps.get("rej_reach", 0),
			ps.get("rej_spin", 0),
			ps.get("active_valid", 0), ps.get("active_invalid", 0),
			str(ps.get("contact_d", []))])
		print("[play-bench] PARRY blocks_fb=%d (fallback 路径格挡，不占主动迎击)" % [
			ps.get("blocks_fb", 0)])
		print("[play-bench] PARRY ms threat=%.1f(n=%d) clash=%.1f find=%.1f reach=%.1f strike=%.1f planb=%.1f | budget reach=%d planb=%d" % [
			float(ps.get("ms_threat", 0.0)), int(ps.get("n_threat", 0)),
			float(ps.get("ms_clash", 0.0)),
			float(ps.get("ms_find", 0.0)), float(ps.get("ms_reach", 0.0)),
			float(ps.get("ms_strike", 0.0)), float(ps.get("ms_planb", 0.0)),
			int(ps.get("gate_budget_reach", 0)), int(ps.get("gate_budget_planb", 0))])
		var gates := {}
		for k in ps:
			if String(k).begins_with("gate_"):
				gates[k] = ps[k]
		print("[play-bench] PARRY gates=%s" % str(gates))
		var ap = load("res://core/active_parry.gd")
		var fl: Array = ap.usec_list.duplicate()
		fl.sort()
		var p95: float = fl[min(int(fl.size() * 0.95), fl.size() - 1)] \
			if not fl.is_empty() else 0.0
		print("[play-bench] PARRY find_calls=%d find_ms=%.1f avg=%.2fms p95=%.2fms max=%.2fms" % [
			ap.calls, ap.usec_total, ap.usec_total / maxf(ap.calls, 1), p95,
			fl[-1] if not fl.is_empty() else 0.0])
	print("[play-bench] RESULT p50=%.1fms p95=%.1fms p99=%.1fms max=%.1fms avg=%.1fms fps=%.1f frames=%d | game=%.1f driver=%.1f gap=%.1f/%.1f gpu=%.1f/%.1f setup=%.1f/%.1f | vp=%s tex=%s scale=%.2f" % [
		stats.get("p50_ms", 0), stats.get("p95_ms", 0), stats.get("p99_ms", 0),
		stats.get("max_ms", 0), stats.get("avg_ms", 0), stats.get("fps_avg", 0),
		stats.get("frames", 0),
		stats.get("game_process_p50_ms", 0), stats.get("driver_process_p50_ms", 0),
		stats.get("post_process_gap_p50_ms", 0), stats.get("post_process_gap_p95_ms", 0),
		stats.get("gpu_p50_ms", 0), stats.get("gpu_p95_ms", 0),
		stats.get("render_setup_p50_ms", 0), stats.get("render_setup_p95_ms", 0),
		str(get_viewport().size), str(get_viewport().get_texture().get_size()),
		get_viewport().scaling_3d_scale])
	if _args.has("navview"):
		# 与 F6 相同的路径：只走 TurnSession.toggle_nav_view()。
		TurnSession.toggle_nav_view()
		await get_tree().process_frame
		await get_tree().process_frame
	if _args.has("colview"):
		# 与 F7 相同的路径：物理体 debug 视图。
		TurnSession.toggle_collision_view()
		await get_tree().process_frame
		await get_tree().process_frame
	if _args.has("screenshot"):
		await _screenshot(String(_args["screenshot"]))
	_write_report(stats)
	if _gpu_query:
		RenderingServer.viewport_set_measure_render_time(
			get_viewport().get_viewport_rid(), false)
	if _hud_toggled:
		TurnSession.toggle_debug_hud()
	print("[play-bench] DONE")
	get_tree().quit()


# ------------------------------------------------------------------ driving
## 完全通过 Input 动作驱动：WASD 移动、左键攻击、偶尔跳跃/弹反。
func _drive(delta: float) -> void:
	if _idle:
		_release_all()
		if _cam != null:
			_cam.yaw = 0.0
			_cam.pitch = -0.20
		return
	if not is_instance_valid(_player) or not is_instance_valid(_level) or not bool(_player.get("alive")):
		_release_all()
		return
	var rig = _player.get("rig")
	if rig == null:
		return
	var enemies: Array = _level.get("enemies")
	var target = null
	var best := 1e9
	for e in enemies:
		if is_instance_valid(e) and bool(e.get("alive")):
			var d: float = rig.global_position.distance_to(e.global_position)
			if d < best:
				best = d
				target = e
	if target == null:
		_release_all()
		return
	if _cam != null:
		var to: Vector3 = target.global_position - rig.global_position
		_cam.yaw = atan2(-to.x, -to.z)
		# 真人会俯视场内的敌人；高台上先看到整个中庭。
		_cam.pitch = clampf(-0.14 - best * 0.006, -0.42, -0.10)
	_attack_cd -= delta
	_jump_cd -= delta
	var moved: float = rig.global_position.distance_to(_last_pos)
	_last_pos = rig.global_position
	if moved < 0.02 and best > 4.0:
		_stuck += delta
	else:
		_stuck = 0.0
	_release_all()
	if _stuck > 1.2 and _jump_cd <= 0.0:
		Input.action_press("jump")
		_jump_cd = 1.6
		_stuck = 0.0
	# --parry-always：无敌 + 一有机会就弹反，在敌刀半径内贴身缠斗量格挡率
	if _parry_always:
		if best > 2.9:
			Input.action_press("move_forward")
		elif best < 2.0:
			Input.action_press("move_back")
		elif best < 3.4:
			Input.action_press("move_right" if int(Time.get_ticks_msec() / 2400) % 2 == 0 else "move_left")
		# 直接触发 _begin_parry：不依赖 InputMap/按键，CD 由 player.parry_cd 管
		if _player.has_method("_begin_parry") and float(_player.get("parry_cd")) <= 0.0 \
				and not bool(rig.get("is_attacking")):
			_player.call("_begin_parry")
		return
	# 验收基准默认不打怪：保证测量全程 6 只敌人同时活跃（死亡会减少场景负载）。
	var keep_enemies := String(_args.get("keep-enemies", "1")) != "0"
	if keep_enemies:
		# 在敌人周围绕圈：不靠近到贴身，也不离开战斗区。
		if best > 9.0:
			Input.action_press("move_forward")
		elif best < 5.0:
			Input.action_press("move_back")
		else:
			Input.action_press("move_right" if int(Time.get_ticks_msec() / 2100) % 2 == 0 else "move_left")
		if _jump_cd <= 0.0 and moved < 0.02:
			Input.action_press("jump")
			_jump_cd = 1.6
	else:
		if best > 3.6:
			Input.action_press("move_forward")
			if _jump_cd <= 0.0 and moved < 0.02:
				Input.action_press("jump")
				_jump_cd = 1.6
		if best < 5.2 and _attack_cd <= 0.0:
			Input.action_press("attack_light")
			_attack_cd = 0.5
		# 靠近时偶尔横移，模拟真人绕侧，也避免一直贴脸卡住
		if best < 4.0:
			Input.action_press("move_right" if int(Time.get_ticks_msec() / 1700) % 2 == 0 else "move_left")


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right",
			"attack_light", "attack_heavy", "attack_spin", "parry", "dash", "jump"]:
		Input.action_release(a)


# ------------------------------------------------------------------ ablate
func _ablate(what: String) -> void:
	var scene := get_tree().current_scene
	match what:
		"enemies":
			for e in _level.get("enemies"):
				if is_instance_valid(e) and e.get("rig") != null:
					e.rig.visible = false
		"player":
			if _player != null and _player.get("rig") != null:
				_player.rig.visible = false
		"arena":
			var an = _level.get("arena_node")
			if an != null:
				an.visible = false
		"lights":
			for n in scene.find_children("*", "Light3D", true, false):
				(n as Light3D).visible = false
		"shadows":
			for n in scene.find_children("*", "GeometryInstance3D", true, false):
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"rigshadow":
			# 只关角色（玩家+敌人）的投影：arena 阴影保留，区分 rig 投影成本。
			var rigs := []
			for e in _level.get("enemies"):
				if is_instance_valid(e) and e.get("rig") != null:
					rigs.append(e.rig)
			if _player != null and _player.get("rig") != null:
				rigs.append(_player.rig)
			for r in rigs:
				for n in (r as Node).find_children("*", "GeometryInstance3D", true, false):
					(n as GeometryInstance3D).cast_shadow = \
						GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"gi":
			for n in scene.find_children("*", "VoxelGI", true, false):
				(n as VoxelGI).visible = false
		"probe":
			for n in scene.find_children("*", "ReflectionProbe", true, false):
				(n as ReflectionProbe).visible = false
		"particles":
			for n in scene.find_children("*", "GPUParticles3D", true, false):
				(n as GPUParticles3D).emitting = false
				n.visible = false
		"post":
			for n in scene.find_children("*", "WorldEnvironment", true, false):
				var env: Environment = (n as WorldEnvironment).environment
				env.glow_enabled = false
				env.fog_enabled = false
				env.ssr_enabled = false
				env.ssao_enabled = false
				env.volumetric_fog_enabled = false
		"msaa":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"hud":
			var game_hud = scene.get("hud")
			if game_hud != null:
				game_hud.visible = false
			var debug_hud := TurnSession.get_node_or_null("DebugHud")
			if debug_hud != null:
				debug_hud.visible = false
		"all":
			for e in _level.get("enemies"):
				if is_instance_valid(e) and e.get("rig") != null:
					e.rig.visible = false
			if _player != null and _player.get("rig") != null:
				_player.rig.visible = false
			var an = _level.get("arena_node")
			if an != null:
				an.visible = false
			for n in scene.find_children("*", "Light3D", true, false):
				(n as Light3D).visible = false
	print("[play-bench] ablate=", what)


# ------------------------------------------------------------------ report
func _snapshot(tag: String) -> void:
	var scene := get_tree().current_scene
	var meshes := 0
	var lights := 0
	var gi := 0
	var probes := 0
	if scene != null:
		meshes = scene.find_children("*", "MeshInstance3D", true, false).size()
		lights = scene.find_children("*", "Light3D", true, false).size()
		gi = scene.find_children("*", "VoxelGI", true, false).size()
		probes = scene.find_children("*", "ReflectionProbe", true, false).size()
	var alive := 0
	var total := 0
	if _level != null and _level.get("enemies") != null:
		for e in _level.get("enemies"):
			if is_instance_valid(e):
				total += 1
				if bool(e.get("alive")):
					alive += 1
	_snapshots.append({
		"tag": tag,
		"time_s": snappedf(Time.get_ticks_msec() / 1000.0, 0.01),
		"enemies_alive": alive,
		"enemies_total": total,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"mesh_instances": meshes,
		"lights": lights,
		"voxel_gi": gi,
		"reflection_probes": probes,
	})


func _stats() -> Dictionary:
	if _frames.is_empty():
		return {}
	var values: Array[float] = []
	var process_values: Array[float] = []
	var proc_values: Array[float] = []
	var game_values: Array[float] = []
	var driver_values: Array[float] = []
	var gap_values: Array[float] = []
	var gpu_values: Array[float] = []
	var setup_values: Array[float] = []
	var sum := 0.0
	for f in _frames:
		values.append(float(f["ms"]))
		process_values.append(float(f["process"]))
		proc_values.append(float(f.get("proc", 0.0)))
		game_values.append(float(f.get("game", 0.0)))
		driver_values.append(float(f.get("driver", 0.0)))
		gap_values.append(float(f.get("gap", 0.0)))
		gpu_values.append(float(f.get("gpu", 0.0)))
		setup_values.append(float(f.get("setup", 0.0)))
		sum += float(f["ms"])
	values.sort()
	process_values.sort()
	proc_values.sort()
	game_values.sort()
	driver_values.sort()
	gap_values.sort()
	gpu_values.sort()
	setup_values.sort()
	var n := values.size()
	var over := {"16.7ms": 0, "33ms": 0, "50ms": 0, "80ms": 0, "100ms": 0}
	for v in values:
		if v > 100.0:
			over["100ms"] += 1
		elif v > 80.0:
			over["80ms"] += 1
		elif v > 50.0:
			over["50ms"] += 1
		elif v > 33.0:
			over["33ms"] += 1
		elif v > 16.7:
			over["16.7ms"] += 1
	var worst: Array = []
	for i in n:
		worst.append({"ms": snappedf(values[n - 1 - i], 0.01)})
		if worst.size() >= 10:
			break
	return {
		"frames": n,
		"avg_ms": snappedf(sum / n, 3),
		"fps_avg": snappedf(1000.0 / (sum / n), 1),
		"p50_ms": snappedf(values[n / 2], 3),
		"p95_ms": snappedf(values[mini(int(n * 0.95), n - 1)], 3),
		"p99_ms": snappedf(values[mini(int(n * 0.99), n - 1)], 3),
		"max_ms": snappedf(values[n - 1], 3),
		"min_ms": snappedf(values[0], 3),
		"process_p50_ms": snappedf(process_values[n / 2], 3),
		"process_p95_ms": snappedf(process_values[mini(int(n * 0.95), n - 1)], 3),
		"node_process_p50_ms": snappedf(proc_values[n / 2], 3),
		"node_process_p95_ms": snappedf(proc_values[mini(int(n * 0.95), n - 1)], 3),
		"game_process_p50_ms": snappedf(game_values[n / 2], 3),
		"driver_process_p50_ms": snappedf(driver_values[n / 2], 3),
		"gpu_p50_ms": snappedf(gpu_values[n / 2], 3),
		"gpu_p95_ms": snappedf(gpu_values[mini(int(n * 0.95), n - 1)], 3),
		"post_process_gap_p50_ms": snappedf(gap_values[n / 2], 3),
		"post_process_gap_p95_ms": snappedf(gap_values[mini(int(n * 0.95), n - 1)], 3),
		"render_setup_p50_ms": snappedf(setup_values[n / 2], 3),
		"render_setup_p95_ms": snappedf(setup_values[mini(int(n * 0.95), n - 1)], 3),
		"over_budget": over,
		"worst": worst,
	}


func _write_report(stats: Dictionary) -> void:
	var path := String(_args.get("report", "/tmp/opencode/play_bench.json"))
	var report := {
		"level": Catalog.get_entry(_level_index)[0],
		"level_index": _level_index,
		"display": OS.get_environment("DISPLAY"),
		"renderer": RenderingServer.get_video_adapter_name(),
		"viewport": str(get_viewport().get_visible_rect().size),
		"viewport_size": str(get_viewport().size),
		"texture_size": str(get_viewport().get_texture().get_size()),
		"window": str(DisplayServer.window_get_size()),
		"screen_scale": DisplayServer.screen_get_scale(),
		"screen_dpi": DisplayServer.screen_get_dpi(),
		"content_scale_factor": get_window().content_scale_factor,
		"content_scale_size": str(get_window().content_scale_size),
		"content_scale_mode": get_window().content_scale_mode,
		"stretch_scale_setting": ProjectSettings.get_setting("display/window/stretch/scale", -1),
		"scaling_3d_scale": get_viewport().scaling_3d_scale,
		"measure_s": _measure,
		"stats": stats,
		"snapshots": _snapshots,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[play-bench] report written to ", path)


## 诊断：按直接父节点统计 MeshInstance3D 数量，找出模型碎片化位置。
func _inspect_rigs() -> void:
	var reported := {}
	for e in _level.get("enemies"):
		if not is_instance_valid(e) or e.get("rig") == null:
			continue
		var kind := String(e.kind)
		if reported.has(kind) and int(reported[kind]) >= 1:
			continue
		reported[kind] = int(reported.get(kind, 0)) + 1
		var root: Node = e.rig
		var counts := {}
		var total := 0
		var stack: Array = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			var direct := 0
			for c in n.get_children():
				if c is MeshInstance3D:
					direct += 1
				elif c is Node3D:
					stack.append(c)
			total += direct
			if direct > 0:
				counts[String(root.get_path_to(n))] = direct
		print("[inspect] %s meshes=%d groups=%d" % [kind, total, counts.size()])
		var keys := counts.keys()
		keys.sort_custom(func(a, b): return counts[a] > counts[b])
		for k in keys.slice(0, mini(12, keys.size())):
			print("[inspect]   %4d @ %s" % [counts[k], k])


func _recent_p50() -> float:
	var take := mini(120, _frames.size())
	if take <= 0:
		return 0.0
	var vals: Array[float] = []
	for i in range(_frames.size() - take, _frames.size()):
		vals.append(float(_frames[i]["ms"]))
	vals.sort()
	return vals[vals.size() / 2]


func _screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("[play-bench] screenshot ", path)
