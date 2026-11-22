extends Node3D
const MainScene = preload("res://main.tscn")
const Shot = preload("res://tools/shot.gd")
var game
var path: Array = []

func _ready() -> void:
	game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	P.set_value("rules.god_mode", true)
	P.set_value("cam.mode", "first")
	# 跑 4 秒真实模拟，中途挥砍，同时记录玩家位置轨迹
	for i in 240:
		await get_tree().process_frame
		if i == 60:
			game.player._attack_from_input(Vector2(-1, 0))
		if i % 30 == 0:
			path.append(game.player.rig.global_position.snapped(Vector3(0.1, 0.1, 0.1)))
	print("[rep] 录制帧数 = %d （%.1f 秒）" % [game.replay.head, game.replay.recorded_seconds()])
	print("[rep] 玩家轨迹采样 = ", path.slice(0, 4))
	# 用真按键 Del 触发回放
	var ev := InputEventKey.new()
	ev.keycode = KEY_DELETE
	ev.physical_keycode = KEY_DELETE
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[rep] 回放开始 active=%s" % str(game.replay.active))
	var p0: Vector3 = game.player.rig.global_position
	for i in 60:
		await get_tree().process_frame
	var p1: Vector3 = game.player.rig.global_position
	print("[rep] Del 触发后：active=%s cam=%s" % [str(game.replay.active), P.gets("cam.mode")])
	print("[rep] 回放 1 秒后：玩家位置 %s → %s（应该动起来）" % [str(p0.snapped(Vector3(0.1,0.1,0.1))), str(p1.snapped(Vector3(0.1,0.1,0.1)))])
	print("[rep] 进度 %.2f 相机模式=%s" % [game.replay.progress(), P.gets("cam.mode")])
	var s = Shot.new()
	await s.capture(self, "res://shots/replay_check.png", 2)
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[rep] 退出回放 active=%s 相机模式=%s" % [str(game.replay.active), P.gets("cam.mode")])
	get_tree().quit()
