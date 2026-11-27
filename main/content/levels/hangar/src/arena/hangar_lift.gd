extends Node3D
## 控制台升降台：玩家站进轿厢后自动升到控制台层；离开后延时回落。
##
## 引擎没有斜坡/台阶行走，`platforms` 只提供水平支撑面。这里每帧同步三件事：
## 轿厢视觉高度、`platforms` 里这块台面的高度、以及站在上面的玩家高度。
## 另外做垂直夹紧，防止从轿厢顶棚钻出去。

const U := 1.0 / 0.547

var car: Node3D
var plats: Array
var idx := -1
var center := Vector3.ZERO
var top_y := 8.5
var car_y := 0.0
var target_y := 0.0
var speed := 1.4
var hold := 2.2
var headroom := 2.35
var player = null
var _moving := false
var _dbg := 0.0


func setup(p_car: Node3D, p_plats: Array, p_idx: int, p_center: Vector3,
		p_top: float, p_headroom: float) -> void:
	car = p_car
	plats = p_plats
	idx = p_idx
	center = p_center
	top_y = p_top
	headroom = p_headroom


func _process(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		var s := get_tree().current_scene
		if s == null:
			return
		player = s.get("player")
		if player == null:
			return

	var p: Vector3 = player.rig.position
	var cx: float = center.x * U
	var cz: float = center.z * U
	# 轿厢地板面 = 轿厢位置 + 甲板厚度；托人与台面必须用同一个高度，
	# 差超过 5.5 cm（引擎着地容差）角色就会失去支撑、留在原地。
	var floor_y: float = car_y + 0.10
	var inside_xz := absf(p.x - cx) <= 1.16 * U and absf(p.z - cz) <= 1.42 * U
	# 在井道平面内、但已经掉到轿厢下面：直接拉回地板（避免“被挤下来”的观感）
	if inside_xz and p.y < (floor_y - 0.5) * U:
		p.y = floor_y * U
		player.rig.position = p
		if player.rig.get("vertical_velocity") != null:
			player.rig.vertical_velocity = 0.0

	var inside := inside_xz and p.y >= (floor_y - 0.6) * U and p.y <= (floor_y + 2.2) * U

	if inside:
		target_y = top_y
		hold = 2.2
	elif car_y > 0.2 and hold > 0.0:
		hold -= dt
		if hold <= 0.0:
			target_y = 0.0

	if absf(car_y - target_y) > 0.0005:
		car_y = move_toward(car_y, target_y, speed * dt)

	car.position.y = car_y * U
	if idx >= 0 and idx < plats.size():
		plats[idx]["h"] = floor_y * U

	if inside:
		# 站在地板上
		p.y = maxf(p.y, floor_y * U)
		# 顶棚：超过净高就压回去，并清掉上升速度
		var ceiling: float = (floor_y + headroom) * U
		if p.y > ceiling:
			p.y = ceiling
			if player.rig.get("vertical_velocity") != null:
				player.rig.vertical_velocity = minf(player.rig.vertical_velocity, 0.0)
		player.rig.position = p

	#_dbg += dt
	#if _dbg > 0.25:
	#	_dbg = 0.0
	#	print("[lift] car=%.2f inside=%s p=(%.2f, %.2f, %.2f)" % [car_y, inside, p.x * 0.547, p.y * 0.547, p.z * 0.547])

	var moving := absf(car_y - target_y) > 0.0005
	if moving != _moving:
		_moving = moving
		print("[lift] ", "moving" if moving else "stopped", " at %.2f" % car_y)
