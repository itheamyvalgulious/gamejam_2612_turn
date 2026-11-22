extends Node

func _ready() -> void:
	print("启动时的用户存档参数：")
	print("  rules.god_mode = ", P.getb("rules.god_mode"))
	print("  rules.time_scale = ", P.getf("rules.time_scale"))
	print("  boss.hp = ", P.getf("boss.hp"))
	print("  boss.laser_trigger = ", P.gets("boss.laser_trigger"))
	print("  存档路径 = ", ProjectSettings.globalize_path("user://actdemo_params.json"))
	get_tree().quit(0)
