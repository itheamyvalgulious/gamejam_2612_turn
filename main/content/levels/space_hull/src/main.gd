extends "res://src/main.gd"
## 轨道船背：默认第一视角。
##
## 路线整体在 y=4 的背脊甲板上，船壳顶在 y=0；掉下甲板就会落回船壳，
## 这里把“低于甲板 0.8 m”当作跌落，送回最近检查点。
##
## 三道防空门禁：炮和光闸通电时走进门禁范围会被推回，并提示先拆供能节点。
## 初稿没有敌人：
##   走到琥珀色桅杆旁按住 F 约 2.5 s = 模拟“拆供能节点”；
##   F8 = 立刻切全部断电，用来快速预览。
##   F9 = 截图到 user://space_live.png。

const U := 1.0 / 0.547
const DECK_Y := 4.0
const FALL_Y := 3.2
const GATE_Y_MAX := 12.0
const NODE_RADIUS := 4.5
const SABOTAGE_TIME := 2.5

var _cps: Array = []
var _cp := 0
var _grace := 1.0
var _off_t := 0.0
var _done := false
var _dbg := 0.0
var _near_node := -1
var _sabotage_t := 0.0
var _gate_cd := 0.0


func _ready() -> void:
	super()
	P.set_value("cam.mode", "first")
	cam.set_first_person(true)
	# 地球在 ~2.3 km 外，默认 500 单位远裁面会把它切掉
	cam.camera.far = 6000.0
	if level != null and not level.arena.is_empty():
		_cps = level.arena.get("checkpoints", [])
	# room_shared 的 player.reset() 会把 rig.ground_height 归零，
	# mech_rig.reset_demo() 最后又把 position.y 压回 ground_height；
	# 所以 y=4 的背脊甲板必须在 reset 之后手动抬回去一次。
	if not _cps.is_empty():
		_lift_to(Vector3(float(_cps[0]["x"]), DECK_Y, float(_cps[0]["z"])))


func _process(delta: float) -> void:
	super(delta)
	if player == null or level == null or level.arena.is_empty():
		return
	if _cps.is_empty():
		_cps = level.arena.get("checkpoints", [])
	if _cps.is_empty():
		return
	if _grace > 0.0:
		_grace -= delta
	if _gate_cd > 0.0:
		_gate_cd -= delta

	var w: Vector3 = player.rig.position / U

	if _grace <= 0.0:
		# 门面通电时本身有实体碰撞；这里只处理“从上方越过门面”的薄判定
		if _gate_cd <= 0.0:
			for g in level.arena.get("gates", []):
				var st = g.get("state")
				if st == null or not st.online:
					continue
				if (w.x >= float(g["x0"]) and w.x <= float(g["x1"])
						and w.z >= float(g["z0"]) and w.z <= float(g["z1"])
						and w.y < GATE_Y_MAX):
					_gate_push(g)
					return

		# 跌落：路线在 y=4，船壳顶在 y=0
		if w.y < FALL_Y:
			_off_t += delta
			if _off_t > 0.30:
				_respawn("跌落", "已送回最近的检查点")
				return
		else:
			_off_t = 0.0
			_update_sabotage(delta, w)
			_checkpoint(w)
			if not _done and w.x > 188.2 and absf(w.z) < 15.0:
				_done = true
				hud.show_banner("抵达船坞大门", "场景初稿终点 · 门后是最终 Boss 关", 2.4)
				print("[hull] finish")

	_dbg += delta
	if _dbg >= 1.0:
		_dbg = 0.0
		var states: Array = level.arena.get("aa_states", [])
		var on := 0
		for st in states:
			if st.online:
				on += 1
		print("[hull] p=(%.1f, %.2f, %.1f) cp=%d aa=%d/%d" % [w.x, w.y, w.z, _cp, on, states.size()])


func _update_sabotage(delta: float, w: Vector3) -> void:
	var nodes: Array = level.arena.get("nodes", [])
	var best := -1
	var best_d := 999.0
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		var d := Vector2(w.x - float(n["x"]), w.z - float(n["z"])).length()
		if d < best_d:
			best_d = d
			best = i
	if best < 0 or best_d > NODE_RADIUS:
		if _near_node != -1:
			hud.set_hint("")
		_near_node = -1
		_sabotage_t = 0.0
		return
	var st = nodes[best].get("state")
	if st == null or not st.online:
		if _near_node != -1:
			hud.set_hint("")
		_near_node = -1
		_sabotage_t = 0.0
		return
	_near_node = best
	if Input.is_key_pressed(KEY_F):
		_sabotage_t += delta
		var pct := int(minf(_sabotage_t / SABOTAGE_TIME, 1.0) * 100.0)
		hud.set_hint("拆除本段供能节点 … %d%%（按住 F）" % pct)
		if _sabotage_t >= SABOTAGE_TIME:
			st.set_online(false)
			hud.show_banner("本段供能节点已拆除", "本段防空炮与光闸离线；可以继续推进", 1.6)
			hud.set_hint("")
			_near_node = -1
			_sabotage_t = 0.0
	else:
		_sabotage_t = 0.0
		hud.set_hint("按住 F 拆除本段供能节点（初稿模拟 2.5 s）")


func _gate_push(g: Dictionary) -> void:
	var mid := (float(g["x0"]) + float(g["x1"])) * 0.5
	var dir := -1.0 if player.rig.position.x / U <= mid else 1.0
	player.block_push = Vector3(dir * 10.0 * U, 0.0, 0.0)
	hud.show_banner("防空火力封锁", "先拆本段供能节点（或 F8 预览）", 1.2)
	_gate_cd = 1.0


func _checkpoint(w: Vector3) -> void:
	if _cp + 1 >= _cps.size():
		return
	var nxt: Dictionary = _cps[_cp + 1]
	if w.x >= float(nxt["x"]) - 0.8 and absf(w.z - float(nxt["z"])) < 6.0:
		_cp += 1
		hud.show_banner("检查点", "%d / %d" % [_cp, _cps.size() - 1], 1.0)


func _respawn(title: String, sub: String) -> void:
	var cp: Dictionary = _cps[_cp]
	var spawn := Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)),
		Vector3(float(cp["x"]), DECK_Y, float(cp["z"])) * U)
	player.reset(spawn)
	_lift_to(Vector3(float(cp["x"]), DECK_Y, float(cp["z"])))
	hud.show_banner(title, sub, 1.2)
	_grace = 0.8
	_off_t = 0.0


func _lift_to(p: Vector3) -> void:
	# reset 之后重新落到甲板面，而不是引擎默认的 y=0
	if player == null or player.rig == null:
		return
	player.rig.position = p * U
	player.rig.ground_height = p.y * U


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8:
			var states: Array = level.arena.get("aa_states", []) if level != null else []
			if not states.is_empty():
				var any_on := false
				for st in states:
					if st.online:
						any_on = true
				var next := not any_on
				for st in states:
					st.set_online(next)
				hud.show_banner("防空火力", "全部离线（初稿预览）" if not next else "全部上线", 1.2)
			return
		if event.keycode == KEY_F10:
			# 初稿调试：按 F10 依次跳到下一个检查点，省得每次从实验室重走
			if not _cps.is_empty():
				_cp = (_cp + 1) % _cps.size()
				var cp: Dictionary = _cps[_cp]
				_lift_to(Vector3(float(cp["x"]), DECK_Y, float(cp["z"])))
				hud.show_banner("调试传送", "检查点 %d / %d" % [_cp, _cps.size() - 1], 1.0)
			return
		if event.keycode == KEY_F9:
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://space_live.png")
			hud.show_banner("已截图", "user://space_live.png", 1.0)
			return
	super(event)
