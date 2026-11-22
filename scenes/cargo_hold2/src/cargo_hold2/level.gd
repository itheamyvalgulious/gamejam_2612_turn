extends LevelUnit
const CargoArena = preload("res://src/cargo_hold2/arena.gd")
const Phase = preload("res://src/cargo_hold2/phase_enemy.gd")
const PhaseFX = preload("res://src/cargo_hold2/phase_fx.gd")
const ACTOR_RADIUS := 1.75
var rng := RandomNumberGenerator.new()
var player_previous := Vector3.ZERO
var phase_effects: Array = []

func start_level(_idx: int) -> void:
	_clear_enemies()
	_clear_arena()
	for effect in phase_effects:
		if is_instance_valid(effect):
			effect.queue_free()
	phase_effects.clear()
	index = 0
	arena = CargoArena.build()
	arena_node = arena["node"]
	add_child(arena_node)
	player.reset(arena["player_spawn"])
	player.rig.arena_bounds = Vector2.ZERO
	player_previous = player.rig.global_position
	cam.yaw = 0
	cam.pitch = -0.12
	cam.snap(arena)
	rng.randomize()
	for pad in [0, 4, 2]:
		var enemy := Phase.new()
		enemy.setup_phase()
		enemy.anchor_index = pad
		add_child(enemy)
		enemy.level = self
		enemy.global_position = arena["anchors"][pad]
		enemies.append(enemy)
	var basic = preload("res://src/cargo_hold2/basic_enemy.gd").new()
	basic.setup_mob(PAL_MOB)
	add_child(basic)
	basic.level = self
	basic.global_position = CargoArena.BASIC_SPAWN
	for enemy in enemies + [basic]:
		enemy.rig.reset_demo(Vector3.ZERO, PI)
		enemy.rig.advance(0.001)
		enemy.rig.weapon_prev_xf = enemy.rig.weapon_xf
	enemies.append(basic)
	total_enemies = 4
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
				var resolved := resolve_motion(old, enemy.rig.global_position)
				enemy.rig.weapon_xf.origin += resolved-enemy.rig.global_position
				enemy.rig.global_position = resolved
	elif state == "clear":
		# Finish this independent room; never load the demo's next arena.
		for enemy in enemies:
			enemy.step(dt, ctx)
		if state_t > 1.4:
			state = "finished"
	elif state == "dead" and state_t > P.getf("rules.death_delay"):
		start_level(0)

func constrain_player() -> void:
	var resolved := resolve_motion(player_previous, player.rig.global_position)
	for enemy in enemies:
		if not enemy.alive:
			continue
		var offset: Vector3 = resolved - enemy.rig.global_position
		offset.y = 0
		if offset.length() < 2.6:
			if offset.length_squared() < 0.001:
				offset = Vector3.FORWARD
			var separation: Vector3 = enemy.rig.global_position + offset.normalized()*2.6
			separation.y = resolved.y
			resolved = resolve_motion(player_previous, separation)
	player.rig.weapon_xf.origin += resolved-player.rig.global_position
	player.rig.global_position = resolved
	player_previous = player.rig.global_position

func resolve_motion(from: Vector3, target: Vector3) -> Vector3:
	# Substepped swept movement prevents dashes tunnelling through box corners.
	# Containers are closed cover, not climbable platforms in the demo's flat-floor rig.
	var distance := Vector2(target.x-from.x, target.z-from.z).length()
	var count := maxi(1, ceili(distance / 0.3))
	var delta := (target-from) / float(count)
	var pos := from
	for i in count:
		for axis in [0, 2]:
			var next := pos
			next[axis] += delta[axis]
			next.x = clampf(next.x, -CargoArena.HALF_WIDTH+3.0, CargoArena.HALF_WIDTH-3.0)
			next.z = clampf(next.z, -CargoArena.HALF_DEPTH+3.0, CargoArena.HALF_DEPTH-3.0)
			if position_clear(next):
				pos = next
	pos.y = clampf(target.y, 0.0, CargoArena.CEILING-5.0)
	return pos

func position_clear(pos: Vector3, radius := ACTOR_RADIUS) -> bool:
	for box: AABB in arena.get("solids", []):
		var rect := Rect2(box.position.x-radius, box.position.z-radius, box.size.x+radius*2, box.size.z+radius*2)
		if rect.has_point(Vector2(pos.x,pos.z)):
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
	desired.x = clampf(desired.x,-CargoArena.HALF_WIDTH+0.5,CargoArena.HALF_WIDTH-0.5)
	desired.y = clampf(desired.y,0.3,CargoArena.CEILING-0.5)
	desired.z = clampf(desired.z,-CargoArena.HALF_DEPTH+0.5,CargoArena.HALF_DEPTH-0.5)
	var direction := (desired-focus).normalized()
	var nearest := focus.distance_to(desired)
	for box: AABB in arena["solids"]:
		var hit = box.grow(0.22).intersects_segment(focus,desired)
		if hit != null:
			nearest = minf(nearest, maxf(0.1, focus.distance_to(hit)-0.15))
	cam.camera.global_position = focus + direction*nearest
