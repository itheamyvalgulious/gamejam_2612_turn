extends LevelUnit
## 街道关卡流程：无敌人，读到东端终点即通关。
## 碰撞、台阶与镜头夹紧沿用城市关卡的做法（见 resolve_motion / position_clear）。

const SceneArena = preload("res://src/encounter/arena.gd")
const ACTOR_RADIUS := 1.75
const M := 1.8281536
const GOAL_RADIUS := 2.8 * M

var player_previous := Vector3.ZERO
var traffic


func start_level(_idx: int) -> void:
	_clear_enemies()
	index = 0
	if arena_node == null:
		arena = SceneArena.build()
		arena_node = arena["node"]
		add_child(arena_node)
		preload("res://src/encounter/neon_gi.gd").install(arena_node, not arena["vertical"])
		_build_traffic()
	player.rig.ground_height = arena["player_spawn"].origin.y
	player.reset(arena["player_spawn"])
	player_previous = player.rig.global_position
	# 出生面向东（+X）：forward = (-sin(yaw), 0, -cos(yaw))
	cam.yaw = -PI * 0.5
	cam.pitch = -0.12
	cam.snap(arena)
	total_enemies = 0
	state = "fight"
	state_t = 0.0
	Snd.set_arena(arena)
	if on_level_changed.is_valid():
		on_level_changed.call(0, String(arena["name_cn"]), String(arena["hint"]))


func _build_traffic() -> void:
	traffic = preload("res://src/traffic/street_traffic.gd").new()
	traffic.name = "StreetTraffic"
	add_child(traffic)
	traffic.build(arena["lanes"])


func step(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	if traffic != null:
		traffic.step(dt)
	if state == "fight":
		if player.alive and player.rig.global_position.distance_to(arena["goal"]) < GOAL_RADIUS:
			state = "clear"
			state_t = 0.0
			Snd.play_at("hit", arena["goal"], {"gain": 0.8})
	elif state == "clear":
		if state_t > 1.4:
			state = "finished"
	elif state == "dead" and state_t > P.getf("rules.death_delay"):
		start_level(0)


func combat_targets() -> Array:
	return []


func constrain_camera() -> void:
	# 开阔街道不需要「沿视线收紧」——那套逻辑拿当前相机位置算距离，切关或瞬移
	# 的那一帧会把镜头锁死在近处（city 关卡的既有问题）。这里只夹边界，
	# 只有相机真的落进实体里时才沿视线推出来。
	var focus: Vector3 = player.rig.global_position + Vector3(0, 2.8 * M, 0)
	var pos := cam.camera.global_position
	pos.x = clampf(pos.x, -SceneArena.HALF_WIDTH + 0.5, SceneArena.HALF_WIDTH - 0.5)
	pos.z = clampf(pos.z, -SceneArena.HALF_DEPTH + 0.5, SceneArena.HALF_DEPTH - 0.5)
	pos.y = clampf(pos.y, 0.3, SceneArena.CEILING - 0.5)
	for box: AABB in arena["solids"]:
		if box.has_point(pos):
			var dir := (pos - focus).normalized()
			pos = focus + dir * maxf(2.0, focus.distance_to(pos) * 0.6)
			break
	cam.camera.global_position = pos


func constrain_player() -> void:
	var rig = player.rig
	var resolved := resolve_motion(player_previous, rig.global_position)
	if resolved.y < rig.global_position.y - 0.01 and rig.vertical_velocity > 0:
		rig.vertical_velocity = 0
	var floor_y := floor_at(resolved, maxf(player_previous.y, resolved.y) + 0.45)
	if rig.jump_state in ["GROUND", "LANDING"]:
		if resolved.y - floor_y > 0.5:
			rig.jump_state = "AIR"
			rig.vertical_velocity = 0.0
			rig.jump_t = 0.0
		else:
			resolved.y = floor_y
	elif rig.jump_state == "AIR" and rig.vertical_velocity <= 0 \
			and resolved.y <= floor_y and player_previous.y >= floor_y - 0.1:
		resolved.y = floor_y
		rig.jump_state = "LANDING"
		rig.jump_t = 0.0
		rig.vertical_velocity = 0.0
	rig.ground_height = floor_y
	rig.weapon_xf.origin += resolved - rig.global_position
	rig.global_position = resolved
	player_previous = resolved


func resolve_motion(from: Vector3, target: Vector3, can_step := true) -> Vector3:
	var count := maxi(1, ceili(Vector2(target.x - from.x, target.z - from.z).length() / 0.25))
	var delta := (target - from) / float(count)
	var pos := from
	for i in count:
		pos.y = lerpf(from.y, target.y, float(i + 1) / count)
		for axis in [0, 2]:
			var next := pos
			next[axis] += delta[axis]
			next.x = clampf(next.x, -SceneArena.HALF_WIDTH + 2.3, SceneArena.HALF_WIDTH - 2.3)
			next.z = clampf(next.z, -SceneArena.HALF_DEPTH + 2.3, SceneArena.HALF_DEPTH - 2.3)
			if position_clear(next, ACTOR_RADIUS, can_step):
				pos = next
	pos.y = clampf(target.y, 0.0, SceneArena.CEILING - 5.0)
	if target.y > from.y:
		for box: AABB in arena["solids"]:
			if from.y + 4.6 <= box.position.y and target.y + 4.6 > box.position.y \
					and Rect2(box.position.x - ACTOR_RADIUS, box.position.z - ACTOR_RADIUS,
						box.size.x + ACTOR_RADIUS * 2, box.size.z + ACTOR_RADIUS * 2) \
					.has_point(Vector2(pos.x, pos.z)):
				pos.y = minf(pos.y, box.position.y - 4.6)
	if target.y < from.y:
		for box: AABB in arena["solids"]:
			if from.y >= box.end.y - 0.03 and pos.y < box.end.y \
					and Rect2(box.position.x, box.position.z, box.size.x, box.size.z) \
					.has_point(Vector2(pos.x, pos.z)):
				pos.y = box.end.y
	return pos


func position_clear(pos: Vector3, radius := ACTOR_RADIUS, can_step := true) -> bool:
	for box: AABB in arena.get("solids", []):
		var step_height := 0.45 if can_step and arena["walkables"].has(box) else 0.05
		if pos.y >= box.end.y - step_height or pos.y + 4.6 <= box.position.y:
			continue
		var padding := 0.0 if can_step and arena["walkables"].has(box) else radius
		if Rect2(box.position.x - padding, box.position.z - padding,
				box.size.x + padding * 2, box.size.z + padding * 2) \
				.has_point(Vector2(pos.x, pos.z)):
			return false
	return true


func floor_at(pos: Vector3, max_height: float) -> float:
	var height := 0.0
	for box: AABB in arena.get("solids", []):
		if box.end.y <= max_height and Rect2(box.position.x, box.position.z,
				box.size.x, box.size.z).has_point(Vector2(pos.x, pos.z)):
			height = maxf(height, box.end.y)
	return height


func prepare_player() -> void:
	var rig = player.rig
	rig.ground_height = floor_at(rig.global_position, rig.global_position.y + 0.45)
