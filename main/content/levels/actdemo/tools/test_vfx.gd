extends Node3D
## VFX 自测场景：黑场地上依次播放每种特效并出图，附带性能与健壮性统计。
##   出图 res://shots/vfx_1.png .. vfx_6.png
##   打印：节点数峰值 / 粒子上限 / 300 帧平均帧耗时 / 健壮性调用结果

const SHOT_DIR := "res://shots"

var _camera: Camera3D
var _fx: Node = null
var _persist_beam: Node3D = null

var _peak_tree_nodes := 0
var _peak_fx_nodes := 0
var _peak_particles := 0
var _peak_shake := 0.0
var _fired_ok := 0
var _robust_ok := 0


func _ready() -> void:
	_fx = get_node_or_null("/root/Fx")
	_build_world()
	# 关掉 vsync，帧耗时才有意义
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().process_frame
	_run()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.004, 0.005, 0.008)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.05, 0.06, 0.09)
	e.ambient_light_energy = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.15
	env.environment = e
	add_child(env)

	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.03, 0.034, 0.042)
	fm.metallic = 0.3
	fm.roughness = 0.45
	floor_mi.material_override = fm
	add_child(floor_mi)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, 38, 0)
	key.light_energy = 1.15
	key.light_color = Color(0.75, 0.82, 1.0)
	add_child(key)

	_camera = Camera3D.new()
	_camera.position = Vector3(4.6, 3.0, 6.4)
	add_child(_camera)
	_camera.look_at(Vector3(0, 1.5, 0.6), Vector3.UP)
	_camera.fov = 60.0
	_camera.current = true


# ------------------------------------------------------------------ driver
func _run() -> void:
	var stages := ["spark/clang", "impact_ring", "death_burst", "slash_arc", "beam", "projectiles"]
	for i in stages.size():
		await _stage(i, stages[i])

	var perf: Dictionary = await _perf_run()
	await _robustness()

	_print_report(stages, perf)


func _watch() -> void:
	var t := get_tree()
	if t == null:
		return
	_peak_tree_nodes = maxi(_peak_tree_nodes, t.get_node_count())
	if _fx != null and is_instance_valid(_fx):
		_peak_fx_nodes = maxi(_peak_fx_nodes, _fx.get_child_count())
		if _fx.has_method("particle_count"):
			_peak_particles = maxi(_peak_particles, int(_fx.particle_count()))
		_peak_shake = maxf(_peak_shake, float(_fx.shake_amount))


func _stage(idx: int, name: String) -> void:
	await _settle(0.50)
	match name:
		"spark/clang":
			for k in 6:
				var p := Vector3(-1.4 + k * 0.56, 1.2 + 0.3 * sin(float(k)), -1.0)
				if k % 2 == 0:
					_fx.spark(p, Vector3.UP, 0.7 + 0.25 * k)
					_fx.spark(p + Vector3(0.4, 0, 0.3), Vector3.UP)
				else:
					_fx.clang(p, Vector3(0.4, 0.6, 0.2))
		"impact_ring":
			_fx.impact_ring(Vector3(0, 0, 0), 5.0, 1.2)
		"death_burst":
			_fx.death_burst(Vector3(0, 0, 0))
		"slash_arc":
			for k in 3:
				var xf := Transform3D(Basis(Vector3.UP, -0.85 + 0.57 * k), Vector3(0, 1.55 + 0.16 * k, 0))
				_fx.slash_arc(xf, 3.4, 2.4, Color(1, 0.4, 0.12), 0.4)
		"beam":
			_fx.beam(Vector3(-4, 1.4, 0), Vector3(4, 1.6, 0), 0.5, Color(1, 0.25, 0.6), 0.4)
			_fx.beam(Vector3(0, 0.4, -3), Vector3(0, 3.2, 3), 0.35, Color(0.3, 0.7, 1.0), 0.4)
			_spawn_persistent_beam()
		"projectiles":
			_spawn_projectiles()
	# 让效果推进到视觉峰值再抓图
	await _settle(0.09)
	if name == "beam" and _persist_beam != null:
		# 验证 update_beam：把持续光束的另一端移动
		_fx.update_beam(_persist_beam, Vector3(-3.5, 0.5, 3.0), Vector3(2.5, 3.6, -2.0), 0.30)
	await _settle(0.05)
	await _snap("%s/vfx_%d.png" % [SHOT_DIR, idx + 1])
	if name == "beam" and _persist_beam != null:
		_fx.free_beam(_persist_beam)
		_persist_beam = null
	_report_stage(idx + 1, name)


func _spawn_persistent_beam() -> void:
	var a := Vector3(-3.5, 0.5, 3.0)
	var b := Vector3(2.5, 2.6, -2.0)
	_persist_beam = _fx.beam_persistent(a, b, 0.30, Color(0.4, 1.0, 0.7))


func _spawn_projectiles() -> void:
	# 刀气：沿 -Z 飞行
	var qi := MeshInstance3D.new()
	qi.mesh = _fx.qi_mesh()
	add_child(qi)
	qi.position = Vector3(-2.4, 2.0, 3.4)
	qi.look_at(qi.position + Vector3(1.0, -0.12, -0.55))
	# 箭矢：箭头朝 -Z（这里换个朝向，让镜头看到侧面轮廓）
	var arrow := MeshInstance3D.new()
	arrow.mesh = _fx.arrow_mesh()
	add_child(arrow)
	arrow.position = Vector3(1.9, 1.9, 2.6)
	arrow.look_at(arrow.position + Vector3(-1.0, -0.03, -0.10))
	# 激光
	var laser := MeshInstance3D.new()
	laser.mesh = _fx.laser_mesh()
	add_child(laser)
	laser.scale = Vector3(0.32, 0.32, 5.5)
	laser.position = Vector3(2.6, 0.7, 1.2)
	laser.look_at(laser.position + Vector3(-1.0, 0.02, -0.12))


func _settle(seconds: float) -> void:
	await wait_seconds(seconds)


func wait_seconds(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		_watch()


func _snap(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[vfx-test] headless: skip shot %s" % path)
		return
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	var tex = vp.get_texture() if vp != null else null
	if tex == null:
		print("[vfx-test] no viewport texture: skip shot %s" % path)
		return
	var img := tex.get_image()
	if img == null:
		print("[vfx-test] no image: skip shot %s" % path)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var err := img.save_png(path)
	print("[vfx-test] shot %s err=%d size=%s" % [path, err, str(img.get_size())])


# ------------------------------------------------------------------ perf
func _perf_run() -> Dictionary:
	await _settle(0.5)
	var frames := 300
	var total_us := 0
	var t0 := Time.get_ticks_usec()
	var last := t0
	for f in frames:
		# 每帧随机点火，模拟实战负载
		if f % 5 == 0:
			_fx.spark(Vector3(randf_range(-3, 3), randf_range(1, 3), randf_range(-2, 2)), Vector3.UP, 0.8)
		if f % 15 == 0:
			_fx.clang(Vector3(randf_range(-2, 2), randf_range(1, 2), randf_range(-2, 2)), Vector3.UP)
		if f % 40 == 0:
			_fx.impact_ring(Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 4.0, 1.0)
		if f % 70 == 0:
			_fx.slash_arc(Transform3D(Basis(Vector3.UP, randf_range(-1, 1)), Vector3(0, 1.6, 0)), 3.4, 2.4)
		if f % 90 == 0:
			_fx.beam(Vector3(-4, 2, 0), Vector3(4, 2, 0), 0.5, Color(1, 0.3, 0.6), 0.3)
		_watch()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		total_us += now - last
		last = now
	var avg_ms := float(total_us) / float(frames) / 1000.0
	print("[vfx-test] perf avg frame = %.3f ms over %d frames (fps %.1f)" % [avg_ms, frames, 1000.0 / maxf(avg_ms, 0.001)])
	return {"avg_ms": avg_ms, "frames": frames}


# ------------------------------------------------------------------ robustness
func _robustness() -> void:
	var calls := [
		func(): _fx.spark(Vector3.ZERO),
		func(): _fx.spark(Vector3(1, 0, 1), Vector3.ZERO, 0.0),
		func(): _fx.clang(Vector3.ZERO, Vector3.ZERO),
		func(): _fx.impact_ring(Vector3.ZERO, 0.0, 0.0),
		func(): _fx.death_burst(Vector3(2, 0, 2)),
		func(): _fx.slash_arc(Transform3D.IDENTITY, 0.0, 0.0),
		func(): _fx.beam(Vector3.ZERO, Vector3.ZERO, 0.0),
		func(): _fx.screen_flash(0.0),
		func(): _fx.screen_flash(5.0, Color(1, 1, 1)),
		func(): _fx.shake(0.0),
		func(): _fx.shake(999.0),
	]
	for c in calls:
		c.call()
		_robust_ok += 1
	# null / 退化输入
	_fx.update_beam(null, Vector3.ZERO, Vector3.ONE, 1.0)
	_fx.free_beam(null)
	var b: Node3D = _fx.beam_persistent(Vector3.ZERO, Vector3.ZERO, 0.0, Color(1, 1, 1))
	_fx.update_beam(b, Vector3.ZERO, Vector3(0, 5, 0), 0.5)
	_fx.free_beam(b)
	_fx.free_beam(b)   # 二次释放
	_robust_ok += 5
	# 网格可生成
	var meshes := [func(): return _fx.qi_mesh(), func(): return _fx.arrow_mesh(), func(): return _fx.laser_mesh()]
	var names := ["qi", "arrow", "laser"]
	var mi := 0
	for m in meshes:
		var mm: Mesh = m.call()
		if mm != null and mm.get_surface_count() > 0:
			_robust_ok += 1
		if mm != null:
			var ab := mm.get_aabb()
			print("[vfx-test] mesh %-5s surfaces=%d aabb_size=%s" % [names[mi], mm.get_surface_count(), str(ab.size)])
		mi += 1
	await _settle(0.2)
	print("[vfx-test] robustness calls passed: %d" % _robust_ok)


# ------------------------------------------------------------------ report
func _report_stage(i: int, name: String) -> void:
	print("[vfx-test] stage %d (%s): fx_children=%d particles=%d tree_nodes=%d"
		% [i, name, _fx.get_child_count() if _fx else -1,
			int(_fx.particle_count()) if _fx else -1, get_tree().get_node_count()])


func _print_report(stages: Array, perf: Dictionary) -> void:
	print("================= VFX TEST REPORT =================")
	print("stages           : %s" % ", ".join(stages))
	print("peak tree nodes  : %d (Fx 子树峰值 %d)" % [_peak_tree_nodes, _peak_fx_nodes])
	print("peak particles   : %d (上限 %d)" % [_peak_particles, 600])
	print("peak shake       : %.2f" % _peak_shake)
	print("avg frame (300f): %.3f ms -> %.1f fps" % [perf["avg_ms"], 1000.0 / maxf(perf["avg_ms"], 0.001)])
	print("robustness       : %d calls" % _robust_ok)
	print("shots            : res://shots/vfx_1.png .. vfx_6.png")
	print("==================================================")
	print("[vfx-test] DONE")
	get_tree().quit()
