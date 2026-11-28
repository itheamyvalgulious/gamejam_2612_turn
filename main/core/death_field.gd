extends Node3D
## DeathField —— 关卡级死亡物理管理器（requirement #5/#6/#7）。
##
## 由每个 level 模块在 start_level 里 `DeathField.install(self)`：
##   * arena → StaticBody3D：walls 段 / cover 圆柱 / platforms 台板 /
##     solids+walkables AABB / 主地面薄板（layer 1，世界几何）。
##   * 击杀入口 `enemy_died(enemy, info)`：DeathFracture 模板化切割 +
##     PinJoint ragdoll + 冲量；旧的 Knockdown/Wreckage 路径不再触发。
##   * 碎块管理：layer 1<<8，世界封顶 300 个体（FIFO 回收最老的，
##     连同其 PinJoint），重生时全部清掉并还原被隐藏的 rig 网格。
##   * 推挤体：玩家 + 每个活敌人一根 AnimatableBody3D 胶囊
##     （layer 1<<9，碎块 mask 含它；它自己 mask=0 不被任何东西挡），
##     sync_to_physics 让"被挤开"带真实动量。
##   * F7：发现 /root/TurnSession.body_debug_view() 变化时自动登记
##     body provider（0.5s 刷新画橙线框）。

const Fracture = preload("res://core/death_fracture.gd")

const DEBRIS_LAYER := 1 << 8
const PUSHER_LAYER := 1 << 9
const WORLD_LAYER := 1
const DEBRIS_CAP := 180           # 同时参与物理模拟的碎屑上限
const FROZEN_CAP := 900           # 冻结静态残骸上限（几乎到不了才会真正回收）
const WALL_THICK := 0.45
const FLOOR_THICK := 0.6
const PLATFORM_THICK := 0.5

var _level: Node
var _arena_node: Node3D
var _statics: Node3D
var _debris: Node3D
var _pushers: Node3D
var _live: Array = []                 # 还在模拟的 RigidBody3D FIFO（含整块+碎块）
var _frozen_bodies: Array = []        # 冻结成静态的残骸 FIFO（永不消失，只等清场）
var _joints: Array = []               # {joint, a, b, born_t}
var _frozen := {}                     # enemy -> {"rig","hidden":[[node,vis]]}
var _pusher_map := {}                 # owner(Node) -> AnimatableBody3D
var _bound_view: Node3D
var _report: Dictionary = {}
var _warm_queue: Array = []           # 待预处理的敌人（spawn 后逐帧摊销）
var _pool_chunks: Array = []          # 可复用的盒体碎块刚体（击杀零 new）
var _pool_whole := {}                 # part_key -> [整块刚体]（形状随模板绑定）
const POOL_CHUNK_TARGET := 64         # 池化碎块体数量（覆盖一次击杀的预算）


## ================================================================ 安装
static func install(level: Node) -> Node3D:
	var field: Node3D = null
	for c in level.get_children():
		if c != null and c.get_script() == load("res://core/death_field.gd"):
			field = c
			break
	if field == null:
		field = new()
		field.name = "DeathField"
		level.add_child(field)
	level.set_meta(&"death_field", field)
	field.call("reset")
	return field


static func find(level: Node) -> Node3D:
	if level == null or not is_instance_valid(level):
		return null
	var f: Variant = level.get_meta(&"death_field", null)
	if f != null and is_instance_valid(f):
		return f
	return null


## 敌人侧的统一入口：返回 true 表示新死亡系统已接管（旧 knockdown 不走）。
static func try_kill(enemy: Node, info := {}) -> bool:
	var lvl: Node = enemy.get("level")
	var field := find(lvl)
	if field == null or enemy.get_meta(&"death_done", false):
		return false
	enemy.set_meta(&"death_done", true)
	field.enemy_died(enemy, info)
	return true


## ================================================================ 复位
func reset() -> void:
	_level = get_parent()
	if _statics == null:
		_statics = Node3D.new()
		_statics.name = "Statics"
		add_child(_statics)
		_debris = Node3D.new()
		_debris.name = "Debris"
		add_child(_debris)
		_pushers = Node3D.new()
		_pushers.name = "Pushers"
		add_child(_pushers)
	# 重生：清碎块（回池不销毁）、解冻 rig（respawn 的敌人下一帧会重摆姿态）。
	for e in _frozen.keys():
		_unfreeze(e)
	_frozen.clear()
	for b in _live:
		if is_instance_valid(b):
			_checkin(b)
	_live.clear()
	for b in _frozen_bodies:
		if not is_instance_valid(b):
			continue
		if b is RigidBody3D:
			_checkin(b)
		else:
			b.free()   # 合并的 StaticBody 不进池，直接释放
	_frozen_bodies.clear()
	for j in _joints:
		if is_instance_valid(j["joint"]):
			j["joint"].queue_free()
	_joints.clear()
	# arena 重建过才重做静态体；同一场景重生直接复用。
	var arena: Dictionary = _level.get("arena")
	var node: Node3D = _level.get("arena_node")
	if node != _arena_node or _statics.get_child_count() == 0:
		_arena_node = node
		for c in _statics.get_children():
			c.queue_free()
		if arena is Dictionary:
			_build_statics(arena)
	# 推挤体：活着的对象各一根胶囊。
	_sync_pushers(true)
	# 预热：reset() 运行在 start_level 内（加载遮罩/暂停期），同步排空
	# 队列而不是摊到战斗帧——同型敌人的切割几何已按 rig 签名共享
	# （death_fracture._geo），第二只起只做轻绑定，排空总耗 ≈ 每类型一次。
	_warm_queue.clear()
	var pl_node: Node = _level.get("player")
	if pl_node != null and is_instance_valid(pl_node) and pl_node.get("rig") != null and pl_node.get("rig").has_method("hit_parts"):
		pl_node.get("rig").hit_parts()
	for e in _level.get("enemies") if _level.get("enemies") is Array else []:
		if e != null and is_instance_valid(e):
			e.set_meta(&"death_done", false)
			if e.has_method("hit_parts"):
				e.hit_parts()
			if e.get("rig") != null:
				var t := Fracture.prepare(e, e.get("rig"))
				_prime_whole_pool(t)
	for i in POOL_CHUNK_TARGET - _pool_chunks.size():
		_pool_chunks.append(_make_chunk())


## ================================================================ 静态体
var _static_body: StaticBody3D


func _build_statics(arena: Dictionary) -> void:
	_static_body = _new_static()
	_static_body.name = "ArenaStatic"
	_statics.add_child(_static_body)
	var bounds: AABB = arena.get("bounds", AABB())
	var floor_y := float(arena.get("floor_y", 0.0))
	# 主地面：bounds xz 的一薄板。
	if bounds.size.x > 0.1:
		_add_box(Vector3(bounds.position.x + bounds.size.x * 0.5,
				floor_y - FLOOR_THICK * 0.5,
				bounds.position.z + bounds.size.z * 0.5),
			Vector3(bounds.size.x + 8.0, FLOOR_THICK, bounds.size.z + 8.0))
	# walls 段：沿 (a,b) 的薄长方体（法线方向留厚度）。
	for w in arena.get("walls", []):
		var a: Vector2 = w.get("a", Vector2.ZERO)
		var b: Vector2 = w.get("b", Vector2.ZERO)
		var h := float(w.get("h", 0.0))
		if h <= 0.05 or a.distance_squared_to(b) < 0.01:
			continue
		var y0 := float(w.get("base_y", 0.0))
		var d := b - a
		var dir := Vector3(d.x, 0.0, d.y).normalized()
		var zdir := dir.cross(Vector3.UP).normalized()
		var mid := Vector3((a.x + b.x) * 0.5, y0 + h * 0.5, (a.y + b.y) * 0.5)
		var sh := _box(Vector3(d.length() + WALL_THICK, h, WALL_THICK))
		sh.transform = Transform3D(Basis(dir, Vector3.UP, zdir), mid)
		_static_body.add_child(sh)
	# cover 圆柱：c 是柱心（y = 底），r/h 高。
	for cvr in arena.get("cover", []):
		var c: Vector3 = cvr.get("c", Vector3.ZERO)
		var r := float(cvr.get("r", 0.0))
		var h := float(cvr.get("h", 0.0))
		if r <= 0.02 or h <= 0.02:
			continue
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = h
		cs.shape = cyl
		cs.position = Vector3(c.x, c.y + h * 0.5, c.z)
		_static_body.add_child(cs)
	# platforms {c,hx,hz,h}：顶在 h 的台板；低台填到底，高台只做顶板。
	for p in arena.get("platforms", []):
		if not p is Dictionary:
			continue
		var c: Vector3 = p.get("c", Vector3.ZERO)
		var hx := float(p.get("hx", 0.0))
		var hz := float(p.get("hz", 0.0))
		var top := float(p.get("h", 0.0))
		if hx <= 0.02 or hz <= 0.02 or top <= c.y + 0.02:
			continue
		var th := minf(top - c.y, PLATFORM_THICK)
		var sh := _box(Vector3(hx * 2.0, th, hz * 2.0))
		sh.position = Vector3(c.x, top - th * 0.5, c.z)
		_static_body.add_child(sh)
	# solids / walkables：已是绝对 AABB。
	var done := {}
	var solids: Array = arena.get("solids", [])
	var dynamic_indices: Array = arena.get("dynamic_solid_indices", [])
	for i in solids.size():
		# Moving doors own a body that follows the mesh. A static copy would block the open doorway.
		if i in dynamic_indices:
			continue
		var box = solids[i]
		if box is AABB:
			done[box] = true
			_add_aabb(box)
	for box in arena.get("walkables", []):
		if box is AABB and not done.has(box):
			_add_aabb(box)


func _new_static() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	return body


func _box(size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	return cs


func _add_box(center: Vector3, size: Vector3) -> void:
	var sh := _box(size)
	sh.position = center
	_static_body.add_child(sh)


func _add_aabb(box: AABB) -> void:
	if box.size.x <= 0.01 or box.size.z <= 0.01:
		return
	_add_box(box.get_center(), box.size)


## ================================================================ 击杀
func enemy_died(enemy: Node, info := {}) -> Dictionary:
	var rig: Node3D = enemy.get("rig")
	if rig == null or not is_instance_valid(rig):
		return {}
	# 无刀口信息时（plunge/beam/环境杀）用敌人中心当切点、远离玩家的
	# 方向当剑迹 —— 绝不能让默认 Vector3.ZERO 落到世界原点。
	var e_center: Vector3 = enemy.center() if enemy.has_method("center") \
		else rig.global_position
	var contact: Vector3 = info.get("contact", Vector3.ZERO)
	if contact.length_squared() < 0.01 or contact.distance_to(e_center) > 12.0:
		contact = e_center
	var travel: Vector3 = info.get("travel", Vector3.ZERO)
	if travel.length_squared() < 0.001:
		travel = _kill_dir(enemy, e_center)
	info["contact"] = contact
	info["travel"] = travel
	var t0 := Time.get_ticks_usec()
	_freeze(enemy, rig)
	var res := Fracture.kill(self, enemy, rig, info)
	res["freeze_ms"] = 0.0
	for b: RigidBody3D in res.get("list", []):
		_live.append(b)
	var now_s := Time.get_ticks_msec() / 1000.0
	for j in res.get("joint_list", []):
		var ja := _path_body(j.node_a)
		var jb := _path_body(j.node_b)
		_joints.append({"joint": j, "a": ja, "b": jb, "born_t": now_s})
	# 死掉的敌人不再有推挤体。
	var pb: Node = _pusher_map.get(enemy)
	if pb != null:
		pb.queue_free()
		_pusher_map.erase(enemy)
	_enforce_cap()
	res["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	res["enemy"] = String(enemy.get("enemy_id"))
	_report[String(enemy.get("enemy_id"))] = res
	return res


## 非刀击杀的默认方向：敌人朝远离玩家的方向倒；没有玩家就顺 rig 朝向。
func _kill_dir(enemy: Node, e_center: Vector3) -> Vector3:
	var p: Variant = enemy.get("player")
	if p is Node and is_instance_valid(p):
		var pc: Vector3 = p.center() if p.has_method("center") \
			else (p as Node3D).global_position
		var away := e_center - pc
		away.y = 0.0
		if away.length_squared() > 0.01:
			return away.normalized() * 1.2
	var rig: Node3D = enemy.get("rig")
	if rig != null and is_instance_valid(rig):
		var fwd := -rig.global_basis.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.01:
			return fwd.normalized() * 1.2
	return Vector3.RIGHT * 1.2


func _path_body(p: NodePath) -> Node:
	var n := get_node_or_null(p)
	if n == null and _debris != null:
		n = _debris.get_node_or_null(str(p).get_file())
	return n


func _freeze(enemy: Node, rig: Node3D) -> void:
	var hidden: Array = []
	var stack: Array = [rig]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is GeometryInstance3D or n is Light3D \
				or n is GPUParticles3D or n is CPUParticles3D:
			hidden.append([n, n.visible])
			n.visible = false
	# 也收 rig 之外、enemy 名下的散件（shard 的 field mods 已在 rig 下，
	# 但 encounter 包装层偶尔会自己持特效子节点）。
	for c in enemy.get_children():
		if c != rig and c is GeometryInstance3D:
			hidden.append([c, c.visible])
			c.visible = false
	_frozen[enemy] = {"rig": rig, "hidden": hidden}


func _unfreeze(enemy: Node) -> void:
	var rec: Dictionary = _frozen.get(enemy, {})
	for pair in rec.get("hidden", []):
		if is_instance_valid(pair[0]):
			pair[0].visible = pair[1]


func _enforce_cap() -> void:
	# 只把"已经沉降"的最老碎屑冻结成静态体：还在飞/滚的继续模拟，
	# 宁可临时超上限也不允许半空定格（需求：散落到地上、永不消失）。
	var scanned := 0
	var removed := 0
	while _live.size() > DEBRIS_CAP and scanned < _live.size() and scanned < 64:
		var old: RigidBody3D = _live[0]
		scanned += 1
		if not is_instance_valid(old):
			_live.pop_front()
			continue
		if not _settled(old):
			_live.append(_live.pop_front())   # 未沉降：排到队尾等下次
			continue
		_live.pop_front()
		removed += 1
		for j in _joints.duplicate():
			if j["a"] == old or j["b"] == old:
				if is_instance_valid(j["joint"]):
					j["joint"].queue_free()
				_joints.erase(j)
		_freeze_body(old)


## 沉降判定：必须有"不会动的支撑"——live 刚体支撑可能被推挤体
## 继续搬走，把上面的体冻在半空；只有静态世界/已冻结残骸才算数。
func _settled(body: RigidBody3D) -> bool:
	if not body.sleeping and body.linear_velocity.length_squared() > 0.04:
		return false
	var hit := _support_ray(body)
	if hit.is_empty():
		return false
	var col: Object = hit.get("collider")
	# AnimatableBody3D 推挤体也会动，不算支撑；live 刚体会被推挤/冲击
	# 继续挪动，也不算；只有静态世界几何和已冻结残骸稳定。
	if col is StaticBody3D:
		return true
	return col is RigidBody3D and col.freeze


func _support_ray(body: PhysicsBody3D) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := body.global_position
	var aabb: AABB = body.get_meta(&"aabb", AABB())
	var reach := 0.28 + aabb.get_longest_axis_size() * 0.62
	var q := PhysicsRayQueryParameters3D.create(from,
		from + Vector3.DOWN * reach, WORLD_LAYER | DEBRIS_LAYER,
		[body.get_rid()])
	return space.intersect_ray(q)


## QA/调试用贴地检测：下方有没有任何东西托住（live/静态都算）。
func _has_support(body: PhysicsBody3D) -> bool:
	return not _support_ray(body).is_empty()


## 超上限的碎屑**冻结**而不是消失：FREEZE_MODE_STATIC 让 RigidBody
## 退化成静态体（不再模拟、其他碎屑/推挤体不再搬动它），网格与
## 落地位置原样保留。只有关卡重生/切换才统一清场。
func _freeze_body(body: RigidBody3D) -> void:
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	# 冻住的残骸退到 WORLD 层：live 碎屑 mask 只有 WORLD|PUSHER，
	# 这样才继续支撑沉降判定与落地；live×live 彻底不成对。
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.set_meta(&"frozen", true)
	_frozen_bodies.append(body)
	# 冻结堆也满：最老的一批合并成一个 StaticBody（形状/网格全部
## 原样保留，依然不消失），物理节点数收敛。
	while _frozen_bodies.size() > FROZEN_CAP:
		_merge_frozen(24)


## 把 n 个最老冻结碎屑合成一个 StaticBody3D：CollisionShape/MeshInstance
## 直接重挂（网格共享资源、变换沿用世界位姿），刚体壳回收。
func _merge_frozen(n: int) -> void:
	var merged := StaticBody3D.new()
	merged.name = "Pile"
	merged.collision_layer = WORLD_LAYER
	merged.collision_mask = 0
	merged.top_level = true
	var union := AABB()
	var members := 0
	for i in mini(n, _frozen_bodies.size()):
		var old: Node = _frozen_bodies.pop_front()
		if not is_instance_valid(old):
			continue
		var xf: Transform3D = old.global_transform
		for c in old.get_children():
			c.reparent(merged, true)
		var aabb: AABB = old.get_meta(&"aabb", AABB())
		var waabb: AABB = xf * aabb
		union = waabb if members == 0 else union.merge(waabb)
		old.free()
		members += 1
	if members == 0:
		merged.queue_free()
		return
	# merged 停在原点（top_level），成员子节点保留原世界变换；
	# debug aabb 存的是世界空间并集，配 identity xf 画线框正好。
	merged.set_meta(&"aabb", union)
	merged.set_meta(&"frozen", true)
	_frozen_bodies.push_back(merged)
	_debris.add_child(merged)


## ================================================================ 刚体池
## 击杀帧预算 < 1 帧：所有 new()/CollisionShape/MeshInstance 都在预热期
## 完成；kill 只 add_child + 摆变换 + 设冲量。
func take_whole(p: Dictionary, xf: Transform3D) -> RigidBody3D:
	# 池键用模板路径而不是实例 id：同型敌共享池化整块。
	var key := str(p.get("path", NodePath(""))) + "#" + str(p.get("mod_idx", -1))
	var pool: Array = _pool_whole.get(key, [])
	var body: RigidBody3D = null
	while not pool.is_empty():
		body = pool.pop_back()
		if is_instance_valid(body):
			break
		body = null
	if body == null:
		body = _make_whole(p)
	_pool_whole[key] = pool
	_debris.add_child(body)
	body.global_transform = xf
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = false
	body.freeze = false
	body.set_meta(&"weapon", bool(p["is_weapon"]))
	return body


func _make_whole(p: Dictionary) -> RigidBody3D:
	var body := _new_pool_body("D_" + String(p["node"].name).validate_node_name())
	var shape := CollisionShape3D.new()
	shape.shape = p["whole"]["shape"]
	shape.position = p["whole"].get("shape_pos", Vector3.ZERO)
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.mesh = p["whole"]["mesh"]
	if (p["aabb"] as AABB).size.length() < 0.7:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	body.mass = float(p["whole"]["mass"])
	body.set_meta(&"tris", p["tri_count"])
	body.set_meta(&"aabb", p["aabb"])
	body.set_meta(&"pool_kind", "whole")
	body.set_meta(&"pool_key",
		str(p.get("path", NodePath(""))) + "#" + str(p.get("mod_idx", -1)))
	return body


func take_chunk(mesh: Mesh, aabb: AABB, xf: Transform3D) -> RigidBody3D:
	var body: RigidBody3D = null
	while not _pool_chunks.is_empty():
		body = _pool_chunks.pop_back()
		if is_instance_valid(body):
			break
		body = null
	if body == null:
		body = _make_chunk()
	var shape: CollisionShape3D = body.get_meta(&"shape")
	var box: BoxShape3D = body.get_meta(&"box")
	box.size = aabb.size
	shape.position = aabb.get_center()
	var mi: MeshInstance3D = body.get_meta(&"mi")
	mi.mesh = mesh
	_debris.add_child(body)
	body.global_transform = xf
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = false
	body.freeze = false
	body.mass = maxf(aabb.size.x * aabb.size.y * aabb.size.z * 0.14, 0.04)
	body.set_meta(&"aabb", aabb)
	return body


func _make_chunk() -> RigidBody3D:
	var body := _new_pool_body("C")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	body.set_meta(&"shape", shape)
	body.set_meta(&"box", box)
	body.set_meta(&"mi", mi)
	body.set_meta(&"chunk", true)
	body.set_meta(&"pool_kind", "chunk")
	return body


func _new_pool_body(name_: String) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = name_
	body.collision_layer = DEBRIS_LAYER
	# 碎屑不互相碰撞：60+ 块同帧激活时 live×live 对数爆到 ~1000+，
	# 物理岛解算单帧 100ms+。冻住的残骸放在 WORLD 层，仍然当支撑。
	body.collision_mask = WORLD_LAYER | PUSHER_LAYER
	body.top_level = true
	body.can_sleep = true
	body.gravity_scale = Fracture.GRAVITY_SCALE
	body.physics_material_override = Fracture._phys_mat()
	body.contact_monitor = false
	body.max_contacts_reported = 0
	body.linear_damp = 0.25
	body.angular_damp = 0.65
	return body


## 尸体下场：摘出树、停物理、回池（不销毁 → 池子越打越厚，后续击杀零 new）。
func _checkin(body: RigidBody3D) -> void:
	if not is_instance_valid(body):
		return
	if body.get_parent() == _debris:
		_debris.remove_child(body)
	body.freeze = false
	body.sleeping = true
	body.collision_layer = DEBRIS_LAYER
	body.collision_mask = WORLD_LAYER | PUSHER_LAYER
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	match String(body.get_meta(&"pool_kind", "")):
		"whole":
			var key := String(body.get_meta(&"pool_key", ""))
			if not _pool_whole.has(key):
				_pool_whole[key] = []
			_pool_whole[key].append(body)
		"chunk":
			_pool_chunks.append(body)
		_:
			body.queue_free()


## ================================================================ 推挤体
func _sync_pushers(rebuild := false) -> void:
	if _level == null:
		return
	var want := {}
	var player: Node = _level.get("player")
	if player != null and is_instance_valid(player) and bool(player.get("alive")):
		want[player] = true
	for e in _level.get("enemies") if _level.get("enemies") is Array else []:
		if e != null and is_instance_valid(e) and bool(e.get("alive")) \
				and e.get("rig") != null:
			want[e] = true
	for k in _pusher_map.keys():
		if not want.has(k) or not is_instance_valid(_pusher_map[k]) or rebuild:
			if is_instance_valid(_pusher_map[k]):
				_pusher_map[k].queue_free()
			_pusher_map.erase(k)
	for k in want:
		if _pusher_map.has(k):
			continue
		var body := _new_pusher()
		_pusher_map[k] = body
		_update_pusher(k, body)


func _new_pusher() -> AnimatableBody3D:
	var b := AnimatableBody3D.new()
	b.name = "Push"
	b.collision_layer = PUSHER_LAYER
	b.collision_mask = 0
	b.sync_to_physics = true
	b.top_level = true
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cs.shape = cap
	b.add_child(cs)
	b.set_meta(&"cap", cap)
	_pushers.add_child(b)
	return b


func _update_pusher(owner: Node, body: AnimatableBody3D) -> void:
	var cap := _capsule_of(owner)
	var cap_shape: CapsuleShape3D = body.get_meta(&"cap")
	var a: Vector3 = cap["a"]
	var b: Vector3 = cap["b"]
	cap_shape.radius = maxf(float(cap["r"]), 0.12)
	cap_shape.height = maxf((b - a).length() + cap_shape.radius * 2.0,
		cap_shape.radius * 2.0)
	body.global_transform = _capsule_xf(a, b)


func _capsule_of(owner: Node) -> Dictionary:
	# 玩家走 combat_capsule；敌人用 hit_parts 的联合胶囊（粗推挤即可）。
	if owner.has_method("capsule"):
		var cap: Dictionary = owner.capsule()
		if cap.has("a"):
			return cap
	var parts: Array = []
	if owner.has_method("hit_parts"):
		parts = owner.hit_parts()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var r := 0.0
	for p: Dictionary in parts:
		var pa: Vector3 = p.get("a", Vector3.ZERO)
		var pb: Vector3 = p.get("b", pa)
		var pr := float(p.get("r", 0.4))
		r = maxf(r, pr)
		lo = lo.min(pa).min(pb)
		hi = hi.max(pa).max(pb)
	if parts.is_empty() or lo.x > hi.x:
		var rig: Node3D = owner.get("rig")
		var pos := rig.global_position if rig != null else Vector3.ZERO
		var sc := float(owner.get("scale_factor")) if owner.get("scale_factor") != null else 1.0
		return {"a": pos + Vector3.UP * 0.3 * sc, "b": pos + Vector3.UP * 3.4 * sc,
			"r": 1.0 * sc}
	var c := (lo + hi) * 0.5
	var rad := maxf(r, maxf(hi.x - lo.x, hi.z - lo.z) * 0.5)
	return {"a": Vector3(c.x, lo.y - r * 0.4, c.z),
		"b": Vector3(c.x, hi.y + r * 0.4, c.z), "r": rad}


static func _capsule_xf(a: Vector3, b: Vector3) -> Transform3D:
	var mid := (a + b) * 0.5
	var d := b - a
	var y := d.normalized() if d.length_squared() > 1e-8 else Vector3.UP
	var z := y.cross(Vector3.FORWARD)
	if z.length_squared() < 1e-4:
		z = y.cross(Vector3.RIGHT)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z).orthonormalized(), mid)


## ================================================================ 帧循环
var _cap_tick := 0.0
var _pusher_stagger := false

## --death-prof：物理帧打点（与 nav_field 同款惰性 cmdline 查询）。
var _prof := {}
var _prof_on := false
var _prof_asked := false


func _prof_tick() -> bool:
	if not _prof_asked:
		_prof_asked = true
		_prof_on = "--nav-profile" in OS.get_cmdline_user_args() \
			or "--death-prof" in OS.get_cmdline_user_args()
	return _prof_on


func _prof_add(name: String, start_us: int) -> void:
	var e: Dictionary = _prof.get(name, {"us": 0, "n": 0, "max": 0})
	var us := Time.get_ticks_usec() - start_us
	e["us"] = int(e["us"]) + us
	e["n"] = int(e["n"]) + 1
	e["max"] = maxi(int(e["max"]), us)
	_prof[name] = e


func prof_dump() -> String:
	var out := PackedStringArray()
	var keys := _prof.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = _prof[k]
		out.append("%s=%.1fms/%d/max%.1f" % [k, float(e["us"]) / 1000.0,
			int(e["n"]), float(e["max"]) / 1000.0])
	_prof.clear()
	out.append("live=%d frozen=%d pool=%d" % [_live.size(),
		_frozen_bodies.size(), _pool_chunks.size()])
	return ", ".join(out)


func _physics_process(dt: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_sync_pushers()
	# 推挤胶囊：玩家每帧（移动快、单个体）；敌人 30Hz 交错，
	# 碎屑推挤精度不变（体位近似、对碎屑是持续接触而非瞬时判定）。
	_pusher_stagger = not _pusher_stagger
	var player: Node = _level.get("player")
	var keys := _pusher_map.keys()
	var n := keys.size()
	for i in n:
		var k = keys[i]
		if k == player or (i % 2 == 0) == _pusher_stagger or n == 1:
			_update_pusher(k, _pusher_map[k])
	# 击杀时未沉降的碎屑留在 live 里；每 0.4s 复查一次，
	# 等它们落地后再冻结（防止一直超额模拟、也不允许半空定格）。
	_cap_tick += dt
	if _cap_tick >= 0.4:
		_cap_tick = 0.0
		# 关节沉降解散：超过 1.8s 且两端刚体已慢下/休眠时拆掉 PinJoint3D，让刚体彻底休眠（~0 CPU）
		if not _joints.is_empty():
			var now_s := Time.get_ticks_msec() / 1000.0
			for j in _joints.duplicate():
				if now_s - float(j.get("born_t", 0.0)) < 1.8:
					continue
				var ja = j["a"]
				var jb = j["b"]
				var a_slow: bool = not is_instance_valid(ja) or (ja is RigidBody3D and (bool((ja as RigidBody3D).sleeping) or (ja as RigidBody3D).linear_velocity.length_squared() < 0.08))
				var b_slow: bool = not is_instance_valid(jb) or (jb is RigidBody3D and (bool((jb as RigidBody3D).sleeping) or (jb as RigidBody3D).linear_velocity.length_squared() < 0.08))
				if a_slow and b_slow:
					if is_instance_valid(j["joint"]):
						j["joint"].queue_free()
					_joints.erase(j)
		if _live.size() > DEBRIS_CAP:
			_enforce_cap()
	# --death-prof：打点（平时两次字典查找 ≈ 0 开销）
	if _prof_on or _prof_tick():
		_prof_add("death_phys", _t0)


func _process(_dt: float) -> void:
	# 模板摊销：每帧最多预处理一个敌人 / 补一个池化体，spawn 尖峰被铺平。
	if not _warm_queue.is_empty():
		var item = _warm_queue.pop_front()
		if item is Dictionary and item.get("pool_chunk"):
			_pool_chunks.append(_make_chunk())
		elif item != null and is_instance_valid(item) and item.get("rig") != null:
			var t := Fracture.prepare(item, item.get("rig"))
			_prime_whole_pool(t)
	# 敌人复活 → 还原被隐藏的网格。
	for e in _frozen.keys().duplicate():
		if not is_instance_valid(e):
			_frozen.erase(e)
		elif bool(e.get("alive")):
			_unfreeze(e)
			_frozen.erase(e)
	# F7：视图被重建时重新登记 provider。
	var sess := get_node_or_null("/root/TurnSession")
	var view: Node3D = null
	if sess != null and sess.has_method("body_debug_view"):
		view = sess.body_debug_view()
	if view != _bound_view:
		_bound_view = view
		if view != null and view.has_method("add_body_provider"):
			view.add_body_provider(Callable(self, "debug_bodies"))


## 把模板里的"整块"部位预制一个刚体进池（一个部位一整关最多一个 body
## 在场，prefill 1 个即可；不够时 take_whole 现场补）。
func _prime_whole_pool(t: Dictionary) -> void:
	for p: Dictionary in t.get("parts", []):
		if p.get("tri_count", 0) <= 0 or not p.has("whole"):
			continue
		var key := str(p.get("path", NodePath(""))) \
			+ "#" + str(p.get("mod_idx", -1))
		var pool: Array = _pool_whole.get(key, [])
		if pool.is_empty():
			pool.append(_make_whole(p))
			_pool_whole[key] = pool


## F7 body provider：关卡静态物理体（绿）+ 推挤胶囊（青）+ 活动碎块（橙）+ 冻结残骸（黄绿）。
func debug_bodies() -> Array:
	var out: Array = []
	if _static_body != null and is_instance_valid(_static_body):
		for cs in _static_body.get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape != null:
				var c3 := cs as CollisionShape3D
				var s := c3.shape
				var ab := AABB()
				if s is BoxShape3D:
					var sz := (s as BoxShape3D).size
					ab = AABB(-sz * 0.5, sz)
				elif s is CylinderShape3D:
					var cy := s as CylinderShape3D
					var sz := Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0)
					ab = AABB(-sz * 0.5, sz)
				if ab.size.length_squared() > 1e-6:
					out.append({"aabb": ab, "xf": c3.global_transform,
						"color": Color(0.25, 1.0, 0.45, 0.85)})
	if _pushers != null and is_instance_valid(_pushers):
		for pb in _pushers.get_children():
			if not is_instance_valid(pb):
				continue
			var cap: Variant = pb.get_meta(&"cap", null)
			if cap is CapsuleShape3D:
				var csh := cap as CapsuleShape3D
				var sz := Vector3(csh.radius * 2.0, csh.height, csh.radius * 2.0)
				out.append({"aabb": AABB(-sz * 0.5, sz), "xf": (pb as Node3D).global_transform,
					"color": Color(0.25, 0.9, 1.0, 0.95)})
	for b in _live:
		if not is_instance_valid(b):
			continue
		var aabb: AABB = b.get_meta(&"aabb", AABB())
		out.append({"aabb": aabb, "xf": b.global_transform,
			"color": Color(1.0, 0.55, 0.15, 0.95)})
	for b in _frozen_bodies:
		if not is_instance_valid(b):
			continue
		var aabb: AABB = b.get_meta(&"aabb", AABB())
		out.append({"aabb": aabb, "xf": b.global_transform,
			"color": Color(0.55, 0.9, 0.35, 0.85)})
	return out


## 报告：每类敌人最近一次击杀的统计（play_bench/QA 用）。
func report() -> Dictionary:
	return {"debris": _live.size(), "frozen": _frozen_bodies.size(),
		"joints": _joints.size(),
		"kills": _report.duplicate(), "templates": Fracture.stats()}


func _exit_tree() -> void:
	# 池化节点在树外挂着（_checkin remove_child 但没 free）：退场统一释放，
	# 否则退出时按对象泄漏报。
	for b in _pool_chunks:
		if is_instance_valid(b):
			b.free()
	_pool_chunks.clear()
	for key in _pool_whole.keys():
		for b in _pool_whole[key]:
			if is_instance_valid(b):
				b.free()
	_pool_whole.clear()
