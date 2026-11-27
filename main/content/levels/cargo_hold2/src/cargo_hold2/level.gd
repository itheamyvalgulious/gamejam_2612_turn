extends LevelUnit

signal opening_reset
signal radio_line(text: String, duration: float, emergency: bool)
signal instruction_changed(text: String)

const CargoArena = preload("res://src/cargo_hold2/arena.gd")
const Sentinel = preload("res://src/game/arc_encounter.gd")
const LevelDeathField = preload("res://core/death_field.gd")
const ACTOR_RADIUS := 1.75
const GATE_OPEN_TIME := 0.9

var player_previous := Vector3.ZERO
var _practice_prompt := false
var _practice_contact := false
var _practice_serial := -1
var _guard_tip := false
var _route_sent := false
var _radio_cut := false
var _radio_opened := false
var _gate_locked := true
var _alarm_due := 0.0
var _alarm_voice := -1


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
	player.reset(arena["player_spawn"])
	player.rig.arena_bounds = Vector2.ZERO
	player_previous = player.rig.global_position
	cam.yaw = 0
	cam.pitch = -0.16
	cam.wake_offset = -1.05
	cam.snap(arena)
	total_enemies = enemies.size()
	_practice_prompt = false
	_practice_contact = false
	_practice_serial = -1
	_guard_tip = false
	_route_sent = false
	_radio_cut = false
	_radio_opened = false
	_alarm_due = 0.0
	_stop_alarm()
	# The moving gate already has its own collider for debris.
	LevelDeathField.install(self)
	_set_gate_locked(true)
	arena["guide"].hide()
	_set_beacons(0.0)
	state = "intro"
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


func step(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	match state:
		"intro":
			_step_opening()
		"fight":
			_step_sentinel(dt, ctx)
		"evacuate":
			_step_evacuation(dt, ctx)
		"clear":
			_step_sentinel(dt, ctx)
			if state_t >= 0.48:
				state = "finished"


func _step_opening() -> void:
	cam.wake_offset = -1.05 * (1.0 - smoothstep(0.0, 1.22, state_t))
	if not _radio_opened:
		_radio_opened = true
		Snd.play_at("cargo_radio", player.rig.global_position, {"gain": 0.62, "prio": 3})
		radio_line.emit("Sivi？是我，Nova。你先试着走出集装箱。", 4.7, false)
		var keys := [B.event_text("move_forward"), B.event_text("move_left"),
			B.event_text("move_back"), B.event_text("move_right")]
		instruction_changed.emit("%s  ·  移动" % " / ".join(keys))
	var pos: Vector3 = player.rig.global_position
	if pos.z < 28.2 and not _practice_prompt:
		_practice_prompt = true
		radio_line.emit("记忆还没传完。先动一动义体，试试你的刀。", 4.4, false)
		instruction_changed.emit("%s  ·  挥刀试刃" % B.event_text("attack_light"))
	if pos.z < 9.0:
		cam.wake_offset = 0.0
		state = "fight"
		state_t = 0.0
		enemies[0].show()
		Snd.play_at("cargo_alarm", enemies[0].ground_position(), {"gain": 0.64, "prio": 4})
		radio_line.emit("是旧型号的巡检哨兵。小心它的红眼。", 4.1, false)
		instruction_changed.emit("击倒 ARC Sentinel")


func _step_sentinel(dt: float, ctx: Dictionary) -> void:
	enemies[0].step(dt, ctx)


func on_guard_contact() -> void:
	if _guard_tip or state != "fight":
		return
	_guard_tip = true
	radio_line.emit("那是麦克斯韦之瞳。把它移出画面，再从侧面出刀。", 5.0, false)
	var prompt := "移开视线  ·  侧斩哨兵"
	if not cam.first_person:
		prompt = "%s  ·  切换第一人称  /  试着侧斩" % B.event_text("cam_mode")
	instruction_changed.emit(prompt)


func check_practice_contact() -> void:
	var rig = player.rig
	if state != "intro" or not _practice_prompt or not rig.in_hit_window() or player.swing_serial == _practice_serial:
		return
	var parts: Array = []
	for x in [-0.74, 0.0, 0.74]:
		var point := CargoArena.TARGET + Vector3(x, 0, 0.19)
		parts.append({"a": point - Vector3.UP * 0.51, "b": point + Vector3.UP * 0.51, "r": 0.36})
	var contact := Hit.sweep_blade_parts(rig.weapon_prev_xf, rig.weapon_xf, rig.blade_proxy, parts)
	if not contact.get("hit", false) or not player.blade_terrain.allows_hit(rig, contact):
		return
	_practice_serial = player.swing_serial
	Snd.play_at("clang", contact["point"], {"gain": 0.73})
	Fx.spark(contact["point"], contact["normal"], 0.77)
	if not _practice_contact:
		_practice_contact = true
		instruction_changed.emit("沿装卸标线进入主舱")


func on_enemy_died(_enemy) -> void:
	if state != "fight":
		return
	state = "evacuate"
	state_t = 0.0
	_alarm_due = 0.0
	arena["guide"].show()
	_set_beacons(3.0)
	radio_line.emit("安保警报。人员气闸已解锁。", 1.7, true)
	instruction_changed.emit("沿青色箭头撤离  ·  前往中庭")


func _step_evacuation(dt: float, ctx: Dictionary) -> void:
	_step_sentinel(dt, ctx)
	var gate: Node3D = arena["gate"]["panel"]
	gate.position.y = 7.95 * smoothstep(0.0, GATE_OPEN_TIME, state_t)
	if _gate_locked and state_t >= GATE_OPEN_TIME:
		_set_gate_locked(false)
	_alarm_due -= dt
	if _alarm_due <= 0.0:
		_alarm_voice = Snd.play_at("cargo_alarm", Vector3(9, 5.5, -19), {"gain": 1.04, "prio": 4})
		_alarm_due = 2.3
	var pulse := 0.5 + 0.5 * sin(state_t * TAU * 0.67)
	_set_beacons(0.68 + 3.1 * pulse * pulse)
	if state_t >= 1.7 and not _route_sent:
		_route_sent = true
		radio_line.emit("路线发给你了。到实验室去，那里有——", 3.1, false)
	if state_t >= 4.6 and not _radio_cut:
		_radio_cut = true
		Snd.play_at("cargo_radio", player.rig.global_position, {"gain": 0.76, "prio": 4})
		radio_line.emit("……通信中断。", 1.8, false)
	var at: Vector3 = player.rig.global_position
	if not _gate_locked and CargoArena.EXIT_TRIGGER.has_point(Vector2(at.x, at.z)):
		_stop_alarm()
		_set_beacons(0.0)
		instruction_changed.emit("")
		state = "clear"
		state_t = 0.0


func _set_gate_locked(locked: bool) -> void:
	var gate: Dictionary = arena["gate"]
	var passage_solids: Array = arena["solids"]
	var camera_solids: Array = arena["camera_solids"]
	passage_solids.erase(gate["box"])
	camera_solids.erase(gate["box"])
	if locked:
		passage_solids.append(gate["box"])
		camera_solids.append(gate["box"])
		gate["panel"].position.y = 0.0
	gate["collider"].get_child(0).set_deferred("disabled", not locked)
	_gate_locked = locked
	nav = NavField.build(arena, CargoArena.nav_spec())
	geometry = LevelGeometry.build(arena)


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


func constrain_player() -> void:
	var resolved := resolve_motion(player_previous, player.rig.global_position)
	if state == "fight" and enemies[0].alive:
		var enemy_at: Vector3 = enemies[0].ground_position()
		var offset := (resolved - enemy_at) * Vector3(1, 0, 1)
		if offset.length() < 2.6:
			if offset.length_squared() < 0.001:
				offset = Vector3.FORWARD
			var separation := enemy_at + offset.normalized() * 2.6
			separation.y = resolved.y
			resolved = resolve_motion(player_previous, separation)
	if resolved.y < player.rig.global_position.y and player.rig.vertical_velocity > 0.0:
		player.rig.vertical_velocity = 0.0
	player.rig.weapon_xf.origin += resolved - player.rig.global_position
	player.rig.global_position = resolved
	player_previous = resolved


func resolve_motion(from: Vector3, target: Vector3) -> Vector3:
	var distance := Vector2(target.x - from.x, target.z - from.z).length()
	var count := maxi(1, ceili(distance / 0.3))
	var delta := (target - from) / float(count)
	var pos := from
	for i in count:
		for axis in [0, 2]:
			var next := pos
			next[axis] += delta[axis]
			next.x = clampf(next.x, -CargoArena.HALF_WIDTH + 3.0, CargoArena.HALF_WIDTH - 3.0)
			next.z = clampf(next.z, -CargoArena.HALF_DEPTH + 3.0, CargoArena.HALF_DEPTH - 3.0)
			if position_clear(next):
				pos = next
	var ceiling := CargoArena.CEILING - 5.0
	for box: AABB in arena["headroom"]:
		var footprint := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		if footprint.grow(0.7).has_point(Vector2(pos.x, pos.z)):
			ceiling = minf(ceiling, box.position.y - 4.3)
	pos.y = clampf(target.y, 0.0, ceiling)
	return pos


func position_clear(pos: Vector3, radius := ACTOR_RADIUS) -> bool:
	for box: AABB in arena["solids"]:
		var expanded := Rect2(box.position.x - radius, box.position.z - radius,
			box.size.x + radius * 2.0, box.size.z + radius * 2.0)
		if expanded.has_point(Vector2(pos.x, pos.z)):
			return false
	return true


func combat_targets() -> Array:
	if state == "fight" and enemies[0].alive and melee_clear(
			player.rig.global_position + Vector3.UP * 2.3, enemies[0].center()):
		return enemies
	return []


func constrain_camera() -> void:
	if cam.first_person:
		return
	var focus: Vector3 = player.rig.global_position + Vector3.UP * (2.8 + cam.wake_offset)
	var desired := cam.camera.global_position
	var direction := (desired - focus).normalized()
	var nearest := focus.distance_to(desired)
	for box: AABB in arena["camera_solids"]:
		var hit = box.grow(0.18).intersects_segment(focus, desired)
		if hit != null:
			nearest = minf(nearest, maxf(0.15, focus.distance_to(hit) - 0.15))
	cam.camera.global_position = focus + direction * nearest
