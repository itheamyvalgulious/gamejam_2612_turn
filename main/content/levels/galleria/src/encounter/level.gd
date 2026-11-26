extends LevelUnit
const SceneArena = preload("res://src/encounter/arena.gd")
const Sentinel = preload("res://src/game/arc_encounter.gd")
const Sentry = preload("res://src/game/wheel_encounter.gd")
const Duelist = preload("res://src/game/duelist_encounter.gd")
const ACTOR_RADIUS := 1.75
const DUELIST_STEP_HEIGHT := 0.44
const SENTRY_STEP_HEIGHT := 0.37
const SENTINEL_STEP_HEIGHT := 0.38
const SENTINEL_TRACK_RADIUS := 1.20
const SENTRY_ROLL_RADIUS := 1.58
const DUELIST_STRIKE_HEIGHT := 0.87
const STAIR_BLADE_MARGIN := 0.22
const STAIR_ENTRY := Vector3(SceneArena.STAIR_X, 0.0, SceneArena.STAIR_BOTTOM - 1.6)
const STAIR_EXIT := Vector3(SceneArena.STAIR_X, SceneArena.DECK_HEIGHT, SceneArena.STAIR_TOP + 3.2)
const STAIR_ASCENT := Vector3(SceneArena.STAIR_X, 1.5, SceneArena.STAIR_BOTTOM + 5.2)
var nav: AStarGrid2D
var plunge_armed := false
var drop_start_height := 0.0
var was_airborne := false
var rng := RandomNumberGenerator.new()
var player_previous := Vector3.ZERO
var finishing_enemy: Node3D
## 碰撞预计算：把 walkables 的线性查找换成一次性标记，position_clear 每帧
## 会被寻路/移动调用上千次，这是 sentinel 寻路热点的根源。
var _solid_boxes: Array = []
var _solid_walk: PackedByteArray = PackedByteArray()
var _walkable_boxes: Array = []
var _collision_ready := false
## 2m XZ 空间网格：position_clear 只检查附近格子里的碰撞体，结果与全量扫描一致。
const SOLID_CELL := 2.0
var _solid_grid: Dictionary = {}
var _solid_seen: PackedInt32Array = PackedInt32Array()
var _solid_stamp := 0

func start_level(_idx: int) -> void:
	finishing_enemy = null
	index = 0
	var first_start := arena_node == null
	if first_start:
		arena = SceneArena.build("--galleria-height-test" in OS.get_cmdline_user_args())
		arena_node = arena["node"]
		add_child(arena_node)
		preload("res://src/encounter/neon_gi.gd").install(arena_node,not arena["vertical"])
	_rebuild_collision_cache()
	if projectiles != null:
		projectiles.clear_all()
	player.rig.ground_height = arena["player_spawn"].origin.y
	player.reset(arena["player_spawn"])
	plunge_armed = false
	drop_start_height = player.rig.global_position.y
	if nav == null:
		build_navigation()
	player.rig.arena_bounds = Vector2.ZERO
	player_previous = player.rig.global_position
	cam.yaw = 0
	cam.pitch = -0.12
	cam.snap(arena)
	rng.randomize()
	if first_start:
		_spawn_encounters()
	else:
		# Put the player at the spawn before enemies reacquire a target.
		for e in enemies:
			if is_instance_valid(e):
				e.respawn()
	total_enemies = enemies.size()
	state = "fight"
	state_t = 0
	Snd.set_arena(arena)
	if on_level_changed.is_valid():
		on_level_changed.call(0, arena["name_cn"], arena["hint"])


func _spawn_encounters() -> void:
	for entry in arena["encounters"]:
		var enemy
		match entry["kind"]:
			"archer":
				enemy = Sentry.new()
			"duelist":
				enemy = Duelist.new()
			_:
				enemy = Sentinel.new()
		add_child(enemy)
		enemy.level = self
		match entry["kind"]:
			"duelist":
				enemy.setup_duelist(player, _duelist_cover(), arena["bounds"], entry["pos"], entry["health"])
			"archer":
				enemy.global_position = entry["pos"]
				enemy.setup_sentry(PI, 0.95 + float(archers.size()) * 0.35)
				archers.append(enemy)
			_:
				enemy.global_position = arena["anchors"][entry["pad"]] if entry["kind"] == "phase" else entry["pos"]
				enemy.use_ground_routes(sentinel_ground_move, sentinel_support_floor, sentinel_waypoint)
		enemy.spawn_xf = enemy.global_transform
		if enemy.rig != null:
			enemy.spawn_rig_xf = enemy.rig.transform
		enemies.append(enemy)

func step(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	if state == "fight":
		for enemy in enemies:
			var old: Vector3 = enemy.rig.global_position
			enemy.step(dt, ctx)
			if enemy.kind == "duelist" and enemy.alive and not enemy.uses_ground_motion():
				enemy.rig.global_position = resolve_motion(old, enemy.rig.global_position, false)
	elif state == "clear":
		# Finish this independent room; never load the demo's next arena.
		for enemy in enemies:
			enemy.step(dt, ctx)
		var clear_time := 1.60 if is_instance_valid(finishing_enemy) else 1.4
		if state_t > clear_time:
			state = "finished"
	elif state == "dead" and state_t > P.getf("rules.death_delay"):
		start_level(0)

func on_enemy_died(enemy) -> void:
	var was_fighting := state == "fight"
	super.on_enemy_died(enemy)
	if was_fighting and state == "clear" and arena.get("height_test", false):
		finishing_enemy = enemy


func _duelist_cover() -> Array:
	var cover: Array = []
	for box: AABB in arena["solids"]:
		if arena["walkables"].has(box) or absf(box.position.y) > 0.05 or box.size.x >= 35.0 or box.size.z >= 35.0:
			continue
		var radius := Vector2(box.size.x, box.size.z).length() * 0.5
		var at := box.get_center()
		at.y = box.position.y
		cover.append({"c": at, "r": radius + 0.65, "h": box.size.y})
	return cover


func constrain_player() -> void:
	var rig = player.rig
	var resolved := resolve_motion(player_previous,rig.global_position)
	if resolved.y < rig.global_position.y-0.01 and rig.vertical_velocity>0:
		rig.vertical_velocity = 0
	var floor_y := floor_at(resolved,maxf(player_previous.y,resolved.y)+0.45)
	if rig.jump_state in ["GROUND","LANDING"]:
		if resolved.y-floor_y > 0.5:
			rig.jump_state = "AIR"
			rig.vertical_velocity = 0.0
			rig.jump_t = 0.0
		else:
			resolved.y = floor_y
	elif rig.jump_state == "AIR" and rig.vertical_velocity<=0 and resolved.y<=floor_y and player_previous.y>=floor_y-0.1:
		resolved.y = floor_y
		rig.jump_state = "LANDING"
		rig.jump_t = 0.0
		rig.vertical_velocity = 0.0
	rig.ground_height = floor_y
	if plunge_armed and was_airborne and rig.jump_state == "LANDING":
		land_plunge(resolved)
	for enemy in enemies:
		if not enemy.alive or enemy.hit_parts().is_empty() or absf(resolved.y-enemy.ground_position().y)>3:
			continue
		var offset: Vector3 = resolved-enemy.ground_position()
		offset.y = 0
		if offset.length()<2.6:
			if offset.length_squared()<0.001:
				offset = Vector3.FORWARD
			var separation: Vector3 = enemy.ground_position()+offset.normalized()*2.6
			separation.y = resolved.y
			resolved = resolve_motion(resolved,separation)
	rig.weapon_xf.origin += resolved-rig.global_position
	rig.global_position = resolved
	player_previous = resolved

func resolve_motion(from: Vector3, target: Vector3, can_step := true) -> Vector3:
	var count := maxi(1,ceili(Vector2(target.x-from.x,target.z-from.z).length()/0.25))
	var delta := (target-from)/float(count)
	var pos := from
	for i in count:
		pos.y = lerpf(from.y,target.y,float(i+1)/count)
		for axis in [0,2]:
			var next := pos
			next[axis] += delta[axis]
			next.x = clampf(next.x,-SceneArena.HALF_WIDTH+2.3,SceneArena.HALF_WIDTH-2.3)
			next.z = clampf(next.z,-SceneArena.HALF_DEPTH+2.3,SceneArena.HALF_DEPTH-2.3)
			if position_clear(next,ACTOR_RADIUS,can_step):
				pos = next
	pos.y = clampf(target.y,0,SceneArena.CEILING-5.0)
	if target.y>from.y:
		for box: AABB in arena["solids"]:
			if from.y+4.6<=box.position.y and target.y+4.6>box.position.y and Rect2(box.position.x-ACTOR_RADIUS,box.position.z-ACTOR_RADIUS,box.size.x+ACTOR_RADIUS*2,box.size.z+ACTOR_RADIUS*2).has_point(Vector2(pos.x,pos.z)):
				pos.y = minf(pos.y,box.position.y-4.6)
	# Downward sweep also lands on cover tops; no falling through vehicles or cabinets.
	if target.y<from.y:
		for box: AABB in arena["solids"]:
			if from.y>=box.end.y-0.03 and pos.y<box.end.y and Rect2(box.position.x,box.position.z,box.size.x,box.size.z).has_point(Vector2(pos.x,pos.z)):
				pos.y = box.end.y
	return pos

func _rebuild_collision_cache() -> void:
	_solid_boxes.clear()
	_solid_walk.clear()
	_walkable_boxes.clear()
	var walkable_set := {}
	for box: AABB in arena.get("walkables", []):
		walkable_set[box] = true
		_walkable_boxes.append(box)
	for box: AABB in arena.get("solids", []):
		_solid_boxes.append(box)
		_solid_walk.append(1 if walkable_set.has(box) else 0)
	_solid_grid.clear()
	for i in _solid_boxes.size():
		var box: AABB = _solid_boxes[i]
		for gx in range(int(floor(box.position.x / SOLID_CELL)), int(floor(box.end.x / SOLID_CELL)) + 1):
			for gz in range(int(floor(box.position.z / SOLID_CELL)), int(floor(box.end.z / SOLID_CELL)) + 1):
				var key := Vector2i(gx, gz)
				if not _solid_grid.has(key):
					_solid_grid[key] = []
				(_solid_grid[key] as Array).append(i)
	_solid_seen.resize(_solid_boxes.size())
	_solid_stamp = 0
	_collision_ready = true


func position_clear(pos: Vector3, radius := ACTOR_RADIUS, can_step := true) -> bool:
	if not _collision_ready:
		_rebuild_collision_cache()
	_solid_stamp += 1
	if _solid_stamp >= 0x3FFFFFFF:
		_solid_seen.fill(0)
		_solid_stamp = 1
	var x0 := int(floor((pos.x - radius) / SOLID_CELL))
	var x1 := int(floor((pos.x + radius) / SOLID_CELL))
	var z0 := int(floor((pos.z - radius) / SOLID_CELL))
	var z1 := int(floor((pos.z + radius) / SOLID_CELL))
	for gx in range(x0, x1 + 1):
		for gz in range(z0, z1 + 1):
			var cell = _solid_grid.get(Vector2i(gx, gz))
			if cell == null:
				continue
			for index: int in cell:
				if _solid_seen[index] == _solid_stamp:
					continue
				_solid_seen[index] = _solid_stamp
				var box: AABB = _solid_boxes[index]
				var walk := _solid_walk[index] != 0
				var step_height := 0.45 if can_step and walk else 0.05
				if pos.y >= box.end.y - step_height or pos.y + 4.6 <= box.position.y:
					continue
				# Tread noses have zero horizontal padding: support is resolved at the actor center.
				var padding := 0.0 if can_step and walk else radius
				if Rect2(box.position.x-padding, box.position.z-padding,
						box.size.x+padding*2, box.size.z+padding*2).has_point(Vector2(pos.x, pos.z)):
					return false
	return true

func phase_visible(enemy) -> bool:
	if cam == null or cam.camera == null:
		return false
	# Test actual body samples, not only an oversized bounding sphere.
	for offset in [Vector3(0,2.3,0), Vector3(0,3.8,0), Vector3(-1.0,2.5,0), Vector3(1.0,2.5,0), Vector3(0,1,0)]:
		var point: Vector3 = enemy.center() + offset - Vector3.UP * 2.3
		if not cam.camera.is_position_in_frustum(point):
			continue
		var blocked := false
		for box: AABB in arena["solids"]:
			if box.intersects_segment(cam.camera.global_position, point) != null:
				blocked = true
				break
		if not blocked:
			return true
	return false

func choose_phase_point(enemy) -> int:
	var choices: Array[int] = []
	for i in arena["anchors"].size():
		if i == enemy.anchor_index:
			continue
		var pos: Vector3 = arena["anchors"][i]
		if pos.distance_to(player.rig.global_position) < ACTOR_RADIUS*2.0:
			continue
		var occupied := false
		for other in enemies:
			if other != enemy and other.alive and other.ground_position().distance_to(pos) < ACTOR_RADIUS*2.0:
				occupied = true
				break
		if not occupied:
			choices.append(i)
	return -1 if choices.is_empty() else choices[rng.randi_range(0,choices.size()-1)]




func melee_clear(a: Vector3, b: Vector3) -> bool:
	for box: AABB in _solid_boxes:
		if box.intersects_segment(a, b) != null:
			return false
	return true

func combat_targets() -> Array:
	var targets: Array = []
	for enemy in enemies:
		if enemy.alive and melee_clear(player.rig.global_position+Vector3(0,2.3,0), enemy.center()):
			targets.append(enemy)
	return targets

func constrain_camera() -> void:
	var focus: Vector3 = player.rig.global_position + Vector3(0,2.8,0)
	var desired := cam.camera.global_position
	desired.x = clampf(desired.x,-SceneArena.HALF_WIDTH+0.5,SceneArena.HALF_WIDTH-0.5)
	desired.y = clampf(desired.y,0.3,SceneArena.CEILING-0.5)
	desired.z = clampf(desired.z,-SceneArena.HALF_DEPTH+0.5,SceneArena.HALF_DEPTH-0.5)
	var direction := (desired-focus).normalized()
	var nearest := focus.distance_to(desired)
	for box: AABB in arena["solids"]:
		var hit = box.grow(0.22).intersects_segment(focus,desired)
		if hit != null:
			nearest = minf(nearest, maxf(0.1, focus.distance_to(hit)-0.15))
	cam.camera.global_position = focus + direction*nearest

func build_navigation() -> void:
	nav = AStarGrid2D.new()
	nav.region = Rect2i(-23,-23,47,47)
	nav.cell_size = Vector2(1.5,1.5)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for x in range(-23,24):
		for z in range(-23,24):
			var p := Vector3(x*1.5,0,z*1.5)
			var blocked := not position_clear(p,2.1,false)
			blocked = blocked or absf(p.x)>SceneArena.HALF_WIDTH-3 or absf(p.z)>SceneArena.HALF_DEPTH-3
			nav.set_point_solid(Vector2i(x,z),blocked)

func nearest_cell(pos: Vector3) -> Vector2i:
	var start := Vector2i(clampi(roundi(pos.x/1.5),-23,23),clampi(roundi(pos.z/1.5),-23,23))
	if not nav.is_point_solid(start):
		return start
	var best := start
	var distance := INF
	for x in range(-23,24):
		for z in range(-23,24):
			var cell := Vector2i(x,z)
			if not nav.is_point_solid(cell) and Vector2(cell-start).length_squared()<distance:
				best = cell
				distance = Vector2(cell-start).length_squared()
	return best

func navigation_direction(position_at: Vector3, goal: Vector3, heading: Vector3) -> Vector3:
	if nav == null or position_clear(position_at + heading * 2.0, 2.1, false) and melee_clear(position_at + Vector3.UP, goal + Vector3.UP):
		return heading
	var path := nav.get_point_path(nearest_cell(position_at), nearest_cell(goal))
	for point in path:
		var direction := Vector3(point.x - position_at.x, 0.0, point.y - position_at.z)
		if direction.length() > 0.9:
			return direction.normalized()
	return heading


func duelist_on_stairs(at: Vector3) -> bool:
	return absf(at.x - SceneArena.STAIR_X) < SceneArena.STAIR_WIDTH * 0.5 \
		and at.z >= SceneArena.STAIR_BOTTOM and at.z < SceneArena.STAIR_TOP


func duelist_stair_lane(at: Vector3) -> Vector2:
	# Include the approach and the upper landing where a cut can still reach the rails.
	var half_width := SceneArena.STAIR_WIDTH * 0.5
	if absf(at.x - SceneArena.STAIR_X) > half_width + 0.4 \
			or at.z < SceneArena.STAIR_BOTTOM - 1.4 or at.z > STAIR_EXIT.z + 1.7:
		return Vector2.INF
	# The left side opens into the platform at the top of the rail.
	var left_edge := SceneArena.STAIR_X - half_width + STAIR_BLADE_MARGIN
	left_edge -= 5.0 * smoothstep(SceneArena.STAIR_TOP, STAIR_EXIT.z, at.z)
	return Vector2(left_edge, SceneArena.STAIR_X + half_width - STAIR_BLADE_MARGIN)


func duelist_blade_clear(heel: Vector3, tip: Vector3) -> bool:
	var span := AABB(heel, Vector3.ZERO).expand(tip).grow(0.14)
	for box: AABB in arena["solids"]:
		if box.intersects(span) and box.grow(0.14).intersects_segment(heel, tip) != null:
			return false
	return true


func duelist_floor(at: Vector3, ceiling: float) -> float:
	var height := 0.0
	for box: AABB in _walkable_boxes:
		if box.end.y <= ceiling and Rect2(box.position.x, box.position.z, box.size.x, box.size.z).has_point(Vector2(at.x, at.z)):
			height = maxf(height, box.end.y)
	return height


func sentinel_ground_move(from: Vector3, goal: Vector3) -> Vector3:
	return _supported_motion(from, goal, SENTINEL_TRACK_RADIUS, SENTINEL_STEP_HEIGHT, 0.06)


func sentinel_support_floor(at: Vector3) -> float:
	return floor_at(at, at.y + 0.04)


func sentinel_waypoint(from: Vector3, goal: Vector3) -> Vector3:
	var from_stairs := duelist_on_stairs(from)
	var goal_stairs := duelist_on_stairs(goal)
	var from_upper := from.y >= SceneArena.DECK_HEIGHT - SENTINEL_STEP_HEIGHT
	var goal_upper := goal.y >= SceneArena.DECK_HEIGHT - SENTINEL_STEP_HEIGHT
	if not from_stairs and not from_upper and (goal_stairs or goal_upper):
		var at_entry := absf(from.x - STAIR_ENTRY.x) < 1.0 and from.z < SceneArena.STAIR_BOTTOM \
			and from.z >= STAIR_ENTRY.z - 1.0
		if not at_entry:
			return _sentinel_ground_waypoint(from, STAIR_ENTRY)
	if from_stairs or goal_stairs or from_upper or goal_upper:
		return duelist_route_point(from, goal, true)
	return _sentinel_ground_waypoint(from, goal)


func _sentinel_ground_waypoint(from: Vector3, goal: Vector3) -> Vector3:
	var offset := (goal - from).slide(Vector3.UP)
	var probe := from + offset.limit_length(4.0)
	if melee_clear(from + Vector3.UP, goal + Vector3.UP) \
			and sentinel_ground_move(from, probe).distance_to(probe) < 0.06:
		return goal
	var path := nav.get_point_path(nearest_cell(from), nearest_cell(goal))
	# Prefer a clear point farther along the path so grid rounding cannot pull the
	# tracks back to the start cell at a corner.
	for i in range(mini(path.size() - 1, 4), -1, -1):
		var point := Vector3(path[i].x, from.y, path[i].y)
		if point.distance_squared_to(from) < 0.12:
			continue
		if sentinel_ground_move(from, point).distance_to(point) < 0.06:
			return point
	return from


func sentry_ground_move(from: Vector3, goal: Vector3) -> Vector3:
	return _supported_motion(from, goal, SENTRY_ROLL_RADIUS, SENTRY_STEP_HEIGHT)


func duelist_ground_move(from: Vector3, goal: Vector3) -> Vector3:
	return _supported_motion(from, goal, ACTOR_RADIUS, DUELIST_STEP_HEIGHT)


func _supported_motion(from: Vector3, goal: Vector3, radius: float, step_height: float, sample_distance := 0.24) -> Vector3:
	# Sample the treads in order so a path cannot skip over a gap.
	var offset := (goal - from).slide(Vector3.UP)
	var count := maxi(1, ceili(offset.length() / sample_distance))
	var position := from
	for i in range(1, count + 1):
		var next := from + offset * (float(i) / count)
		next.y = duelist_floor(next, position.y + step_height)
		if position.y - next.y > step_height or not position_clear(next, radius, true):
			break
		position = next
	return position


func duelist_can_strike(from: Vector3, goal: Vector3) -> bool:
	if absf(from.y - goal.y) > DUELIST_STRIKE_HEIGHT:
		return false
	return melee_clear(from + Vector3.UP * 2.3, goal + Vector3.UP * 2.3)


func duelist_can_rush(from: Vector3, goal: Vector3, clearance: float) -> bool:
	if not duelist_stair_lane(goal).is_finite():
		return false
	var heading := (goal - from).slide(Vector3.UP).normalized()
	var landing := goal - heading * clearance
	var ground := duelist_ground_move(from, landing)
	return ground.slide(Vector3.UP).distance_to(landing.slide(Vector3.UP)) < 0.35 and duelist_can_strike(ground, goal)


func duelist_needs_route(from: Vector3, goal: Vector3) -> bool:
	return duelist_stair_lane(from).is_finite() or duelist_stair_lane(goal).is_finite() or not duelist_can_strike(from, goal)


func duelist_route_point(from: Vector3, goal: Vector3, flowing := false) -> Vector3:
	var from_stairs := duelist_on_stairs(from)
	var goal_stairs := duelist_on_stairs(goal)
	var from_upper := from.y >= SceneArena.DECK_HEIGHT - DUELIST_STEP_HEIGHT and not from_stairs
	var goal_upper := goal.y >= SceneArena.DECK_HEIGHT - DUELIST_STEP_HEIGHT and not goal_stairs
	if flowing and goal_upper and from.z > SceneArena.STAIR_TOP - 1.0 and from.z < STAIR_EXIT.z - 0.3 \
		and from.y >= SceneArena.DECK_HEIGHT - DUELIST_STEP_HEIGHT and absf(from.x - SceneArena.STAIR_X) < SceneArena.STAIR_WIDTH * 0.5:
		# Start cutting across the deck as soon as the whole diagonal clears the last guard.
		var merge := Vector3(lerpf(SceneArena.STAIR_X, goal.x, 0.14), SceneArena.DECK_HEIGHT, STAIR_EXIT.z + 1.2)
		if duelist_ground_move(from, merge).distance_to(merge) < 0.12:
			return merge
	if from_stairs:
		if goal_stairs:
			return Vector3(SceneArena.STAIR_X, goal.y, goal.z)
		return STAIR_EXIT if goal_upper else STAIR_ENTRY
	if from_upper:
		if goal_upper:
			# Finish clearing the padded stair guards before cutting across the deck.
			if from.z < STAIR_EXIT.z - 0.3 and absf(from.x - SceneArena.STAIR_X) < SceneArena.STAIR_WIDTH * 0.5:
				return STAIR_EXIT
			return goal
		if absf(from.x - SceneArena.STAIR_X) > 1.0 or from.z > STAIR_EXIT.z + 1.0:
			return STAIR_EXIT
		return Vector3(SceneArena.STAIR_X, 6.4, SceneArena.STAIR_TOP - 4.8)
	if goal_stairs or goal_upper:
		if flowing and from.z < SceneArena.STAIR_BOTTOM and from.z > STAIR_ENTRY.z - 4.0 \
			and absf(from.x - SceneArena.STAIR_X) < 5.0:
			# Skip the corner point when a continuous diagonal can feed into the stair lane.
			var merge := Vector3(SceneArena.STAIR_X, 0.57, SceneArena.STAIR_BOTTOM + 1.5)
			if duelist_ground_move(from, merge).distance_to(merge) < 0.16:
				return merge
		if absf(from.x - SceneArena.STAIR_X) < 1.0 and from.z < SceneArena.STAIR_BOTTOM and from.z >= STAIR_ENTRY.z - 1.0:
			return STAIR_ASCENT
		return _duelist_lower_waypoint(from, STAIR_ENTRY)
	return _duelist_lower_waypoint(from, goal)


func _duelist_lower_waypoint(from: Vector3, goal: Vector3) -> Vector3:
	var toward := (goal - from).slide(Vector3.UP)
	if toward.length_squared() < 0.001:
		return goal
	var near := from + toward.limit_length(4.5)
	if duelist_ground_move(from, near).distance_to(near) < 0.12 and melee_clear(from + Vector3.UP, goal + Vector3.UP):
		return goal
	var cells := nav.get_point_path(nearest_cell(from), nearest_cell(goal))
	var waypoint := from
	for i in range(mini(cells.size(), 6)):
		var point := Vector3(cells[i].x, from.y, cells[i].y)
		if point.distance_to(from) < 0.65:
			continue
		if duelist_ground_move(from, point).distance_to(point) > 0.18:
			break
		waypoint = point
	return waypoint


func floor_at(pos: Vector3, max_height: float) -> float:
	var height := 0.0
	for box: AABB in _solid_boxes:
		if box.end.y <= max_height and Rect2(box.position.x,box.position.z,box.size.x,box.size.z).has_point(Vector2(pos.x,pos.z)):
			height = maxf(height,box.end.y)
	return height

func prepare_player() -> void:
	var rig = player.rig
	var pos: Vector3 = rig.global_position
	was_airborne = rig.jump_state == "AIR"
	if rig.jump_state == "GROUND":
		drop_start_height = pos.y
	rig.ground_height = floor_at(pos,pos.y+0.45)
	if arena.get("vertical",false) and rig.jump_state == "AIR" and drop_start_height>=6.0 and pos.y-rig.ground_height>1.0 and B.just("attack_light") and not plunge_armed:
		arm_plunge()

func arm_plunge() -> void:
	plunge_armed = true
	player.rig.vertical_velocity = minf(player.rig.vertical_velocity,-18.0)
	player.rig.play_action("plunge", 0.0)
	player.last_attack = "heavy"
	player.swing_serial += 1
	Fx.beam(player.rig.global_position+Vector3(0,4,0),player.rig.global_position,0.15,Color("79dbe7"))

func land_plunge(pos: Vector3) -> void:
	plunge_armed = false
	if drop_start_height-pos.y < 3.0:
		return
	Fx.impact_ring(pos+Vector3(0,0.12,0),7.0,1.5)
	Fx.shake(0.65)
	Snd.play_at("hit",pos,{"gain":1.1})
	for enemy in enemies:
		if enemy.alive and enemy.ground_position().distance_to(pos)<7.0 and melee_clear(pos+Vector3(0,1.5,0),enemy.center()):
			enemy.hurt(90.0,enemy.rig.global_position-pos,1.2)

func separate_enemies() -> void:
	for enemy in enemies:
		if not enemy.alive or enemy.kind=="phase":
			continue
		var old: Vector3 = enemy.rig.global_position
		var pos := old
		for other in enemies:
			if other==enemy or not other.alive:
				continue
			var away: Vector3 = pos-other.ground_position()
			away.y = 0
			var dist := away.length()
			if dist<3.2:
				if dist<0.001:
					away = Vector3.RIGHT if enemy.get_instance_id()>other.get_instance_id() else Vector3.LEFT
			pos = resolve_motion(pos,pos+away.normalized()*(3.2-dist)*0.55,false)
		enemy.rig.global_position = pos


func clamp_enemy_position(point: Vector3, _scale_factor: float = 1.0) -> Vector3:
	return resolve_motion(point, point, false) if position_clear(point, 1.8, false) else Vector3.INF


func duelist_defeat_path(start: Vector3, direction: Vector3) -> Dictionary:
	var samples: Array[Vector3] = [start]
	var best := _defeat_rest(start, direction)
	var best_count := 1
	for step in range(1, 21):
		var candidate := start + direction * (float(step) * 0.24)
		var previous := samples[-1]
		candidate.y = _defeat_support(candidate, minf(start.y + 1.10, previous.y + 0.44))
		if candidate.y < previous.y - 0.55 or not _defeat_clear(candidate, 1.26, 3.8):
			break
		samples.append(candidate)
		var rest := _defeat_rest(candidate, direction)
		if not rest.is_empty():
			best = rest
			best_count = samples.size()
	if best.is_empty():
		var inward := Vector3(-start.x, 0.0, -start.z).normalized()
		best = {"facing": inward if not inward.is_zero_approx() else direction,
			"normal": Vector3.UP, "compact": true, "support_lift": 0.0}
	best["samples"] = samples.slice(0, best_count)
	return best


func _defeat_rest(center: Vector3, forward: Vector3) -> Dictionary:
	for degrees: float in [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
		var facing := forward.rotated(Vector3.UP, deg_to_rad(degrees))
		var across := facing.cross(Vector3.UP)
		var head := center + facing * 2.77
		var feet := center - facing * 2.00
		head.y = _defeat_support(head, center.y + 1.02)
		feet.y = _defeat_support(feet, center.y + 1.02)
		if absf(head.y - center.y) > 0.96 or absf(feet.y - center.y) > 0.96:
			continue
		if not _defeat_clear(head, 0.82, 0.98) or not _defeat_clear(feet, 0.82, 0.78):
			continue
		var legs_clear := true
		for side: float in [-1.0, 1.0]:
			var foot := feet + across * 0.96 * side
			foot.y = _defeat_support(foot, center.y + 1.02)
			legs_clear = legs_clear and absf(foot.y - feet.y) <= 0.50 and _defeat_clear(foot, 0.66, 0.80)
		if not legs_clear:
			continue
		if not _defeat_clear(center, 1.02, 1.2):
			continue
		var rise := (head.y - feet.y) / 4.77
		var up := (Vector3.UP - facing * rise).normalized()
		# Fit the support plane above the discrete stair noses as well as the endpoints.
		var lift := 0.0
		for offset: float in [-1.65, -0.8, 0.55, 1.15, 1.80, 2.45]:
			var along := center + facing * offset
			var height := _defeat_support(along, center.y + 1.02)
			lift = maxf(lift, height - center.y - rise * offset)
		return {"facing": facing, "normal": up, "compact": false, "support_lift": minf(lift, 0.31)}
	return {}


func _defeat_support(at: Vector3, ceiling: float) -> float:
	var top := Vector3(at.x, ceiling + 0.01, at.z)
	var ray := PhysicsRayQueryParameters3D.create(top, Vector3(at.x, -0.42, at.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.54:
		return (hit["position"] as Vector3).y
	return floor_at(at, ceiling)


func _defeat_clear(at: Vector3, radius: float, height: float) -> bool:
	if absf(at.x) > SceneArena.HALF_WIDTH - radius or absf(at.z) > SceneArena.HALF_DEPTH - radius:
		return false
	for box: AABB in arena["solids"]:
		if box.end.y <= at.y + 0.045 or box.position.y >= at.y + height:
			continue
		if arena["walkables"].has(box) and box.end.y <= at.y + 0.18 + radius * 0.37:
			continue
		var footprint := Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(radius)
		if footprint.has_point(Vector2(at.x, at.z)):
			return false
	return true
