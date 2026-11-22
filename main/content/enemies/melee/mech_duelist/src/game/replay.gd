extends Node
class_name Replay
## 回放：把最后 20 秒的**世界变换**录下来，按 Del 用第三人称重放。
##
## 录制的是"结果"而不是"输入"：每个机甲关节的世界变换（位置+四元数+缩放）逐帧存，
## 回放时直接写回节点。优点是与模拟完全解耦——不会因为随机数/时序判断不一致而跑偏，
## 也顺手把刀身的扫掠过程完整录下来了（排查"为什么砍不到"最直接）。
##
## 每帧结构（float 平铺）：
##   [关卡号, 玩家有效, 演员槽 0..ACTORS-1 (每个 1+NODES_PER_ACTOR*NODE_FLOATS),
##    飞行物槽 0..PROJ-1 (每个 1+3)]

const SECONDS := 20.0
const ACTORS := 5          # 0=玩家, 1..4=敌人
const PROJ := 16
const EVENTS := 4           # 每帧最多记 4 条战斗事件：kind + 位置
const NODES_PER_ACTOR := 24   # 6 根(body/torso/head/weapon×2/root) + 4 腿×3 + 2 臂×3
const NODE_FLOATS := 10       # 每个关节：位置 3 + 四元数 4 + 缩放 3（缩放必须录，见 _apply）

var active := false
const _KIND_ID := {"hit": 1.0, "block": 2.0, "kill": 3.0, "parry": 4.0}
const _ID_KIND := {1.0: "命中", 2.0: "被格挡", 3.0: "击破", 4.0: "弹反"}

var buf := PackedFloat32Array()
var head := 0              # 已写入帧数（环形）
var stride := 0
var level_index := -1
var play_frame := 0.0
var speed := 1.0           # 回放速度（实时）
var paused := false

var _player
var _level
var _proj
var _cache: Dictionary = {}     # rig -> Array[Node3D]
var _pending: Array = []        # 本帧待记录的判决事件
var cur_events: Array = []      # 当前回放帧的事件（kind,pos）
var dbg: MeshInstance3D
var _dbg_mesh := ArrayMesh.new()


func setup(player, level, proj) -> void:
	_player = player
	_level = level
	_proj = proj
	stride = 2 + ACTORS * (1 + NODES_PER_ACTOR * NODE_FLOATS) + PROJ * 4 + EVENTS * 4
	buf.resize(stride * int(SECONDS * 70.0))


func clear() -> void:
	head = 0
	_cache.clear()


## 战斗判决事件：kind = "hit" / "block" / "kill" / "parry"
func note_event(kind: String, pos: Vector3) -> void:
	if _pending.size() < EVENTS:
		_pending.append({"k": kind, "p": pos})


## 每个模拟帧调一次
func record() -> void:
	if active or _player == null or _level == null:
		return
	if _level.index != level_index:
		level_index = _level.index
		head = 0
		_cache.clear()
	var n := stride
	var need := (head + 1) * n
	if need > buf.size():
		# 环形覆盖：必须按"整帧"丢弃，否则字段会错位（之前的轨迹对不上就是这个）
		var keep_frames := (buf.size() / n) / 2
		var keep := keep_frames * n
		var tmp := buf.slice(keep)
		buf = tmp
		buf.resize(stride * int(SECONDS * 70.0))
		head = keep_frames
		need = (head + 1) * n
	var o := head * n
	buf[o] = float(_level.index)
	buf[o + 1] = 1.0
	var p := o + 2
	# 玩家
	p = _write_actor(p, _player.rig)
	# 敌人
	for i in ACTORS - 1:
		if i < _level.enemies.size() and is_instance_valid(_level.enemies[i]):
			var e = _level.enemies[i]
			if e.alive or e.visible:
				p = _write_actor(p, e.rig)
			else:
				p = _write_empty(p)
		else:
			p = _write_empty(p)
	# 判决事件
	for i in EVENTS:
		if i < _pending.size():
			var ev: Dictionary = _pending[i]
			buf[p] = float(_KIND_ID.get(String(ev["k"]), 0))
			var ep: Vector3 = ev["p"]
			buf[p + 1] = ep.x
			buf[p + 2] = ep.y
			buf[p + 3] = ep.z
		else:
			buf[p] = 0.0
		p += 4
	_pending.clear()
	# 飞行物
	var items: Array = _proj.items if _proj != null else []
	for i in PROJ:
		if i < items.size() and bool(items[i]["alive"]) and is_instance_valid(items[i]["node"]):
			buf[p] = 1.0
			var wp: Vector3 = (items[i]["node"] as Node3D).global_position
			buf[p + 1] = wp.x
			buf[p + 2] = wp.y
			buf[p + 3] = wp.z
			p += 4
		else:
			buf[p] = 0.0
			p += 4
	head += 1


func _nodes_for(rig) -> Array:
	if rig == null or not is_instance_valid(rig):
		return []
	if _cache.has(rig):
		return _cache[rig]
	var list: Array = [rig, rig.body, rig.torso, rig.head, rig.weapon_root, rig.weapon_spin]
	for leg in rig.legs:
		list.append(leg["hip"])
		list.append(leg["knee"])
		list.append(leg["ankle"])
	for arm in rig.arms:
		list.append(arm["shoulder"])
		list.append(arm["elbow"])
		list.append(arm["wrist"])
	_cache[rig] = list
	return list


func _write_actor(p: int, rig) -> int:
	var list := _nodes_for(rig)
	if list.is_empty():
		return _write_empty(p)
	buf[p] = 1.0
	var q := p + 1
	for nd in list:
		var xf: Transform3D = nd.global_transform
		var pos := xf.origin
		var quat := xf.basis.get_rotation_quaternion()
		buf[q] = pos.x
		buf[q + 1] = pos.y
		buf[q + 2] = pos.z
		buf[q + 3] = quat.x
		buf[q + 4] = quat.y
		buf[q + 5] = quat.z
		buf[q + 6] = quat.w
		var sc := xf.basis.get_scale()
		buf[q + 7] = sc.x
		buf[q + 8] = sc.y
		buf[q + 9] = sc.z
		q += NODE_FLOATS
	return p + 1 + NODES_PER_ACTOR * NODE_FLOATS


func _write_empty(p: int) -> int:
	buf[p] = 0.0
	return p + 1 + NODES_PER_ACTOR * NODE_FLOATS


# ------------------------------------------------------------------ 回放
func start() -> void:
	if head < 4 or _player == null:
		return
	active = true
	play_frame = 0.0
	paused = false


func stop() -> void:
	active = false
	if dbg != null and is_instance_valid(dbg):
		dbg.mesh = null


func toggle() -> void:
	if active:
		stop()
	else:
		start()


func step(dt: float) -> void:
	if not active:
		return
	if not paused:
		play_frame += dt * 60.0 * speed
	var i := int(play_frame)
	if i >= head:
		active = false
		return
	_apply(i)
	_read_events(i)
	_draw_debug()
	# 记录用的飞行物位置直接写回（找不到节点就跳过）
	var o := i * stride
	var p := o + 2 + ACTORS * (1 + NODES_PER_ACTOR * NODE_FLOATS)
	var items: Array = _proj.items if _proj != null else []
	for k in PROJ:
		if buf[p] > 0.5 and k < items.size():
			var nd = items[k]["node"]
			if is_instance_valid(nd):
				(nd as Node3D).global_position = Vector3(buf[p + 1], buf[p + 2], buf[p + 3])
		p += 4


## 事件区在本帧数据里的偏移
func _ev_offset(i: int) -> int:
	return i * stride + 2 + ACTORS * (1 + NODES_PER_ACTOR * NODE_FLOATS) + PROJ * 4


func _read_events(i: int) -> void:
	cur_events.clear()
	var o := _ev_offset(i)
	for k in EVENTS:
		var id := buf[o + k * 4]
		if id > 0.5:
			cur_events.append({"k": _ID_KIND.get(id, "?"),
				"p": Vector3(buf[o + k * 4 + 1], buf[o + k * 4 + 2], buf[o + k * 4 + 3])})


## 判定可视化：画出玩家刀身真实的碰撞圆盘链 + 敌人多段判定件 + 判决点
func _draw_debug() -> void:
	if dbg == null:
		dbg = MeshInstance3D.new()
		dbg.name = "ReplayDebug"
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.no_depth_test = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 0.95)
		dbg.material_override = m
		dbg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dbg)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	# 玩家刀身圆盘链（用录制下来的 weapon_spin 变换重建）
	var rig = _player.rig
	if is_instance_valid(rig) and rig.blade_discs.size() > 0:
		var xf: Transform3D = rig.weapon_spin.global_transform
		var sc: float = xf.basis.get_scale().x
		for d in rig.blade_discs:
			var c: Vector3 = xf * Vector3(0, float(d["y"]), 0)
			var r: float = float(d["r"]) * sc
			# 十字线表示半径
			_line(st, c + Vector3(r, 0, 0), c - Vector3(r, 0, 0), Color(1.0, 0.75, 0.15, 0.85))
			_line(st, c + Vector3(0, 0, r), c - Vector3(0, 0, r), Color(1.0, 0.45, 0.1, 0.6))
	# 敌人受击判定件（多段胶囊：躯干/头/四肢，跟着关节走）
	for e in _level.enemies:
		if not is_instance_valid(e):
			continue
		for part in e.hit_parts():
			var a: Vector3 = part["a"]
			var b: Vector3 = part["b"]
			var rr: float = float(part["r"])
			_line(st, a, b, Color(0.3, 0.9, 1.0, 0.9))
			for k in 8:
				var ang := TAU * float(k) / 8.0
				var ang2 := TAU * float(k + 1) / 8.0
				_line(st, a + Vector3(cos(ang), 0, sin(ang)) * rr,
					a + Vector3(cos(ang2), 0, sin(ang2)) * rr, Color(0.3, 0.9, 1.0, 0.7))
			if b.distance_to(a) > 0.4:
				for k in 8:
					var ang := TAU * float(k) / 8.0
					var ang2 := TAU * float(k + 1) / 8.0
					_line(st, b + Vector3(cos(ang), 0, sin(ang)) * rr,
						b + Vector3(cos(ang2), 0, sin(ang2)) * rr, Color(0.3, 0.9, 1.0, 0.7))
	# 判决点
	for ev in cur_events:
		var p: Vector3 = ev["p"]
		var col := Color(0.2, 1.0, 0.35, 1.0) if String(ev["k"]) == "命中" else Color(1.0, 0.25, 0.2, 1.0)
		for ax in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
			_line(st, p - ax * 0.5, p + ax * 0.5, col)
	dbg.mesh = st.commit()


func _line(st: SurfaceTool, a: Vector3, b: Vector3, c: Color) -> void:
	st.set_color(c)
	st.add_vertex(a)
	st.set_color(c)
	st.add_vertex(b)


func _apply(i: int) -> void:
	var o := i * stride
	var p := o + 2
	var rigs: Array = [_player.rig]
	for e in _level.enemies:
		rigs.append(e.rig)
	for a in ACTORS:
		if buf[p] > 0.5 and a < rigs.size():
			var actor = rigs[a]
			var list := _nodes_for(actor)
			var q := p + 1
			for nd in list:
				if not is_instance_valid(nd):
					q += NODE_FLOATS
					continue
				var pos := Vector3(buf[q], buf[q + 1], buf[q + 2])
				var quat := Quaternion(buf[q + 3], buf[q + 4], buf[q + 5], buf[q + 6])
				var sc := Vector3(buf[q + 7], buf[q + 8], buf[q + 9])
				# 直接写全局变换：录制的是结果，回放不该再受父级驱动。
				# 缩放必须一起还原：torso ×1.45 / head ×1.42 / 大怪 rig ×2 都在节点缩放里，
				# 只写「位置 + 旋转」会把机体压成细柱子。
				nd.global_transform = Transform3D(Basis(quat.normalized()).scaled(sc), pos)
				q += NODE_FLOATS
			if actor.has_method("sync_replay_pose"):
				actor.sync_replay_pose()
		else:
			p += 1 + NODES_PER_ACTOR * NODE_FLOATS
			continue
		p += 1 + NODES_PER_ACTOR * NODE_FLOATS


func progress() -> float:
	if head <= 0:
		return 0.0
	return clampf(play_frame / float(head), 0.0, 1.0)


func recorded_seconds() -> float:
	return float(head) / 60.0
