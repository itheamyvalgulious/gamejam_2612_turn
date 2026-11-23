extends Node3D
class_name ModuleField
## ModuleField — the 50..90 physical chunks of SHARD // PHANTOM and the
## dispersal / reform simulation.
##
## ASSEMBLED  : every module rides its joint (rig.global_transform * slot).
## DISPERSING : staggered quadratic Bezier launch from the assembled slot to a
##              spread cloud around the destination, each with its own arc and
##              tumble.
## FLYING     : hold the cloud, slow orbital drift, thrusters boosted.
## REFORMING  : staggered Bezier convergence back onto the destination slots,
##              terminal overshoot + damped settle.
##
## Modules live at top level and are driven from the joint global transforms, so
## the same nodes survive teleports without reparenting.

enum State { ASSEMBLED, DISPERSING, FLYING, REFORMING }

const PK := preload("res://scripts/phantom/phantom_kit.gd")
const PM := preload("res://scripts/phantom/phantom_materials.gd")
const STREAK_SHADER := preload("res://shaders/motion_streak.gdshader")

const MESH_REF := [
	Vector3(0.100, 0.100, 0.024),
	Vector3(0.060, 0.160, 0.026),
	Vector3(0.100, 0.120, 0.028),
	Vector3(0.045, 0.160, 0.020),
	Vector3(0.130, 0.095, 0.022),
]

var rig: PhantomRig
var state: int = State.ASSEMBLED
var mods: Array = []            # {node, plume_i, slot, joint, base_scale, seed}
var meshes: Array = []
var plume_mm: MultiMesh
var plume_node: MultiMeshInstance3D
var streak_mm: MultiMesh
var streak_node: MultiMeshInstance3D

var center := Vector3.ZERO
var spread := 1.8
var fly_time := 0.8
var stagger := 0.28
var arc_height := 0.55
var spin_speed := 480.0
var reform_time := 0.7
var settle_overshoot := 0.06
var thruster_size := 0.012
var thruster_intensity := 1.0
var plume_mat: ShaderMaterial

var sim_t := 0.0
var breath := 0.0025
var breath_time := 0.0
var active := 0

var _start: Array = []      # Transform3D
var _dest: Array = []       # Vector3
var _ctrl: Array = []       # Vector3
var _delay: Array = []
var _fly: Array = []
var _spin_axis: Array = []
var _spin_amt: Array = []
var _orbit_phase: Array = []
var _orbit_speed: Array = []
var _ref_start: Array = []
var _ref_target: Array = []
var _ref_delay: Array = []
var _ref_dur: Array = []
var _rng := RandomNumberGenerator.new()
var _mat: ShaderMaterial
var _phase_cache := -1.0
var _boost := 0.2
var _plume_custom := PackedFloat32Array()


func build(p_rig: PhantomRig, slots: Array, count: int) -> void:
	rig = p_rig
	for c in get_children():
		remove_child(c)
		c.queue_free()
	mods.clear()
	_start.clear()
	_dest.clear()
	_ctrl.clear()
	_delay.clear()
	_fly.clear()
	_spin_axis.clear()
	_spin_amt.clear()
	_orbit_phase.clear()
	_orbit_speed.clear()
	_ref_start.clear()
	_ref_target.clear()
	_ref_delay.clear()
	_ref_dur.clear()
	_rng.seed = 913771
	if meshes.is_empty():
		meshes = [
			PK.module_plate(0.100, 0.100, 0.024, 0.84, 0.96, 0.18),
			PK.module_shard(0.060, 0.160, 0.026),
			PK.module_plate(0.100, 0.120, 0.028, 0.50, 0.88, 0.12),
			PK.module_shard(0.045, 0.160, 0.020),
			PK.module_plate(0.130, 0.095, 0.022, 0.92, 0.68, 0.14),
		]
	_mat = PM.module()
	var picked := rig.select_slots(clampi(count, 2, 90))
	active = picked.size()
	# sparse configurations grow their plates so the body still reads
	if active < 75:
		var boost := sqrt(75.0 / float(active))
		for i in active:
			var cp: Dictionary = picked[i].duplicate()
			var sz: Vector3 = cp["size"]
			cp["size"] = Vector3(minf(sz.x * boost, 0.16), minf(sz.y * boost, 0.16), sz.z)
			picked[i] = cp
	print("[phantom] modules=", active, " pool=", rig.slots.size())
	_plume_custom = PackedFloat32Array()
	_plume_custom.resize(active * 4)
	for i in active:
		var s: Dictionary = picked[i]
		var mi := MeshInstance3D.new()
		mi.top_level = true
		mi.mesh = meshes[int(s["mesh"])]
		mi.material_override = _mat
		mi.name = "M%d" % i
		var sz: Vector3 = s["size"]
		var ref: Vector3 = MESH_REF[int(s["mesh"])]
		mi.set_instance_shader_parameter("fx_tint", PM.TINTS[int(s["tint"])])
		mi.set_instance_shader_parameter("fx_seed", float(s["seed"]))
		mi.set_instance_shader_parameter("fx_edge", float(s["edge"]))
		mi.set_instance_shader_parameter("fx_signal", float(s["signal"]))
		mi.set_instance_shader_parameter("fx_phase", 0.0)
		add_child(mi)
		var scl := Vector3(sz.x / ref.x, sz.y / ref.y, sz.z / ref.z)
		mods.append({
			"node": mi, "slot": s, "joint": rig.joints[s["joint"]],
			"scale": scl * rig.height_scale, "seed": float(s["seed"]),
		})
		_plume_custom[i * 4 + 0] = float(s["seed"])
		_plume_custom[i * 4 + 1] = 0.0
		_plume_custom[i * 4 + 2] = 0.0
		_plume_custom[i * 4 + 3] = 1.0
	# --- plumes: one MultiMesh draw call for the whole swarm
	plume_node = MultiMeshInstance3D.new()
	plume_node.name = "Thrusters"
	plume_node.top_level = true
	plume_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume_node.custom_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 9, 16))
	plume_mm = MultiMesh.new()
	plume_mm.transform_format = MultiMesh.TRANSFORM_3D
	plume_mm.use_custom_data = true
	plume_mm.mesh = PK.plume_cross(1.0, 1.0)
	plume_mm.instance_count = active * 2
	for i in active * 2:
		var sd = _plume_custom[(i % active) * 4]
		plume_mm.set_instance_custom_data(i, Color(sd, 0.0, 0.0, 1.0))
	plume_node.multimesh = plume_mm
	var pmat := ShaderMaterial.new()
	pmat.shader = PM.PLUME_SHADER
	pmat.set_shader_parameter("hot_color", Color(1.0, 0.90, 0.72))
	pmat.set_shader_parameter("flame_color", Color(1.0, 0.20, 0.03))
	pmat.set_shader_parameter("intensity", 1.35)
	plume_node.material_override = pmat
	plume_mat = pmat
	add_child(plume_node)
	# flight motion streaks (one wide additive quad per module)
	streak_node = MultiMeshInstance3D.new()
	streak_node.name = "Streaks"
	streak_node.top_level = true
	streak_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streak_node.custom_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 9, 16))
	streak_mm = MultiMesh.new()
	streak_mm.transform_format = MultiMesh.TRANSFORM_3D
	streak_mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	# shift the quad so its origin is the head edge
	streak_mm.mesh = _head_quad()
	streak_mm.instance_count = active
	streak_node.multimesh = streak_mm
	var smat := ShaderMaterial.new()
	smat.shader = STREAK_SHADER
	streak_node.material_override = smat
	add_child(streak_node)
	state = State.ASSEMBLED
	set_thruster_intensity(thruster_intensity)
	update_plumes(0.0)


## Crossed unit quad along -Z with its origin at the head edge.
## UV.y 0 at the head, 1 at the tail.
func _head_quad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := Vector3.UP
	for plane in 2:
		var a := Vector3(-0.5, 0, 0) if plane == 0 else Vector3(0, -0.5, 0)
		var b := Vector3(0.5, 0, 0) if plane == 0 else Vector3(0, 0.5, 0)
		var c := Vector3(0.5, 0, -1) if plane == 0 else Vector3(0, 0.5, -1)
		var d := Vector3(-0.5, 0, -1) if plane == 0 else Vector3(0, -0.5, -1)
		var nrm := Vector3.UP if plane == 0 else Vector3.RIGHT
		var corners := [a, b, c, d]
		var cu := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for idx in [[0, 1, 2], [0, 2, 3]]:
			var p0: Vector3 = corners[idx[0]]
			var p1: Vector3 = corners[idx[1]]
			var p2: Vector3 = corners[idx[2]]
			var g := (p1 - p0).cross(p2 - p0)
			if g.dot(nrm) < 0.0:
				var tmp: int = idx[1]
				idx[1] = idx[2]
				idx[2] = tmp
			for k in 3:
				var ci: int = idx[k]
				st.set_normal(nrm)
				st.set_uv(cu[ci])
				st.add_vertex(corners[ci])
	return st.commit()


func set_thruster_intensity(v: float) -> void:
	thruster_intensity = clampf(v, 0.0, 3.0)
	if plume_mat:
		plume_mat.set_shader_parameter("intensity", 1.35 * thruster_intensity)
	if plume_node:
		plume_node.visible = thruster_intensity > 0.015
	if streak_node:
		streak_node.visible = thruster_intensity > 0.015


func set_geometry_scale(hs: float) -> void:
	for m in mods:
		var s: Dictionary = m["slot"]
		var ref: Vector3 = MESH_REF[int(s["mesh"])]
		var sz: Vector3 = s["size"]
		m["scale"] = Vector3(sz.x / ref.x, sz.y / ref.y, sz.z / ref.z) * hs


# ------------------------------------------------------------------ assembled

func update_assembled(breath_amp: float, t: float, period := 6.0) -> void:
	breath = breath_amp
	breath_time = t
	for m in mods:
		var slot: Dictionary = m["slot"]
		var jn: Node3D = m["joint"]
		var b := Basis(slot["quat"])
		var pos: Vector3 = slot["pos"]
		var ph := float(m["seed"]) * 2.1
		var br := sin(TAU * t / maxf(period, 0.001) + ph) * breath_amp
		pos += b.z * br
		var xf := jn.global_transform * Transform3D(b, pos)
		var mi: MeshInstance3D = m["node"]
		mi.global_transform = Transform3D(xf.basis.orthonormalized() * Basis().scaled(m["scale"]), xf.origin)
	_set_phase(0.0, 0.22)
	update_plumes(1.0)


func update_plumes(_dt: float) -> void:
	if plume_mm == null:
		return
	if thruster_intensity <= 0.015:
		return
	var sf := 1.0 + 0.35 * (thruster_intensity - 1.0)
	for i in mods.size():
		var m: Dictionary = mods[i]
		var mi: MeshInstance3D = m["node"]
		var xf := mi.global_transform
		var b := xf.basis.orthonormalized()
		var th: float = float(m["scale"].z) * MESH_REF[int(m["slot"]["mesh"])].z
		var hgt: float = float(m["scale"].y) * MESH_REF[int(m["slot"]["mesh"])].y
		var pl := thruster_size * 2.4 * (1.0 + 0.8 * _boost) * sf
		var pw := thruster_size * (1.0 + 0.55 * _boost) * sf
		var pos := xf.origin - b.z * (th * 0.5 + 0.001)
		plume_mm.set_instance_transform(i, Transform3D(b * Basis().scaled(Vector3(pw, pw, pl)), pos))
		plume_mm.set_instance_custom_data(i, Color(float(m["seed"]), _boost, 0.0, 1.0))
		# outer bleed jet on the lower edge of every second module: the visible
		# micro-thruster read while the body is assembled
		var outer_i := i + mods.size()
		if fmod(absf(float(m["seed"]) * 3.71), 1.0) > 0.46:
			var dir := (b * Vector3(0.15, -1.0, 0.55)).normalized()
			var ob := Basis.looking_at(dir, b.y).orthonormalized()
			var op := xf.origin + b * Vector3(0.0, -hgt * 0.36, th * 0.5 + 0.002)
			var ow := thruster_size * 0.62 * (1.0 + 0.5 * _boost) * sf
			var ol := thruster_size * 1.5 * (1.0 + 0.7 * _boost) * sf
			plume_mm.set_instance_transform(outer_i, Transform3D(ob * Basis().scaled(Vector3(ow, ow, ol)), op))
			plume_mm.set_instance_custom_data(outer_i, Color(float(m["seed"]) + 3.3, _boost, 0.0, 1.0))
		else:
			plume_mm.set_instance_transform(outer_i, Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -100, 0)))
			plume_mm.set_instance_custom_data(outer_i, Color(0.0, 0.0, 0.0, 0.0))


func _set_phase(v: float, boost: float) -> void:
	if absf(v - _phase_cache) > 0.01:
		_phase_cache = v
		for m in mods:
			var mi: MeshInstance3D = m["node"]
			mi.set_instance_shader_parameter("fx_phase", v)
	_boost = boost


func _set_boost(b: float) -> void:
	_boost = b


# ------------------------------------------------------------------- disperse

func begin_disperse(p_center: Vector3, p_spread: float, p_fly: float, p_stagger: float,
		p_arc: float, p_spin: float, seed_v := 913771) -> void:
	_rng.seed = seed_v
	spread = p_spread
	fly_time = p_fly
	stagger = p_stagger
	arc_height = p_arc
	spin_speed = p_spin
	center = p_center
	sim_t = 0.0
	_start.clear()
	_dest.clear()
	_ctrl.clear()
	_delay.clear()
	_fly.clear()
	_spin_axis.clear()
	_spin_amt.clear()
	_orbit_phase.clear()
	_orbit_speed.clear()
	var n := mods.size()
	var order: Array = []
	for i in n:
		order.append(i)
	for i in range(n - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	_start.resize(n)
	_dest.resize(n)
	_ctrl.resize(n)
	_delay.resize(n)
	_fly.resize(n)
	_spin_axis.resize(n)
	_spin_amt.resize(n)
	_orbit_phase.resize(n)
	_orbit_speed.resize(n)
	# even-ish sphere directions (golden angle) so the cloud is uniform
	var ga := PI * (3.0 - sqrt(5.0))
	for k in n:
		var i: int = order[k]
		var m: Dictionary = mods[i]
		var mi: MeshInstance3D = m["node"]
		_start[i] = mi.global_transform
		_delay[i] = float(k) / float(maxi(n, 1)) * stagger + _rng.randf() * 0.03
		_fly[i] = fly_time * _rng.randf_range(0.78, 1.16)
		var z := 1.0 - 2.0 * (float(k) + 0.5) / float(n)
		var r := sqrt(maxf(0.0, 1.0 - z * z))
		var th := ga * float(k) + _rng.randf() * 0.5
		var dir := Vector3(cos(th) * r, z, sin(th) * r)
		dir = (dir + Vector3(_rng.randf_range(-0.18, 0.18), _rng.randf_range(-0.18, 0.18),
			_rng.randf_range(-0.18, 0.18))).normalized()
		var rad := spread * _rng.randf_range(0.58, 1.0)
		var d := center + Vector3(dir.x * rad, dir.y * rad * 0.52, dir.z * rad)
		d.y = maxf(d.y, 0.30)
		_dest[i] = d
		var mid: Vector3 = (_start[i].origin + d) * 0.5
		var tang := Vector3(-dir.z, 0.0, dir.x) * _rng.randf_range(-0.9, 0.9)
		_ctrl[i] = mid + Vector3(0, arc_height * _rng.randf_range(0.45, 1.15), 0) \
			+ tang + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
		_spin_axis[i] = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1),
			_rng.randf_range(-1, 1)).normalized()
		_spin_amt[i] = _rng.randf_range(0.55, 1.5)
		_orbit_phase[i] = _rng.randf() * TAU
		_orbit_speed[i] = _rng.randf_range(0.05, 0.16) * (1.0 if _rng.randf() > 0.5 else -1.0)
	state = State.DISPERSING
	eval_disperse(0.0)


func eval_disperse(t: float) -> void:
	sim_t = t
	var phase := 0.0
	var arrived := 0
	for i in mods.size():
		var u := clampf((t - _delay[i]) / maxf(_fly[i], 0.001), 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		var a: Vector3 = _start[i].origin
		var b: Vector3 = _ctrl[i]
		var c: Vector3 = _dest[i]
		var p := a.lerp(b, e).lerp(b.lerp(c, e), e)
		# slow orbital drift once the cloud has formed
		var hold := maxf(t - _delay[i] - _fly[i], 0.0)
		if hold > 0.0:
			var rel := p - center
			var ang: float = _orbit_speed[i] * hold
			var ca := cos(ang)
			var sa := sin(ang)
			rel = Vector3(rel.x * ca - rel.z * sa, rel.y + sin(hold * 1.2 + _orbit_phase[i]) * 0.04,
				rel.x * sa + rel.z * ca)
			p = center + rel
		if u >= 1.0:
			arrived += 1
		var spin := Basis(_spin_axis[i], deg_to_rad(spin_speed) * (t - _delay[i]) * _spin_amt[i])
		var rot: Basis = spin * _start[i].basis.orthonormalized()
		var mi: MeshInstance3D = mods[i]["node"]
		mi.global_transform = Transform3D(rot * Basis().scaled(mods[i]["scale"]), p)
		_update_streak(i, p, u)
		phase = maxf(phase, u)
	_set_phase(clampf(0.18 + 0.42 * phase, 0.0, 1.0), 0.55 + 0.45 * phase)
	if arrived >= mods.size():
		state = State.FLYING
	update_plumes(0.0)


func set_disperse_params(p_center: Vector3, p_spread: float, p_fly: float, p_stagger: float,
		p_arc: float, p_spin: float) -> void:
	center = p_center
	spread = p_spread
	fly_time = p_fly
	stagger = p_stagger
	arc_height = p_arc
	spin_speed = p_spin


# --------------------------------------------------------------------- reform

func begin_reform(p_reform_time: float, p_overshoot: float, seed_v := 713377) -> void:
	_rng.seed = seed_v
	reform_time = p_reform_time
	settle_overshoot = p_overshoot
	_ref_start.clear()
	_ref_target.clear()
	_ref_delay.clear()
	_ref_dur.clear()
	for i in mods.size():
		var m: Dictionary = mods[i]
		var mi: MeshInstance3D = m["node"]
		_ref_start.append(mi.global_transform)
		var target := target_xform(i)
		_ref_target.append(target)
		_ref_delay.append(_rng.randf() * 0.08)
		_ref_dur.append(reform_time * _rng.randf_range(0.82, 1.1))
	sim_t = 0.0
	state = State.REFORMING
	eval_reform(0.0)


func target_xform(i: int) -> Transform3D:
	var m: Dictionary = mods[i]
	var slot: Dictionary = m["slot"]
	var jn: Node3D = m["joint"]
	var xf := jn.global_transform * Transform3D(Basis(slot["quat"]), slot["pos"])
	return Transform3D(xf.basis.orthonormalized() * Basis().scaled(m["scale"]), xf.origin)


func eval_reform(t: float) -> void:
	sim_t = t
	var done := 0
	for i in mods.size():
		var u := clampf((t - _ref_delay[i]) / maxf(_ref_dur[i], 0.001), 0.0, 1.0)
		var s: Transform3D = _ref_start[i]
		var tg: Transform3D = _ref_target[i]
		if u >= 1.0:
			done += 1
		var approach := 0.86
		var p: Vector3
		var e: float
		if u <= approach:
			e = smoothstep(0.0, 1.0, u / approach)
			p = s.origin.lerp(tg.origin, e)
		else:
			var v := (u - approach) / (1.0 - approach)
			p = tg.origin + (tg.origin - s.origin).normalized() * settle_overshoot \
				* sin(v * PI) * (1.0 - v)
			e = 1.0
		var spin := Basis(_spin_axis[i], deg_to_rad(spin_speed) * (t - _ref_delay[i]) * _spin_amt[i])
		var rot_from := spin * s.basis.orthonormalized()
		var rot_to := tg.basis.orthonormalized()
		var rot := rot_from.slerp(rot_to, e).orthonormalized()
		var mi: MeshInstance3D = mods[i]["node"]
		mi.global_transform = Transform3D(rot * Basis().scaled(mods[i]["scale"]), p)
		_update_streak(i, p, u)
	_set_phase(clampf(1.0 - t / maxf(reform_time, 0.001), 0.0, 1.0) * 0.45, 0.5)
	if done >= mods.size():
		state = State.ASSEMBLED
	set_thruster_intensity(thruster_intensity)
	update_plumes(0.0)


func _update_streak(i: int, p: Vector3, u: float) -> void:
	if streak_mm == null:
		return
	var prev := p
	var age0: float = _delay[i]
	var t := sim_t
	var dt := 0.035
	var a := t - dt
	if a < 0.0:
		a = 0.0
	var uu := clampf((a - age0) / maxf(_fly[i], 0.001), 0.0, 1.0)
	var e := uu * uu * (3.0 - 2.0 * uu)
	var aa: Vector3 = _start[i].origin
	var bb: Vector3 = _ctrl[i]
	var cc: Vector3 = _dest[i]
	prev = aa.lerp(bb, e).lerp(bb.lerp(cc, e), e)
	var vel := (p - prev)
	var speed := vel.length() / maxf(dt, 0.001)
	if speed < 0.6 or u >= 0.999:
		streak_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -100, 0)))
		return
	var dir := vel.normalized()
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-4:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up2 := side.cross(dir).normalized()
	var b := Basis(side, up2, dir)
	var ln := clampf(speed * 0.035, 0.06, 0.34)
	var wd := 0.012
	streak_mm.set_instance_transform(i, Transform3D(b * Basis().scaled(Vector3(wd, wd, ln)), p))
	streak_mm.set_instance_custom_data(i, Color(float(mods[i]["seed"]), 0.0, 0.0, 1.0))


func is_assembled() -> bool:
	return state == State.ASSEMBLED


func ref_dur_est() -> float:
	return reform_time * 1.1


func state_name() -> String:
	match state:
		State.ASSEMBLED: return "ASSEMBLED"
		State.DISPERSING: return "DISPERSING"
		State.FLYING: return "FLYING"
		State.REFORMING: return "REFORMING"
	return "?"


## Current cloud spread (max distance from the swarm centre), for the HUD.
func centroid() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for m in mods:
		var mi: MeshInstance3D = m["node"]
		if mi.visible:
			c += mi.global_position
			n += 1
	if n == 0:
		return center
	return c / float(n)


func swarm_radius() -> float:
	var mx := 0.0
	for m in mods:
		mx = maxf(mx, (m["node"] as Node3D).global_position.distance_to(center))
	return mx