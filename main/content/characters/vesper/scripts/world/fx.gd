extends Node3D
## Impact VFX generated at runtime: pressure rings, embers, flashes, dust.
## Everything is code-built and animated with simple ballistic maths.

const MK = preload("res://scripts/mech/mesh_kit.gd")
const MAT = preload("res://scripts/mech/materials.gd")
const TAU := PI * 2.0

var _items: Array = []
var _rng := RandomNumberGenerator.new()
var _quad_mesh: QuadMesh


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.seed = 0x7A4F11
	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = Vector2.ONE
	set_process(false)


func clear_effects() -> void:
	for it in _items:
		var n: Node = it["node"]
		if is_instance_valid(n):
			n.queue_free()
	_items.clear()


func advance(delta: float) -> void:
	delta = minf(delta, 0.05)
	var i := _items.size() - 1
	while i >= 0:
		var it: Dictionary = _items[i]
		it["age"] = float(it["age"]) + delta
		var t := float(it["age"]) / float(it["life"])
		if t >= 1.0:
			var n: Node = it["node"]
			if is_instance_valid(n):
				n.queue_free()
			_items.remove_at(i)
			i -= 1
			continue
		var node: Node3D = it["node"]
		if not is_instance_valid(node):
			_items.remove_at(i)
			i -= 1
			continue
		match String(it["kind"]):
			"ring":
				var eased := 1.0 - pow(1.0 - t, 2.4)
				var s: float = lerpf(float(it["s0"]), float(it["s1"]), eased)
				node.scale = Vector3(s, s, s)
				node.transparency = clampf(pow(t, 1.35), 0.0, 1.0)
				node.position.y = float(it["y"])
			"ember":
				var vel: Vector3 = it["vel"]
				vel.y -= 12.0 * delta
				it["vel"] = vel
				node.position += vel * delta
				var s2: float = float(it["size"]) * (1.0 - t * 0.55)
				node.scale = Vector3(s2, s2, s2)
				node.transparency = clampf(pow(t, 1.7), 0.0, 1.0)
				if node.position.y < 0.03:
					node.position.y = 0.03
					vel.y = absf(vel.y) * 0.25
					it["vel"] = vel
			"light":
				var l: OmniLight3D = it["node"]
				l.light_energy = float(it["energy"]) * pow(1.0 - t, 3.0)
			"flash":
				var sf: float = lerpf(float(it["s0"]), float(it["s1"]), 1.0 - pow(1.0 - t, 3.0))
				node.scale = Vector3(sf, sf, sf)
				node.transparency = clampf(pow(t, 1.5), 0.0, 1.0)
			"smoke":
				var ss: float = lerpf(float(it["s0"]), float(it["s1"]), sqrt(t))
				node.scale = Vector3(ss, ss, ss)
				node.position.y += float(it["rise"]) * delta
				node.transparency = clampf(pow(t, 1.25), 0.0, 1.0)
		_items[i] = it
		i -= 1


func footstep(pos: Vector3, strength: float) -> void:
	_ring(pos, 0.16, 0.55 + 0.35 * strength, 0.22, 0.004)
	for i in int(1 + strength * 3.0):
		_ember(pos + Vector3(_rng.randf_range(-0.12, 0.12), 0.03, _rng.randf_range(-0.12, 0.12)),
			Vector3(_rng.randf_range(-1.4, 1.4), _rng.randf_range(0.3, 1.6), _rng.randf_range(-1.4, 1.4)) * (0.5 + strength),
			_rng.randf_range(0.035, 0.07), 0.25 + _rng.randf() * 0.15)


func impact(pos: Vector3, strength: float) -> void:
	_ring(pos + Vector3(0, 0.02, 0), 0.28, 2.3 + 1.7 * strength, 0.46, 0.002)
	_ring(pos + Vector3(0, 0.05, 0), 0.14, 1.0, 0.32, 0.02)
	for i in int(8 + strength * 10.0):
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.15, 1.4), _rng.randf_range(-1, 1)).normalized()
		_ember(pos + Vector3(0, 0.2, 0) + dir * _rng.randf_range(0.0, 0.3),
			dir * _rng.randf_range(3.0, 10.0), _rng.randf_range(0.045, 0.105), _rng.randf_range(0.28, 0.60))


func blade_hit(pos: Vector3, dir: Vector3, kind: String, strength: float) -> void:
	if kind == "ground":
		_ring(Vector3(pos.x, 0.02, pos.z), 0.32, 2.8 + strength * 1.5, 0.48, 0.003)
		_ring(Vector3(pos.x, 0.04, pos.z), 0.16, 1.3, 0.32, 0.01)
		for i in 10:
			var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.15, 1.3), _rng.randf_range(-1, 1)).normalized()
			_ember(pos + Vector3(0, 0.12, 0), d * _rng.randf_range(3.0, 9.0),
				_rng.randf_range(0.04, 0.10), _rng.randf_range(0.30, 0.62), MAT.spark())
	else:
		for i in 10:
			var d2 := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
			var bias: Vector3 = dir.normalized() * _rng.randf_range(1.0, 4.0)
			_ember(pos + d2 * _rng.randf_range(0.0, 0.2), d2 * _rng.randf_range(2.0, 7.0) + bias,
				_rng.randf_range(0.025, 0.075), _rng.randf_range(0.22, 0.48), MAT.spark())


func land(pos: Vector3, strength: float) -> void:
	_ring(Vector3(pos.x, 0.02, pos.z), 0.55, 3.2 + strength * 0.8, 0.52, 0.003)
	for i in 14:
		var a := TAU * _rng.randf()
		var r := _rng.randf_range(1.2, 2.6)
		var fp := Vector3(pos.x + cos(a) * r, 0.06, pos.z + sin(a) * r)
		_ember(fp, Vector3(_rng.randf_range(-2.2, 2.2), _rng.randf_range(0.3, 2.6), _rng.randf_range(-2.2, 2.2)),
			_rng.randf_range(0.04, 0.10), _rng.randf_range(0.3, 0.7), MAT.spark())


func _flash(pos: Vector3, size: float, life: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad_mesh
	mi.material_override = MAT.hit_flash()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(0.2, 0.2, 0.2)
	add_child(mi)
	mi.global_position = pos
	_items.append({"node": mi, "kind": "flash", "age": 0.0, "life": life, "s0": 0.2, "s1": size})


func _smoke(pos: Vector3, size: float, life: float, rise: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad_mesh
	mi.material_override = MAT.smoke()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(size * 0.4, size * 0.4, size * 0.4)
	add_child(mi)
	mi.global_position = pos
	_items.append({"node": mi, "kind": "smoke", "age": 0.0, "life": life,
		"s0": size * 0.4, "s1": size, "rise": rise})


func _ring(pos: Vector3, s0: float, s1: float, life: float, y_lift: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad_mesh
	mi.material_override = MAT.ring_fx()
	mi.rotation_degrees.x = -90.0
	mi.scale = Vector3(s0, s0, s0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(pos.x, y_lift, pos.z)
	_items.append({"node": mi, "kind": "ring", "age": 0.0, "life": life, "s0": s0, "s1": s1, "y": pos.y + y_lift})


func _ember(pos: Vector3, vel: Vector3, size: float, life: float, mat: Material = null) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad_mesh
	mi.material_override = mat if mat != null else MAT.dust()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(size, size, size)
	add_child(mi)
	mi.global_position = pos
	_items.append({"node": mi, "kind": "ember", "age": 0.0, "life": life, "vel": vel, "size": size})


func _light_flash(pos: Vector3, energy: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(0.30, 0.60, 1.0)
	l.light_energy = energy
	l.omni_range = 8.5
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos
	_items.append({"node": l, "kind": "light", "age": 0.0, "life": 0.22, "energy": energy})