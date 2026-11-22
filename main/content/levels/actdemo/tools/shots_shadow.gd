extends Node3D
## 出图：第三关影子（新系统）—— 出生点 / 墙面正面 / 第一人称自己的影子 / 挥刀。
##   DISPLAY=:0 godot --path . res://scenes/shots_shadow.tscn

const MainScene = preload("res://main.tscn")
const Shot = preload("res://tools/shot.gd")

var game
var shot = Shot.new()


func _ready() -> void:
	game = MainScene.instantiate()
	add_child(game)
	await _f(4)
	P.set_value("rules.god_mode", true)
	P.set_value("boss.laser_trigger", "disabled")
	P.set_value("cam.mode", "third")
	game.level.start_level(2)
	await _f(20)
	game.hud.show_banner("", "", 0.01)
	var sp: Transform3D = game.level.arena["player_spawn"]
	var boss = game.level.enemies[0]

	# 1) 出生点：面朝南墙（第三人称）
	_pose(boss, Vector3(-4, 0, 6), 0.4)
	_place(sp.origin, sp.basis.get_euler().y, 7.7)
	await _snap("res://shots/shadow_v2_spawn.png")

	# 2) 站到南墙前看整面墙（大怪放远处，别挡住镜头）
	_pose(boss, Vector3(-2, 0, 14), PI)
	_place(Vector3(0, 0, 30), PI, 9.0)
	game.cam.yaw = PI
	await _snap("res://shots/shadow_v2_wall.png")

	# 3) 第一人称：自己的影子
	P.set_value("cam.mode", "first")
	game.cam.set_first_person(true)
	_pose(boss, Vector3(2, 0, 16), PI)
	_place(Vector3(-6, 0, 33), PI * 0.97, 7.7)
	game.cam.pitch = 0.02
	await _snap("res://shots/shadow_v2_fp.png")

	# 4) 大怪挥刀（第三人称，看北墙）
	P.set_value("cam.mode", "third")
	game.cam.set_first_person(false)
	_pose(boss, Vector3(0, 0, -12), PI)
	_place(Vector3(0, 0, 8), PI, 8.5)
	game.cam.yaw = PI
	game.set_process(false)
	boss.rig.force_attack("heavy")
	var g := 0
	while not boss.rig.in_hit_window() and g < 400:
		boss.rig.advance(1.0 / 240.0)
		g += 1
	await _snap("res://shots/shadow_v2_attack.png")
	get_tree().quit()


## 摆好位置后冻结游戏逻辑（影子遮罩仍然每帧由引擎渲染）
func _pose(boss, pos: Vector3, yaw: float) -> void:
	game.set_process(true)
	boss.rig.global_position = pos
	boss.rig.heading = yaw
	boss.rig.rotation.y = yaw
	boss.rig.facing_override = true
	boss.rig.facing_heading = yaw


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(path: String) -> void:
	game.set_process(false)          # 冻结：AI 不会跑到镜头前
	await _f(3)
	game.level.shadow.refresh()
	await _f(3)
	await shot.capture(self, path, 3)
	game.set_process(true)


func _place(player_pos: Vector3, yaw: float, dist := 8.2) -> void:
	game.player.rig.global_position = player_pos
	game.player.rig.heading = yaw
	game.player.rig.rotation.y = yaw
	game.player.rig.facing_override = true
	game.cam.yaw = yaw
	game.cam.pitch = -0.10
	P.set_value("cam.distance", dist)
	game.cam.step(1.0 / 60.0, game.level.arena)
	game.cam.step(1.0 / 60.0, game.level.arena)
