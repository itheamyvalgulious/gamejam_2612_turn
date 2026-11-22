extends RefCounted
class_name BladePath
## 刀位姿过渡规划器 —— 「任意两个刀位姿之间」的过渡。
##
## 一个刀位姿 = 刀柄位置 + 刀身基（局部 Y = 刀轴，局部 Z = 刀面法线）+ 躯干偏航。
## 规划器在这两端之间生成：
##   · 位置：二次贝塞尔曲线，控制点把刀往躯干外侧撑开，
##     所以刀是绕着身体划过去，而不是直线切过胸腔；
##   · 朝向：四元数最短弧插值（slerp）；
##   · 躯干：偏航角同步插值（腰环跟着转，才不会只有手臂在拧）；
##   · 时间：给定总时长，内部 smoothstep 缓动 —— 起步快、到位稳。
##
## rig 每帧把采样结果写进 weapon_root，两条手臂的两骨 IK 再跟到刀柄上 ——
## 所以「刀的路」自动就是「机械臂的路」，不需要单独解关节角。

var active := false
var done := false

var _t := 0.0
var _dur := 0.1
var _from_pos := Vector3.ZERO
var _to_pos := Vector3.ZERO
var _ctl := Vector3.ZERO
var _from_q := Quaternion()
var _to_q := Quaternion()
var _from_yaw := 0.0
var _to_yaw := 0.0


## 规划一条过渡：dur = 总时长（秒），yaw 是躯干偏航（rad）
func plan(from_pos: Vector3, from_basis: Basis, to_pos: Vector3, to_basis: Basis,
		dur: float, from_yaw := 0.0, to_yaw := 0.0) -> void:
	var a := from_basis.orthonormalized()
	var b := to_basis.orthonormalized()
	_from_pos = from_pos
	_to_pos = to_pos
	_from_q = a.get_rotation_quaternion()
	_to_q = b.get_rotation_quaternion()
	if _from_q.dot(_to_q) < 0.0:
		_to_q = Quaternion(-_to_q.x, -_to_q.y, -_to_q.z, -_to_q.w)
	# 控制点：中点再往「外侧」推一点，机械臂会绕开身体
	var mid := (from_pos + to_pos) * 0.5
	var out := Vector3(mid.x, 0.0, mid.z)
	if out.length_squared() < 0.0001:
		out = Vector3(0.0, 0.0, -1.0)
	_ctl = mid - out.normalized() * 0.16
	_ctl.z = minf(_ctl.z, -0.90)          # 与 weapon_root 的胸腔净空约束一致
	_from_yaw = from_yaw
	_to_yaw = to_yaw
	_dur = maxf(dur, 0.001)
	_t = 0.0
	done = false
	active = true


## 推进时间，返回这一帧的刀位姿；空字典 = 当前没有规划（走常规姿势）
func sample(dt: float) -> Dictionary:
	if not active:
		return {}
	_t = minf(_t + dt, _dur)
	var u := _t / _dur
	var e := u * u * (3.0 - 2.0 * u)
	var u2 := 1.0 - e
	var pos := _from_pos * (u2 * u2) + _ctl * (2.0 * u2 * e) + _to_pos * (e * e)
	done = u >= 1.0
	return {
		"pos": pos,
		"basis": Basis(_from_q.slerp(_to_q, e)),
		"yaw": lerpf(_from_yaw, _to_yaw, e),
		"u": u,
		"done": done,
	}


func cancel() -> void:
	active = false
	done = false
	_t = 0.0


func progress() -> float:
	return clampf(_t / maxf(_dur, 0.0001), 0.0, 1.0)
