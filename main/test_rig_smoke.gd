extends SceneTree
## Headless smoke test: instantiate the campaign rig at the in-game unit scale
## and check (a) hair skeleton keeps the external rig scale, (b) request_dash
## honours a local direction.

const Rig = preload("res://runtime/characters/vesper/design/integration/campaign_rig.gd")
const UNIT := 1.0 / 0.547  # main/content/levels/*/src/core/units.gd

var _frame := 0
var _failures := 0


func _init() -> void:
	var rig := Rig.new()
	rig.auto_step = false
	rig.set_process(false)
	rig.scale = Vector3.ONE * UNIT
	root.add_child(rig)
	await process_frame  # let _ready run

	# ---------- (a) hair skeleton scale ----------
	var skel_scale: float = rig.hair._skeleton.global_transform.basis.get_scale().x
	var head_scale: float = rig.head.global_transform.basis.get_scale().x
	print("head world scale = %.4f, hair skeleton scale = %.4f (rig scale %.4f)"
		% [head_scale, skel_scale, UNIT])
	if absf(skel_scale - UNIT) < 0.001:
		print("PASS hair skeleton keeps external rig scale")
	else:
		print("FAIL hair skeleton scale ", skel_scale, " != ", UNIT)
		_failures += 1

	# Simulate a few frames so spring bones settle, then measure tip distance.
	for i in 30:
		rig.advance(1.0 / 60.0)
		_frame += 1
		await process_frame
	var tips: Array = rig.hair_tips()
	if tips.is_empty():
		print("FAIL no hair tips")
		_failures += 1
	else:
		var head_pos: Vector3 = rig.head.global_position
		var d_min := INF
		var d_max := 0.0
		for t in tips:
			var d: float = head_pos.distance_to(t)
			d_min = minf(d_min, d)
			d_max = maxf(d_max, d)
		print("hair tip dist from head origin: min %.3f max %.3f (world units)" % [d_min, d_max])
		# authored back-hair length ~0.6 m -> ~1.1 units at scale 1.828
		if d_max > 0.9:
			print("PASS hair tips reach authored length in world units")
		else:
			print("FAIL hair tips too close to head (hair rendered unscaled)")
			_failures += 1

	# ---------- (b) dash direction ----------
	rig.dash_distance = 2.0
	rig.dash_duration = 0.28
	rig.dash_cd = 0.0
	var p0: Vector3 = rig.position
	rig.request_dash(Vector3.RIGHT)  # local +X = strafe right
	var stepped := 0.0
	while stepped < 0.35:
		var dt := 1.0 / 60.0
		rig.advance(dt)
		stepped += dt
		_frame += 1
		await process_frame
	var disp: Vector3 = rig.position - p0
	print("dash displacement = ", disp, " len=%.3f" % disp.length())
	var lat: float = disp.dot(rig.global_transform.basis.x.normalized())
	var fwd: float = disp.dot(-rig.global_transform.basis.z.normalized())
	print("lateral %.3f / forward %.3f" % [lat, fwd])
	# WASD decides the dash direction; the vector is fixed for the whole dash
	# (no steering toward facing).
	if absf(lat) > 0.95 * disp.length() and absf(fwd) < 0.1:
		print("PASS dash honours local direction (straight)")
	else:
		print("FAIL dash went forward instead of sideways")
		_failures += 1

	# diagonal input (W+D style: local (0.707, 0, -0.707)) must dash diagonally
	rig._dash_cooldown = 0.0
	var pd: Vector3 = rig.position
	# replicate what player.gd passes: camera-relative world dir -> local
	var world_diag := (rig.global_transform.basis.x - rig.global_transform.basis.z).normalized()
	rig.request_dash(rig.global_transform.basis.inverse() * world_diag)
	stepped = 0.0
	while stepped < 0.35:
		var dt := 1.0 / 60.0
		rig.advance(dt)
		stepped += dt
		_frame += 1
		await process_frame
	var dispd: Vector3 = rig.position - pd
	var latd: float = dispd.dot(rig.global_transform.basis.x.normalized())
	var fwdd: float = dispd.dot(-rig.global_transform.basis.z.normalized())
	print("diag dash displacement = ", dispd, " lat=%.3f fwd=%.3f" % [latd, fwdd])
	if latd > 0.6 and fwdd > 0.6 and absf(absf(latd) - absf(fwdd)) < 0.15:
		print("PASS diagonal dash")
	else:
		print("FAIL diagonal dash not diagonal")
		_failures += 1

	# forward default still works
	rig._dash_cooldown = 0.0
	var p1: Vector3 = rig.position
	rig.request_dash()
	stepped = 0.0
	while stepped < 0.35:
		var dt := 1.0 / 60.0
		rig.advance(dt)
		stepped += dt
		_frame += 1
		await process_frame
	var disp2: Vector3 = rig.position - p1
	var fwd2: float = disp2.dot(-rig.global_transform.basis.z.normalized())
	print("default dash displacement = ", disp2, " fwd=%.3f" % fwd2)
	if fwd2 > 0.9 * disp2.length() and disp2.length() > 0.3:
		print("PASS default dash still forward")
	else:
		print("FAIL default dash")
		_failures += 1

	# ---------- (c) movement model ----------
	# c1. WASD accelerates toward a peak speed; releasing on the ground brakes
	#     hard; releasing in the air only drags lightly (momentum survives).
	rig._vel_h = Vector3.ZERO
	rig.move_command = -rig.global_transform.basis.z.normalized() * 5.0
	var speeds: Array[float] = []
	for i in 40:
		rig.advance(1.0 / 60.0)
		speeds.append(rig.speed)
		await process_frame
	var s10: float = speeds[9]
	var s40: float = speeds[39]
	print("accel ramp: t=0.17s %.2f -> t=0.67s %.2f (target 5.0)" % [s10, s40])
	if s10 > 0.3 and s10 < s40 - 0.3 and absf(s40 - 5.0) < 0.3:
		print("PASS accelerate toward target speed")
	else:
		print("FAIL acceleration ramp")
		_failures += 1

	# ground release -> hard brake
	rig.move_command = Vector3.ZERO
	for i in 20:
		rig.advance(1.0 / 60.0)
		await process_frame
	print("ground stop after 0.33s: speed %.2f" % rig.speed)
	if rig.speed < 1.5:
		print("PASS ground braking")
	else:
		print("FAIL ground braking too soft")
		_failures += 1

	# c2. jump preserves horizontal velocity; air drift keeps it
	rig.move_command = -rig.global_transform.basis.z.normalized() * 5.0
	for i in 40:
		rig.advance(1.0 / 60.0)
		await process_frame
	rig.move_command = Vector3.ZERO
	rig.request_jump()
	rig.jump_state = "AIR"          # skip the takeoff crouch for the test
	rig.vertical_velocity = 5.0
	var air_v0 := rig.speed
	for i in 12:
		rig.advance(1.0 / 60.0)
		await process_frame
	print("air momentum: %.2f -> %.2f over 0.2s airborne" % [air_v0, rig.speed])
	if air_v0 > 4.0 and rig.speed > air_v0 - 0.9:
		print("PASS jump keeps horizontal velocity + light air drag")
	else:
		print("FAIL air momentum")
		_failures += 1

	# c3. air dash is allowed and keeps the fixed dash speed/direction
	rig._dash_cooldown = 0.0
	var pdash: Vector3 = rig.position
	rig.request_dash(Vector3(0, 0, -1))
	for i in 22:
		rig.advance(1.0 / 60.0)
		await process_frame
	var ddisp: Vector3 = rig.position - pdash
	ddisp.y = 0.0
	print("air dash disp = ", ddisp, " len %.2f" % ddisp.length())
	if ddisp.length() > 0.8:
		print("PASS air dash")
	else:
		print("FAIL dash blocked in air")
		_failures += 1

	# land again
	rig.jump_state = "GROUND"
	rig.position.y = rig.ground_height

	# c4. attacking does not freeze movement: velocity keeps integrating
	rig.move_command = -rig.global_transform.basis.z.normalized() * 5.0
	for i in 30:
		rig.advance(1.0 / 60.0)
		await process_frame
	rig.play_action("slash_fwd", 0.5)
	var p_att: Vector3 = rig.position
	for i in 20:
		rig.advance(1.0 / 60.0)
		await process_frame
	var move_during_attack: float = (rig.position - p_att).length()
	print("moved %.2f u during attack (is_attacking=%s)" % [move_during_attack, rig.is_attacking])
	if move_during_attack > 0.8:
		print("PASS movement continues while attacking")
	else:
		print("FAIL attack froze movement")
		_failures += 1
	rig.move_command = Vector3.ZERO
	rig.is_attacking = false

	# c5. dash OVERWRITES velocity: run forward, dash backward, keep going back
	rig.move_command = -rig.global_transform.basis.z.normalized() * 5.0
	for i in 40:
		rig.advance(1.0 / 60.0)
		await process_frame
	rig.move_command = Vector3.ZERO
	rig._dash_cooldown = 0.0
	rig.request_dash(Vector3(0, 0, 1))  # local +Z = backward
	var pb: Vector3 = rig.position
	for i in 20:
		rig.advance(1.0 / 60.0)
		await process_frame
	# dash is over; coast a few frames with no input
	for i in 12:
		rig.advance(1.0 / 60.0)
		await process_frame
	var back: float = (rig.position - pb).dot(rig.global_transform.basis.z.normalized())
	var vel_back: float = rig._vel_h.dot(rig.global_transform.basis.z.normalized())
	print("after back-dash: disp_back %.2f, residual _vel_h back %.2f" % [back, vel_back])
	if back > 1.2 and vel_back > 0.5:
		print("PASS dash overwrites velocity direction")
	else:
		print("FAIL velocity snapped back to pre-dash direction")
		_failures += 1

	print("=== %d failure(s) ===" % _failures)
	quit(_failures)
