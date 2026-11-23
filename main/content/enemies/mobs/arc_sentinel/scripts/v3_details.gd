extends Node3D
## Detail stills for ARC // GRINDER v3.
##   DISPLAY=:10 godot --path . res://scenes/v3_details.tscn

const STUDIO := preload("res://scenes/studio.tscn")
var studio
var ch
const SHOTS := [
	["hero", -36.0, 7.0, 3.55, Vector3(0, 0.96, 0.0)],
	["hero_low", 28.0, -2.0, 3.30, Vector3(0, 0.80, 0.1)],
	["front_full", 0.0, 5.0, 3.40, Vector3(0, 0.92, 0.0)],
	["side_full", 270.0, 5.0, 3.40, Vector3(0, 0.92, 0.0)],
	["back_full", 180.0, 7.0, 3.40, Vector3(0, 0.92, 0.0)],
	["optic", 16.0, 4.0, 1.05, Vector3(0, 0.80, 0.36)],
	["optic_side", -62.0, 3.0, 0.95, Vector3(0.02, 0.80, 0.34)],
	["optic_high", 10.0, 22.0, 1.00, Vector3(0, 0.86, 0.38)],
	["track", 38.0, 9.0, 1.15, Vector3(0.44, 0.34, 0.10)],
	["track_front", 6.0, 4.0, 1.25, Vector3(0.44, 0.30, 0.35)],
	["track_rear", 208.0, 10.0, 1.30, Vector3(0.44, 0.34, -0.15)],
	["arm_shoulder", -28.0, 10.0, 1.15, Vector3(0.02, 1.20, 0.05)],
	["arm_elbow", 40.0, 6.0, 1.05, Vector3(0.42, 1.25, 0.18)],
	["blade_hilt", 18.0, 2.0, 0.95, Vector3(0.20, 1.05, 0.55)],
	["top_deck", 24.0, 42.0, 1.90, Vector3(0, 1.05, 0.0)],
	["metal", 30.0, 6.0, 1.20, Vector3(-0.18, 1.00, 0.05)],
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders/v3/details"))
	studio = STUDIO.instantiate()
	add_child(studio)
	await _f(6)
	studio.ui_root.visible = false
	if studio._overlay:
		studio._overlay.visible = false
	studio._shot_mode = true
	ch = studio.character
	ch.set_param("lens_track", 0.0)
	ch.set_block_threat(0.0, 0.0)
	for s in SHOTS:
		ch.current_anim = "idle"
		ch._playing = false
		ch._t = 0.35
		ch._prev_t = 0.35
		ch._manual = false
		ch._fade_t = 0.0
		ch._apply_now(0.35)
		ch._update_fx(0.016)
		studio.set_view(float(s[1]), float(s[2]), float(s[3]), s[4])
		await _f(2)
		await studio.snap("res://renders/v3/details/" + str(s[0]) + ".png")
	# eye aiming to the side, to show that the shell stays fixed
	ch.aim_eye_at(Vector3(-3.2, 1.35, 2.2))
	studio.set_view(8.0, 3.0, 1.00, Vector3(0, 0.80, 0.36))
	await _f(2)
	await studio.snap("res://renders/v3/details/optic_aimed.png")
	# block guard still
	ch.set_block_threat(-45.0, 0.0)
	ch.current_anim = "block"
	ch._playing = false
	ch._t = float(ch.anim.block_stats.get("t_guard", 0.2))
	ch._apply_now(ch._t)
	ch._update_fx(0.016)
	studio.set_view(-30.0, 8.0, 4.10, Vector3(0, 1.05, 0.1))
	await _f(2)
	await studio.snap("res://renders/v3/details/block_guard.png")
	get_tree().quit(0)


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame