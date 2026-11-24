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
	# campaign _steer_dash curves the dash toward facing (authored); a lateral
	# input must still produce a substantial sideways arc vs the old bug's 0.
	if absf(lat) > 0.5:
		print("PASS dash honours local direction")
	else:
		print("FAIL dash went forward instead of sideways")
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

	print("=== %d failure(s) ===" % _failures)
	quit(_failures)
