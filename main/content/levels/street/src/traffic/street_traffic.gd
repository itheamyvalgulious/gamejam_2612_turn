extends Node3D
## 街道 P1 车流：4 条车道，每条 3 组、每组 3 辆，沿 X 循环。
## 车辆不碰撞玩家；只负责「看得见的过街空档」。
## 循环 176 m、组间隔 58.7 m、组内 10 m，空档约 (58.7 − 20) / 9 ≈ 4.3 s。
## 单位：几何一律世界单位（1 u = 0.547 m）。

const M := 1.8281536
const SPAN := 176.0 * M
const HALF_SPAN := 88.0 * M
const CAR_LEN := 4.35 * M
const CAR_W := 1.86 * M
const GROUP_PHASE := 58.7 * M
const CAR_GAP := 10.0 * M

var cars: Array = []
var _body_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D
var _tire_mat: StandardMaterial3D
var _body: BoxMesh
var _cabin: BoxMesh
var _glass: BoxMesh
var _lamp: BoxMesh
var _tire: CylinderMesh


func build(lanes: Array) -> void:
	_make_materials()
	for li in lanes.size():
		var lane: Dictionary = lanes[li]
		var z: float = float(lane["z"])
		var dir: float = float(lane["dir"])
		var speed: float = float(lane["speed"])
		# 每条车道错开相位，避免四条车道的车并排成排
		var shift: float = float(li) * 14.7 * M
		for group in 3:
			for i in 3:
				var x: float = -HALF_SPAN + shift + float(group) * GROUP_PHASE \
					+ float(i) * CAR_GAP
				x = fposmod(x + HALF_SPAN, SPAN) - HALF_SPAN
				_spawn(x, z, dir, speed)


func step(dt: float) -> void:
	for entry in cars:
		var node: Node3D = entry["node"]
		node.position.x += float(entry["dir"]) * float(entry["speed"]) * dt
		if node.position.x > HALF_SPAN:
			node.position.x -= SPAN
		elif node.position.x < -HALF_SPAN:
			node.position.x += SPAN


func car_positions() -> Array:
	var out: Array = []
	for entry in cars:
		out.append(entry["node"].position)
	return out


# ---------------------------------------------------------------- internals
func _spawn(x: float, z: float, dir: float, speed: float) -> void:
	var node := Node3D.new()
	node.name = "Car"
	node.position = Vector3(x, 0.0, z)
	node.rotation.y = 0.0 if dir > 0.0 else PI
	add_child(node)
	_add_box(node, _body, _body_mat, Vector3(0.0, 0.62 * M, 0.0))
	_add_box(node, _cabin, _body_mat, Vector3(-0.25 * M, 1.18 * M, 0.0))
	_add_box(node, _glass, _glass_mat, Vector3(-0.25 * M, 1.24 * M, 0.0))
	for side in [-1.0, 1.0]:
		_add_box(node, _lamp, _head_mat,
			Vector3(CAR_LEN * 0.5 - 0.02 * M, 0.72 * M, side * 0.62 * M))
		_add_box(node, _lamp, _tail_mat,
			Vector3(-CAR_LEN * 0.5 + 0.02 * M, 0.72 * M, side * 0.62 * M))
		for front in [-1.0, 1.0]:
			_add_box(node, _tire, _tire_mat,
				Vector3(front * 1.42 * M, 0.34 * M, side * (CAR_W * 0.5 - 0.06 * M)),
				Vector3(PI * 0.5, 0.0, 0.0))
	cars.append({"node": node, "dir": dir, "speed": speed})


func _add_box(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)


func _make_materials() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color("39424f")
	_body_mat.metallic = 0.35
	_body_mat.roughness = 0.48

	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color("0b1118")
	_glass_mat.metallic = 0.7
	_glass_mat.roughness = 0.12

	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color("dff1ff")
	_head_mat.emission_enabled = true
	_head_mat.emission = Color("dff1ff")
	_head_mat.emission_energy_multiplier = 4.5

	_tail_mat = StandardMaterial3D.new()
	_tail_mat.albedo_color = Color("ff4a3a")
	_tail_mat.emission_enabled = true
	_tail_mat.emission = Color("ff3a2a")
	_tail_mat.emission_energy_multiplier = 3.2

	_tire_mat = StandardMaterial3D.new()
	_tire_mat.albedo_color = Color("14161a")
	_tire_mat.roughness = 0.9

	_body = BoxMesh.new()
	_body.size = Vector3(CAR_LEN, 0.66 * M, CAR_W)

	_cabin = BoxMesh.new()
	_cabin.size = Vector3(2.3 * M, 0.62 * M, CAR_W - 0.16 * M)

	_glass = BoxMesh.new()
	_glass.size = Vector3(2.34 * M, 0.5 * M, CAR_W - 0.1 * M)

	_lamp = BoxMesh.new()
	_lamp.size = Vector3(0.1 * M, 0.18 * M, 0.36 * M)

	_tire = CylinderMesh.new()
	_tire.top_radius = 0.34 * M
	_tire.bottom_radius = 0.34 * M
	_tire.height = 0.24 * M
	# 轮子轴向沿 Z：CylinderMesh 默认沿 Y，实例上绕 X 转 90°
	_tire.radial_segments = 12
	_tire.rings = 1
