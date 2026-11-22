extends Node3D
## qa_visual — 独立视觉验收（只读游戏代码，只新增本脚本 + scenes/qa_visual.tscn）
##
##   DISPLAY=:0 godot --path actdemo res://scenes/qa_visual.tscn
##
## 产出：
##   res://shots/qa_L{1,2,3}_{a,b,c}.png   三关 远/中/近 第三人称
##   res://shots/qa_L{1,2,3}_fp.png        第一人称（机身/准星/刀）
##   res://shots/qa_L1_fp_weapon.png       第一人称 + cam.first_show_weapon=true
##   res://shots/qa_L3_shadow_{idle,attack}.png
##   res://shots/qa_ui_tuning.png / qa_ui_binds.png / qa_hud_death.png
##   res://shots/qa_fx_swing.png / qa_fx_block.png
##   res://shots/qa_hud_L1.png             正常 HUD（检查提示文字是否出屏）
##   /tmp/opencode/qa_visual/              中间帧（z-fighting 抖动对比、挥刀扫帧、亮度 A/B）
##
## 所有「冻结」都靠关掉 main 的 _process：游戏自身逻辑/相机全部停下，
## 只有 HUD 的 _process（另一个节点）继续跑，便于截图。不改任何游戏参数语义。

const MainScene := preload("res://main.tscn")
const OUT := "res://shots"
const TMP := "/tmp/opencode/qa_visual"

## 每关 3 个机位：pos=玩家站位  yaw=朝向  dist=第三人称距离  pitch=俯仰
const SURVEY := [
	{
		"enemies": [{"i": 0, "pos": Vector3(0, 0, -10), "heading": PI}],
		"views": [
			{"t": "a", "pos": Vector3(0, 0, 6), "yaw": 0.0, "dist": 24.0, "pitch": -0.04,
				"note": "远：沿窄巷向 -Z 看全长（两侧立面 + 跨巷钢桁架 + 湿沥青）"},
			{"t": "b", "pos": Vector3(14, 0, -2), "yaw": -PI * 0.5, "dist": 13.0, "pitch": 0.0,
				"note": "中：向 +X 看东侧装卸凹龛 / 卷帘门 / 危险条纹"},
			{"t": "c", "pos": Vector3(18, 0, 4), "yaw": 0.0, "dist": 6.0, "pitch": 0.04,
				"note": "近：贴东墙、沿墙掠视 6 m（墙面莫尔纹 / z-fighting / 墙基）"},
		],
	},
	{
		"enemies": [
			{"i": 0, "pos": Vector3(-7, 0, -6), "heading": PI},
			{"i": 1, "pos": Vector3(7, 0, -16), "heading": PI},
			{"i": 2, "pos": Vector3(0, 0, -26), "heading": PI},
			{"i": 3, "pos": Vector3(20, 0, -34), "heading": PI},
		],
		"views": [
			{"t": "a", "pos": Vector3(5, 0, 18), "yaw": 0.0, "dist": 18.0, "pitch": -0.02,
				"note": "远：广场全景（北侧楼群 + 霓虹刀牌 + 亮窗）"},
			{"t": "b", "pos": Vector3(0, 0, 6), "yaw": 0.0, "dist": 14.0, "pitch": -0.06,
				"note": "中：广场中心环线 + 敌人 + 地面铺装"},
			{"t": "c", "pos": Vector3(-30, 0, -33), "yaw": 0.0, "dist": 6.0, "pitch": 0.04,
				"note": "近：北侧拱廊 / 自动售货机 / 墙脚特写"},
		],
	},
	{
		"enemies": [{"i": 0, "pos": Vector3(0, 0, -2), "heading": PI}],
		"views": [
			{"t": "a", "pos": Vector3(0, 0, 8), "yaw": 0.0, "dist": 26.0, "pitch": -0.03,
				"note": "远：灯墙之厅全景（四面大墙 + 壁灯 + 大怪）"},
			{"t": "b", "pos": Vector3(0, 0, 6), "yaw": 0.0, "dist": 14.0, "pitch": -0.06,
				"note": "中：场地中心的大怪（×2 体型）"},
			{"t": "c", "pos": Vector3(-27, 0, 0), "yaw": PI * 0.5, "dist": 6.0, "pitch": 0.04,
				"note": "近：西墙特写（墙面 / 壁灯 / 危险条纹 / 影子承载面）"},
		],
	},
]

## 影子观测机位（自由相机：直接摆 Camera3D；大怪在 z=+4，机位都在它南侧 → 大怪永远在画面外）
const SHADOW_CAMS := [
	{"tag": "front", "pos": Vector3(0.0, 6.0, 15.0), "look": Vector3(0.0, 7.2, 30.0),
		"note": "正面平视南墙，影子居中（亮度 A/B 用这一张）"},
	{"tag": "side", "pos": Vector3(9.0, 5.0, 14.0), "look": Vector3(0.0, 6.6, 30.0),
		"note": "从东南侧斜看南墙（3/4 侧后视角）"},
	{"tag": "low", "pos": Vector3(-4.0, 2.2, 16.0), "look": Vector3(0.0, 5.6, 30.0),
		"note": "低位仰角（接近玩家视线高度）"},
]

var game
var _params0: Dictionary = {}
var _had_params := false
var _perf: Array = []


func _ready() -> void:
	print("[qa] ===== qa_visual start =====")
	print("[qa] adapter=%s api=%s refresh=%.2fHz" % [RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_api_version(), DisplayServer.screen_get_refresh_rate()])
	print("[qa] window_size=%s screen=%s" % [str(DisplayServer.window_get_size()),
		str(DisplayServer.screen_get_size())])
	_params0 = P.snapshot()
	_had_params = FileAccess.file_exists("user://actdemo_params.json")
	DirAccess.make_dir_recursive_absolute(TMP)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	game = MainScene.instantiate()
	add_child(game)
	await _f(6)

	# 只动运行期状态，测试结束会完整还原（并把用户参数文件写回原值）
	P.set_value("rules.god_mode", true)
	P.set_value("boss.laser_trigger", "disabled")
	P.set_value("rules.banner_time", 0.6)
	P.set_value("cam.mode", "third")

	var only := OS.get_environment("QA_ONLY")
	if only == "" or only == "survey":
		await _phase_survey()
	if only == "" or only == "fp":
		await _phase_fp()
	if only == "" or only == "perf":
		await _phase_perf()
	if only == "" or only == "shadow":
		await _phase_shadow()
	if only == "" or only == "ui":
		await _phase_ui()
	if only == "" or only == "fx":
		await _phase_fx()
	if only == "" or only == "extra":
		await _phase_extra()

	P.apply_snapshot(_params0)
	P.save()
	if not _had_params:
		var p := ProjectSettings.globalize_path("user://actdemo_params.json")
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	print("[qa] ===== qa_visual done =====")
	await _f(2)
	get_tree().quit()


# ------------------------------------------------------------------ 基础工具
func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _freeze(on: bool) -> void:
	game.set_process(not on)


func _hud_show(on: bool) -> void:
	game.hud.set_hud_visible(on)


func _place(pos: Vector3, yaw: float, dist: float, pitch := -0.08) -> void:
	var rig = game.player.rig
	rig.global_position = pos
	rig.heading = yaw
	rig.rotation.y = yaw
	rig.facing_override = true
	rig.facing_heading = yaw
	rig.move_command = Vector3.ZERO
	game.cam.yaw = yaw
	game.cam.pitch = pitch
	P.set_value("cam.distance", dist)
	game.cam._initialized = false
	game.cam.step(1.0 / 60.0, game.level.arena)
	game.cam.step(1.0 / 60.0, game.level.arena)


func _free_cam(pos: Vector3, look: Vector3) -> void:
	var c = game.cam.camera
	c.global_position = pos
	c.fov = P.getf("cam.fov")
	c.look_at(look, Vector3.UP)


func _fp_place(pos: Vector3, yaw: float, pitch := 0.0, eye_h := -1.0) -> void:
	var rig = game.player.rig
	rig.global_position = pos
	rig.heading = yaw
	rig.rotation.y = yaw
	game.cam.yaw = yaw
	game.cam.pitch = pitch
	if eye_h > 0.0:
		P.set_value("cam.first_height", eye_h)
	game.cam._initialized = false
	game.cam.step(1.0 / 60.0, game.level.arena)
	game.cam.step(1.0 / 60.0, game.level.arena)


func _snap(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var e1 := img.save_png("%s/%s.png" % [OUT, name])
	var e2 := img.save_png("%s/ref_%s.png" % [TMP, name])
	print("[qa] SHOT %s/%s.png err=%d/%d size=%s" % [OUT, name, e1, e2, str(img.get_size())])


func _snap_tmp(name: String) -> void:
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [TMP, name])


## 微移相机（亚像素）再拍两张：同机位基线帧（只含雨/粒子噪声）+ 位移帧
##   z-fighting → 位移帧的整片翻转，同机位基线帧不会出现
func _zfight_probe(name: String) -> void:
	var c = game.cam.camera
	await _snap_tmp("base_%s" % name)
	var xf: Transform3D = c.global_transform
	c.global_position = xf.origin + Vector3(0.020, 0.008, 0.016)
	await _snap_tmp("zf_%s" % name)
	c.global_transform = xf
	await _f(2)


func _set_enemies(list: Array) -> void:
	var en: Array = game.level.enemies
	for spec in list:
		var i := int(spec["i"])
		if i >= en.size() or not is_instance_valid(en[i]):
			continue
		var e = en[i]
		e.alive = true
		e.visible = true
		e.rig.visible = true
		e.global_position = spec["pos"]
		e.rig.position = Vector3.ZERO        # 清掉 AI 累积的局部位移，站位才可复现
		e.rig.move_command = Vector3.ZERO
		e.rig.heading = float(spec["heading"])
		e.rig.rotation.y = float(spec["heading"])
		e.rig.facing_override = true
		e.rig.facing_heading = float(spec["heading"])


func _count_visible_meshes(root: Node3D) -> int:
	var n := 0
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).is_visible_in_tree():
			n += 1
		if c is Node3D:
			n += _count_visible_meshes(c)
	return n


# ------------------------------------------------------------------ 1) 三关机位
func _phase_survey() -> void:
	P.set_value("cam.mode", "third")
	_freeze(false)
	game.cam.set_first_person(false)
	for li in 3:
		var spec: Dictionary = SURVEY[li]
		game.level.start_level(li)
		await _f(45)
		game.hud.show_banner("", "", 0.01)
		game.hud.clear_death()
		_set_enemies(spec["enemies"])
		await _f(3)
		_freeze(true)
		_hud_show(false)
		for v in spec["views"]:
			_place(v["pos"], v["yaw"], v["dist"], v["pitch"])
			await _f(4)
			var nm := "qa_L%d_%s" % [li + 1, v["t"]]
			print("[qa] VIEW %s cam=%s player=%s | %s" % [nm,
				str(game.cam.camera.global_position.round()), str(v["pos"]), v["note"]])
			await _snap(nm)
			await _zfight_probe(nm)
		_freeze(false)
		_hud_show(true)


# ------------------------------------------------------------------ 2) 第一人称
func _phase_fp() -> void:
	P.set_value("cam.mode", "first")
	P.set_value("cam.first_show_weapon", false)
	print("[qa] FP start hud._first_person=%s" % str(game.hud._first_person))
	for li in 3:
		_freeze(false)
		game.level.start_level(li)
		await _f(45)
		game.hud.show_banner("", "", 0.01)
		var sp: Transform3D = game.level.arena["player_spawn"]
		var yaw: float = sp.basis.get_euler().y
		_freeze(true)
		_hud_show(true)
		_fp_place(sp.origin, yaw, 0.02)
		await _f(4)
		var meshes := _count_visible_meshes(game.player.rig)
		var hud_fp: bool = game.hud._first_person
		print("[qa] FP L%d rig.visible=%s visible_meshes=%d hud._first_person=%s eye=%s" % [
			li + 1, str(game.player.rig.visible), meshes, str(hud_fp),
			str(game.cam.camera.global_position)])
		if hud_fp:
			# 把 HUD 的标记临时关掉，单独确认准星
			game.hud.set_markers([])
		await _snap("qa_L%d_fp" % (li + 1))
		# 对照：走 HUD 自己的接口把准星打开（游戏本体没有调用它）
		if li == 0:
			game.hud.set_first_person(true)
			await _f(3)
			await _snap("qa_L1_fp_crosshair")
			game.hud.set_first_person(false)

	# 参数：第一人称显示刀
	_freeze(false)
	game.level.start_level(0)
	await _f(45)
	game.hud.show_banner("", "", 0.01)
	P.set_value("cam.mode", "first")
	P.set_value("cam.first_show_weapon", true)
	game.player.rig.set_first_person_view(true, true)
	var sp2: Transform3D = game.level.arena["player_spawn"]
	var yaw2: float = sp2.basis.get_euler().y
	_freeze(true)
	_fp_place(sp2.origin, yaw2, 0.02)
	await _f(4)
	print("[qa] FP weapon-on visible_meshes=%d" % _count_visible_meshes(game.player.rig))
	await _snap("qa_L1_fp_weapon")
	P.set_value("cam.first_show_weapon", false)
	P.set_value("cam.mode", "third")
	game.player.rig.set_first_person_view(false, false)
	_freeze(false)


# ------------------------------------------------------------------ 6) 性能
func _phase_perf() -> void:
	P.set_value("cam.mode", "third")
	game.cam.set_first_person(false)
	_freeze(false)
	_hud_show(true)
	P.set_value("rules.time_scale", 1.0)
	for li in 3:
		game.level.start_level(li)
		await _settle_fps()
		await _perf_window("L%d_vsync_on" % (li + 1), 3.0)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		await _f(30)
		await _perf_window("L%d_vsync_off" % (li + 1), 3.0)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		await _f(20)


## 等 FPS 从「关卡构建 + 着色器编译」的抖动里爬出来，再开始计时
func _settle_fps() -> void:
	var t0 := Time.get_ticks_msec()
	var ok := 0
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		if Engine.get_frames_per_second() >= 45:
			ok += 1
			if ok >= 30:
				return
		else:
			ok = 0
	print("[qa] WARN settle timeout after %d ms, fps=%d" % [
		Time.get_ticks_msec() - t0, Engine.get_frames_per_second()])


func _perf_window(label: String, secs: float) -> void:
	var fps: Array = []
	var dc: Array = []
	var objs: Array = []
	var prims: Array = []
	var ft: Array = []
	var proc: Array = []
	var t0 := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ft.append(float(now - last) / 1000.0)
		last = now
		fps.append(Engine.get_frames_per_second())
		dc.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		objs.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		prims.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	if fps.is_empty():
		return
	var rec := {
		"label": label,
		"n": fps.size(),
		"fps_avg": _avg(fps), "fps_min": _min(fps), "fps_max": _max(fps),
		"dc_avg": _avg(dc), "dc_min": _min(dc), "dc_max": _max(dc),
		"obj_avg": _avg(objs), "prim_avg": _avg(prims),
		"framems_avg": _avg(ft), "proc_ms_avg": _avg(proc),
	}
	_perf.append(rec)
	print("[qa] PERF %s frames=%d fps(min/avg/max)=%d/%.1f/%d draws(min/avg/max)=%d/%.1f/%d objs=%.0f prims=%.0f frame_ms=%.1f script_ms=%.2f" % [
		label, rec["n"], int(rec["fps_min"]), rec["fps_avg"], int(rec["fps_max"]),
		int(rec["dc_min"]), rec["dc_avg"], int(rec["dc_max"]),
		rec["obj_avg"], rec["prim_avg"], rec["framems_avg"], rec["proc_ms_avg"]])


func _avg(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(1.0, float(a.size()))


func _min(a: Array) -> float:
	var m := INF
	for v in a:
		m = minf(m, float(v))
	return m


func _max(a: Array) -> float:
	var m := -INF
	for v in a:
		m = maxf(m, float(v))
	return m


# ------------------------------------------------------------------ 3) 第三关影子
func _phase_shadow() -> void:
	P.set_value("cam.mode", "third")
	game.cam.set_first_person(false)
	_freeze(false)
	game.level.start_level(2)
	await _f(60)
	game.hud.show_banner("", "", 0.01)
	game.hud.clear_death()
	_hud_show(false)
	# 大怪放场地中央靠南（z=+4）：南墙影子由北墙壁灯投出，放大 1.78×，全身都落进墙里
	_set_enemies([{"i": 0, "pos": Vector3(0, 0, 4), "heading": PI}])
	game.player.rig.global_position = Vector3(0, 0, 22)
	game.player.rig.heading = PI
	game.player.rig.rotation.y = PI
	await _f(10)
	# 再摆一次（AI 在这 10 帧里会走），然后冻结
	_set_enemies([{"i": 0, "pos": Vector3(0, 0, 4), "heading": PI}])
	game.player.rig.global_position = Vector3(0, 0, 22)
	game.player.rig.heading = PI
	game.player.rig.rotation.y = PI
	_freeze(true)
	var boss = game.level.enemies[0]
	print("[qa] SHADOW boss_world=%s rig_local=%s player=%s" % [
		str(boss.rig.global_position.round()), str(boss.rig.position.round()),
		str(game.player.rig.global_position.round())])

	var shadow = game.level.shadow
	print("[qa] SHADOW node=%s enabled=%s slots=%d lamps=%d" % [str(shadow),
		str(shadow.enabled), shadow._slots.size(), shadow._lamp_pos.size()])

	# ---- 静止姿态
	_drive_rig(boss.rig, 1.4)
	shadow.refresh()
	await _f(3)

	# (a) 游戏内第三人称机位：玩家站在大怪南侧、面朝南墙看影子（大怪在身后）
	_place(Vector3(0, 0, 22), PI, 9.0, 0.02)
	await _f(4)
	await _snap("qa_L3_shadow_ingame")
	print("[qa] SHADOW ingame cam=%s boss=%s" % [
		str(game.cam.camera.global_position.round()), str(boss.rig.global_position.round())])
	# 之后把玩家挪开，免得挡自由机位
	game.player.rig.global_position = Vector3(26, 0, 26)
	game.player.rig.rotation.y = PI

	# (b) 自由机位
	for c in SHADOW_CAMS:
		_free_cam(c["pos"], c["look"])
		shadow.refresh()
		await _f(3)
		await _snap("qa_L3_shadow_idle_%s" % c["tag"])
		print("[qa] SHADOW idle cam=%s pos=%s | %s" % [c["tag"],
			str(c["pos"]), c["note"]])
	_dump_debug(shadow)

	# (c) 亮度 A/B（同机位同姿态：有影子 / 关掉影子）
	_free_cam(SHADOW_CAMS[0]["pos"], SHADOW_CAMS[0]["look"])
	shadow.refresh()
	await _f(3)
	await _snap_tmp("shadow_on")
	shadow.set_enabled(false)
	await _f(3)
	await _snap_tmp("shadow_off")
	shadow.set_enabled(true)
	shadow.refresh()
	await _f(3)

	# ---- 挥刀姿态（直接驱动 rig，绕开 AI，保证可复现）
	var boss_pose := func(target_frac: float) -> void:
		boss.rig.force_attack("heavy")
		var g := 0
		while not boss.rig.in_hit_window() and g < 300:
			boss.rig.advance(1.0 / 240.0)
			g += 1
		var tgt: float = boss.rig.attack_hit_from + (boss.rig.attack_hit_to - boss.rig.attack_hit_from) * target_frac
		g = 0
		while boss.rig.attack_elapsed < tgt and g < 3000:
			boss.rig.advance(1.0 / 240.0)
			g += 1
		shadow.refresh()

	# 交付用挥刀姿态：判定窗口 40% 处（刀已扬起、正在下劈）
	boss_pose.call(0.40)
	await _f(3)
	print("[qa] SHADOW attack elapsed=%.3f window=[%.3f,%.3f] blade_tip=%s" % [
		boss.rig.attack_elapsed, boss.rig.attack_hit_from, boss.rig.attack_hit_to,
		str(boss.rig.blade_tip.global_position.round()) if boss.rig.blade_tip != null else "null"])
	for c in SHADOW_CAMS:
		_free_cam(c["pos"], c["look"])
		shadow.refresh()
		await _f(3)
		await _snap("qa_L3_shadow_attack_%s" % c["tag"])
	# 高机位（俯角大，容易看清刀的方向）
	_free_cam(Vector3(0.0, 8.5, 15.0), Vector3(0.0, 9.0, 30.0))
	shadow.refresh()
	await _f(3)
	await _snap("qa_L3_shadow_attack_high")
	_dump_debug(shadow)

	# ---- 挥刀扫帧：整段判定窗口拍成序列（事后挑帧用）
	var win_a: float = boss.rig.attack_hit_from
	var win_b: float = boss.rig.attack_hit_to
	if win_b <= win_a:
		win_a = 0.0
		win_b = 1.0
	boss_pose.call(0.0)
	var steps := 26
	for i in steps:
		boss.rig.advance(maxf((win_b - win_a) / float(steps - 1), 0.0005))
		shadow.refresh()
		await _f(1)
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/sweep_%02d.png" % [TMP, i])
	print("[qa] SHADOW sweep=%d window=[%.3f, %.3f]" % [steps, win_a, win_b])
	_freeze(false)


func _drive_rig(rig, seconds: float) -> void:
	var t := 0.0
	var step := 1.0 / 90.0
	while t < seconds:
		rig.advance(step)
		t += step


func _dump_debug(shadow) -> void:
	var rep: Dictionary = shadow.debug_report()
	var parts: Array = rep.get("slots", [])
	var s := ""
	for p in parts:
		s += " [slot%d tris=%d verts=%d lamp=%d paired=%d min=%s max=%s half=%s]" % [
			int(p.get("slot", -1)), int(p.get("tris", 0)), int(p.get("verts", 0)),
			int(p.get("lamp", -1)), int(p.get("paired_ok", 0)),
			str(p.get("min")), str(p.get("max")), str(p.get("half"))]
	print("[qa] SHADOW debug usec=%.0f decim=%.2f%s" % [float(rep.get("usec", 0.0)),
		float(rep.get("decim", 1.0)), s])


# ------------------------------------------------------------------ 4) UI
func _phase_ui() -> void:
	P.set_value("cam.mode", "third")
	_freeze(false)
	game.level.start_level(0)
	await _f(45)
	game.hud.show_banner("", "", 0.01)
	_place(Vector3(0, 0, 8), 0.0, 15.0, -0.10)
	await _f(6)
	_freeze(true)
	_hud_show(true)
	await _snap("qa_hud_L1")
	print("[qa] HUD hint=%s" % game.hud._hint)

	var groups: Array = P.groups()
	var gi: int = groups.find("攻击")
	game.tuning.open()
	if gi >= 0:
		game.tuning._jump_group(gi)
	await _f(8)
	await _snap("qa_ui_tuning")
	print("[qa] UI tuning group=%s rows=%d groups=%d open=%s" % [
		str(game.tuning._current_group()), game.tuning.param_row_count(),
		game.tuning.group_count(), str(game.tuning.is_open())])
	game.tuning.close()
	await _f(4)

	game.binds.open()
	await _f(8)
	await _snap("qa_ui_binds")
	print("[qa] UI binds rows=%d sys=%d open=%s" % [game.binds.action_row_count(),
		game.binds.system_row_count(), str(game.binds.is_open())])
	game.binds.close()
	await _f(4)

	game.hud.flash_death("测试")
	await _f(40)
	await _snap("qa_hud_death")
	game.hud.flash_death("被大怪激光蒸发 · 直视即死")
	await _f(40)
	await _snap("qa_hud_death_long")
	game.hud.clear_death()
	_freeze(false)


# ------------------------------------------------------------------ 5) 战斗特效
func _phase_fx() -> void:
	P.set_value("cam.mode", "third")
	game.cam.set_first_person(false)
	P.set_value("rules.time_scale", 1.0)
	_freeze(false)
	_hud_show(true)

	# ---- 挥砍弧（冻结主循环后手动推进 rig：完全可复现，并逐帧记录拖尾状态）
	game.level.start_level(0)
	await _f(50)
	game.hud.show_banner("", "", 0.01)
	var sp: Transform3D = game.level.arena["player_spawn"]
	_set_enemies([{"i": 0, "pos": sp.origin + Vector3(6.5, 0, -5.5), "heading": PI * 0.7}])
	_place(sp.origin, 0.0, 9.0, -0.05)
	await _f(24)
	_freeze(true)
	_hud_show(true)
	game.player._attack_from_input(Vector2.ZERO)
	var bt = game.player.rig.blade_trail
	var trail_frames := 20
	for i in trail_frames:
		game.player.rig.advance(1.0 / 120.0)
		await _f(1)
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/swing_%02d.png" % [TMP, i])
		print("[qa] SWING f%02d elapsed=%.3f hit=%s trail_vis=%s samples=%d surf=%d" % [
			i, game.player.rig.attack_elapsed, str(game.player.rig.in_hit_window()),
			str(bt.visible), bt._samples.size(),
			0 if bt.mesh == null else bt.mesh.get_surface_count()])
	_freeze(false)
	await _f(6)

	# 重来一次，在判定窗口中点冻结出交付图（正机位 + 俯视诊断）
	game.level.start_level(0)
	await _f(60)
	game.hud.show_banner("", "", 0.01)
	sp = game.level.arena["player_spawn"]
	_set_enemies([{"i": 0, "pos": sp.origin + Vector3(6.5, 0, -5.5), "heading": PI * 0.7}])
	_place(sp.origin, 0.0, 9.0, -0.05)
	await _f(24)
	game.player._attack_from_input(Vector2.ZERO)
	var g := 0
	while g < 240 and not (game.player.rig.in_hit_window()
			and game.player.rig.attack_elapsed >= game.player.rig.attack_hit_from
				+ (game.player.rig.attack_hit_to - game.player.rig.attack_hit_from) * 0.45):
		await get_tree().process_frame
		g += 1
	_freeze(true)
	await _snap("qa_fx_swing")
	print("[qa] FX swing frozen at attack_elapsed=%.3f window=[%.3f,%.3f] trail_samples=%d blink=%s" % [
		game.player.rig.attack_elapsed, game.player.rig.attack_hit_from,
		game.player.rig.attack_hit_to, game.player.rig.blade_trail._samples.size(),
		str(game.player.rig.blade_trail.visible)])
	var pp: Vector3 = game.player.rig.global_position
	_free_cam(pp + Vector3(0.0, 14.0, 5.0), pp + Vector3(0.0, 2.0, 0.0))
	await _snap("qa_fx_swing_top")
	_free_cam(pp + Vector3(12.0, 5.5, -1.0), pp + Vector3(0.0, 2.4, 0.0))
	await _snap("qa_fx_swing_side")
	_freeze(false)

	# ---- 格挡（小怪在正面、完全在画面里 → 100% 格挡）
	game.level.start_level(0)
	await _f(50)
	game.hud.show_banner("", "", 0.01)
	var sp2: Transform3D = game.level.arena["player_spawn"]
	var mob = game.level.enemies[0]
	_set_enemies([{"i": 0, "pos": sp2.origin + Vector3(0.6, 0, -3.1), "heading": 0.0}])
	_place(sp2.origin, 0.0, 8.5, -0.02)
	await _f(24)
	game.player._attack_from_input(Vector2.ZERO)
	g = 0
	while g < 150 and game.hud._block_t <= 0.0:
		await get_tree().process_frame
		g += 1
	_freeze(true)
	await _f(2)      # 让火花/冲击环先跑 2 帧再拍（Fx 自己还在动）
	await _snap("qa_fx_block")
	print("[qa] FX block block_t=%.3f device_wait=%d mob_last_hit_serial=%d player_swing=%d" % [
		game.hud._block_t, g, mob.last_hit_serial, game.player.swing_serial])
	_freeze(false)
	await _f(4)
	print("[qa] FX block particles alive after unfreeze=%d" % Fx.particle_count())


# ------------------------------------------------------------------ 7) 补充证据
## 两个额外取证：L2 南端机位（整面纯黑的巨幅面片）+ L3 顶棚（死黑）
func _phase_extra() -> void:
	P.set_value("cam.mode", "third")
	game.cam.set_first_person(false)
	_freeze(false)
	_hud_show(false)

	# L2：站在广场南端往北看——大块近黑面片挡住天际线
	game.level.start_level(1)
	await _f(45)
	game.hud.show_banner("", "", 0.01)
	_set_enemies([{"i": 0, "pos": Vector3(-7, 0, -6), "heading": PI},
		{"i": 1, "pos": Vector3(7, 0, -16), "heading": PI},
		{"i": 2, "pos": Vector3(0, 0, -26), "heading": PI},
		{"i": 3, "pos": Vector3(20, 0, -34), "heading": PI}])
	await _f(3)
	_freeze(true)
	_place(Vector3(0, 0, 28), 0.0, 26.0, -0.02)
	await _f(4)
	await _snap("qa_L2_blackpanel")
	print("[qa] EXTRA L2 blackpanel cam=%s" % str(game.cam.camera.global_position.round()))
	# 抬一点镜头，把那块面片放到画面中间
	_free_cam(Vector3(0.0, 6.0, 34.0), Vector3(0.0, 13.0, -20.0))
	await _f(3)
	await _snap("qa_L2_blackpanel_zoom")

	# L3：顶棚
	_freeze(false)
	game.level.start_level(2)
	await _f(45)
	game.hud.show_banner("", "", 0.01)
	_set_enemies([{"i": 0, "pos": Vector3(0, 0, -2), "heading": PI}])
	await _f(3)
	_freeze(true)
	_free_cam(Vector3(0.0, 3.0, 12.0), Vector3(0.0, 17.0, -6.0))
	await _f(3)
	await _snap("qa_L3_ceiling")
	_free_cam(Vector3(0.0, 3.0, 12.0), Vector3(0.0, 2.0, -18.0))
	await _f(3)
	await _snap("qa_L3_wall_north")
	print("[qa] EXTRA ceiling/wall done")
	_freeze(false)
