extends Node3D
## Fx — global combat VFX bus (autoload).
##
## FROZEN API — gameplay code only ever calls these entry points.
##   spark / clang / slash_arc / impact_ring / death_burst / beam / screen_flash / shake
##   qi_mesh() / arrow_mesh() / laser_mesh()      -> reusable projectile meshes
##   shake_amount                                 -> read by the camera rig
##   beam_persistent / update_beam / free_beam    -> long-lived beams
##
## 全部视觉都走 res://gfx/fx_*.gdshader（无光照 / 加色为主），几何全部程序化生成。
## 粒子用两个常驻 MultiMesh 池（加色 / 混合），每帧只刷新实例，不 New 节点；
## 灯光与定时特效走对象池 + _layers 生命周期表，_process -> advance() 统一推进。
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const ArcShader := preload("res://gfx/fx_arc.gdshader")
const RingShader := preload("res://gfx/fx_ring.gdshader")
const BeamShader := preload("res://gfx/fx_beam.gdshader")
const SparkShader := preload("res://gfx/fx_spark.gdshader")
const SmokeShader := preload("res://gfx/fx_smoke.gdshader")
const FlashShader := preload("res://gfx/fx_flash.gdshader")
const MK := preload("res://src/vesper/mesh_kit.gd")

const MAX_ADD := 420       # 加色粒子池
const MAX_MIX := 180       # 烟雾粒子池
const MAX_LIGHTS := 8      # 复用灯光池
const TAU := PI * 2.0

var shake_amount := 0.0
var time_scale := 1.0

var _flash_layer: CanvasLayer
var _flash: ColorRect
var _flash_col := Color(1, 0.4, 0.25)
var _flash_a := 0.0
var _layers: Array = []     # 通用定时 3D 特效记录

var _mm_add: MultiMeshInstance3D
var _mm_mix: MultiMeshInstance3D
var _p_add: Array = []      # 加色粒子记录
var _p_mix: Array = []      # 烟雾粒子记录
var _lights: Array = []     # {node, age, life, e0}

var _rng := RandomNumberGenerator.new()
var _mesh_cache := {}       # 网格缓存
var _beams := {}            # 持续光束: Node3D -> MeshInstance3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.seed = 0x7A4F11

	_build_particle_pool()
	_build_lights()

	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 60
	add_child(_flash_layer)
	_flash = ColorRect.new()
	var fm := ShaderMaterial.new()
	fm.shader = FlashShader
	_flash.material = fm
	_flash.color = Color(1, 1, 1, 1)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_layer.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	var dt := delta * maxf(0.0, time_scale)
	if dt <= 0.0:
		return
	advance(dt)


# ------------------------------------------------------------------ lifecycle
## 统一的特效推进：粒子 / 灯光 / 定时层 / 抖屏 / 闪白。外部主循环可直接调用。
func advance(delta: float) -> void:
	var dt := minf(delta, 0.05)
	_sim_particles(_p_add, dt)
	_sim_particles(_p_mix, dt)
	_refresh_multimesh()
	_tick_lights(dt)
	shake_amount = maxf(0.0, shake_amount - delta * 2.4)
	_flash_a = maxf(0.0, _flash_a - delta * 2.0)
	if _flash != null:
		(_flash.material as ShaderMaterial).set_shader_parameter("strength", _flash_a)
		(_flash.material as ShaderMaterial).set_shader_parameter("color", _flash_col)
	_tick_layers(dt)


func _tick_layers(dt: float) -> void:
	var kept: Array = []
	for it in _layers:
		it["t"] = float(it["t"]) + dt
		var life: float = float(it["life"])
		var u: float = float(it["t"]) / maxf(life, 0.0001)
		if u >= 1.0:
			var n = it["node"]
			if n != null and is_instance_valid(n):
				n.queue_free()
			continue
		_animate(it, u)
		kept.append(it)
	_layers = kept


func _animate(it: Dictionary, u: float) -> void:
	var n = it["node"]
	if n == null or not is_instance_valid(n):
		return
	match String(it.get("kind", "")):
		"arc":
			var mt = n as Node3D
			var s: float = 1.0 + 0.30 * u
			mt.scale = Vector3(s, s, s)
			for mi in mt.get_children():
				if mi is MeshInstance3D:
					var m := (mi as MeshInstance3D).material_override as ShaderMaterial
					if m != null:
						m.set_shader_parameter("progress", u)
						m.set_shader_parameter("energy",
							float(it["energy"]) * (1.0 - u) * (1.0 - u) * float(mi.get_meta("mul", 1.0)))
		"ring":
			var mt2 = n as Node3D
			var r: float = lerpf(float(it["r0"]), float(it["r1"]), 1.0 - pow(1.0 - u, 2.2))
			mt2.scale = Vector3(r, r, r)
			var mi2 := mt2.get_child(0) as MeshInstance3D
			if mi2 != null:
				var m2 := mi2.material_override as ShaderMaterial
				if m2 != null:
					m2.set_shader_parameter("progress", u)
					m2.set_shader_parameter("energy", float(it["energy"]) * (1.0 - u))
		"beam":
			var mi3 = n as MeshInstance3D
			if mi3 != null:
				var m3 := mi3.material_override as ShaderMaterial
				if m3 != null:
					m3.set_shader_parameter("progress", u)
					m3.set_shader_parameter("energy", float(it["energy"]) * (1.0 - u))


func _push(node: Node3D, kind: String, life: float, extra: Dictionary) -> void:
	var it := {"node": node, "kind": kind, "t": 0.0, "life": life}
	for k in extra.keys():
		it[k] = extra[k]
	_layers.append(it)
	# 极端情况下防止特效层无限增长
	if _layers.size() > 160:
		var old = _layers.pop_front()
		if old != null and is_instance_valid(old["node"]):
			old["node"].queue_free()


# ------------------------------------------------------------------ particle pool
func _build_particle_pool() -> void:
	_mm_add = _make_multimesh(SparkShader, MAX_ADD)
	_mm_mix = _make_multimesh(SmokeShader, MAX_MIX)


func _make_multimesh(shader: Shader, count: int) -> MultiMeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


func _build_lights() -> void:
	for i in MAX_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.45, 0.14)
		l.light_energy = 0.0
		l.omni_range = 9.5
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append({"node": l, "age": 0.0, "life": 0.0, "e0": 0.0})


## 主粒子发射入口。
func _emit_particle(pos: Vector3, vel: Vector3, life: float, size: float,
		color: Color, opts: Dictionary = {}) -> void:
	var smoke: bool = opts.get("smoke", false)
	var pool: Array = _p_mix if smoke else _p_add
	var cap: int = MAX_MIX if smoke else MAX_ADD
	if pool.size() >= cap:
		# O(1) 淘汰一个旧粒子，保证总量硬上限
		pool[0] = pool[pool.size() - 1]
		pool.remove_at(pool.size() - 1)
	var d: Vector3 = vel.normalized() if vel.length_squared() > 1e-6 else Vector3.UP
	pool.append({
		"age": 0.0,
		"life": maxf(0.05, life),
		"pos": pos,
		"vel": vel,
		"size": size,
		"drag": float(opts.get("drag", 1.6)),
		"grav": float(opts.get("grav", 12.0)),
		"color": color,
		"stretch": clampf(float(opts.get("stretch", 0.0)), 0.0, 1.0),
		"dir": d,
		"fade": float(opts.get("fade", 1.6)),
		"grow": float(opts.get("grow", -0.45)),
		"ground": bool(opts.get("ground", true)),
	})


func _sim_particles(pool: Array, dt: float) -> void:
	var i := 0
	while i < pool.size():
		var p: Dictionary = pool[i]
		var age: float = float(p["age"]) + dt
		p["age"] = age
		if age >= float(p["life"]):
			pool[i] = pool[pool.size() - 1]
			pool.remove_at(pool.size() - 1)
			continue
		var vel: Vector3 = p["vel"]
		var drag: float = float(p["drag"])
		vel *= maxf(0.0, 1.0 - drag * dt)
		vel.y -= float(p["grav"]) * dt
		var pos: Vector3 = p["pos"] + vel * dt
		if bool(p["ground"]) and pos.y < 0.03:
			pos.y = 0.03
			vel.y = absf(vel.y) * 0.28
			vel.x *= 0.62
			vel.z *= 0.62
		p["vel"] = vel
		p["pos"] = pos
		pool[i] = p
		i += 1


func _refresh_multimesh() -> void:
	if _mm_add == null or _mm_mix == null:
		return
	_fill(_p_add, _mm_add)
	_fill(_p_mix, _mm_mix)


func _fill(pool: Array, inst: MultiMeshInstance3D) -> void:
	if inst == null or not is_instance_valid(inst) or inst.multimesh == null:
		return
	var mm: MultiMesh = inst.multimesh
	var n := pool.size()
	mm.visible_instance_count = n
	for i in n:
		var p: Dictionary = pool[i]
		var t: float = clampf(float(p["age"]) / float(p["life"]), 0.0, 1.0)
		var s: float = float(p["size"]) * maxf(0.05, 1.0 + float(p["grow"]) * t)
		var ppos: Vector3 = p["pos"]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), ppos))
		var c: Color = p["color"]
		c.a *= pow(1.0 - t, float(p["fade"]))
		mm.set_instance_color(i, c)
		var d: Vector3 = p["dir"]
		mm.set_instance_custom_data(i, Color(
			d.x * 0.5 + 0.5, d.y * 0.5 + 0.5, d.z * 0.5 + 0.5, float(p["stretch"])))


func particle_count() -> int:
	return _p_add.size() + _p_mix.size()


# ------------------------------------------------------------------ light pool
func _emit_light(pos: Vector3, energy: float, life: float,
		color := Color(1.0, 0.45, 0.14)) -> void:
	var best: Dictionary = {}
	for rec in _lights:
		if float(rec["age"]) >= float(rec["life"]):
			best = rec
			break
		if best.is_empty() or float(rec["e0"]) < float(best["e0"]):
			best = rec
	if best.is_empty():
		return
	best["age"] = 0.0
	best["life"] = maxf(0.02, life)
	best["e0"] = energy
	var l := best["node"] as OmniLight3D
	l.global_position = pos
	l.light_color = color
	l.light_energy = energy
	l.visible = true


func _tick_lights(dt: float) -> void:
	for rec in _lights:
		if float(rec["age"]) >= float(rec["life"]):
			continue
		rec["age"] = float(rec["age"]) + dt
		var t: float = clampf(float(rec["age"]) / maxf(0.0001, float(rec["life"])), 0.0, 1.0)
		var l := rec["node"] as OmniLight3D
		l.light_energy = float(rec["e0"]) * pow(1.0 - t, 3.0)
		if t >= 1.0:
			l.light_energy = 0.0
			l.visible = false


# ------------------------------------------------------------------ material helpers
func _mat(shader: Shader, color: Color, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	return m


# ------------------------------------------------------------------ hits
func spark(pos: Vector3, dir := Vector3.UP, power := 1.0) -> void:
	var p := clampf(power, 0.15, 3.0)
	var base: Vector3 = dir.normalized() if dir.length_squared() > 1e-5 else Vector3.UP
	# 命中核心闪光
	_emit_particle(pos, Vector3.ZERO, 0.10, 0.55 + 0.45 * p,
		Color(1.0, 0.72, 0.38, 1.1), {"grav": 0.0, "drag": 6.0, "grow": 1.6, "fade": 2.4})
	# 方向性火花：一半沿命中法线喷溅，一半向上炸开
	var n := int(8 + 12 * p)
	for i in n:
		var d := _dir_spread(base, 0.55) if i % 2 == 0 else _hemi(Vector3.UP, 0.8)
		var speed := _rng.randf_range(6.0, 16.0) * (0.75 + 0.45 * p)
		_emit_particle(pos + d * 0.05, d * speed, _rng.randf_range(0.12, 0.34),
			_rng.randf_range(0.05, 0.14),
			Color(1.0, _rng.randf_range(0.42, 0.72), 0.18, 1.0),
			{"grav": 16.0, "drag": 1.1, "fade": 1.4, "stretch": 1.0})
	# 少量上浮烟尘
	for i in 2:
		_emit_particle(pos + Vector3(_rng.randf_range(-0.2, 0.2), 0.1, _rng.randf_range(-0.2, 0.2)),
			Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.6, 1.6), _rng.randf_range(-0.6, 0.6)),
			_rng.randf_range(0.4, 0.7), _rng.randf_range(0.35, 0.6),
			Color(0.20, 0.17, 0.15, 0.26), {"smoke": true, "grav": -1.5, "drag": 1.2, "grow": 1.1})
	_emit_light(pos + Vector3.UP * 0.4, 4.0 + 3.0 * p, 0.18)


func clang(pos: Vector3, dir := Vector3.UP) -> void:
	# 打铁：白色高能火花 + 冲击环 + 强光
	_emit_particle(pos, Vector3.ZERO, 0.09, 0.8,
		Color(1.0, 0.98, 0.92, 1.5), {"grav": 0.0, "drag": 7.0, "grow": 1.8, "fade": 2.6})
	var n := 16
	for i in n:
		var d := _dir_spread(dir, 1.0)
		var speed := _rng.randf_range(7.0, 19.0)
		_emit_particle(pos + d * 0.04, d * speed, _rng.randf_range(0.14, 0.40),
			_rng.randf_range(0.05, 0.13),
			Color(1.0, _rng.randf_range(0.85, 1.0), _rng.randf_range(0.55, 0.9), 1.0),
			{"grav": 17.0, "drag": 0.9, "fade": 1.2, "stretch": 1.0})
	impact_ring(pos, 1.3, 0.5)
	_emit_light(pos + Vector3.UP * 0.3, 7.0, 0.16, Color(1.0, 0.9, 0.7))


func impact_ring(pos: Vector3, radius := 3.0, power := 1.0) -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _disc()
	mi.material_override = _mat(RingShader, Color(1.0, 0.62, 0.22), 1.7 * power)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	add_child(root)
	root.global_position = pos + Vector3(0, 0.03, 0)
	_push(root, "ring", 0.46, {"r0": radius * 0.14, "r1": radius, "energy": 1.7 * power})
	# 扬尘
	for i in int(4 + 6 * power):
		var a := _rng.randf() * TAU
		var r := radius * _rng.randf_range(0.2, 0.7)
		_emit_particle(Vector3(pos.x + cos(a) * r, 0.12, pos.z + sin(a) * r),
			Vector3(cos(a) * _rng.randf_range(0.4, 2.0), _rng.randf_range(0.4, 1.8), sin(a) * _rng.randf_range(0.4, 2.0)),
			_rng.randf_range(0.4, 0.8), _rng.randf_range(0.3, 0.7) * (0.6 + 0.5 * power),
			Color(0.22, 0.19, 0.16, 0.24), {"smoke": true, "grav": -1.6, "drag": 1.3, "grow": 1.0})


func death_burst(pos: Vector3) -> void:
	impact_ring(pos, 9.0, 1.6)
	# 向上爆发的能量柱
	beam(pos + Vector3.UP * 0.2, pos + Vector3.UP * 6.5, 1.4, Color(1.0, 0.55, 0.2), 0.34)
	# 四散碎屑
	for i in 34:
		var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 1.5), _rng.randf_range(-1, 1)).normalized()
		var speed := _rng.randf_range(6.0, 18.0)
		_emit_particle(pos + d * _rng.randf_range(0.1, 0.5), d * speed,
			_rng.randf_range(0.4, 1.1), _rng.randf_range(0.08, 0.2),
			Color(1.0, _rng.randf_range(0.35, 0.7), 0.16, 1.0),
			{"grav": 14.0, "drag": 0.7, "fade": 1.3, "stretch": 0.9})
	for i in 8:
		_emit_particle(pos + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.1, 1.2), _rng.randf_range(-1, 1)),
			Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(1.0, 3.0), _rng.randf_range(-1.5, 1.5)),
			_rng.randf_range(0.6, 1.2), _rng.randf_range(0.7, 1.3),
			Color(0.21, 0.18, 0.16, 0.28), {"smoke": true, "grav": -1.8, "drag": 1.0, "grow": 1.2})
	screen_flash(0.35, Color(1.0, 0.55, 0.25))
	shake(1.4)
	_emit_light(pos + Vector3.UP * 1.2, 14.0, 0.34, Color(1.0, 0.6, 0.25))


# ------------------------------------------------------------------ slashes / beams
func slash_arc(xf: Transform3D, radius := 3.4, arc := 2.4,
		color := Color(1, 0.4, 0.12), life := 0.24) -> void:
	var root := Node3D.new()
	# 主体刃弧
	var mi := MeshInstance3D.new()
	mi.mesh = _arc_mesh(radius, arc, 1.0)
	mi.material_override = _mat(ArcShader, color, 2.8)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("mul", 1.0)
	root.add_child(mi)
	# 拖尾层：更大、更淡，滞后于刃口
	var tr := MeshInstance3D.new()
	tr.mesh = _arc_mesh(radius * 0.95, arc * 1.03, 1.45)
	var tm := _mat(ArcShader, color.darkened(0.22), 1.15)
	tm.set_shader_parameter("trail_len", 1.15)
	tm.set_shader_parameter("tear", 0.8)
	tr.material_override = tm
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tr.set_meta("mul", 0.8)
	root.add_child(tr)
	add_child(root)
	root.global_transform = xf
	_push(root, "arc", maxf(0.05, life), {"energy": 2.6})


func beam(from: Vector3, to: Vector3, width := 0.6,
		color := Color(1, 0.2, 0.6), life := 0.25) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _beam_tube()
	mi.material_override = _mat(BeamShader, color, 2.4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_place_beam(mi, from, to, width)
	_push(mi, "beam", maxf(0.05, life), {"energy": 2.4})


func beam_persistent(from: Vector3, to: Vector3, width: float, color: Color) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _beam_tube()
	var m := _mat(BeamShader, color, 2.2)
	m.set_shader_parameter("scroll", 1.6)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	add_child(root)
	_beams[root] = mi
	_place_beam(mi, from, to, width)
	return root


func update_beam(node: Node3D, from: Vector3, to: Vector3, width: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not _beams.has(node):
		return
	var mi = _beams[node]
	if mi == null or not is_instance_valid(mi):
		return
	_place_beam(mi, from, to, width)


func free_beam(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	_beams.erase(node)
	node.queue_free()


func _place_beam(mi: MeshInstance3D, from: Vector3, to: Vector3, width: float) -> void:
	var d := to - from
	var len := d.length()
	mi.scale = Vector3(maxf(0.02, width), maxf(0.02, width), maxf(0.05, len))
	if len < 0.0001:
		mi.global_position = from
		mi.global_rotation = Vector3.ZERO
		return
	mi.global_position = from
	# 方向近乎竖直时换一个 up，避免 look_at 的 up 与方向平行报错
	var up := Vector3.UP
	if absf(d.normalized().dot(Vector3.UP)) > 0.995:
		up = Vector3.FORWARD
	mi.look_at(to, up)
	# 单位光束网格从 z=0 伸向 -Z，look_at 已让 -Z 指向 to，无需额外旋转


func screen_flash(strength: float, color := Color(1, 0.4, 0.25)) -> void:
	_flash_col = color
	_flash_a = maxf(_flash_a, clampf(strength, 0.0, 1.0))


func shake(amount: float) -> void:
	shake_amount = minf(3.5, shake_amount + amount)


# ------------------------------------------------------------------ projectile meshes
func qi_mesh() -> Mesh:
	if _mesh_cache.has("qi"):
		return _mesh_cache["qi"]
	# 月牙向相机侧倾斜，避免被高机位压成一条线
	var m := _qi_crescent(2.0, 0.82, 0.11, 30, deg_to_rad(34.0))
	var mat := _mat(ArcShader, Color(1.0, 0.55, 0.24), 1.6)
	mat.set_shader_parameter("progress", 1.0)   # 飞行物常亮，不做挥砍扫描
	mat.set_shader_parameter("tear", 0.5)
	m.surface_set_material(0, mat)
	_mesh_cache["qi"] = m
	return m


func arrow_mesh() -> Mesh:
	if _mesh_cache.has("arrow"):
		return _mesh_cache["arrow"]
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.63, 0.68)
	steel.metallic = 0.75
	steel.roughness = 0.32
	steel.emission_enabled = true
	steel.emission = Color(0.10, 0.11, 0.15)
	steel.emission_energy_multiplier = 0.35
	var steel_bright := StandardMaterial3D.new()
	steel_bright.albedo_color = Color(0.86, 0.87, 0.91)
	steel_bright.metallic = 0.9
	steel_bright.roughness = 0.2
	steel_bright.emission_enabled = true
	steel_bright.emission = Color(0.32, 0.34, 0.42)
	steel_bright.emission_energy_multiplier = 0.5
	var feather := StandardMaterial3D.new()
	feather.albedo_color = Color(0.85, 0.30, 0.14)
	feather.metallic = 0.1
	feather.roughness = 0.6
	feather.emission_enabled = true
	feather.emission = Color(1.0, 0.32, 0.12)
	feather.emission_energy_multiplier = 1.2

	var parts: Array = []
	# 箭杆：沿 -Z，从 z=-0.10 到 z=-1.35（长 1.25）
	parts.append({"mesh": MK.prism(6, 0.055, 0.055, 1.5),
		"xf": _axis_y_to_neg_z(Vector3(0, 0, -0.75)), "mat": steel})
	# 箭头：锥体指向 -Z，z=-1.20 .. -1.50
	parts.append({"mesh": MK.prism(6, 0.115, 0.0, 0.30),
		"xf": _axis_y_to_neg_z(Vector3(0, 0, -1.35)), "mat": steel_bright})
	# 尾羽：3 片，绕 Z 轴均布，沿箭杆方向展开
	for k in 3:
		var ang := TAU * float(k) / 3.0 + 0.4
		var xf := Transform3D(Basis(Vector3.BACK, ang), Vector3(0, 0, -0.24))
		parts.append({"mesh": MK.slab(0.02, 0.26, 0.13, 0.006), "xf": xf, "mat": feather})
	var out := _merge_surfaces(parts)
	_mesh_cache["arrow"] = out
	return out


func laser_mesh() -> Mesh:
	if _mesh_cache.has("laser"):
		return _mesh_cache["laser"]
	var m := _beam_tube()
	var mat := _mat(BeamShader, Color(1.0, 0.25, 0.55), 2.6)
	mat.set_shader_parameter("scroll", 2.0)
	m.surface_set_material(0, mat)
	_mesh_cache["laser"] = m
	return m


# ------------------------------------------------------------------ mesh helpers
func _disc(segs := 48) -> ArrayMesh:
	if _mesh_cache.has("disc"):
		return _mesh_cache["disc"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := Vector3(cos(a0), 0, sin(a0)) * 0.5
		var p1 := Vector3(cos(a1), 0, sin(a1)) * 0.5
		st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(Vector3.ZERO)
		st.set_uv(Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5)); st.add_vertex(p0)
		st.set_uv(Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5)); st.add_vertex(p1)
	var m: ArrayMesh = st.commit()
	_mesh_cache["disc"] = m
	return m


## 兼容保留：旧的外部圆环网格实现（现在改用 _disc）。
func _ring_mesh(segs := 48) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		var p := Vector3(cos(a), 0.0, sin(a)) * 0.5
		st.set_uv(Vector2(float(i) / float(segs), 0.0))
		st.add_vertex(p)
		st.set_uv(Vector2(float(i) / float(segs), 1.0))
		st.add_vertex(Vector3(0, 0, 0))
	return st.commit()


## 刃弧（月牙）网格，位于 XZ 平面。UV.x 沿弧长，UV.y 径向 0(内)->1(外)。
func _arc_mesh(radius: float, arc: float, thickness := 1.0) -> ArrayMesh:
	var key := "arc_%.3f_%.3f_%.3f" % [radius, arc, thickness]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 40
	for i in segs:
		var u0 := float(i) / float(segs)
		var u1 := float(i + 1) / float(segs)
		var a0 := -arc * 0.5 + arc * u0
		var a1 := -arc * 0.5 + arc * u1
		var ri := radius * 0.37
		var ro := radius * 0.5
		var p0i := Vector3(sin(a0) * ri, 0, -cos(a0) * ri)
		var p1i := Vector3(sin(a1) * ri, 0, -cos(a1) * ri)
		var p0o := Vector3(sin(a0) * ro * thickness, 0, -cos(a0) * ro)
		var p1o := Vector3(sin(a1) * ro * thickness, 0, -cos(a1) * ro)
		st.set_uv(Vector2(u0, 0.0)); st.add_vertex(p0i)
		st.set_uv(Vector2(u1, 1.0)); st.add_vertex(p1o)
		st.set_uv(Vector2(u0, 1.0)); st.add_vertex(p0o)
		st.set_uv(Vector2(u0, 0.0)); st.add_vertex(p0i)
		st.set_uv(Vector2(u1, 0.0)); st.add_vertex(p1i)
		st.set_uv(Vector2(u1, 1.0)); st.add_vertex(p1o)
	var m: ArrayMesh = st.commit()
	_mesh_cache[key] = m
	return m


## 单位光束网格：沿 -Z 从 z=0 到 z=-1，宽 1，3 片交叉四边形。UV.x 沿长度。
func _beam_tube() -> ArrayMesh:
	if _mesh_cache.has("beam_tube"):
		return _mesh_cache["beam_tube"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 3
	for k in quads:
		var th := PI * float(k) / float(quads)
		var u := Vector3(cos(th), sin(th), 0)
		var a := -u * 0.5
		var b := u * 0.5
		# quad: a@z0, b@z0, b@z-1, a@z-1,  uv.x 沿 -Z
		_add_quad(st, a, b, b + Vector3(0, 0, -1), a + Vector3(0, 0, -1),
			Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	var m: ArrayMesh = st.commit()
	_mesh_cache["beam_tube"] = m
	return m


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_vert(st, a, ua)
	_vert(st, b, ub)
	_vert(st, c, uc)
	_vert(st, a, ua)
	_vert(st, c, uc)
	_vert(st, d, ud)


func _vert(st: SurfaceTool, v: Vector3, uv: Vector2) -> void:
	st.set_uv(uv)
	st.add_vertex(v)


## 兼容保留：旧签名（len, width）的一次性光束网格，现返回沿 -Z 的管状网格。
func _beam_mesh(len: float, width: float) -> ArrayMesh:
	var key := "beam_%.3f_%.3f" % [len, width]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := width * 0.5
	for k in 3:
		var th := PI * float(k) / 3.0
		var u := Vector3(cos(th), sin(th), 0)
		var a := -u * h
		var b := u * h
		_add_quad(st, a, b, b + Vector3(0, 0, -len), a + Vector3(0, 0, -len),
			Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	var m: ArrayMesh = st.commit()
	_mesh_cache[key] = m
	return m


## 双向贝塞尔月牙（刀气）：宽度 width，尖端朝 -Z，腹部在 +Z。
## 用两片互相垂直的月牙交叉，保证任何视角都能读出月牙轮廓（单张平面侧看会退化成线）。
func _qi_crescent(width: float, depth: float, thickness: float, segs := 30, tilt := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bases: Array = [
		{"rot": Basis(Vector3.RIGHT, tilt), "w": 1.0},
		{"rot": Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.RIGHT, tilt), "w": 0.86},
	]
	for b in bases:
		_emit_crescent(st, width * float(b["w"]), depth * float(b["w"]), thickness,
			segs, b["rot"])
	return st.commit()


func _emit_crescent(st: SurfaceTool, width: float, depth: float, thickness: float,
		segs: int, rot: Basis) -> void:
	var tip_z := -depth * 0.18
	var a := Vector3(-width * 0.5, 0, tip_z)
	var b := Vector3(width * 0.5, 0, tip_z)
	var outer := Vector3(0, 0, 2.0 * depth + tip_z)
	var inner := Vector3(0, 0, 2.0 * depth * 0.15 + tip_z)
	var h := thickness * 0.5
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var o0 := rot * _bez2(a, outer, b, t0)
		var o1 := rot * _bez2(a, outer, b, t1)
		var i0 := rot * _bez2(a, inner, b, t0)
		var i1 := rot * _bez2(a, inner, b, t1)
		var up := rot * Vector3(0, h, 0)
		_add_quad(st, o0 + up, o1 + up, i1 + up, i0 + up,
			Vector2(t0, 1), Vector2(t1, 1), Vector2(t1, 0), Vector2(t0, 0))
		_add_quad(st, o0 - up, o1 - up, i1 - up, i0 - up,
			Vector2(t0, 1), Vector2(t1, 1), Vector2(t1, 0), Vector2(t0, 0))
		_add_quad(st, o0 - up, o1 - up, o1 + up, o0 + up,
			Vector2(t0, 0), Vector2(t1, 0), Vector2(t1, 1), Vector2(t0, 1))
		_add_quad(st, i0 - up, i1 - up, i1 + up, i0 + up,
			Vector2(t0, 0), Vector2(t1, 0), Vector2(t1, 1), Vector2(t0, 1))


static func _bez2(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	var it := 1.0 - t
	return a * (it * it) + c * (2.0 * it * t) + b * (t * t)


## 把 +Y 朝向的网格变换到 -Z 朝向（箭头/箭杆用）。
static func _axis_y_to_neg_z(pos: Vector3) -> Transform3D:
	var b := Basis(Vector3.RIGHT, -PI * 0.5)
	return Transform3D(b, pos)


func _merge_surfaces(parts: Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	for p in parts:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(p["mesh"], 0, p["xf"])
		var arr := st.commit_to_arrays()
		var idx := out.get_surface_count()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(idx, p["mat"])
	return out


# ------------------------------------------------------------------ small maths
func _hemi(up: Vector3, spread: float) -> Vector3:
	var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	if d.length_squared() < 1e-5:
		d = Vector3.UP
	d = d.normalized().lerp(up.normalized(), clampf(spread, 0.0, 0.98))
	return (d + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))).normalized()


func _dir_spread(base: Vector3, spread: float) -> Vector3:
	var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var b := base.normalized() if base.length_squared() > 1e-5 else Vector3.UP
	return (d.lerp(b, clampf(spread, 0.0, 0.9))).normalized()
