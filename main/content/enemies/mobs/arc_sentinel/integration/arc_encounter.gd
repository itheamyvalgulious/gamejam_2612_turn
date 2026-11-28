extends "res://src/game/encounter_unit.gd"

const Model = preload("res://team/arc/scripts/ch/arc_sentinel.gd")
const SCALE := 1.0 / 0.547
const EDGE_RADIUS := 0.24
const HIT_FROM := 0.30
const HIT_TO := 0.87
const ATTACK_CLIPS := ["attack1", "attack2"]
const STRIKE_HEIGHT := 0.87

var _cooldown := 0.0
var _attack := 0
var _blade_prev: Transform3D
var _blade_now: Transform3D
var _consumed := true
var _ground_move: Callable
var _support_floor: Callable
var _waypoint: Callable
var _ground_pose: Callable
var _ground_lift := 0.0
var _fall_speed := 0.0
## 寻路点缓存：路径规划对每只 sentinel 每帧要跑多次碰撞采样，按 0.12s /
## 位移 0.6m 复用即可，肉眼与命中判定都察觉不到差别。
var _wp_next := Vector3.ZERO
var _wp_from := Vector3.ZERO
var _wp_goal := Vector3.ZERO
var _wp_age := 0.0
var _wp_valid := false
## 同帧规划预算：一帧最多 2 只哨兵重算路径，其余延后一帧（见 step）。
const WP_PLAN_PER_FRAME := 2
static var _wp_plan_frame := -1
static var _wp_plan_used := 0


static func _wp_budget_take() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _wp_plan_frame:
		_wp_plan_frame = frame
		_wp_plan_used = 0
	if _wp_plan_used >= WP_PLAN_PER_FRAME:
		return false
	_wp_plan_used += 1
	return true


func _on_respawn() -> void:
	_fall_speed = 0.0
	_ground_lift = 0.0
	_cooldown = 0.0
	_attack = 0
	_consumed = true
	_wp_valid = false
	_wp_age = 0.0
	if rig != null:
		rig.play_anim("idle")
		rig.rotation = Vector3(0.0, rig.rotation.y, 0.0)
		_blade_now = _blade()
		_blade_prev = _blade_now

# Intercept and damage checks share the blade proxy in world units.
# blade_discs 仅作调试剖面；命中判定走 blade_proxy（16 棱柱包等离子刃缘）。
var blade_discs: Array = []
var blade_proxy: BladeProxy
var weapon_scale := 1.0
var last_dt := 0.0
var is_attacking: bool:
	get:
		return _fall_speed <= 0.0 and not _consumed and rig.current_anim in ATTACK_CLIPS
var attack_elapsed: float:
	get:
		return rig.anim_time()
var attack_hit_from: float:
	get:
		return rig.anim_duration() * HIT_FROM
var attack_hit_to: float:
	get:
		return rig.anim_duration() * HIT_TO

var _blade_length := 0.0


func _ready() -> void:
	enemy_id = "arc_sentinel"
	kind = "mob"
	set_health(P.getf("mob.hp"))
	rig = Model.new()
	rig.scale = Vector3.ONE * SCALE
	add_child(rig)
	rig.set_process(false)
	_blade_now = _blade()
	_blade_prev = _blade_now
	_blade_length = rig.rig.marker_tip.global_position.distance_to(_blade_now.origin)
	for i in 7:
		blade_discs.append({"y": _blade_length * float(i) / 6.0, "r": EDGE_RADIUS})
	# 等离子弧刃没有网格：用外切 24 棱柱包住圆柱刃缘
	# （r/cos(π/24) 外接半径 → 圆柱全包含，体胀仅 +0.9%）
	blade_proxy = BladeProxy.from_prism(
		BladeProxy.regular_ring(24, EDGE_RADIUS / cos(PI / 24.0)),
		0.0, _blade_length)
	for clip in ATTACK_CLIPS:
		_ensure_blade_cache(clip)


func use_ground_routes(move: Callable, support: Callable, waypoint: Callable) -> void:
	_ground_move = move
	_support_floor = support
	_waypoint = waypoint


func use_ground_pose(solve: Callable) -> void:
	_ground_pose = solve


func _restore_ground_base() -> void:
	if not _ground_pose.is_valid():
		return
	rig.global_position -= Vector3.UP * _ground_lift
	rig.rotation.x = 0.0
	_ground_lift = 0.0


func _fit_ground_pose() -> void:
	if not _ground_pose.is_valid():
		return
	var pose: Vector2 = _ground_pose.call(rig.global_position, rig.rotation.y)
	rig.rotation.x = pose.x
	_ground_lift = pose.y
	rig.global_position += Vector3.UP * _ground_lift


func hurt(amount: float, normal := Vector3.UP, knock := 0.0) -> void:
	if _ground_move.is_valid() and alive and amount > 0.0 and knock > 0.0:
		_restore_ground_base()
		var from: Vector3 = rig.global_position
		var push := normal.slide(Vector3.UP).normalized() * knock
		rig.global_position = _ground_move.call(from, from + push)
		_fit_ground_pose()
		_blade_now = _blade()
		_blade_prev = _blade_now
		knock = 0.0
	super.hurt(amount, normal, knock)


func blocks_when_seen() -> bool:
	if _guard_broken > 0.0:
		return false
	return rig.current_anim not in ATTACK_CLIPS


func on_seen_block(source: Vector3) -> void:
	var local: Vector3 = rig.to_local(source)
	rig.set_block_threat(rad_to_deg(atan2(local.x, local.z)))
	if rig.current_anim != "block":
		rig.play_anim("block")


## Q 键打断自己挥剑时强行破防：把 block 播完 + 标记短时间不可再架。
var _guard_broken := 0.0
func break_guard(_source: Vector3) -> void:
	_guard_broken = 1.2
	if rig.current_anim == "block":
		# 快放完这一小段 block，让它自然回到 idle
		rig.set_anim_time(rig.anim_duration() * 0.92)


func hit_parts() -> Array:
	# Cápsulas por articulación (chasis/torreta/brazo/orugas) ajustadas por
	# BodyColliders — la unión contiene todos los vértices del cuerpo.
	return rig.rig.body_colliders() if rig != null and rig.rig != null else []


func step(dt: float, ctx: Dictionary) -> void:
	super.step(dt, ctx)
	last_dt = dt
	if not alive:
		finish_death(dt)
		return
	_guard_broken = maxf(0.0, _guard_broken - dt)
	_cooldown = maxf(0.0, _cooldown - dt)
	var pace := 0.0
	_restore_ground_base()
	var grounded := _settle_on_ground(dt)
	var clip: String = rig.current_anim
	if grounded and player != null and player.alive and level.state == "fight" and clip in ["idle", "run"]:
		var center_at: Vector3 = rig.global_position
		var target: Vector3 = player.rig.global_position
		var offset := (target - center_at).slide(Vector3.UP)
		var distance := offset.length()
		var same_level := not _ground_move.is_valid() or absf(target.y - center_at.y) <= STRIKE_HEIGHT
		var clear: bool = same_level and (not level.has_method("melee_clear") \
			or level.melee_clear(center(), target + Vector3.UP * 1.4))
		var chase := target
		if _waypoint.is_valid() and (not clear or distance > 3.25):
			# 路径规划按 0.12s / 位移 0.6m 复用，行为与逐帧重算一致。
			_wp_age -= dt
			if not _wp_valid or _wp_age <= 0.0 \
					or center_at.distance_squared_to(_wp_from) > 0.36 \
					or target.distance_squared_to(_wp_goal) > 0.36 \
					or center_at.distance_squared_to(_wp_next) < 0.16:
				# 同帧规划预算：多只哨兵在同一帧到期时（同帧出生/玩家高速移动
				# 都会导致），错开到后续帧重算。没拿到预算时这一帧不更新路点：
				# 有效就继续用上一条，没有就直冲玩家（chase 初值即 target）。
				if _wp_budget_take():
					_wp_next = _waypoint.call(center_at, target)
					_wp_from = center_at
					_wp_goal = target
					_wp_age = 0.12
					_wp_valid = true
				else:
					_wp_age = 0.0
			if _wp_valid:
				chase = _wp_next
		else:
			_wp_valid = false
		var heading := (chase - center_at).slide(Vector3.UP)
		# 多怪防堆叠/互卡：软排斥周围活体非虚化敌人
		var sep := Vector3.ZERO
		if level != null and level.get("enemies") is Array:
			for other in level.get("enemies"):
				if other == self or other == null or not is_instance_valid(other) or not bool(other.get("alive")):
					continue
				if String(other.get("kind")) == "phase":
					continue
				var op: Vector3 = other.ground_position()
				if absf(op.y - center_at.y) > 2.4:
					continue
				var away := (center_at - op).slide(Vector3.UP)
				var d2 := away.length_squared()
				if d2 < 2.8 * 2.8:
					if d2 < 0.001:
						away = Vector3.RIGHT if get_instance_id() > other.get_instance_id() else Vector3.LEFT
						d2 = 1.0
					var d := sqrt(d2)
					sep += (away / d) * ((2.8 - d) / 2.8)
		if sep.length_squared() > 0.001 and heading.length_squared() > 0.01:
			heading = (heading.normalized() + sep * 0.85).normalized() * heading.length()
		var desired: float = atan2(heading.x, heading.z) if heading.length_squared() > 0.0001 else rig.rotation.y
		rig.rotation.y = rotate_toward(rig.rotation.y, desired, dt * 6.0)
		if distance <= 3.25 and clear and _cooldown <= 0.0:
			_attack += 1
			swung_serial += 1
			rig.play_anim(_choose_attack(player))
			_cooldown = rig.anim_duration() + 0.43
			_consumed = false
			Snd.play_at("swing_light", center(), {"gain": 0.44})
		elif (distance > 2.65 or not same_level) and dt > 0.0:
			pace = _move_toward(center_at, target, heading, dt)
			var movement_clip := "run" if pace > 0.04 else "idle"
			if clip != movement_clip:
				rig.play_anim(movement_clip)
		elif clip != "idle":
			rig.play_anim("idle")
	rig.set_track_speed(pace / SCALE, pace / SCALE)
	_blade_prev = _blade_now
	if grounded:
		_fit_ground_pose()
	rig._process(dt)
	_blade_now = _blade()


func _settle_on_ground(dt: float) -> bool:
	if not _support_floor.is_valid():
		return true
	var at: Vector3 = rig.global_position
	var floor_y: float = _support_floor.call(at)
	if at.y <= floor_y + 0.04:
		_fall_speed = 0.0
		return true
	# A displaced unit must land before it can chase or swing.
	_fall_speed += P.getf("jump.gravity") * dt
	at.y = maxf(floor_y, at.y - _fall_speed * dt)
	rig.global_position = at
	if at.y > floor_y:
		_consumed = true
		if rig.current_anim != "idle":
			rig.play_anim("idle")
		return false
	_fall_speed = 0.0
	return true


func _move_toward(from: Vector3, target: Vector3, heading: Vector3, dt: float) -> float:
	var pace := minf(P.getf("mob.speed"), 8.0)
	var forward: Vector3 = rig.global_basis.z.normalized()
	if _ground_move.is_valid():
		if heading.normalized().dot(forward) < 0.25:
			return 0.0
		var at: Vector3 = _ground_move.call(from, from + heading.limit_length(pace * dt))
		rig.global_position = at
		return (at - from).slide(Vector3.UP).length() / dt
	# 没接 use_ground_routes 的哨兵保持直行（旧 AStarGrid2D 回退已删除）。
	rig.global_position += forward * pace * dt
	return pace


const BLADE_CACHE_SAMPLES := 32
static var _blade_pose_cache := {}   # clip -> {dur: float, samples: Array[{tool, tip}]}


func _ensure_blade_cache(clip: String) -> Dictionary:
	if _blade_pose_cache.has(clip):
		return _blade_pose_cache[clip]
	var dur: float = rig.anim.duration(clip)
	var samples: Array = []
	for i in BLADE_CACHE_SAMPLES + 1:
		var t: float = dur * float(i) / float(BLADE_CACHE_SAMPLES)
		var joints: Dictionary = rig.predict_blade_pose_for(clip, t) if rig.has_method("predict_blade_pose_for") else rig.predict_blade_pose(t)
		samples.append({"tool": joints["tool"], "tip": joints["tip"]})
	var entry := {"dur": dur, "samples": samples}
	_blade_pose_cache[clip] = entry
	return entry


func predict_weapon_xf(time: float) -> Transform3D:
	var clip: String = rig.current_anim
	if clip in ATTACK_CLIPS and rig != null and rig.anim != null:
		var entry := _ensure_blade_cache(clip)
		var dur: float = maxf(float(entry["dur"]), 1e-4)
		var samples: Array = entry["samples"]
		var u := clampf(time / dur, 0.0, 1.0) * float(BLADE_CACHE_SAMPLES)
		var i0 := mini(int(floor(u)), BLADE_CACHE_SAMPLES - 1)
		var frac := u - float(i0)
		var s0: Dictionary = samples[i0]
		var s1: Dictionary = samples[i0 + 1]
		var tool_l: Vector3 = (s0["tool"] as Vector3).lerp(s1["tool"] as Vector3, frac)
		var tip_l: Vector3 = (s0["tip"] as Vector3).lerp(s1["tip"] as Vector3, frac)
		return _blade_transform(rig.to_global(tool_l), rig.to_global(tip_l))
	var joints: Dictionary = rig.predict_blade_pose(time)
	return _blade_transform(rig.to_global(joints["tool"]), rig.to_global(joints["tip"]))


func resolve_attack(target) -> Dictionary:
	if not is_attacking or not target.alive or attack_elapsed < attack_hit_from or attack_elapsed > attack_hit_to:
		return {"hit": false}
	if target.rig == null or rig.global_position.distance_squared_to(target.rig.global_position) > 9.0 * 9.0:
		return {"hit": false}
	var push: Vector3 = (target.rig.global_position - rig.global_position).slide(Vector3.UP).normalized()
	# 只有格挡姿态才判剑挡剑：挥砍/收刀途中碰到刀不能再白嫖挡刀。
	if P.getb("parry.melee_block") and (not target.has_method("is_guard_up") or target.is_guard_up()):
		var clash_slack := 0.18
		var guard: Dictionary = Hit.blade_vs_blade_swept(
			target.rig.weapon_prev_xf, target.rig.weapon_xf, target.rig.blade_proxy,
			_blade_prev, _blade_now, blade_proxy, clash_slack,
			target.rig.blade_span(), Vector2(0.0, _blade_length),
			3, 4, -1)
		if guard.get("hit", false):
			var contact: Vector3 = guard["point"]
			if not level.has_method("melee_clear") or level.melee_clear(center(), contact):
				_consumed = true
				target.on_block(push, P.getf("parry.block_knockback"))
				return {"hit": false, "parried": true, "melee": true, "pos": contact, "normal": guard["normal"], "push": push}
	var parts: Array = target.rig.hit_parts() if target.rig != null and target.rig.has_method("hit_parts") \
		else []
	var hit: Dictionary = Hit.sweep_blade_parts(_blade_prev, _blade_now, blade_proxy, parts) \
		if not parts.is_empty() \
		else Hit.sweep_blade(_blade_prev, _blade_now, blade_proxy,
			target.capsule()["a"], target.capsule()["b"], target.capsule()["r"])
	if not hit.get("hit", false):
		return {"hit": false}
	var location: Vector3 = hit.get("point", center())
	if level.has_method("melee_clear") and not level.melee_clear(center(), location):
		return {"hit": false}
	_consumed = true
	var previous: float = target.hp
	target.hurt(damage, push, "被 ARC Sentinel 击中")
	return {"hit": not target.alive or target.hp < previous, "pos": location}


## 按「现在的姿势能不能打中、会不会撞上你的刀」在两个挥击 clip 之间做选择。
## attack1 是上段劈、attack2 是侧扫：先对每个 clip 的判定窗取样几个刀位，
## 看扫掠体是贴近身体（hit_parts）还是贴近玩家刀身（blade 段）；
## 能命中且不送格挡的最好，打不中的不选，全一样就照旧交替保变化。
func _choose_attack(target) -> String:
	var parts: Array = target.rig.hit_parts() if target.rig != null and target.rig.has_method("hit_parts") \
		else []
	if parts.is_empty() or not rig.has_method("predict_blade_pose_for"):
		return "attack1" if _attack % 2 else "attack2"
	# 玩家当前刀段：起手这一瞬的静止刀身就是「他现在怎么架」。
	var pspan: Vector2 = target.rig.blade_span()
	var pb0: Vector3 = target.rig.weapon_xf * Vector3(0, pspan.x, 0)
	var pb1: Vector3 = target.rig.weapon_xf * Vector3(0, pspan.y, 0)
	# 选择器用解析线-线近似做便宜估计（与 active_parry 的扫描同款）：
	# 只需要「碰到/没碰到」决策语义，不用逐位姿 GJK —— 旧实现一次选刀
	# ~20 组凸体扫描、实测单帧 100ms+，是周期性大尖峰的主因。
	# 命中的真实判定仍走 Combat/Hit 的精确路径，这里只影响 attack1/2 的选择。
	var reach := EDGE_RADIUS + 0.18        # 刃厚 + 命中余量（近似）
	var blade_reach := EDGE_RADIUS + 0.30  # 刀-刀近距离近似（含对方刃厚）
	var prev_e0 := Vector3.INF
	var prev_e1 := Vector3.INF
	var have_prev := false
	var scores: Array = []
	for clip in ATTACK_CLIPS:
		var entry := _ensure_blade_cache(clip)
		var dur: float = maxf(float(entry["dur"]), 1e-4)
		var samples: Array = entry["samples"]
		var t0: float = dur * HIT_FROM
		var t1: float = dur * HIT_TO
		var touch_body := false
		var touch_blade := false
		prev_e0 = Vector3.INF
		prev_e1 = Vector3.INF
		have_prev = false
		for i in 6:
			var e: float = lerpf(t0, t1, float(i) / 5.0)
			var u := clampf(e / dur, 0.0, 1.0) * float(BLADE_CACHE_SAMPLES)
			var i0 := mini(int(floor(u)), BLADE_CACHE_SAMPLES - 1)
			var frac := u - float(i0)
			var s0: Dictionary = samples[i0]
			var s1: Dictionary = samples[i0 + 1]
			var edge0: Vector3 = rig.to_global((s0["tool"] as Vector3).lerp(s1["tool"] as Vector3, frac))
			var edge1: Vector3 = rig.to_global((s0["tip"] as Vector3).lerp(s1["tip"] as Vector3, frac))
			if have_prev:
				# 扫掠四边形近似：当前刀段、上一位姿刀段、柄端轨迹、尖
				# 端轨迹四条边到目标的最近距 —— 包住两步采样间的扫掠面。
				for part: Dictionary in parts:
					var cap_a: Vector3 = part["a"]
					var cap_b: Vector3 = part["b"]
					var d := _seg_seg_d(edge0, edge1, cap_a, cap_b)
					d = minf(d, _seg_seg_d(prev_e0, prev_e1, cap_a, cap_b))
					d = minf(d, _seg_seg_d(prev_e0, edge0, cap_a, cap_b))
					d = minf(d, _seg_seg_d(prev_e1, edge1, cap_a, cap_b))
					if d - float(part["r"]) <= reach:
						touch_body = true
						break
				var db := _seg_seg_d(edge0, edge1, pb0, pb1)
				db = minf(db, _seg_seg_d(prev_e0, prev_e1, pb0, pb1))
				db = minf(db, _seg_seg_d(prev_e0, edge0, pb0, pb1))
				db = minf(db, _seg_seg_d(prev_e1, edge1, pb0, pb1))
				if db <= blade_reach:
					touch_blade = true
			prev_e0 = edge0
			prev_e1 = edge1
			have_prev = true
		var score := 0
		if touch_body:
			score += 2
		if touch_blade:
			score -= 3
		scores.append(score)
	var pick_idx := _attack % 2 if scores[0] == scores[1] else (0 if scores[0] > scores[1] else 1)
	return ATTACK_CLIPS[pick_idx]


## 两线段轴心距（_choose_attack 的解析近似用；与 active_parry._seg_seg 同式）。
static func _seg_seg_d(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.000001 and e <= 0.000001:
		return r.length()
	if a <= 0.000001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.000001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			s = clampf((b * f - c * e) / den, 0.0, 1.0) if den > 0.000001 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var c0 := p1 + d1 * s
	var c1 := p2 + d2 * t
	return c0.distance_to(c1)


func _blade() -> Transform3D:
	var base: Vector3 = rig.rig.marker_base.global_position
	var tip: Vector3 = rig.rig.marker_tip.global_position
	return _blade_transform(base, tip)


func _blade_transform(base: Vector3, tip: Vector3) -> Transform3D:
	var axis := (tip - base).normalized()
	var reference := Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > 0.97 else Vector3.UP
	var right := axis.cross(reference).normalized()
	return Transform3D(Basis(right, axis, right.cross(axis)), base)


func hud_alert(target: PlayerUnit) -> bool:
	return is_attacking and attack_elapsed >= attack_hit_from - 0.26 and attack_elapsed <= attack_hit_to \
		and ground_position().distance_squared_to(target.rig.global_position) < 4.25 * 4.25
