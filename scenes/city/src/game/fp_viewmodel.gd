extends Node3D
class_name FpViewmodel
## 第一人称手持武器（独立于世界模型的一把"缩小版"刀 + 两段前臂）。
##
## 为什么单独做：世界里的刀是 4.2 m 长、0.55 m 宽的四足机甲武器，
## 直接塞进第一人称画面又大又爆白，完全不像"手持"。
## 这里按第一人称惯例建一把 0.9 m 的等比缩小刀，挂到相机下，
## 姿态由玩家的攻击相位驱动（左右横斩 / 后刺 / 弹反指向都能对上）。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const MK = preload("res://src/vesper/mesh_kit.gd")
const PAL = preload("res://src/vesper/material_palette.gd")

var hand: Node3D          # 握把组（绕相机 Y 扫）
var blade: Node3D         # 刀身（在手里做俯仰）
var arms_root: Node3D
var _mats
var _ready_done := false
var _sway := 0.0
var _last_pos := Vector3.ZERO
var _swing_prev := 0.0


func setup(palette: Dictionary) -> void:
	if _ready_done:
		return
	_ready_done = true
	_mats = PAL.for_palette(palette)
	arms_root = Node3D.new()
	add_child(arms_root)
	hand = Node3D.new()
	add_child(hand)
	blade = Node3D.new()
	hand.add_child(blade)

	# ---- 刀：柄 + 护手 + 刀身（0.9 m 级）
	var m = _mats
	MK.add(blade, MK.prism(8, 0.022, 0.024, 0.30, PI / 8.0), m.rubber(), Vector3(0, -0.10, 0))
	MK.add(blade, MK.prism(12, 0.028, 0.028, 0.010, 0), m.emissive(Color(1.0, 0.30, 0.06), 2.2), Vector3(0, -0.02, 0))
	MK.add(blade, MK.slab(0.10, 0.05, 0.016, 0.004), m.frame_light(), Vector3(0, 0.04, 0))
	MK.add(blade, MK.blade(0.62, 0.056, 0.014, 0.0, 16), m.blade_core(), Vector3(0, 0.06, 0))
	MK.add(blade, MK.blade(0.58, 0.078, 0.020, 0.0, 12), m.blade_glow(), Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(1.2, 1.0, 1.2))

	# ---- 两段前臂（从画面右下伸进来握住刀柄）
	for side in [1.0, -1.0]:
		var arm := MK.add(arms_root, MK.beam_x(0.42, 0.075, 0.075, 0.055, 0.055), m.armor(),
			Vector3(0.30 * side - 0.06, -0.30, 0.06 * side), Vector3(0, -62.0 * side, -8.0 * side))
		MK.add(arms_root, MK.beam_x(0.30, 0.055, 0.055, 0.045, 0.045), m.frame(),
			Vector3(0.12 * side, -0.16, 0.02 * side), Vector3(0, -80.0 * side, -22.0 * side))

	scale = Vector3(0.82, 0.82, 0.82)
	position = Vector3(0.34, -0.28, -0.48)
	rotation = Vector3(0.04, 0.14, 0.03)
	blade.rotation = Vector3(-0.78, 0.0, -0.12)


func update(dt: float, player) -> void:
	if not _ready_done or player == null:
		return
	var rig = player.rig
	var t := 1.0 - exp(-12.0 * dt)
	var want_pos := Vector3(0.34, -0.28, -0.48)
	var want_rot := Vector3(0.04, 0.14, 0.03)
	var want_blade := Vector3(-0.78, 0.0, -0.12)

	if rig.is_attacking and rig.proc_active:
		var w0: float = rig.attack_hit_from
		var span: float = maxf(rig.attack_hit_to - rig.attack_hit_from, 0.02)
		var u: float = clampf((rig.attack_elapsed - w0) / span, 0.0, 1.0)
		var wind: float = clampf(rig.attack_elapsed / maxf(w0, 0.02), 0.0, 1.0)
		var ease: float = u * u * (3.0 - 2.0 * u)
		# 前摇：手往反方向抬一点
		var wind_off: float = (1.0 - wind) * -0.55 * signf(rig.proc_a1 - rig.proc_a0)
		var ang: float = lerpf(rig.proc_a0, rig.proc_a1, ease) + wind_off
		# 把"角色空间的方位角"映射到相机空间：+ 是左
		want_rot = Vector3(0.04 - 0.28 * sin(PI * u), ang, 0.03 + 0.22 * sin(PI * u))
		want_pos = Vector3(0.34 - 0.16 * clampf(ang, -1.2, 1.2), -0.28 + 0.05 * sin(PI * u),
			-0.48 - 0.18 * sin(PI * u))
		want_blade = Vector3(-0.78 - 0.30 * sin(PI * u), 0.0, -0.12)
	elif rig.blade_path_active():
		# 架刀：把刀端到镜头正前方（格挡/弹反），刀尖略微抬起
		want_rot = Vector3(-0.10, 0.02, 0.06)
		want_pos = Vector3(0.24, -0.20, -0.54)
		want_blade = Vector3(-0.62, 0.0, -0.16)

	position = position.lerp(want_pos, t)
	rotation = rotation.lerp(want_rot, t)
	blade.rotation = blade.rotation.lerp(want_blade, t)

	# 走路摆动
	var p: Vector3 = player.rig.global_position
	var vel := (p - _last_pos) / maxf(dt, 1e-4)
	_last_pos = p
	var sp: float = clampf(vel.length() / 12.0, 0.0, 1.0)
	_sway += dt * 6.0
	position += Vector3(sin(_sway) * 0.012, -absf(sin(_sway)) * 0.010, 0.0) * sp
