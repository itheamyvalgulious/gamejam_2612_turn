extends RefCounted
## 主动迎击刀的 3 段运动规划 —— 「放到落点等它来」的反面。
##
## 一条迎击 = 从当前刀位姿挥出、以速度 v = e·speed 横切穿过敌刀上的
## 接触点 P，再收一小段。刀位姿 = 刀柄位置 + 刀身基（局部 Y = 刀轴，
## 局部 Z = 刀面法线）+ 躯干偏航（全部躯干局部系）：
##
##   approach 段：当前位姿 → 打击起点 pre（P - e·back），二次贝塞尔绕行
##     躯干外侧（控制点外撑），smoothstep 缓动；时长 ta。
##   strike 段：pre → post（P + e·through_post），沿迎击方向 e 匀速，
##     接触帧在曲线中点（位置、时间双重命中 P）；姿态保持接触解。
##   recover 段：post → hold（post 再往外走一点后往待机柄位收），避免
##     剑在接触瞬间硬停；与 BladePath 的 plan() 末尾自然收势语义一致。
##
## 采样对外接口与 BladePath 一致：sample(dt) → {pos, basis, yaw, u, done}。
## rig._current_pose 把它写进 weapon_root，双臂 IK 照旧跟随 —— 不改
## mech_rig 动画/IK 基础。

var active := false
var done := false
# 接触时刻（世界）：调试/统计用 —— 计划接触发生时预测的剑世界变换。
var contact_hint := Transform3D.IDENTITY
var contact_time := -1.0        # 接触点在全局时间轴上的时刻（rig.time）
var strike_dir := Vector3.ZERO  # 迎击方向 e（躯干局部）

var _t := 0.0
var _ta := 0.05                  # approach 时长
var _tb := 0.04                  # strike 时长
var _tc := 0.14                  # recover 时长

var _from_pos := Vector3.ZERO
var _ctl := Vector3.ZERO
var _pre_pos := Vector3.ZERO
var _post_pos := Vector3.ZERO
var _hold_pos := Vector3.ZERO
var _from_q := Quaternion()
var _contact_q := Quaternion()
var _from_yaw := 0.0
var _contact_yaw := 0.0
var _a_plan := Vector3.ZERO    # 规划时我方有效刀轴 a（躯干局部 = (contact_basis×spin).y）
var _track_b := Callable()     # 敌刀轴 b（躯干局部）活查询；空=不跟踪
var _spin := Basis()           # weapon_spin 局部基：有效基 = root 基 × _spin
var _spin_inv := Basis()       # 其逆：root 基 = 有效基 × _spin_inv（rotation.y≈2.35 必须补偿）
var _along := 0.0


## 规划一条迎击：
##   from_*    当前刀位姿（躯干局部）
##   contact_* 接触瞬间的目标位姿（刀柄/基/腰环 yaw，躯干局部）
##   dir       迎击方向 e（躯干局部，单位化，刀速沿它）
##   back      strike 段在接触点之前的行程（躯干局部单位）
##   after     strike 段在接触点之后的行程
##   ta/tb/tc  三段时长；tc 之后自然衔接 plan_blade_return（调用方负责）
##   track_b   可选 Callable→Vector3：每帧返回敌刀轴 b 的实际值（躯干局部）。
##             敌刀在挥砍途中继续转，接触帧 a·b 会漂；用它把目标基沿敌刀
##             实时重拼（X=刃向≈e、Y=刀轴 a=b×e、Z≈b），strike 段完全跟踪。
##   spin_local weapon_spin 的局部基（weapon_root 的子节点，自带 ~2.35rad
##             的刃向滚转）：写进 weapon_root 的基必须是 有效基 × spin⁻¹。
func plan(from_pos: Vector3, from_basis: Basis, contact_pos: Vector3,
		contact_basis: Basis, dir: Vector3, back: float, after: float,
		ta: float, tb: float, tc: float, from_yaw: float, contact_yaw: float,
		track_b := Callable(), spin_local := Basis(), along := 0.0) -> void:
	var a := from_basis.orthonormalized()
	var b := contact_basis.orthonormalized()
	_from_q = a.get_rotation_quaternion()
	_contact_q = b.get_rotation_quaternion()
	if _from_q.dot(_contact_q) < 0.0:
		_contact_q = Quaternion(-_contact_q.x, -_contact_q.y, -_contact_q.z, -_contact_q.w)
	_from_pos = from_pos
	strike_dir = dir.normalized()
	_pre_pos = contact_pos - strike_dir * back
	_post_pos = contact_pos + strike_dir * after
	# 收势段：顺势再走一点，让上段和下段的衔接是减速而不是急停
	_hold_pos = _post_pos.lerp(
		Vector3(BASE_W.x, BASE_W.y, BASE_W.z), 0.18)
	# approach 控制点：中点往「外侧+迎击方向」撑，让剑绕开胸廓斜着迎上去
	var mid := (_from_pos + _pre_pos) * 0.5
	var out := Vector3(mid.x, 0.0, mid.z)
	if out.length_squared() < 0.0001:
		out = Vector3(0.0, 0.0, -1.0)
	_ctl = mid + out.normalized() * 0.07 + strike_dir * back * 0.35
	_ctl.z = minf(_ctl.z, -0.28)
	_from_yaw = from_yaw
	_contact_yaw = contact_yaw
	_spin = spin_local
	_spin_inv = spin_local.inverse()
	_a_plan = (b * _spin).y.normalized()
	_along = along
	_track_b = track_b
	_ta = maxf(ta, 0.001)
	_tb = maxf(tb, 0.004)
	_tc = maxf(tc, 0.001)
	_t = 0.0
	done = false
	active = true


# 待机刀柄位（与 campaign_rig.plan_blade_return 同一目标）
const BASE_W := Vector3(0.18, 0.15, -0.40)


## 推进时间，返回这一帧的刀位姿；空字典 = 无规划
func sample(dt: float) -> Dictionary:
	if not active:
		return {}
	var total := _ta + _tb + _tc
	_t = minf(_t + dt, total)
	var pos := _from_pos
	var q := _from_q
	var yaw := _from_yaw
	var u := 0.0
	if _t <= _ta:
		# approach：二次贝塞尔 + smoothstep
		u = _t / _ta
		var e := u * u * (3.0 - 2.0 * u)
		var u2 := 1.0 - e
		pos = _from_pos * (u2 * u2) + _ctl * (2.0 * u2 * e) + _pre_pos * (e * e)
		var k := smoothstep(0.55, 1.0, u)      # 姿态只在尾段贴到接触解
		q = _from_q.slerp(_contact_q, k)
		yaw = lerpf(_from_yaw, _contact_yaw, k)
	elif _t <= _ta + _tb:
		# strike：匀速横切，姿态/腰环保持接触解
		u = (_t - _ta) / _tb
		pos = _pre_pos.lerp(_post_pos, u)
		q = _contact_q
		yaw = _contact_yaw
	else:
		# recover：post → hold 的减速曲线
		u = (_t - _ta - _tb) / _tc
		var e := 1.0 - (1.0 - u) * (1.0 - u)
		pos = _post_pos.lerp(_hold_pos, e)
		var k := smoothstep(0.35, 1.0, u)
		var rest := Basis.from_euler(Vector3(-1.05, 0.0, 0.08))
		var rq := rest.get_rotation_quaternion()
		if q.dot(rq) < 0.0:
			rq = Quaternion(-rq.x, -rq.y, -rq.z, -rq.w)
		q = _contact_q.slerp(rq, k)
		yaw = lerpf(_contact_yaw, _from_yaw, k)
	done = _t >= total
	var basis := Basis(q)
	# 垂直跟踪：敌刀在挥砍途中继续转，接触帧 a·b 会漂 —— 每帧用敌刀轴的
	# 实际值重拼有效目标基（X≈e、Y=a_des=b×e、Z≈b），乘 spin⁻¹ 换回 root
	# 基后 slerp 过去。approach 尾段渐入、strike 段完全贴到。
	# 接触也可能落在 strike 之后（阻挡判定窗口比预测宽），跟踪延伸到
	# recover 前 35% 再逐渐退出；approach 从 35% 处就开始贴目标基。
	if _track_b.is_valid() and _t <= _ta + _tb + _tc * 0.35:
		# 给 tracker 传「距接触剩余秒数」：敌刀轴取预测表 lookahead，
		# lead→0 时落在当前轴 —— 消掉 10-20rad/s 自转的帧滞后残差。
		var b_now: Vector3 = _track_b.call(maxf(_ta + _tb - _t, 0.0))
		if b_now.length_squared() > 0.01:
			b_now = b_now.normalized()
			if b_now.dot((basis * _spin).z) < 0.0:
				b_now = -b_now
			# a_des = b×e；退化（b 与 e 近平行）时用 a_plan 在 b⊥ 平面
			# 的投影兜底 —— 静默放弃会把接触帧刀轴停在非垂直姿态。
			var a_des: Vector3 = b_now.cross(strike_dir)
			if a_des.length_squared() <= 0.01:
				a_des = _a_plan - b_now * _a_plan.dot(b_now)
			if a_des.length_squared() > 0.01:
				a_des = a_des.normalized()
				if a_des.dot(_a_plan) < 0.0:
					a_des = -a_des
				var x_axis := a_des.cross(b_now).normalized()
				var eff := Basis(x_axis, a_des, b_now)
				var target: Basis = eff * _spin_inv
				var w := 1.0
				if _t <= _ta:
					w = smoothstep(0.35, 1.0, _t / _ta)
				elif _t > _ta + _tb:
					w = 1.0 - smoothstep(0.0, 0.35, (_t - _ta - _tb) / _tc)
				var q2 := basis.get_rotation_quaternion().slerp(
					target.get_rotation_quaternion(), w)
				basis = Basis(q2)
				if _along > 0.01:
					var eff_a: Vector3 = (basis * _spin).y.normalized()
					var p_cur := pos + _a_plan * _along
					pos = p_cur - eff_a * _along
					pos.z = minf(pos.z, -0.25)
	return {"pos": pos, "basis": basis, "yaw": yaw, "u": u, "done": done,
		"phase": (0 if _t <= _ta else (1 if _t <= _ta + _tb else 2))}


func cancel() -> void:
	active = false
	done = false
	_t = 0.0


func progress() -> float:
	return clampf(_t / maxf(_ta + _tb + _tc, 0.0001), 0.0, 1.0)


## 当前段：0 approach / 1 strike / 2 recover（parry_contact 归因用）
func phase() -> int:
	return (0 if _t <= _ta else (1 if _t <= _ta + _tb else 2))
