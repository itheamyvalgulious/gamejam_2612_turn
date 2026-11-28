extends LevelUnit

signal opening_reset
signal radio_line(text: String, duration: float, emergency: bool)
signal instruction_changed(text: String)
signal interaction_changed(text: String)

const CargoArena = preload("res://src/cargo_hold2/arena.gd")
const Opening = preload("res://src/cargo_hold2/opening.gd")
const ServiceLadder = preload("res://src/cargo_hold2/service_ladder.gd")
const Inspection = preload("res://src/cargo_hold2/inspection_crate.gd")
const Sentinel = preload("res://src/game/arc_encounter.gd")
const LevelDeathField = preload("res://core/death_field.gd")
const PLAYER_RADIUS := 0.85
const PLAYER_HEIGHT := 3.8
const CONTACT_EPS := 0.015
const STAIR_STEP_HEIGHT := 0.24
const GATE_OPEN_TIME := 0.9
const PATROL_DOOR_TIME := 0.93
const ROUTE_ARRIVAL := 1.7
const LIFT_REST_Y := 0.04
const LIFT_RATE := 2.25
const LIFT_TRAVEL_RATE := 3.20
const LIFT_INTERACTION_RANGE := 4.40

enum LiftPhase { IDLE, HOIST, TRAVEL, LOWER }

var opening := Opening.new()
var service_ladder := ServiceLadder.new()
var player_previous := Vector3.ZERO
var _guard_tip := false
var _route_sent := false
var _radio_cut := false
var _radio_opened := false
var _alarm_due := 0.0
var _alarm_voice := -1
var _lift_phase := LiftPhase.IDLE
var _lift_destination := 0
var _lift_reserved_dock := -1
var _interaction_prompt := ""


func start_level(_idx: int) -> void:
	index = 0
	if arena_node == null:
		arena = CargoArena.build()
		arena_node = arena["node"]
		add_child(arena_node)
		_spawn_encounters()
	else:
		enemies[0].respawn()
	enemies[0].hide()
	if projectiles != null:
		projectiles.clear_all()
	service_ladder.active = false
	player.rig.reset_ladder_pose()
	player.rig.ground_height = float(arena["floor_y"])
	player.reset(arena["player_spawn"])
	player.rig.arena_bounds = Vector2.ZERO
	player_previous = player.rig.global_position
	cam.yaw = 0
	cam.pitch = -0.16
	opening.begin(player, cam, arena)
	total_enemies = enemies.size()
	_guard_tip = false
	_route_sent = false
	_radio_cut = false
	_radio_opened = false
	_alarm_due = 0.0
	_stop_alarm()
	LevelDeathField.install(self)
	var lift_was_blocked := _lift_reserved_dock >= 0
	_lift_phase = LiftPhase.IDLE
	_lift_destination = 0
	_lift_reserved_dock = -1
	_move_lift(CargoArena.LIFT_PARK_Y, CargoArena.LIFT_CENTER.z)
	var crates_changed := _reset_inspection_crates()
	_set_interaction_prompt("")
	_place_world_prompt(null)
	_set_lift_status("A 位悬停", false)
	_move_passage(arena["security"], 0.0)
	_move_passage(arena["gate"], 0.0)
	if lift_was_blocked or crates_changed:
		_refresh_navigation()
	var amber: OmniLight3D = arena["security"]["warning"]
	amber.light_energy = 0.0
	arena["approach_guide"].hide()
	arena["guide"].hide()
	_set_beacons(0.0)
	state = "opening_cg"
	state_t = 0.0
	Snd.set_arena(arena)
	if on_level_changed.is_valid():
		on_level_changed.call(0, String(arena["name_cn"]), String(arena["hint"]))
	opening_reset.emit()


func _spawn_encounters() -> void:
	var enemy := Sentinel.new()
	add_child(enemy)
	enemy.level = self
	enemy.use_ground_routes(sentinel_ground_move, sentinel_support_floor, sentinel_waypoint)
	enemy.global_position = CargoArena.BASIC_SPAWN
	enemy.spawn_xf = enemy.global_transform
	enemy.spawn_rig_xf = enemy.rig.transform
	enemies.append(enemy)


func step_cinematic(dt: float) -> void:
	opening.step(dt)
	if opening.active:
		return
	P.set_value("cam.mode", "first")
	player.sync_opening_handoff()
	player_previous = player.rig.global_position
	state = "intro"
	state_t = 0.0
	_step_opening()


func step(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	match state:
		"intro":
			_step_opening()
		"alert":
			_step_patrol_alert(dt, ctx)
		"fight":
			if state_t >= 4.1 and not _guard_tip:
				on_guard_contact()
			_step_sentinel(dt, ctx)
		"evacuate":
			_step_evacuation(dt, ctx)
		"clear":
			_step_sentinel(dt, ctx)
			if state_t >= 0.48:
				state = "finished"
	var crane_available := _step_crane(dt)
	var crate_anchor: Variant = _step_inspection_crates(dt)
	var anchor: Variant = crate_anchor
	if crane_available:
		anchor = arena["crane"]["interact_at"]
	elif _ladder_available():
		anchor = CargoArena.ladder_interact_at(player.rig.global_position.y)
	_place_world_prompt(anchor if not service_ladder.active else null)
	_set_interaction_prompt("%s / %s" % [B.event_text("move_forward"), B.event_text("move_back")]
		if service_ladder.active else "")


func _step_opening() -> void:
	if not _radio_opened:
		_radio_opened = true
		Snd.play_at("cargo_radio", player.rig.global_position, {"gain": 0.62, "prio": 3})
		radio_line.emit("Sivi?\n咦 你已经都不记得了吗, 我是Nova\n记忆没有上传完整呢...如果数据完整的话应该还可以上载?\n你先重新习惯一下自己的义体吧", 7.8, false)
		arena["approach_guide"].show()
	var pos: Vector3 = player.rig.global_position
	if pos.z < 9.0:
		arena["approach_guide"].hide()
		state = "alert"
		state_t = 0.0
		enemies[0].show()
		var warning: OmniLight3D = arena["security"]["warning"]
		Snd.play_at("cargo_alarm", warning.global_position, {"gain": 0.64, "prio": 4})
		radio_line.emit("这么老旧的型号 看来他们觉得这里很安全?", 4.1, false)
		instruction_changed.emit("击倒 ARC Sentinel")


func _step_patrol_alert(dt: float, ctx: Dictionary) -> void:
	var door: Dictionary = arena["security"]
	var t := smoothstep(0.08, PATROL_DOOR_TIME, state_t)
	_move_passage(door, float(door["stroke"]) * t)
	var warning: OmniLight3D = door["warning"]
	warning.light_energy = 0.26 + 1.25 * pow(0.5 + 0.5 * sin(state_t * 26.0), 2.0)
	var lamp: StandardMaterial3D = door["lamp"]
	lamp.emission_energy_multiplier = 0.42 + warning.light_energy
	_step_sentinel(dt, ctx)
	if state_t >= PATROL_DOOR_TIME:
		state = "fight"
		state_t = 0.0
		warning.light_energy = 0.26
		lamp.emission_energy_multiplier = 0.68


func _step_sentinel(dt: float, ctx: Dictionary) -> void:
	enemies[0].step(dt, ctx)


func on_guard_contact() -> void:
	if _guard_tip or state != "fight":
		return
	_guard_tip = true
	radio_line.emit("记住转过头去不要看他 那是过去的你研发的麦克斯韦之瞳. 只有你完全看不到他时他才挡不住你的攻击", 5.0, false)
	var prompt := "移开视线  ·  侧斩哨兵"
	if not cam.first_person:
		prompt = "%s  ·  切换第一人称  /  试着侧斩" % B.event_text("cam_mode")
	instruction_changed.emit(prompt)


func on_enemy_died(_enemy) -> void:
	if state != "fight":
		return
	state = "evacuate"
	state_t = 0.0
	_alarm_due = 0.0
	_set_beacons(3.0)
	instruction_changed.emit("撤离货舱")


func _step_evacuation(dt: float, ctx: Dictionary) -> void:
	_step_sentinel(dt, ctx)
	var gate: Dictionary = arena["gate"]
	if state_t >= ROUTE_ARRIVAL:
		var lift := smoothstep(ROUTE_ARRIVAL, ROUTE_ARRIVAL + GATE_OPEN_TIME, state_t)
		_move_passage(gate, float(gate["stroke"]) * lift)
	_alarm_due -= dt
	if _alarm_due <= 0.0:
		_alarm_voice = Snd.play_at("cargo_alarm", Vector3(9, 5.5, -19), {"gain": 1.04, "prio": 4})
		_alarm_due = 2.3
	var pulse := 0.5 + 0.5 * sin(state_t * TAU * 0.67)
	_set_beacons(0.68 + 3.1 * pulse * pulse)
	if state_t >= ROUTE_ARRIVAL and not _route_sent:
		_route_sent = true
		arena["guide"].show()
		instruction_changed.emit("沿青色指引撤离")
		radio_line.emit("快走 路线发给你了 去实验室,那里有...", 3.1, false)
	if state_t >= 4.6 and not _radio_cut:
		_radio_cut = true
		Snd.play_at("cargo_radio", player.rig.global_position, {"gain": 0.76, "prio": 4})
	var at: Vector3 = player.rig.global_position
	if not bool(gate["closed"]) and _route_sent and at.y < CargoArena.EXIT_ROOF_Y \
			and CargoArena.EXIT_TRIGGER.has_point(Vector2(at.x, at.z)):
		_stop_alarm()
		_set_beacons(0.0)
		instruction_changed.emit("")
		state = "clear"
		state_t = 0.0


func _move_passage(door: Dictionary, height: float) -> void:
	var panel: Node3D = door["panel"]
	if door.has("moving_box") and is_equal_approx(panel.position.y, height):
		return
	var camera_solids: Array = arena["camera_solids"]
	var blade_boxes: Array = arena["blade_boxes"]
	if door.has("moving_box"):
		camera_solids.erase(door["moving_box"])
		blade_boxes.erase(door["moving_box"])
	var opening_box: AABB = door["box"]
	var moving_box := AABB(opening_box.position + Vector3.UP * height, opening_box.size)
	door["moving_box"] = moving_box
	camera_solids.append(moving_box)
	blade_boxes.append(moving_box)
	panel.position.y = height
	var collider: StaticBody3D = door["collider"]
	collider.position.y = moving_box.get_center().y

	var closed := height < PLAYER_HEIGHT
	if door.get("closed") != closed:
		door["closed"] = closed
		_refresh_navigation()
		var lamp: StandardMaterial3D = door["lamp"]
		var color := Color("b0834b") if closed else Color("82aca7")
		lamp.albedo_color = color
		lamp.emission = color
		lamp.emission_energy_multiplier = 0.42 if closed else 0.85
	geometry = LevelGeometry.build(arena)


func _refresh_navigation() -> void:
	var spec := CargoArena.nav_spec()
	var blocks: Array = []
	for entry: Dictionary in [arena["security"], arena["gate"]]:
		if entry.get("closed", true):
			blocks.append({"aabb": entry["box"]})
	for crate: Inspection in arena["inspection_crates"]:
		if _shutter_blocks_ground(crate.current_bounds):
			blocks.append({"aabb": crate.current_bounds})
	if _lift_reserved_dock >= 0:
		var crane: Dictionary = arena["crane"]
		var floor_box: AABB = crane["volumes"][0]["base"]
		var dock: Vector3 = crane["docks"][_lift_reserved_dock]
		floor_box.position.z += dock.z - CargoArena.LIFT_CENTER.z
		blocks.append({"aabb": floor_box})
	spec["obstacles"] = blocks
	nav = NavField.build(arena, spec)


func _reserve_lift_dock(index: int) -> void:
	if _lift_reserved_dock != index:
		_lift_reserved_dock = index
		_refresh_navigation()


func _step_crane(dt: float) -> bool:
	var crane: Dictionary = arena["crane"]
	var load: Node3D = crane["load"]
	var at: Vector3 = player.rig.global_position
	var station: Vector3 = crane["station"]
	var distance := Vector2(at.x - station.x, at.z - station.z).length_squared()
	var near := (player.alive and state in ["fight", "evacuate"] and absf(at.y - station.y) < 1.0
		and at.z >= station.z - 0.22 and distance <= LIFT_INTERACTION_RANGE * LIFT_INTERACTION_RANGE)
	var arrived: Vector3 = crane["docks"][_lift_destination]
	var bay := "A" if _lift_destination == 0 else "B"
	var status: String
	match _lift_phase:
		LiftPhase.HOIST:
			if _lift_occupied(crane, load.position.z, at):
				status = "原货位占用 · 等待起吊"
			else:
				status = "正在起吊"
				var height := move_toward(load.position.y, CargoArena.LIFT_PARK_Y, LIFT_RATE * dt)
				_move_lift(height, load.position.z)
				if is_equal_approx(height, CargoArena.LIFT_PARK_Y):
					_reserve_lift_dock(-1)
					_lift_phase = LiftPhase.TRAVEL
		LiftPhase.TRAVEL:
			status = "正在运往 %s 位" % bay
			var depth := move_toward(load.position.z, arrived.z, LIFT_TRAVEL_RATE * dt)
			_move_lift(CargoArena.LIFT_PARK_Y, depth)
			if is_equal_approx(depth, arrived.z):
				_lift_phase = LiftPhase.LOWER
		LiftPhase.LOWER:
			if _lift_occupied(crane, arrived.z, at):
				status = "%s 位占用 · 暂停落货" % bay
			else:
				_reserve_lift_dock(_lift_destination)
				status = "%s 位正在落货" % bay
				var height := move_toward(load.position.y, LIFT_REST_Y, LIFT_RATE * dt)
				_move_lift(height, arrived.z)
				if is_equal_approx(height, LIFT_REST_Y):
					_lift_phase = LiftPhase.IDLE
					status = "%s 位已落货" % bay
		_:
			var raised := is_equal_approx(load.position.y, CargoArena.LIFT_PARK_Y)
			_set_lift_status("%s 位%s" % [bay, "悬停" if raised else "已落货"], false)
			if near and B.just("interact"):
				_lift_destination = 1 - _lift_destination
				_lift_phase = LiftPhase.TRAVEL if raised else LiftPhase.HOIST
				return false
			return near
	_set_lift_status(status, true)
	return false


func _lift_occupied(crane: Dictionary, depth: float, player_at: Vector3) -> bool:
	var box: AABB = crane["volumes"][0]["base"]
	var pad := Rect2(Vector2(box.position.x, box.position.z + depth - CargoArena.LIFT_CENTER.z),
		Vector2(box.size.x, box.size.z))
	if pad.grow(PLAYER_RADIUS + 0.16).has_point(Vector2(player_at.x, player_at.z)):
		return true
	var enemy: Node3D = enemies[0]
	var at: Vector3 = enemy.ground_position()
	return enemy.visible and enemy.alive and pad.grow(NAV_SENTINEL_RADIUS + 0.16).has_point(Vector2(at.x, at.z))


func _move_lift(height: float, depth: float) -> void:
	var crane: Dictionary = arena["crane"]
	var load: Node3D = crane["load"]
	var bridge: Node3D = crane["bridge"]
	var ropes: Node3D = crane["ropes"]
	var camera_solids: Array = arena["camera_solids"]
	var blade_boxes: Array = arena["blade_boxes"]
	var needs_rebuild := false
	for group in [crane["volumes"], crane["bridge_volumes"]]:
		var offset := Vector3(0, height if group == crane["volumes"] else 0.0, depth - CargoArena.LIFT_CENTER.z)
		for part: Dictionary in group:
			var base: AABB = part["base"]
			var current := AABB(base.position + offset, base.size)
			if part.has("current"):
				var previous: AABB = part["current"]
				if previous == current:
					continue
				camera_solids.erase(previous)
				blade_boxes.erase(previous)
				if geometry != null and not geometry.translate_box(previous, current.position - previous.position):
					needs_rebuild = true
			else:
				needs_rebuild = true
			part["current"] = current
			camera_solids.append(current)
			blade_boxes.append(current)
			var body: StaticBody3D = part["body"]
			body.position = current.get_center()
	bridge.position.z = depth
	load.position.y = height
	load.position.z = depth
	ropes.scale.y = ropes.position.y - (height + float(crane["seat_height"]))
	if needs_rebuild:
		geometry = LevelGeometry.build(arena)


func _set_lift_status(text: String, busy: bool) -> void:
	var readout: Label3D = arena["crane"]["status"]
	if readout.text == text:
		return
	readout.text = text
	readout.modulate = Color("e6b780") if busy else Color("b9e2df")


func _reset_inspection_crates() -> bool:
	var changed := false
	for crate: Inspection in arena["inspection_crates"]:
		var before := crate.current_bounds if crate.opened else AABB()
		if not crate.opened and arena["camera_solids"].has(crate.current_bounds):
			continue
		crate.reset()
		_update_inspection_collision(before, crate.current_bounds)
		changed = true
	if changed:
		geometry = LevelGeometry.build(arena)
	return changed


func _step_inspection_crates(dt: float) -> Variant:
	var at: Vector3 = player.rig.global_position
	var facing := Vector3(-sin(cam.yaw), 0, -cos(cam.yaw))
	var can_interact := player.alive and state in ["intro", "alert", "fight", "evacuate"]
	var anchor: Variant = null
	var geometry_changed := false
	var navigation_changed := false
	for crate: Inspection in arena["inspection_crates"]:
		var before := crate.current_bounds
		if crate.step(dt) and before != crate.current_bounds:
			_update_inspection_collision(before, crate.current_bounds)
			geometry_changed = true
			navigation_changed = navigation_changed or (
				_shutter_blocks_ground(before) != _shutter_blocks_ground(crate.current_bounds))
		if can_interact and crate.standing_at_control(at, facing):
			if B.just("interact"):
				crate.start_opening()
			else:
				anchor = crate.interact_at
	if geometry_changed:
		geometry = LevelGeometry.build(arena)
	if navigation_changed:
		_refresh_navigation()
	return anchor


func _place_world_prompt(anchor: Variant) -> void:
	var hint: Label3D = arena["interact_hint"]
	hint.visible = anchor != null
	if hint.visible:
		hint.global_position = anchor
		hint.text = B.event_text("interact")


func _update_inspection_collision(before: AABB, current: AABB) -> void:
	for boxes: Array in [arena["camera_solids"], arena["blade_boxes"]]:
		if before.has_volume():
			boxes.erase(before)
		if current.has_volume():
			boxes.append(current)


func _shutter_blocks_ground(box: AABB) -> bool:
	return box.has_volume() and box.position.y < PLAYER_HEIGHT


func _set_interaction_prompt(text: String) -> void:
	if _interaction_prompt == text:
		return
	_interaction_prompt = text
	interaction_changed.emit(text)


func _set_beacons(power: float) -> void:
	for light: OmniLight3D in arena["beacons"]:
		light.light_energy = power
	var signal_mat: StandardMaterial3D = arena["beacon_material"]
	signal_mat.emission_energy_multiplier = 0.16 + 0.85 * power


func _stop_alarm() -> void:
	if _alarm_voice >= 0:
		Snd.stop(_alarm_voice)
		_alarm_voice = -1


func player_can_act() -> bool:
	return super.player_can_act() or state == "evacuate"


func _ladder_available() -> bool:
	return player.alive and state in ["intro", "alert", "fight", "evacuate"] 		and player.rig.jump_state in ["GROUND", "LANDING"] 		and not player.rig.is_attacking and player.rig.dash_time <= 0.0 		and service_ladder.available(player.rig.global_position, cam.flat_forward())


func step_service_ladder(dt: float) -> bool:
	if not service_ladder.active:
		if not B.just("interact") or not _ladder_available():
			return false
		service_ladder.begin(player.rig.global_position, player.rig.heading)
		player.begin_service_climb()
	service_ladder.step(dt, -B.move_vector().y)
	player.step_service_climb(dt, service_ladder.at, service_ladder.yaw,
		service_ladder.weight, service_ladder.active)
	player_previous = service_ladder.at
	if not service_ladder.active:
		player.sync_opening_handoff()
	return true


func on_player_died() -> void:
	service_ladder.active = false
	player.rig.reset_ladder_pose()
	super.on_player_died()


func constrain_player() -> void:
	var rig = player.rig
	var grounded: bool = rig.jump_state in ["GROUND", "LANDING"]
	var resolved := resolve_motion(player_previous, rig.global_position, grounded)
	if state == "fight" and enemies[0].alive:
		var enemy_at: Vector3 = enemies[0].ground_position()
		var offset := (resolved - enemy_at) * Vector3(1, 0, 1)
		if absf(resolved.y - enemy_at.y) < 3.0 and offset.length_squared() < 2.6 * 2.6:
			if offset.length_squared() < 0.001:
				offset = Vector3.FORWARD
			var separation := enemy_at + offset.normalized() * 2.6
			separation.y = resolved.y
			resolved = resolve_motion(resolved, separation)
	if resolved.y < rig.global_position.y - CONTACT_EPS and rig.vertical_velocity > 0.0:
		rig.vertical_velocity = 0.0
	rig.ground_height = _floor_at(resolved)
	var supported: bool = resolved.y <= rig.ground_height + CONTACT_EPS
	if not supported and rig.jump_state in ["GROUND", "LANDING"]:
		rig.jump_state = "AIR"
		rig.jump_t = 0.0
		rig.air_time = 0.0
		rig.vertical_velocity = 0.0
	elif supported and rig.jump_state == "AIR" and rig.vertical_velocity <= 0.0:
		resolved.y = rig.ground_height
		rig.jump_state = "LANDING"
		rig.jump_t = 0.0
		rig.vertical_velocity = 0.0
	rig.weapon_xf.origin += resolved - rig.global_position
	rig.global_position = resolved
	player_previous = resolved


func resolve_motion(from: Vector3, target: Vector3, grounded := false) -> Vector3:
	var count := maxi(1, ceili(from.distance_to(target) / 0.25))
	var delta := (target - from) / float(count)
	var pos := from
	for _i in count:
		pos.y = _resolve_height(pos, pos.y + delta.y)
		for axis in [0, 2]:
			if is_zero_approx(delta[axis]):
				continue
			var next := pos
			next[axis] += delta[axis]
			if grounded:
				next.y = _service_step_height(pos, next)
			if position_clear(next):
				pos = next
	return pos


func _service_step_height(from: Vector3, to: Vector3) -> float:
	var touches_stairs := false
	var step_up := from.y
	for tread: AABB in arena["service_treads"]:
		var rise := tread.end.y - from.y
		if absf(rise) > STAIR_STEP_HEIGHT:
			continue
		if _overlaps_footprint(to, tread):
			touches_stairs = true
			step_up = maxf(step_up, tread.end.y)
		elif _overlaps_footprint(from, tread):
			touches_stairs = true
	if step_up > from.y:
		return step_up if _resolve_height(from, step_up) >= step_up - CONTACT_EPS else to.y
	if touches_stairs:
		var support := _floor_at(to)
		if support >= from.y - STAIR_STEP_HEIGHT:
			return support
	return to.y


func _resolve_height(pos: Vector3, target_y: float) -> float:
	if is_equal_approx(pos.y, target_y):
		return pos.y
	var height := maxf(target_y, float(arena["floor_y"]))
	var rising := target_y > pos.y
	for box: AABB in arena["camera_solids"]:
		if rising:
			var head_limit := box.position.y - PLAYER_HEIGHT
			if pos.y <= head_limit + CONTACT_EPS and height > head_limit and _overlaps_footprint(pos, box):
				height = minf(height, head_limit)
		elif pos.y >= box.end.y - CONTACT_EPS and height < box.end.y and _overlaps_footprint(pos, box):
			height = maxf(height, box.end.y)
	return height


func _floor_at(pos: Vector3) -> float:
	var floor_y: float = arena["floor_y"]
	for box: AABB in arena["camera_solids"]:
		if box.end.y > floor_y and box.end.y <= pos.y + CONTACT_EPS and _overlaps_footprint(pos, box):
			floor_y = box.end.y
	return floor_y


func position_clear(pos: Vector3) -> bool:
	for box: AABB in arena["camera_solids"]:
		if pos.y >= box.end.y - CONTACT_EPS or pos.y + PLAYER_HEIGHT <= box.position.y + CONTACT_EPS:
			continue
		if _overlaps_footprint(pos, box):
			return false
	return true


func _overlaps_footprint(pos: Vector3, box: AABB) -> bool:
	var near_x := clampf(pos.x, box.position.x, box.end.x)
	var near_z := clampf(pos.z, box.position.z, box.end.z)
	return Vector2(pos.x - near_x, pos.z - near_z).length_squared() < PLAYER_RADIUS * PLAYER_RADIUS


func melee_clear(a: Vector3, b: Vector3) -> bool:
	# Both door leaves move in the blade volume while the navigation grid changes
	# only once they offer sufficient clearance to walk underneath.
	return geometry == null or geometry.segment_clear(a, b)


func combat_targets() -> Array:
	if state == "fight" and enemies[0].alive and melee_clear(
			player.rig.global_position + Vector3.UP * 2.3, enemies[0].center()):
		return enemies
	return []


func constrain_camera() -> void:
	if cam.first_person:
		return
	var focus: Vector3 = player.rig.global_position + Vector3.UP * (2.8)
	var desired := cam.camera.global_position
	var direction := (desired - focus).normalized()
	var nearest := focus.distance_to(desired)
	for box: AABB in arena["camera_solids"]:
		var hit = box.grow(0.18).intersects_segment(focus, desired)
		if hit != null:
			nearest = minf(nearest, maxf(0.15, focus.distance_to(hit) - 0.15))
	cam.camera.global_position = focus + direction * nearest
