extends Node3D
class_name LevelUnit
## 关卡流程 + 敌人编排 + 第三关的四面墙影子。
##
## 三关：窄巷(1 小怪) → 广场(3 小怪 + 1 远程) → 灯墙厅(1 大怪，×2 体型)
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const ArenaKit = preload("res://src/arena/arena.gd")
const Mob = preload("res://src/game/enemy_mob.gd")
const Archer = preload("res://src/game/enemy_archer.gd")
const Boss = preload("res://src/game/enemy_boss.gd")
const WallShadow = preload("res://src/fx/wall_shadow.gd")

const PAL_MOB := {"tag": "mob", "accent": Color(0.30, 1.0, 0.72), "tint": Color(0.80, 0.92, 1.02),
	"metal_mix": 0.26}
const PAL_ARCHER := {"tag": "archer", "accent": Color(0.82, 0.42, 1.0), "tint": Color(1.04, 0.95, 1.10),
	"metal_mix": 0.30}
const PAL_BOSS := {"tag": "boss", "accent": Color(0.42, 0.86, 1.0), "tint": Color(0.74, 0.82, 0.96),
	"metal_mix": 0.22}

const LEVELS := [
	{"kind": "alley", "enemies": ["mob"]},
	{"kind": "plaza", "enemies": ["mob", "mob", "mob", "archer"]},
	{"kind": "chamber", "enemies": ["boss"]},
]

var index := 0
var arena: Dictionary = {}
var arena_node: Node3D
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


func setup(p_player: PlayerUnit, p_proj: Projectiles, p_cam: GameCam) -> void:
	player = p_player
	projectiles = p_proj
	cam = p_cam


func start_level(idx: int) -> void:
	index = clampi(idx, 0, LEVELS.size() - 1)
	_clear_arena()
	_clear_enemies()
	arena = ArenaKit.build(String(LEVELS[index]["kind"]), Vector3.ZERO)
	arena_node = arena["node"]
	add_child(arena_node)
	if shadow != null and is_instance_valid(shadow):
		shadow.queue_free()
	shadow = null
	player.reset(arena["player_spawn"])
	player.rig.arena_bounds = Vector2.ZERO
	# 相机立刻对位：切关的第一帧敌人就开始思考，相机不能还停在上一关
	if cam != null:
		cam.snap(arena)
	_spawn_enemies()
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


func _spawn_enemies() -> void:
	var spawns: Array = arena.get("spawns", [])
	var list: Array = LEVELS[index]["enemies"]
	var ppos: Vector3 = player.rig.global_position
	# 出生点：优先用美术给的，数量不够就绕玩家环形补（离玩家至少 18 m）
	var used: Array = []
	for i in list.size():
		var t: Transform3D
		if i < spawns.size():
			t = spawns[i]
		else:
			var ang := TAU * float(i) / float(maxf(1.0, float(list.size()))) + 0.7
			var r := 20.0 + 6.0 * float(i)
			t = Transform3D(Basis(Vector3.UP, atan2(-(cos(ang)), -(sin(ang)))),
				ppos + Vector3(cos(ang) * r, 0.0, sin(ang) * r))
		# 别贴着玩家出生
		var p := t.origin
		if Vector2(p.x - ppos.x, p.z - ppos.z).length() < 16.0:
			var d := Vector2(p.x - ppos.x, p.z - ppos.z)
			if d.length() < 0.1:
				d = Vector2(1, 0)
			d = d.normalized() * 22.0
			p = ppos + Vector3(d.x, 0.0, d.y)
			t = Transform3D(t.basis, p)
		used.append(t)
		var ty := String(list[i])
		var e
		match ty:
			"archer":
				e = Archer.new()
				e.setup_archer(PAL_ARCHER)
				archers.append(e)
			"boss":
				e = Boss.new()
				e.setup_boss(PAL_BOSS)
				# 大怪自己就是最大的目标
			_:
				e = Mob.new()
				e.setup_mob(PAL_MOB)
		add_child(e)
		e.level = self
		e.global_position = t.origin
		e.rig.heading = t.basis.get_euler().y
		e.rig.rotation.y = e.rig.heading
		e.rig.facing_override = true
		enemies.append(e)
	if String(LEVELS[index]["kind"]) == "chamber":
		_setup_shadows()
	# 远程怪放到最远的出生点
	if archers.size() > 0 and enemies.size() > 1:
		var far = enemies[enemies.size() - 1]
		var far_t: Transform3D = used[used.size() - 1]
		far.global_position = far_t.origin


func _setup_shadows() -> void:
	var slots: Array = arena.get("wall_slots", [])
	var lamps: Array = arena.get("lamps", [])
	if slots.size() < 1:
		return
	shadow = WallShadow.new()
	shadow.name = "BossShadow"
	add_child(shadow)
	shadow.setup(slots, {"intensity": clampf(P.getf("boss.shadow_intensity"), 0.0, 1.0),
		"softness": P.getf("boss.shadow_softness")})
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
				if index + 1 < LEVELS.size():
					start_level(index + 1)
				else:
					state = "finished"
					state_t = 0.0
		"dead":
			if state_t > P.getf("rules.death_delay"):
				start_level(index)
		"finished":
			pass


func _clamp_enemy(e) -> void:
	var b: AABB = arena.get("bounds", AABB())
	if b.size.length() < 0.1:
		return
	# 用世界坐标夹（rig 在敌人节点下会自己漂移，不能夹 local position）
	var wp: Vector3 = e.rig.global_position
	var want := Vector3(clampf(wp.x, b.position.x + 3.0, b.position.x + b.size.x - 3.0),
		wp.y, clampf(wp.z, b.position.z + 3.0, b.position.z + b.size.z - 3.0))
	want = Hit.resolve_circles(want, 1.1 * e.scale_factor, arena.get("cover", []), wp.y)
	if not want.is_equal_approx(wp):
		e.global_position += Vector3(want.x - wp.x, 0.0, want.z - wp.z)


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
