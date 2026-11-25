extends "res://src/main.gd"
## 暮色楼顶：默认第一视角。
##
## 楼顶样段没有死亡判定，掉出屋面会一直落到街面 y=0 并卡在那里。
## 这里只加一条兜底：低于大屋面 6 m 就把玩家送回出生点，省得只能重开关卡。


const U := 1.0 / 0.547
const FALL_Y := -6.0   # 米；大屋面在 0 m，掉到街面以下才兜底
const DECK_X0 := -46.0
const DECK_X1 := 56.0
const DECK_Z0 := -30.0
const DECK_Z1 := 30.0

var _dbg := 0.0


func _ready() -> void:
	super()
	P.set_value("cam.mode", "first")
	cam.set_first_person(true)


func _process(delta: float) -> void:
	super(delta)
	if player == null or level == null or level.arena.is_empty():
		return
	if player.rig.position.y < FALL_Y * U:
		player.reset(level.arena["player_spawn"])
		hud.show_banner("跌出屋面", "已送回起点", 1.2)
		return
	var w: Vector3 = player.rig.position / U
	if w.x < DECK_X0 - 0.5 or w.x > DECK_X1 + 0.5 or w.z < DECK_Z0 - 0.5 or w.z > DECK_Z1 + 0.5:
		player.reset(level.arena["player_spawn"])
		hud.show_banner("跌出屋面", "已送回起点", 1.2)
		return
	_dbg += delta
	if _dbg >= 0.5:
		_dbg = 0.0
		var p: Vector3 = player.rig.position / U
		print("[roof] p=(%.1f, %.2f, %.1f) yaw=%.0f ground=%.2f" % [
			p.x, p.y, p.z, rad_to_deg(player.rig.heading), player.rig.ground_height / U])
