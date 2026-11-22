extends Node3D
const MainScene = preload("res://main.tscn")
var game
var walked: Array = []
var recorded: Array = []

func _ready() -> void:
	game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	P.set_value("rules.god_mode", true)
	P.set_value("cam.mode", "third")
	# 走一段已知路线：按 W 前进 3 秒（世界 -Z 方向），并记录每帧位置
	Input.action_press("move_forward")
	for i in 180:
		await get_tree().process_frame
		if i % 30 == 0:
			walked.append(game.player.rig.global_position.snapped(Vector3(0.01, 0.01, 0.01)))
	Input.action_release("move_forward")
	print("[rep2] 实际走过的采样 = ", walked)
	# 逐帧读出录制缓冲里的位置，做对比
	var n: int = game.replay.stride
	var rig = game.player.rig
	var cache: Array = game.replay._nodes_for(rig)
	for i in range(0, game.replay.head, 30):
		var o: int = i * n + 2
		var pos := Vector3(game.replay.buf[o + 1], game.replay.buf[o + 2], game.replay.buf[o + 3])
		recorded.append(pos.snapped(Vector3(0.01, 0.01, 0.01)))
	print("[rep2] 录制缓冲里的采样 = ", recorded)
	# 回放：逐帧比对"写到节点上的位置"与"缓冲里的位置"
	game.replay.start()
	var bad := 0
	var checked := 0
	for i in 90:
		await get_tree().process_frame
		if i % 15 == 0:
			var fi: int = int(game.replay.play_frame)
			var o: int = fi * n + 2
			var want := Vector3(game.replay.buf[o + 1], game.replay.buf[o + 2], game.replay.buf[o + 3])
			var got: Vector3 = game.player.rig.global_position
			checked += 1
			if want.distance_to(got) > 0.05:
				bad += 1
			if i == 0:
				print("[rep2] 回放帧 %d：缓冲=%s 节点=%s" % [fi, str(want.snapped(Vector3(0.01,0.01,0.01))), str(got.snapped(Vector3(0.01,0.01,0.01)))])
	print("[rep2] 回放一致性：%d 次比对，%d 次不一致（应 0）" % [checked, bad])
	print("[rep2] 回放速度 %.1f×  已录 %.1f 秒" % [game.replay.speed, game.replay.recorded_seconds()])
	get_tree().quit()
