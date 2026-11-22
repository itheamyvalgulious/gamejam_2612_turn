extends Node3D
const MainScene = preload("res://main.tscn")
var game

func _ready() -> void:
	game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	P.set_value("rules.god_mode", true)
	P.set_value("cam.mode", "first")
	await get_tree().process_frame
	game.cam.set_first_person(true)
	game.cam.pitch = 0.02
	for i in 60:
		await get_tree().process_frame
	var cam: Camera3D = game.cam.camera
	var vp: Vector2 = cam.get_viewport().get_visible_rect().size
	var rig = game.player.rig
	var hilt: Vector3 = rig.weapon_xf.origin
	var tip: Vector3 = rig.weapon_xf * Vector3(0, 2.87, 0)
	var mid: Vector3 = rig.weapon_xf * Vector3(0, 1.4, 0)
	print("[fp] 视口 %s  FOV %.0f" % [str(vp), cam.fov])
	print("[fp] 刀柄屏幕坐标 %s（视口比例 %.2f, %.2f）" % [str(cam.unproject_position(hilt).snapped(Vector2(1,1))),
		cam.unproject_position(hilt).x / vp.x, cam.unproject_position(hilt).y / vp.y])
	print("[fp] 刀中屏幕坐标 %s（比例 %.2f, %.2f）" % [str(cam.unproject_position(mid).snapped(Vector2(1,1))),
		cam.unproject_position(mid).x / vp.x, cam.unproject_position(mid).y / vp.y])
	print("[fp] 刀尖屏幕坐标 %s（比例 %.2f, %.2f）" % [str(cam.unproject_position(tip).snapped(Vector2(1,1))),
		cam.unproject_position(tip).x / vp.x, cam.unproject_position(tip).y / vp.y])
	print("[fp] 相机世界位置 %s 刀柄 %s" % [str(cam.global_position.snapped(Vector3(0.01,0.01,0.01))), str(hilt.snapped(Vector3(0.01,0.01,0.01)))])
	get_tree().quit()
