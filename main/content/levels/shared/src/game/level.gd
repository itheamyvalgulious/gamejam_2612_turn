extends Node3D
class_name LevelUnit
## 共用的关卡流程，地图由各关卡场景传入。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const LevelGeometry = preload("res://core/level_geometry.gd")
const WallShadow = preload("res://src/fx/wall_shadow.gd")
const StaticBatch = preload("res://core/static_batch.gd")
const NavField = preload("res://core/nav_field.gd")
const LevelDeath = preload("res://core/death_field.gd")


var index: int
var _arena_builder: Script
var arena: Dictionary = {}
var arena_node: Node3D
## 导航元信息（core/nav_field.gd）：区域+线+障碍棱柱，纯数据/解析。
var nav: RefCounted
## 刀的解析地形（core/level_geometry.gd）：arena 元信息生成的凸体。
var geometry: RefCounted
var enemies: Array = []
var archers: Array = []
var player: PlayerUnit
var projectiles: Projectiles
var cam: GameCam
var state := "intro"           # intro / fight / clear / dead / finished
var state_t := 0.0
var shadow = null
var markers: Array = []
var total_enemies := 0
var on_level_changed: Callable = Callable()


func setup(p_player: PlayerUnit, p_proj: Projectiles, p_cam: GameCam, arena_builder: Script) -> void:
	player = p_player
	projectiles = p_proj
	cam = p_cam
	_arena_builder = arena_builder
	index = TurnSession.active_level_index()


func start_level() -> void:
	if arena_node != null and is_instance_valid(arena_node):
		# 房间场景全程不变：重生只复位，不重建（原实现重生要重建整个竞技场）
		for e in enemies:
			if is_instance_valid(e):
				e.respawn()
	else:
		_clear_arena()
		_clear_enemies()
		arena = _arena_builder.build(Vector3.ZERO)
		nav = NavField.build(arena, _nav_spec_for(arena))
		geometry = LevelGeometry.build(arena)
		arena_node = arena["node"]
		add_child(arena_node)
		StaticBatch.apply(arena_node)
		_spawn_enemies()
	if shadow != null and is_instance_valid(shadow):
		shadow.queue_free()
	shadow = null
	player.reset(arena["player_spawn"])
	player.rig.arena_bounds = Vector2.ZERO
	# 相机立刻对位：切关的第一帧敌人就开始思考，相机不能还停在上一关
	if cam != null:
		cam.snap(arena)
	LevelDeath.install(self)
	total_enemies = enemies.size()
	state = "intro"
	state_t = 0.0
	Snd.set_arena(arena)
	if on_level_changed.is_valid():
		on_level_changed.call(index, String(arena.get("name_cn", "")), String(arena.get("hint", "")))


func _clear_arena() -> void:
	if arena_node != null and is_instance_valid(arena_node):
		arena_node.queue_free()
	arena_node = null
	arena = {}


func _clear_enemies() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	archers.clear()
	if projectiles != null:
		projectiles.clear_all()


func step_cinematic(_real_dt: float) -> bool:
	return false


func constrain_player(_previous: Vector3) -> void:
	pass


func can_advance() -> bool:
	return true


func _spawn_enemies() -> void:
	pass


func _setup_shadows() -> void:
	var slots: Array = arena.get("wall_slots", [])
	var lamps: Array = arena.get("lamps", [])
	if slots.size() < 1:
		return
	shadow = WallShadow.new()
	shadow.name = "BossShadow"
	add_child(shadow)
	shadow.setup(slots, {"intensity": clampf(P.getf("boss.shadow_intensity"), 0.0, 1.0),
		"softness": P.getf("boss.shadow_softness"), "mask_hz": 2})
	shadow.set_caster_scale(P.getf("boss.shadow_size"))
	shadow.set_lamps(lamps)
	# 影子层：玩家 + 这一关的所有敌人（真几何，谁在场上谁就有影子）
	if player != null and player.rig != null:
		shadow.add_caster(player.rig)
	for e in enemies:
		if is_instance_valid(e) and e.rig != null:
			shadow.add_caster(e.rig)


func on_enemy_died(_e) -> void:
	var alive_count := 0
	for e in enemies:
		if e.alive:
			alive_count += 1
	if alive_count == 0 and state == "fight":
		state = "clear"
		state_t = 0.0


func alive_count() -> int:
	var n := 0
	for e in enemies:
		if e.alive:
			n += 1
	return n


func context() -> Dictionary:
	return {"player": player, "ray": player, "cam": cam, "arena": arena,
		"enemies": enemies, "archers": archers, "projectiles": projectiles}


# ------------------------------------------------------------------ 导航
## 怪物移动/视线全部走 nav_field 的元信息（不再碰物理空间）。
## 每个房间 arena 自带 nav_spec()；缺省退回纯 bounds 地面 + walls/cover 障碍。
func _nav_spec_for(target_arena: Dictionary) -> Dictionary:
	for m in _arena_builder.get_script_method_list():
		if String(m.get("name", "")) == "nav_spec":
			return _arena_builder.nav_spec(target_arena)
	return {}


const NAV_SENTINEL_RADIUS := 1.20
const NAV_SENTINEL_STEP := 0.38
const NAV_SENTRY_RADIUS := 1.58
const NAV_SENTRY_STEP := 0.37


func melee_clear(a: Vector3, b: Vector3) -> bool:
	return nav == null or nav.segment_clear(a, b)


func sentinel_ground_move(from: Vector3, goal: Vector3) -> Vector3:
	return nav.move_slide(from, goal, NAV_SENTINEL_RADIUS,
		NAV_SENTINEL_STEP, NAV_SENTINEL_STEP)


func sentinel_support_floor(at: Vector3) -> float:
	var support: float = nav.rest_at(at, at.y + 0.04)
	return support if support > -INF * 0.5 else 0.0


func sentinel_waypoint(from: Vector3, goal: Vector3) -> Vector3:
	return nav.next_waypoint(from, goal, NAV_SENTINEL_RADIUS, NAV_SENTINEL_STEP)


func sentry_ground_move(from: Vector3, goal: Vector3) -> Vector3:
	return nav.move_supported(from, goal, NAV_SENTRY_RADIUS,
		NAV_SENTRY_STEP, NAV_SENTRY_STEP)


func duelist_floor(at: Vector3, ceiling: float) -> float:
	var support: float = nav.support_at(at, ceiling)
	return support if support > -INF * 0.5 else 0.0


func step(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	# 敌人
	for e in enemies:
		if is_instance_valid(e):
			e.step(dt, ctx)
			_clamp_enemy(e)
	# 影子（相机 / 遮罩是静态的：这里只同步每个角色影子网格的位姿 + 跟手感参数）
	if shadow != null and is_instance_valid(shadow):
		shadow.refresh()
		var v_inten: float = clampf(P.getf("boss.shadow_intensity"), 0.0, 1.0)
		if absf(v_inten - shadow.intensity) > 1e-4:
			shadow.set_intensity(v_inten)
		var v_soft: float = P.getf("boss.shadow_softness")
		if absf(v_soft - shadow.softness) > 1e-4:
			shadow.set_softness(v_soft)
		var v_size: float = P.getf("boss.shadow_size")
		if absf(v_size - shadow.caster_scale) > 1e-4:
			shadow.set_caster_scale(v_size)
	# 流程
	match state:
		"intro":
			if state_t > minf(1.4, P.getf("rules.banner_time") * 0.6):
				state = "fight"
				state_t = 0.0
		"fight":
			pass
		"clear":
			if state_t > P.getf("rules.banner_time"):
				state = "finished"
				state_t = 0.0
		"dead":
			if state_t > P.getf("rules.death_delay"):
				start_level()
		"finished":
			pass


func clamp_enemy_position(point: Vector3, scale_factor: float = 1.0) -> Vector3:
	var bounds: AABB = arena.get("bounds", AABB())
	if bounds.size.length_squared() < 0.01:
		return point
	var pos := Vector3(clampf(point.x, bounds.position.x + 3.0, bounds.end.x - 3.0),
			point.y, clampf(point.z, bounds.position.z + 3.0, bounds.end.z - 3.0))
	return Hit.resolve_circles(pos, 1.1 * scale_factor, arena.get("cover", []), point.y)


func _clamp_enemy(enemy) -> void:
	var old: Vector3 = enemy.rig.global_position
	enemy.rig.global_position = clamp_enemy_position(old, enemy.scale_factor)


func on_player_died() -> void:
	if state == "dead":
		return
	state = "dead"
	state_t = 0.0


func player_can_act() -> bool:
	return state == "fight" or state == "intro"


## 屏幕外/屏幕内的敌人标记（HUD 用）
func build_markers() -> Array:
	var out: Array = []
	if not P.getb("rules.edge_markers") or cam == null or cam.camera == null:
		return out
	var vp_size: Vector2 = cam.camera.get_viewport().get_visible_rect().size
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var c: Vector3 = e.center()
		var d: float = cam.camera.global_position.distance_to(c)
		if d > P.getf("rules.marker_range"):
			continue
		var off: bool = Vision.fully_offscreen(cam.camera, c, e.mark_radius())
		var screen: Vector2 = cam.camera.unproject_position(c)
		# 屏幕外、或者投影点跑到画外很远时，把标记推到边缘。
		# 相机几乎贴在敌人身上（在 mark_radius 内，只差几毫米就在视线上）时，
		# unproject_position 会给出 1e5~1e8 级的天文数字坐标；HUD 的菱形是以这个点为
		# 中心画的 4 边形，坐标一旦到十几万，Godot 的三角化（core/math/triangulate.cpp
		# 里用 float 算有符号面积）会判错环绕方向而返回空，刷 "Invalid polygon data"。
		if off or not Rect2(Vector2.ZERO, vp_size).has_point(screen):
			var center := vp_size * 0.5
			var dir := screen - center
			if dir.length() < 1.0:
				dir = Vector2(0, -1)
			dir = dir.normalized()
			var margin := 42.0
			var half := vp_size * 0.5 - Vector2(margin, margin)
			var t := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
			screen = center + dir * t
		out.append({"screen": screen, "off": off, "kind": e.kind, "dist": d,
			"seen": not off, "world": c})
	return out
