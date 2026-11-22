extends Node3D
## 走真实输入链路（真按键 + 真鼠标 + main 的主循环），复现"扫到了没反应"

const MainScene = preload("res://main.tscn")
var game
var events: Array = []


func _ready() -> void:
	game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	P.set_value("rules.god_mode", true)
	print("[real] 场景：敌人 4.6 m 正前，分别测「相机朝前 / 转左90 / 转右90」× 「A左斩 / D右斩」")
	for cam_deg in [0.0, 90.0, -90.0]:
		for atk in ["A", "D"]:
			await _case(cam_deg, atk)
	get_tree().quit()


func _case(cam_deg: float, atk: String) -> void:
	game.level.start_level(0)
	await get_tree().process_frame
	var mob = game.level.enemies[0]
	var player = game.player
	P.set_value("cam.mode", "first")
	P.set_value("move.facing_mode", "camera")
	player.reset(Transform3D(Basis(), Vector3.ZERO))
	await get_tree().process_frame
	mob.global_position = Vector3(0, 0, -4.6)
	game.cam.yaw = deg_to_rad(cam_deg)
	game.cam.step(1.0 / 60.0, game.level.arena)
	game.cam.step(1.0 / 60.0, game.level.arena)
	var visible_now: bool = Vision.is_visible(game.cam.camera, mob.center(), mob.mark_radius())
	# 真按键：按住 A 或 D
	var key: int = KEY_A if atk == "A" else KEY_D
	Input.action_press("move_left" if atk == "A" else "move_right")
	for i in 4:
		Input.parse_input_event(_key(key, true))
		await get_tree().process_frame
	# 真鼠标左键
	var me := InputEventMouseButton.new()
	me.button_index = MOUSE_BUTTON_LEFT
	me.pressed = true
	Input.parse_input_event(me)
	var hp0: float = mob.hp
	var min_clear := 999.0
	var frame_log := ""
	for i in 90:
		await get_tree().process_frame
		var parts: Array = mob.hit_parts()
		var rig = player.rig
		if rig.in_hit_window():
			for d in rig.blade_discs:
				var c: Vector3 = rig.weapon_xf * Vector3(0, float(d["y"]), 0)
				for part in parts:
					var dd: float = Hit.dist_point_segment(c, part["a"], part["b"])
					min_clear = minf(min_clear, dd - (float(d["r"]) * rig.weapon_scale + float(part["r"])))
				if i < 2 and min_clear < 99.0:
					frame_log += "f%d" % i
	Input.action_release("move_left")
	Input.action_release("move_right")
	var me2 := InputEventMouseButton.new()
	me2.button_index = MOUSE_BUTTON_LEFT
	me2.pressed = false
	Input.parse_input_event(me2)
	var dmg: float = hp0 - mob.hp
	print("[real] 相机%+4d° %s斩 → 画内=%s  伤害=%.0f  (hp %.0f→%.0f)  判定窗口内刀-怪最近间隙=%.2f" % [
		int(cam_deg), atk, str(visible_now), dmg, hp0, mob.hp, min_clear])


func _key(code: int, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	return e
