extends Node3D
## 探针：Esc 开关菜单 + 鼠标锁定 + 关菜单后能不能继续操作

const MainScene = preload("res://main.tscn")

var game


func _ready() -> void:
	game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	P.set_value("rules.god_mode", true)

	func_ev(KEY_ESCAPE)
	await get_tree().process_frame
	print("[esc] 按 Esc 后：菜单开=%s 鼠标=%d" % [str(game._menus_open()), Input.mouse_mode])
	# 面板句柄
	func_ev(KEY_ESCAPE)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[esc] 再按 Esc：菜单开=%s 鼠标=%d（应 关 / 2=CAPTURED）" % [
		str(game._menus_open()), Input.mouse_mode])
	# 关掉后能不能继续挥手
	var before: bool = game.player.rig.is_attacking
	func_ev(KEY_A)
	await get_tree().process_frame
	func_ev(KEY_A, false)
	print("[esc] 关掉菜单后仍可输入：A 键移动指令长度=%.2f" % game.player.rig.move_command.length())
	# 面板里的「继续游戏」按钮路径（直接调 close）
	game.binds.open()
	await get_tree().process_frame
	game.binds.close()
	await get_tree().process_frame
	await get_tree().process_frame
	print("[esc] 用面板按钮关闭后：菜单开=%s 鼠标=%d（应 关 / 2）" % [
		str(game._menus_open()), Input.mouse_mode])
	get_tree().quit()


func func_ev(code: int, pressed := true) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
