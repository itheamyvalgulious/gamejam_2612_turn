extends Node3D
## 仓库单向透视：相机在墙外时隐藏靠近相机的墙；在屋顶上方时隐藏屋顶。
## 相机在室内/屋顶下方时，外壳正常显示。

var shell: Node3D
var half_x := 1.0
var half_z := 1.0
var height := 1.0
var _parts := {}


func setup(p_shell: Node3D, p_half_x: float, p_half_z: float, p_height: float) -> void:
	shell = p_shell
	half_x = p_half_x
	half_z = p_half_z
	height = p_height


func _process(_delta: float) -> void:
	if shell == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := to_local(cam.global_position)
	var inside := absf(p.x) < half_x and absf(p.z) < half_z

	_vis("North", p.z >= -half_z)
	_vis("South", p.z <= half_z)
	_vis("West", p.x >= -half_x)
	_vis("East", p.x <= half_x)
	_vis("Roof", inside and p.y < height * 0.98)


func _vis(part: String, on: bool) -> void:
	if not _parts.has(part):
		_parts[part] = shell.get_node_or_null(part)
	var n: Node3D = _parts[part]
	if n != null and n.visible != on:
		n.visible = on
