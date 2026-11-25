extends Node3D
## Bridges Fold's animation and AI to the original ACT level and combat APIs.

const Controller = preload("res://team/fold/src/enemies/phase_boss/phase_boss_combat.gd")
const State = preload("res://team/fold/src/enemies/phase_boss/phase_boss_state.gd")
const Body = preload("res://team/fold/src/enemies/phase_boss/phase_boss_body.gd")
const BOSS_HEALTH := 12.0
const COVER_MARGIN := 1.2
const IMPACT_METERS := {
	"sweep": 5.0, "tail": 5.0, "tail_left": 5.0, "phase": 5.0,
	"pounce": 5.5, "stomp": 6.0, "high_pounce": 6.5, "run_pounce": 6.5,
	"sprint": 7.0, "back_cannon": 6.0,
}

var rig: Node3D
var kind := "boss"
const enemy_id := "phase_boss"
var alive := true
var last_hit_serial := -1
var level
var controller: Controller
var _arena: Dictionary = {}
var _pending: Dictionary = {}
var _death_time := 0.0


func _ready() -> void:
	controller = Controller.new()
	controller.max_hp = BOSS_HEALTH
	controller.trace_world = _trace_arena
	add_child(controller)
	rig = controller.model
	controller.attack_hit.connect(_queue_attack)
	controller.impact_shake.connect(_shake_camera)
	controller.footfall_shake.connect(_shake_camera.bind(false))


func spawn_fold(spawn: Transform3D, arena: Dictionary) -> void:
	_arena = arena
	var bounds: AABB = arena["bounds"]
	controller.arena_half_extent = minf(bounds.size.x, bounds.size.z) * 0.5
	controller.reset_at(spawn.origin, spawn.basis.get_euler().y)


## 重生复用：controller.reset_at 已做全量复位（hp/相位/姿态），
## 这里只需补外壳层的存活标记与出场 intro。
var spawn_xf := Transform3D.IDENTITY


func respawn() -> void:
	alive = true
	_death_time = 0.0
	visible = true
	_pending.clear()
	controller.reset_at(spawn_xf.origin, spawn_xf.basis.get_euler().y)


func step(dt: float, ctx: Dictionary) -> void:
	_pending.clear()
	if not alive:
		_death_time -= dt
		visible = _death_time > 0.0
		return
	var player: PlayerUnit = ctx["player"]
	var cam: GameCam = ctx["cam"]
	if level.state == "intro":
		controller.advance_intro(dt)
	elif player.alive and level.state == "fight":
		controller.step(dt, player.rig.global_position, cam.camera, player.capsule())


func block_player_motion(player: PlayerUnit, from: Vector3) -> void:
	if not alive:
		return
	var to: Vector3 = player.rig.global_position
	var safe := Body.resolve(rig, from, to, player.capsule(), _arena)
	player.apply_body_collision(safe)


func hit_parts() -> Array:
	return controller.hit_parts()


func center() -> Vector3:
	return rig.chest.global_position


func mark_radius() -> float:
	return 4.7


func blocks_when_seen() -> bool:
	return false


func is_fold_visible(camera: Camera3D) -> bool:
	return camera != null and controller.aim_at_camera(camera)


func hurt(amount: float, _normal := Vector3.UP, _knock := 0.0) -> float:
	if not alive:
		return 0.0
	var visible_now := is_fold_visible(level.cam.camera)
	var damage := controller.take_damage(amount, visible_now, level.player.rig.global_position)
	if controller.hp <= 0.0:
		alive = false
		_death_time = 1.2
		Snd.play_at("death", center(), {"gain": 1.2})
		Fx.death_burst(center())
		level.on_enemy_died(self)
	return damage


func status_text() -> String:
	if controller.action == "wake_intro":
		return "折相 · " + controller.activity_label()
	var state := "实体"
	match controller.phase.stage:
		State.Stage.ENTERING:
			state = "转入虚化"
		State.Stage.PHASED:
			state = "虚化"
		State.Stage.RETURNING:
			state = "复实"
	return "折相 · %s · %s" % [state, controller.activity_label()]


func melee_threat(player: PlayerUnit, margin: float) -> Dictionary:
	var threat := controller.melee_forecast(player.capsule(), margin, P.getf("parry.plan_lead"))
	if not threat.is_empty():
		threat["enemy"] = self
	return threat


func _queue_attack(damage: float, blockable: bool, source: Vector3) -> void:
	_pending = {"damage": damage, "blockable": blockable, "source": source,
		"displacement": IMPACT_METERS[controller.action]}


func _shake_camera(source: Vector3, strength: float, accumulate := true) -> void:
	var meters: float = source.distance_to(level.player.rig.global_position) * Controller.METERS_PER_UNIT
	Fx.shake(strength * lerpf(1.0, 0.30, smoothstep(4.0, 30.0, meters)), accumulate)


func resolve_fold_attack(player: PlayerUnit) -> Dictionary:
	if _pending.is_empty() or not player.alive:
		return {"hit": false}
	var attack := _pending.duplicate()
	_pending.clear()
	var source: Vector3 = attack["source"]
	var player_at: Vector3 = player.rig.global_position
	var away := (player_at - controller.ground_position()).slide(Vector3.UP).normalized()
	var push := (player_at - source).slide(Vector3.UP).normalized()
	# Side hits can come from the tail or paw. Keep their impulse out of the hull.
	if push.dot(away) < 0.30:
		push = away
	if push.is_zero_approx():
		push = -rig.global_basis.z.normalized()
	var displacement: float = attack["displacement"]
	if attack["blockable"] and P.getb("parry.melee_block"):  # 碰到刀即格挡
		if Combat.blade_contacts_point(player.rig, source, controller.contact_radius() + 0.25):
			player.launch_impact(push, displacement)
			return {"hit": false, "parried": true, "melee": true, "pos": source, "normal": -push, "push": push}
	var old_hp := player.hp
	player.hurt(attack["damage"], push, "被折相击中" if attack["blockable"] else "被折相的背炮击中")
	var hit := not player.alive or player.hp < old_hp
	if hit:
		player.launch_impact(push, displacement)
	return {"hit": hit, "pos": source}


func _trace_arena(start: Vector3, end: Vector3) -> Dictionary:
	var a := Vector2(start.x, start.z)
	var b := Vector2(end.x, end.z)
	var delta := b - a
	var length_squared := delta.length_squared()
	if length_squared < 0.0000001:
		return {}
	var first := 1.0
	var floor_y: float = _arena.get("floor_y", 0.0)
	for wall: Dictionary in _arena.get("walls", []):
		var cross: Variant = Geometry2D.segment_intersects_segment(a, b, wall["a"], wall["b"])
		if cross == null:
			continue
		var t: float = (cross - a).dot(delta) / length_squared
		var y := lerpf(start.y, end.y, t)
		if t > 0.0001 and y >= floor_y and y <= floor_y + float(wall["h"]):
			first = minf(first, t)
	for cover: Dictionary in _arena.get("cover", []):
		var center: Vector3 = cover["c"]
		var radial := a - Vector2(center.x, center.z)
		var radius := maxf(0.05, float(cover["r"]) - COVER_MARGIN)
		var along := radial.dot(delta)
		var c := radial.length_squared() - radius * radius
		var discriminant := along * along - length_squared * c
		if discriminant < 0.0:
			continue
		var begin := maxf(0.0, (-along - sqrt(discriminant)) / length_squared)
		var finish := minf(first, (-along + sqrt(discriminant)) / length_squared)
		var ascent := end.y - start.y
		var high := floor_y + float(cover["h"])
		if absf(ascent) > 0.00001:
			var lower_hit := (floor_y - start.y) / ascent
			var upper_hit := (high - start.y) / ascent
			begin = maxf(begin, minf(lower_hit, upper_hit))
			finish = minf(finish, maxf(lower_hit, upper_hit))
		elif start.y < floor_y or start.y > high:
			continue
		if begin <= finish and finish > 0.0:
			first = minf(first, begin)
	return {"position": start.lerp(end, first)} if first < 0.99999 else {}


func hud_alert(target: PlayerUnit) -> bool:
	return not controller.melee_forecast(target.capsule(), 0.12, 0.42).is_empty()
