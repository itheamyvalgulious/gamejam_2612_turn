extends "res://src/main.gd"
## 三号船坞：默认第一视角。
##
## 共用房间关卡的装配流程（玩家、HUD、参数面板都来自 room_shared），
## 只在装配完成后把视角切成第一人称。第三人称视角已废弃，本关不按它调参。


func _ready() -> void:
	super()
	P.set_value("cam.mode", "first")
	cam.set_first_person(true)
