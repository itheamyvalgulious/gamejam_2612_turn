extends LevelUnit
const SceneArena = preload("res://src/encounter/arena.gd")
const Phase = preload("res://src/encounter/phase_enemy.gd")
const PhaseFX = preload("res://src/encounter/phase_fx.gd")
const ACTOR_RADIUS := 1.75
var nav: AStarGrid2D
var plunge_armed := false
var drop_start_height := 0.0
var was_airborne := false
var rng := RandomNumberGenerator.new()
var player_previous := Vector3.ZERO
var phase_effects: Array = []

func start_level(_idx: int) -> void:
	_clear_enemies()
	for effect in phase_effects:
		if is_instance_valid(effect):
			effect.queue_free()
	phase_effects.clear()
	index = 0
	if arena_node == null:
		arena = SceneArena.build()
		arena_node = arena["node"]
		add_child(arena_node)
		preload("res://src/encounter/neon_gi.gd").install(arena_node,not arena["vertical"])
	player.rig.ground_height = arena["player_spawn"].origin.y
	player.reset(arena["player_spawn"])
	plunge_armed = false
	drop_start_height = player.rig.global_position.y
	build_navigation()
	player.rig.arena_bounds = Vector2.ZERO
	player_previous = player.rig.global_position
	cam.yaw = 0
	cam.pitch = -0.12
	cam.snap(arena)
	rng.randomize()
	for entry in arena["encounters"]:
		var enemy
		match entry["kind"]:
			"phase":
				enemy = Phase.new()
				enemy.setup_phase()
				enemy.anchor_index = entry["pad"]
			"archer":
				enemy = preload("res://src/encounter/archer_enemy.gd").new()
				enemy.setup_archer(PAL_ARCHER)
				archers.append(enemy)
			_:
				enemy = preload("res://src/encounter/basic_enemy.gd").new()
				enemy.setup_mob(PAL_MOB)
		add_child(enemy)
		enemy.level = self
		enemy.global_position = arena["anchors"][entry["pad"]] if entry["kind"]=="phase" else entry["pos"]
		enemy.rig.reset_demo(Vector3.ZERO,PI)
		enemy.rig.advance(0.001)
		enemy.rig.weapon_prev_xf = enemy.rig.weapon_xf
		enemies.append(enemy)
	total_enemies = enemies.size()
	state = "fight"
	state_t = 0
	Snd.set_arena(arena)
	if on_level_changed.is_valid():
		on_level_changed.call(0, arena["name_cn"], arena["hint"])

func step(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	for effect in phase_effects.duplicate():
		if is_instance_valid(effect) and not effect.is_queued_for_deletion():
			effect.advance(dt)
		else:
			phase_effects.erase(effect)
	if state == "fight":
		for enemy in enemies:
			var old: Vector3 = enemy.rig.global_position
			enemy.step(dt, ctx)
			if enemy.kind == "phase" and enemy.alive:
				# Attack root motion cannot carry a phase guard off its fixed pad.
				enemy.rig.global_position = arena["anchors"][enemy.anchor_index]
			else:
				var resolved := resolve_motion(old, enemy.rig.global_position, false)
				enemy.rig.weapon_xf.origin += resolved-enemy.rig.global_position
				enemy.rig.global_position = resolved
		separate_enemies()
	elif state == "clear":
		# Finish this independent room; never load the demo's next arena.
		for enemy in enemies:
			enemy.step(dt, ctx)
		if state_t > 1.4:
			state = "finished"
	elif state == "dead" and state_t > P.getf("rules.death_delay"):
		start_level(0)

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
		if not enemy.alive or absf(resolved.y-enemy.rig.global_position.y)>3:
			continue
		var offset: Vector3 = resolved-enemy.rig.global_position
		offset.y = 0
		if offset.length()<2.6:
			if offset.length_squared()<0.001:
				offset = Vector3.FORWARD
			var separation: Vector3 = enemy.rig.global_position+offset.normalized()*2.6
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

func position_clear(pos: Vector3, radius := ACTOR_RADIUS, can_step := true) -> bool:
	for box: AABB in arena.get("solids",[]):
		var step_height := 0.45 if can_step and arena["walkables"].has(box) else 0.05
		if pos.y>=box.end.y-step_height or pos.y+4.6<=box.position.y:
			continue
		# Tread noses have zero horizontal padding: support is resolved at the actor center.
		var padding := 0.0 if can_step and arena["walkables"].has(box) else radius
		if Rect2(box.position.x-padding,box.position.z-padding,box.size.x+padding*2,box.size.z+padding*2).has_point(Vector2(pos.x,pos.z)):
			return false
	return true

func phase_visible(enemy) -> bool:
	if cam == null or cam.camera == null:
		return false
	# Test actual body samples, not only an oversized bounding sphere.
	for offset in [Vector3(0,2.3,0), Vector3(0,3.8,0), Vector3(-1.0,2.5,0), Vector3(1.0,2.5,0), Vector3(0,1,0)]:
		var point: Vector3 = enemy.rig.global_position + offset
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
			if other != enemy and other.alive and other.rig.global_position.distance_to(pos) < ACTOR_RADIUS*2.0:
				occupied = true
				break
		if not occupied:
			choices.append(i)
	return -1 if choices.is_empty() else choices[rng.randi_range(0,choices.size()-1)]

func show_phase(from: Vector3, to: Vector3) -> void:
	var effect := PhaseFX.new()
	add_child(effect)
	effect.setup(from,to)
	phase_effects.append(effect)
	Snd.play_at("parry", to+Vector3(0,2,0), {"gain": 0.45})

func melee_clear(a: Vector3, b: Vector3) -> bool:
	for box: AABB in arena["solids"]:
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

func steer_enemy(enemy, dt: float, ranged := false) -> void:
	if enemy.rig.is_attacking:
		return
	var pos: Vector3 = enemy.rig.global_position
	var goal: Vector3 = player.rig.global_position
	if goal.y>4:
		goal = Vector3(0,0,8)
	var speed: float = P.getf("archer.speed" if ranged else "mob.speed")
	var command: Vector3 = enemy.rig.move_command
	var blocked := not position_clear(pos+command.normalized()*3,2.1,false)
	if ranged and melee_clear(enemy.fire_origin(),player.rig.global_position+Vector3(0,2.3,0)) and not blocked:
		return
	if not ranged and goal.distance_to(pos)<P.getf("mob.attack_range") and goal.y<1 and melee_clear(enemy.center(),goal+Vector3(0,2.3,0)):
		return
	enemy.nav_time -= dt
	if enemy.nav_time <= 0:
		enemy.nav_time = 0.4
		enemy.nav_path = nav.get_point_path(nearest_cell(pos),nearest_cell(goal))
	while enemy.nav_path.size()>0:
		var next: Vector2 = enemy.nav_path[0]
		if Vector2(pos.x,pos.z).distance_to(next)<0.9:
			enemy.nav_path.remove_at(0)
		else:
			break
	if enemy.nav_path.size()>0:
		var point: Vector2 = enemy.nav_path[0]
		enemy.rig.move_command = Vector3(point.x-pos.x,0,point.y-pos.z).normalized()*speed

func floor_at(pos: Vector3, max_height: float) -> float:
	var height := 0.0
	for box: AABB in arena.get("solids",[]):
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
	player.rig.timing_key = "heavy"
	player.rig.force_swing(-0.8,0.9,{"height":0.9,"lift":-0.4,"lean":0.35,"lunge":0.0})
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
		if enemy.alive and enemy.rig.global_position.distance_to(pos)<7.0 and melee_clear(pos+Vector3(0,1.5,0),enemy.center()):
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
			var away: Vector3 = pos-other.rig.global_position
			away.y = 0
			var dist := away.length()
			if dist<3.2:
				if dist<0.001:
					away = Vector3.RIGHT if enemy.get_instance_id()>other.get_instance_id() else Vector3.LEFT
				pos = resolve_motion(pos,pos+away.normalized()*(3.2-dist)*0.55,false)
		enemy.rig.weapon_xf.origin += pos-old
		enemy.rig.global_position = pos
