extends Node3D
## Render suite for SHARD // PHANTOM. Renders the acceptance material:
##   SUITE=contact  - idle / walk / attack x 5 views x 6-9 samples
##   SUITE=swarm    - disperse + reform strip (SUITE_VIEW=three_q|side|front)
##   SUITE=hero     - hero stills at 1600x900
##   SUITE=closeup  - module / thruster / visor / shuriken close-ups
## Output: renders/suite/<name>.png (set SUITE_DIR to override).

const STUDIO := preload("res://scenes/studio.tscn")

var studio: Studio
var ch: Node3D
var out_dir := "res://renders/suite"

const VIEWS := {
	"three_q": [34.0, 8.0, 4.6, 0.95],
	"front": [0.0, 4.0, 4.2, 0.95],
	"side": [90.0, 5.0, 4.2, 0.95],
	"back": [160.0, 8.0, 4.4, 0.95],
	"low": [28.0, -5.0, 4.2, 0.80],
	"top": [20.0, 46.0, 5.0, 0.85],
	"gameplay": [38.0, 6.0, 5.4, 0.95],
	"hero": [34.0, 5.0, 3.5, 1.00],
}


func _ready() -> void:
	var env_dir := OS.get_environment("SUITE_DIR")
	if env_dir != "":
		out_dir = env_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	studio = STUDIO.instantiate()
	add_child(studio)
	await _frames(6)
	studio.ui_root.visible = false
	studio._shot_mode = true
	ch = studio.character
	if ch == null:
		push_error("[suite] no character")
		get_tree().quit(1)
		return
	var mode := OS.get_environment("SUITE")
	match mode:
		"swarm": await _suite_swarm()
		"blink": await _suite_blink()
		"hero": await _suite_hero()
		"walkside": await _suite_walkside()
		"closeup": await _suite_closeup()
		"spin": await _suite_spin()
		_: await _suite_contact()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _view(name: String) -> void:
	var v: Array = VIEWS[name]
	studio.set_view(v[0], v[1], v[2], Vector3(0, v[3], 0))


func _shot(name: String) -> void:
	await _frames(2)
	await studio.snap(out_dir.path_join(name + ".png"))


func _set_t(t: float) -> void:
	ch.set_anim_time(t)
	await _frames(1)


# ------------------------------------------------------------------- contact

func _suite_contact() -> void:
	var sets := {
		"idle": [0.0, 1.0, 2.0, 3.0, 4.0, 5.0],
		"walk": [0.0, 0.35, 0.7, 1.05, 1.4, 1.75, 2.1, 2.45],
		"attack": [0.0, 0.10, 0.22, 0.34, 0.43, 0.50, 0.58, 0.68, 0.80, 0.92, 1.0],
	}
	var views := ["three_q", "front", "side", "back", "low"]
	for anim in ["idle", "walk", "attack"]:
		var dur: float = ch.anim_duration() if anim != "attack" else 1.0
		for v in views:
			_view(v)
			ch.play_anim(anim)
			ch.set_playing(false)
			dur = ch.anim_duration()
			var fracs: Array = sets[anim]
			for f in fracs:
				var t: float = float(f) * (dur if anim != "attack" else dur)
				if anim == "attack":
					t = float(f) * dur
				ch.set_anim_time(t)
				await _frames(1)
				var tag := "%s__%s__%02d" % [anim, v, int(float(f) * 100.0)]
				await _shot(tag)
		print("[suite] %s done" % anim)


# --------------------------------------------------------------------- blink

func _suite_blink() -> void:
	var vname := OS.get_environment("SUITE_VIEW")
	if vname == "":
		vname = "three_q"
	match vname:
		"front":
			studio.set_view(4.0, 5.0, 8.0, Vector3(2.5, 1.05, 0.3))
		"side":
			studio.set_view(72.0, 5.0, 8.5, Vector3(2.5, 1.05, 0.3))
		_:
			studio.set_view(30.0, 6.0, 8.0, Vector3(2.5, 1.05, 0.3))
	await _frames(3)
	# explicit A -> B blink: 6.2 m along +X, both ends in the same fixed frame
	ch.disperse_to(Vector3(5.0, 0.0, 0.6))
	ch.set_playing(false)
	var dd: float = ch.anim_duration()
	var fr := [0.0, 0.12, 0.25, 0.38, 0.50, 0.62, 0.75, 0.88, 1.0]
	var idx := 0
	for f in fr:
		ch.set_anim_time(dd * float(f))
		await _frames(1)
		await _shot("blink_%s_%02d" % [vname, idx])
		idx += 1
	# hold then converge
	ch.set_anim_time(dd)
	await _frames(1)
	ch.reform()
	ch.set_playing(false)
	var rd: float = ch.anim_duration()
	for f in [0.15, 0.35, 0.55, 0.75, 1.0]:
		ch.set_anim_time(rd * float(f))
		await _frames(1)
		await _shot("blink_%s_%02d" % [vname, idx])
		idx += 1
	print("[suite] blink strip done: ", idx)


# --------------------------------------------------------------------- swarm

func _suite_swarm() -> void:
	var vname := OS.get_environment("SUITE_VIEW")
	if vname == "":
		vname = "three_q"
	match vname:
		"side":
			studio.set_view(72.0, 6.0, 7.2, Vector3(1.25, 1.05, 0.0))
		"front":
			studio.set_view(4.0, 5.0, 7.0, Vector3(1.25, 1.05, 0.0))
		_:
			studio.set_view(30.0, 6.0, 7.2, Vector3(1.25, 1.05, 0.0))
	await _frames(3)
	ch.play_anim("disperse")
	ch.set_playing(false)
	var dd: float = ch.anim_duration()
	for i in 9:
		var t := dd * float(i) / 8.0
		ch.set_anim_time(t)
		await _frames(1)
		await _shot("swarm_%s_%02d" % [vname, i])
	print("[suite] disperse strip done")
	# reform: snapshot from the held flying cloud
	ch.play_anim("reform")
	ch.set_playing(false)
	ch.set_anim_time(0.0)
	var rd: float = ch.anim_duration()
	for i in 8:
		var t := rd * float(i) / 7.0
		ch.set_anim_time(t)
		await _frames(1)
		await _shot("reform_%s_%02d" % [vname, i])
	print("[suite] reform strip done")


# --------------------------------------------------------------------- hero

func _suite_hero() -> void:
	var shots := [
		["hero_three_q", 34.0, 5.0, 3.35, 1.00, "idle", 2.2],
		["hero_front", 0.0, 4.0, 3.55, 0.98, "idle", 1.4],
		["hero_side", 88.0, 5.0, 3.50, 0.98, "idle", 3.0],
		["hero_back", 152.0, 7.0, 3.45, 0.98, "walk", 0.5],
		["hero_low", 28.0, -6.0, 3.9, 0.82, "idle", 4.4],
		["hero_gameplay", 38.0, 6.0, 5.4, 0.95, "walk", 1.1],
		["hero_attack_charge", 26.0, 6.0, 3.8, 1.05, "attack", 0.40],
		["hero_attack_fire", 26.0, 6.0, 4.4, 1.05, "attack", 0.52],
		["hero_attack_aim", 0.0, 4.0, 3.9, 1.05, "attack", 0.42],
	]
	for s in shots:
		studio.set_view(s[1], s[2], s[3], Vector3(0, s[4], 0))
		ch.play_anim(s[5])
		ch.set_playing(false)
		ch.set_anim_time(s[6])
		await _frames(2)
		await _shot(s[0])
	# side-on throw: aim forward so the star crosses the frame
	ch.set_param("aim_at_camera", 0.0)
	studio.set_view(40.0, 4.0, 3.7, Vector3(0, 1.10, 0.9))
	ch.play_anim("attack")
	ch.set_playing(false)
	ch.set_anim_time(0.555)
	await _frames(2)
	await _shot("hero_attack_side")
	ch.set_param("aim_at_camera", 1.0)
	# swarm mid-flight beauty
	studio.set_view(30.0, 4.0, 5.0, Vector3(0.7, 1.2, 0))
	ch.play_anim("disperse")
	ch.set_playing(false)
	ch.set_anim_time(ch.anim_duration() * 0.42)
	await _frames(2)
	await _shot("hero_swarm_mid")


# ------------------------------------------------------------------ spin strip

func _suite_spin() -> void:
	ch.set_param("aim_at_camera", 0.0)
	ch.play_anim("attack")
	ch.set_playing(false)
	var fire: float = ch._attack_moments()[2]
	var prev_x := Vector3.ZERO
	var deltas: Array = []
	for k in 6:
		ch.set_anim_time(fire + 0.14 + 0.05 * float(k))
		await _frames(2)
		var s = ch.shurikens[0]
		var p: Vector3 = s.blade.global_position
		studio.set_view(30.0, 8.0, 0.80, p)
		await _frames(2)
		await _shot("spin_%02d" % k)
		var x: Vector3 = s.blade.global_transform.basis.orthonormalized().x.normalized()
		if k > 0:
			deltas.append(rad_to_deg(prev_x.angle_to(x)))
		prev_x = x
	print("[suite] spin deltas deg: ", deltas)


# ----------------------------------------------------------------- walk side

func _suite_walkside() -> void:
	studio.set_view(88.0, 4.0, 3.0, Vector3(0, 0.98, 0.0))
	ch.play_anim("walk")
	ch.set_playing(false)
	var d: float = ch.anim_duration()
	for i in 6:
		ch.set_anim_time(d * float(i) / 6.0)
		await _frames(1)
		await _shot("walk_side_%02d" % i)
	print("[suite] walk side strip done")


# ------------------------------------------------------------------ closeups

func _suite_closeup() -> void:
	# module/thruster close-up while the cloud is flying
	studio.set_view(30.0, 6.0, 5.2, Vector3(0.7, 1.2, 0))
	ch.play_anim("disperse")
	ch.set_playing(false)
	ch.set_anim_time(ch.anim_duration() * 0.55)
	await _frames(2)
	# move the camera into the cloud
	var field = ch.field
	var center: Vector3 = field.center
	studio.set_view(26.0, 8.0, 1.35, Vector3(center.x, center.y + 0.1, center.z))
	await _frames(3)
	await _shot("close_modules")
	# visor close-up
	ch.reform()
	ch.set_playing(false)
	ch.set_anim_time(ch.anim_duration())
	await _frames(2)
	var hx: float = ch._home_xz.x
	var head_p: Vector3 = ch.rig.joints["Head"].global_transform * Vector3(0, 0.092, 0.075)
	studio.set_view(16.0, 4.0, 1.65, head_p)
	await _frames(3)
	await _shot("close_head")
	# palm emitter close-up (hands behind the back -> back 3/4)
	var hand_p: Vector3 = (ch.rig.hand_emitter_xform("L").origin + ch.rig.hand_emitter_xform("R").origin) * 0.5
	studio.set_view(158.0, 2.0, 0.78, hand_p + Vector3(0.0, 0.01, -0.03))
	await _frames(3)
	await _shot("close_palm")
	# calf / sole thruster close-up
	var knee_p: Vector3 = ch.rig.joints["Knee_L"].global_position
	var ankle_p: Vector3 = ch.rig.joints["Ankle_L"].global_position
	studio.set_view(46.0, -3.0, 0.95, (knee_p + ankle_p) * 0.5 + Vector3(0.10, 0.0, 0.0))
	await _frames(3)
	await _shot("close_calf_thruster")
	# shoulder-back thruster close-up
	var sh_p: Vector3 = ch.rig.joints["Shoulder_L"].global_position
	studio.set_view(146.0, 9.0, 0.95, sh_p + Vector3(0.04, -0.01, -0.07))
	await _frames(3)
	await _shot("close_shoulder_thruster")
	# hover plume + ground wash (assembled)
	studio.set_view(148.0, 2.0, 3.4, Vector3(hx, 0.95, 0.0))
	await _frames(3)
	await _shot("close_hover")
	# metal micro-detail close-up on the chest, with a temporary grazing key
	var metal_p: Vector3 = ch.rig.chest_center() + Vector3(0.03, 0.02, 0.06)
	var fov0: float = studio.camera.fov
	studio.camera.fov = 22.0
	studio.set_view(30.0, 4.0, 1.25, metal_p + Vector3(0.0, -0.11, 0.02))
	var insp := SpotLight3D.new()
	insp.light_cull_mask = 1
	insp.light_color = Color(1.0, 0.95, 0.90)
	insp.light_energy = 6.5
	insp.spot_range = 2.5
	insp.spot_angle = 32.0
	insp.position = metal_p + Vector3(0.30, 0.24, 0.55)
	insp.look_at_from_position(insp.position, metal_p, Vector3.UP)
	studio.add_child(insp)
	await _frames(3)
	await _shot("close_metal")
	insp.queue_free()
	studio.camera.fov = fov0
	# attack muzzle close-up
	ch.play_anim("attack")
	ch.set_playing(false)
	ch.set_anim_time(ch.anim_duration() * 0.50)
	studio.set_view(20.0, 4.0, 1.8, Vector3(hx, 1.35, 0.15))
	await _frames(3)
	await _shot("close_shot")