extends Node3D
## LEVIATHAN // ABYSSAL WARDEN — boss contract implementation.
##
## One armoured sphere, eight independent tentacles, two phases.
##
## At any instant: at most 2 tentacles attacking, at most 5 supporting, the
## rest idle. Every `role_period` seconds two random tentacles are re-tasked.
## With three tentacles left the shell opens fully, the plasma core ignites and
## the containment wall + laser become available.
##
## Simulation is deterministic for a given seed/dt. Studio/QA can set `manual`
## and call `sim_step(dt)` themselves; the auto scheduler can be disabled.

signal scene_param_changed(key: String, value: float)
signal state_changed()

const RIG := preload("res://scripts/boss/boss_rig.gd")
const TENT := preload("res://scripts/boss/tentacle.gd")
const BM := preload("res://scripts/boss/boss_materials.gd")
const MK := preload("res://scripts/kit/mesh_kit.gd")
const SK := preload("res://scripts/kit/shape_kit.gd")
const TRAIL_MAT_SHADER := preload("res://shaders/boss_trail.gdshader")
const D2R := PI / 180.0
const TAU := PI * 2.0
const N_TENT := 8
const BODY_R := 2.0
const BODY_SCALE := 2.0 / 3.0
const TENT_N := 40
const FX_RING := preload("res://shaders/fx_ring.gdshader")
const FX_SPARK_P := preload("res://shaders/fx_spark_particle.gdshader")
const FX_VOL := preload("res://shaders/fx_vol_explosion.gdshader")
const ICH0 := preload("res://shaders/ich0_rgba_noise_medium.png")
const ICH2 := preload("res://shaders/ich2_grey_noise_small.png")
const N_BURST := 72

const DEFAULTS := {
	"motion_amp": 1.15, "motion_speed": 1.0, "wave_amp": 1.0,
	"role_period": 2.0, "support_max": 5, "attack_max": 2,
	"shell_speed": 0.22, "laser_interval": 6.2, "laser_power": 1.0,
	"env_energy": 1.0, "env_exposure": 1.08,
	"idle_len": 15.0, "max_accel": 110.0, "bend_radius": 1.40,
	"length_rate": 9.0, "attack3_height": 1.0, "attack3_len": 20.0,
	"overshoot": 2.2, "stand_height": 6.00, "support_min": 3.0,
}

var P: Dictionary = DEFAULTS.duplicate()
var rig
var tents: Array = []
var t := 0.0
var manual := false
var paused := false
var auto_roles := true
var auto_laser := true
var time_scale := 1.0
var motion_mode := "free"
var _circle_r := 1.2
var _circle_period := 10.0
var rng := RandomNumberGenerator.new()
var live := N_TENT
var forced_phase := 0
var phase := 1
var target_chest := Vector3(0.0, 1.15, 14.0)
var target_ground := Vector3(0.0, 0.0, 14.0)
var target_node: Node3D
var body_center := Vector3(0.0, 6.00, 0.0)
var body_h := 6.00
var shell_t := 0.30
var phase2_t := 0.0
var duck := 0.0
var role_timer := 0.0
var since_attack := 0.0
var laser_state := "idle"
var laser_t := 0.0
var laser_timer := 0.0
var laser_charge := 0.0
var beam_dist := 0.0
var last_hit := ""
var steps := 0

var _fallen := false
var _rest_h := 2.06
var _stand_h := 6.00
var _trails: Array = []
var _tip_hist: Array = []
var _impact_pool: Array = []
var _cut_fx: Array = []
var _bursts: Array = []
var _fx_rng := RandomNumberGenerator.new()
var _beam_core: MeshInstance3D
var _beam_glow: MeshInstance3D
var _muzzle: MeshInstance3D
var _laser_mat_core: ShaderMaterial
var _laser_mat_glow: ShaderMaterial
var _impact_mat_cache: Array = []
var _phase2_announced := false
var _sweep_announced := false
var _clear_timer := 0.0
var _min_clear := 999.0
var _telem := 0
var debug_no_mesh := false
var debug_no_relax := false
var debug_no_tent := false
var _shell_set := -10.0
var _p2_set := -10.0
var _charge_set := -10.0


func _ready() -> void:
	rng.seed = 261218
	_fx_rng.seed = 99811
	rig = RIG.new()
	rig.name = "Rig"
	add_child(rig)
	rig.build()
	_build_shadow()
	_build_tentacles()
	_build_trails()
	_build_laser()
	_build_impact_pool()
	_build_burst_pool()
	_build_cut_fx_systems()
	# initial formation: four planted, four loose
	for i in N_TENT:
		if i % 2 == 0:
			tents[i].set_support(body_center, 7.4)
		else:
			tents[i].set_idle()
	role_timer = 0.0
	sim_step(0.016)
	set_process(true)


func _process(dt: float) -> void:
	if manual or paused:
		return
	sim_step(minf(dt, 1.0 / 24.0) * time_scale)


# ==================================================================== build

func _build_tentacles() -> void:
	for i in N_TENT:
		var tn = TENT.new()
		tn.setup(i, rig.socket_dir(i), 0.37 + 0.11 * float(i))
		add_child(tn.root)
		tents.append(tn)


func _build_trails() -> void:
	for i in N_TENT:
		var mi := MeshInstance3D.new()
		mi.name = "Trail%d" % i
		var m := ShaderMaterial.new()
		m.shader = TRAIL_MAT_SHADER
		m.set_shader_parameter("tint", Color(1.0, 0.22, 0.03))
		m.set_shader_parameter("intensity", 1.25)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_trails.append(mi)
		_tip_hist.append(PackedVector3Array())


func _build_laser() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 20
	cyl.rings = 1
	_beam_core = MeshInstance3D.new()
	_beam_core.mesh = cyl
	_laser_mat_core = BM.laser(Color(1.0, 0.92, 0.82), Color(1.0, 0.30, 0.04), 2.2)
	_beam_core.material_override = _laser_mat_core
	_beam_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_core.visible = false
	add_child(_beam_core)
	_beam_glow = MeshInstance3D.new()
	_beam_glow.mesh = cyl
	_laser_mat_glow = BM.laser(Color(1.0, 0.30, 0.04), Color(1.0, 0.06, 0.008), 0.9)
	_beam_glow.material_override = _laser_mat_glow
	_beam_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_glow.visible = false
	add_child(_beam_glow)
	# muzzle flare quad
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_muzzle = MeshInstance3D.new()
	_muzzle.mesh = q
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mm.albedo_texture = BM.contact_shadow().albedo_texture
	mm.albedo_color = Color(1.0, 0.45, 0.12, 0.9)
	mm.disable_receive_shadows = true
	_muzzle.material_override = mm
	_muzzle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.visible = false
	add_child(_muzzle)


func _build_impact_pool() -> void:
	for i in 6:
		var root := Node3D.new()
		root.name = "Impact%d" % i
		add_child(root)
		var mi := MeshInstance3D.new()
		mi.mesh = MK.sphere(1.0, 14, 20, true)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.42, 0.10, 1.0)
		m.disable_receive_shadows = true
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var rq := QuadMesh.new()
		rq.size = Vector2(1, 1)
		var ring := MeshInstance3D.new()
		ring.mesh = rq
		var rm := ShaderMaterial.new()
		rm.shader = FX_RING
		rm.set_shader_parameter("tint", Color(1.0, 0.34, 0.06))
		rm.set_shader_parameter("intensity", 2.2)
		ring.material_override = rm
		ring.rotation_degrees = Vector3(-90, 0, 0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		var li := OmniLight3D.new()
		li.light_color = Color(1.0, 0.32, 0.06)
		li.light_energy = 0.0
		li.omni_range = 7.0
		li.shadow_enabled = false
		root.add_child(li)
		root.visible = false
		_impact_pool.append({"root": root, "quad": mi, "ring": ring, "light": li,
			"mat": m, "ring_mat": rm, "t": 0.0, "active": false})


func _make_spark_pm() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.32
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 3.5
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -17.0, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.particle_flag_align_y = true
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.75, 1.0))
	g.set_color(0.55, Color(1.0, 0.35, 0.05, 0.85))
	g.set_color(1, Color(0.8, 0.12, 0.01, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	return pm


func _make_frag_pm() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.40
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -12.0, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	pm.angular_velocity_min = -540.0
	pm.angular_velocity_max = 540.0
	return pm


func _make_particles(mesh: Mesh, pm: ParticleProcessMaterial,
		amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.65
	p.local_coords = false
	p.emitting = false
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.visibility_aabb = AABB(Vector3(-16, -6, -16), Vector3(32, 22, 32))
	return p


func _build_burst_pool() -> void:
	# 24 one-shot raymarched fireballs, recycled by age. The shader is a 1:1
	# port of Duke's "Volumetric explosion" (shadertoy.com/view/lsySzd), using
	# the original iChannel0 / iChannel2 textures.
	for i in N_BURST:
		var mat := ShaderMaterial.new()
		mat.shader = FX_VOL
		mat.set_shader_parameter("noise_tex", ICH0)
		mat.set_shader_parameter("noise2_tex", ICH2)
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var mi := MeshInstance3D.new()
		mi.name = "CutBurst%d" % i
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_bursts.append({"mi": mi, "mat": mat, "active": false,
			"age": 0.0, "life": 1.0, "rad": 0.8, "seed": 0.0, "ts": 2.2})


func spawn_burst(pos: Vector3, radius: float, life: float) -> void:
	var slot: Dictionary = {}
	var oldest := -1.0
	for b in _bursts:
		if not b["active"]:
			slot = b
			break
		if b["age"] > oldest:
			oldest = b["age"]
			slot = b
	if slot.is_empty():
		return
	slot["active"] = true
	slot["age"] = 0.0
	slot["life"] = life
	slot["rad"] = radius
	slot["seed"] = _fx_rng.randf() * TAU
	slot["ts"] = 2.40 + _fx_rng.randf() * 1.30
	slot["mi"].global_position = pos
	slot["mi"].scale = Vector3.ONE * (radius * 2.42 * 0.62)
	slot["mi"].visible = true
	var mat: ShaderMaterial = slot["mat"]
	mat.set_shader_parameter("seed", slot["seed"])
	mat.set_shader_parameter("time_scale", slot["ts"])
	mat.set_shader_parameter("lt", 0.0)
	mat.set_shader_parameter("fade", 0.0)
	mat.set_shader_parameter("intensity", 1.0)


func _update_bursts(dt: float) -> void:
	for b in _bursts:
		if not b["active"]:
			continue
		b["age"] += dt
		var u: float = b["age"] / b["life"]
		if u >= 1.0:
			b["active"] = false
			b["mi"].visible = false
			continue
		var f := smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.70, 1.0, u))
		var mat: ShaderMaterial = b["mat"]
		mat.set_shader_parameter("lt", b["age"])
		mat.set_shader_parameter("fade", f)
		var k: float = 0.58 + 0.42 * smoothstep(0.0, 0.34, u)
		b["mi"].scale = Vector3.ONE * (b["rad"] * 2.42 * k)


func _build_cut_fx_systems() -> void:
	# Per-limb debris rig: sparks, torn plates and a muzzle light. The fire
	# itself is the raymarched fireball, not sprite particles.
	for i in N_TENT:
		var root := Node3D.new()
		root.name = "CutFX%d" % i
		add_child(root)
		var spark_mesh := CylinderMesh.new()
		spark_mesh.top_radius = 0.008
		spark_mesh.bottom_radius = 0.002
		spark_mesh.height = 0.22
		spark_mesh.radial_segments = 4
		spark_mesh.rings = 1
		var spark_mat := ShaderMaterial.new()
		spark_mat.shader = FX_SPARK_P
		spark_mesh.material = spark_mat
		var sparks := _make_particles(spark_mesh, _make_spark_pm(), 64, 0.60)
		root.add_child(sparks)
		var frag_mesh := MK.plate(0.10, 0.07, 0.02, 0.004)
		frag_mesh.surface_set_material(0, BM.steel_dark())
		var frags := _make_particles(frag_mesh, _make_frag_pm(), 18, 1.0)
		root.add_child(frags)
		var li := OmniLight3D.new()
		li.light_color = Color(1.0, 0.40, 0.10)
		li.light_energy = 0.0
		li.omni_range = 10.0
		li.shadow_enabled = false
		root.add_child(li)
		_cut_fx.append({"root": root, "sparks": sparks, "frags": frags,
			"light": li, "active": false, "next_burst_t": 0.0})


func emit_cut_fx(i: int, pos: Vector3, on: bool, fade: float) -> void:
	if i < 0 or i >= _cut_fx.size():
		return
	var e = _cut_fx[i]
	e["root"].global_position = pos
	e["sparks"].emitting = on
	e["frags"].emitting = on
	if on:
		e["active"] = true
		var fl := 0.72 + 0.28 * absf(sin(t * 23.0 + float(i) * 2.1))
		e["light"].light_energy = 14.0 * fl * clampf(fade, 0.25, 1.0)
		if t >= e["next_burst_t"]:
			e["next_burst_t"] = t + 0.040 + 0.050 * _fx_rng.randf()
			var jitter := Vector3(_fx_rng.randf_range(-0.22, 0.22),
				_fx_rng.randf_range(-0.22, 0.22), _fx_rng.randf_range(-0.22, 0.22))
			var r: float = lerpf(0.85, 1.55, clampf(fade, 0.0, 1.0))
			r *= 0.72 + 0.62 * _fx_rng.randf()
			spawn_burst(pos + jitter, r, 2.10 + 0.90 * _fx_rng.randf())
	else:
		e["active"] = false
		e["light"].light_energy = 0.0


func _stop_cut_fx() -> void:
	for e in _cut_fx:
		e["sparks"].emitting = false
		e["frags"].emitting = false
		e["light"].light_energy = 0.0
		e["active"] = false
		e["sparks"].restart()
		e["frags"].restart()
		e["sparks"].emitting = false
		e["frags"].emitting = false
	for b in _bursts:
		b["active"] = false
		b["mi"].visible = false


# ====================================================================== step
# ====================================================================== step
# ====================================================================== step
# ====================================================================== step
# ====================================================================== step

func sim_step(dt: float) -> void:
	dt = clampf(dt, 0.001, 0.05)
	t += dt
	steps += 1
	# body first: sockets move before the tentacles are re-planned
	_update_body(dt)
	_update_phase(dt)
	_update_scheduler(dt)
	_enforce_roles(dt)
	_update_laser(dt)
	# targets / roles per tentacle
	var ctx := {
		"body_xf": rig.body.global_transform,
		"center": body_center,
		"target": target_chest,
		"time": t,
		"phase": phase,
		"idle_scale": float(P["wave_amp"]),
		"duck": duck,
		"idle_len": float(P["idle_len"]),
		"max_accel": float(P["max_accel"]),
		"bend_radius": float(P["bend_radius"]),
		"length_rate": float(P["length_rate"]),
		"attack3_height": float(P["attack3_height"]),
		"attack3_len": float(P["attack3_len"]),
		"overshoot": float(P["overshoot"]),
		"stand_height": float(P["stand_height"]),
		"support_min": float(P["support_min"]),
		"boss": self,
	}
	if not debug_no_tent:
		for i in N_TENT:
			tents[i].update(dt, ctx)
	if not debug_no_relax:
		_relax_collisions()
	if not debug_no_mesh:
		for i in N_TENT:
			tents[i].build_mesh()
			if tents[i].attack_hit:
				tents[i].attack_hit = false
				_spawn_impact(tents[i].attack_target, 1.0)
				if target_node and target_node.has_method("hit"):
					target_node.hit()
				last_hit = "%s a%d" % [tents[i].mi.name, tents[i].attack_kind]
	_update_trails(dt)
	_update_fx(dt)
	rig.tick_core(dt)
	var dirw := (target_chest - body_center).normalized()
	var loc: Vector3 = rig.body.global_transform.basis.inverse() * dirw
	rig.update_eye(loc, dt)


func _update_body(dt: float) -> void:
	var sup := 0
	for tn in tents:
		if tn.alive and tn.role == "support":
			sup += 1
	_stand_h = float(P["stand_height"])
	var target_h := _rest_h
	if not _fallen:
		target_h = _rest_h + (_stand_h - _rest_h) * clampf(float(sup) / 3.0, 0.0, 1.0)
	body_h = move_toward(body_h, target_h, dt * (1.35 if _fallen else 0.62))
	var amp := float(P["motion_amp"])
	var sp := float(P["motion_speed"])
	var tt := t * sp
	if sup <= 0:
		amp *= 0.45
	# slow 3D drift inside the 2 m budget
	var px := amp * (0.62 * sin(tt * 0.19 + 0.4) + 0.26 * sin(tt * 0.31 + 1.1))
	var pz := amp * (0.55 * sin(tt * 0.23 + 2.0) + 0.20 * sin(tt * 0.37 + 0.3))
	var py := body_h + 0.16 * sin(tt * 0.41 + 0.3)
	if motion_mode == "circle":
		var w := TAU / maxf(_circle_period, 0.5)
		px = _circle_r * cos(w * tt)
		pz = _circle_r * sin(w * tt)
		py = body_h + 0.12 * sin(2.0 * w * tt)
	var roll := 0.024 * sin(tt * 0.21 + 1.0)
	var pitch := 0.018 * sin(tt * 0.27 + 2.4)
	var yaw := 0.030 * sin(tt * 0.11 + 0.2)
	var b := Basis.from_euler(Vector3(pitch, yaw, roll)).scaled(Vector3.ONE * BODY_SCALE)
	rig.body.transform = Transform3D(b, Vector3(px, py, pz))
	body_center = rig.body.global_position
	# contact shadow follows
	if _shadow_mi:
		_shadow_mi.position = Vector3(body_center.x, 0.04, body_center.z)
		var k := clampf((body_center.y - 2.0) / 1.7, 0.0, 1.0)
		_shadow_mi.scale = Vector3.ONE * (4.2 + 1.4 * k)


var _shadow_mi: MeshInstance3D


func _build_shadow() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_shadow_mi = MeshInstance3D.new()
	_shadow_mi.mesh = q
	var m := BM.contact_shadow()
	_shadow_mi.material_override = m
	_shadow_mi.rotation_degrees = Vector3(-90, 0, 0)
	_shadow_mi.scale = Vector3.ONE * 5.0
	_shadow_mi.position = Vector3(0, 0.04, 0)
	_shadow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow_mi)


func _update_phase(dt: float) -> void:
	var want := 1
	if forced_phase > 0:
		want = forced_phase
	else:
		want = 2 if live <= 3 else 1
	if want != phase:
		phase = want
		if phase == 2 and not _phase2_announced:
			_phase2_announced = true
			_spawn_impact(body_center + Vector3(0, -1.0, 0), 1.5)
		state_changed.emit()
	var st := 0.30 if phase == 1 else 1.0
	shell_t = move_toward(shell_t, st, dt * float(P["shell_speed"]))
	var p2 := 1.0 if phase == 2 else 0.0
	phase2_t = move_toward(phase2_t, p2, dt * 0.65)
	if phase == 2 and shell_t > 0.93 and not _sweep_announced:
		_sweep_announced = true
		_spawn_impact(body_center, 2.0)
	if phase == 1:
		_sweep_announced = false
	if absf(shell_t - _shell_set) > 0.0008:
		_shell_set = shell_t
		rig.set_shell(shell_t)
	if absf(phase2_t - _p2_set) > 0.0008 or absf(laser_charge - _charge_set) > 0.004:
		_p2_set = phase2_t
		_charge_set = laser_charge
		rig.set_phase2(phase2_t)
		if rig.orb_mat:
			rig.orb_mat.set_shader_parameter("charge", laser_charge)
			rig.core_mat.set_shader_parameter("charge", laser_charge * 0.8)
	# attack 3 is independent of the other limbs: no ducking or retracting
	duck = move_toward(duck, 0.0, dt * 3.0)


func _update_scheduler(dt: float) -> void:
	since_attack += dt
	if not auto_roles:
		return
	role_timer += dt
	if role_timer >= float(P["role_period"]):
		role_timer = 0.0
		_retask()


func _count_role(r: String) -> int:
	var n := 0
	for tn in tents:
		if tn.alive and tn.role == r:
			n += 1
	return n


func _retask() -> void:
	var eligible: Array = []
	var sup_now := _count_role("support")
	var smin := _support_min()
	for i in N_TENT:
		var tn = tents[i]
		if tn.alive and tn.role != "attack" and tn.role != "explode":
			if sup_now <= smin and tn.role == "support":
				continue
			eligible.append(i)
	if eligible.size() < 2:
		return
	var a: int = eligible[rng.randi_range(0, eligible.size() - 1)]
	var b := a
	while b == a:
		b = eligible[rng.randi_range(0, eligible.size() - 1)]
	for idx in [a, b]:
		_assign_random(idx)
	state_changed.emit()


func _assign_random(idx: int) -> void:
	var tn = tents[idx]
	var atk := _count_role("attack")
	var sup := _count_role("support")
	# never pull a support if that would break the support floor
	if tn.role == "support" and sup <= _support_min():
		return
	if tn.role == "attack":
		return
	var forced_attack := since_attack > 8.0 and atk < int(P["attack_max"])
	var r := rng.randf()
	var choice := "idle"
	if forced_attack:
		choice = "attack"
	elif r < 0.16 and atk < int(P["attack_max"]):
		choice = "attack"
	elif r < 0.52 and sup < int(P["support_max"]):
		choice = "support"
	else:
		choice = "idle"
	if choice == tn.role:
		if choice == "idle" and sup < int(P["support_max"]) and rng.randf() < 0.55:
			choice = "support"
		elif choice == "support":
			choice = "idle"
		elif choice == "attack" and sup < int(P["support_max"]):
			choice = "support"
	if choice == "attack":
		var kind := 1
		var kr := rng.randf()
		var has3 := false
		for other in tents:
			if other.alive and other.role == "attack" and other.attack_kind == 3:
				has3 = true
		if kr < 0.42:
			kind = 1
		elif kr < 0.84:
			kind = 2
		else:
			kind = 3
		if kind == 3 and has3:
			kind = 1
		if tn.role == "support":
			tn.set_idle()
		tn.start_attack(kind, target_chest, body_center)
		tn.role = "attack"
		since_attack = 0.0
		return
	if choice == "support":
		if tn.role == "support":
			choice = "idle"
		if tn.role == "attack":
			return
		tn.set_support(body_center, 7.4)
		return
	# idle
	if tn.role == "attack":
		return
	tn.set_idle()
	tn.role = "idle"


func _support_min() -> int:
	var smin := int(P["support_min"])
	var smax := int(P["support_max"])
	return mini(smin, smax)


func _enforce_roles(_dt: float) -> void:
	# below three limbs the body is down: this rule is part of the fight and
	# applies even in manual/QA mode
	if live < 3:
		if not _fallen:
			_fallen = true
		for i in N_TENT:
			var tn = tents[i]
			if tn.alive and tn.role != "attack" and tn.role != "explode":
				_start_fallen_attack(i)
		return
	if not auto_roles:
		return
	# keep at least support_min planted limbs; idle limbs convert first
	var smin := _support_min()
	var sup := _count_role("support")
	if sup >= smin:
		return
	for i in N_TENT:
		if sup >= smin:
			return
		var tn = tents[i]
		if tn.alive and tn.role == "idle":
			tn.set_support(body_center, 7.4)
			tn.role = "support"
			sup += 1


func _start_fallen_attack(i: int) -> void:
	var tn = tents[i]
	if not tn.alive or tn.role == "attack" or tn.role == "explode":
		return
	var kind := 1 + (i % 2)
	if i % 3 == 2:
		kind = 3
	tn.start_attack(kind, target_chest, body_center)
	tn.role = "attack"


func _on_attack_finished(idx: int, kind: int) -> void:
	if kind == 3:
		_spawn_impact(body_center + Vector3(0, -1.2, 0), 1.2)
	if live < 3 and auto_roles:
		_start_fallen_attack(idx)
	state_changed.emit()


# ================================================================ collisions

func _relax_collisions() -> void:
	_min_clear = 999.0
	var bounds: Array = []
	for i in N_TENT:
		var tn = tents[i]
		if tn.alive and tn.role != "retract" and tn.pts.size() >= TENT_N:
			bounds.append(tn.bound())
		else:
			bounds.append({})
	for it in 2:
		var any := false
		for i in N_TENT:
			var A = tents[i]
			if not A.alive or A.role == "retract" or A.pts.size() < TENT_N:
				continue
			for j in range(i + 1, N_TENT):
				var B = tents[j]
				if not B.alive or B.role == "retract" or B.pts.size() < TENT_N:
					continue
				var ba: Dictionary = bounds[i]
				var bb: Dictionary = bounds[j]
				if ba.is_empty() or bb.is_empty():
					continue
				var amn: Vector3 = ba["mn"]
				var amx: Vector3 = ba["mx"]
				var bmn: Vector3 = bb["mn"]
				var bmx: Vector3 = bb["mx"]
				if amx.x < bmn.x or bmx.x < amn.x or amx.y < bmn.y or bmx.y < amn.y or amx.z < bmn.z or bmx.z < amn.z:
					continue
				var pushed := false
				var wa := 0.5
				var wb := 0.5
				if A.role == "attack" and B.role != "attack":
					wa = 0.10
					wb = 0.90
				elif B.role == "attack" and A.role != "attack":
					wb = 0.10
					wa = 0.90
				elif A.role == "support" and B.role != "support":
					wa = 0.04
					wb = 0.96
				elif B.role == "support" and A.role != "support":
					wb = 0.04
					wa = 0.96
				for ia in range(2, TENT_N - 1, 2):
					for ib in range(2, TENT_N - 1, 2):
						var d: Vector3 = A.pts[ia] - B.pts[ib]
						var dist := d.length()
						var min_d: float = A.radii[ia] + B.radii[ib] + 0.16
						if dist < min_d and dist > 0.0001:
							var push := d / dist * (min_d - dist)
							A.pts[ia] = A.pts[ia] + push * wa
							B.pts[ib] = B.pts[ib] - push * wb
							pushed = true
							any = true
				if pushed:
					# supports are length-locked props: never smooth them, or a
					# collision nudge would shorten the planted limb
					if A.role != "support":
						A.relax_clean()
					if B.role != "support":
						B.relax_clean()
					bounds[i] = A.bound()
					bounds[j] = B.bound()
		if not any:
			break
	# light self-clearance pass (uniform thick chains can graze themselves)
	for i in N_TENT:
		var T = tents[i]
		if not T.alive or T.role == "retract" or T.pts.size() < TENT_N:
			continue
		var disturbed := false
		for ia in range(2, TENT_N - 2, 2):
			for ib in range(ia + 6, TENT_N - 1, 2):
				var dd: Vector3 = T.pts[ia] - T.pts[ib]
				var dl := dd.length()
				var lim: float = T.radii[ia] + T.radii[ib] + 0.02
				if dl < lim and dl > 0.0001:
					var push2 := dd / dl * (lim - dl) * 0.5
					T.pts[ia] = T.pts[ia] + push2
					T.pts[ib] = T.pts[ib] - push2
					disturbed = true
		if disturbed:
			T.relax_clean()
	for tn in tents:
		if tn.alive:
			tn.rebuild_radii()
	_telem += 1
	if _telem % 10 != 0:
		return
	# cheap global clearance sample for telemetry
	for i in N_TENT:
		var A = tents[i]
		if not A.alive:
			continue
		for j in range(i + 1, N_TENT):
			var B = tents[j]
			if not B.alive:
				continue
			for ia in range(3, TENT_N - 1, 4):
				for ib in range(3, TENT_N - 1, 4):
					var d2: float = A.pts[ia].distance_to(B.pts[ib]) - A.radii[ia] - B.radii[ib]
					if d2 < _min_clear:
						_min_clear = d2


# ==================================================================== laser

func _laser_ready() -> bool:
	return phase == 2 and shell_t > 0.90 and phase2_t > 0.5


func _update_laser(dt: float) -> void:
	laser_timer += dt
	if laser_state == "idle":
		laser_charge = maxf(0.0, laser_charge - dt * 2.0)
		if _laser_ready() and auto_laser and laser_timer >= float(P["laser_interval"]):
			laser_state = "charge"
			laser_t = 0.0
			laser_timer = 0.0
	elif laser_state == "charge":
		laser_t += dt
		laser_charge = clampf(laser_t / 0.95, 0.0, 1.0)
		if laser_t >= 0.95:
			laser_state = "fire"
			laser_t = 0.0
			_fire_beam()
	elif laser_state == "fire":
		laser_t += dt
		laser_charge = 1.0
		_update_beam(dt)
		if laser_t >= 0.72:
			laser_state = "cool"
			laser_t = 0.0
			_hide_beam()
	elif laser_state == "cool":
		laser_t += dt
		laser_charge = maxf(0.0, 1.0 - laser_t / 0.55)
		if laser_t >= 0.55:
			laser_state = "idle"
			laser_charge = 0.0
	if laser_state != "fire":
		_hide_beam_visuals_only()


func fire_laser() -> void:
	if not _laser_ready():
		return
	laser_state = "charge"
	laser_t = 0.0
	laser_timer = 0.0


func _fire_beam() -> void:
	var dir := (target_chest - body_center).normalized()
	var origin := body_center + dir * (1.05 + 0.45 * phase2_t)
	beam_dist = origin.distance_to(target_chest)
	var mid := origin.lerp(target_chest, 0.5)
	var b := SK.basis_y(dir)
	var lp := float(P["laser_power"])
	_beam_core.visible = true
	_beam_glow.visible = true
	_beam_core.transform = Transform3D(b * Basis.from_scale(Vector3(0.23 * lp, beam_dist, 0.23 * lp)), mid)
	_beam_glow.transform = Transform3D(b * Basis.from_scale(Vector3(0.72 * lp, beam_dist, 0.72 * lp)), mid)
	_laser_mat_core.set_shader_parameter("intensity", 2.4 * lp)
	_laser_mat_glow.set_shader_parameter("intensity", 1.1 * lp)
	_muzzle.visible = true
	_muzzle.position = origin
	_muzzle.scale = Vector3.ONE * (6.5 * lp)
	_spawn_impact(target_chest, 1.4)
	if target_node and target_node.has_method("hit"):
		target_node.hit()
	last_hit = "laser"
	state_changed.emit()


func _update_beam(_dt: float) -> void:
	var dir := (target_chest - body_center).normalized()
	var origin := body_center + dir * (1.05 + 0.45 * phase2_t)
	beam_dist = origin.distance_to(target_chest)
	var mid := origin.lerp(target_chest, 0.5)
	var b := SK.basis_y(dir)
	var lp := float(P["laser_power"]) * (0.94 + 0.06 * sin(t * 53.0))
	_beam_core.transform = Transform3D(b * Basis.from_scale(Vector3(0.23 * lp, beam_dist, 0.23 * lp)), mid)
	_beam_glow.transform = Transform3D(b * Basis.from_scale(Vector3(0.72 * lp, beam_dist, 0.72 * lp)), mid)
	_muzzle.position = origin
	_muzzle.scale = Vector3.ONE * (6.5 * lp) * (0.9 + 0.1 * sin(t * 41.0))


func _hide_beam() -> void:
	_beam_core.visible = false
	_beam_glow.visible = false
	_muzzle.visible = false


func _hide_beam_visuals_only() -> void:
	if laser_state != "fire":
		_beam_core.visible = false
		_beam_glow.visible = false
		_muzzle.visible = false


# ======================================================================= FX

func _spawn_impact(pos: Vector3, scale_mul: float) -> void:
	var pick = null
	for e in _impact_pool:
		if not e["active"]:
			pick = e
			break
	if pick == null:
		pick = _impact_pool[0]
	pick["active"] = true
	pick["t"] = 0.0
	pick["root"].visible = true
	pick["root"].position = pos
	pick["quad"].position = Vector3.ZERO
	pick["quad"].scale = Vector3.ONE * 0.24 * scale_mul
	pick["mat"].albedo_color = Color(1.0, 0.50, 0.16, 0.75) * scale_mul
	pick["ring"].position = Vector3(0, 0.06 - pos.y, 0)
	pick["ring"].scale = Vector3.ONE * (2.5 * scale_mul)
	pick["ring_mat"].set_shader_parameter("progress", 0.0)
	pick["ring_mat"].set_shader_parameter("intensity", 2.6 * scale_mul)
	pick["light"].light_energy = 5.0 * scale_mul


func _update_fx(dt: float) -> void:
	_update_bursts(dt)
	for e in _impact_pool:
		if not e["active"]:
			continue
		e["t"] += dt
		var u: float = e["t"] / 0.62
		if u >= 1.0:
			e["active"] = false
			e["root"].visible = false
			continue
		e["mat"].albedo_color = Color(1.0, 0.40, 0.10, (1.0 - u) * 0.65) * 1.1
		e["quad"].scale = Vector3.ONE * lerpf(0.24, 1.15, u)
		e["ring_mat"].set_shader_parameter("progress", u)
		e["ring_mat"].set_shader_parameter("intensity", lerpf(2.6, 0.0, u))
		e["ring"].scale = Vector3.ONE * lerpf(2.5, 7.5, u)
		e["light"].light_energy = lerpf(5.0, 0.0, u)


func _update_trails(dt: float) -> void:
	for i in N_TENT:
		var tn = tents[i]
		var hist: PackedVector3Array = _tip_hist[i]
		var active: bool = tn.alive and tn.role == "attack"
		if active:
			var p: Vector3 = tn.tip
			var push := true
			if hist.size() > 0 and hist[hist.size() - 1].distance_to(p) < 0.22:
				push = false
			if push:
				hist.append(p)
				if hist.size() > 30:
					hist.remove_at(0)
			# trim old
			if hist.size() > 2 and hist[0].distance_to(p) > tn.actual_len * 0.95:
				hist.remove_at(0)
		else:
			if hist.size() > 0:
				hist.remove_at(0)
		_tip_hist[i] = hist
		var mi: MeshInstance3D = _trails[i]
		if hist.size() >= 3:
			var mesh := MK.ribbon_cross(hist, 0.20 + 0.22 * float(tn.attack_kind == 3), Vector3.UP, true)
			mi.mesh = mesh
			mi.visible = true
			var mat: ShaderMaterial = mi.material_override
			mat.set_shader_parameter("intensity", 0.55 + 0.35 * float(tn.attack_kind == 3))
		else:
			mi.visible = false
			mi.mesh = null


# ====================================================================== API

func set_motion_mode(mode: String, radius := 1.2, period := 10.0) -> void:
	motion_mode = mode
	_circle_r = clampf(radius, 0.0, 2.0)
	_circle_period = maxf(period, 2.0)
	if mode == "free":
		motion_mode = "free"


func set_target(chest: Vector3, ground: Vector3) -> void:
	target_chest = chest
	target_ground = ground


func set_target_node(n: Node3D) -> void:
	target_node = n


func force_role(i: int, what: String) -> bool:
	if i < 0 or i >= N_TENT:
		return false
	var tn = tents[i]
	if not tn.alive or tn.role == "retract":
		return false
	if tn.role == "attack":
		return false
	match what:
		"idle":
			tn.set_idle()
			tn.role = "idle"
			return true
		"support":
			if _count_role("support") >= int(P["support_max"]):
				return false
			tn.set_support(body_center, 7.4)
			tn.role = "support"
			return true
		"attack1", "attack2", "attack3":
			if _count_role("attack") >= int(P["attack_max"]):
				return false
			var kind := int(what.substr(6))
			tn.start_attack(kind, target_chest, body_center)
			tn.role = "attack"
			since_attack = 0.0
			return true
	return false


func cut_tentacle(i: int) -> bool:
	if i < 0 or i >= N_TENT:
		return false
	var tn = tents[i]
	if not tn.alive or tn.role == "explode":
		return false
	var base: Vector3 = tn.base
	tn.set_explode()
	live -= 1
	if live < 3:
		_fallen = true
		duck = 0.0
		if forced_phase == 0 and phase != 2:
			phase = 2
			if not _phase2_announced:
				_phase2_announced = true
				_spawn_impact(body_center, 1.8)
	elif live <= 3 and forced_phase == 0:
		phase = 2
		if not _phase2_announced:
			_phase2_announced = true
			_spawn_impact(body_center, 1.8)
	state_changed.emit()
	return true


func set_phase_force(p: int) -> void:
	forced_phase = clampi(p, 0, 2)
	if forced_phase == 2:
		_phase2_announced = true
	_update_phase(0.001)
	state_changed.emit()


func set_auto(v: bool) -> void:
	auto_roles = v
	role_timer = 0.0


func reset_boss() -> void:
	_stop_cut_fx()
	live = N_TENT
	_fallen = false
	duck = 0.0
	forced_phase = 0
	phase = 1
	shell_t = 0.30
	phase2_t = 0.0
	laser_state = "idle"
	laser_charge = 0.0
	_hide_beam()
	body_h = _stand_h
	body_center = Vector3(0, _stand_h, 0)
	rig.body.transform = Transform3D(Basis.IDENTITY, body_center)
	phase = 1
	_phase2_announced = false
	_sweep_announced = false
	for i in N_TENT:
		var tn = tents[i]
		tn.alive = true
		tn.mi.visible = true
		if tn.root:
			tn.root.visible = true
		tn.role = "idle"
		tn.attack_t = -1.0
		tn.attack_kind = 0
		tn.retract_t = 0.0
		tn.dyn_ready = false
		tn.planted = false
		tn.foot_valid = false
		tn.trans_t = -1.0
		tn.L = 6.0
		tn.tip = body_center + rig.socket_dir(i) * 3.0
		tn.pts = PackedVector3Array()
		if i % 2 == 0:
			tn.set_support(body_center, 7.4)
		else:
			tn.set_idle()
	_shell_set = -10.0
	_p2_set = -10.0
	_charge_set = -10.0
	rig.set_shell(shell_t)
	rig.set_phase2(phase2_t)
	_shell_set = shell_t
	_p2_set = phase2_t
	_charge_set = laser_charge
	role_timer = 0.0
	since_attack = 0.0
	sim_step(0.016)
	state_changed.emit()


func random_target() -> Vector3:
	var az := deg_to_rad(rng.randf_range(-62.0, 62.0))
	var r := rng.randf_range(11.0, 18.0)
	var g := Vector3(sin(az) * r, 0.0, cos(az) * r + 2.0)
	target_ground = g
	target_chest = g + Vector3(0, 1.15, 0)
	return g


func role_counts() -> Dictionary:
	var d := {"idle": 0, "support": 0, "attack": 0, "retract": 0}
	for tn in tents:
		if not tn.alive:
			continue
		if d.has(tn.role):
			d[tn.role] += 1
	return d


func tentacle_role(i: int) -> String:
	if i < 0 or i >= N_TENT:
		return ""
	return tents[i].role


func status() -> Dictionary:
	var rc := role_counts()
	return {
		"phase": phase, "live": live, "shell": shell_t, "core": phase2_t,
		"support": rc["support"], "attack": rc["attack"], "idle": rc["idle"],
		"laser": laser_state, "charge": laser_charge, "beam": beam_dist,
		"min_clear": _min_clear, "body_h": body_center.y, "last_hit": last_hit,
	}


func rig_debug() -> Dictionary:
	var rc := role_counts()
	return {
		"phase": phase, "live": live, "shell_open": "%.2f" % shell_t,
		"support": rc["support"], "attack": rc["attack"], "idle": rc["idle"],
		"body_height": "%.2f m" % body_center.y, "laser": laser_state,
		"min_clear": "%.3f m" % _min_clear,
	}


# =================================================================== params

func param_specs() -> Array:
	return [
		{"group": "MOTION", "key": "motion_amp", "label": "body drift (m)", "min": 0.0, "max": 12.0, "step": 0.05, "value": P["motion_amp"]},
		{"group": "MOTION", "key": "motion_speed", "label": "body drift speed", "min": 0.05, "max": 6.0, "step": 0.05, "value": P["motion_speed"]},
		{"group": "MOTION", "key": "wave_amp", "label": "idle wave", "min": 0.0, "max": 6.0, "step": 0.02, "value": P["wave_amp"]},
		{"group": "LIMBS", "key": "idle_len", "label": "idle length (m)", "min": 3.0, "max": 30.0, "step": 0.5, "value": P["idle_len"]},
		{"group": "LIMBS", "key": "max_accel", "label": "joint accel cap", "min": 10.0, "max": 3000.0, "step": 5.0, "value": P["max_accel"]},
		{"group": "LIMBS", "key": "bend_radius", "label": "min bend radius", "min": 0.2, "max": 8.0, "step": 0.05, "value": P["bend_radius"]},
		{"group": "LIMBS", "key": "length_rate", "label": "telescope rate", "min": 0.5, "max": 40.0, "step": 0.5, "value": P["length_rate"]},
		{"group": "ROLES", "key": "role_period", "label": "retask period (s)", "min": 0.2, "max": 30.0, "step": 0.1, "value": P["role_period"]},
		{"group": "ROLES", "key": "support_max", "label": "support max", "min": 0.0, "max": 8.0, "step": 1.0, "value": P["support_max"]},
		{"group": "ROLES", "key": "attack_max", "label": "attack max", "min": 0.0, "max": 8.0, "step": 1.0, "value": P["attack_max"]},
		{"group": "ATTACKS", "key": "overshoot", "label": "stab overshoot (m)", "min": 0.0, "max": 6.0, "step": 0.05, "value": P["overshoot"]},
		{"group": "ATTACKS", "key": "attack3_height", "label": "sweep height (m)", "min": 0.5, "max": 12.0, "step": 0.1, "value": P["attack3_height"]},
		{"group": "ATTACKS", "key": "attack3_len", "label": "sweep length (m)", "min": 6.0, "max": 30.0, "step": 0.5, "value": P["attack3_len"]},
		{"group": "SHELL", "key": "shell_speed", "label": "shell speed", "min": 0.01, "max": 4.0, "step": 0.01, "value": P["shell_speed"]},
		{"group": "SHELL", "key": "laser_interval", "label": "laser interval (s)", "min": 0.2, "max": 120.0, "step": 0.1, "value": P["laser_interval"]},
		{"group": "SHELL", "key": "laser_power", "label": "laser power", "min": 0.05, "max": 12.0, "step": 0.05, "value": P["laser_power"]},
		{"group": "STAGE", "key": "env_energy", "label": "ambient", "min": 0.0, "max": 10.0, "step": 0.02, "value": P["env_energy"]},
		{"group": "STAGE", "key": "env_exposure", "label": "exposure", "min": 0.05, "max": 10.0, "step": 0.02, "value": P["env_exposure"]},
	]


func set_param(key: String, value: float) -> void:
	if not P.has(key):
		return
	P[key] = value
	if key == "support_max":
		var excess := _count_role("support") - int(value)
		if excess > 0:
			for tn in tents:
				if excess <= 0:
					break
				if tn.alive and tn.role == "support":
					tn.set_idle()
					tn.role = "idle"
					excess -= 1
	if key == "attack_max":
		var ex := _count_role("attack") - int(value)
		if ex > 0:
			for tn in tents:
				if ex <= 0:
					break
				if tn.alive and tn.role == "attack":
					tn.attack_t = -1.0
					tn.role = "idle"
					ex -= 1
	if key == "env_energy" or key == "env_exposure":
		scene_param_changed.emit(key, value)


func get_param(key: String) -> float:
	return float(P.get(key, 0.0))