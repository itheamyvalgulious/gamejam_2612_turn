extends Node3D
const MainScene = preload("res://main.tscn")
const Shot = preload("res://tools/shot.gd")
func _ready() -> void:
	var game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	P.set_value("rules.god_mode", true)
	P.set_value("cam.mode", "first")
	game.cam.set_first_person(true)
	game.cam.pitch = 0.02
	P.set_value("attack.slash_left.duration", 2.0)
	P.set_value("attack.slash_left.windup", 0.6)
	if OS.has_feature("shot_mid"):
		pass
	for i in 260:
		await get_tree().process_frame
	var s = Shot.new()
	await s.capture(self, "res://shots/fp_idle.png", 2)
	# 挥砍中段
	game.player._attack_from_input(Vector2(-1, 0))
	for i in 48:
		await get_tree().process_frame
	await s.capture(self, "res://shots/fp_left.png", 2)
	P.reset_all()
	get_tree().quit()
