extends "res://src/main.gd"
## 三号船坞：默认第一视角。
##
## 共用房间关卡的装配流程（玩家、HUD、参数面板都来自 room_shared），
## 只在装配完成后把视角切成第一人称。第三人称视角已废弃，本关不按它调参。
##
## F8 = 预览二阶段灯光（只切灯，不推进 Boss 流程）。


func _ready() -> void:
	super()
	P.set_value("cam.mode", "first")
	cam.set_first_person(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://hangar_live.png")
		hud.show_banner("已截图", "build/hangar_shots/live.png", 1.0)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		var rig = level.arena.get("phase2")
		if rig != null:
			rig.set_phase2(not rig.active)
			hud.show_banner("二阶段灯光预览", "ON · 其他灯关闭，只留投影灯" if rig.active else "OFF", 1.0)
			return
	super(event)
