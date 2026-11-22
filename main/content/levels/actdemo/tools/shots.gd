extends Node3D
## 出图：把整局游戏挂起来，逐关摆机位截图（用来看画面，不做逻辑断言）
##   DISPLAY=:0 godot --path actdemo res://scenes/shots.tscn

const MainScene = preload("res://main.tscn")
const Shot = preload("res://tools/shot.gd")

var game
var shot = Shot.new()


func _ready() -> void:
	print("[shots] 开始")
	game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	P.set_value("rules.god_mode", true)
	P.set_value("cam.mode", "third")

	await _l1()
	await _l2()
	await _l3()
	await _l3_shadow()
	await _fp()
	await _ui()
	P.set_value("rules.god_mode", false)
	P.reset_group("规则")
	print("[shots] 完成")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(path: String) -> void:
	await _frames(6)
	await shot.capture(self, path, 2)


func _place(player_pos: Vector3, yaw: float, dist := 8.2) -> void:  # 米
	game.player.rig.global_position = player_pos
	game.player.rig.heading = yaw
	game.player.rig.rotation.y = yaw
	game.player.rig.facing_override = true
	game.cam.yaw = yaw
	game.cam.pitch = -0.12
	P.set_value("cam.distance", dist)
	game.cam.step(1.0 / 60.0, game.level.arena)
	game.cam.step(1.0 / 60.0, game.level.arena)


func _l1() -> void:
	game.level.start_level(0)
	await _frames(30)
	var sp: Transform3D = game.level.arena["player_spawn"]
	_place(sp.origin, sp.basis.get_euler().y)
	await _frames(40)
	await _snap("res://shots/game_L1.png")
	# 挥砍瞬间
	game.player._attack_from_input(Vector2.ZERO)
	await _frames(12)
	await _snap("res://shots/game_L1_swing.png")


func _l2() -> void:
	game.level.start_level(1)
	await _frames(30)
	var sp: Transform3D = game.level.arena["player_spawn"]
	_place(sp.origin, sp.basis.get_euler().y, 8.2)
	var fwd: Vector3 = -game.player.rig.global_transform.basis.z
	var right: Vector3 = game.player.rig.global_transform.basis.x
	game.level.enemies[0].global_position = sp.origin + fwd * 12.0 - right * 5.0
	game.level.enemies[1].global_position = sp.origin + fwd * 16.0 + right * 4.0
	game.level.enemies[2].global_position = sp.origin + fwd * 20.0 - right * 1.0
	game.level.archers[0].global_position = sp.origin + fwd * 26.0 + right * 7.0
	await _frames(200)
	await _snap("res://shots/game_L2.png")


func _l3() -> void:
	game.level.start_level(2)
	await _frames(30)
	var boss = game.level.enemies[0]
	boss.global_position = Vector3(0, 0, -4)
	_place(Vector3(0, 0, 20), 0.0, 7.7)
	await _frames(200)
	await _snap("res://shots/game_L3.png")


func _l3_shadow() -> void:
	var boss = game.level.enemies[0]
	boss.global_position = Vector3(-2, 0, -6)
	boss.rig.face_target(Vector3(2, 0, 6))
	await _frames(40)
	# 站在侧后方看「墙上的影子」，不直视大怪
	_place(Vector3(16, 0, 16), deg_to_rad(-140.0), 6.6)
	game.cam.yaw = deg_to_rad(-128.0)
	game.cam.pitch = -0.02
	await _frames(200)
	await _snap("res://shots/game_L3_shadow.png")


func _fp() -> void:
	game.level.start_level(0)
	await _frames(30)
	P.set_value("cam.mode", "first")
	var sp: Transform3D = game.level.arena["player_spawn"]
	_place(sp.origin, sp.basis.get_euler().y)
	game.cam.set_first_person(true)
	game.cam.pitch = 0.02
	await _frames(200)
	await _snap("res://shots/game_L1_fp.png")
	P.set_value("cam.mode", "third")


func _ui() -> void:
	P.set_value("cam.mode", "third")
	game.tuning.open()
	await _frames(10)
	await _snap("res://shots/game_ui_tuning.png")
	game.tuning.close()
	game.binds.open()
	await _frames(10)
	await _snap("res://shots/game_ui_binds.png")
	game.binds.close()
