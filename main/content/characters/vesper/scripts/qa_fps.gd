extends Node3D
## VESPER FPS camera acceptance.  Headless:
##   godot --headless --path . res://scenes/qa_fps.tscn
## Drives the real main scene with synthetic input events and checks the
## custom FPS camera: eye anchor, 1-6 translation, 7-0 boom orbit, head hiding.

var main
var rig
var cam
var cam3d: Camera3D
var fails: Array[String] = []
var checks := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	rig = main.rig
	cam = main.cam_rig
	cam3d = cam.camera
	await _run()
	_finish()


func _ok(cond: bool, label: String, detail := "") -> void:
	checks += 1
	if cond:
		print("PASS  ", label, "  ", detail)
	else:
		print("FAIL  ", label, "  ", detail)
		fails.append(label + " " + detail)


func _press(key: int) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	e.pressed = true
	Input.parse_input_event(e)


func _release(key: int) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	e.pressed = false
	Input.parse_input_event(e)


func _wheel(btn: int) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = true
	Input.parse_input_event(e)


func _cam_fwd() -> Vector3:
	return (-cam3d.global_transform.basis.z).normalized()


func _eye() -> Vector3:
	return (rig.head_camera as Node3D).global_position


func _char_fwd() -> Vector3:
	return (-rig.global_transform.basis.z).normalized()


func _run() -> void:
	# ---------------- take manual control, enter FPS mode
	main._take_control()
	main._set_fps(true)
	await get_tree().create_timer(0.6).timeout
	_ok(cam.fps_mode, "fps mode on")
	_ok(cam.fps_offset.length() < 0.001, "fps offset starts at zero")

	# ---------------- idle stance: flat low-ready grip, left elbow hangs down
	await get_tree().create_timer(0.6).timeout
	var hilt_y: Vector3 = (rig.weapon_root.global_transform.basis.y).normalized()
	var elev := rad_to_deg(asin(clampf(hilt_y.y, -1.0, 1.0)))
	_ok(hilt_y.dot(_char_fwd()) > 0.90, "idle blade points forward",
		"dot %.2f dir %s" % [hilt_y.dot(_char_fwd()), hilt_y])
	_ok(elev > 10.0 and elev < 32.0, "idle blade ~20 deg above horizontal",
		"elev %.1f" % elev)
	var elbow_l: Vector3 = (rig.arms[1]["elbow"] as Node3D).global_position
	var shoulder_l: Vector3 = (rig.arms[1]["shoulder"] as Node3D).global_position
	_ok(elbow_l.y < shoulder_l.y - 0.05, "left elbow hangs below the shoulder",
		"elbow %.2f vs shoulder %.2f" % [elbow_l.y, shoulder_l.y])
	var grip_l: Vector3 = rig.weapon_root.global_transform * Vector3(0, 0.16, 0)
	var wrist_l: Vector3 = (rig.arms[1]["wrist"] as Node3D).global_position
	_ok(wrist_l.distance_to(grip_l) < 0.08, "left fist welded to the hilt",
		"%.3f m" % wrist_l.distance_to(grip_l))

	# ---------------- camera export (P)
	var json: String = cam.export_camera_transform("res://renders/qa_fps_cam.json")
	_ok(json.length() > 50 and FileAccess.file_exists("res://renders/qa_fps_cam.json"),
		"camera export writes json")
	var parsed = JSON.parse_string(json)
	_ok(parsed is Dictionary and parsed.has("transform") and parsed.has("fps"),
		"export contains transform + fps params")
	if parsed is Dictionary:
		var p: Array = parsed["transform"]["position"]
		_ok(Vector3(p[0], p[1], p[2]).distance_to(cam3d.global_position) < 0.01,
			"exported position matches camera")
		_ok(parsed["fps"].has("dolly"), "export carries the dolly param")

	var dist := cam3d.global_position.distance_to(_eye())
	_ok(dist < 0.28, "camera welded to the blue eye", "%.3f m" % dist)
	_ok(_cam_fwd().dot(_char_fwd()) > 0.97, "fps view looks along -Z",
		"dot %.3f" % _cam_fwd().dot(_char_fwd()))
	_ok(cam3d.global_position.y > 1.4, "camera at head height",
		"y %.2f" % cam3d.global_position.y)
	# FPS shows ONLY arms + sword: everything else hidden, arms stay visible.
	_ok(not rig.lower_body.visible, "legs + pelvis hidden")
	_ok(not rig.head.visible, "head + hair hidden")
	_ok(not rig.contact_shadow.visible, "contact shadow hidden")
	_ok(rig.arms[0]["shoulder"].visible and rig.arms[1]["shoulder"].visible,
		"both arms visible")
	_ok(rig.weapon_root.visible, "greatsword visible")
	var pack = null
	for c in rig.torso.get_children():
		if String(c.name) == "VectorPack":
			pack = c
	if pack != null:
		_ok(not pack.visible, "backpack hidden")

	# ---------------- move while in fps
	Input.action_press("move_forward")
	await get_tree().create_timer(0.7).timeout
	Input.action_release("move_forward")
	var walk_d := cam3d.global_position.distance_to(_eye())
	_ok(rig.position.z < -0.5, "character advanced", "z %.2f" % rig.position.z)
	_ok(walk_d < 0.28, "camera stays welded while walking", "%.3f m" % walk_d)

	# ---------------- pure view rotation at zero offset (7-0 = aim)
	# Convention: latitude is the CAMERA's elevation — 9 raises the boom
	# (aim pitches down), 0 drops it (aim pitches up).
	_press(KEY_8)
	await get_tree().create_timer(0.55).timeout
	_release(KEY_8)
	_press(KEY_0)
	await get_tree().create_timer(0.35).timeout
	_release(KEY_0)
	_ok(absf(cam.fps_orbit_lon - 0.88) < 0.25, "8 turns longitude", "lon %.2f" % cam.fps_orbit_lon)
	_ok(cam3d.global_position.distance_to(_eye()) < 0.30, "orbit keys keep the eye at zero offset")
	var aim := _cam_fwd()
	_ok(aim.x > 0.65, "view yawed to the right", "fwd x %.2f" % aim.x)
	_ok(aim.y > 0.25, "0 pitches the view up", "fwd y %.2f" % aim.y)

	# reset orbit before translation tests
	main._set_fps(false)
	main._set_fps(true)
	await get_tree().create_timer(0.3).timeout

	# ---------------- 1-6 translate the boom (character space)
	_press(KEY_6)
	_press(KEY_4)
	await get_tree().create_timer(0.55).timeout
	_release(KEY_6)
	_release(KEY_4)
	_ok(absf(cam.fps_offset.z - 0.88) < 0.30, "6 dollies the camera back", "z %.2f" % cam.fps_offset.z)
	_ok(absf(cam.fps_offset.y - 0.88) < 0.30, "4 raises the camera", "y %.2f" % cam.fps_offset.y)
	var back := (cam3d.global_position - _eye())
	back.y = 0.0
	back = back.normalized()
	_ok(back.dot(_char_fwd()) < -0.55, "camera sits behind the character",
		"dot %.2f" % back.dot(_char_fwd()))
	# Aim is the keys' own: parallel to character forward, never a look-at-head.
	_ok(_cam_fwd().dot(_char_fwd()) > 0.97, "aim is parallel to char forward",
		"dot %.2f" % _cam_fwd().dot(_char_fwd()))
	var to_head := (_eye() - cam3d.global_position).normalized()
	_ok(to_head.dot(_cam_fwd()) < 0.95, "aim does NOT chase the head",
		"dot %.2f" % to_head.dot(_cam_fwd()))
	_ok(not rig.head.visible, "body still hidden at boom distance")

	# ---------------- orbit the boom (7-0 swing + aim)
	_press(KEY_8)
	await get_tree().create_timer(0.55).timeout
	_release(KEY_8)
	var side := (cam3d.global_position - _eye()).normalized()
	_ok(side.x < -0.45, "8 swings the boom to the left", "x %.2f" % side.x)
	_press(KEY_9)
	await get_tree().create_timer(0.35).timeout
	_release(KEY_9)
	_ok(cam3d.global_position.y > _eye().y + 0.5, "9 lifts the boom",
		"cam y %.2f > eye %.2f" % [cam3d.global_position.y, _eye().y])
	var aim2 := _cam_fwd()
	_ok(aim2.x > 0.5, "orbited aim pans right with 8", "fwd x %.2f" % aim2.x)
	_ok(aim2.y < -0.25, "9 lifts boom -> aim pitches down", "fwd y %.2f" % aim2.y)

	# ---------------- pure +Z boom lies on the view axis -> auto orbit rig
	main._set_fps(false)
	main._set_fps(true)
	await get_tree().create_timer(0.25).timeout
	cam.adjust_fps(Vector3(0, 0, 1.0), 0.0, 0.0)
	await get_tree().create_timer(0.4).timeout
	var th := (_eye() - cam3d.global_position).normalized()
	_ok(th.dot(_cam_fwd()) > 0.98, "pure +Z boom auto-frames the head",
		"dot %.2f" % th.dot(_cam_fwd()))

	# ---------------- uniform FOV zoom (- / = scale together)
	main._set_fps(false)
	main._set_fps(true)
	await get_tree().create_timer(0.3).timeout
	var fov0 := cam3d.fov
	_press(KEY_EQUAL)
	await get_tree().create_timer(0.6).timeout
	_release(KEY_EQUAL)
	_ok(cam.fps_fov > fov0 + 10.0, "= zooms the fov wider",
		"fov %.1f -> %.1f" % [fov0, cam.fps_fov])
	_press(KEY_MINUS)
	await get_tree().create_timer(0.9).timeout
	_release(KEY_MINUS)
	_ok(cam.fps_fov < fov0 + 5.0, "- zooms the fov back down",
		"fov %.1f" % cam.fps_fov)

	# ---------------- dolly = camera<->subject distance (size on screen)
	_press(KEY_BRACKETRIGHT)
	await get_tree().create_timer(0.5).timeout
	_release(KEY_BRACKETRIGHT)
	_ok(cam.fps_dolly > 0.5, "] pulls the camera back", "dolly %.2f" % cam.fps_dolly)
	var p_far := cam3d.global_position
	_press(KEY_BRACKETLEFT)
	await get_tree().create_timer(1.0).timeout
	_release(KEY_BRACKETLEFT)
	_ok(cam.fps_dolly < -0.6, "[ pushes the camera in", "dolly %.2f" % cam.fps_dolly)
	_ok(p_far.distance_to(cam3d.global_position) > 0.9,
		"dolly moves the camera along the view axis",
		"moved %.2f m" % p_far.distance_to(cam3d.global_position))
	_ok(cam.fps_offset.length() < 0.001,
		"dolly is independent of the 3-axis offset")
	var dolly_pre: float = cam.fps_dolly
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await get_tree().create_timer(0.15).timeout
	_ok(cam.fps_dolly > dolly_pre + 0.4,
		"wheel-down pulls the camera back", "dolly %.2f" % cam.fps_dolly)

	# ---------------- reset + exit
	_press(KEY_R)
	_release(KEY_R)
	await get_tree().create_timer(0.5).timeout
	_ok(absf(cam.fps_fov - 55.0) < 0.1, "R resets fov", "fov %.1f" % cam.fps_fov)
	_press(KEY_R)
	_release(KEY_R)
	await get_tree().create_timer(0.5).timeout
	_ok(cam.fps_mode, "R keeps fps mode (reset)")
	_ok(cam.fps_offset.length() < 0.05 and absf(cam.fps_orbit_lon) < 0.05
		and absf(cam.fps_orbit_lat) < 0.05 and absf(cam.fps_dolly) < 0.05,
		"R resets offset + orbit + dolly")
	_press(KEY_V)
	_release(KEY_V)
	await get_tree().create_timer(0.5).timeout
	_ok(not cam.fps_mode, "V exits fps mode")
	_ok(rig.head.visible and rig.lower_body.visible, "body restored on exit")
	var td := cam3d.global_position.distance_to(rig.global_position + Vector3(0, 1.4, 0))
	_ok(td > 3.0, "third-person shot restored", "dist %.2f m" % td)


func _finish() -> void:
	print("\n==== VESPER FPS QA: %d checks, %d failures ====" % [checks, fails.size()])
	for f in fails:
		print("  FAILED: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
