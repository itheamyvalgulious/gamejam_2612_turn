extends Node3D
## VESPER v2 — procedural blue-white four-legged assault frame.
##
## Generated 100% from code: meshes, materials, rig, motion.  No imported assets
## and no AnimationPlayer keyframes.  Every pose is a closed-form function of
## time, velocity, gait phase and combat timeline.
##
## v2 changes
##   * 2.00 m tall (real metres), compact 0.5 m stance radius, legs near-straight
##     at rest (knee interior ~137 deg instead of 90 deg)
##   * blue/white all-metal surfaces, black asymmetric mask with one blue camera
##   * medieval flat plasma greatsword with an energy crossguard
##   * gimballed vector thruster backpack, forward / lateral dashes
##   * bone-chain + SpringBoneSimulator3D hair (blue/white, wind + motion)
##   * four front attacks (mirrored pair + mirrored risers), side thrust,
##     back thrust, overhead heavy, 360-degree spin
##
## Locomotion: analytic gait clock + two-bone leg IK (law of cosines)
## Combat:     weapon-space pose keys, two-bone arm IK solved every frame so
##             both fists track the hilt, 360-degree waist spin, blade ribbons.

const MK = preload("res://scripts/mech/mesh_kit.gd")
const MAT = preload("res://scripts/mech/materials.gd")
const BB = preload("res://scripts/mech/body_builder.gd")
const Trail = preload("res://scripts/mech/blade_trail.gd")
const FX = preload("res://scripts/world/fx.gd")

signal footstep(world_pos: Vector3, strength: float)
signal impact(world_pos: Vector3, strength: float)
signal attack_started(label: String, heavy: bool)

# ---------------------------------------------------------------- proportions
# Source of truth: body_builder.gd P.  Kept here as typed constants for the
# animation maths (all metres).
const HIP_Y := 1.235
const HIP_R := 0.30
const FEMUR := 0.60
const TIBIA := 0.66
const FOOT_R := 0.50
const ANKLE_H := 0.08
const WAIST_Y := 0.12
const TORSO_SCALE := 1.107  # P.torso_scale 0.82 * P.upper_scale 1.35
const UPPER := 0.452
const FORE := 0.422
const GRIP := 0.16
const BLADE_Y0 := 0.28
const BLADE_LEN := 1.28

const WALK_SPEED := 2.2
const RUN_SPEED := 5.6
const SPRINT_SPEED := 7.6
const TAU := PI * 2.0
const GRAVITY := 18.0
const JUMP_SPEED := 6.3
const TAKEOFF_TIME := 0.20
const LAND_TIME := 0.58
## Authored clip times run this much faster than wall clock.  Keeps every
## trajectory/key/hit window in attack_data.gd as the single source of truth.
const ATTACK_RATE := 1.5
## body_builder.P proportions: upper body is uniformly enlarged, lower body
## uniformly shrunk.  Kept here so motion maths stays in the right space.
const UPPER_SCALE := 1.35
const LOWER_SCALE := 0.78

const LEG_AZ := [45.0, 135.0, 225.0, 315.0]

const BASE_POSE := {
	"ty": 0.0, "tx": 0.0, "tz": 0.0, "hy": 0.04, "hx": -0.02,
	"crouch": 0.0, "lean": 0.0, "offhand": 0.0, "left_raise": 0.0,
	# Low-ready guard: hilt ~20 deg above horizontal, blade pointing forward.
	# wrx -1.222 rad puts hilt_y at (0, sin 20deg, -cos 20deg).
	"wpx": 0.18, "wpy": 0.15, "wpz": -0.40,
	"wrx": -1.222, "wry": 0.0, "wrz": 0.08,
}

## Elbow "pole" overrides (torso space, direction only).  Only the two side
## thrusts need one: there both fists sit on the same hilt on ONE side of the
## body, so the left arm has to cross over the right one and the two forearms
## would otherwise intersect.  The left elbow is parked up-forward (forearm
## passes above the right forearm) and the right elbow down-forward.  Chosen by
## sweeping the elbow direction around the shoulder->grip axis and maximising
## the clearance to the other forearm / hand, the chest and the blade.
const CROSS_POLES := {
	"SIDE_THRUST_R": {
		"L": Vector3(-1.10, 1.90, -0.85), "R": Vector3(1.60, -0.60, -0.60),
	},
	"SIDE_THRUST_L": {
		"L": Vector3(-1.95, 0.10, -0.30), "R": Vector3(1.90, -0.55, -0.35),
	},
}

# ---------------------------------------------------------------- public state
var move_command := Vector3.ZERO       # desired world-space velocity (XZ)
var speed := 0.0
var strafe := 0.0
var gait_sign := 1.0
var lock_heading := false
var display_speed := 0.0
var heading := 0.0
var angular_velocity := 0.0
var gait_phase := 0.0
var locomotion_state := "IDLE"
var attack_name := ""
var combo_step := 0
var is_attacking := false
var attack_time := 0.0
var dash_time := 0.0
var jump_state := "GROUND"
var jump_t := 0.0
var vertical_velocity := 0.0
var air_time := 0.0
var time := 0.0
var auto_step := true
var vfx_root: Node3D

# ---------------------------------------------------------------- node refs
var body: Node3D
var lower_body: Node3D
var torso: Node3D
var head: Node3D
var head_camera: Node3D
var head_green_dot: MeshInstance3D
var lens_material: ShaderMaterial
var lens_light: OmniLight3D
var reactor_ring: Node3D
var chest_light: OmniLight3D
var thruster_light: OmniLight3D
var weapon_root: Node3D
var weapon_spin: Node3D
var weapon_light: OmniLight3D
var blade_base: Marker3D
var blade_tip: Marker3D
var blade_trail
var contact_shadow: MeshInstance3D
var legs: Array = []
var arms: Array = []
var pauldrons: Array = []
var thruster_nodes: Array = []
var engine_petals: Array = []
var left_indicator_meshes: Array = []
var hair
var hair_anchor: Node3D

var _attack: Dictionary = {}
var _attack_queue: Array = []
var _clips: Dictionary = {}
var _dash_dir := Vector3.FORWARD
var _dash_cooldown := 0.0
var _yaw_rate := 0.0
var _shake_sent := {}
var _lunge_prev := 0.0
var _carry_w := 0.0
var _fx: Node3D
var _attack_style := "twohand"
var _onehand := 0.0
var _left_raise := 0.0
var _smooth_pose: Dictionary = {}
var _torso_turn_offset := 0.0
var _offhand_cur := 0.0
var _special := ""
var _special_w := 0.0
var _iris := 0.0

# actdemo-facing knobs kept at defaults so the same rig can be vendored later
var jump_vel := JUMP_SPEED
var grav := GRAVITY
var takeoff_time := TAKEOFF_TIME
var land_time := LAND_TIME
var dash_distance := 2.0
var dash_duration := 0.28
var dash_cd := 0.50
var accel_rate := 18.0
var decel_rate := 26.0
var turn_rate := 12.0
var facing_override := false
var facing_heading := 0.0
var face_rate := 7.0
var vfx_enabled := false

func _ready() -> void:
	_fx = FX.new()
	_fx.name = "FX"
	_fx.top_level = true
	add_child(_fx)
	_fx.global_transform = Transform3D.IDENTITY
	vfx_root = _fx
	_clips = _load_clips()
	BB.build(self)
	_build_hair()
	blade_trail = Trail.new()
	blade_trail.name = "GreatswordTrail"
	_fx.add_child(blade_trail)
	heading = rotation.y
	_update_legs(1.0 / 60.0, 0.0)
	_update_arms(BASE_POSE)
	_update_thrusters(0.0)
	if auto_step:
		set_process(true)


func _process(delta: float) -> void:
	if auto_step:
		advance(minf(delta, 0.05))


func _load_clips() -> Dictionary:
	var out := {}
	var ad = load("res://scripts/mech/attack_data.gd")
	if ad == null:
		push_error("attack_data.gd missing")
		return out
	for n in ["FRONT_R", "FRONT_L", "RISE_R", "RISE_L",
			"SIDE_THRUST_R", "SIDE_THRUST_L", "BACK_THRUST", "HEAVY", "SPIN"]:
		var c: Dictionary = ad.get_clip(n)
		out[String(c["name"])] = c
	return out


func _build_hair() -> void:
	var hair_script = load("res://scripts/mech/hair.gd")
	if hair_script == null:
		return
	hair = hair_script.new()
	hair.name = "Hair"
	var parent: Node3D = hair_anchor if hair_anchor != null else head
	parent.add_child(hair)
	hair.setup(head, {})


# ============================================================== attack input
func request_light_attack() -> void:
	if jump_state != "GROUND":
		return
	if is_attacking:
		if combo_step < 4 and _attack_queue.is_empty():
			_attack_queue.append(combo_step + 1)
		return
	combo_step = 1
	_begin_attack(_clip("FRONT_R"), false)


## QA / demo helper: start a specific front attack (1..4).
func request_front_attack(index: int) -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	var names := ["FRONT_R", "FRONT_L", "RISE_R", "RISE_L"]
	combo_step = clampi(index, 1, 4)
	_begin_attack(_clip(names[combo_step - 1]), false)


func request_side_attack(side := 1.0) -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	combo_step = 0
	_begin_attack(_clip("SIDE_THRUST_L" if side < 0.0 else "SIDE_THRUST_R"), false)


func request_back_attack() -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	combo_step = 0
	_begin_attack(_clip("BACK_THRUST"), true)


func request_heavy_attack() -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	combo_step = 0
	_begin_attack(_clip("HEAVY"), true)


func request_spin_attack() -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	combo_step = 0
	_begin_attack(_clip("SPIN"), true)


## local_dir is in the character's local space; default = forward (-Z).
func request_dash(local_dir := Vector3(0, 0, -1)) -> void:
	if jump_state != "GROUND" or _dash_cooldown > 0.0 or is_attacking:
		return
	var d := local_dir
	if d.length_squared() < 0.001:
		d = Vector3(0, 0, -1)
	_dash_dir = (global_transform.basis * d.normalized())
	_dash_dir.y = 0.0
	_dash_dir = _dash_dir.normalized()
	dash_time = dash_duration
	_dash_cooldown = dash_cd
	impact.emit(global_position + Vector3(0, 0.2, 0), 0.2)


func request_jump() -> void:
	if jump_state != "GROUND" or is_attacking or dash_time > 0.0:
		return
	jump_state = "TAKEOFF"
	jump_t = 0.0
	vertical_velocity = 0.0
	air_time = 0.0


func _clip(n: String) -> Dictionary:
	if _clips.has(n):
		return _clips[n]
	# fallback so a missing data file never hard-crashes
	return {
		"name": n, "duration": 0.8, "trail": [0.18, 0.44],
		"keys": [{"t": 0.0, "p": {}}, {"t": 0.8, "p": {}}],
		"lunge": [[0.0, 0.0], [0.8, 0.5]], "hit_at": 0.32,
		"hit_kind": "air", "style": "twohand",
	}


func _advance_jump(dt: float) -> void:
	match jump_state:
		"TAKEOFF":
			jump_t += dt
			if jump_t >= takeoff_time:
				jump_state = "AIR"
				jump_t = 0.0
				vertical_velocity = jump_vel
				air_time = 0.0
				if vfx_enabled:
					_fx.footstep(global_position, 0.45)
		"AIR":
			air_time += dt
			vertical_velocity -= grav * dt
			position.y += vertical_velocity * dt
			if position.y <= 0.0 and vertical_velocity < 0.0:
				position.y = 0.0
				jump_state = "LANDING"
				jump_t = 0.0
				vertical_velocity = 0.0
				if vfx_enabled:
					_fx.land(global_position, 1.0)
				impact.emit(global_position + Vector3(0, 0.12, 0), 0.75)
		"LANDING":
			jump_t += dt
			if jump_t >= land_time:
				jump_state = "GROUND"
				jump_t = 0.0


func _begin_attack(data: Dictionary, heavy: bool) -> void:
	_attack = data
	is_attacking = true
	attack_name = String(data["name"])
	attack_time = 0.0
	# Prepend the LIVE smoothed pose as the clip's first key.  The flat
	# low-ready idle sits far from authored key-0 poses (side thrusts ~0.3 m
	# on the tip), so blending "idle -> clip" at rate 110 used to launch the
	# blade through a whip (tip accel ~4000 vs the 3315 reference).  With the
	# first key = where the body actually is, the clip's own PCHIP starts at
	# zero velocity and the transition is authored, bounded and C1-smooth.
	_attack = data.duplicate()
	var keys: Array = _attack.get("keys", []).duplicate(true)
	if not keys.is_empty():
		var snap: Dictionary = _smooth_pose.duplicate() if not _smooth_pose.is_empty() else BASE_POSE.duplicate()
		snap.merge(keys[0].get("p", {}), true)   # authored t0 channels still win
		keys[0] = {"t": 0.0, "p": snap}
		_attack["keys"] = keys
	_attack_style = String(data.get("style", "twohand"))
	_special = attack_name
	_onehand = 1.0 if _attack_style == "side_r" else 0.0
	_left_raise = 1.0 if _attack_style == "side_r" else 0.0
	_lunge_prev = 0.0
	_shake_sent.clear()
	attack_started.emit(attack_name, heavy)
	var tw: Array = data.get("trail", [0.0, 1.0])
	if blade_trail != null:
		blade_trail.begin(self, blade_base, blade_tip, tw[0], tw[1])


func advance(dt: float) -> void:
	dt = clampf(dt, 0.0, 0.05)
	var start_pos := position
	time += dt
	_dash_cooldown = maxf(0.0, _dash_cooldown - dt)
	_advance_jump(dt)

	# ---------------- locomotion
	var moving := move_command.length() > 0.05
	var target_speed := move_command.length()
	if is_attacking:
		target_speed *= 0.10
		moving = false
	if dash_time > 0.0:
		target_speed = 0.0
		moving = false
	var accel := accel_rate if speed < target_speed else decel_rate
	speed = move_toward(speed, target_speed, accel * dt)
	if dash_time > 0.0:
		speed = 0.0

	if moving:
		if lock_heading:
			angular_velocity = 0.0
		else:
			var desired := move_command.normalized()
			var target_heading := atan2(-desired.x, -desired.z)
			if facing_override:
				target_heading = facing_heading
			var turn_speed := lerpf(turn_rate * 0.42, turn_rate, clampf(speed / RUN_SPEED, 0.0, 1.0))
			if facing_override:
				turn_speed = face_rate
			var before := heading
			heading = lerp_angle(heading, target_heading, 1.0 - exp(-turn_speed * dt))
			angular_velocity = wrapf(heading - before, -PI, PI) / maxf(dt, 0.0001)
	else:
		if facing_override:
			var before_f := heading
			heading = lerp_angle(heading, facing_heading, 1.0 - exp(-face_rate * dt))
			angular_velocity = wrapf(heading - before_f, -PI, PI) / maxf(dt, 0.0001)
		else:
			angular_velocity = lerpf(angular_velocity, 0.0, 1.0 - exp(-8.0 * dt))
	rotation.y = heading
	_yaw_rate = lerpf(_yaw_rate, angular_velocity, 1.0 - exp(-6.0 * dt))

	var forward := -global_transform.basis.z
	var vel := forward * speed
	# Movement follows the input vector, never the facing alone: S must
	# backpedal and A/D must strafe even while the body is locked forward.
	if move_command.length() > 0.05:
		vel = move_command.normalized() * speed
	if speed > 0.08 and move_command.length() > 0.05:
		var local_move := global_transform.basis.inverse() * move_command
		strafe = clampf(local_move.x / maxf(speed, 0.1), -1.0, 1.0)
		gait_sign = signf(-local_move.z)
		if absf(gait_sign) < 0.05:
			gait_sign = 1.0
	if is_attacking and _attack.has("lunge"):
		var lunge := _eval_curve(_attack["lunge"], attack_time)
		var d := lunge - _lunge_prev
		_lunge_prev = lunge
		position += forward * d
		vel += forward * (d / maxf(dt, 0.0001))
	if dash_time > 0.0:
		var dash_t := 1.0 - dash_time / maxf(dash_duration, 0.01)
		# integral of the old curve is ~9.92; convert distance to a scale
		var dash_speed := (18.0 * pow(1.0 - dash_t, 1.6) + 3.0) \
			* (dash_distance / maxf(9.923 * dash_duration, 0.001))
		# direction is fixed for the whole dash: forward and lateral dashes are
		# distinct authored inputs, not a steering blend.
		var dash_step := minf(dt, dash_time)
		position += _dash_dir * dash_speed * dash_step
		dash_time = maxf(0.0, dash_time - dash_step)
	if not is_attacking:
		position += vel * dt

	var flat := Vector2(position.x, position.z)
	if flat.length() > 15.0:
		flat = flat.normalized() * 15.0
		position.x = flat.x
		position.z = flat.y

	# ---------------- gait clock
	var run_amt := clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	var freq := lerpf(1.55, 2.75, clampf(speed / RUN_SPEED, 0.0, 1.0))
	if speed > 0.08 and jump_state != "AIR" and jump_state != "LANDING":
		gait_phase = fmod(gait_phase + freq * dt, 1.0)
	locomotion_state = "IDLE"
	if speed > 0.4:
		locomotion_state = "WALK"
	if speed > WALK_SPEED:
		locomotion_state = "RUN"
	if speed > RUN_SPEED + 0.4:
		locomotion_state = "SPRINT"
	if is_attacking:
		locomotion_state = "STRIKE"
	if dash_time > 0.0:
		locomotion_state = "DASH"
	if jump_state == "TAKEOFF":
		locomotion_state = "JUMP"
	elif jump_state == "AIR":
		locomotion_state = "AIRBORNE"
	elif jump_state == "LANDING":
		locomotion_state = "LANDING"

	# ---------------- attack timeline
	if is_attacking:
		attack_time += dt * ATTACK_RATE
		if not _attack_queue.is_empty() and attack_time >= float(_attack["duration"]) * 0.70:
			var nxt: int = _attack_queue.pop_front()
			combo_step = nxt
			var names := ["", "FRONT_R", "FRONT_L", "RISE_R", "RISE_L"]
			_begin_attack(_clip(names[nxt]), false)
		elif attack_time >= float(_attack["duration"]):
			# A full spin ends facing the same direction.  Fold the extra 2π
			# into a persistent offset so the recovery never unwinds backwards.
			if attack_name == "SPIN":
				_torso_turn_offset += TAU
				if _smooth_pose.has("ty"):
					_smooth_pose["ty"] = float(_smooth_pose["ty"]) - TAU
			is_attacking = false
			attack_name = ""
			combo_step = 0
			_attack_queue.clear()
			_lunge_prev = 0.0
			_attack_style = "twohand"
			_onehand = 0.0
			_left_raise = 0.0

	# Special IK poles fade in/out with the clip: switching them instantly at
	# clip start/end snapped the elbow by up to 0.6 m in one frame.  The two
	# side thrusts rely on their CROSS_POLES being nearly in place before the
	# hilt reaches full extension, so they converge a bit faster.
	var sp_target := 1.0 if (is_attacking and _special != "") else 0.0
	var sp_rate := 13.0 if CROSS_POLES.has(_special) else 9.0
	_special_w = lerpf(_special_w, sp_target, 1.0 - exp(-sp_rate * dt))

	# ---------------- body mechanics
	var lean_speed := clampf(speed / RUN_SPEED, 0.0, 1.2) * 0.17
	var bob_amp := lerpf(0.006, 0.026, run_amt) * clampf(speed / 1.2, 0.0, 1.0)
	var bob := sin((gait_phase * 2.0 + 0.13) * TAU) * bob_amp
	if speed < 0.4:
		bob = sin(time * 1.35) * 0.007
	if jump_state == "AIR" or jump_state == "LANDING":
		bob = 0.0
	var stance_count := 0
	for leg in legs:
		if leg["down"]:
			stance_count += 1
	if jump_state != "AIR" and jump_state != "LANDING":
		bob += (1.0 - clampf(stance_count / 4.0, 0.0, 1.0)) * lerpf(0.006, 0.020, run_amt)
	var lat := clampf(strafe, -1.0, 1.0)
	var bank := clampf(_yaw_rate * speed * 0.020, -0.24, 0.24) \
		+ lat * 0.12 * clampf(speed / RUN_SPEED, 0.0, 1.0)
	var sway := sin(gait_phase * TAU) * lerpf(0.004, 0.010, run_amt)

	var carry_target := smoothstep(0.0, 1.0, clampf((speed - 0.5) / 2.0, 0.0, 1.0))
	_carry_w = lerpf(_carry_w, carry_target, 1.0 - exp(-3.2 * dt))
	var pose := _current_pose(dt)
	var body_y := HIP_Y * LOWER_SCALE - float(pose["crouch"]) * LOWER_SCALE + bob
	if dash_time > 0.0:
		var dt_n := 1.0 - dash_time / maxf(dash_duration, 0.01)
		body_y -= 0.10 * sin(PI * clampf(dt_n, 0.0, 1.0))
	body.position = Vector3(0, body_y, 0)
	body.rotation = Vector3(-(lean_speed + float(pose["lean"])), sway, bank)
	torso.rotation = Vector3(pose["tx"], float(pose["ty"]) + _torso_turn_offset, pose["tz"])
	head.rotation = Vector3(pose["hx"], pose["hy"], 0)
	_update_weapon(pose)
	_update_arms(pose)
	if contact_shadow != null:
		contact_shadow.position.y = 0.012 - position.y
		var hgt := maxf(position.y, 0.0)
		var sh_scale := 1.0 + hgt * 0.14
		contact_shadow.scale = Vector3(sh_scale, 1.0, sh_scale)
		contact_shadow.transparency = clampf(hgt * 0.16, 0.0, 0.55)

	# head look / idle life
	if not is_attacking:
		var look := clampf(_yaw_rate * 0.16, -0.22, 0.22)
		head.rotation.y = lerpf(head.rotation.y, look + sin(time * 0.7) * 0.035, 1.0 - exp(-4.0 * dt))
		head.rotation.x += sin(time * 0.9 + 1.0) * 0.010

	if reactor_ring != null:
		reactor_ring.rotation.y += dt * lerpf(0.25, 2.4, clampf(speed / RUN_SPEED, 0.0, 1.0))
		reactor_ring.rotation.x = sin(time * 0.6) * 0.05

	_update_legs(dt, run_amt)
	_update_thrusters(dt)
	_update_indicators(dt)
	if hair != null:
		hair.update(dt, self)
	_update_trail(dt)
	_update_fx(dt)
	_fx.advance(dt)
	# 光学镜头始终在呼吸/扫描，与打击特效开关无关
	if lens_material != null:
		var pulse := 1.0 + 0.12 * sin(time * 2.6) * sin(time * 0.7 + 1.3)
		var focus := 0.30
		if is_attacking:
			var flare := smoothstep(0.10, 0.30, attack_time) * (1.0 - smoothstep(0.55, 0.80, attack_time))
			pulse += 0.55 * flare
			focus = lerpf(0.30, 0.16, flare)
		lens_material.set_shader_parameter("intensity", 1.75 * pulse)
		lens_material.set_shader_parameter("pupil_radius", focus)
		lens_material.set_shader_parameter("phase", time * 0.35)
	if lens_light != null:
		lens_light.light_energy = 0.65 + 0.25 * sin(time * 2.3)
	var moved := position.distance_to(start_pos)
	display_speed = lerpf(display_speed, moved / maxf(dt, 0.0001), 0.55)


func dash_direction_is_forward() -> bool:
	var f := -global_transform.basis.z
	f.y = 0.0
	return _dash_dir.dot(f.normalized()) > 0.75


func _current_pose(dt: float) -> Dictionary:
	var pose := BASE_POSE.duplicate()
	var breath := sin(time * 1.25)
	pose["tx"] = float(pose["tx"]) + breath * 0.010
	pose["wpx"] = float(pose["wpx"]) + sin(time * 0.8) * 0.004
	pose["wrx"] = float(pose["wrx"]) + sin(time * 1.05) * 0.014
	pose["wrz"] = float(pose["wrz"]) + sin(time * 0.9) * 0.010
	if _carry_w > 0.01 and not is_attacking:
		var w := clampf(_carry_w, 0.0, 1.0)
		# Carry = the low-ready grip, bobbing with the gait.  The hilt stays
		# ~20 deg above horizontal; hands ride up a touch while moving.
		pose["wpx"] = lerpf(0.18, 0.18, w)
		pose["wpy"] = lerpf(0.15, 0.20, w) + sin(gait_phase * TAU) * 0.012 * w
		pose["wpz"] = lerpf(-0.40, -0.44, w)
		pose["wrx"] = lerpf(-1.222, -1.15, w)
		pose["wry"] = lerpf(0.0, -0.10, w)
		pose["wrz"] = lerpf(0.08, 0.02, w)
		pose["ty"] = float(pose["ty"]) + sin(gait_phase * TAU) * 0.05 * w
		pose["tx"] = float(pose["tx"]) + 0.04 * w
	if dash_time > 0.0:
		var t := 1.0 - dash_time / maxf(dash_duration, 0.01)
		pose["wrx"] = lerpf(-1.10, -0.90, sin(PI * t))
		pose["wpz"] = float(pose["wpz"]) - 0.06
		pose["lean"] = float(pose["lean"]) + 0.10 * sin(PI * t)
	if jump_state == "TAKEOFF":
		var u := clampf(jump_t / maxf(takeoff_time, 0.001), 0.0, 1.0)
		var c := sin(PI * u)
		pose["crouch"] = float(pose["crouch"]) + 0.34 * c
		pose["tx"] = float(pose["tx"]) - 0.12 * c
		pose["lean"] = float(pose["lean"]) + 0.06 * c
		pose["wpy"] = float(pose["wpy"]) - 0.10 * c
		pose["wpz"] = float(pose["wpz"]) - 0.03 * c
	elif jump_state == "AIR":
		var fall := clampf(-vertical_velocity / 6.0, 0.0, 1.0)
		pose["crouch"] = -0.02
		pose["tx"] = 0.09 * clampf(vertical_velocity / 6.0, -1.0, 1.0)
		pose["ty"] = -0.06
		pose["hy"] = 0.02
		pose["wpx"] = 0.16
		pose["wpy"] = 0.22 + 0.02 * sin(air_time * 5.0)
		pose["wpz"] = -0.42
		pose["wrx"] = -1.05 + 0.18 * fall
		pose["wry"] = 0.06
		pose["wrz"] = 0.16
		pose["lean"] = 0.03
	elif jump_state == "LANDING":
		var u2 := clampf(jump_t / maxf(land_time, 0.001), 0.0, 1.0)
		var c2 := 1.0 - smoothstep(0.0, 1.0, u2)
		pose["crouch"] = float(pose["crouch"]) + 0.30 * c2
		pose["tx"] = float(pose["tx"]) - 0.26 * c2
		pose["lean"] = float(pose["lean"]) + 0.09 * c2
		pose["wpx"] = lerpf(0.16, 0.18, u2)
		pose["wpy"] = lerpf(0.22, 0.15, u2)
		pose["wpz"] = lerpf(-0.42, -0.40, u2)
		pose["wrx"] = lerpf(-1.05, -1.222, u2)
		pose["wry"] = lerpf(0.06, 0.0, u2)
		pose["wrz"] = lerpf(0.16, 0.08, u2)
	if is_attacking:
		var kp := _evaluate_keys(attack_time)
		for k in kp.keys():
			pose[k] = kp[k]
		_apply_attack_overrides(pose, attack_time)
	# release weights blend in/out so one-hand attacks do not pop
	# idle / locomotion / non-attack actions: both hands hold the greatsword
	# (offhand = 0.0).  Only one-hand attacks (like BACK_THRUST) release the
	# left hand and raise it clear.
	pose["offhand"] = float(pose.get("offhand", 0.0)) if is_attacking else 0.0
	pose["left_raise"] = float(pose.get("left_raise", 0.0)) if is_attacking else 0.0

	# Continuous pose blend.  No action may teleport the hands or the hilt
	# between states; attacks use a fast blend, idle/jump a softer one.
	#
	# Attack ENTRY: the flat low-ready idle sits far from some clips' first
	# keys (side thrusts ~0.3 m on the tip), so a constant-rate exponential
	# converge launches the tip at err*rate in one step — a whip that pushed
	# blade-tip accel past the FRONT_R reference.  While the error is large
	# the effective rate is capped so the launch speed stays under ~10 u/s;
	# the cap releases automatically as the pose closes in on the clip.
	if _smooth_pose.is_empty():
		_smooth_pose = pose.duplicate()
	else:
		var rate := 110.0 if is_attacking else (14.0 if jump_state != "GROUND" or dash_time > 0.0 else 8.0)
		var k := 1.0 - exp(-rate * dt)
		for key in pose.keys():
			if _smooth_pose.has(key):
				_smooth_pose[key] = lerpf(float(_smooth_pose[key]), float(pose[key]), k)
			else:
				_smooth_pose[key] = pose[key]
		pose = _smooth_pose
	return pose


## Extra pose channels driven by the attack phase rather than keyframes.
func _apply_attack_overrides(pose: Dictionary, t: float) -> void:
	var st := _attack_style
	if st == "spin" and t >= 0.20 and t <= 1.16:
		# Continuous trapezoid over the authored 0.20 -> 1.16 spin window.
		# Outside this window the clip keys handle windup / recovery, so the
		# waist never snaps at attack start or end.
		var su := clampf((t - 0.20) / 0.96, 0.0, 1.0)
		pose["ty"] = lerpf(-0.52, TAU - 0.263, _spin_progress(su))
	# Only BACK_THRUST releases the left hand (it must raise clear so the blade
	# can pass underneath).  Every other clip — including both side thrusts —
	# keeps BOTH fists welded to the hilt.
	if attack_name != "BACK_THRUST":
		pose["offhand"] = 0.0
		pose["left_raise"] = 0.0


## Monotone cubic Hermite (PCHIP-style) over all keys of the active clip.
## The old per-segment quintic eased to zero velocity at *every* key, which made
## every attack feel like a chain of little stops.  Tangents are shared between
## neighbouring keys (C1 continuous) and limited so a channel never overshoots
## its authored values; only the first and last key have zero velocity.
func _evaluate_keys(t: float) -> Dictionary:
	if _attack.is_empty():
		return BASE_POSE.duplicate()
	var keys: Array = _attack.get("keys", [])
	if keys.is_empty():
		return BASE_POSE.duplicate()
	var seg := 0
	for i in keys.size() - 1:
		if t <= float(keys[i + 1]["t"]):
			seg = i
			break
	var a: Dictionary = keys[seg]
	var b: Dictionary = keys[seg + 1]
	var span: float = maxf(float(b["t"]) - float(a["t"]), 0.0001)
	var u: float = clampf((t - float(a["t"])) / span, 0.0, 1.0)
	var pa: Dictionary = BASE_POSE.duplicate()
	var pb: Dictionary = BASE_POSE.duplicate()
	pa.merge(a.get("p", {}), true)
	pb.merge(b.get("p", {}), true)
	var out := {}
	for ch in BASE_POSE.keys():
		var va := float(pa[ch])
		var vb := float(pb[ch])
		var m0 := _key_tangent(keys, seg, ch)
		var m1 := _key_tangent(keys, seg + 1, ch)
		var u2 := u * u
		var u3 := u2 * u
		var h00 := 2.0 * u3 - 3.0 * u2 + 1.0
		var h10 := u3 - 2.0 * u2 + u
		var h01 := -2.0 * u3 + 3.0 * u2
		var h11 := u3 - u2
		out[ch] = h00 * va + h10 * (m0 * span) + h01 * vb + h11 * (m1 * span)
	return out


## Fritsch-Carlson limited slope at key `i` for one pose channel (per clip second).
func _key_tangent(keys: Array, i: int, ch: String) -> float:
	var n := keys.size()
	if i <= 0 or i >= n - 1:
		return 0.0
	var vm := _key_value(keys, i - 1, ch)
	var vi := _key_value(keys, i, ch)
	var vp := _key_value(keys, i + 1, ch)
	var tm := float(keys[i - 1]["t"])
	var ti := float(keys[i]["t"])
	var tp := float(keys[i + 1]["t"])
	var dm := (vi - vm) / maxf(ti - tm, 0.0001)
	var dp := (vp - vi) / maxf(tp - ti, 0.0001)
	if dm * dp <= 0.0:
		return 0.0
	var lim := 3.0 * minf(absf(dm), absf(dp))
	return clampf(0.5 * (dm + dp), -lim, lim)


func _key_value(keys: Array, i: int, ch: String) -> float:
	var d: Dictionary = BASE_POSE.duplicate()
	d.merge(keys[i].get("p", {}), true)
	return float(d.get(ch, 0.0))


func preview_weapon_pose(override: Dictionary) -> void:
	var pose := BASE_POSE.duplicate()
	for k in override.keys():
		pose[k] = override[k]
	torso.rotation = Vector3(float(pose["tx"]), float(pose["ty"]), float(pose["tz"]))
	_update_weapon(pose)
	_update_arms(pose)


func _update_weapon(pose: Dictionary) -> void:
	if weapon_root == null:
		return
	var wz := float(pose["wpz"])
	var wy := float(pose["wpy"])
	# The front-of-chest clamp is blended IN/OUT instead of switched: switching
	# it instantly when a clip changes style used to teleport the hilt (idle
	# -0.56 -> back-thrust -0.40 in one frame).
	# NO hidden clamp here.  The old front-of-chest clamp jumped to -0.56 in
	# the first attack frame (idle is -0.37), which teleported the hilt forward
	# by ~0.19 m.  Every clip is authored to stay clear of the body instead.
	weapon_root.position = Vector3(float(pose["wpx"]), wy, wz)
	weapon_root.rotation = Vector3(float(pose["wrx"]), float(pose["wry"]), float(pose["wrz"]))


func _update_arms(pose: Dictionary) -> void:
	if weapon_root == null or arms.size() < 2:
		return
	var hilt_y := weapon_root.basis.y.normalized()
	var hilt_x := weapon_spin.basis.x.normalized()
	# FIXED GRIP CONVENTION — the right fist always takes the LOWER/pommel end
	# and the left fist the UPPER/forward end.  It never swaps: the old
	# SIDE_THRUST_L special case put the left hand on the forward grip, which
	# read as a mid-swing hand swap.
	var grip_r: Vector3 = weapon_root.transform * Vector3(0, -GRIP, 0)
	var grip_l: Vector3 = weapon_root.transform * Vector3(0, GRIP, 0)
	var offhand := clampf(float(pose.get("offhand", 0.0)), 0.0, 1.0)
	var raise := clampf(float(pose.get("left_raise", 0.0)), 0.0, 1.0)
	var off_idx := 1
	var hold_idx := 0
	var grips: Array = [grip_r, grip_l]
	# The holding hand stays welded to its grip.  During the back thrust the
	# right elbow is blended into the blade-normal plane so the forearm ends up
	# PERPENDICULAR to the sword (a real backhanded reverse grip) without the
	# elbow snapping when the left hand lets go.
	var perp_w := 0.0
	if attack_name == "BACK_THRUST":
		# The exact right-angle is required for the finished reverse grip; during
		# the horizontal sweep the arm uses its natural elbow and blends into the
		# perpendicular pose as the rotation completes.
		perp_w = smoothstep(0.62, 0.74, attack_time) * (1.0 - smoothstep(0.86, 0.98, attack_time))
	_solve_arm(arms[hold_idx], grips[hold_idx], hilt_y, hilt_x, perp_w)
	# The off hand either grips its end or drifts to a rest position up and out
	# on its own side, clear of the weapon's sweep.
	var target: Vector3 = grips[off_idx]
	if offhand > 0.01:
		var sgn := -1.0
		var sh: Vector3 = arms[off_idx]["shoulder"].position
		# low = just outside the hip; high = raised up-left, forward of the
		# shoulder so the blade can pass underneath the armpit.  Offsets are
		# scaled to the arm length (0.75x of the old 1.20 m arm) so the released
		# hand stays inside a comfortable elbow bend instead of locking straight.
		var low := sh + Vector3(sgn * 0.35, -0.040, -0.32)
		var high := sh + Vector3(sgn * 0.33, 0.61, -0.39)
		var rest := low.lerp(high, raise)
		# Swing the releasing hand OUTWARD while it travels: a straight lerp
		# between the hilt and the raised rest passes too close to the shoulder
		# and folds the elbow into the upper arm.
		var out_dir := Vector3(sgn, 0.0, 0.0)
		target = grips[off_idx].lerp(rest, offhand) + out_dir * (sin(PI * offhand) * 0.165)
	_solve_arm(arms[off_idx], target, hilt_y, hilt_x)
	_offhand_cur = offhand


func _solve_arm(arm: Dictionary, target: Vector3, hilt_y: Vector3, hilt_x: Vector3, perp_w := 0.0) -> void:
	var shoulder: Node3D = arm["shoulder"]
	var upper: float = arm["upper"]
	var fore: float = arm["fore"]
	var side: float = arm["side"]
	var S := shoulder.position
	var delta := target - S
	var dist := clampf(delta.length(), 0.10, upper + fore - 0.006)
	var dir := delta.normalized()
	var sw := clampf(_special_w, 0.0, 1.0)
	var pole: Vector3
	if side > 0.0:
		pole = Vector3(0.95, -0.85, -0.25)
	else:
		# Left elbow hangs low AND far outward for the idle low-ready grip
		# (-0.95,-0.55,-0.30), then blends to the authored flared pole
		# (+0.45 y) as _special_w ramps.  Pulling the idle pole out to -0.30 z
		# (backward) keeps the elbow clear of the right fist during the brief
		# mid-blend window of the side thrusts (measured -0.030 contact at
		# (-0.95,-0.55,-0.10) vs pass at -0.30).
		pole = Vector3(-0.95, lerpf(-0.55, 0.45, sw), lerpf(-0.30, 0.05, sw))
	# Per-clip elbow poles (see CROSS_POLES).  The weight ramps with _special_w,
	# so the elbow glides into and out of these directions instead of snapping.
	if CROSS_POLES.has(_special):
		var tbl: Dictionary = CROSS_POLES[_special]
		var key := "R" if side > 0.0 else "L"
		if tbl.has(key):
			pole = pole.lerp(tbl[key], sw)
	if _special == "BACK_THRUST":
		if side < 0.0 and _offhand_cur > 0.01:
			# Released left arm lives BEHIND/above the blade's sweep plane.
			pole = pole.lerp(Vector3(-0.70, 1.00, -0.30), sw * clampf(_offhand_cur, 0.0, 1.0))
		if side > 0.0:
			var rec := smoothstep(0.86, 0.96, attack_time)
			pole = pole.lerp(Vector3(1.05, 0.60, -0.80), sw * rec)
	var perp := pole - dir * pole.dot(dir)
	if perp.length_squared() < 0.001:
		perp = Vector3(side, 0, 0)
	perp = perp.normalized()
	var a := (upper * upper - fore * fore + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(upper * upper - a * a, 0.0))
	# Blend the POLE (not the elbow) toward the blade-normal solution: any pole
	# gives an exact two-bone reach, so the fist stays welded to the grip while
	# the elbow glides into the perpendicular pose.
	if perp_w > 0.001:
		var ep = _perp_elbow(arm, target, hilt_y)
		if ep != null:
			var pp: Vector3 = (ep as Vector3) - S
			pp = pp - dir * pp.dot(dir)
			if pp.length_squared() > 1e-6:
				perp = perp.slerp(pp.normalized(), clampf(perp_w, 0.0, 1.0))
	var elbow_pos := S + dir * a + perp * h
	_apply_arm(arm, target, dist, elbow_pos, hilt_y, hilt_x)


## Elbow position whose FOREARM is exactly perpendicular to the blade axis.
## Used by BACK_THRUST: the sword is flipped into a reverse grip, so the fist's
## last segment and the blade form a clean right angle.
func _perp_elbow(arm: Dictionary, target: Vector3, hilt_y: Vector3):
	var S: Vector3 = arm["shoulder"].position
	var upper: float = arm["upper"]
	var fore: float = arm["fore"]
	var d := target - S
	var dist := clampf(d.length(), 0.10, upper + fore - 0.006)
	if dist < d.length() - 1e-5:
		return null
	var u := hilt_y.normalized()
	var dp_raw := d - u * d.dot(u)
	var dpl := dp_raw.length()
	if dpl < 1e-5:
		return null
	var dp := dp_raw / dpl
	var e2 := u.cross(dp).normalized()
	# |E-S| = upper with E = H + v, v = fore*(cos*e1 + sin*e2), v.u = 0:
	#   dist^2 + 2*fore*cos*|d_perp| + fore^2 = upper^2
	var cos_phi := clampf((upper * upper - dist * dist - fore * fore) / maxf(2.0 * fore * dpl, 1e-5), -1.0, 1.0)
	var sin_phi := sqrt(maxf(1.0 - cos_phi * cos_phi, 0.0))
	var cand_a := target + (dp * cos_phi + e2 * sin_phi) * fore
	var cand_b := target + (dp * cos_phi - e2 * sin_phi) * fore
	# Choose the elbow that stays out to this arm's side and IN FRONT of the
	# body (never behind the pelvis), which is where a reverse grip lives.
	var pref := Vector3(float(arm["side"]) * 0.75, -0.30, -0.95).normalized()
	var sa := ((cand_a - S).normalized()).dot(pref)
	var sb := ((cand_b - S).normalized()).dot(pref)
	return cand_a if sa > sb else cand_b


func _apply_arm(arm: Dictionary, target: Vector3, dist: float, elbow_pos: Vector3,
		hilt_y: Vector3, hilt_x: Vector3) -> void:
	var shoulder: Node3D = arm["shoulder"]
	var elbow: Node3D = arm["elbow"]
	var wrist: Node3D = arm["wrist"]
	var side: float = arm["side"]
	var S := shoulder.position
	var dir := (target - S).normalized()
	var Teff := S + dir * dist
	var up_dir := (elbow_pos - S).normalized()
	var fore_dir := (Teff - elbow_pos).normalized()
	var x_axis := up_dir.cross(fore_dir)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3(side, 0, 0)
	x_axis = x_axis.normalized()
	var y_axis := -up_dir
	var z_axis := x_axis.cross(y_axis).normalized()
	x_axis = y_axis.cross(z_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	shoulder.basis = basis
	var ang := acos(clampf(up_dir.dot(fore_dir), -1.0, 1.0))
	elbow.rotation = Vector3(ang, 0.0, 0.0)
	var parent_basis := basis * elbow.transform.basis
	var hy := hilt_y.normalized()
	var hx := hilt_x - hy * hilt_x.dot(hy)
	if hx.length_squared() < 0.0001:
		hx = x_axis
	hx = hx.normalized()
	var hz := hx.cross(hy).normalized()
	hx = hy.cross(hz).normalized()
	var target_basis := Basis(hx, hy, hz)
	wrist.basis = parent_basis.inverse() * target_basis


# --------------------------------------------------------------------- legs
func _leg_phase_offset(index: int, run_amt: float) -> float:
	var wave := [0.0, 0.25, 0.5, 0.75]
	var trot := [0.0, 0.5, 0.0, 0.5]
	return lerpf(wave[index], trot[index], smoothstep(0.0, 1.0, run_amt))


func _update_legs(dt: float, run_amt: float) -> void:
	var duty := lerpf(0.68, 0.44, smoothstep(0.0, 1.0, run_amt))
	var freq := lerpf(1.55, 2.75, clampf(speed / RUN_SPEED, 0.0, 1.0))
	var stride := 0.0
	if speed > 0.08:
		stride = speed * duty / freq
	stride = minf(stride, 0.55)
	var lift_amt := lerpf(0.07, 0.22, smoothstep(0.0, 1.0, run_amt))
	var gait_w := clampf(speed / 1.0, 0.0, 1.0)
	var body_inv := body.transform.affine_inverse()
	var lower: Node3D = get("lower_body") if has_method("get") else null
	var lower_inv := lower.transform.affine_inverse() if lower != null else Transform3D.IDENTITY

	for i in 4:
		var leg: Dictionary = legs[i]
		if jump_state == "AIR":
			var fall := clampf(-vertical_velocity / 6.0, 0.0, 1.0)
			var tuck := smoothstep(0.0, 0.20, air_time) * (1.0 - 0.85 * fall)
			var rr := lerpf(FOOT_R, 0.33, tuck)
			var yy := lerpf(ANKLE_H - HIP_Y, -0.62, tuck)
			var wob := sin(air_time * 4.5 + i * 1.7) * 0.02 * tuck
			var az: float = float(leg["az"])
			var target_body := Vector3(cos(az) * (rr + wob), yy, sin(az) * (rr + wob))
			_solve_leg_ik(leg, target_body, dt, 0.24 + 0.14 * fall)
			leg["down"] = false
			leg["phase"] = 0.0
			continue
		var off := _leg_phase_offset(i, run_amt)
		var q := fmod(gait_phase + off, 1.0)
		var foot := Vector3(cos(leg["az"]) * FOOT_R, ANKLE_H, sin(leg["az"]) * FOOT_R)
		var down := true
		var lift := 0.0
		var radial := 0.0
		if speed > 0.08:
			# Blend the analytic stride between forward (-Z) and lateral (X)
			# so A/D is a real side-step, not a body turn with sliding feet.
			var lat_w := clampf(strafe, -1.0, 1.0)
			var fwd_w := sqrt(maxf(0.0, 1.0 - lat_w * lat_w))
			if q < duty:
				var ts := q / duty
				var s := lerpf(stride * 0.5, -stride * 0.5, ts)
				# Lateral stance moves the planted foot OPPOSITE the travel
				# direction (same as the forward case, whose sign is already
				# correct) — the old -lat_w*s had sideways footwork reversed.
				foot.x += lat_w * s
				foot.z -= fwd_w * s * gait_sign
			else:
				var ts := (q - duty) / (1.0 - duty)
				var s := lerpf(-stride * 0.5, stride * 0.5, smoothstep(0.0, 1.0, ts))
				s += sin(PI * ts) * lerpf(0.01, 0.04, run_amt)
				foot.x += lat_w * s
				foot.z -= fwd_w * s * gait_sign
				lift = sin(PI * ts) * lift_amt
				radial = -sin(PI * ts) * lerpf(0.02, 0.06, run_amt)
				down = false
		if gait_w < 0.99:
			var idle_w := 1.0 - gait_w
			var ph := time * 0.55 + i * 1.7
			foot.x += cos(ph) * 0.006 * idle_w
			foot.z += sin(ph) * 0.006 * idle_w
		if dash_time > 0.0:
			var d := 1.0 - dash_time / maxf(dash_duration, 0.01)
			var tuck := sin(PI * clampf(d, 0.0, 1.0))
			foot.z += tuck * 0.10
			foot.x *= (1.0 - tuck * 0.10)
			lift = maxf(lift, tuck * 0.16)
			down = false
		var radial_dir := Vector3(cos(leg["az"]), 0, sin(leg["az"]))
		foot += radial_dir * radial
		foot.y = ANKLE_H + lift
		if down and not bool(leg["down"]) and speed > 0.4:
			var wp := global_transform * Vector3(foot.x * LOWER_SCALE, 0.02, foot.z * LOWER_SCALE)
			footstep.emit(wp, clampf(speed / RUN_SPEED, 0.2, 1.0))
			if i >= 2 and vfx_enabled:
				_fx.footstep(wp, clampf(speed / RUN_SPEED, 0.2, 1.0) * 0.7)
		leg["down"] = down
		leg["phase"] = q
		# foot is authored in LowerBody-local metres; convert to world for
		# QA/footsteps, then back into LowerBody space for the two-bone IK.
		var foot_world := foot * LOWER_SCALE
		leg["target"] = foot_world

		var target := lower_inv * (body_inv * foot_world)
		var foot_pitch := 0.0
		if not down:
			var ts := clampf((q - duty) / maxf(1.0 - duty, 0.001), 0.0, 1.0)
			foot_pitch = sin(PI * ts) * lerpf(0.10, 0.30, run_amt)
		_solve_leg_ik(leg, target, dt, foot_pitch)


func _solve_leg_ik(leg: Dictionary, target: Vector3, dt: float, foot_pitch: float) -> void:
	var hip_pos: Vector3 = leg["root"].position
	var v := target - hip_pos
	var d := Vector2(v.x, v.z).length()
	var h := v.y
	d = maxf(d, 0.02)
	var reach := sqrt(d * d + h * h)
	var max_reach := FEMUR + TIBIA - 0.008
	if reach > max_reach:
		var k := max_reach / reach
		d *= k
		h *= k
		reach = max_reach
	var base := atan2(h, d)
	var cos_a := (FEMUR * FEMUR + reach * reach - TIBIA * TIBIA) / (2.0 * FEMUR * reach)
	var aa := acos(clampf(cos_a, -1.0, 1.0))
	var femur_angle := base + aa
	var cos_b := (FEMUR * FEMUR + TIBIA * TIBIA - reach * reach) / (2.0 * FEMUR * TIBIA)
	var bb := acos(clampf(cos_b, -1.0, 1.0))
	var knee_angle := -(PI - bb)
	var yaw_angle: float = atan2(-v.z, v.x) + float(leg["az"])
	leg["yaw"].rotation.y = lerp_angle(leg["yaw"].rotation.y, yaw_angle, 1.0 - exp(-28.0 * dt))
	leg["hip"].rotation.z = femur_angle
	leg["knee"].rotation.z = knee_angle
	leg["ankle"].rotation.z = -(femur_angle + knee_angle) + foot_pitch
	leg["ankle"].rotation.x = clampf(_yaw_rate * 0.08, -0.12, 0.12)


# ------------------------------------------------------------------ visuals
func _update_thrusters(dt: float) -> void:
	var boost := 0.0
	if dash_time > 0.0:
		boost = 1.0 - dash_time / maxf(dash_duration, 0.01)
		boost = sin(PI * clampf(boost, 0.0, 1.0))
	if is_attacking and _attack_style == "spin":
		boost = maxf(boost, 0.35)
	var step := maxf(dt, 1.0 / 240.0)

	# ---- vectoring ---------------------------------------------------------
	# The nozzle tracks the direction of TRAVEL, not only the dash vector, so
	# it starts swinging the moment A/D/W/S is pressed.  A dash merely drives
	# the same deflection to its full angle (no more one-frame snap on Shift).
	var desire := Vector3.ZERO
	if dash_time > 0.0:
		desire = _dash_dir
	elif move_command.length() > 0.05:
		desire = move_command
	elif speed > 0.25:
		desire = -global_transform.basis.z * gait_sign
	var local := global_transform.basis.inverse() * desire
	var walk_w := clampf(speed / maxf(RUN_SPEED, 0.1), 0.0, 1.0)
	if dash_time > 0.0:
		walk_w = 1.0
	var target_pitch := 0.0
	var idle := 0.85 + 0.15 * sin(time * 9.0) * sin(time * 3.7)
	var back_w := 0.0
	var yaw_fl := 0.0
	if desire.length_squared() > 1e-4:
		back_w = smoothstep(0.05, 0.65, local.z)
		yaw_fl = atan2(-local.x, maxf(-local.z, 0.001))
		target_pitch = clampf(-local.y * 0.30, -0.24, 0.24) * walk_w
	for n in thruster_nodes:
		if not is_instance_valid(n):
			continue
		var side := float(n.get_meta("side", 1.0))
		var target_yaw := 0.0
		if desire.length_squared() > 1e-4:
			var yaw_side := clampf(yaw_fl, -0.82, 1.57) if side > 0.0 else clampf(yaw_fl, -1.57, 0.82)
			var yaw_back := clampf(2.82 - local.x * 0.30, 2.55, 2.95) if side > 0.0 else clampf(-2.82 - local.x * 0.30, -2.95, -2.55)
			target_yaw = lerpf(yaw_side, yaw_back, back_w) * lerpf(0.60, 1.0, walk_w)
		var turn_rate := 14.0 if dash_time > 0.0 else 9.0
		n.rotation.y = lerpf(n.rotation.y, target_yaw, 1.0 - exp(-turn_rate * step))
		n.rotation.x = lerpf(n.rotation.x, target_pitch, 1.0 - exp(-turn_rate * step))
		# The plume is built with its base ON the nozzle plane, so it physically
		# cannot reach back into the pack at any gimbal angle.
		var s := 0.45 * idle + 1.00 * boost
		for fn in ["flame_core", "flame", "flame_outer"]:
			var flame = n.get_node_or_null(fn)
			if flame is MeshInstance3D:
				# The iris must completely seal the throat at idle: no flame can
				# exist outside a closed cover.  The plume grows out of the
				# opening as the blades retract.
				flame.visible = _iris > 0.02
				var w := (0.45 if fn == "flame_outer" else (0.32 if fn == "flame" else 0.22))
				w = w * (0.88 + 0.12 * idle) + 0.22 * boost
				var open := lerpf(0.15, 1.0, clampf(_iris, 0.0, 1.0))
				flame.scale = Vector3(w, s * open * (0.82 if fn == "flame_core" else 1.0), w)
				var mat := flame.material_override as ShaderMaterial
				if mat != null:
					mat.set_shader_parameter("intensity", 0.55 + 0.65 * boost)
					mat.set_shader_parameter("boost", boost)

	# ---- iris aperture -----------------------------------------------------
	# Opens fast (the blades snap clear of the jet), closes slowly (they slide
	# back over the throat like a camera iris).
	var iris_target := 1.0 if boost > 0.04 else 0.0
	var iris_rate := 26.0 if iris_target > _iris else 2.6
	_iris = lerpf(_iris, iris_target, 1.0 - exp(-iris_rate * step))
	for p in engine_petals:
		if is_instance_valid(p):
			var base := float(p.get_meta("base_z", 0.0))
			p.rotation.z = base + 1.02 * _iris
	var petal_mat := MAT.engine_petal() as ShaderMaterial
	if petal_mat != null:
		petal_mat.set_shader_parameter("open_glow", clampf(_iris * 0.85, 0.0, 1.0))
	if thruster_light != null:
		thruster_light.light_energy = 0.22 + 2.2 * boost


func _update_indicators(dt: float) -> void:
	var pulse := 0.75 + 0.25 * sin(time * 3.4)
	for i in left_indicator_meshes.size():
		var mi = left_indicator_meshes[i]
		if not is_instance_valid(mi):
			continue
		var p := pulse if i != left_indicator_meshes.size() - 1 else (0.5 + 0.5 * sin(time * 1.7))
		mi.scale = Vector3.ONE * (0.7 + 0.6 * p)


func _update_trail(dt: float) -> void:
	if blade_trail == null:
		return
	var active := is_attacking
	var window: Array = [0.0, 999.0]
	if not _attack.is_empty():
		window = _attack.get("trail", [0.0, 999.0])
	var now_active: bool = active and attack_time >= float(window[0]) and attack_time <= float(window[1])
	blade_trail.tick(dt, now_active)
	if now_active:
		blade_trail.add_sample(blade_base.global_position, blade_tip.global_position,
			Color(0.30, 0.62, 1.0, 1.0))


func _update_fx(dt: float) -> void:
	if not vfx_enabled:
		return
	if is_attacking and not _attack.is_empty():
		var hit_at: float = float(_attack.get("hit_at", -1.0))
		if hit_at >= 0.0 and attack_time >= hit_at and not _shake_sent.has("hit"):
			_shake_sent["hit"] = true
			var kind: String = String(_attack.get("hit_kind", "air"))
			var tip := blade_tip.global_position
			if kind == "ground":
				tip.y = 0.04
			var blade_dir := weapon_root.global_transform.basis.y.normalized()
			impact.emit(tip, 1.0)
			_fx.blade_hit(tip, blade_dir, kind, 1.0)
	if weapon_light != null:
		weapon_light.light_energy = 0.16 + 0.04 * sin(time * 8.0)
	if chest_light != null:
		chest_light.light_energy = 0.06 + 0.015 * sin(time * 3.2)


# ----------------------------------------------------------- FPS body hide
## FPS camera view: hide everything that is NOT the arms or the greatsword —
## legs/pelvis, torso shells, head+hair, backpack, pauldrons, contact shadow.
## Only the named subtrees toggle; the IK maths keeps running untouched.
## The exact nodes hidden are recorded so restore is lossless (a node that was
## already invisible stays invisible).
var _fp_hidden: Array = []

func set_body_hidden(hidden: bool) -> void:
	if hidden:
		_fp_hidden.clear()
		var cand: Array = []
		if lower_body != null:
			cand.append(lower_body)
		if contact_shadow != null:
			cand.append(contact_shadow)
		if torso != null:
			for c in torso.get_children():
				if c is Node3D and c != weapon_root \
						and not String(c.name).begins_with("Shoulder"):
					cand.append(c)
		for c in cand:
			if c.visible:
				c.visible = false
				_fp_hidden.append(c)
	else:
		for c in _fp_hidden:
			if is_instance_valid(c):
				c.visible = true
		_fp_hidden.clear()


func reset_demo(pos: Vector3, new_heading: float) -> void:
	set_body_hidden(false)
	position = pos
	heading = new_heading
	rotation.y = new_heading
	speed = 0.0
	display_speed = 0.0
	move_command = Vector3.ZERO
	is_attacking = false
	attack_name = ""
	_attack = {}
	_attack_queue.clear()
	attack_time = 0.0
	combo_step = 0
	dash_time = 0.0
	_dash_cooldown = 0.0
	jump_state = "GROUND"
	jump_t = 0.0
	vertical_velocity = 0.0
	air_time = 0.0
	_carry_w = 0.0
	_attack_style = "twohand"
	_onehand = 0.0
	_left_raise = 0.0
	_smooth_pose.clear()
	_torso_turn_offset = 0.0
	time = 0.0
	gait_phase = 0.0
	position.y = 0.0
	body.position = Vector3(0, HIP_Y * LOWER_SCALE, 0)
	body.rotation = Vector3.ZERO
	torso.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	var base := BASE_POSE.duplicate()
	_update_weapon(base)
	_update_arms(base)
	_update_legs(1.0 / 60.0, 0.0)
	if blade_trail != null:
		blade_trail.clear()
	if hair != null:
		hair.reset_sim()
	if _fx != null:
		_fx.clear_effects()


func _spin_progress(u: float) -> float:
	var r := 0.24
	var v := 1.0 / (1.0 - r)
	if u < r:
		var x := u / r
		return v * r * (x * x * x - 0.5 * x * x * x * x)
	elif u > 1.0 - r:
		var x := (1.0 - u) / r
		return 1.0 - v * r * (x * x * x - 0.5 * x * x * x * x)
	return v * r * 0.5 + v * (u - r)


func _eval_curve(curve: Array, t: float) -> float:
	if curve.is_empty():
		return 0.0
	if t <= float(curve[0][0]):
		return float(curve[0][1])
	for i in curve.size() - 1:
		if t >= float(curve[i][0]) and t <= float(curve[i + 1][0]):
			var u: float = (t - float(curve[i][0])) / maxf(float(curve[i + 1][0]) - float(curve[i][0]), 0.0001)
			u = u * u * (3.0 - 2.0 * u)
			return lerpf(float(curve[i][1]), float(curve[i + 1][1]), u)
	return float(curve[curve.size() - 1][1])


func face_target(pos: Vector3) -> void:
	var d := pos - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	facing_override = true
	facing_heading = atan2(-d.x, -d.z)


func get_diagnostics() -> Dictionary:
	return {
		"speed": speed, "state": locomotion_state, "attack": attack_name,
		"combo": combo_step, "gait": gait_phase, "heading": heading,
		"display_speed": display_speed, "jump": jump_state, "dash": dash_time,
	}


# ------------------------------------------------------------------- QA hooks
func visual_aabb() -> AABB:
	var out := AABB()
	var started := false
	var stack: Array = [self]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and n.visible:
			var mi: MeshInstance3D = n
			var bb: AABB = mi.global_transform * mi.get_aabb()
			if not started:
				out = bb
				started = true
			else:
				out = out.merge(bb)
		for c in n.get_children():
			if c is Node3D:
				stack.append(c)
	return out


## Body-only AABB: excludes the sword and the hair ribbons, both of which can
## legitimately extend past the 2 m silhouette.
func body_aabb() -> AABB:
	var out := AABB()
	var started := false
	var stack: Array = [self]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n == weapon_spin or n == hair or n == contact_shadow:
			continue
		# The exhaust plumes are additive FX, not part of the body silhouette.
		if n is MeshInstance3D and String(n.name).begins_with("flame"):
			continue
		if n is MeshInstance3D and n.visible:
			var mi: MeshInstance3D = n
			var bb: AABB = mi.global_transform * mi.get_aabb()
			if not started:
				out = bb
				started = true
			else:
				out = out.merge(bb)
		for c in n.get_children():
			if c is Node3D:
				stack.append(c)
	return out


func get_knee_angle(index: int) -> float:
	if index < 0 or index >= legs.size():
		return 0.0
	var leg: Dictionary = legs[index]
	var hip: Node3D = leg["hip"]
	var knee: Node3D = leg["knee"]
	var ankle: Node3D = leg["ankle"]
	var a := hip.global_position - knee.global_position
	var b := ankle.global_position - knee.global_position
	return rad_to_deg(a.angle_to(b))


func blade_tip_world() -> Vector3:
	return blade_tip.global_position if blade_tip != null else global_position


func hair_tips() -> Array:
	if hair != null and hair.has_method("get_tip_positions"):
		return hair.get_tip_positions()
	return []