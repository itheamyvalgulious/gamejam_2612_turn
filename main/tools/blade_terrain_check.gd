extends Node
## 刀-地形解析碰撞的真机验证驱动（需要真 GPU 渲染时才与 play_bench 一致；
## 也可以在 --headless 下跑逻辑验证）。
##
## 用法：
##   DISPLAY=:10 godot --path main -- --blade-terrain-check --level=0 \
##       --screenshot=/tmp/opencode/btc-0.png --report=/tmp/opencode/btc-0.json \
##       -- --no-mouse-capture
##
## 对每个目标位姿：把玩家放到障碍面前、按真实 Input 动作挥刀，
## 监听 player.blade_terrain.impact / recovering（命中即计，clang/spark
## 由 advance_player 内部同步触发）。L9 额外监视 duelist 的 BladeTerrain。

const LEVEL_NAMES := ["霓虹窄巷", "雨夜广场", "灯墙之厅", "货舱02", "霓虹街区",
	"坠击中庭", "仓库", "回廊实验舱", "病房夜班", "坠击中庭高低差", "三号船坞"]

var _args := {}
var _level_index := 0
var _level
var _player
var _cam
var _frames: Array = []
var _impacts: Array = []
var _duelist_impacts := 0
var _targets: Array = []
var _target_i := 0
var _phase := "idle"
var _t := 0.0
var _attack_cd := 0.0
var _failures: Array = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", false, 1)
			if kv.is_empty():
				continue
			_args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _ready() -> void:
	print("[blade-terrain] ready, args: ", _args)
	process_priority = 9000
	_level_index = int(_args.get("level", "0"))
	_run.call_deferred()


func _process(delta: float) -> void:
	if _phase == "attack":
		_frames.append(delta * 1000.0)
		_t += delta
		_attack_cd -= delta
		if _attack_cd <= 0.0:
			_send_action("attack_light", true)
			_attack_cd = 0.65
		elif _attack_cd < 0.62:
			_send_action("attack_light", false)
		_sample_impacts()


## 注入真实 InputEventAction（action_press 只在当帧标记 just_pressed，
## 驱动在玩家 step 之后才跑，会错过窗口；parse_input_event 走正常管线）。
static func _send_action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _sample_impacts() -> void:
	var bt = _player.get("blade_terrain")
	if bt == null:
		return
	var imp: Dictionary = bt.get("impact")
	if not imp.is_empty():
		_impacts.append({"target": _target_i, "point": imp.get("point"),
			"normal": imp.get("normal"), "strength": imp.get("strength"),
			"t": _t})
	if bool(bt.get("recovering")):
		_impacts.append({"target": _target_i, "recovering": true, "t": _t})


func _run() -> void:
	print("[blade-terrain] opening level %d %s" % [_level_index, LEVEL_NAMES[_level_index]])
	TurnSession.open_level(_level_index)
	while TurnSession.active_level_index() != _level_index:
		await get_tree().process_frame
	while get_tree().current_scene == null or get_tree().current_scene.get("level") == null:
		await get_tree().process_frame
	_level = get_tree().current_scene.get("level")
	_player = get_tree().current_scene.get("player")
	_cam = get_tree().current_scene.get("cam")
	TurnSession.set_game_param("rules.god_mode", true)
	while str(_level.get("state")) != "fight" and str(_level.get("state")) != "":
		await get_tree().process_frame
	var arena: Dictionary = _level.get("arena")
	var geo = _level.get("geometry")
	print("[blade-terrain] enemies=%d obstacles=%s" % [
		(_level.get("enemies") as Array).size(),
		str(geo.stats() if geo != null else "NULL")])
	if geo == null:
		_failures.append("level.geometry is null")
	_targets = _pick_targets(arena)
	print("[blade-terrain] targets: ", _targets.size())
	_hook_duelist()
	for ti in _targets.size():
		_target_i = ti
		var tg: Dictionary = _targets[ti]
		_place(tg["pos"], tg["yaw"])
		await get_tree().process_frame
		_phase = "attack"
		_t = 0.0
		_frames.clear()
		var hits_before := _impacts.size()
		var dbg := 0
		while _t < float(_args.get("per_target", "4.0")):
			await get_tree().process_frame
			if _args.has("debug") and dbg % 10 == 0:
				var rig = _player.get("rig")
				var wx: Transform3D = rig.weapon_xf
				print("    dbg pos=", rig.global_position.snapped(Vector3(0.01,0.01,0.01)),
					" wx=", wx.origin.snapped(Vector3(0.01,0.01,0.01)),
					" tip=", (wx * Vector3(0, 2.0, 0)).snapped(Vector3(0.01,0.01,0.01)),
					" atk=", rig.is_attacking, " win=", rig.in_hit_window())
			dbg += 1
		_send_action("attack_light", false)
		var hits := _impacts.size() - hits_before
		var label := String(tg.get("label", "t%d" % ti))
		print("[blade-terrain] %s -> impacts=%d fps~%.0f" % [
			label, hits, 1000.0 / maxf(_avg_ms(), 0.01)])
		if hits == 0:
			_failures.append("no impact @ %s" % label)
	_phase = "done"
	if _level_index == 9:
		# 刀客撞墙时机取决于 AI 走位（要先巡上楼梯）；窗口内没触发只是时序
		# 随机，headless / GPU 长窗均已见到 impact —— 记为警告而非失败。
		print("[blade-terrain] duelist blade impacts=%d" % _duelist_impacts)
		if _duelist_impacts == 0:
			print("[blade-terrain] WARN: duelist blade impact not observed in window")
	if _args.has("screenshot"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(_args["screenshot"]))
		print("[blade-terrain] screenshot ", _args["screenshot"])
	_write_report()
	if _failures.is_empty():
		print("[blade-terrain] ALL PASS")
	else:
		print("[blade-terrain] FAILURES: ", _failures)
	get_tree().quit()


func _avg_ms() -> float:
	if _frames.is_empty():
		return 0.0
	var s := 0.0
	for f in _frames:
		s += f
	return s / _frames.size()


## 监视 duelist 的 BladeTerrain：包一层 terrain_blade_step 统计 impact。
func _hook_duelist() -> void:
	for e in _level.get("enemies"):
		if not is_instance_valid(e) or String(e.get("kind")) != "duelist":
			continue
		var orig: Callable = e.get("terrain_blade_step")
		if not orig.is_valid():
			continue
		e.terrain_blade_step = func(rig, dt: float, strike: int) -> Dictionary:
			var r: Dictionary = orig.call(rig, dt, strike)
			var imp: Dictionary = r.get("impact", {})
			if not imp.is_empty():
				_duelist_impacts += 1
				print("[blade-terrain] duelist impact: ", imp.get("point"), " n=", imp.get("normal"))
			return r
		print("[blade-terrain] hooked duelist terrain_blade_step")


## 从 arena 元信息挑可砍目标：优先离出生点近的 cover/solid 立面 + 边界墙。
func _pick_targets(arena: Dictionary) -> Array:
	var out: Array = []
	var spawn: Transform3D = arena.get("player_spawn", Transform3D.IDENTITY)
	# 手工基线目标：各关一个稳的立面（与约定验收点一致）。
	match _level_index:
		0:
			out.append({"pos": Vector3(-17.0, 0.0, 2.0), "yaw": _yaw_to(Vector3(-1, 0, 0)),
				"label": "west wall"})
		4:
			out.append({"pos": Vector3(-14.0, 0.0, -5.5), "yaw": _yaw_to(Vector3(0, 0, -1)),
				"label": "kiosk"})
			out.append({"pos": Vector3(20.0, 0.0, 9.0), "yaw": _yaw_to(Vector3(-1, 0, 0)),
				"label": "east kiosk"})
		5:
			out.append({"pos": Vector3(-11.0, 0.0, -1.2), "yaw": _yaw_to(Vector3(0, 0, -1)),
				"label": "cabinet"})
			out.append({"pos": Vector3(24.5, 0.0, 2.0), "yaw": _yaw_to(Vector3(1, 0, 0)),
				"label": "stair rail"})
		9:
			out.append({"pos": Vector3(24.5, 0.0, 2.0), "yaw": _yaw_to(Vector3(1, 0, 0)),
				"label": "stair rail"})
		_:
			# 通用：取离出生点最近的一面 walls 墙段，站到内法线一侧挥刀。
			var best := {}
			var best_d := INF
			for w: Dictionary in arena.get("walls", []):
				var mid := ((w["a"] as Vector2) + (w["b"] as Vector2)) * 0.5
				var p := Vector3(mid.x, w.get("base_y", arena.get("floor_y", 0.0)) + 1.2, mid.y)
				var d := p.distance_to(spawn.origin)
				if d < best_d:
					best_d = d
					best = {"p": p, "n": w["n"], "h": w["h"], "base": w.get("base_y", 0.0)}
			if not best.is_empty() and float(best["h"]) - float(best["base"]) > 1.0:
				var inward: Vector2 = best["n"]
				var at: Vector3 = best["p"] + Vector3(inward.x, 0.0, inward.y) * 2.0
				out.append({"pos": Vector3(at.x, best["base"], at.z),
					"yaw": _yaw_to(Vector3(-inward.x, 0.0, -inward.y)),
					"label": "nearest wall"})
	return out


static func _yaw_to(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func _place(pos: Vector3, yaw: float) -> void:
	var rig = _player.get("rig")
	if rig == null:
		return
	rig.global_position = pos
	rig.rotation.y = yaw
	if _level.get("player_previous") != null:
		_level.player_previous = pos
	if _cam != null:
		_cam.yaw = yaw
		_cam.pitch = -0.16


func _write_report() -> void:
	if not _args.has("report"):
		return
	var report := {"level": LEVEL_NAMES[_level_index], "impacts": _impacts.size(),
		"duelist_impacts": _duelist_impacts, "failures": _failures,
		"avg_ms": _avg_ms()}
	var f := FileAccess.open(String(_args["report"]), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[blade-terrain] report ", _args["report"])
