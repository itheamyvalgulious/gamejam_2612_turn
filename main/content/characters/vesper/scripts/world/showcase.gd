extends RefCounted
## Deterministic showcase director.  Drives locomotion, combat and camera cuts
## for the auto demo / showreel.  Everything follows a pure function of time.

var rig
var cam
var hud
var t := 0.0
var phase := ""
var phase_t := 0.0
var loop_len := 24.0
var flags := {}

const STARTS := {
	"INTRO": 0.0, "WALK": 2.4, "SPRINT": 4.8, "COMBO": 7.6,
	"SIDE": 10.9, "BACK": 12.3, "HEAVY": 13.9, "SPIN": 15.9,
	"FINISH": 18.3, "HERO": 21.3,
}
const SHOTS := {
	"INTRO": [-2.62, 5.2, 1.90, 1.25, 40.0],
	"WALK": [-1.85, 4.8, 1.70, 1.20, 41.0],
	"SPRINT": [-2.25, 5.4, 1.55, 1.20, 43.0],
	"COMBO": [-2.20, 5.0, 2.00, 1.25, 38.0],
	"SIDE": [-1.55, 4.6, 1.70, 1.20, 40.0],
	"BACK": [0.95, 4.8, 1.85, 1.20, 40.0],
	"HEAVY": [-2.35, 5.4, 2.20, 1.30, 41.0],
	"SPIN": [-1.90, 5.6, 1.80, 1.20, 41.0],
	"FINISH": [-3.02, 5.4, 1.70, 1.20, 41.0],
	"HERO": [-2.55, 5.2, 1.90, 1.30, 39.0],
}
const PHASE_LABEL := {
	"INTRO": "01 / CALIBRATION",
	"WALK": "02 / LOCOMOTION",
	"SPRINT": "03 / OVERDRIVE",
	"COMBO": "04 / FOUR-WAY FRONT",
	"SIDE": "05 / SIDE THRUST",
	"BACK": "06 / REVERSE THRUST",
	"HEAVY": "07 / GUILLOTINE",
	"SPIN": "08 / HELIX STORM",
	"FINISH": "09 / VECTOR DASH",
	"HERO": "10 / STANDBY",
}


func setup(p_rig, p_cam, p_hud) -> void:
	rig = p_rig
	cam = p_cam
	hud = p_hud


func reset() -> void:
	t = 0.0
	phase = ""
	phase_t = 0.0
	flags.clear()
	rig.reset_demo(Vector3.ZERO, 0.0)
	cam.set_shot(-2.62, 5.2, 1.90, 1.25, 40.0, false)
	cam.snap()
	hud.phase_text = PHASE_LABEL["INTRO"]
	hud.auto_mode = true
	hud.show_intro(2.4)
	hud.set_fade(1.0)


func update(dt: float) -> void:
	t += dt
	if t >= loop_len:
		reset()
		return
	var next_phase := _phase_for(t)
	if next_phase != phase:
		_enter(next_phase)
	phase_t = t - float(STARTS[phase])
	_phase_update(dt)
	var fade := 0.0
	if t < 0.55:
		fade = 1.0 - t / 0.55
	elif t > loop_len - 0.6:
		fade = (t - (loop_len - 0.6)) / 0.6
	hud.set_fade(fade)
	hud.auto_mode = true


func _phase_for(tt: float) -> String:
	if tt < 2.4:
		return "INTRO"
	if tt < 4.8:
		return "WALK"
	if tt < 7.6:
		return "SPRINT"
	if tt < 10.9:
		return "COMBO"
	if tt < 12.3:
		return "SIDE"
	if tt < 13.9:
		return "BACK"
	if tt < 15.9:
		return "HEAVY"
	if tt < 18.3:
		return "SPIN"
	if tt < 21.3:
		return "FINISH"
	return "HERO"


func _enter(p: String) -> void:
	phase = p
	phase_t = 0.0
	flags.clear()
	var shot: Array = SHOTS[p]
	match p:
		"INTRO":
			rig.reset_demo(Vector3.ZERO, 0.0)
			hud.show_intro(2.4)
		"WALK":
			pass
		"SPRINT":
			rig.reset_demo(Vector3.ZERO, 0.0)
		"COMBO", "SIDE", "BACK", "HEAVY", "SPIN", "FINISH":
			rig.reset_demo(Vector3.ZERO, 0.0)
		"HERO":
			rig.reset_demo(Vector3.ZERO, 0.0)
	hud.phase_text = PHASE_LABEL[p]
	if p == "SPIN":
		cam.set_shot(1.55, 6.8, 1.8, 1.20, 41.0, true, 1.55)
	elif p == "BACK":
		cam.set_shot(1.35, 6.0, 1.85, 1.20, 40.0, true, 1.35)
	elif p == "FINISH":
		cam.set_shot(-1.55, 7.2, 1.7, 1.20, 42.0, true, -1.55)
	elif p == "COMBO":
		cam.set_shot(-2.35, 5.0, 2.35, 1.25, 41.0, false)
	elif p == "HEAVY":
		cam.set_shot(-2.35, 5.2, 2.35, 1.25, 41.0, false)
	else:
		cam.set_shot(shot[0], shot[1], shot[2], shot[3], shot[4], false)
	cam.snap()


func _phase_update(_dt: float) -> void:
	match phase:
		"INTRO":
			rig.move_command = Vector3.ZERO
			cam.yaw = -2.62 - sin(t * 0.42) * 0.055
		"WALK":
			var a := -0.7 + phase_t * 1.15
			rig.move_command = Vector3(cos(a), 0, sin(a)) * 2.0
			cam.yaw = -1.85 - phase_t * 0.02
		"SPRINT":
			var a2 := 0.4 + phase_t * 2.05
			rig.move_command = Vector3(cos(a2), 0, sin(a2)) * 6.0
			cam.yaw = -2.25 - phase_t * 0.015
		"COMBO":
			rig.move_command = Vector3.ZERO
			var times := [0.25, 0.98, 1.71, 2.44]
			for i in times.size():
				if phase_t >= times[i] and not flags.has("c%d" % i):
					flags["c%d" % i] = true
					rig.request_light_attack()
		"SIDE":
			rig.move_command = Vector3.ZERO
			if phase_t >= 0.28 and not flags.has("side"):
				flags["side"] = true
				rig.request_side_attack(1.0)
		"BACK":
			rig.move_command = Vector3.ZERO
			if phase_t >= 0.30 and not flags.has("back"):
				flags["back"] = true
				rig.request_back_attack()
		"HEAVY":
			rig.move_command = Vector3.ZERO
			if phase_t >= 0.25 and not flags.has("heavy"):
				flags["heavy"] = true
				rig.request_heavy_attack()
			if phase_t >= 0.78 and not flags.has("heavy_low"):
				flags["heavy_low"] = true
				cam.set_shot(1.55, 5.8, 1.4, 1.10, 43.0, true, 1.55)
				cam.snap()
		"SPIN":
			rig.move_command = Vector3.ZERO
			if phase_t >= 0.30 and not flags.has("spin"):
				flags["spin"] = true
				rig.request_spin_attack()
		"FINISH":
			if phase_t >= 0.15 and not flags.has("dash_r"):
				flags["dash_r"] = true
				rig.request_dash(Vector3(1, 0, 0))
			if phase_t >= 0.95 and not flags.has("dash_f"):
				flags["dash_f"] = true
				rig.request_dash(Vector3(0, 0, -1))
			if phase_t >= 1.75 and not flags.has("jump"):
				flags["jump"] = true
				rig.request_jump()
			if flags.has("jump"):
				match String(rig.jump_state):
					"TAKEOFF":
						hud.phase_text = "09 / JUMP CROUCH"
					"AIR":
						hud.phase_text = "09 / AIRBORNE"
					"LANDING":
						hud.phase_text = "09 / LANDING"
					"GROUND":
						if phase_t > 2.2:
							hud.phase_text = "09 / STANDBY"
		"HERO":
			rig.move_command = Vector3.ZERO
			cam.yaw = -2.55 + phase_t * 0.62