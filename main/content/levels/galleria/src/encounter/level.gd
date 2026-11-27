extends LevelUnit
const SceneArena = preload("res://src/encounter/arena.gd")
const Sentinel = preload("res://src/game/arc_encounter.gd")
const Sentry = preload("res://src/game/wheel_encounter.gd")
const Duelist = preload("res://src/game/duelist_encounter.gd")
const LevelDeathField = preload("res://core/death_field.gd")
const BladeTerrain = preload("res://core/blade_terrain.gd")
const ACTOR_RADIUS := 1.75
const PLAYER_RADIUS := 1.10
const PLAYER_HEIGHT := 3.80
const DUELIST_STEP_HEIGHT := 0.44
const SENTRY_STEP_HEIGHT := 0.37
const SENTINEL_STEP_HEIGHT := 0.38
const SENTINEL_TRACK_RADIUS := 1.20
const GALLERIA_SENTINEL_RADIUS := 1.62
const SENTRY_ROLL_RADIUS := 1.58
const DUELIST_STRIKE_HEIGHT := 0.87
const STAIR_BLADE_MARGIN := 0.22
const STAIR_EXIT := Vector3(SceneArena.STAIR_X, SceneArena.DECK_HEIGHT, SceneArena.STAIR_TOP + 3.2)
## 刀客上半身净空分段（旧 _duelist_body_clear 的元信息版参数）。
const DUELIST_UPPER := {"radius": 1.18, "bottom": 1.10, "top": 4.53}
var plunge_armed := false
var drop_start_height := 0.0
var was_airborne := false
var rng := RandomNumberGenerator.new()
var player_previous := Vector3.ZERO
var finishing_enemy: Node3D
var _plunge_demonstrated := false
var _lab_lift := 0.0
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
		arena = SceneArena.build("--galleria-height-test" in TurnSession.level_arguments())
		arena_node = arena["node"]
		add_child(arena_node)
		if arena["height_test"]:
			preload("res://src/encounter/neon_gi.gd").install(arena_node, false)
	else:
		_set_lab_lift(0.0)
		if arena.has("controls"):
			arena["controls"].reset()
	_plunge_demonstrated = false
	_rebuild_collision_cache()
	if projectiles != null:
		projectiles.clear_all()
	player.rig.ground_height = arena["player_spawn"].origin.y
	player.reset(arena["player_spawn"])
	plunge_armed = false
	drop_start_height = player.rig.global_position.y
	if nav == null:
		nav = NavField.build(arena, SceneArena.nav_spec(arena))
		# 刀客（1.75 半径 + 上半身圆柱）的图只有高低差关用得上：普通中庭只有
		# 哨兵/单轮，预建这棵树在进关时白吃 ~76ms。按实际阵容决定。非高低差时
		# 另按哨兵半径预建一张（上游在哨兵楼梯穿模修复里引入）。
		if bool(arena.get("height_test", false)):
			nav.prewarm_graph(ACTOR_RADIUS, DUELIST_STEP_HEIGHT, DUELIST_UPPER)
		else:
			nav.prewarm_graph(GALLERIA_SENTINEL_RADIUS, NAV_SENTINEL_STEP)
		geometry = LevelGeometry.build(arena)
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
	LevelDeathField.install(self)
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
				var blade := BladeTerrain.new()
				enemy.terrain_blade_step = _constrain_duelist_blade.bind(blade)
				enemy.terrain_blade_reset = blade.reset
				enemy.rig.blade_effect_endpoint = _terrain_blade_endpoint
			"archer":
				enemy.global_position = entry["pos"]
				enemy.setup_sentry(PI, 0.95 + float(archers.size()) * 0.35)
				if not arena["height_test"]:
					enemy.use_ground_pose(_wheel_stair_pose)
				archers.append(enemy)
			_:
				enemy.global_position = arena["anchors"][entry["pad"]] if entry["kind"] == "phase" else entry["pos"]
				enemy.use_ground_routes(sentinel_ground_move, sentinel_support_floor, sentinel_waypoint)
				if not arena["height_test"]:
					enemy.use_ground_pose(_tracked_stair_pose)
		enemy.spawn_xf = enemy.global_transform
		if enemy.rig != null:
			enemy.spawn_rig_xf = enemy.rig.transform
		enemies.append(enemy)

func step(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	if arena.has("controls"):
		arena["controls"].step(dt, cam.fp_transform(), geometry,
			player.alive and state in ["fight", "clear"], enemies, _lab_lift >= 4.65)
	if state in ["fight", "clear"]:
		for enemy in enemies:
			enemy.step(dt, ctx)
	if state == "clear":
		if arena.has("lab"):
			_step_lab_exit()
		else:
			var clear_time := 1.60 if is_instance_valid(finishing_enemy) else 1.4
			if state_t > clear_time:
				state = "finished"
	elif state == "dead" and state_t > P.getf("rules.death_delay"):
		start_level(0)

func on_enemy_died(enemy) -> void:
	if arena.has("controls"):
		arena["controls"].mark_defeat(enemies.find(enemy), enemy.ground_position())
	var was_fighting := state == "fight"
	super.on_enemy_died(enemy)
	if was_fighting and state == "clear" and arena.get("height_test", false):
		finishing_enemy = enemy


func approach_hint() -> String:
	if not arena.has("lab") or _plunge_demonstrated or state != "fight" or not player.alive:
		return ""
	var at: Vector3 = player.rig.global_position
	if (at.y >= 4.0 and at.y <= SceneArena.DECK_HEIGHT + 5.0 and absf(at.x) < 5.2
			and at.z >= 12.0 and at.z <= 22.0):
		return "跃下后按 %s 坠击" % B.event_text("attack_light")
	return ""


func _step_lab_exit() -> void:
	_set_lab_lift(SceneArena.LAB_GATE_STROKE * smoothstep(0.36, 1.54, state_t))
	var at: Vector3 = player.rig.global_position
	if (_lab_lift >= 4.65 and player.alive and at.y < 1.2
			and SceneArena.LAB_EXIT.has_point(Vector2(at.x, at.z))):
		state = "finished"


func _set_lab_lift(height: float) -> void:
	if not arena.has("lab") or is_equal_approx(_lab_lift, height):
		return
	var lab: Dictionary = arena["lab"]
	var shutter: Node3D = lab["shutter"]
	var base: AABB = lab["base"]
	var index: int = lab["index"]
	var before: AABB = arena["solids"][index]
	var after := AABB(base.position + Vector3.UP * height, base.size)
	arena["solids"][index] = after
	# The shutter travels in Y only. The XZ broad-phase cells stay the same.
	_solid_boxes[index] = after
	shutter.position.y = height
	if geometry != null and not geometry.translate_box(before, after.position - before.position):
		geometry = LevelGeometry.build(arena)
	var open := height >= 4.65
	if open != (_lab_lift >= 4.65):
		nav = NavField.build(arena, SceneArena.nav_spec(arena))
		var route: Node3D = lab["route"]
		route.visible = open
		var lamp: StandardMaterial3D = lab["lamp"]
		var color := Color("79d3d7") if open else Color("b68b63")
		lamp.albedo_color = color
		lamp.emission = color
	_lab_lift = height


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
		if not enemy.alive or absf(resolved.y-enemy.ground_position().y)>3 \
				or enemy.hit_parts().is_empty():
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

func resolve_motion(from: Vector3, target: Vector3, can_step := true, player_motion := true) -> Vector3:
	var height_test: bool = arena.get("height_test", false)
	var use_player_body := player_motion and not height_test
	var radius := PLAYER_RADIUS if use_player_body else ACTOR_RADIUS
	var body_height := PLAYER_HEIGHT if use_player_body else 4.6
	var count := maxi(1,ceili(Vector2(target.x-from.x,target.z-from.z).length()/0.25))
	var delta := (target-from)/float(count)
	var pos := from
	for i in count:
		pos.y = lerpf(from.y,target.y,float(i+1)/count)
		for axis in [0,2]:
			var next := pos
			next[axis] += delta[axis]
			if height_test:
				next.x = clampf(next.x,-SceneArena.HALF_WIDTH+2.3,SceneArena.HALF_WIDTH-2.3)
				next.z = clampf(next.z,-SceneArena.HALF_DEPTH+2.3,SceneArena.HALF_DEPTH-2.3)
			if position_clear(next, radius, can_step, body_height):
				pos = next
	pos.y = clampf(target.y, 0.0, SceneArena.CEILING - 5.0) if height_test else maxf(0.0, target.y)
	if target.y>from.y:
		for box: AABB in arena["solids"]:
			if from.y + body_height <= box.position.y and target.y + body_height > box.position.y \
					and _overlaps_footprint(box, pos, radius):
				pos.y = minf(pos.y, box.position.y - body_height)
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
	_solid_seen.fill(0)
	_solid_stamp = 0
	_collision_ready = true


func position_clear(pos: Vector3, radius := ACTOR_RADIUS, can_step := true, body_height := 4.6) -> bool:
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
				if pos.y >= box.end.y - step_height or pos.y + body_height <= box.position.y:
					continue
				# Tread noses have zero horizontal padding: support is resolved at the actor center.
				var padding := 0.0 if can_step and walk else radius
				if _overlaps_footprint(box, pos, padding):
					return false
	return true

func _overlaps_footprint(box: AABB, pos: Vector3, radius: float) -> bool:
	if arena.get("height_test", false) or radius == 0.0:
		return Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(radius).has_point(Vector2(pos.x, pos.z))
	var dx := pos.x - clampf(pos.x, box.position.x, box.end.x)
	var dz := pos.z - clampf(pos.z, box.position.z, box.end.z)
	return dx * dx + dz * dz < radius * radius

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




func combat_targets() -> Array:
	var targets: Array = []
	for enemy in enemies:
		if enemy.alive and melee_clear(player.rig.global_position+Vector3(0,2.3,0), enemy.center()):
			targets.append(enemy)
	return targets

func constrain_camera() -> void:
	var focus: Vector3 = player.rig.global_position + Vector3(0,2.8,0)
	var desired := cam.camera.global_position
	if arena.get("height_test", false):
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

## 在任意一条楼梯/坡道走廊内都算「在楼梯上」。
func duelist_on_stairs(at: Vector3) -> bool:
	return nav != null and nav.stair_at(at) >= 0


func duelist_stair_lane(at: Vector3) -> Vector2:
	if nav == null:
		return Vector2.INF
	# 可挥刀的窗口照旧包含楼梯口与上平台边（旧行为），但边界来自 nav 线元信息。
	var li: int = nav.stair_at(at, 0.4)
	if li < 0:
		var wide: int = nav.stair_at(at, 1.9)
		if wide < 0 or at.z > STAIR_EXIT.z + 1.7 or at.z < SceneArena.STAIR_BOTTOM - 1.4:
			return Vector2.INF
		li = wide
	var line: Dictionary = nav.lines[li]
	var center: Vector2 = (line["a"] as Vector2 + line["b"] as Vector2) * 0.5
	var half_width := float(line["width"]) * 0.5
	var left_edge := center.x - half_width + STAIR_BLADE_MARGIN
	# 上行出平台口时左侧让开，能砍到栏杆外侧。
	left_edge -= 5.0 * smoothstep(SceneArena.STAIR_TOP, STAIR_EXIT.z, at.z)
	return Vector2(left_edge, center.x + half_width - STAIR_BLADE_MARGIN)


func duelist_floor_normal(at: Vector3, _ceiling: float) -> Vector3:
	return nav.normal_at(at)


func _constrain_duelist_blade(rig, dt: float, strike: int, blade: BladeTerrain) -> Dictionary:
	var authored: Transform3D = rig.weapon_spin.global_transform
	var shoulder: Vector3 = rig.arms[1]["shoulder"].global_position
	var was_recovering := blade.recovering
	var pose := blade.advance(geometry, authored,
		Vector2(rig.BLADE_START, rig.BLADE_END), shoulder, dt, strike,
		rig.get("blade_proxy"))
	if blade.recovering or not pose.is_equal_approx(authored):
		rig.apply_terrain_blade(pose, blade.shoulder_recoil())
	return {"was_recovering": was_recovering, "recovering": blade.recovering, "impact": blade.impact}


func _terrain_blade_endpoint(from: Vector3, to: Vector3) -> Vector3:
	if from.is_equal_approx(to) or geometry == null:
		return to
	var hit: Dictionary = geometry.raycast(from, to)
	if hit.is_empty():
		return to
	var point: Vector3 = hit["point"]
	return from.move_toward(point, maxf(0.0, from.distance_to(point) - 0.025))


func terrain_blade_clear(from: Vector3, to: Vector3) -> bool:
	return _terrain_blade_endpoint(from, to).is_equal_approx(to)


func duelist_ground_move(from: Vector3, goal: Vector3) -> Vector3:
	return nav.move_slide(from, goal, ACTOR_RADIUS,
		DUELIST_STEP_HEIGHT, DUELIST_STEP_HEIGHT, DUELIST_UPPER)


func duelist_can_strike(from: Vector3, goal: Vector3) -> bool:
	if absf(from.y - goal.y) > DUELIST_STRIKE_HEIGHT:
		if from.distance_to(goal) > 6.0 or not nav.move_clear(from, goal, ACTOR_RADIUS,
				DUELIST_STEP_HEIGHT, DUELIST_STEP_HEIGHT, DUELIST_UPPER):
			var landed: Vector3 = nav.move_supported(from, goal, ACTOR_RADIUS,
				DUELIST_STEP_HEIGHT, DUELIST_STEP_HEIGHT, DUELIST_UPPER)
			if landed.distance_to(goal) > 0.28:
				return false
	return nav.segment_clear(from + Vector3.UP * 2.3, goal + Vector3.UP * 2.3)


func duelist_can_rush(from: Vector3, goal: Vector3, clearance: float) -> bool:
	if not duelist_stair_lane(goal).is_finite():
		return false
	var heading := (goal - from).slide(Vector3.UP).normalized()
	var landing := goal - heading * clearance
	var ground := duelist_ground_move(from, landing)
	return ground.slide(Vector3.UP).distance_to(landing.slide(Vector3.UP)) < 0.35 \
		and duelist_can_strike(ground, goal)


func duelist_needs_route(from: Vector3, goal: Vector3) -> bool:
	return duelist_stair_lane(from).is_finite() or duelist_stair_lane(goal).is_finite() \
		or not duelist_can_strike(from, goal)


func duelist_route_point(from: Vector3, goal: Vector3, flowing := false) -> Vector3:
	if flowing:
		return nav.route_pull(from, goal, ACTOR_RADIUS, 3.2,
			DUELIST_STEP_HEIGHT, DUELIST_UPPER)
	return nav.next_waypoint(from, goal, ACTOR_RADIUS,
		DUELIST_STEP_HEIGHT, 0.0, DUELIST_UPPER)


func floor_at(pos: Vector3, max_height: float) -> float:
	var height := 0.0
	for box: AABB in _solid_boxes:
		if box.end.y <= max_height and Rect2(box.position.x,box.position.z,box.size.x,box.size.z).has_point(Vector2(pos.x,pos.z)):
			height = maxf(height,box.end.y)
	return height


func sentinel_ground_move(from: Vector3, goal: Vector3) -> Vector3:
	if arena["height_test"]:
		return super.sentinel_ground_move(from, goal)
	return nav.move_slide(from, goal, GALLERIA_SENTINEL_RADIUS, NAV_SENTINEL_STEP, NAV_SENTINEL_STEP)


func sentinel_waypoint(from: Vector3, goal: Vector3) -> Vector3:
	if arena["height_test"]:
		return super.sentinel_waypoint(from, goal)
	return nav.next_waypoint(from, goal, GALLERIA_SENTINEL_RADIUS, NAV_SENTINEL_STEP)


func _near_stair_treads(at: Vector3) -> bool:
	return (absf(at.x - SceneArena.STAIR_X) < SceneArena.STAIR_WIDTH * 0.5
		and at.z >= SceneArena.STAIR_BOTTOM - 1.45 and at.z <= SceneArena.STAIR_TOP + 1.45)


func _stair_support(at: Vector3, offset: Vector3) -> float:
	# Only walkable surfaces can support the running gear. Rails never become footholds.
	return maxf(0.0, nav.support_at(at + offset, at.y + 0.8))


func _tracked_stair_pose(at: Vector3, yaw: float) -> Vector2:
	if not _near_stair_treads(at):
		return Vector2.ZERO
	var basis := Basis(Vector3.UP, yaw)
	var fore_z := clampf(at.z + basis.z.z * 1.15, SceneArena.STAIR_BOTTOM, SceneArena.STAIR_TOP)
	var aft_z := clampf(at.z - basis.z.z * 1.15, SceneArena.STAIR_BOTTOM, SceneArena.STAIR_TOP)
	var slope := SceneArena.DECK_HEIGHT / (SceneArena.STAIR_TOP - SceneArena.STAIR_BOTTOM)
	var pitch := -atan((fore_z - aft_z) * slope / 2.3)
	var tilted := Basis.from_euler(Vector3(pitch, yaw, 0))
	var lift := 0.0
	for side in [-1.0, 1.0]:
		for z in [-1.21, -1.04, -0.83, -0.55, -0.28, 0.0, 0.28, 0.55, 0.83, 1.04, 1.21]:
			var nose := maxf(0.0, absf(z) - 0.85)
			var rise := nose * nose * 1.38
			var offset := tilted * Vector3(side * 1.03, rise, z)
			lift = maxf(lift, _stair_support(at, offset) - at.y - offset.y)
	return Vector2(pitch, lift + 0.013 if lift > 0.0 else 0.0)


func _wheel_stair_pose(at: Vector3, yaw: float, radius: float) -> float:
	if not _near_stair_treads(at):
		return 0.0
	# The armor segments of the tire sit outside the nominal rolling radius.
	var tread_radius := radius + 0.043
	var axes := Basis(Vector3.UP, yaw)
	var lift := 0.0
	for side in [-0.39, 0.0, 0.39]:
		for fraction in [-0.98, -0.85, -0.68, -0.51, -0.34, -0.17, 0.0, 0.17, 0.34, 0.51, 0.68, 0.85, 0.98]:
			var z: float = tread_radius * fraction
			var bottom := radius - sqrt(tread_radius * tread_radius - z * z)
			var offset := axes * Vector3(side, 0, z)
			lift = maxf(lift, _stair_support(at, offset) - at.y - bottom)
	return lift

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
	if player.blade_terrain.recovering:
		return
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
	_plunge_demonstrated = true
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
			pos = resolve_motion(pos, pos + away.normalized() * (3.2 - dist) * 0.55, false, false)
		enemy.rig.global_position = pos


func clamp_enemy_position(point: Vector3, _scale_factor: float = 1.0) -> Vector3:
	if not arena.get("height_test", false) and nav != null and nav.support_at(point, point.y + SENTRY_STEP_HEIGHT) == -INF:
		return Vector3.INF
	return resolve_motion(point, point, false, false) if position_clear(point, 1.8, false) else Vector3.INF


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
			"normal": duelist_floor_normal(start, start.y + 0.16), "compact": true, "support_lift": 0.0}
	best["samples"] = samples.slice(0, best_count)
	return best


func _defeat_rest(center: Vector3, forward: Vector3) -> Dictionary:
	var surface := duelist_floor_normal(center, center.y + 0.16)
	for degrees: float in [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
		var facing := forward.rotated(Vector3.UP, deg_to_rad(degrees))
		var across := facing.cross(Vector3.UP)
		var head := center + facing * 2.77
		var feet := center - facing * 2.00
		var head_plane := _support_plane_height(head, center, surface)
		var feet_plane := _support_plane_height(feet, center, surface)
		head.y = _defeat_support(head, head_plane + 1.02)
		feet.y = _defeat_support(feet, feet_plane + 1.02)
		if absf(head.y - head_plane) > 0.96 or absf(feet.y - feet_plane) > 0.96:
			continue
		if not _defeat_clear(head, 0.82, 0.98) or not _defeat_clear(feet, 0.82, 0.78):
			continue
		var legs_clear := true
		for side: float in [-1.0, 1.0]:
			var foot := feet + across * 0.96 * side
			var on_plane := _support_plane_height(foot, feet, surface)
			foot.y = _defeat_support(foot, on_plane + 0.68)
			legs_clear = legs_clear and absf(foot.y - on_plane) <= 0.50 and _defeat_clear(foot, 0.66, 0.80)
		if not legs_clear:
			continue
		if not _defeat_clear(center, 1.02, 1.2):
			continue
		var rise := (head.y - feet.y) / 4.77
		var cross_grade := -surface.dot(across) / surface.y
		var up := (Vector3.UP - facing * rise - across * cross_grade).normalized()
		# Fit the support plane above the discrete stair noses as well as the endpoints.
		var lift := 0.0
		for offset: float in [-1.65, -0.8, 0.55, 1.15, 1.80, 2.45]:
			var along := center + facing * offset
			var height := _defeat_support(along, _support_plane_height(along, center, surface) + 1.02)
			lift = maxf(lift, height - center.y - rise * offset)
		return {"facing": facing, "normal": up, "compact": false, "support_lift": minf(lift, 0.31)}
	return {}


func _support_plane_height(at: Vector3, anchor: Vector3, normal: Vector3) -> float:
	return anchor.y - normal.dot((at - anchor).slide(Vector3.UP)) / normal.y


## 搁浅支撑：可走面 + 棱柱顶面（旧 floor_at 的「任何实体顶面」等价物）。
func _defeat_support(at: Vector3, ceiling: float) -> float:
	var support: float = nav.rest_at(at, ceiling)
	return support if support > -INF * 0.5 else floor_at(at, ceiling)


func _defeat_clear(at: Vector3, radius: float, height: float) -> bool:
	if absf(at.x) > SceneArena.HALF_WIDTH - radius or absf(at.z) > SceneArena.HALF_DEPTH - radius:
		return false
	var normal := duelist_floor_normal(at, at.y + 0.15)
	var slope := normal.slide(Vector3.UP).length() / normal.y
	# Match the tread allowance above so the shape check does not block a
	# fall on a neighboring stair before the posed body reaches it.
	var tread_clearance := 0.18 + radius * 0.37
	var bottom := minf(height - 0.10, maxf(tread_clearance, radius * slope + 0.035))
	return nav.column_clear(at, radius, bottom, height)
