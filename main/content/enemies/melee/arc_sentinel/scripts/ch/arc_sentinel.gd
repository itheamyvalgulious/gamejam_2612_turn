extends Node3D
## ARC // GRINDER v3 — tracked turret with a single top-mounted sword arm.
##
## Everything (meshes, materials, motion, FX) is generated from code. Animation
## is 100% joint-driven: poses are joint dictionaries produced by ArcAnim3 and
## applied by ArcRig3. The optic ball inside the fixed lens shell aims at the
## viewer; the shell itself never rotates.
##
## Clips: idle / run (loops), attack1 (overhead chop), attack2 (horizontal
## sweep), block (runtime-planned blade parry).
##
## Locomotion (belts + wheels) is a separate layer: see set_track_speed /
## set_track_travel. Body clips never carry track state, so the chassis can
## pivot or drive straight while any clip plays.
##
## Contract: anim_names/play_anim/set_playing/is_playing/anim_time/set_anim_time/
## anim_duration/set_anim_speed/anim_speed/set_loop/is_looping/param_specs/
## set_param/get_param/joint_specs/set_joint/get_joint/rig_debug.

signal scene_param_changed(key: String, value: float)

const RIG := preload("res://scripts/ch/arc_rig.gd")
const ANIM := preload("res://scripts/ch/arc_anim.gd")
const KIN := preload("res://scripts/ch/arc_kin.gd")
const AM := preload("res://scripts/ch/arc_materials.gd")
const MK := preload("res://scripts/kit/mesh_kit.gd")

const D2R := PI / 180.0
const TAU := PI * 2.0
const ANIMS := ["idle", "run", "attack1", "attack2", "block"]
const LOOPS := ["idle", "run"]
const ONE_SHOTS := ["attack1", "attack2", "block"]

var current_anim := "idle"
var rig: ArcRig3
var kin: ArcKin3
var anim: ArcAnim3
var P: Dictionary = {}

var _t := 0.0
var _playing := true
var _loop := true
var _speed := 1.0
var _manual := false
var _pose: Dictionary = {}
var _fade_from: Dictionary = {}
var _fade_t := 0.0
const FADE_TIME := 0.10
var _queued := ""
var _camera: Camera3D
var _trail_mi: MeshInstance3D
var _impact_mi: MeshInstance3D
var _impact_light: OmniLight3D
var _impact_t := 0.0
var _impact_span := 0.16
var _fx_t := 0.0
var _radius_cache := 0.0
var _clear_cache := 9.0
var _clear_pair := ["", ""]
var _prev_t := 0.0
## True while a caller drives the belts directly (renderers / QA). The clip
## layer then leaves the track state alone.
var _track_lock := false
## External speed command (game code). Persists across clip changes.
var _track_cmd := Vector2.ZERO
var _track_cmd_on := false

const GEOM_KEYS := {
	"cube_size": true, "arm_scale": true, "blade_length": true, "blade_width": true,
}

const DEFAULTS := {
	"cube_size": 0.52, "arm_scale": 1.00,
	"blade_length": 1.030, "blade_width": 0.176,
	"idle_sway": 1.00, "run_speed": 2.00,
	"track_L_speed": 0.0, "track_R_speed": 0.0,
	"attack1_lead": 1.00, "attack1_follow": 1.00, "attack1_overshoot": 1.00,
	"attack2_lead": 1.00, "attack2_follow": 1.00, "attack2_overshoot": 1.00,
	"block_threat": 0.0, "block_elev": 0.0,
	"block_lead": 1.00, "block_hold": 1.00, "block_follow": 1.00,
	"blade_intensity": 0.72, "arc_speed": 1.0, "trail_life": 0.05,
	"lens_intensity": 0.55, "lens_track": 1.0,
	"env_energy": 1.25, "env_exposure": 1.15,
}


func _ready() -> void:
	P = DEFAULTS.duplicate()
	rig = RIG.new()
	rig.name = "Rig"
	add_child(rig)
	rig.build(P)
	kin = rig.kin
	anim = ANIM.new(kin, P)
	anim.build()
	_pose = anim.idle(0.0)
	_apply_now(0.0)
	_radius_cache = rig.measure_radius()
	_refresh_clearance()
	_build_fx()


# ================================================================== lifecycle

func _process(dt: float) -> void:
	if _fade_t > 0.0:
		_fade_t = maxf(_fade_t - dt, 0.0)
	_prev_t = _t
	if _playing:
		_t += dt * _speed
		var d := anim_duration()
		if _loop:
			if d > 0.001:
				_t = fmod(_t, d)
		else:
			if _t >= d:
				_t = d
				_playing = false
				_finish_one_shot()
	if _playing or not _manual:
		_apply_now(_t)
		_check_impact()
		if _fade_t > 0.0 and not _fade_from.is_empty():
			var k: float = smoothstep(0.0, 1.0, 1.0 - _fade_t / FADE_TIME)
			_pose = _blend_pose(_fade_from, _pose, k)
			rig.apply_pose(_pose)
			_track_lens()
	_drive_tracks(dt)
	_update_fx(dt)


func _finish_one_shot() -> void:
	if _queued != "":
		var q := _queued
		_queued = ""
		_go(q)
		return
	_play_direct("idle")


# ================================================================== contract

func anim_names() -> PackedStringArray:
	return PackedStringArray(ANIMS)


func play_anim(name: String) -> void:
	if not (name in ANIMS):
		return
	# One-shots are never cancelled mid-swing; queue the latest request.
	if _playing and current_anim in ONE_SHOTS:
		if name == current_anim:
			return
		_queued = name
		return
	_go(name)


func _go(name: String) -> void:
	_play_direct(name)


func _play_direct(name: String) -> void:
	current_anim = name
	_t = 0.0
	_prev_t = 0.0
	_playing = true
	_loop = name in LOOPS
	_fade_from = _pose.duplicate()
	_fade_t = FADE_TIME
	_manual = false
	if _trail_mi:
		_trail_mi.mesh = null
	_apply_now(0.0)
	_refresh_clearance()
	_update_fx(0.016)


func set_playing(v: bool) -> void:
	_playing = v


func is_playing() -> bool:
	return _playing


func anim_time() -> float:
	return _t


func set_anim_time(t: float) -> void:
	_manual = false
	_t = clampf(t, 0.0, anim_duration())
	_prev_t = _t
	_apply_now(_t)
	_update_fx(0.0)


func anim_duration() -> float:
	return anim.duration(current_anim)


func set_anim_speed(v: float) -> void:
	_speed = clampf(v, 0.02, 4.0)


func anim_speed() -> float:
	return _speed


func set_loop(v: bool) -> void:
	_loop = v


func is_looping() -> bool:
	return _loop


# ================================================================== locomotion

## The belts + wheels are driven outside the clip system. Set each side's signed
## ground speed in m/s (+Z forward) and the rig will keep rolling at that speed;
## the wheel angle is always travel / wheel_r, never an independent value.
func set_track_speed(left_mps: float, right_mps: float) -> void:
	_track_lock = false
	_track_cmd = Vector2(left_mps, right_mps)
	_track_cmd_on = true
	rig.set_track_speed(left_mps, right_mps)


## Absolute belt phase (metres travelled forward), for deterministic rendering
## and tests. Freezes the speed until clear_track_control().
func set_track_travel(left_m: float, right_m: float) -> void:
	_track_lock = true
	rig.set_track_speed(0.0, 0.0)
	rig.set_track_dist(left_m, right_m)


## Hand the tracks back to the clip layer (run = run_speed, everything else = 0)
## and drop the manual L/R speed sliders.
func clear_track_control() -> void:
	_track_lock = false
	_track_cmd_on = false
	_track_cmd = Vector2.ZERO
	P["track_L_speed"] = 0.0
	P["track_R_speed"] = 0.0
	rig.set_track_speed(0.0, 0.0)


func track_state() -> Dictionary:
	var d := rig.track_distances()
	var v := rig.track_speeds()
	var wa := rig.wheel_angles()
	return {
		"left_speed": v.x, "right_speed": v.y,
		"left_travel": d.x, "right_travel": d.y,
		"left_wheel": wa.x, "right_wheel": wa.y,
		"wheel_radius": rig.wheel_r, "max_speed": rig.MAX_TRACK_SPEED,
		"locked": _track_lock, "manual": _track_cmd_on,
	}


## Advance the locomotion layer by hand (QA / fixed-step callers). Normal
## playback already does this once per frame.
func step_tracks(dt: float) -> void:
	rig.advance_tracks(dt)


func _drive_tracks(dt: float) -> void:
	if _track_lock:
		return
	# Paused / scrubbed playback freezes clip-driven tracks, but an explicit
	# speed command from game code keeps running (it is a separate layer).
	if not _playing and not _track_cmd_on:
		return
	var l := 0.0
	var r := 0.0
	if _track_cmd_on:
		l = _track_cmd.x
		r = _track_cmd.y
	else:
		l = float(P["track_L_speed"])
		r = float(P["track_R_speed"])
		if absf(l) < 0.0001 and absf(r) < 0.0001:
			l = 0.0
			r = 0.0
			if current_anim == "run":
				var s := clampf(float(P["run_speed"]) * _speed, 0.0, rig.MAX_TRACK_SPEED)
				l = s
				r = s
	rig.set_track_speed(l, r)
	rig.advance_tracks(dt)


# ================================================================== params

func param_specs() -> Array:
	var s: Array = []
	_add_spec(s, "BODY", "cube_size", "turret cube (m)", 0.46, 0.60, 0.01, P["cube_size"])
	_add_spec(s, "BODY", "arm_scale", "arm length scale", 0.85, 1.15, 0.01, P["arm_scale"])
	_add_spec(s, "BODY", "idle_sway", "idle sway", 0.0, 2.5, 0.02, P["idle_sway"])
	_add_spec(s, "LOCOMOTION", "run_speed", "run track speed (m/s)", 0.4, 3.0, 0.05, P["run_speed"])
	_add_spec(s, "LOCOMOTION", "track_L_speed", "manual L track (m/s)", -3.0, 3.0, 0.05, P["track_L_speed"])
	_add_spec(s, "LOCOMOTION", "track_R_speed", "manual R track (m/s)", -3.0, 3.0, 0.05, P["track_R_speed"])
	_add_spec(s, "WEAPON", "blade_length", "blade length (m)", 0.85, 1.25, 0.005, P["blade_length"])
	_add_spec(s, "WEAPON", "blade_width", "blade width (m)", 0.13, 0.23, 0.005, P["blade_width"])
	_add_spec(s, "ATTACK 1", "attack1_lead", "windup lead-in", 0.6, 1.6, 0.02, P["attack1_lead"])
	_add_spec(s, "ATTACK 1", "attack1_follow", "follow-through", 0.5, 2.0, 0.02, P["attack1_follow"])
	_add_spec(s, "ATTACK 1", "attack1_overshoot", "overshoot", 0.0, 2.0, 0.02, P["attack1_overshoot"])
	_add_spec(s, "ATTACK 2", "attack2_lead", "windup lead-in", 0.6, 1.6, 0.02, P["attack2_lead"])
	_add_spec(s, "ATTACK 2", "attack2_follow", "follow-through", 0.5, 2.0, 0.02, P["attack2_follow"])
	_add_spec(s, "ATTACK 2", "attack2_overshoot", "overshoot", 0.0, 2.0, 0.02, P["attack2_overshoot"])
	_add_spec(s, "BLOCK // PLAN", "block_threat", "threat azimuth (deg)", -85.0, 85.0, 1.0, P["block_threat"])
	_add_spec(s, "BLOCK // PLAN", "block_elev", "threat elevation (deg)", -15.0, 15.0, 1.0, P["block_elev"])
	_add_spec(s, "BLOCK // PLAN", "block_lead", "guard lead-in", 0.5, 1.8, 0.02, P["block_lead"])
	_add_spec(s, "BLOCK // PLAN", "block_hold", "guard hold", 0.35, 2.4, 0.02, P["block_hold"])
	_add_spec(s, "BLOCK // PLAN", "block_follow", "guard release", 0.5, 2.0, 0.02, P["block_follow"])
	_add_spec(s, "FX", "blade_intensity", "blade intensity", 0.0, 2.0, 0.02, P["blade_intensity"])
	_add_spec(s, "FX", "arc_speed", "arc speed", 0.0, 2.0, 0.02, P["arc_speed"])
	_add_spec(s, "FX", "trail_life", "trail life (s)", 0.03, 0.30, 0.005, P["trail_life"])
	_add_spec(s, "FX", "lens_intensity", "optic intensity", 0.0, 8.0, 0.05, P["lens_intensity"])
	_add_spec(s, "FX", "lens_track", "optic tracks viewer", 0.0, 1.0, 1.0, P["lens_track"])
	_add_spec(s, "ENVIRONMENT", "env_energy", "ambient light", 0.0, 3.0, 0.05, P["env_energy"])
	_add_spec(s, "ENVIRONMENT", "env_exposure", "exposure", 0.5, 2.0, 0.01, P["env_exposure"])
	return s


func _add_spec(arr: Array, group: String, key: String, label: String,
		lo: float, hi: float, step: float, value: float) -> void:
	arr.append({"group": group, "key": key, "label": label, "min": lo,
		"max": hi, "step": step, "value": value})


func set_param(key: String, value: float) -> void:
	if not P.has(key):
		return
	P[key] = value
	if key == "env_energy" or key == "env_exposure":
		scene_param_changed.emit(key, value)
	if GEOM_KEYS.has(key):
		_rebuild()
		return
	if key.begins_with("attack1_"):
		anim.P[key] = value
		anim.build()
	elif key.begins_with("attack2_"):
		anim.P[key] = value
		anim.build()
	elif key.begins_with("block_"):
		anim.P[key] = value
		anim.plan_block(P["block_threat"], P["block_elev"])
	elif key == "track_L_speed" or key == "track_R_speed":
		# Touching the manual L/R sliders takes the tracks off clip autopilot
		# and cancels an API speed command.
		_track_lock = false
		_track_cmd_on = false
		rig.set_track_speed(P["track_L_speed"], P["track_R_speed"])
	elif key == "idle_sway":
		anim.P[key] = value
	_apply_now(_t)
	_update_fx(0.0)


func get_param(key: String) -> float:
	return float(P.get(key, 0.0))


# ================================================================== joints

const JOINT_DEFS := [
	["ROOT", "root_yaw", "root yaw", -40, 40, 0.5, 1],
	["TURRET", "body_lift", "body lift (m)", -0.03, 0.03, 0.002, 0],
	["TURRET", "body_sway", "body sway (m)", -0.04, 0.04, 0.002, 0],
	["TURRET", "body_shift", "body shift (m)", -0.04, 0.04, 0.002, 0],
	["TURRET", "body_pitch", "body pitch", -12, 12, 0.5, 1],
	["TURRET", "body_yaw", "body yaw", -8, 8, 0.5, 1],
	["TURRET", "body_roll", "body roll", -8, 8, 0.5, 1],
	["OPTIC", "cam_yaw", "eye yaw", -55, 55, 0.5, 1],
	["OPTIC", "cam_pitch", "eye pitch", -40, 40, 0.5, 1],
	["ARM", "sh_pitch", "shoulder pitch", -170, 170, 0.5, 1],
	["ARM", "sh_yaw", "shoulder yaw", -170, 170, 0.5, 1],
	["ARM", "sh_roll", "shoulder roll", -170, 170, 0.5, 1],
	["ARM", "elb_pitch", "elbow bend", -10, 165, 0.5, 1],
	["ARM", "elb_yaw", "elbow yaw", -60, 60, 0.5, 1],
	["ARM", "elb_roll", "elbow roll", -60, 60, 0.5, 1],
	["ARM", "wr_pitch", "wrist pitch", -170, 170, 0.5, 1],
	["ARM", "wr_yaw", "wrist yaw", -170, 170, 0.5, 1],
	["ARM", "wr_roll", "wrist roll", -170, 170, 0.5, 1],
]


func _arm_qbase(key: String) -> String:
	for j in ["sh", "elb", "wr"]:
		if key.begins_with(j) and (key.find("_pitch") > 0 or key.find("_yaw") > 0 or key.find("_roll") > 0):
			return key.substr(0, key.find("_"))
	return ""


func _joint_euler(key: String) -> Vector3:
	var base := _arm_qbase(key)
	if base != "" and _pose.has(base + "_q") and _pose[base + "_q"] is Quaternion:
		return Basis(_pose[base + "_q"] as Quaternion).get_euler()
	return Vector3(float(_pose.get(base + "_pitch", 0.0)),
		float(_pose.get(base + "_yaw", 0.0)),
		float(_pose.get(base + "_roll", 0.0)))


func joint_specs() -> Array:
	var out: Array = []
	for d in JOINT_DEFS:
		var rad: bool = int(d[6]) == 1
		var key: String = d[1]
		var v := 0.0
		var base := _arm_qbase(key)
		if base != "":
			var e := _joint_euler(key)
			if key.ends_with("_pitch"):
				v = e.x
			elif key.ends_with("_yaw"):
				v = e.y
			else:
				v = e.z
		else:
			v = float(_pose.get(key, 0.0))
		out.append({"group": d[0], "key": key, "label": d[2],
			"min": d[3], "max": d[4], "step": d[5],
			"value": rad_to_deg(v) if rad else v})
	return out


func set_joint(key: String, value: float) -> void:
	var is_rad := false
	var found := false
	for d in JOINT_DEFS:
		if d[1] == key:
			is_rad = int(d[6]) == 1
			found = true
			break
	if not found:
		return
	_playing = false
	_manual = true
	_pose[key] = value * D2R if is_rad else value
	var base := _arm_qbase(key)
	if base != "":
		var e := _joint_euler(key)
		if key.ends_with("_pitch"):
			e.x = float(_pose[key])
		elif key.ends_with("_yaw"):
			e.y = float(_pose[key])
		else:
			e.z = float(_pose[key])
		_pose[base + "_q"] = Basis.from_euler(e).get_rotation_quaternion()
	rig.apply_pose(_pose)
	_track_lens()


func get_joint(key: String) -> float:
	var is_rad := false
	for d in JOINT_DEFS:
		if d[1] == key:
			is_rad = int(d[6]) == 1
			break
	var base2 := _arm_qbase(key)
	var v := 0.0
	if base2 != "":
		var e2 := _joint_euler(key)
		if key.ends_with("_pitch"):
			v = e2.x
		elif key.ends_with("_yaw"):
			v = e2.y
		else:
			v = e2.z
	else:
		v = float(_pose.get(key, 0.0))
	return rad_to_deg(v) if is_rad else v


# ================================================================== optics

## Aim the inner ball at a world point. The fixed shell is untouched.
func aim_eye_at(target: Vector3) -> Vector2:
	if rig == null:
		return Vector2.ZERO
	var eye: Node3D = rig.J["eye_aim"]
	var body: Node3D = rig.J["body"]
	var a := ArcAnim3.eye_aim(body.global_transform.basis, eye.global_position, target)
	eye.rotation = Vector3(a.y, a.x, 0)
	eye.force_update_transform()
	_pose["cam_yaw"] = a.x
	_pose["cam_pitch"] = a.y
	return a


func eye_dir() -> Vector3:
	if rig == null:
		return Vector3.FORWARD
	return rig.eye_world_dir()


func _track_lens() -> void:
	if float(P.get("lens_track", 1.0)) < 0.5:
		return
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return
	aim_eye_at(_camera.global_position)


# ================================================================== planning stats

func set_block_threat(az_deg: float, elev_deg := 0.0) -> void:
	P["block_threat"] = az_deg
	P["block_elev"] = elev_deg
	anim.P["block_threat"] = az_deg
	anim.P["block_elev"] = elev_deg
	anim.plan_block(az_deg, elev_deg)
	if current_anim == "block":
		_apply_now(_t)
		_update_fx(0.0)


func block_threat_id() -> float:
	return float(P.get("block_threat", 0.0))


func block_plan_stats() -> Dictionary:
	var s: Dictionary = anim.block_stats.duplicate()
	s["effector"] = "blade"
	s["threat_name"] = "azimuth %.0f elev %.0f" % [float(P["block_threat"]), float(P["block_elev"])]
	s["feasible"] = bool(s.get("guarded", false))
	s["blocked"] = bool(s.get("guarded", false))
	var guard: Dictionary = anim.action_key("block", "guard")
	s["block_point"] = kin.blade_mid(guard) if not guard.is_empty() else Vector3.ZERO
	return s


func attack_plan_stats(which := "attack1") -> Dictionary:
	var tr: Array = anim.trajs.get(which, [])
	var worst := 99.0
	var wp := ["", ""]
	for s in tr:
		var a := kin.audit(s["pose"], false, 10.0)
		if float(a["min"]) < worst:
			worst = float(a["min"])
			wp = a["pair"]
	var ms := anim.attack1_ms if which == "attack1" else anim.attack2_ms
	var keys: Array = anim.attack1_keys if which == "attack1" else anim.attack2_keys
	return {"total": anim.duration(which), "plan_ms": ms, "mode": which,
		"min_clear": worst, "min_pair": wp, "qdot_max": anim.traj_qdot(which),
		"keys": keys.size(), "reach_ok": true, "samples": tr.size(),
		"swivel": float(anim.clip_swivel.get(which, 0.0))}


# ================================================================== evaluation

func _eval(t: float) -> Dictionary:
	return anim.sample(current_anim, t)


func _apply_now(t: float) -> void:
	_pose = _eval(t)
	rig.apply_pose(_pose)
	_track_lens()
	_update_anim_fx()


func _blend_pose(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	return ArcKin3.blend_pose(a, b, k)


func _update_anim_fx() -> void:
	var on := clampf(float(_pose.get("_blade_on", 1.0)), 0.0, 1.0)
	var intensity := float(P["blade_intensity"]) * on
	rig.set_blade_params(1.05 * intensity, P["arc_speed"], intensity)
	rig.set_lens_params(P["lens_intensity"], 0.0)
	if _impact_t > 0.0:
		rig.set_lens_params(P["lens_intensity"] * (1.0 + 1.6 * _impact_t), 0.0)
	rig.set_status_time(_fx_t)


# ================================================================== FX

func _build_fx() -> void:
	if _trail_mi:
		_trail_mi.queue_free()
	_trail_mi = MeshInstance3D.new()
	_trail_mi.name = "BladeTrail"
	_trail_mi.material_override = AM.trail()
	_trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mi.top_level = true
	add_child(_trail_mi)
	if _impact_mi:
		_impact_mi.queue_free()
	_impact_mi = MeshInstance3D.new()
	_impact_mi.name = "ImpactFlash"
	_impact_mi.mesh = MK.sphere(0.10, 16, 12, true)
	_impact_mi.material_override = AM.emissive(Color(1.0, 0.55, 0.18), 6.0)
	_impact_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_impact_mi.top_level = true
	_impact_mi.visible = false
	add_child(_impact_mi)
	if _impact_light:
		_impact_light.queue_free()
	_impact_light = OmniLight3D.new()
	_impact_light.light_color = Color(1.0, 0.42, 0.10)
	_impact_light.light_energy = 0.0
	_impact_light.omni_range = 2.6
	_impact_light.shadow_enabled = false
	_impact_light.top_level = true
	add_child(_impact_light)


func _check_impact() -> void:
	if not (current_anim in ONE_SHOTS):
		return
	var tr: Array = anim.trajs.get(current_anim, [])
	if tr.is_empty():
		return
	var hit_t := -1.0
	if current_anim == "attack1":
		hit_t = anim._label_time(anim.attack1_keys, "a1/hit")
	elif current_anim == "attack2":
		hit_t = anim._label_time(anim.attack2_keys, "a2/sweep2")
	else:
		hit_t = float(anim.block_stats.get("t_guard", -1.0))
	if hit_t < 0.0:
		return
	if _prev_t < hit_t and _t >= hit_t:
		rig.marker_tip.force_update_transform()
		_spawn_impact(rig.marker_tip.global_position if current_anim != "block" else _blade_mid_world())


func _blade_mid_world() -> Vector3:
	var fk := kin.arm_fk(_pose)
	return fk["tool"] + (fk["dir"] as Vector3) * (kin.blade_len * 0.36)


func _spawn_impact(pos: Vector3) -> void:
	_impact_t = 1.0
	if _impact_mi:
		_impact_mi.visible = true
		_impact_mi.position = pos
		_impact_mi.scale = Vector3.ONE * 0.8
	if _impact_light:
		_impact_light.position = pos
		_impact_light.light_energy = 6.0


func _update_fx(dt: float) -> void:
	_fx_t += dt
	_impact_t = maxf(_impact_t - dt / _impact_span, 0.0)
	if _impact_mi:
		_impact_mi.visible = _impact_t > 0.02
		_impact_mi.scale = Vector3.ONE * (0.6 + 1.8 * _impact_t)
	if _impact_light:
		_impact_light.light_energy = 6.0 * _impact_t * _impact_t
	_update_trail(dt)


func _update_trail(_dt: float) -> void:
	if _trail_mi == null:
		return
	if not (current_anim in ["attack1", "attack2"]) or float(_pose.get("_blade_on", 1.0)) < 0.5:
		if _trail_mi.mesh != null:
			_trail_mi.mesh = null
		return
	var life := float(P["trail_life"])
	var n := 6
	var samples: Array = []
	var keep := _pose
	var t0: float = maxf(_t - life, 0.0)
	for i in n + 1:
		var tt := lerpf(t0, _t, float(i) / float(n))
		if tt >= _t:
			continue
		var p := _eval(tt)
		rig.apply_pose(p)
		rig.marker_base.force_update_transform()
		rig.marker_tip.force_update_transform()
		samples.append({"b": rig.marker_base.global_position,
			"t": rig.marker_tip.global_position, "age": 1.0 - float(i) / float(n)})
	rig.apply_pose(keep)
	rig.marker_base.force_update_transform()
	rig.marker_tip.force_update_transform()
	if samples.size() < 2:
		_trail_mi.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var off := global_position
	for i in samples.size() - 1:
		var s0: Dictionary = samples[i]
		var s1: Dictionary = samples[i + 1]
		var pa0: Vector3 = (s0["b"] as Vector3) - off
		var pa1: Vector3 = (s0["t"] as Vector3) - off
		var pb0: Vector3 = (s1["b"] as Vector3) - off
		var pb1: Vector3 = (s1["t"] as Vector3) - off
		var a0 := pa0.lerp(pa1, 0.55)
		var a1 := pa1
		var b0 := pb0.lerp(pb1, 0.55)
		var b1 := pb1
		var age := float(s0["age"])
		var age1 := float(s1["age"])
		var c0 := Color(1.0, 0.32, 0.05, age * age * 0.025)
		var c1 := Color(1.0, 0.72, 0.42, age * age * 0.09)
		var c2 := Color(1.0, 0.72, 0.42, age1 * age1 * 0.09)
		var c3 := Color(1.0, 0.32, 0.05, age1 * age1 * 0.025)
		var u0 := float(i) / float(samples.size() - 1)
		var u1 := float(i + 1) / float(samples.size() - 1)
		_tri(st, a0, a1, b1, c0, c1, c2, Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1))
		_tri(st, a0, b1, b0, c0, c2, c3, Vector2(u0, 0), Vector2(u1, 1), Vector2(u1, 0))
	_trail_mi.mesh = st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color,
		cc: Color, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.set_color(ca)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.set_uv(uc)
	st.add_vertex(c)


# ================================================================== debug

func rig_debug() -> Dictionary:
	var d := {}
	d["anim"] = current_anim
	d["time"] = "%.3f / %.2f s" % [_t, anim_duration()]
	d["playing"] = _playing
	d["loop"] = _loop
	d["speed"] = "%.2f" % _speed
	d["radius"] = "%.3f m" % _radius_cache
	d["min clearance"] = "%.3f m (%s/%s)" % [_clear_cache, str(_clear_pair[0]), str(_clear_pair[1])]
	d["joints"] = "%d" % rig.J.size()
	d["attack plan"] = "%.0f / %.0f ms" % [anim.attack1_ms, anim.attack2_ms]
	var bl := anim.block_stats
	d["block plan"] = "%.1f ms  threat %.0f  miss %.4f  clear %.3f" % [
		float(bl.get("plan_ms", 0.0)), float(bl.get("threat", 0.0)),
		float(bl.get("miss", 9.0)), float(bl.get("min_clear", -9.0))]
	d["block guard"] = "guarded %s  face err %.1f deg" % [str(bl.get("guarded", false)),
		float(bl.get("face_err", 99.0))]
	d["blade tip"] = _fmt_v(rig.marker_tip.global_position)
	d["eye dir"] = _fmt_v(eye_dir())
	d["eye track"] = "on" if float(P.get("lens_track", 1.0)) >= 0.5 else "authored"
	var ts := track_state()
	d["tracks"] = "L %+.2f  R %+.2f m/s  (cap %.1f)" % [
		float(ts["left_speed"]), float(ts["right_speed"]), float(ts["max_speed"])]
	d["wheel spin"] = "L %.2f  R %.2f rev  (r %.3f m)" % [
		float(ts["left_wheel"]) / TAU, float(ts["right_wheel"]) / TAU,
		float(ts["wheel_radius"])]
	d["track travel"] = "L %+.2f  R %+.2f m" % [
		float(ts["left_travel"]), float(ts["right_travel"])]
	if _track_lock:
		d["track drive"] = "locked"
	if _queued != "":
		d["queued"] = _queued
	return d


func _fmt_v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func _refresh_clearance() -> void:
	if rig == null:
		return
	var a := kin.audit(_pose)
	_clear_cache = float(a["min"])
	_clear_pair = a["pair"]


# ================================================================== rebuild

func _rebuild() -> void:
	var keep_t := _t
	var keep_anim := current_anim
	var keep_playing := _playing
	rig.build(P)
	_radius_cache = rig.measure_radius()
	kin = rig.kin
	anim = ANIM.new(kin, P)
	anim.build()
	current_anim = keep_anim if keep_anim in ANIMS else "idle"
	_t = keep_t
	_playing = keep_playing
	_loop = current_anim in LOOPS
	_pose = _eval(_t)
	rig.apply_pose(_pose)
	_refresh_clearance()
	_track_lens()
	_update_anim_fx()
	_build_fx()