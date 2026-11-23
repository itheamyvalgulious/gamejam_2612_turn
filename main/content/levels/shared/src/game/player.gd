extends Node3D
class_name PlayerUnit
## 玩家：四足机甲 + 武士刀。
##
## 输入映射（全部可在 Esc 面板重绑）：
##   鼠标 = 视角         WASD = 相机相对移动        空格 = 跳       Shift = 冲刺
##   左键 = 攻击（配合 A/D/S 出 左斩/右斩/回身斩，不按 = 正前斩）
##   右键 = 架招：读威胁的轨迹 → 规划一条机械臂路径把刀送到它必经之路上
##          （剑挡剑：免伤 + 被击退；接箭：原路弹回）   Q = 重斩   E = 回旋斩
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const Rig = preload("res://src/vesper/mech_rig.gd")
const PAL = preload("res://src/vesper/material_palette.gd")
# 直接 preload：不依赖全局类缓存，headless / 首次 clone 都能跑
const InterceptS = preload("res://src/game/intercept.gd")

const PALETTE := {
	"tag": "hero",
	"accent": Color(1.0, 0.30, 0.055),
	"tint": Color(1.0, 1.0, 1.0),
	"metal_mix": 0.16,
}

# 每段动画本身的最大前冲量（用于把「前冲距离(m)」参数换算成缩放）
const LUNGE_MAX := {"light": 1.05, "fang": 1.00, "heavy": 1.15, "spin": 1.30}

var rig
var cam: GameCam
var alive := true
var parry_timer := 0.0        # 剩余弹反窗口
var parry_cd := 0.0
var block_push := Vector3.ZERO   # 格挡成功后被推开的残余速度
var last_attack := ""
var pending_hitstop := 0.0
var hurt_flash := 0.0
var swing_serial := 0
var hurt_serial := -1
var last_cause := ""
var hp := 100.0
var invuln := 0.0
var air_jumps := 0
var jump_buffer_dt := 0.0
var run_hold := 0.0
var coyote_left := 0.0
var _was_in_window := false
var projectiles = null
var _platform_grace := 0.0
var _last_platform := 0.0

# 弹反拦截规划的运行状态
var _intercept_on := false
var _intercept_kind := ""
var _plan_point := Vector3.ZERO
var _plan_body_yaw := 0.0
var _plan_left := 0.0
var _plan_idle := 0.0      # 已经多久没看到威胁了（收势的触发条件）
var _return_left := 0.0

var _last_swing_before := Transform3D.IDENTITY
var _swing_prev_xf := Transform3D.IDENTITY
var _swing_cur_xf := Transform3D.IDENTITY


func _ready() -> void:
	rig = Rig.new()
	rig.name = "Mech"
	rig.auto_step = false
	rig.set_process(false)
	rig.palette = PALETTE
	add_child(rig)
	rig.footstep.connect(_on_footstep)
	_sync_params()
	rig.facing_override = true


func set_camera(c: GameCam) -> void:
	cam = c


func _sync_params() -> void:
	rig.jump_vel = P.jump_velocity()
	rig.grav = P.getf("jump.gravity")
	rig.takeoff_time = P.getf("jump.takeoff_time")
	rig.land_time = P.getf("jump.land_time")
	rig.dash_distance = P.getf("dash.distance")
	rig.dash_duration = P.getf("dash.duration")
	rig.dash_cd = P.getf("dash.cooldown")
	rig.accel_rate = P.getf("move.accel")
	rig.decel_rate = P.getf("move.decel")
	rig.turn_rate = P.getf("move.turn_rate")
	rig.face_rate = P.getf("jump.air_steer") * 8.0 if rig.jump_state != "GROUND" else P.getf("move.turn_rate")
	var t := {}
	for id in ["slash_fwd", "slash_left", "slash_right", "slash_back", "heavy", "spin"]:
		t[id] = {
			"duration": P.getf("attack.%s.duration" % id),
			"windup": P.getf("attack.%s.windup" % id),
			"active": P.attack_active(id),
			"recovery": P.getf("attack.%s.recovery" % id),
		}
	rig.set_timings(t)


func step(dt: float, arena: Dictionary, enemies: Array = []) -> void:
	_sync_params()
	if not alive:
		return
	parry_timer = maxf(0.0, parry_timer - dt)
	parry_cd = maxf(0.0, parry_cd - dt)
	hurt_flash = maxf(0.0, hurt_flash - dt)
	invuln = maxf(0.0, invuln - dt)
	jump_buffer_dt = maxf(0.0, jump_buffer_dt - dt)

	var mv := B.move_vector()
	var cam_yaw: float = cam.yaw if cam != null else rig.heading
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var dir := right * mv.x + fwd * (-mv.y)

	var mag := clampf(mv.length(), 0.0, 1.0)
	if mag > 0.15:
		run_hold += dt
	else:
		run_hold = 0.0
	var move_speed := lerpf(P.getf("move.walk_speed"), P.getf("move.run_speed"), mag)
	if P.getb("move.auto_sprint") and run_hold > 1.4:
		move_speed = maxf(move_speed, P.getf("move.sprint_speed"))
	if rig.is_attacking:
		move_speed *= P.getf("move.attack_drag")
	if rig.jump_state == "AIR" or rig.jump_state == "LANDING":
		move_speed *= P.getf("move.air_control")
	if dir.length() > 0.15:
		rig.move_command = dir.normalized() * move_speed
	else:
		rig.move_command = Vector3.ZERO

	# 朝向：相机前方 or 移动方向
	if P.gets("move.facing_mode") == "camera":
		rig.facing_override = true
		rig.facing_heading = cam_yaw
	else:
		rig.facing_override = dir.length() > 0.15

	# ---------------- 输入
	# 跳跃：输入缓冲 + 二段跳 + 落地宽容
	if rig.jump_state == "GROUND":
		air_jumps = 0
		coyote_left = P.getf("jump.coyote_time")
	else:
		coyote_left = maxf(0.0, coyote_left - dt)
	if B.just("jump"):
		jump_buffer_dt = P.getf("jump.buffer_time")
		if P.getb("jump.double_jump") and rig.jump_state == "AIR" and air_jumps < 1:
			air_jumps += 1
			rig.vertical_velocity = P.jump_velocity()
			rig.jump_state = "AIR"
			rig.jump_t = 0.0
			jump_buffer_dt = 0.0
	if jump_buffer_dt > 0.0 and (rig.jump_state == "GROUND"
			or (rig.jump_state == "LANDING" and rig.jump_t <= coyote_left)):
		rig.jump_vel = P.jump_velocity()
		rig.request_jump()
		jump_buffer_dt = 0.0
	if B.just("dash"):
		rig.request_dash()
	if B.just("parry"):
		_begin_parry()
	if B.just("attack_light"):
		_attack_from_input(mv)
	if B.just("attack_heavy"):
		_attack("heavy", 0.0)
	if B.just("attack_spin"):
		_attack("spin", 0.0)

	# 举刀 / 架招：先把刀规划到威胁的必经之路上（读招 → 落点 → 机械臂过渡）
	# 窗口内一定在规划；窗口过了只要威胁还在、刀还架着，就继续跟着它走。
	if parry_timer > 0.0 or (_intercept_on and _plan_idle < P.getf("parry.pose_time")):
		_return_left = 0.0
		if P.getb("parry.auto_aim"):
			rig.guard = 0.0
			_plan_intercept(dt, enemies)
		else:
			rig.guard = 1.0 if parry_timer > 0.0 else 0.0
	elif _intercept_on:
		# 威胁没了：规划一条收势，把刀平滑地放回自然持刀位
		rig.guard = 0.0
		if _return_left <= 0.0:
			_return_left = maxf(P.getf("parry.pose_time"), 0.08)
			rig.plan_blade_return(_return_left)
		_return_left -= dt
		if _return_left <= 0.0:
			_end_intercept()
	else:
		rig.guard = 0.0
	if P.getf("dash.invuln") > 0.0 and rig.dash_time > 0.0:
		invuln = maxf(invuln, P.getf("dash.invuln"))

	# ---------------- 推进（记录刀的扫掠）
	_last_swing_before = rig.weapon_xf
	var ph := _platform_height(arena)
	if ph > 0.01:
		_last_platform = ph
		_platform_grace = 0.16
		rig.ground_y = ph
	elif _platform_grace > 0.0 and rig.jump_state == "GROUND":
		# 刚走出箱沿：给 0.16s 缓冲，避免“一只脚还在箱上”就被判掉下去
		_platform_grace = maxf(0.0, _platform_grace - dt)
		rig.ground_y = _last_platform
	else:
		_platform_grace = 0.0
		rig.ground_y = 0.0
	rig.advance(dt)
	# 攻击中允许按 move.attack_drag 慢慢位移（rig 在攻击时会锁住位移）
	if rig.is_attacking and dir.length() > 0.15:
		rig.position += dir.normalized() * (P.getf("move.run_speed") * P.getf("move.attack_drag")) * dt
	# 格挡击退：被架住的那一刀把人推开
	if block_push.length_squared() > 0.0001:
		rig.position += block_push * dt
		block_push *= exp(-7.0 * dt)
		if block_push.length() < 0.05:
			block_push = Vector3.ZERO
	_swing_prev_xf = _last_swing_before
	_swing_cur_xf = rig.weapon_xf

	# 挥剑风声：判定窗口打开的那一帧起风
	var in_win: bool = rig.in_hit_window()
	if in_win and not _was_in_window:
		var heavy: bool = rig.attack_name in ["GUILLOTINE", "HELIX STORM"]
		var blade: Vector3 = rig.weapon_xf * Vector3(0, 1.4, 0)
		Snd.play_at("swing_heavy" if heavy else "swing_light", blade,
			{"gain": 1.0 if heavy else 0.85})
	_was_in_window = in_win
	_clamp_to_arena(arena)


## 弹反拦截规划：找出最紧迫的威胁，把刀按规划好的路径送过去。
##
## 近战走 InterceptS.melee_threat（读敌人这一刀未来几帧的刀位姿），
## 远程走 InterceptS.projectile_threat（箭/刀气直线外推），两者共用同一套落点算法。
func _plan_intercept(dt: float, enemies: Array) -> void:
	var lead := P.getf("parry.plan_lead")
	var margin := P.getf("parry.intercept_margin")
	var best := {}
	# ---- 近战：读它的出剑轨迹
	if P.getb("parry.melee_block"):
		for e in enemies:
			if e == null or not is_instance_valid(e) or not e.alive:
				continue
			var t: Dictionary = InterceptS.melee_threat(self, e, margin)
			if not bool(t.get("ok", false)):
				continue
			if float(t["eta"]) > lead:
				continue
			if best.is_empty() or float(t["eta"]) < float(best["eta"]) - 0.02:
				best = t
	# ---- 远程：箭 / 刀气
	if projectiles != null:
		for it in projectiles.items:
			if not bool(it["alive"]) or String(it["owner"]) != "enemy" or bool(it["spent"]):
				continue
			var t2: Dictionary = InterceptS.projectile_threat(self, it,
				P.getf("parry.radius"), P.getf("parry.plan_speed"), P.getf("parry.arc_deg"))
			if not bool(t2.get("ok", false)):
				continue
			if float(t2["eta"]) > lead:
				continue
			if best.is_empty() or float(t2["eta"]) < float(best["eta"]) - 0.02:
				best = t2
	if best.is_empty():
		_plan_idle += dt
		_plan_left -= dt
		return
	_plan_idle = 0.0
	var point: Vector3 = best["point"]
	var eta: float = float(best["eta"])
	# 躯干在世界里的朝向（机体 + 腰环）：身体还在转的时候，刀要跟着重新规划
	var body_yaw: float = rig.heading + rig.torso.rotation.y
	var turned: float = absf(wrapf(body_yaw - _plan_body_yaw, -PI, PI))
	# 新威胁 / 落点跑掉了 / 身体转过角度了 / 上一条路径已经走完 → 重新规划
	if _intercept_on and _plan_left > 0.0 and _plan_point.distance_to(point) <= 0.22 \
			and turned <= 0.12:
		_plan_left -= dt
		return
	var dur := clampf(eta * 0.9, 0.05, 0.20)
	var res: Dictionary = rig.plan_blade_intercept(point, best["axis"], best["normal"],
		P.getf("parry.torso_turn"), dur, P.getf("parry.plan_speed"))
	if res.is_empty():
		return
	_intercept_on = true
	_intercept_kind = String(best["kind"])
	_plan_point = point
	_plan_body_yaw = body_yaw
	_plan_left = float(res.get("dur", dur))


func _end_intercept() -> void:
	_intercept_on = false
	_intercept_kind = ""
	_plan_left = 0.0
	_plan_idle = 999.0
	_return_left = 0.0
	rig.clear_blade_path()


## 格挡成功：免伤，但被这一刀推开
func on_block(push_dir: Vector3, speed: float) -> void:
	if not alive:
		return
	var d := push_dir
	d.y = 0.0
	if d.length_squared() < 0.0001:
		d = -rig.global_transform.basis.z
	block_push = d.normalized() * maxf(speed, 0.0)


func _on_footstep(pos: Vector3, strength: float) -> void:
	Snd.play_at("step", pos, {"gain": 0.30 + 0.25 * clampf(strength, 0.0, 1.5)})


func _platform_height(arena: Dictionary) -> float:
	var best := 0.0
	# 四足机甲不是质点：中心离台面边缘 0.6 u 以内仍算有支撑（约 0.33 m）
	const SUPPORT_MARGIN := 0.6
	for p in arena.get("platforms", []):
		var c: Vector3 = p["c"]
		var hx: float = float(p["hx"])
		var hz: float = float(p["hz"])
		var top: float = float(p["h"])
		# strict：窄面（栏杆顶这种）用机体中心判定，不加支撑余量
		var mx: float = hx if bool(p.get("strict", false)) else hx + SUPPORT_MARGIN
		var mz: float = hz if bool(p.get("strict", false)) else hz + SUPPORT_MARGIN
		if absf(rig.position.x - c.x) <= mx and absf(rig.position.z - c.z) <= mz:
			if rig.position.y >= top - 0.10 and top >= best:
				best = top
	return best


func _clamp_to_arena(arena: Dictionary) -> void:
	if arena.is_empty():
		return
	# 圆形场地：按半径夹紧（AABB 的四个角会跑到圆外）
	var rc: float = float(arena.get("bounds_circle", 0.0))
	if rc > 0.01:
		var flat := Vector2(rig.position.x, rig.position.z)
		if flat.length() > rc:
			flat = flat.normalized() * rc
			rig.position.x = flat.x
			rig.position.z = flat.y
	# 头顶不能穿出天花板（引擎没有天花板碰撞，这里按机体高度夹一下）
	var ceil_h: float = float(arena.get("ceiling", 0.0))
	if ceil_h > 0.1:
		rig.position.y = minf(rig.position.y, ceil_h - 4.60)
	var b: AABB = arena.get("bounds", AABB())
	if b.size.length() > 0.1:
		var p: Vector3 = rig.position
		p.x = clampf(p.x, b.position.x + 3.0, b.position.x + b.size.x - 3.0)
		p.z = clampf(p.z, b.position.z + 3.0, b.position.z + b.size.z - 3.0)
		p = Hit.resolve_circles(p, 1.1, arena.get("cover", []), p.y)
		rig.position = p


func _begin_parry() -> void:
	if parry_cd > 0.0 or rig.is_attacking:
		return
	parry_timer = P.getf("parry.window")
	parry_cd = P.getf("parry.cooldown") + P.getf("parry.window")
	# 不清 _intercept_on：上一刀可能还架着，刀还在外面就该继续挡
	_plan_left = 0.0
	_return_left = 0.0


## 「正对/侧/背」由按下瞬间按住的 WASD 决定
func _attack_from_input(mv: Vector2) -> void:
	if absf(mv.x) > 0.5 and absf(mv.x) >= absf(mv.y):
		if mv.x < 0.0:
			_attack("slash_left", PI * 0.5)
		else:
			_attack("slash_right", -PI * 0.5)
	elif mv.y > 0.5:
		_attack("slash_back", PI)
	else:
		_attack("slash_fwd", 0.0)


func _attack(move_id: String, yaw_off: float) -> void:
	if not alive:
		return
	if rig.is_attacking or rig.jump_state != "GROUND":
		return
	var lunge_param := P.getf("attack.%s.lunge" % move_id)
	# 左右横斩：单手持刀、刀身水平外伸，够得远
	if move_id == "slash_left" or move_id == "slash_right":
		var sgn := 1.0 if move_id == "slash_left" else -1.0
		rig.timing_key = move_id
		rig.force_swing(0.16 * sgn, 2.50 * sgn, {
			"offhand": 1.0, "reach": 0.72, "height": 0.34, "lift": 0.05,
			"torso": 0.62, "lean": 0.16, "lunge": lunge_param / 1.05,
		})
		last_attack = move_id
		swing_serial += 1
		return
	# 正前斩：双手、刀身水平前伸，横扫正前方扇形（够远）
	if move_id == "slash_fwd":
		rig.timing_key = move_id
		rig.force_swing(-1.05, 1.05, {
			"offhand": 0.0, "reach": 0.88, "height": 0.46, "lift": 0.10,
			"torso": 0.55, "lean": 0.10, "lunge": lunge_param / 1.05,
		})
		last_attack = move_id
		swing_serial += 1
		return
	# 反手后刺：刀指正后方，沿刀轴捅出去
	if move_id == "slash_back":
		rig.timing_key = move_id
		# 反手后刺：刀指正后方，沿刀轴捅出去
		rig.force_swing(PI, PI, {
			"offhand": 0.75, "reach": 0.35, "height": 0.16, "lift": -0.05,
			"torso": 0.28, "lean": 0.04, "thrust": 1.85, "lunge": 0.0,
		})
		last_attack = move_id
		swing_serial += 1
		return
	var clip := "light"
	if move_id == "heavy":
		clip = "heavy"
	elif move_id == "spin":
		clip = "spin"
	var lunge_scale := lunge_param / maxf(LUNGE_MAX.get(clip, 1.05), 0.01)
	rig.timing_key = move_id
	rig.force_attack(clip, yaw_off, lunge_scale)
	rig.attack_yaw = yaw_off
	last_attack = move_id
	swing_serial += 1


func is_parrying() -> bool:
	return parry_timer > 0.0


## 刀现在是不是「架着的」：规划中 / 等它撞上来 / 收势中（刀还在外面）都算。
## 判定用的是刀的真实几何，所以只要是举着刀这个状态，物理上就该挡得住。
func is_guard_up() -> bool:
	return _intercept_on


## 当前正在架什么（HUD 显示用）：""=没在架，"它的刀"=近战，"飞行物"=远程
func parry_plan_label() -> String:
	if not _intercept_on:
		return ""
	return "它的刀" if _intercept_kind == "melee" else "飞行物"


func parry_progress() -> float:
	var w := maxf(P.getf("parry.window"), 0.001)
	return clampf(1.0 - parry_timer / w, 0.0, 1.0)


func capsule() -> Dictionary:
	return Hit.rig_capsule(rig, 1.1, 3.4)


func hurt(_amount: float, _from_dir := Vector3.FORWARD, cause := "") -> void:
	if not alive or P.getb("rules.god_mode"):
		return
	if _amount <= 0.0:
		return          # 0 伤害的攻击不该致死（一击必死模式也一样）
	if invuln > 0.0:
		return
	last_cause = cause if cause != "" else "被斩中"
	if not P.getb("rules.one_hit_kill"):
		# 非一击必死：按最大血量比例扣血 + 无敌帧
		var dmg: float = P.getf("rules.hit_damage_scale") * maxf(1.0, P.getf("rules.player_hp"))
		hp = maxf(0.0, hp - dmg)
		invuln = P.getf("rules.invuln_time")
		hurt_flash = 0.2
		if Fx != null:
			Fx.screen_flash(0.22, Color(0.85, 0.08, 0.08))
			Fx.shake(0.6)
		if hp > 0.0:
			return
	alive = false
	rig.move_command = Vector3.ZERO
	Snd.play_at("player_death", rig.global_position + Vector3(0, 2.0, 0))
	if Fx != null:
		Fx.death_burst(rig.global_position + Vector3(0, 2.0, 0))
		Fx.screen_flash(0.55, Color(0.8, 0.05, 0.05))
		Fx.shake(1.2)


func reset(pos: Transform3D) -> void:
	alive = true
	hp = P.getf("rules.player_hp")
	invuln = 0.0
	air_jumps = 0
	run_hold = 0.0
	jump_buffer_dt = 0.0
	hurt_serial = -1
	swing_serial = 0
	parry_timer = 0.0
	parry_cd = 0.0
	block_push = Vector3.ZERO
	last_cause = ""
	_end_intercept()
	rig.ground_y = 0.0
	rig.reset_demo(pos.origin, pos.basis.get_euler().y)
	rig.facing_override = true
	rig.heading = pos.basis.get_euler().y
	rig.rotation.y = rig.heading
	if cam != null:
		cam.yaw = rig.heading
		cam.pitch = -0.16
		cam.set_first_person(P.gets("cam.mode") == "first")
