extends Node3D
## Deterministic render suite for visual review.
##
## Usage: DISPLAY=:10 godot --path . res://scenes/shots.tscn
## Writes sequences to renders/shots/*/ and a contact sheet index.
## The simulation is stepped manually at 60 Hz so frames are exactly 0.1-0.25 s
## apart and every sequence is reproducible.

const STUDIO := preload("res://scenes/studio.tscn")
const D2R := PI / 180.0

var studio
var b
var outdir := "res://renders/shots"
var lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var env_dir := OS.get_environment("SHOT_DIR")
	if env_dir != "":
		outdir = env_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outdir))
	studio = STUDIO.instantiate()
	add_child(studio)
	await _frames(6)
	studio.ui_root.visible = false
	studio._shot_mode = true
	if studio._overlay:
		studio._overlay.visible = false
	b = studio.boss
	b.manual = true
	b.set_auto(false)

	var only := OS.get_environment("SHOT_ONLY")
	var pick := only.split(",", false)
	var run_all := only == ""
	if run_all or "idle" in pick:
		await _seq_idle()
	if run_all or "support" in pick:
		await _seq_support()
	if run_all or "attack1" in pick:
		await _seq_attack1()
	if run_all or "attack2" in pick:
		await _seq_attack2()
	if run_all or "attack3" in pick:
		await _seq_attack3()
	if run_all or "phase1" in pick:
		await _seq_phase1()
	if run_all or "phase2" in pick:
		await _seq_phase2()
	if run_all or "laser" in pick:
		await _seq_laser()
	if run_all or "telescope" in pick:
		await _seq_telescope()
	if run_all or "cut" in pick:
		await _seq_cut()

	var idx_name := "index.txt" if run_all else "index_%s.txt" % only.replace(",", "_")
	var f := FileAccess.open(outdir.path_join(idx_name), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()
	print("[shots] done -> ", ProjectSettings.globalize_path(outdir))
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _step(n: int) -> void:
	for i in n:
		b.sim_step(1.0 / 60.0)


func _snap(rel: String) -> void:
	var path: String = outdir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	await studio.snap(path)
	lines.append(rel)


func _all_idle() -> void:
	b.set_auto(false)
	for i in 8:
		b.force_role(i, "idle")


func _roles(support: Array) -> void:
	_all_idle()
	for i in support:
		b.force_role(i, "support")


func _target(g: Vector3) -> void:
	studio.dummy.set_target_pos(g)
	b.set_target(studio.dummy.chest_world(), studio.dummy.ground_world())


func _reset() -> void:
	b.reset_boss()
	b.manual = true
	b.set_auto(false)
	b.set_motion_mode("free")
	b.set_phase_force(0)


# ------------------------------------------------------------------ idle

func _seq_idle() -> void:
	_reset()
	_all_idle()
	b.set_motion_mode("free")
	_target(Vector3(0, 0, 13.0))
	_step(150)
	studio.set_view(26, 12, 40.0, Vector3(0, 5.0, 0.5))
	for i in 30:
		_step(12)  # 0.2 s
		await _snap("idle/%02d.png" % i)
	# top view for mutual clearance
	studio.set_view(18, 48, 44.0, Vector3(0, 3.0, 0.0))
	for i in 20:
		_step(12)
		await _snap("idle_top/%02d.png" % i)
	lines.append("idle: all 8 idle, 0.2 s/frame, 6 s + 4 s top")


# --------------------------------------------------------------- support

func _seq_support() -> void:
	_reset()
	_roles([0, 1, 2, 3, 4])
	b.set_motion_mode("circle", 1.2, 10.0)
	_target(Vector3(0, 0, 13.0))
	_step(330)
	studio.set_view(30, 9, 34.0, Vector3(0, 4.4, 1.0))
	for i in 30:
		_step(15)  # 0.25 s, 7.5 s of a 10 s circle
		await _snap("support/%02d.png" % i)
	studio.set_view(86, 7, 34.0, Vector3(0, 4.2, 0.3))
	for i in 20:
		_step(15)
		await _snap("support_side/%02d.png" % i)
	# low closeup of the front feet / contact rings against the floor
	studio.set_view(55, 0, 12.5, Vector3(0, 1.0, 4.2))
	for i in 10:
		_step(15)
		await _snap("support_feet/%02d.png" % i)
	lines.append("support: 5 planted, body circle r=1.2 m / 10 s, 0.25 s/frame; foot closeup")
	lines.append("support_feet: low front closeup of the planted feet, 0.25 s/frame")


# --------------------------------------------------------------- attacks

func _seq_attack1() -> void:
	_reset()
	_roles([0, 4, 6])
	_target(Vector3(2.5, 0, 11.5))
	_step(220)
	studio.set_view(60, 13, 36.0, Vector3(0.5, 3.6, 6.0))
	b.force_role(2, "attack1")
	for i in 22:
		_step(8)  # 0.133 s
		await _snap("attack1/%02d.png" % i)
	lines.append("attack1: line thrust at a target 11.8 m away, 0.133 s/frame")


func _seq_attack2() -> void:
	_reset()
	_roles([0, 4, 6])
	_target(Vector3(-3.0, 0, 11.0))
	_step(220)
	studio.set_view(60, 13, 36.0, Vector3(0.5, 3.6, 6.0))
	b.force_role(2, "attack2")
	for i in 26:
		_step(8)
		await _snap("attack2/%02d.png" % i)
	lines.append("attack2: reach overhead then plunge at a target 11.4 m away, 0.133 s/frame")


func _seq_attack3() -> void:
	_reset()
	_roles([0, 4, 6])
	_target(Vector3(2.0, 0, 12.0))
	_step(220)
	studio.set_view(28, 30, 50.0, Vector3(0, 2.4, 0.0))
	b.force_role(2, "attack3")
	for i in 45:
		_step(9)  # 0.15 s
		await _snap("attack3/%02d.png" % i)
	lines.append("attack3: 20 m limb laid at 1 m, full 360 deg sweep, 0.15 s/frame")


# ---------------------------------------------------------------- phases

func _seq_phase1() -> void:
	_reset()
	_roles([0, 2, 4, 6])
	_target(Vector3(0, 0, 13.0))
	_step(240)
	studio.set_view(26, 11, 34.0, Vector3(0, 5.0, 1.0))
	await _snap("phase1/hero.png")
	studio.set_view(0, 7, 33.0, Vector3(0, 5.0, 0.8))
	await _snap("phase1/front.png")
	studio.set_view(90, 7, 34.0, Vector3(0, 4.6, 0.5))
	await _snap("phase1/side.png")
	studio.set_view(8, 7, 7.4, Vector3(0, 3.6, 1.5))
	await _snap("phase1/eye.png")
	lines.append("phase1: four planted supports, sealed optic")


func _seq_phase2() -> void:
	# opening sequence from the phase-1 stance
	studio.set_view(26, 11, 34.0, Vector3(0, 5.0, 1.0))
	b.set_phase_force(2)
	for i in 18:
		_step(10)  # 0.167 s, 3 s opening
		await _snap("phase2_open/%02d.png" % i)
	_step(160)
	studio.set_view(26, 11, 34.0, Vector3(0, 5.0, 1.0))
	await _snap("phase2/hero.png")
	studio.set_view(8, 7, 7.4, Vector3(0, 3.6, 1.5))
	await _snap("phase2/core.png")
	studio.set_view(0, 7, 33.0, Vector3(0, 5.0, 0.8))
	await _snap("phase2/front.png")
	studio.set_view(90, 7, 34.0, Vector3(0, 4.6, 0.5))
	await _snap("phase2/side.png")
	studio.set_view(180, 8, 34.0, Vector3(0, 4.6, 0.0))
	await _snap("phase2/back.png")
	lines.append("phase2: shell fully open, plasma core, containment wall")


func _seq_telescope() -> void:
	# one limb telescopes from idle (15 m) to support (~8 m) and back; the root
	# gains/loses links at the socket, the tip pattern stays anchored
	_reset()
	_all_idle()
	_target(Vector3(0, 0, 13.0))
	_step(160)
	studio.set_view(30, 3, 16.0, Vector3(2.5, 2.2, 1.0))
	for i in 8:
		_step(6)
		await _snap("telescope_idle/%02d.png" % i)
	b.force_role(0, "support")
	for i in 16:
		_step(6)
		await _snap("telescope_in/%02d.png" % i)
	_step(40)
	for i in 16:
		b.force_role(0, "idle")
		_step(6)
		await _snap("telescope_out/%02d.png" % i)
	lines.append("telescope: T1 idle 15 m -> support ~8 m -> idle, 0.1 s/frame, root view")


func _seq_cut() -> void:
	# cut limb 1 from the tip to the socket: joint pops, sparks, shards
	_reset()
	_all_idle()
	_target(Vector3(0, 0, 13.0))
	_step(120)
	studio.set_view(28, 8, 20.0, Vector3(4.6, 3.4, 4.6))
	b.cut_tentacle(0)
	for i in 42:
		_step(3)  # 0.05 s
		await _snap("cut/%02d.png" % i)
	_step(60)
	await _snap("cut/after.png")
	lines.append("cut: tip-to-root joint pops on T1, 0.05 s/frame + 1 s later still")


func _seq_laser() -> void:
	_reset()
	_roles([0, 4, 6])
	_target(Vector3(3.0, 0, 11.0))
	_step(220)
	b.set_phase_force(2)
	_step(280)
	studio.set_view(60, 13, 36.0, Vector3(0.5, 3.6, 6.0))
	b.fire_laser()
	_step(56)  # charge
	for i in 14:
		_step(3)
		await _snap("laser/%02d.png" % i)
	lines.append("laser: phase 2 charge + fire at the target, 0.05 s/frame")