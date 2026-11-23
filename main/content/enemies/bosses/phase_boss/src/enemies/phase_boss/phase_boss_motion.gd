extends RefCounted
## Samples a pose at an absolute time so pausing and frame scrubbing share the same motion.

const PhaseState = preload("res://src/enemies/phase_boss/phase_boss_state.gd")
const PHASE_FIGHT_START := PhaseState.CHARGE_TIME + PhaseState.ENTER_TIME
const PHASE_FIGHT_END := PHASE_FIGHT_START + PhaseState.ACTIVE_TIME
const PHASE_CYCLE_TIME := PHASE_FIGHT_END + PhaseState.RETURN_TIME
const PHASE_ATTACK_RATE := 1.22
const PHASE_MOVE_RATE := 1.28
const INTRO_SLEEP_TIME := 1.45
const INTRO_GROWL_TIME := 3.12
const INTRO_DURATION := 4.65
const WALK_PERIOD := 1.45
const WALK_SPEED := 2.55
const REPOSITION_TIME := 1.12
const REPOSITION_DISTANCE := 2.45
const FLANK_LEAP_DISTANCE := 5.35
const FLANK_BACKSTEP_DISTANCE := 4.25
const FLANK_LEAP_LAND := 0.46
const FLANK_LEAP_DURATION := 1.32
const RUSH_TURN_TIME := 0.72
const RUSH_TURN_LAND := 0.51
const RUSH_TURN_MAX_DEGREES := 150.0
const SHORT_POUNCE_TAKEOFF := 0.747
const SHORT_POUNCE_LAND := 1.19
const SPRINT_PERIOD := 0.60
const SPRINT_LAND_PHASES := [0.51, 0.0, 0.70, 0.18]
const SPRINT_FOOT_SHAKES := [0.38, 0.24, 0.38, 0.24]
const SPRINT_SPEED := 14.25
const RUN_IN := SPRINT_PERIOD * 2.16
const RUN_GATHER_DISTANCE := 4.35
const RUN_APPROACH_DISTANCE := SPRINT_SPEED * RUN_IN + RUN_GATHER_DISTANCE
const RUN_LEAP_SPEED := 6.2
const LEAP_TAKEOFF := 0.56
const LEAP_CONTACT := 1.61
const LEAP_DURATION := 2.36
const CANNON_OPEN := 0.17
const CANNON_SEATED := 0.64
const CANNON_CHARGE := 0.85
const CANNON_FIRE := CANNON_CHARGE + 1.72
const CANNON_LOCK := CANNON_FIRE - 0.36
const CANNON_RELEASE := CANNON_FIRE + 1.20
const CANNON_STOW := CANNON_RELEASE + 0.56
const CANNON_DURATION := CANNON_STOW + 0.38
const MELEE_WINDUP_EXTENSION := 0.30
const SWEEP_STRIKE := 0.53
const SWEEP_REACH := 1.42
const STOMP_STRIKE := 0.74
const STOMP_IMPACT := 0.75 + MELEE_WINDUP_EXTENSION
const STOMP_WAVE_END := 0.96 + MELEE_WINDUP_EXTENSION
const STOMP_WAVE_RADIUS := 3.70
const TAIL_STRIKE := 0.54
const TAIL_SWEEP_TIME_CUT := 0.15
const TAIL_CONTACT_BEGIN := TAIL_STRIKE + MELEE_WINDUP_EXTENSION
const TAIL_CONTACT_END := 1.19 + MELEE_WINDUP_EXTENSION - TAIL_SWEEP_TIME_CUT
const TAIL_DURATION := 1.87 + MELEE_WINDUP_EXTENSION - TAIL_SWEEP_TIME_CUT
const IMPACT_SHAKES := {
	"rush_turn": [RUSH_TURN_LAND, 1.18],
	"stomp": [STOMP_IMPACT, 1.40],
	"pounce": [SHORT_POUNCE_LAND, 2.55],
	"high_pounce": [LEAP_CONTACT, 3.12],
	"run_pounce": [RUN_IN + LEAP_CONTACT, 3.12],
	"back_cannon": [CANNON_FIRE, 1.75],
}
const ROAR_DURATION := 3.20
const ROAR_SOUND_TIME := 0.37
const ROAR_SOUND_DURATION := 2.46
const TAIL_TURN_KEYS := [
	Vector3(0.04, 0.0, 0.0),
	Vector3(0.30, -0.19, 0.0),
	Vector3(0.56, 0.07, 2.45),
	Vector3(0.83, 0.76, 2.20),
	Vector3(1.09, 1.0, 0.0),
	Vector3(1.76, 0.0, 0.0),
]
const PHASE_SEQUENCE := [
	["phase_roar", "仰天咆哮", ROAR_DURATION, 1.0],
	["phase", "交叉扫", 4.05, PHASE_ATTACK_RATE],
	["sweep", "低颚横扫", 1.55 + MELEE_WINDUP_EXTENSION, PHASE_ATTACK_RATE],
	["stomp", "压肩踏爪", 1.70 + MELEE_WINDUP_EXTENSION, PHASE_ATTACK_RATE],
	["tail_left", "向左扫尾", TAIL_DURATION, PHASE_ATTACK_RATE],
	["back_cannon", "背炮激光", CANNON_DURATION, 1.0],
	["pounce", "低伏短扑", 1.75, PHASE_ATTACK_RATE],
	["stomp", "压肩踏爪", 1.70 + MELEE_WINDUP_EXTENSION, PHASE_ATTACK_RATE],
	["tail", "向右扫尾", TAIL_DURATION, PHASE_ATTACK_RATE],
	["sweep", "低颚横扫", 1.55 + MELEE_WINDUP_EXTENSION, PHASE_ATTACK_RATE],
]

const CLIPS := [
	["idle", "低伏待机", 2.8], ["walk", "低伏慢走", 4.35], ["trot", "对角小跑", 3.60],
	["turn", "换脚转身", 1.82], ["sweep", "低颚横扫", 1.55 + MELEE_WINDUP_EXTENSION],
	["stomp", "压肩踏爪", 1.70 + MELEE_WINDUP_EXTENSION],
	["reposition", "低伏让位", REPOSITION_TIME],
	["flank_leap", "侧跳 · 后撤", FLANK_LEAP_DURATION],
	["rush_turn", "腾起转身", RUSH_TURN_TIME],
	["pounce", "低伏短扑", 1.75], ["tail", "向右扫尾", TAIL_DURATION], ["charge", "视野充能", PhaseState.CHARGE_TIME],
	["phase", "虚化交叉扫", 4.05], ["cycle", "充能 · 持续虚化 · 复实", PHASE_CYCLE_TIME],
	["sprint", "全速飞奔", 2.0], ["high_pounce", "长距离高扑", LEAP_DURATION],
	["run_pounce", "飞奔接高扑", RUN_IN + LEAP_DURATION],
	["back_cannon", "背炮展开 · 蓄力激光", CANNON_DURATION],
	["tail_left", "向左扫尾", TAIL_DURATION],
	["phase_enter", "满充 · 转入虚化", PhaseState.ENTER_TIME],
	["phase_roar", "虚化 · 仰天咆哮", ROAR_DURATION],
	["phase_exit", "虚化结束 · 复实", PhaseState.RETURN_TIME],
	["wake_intro", "休眠 · 苏醒", INTRO_DURATION],
]

const CONTACT_WINDOWS := {
	"sweep": [["head", SWEEP_STRIKE + MELEE_WINDUP_EXTENSION, 0.80 + MELEE_WINDUP_EXTENSION, SWEEP_REACH]],
	"stomp": [["paw", STOMP_STRIKE + MELEE_WINDUP_EXTENSION, STOMP_WAVE_END, STOMP_WAVE_RADIUS]],
	"pounce": [["pounce", 1.075, 1.25, 0.88]],
	"high_pounce": [["pounce", LEAP_CONTACT - 0.07, LEAP_CONTACT + 0.12, 1.65]],
	"run_pounce": [["pounce", RUN_IN + LEAP_CONTACT - 0.07, RUN_IN + LEAP_CONTACT + 0.12, 1.65]],
	"tail": [["tail", TAIL_CONTACT_BEGIN, TAIL_CONTACT_END, 0.70]],
	"tail_left": [["tail", TAIL_CONTACT_BEGIN, TAIL_CONTACT_END, 0.70]],
	"phase": [["head", 1.13, 1.44, 0.98], ["tail", 1.99, 2.31, 0.91]],
}

class Pose:
	var position := Vector3.ZERO
	var yaw := 0.0
	var chest := Vector3.ZERO
	var chest_angles := Vector3.ZERO
	var pelvis_offset := Vector3.ZERO
	var hip_angles := Vector3.ZERO
	var neck_angles := Vector3.ZERO
	var head_angles := Vector3.ZERO
	var paw_positions: Array[Vector3] = []
	var paw_angles := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var paw_yaw := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var jaw := 0.0
	var jaw_cut := 0.0
	var tail_sweep := 0.0
	var tail_lift := 0.0
	var delayed_tail := PackedFloat32Array()
	var sweep_tail_yaw := PackedFloat32Array()
	var charge := 0.0
	var phase := 0.0
	var lamp_power := 1.0
	var flash := 0.0
	var fin := 0.0
	var signal_name := ""
	var marker := ""
	var burst := 0.0
	var release_age := 0.0
	var impact := 0.0
	var impact_position := Vector3.ZERO
	var impact_scale := 1.0
	var stomp_wave := 0.0
	var stomp_radius := 0.0
	var cannon_hatches := 0.0
	var cannon_raise := 0.0
	var cannon_extend := 0.0
	var cannon_pitch := 0.0
	var cannon_recoil := 0.0
	var cannon_power := 0.0
	var cannon_heat := 0.0
	var cannon_shot := 0.0
	var cannon_charging := false
	var cannon_locked := false
	var cannon_range := -1.0
	var cannon_surface_hit := false
	var cannon_yaw := 0.0

var model: Node3D
var origin: Transform3D
var maximum_reach_error := 0.0
var _chest: Vector3
var _pelvis: Vector3
var _tails: Array[Vector3] = []
var _fins: Array[Vector3] = []
var _rest_feet: Array[Vector3] = []
var _limbs: Array[Dictionary] = []


func _init(rig: Node3D) -> void:
	model = rig
	origin = model.transform
	_chest = model.chest.position
	_pelvis = model.pelvis.position
	for foot: Dictionary in model.legs:
		_rest_feet.append(model.to_local(foot["paw"].global_position))
		_limbs.append({"upper": foot["joint"].position, "middle": foot["distal"].position,
			"lower": foot["paw"].position})
	for joint: Node3D in model.tail:
		_tails.append(joint.rotation_degrees)
	for fin: Node3D in model.emitters:
		_fins.append(fin.rotation_degrees)


func sample(clip: String, time: float) -> Pose:
	var p := Pose.new()
	p.paw_positions = _rest_feet.duplicate()
	match clip:
		"idle":
			_idle(p, time)
		"walk":
			_gait(p, time, false)
		"trot":
			_gait(p, time, true)
		"turn":
			_turn(p, time)
		"reposition":
			_reposition(p, time, Vector3.BACK)
		"flank_leap":
			_flank_leap(p, time, Vector3.RIGHT * FLANK_LEAP_DISTANCE,
				Basis(Vector3.UP, deg_to_rad(88.0)) * Vector3.BACK * FLANK_BACKSTEP_DISTANCE, 88.0)
		"rush_turn":
			_rush_turn(p, time, 90.0)
		"sweep":
			_sweep(p, time)
		"stomp":
			_stomp(p, time)
		"pounce":
			_pounce(p, time)
		"tail":
			_tail(p, time, 1.0)
		"tail_left":
			_tail(p, time, -1.0)
		"charge":
			_charge(p, time)
		"phase":
			_phase(p, time)
		"phase_enter":
			enter_phase(p, time)
		"phase_roar":
			phase_roar(p, time)
		"phase_exit":
			return_from_phase(p, time)
		"wake_intro":
			_wake_intro(p, time)
		"cycle":
			return _phase_cycle(time)
		"sprint":
			_sprint(p, time)
		"high_pounce":
			_high_pounce(p, time)
		"run_pounce":
			_run_pounce(p, time)
		"back_cannon":
			_back_cannon(p, time)
	return p


func apply(p: Pose) -> void:
	model.transform = origin * Transform3D(Basis(Vector3.UP, deg_to_rad(p.yaw)), p.position)
	model.chest.position = _chest + p.chest
	model.chest.rotation_degrees = p.chest_angles
	model.pelvis.position = _pelvis + p.pelvis_offset
	model.pelvis.rotation_degrees = p.hip_angles
	model.neck.rotation_degrees = p.neck_angles
	model.head.rotation_degrees = p.head_angles
	model.set_jaw_open(p.jaw)
	model.cannon.pose(p.cannon_hatches, p.cannon_raise, p.cannon_extend,
		p.cannon_pitch - p.chest_angles.x * p.cannon_raise, p.cannon_recoil, p.cannon_yaw)
	for i in _tails.size():
		var delayed := sin(float(i) / _tails.size() * PI * 0.8)
		var turn := (p.tail_sweep if p.delayed_tail.is_empty() else p.delayed_tail[i]) * (0.13 + delayed * 0.049)
		if not p.sweep_tail_yaw.is_empty():
			turn = p.sweep_tail_yaw[i]
		model.tail[i].rotation_degrees = _tails[i] + Vector3(p.tail_lift * (0.26 + delayed * 0.09), turn, 0.0)
	for i in _fins.size():
		var side := -1.0 if i == 0 else 1.0
		model.emitters[i].rotation_degrees = _fins[i] + Vector3(-p.fin * 6.0, 0, -side * p.fin * 10.0)
	maximum_reach_error = 0.0
	var parent := model.get_parent_node_3d()
	var stage := origin if parent == null else parent.global_transform * origin
	for i in _limbs.size():
		_solve_leg(i, p, stage)
	model.update_actuators()


func _solve_leg(i: int, p: Pose, stage: Transform3D) -> void:
	var leg: Dictionary = model.legs[i]
	var shoulder: Node3D = leg["root"]
	var elbow: Node3D = leg["joint"]
	var wrist: Node3D = leg["distal"]
	var paw: Node3D = leg["paw"]
	var chain := _limbs[i]
	var upper: Vector3 = chain["upper"]
	var middle: Vector3 = chain["middle"]
	var lower: Vector3 = chain["lower"]
	var frame: Node3D = shoulder.get_parent()
	var desired_sole := Basis(Vector3.UP, deg_to_rad(p.paw_yaw[i])) * Basis(
		Vector3.RIGHT, deg_to_rad(p.paw_angles[i]))
	var frame_basis := frame.global_transform.basis.orthonormalized()
	var local_sole := frame_basis.inverse() * stage.basis.orthonormalized() * desired_sole
	var distal_turn := local_sole.get_rotation_quaternion()
	var ankle_offset := distal_turn * lower
	var endpoint := frame.to_local(stage * p.paw_positions[i]) - shoulder.position - ankle_offset
	var requested := endpoint.length()
	var max_reach := upper.length() + middle.length() - 0.002
	var min_reach := absf(upper.length() - middle.length()) + 0.002
	var distance := clampf(requested, min_reach, max_reach)
	maximum_reach_error = maxf(maximum_reach_error, absf(requested - distance))
	var along := endpoint.normalized()
	if along.is_zero_approx():
		along = Vector3.DOWN
	# Carry the rest bend plane with the ankle direction to avoid a knee flip on a long cross-step.
	var rest_axis := (upper + middle).normalized()
	var pole := Quaternion(rest_axis, along) * upper.slide(rest_axis).normalized()
	var projected := (upper.length_squared() - middle.length_squared() + distance * distance) / (2.0 * distance)
	var bend := sqrt(maxf(0.0, upper.length_squared() - projected * projected))
	var elbow_at := along * projected + pole * bend
	var wrist_at := along * distance
	var upper_turn := Quaternion(upper.normalized(), elbow_at.normalized())
	var middle_turn := Quaternion(middle.normalized(), (wrist_at - elbow_at).normalized())
	shoulder.quaternion = upper_turn
	elbow.quaternion = upper_turn.inverse() * middle_turn
	wrist.quaternion = middle_turn.inverse() * distal_turn
	paw.quaternion = Quaternion.IDENTITY


func _ramp(a: float, b: float, t: float) -> float:
	return smoothstep(a, b, t)


func _pulse(a: float, b: float, c: float, d: float, t: float) -> float:
	return _ramp(a, b, t) * (1.0 - _ramp(c, d, t))


func _lift(u: float, height: float) -> float:
	return pow(sin(clampf(u, 0.0, 1.0) * PI), 1.45) * height


func _step(p: Pose, i: int, from: Vector3, to: Vector3, begin: float, end: float,
		height: float, t: float) -> void:
	var u := clampf(inverse_lerp(begin, end, t), 0.0, 1.0)
	p.paw_positions[i] = _rest_feet[i] + from.lerp(to, smoothstep(0.0, 1.0, u))
	var flight := _lift(u, height)
	p.paw_positions[i].y += flight
	p.paw_angles[i] = sin(u * TAU) * minf(11.0, flight * 19.0)


func _idle(p: Pose, t: float) -> void:
	var breath := sin(t / 2.8 * TAU)
	p.chest.y = breath * 0.050
	p.neck_angles.x = breath * 1.7
	p.head_angles.x = -breath * 1.35
	p.tail_sweep = breath * 5.0


func _wake_intro(p: Pose, t: float) -> void:
	var asleep := 1.0 - _ramp(INTRO_SLEEP_TIME, 2.06, t)
	var low := 1.0 - _ramp(2.05, 2.98, t)
	var folded := 1.0 - _ramp(2.43, 3.13, t)
	var brace := _pulse(1.89, 2.35, 2.53, 3.10, t)
	var growl := _pulse(2.99, 3.30, 3.53, 4.23, t)
	var breath := sin(t * TAU / 2.75) * asleep
	var look_up := _pulse(1.48, 1.93, 2.45, 3.05, t)

	p.position.y = -1.04 * low
	p.chest = Vector3(0.19 * low - 0.24 * brace,
		-0.31 * low - 0.14 * brace + 0.21 * growl + 0.036 * breath, 0.12 * asleep - 0.36 * brace)
	p.chest_angles = Vector3(3.7 * low + 2.0 * brace + 5.3 * growl,
		-1.8 * low, -4.5 * low + 3.8 * brace)
	p.pelvis_offset = Vector3(-0.36 * folded, -0.24 * folded - 0.26 * (folded - low), 0.10 * folded)
	p.hip_angles = Vector3(-4.6 * folded + 3.0 * brace - 3.4 * growl,
		-6.5 * folded, 4.0 * folded)
	p.neck_angles = Vector3(-1.8 * asleep + 12.0 * look_up + 19.0 * growl,
		-13.0 * asleep + 1.2 * look_up, -3.5 * asleep)
	p.head_angles = Vector3(3.0 * asleep + 4.0 * look_up + 11.5 * growl,
		-4.0 * asleep, -1.5 * asleep)
	p.jaw = 0.07 * look_up + 0.70 * growl
	p.lamp_power = _ramp(INTRO_SLEEP_TIME, 2.46, t)

	# The tail rests in a shallow curve and follows the hips as they rise.
	p.tail_lift = 13.0 * folded + 3.0 * asleep - 3.0 * growl
	p.sweep_tail_yaw.resize(_tails.size())
	for i in _tails.size():
		var curl := 1.0 - _ramp(2.55 + i * 0.035, 3.20 + i * 0.035, t)
		p.sweep_tail_yaw[i] = (10.0 - 0.9 * i) * curl + 0.65 * growl

	# The forepaws plant first. The hind paws stay in their resting stance until the chest takes the weight.
	var rest := [Vector3(-0.27, 0.0, -1.18), Vector3(-0.48, 0.0, -0.76),
		Vector3(-0.29, 0.0, -1.06), Vector3(-0.23, 0.0, -0.61)]
	var starts := [1.90, 2.57, 2.21, 2.84]
	var yaw := [5.5, 13.0, -6.0, -2.5]
	for i in 4:
		var start: float = starts[i]
		var end := start + (0.30 if i % 2 == 0 else 0.28)
		_step(p, i, rest[i], Vector3.ZERO, start, end, 0.19 if i % 2 == 0 else 0.13, t)
		p.paw_yaw[i] = yaw[i] * (1.0 - _ramp(start, end, t))
	p.signal_name = "休眠" if t < INTRO_SLEEP_TIME else "苏醒"


func _gait(p: Pose, t: float, trot: bool) -> void:
	var period := 0.72 if trot else WALK_PERIOD
	var speed := 4.55 if trot else WALK_SPEED
	var support := 0.56 if trot else 0.66
	var phases := [0.0, 0.5, 0.5, 0.0] if trot else [0.0, 0.22, 0.50, 0.72]
	var cycle := t / period
	p.position.z = -speed * t
	p.chest.y = (-0.18 if trot else -0.28) + cos(cycle * TAU * 2.0) * (0.15 if trot else 0.068)
	p.chest_angles = Vector3(sin(cycle * TAU * 2.0) * (2.6 if trot else 1.6),
		sin(cycle * TAU) * 3.0, sin(cycle * TAU) * (2.3 if trot else 1.8))
	p.hip_angles.y = -sin(cycle * TAU) * 4.0
	p.neck_angles.x = -p.chest_angles.x * 0.78
	p.tail_sweep = sin(cycle * TAU - 0.9) * (13.0 if trot else 8.0)
	for i in 4:
		var leg_cycle: float = cycle + phases[i]
		var step_number := floorf(leg_cycle)
		var local := leg_cycle - step_number
		var first: float = -speed * period * (step_number - phases[i] + support * 0.5)
		var swing := clampf(inverse_lerp(support, 1.0, local), 0.0, 1.0)
		p.paw_positions[i].z += first - speed * period * smoothstep(0.0, 1.0, swing)
		var flight := _lift(swing, 0.54 if trot else 0.36)
		p.paw_positions[i].y += flight
		p.paw_angles[i] = sin(swing * TAU) * minf(15.0, flight * 19.0)


func _sprint(p: Pose, t: float) -> void:
	var cycle := t / SPRINT_PERIOD
	var phase := fposmod(cycle, 1.0)
	var left_fore: float = SPRINT_LAND_PHASES[0]
	var right_fore: float = SPRINT_LAND_PHASES[2]
	var right_hind: float = SPRINT_LAND_PHASES[3]
	const SUPPORT := 0.26
	var stride := SPRINT_SPEED * SPRINT_PERIOD
	# The shoulders yield under the forefeet before the hind pair drives the next stride.
	var receive := _pulse(left_fore, 0.67, 0.75, 0.91, phase)
	var drive := _pulse(right_hind, 0.35, 0.42, left_fore, phase)
	var extended := _lift(inverse_lerp(right_hind + SUPPORT, left_fore, phase), 0.12)
	var folded := _lift(inverse_lerp(right_fore + SUPPORT, 1.0, phase), 0.065)
	var gather := cos((phase + 0.03) * TAU)
	var fore_load := _pulse(left_fore, 0.56, 0.65, left_fore + SUPPORT, phase) \
		- _pulse(right_fore, 0.76, 0.85, right_fore + SUPPORT, phase)
	var hind_load := _pulse(0.0, 0.05, 0.14, SUPPORT, phase) \
		- _pulse(right_hind, 0.24, 0.32, right_hind + SUPPORT, phase)
	p.position.z = -SPRINT_SPEED * t
	p.chest = Vector3(-0.09 * fore_load - 0.045 * hind_load,
		-0.32 - 0.20 * receive + 0.12 * drive + extended + folded,
		0.12 * gather - 0.16 * receive)
	p.chest_angles = Vector3(3.9 * drive - 4.2 * receive, 2.5 * gather, 2.5 * fore_load + 0.9 * hind_load)
	p.hip_angles = Vector3(5.8 * gather - 7.4 * drive, -2.8 * gather, 1.5 * hind_load - 1.3 * fore_load)
	p.neck_angles.x = -0.75 * p.chest_angles.x + 1.8
	p.head_angles.x = -1.3
	p.tail_lift = -5.5 + 5.0 * sin((phase - 0.13) * TAU)
	p.tail_sweep = 8.0 * sin((phase - 0.20) * TAU)
	for i in 4:
		var land_phase: float = SPRINT_LAND_PHASES[i]
		var elapsed := cycle - land_phase
		var step_number := floorf(elapsed)
		var first := -stride * (step_number + land_phase + 0.5 * SUPPORT)
		var swing := clampf(inverse_lerp(SUPPORT, 1.0, elapsed - step_number), 0.0, 1.0)
		var flight := _lift(swing, 0.62 if i % 2 == 0 else 0.87)
		p.paw_positions[i] += Vector3(0, flight, first - stride * smoothstep(0.0, 1.0, swing))
		p.paw_angles[i] = sin(swing * TAU) * minf(16.0, flight * 17.0)


static func sprint_footfalls(clip: String, before: float, after: float) -> PackedInt32Array:
	var feet := PackedInt32Array()
	if clip == "run_pounce":
		after = minf(after, RUN_IN)
	elif clip != "sprint":
		return feet
	if after <= before:
		return feet
	for i in SPRINT_LAND_PHASES.size():
		var land_phase: float = SPRINT_LAND_PHASES[i]
		var previous_stride := floori(before / SPRINT_PERIOD - land_phase + 0.000001)
		var current_stride := floori(after / SPRINT_PERIOD - land_phase + 0.000001)
		for stride in range(previous_stride + 1, current_stride + 1):
			feet.append(i)
	return feet


static func impact_shake(clip: String, before: float, after: float) -> float:
	var cue: Array = IMPACT_SHAKES.get(clip, [])
	if cue.is_empty():
		return 0.0
	var at: float = cue[0]
	return cue[1] if before < at and after >= at else 0.0


static func cannon_floor_range(source: Vector3, direction: Vector3, floor_y: float) -> float:
	return maxf(0.0, (source.y - floor_y) / -direction.y) if direction.y < -0.000001 else INF


func _high_pounce(p: Pose, t: float) -> void:
	var tension := _pulse(0.06, 0.42, 0.46, 0.63, t)
	var push := _pulse(0.44, LEAP_TAKEOFF, 0.61, 0.84, t)
	var settle := _pulse(1.54, 1.70, 1.82, LEAP_DURATION, t)
	var arc := clampf(inverse_lerp(LEAP_TAKEOFF, LEAP_CONTACT, t), 0.0, 1.0)
	var height := 4.45 * 4.0 * arc * (1.0 - arc)
	var spread := _pulse(0.76, 1.23, 1.49, 1.76, t)
	var rear_fold := _pulse(0.61, 0.98, 1.37, 1.70, t)
	var travel := -19.5
	p.position = Vector3(0.0, height, travel * smoothstep(0.0, 1.0, arc))
	p.chest = Vector3(0, -0.63 * tension + 0.14 * push - 0.61 * settle,
		0.38 * tension - 0.20 * settle - 0.08 * _ramp(1.58, 1.80, t))
	p.chest_angles.x = 2.0 * tension + 17.0 * push - 11.0 * spread - 6.0 * settle
	p.hip_angles.x = 10.0 * tension - 8.0 * push + 8.0 * rear_fold - 5.0 * settle
	p.neck_angles.x = -3.0 * tension - 11.0 * push + 7.0 * spread + 10.0 * settle
	p.head_angles.x = 2.0 * push - 4.0 * spread
	p.tail_lift = 5.0 * tension - 13.0 * push - 7.0 * rear_fold
	p.tail_sweep = 8.0 * _pulse(0.61, 1.10, 1.40, 1.91, t)
	p.jaw = 0.57 * _pulse(0.43, 1.01, 1.43, 1.66, t)
	for i in 4:
		var front := i % 2 == 0
		var lag := 0.025 if i < 2 else 0.0
		if front:
			var lead := _lift(inverse_lerp(0.41 + lag, 0.81 + lag, t), 0.75)
			var plant := _ramp(1.27 + lag, LEAP_CONTACT, t)
			var reach := lerpf(1.22 * spread, 0.90, plant)
			var splay := lerpf(0.30 * spread, 0.28, plant) * signf(_rest_feet[i].x)
			p.paw_positions[i] += Vector3(splay, height + lead, p.position.z - reach)
			p.paw_angles[i] = 13.0 * _pulse(0.44 + lag, 0.55 + lag, 0.68, 0.91, t) - 14.0 * spread
			p.paw_angles[i] *= clampf((height + lead) * 3.0, 0.0, 1.0)
		else:
			var catch := _lift(inverse_lerp(1.56 + lag, 1.78 + lag, t), 0.39)
			var reach := 0.86 * _pulse(0.56, 0.72, 1.30, 1.62, t)
			p.paw_positions[i] += Vector3(0, height + 0.90 * rear_fold + catch,
				p.position.z + reach - 1.13 * rear_fold)
			p.paw_angles[i] = 16.0 * rear_fold
	p.flash = _pulse(0.30, 0.49, 1.65, 1.94, t)
	p.impact = _pulse(LEAP_CONTACT, 1.65, 1.68, 2.04, t)
	p.impact_position = (_rest_feet[0] + _rest_feet[2]) * 0.5 + Vector3(0, 0, travel - 0.90)
	p.impact_scale = 2.05
	_warn(p, "pounce", 0.30, 1.83, t)


func _run_pounce(p: Pose, t: float) -> void:
	if t < RUN_IN:
		_sprint(p, t)
		return
	var local := t - RUN_IN
	_high_pounce(p, local)
	var run_out := Vector3(0, 0, -RUN_APPROACH_DISTANCE)
	p.position += run_out
	p.impact_position += run_out
	for i in 4:
		p.paw_positions[i] += run_out
	if local >= LEAP_TAKEOFF:
		var flight_time := LEAP_CONTACT - LEAP_TAKEOFF
		var flight := clampf(inverse_lerp(LEAP_TAKEOFF, LEAP_CONTACT, local), 0.0, 1.0)
		var carry := RUN_LEAP_SPEED * flight_time * flight * pow(1.0 - flight, 2.0)
		p.position.z -= carry
		for i in 4:
			p.paw_positions[i].z -= carry
	else:
		var u := local / LEAP_TAKEOFF
		var u2 := u * u
		var u3 := u2 * u
		# Brake over the whole gather and carry forward velocity into takeoff.
		var ease_to := (3.0 * u2 - 2.0 * u3) * RUN_GATHER_DISTANCE
		var entry_carry := (u3 - 2.0 * u2 + u) * SPRINT_SPEED * LEAP_TAKEOFF
		var launch_carry := (u3 - u2) * RUN_LEAP_SPEED * 0.44 * LEAP_TAKEOFF
		var travel := ease_to + entry_carry + launch_carry
		p.position.z += RUN_GATHER_DISTANCE - travel
	const GATHER_TIME := 0.41
	if local >= GATHER_TIME:
		return
	var run := Pose.new()
	run.paw_positions = _rest_feet.duplicate()
	_sprint(run, RUN_IN)
	var u := local / GATHER_TIME
	var blend := smoothstep(0.0, 1.0, u)
	p.chest = run.chest.lerp(p.chest, blend)
	p.chest_angles = run.chest_angles.lerp(p.chest_angles, blend)
	p.hip_angles = run.hip_angles.lerp(p.hip_angles, blend)
	p.neck_angles = run.neck_angles.lerp(p.neck_angles, blend)
	p.head_angles = run.head_angles.lerp(p.head_angles, blend)
	p.tail_lift = lerpf(run.tail_lift, p.tail_lift, blend)
	p.tail_sweep = lerpf(run.tail_sweep, p.tail_sweep, blend)
	for i in 4:
		var start: float = [0.0, 0.10, 0.025, 0.14][i]
		var finish: float = [0.22, 0.36, 0.34, GATHER_TIME][i]
		var step := clampf(inverse_lerp(start, finish, local), 0.0, 1.0)
		p.paw_positions[i] = run.paw_positions[i].lerp(p.paw_positions[i], smoothstep(0.0, 1.0, step))
		p.paw_positions[i].y += _lift(step, 0.30 if i % 2 == 0 else 0.62)
		p.paw_angles[i] = lerpf(run.paw_angles[i], p.paw_angles[i], step)


func sample_cannon(t: float, turn_degrees: float) -> Pose:
	var p := Pose.new()
	p.paw_positions = _rest_feet.duplicate()
	_back_cannon(p, t, turn_degrees)
	return p


func _back_cannon(p: Pose, t: float, turn_degrees := 0.0) -> void:
	p.yaw = turn_degrees * _ramp(0.06, 0.73, t)
	p.cannon_hatches = _pulse(CANNON_OPEN, 0.36, CANNON_STOW, CANNON_STOW + 0.22, t)
	p.cannon_raise = _pulse(0.35, CANNON_SEATED, CANNON_STOW - 0.25, CANNON_STOW, t)
	p.cannon_extend = _pulse(0.59, CANNON_CHARGE, CANNON_RELEASE + 0.09, CANNON_RELEASE + 0.32, t)
	p.cannon_pitch = -10.9 * _pulse(0.82, CANNON_LOCK, CANNON_RELEASE, CANNON_RELEASE + 0.20, t)
	p.cannon_power = _ramp(CANNON_CHARGE, CANNON_FIRE, t) * (1.0 - _ramp(CANNON_RELEASE - 0.05, CANNON_RELEASE + 0.28, t))
	p.cannon_heat = clampf(inverse_lerp(CANNON_CHARGE, CANNON_FIRE, t), 0.0, 1.0)
	p.cannon_heat *= 1.0 - _ramp(CANNON_RELEASE, CANNON_STOW + 0.16, t)
	p.cannon_charging = t >= CANNON_CHARGE and t < CANNON_FIRE
	p.cannon_locked = t >= CANNON_LOCK and t < CANNON_FIRE
	p.cannon_shot = _pulse(CANNON_FIRE, CANNON_FIRE + 0.022, CANNON_RELEASE - 0.19, CANNON_RELEASE, t)
	p.cannon_recoil = _pulse(CANNON_FIRE, CANNON_FIRE + 0.035, CANNON_FIRE + 0.13, CANNON_FIRE + 0.36, t)
	var brace := _pulse(0.06, 0.62, CANNON_RELEASE + 0.05, CANNON_DURATION - 0.07, t)
	var latch := _pulse(CANNON_SEATED - 0.045, CANNON_SEATED + 0.02, CANNON_SEATED + 0.045, 0.82, t)
	p.chest = Vector3(0, -0.46 * brace - 0.115 * latch, 0.22 * brace + 0.059 * latch)
	p.chest_angles.x = 2.1 * brace
	p.neck_angles.x = -6.0 * brace
	p.head_angles.x = 2.0 * brace
	p.hip_angles.x = 2.9 * brace
	p.tail_lift = 4.2 * brace
	var starts := [0.05, 0.28, 0.17, 0.39]
	var return_delays := [0.29, 0.66, 0.44, 0.12]
	var turn := Basis(Vector3.UP, deg_to_rad(turn_degrees))
	for i in 4:
		var front := i % 2 == 0
		var shift := Vector3(signf(_rest_feet[i].x) * 0.23, 0, -0.33 if front else 0.31)
		var turned_rest := turn * _rest_feet[i] - _rest_feet[i]
		var braced := turned_rest + turn * shift
		var start: float = starts[i if turn_degrees >= 0.0 else (i + 2) % 4]
		var recover: float = CANNON_RELEASE + return_delays[i]
		if t < recover:
			_step(p, i, Vector3.ZERO, braced, start, start + 0.26, 0.24, t)
		else:
			_step(p, i, braced, turned_rest, recover, recover + 0.28, 0.132, t)
		p.paw_yaw[i] = turn_degrees * _ramp(start, start + 0.26, t)
	if t < CANNON_CHARGE:
		p.signal_name = "背甲展开"
	elif t < CANNON_LOCK:
		p.signal_name = "背炮蓄力"
	elif p.cannon_locked:
		p.signal_name = "炮口锁向"
	elif t < CANNON_RELEASE:
		p.signal_name = "激光发射"
	elif t < CANNON_STOW + 0.23:
		p.signal_name = "背炮收回"


func sample_turn(t: float, degrees: float) -> Pose:
	var p := Pose.new()
	p.paw_positions = _rest_feet.duplicate()
	_turn(p, t, degrees)
	return p


func sample_reposition(t: float, direction: Vector3) -> Pose:
	var p := Pose.new()
	p.paw_positions = _rest_feet.duplicate()
	_reposition(p, t, direction)
	return p


func _reposition(p: Pose, t: float, direction: Vector3) -> void:
	var travel := direction * REPOSITION_DISTANCE
	var lateral := direction.x != 0.0
	p.position = travel * (_ramp(0.045, 0.86, t) if lateral else _ramp(0.10, 0.99, t))
	p.chest.y = -0.18 * _pulse(0.02, 0.24, 0.83, REPOSITION_TIME, t)
	p.neck_angles.x = -2.0 * _pulse(0.06, 0.24, 0.80, REPOSITION_TIME, t)
	var starts := [0.16, 0.025, 0.37, 0.58]
	if lateral:
		starts = [0.17, 0.04, 0.48, 0.60] if direction.x < 0.0 else [0.48, 0.60, 0.17, 0.04]
	for i in 4:
		_step(p, i, Vector3.ZERO, travel, starts[i], starts[i] + 0.29, 0.27, t)


func sample_flank_leap(t: float, hop: Vector3, retreat: Vector3, turn_degrees: float) -> Pose:
	var p := Pose.new()
	p.paw_positions = _rest_feet.duplicate()
	_flank_leap(p, t, hop, retreat, turn_degrees)
	return p


func _flank_leap(p: Pose, t: float, hop: Vector3, retreat: Vector3, turn_degrees: float) -> void:
	var side := signf(hop.x)
	var load := _pulse(0.0, 0.092, 0.133, 0.23, t)
	var push := _pulse(0.10, 0.157, 0.201, 0.32, t)
	var catch := _pulse(FLANK_LEAP_LAND - 0.035, 0.51, 0.56, 0.70, t)
	var arc := _ramp(0.136, FLANK_LEAP_LAND + 0.074, t)
	var first := _ramp(0.54, 0.92, t)
	var second := _ramp(0.92, 1.26, t)
	var landed_yaw := turn_degrees * 0.76
	p.position = hop * arc + retreat * (first + second) * 0.5
	p.position.y = _lift(inverse_lerp(0.151, 0.534, t), 0.93)
	p.yaw = landed_yaw * _ramp(0.165, 0.53, t) + (turn_degrees - landed_yaw) * (first + second) * 0.5
	var step_weight := _pulse(0.56, 0.68, 0.75, 0.91, t) - _pulse(0.93, 1.04, 1.13, 1.30, t)
	p.chest = Vector3(-side * 0.19 * load + side * 0.12 * push,
		-0.43 * load + 0.18 * push - 0.48 * catch - 0.14 * absf(step_weight), 0.17 * catch)
	p.chest_angles = Vector3(4.5 * push - 4.0 * catch, turn_degrees * (0.095 * push + 0.035 * step_weight),
		-side * (5.5 * load - 7.0 * push + 5.3 * catch))
	p.hip_angles = Vector3(7.0 * load - 7.0 * push + 4.0 * catch, -turn_degrees * 0.075 * push,
		-side * 3.8 * catch)
	p.neck_angles = Vector3(-4.0 * push + 4.8 * catch, turn_degrees * 0.12 *
		_pulse(0.04, 0.20, 0.32, 0.64, t), 0.0)
	p.tail_sweep = -side * (31.0 * push - 10.5 * catch) - turn_degrees * 0.16 * step_weight
	p.tail_lift = -8.0 * push + 5.5 * catch
	var land_basis := Basis(Vector3.UP, deg_to_rad(landed_yaw))
	var mid_yaw := lerpf(landed_yaw, turn_degrees, 0.5)
	var mid_basis := Basis(Vector3.UP, deg_to_rad(mid_yaw))
	var end_basis := Basis(Vector3.UP, deg_to_rad(turn_degrees))
	for i in 4:
		var rest := _rest_feet[i]
		var front := i % 2 == 0
		var leading := rest.x * side > 0.0
		var off := (0.104 if leading else 0.127) if front else (0.155 if leading else 0.174)
		var land := (FLANK_LEAP_LAND if leading else 0.483) if front else (0.51 if leading else 0.534)
		var diagonal := (i == 0 or i == 3) if side > 0.0 else (i == 2 or i == 1)
		var step1 := 0.544 if diagonal else 0.685
		var step2 := 0.905 if diagonal else 1.035
		if t < step1:
			var u := clampf(inverse_lerp(off, land, t), 0.0, 1.0)
			var progress := smoothstep(0.0, 1.0, u)
			var tuck := sin(u * PI)
			var yaw := landed_yaw * progress
			var paw := Basis(Vector3.UP, deg_to_rad(yaw)) * (rest - Vector3(rest.x * 0.11, 0, rest.z * 0.05) * tuck)
			p.paw_positions[i] = paw + hop * progress + Vector3.UP * _lift(u, 1.18 if front else 1.30)
			p.paw_yaw[i] = yaw
		elif t < step2:
			var start := hop + land_basis * rest - rest
			var half := hop + retreat * 0.5 + mid_basis * rest - rest
			_step(p, i, start, half, step1, step1 + 0.198, 0.29 if front else 0.37, t)
			p.paw_yaw[i] = lerpf(landed_yaw, mid_yaw, _ramp(step1, step1 + 0.198, t))
		else:
			var half := hop + retreat * 0.5 + mid_basis * rest - rest
			var end := hop + retreat + end_basis * rest - rest
			_step(p, i, half, end, step2, step2 + 0.206, 0.27 if front else 0.34, t)
			p.paw_yaw[i] = lerpf(mid_yaw, turn_degrees, _ramp(step2, step2 + 0.206, t))
	p.signal_name = "侧跳" if t < 0.54 else "后撤"


func _turn(p: Pose, t: float, degrees := 55.0) -> void:
	p.yaw = degrees * _ramp(0.11, 1.59, t)
	p.chest.y = -0.30 * _pulse(0.0, 0.30, 1.31, 1.79, t)
	p.chest_angles.y = 5.5 * _pulse(0.06, 0.45, 0.90, 1.48, t)
	p.hip_angles.y = -5.0 * _pulse(0.15, 0.56, 0.77, 1.48, t)
	p.neck_angles.y = 12.0 * _pulse(0.0, 0.26, 0.57, 1.17, t)
	p.tail_sweep = -12.0 * _pulse(0.2, 0.65, 0.95, 1.65, t)
	var starts := [0.16, 0.77, 0.43, 1.00]
	var finishes := [0.57, 1.20, 0.91, 1.49]
	var scale := degrees / 55.0
	p.chest_angles.y *= scale
	p.hip_angles.y *= scale
	p.neck_angles.y *= scale
	p.tail_sweep *= scale
	var turn := Basis(Vector3.UP, deg_to_rad(degrees))
	for i in 4:
		var step := i if degrees >= 0.0 else (i + 2) % 4
		_step(p, i, Vector3.ZERO, turn * _rest_feet[i] - _rest_feet[i],
			starts[step], finishes[step] + 0.08, 0.42, t)
		p.paw_yaw[i] = degrees * _ramp(starts[step], finishes[step] + 0.08, t)


func sample_rush_turn(t: float, degrees: float) -> Pose:
	var p := Pose.new()
	p.paw_positions = _rest_feet.duplicate()
	_rush_turn(p, t, degrees)
	return p


func _rush_turn(p: Pose, t: float, degrees: float) -> void:
	var side := signf(degrees)
	var load := _pulse(0.01, 0.105, 0.136, 0.23, t)
	var push := _pulse(0.105, 0.166, 0.19, 0.30, t)
	var catch := _pulse(RUSH_TURN_LAND - 0.025, 0.57, 0.60, RUSH_TURN_TIME, t)
	var twist := _pulse(0.08, 0.23, 0.38, 0.57, t)
	p.yaw = degrees * _ramp(0.12, 0.575, t)
	p.position.y = _lift(inverse_lerp(0.147, 0.565, t), 0.79)
	p.chest = Vector3(-side * (0.10 * load + 0.16 * catch), -0.47 * load + 0.17 * push - 0.50 * catch, 0.13 * load - 0.13 * push)
	p.chest_angles = Vector3(5.0 * push - 6.5 * catch, side * 6.6 * twist, side * (3.0 * push - 4.2 * catch))
	p.hip_angles = Vector3(7.5 * load - 7.0 * push + 4.5 * catch, -side * 5.1 * twist, side * 2.4 * push)
	p.neck_angles = Vector3(-2.9 * push + 7.0 * catch, side * 10.0 * twist, 0.0)
	p.tail_lift = -7.0 * push + 3.0 * catch
	p.tail_sweep = -side * 25.0 * twist
	p.flash = _ramp(0.12, 0.22, t) * 0.85
	for i in 4:
		var front := i % 2 == 0
		var paw := _rest_feet[i]
		var outer := paw.x * side > 0.0
		var off := (0.106 if outer else 0.128) if front else (0.172 if outer else 0.156)
		var down := (RUSH_TURN_LAND if outer else RUSH_TURN_LAND + 0.038) if front else (0.588 if outer else 0.612)
		var swing := clampf(inverse_lerp(off, down, t), 0.0, 1.0)
		var follow := _ramp(off, off + 0.085, t)
		var reach := _ramp(down - 0.105, down, t)
		var paw_yaw := lerpf(p.yaw * follow, degrees, reach)
		var tuck := sin(PI * swing)
		paw += Vector3(-paw.x * 0.10, 0.0, -paw.z * 0.10) * tuck
		p.paw_positions[i] = Basis(Vector3.UP, deg_to_rad(paw_yaw)) * paw
		p.paw_positions[i].y += _lift(swing, 1.02 if front else 1.15)
		p.paw_yaw[i] = paw_yaw


func _windup_motion_time(time: float, strike: float) -> float:
	return time - MELEE_WINDUP_EXTENSION * smoothstep(0.0, strike + MELEE_WINDUP_EXTENSION, time)


func _sweep(p: Pose, time: float) -> void:
	var t := _windup_motion_time(time, SWEEP_STRIKE)
	var wind := _pulse(0.03, 0.41, 0.48, 0.67, t)
	var cut := _pulse(0.44, 0.76, 0.84, 1.52, t)
	var advance := Vector3(0.32, 0, -4.45)
	p.position = advance * _ramp(0.28, 0.83, t)
	p.chest = Vector3(-wind * 0.24 + cut * 0.32, -0.29 * wind - cut * 0.38, -0.32 * cut)
	p.chest_angles = Vector3(-wind * 2.2 + 2.0 * cut, -14.0 * wind + 23.0 * cut, 3.2 * cut - 4.3 * wind)
	p.hip_angles.y = 6.0 * wind - 7.0 * cut
	p.neck_angles = Vector3(-2.0 * wind - 1.2 * cut, -14.0 * wind + 16.0 * cut, 0)
	p.head_angles.y = -4.5 * wind + 8.0 * cut
	p.jaw = 0.49 * _pulse(0.28, 0.58, 0.74, 1.21, t)
	p.jaw_cut = _pulse(0.49, 0.58, 0.77, 0.91, t)
	p.tail_sweep = -17.0 * cut + 9.0 * wind
	var starts := [0.46, 0.28, 0.29, 0.53]
	var ends := [0.82, 0.58, 0.73, 0.88]
	for i in 4:
		var lead := Vector3(0.67, 0, -0.32) if i == 2 else Vector3.ZERO
		if t < 1.03:
			_step(p, i, Vector3.ZERO, advance + lead, starts[i], ends[i], 0.25 if i == 2 else 0.22, t)
		else:
			_step(p, i, advance + lead, advance, 1.03, 1.45, 0.17 if i == 2 else 0.0, t)
	p.flash = _pulse(0.12, 0.24, 0.62 + MELEE_WINDUP_EXTENSION, 0.85 + MELEE_WINDUP_EXTENSION, time)
	_warn(p, "head", 0.29, 0.83 + MELEE_WINDUP_EXTENSION, time)


func _stomp(p: Pose, time: float) -> void:
	var t := _windup_motion_time(time, STOMP_STRIKE)
	var weight := _pulse(0.05, 0.43, 0.64, 1.20, t)
	var impact := _pulse(0.67, 0.80, 0.87, 1.24, t)
	var advance := Vector3(0.49, 0, -2.05)
	p.position = advance * _ramp(0.31, 0.91, t)
	p.chest = Vector3(-0.33 * weight + 0.26 * impact, -0.44 * weight - 0.41 * impact, -0.19 * impact)
	p.chest_angles = Vector3(-4.2 * impact, -5.0 * weight + 5.4 * impact, -5.2 * weight + 4.5 * impact)
	p.neck_angles.x = 5.5 * impact
	p.jaw = 0.29 * impact
	var supports := [0.76, 0.64, 0.0, 0.86]
	for i: int in [0, 1, 3]:
		var start: float = supports[i]
		_step(p, i, Vector3.ZERO, advance, start, start + 0.35, 0.21, t)
	var plant := advance + Vector3(0.70, 0, -0.64)
	if t < 1.15:
		_step(p, 2, Vector3.ZERO, plant, 0.27, 0.75, 1.17, t)
		var lift := 1.12 * _pulse(0.16, 0.49, 0.59, 0.75, t)
		p.paw_positions[2].y = _rest_feet[2].y + lift
		p.paw_angles[2] = clampf(p.paw_angles[2], -lift * 18.0, lift * 18.0)
	else:
		_step(p, 2, plant, advance, 1.15, 1.56, 0.12, t)
	p.flash = _pulse(0.14, 0.27, 0.78 + MELEE_WINDUP_EXTENSION, 1.04 + MELEE_WINDUP_EXTENSION, time)
	p.impact = _pulse(0.744, 0.779, 0.80, 1.14, t)
	p.impact_position = _rest_feet[2] + plant + Vector3(0, -0.25, -0.75)
	if time >= STOMP_STRIKE + MELEE_WINDUP_EXTENSION:
		p.stomp_wave = 1.0 - _ramp(STOMP_WAVE_END - 0.09, STOMP_WAVE_END + 0.23, time)
		p.stomp_radius = stomp_radius_at(time)
	_warn(p, "paw", 0.30, STOMP_WAVE_END, time)


static func stomp_radius_at(time: float) -> float:
	return lerpf(1.65, STOMP_WAVE_RADIUS,
		smoothstep(STOMP_STRIKE + MELEE_WINDUP_EXTENSION, STOMP_WAVE_END - 0.025, time))


func sample_aimed_pounce(clip: String, t: float, turn_degrees: float) -> Pose:
	var p := sample(clip, t)
	var takeoff := SHORT_POUNCE_TAKEOFF if clip == "pounce" else LEAP_TAKEOFF
	if t >= takeoff or is_zero_approx(turn_degrees):
		return p
	# The attack frame points along the leap. Start with the previous heading
	# and move the feet into line before the body leaves the floor.
	var initial := -turn_degrees
	var turn := Basis(Vector3.UP, deg_to_rad(initial))
	p.yaw = initial * (1.0 - _ramp(0.01, takeoff - 0.04, t))
	var starts := [0.04, 0.15, 0.10, 0.21]
	for i in 4:
		var step := i if turn_degrees >= 0.0 else (i + 2) % 4
		var phase := clampf(inverse_lerp(starts[step], starts[step] + 0.29, t), 0.0, 1.0)
		var unturned := 1.0 - smoothstep(0.0, 1.0, phase)
		p.paw_positions[i] += (turn * _rest_feet[i] - _rest_feet[i]) * unturned
		p.paw_positions[i].y += _lift(phase, 0.17) * absf(turn_degrees) / 29.0
		p.paw_yaw[i] = initial * unturned
	return p


func _pounce(p: Pose, t: float) -> void:
	var crouch := _pulse(0.05, 0.60, 0.69, 0.89, t)
	var arc := _lift(inverse_lerp(0.74, 1.24, t), 0.62)
	var land := _pulse(1.13, 1.26, 1.31, 1.71, t)
	var travel := Vector3(0, 0, -7.35)
	p.position = travel * _ramp(0.77, 1.19, t)
	p.chest = Vector3(0, -0.60 * crouch + arc - 0.47 * land, 0.17 * crouch)
	p.chest_angles.x = 4.1 * crouch + 4.5 * arc - 3.7 * land
	p.hip_angles.x = 5.0 * crouch - 4.8 * arc
	p.neck_angles.x = -4.3 * crouch - 1.8 * arc + 5.6 * land
	p.jaw = 0.54 * _pulse(0.49, 0.93, 1.14, 1.58, t)
	p.tail_lift = 6.0 * crouch - 8.0 * arc
	for i in 4:
		var front := i % 2 == 0
		var lag := 0.018 if i < 2 else 0.0
		_step(p, i, Vector3.ZERO, travel, (SHORT_POUNCE_TAKEOFF if front else 0.785) + lag,
			(1.19 if front else 1.255) + lag, 0.99 if front else 0.78, t)
	p.flash = _pulse(0.66, 0.73, 0.91, 1.24, t)
	p.impact = _pulse(1.18, 1.23, 1.25, 1.55, t)
	p.impact_position = (p.paw_positions[0] + p.paw_positions[2]) * 0.5
	_warn(p, "pounce", 0.39, 1.34, t)


func _tail(p: Pose, time: float, direction: float) -> void:
	var t := _windup_motion_time(time, TAIL_STRIKE) + TAIL_SWEEP_TIME_CUT * _ramp(TAIL_CONTACT_BEGIN, TAIL_CONTACT_END, time)
	var weight := _pulse(0.06, 0.39, 1.11, 1.78, t)
	var shoulder := direction * _sweep_turn(t + 0.035)
	var hip := direction * _sweep_turn(t + 0.065)
	p.position.x = 0.20 * hip
	p.chest = Vector3(-0.16 * shoulder, -0.40 * weight, 0.12 * weight)
	p.chest_angles = Vector3(0.0, 11.0 * shoulder, 2.5 * hip)
	p.hip_angles = Vector3(2.5 * weight, 22.0 * hip, -3.5 * hip)
	p.neck_angles.y = -9.0 * shoulder
	p.tail_lift = 9.0 * weight
	p.sweep_tail_yaw.resize(_tails.size())
	var degrees := [59.0, 22.0, 19.0, 15.0, 12.0, 8.0, 6.0, 4.0, 3.0]
	for i in _tails.size():
		p.sweep_tail_yaw[i] = direction * degrees[i] * _sweep_turn(t - float(i) * 0.016)
	for i in 4:
		var front := i % 2 == 0
		var side := signf(_rest_feet[i].x)
		var lead := side == direction
		var shift := Vector3(side * (0.20 if front else 0.40), 0, -0.17 if front else 0.21)
		var start := 0.24 if front else 0.10
		var stagger := 0.0 if lead else 0.15
		var recover := 1.20 + stagger + (0.12 if front else 0.0)
		_attack_step(p, i, shift, start + stagger, start + stagger + 0.19,
			recover, recover + 0.26, 0.23, t)
	p.flash = _ramp(0.12, 0.24, time) * (1.0 - _ramp(1.02, 1.24, t))
	_warn(p, "tail", 0.26, TAIL_CONTACT_END, time)


func _sweep_turn(t: float) -> float:
	for i in TAIL_TURN_KEYS.size() - 1:
		var a: Vector3 = TAIL_TURN_KEYS[i]
		var b: Vector3 = TAIL_TURN_KEYS[i + 1]
		if t <= b.x:
			var u := clampf(inverse_lerp(a.x, b.x, t), 0.0, 1.0)
			var duration := b.x - a.x
			# Keep the angular velocity continuous through the rear centerline.
			var tangent := a.z * (1.0 - u) - b.z * u
			return lerpf(a.y, b.y, smoothstep(0.0, 1.0, u)) + duration * u * (1.0 - u) * tangent
	return 0.0


static func tail_sweep_direction(clip: String) -> float:
	match clip:
		"tail":
			return 1.0
		"tail_left":
			return -1.0
	return 0.0


func tail_sweep_side_distance(point: Vector3, direction: float) -> float:
	var parent := model.get_parent_node_3d()
	var relative := point if parent == null else parent.to_local(point)
	return (origin.affine_inverse() * relative).x * direction


func tail_sweep_overlaps(clip: String, time: float, target_bottom: Vector3,
		target_top: Vector3, target_radius: float) -> bool:
	var direction := tail_sweep_direction(clip)
	if direction == 0.0:
		return false
	var window: Array = CONTACT_WINDOWS[clip][0]
	if time < window[1] or time > window[2]:
		return false
	# The sweep is assigned to one side of the boss, including its rear centerline.
	if tail_sweep_side_distance((target_bottom + target_top) * 0.5, direction) < -0.00001:
		return false
	var points: PackedVector3Array = model.tail_contact_path()
	var reach: float = float(window[3]) * model.global_basis.x.length() + target_radius
	for i in points.size() - 1:
		var closest := Geometry3D.get_closest_points_between_segments(points[i], points[i + 1], target_bottom, target_top)
		if closest[0].distance_squared_to(closest[1]) <= reach * reach:
			return true
	return false


func _charge(p: Pose, t: float) -> void:
	p.charge = clampf(t / PhaseState.CHARGE_TIME, 0.0, 1.0)
	p.signal_name = "视野充能"


func enter_phase(p: Pose, t: float) -> void:
	var gather := _pulse(0.0, 0.13, 0.16, 0.31, t)
	var lift := _pulse(0.16, 0.30, 0.32, PhaseState.ENTER_TIME, t)
	p.chest += Vector3(0, -0.50 * gather + 0.17 * lift, 0.28 * gather)
	p.chest_angles.x += -4.0 * gather + 5.0 * lift
	p.hip_angles.x += 5.0 * gather - 2.8 * lift
	p.neck_angles.x += 5.0 * gather - 4.0 * lift
	p.phase = _ramp(0.18, 0.45, t)
	p.charge = 1.0 - p.phase
	p.burst = _pulse(0.15, 0.20, 0.24, PhaseState.ENTER_TIME, t)
	p.release_age = clampf((t - 0.15) / 0.33, 0.0, 1.0)
	p.fin = 0.90 * _ramp(0.03, 0.37, t)
	p.signal_name = "满充 · 转入虚化"


func phase_roar(p: Pose, t: float) -> void:
	var inhale := _pulse(0.01, 0.34, 0.39, 0.69, t)
	var raised := _pulse(0.23, 0.99, 2.30, ROAR_DURATION, t)
	var first := _pulse(0.40, 0.93, 1.38, 1.96, t)
	var second := 0.72 * _pulse(1.56, 1.99, 2.24, 2.76, t)
	var voice := maxf(first, second)
	var vibration := sin(TAU * 5.5 * t) * voice
	p.chest += Vector3(0, -0.23 * inhale + 0.34 * raised + 0.063 * voice + 0.025 * vibration, -0.11 * raised)
	p.chest_angles.x += -3.8 * inhale + 7.0 * raised
	p.hip_angles.x += 5.6 * inhale - 4.5 * raised
	p.neck_angles.x += -6.0 * inhale + 25.0 * raised + 1.55 * vibration
	p.head_angles.x += -3.0 * inhale + 15.5 * raised + 2.0 * voice + 0.80 * vibration
	p.jaw = maxf(p.jaw, 0.13 * raised + 0.78 * voice + 0.048 * vibration)
	p.tail_lift -= 6.0 * raised
	p.phase = 1.0
	p.fin = 0.90 + 0.10 * voice
	p.burst = maxf(p.burst, 0.14 * voice)
	p.signal_name = "虚化 · 仰天咆哮"


func return_from_phase(p: Pose, t: float) -> void:
	var settle := _pulse(0.05, 0.27, 0.31, PhaseState.RETURN_TIME, t)
	p.phase = 1.0 - _ramp(0.0, 0.40, t)
	p.fin = 0.9 * p.phase
	p.chest += Vector3(0, -0.35 * settle, 0.14 * settle)
	p.neck_angles.x += 7.0 * settle
	p.hip_angles.x += 3.0 * settle
	p.signal_name = "复实"


static func phase_rate(clip: String) -> float:
	match clip:
		"walk", "trot", "turn", "sprint":
			return PHASE_MOVE_RATE
		"sweep", "stomp", "pounce", "tail", "tail_left", "phase", "high_pounce", "run_pounce":
			return PHASE_ATTACK_RATE
	return 1.0


static func phase_sequence_slot(t: float) -> Vector2:
	var local := maxf(0.0, t - PHASE_FIGHT_START)
	for i in PHASE_SEQUENCE.size():
		var action: Array = PHASE_SEQUENCE[i]
		var duration: float = action[2] / action[3]
		if local < duration:
			return Vector2(i, local * action[3])
		local -= duration
	return Vector2(PHASE_SEQUENCE.size(), local)


func _phase_cycle(t: float) -> Pose:
	if t < PhaseState.CHARGE_TIME:
		return sample("charge", t)
	if t < PHASE_FIGHT_START:
		return sample("phase_enter", t - PhaseState.CHARGE_TIME)
	var slot := phase_sequence_slot(t)
	var index := int(slot.x)
	var shift := Vector3.ZERO
	for i in index:
		var done: Array = PHASE_SEQUENCE[i]
		shift += sample(done[0], done[2]).position
	var p: Pose
	if t >= PHASE_FIGHT_END:
		p = sample("phase_exit", t - PHASE_FIGHT_END)
	elif index < PHASE_SEQUENCE.size():
		var action: Array = PHASE_SEQUENCE[index]
		p = sample(action[0], slot.y)
		p.signal_name = "虚化 · " + action[1]
	else:
		p = sample("idle", slot.y)
		p.signal_name = "虚化"
	if t < PHASE_FIGHT_END:
		p.phase = 1.0
		p.fin = maxf(0.90, p.fin)
		p.signal_name += "  %.1f 秒" % (PHASE_FIGHT_END - t)
	p.position += shift
	p.impact_position += shift
	for i in p.paw_positions.size():
		p.paw_positions[i] += shift
	p.marker = ""
	return p


func _phase(p: Pose, t: float) -> void:
	var brace := _pulse(0.0, 0.14, 0.20, 0.35, t)
	var first := Vector3(1.93, 0, -0.31)
	var final := Vector3(3.82, 0, -0.80)
	p.position = first * _ramp(0.27, 0.59, t) + (final - first) * _ramp(0.53, 0.95, t)
	var prep_head := _pulse(0.76, 1.05, 1.10, 1.30, t)
	var cut := _pulse(1.08, 1.39, 1.43, 1.70, t)
	var prep_tail := _pulse(1.54, 1.84, 1.93, 2.13, t)
	var tail_cut := _pulse(1.89, 2.23, 2.43, 2.81, t)
	var landed := _pulse(2.92, 3.20, 3.31, 3.99, t)
	p.phase = 1.0
	p.fin = 0.90
	var push := _pulse(0.23, 0.40, 0.82, 1.16, t)
	p.chest = Vector3(0.26 * cut - 0.18 * prep_head,
		-0.30 * brace - 0.22 * push - 0.36 * cut - 0.34 * landed,
		0.09 * brace - 0.30 * cut)
	p.chest_angles = Vector3(-2.2 * brace - 2.6 * landed,
		-14 * prep_head + 21 * cut - 10 * tail_cut, 4.5 * cut - 4.0 * prep_head - 3.7 * push)
	p.hip_angles.x = 2.0 * brace
	p.hip_angles.y = -13 * prep_tail + 27 * tail_cut
	p.neck_angles = Vector3(1.2 * cut - 0.4 * brace + 3.6 * landed,
		-14 * prep_head + 16 * cut - 10 * tail_cut, 0.0)
	p.head_angles = Vector3(2.4 * brace, 8.0 * cut, 0.0)
	p.jaw = 0.55 * _pulse(0.96, 1.21, 1.43, 1.62, t)
	p.jaw_cut = _pulse(1.09, 1.19, 1.40, 1.53, t)
	p.delayed_tail.resize(_tails.size())
	for i in _tails.size():
		var q := t - float(i) * 0.018
		var coil := -33 * _pulse(1.53, 1.85, 1.93, 2.14, q)
		p.delayed_tail[i] = -12 * cut + coil + 70 * _pulse(1.89, 2.23, 2.43, 2.81, q)
	p.tail_lift = 7.2 * tail_cut
	for i in 4:
		var early := i == 0 or i == 3
		var settle := 0.54 if early else 0.69
		if t < settle:
			_step(p, i, Vector3.ZERO, first, 0.25 if early else 0.39, settle, 0.40, t)
		else:
			_step(p, i, first, final, settle + 0.06, 0.92 if early else 1.04, 0.33, t)
		if t >= 2.70:
			var is_front := i % 2 == 0
			_step(p, i, final, final, 2.79 if is_front else 2.94, 3.12 if is_front else 3.24,
				0.15 if is_front else 0.11, t)
	if t >= 1.04 and t < 1.69:
		_attack_step(p, 2, Vector3(0.64, 0, -0.56), 1.04, 1.32, 1.48, 1.69, 0.28, t, final)
	if t >= 1.70 and t < 2.62:
		_attack_step(p, 3, Vector3(0.79, 0, 0.37), 1.70, 2.09, 2.39, 2.62, 0.31, t, final)
	p.flash = maxf(_pulse(1.10, 1.17, 1.25, 1.41, t), _pulse(1.94, 2.02, 2.12, 2.34, t))
	p.signal_name = "虚化交叉扫"
	_warn(p, "head", 0.67, 1.47, t)
	_warn(p, "tail", 1.66, 2.29, t)


func _attack_step(p: Pose, i: int, shift: Vector3, a: float, b: float, c: float,
		d: float, height: float, t: float, base := Vector3.ZERO) -> void:
	if t < c:
		_step(p, i, base, base + shift, a, b, height, t)
	else:
		_step(p, i, base + shift, base, c, d, height * 0.55, t)


func _warn(p: Pose, kind: String, start: float, end: float, t: float) -> void:
	if t >= start and t <= end:
		p.marker = kind
