class_name Capture
extends Node
## Automated waypoint camera + PNG capture along the main route and exterior.

const SHOTS := [
	# ---- engine bay (deck 0, stern) ----
	{"name": "01_engine_wide", "pos": Vector3(48, 2.2, 24), "look": Vector3(24, 3.2, -6)},
	{"name": "02_engine_reactor", "pos": Vector3(40.5, 2.0, -13.5), "look": Vector3(30, 3.4, 0)},
	{"name": "03_engine_catwalk", "pos": Vector3(30, 5.1, 13.5), "look": Vector3(30, 2.8, -4)},
	{"name": "04_engine_drives", "pos": Vector3(14, 2.0, 2), "look": Vector3(-10, 3.2, 10)},
	{"name": "05_engine_console", "pos": Vector3(36, 1.75, 15.5), "look": Vector3(30, 2.6, 10.5)},
	# ---- reactor control / airlock / junction ----
	{"name": "06_control_window", "pos": Vector3(63.5, 1.7, 3.0), "look": Vector3(56.5, 2.7, 0.0)},
	{"name": "07_control_room", "pos": Vector3(64.8, 1.7, -8.0), "look": Vector3(58.5, 1.6, 2.0)},
	{"name": "07b_control_consoles", "pos": Vector3(57.2, 1.75, -1.5), "look": Vector3(60.5, 1.3, 4.0)},
	{"name": "08_airlock", "pos": Vector3(72.8, 1.7, 3.8), "look": Vector3(67.2, 1.7, -1.5)},
	{"name": "09_junction", "pos": Vector3(77.5, 1.7, 7.5), "look": Vector3(81.5, 1.9, -8.0)},
	# ---- ramp climb ----
	{"name": "10_ramp_low", "pos": Vector3(84.0, 2.9, -13.0), "look": Vector3(108, 6.6, -13.0)},
	{"name": "11_ramp_mid", "pos": Vector3(97.0, 5.2, -13.0), "look": Vector3(116, 8.4, -11.0)},
	{"name": "12_ramp_top_back", "pos": Vector3(112.5, 9.3, -13.0), "look": Vector3(96, 3.6, -13.0)},
	# ---- deck 1 spine ----
	{"name": "13_lobby_spine", "pos": Vector3(118.0, 9.2, -6.0), "look": Vector3(130, 9.3, 0.0)},
	{"name": "14_spine_perspective", "pos": Vector3(126.0, 9.2, 0.4), "look": Vector3(180, 9.2, -0.3)},
	{"name": "15_hangar_door", "pos": Vector3(128.0, 9.2, 1.8), "look": Vector3(138, 11.8, -16.0)},
	{"name": "16_mess_door", "pos": Vector3(103.0, 9.2, -1.0), "look": Vector3(100, 9.4, 12.0)},
	# ---- hangar ----
	{"name": "17_hangar_wide", "pos": Vector3(130.0, 10.6, -7.5), "look": Vector3(162, 12.0, -26.0)},
	{"name": "18_hangar_shuttle", "pos": Vector3(146.0, 9.2, -12.0), "look": Vector3(161, 10.2, -24.0)},
	{"name": "19_hangar_booth", "pos": Vector3(164.0, 9.2, -20.0), "look": Vector3(184, 12.4, -11.0)},
	{"name": "20_hangar_catwalk", "pos": Vector3(148.0, 16.7, -5.6), "look": Vector3(168, 9.5, -26.0)},
	{"name": "21_hangardoor_inner", "pos": Vector3(160.0, 9.4, -30.0), "look": Vector3(161, 11.5, -43.5)},
	# ---- living / medical / hydro ----
	{"name": "22_mess_hall", "pos": Vector3(99.0, 9.2, 6.0), "look": Vector3(104, 9.6, 22.0)},
	{"name": "23_medical", "pos": Vector3(139.0, 9.2, 5.5), "look": Vector3(146, 9.6, 18.0)},
	{"name": "24_hydro_aisle", "pos": Vector3(170.0, 9.2, 10.2), "look": Vector3(192, 9.8, 10.2)},
	{"name": "25_hydro_close", "pos": Vector3(168.0, 9.2, 14.6), "look": Vector3(190, 10.0, 14.6)},
	{"name": "26_captain_quarters", "pos": Vector3(199.0, 9.2, -8.0), "look": Vector3(204, 9.6, -22.0)},
	{"name": "27_cargo_a", "pos": Vector3(100.0, 1.7, 5.5), "look": Vector3(106, 2.4, 24.0)},
	# ---- shaft B climb ----
	{"name": "28_shaftb_stairs", "pos": Vector3(231.5, 10.6, 2.8), "look": Vector3(235.5, 12.6, -3.5)},
	# ---- deck 2 ----
	{"name": "29_server_aisle", "pos": Vector3(172.0, 16.7, 5.5), "look": Vector3(172, 17.0, 30.0)},
	{"name": "30_server_holo", "pos": Vector3(168.5, 16.7, 13.8), "look": Vector3(172, 17.8, 12.0)},
	{"name": "31_lounge_window", "pos": Vector3(204.0, 16.7, -18.0), "look": Vector3(213, 17.6, -44.0)},
	{"name": "32_lounge_wide", "pos": Vector3(222.0, 16.7, -8.0), "look": Vector3(204, 17.0, -36.0)},
	{"name": "33_command_passage", "pos": Vector3(239.5, 16.7, 0.2), "look": Vector3(252, 17.0, 0.0)},
	# ---- bridge ----
	{"name": "34_bridge_entry", "pos": Vector3(249.5, 16.75, 0.0), "look": Vector3(262, 17.4, 0.0)},
	{"name": "35_bridge_wide", "pos": Vector3(251.0, 17.8, 8.5), "look": Vector3(264, 17.0, -2.0)},
	{"name": "36_bridge_holo", "pos": Vector3(258.5, 16.9, 6.5), "look": Vector3(254.5, 17.9, 13.0)},
	{"name": "37_bridge_captain", "pos": Vector3(256.6, 17.1, -6.0), "look": Vector3(268, 17.6, 0.5)},
	{"name": "38_bridge_helm", "pos": Vector3(259.5, 17.2, -1.0), "look": Vector3(266, 16.9, 1.5)},
	{"name": "39_bridge_window", "pos": Vector3(261.0, 17.0, 3.0), "look": Vector3(268, 18.8, -1.0)},
	# ---- exterior ----
	{"name": "40_ext_stern", "pos": Vector3(-85.0, 30.0, -105.0), "look": Vector3(50.0, 10.0, 0.0), "fov": 60.0},
	{"name": "41_ext_engines", "pos": Vector3(-52.0, 9.0, 30.0), "look": Vector3(-4.0, 4.0, 14.0), "fov": 66.0},
	{"name": "42_ext_side", "pos": Vector3(140.0, 6.0, 235.0), "look": Vector3(140.0, 13.0, 0.0), "fov": 62.0},
	{"name": "43_ext_bow", "pos": Vector3(438.0, 78.0, 96.0), "look": Vector3(248.0, 14.0, 0.0), "fov": 58.0},
	{"name": "44_ext_top", "pos": Vector3(150.0, 330.0, 46.0), "look": Vector3(150.0, 0.0, -6.0), "fov": 60.0},
	{"name": "45_ext_dorsal", "pos": Vector3(52.0, 66.0, -150.0), "look": Vector3(150.0, 16.0, 0.0), "fov": 58.0},
	{"name": "46_ext_hangardoor", "pos": Vector3(158.0, 12.0, -128.0), "look": Vector3(162.0, 11.0, -49.0), "fov": 62.0},
	{"name": "47_ext_windowband", "pos": Vector3(210.0, 19.0, -108.0), "look": Vector3(211.0, 18.0, -47.0), "fov": 60.0},
	# ---- material close-ups (1-2 m scale quality check) ----
	{"name": "48_closeup_wall", "pos": Vector3(150.0, 9.0, 1.9), "look": Vector3(150.6, 9.35, 2.95), "fov": 60.0},
	{"name": "49_closeup_floor", "pos": Vector3(150.0, 8.7, -0.4), "look": Vector3(150.9, 7.52, 0.9), "fov": 60.0},
	{"name": "50_closeup_console", "pos": Vector3(260.4, 16.9, -3.2), "look": Vector3(263.0, 17.05, -2.6), "fov": 55.0},
	{"name": "51_closeup_reactor", "pos": Vector3(34.8, 1.7, 4.6), "look": Vector3(30.6, 2.4, 1.6), "fov": 60.0},
	{"name": "52_damage_cargo", "pos": Vector3(140.0, 1.7, 11.0), "look": Vector3(152.0, 1.4, 11.5), "fov": 65.0},
	{"name": "53_closeup_door", "pos": Vector3(100.0, 8.7, 1.4), "look": Vector3(100.2, 9.4, 3.0), "fov": 60.0},
	{"name": "54_closeup_hullweld", "pos": Vector3(120.0, 12.0, -58.0), "look": Vector3(121.5, 11.2, -50.0), "fov": 55.0},
]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var win := get_window()
	win.size = Vector2i(1920, 1080)
	var cam := Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.04
	cam.far = 16000.0
	add_child(cam)
	cam.current = true
	var dir := DirAccess.open("res://")
	if dir and not dir.dir_exists("shots"):
		dir.make_dir("shots")
	# warm-up frames (reflection probes, volumetric fog history, SSAO)
	for i in 8:
		await RenderingServer.frame_post_draw
	var t0 := Time.get_ticks_msec()
	for s in SHOTS:
		cam.fov = float(s.get("fov", 68.0))
		cam.position = s["pos"]
		cam.look_at(s["look"], Vector3.UP)
		for k in 3:
			await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("res://shots/%s.png" % s["name"])
		print("SHOT ", s["name"], "  t=", Time.get_ticks_msec() - t0, "ms")
	print("CAPTURE_DONE ", SHOTS.size(), " shots in ", Time.get_ticks_msec() - t0, "ms")
	get_tree().quit()
