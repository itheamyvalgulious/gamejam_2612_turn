extends "res://src/game/level.gd"

const Phantom = preload("res://src/game/shard_encounter.gd")
const Ending = preload("res://panopticon/src/arena/panopticon_ending.gd")
const MoveSolver = preload("res://core/move_solver.gd")
const BODY_RADIUS := 1.10
const BODY_HEIGHT := 3.80

var _ending := Ending.new()
var _scan_inside := false
var _scan_clock := -1.0
var _armed := false
var _rng := RandomNumberGenerator.new()


func start_level() -> void:
	super.start_level()
	# The room resolves ledges against solids after the shared controller advances.
	player.rig.follow_platform_height = false
	projectiles.clear_all()
	_armed = false
	arena["camera_geometry"] = geometry
	var control: Dictionary = arena["control"]
	control["indicator"].material_override = control["ready_material"]
	control["alarm"].hide()
	control["prompt_label"].hide()
	for station: Dictionary in arena["archives"]:
		station["panel"].get_node("Schematic").hide()
		station["prompt_label"].hide()
	arena["scan"]["beam"].hide()
	_scan_inside = false
	_scan_clock = -1.0
	if _ending.get_parent() == null:
		add_child(_ending)
	_ending.reset(control)
	arena["experiment_panel"]["prompt_label"].hide()
	arena["experiment_panel"]["experiment"].reset_experiment()


func _spawn_enemies() -> void:
	for i in 3:
		var enemy := Phantom.new()
		enemy.level = self
		enemy.anchor_index = i
		add_child(enemy)
		enemy.global_position = arena["anchors"][i]
		enemy.spawn_xf = enemy.global_transform
		enemy.spawn_rig_xf = enemy.rig.transform
		enemies.append(enemy)


func _clamp_enemy(_enemy) -> void:
	# Shard Phantom only travels between grounded, validated socket positions.
	pass


func context() -> Dictionary:
	var ctx := super.context()
	ctx["projectile_geometry"] = geometry
	return ctx


func phase_visible(enemy) -> bool:
	for offset: Vector3 in [Vector3(0, 0.45, 0), Vector3(0, 1.6, 0),
			Vector3(-0.75, 0.35, 0), Vector3(0.75, 0.35, 0)]:
		var sample: Vector3 = enemy.center() + offset
		if cam.camera.is_position_in_frustum(sample) and melee_clear(cam.camera.global_position, sample):
			return true
	return false


func melee_clear(a: Vector3, b: Vector3) -> bool:
	return geometry.segment_clear(a, b)


func choose_phase_point(enemy) -> int:
	var choices: Array[int] = []
	var close: Vector3 = player.rig.global_position
	var start: Vector3 = enemy.ground_position() + Vector3.UP * 2.25
	for i in arena["anchors"].size():
		var at: Vector3 = arena["anchors"][i]
		var distance: float = at.distance_to(close)
		if i == enemy.anchor_index or distance < 4.2 or distance > 24.0:
			continue
		if not nav.can_stand(at, BODY_RADIUS) or not geometry.segment_clear(start, at + Vector3.UP * 2.25, 0.85):
			continue
		var occupied := false
		for other in enemies:
			if other == enemy or not other.alive:
				continue
			if other.anchor_index == i or other.get("_destination") == i:
				occupied = true
				break
		if not occupied:
			choices.append(i)
	if choices.is_empty():
		return -1
	return choices[_rng.randi_range(0, choices.size() - 1)]


func on_enemy_died(_enemy) -> void:
	if alive_count() == 0 and state in ["intro", "fight"]:
		state = "explore"
		state_t = 0.0


func can_advance() -> bool:
	return _armed and state == "finished"


func step(dt: float, ctx: Dictionary) -> void:
	super.step(dt, ctx)
	_step_checkpoint(dt)
	var experiment_panel: Dictionary = arena["experiment_panel"]
	experiment_panel["prompt_label"].hide()
	arena["control"]["prompt_label"].hide()
	for station: Dictionary in arena["archives"]:
		station["prompt_label"].hide()
	if not player.alive or _armed:
		return
	var eye := cam.fp_transform()
	var facing := -eye.basis.z
	var nearest: Dictionary = {}
	var distance := INF
	var devices: Array = arena["archives"].duplicate()
	devices.append(experiment_panel)
	if state == "explore":
		devices.append(arena["control"])
	for device: Dictionary in devices:
		var target: Vector3 = device["prompt_label"].global_position
		var offset := target - eye.origin
		var gap := offset.length()
		if gap >= distance or gap > 6.0 or facing.dot(offset.normalized()) < 0.56:
			continue
		if (player.rig.global_position - device["stand"]).length() > 4.35:
			continue
		if not melee_clear(eye.origin, target):
			continue
		nearest = device
		distance = gap
	if nearest.is_empty():
		return
	var prompt: Label3D = nearest["prompt_label"]
	prompt.text = B.event_text("interact")
	prompt.show()
	if not B.just("interact"):
		return
	if nearest.has("experiment"):
		nearest["experiment"].toggle_shutter()
		Snd.play_at("clang", prompt.global_position, {"gain": 0.23})
		return
	Snd.play_at("ping", prompt.global_position, {"gain": 0.47})
	if nearest.has("panel"):
		var art: Node3D = nearest["panel"].get_node("Schematic")
		art.visible = not art.visible
		return
	_armed = true
	state = "memory"
	state_t = 0.0
	prompt.hide()
	_ending.start(eye, cam.camera, get_parent().get("hud"), nearest)


func step_cinematic(real_dt: float) -> bool:
	if not _ending.running:
		return false
	if _ending.step(real_dt):
		state = "finished"
	return true


func _step_checkpoint(dt: float) -> void:
	var station: Dictionary = arena["scan"]
	var at: Vector3 = station["center"]
	var local: Vector3 = player.rig.global_position - at
	var inside := player.alive and absf(local.x) < 2.51 and absf(local.z) < 1.45 and local.y < 2.1
	var beam: Node3D = station["beam"]
	if inside and not _scan_inside:
		_scan_clock = 0.0
		beam.show()
		Snd.play_at("ping", at + Vector3.UP * 2.48, {"gain": 0.24})
	_scan_inside = inside
	if _scan_clock < 0.0:
		return
	_scan_clock += dt
	beam.position.y = at.y + lerpf(0.54, 5.14, smoothstep(0.0, 1.24, _scan_clock))
	if _scan_clock >= 1.24:
		_scan_clock = -1.0
		beam.hide()


func constrain_player(previous: Vector3) -> void:
	var rig = player.rig
	var target: Vector3 = rig.global_position
	var tank: Vector2 = arena["blade_center_cylinder"]
	var spec := {
		"solids": arena["solids"], "radius": BODY_RADIUS, "height": BODY_HEIGHT,
		"step_up": 0.5, "clamp_y": Vector2(0.0, 1e9),
		"circles": [{"c": Vector2(0, 0), "r": tank.x, "y1": tank.y}],
	}
	var resolved: Vector3 = MoveSolver.solve(previous, target, spec)
	var support := maxf(MoveSolver.floor_at(resolved, arena["solids"], BODY_RADIUS), 0.0)
	if target.y > previous.y and resolved.y < target.y - 0.025:
		rig.vertical_velocity = 0.0
	elif rig.jump_state == "AIR" and rig.vertical_velocity <= 0.0 and resolved.y <= support + 0.025:
		resolved.y = support
		rig.jump_state = "LANDING"
		rig.jump_t = 0.0
		rig.vertical_velocity = 0.0
	elif rig.jump_state in ["GROUND", "LANDING"]:
		if resolved.y <= support + 0.025:
			resolved.y = support
		else:
			rig.jump_state = "AIR"
			rig.jump_t = 0.0
			rig.vertical_velocity = 0.0
	rig.ground_height = support
	var delta: Vector3 = resolved - rig.global_position
	rig.global_position = resolved
	rig.weapon_xf.origin += delta
	player._swing_cur_xf.origin += delta


func _body_clear(at: Vector3) -> bool:
	var tank: Vector2 = arena["blade_center_cylinder"]
	if at.y < tank.y and Vector2(at.x, at.z).length_squared() < pow(tank.x + BODY_RADIUS, 2):
		return false
	for box: AABB in arena["solids"]:
		if at.y + BODY_HEIGHT <= box.position.y + 0.02 or at.y >= box.end.y - 0.025:
			continue
		if _touches_box(at, box, BODY_RADIUS):
			return false
	return true


func _support_height(at: Vector3, ceiling: float) -> float:
	var support := 0.0
	for box: AABB in arena["solids"]:
		if box.end.y <= ceiling and box.end.y > support and _touches_box(at, box, 0.01):
			support = box.end.y
	return support


func _touches_box(at: Vector3, box: AABB, radius: float) -> bool:
	var nearest := Vector2(clampf(at.x, box.position.x, box.end.x),
		clampf(at.z, box.position.z, box.end.z))
	return nearest.distance_squared_to(Vector2(at.x, at.z)) < radius * radius
