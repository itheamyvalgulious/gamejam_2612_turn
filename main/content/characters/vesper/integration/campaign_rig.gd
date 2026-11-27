extends "res://scripts/mech/mech_rig.gd"
## Applies the campaign's timings and collision rules to the shared VESPER rig.

const BladePath = preload("res://integration/blade_path.gd")
const SwingPath = preload("res://integration/swing_path.gd")
const CLIPS := {
	"slash_fwd": "FRONT_R",
	"slash_left": "SIDE_THRUST_L",
	"slash_right": "SIDE_THRUST_R",
	"slash_back": "BACK_THRUST",
	"heavy": "HEAVY",
	"spin": "SPIN",
	"plunge": "HEAVY",
}

var arena_bounds := Vector2.ZERO
var follow_platform_height := false
var guard := 0.0
var attack_elapsed := 0.0
var attack_hit_from := 0.0
var attack_hit_to := 0.0
var weapon_xf := Transform3D.IDENTITY
var last_intercept_miss := 0.0
var weapon_prev_xf := Transform3D.IDENTITY
var weapon_scale := 1.0
var blade_discs: Array = []        # 仅调试可视化（replay 画剖面），命中判定走 blade_proxy
var blade_proxy: BladeProxy        # 少顶点凸体近似（GJK 最短距离），命中/格挡的唯一几何
var terrain_blade_enabled := false

var _timings: Dictionary = {}
var _attack_total := 0.0
var _lunge_distance := 0.0
var _authored_lunge := 0.0
var _authored_strike := Vector2.ZERO
var _blade_path := BladePath.new()
var _swing_path := SwingPath.new()
var _first_person := false
var _shoulder_rest: Array[Vector3] = []


func _ready() -> void:
	super._ready()
	for arm in arms:
		_shoulder_rest.append(arm["shoulder"].position)
	blade_discs = _measure_blade()
	blade_proxy = _build_blade_proxy()
	_record_blade()
	weapon_prev_xf = weapon_xf
	for clip_n in ["FRONT_R", "FRONT_L", "RISE_R", "RISE_L"]:
		_ensure_front_clip_samples(clip_n)


func advance(dt: float) -> void:
	if terrain_blade_enabled:
		for i in arms.size():
			arms[i]["shoulder"].position = _shoulder_rest[i]
	super.advance(dt)
	_record_blade()


func apply_terrain_blade(pose: Transform3D, recoil: Vector3) -> void:
	if not recoil.is_zero_approx():
		var away := body.global_basis.orthonormalized().inverse() * recoil
		torso.rotate(Vector3.UP, -away.x * 0.17)
		torso.rotate(Vector3.RIGHT, away.z * 0.13)
	weapon_root.global_transform = pose * weapon_spin.transform.affine_inverse()
	for i in arms.size():
		var arm: Dictionary = arms[i]
		var grip := GRIP if i == 1 else -GRIP
		var reach := weapon_root.transform * (Vector3.UP * grip) - _shoulder_rest[i]
		var distance := reach.length()
		var extended := maxf(distance - float(arm["upper"]) - float(arm["fore"]) + 0.006, 0.0)
		var tucked := minf(distance - 0.115, 0.0)
		arm["shoulder"].position = _shoulder_rest[i] + reach.normalized() * clampf(extended + tucked, -0.085, 0.105)
	_update_arms(_smooth_pose)
	weapon_xf = weapon_spin.global_transform


func stop_terrain_swing() -> void:
	_finish_attack()


func _update_trail(dt: float) -> void:
	if not terrain_blade_enabled:
		super._update_trail(dt)


func update_terrain_trail(dt: float, blocked: bool) -> void:
	if blocked:
		blade_trail.tick(dt, false)
	else:
		super._update_trail(dt)


func _record_blade() -> void:
	weapon_prev_xf = weapon_xf
	weapon_xf = weapon_spin.global_transform
	weapon_scale = weapon_xf.basis.get_scale().x


func _constrain_horizontal() -> void:
	if arena_bounds.x > 0.1 and arena_bounds.y > 0.1:
		position.x = clampf(position.x, -arena_bounds.x, arena_bounds.x)
		position.z = clampf(position.z, -arena_bounds.y, arena_bounds.y)


func _advance_jump(dt: float) -> void:
	# Lab rooms support falling off a platform. Galleria and City resolve stairs in the level.
	if follow_platform_height and jump_state == "GROUND":
		if position.y > ground_height + 0.02:
			jump_state = "AIR"
			vertical_velocity = 0.0
			air_time = 0.0
		elif position.y < ground_height:
			position.y = ground_height
	super._advance_jump(dt)


func set_timings(timings: Dictionary) -> void:
	_timings = timings


func play_action(action: String, lunge: float) -> void:
	clear_blade_path()
	_attack_queue.clear()
	var clip := _clip(CLIPS[action])
	_play_clip(action, clip, lunge)


## 按敌人位置细分出的具体 clip 直出（前向 4 选 1）。
func play_action_clip(action: String, clip_name: String, lunge: float) -> void:
	clear_blade_path()
	_attack_queue.clear()
	_play_clip(action, _clip(clip_name), lunge)


func _play_clip(action: String, clip: Dictionary, lunge: float) -> void:
	var timing: Dictionary = _timings.get("heavy" if action == "plunge" else action, {})
	var trail: Array = clip["trail"]
	var duration: float = clip["duration"]
	_authored_strike = Vector2(float(trail[0]), float(trail[1]))
	attack_hit_from = float(timing.get("windup", _authored_strike.x / ATTACK_RATE))
	attack_hit_to = attack_hit_from + maxf(0.02, float(timing.get("active", (_authored_strike.y - _authored_strike.x) / ATTACK_RATE)))
	_attack_total = maxf(attack_hit_to + 0.01, float(timing.get("duration", duration / ATTACK_RATE)))
	attack_elapsed = 0.0
	_lunge_distance = lunge
	_authored_lunge = _eval_curve(clip.get("lunge", []), duration)
	_begin_attack(clip, action in ["heavy", "spin", "plunge"])


func _advance_attack(dt: float) -> void:
	if not is_attacking:
		return
	attack_elapsed = minf(attack_elapsed + dt, _attack_total)
	attack_time = _clip_time(attack_elapsed)
	if attack_elapsed >= _attack_total:
		# Apply the last increment so a completion frame cannot drop root motion.
		position += -global_basis.z.normalized() * (_lunge_at(attack_time) - _lunge_prev)
		_finish_attack()


func _clip_time(elapsed: float) -> float:
	if elapsed < attack_hit_from:
		return lerpf(0.0, _authored_strike.x, elapsed / maxf(attack_hit_from, 0.001))
	if elapsed < attack_hit_to:
		var progress := inverse_lerp(attack_hit_from, attack_hit_to, elapsed)
		return lerpf(_authored_strike.x, _authored_strike.y, progress)
	var recovery := clampf(inverse_lerp(attack_hit_to, _attack_total, elapsed), 0.0, 1.0)
	return lerpf(_authored_strike.y, float(_attack["duration"]), recovery)


func _lunge_at(t: float) -> float:
	if absf(_authored_lunge) > 0.001:
		return super._lunge_at(t) * _lunge_distance / absf(_authored_lunge)
	if t <= _authored_strike.x:
		return 0.0
	return smoothstep(_authored_strike.x, _authored_strike.y, t) * _lunge_distance


func in_hit_window() -> bool:
	return is_attacking and attack_elapsed >= attack_hit_from and attack_elapsed <= attack_hit_to


## 挥剑中强制停下立正（Q/E 用）：立刻收刀回待机姿态。
func cancel_attack() -> void:
	if not is_attacking:
		return
	attack_elapsed = _attack_total
	attack_time = float(_attack.get("duration", 0.0))
	_finish_attack()
	plan_blade_return(0.14)


static var _front_clip_cache := {}


func _ensure_front_clip_samples(n: String) -> Array:
	if _front_clip_cache.has(n):
		return _front_clip_cache[n]
	var saved := _attack
	var clip := _clip(n)
	_attack = clip
	var trail: Array = clip.get("trail", [0.0, 1.0])
	var authored := _eval_curve(clip.get("lunge", []), float(clip.get("duration", 1.0)))
	var samples: Array = []
	for i in 15:
		var t: float = lerpf(float(trail[0]), float(trail[1]), float(i) / 14.0)
		var pose := _evaluate_keys(t)
		var wr := Transform3D(
			Basis.from_euler(Vector3(float(pose["wrx"]), float(pose["wry"]), float(pose["wrz"]))),
			Vector3(float(pose["wpx"]), float(pose["wpy"]), float(pose["wpz"])))
		var lunged := _eval_curve(clip.get("lunge", []), t)
		samples.append({
			"t": t,
			"wr": wr,
			"lunge_scale": (lunged / absf(authored)) if absf(authored) > 0.001 else 0.0,
			"lunge_raw": lunged,
		})
	_attack = saved
	_front_clip_cache[n] = samples
	return samples


## 「哪个前向挥砍能打到 target」：对 4 个 FRONT/RISE clip 离线采样刀尖
## 轨迹（trail 窗内），选离目标最近、且最早覆盖到目标的 clip。
## 返回 CLIPS 字典里的 clip 名（"FRONT_R"/"FRONT_L"/"RISE_R"/"RISE_L"）。
func pick_front_clip(target: Vector3, lunge: float, reach := 0.62) -> String:
	var names := ["FRONT_R", "FRONT_L", "RISE_R", "RISE_L"]
	var torso_xf := _torso_transform(torso.rotation)
	var spin_xf := weapon_spin.transform if weapon_spin != null else Transform3D.IDENTITY
	var fwd := -global_basis.z.normalized()
	var best: String = names[0]
	var best_score := 1e9
	for n in names:
		var samples := _ensure_front_clip_samples(n)
		var min_d := 1e9
		var reach_t := 1e9
		for s: Dictionary in samples:
			var t: float = float(s["t"])
			var wr: Transform3D = s["wr"]
			var wx: Transform3D = torso_xf * wr * spin_xf
			var ls: float = float(s["lunge_scale"])
			var lunged: float = ls * lunge if ls != 0.0 else float(s["lunge_raw"])
			var tip: Vector3 = (wx * Vector3(0.0, BLADE_Y0 + BLADE_LEN, 0.0)) + fwd * lunged
			var base: Vector3 = (wx * Vector3(0.0, BLADE_Y0, 0.0)) + fwd * lunged
			# 刀是线段不是点：横扫/上撩的刀尖都远，但刀身会扫过目标所在高度。
			var d := Geometry3D.get_closest_point_to_segment(
				target, base, tip).distance_to(target)
			if d < min_d:
				min_d = d
			if d <= reach and reach_t > 1e8:
				reach_t = t
		# 主排序：贴多近（横扫贴胸口 > 上撩贴头）；reach_t 只作同档的平局权重。
		var score := min_d * 10.0 + (reach_t if reach_t < 1e8 else 100.0)
		if score < best_score:
			best_score = score
			best = n
	return best


func blade_span() -> Vector2:
	return Vector2(BLADE_Y0, BLADE_Y0 + BLADE_LEN)


func combat_capsule() -> Dictionary:
	# ⚠ 仅作相机/粗筛用的保守包围胶囊——伤害判定与格挡规划一律走 hit_parts()
	# （多圆柱体，完全包含机身顶点）。禁止把本胶囊用于 damage / blocking。
	# These dimensions are in level units. The model's metre conversion must not rescale them.
	# 胶囊顶对齐机体身高：body_aabb 实测 0→3.74u，b+r 给到 3.8 包住头顶为止；
	# 之前 b=4.4（命中面到 5.5）会让明显高过头顶的横斩也判命中。
	return {
		"a": global_position + Vector3.UP,
		"b": global_position + Vector3.UP * 2.7,
		"r": 1.1,
		"scale": 1.0,
	}


func plan_blade_intercept(point: Vector3, axis: Vector3, face: Vector3,
		torso_turn: float, deadline: float, speed := 26.0) -> Dictionary:
	var res := _solve_intercept(point, axis, face, torso_turn)
	if res.is_empty():
		return {}
	var hilt: Vector3 = res["hilt"]
	var yaw: float = res["yaw"]
	var travel: float = weapon_root.position.distance_to(hilt) * float(res["torso_scale"])
	var duration := clampf(travel / maxf(speed, 1.0), 0.015, maxf(deadline, 0.015))
	last_intercept_miss = res["miss"]
	_swing_path.cancel()
	_blade_path.plan(weapon_root.position, weapon_root.basis, hilt, res["basis"], duration,
		torso.rotation.y, yaw)
	return {"hilt": hilt, "yaw": yaw, "t": res["t"], "dur": duration, "travel": travel,
		"miss": res["miss"]}


## 主动迎击：contact 是 active_parry 里已过筛选的接触位姿（躯干局部
## hilt/basis/yaw），e_world 是迎击方向（世界单位向量，刀速沿它），
## contact_in = 距接触还有多久（秒，世界时钟）。
##
## 运动曲线：approach（贝塞尔绕身体到打击起点）→ strike（沿 e 匀速横切，
## 接触帧正好在 pre/post 中点）→ recover（顺势收尾）。
## 速度/行程都在躯干局部系计算 —— weapon_root 的坐标系；世界系量先除
## 躯干世界缩放再进来。
func plan_strike(contact: Dictionary, e_world: Vector3, contact_in: float,
		back_world := 0.26, after_world := 0.34, track_src = null) -> Dictionary:
	var yaw: float = contact["yaw"]
	var target_torso := _torso_transform(
		Vector3(torso.rotation.x, yaw, torso.rotation.z))
	var torso_scale_w: float = target_torso.basis.get_scale().x
	if torso_scale_w < 0.001:
		return {}
	var e_local := (target_torso.affine_inverse().basis * e_world)
	if e_local.length_squared() < 0.0001:
		return {}
	e_local = e_local.normalized()
	var scale_r := 1.0 / torso_scale_w
	var back := back_world * scale_r
	var after := after_world * scale_r
	# strike 段：pre → P → post 匀速；提前 0.045s 进刀，保证迎击窗包住接触时刻
	var approach_d := clampf(contact_in - 0.045, 0.008, 0.14)
	var strike_d := maxf((back + after) * torso_scale_w / maxf(_strike_speed, 1.0), 0.085)
	var recover_d := 0.13
	last_intercept_miss = contact["miss"]
	# 垂直跟踪：返回敌刀轴 b，按「距接触剩余 lead 秒」向前引 —
	# 敌刀 10-20rad/s 时 1-2 帧滞后就 0.3-1.0 的 a·b 残差；预测表在
	# lead≤0.12s 内就是动画本身。lead→0 时退化成当前轴。
	var tracker := Callable()
	if track_src != null and track_src.has_method("predict_weapon_xf"):
		# 混合：活轴（weapon_spin 每帧真值）+ 角速度外推一拍。
		# 纯预测表 lead 与纯活轴都已验证有 0.3-0.9 残差（预测表只存
		# 采样位姿、敌刀动画与表会漂；活轴则滞后一拍）。
		var _tk := {"prev": Vector3.ZERO, "prev_t": -1.0}
		tracker = func(lead: float) -> Vector3:
			var bw := Vector3.ZERO
			var live_spin = track_src.get("weapon_spin")
			if live_spin != null and is_instance_valid(live_spin):
				bw = (live_spin.global_transform.basis * Vector3(0, 1, 0)).normalized()
			else:
				var live_xf = track_src.get("_blade_now")
				if live_xf is Transform3D \
						and not live_xf.is_equal_approx(Transform3D.IDENTITY):
					bw = (live_xf.basis * Vector3(0, 1, 0)).normalized()
				elif track_src.get("weapon_xf") is Transform3D:
					bw = (track_src.get("weapon_xf").basis * Vector3(0, 1, 0)).normalized()
			if bw.length_squared() < 0.01:
				var e_t = track_src.get("attack_elapsed")
				if e_t == null:
					return Vector3.ZERO
				bw = (track_src.predict_weapon_xf(float(e_t)).basis
					* Vector3(0, 1, 0)).normalized()
			# 外推一拍：敌刀 _process 在我之后跑时，读到的是上帧轴，滞后恒为
			# 一帧敌刀角位移（27fps×20rad/s≈0.7rad，正是观测残差量级）。
			# 用实测轴差分补一整步；翻号/突变 >0.6 不外推（存原始值防累积）。
			var now_t := Time.get_ticks_msec() / 1000.0
			var prev: Vector3 = _tk["prev"]
			var prev_t: float = float(_tk["prev_t"])
			_tk["prev"] = bw
			_tk["prev_t"] = now_t
			if prev.length_squared() > 0.01 and now_t - prev_t < 0.1:
				var d: Vector3 = bw - prev
				if d.length() < 0.6:
					bw = (bw + d).normalized()
			return (_torso_transform(torso.rotation).affine_inverse().basis * bw).normalized()
	_blade_path.cancel()
	_swing_path.plan(weapon_root.position, weapon_root.basis,
		contact["hilt"], contact["basis"], e_local, back, after,
		approach_d, strike_d, recover_d, torso.rotation.y, yaw, tracker,
		weapon_spin.basis, float(contact.get("along", 0.0)))
	return {"dur": approach_d + strike_d + recover_d, "contact_in": contact_in,
		"strike_d": strike_d, "approach_d": approach_d}


# 迎击刀速（世界 u/s）：由 player 从 P.getf("parry.plan_speed") 写入
var _strike_speed := 26.0


func set_strike_speed(v: float) -> void:
	_strike_speed = maxf(v, 1.0)


## 旧「架住等它来」的可达性/位姿求解对外接口（active_parry 复用同一套
## 求解器：a ⟂ b、e ⟂ a 的接触基在调用方已经拼好，传 face=敌刀轴 b 即可）。
func solve_intercept_debug(point: Vector3, axis: Vector3, face: Vector3,
		torso_turn: float, u_lock := -1.0) -> Dictionary:
	var res := _solve_intercept(point, axis, face, torso_turn, u_lock)
	if res.is_empty():
		return {}
	res["along"] = float(res["t"]) * weapon_root.scale.y
	return res


## 落点可达性探针：返回「按这套落点+刀轴规划后，刀身到落点的剩余距离」。
## > 0 说明点在机械臂可达域外，调用方应在敌刀路径上换可达拦截点。
func blade_reach_miss(point: Vector3, axis: Vector3, face: Vector3, torso_turn: float) -> float:
	var res := _solve_intercept(point, axis, face, torso_turn)
	if res.is_empty():
		return 1e9
	return float(res["miss"])


## 规划完成后我方刀的 weapon_spin 世界变换（凸体代理的判定位姿）。
func intercept_blade_xf(point: Vector3, axis: Vector3, face: Vector3,
		torso_turn: float) -> Dictionary:
	var res := _solve_intercept(point, axis, face, torso_turn)
	if res.is_empty():
		return {}
	var target_torso := _torso_transform(
		Vector3(torso.rotation.x, res["yaw"], torso.rotation.z))
	var wx: Transform3D = target_torso \
		* Transform3D(res["basis"], res["hilt"]) * weapon_spin.transform
	return {"xf": wx}


## 规划完成后我方刀身在世界里的线段端点 [p0, p1]。
## 用于直接度量「架好这把刀之后，敌刀扫过来时两把刀的真实间隙」。
func intercept_blade_segment(point: Vector3, axis: Vector3, face: Vector3,
		torso_turn: float) -> Array:
	var res := intercept_blade_xf(point, axis, face, torso_turn)
	if res.is_empty():
		return []
	var wx: Transform3D = res["xf"]
	var span := blade_span()
	return [wx * Vector3(0.0, span.x, 0.0), wx * Vector3(0.0, span.y, 0.0)]


## 纯几何求解：挑刀轴正/反两种握法里「刀身最贴近落点」的一种。
## 返回 hilt(躯干局部) / basis(weapon_root 局部基) / yaw / t / miss / torso_scale。
func _solve_intercept(point: Vector3, axis: Vector3, face: Vector3,
		torso_turn: float, u_lock := -1.0) -> Dictionary:
	if axis.length_squared() < 0.000001:
		return {}
	var from_body := body.to_local(point)
	var yaw := clampf(atan2(-from_body.x, -from_body.z) * clampf(torso_turn, 0.0, 1.0), -2.8, 2.8)
	var target_torso := _torso_transform(Vector3(torso.rotation.x, yaw, torso.rotation.z))
	var to_torso := target_torso.affine_inverse()
	var point_local := to_torso * point
	var up := (to_torso.basis * axis).normalized()
	var rest := Vector3(BASE_POSE["wpx"], BASE_POSE["wpy"], BASE_POSE["wpz"])
	var hilt_scale := weapon_root.scale.y
	var span := blade_span() * hilt_scale
	var best_score := INF
	var hilt := rest
	var root_basis := weapon_root.basis.orthonormalized()
	var blade_point := 0.0
	var best_miss := 1e9
	for side in [1.0, -1.0]:
		var blade_axis: Vector3 = up * side
		var normal := (to_torso.basis * face).slide(blade_axis)
		if normal.length_squared() < 0.0001:
			normal = Vector3.UP.cross(blade_axis)
		if normal.length_squared() < 0.0001:
			normal = Vector3.RIGHT
		normal = normal.normalized()
		var blade_basis := Basis(blade_axis.cross(normal).normalized(), blade_axis, normal)
		var basis := blade_basis * weapon_spin.basis.inverse()
		var along := clampf((point_local - rest).dot(blade_axis), span.x, span.y)
		if u_lock >= 0.0:
			along = u_lock
		var candidate := _reachable_hilt(point_local - blade_axis * along, blade_axis)
		# 钳位后的刀柄不一定回到 rest：覆盖点要按真实 hilt 重算，否则把可达
		# 域边界上的落点误判成「还差一整条刀身」。
		var along2 := clampf((point_local - candidate).dot(blade_axis), span.x, span.y)
		if u_lock >= 0.0:
			along2 = u_lock
		var miss := (candidate + blade_axis * along2).distance_to(point_local)
		var score := miss * 3.0 + candidate.distance_to(rest) + 0.45 * candidate.distance_to(weapon_root.position)
		if score < best_score:
			best_score = score
			hilt = candidate
			root_basis = basis
			blade_point = along2 / hilt_scale
			best_miss = miss
	return {"hilt": hilt, "yaw": yaw, "basis": root_basis, "t": blade_point,
		"miss": best_miss, "torso_scale": target_torso.basis.get_scale().x}


func _reachable_hilt(hilt: Vector3, axis: Vector3) -> Vector3:
	hilt.z = minf(hilt.z, -0.30)
	for pass_index in 3:
		for index in arms.size():
			var arm: Dictionary = arms[index]
			var shoulder: Vector3 = arm["shoulder"].position
			var grip := axis * GRIP * (1.0 if index == 1 else -1.0)
			var limit: float = float(arm["upper"]) + float(arm["fore"]) - 0.026
			hilt = shoulder + (hilt + grip - shoulder).limit_length(limit) - grip
	return hilt


func _torso_transform(angles: Vector3) -> Transform3D:
	var basis := Basis.from_euler(angles).scaled(torso.scale)
	return body.global_transform * Transform3D(basis, torso.position)


func plan_blade_return(duration: float) -> void:
	var rest := Vector3(BASE_POSE["wpx"], BASE_POSE["wpy"], BASE_POSE["wpz"])
	var basis := Basis.from_euler(Vector3(BASE_POSE["wrx"], BASE_POSE["wry"], BASE_POSE["wrz"]))
	_swing_path.cancel()
	_blade_path.plan(weapon_root.position, weapon_root.basis, rest, basis, duration, torso.rotation.y, 0.0)


func clear_blade_path() -> void:
	_blade_path.cancel()
	_swing_path.cancel()


func blade_path_active() -> bool:
	return _blade_path.active or _swing_path.active


## 迎击挥砍进行中（approach/strike 段在飞）。玩家侧用它放宽重规划阈值：
## 挥到一半的刀不要因威胁点小漂移就撤掉重挥。
func strike_active() -> bool:
	return _swing_path.active


func strike_in_approach() -> bool:
	return _swing_path.active and _swing_path.phase() == 0


func strike_in_recover() -> bool:
	return _swing_path.active and _swing_path.phase() == 2


func _current_pose(dt: float) -> Dictionary:
	var pose := super._current_pose(dt)
	if is_attacking or not (_blade_path.active or _swing_path.active or guard > 0.0):
		return pose
	pose = pose.duplicate()
	if _swing_path.active:
		var step := _swing_path.sample(dt)
		var hilt: Vector3 = step["pos"]
		var basis: Basis = step["basis"]
		var angles := basis.get_euler()
		pose.merge({
			"wpx": hilt.x, "wpy": hilt.y, "wpz": hilt.z, "ty": float(step["yaw"]),
			"wrx": angles.x, "wry": angles.y, "wrz": angles.z,
		}, true)
	elif _blade_path.active:
		var step := _blade_path.sample(dt)
		var hilt: Vector3 = step["pos"]
		var basis: Basis = step["basis"]
		var angles := basis.get_euler()
		pose.merge({
			"wpx": hilt.x, "wpy": hilt.y, "wpz": hilt.z, "ty": float(step["yaw"]),
			"wrx": angles.x, "wry": angles.y, "wrz": angles.z,
		}, true)
	else:
		pose["wpy"] = lerpf(float(pose["wpy"]), 0.36, guard)
		pose["wrx"] = lerpf(float(pose["wrx"]), -0.37, guard)
	return pose


func set_first_person_view(on: bool) -> void:
	if _first_person == on:
		return
	_first_person = on
	set_body_hidden(on)


func reset_demo(pos: Vector3, new_heading: float) -> void:
	clear_blade_path()
	guard = 0.0
	attack_elapsed = 0.0
	super.reset_demo(pos, new_heading)
	if _first_person:
		set_body_hidden(true)
	_record_blade()
	weapon_prev_xf = weapon_xf


func foot_points_xz() -> Array:
	var points: Array = []
	for leg in legs:
		var ankle: Vector3 = leg["ankle"].global_position
		points.append(Vector2(ankle.x, ankle.z))
	return points


## 回放/终结演出会直接写各关节的全局变换而不走 advance()：top_level 的
## 头发骨架不会跟着 head 走，必须在这里手动对齐，否则回放中头发脱节。
func sync_replay_pose() -> void:
	if hair != null and is_instance_valid(hair):
		hair.update(0.0, self)
		# 机体瞬移后 rig 速度积分会爆一帧，清掉上帧位置让滑移力重新起步。
		hair._has_prev_rig = false


func replay_nodes() -> Array:
	var nodes: Array = [self, body, torso, head, weapon_root, weapon_spin]
	for leg in legs:
		nodes.append_array([leg["hip"], leg["knee"], leg["ankle"]])
	for arm in arms:
		nodes.append_array([arm["shoulder"], arm["elbow"], arm["wrist"]])
	return nodes


## 少顶点凸体拟合：把刀身所有网格切片点收齐后按轴分段取凸包。
## 命中/格挡全部走它；blade_discs 只剩调试图形用途。
func _build_blade_proxy(segments := 6) -> BladeProxy:
	var groups: Array = []
	for child in weapon_spin.get_children():
		if child is not MeshInstance3D or child.name in [&"BladeGlow1", &"BladeAura"]:
			continue
		var part := child as MeshInstance3D
		var points := PackedVector3Array()
		var tris := PackedInt32Array()
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var base := points.size()
			for v in verts:
				points.append(part.transform * v)
			if idx.is_empty():
				for i in verts.size():
					tris.append(base + i)
			else:
				for i in idx:
					tris.append(base + i)
		groups.append({"points": points, "tris": tris})
	return BladeProxy.fit_groups(groups, segments)


func _measure_blade(buckets := 30) -> Array:
	var points := PackedVector3Array()
	var lo := INF
	var hi := -INF
	for child in weapon_spin.get_children():
		if child is not MeshInstance3D or child.name in [&"BladeGlow1", &"BladeAura"]:
			continue
		var part := child as MeshInstance3D
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = part.transform * vertex
				points.append(point)
				lo = minf(lo, point.y)
				hi = maxf(hi, point.y)
	if points.is_empty() or is_equal_approx(lo, hi):
		return []
	var radii := PackedFloat32Array()
	radii.resize(buckets)
	var width := (hi - lo) / float(buckets)
	for point in points:
		var index := clampi(int((point.y - lo) / width), 0, buckets - 1)
		radii[index] = maxf(radii[index], Vector2(point.x, point.z).length())
	var discs: Array = []
	for index in buckets:
		if radii[index] > 0.002:
			discs.append({"y": lo + (float(index) + 0.5) * width, "r": radii[index]})
	return discs


## debug：单 clip 的 min_d / reach_t（开发用）
func _pick_debug(target: Vector3, clip_name: String, lunge: float) -> Array:
	var torso_xf := _torso_transform(torso.rotation)
	var saved := _attack
	var spin_xf := weapon_spin.transform if weapon_spin != null else Transform3D.IDENTITY
	var fwd := -global_basis.z.normalized()
	var clip := _clip(clip_name)
	_attack = clip
	var trail: Array = clip.get("trail", [0.0, 1.0])
	var authored := _eval_curve(clip.get("lunge", []), float(clip.get("duration", 1.0)))
	var min_d := 1e9
	var reach_t := 1e9
	for i in 15:
		var t: float = lerpf(float(trail[0]), float(trail[1]), float(i) / 14.0)
		var pose := _evaluate_keys(t)
		var wr := Transform3D(
			Basis.from_euler(Vector3(float(pose["wrx"]), float(pose["wry"]), float(pose["wrz"]))),
			Vector3(float(pose["wpx"]), float(pose["wpy"]), float(pose["wpz"])))
		var wx: Transform3D = torso_xf * wr * spin_xf
		var lunged := _eval_curve(clip.get("lunge", []), t)
		if absf(authored) > 0.001:
			lunged = lunged / absf(authored) * lunge
		var tip: Vector3 = (wx * Vector3(0.0, BLADE_Y0 + BLADE_LEN, 0.0)) + fwd * lunged
		var base: Vector3 = (wx * Vector3(0.0, BLADE_Y0, 0.0)) + fwd * lunged
		var d := Geometry3D.get_closest_point_to_segment(target, base, tip).distance_to(target)
		if d < min_d: min_d = d
		if d <= 0.62 and reach_t > 1e8: reach_t = t
	_attack = saved
	return [min_d, reach_t]
