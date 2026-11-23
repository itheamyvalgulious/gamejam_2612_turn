extends RefCounted
## LEVIATHAN tentacle: independent motion planning + smooth tube mesh.
##
## Shape pipeline (every tentacle, every frame):
##   1. a mode planner produces a tip target, a target length, a tip approach
##      direction, a bow direction and a "sector plane";
##   2. a cubic Hermite in that vertical plane is bowed until its arc length
##      matches the target length (bisection); two travelling waves add
##      secondary organic motion;
##   3. the curve is resampled to a fixed number of spine points, projected
##      out of the body sphere and above the floor, then re-pinned;
##   4. a procedural tube mesh (rings every 0.22 m, 16 sides) is rebuilt.
##
## Idle and support keep their whole body inside their own vertical sector, so
## eight limbs can never intersect: neighbouring sectors are 45 degrees apart
## and the sector planes share only the vertical axis through the body, which
## every point is at least R_body away from.
##
## Attack 1/2 leave the sector only past the outer third of the limb; attack 3
## sweeps at radius 10 m, outside every idle/support tip. The boss also adds a
## late collision-relaxation pass as a safety net.

const MK := preload("res://scripts/kit/mesh_kit.gd")
const SK := preload("res://scripts/kit/shape_kit.gd")
const BM := preload("res://scripts/boss/boss_materials.gd")
const N := 40                  # spine points
const SIDES := 12              # tube sides
const TIP_R := 0.060
const BASE_R := 0.155
const BALL_R := 0.155
const ROD_R := 0.095
const JOINT_SPACING := 0.60
const JOINT_OFFSET := 0.42
const MAX_LINKS := 60
const SEG_PERIOD := 0.62       # mechanical segment length (m)
const RING_STEP := 0.16

var idx := 0
var dir_local := Vector3.ZERO
var sector_az := 0.0            # body-space azimuth around +Y (from +Z)
var mat: ShaderMaterial
var root: Node3D
var mi: MeshInstance3D
var mesh: ArrayMesh
var rod_mm: MultiMesh
var ball_mm: MultiMesh
var ring_mm: MultiMesh
var rod_mmi: MultiMeshInstance3D
var ball_mmi: MultiMeshInstance3D
var ring_mmi: MultiMeshInstance3D
var ring_mat: StandardMaterial3D
var tip_ring: MeshInstance3D
var foot_mi: MeshInstance3D
var foot_shadow: MeshInstance3D

var role := "idle"              # idle / support / attack / retract
var prev_role := "idle"
var alive := true

var pts := PackedVector3Array()
var radii := PackedFloat32Array()
var actual_len := 6.0

# --- commanded state
var base := Vector3.ZERO
var base_dir_w := Vector3.ZERO
var center := Vector3.ZERO
var tip_target := Vector3.ZERO
var tip := Vector3.ZERO
var tip_vel := Vector3.ZERO
var L := 6.0
var L_target := 6.0
var idle_len := 15.0
var max_accel := 110.0
var bend_radius := 1.40
var length_rate := 9.0
var attack3_height := 4.2
var attack3_len := 15.0
var overshoot := 2.2
var attack_hit_t := 999.0
var attack_rec_t := 9.0
var explode_total := 0.0
var explode_cut := 0.0
var explode_t := 0.0
var explode_dur := 0.9
var explode_burst_t := 0.0
var cut_ember: MeshInstance3D
var explode_pose := PackedVector3Array()
var explode_seed := 0.0
var boss_ref: Node = null
var dyn_pts := PackedVector3Array()
var dyn_vel := PackedVector3Array()
var dyn_ready := false
var bow_dir := Vector3.UP
var approach := Vector3.UP
var wave_amp := 0.0
var wave_phase := 0.0
var wave_phase2 := 0.0
var w1 := 0.22
var w2 := 0.37
var w3 := 0.18
var wave_scale := 1.0
var duck := 0.0
var attack_glow := 0.0

# --- transition / support
var trans_t := -1.0
var trans_dur := 0.8
var trans_from := Vector3.ZERO
var trans_to := Vector3.ZERO
var trans_ctrl := Vector3.ZERO
var foot := Vector3.ZERO
var foot_valid := false
var planted := false
var plant_wait := 0.0

# --- attack
var attack_kind := 0
var attack_t := -1.0
var attack_dur := 0.0
var attack_start_tip := Vector3.ZERO
var attack_target := Vector3.ZERO
var attack_dir := Vector3.ZERO
var attack_over := Vector3.ZERO
var attack_origin := Vector3.ZERO
var attack_az0 := 0.0
var attack_sweep_dir := 1.0
var attack_len := 6.0
var attack_hit_fired := false
var attack_hit := false
var attack_shoulder := Vector3.ZERO
var attack_arc_end := Vector3.ZERO
var attack_sweep_r := 9.5

# --- retract
var retract_t := 0.0

# --- phase offsets (seeded)
var ph := {}
var _sc: PackedFloat32Array = PackedFloat32Array()
var _ss: PackedFloat32Array = PackedFloat32Array()


func setup(index: int, dir_body: Vector3, seed_value: float) -> void:
	idx = index
	dir_local = dir_body.normalized()
	sector_az = atan2(dir_local.x, dir_local.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_value * 100000.0) + index * 7919
	ph = {
		"h1": rng.randf() * TAU, "h2": rng.randf() * TAU, "h3": rng.randf() * TAU,
		"h4": rng.randf() * TAU, "h5": rng.randf() * TAU, "h6": rng.randf() * TAU,
		"r1": rng.randf() * TAU, "r2": rng.randf() * TAU, "l1": rng.randf() * TAU,
	}
	w1 = 0.48 + 0.07 * float((index * 3) % 5) / 4.0   # 12-13 s big swing
	w2 = 0.92 + 0.11 * float((index * 7) % 4) / 3.0   # 6-7 s secondary lash
	w3 = 0.31 + 0.05 * float((index * 5) % 3) / 2.0
	wave_phase = ph["h1"]
	wave_phase2 = ph["h2"]
	_sc.resize(SIDES)
	_ss.resize(SIDES)
	for j in SIDES:
		var a := TAU * float(j) / float(SIDES)
		_sc[j] = cos(a)
		_ss[j] = sin(a)
	# --- mechanical chain visuals: rods + ball joints, both ~0.30 m ----------
	root = Node3D.new()
	root.name = "TentacleRoot%d" % index
	var rod_mesh := MK.prism(10, 0.92, 0.92, 1.0)
	var ball_mesh := SK.merge_meshes([MK.sphere(1.0, 14, 20, true),
		MK.ring(0.93, 1.02, 0.07, 20)])
	var ring_mesh := MK.ring(0.80, 1.0, 0.055, 20)

	rod_mm = MultiMesh.new()
	rod_mm.transform_format = MultiMesh.TRANSFORM_3D
	rod_mm.mesh = rod_mesh
	rod_mm.instance_count = MAX_LINKS + 4
	rod_mmi = MultiMeshInstance3D.new()
	rod_mmi.multimesh = rod_mm
	rod_mmi.material_override = BM.rod_metal()
	rod_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	rod_mmi.custom_aabb = AABB(Vector3(-28, -8, -28), Vector3(56, 28, 56))
	root.add_child(rod_mmi)

	ball_mm = MultiMesh.new()
	ball_mm.transform_format = MultiMesh.TRANSFORM_3D
	ball_mm.mesh = ball_mesh
	ball_mm.instance_count = MAX_LINKS + 2
	ball_mmi = MultiMeshInstance3D.new()
	ball_mmi.multimesh = ball_mm
	ball_mmi.material_override = BM.ball_metal()
	ball_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	ball_mmi.custom_aabb = AABB(Vector3(-28, -8, -28), Vector3(56, 28, 56))
	root.add_child(ball_mmi)

	ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.03, 0.02, 0.015)
	ring_mat.emission_enabled = true
	ring_mat.emission = BM_ORANGE_D
	ring_mat.emission_energy_multiplier = 2.2
	ring_mat.metallic = 0.1
	ring_mat.roughness = 0.4
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.disable_receive_shadows = true
	ring_mm = MultiMesh.new()
	ring_mm.transform_format = MultiMesh.TRANSFORM_3D
	ring_mm.mesh = ring_mesh
	ring_mm.instance_count = MAX_LINKS + 2
	ring_mmi = MultiMeshInstance3D.new()
	ring_mmi.multimesh = ring_mm
	ring_mmi.material_override = ring_mat
	ring_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_mmi.custom_aabb = AABB(Vector3(-28, -8, -28), Vector3(56, 28, 56))
	root.add_child(ring_mmi)

	mi = MeshInstance3D.new()
	mi.name = "Tentacle%d" % index
	mi.mesh = MK.prism(10, 0.85, 0.02, 1.0)
	mi.material_override = BM.ball_metal()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	tip_ring = MeshInstance3D.new()
	tip_ring.mesh = ring_mesh
	tip_ring.material_override = ring_mat
	tip_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tip_ring)
	# white-hot break point while the limb burns back
	cut_ember = MeshInstance3D.new()
	cut_ember.mesh = MK.sphere(0.5, 10, 14, true)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	em.albedo_color = Color(1.0, 0.72, 0.30, 0.95)
	em.disable_receive_shadows = true
	cut_ember.material_override = em
	cut_ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cut_ember.visible = false
	root.add_child(cut_ember)

	# planted-foot contact: a hot ring + a soft contact shadow on the floor
	foot_mi = MeshInstance3D.new()
	foot_mi.mesh = MK.ring(0.55, 0.78, 0.035, 32, 0.01)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.34, 0.06, 0.75)
	fm.disable_receive_shadows = true
	foot_mi.material_override = fm
	foot_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(foot_mi)
	foot_shadow = MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(1, 1)
	foot_shadow.mesh = fq
	foot_shadow.material_override = BM.contact_shadow()
	foot_shadow.rotation_degrees = Vector3(-90, 0, 0)
	foot_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(foot_shadow)


# ======================================================================= state

func set_idle() -> void:
	if role == "attack" or role == "retract":
		return
	if role == "support" and planted:
		prev_role = "support"
		_start_transition(tip, tip + Vector3.UP * 2.4, 0.95, 2.0)
		planted = false
		foot_valid = false
	role = "idle"
	L_target = idle_len
	attack_glow = 0.0
	dyn_ready = false


func set_support(world_center: Vector3, len_hint: float) -> void:
	if role == "attack" or role == "retract" or not alive:
		return
	center = world_center
	var u := base - world_center
	u.y = 0.0
	if u.length_squared() < 1e-4:
		u = Vector3(sin(sector_az), 0.0, cos(sector_az))
	u = u.normalized()
	var lat := Vector3(u.z, 0.0, -u.x)
	var aoff := 0.085 * sin(float(idx) * 1.73 + 0.4)
	var fdir := (u * cos(aoff) + lat * sin(aoff)).normalized()
	var rr := 6.2 + 1.3 * (0.5 + 0.5 * sin(float(idx) * 2.11 + 0.9))
	foot = world_center + fdir * rr
	foot.y = TIP_R + 0.090
	foot_valid = true
	planted = false
	role = "support"
	L_target = maxf(foot.distance_to(base) + 2.4, len_hint)
	L_target = clampf(L_target, 7.0, 13.0)
	_start_transition(tip, foot, 0.85, 2.6)
	plant_wait = 0.0
	dyn_ready = false


func set_retract() -> void:
	if role == "retract":
		return
	role = "retract"
	planted = false
	foot_valid = false
	retract_t = 0.0
	L_target = 1.2
	trans_t = -1.0
	attack_t = -1.0
	attack_kind = 0
	dyn_ready = false


func set_explode() -> void:
	if not alive or role == "explode":
		return
	role = "explode"
	planted = false
	foot_valid = false
	trans_t = -1.0
	attack_t = -1.0
	attack_kind = 0
	explode_t = 0.0
	explode_burst_t = 0.0
	explode_total = maxf(actual_len, spine_length())
	explode_pose.resize(N)
	for i in N:
		explode_pose[i] = pts[i] - base
	explode_seed = float(idx) * 1.913 + 0.7
	if ring_mat != null:
		ring_mat.emission = BM_HOT_D
		ring_mat.emission_energy_multiplier = 4.8
	explode_cut = explode_total
	explode_dur = clampf(explode_total * 0.120, 1.05, 2.80)
	dyn_ready = false


func start_attack(kind: int, target: Vector3, world_center: Vector3) -> void:
	if not alive or role == "attack" or role == "retract":
		return
	center = world_center
	prev_role = role
	role = "attack"
	attack_kind = kind
	attack_t = 0.0
	attack_hit = false
	attack_hit_fired = false
	attack_start_tip = tip
	attack_target = target
	attack_shoulder = base
	attack_origin = attack_start_tip
	attack_dir = (target - attack_start_tip)
	if attack_dir.length_squared() < 0.04:
		attack_dir = (target - base)
	attack_dir = attack_dir.normalized()
	attack_sweep_dir = 1.0 if (idx % 2 == 0) else -1.0
	var c_az := atan2(attack_start_tip.x - world_center.x, attack_start_tip.z - world_center.z)
	attack_az0 = c_az
	attack_over = target + Vector3(0.0, 5.4, 0.0)
	attack_arc_end = Vector3.ZERO
	planted = false
	foot_valid = false
	trans_t = -1.0
	attack_glow = 0.0
	dyn_ready = false
	attack_hit_t = 999.0
	attack_rec_t = attack_dur - 0.9
	match kind:
		1:
			# accelerate from rest to the target, pass through and decelerate
			var dist1 := attack_start_tip.distance_to(attack_target)
			var t1 := clampf(0.28 + dist1 * 0.025, 0.30, 0.60)
			var vmax := 2.0 * dist1 / t1
			var t2 := 2.0 * overshoot / maxf(vmax, 0.1)
			attack_hit_t = 0.62 + t1
			attack_rec_t = 0.62 + t1 + t2 + 0.25
			attack_dur = attack_rec_t + 0.95
			attack_len = clampf(base.distance_to(target) + overshoot + 2.2, 6.0, 30.0)
		2:
			var over2 := attack_over
			var target_low := target - Vector3(0.0, minf(0.9, target.y - 0.2), 0.0)
			var dist2 := over2.distance_to(target)
			var t1b := 0.26
			var vmax2 := 2.0 * dist2 / t1b
			var o2 := minf(0.9, maxf(target.y - 0.2, 0.15))
			var t2b := 2.0 * o2 / maxf(vmax2, 0.1)
			attack_hit_t = 1.20 + t1b
			attack_rec_t = 1.20 + t1b + t2b + 0.25
			attack_dur = attack_rec_t + 0.95
			attack_len = clampf(maxf(base.distance_to(over2),
				base.distance_to(target_low)) + 2.0, 7.0, 30.0)
		3:
			# lay the whole distal limb at attack3_height, then sweep 360°
			attack_dur = 6.45
			attack_hit_t = 999.0
			attack_rec_t = 5.70
			attack_len = clampf(attack3_len, 8.0, 30.0)
			var p0 := _low_band_path(attack_az0, attack_len)
			attack_sweep_r = Vector2(p0["T"].x - world_center.x,
				p0["T"].z - world_center.z).length()
			attack_arc_end = p0["T"]
	L_target = attack_len


func _start_transition(from_p: Vector3, to_p: Vector3, dur: float, lift: float) -> void:
	trans_t = 0.0
	trans_dur = dur
	trans_from = from_p
	trans_to = to_p
	var mid := (from_p + to_p) * 0.5
	var up := Vector3.UP * lift
	trans_ctrl = mid + up


func _trans_tip() -> Vector3:
	var u := clampf(trans_t / maxf(trans_dur, 0.001), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, u)
	var a := trans_from.lerp(trans_ctrl, e)
	var b := trans_ctrl.lerp(trans_to, e)
	return a.lerp(b, e)


# ======================================================================== tick

func update(dt: float, ctx: Dictionary) -> void:
	if not alive:
		return
	var body_xf: Transform3D = ctx["body_xf"]
	center = ctx["center"]
	var target: Vector3 = ctx["target"]
	var time: float = ctx["time"]
	var phase: int = ctx["phase"]
	var idle_scale: float = ctx.get("idle_scale", 1.0)
	idle_len = float(ctx.get("idle_len", idle_len))
	max_accel = float(ctx.get("max_accel", max_accel))
	bend_radius = float(ctx.get("bend_radius", bend_radius))
	length_rate = float(ctx.get("length_rate", length_rate))
	attack3_height = float(ctx.get("attack3_height", attack3_height))
	attack3_len = float(ctx.get("attack3_len", attack3_len))
	overshoot = float(ctx.get("overshoot", overshoot))
	wave_scale = idle_scale
	duck = ctx.get("duck", 0.0)
	var old_center := center
	base = body_xf * (dir_local * 3.0)
	base_dir_w = (body_xf.basis * dir_local).normalized()
	var u_base := base - center
	u_base.y = 0.0
	if u_base.length_squared() < 1e-5:
		u_base = Vector3(sin(sector_az), 0.0, cos(sector_az))
	u_base = u_base.normalized()
	var lat_h := Vector3(u_base.z, 0.0, -u_base.x)
	if ctx.has("boss"):
		boss_ref = ctx["boss"]

	# ---------------------------------------------------------------- explode
	# Cut limbs blow up from the tip toward the socket: the visible chain is
	# clipped at a receding cut point, with a burst of small explosions there.
	if role == "explode":
		explode_t += dt
		var e := clampf(explode_t / explode_dur, 0.0, 1.0)
		explode_cut = explode_total * (1.0 - e)
		_thrash_explode()
		if boss_ref != null:
			# the particle emitters sit on the receding break point and leave a
			# world-space trail of independent fire/smoke puffs behind them
			var cp := _point_at_len(explode_cut)
			boss_ref.call("emit_cut_fx", idx, cp, true, 1.0 - e)
		if e >= 1.0:
			alive = false
			role = "dead"
			explode_cut = 0.0
			mi.visible = false
			tip_ring.visible = false
			root.visible = false
			if boss_ref != null:
				boss_ref.call("emit_cut_fx", idx, base, false, 0.0)
		return

	# ------------------------------------------------------------- role tick
	if role == "support":
		if trans_t >= 0.0:
			trans_t += dt
			if trans_t >= trans_dur:
				trans_t = -1.0
				planted = true
		if planted:
			plant_wait += dt
	if role == "attack":
		_advance_attack(dt, ctx)
	elif role == "retract":
		retract_t += dt
		L_target = maxf(1.0, L_target - dt * 5.5)
		tip_target = base + (tip - base).normalized() * minf(1.0, L_target * 0.5)
		if retract_t > 1.0:
			alive = false
			mi.visible = false

	# --------------------------------------------------------- mode planning
	var tgt_tip := tip_target
	var tgt_L := L_target
	var tgt_approach := approach
	var tgt_bow := bow_dir
	var tgt_wave := 0.0
	if role == "idle":
		var idle := _idle_plan(center, u_base, lat_h, time, idle_scale)
		tgt_tip = idle["tip"]
		tgt_L = idle["L"]
		tgt_approach = idle["approach"]
		tgt_bow = idle["bow"]
		tgt_wave = idle["wave"]
	elif role == "support":
		if foot_valid:
			tgt_tip = foot
		tgt_L = L_target
		tgt_approach = (Vector3.DOWN * 0.85 + u_base * 0.35).normalized()
		tgt_bow = u_base
		tgt_wave = 0.12 * idle_scale
	elif role == "attack":
		var atk := _attack_plan(time, u_base)
		tgt_tip = atk["tip"]
		tgt_L = atk["L"]
		tgt_approach = atk["approach"]
		tgt_bow = atk["bow"]
		tgt_wave = atk["wave"]
	elif role == "retract":
		tgt_approach = (tip - base).normalized()
		tgt_bow = u_base
		tgt_wave = 0.0
	if trans_t >= 0.0 and role == "support":
		tgt_tip = _trans_tip()
		tgt_L = L_target
		tgt_wave = 0.05

	# ------------------------------------------------------------ smoothing
	var follow := 6.0
	var lrate := length_rate
	if role == "attack":
		follow = 26.0
		lrate = maxf(length_rate, 13.0)
	elif role == "support":
		follow = 7.0
	if role == "idle":
		follow = 3.3
	if planted and role == "support":
		tip = foot
		tip_vel = Vector3.ZERO
	elif role == "attack" and attack_t >= 0.0 and attack_t > 0.3:
		# strikes are kinematic so they land exactly; recovery is smoothed
		var rec := attack_t > attack_rec_t
		if rec:
			var k := 1.0 - exp(-9.0 * dt)
			tip = tip.lerp(tgt_tip, k)
		else:
			tip = tgt_tip
	else:
		var k2 := 1.0 - exp(-follow * dt)
		tip = tip.lerp(tgt_tip, k2)

	L_target = tgt_L
	if planted and role == "support":
		L = L_target
	else:
		L = move_toward(L, L_target, lrate * dt)
	L = clampf(L, 3.0, 30.0)

	# shape params lag
	var sh := 1.0 - exp(-5.5 * dt)
	approach = approach.lerp(tgt_approach, sh)
	if approach.length_squared() < 1e-5:
		approach = (target - base).normalized()
	approach = approach.normalized()
	bow_dir = bow_dir.lerp(tgt_bow, sh)
	bow_dir = bow_dir.normalized()
	wave_amp = lerpf(wave_amp, tgt_wave, sh)

	# -------------------------------------------------------------- the curve
	_build_curve(u_base, lat_h, time)
	pts = _limit_curvature(pts)
	# attack 3 is a scripted 360° sweep: drive the spine directly so the whole
	# distal limb stays exactly at the sweep height while it rotates
	if not (role == "attack" and attack_kind == 3):
		_apply_dynamics(dt, u_base, lat_h)
	# attacks present the end of the chain straight along the strike/plunge
	# direction: the last two links are aligned with `approach` so the thrust is
	# a point-first stab, not a sideways slap
	if role == "attack" and alive:
		var seg := actual_len / float(N - 1)
		var app := approach.normalized()
		pts[N - 1] = tip
		pts[N - 2] = tip - app * seg
		pts[N - 3] = pts[N - 2] - app * seg * 0.92
		actual_len = 0.0
		for i in range(1, N):
			actual_len += pts[i - 1].distance_to(pts[i])
		radii.resize(N)
		for i in N:
			radii[i] = _radius_at(actual_len * float(i) / float(N - 1), actual_len)
	_snap_socket()
	# ------------------------------------------------------------- joint glow
	if ring_mat != null:
		var gl := BM_ORANGE_D
		var ge := 2.0
		match role:
			"support":
				gl = BM_AMBER_D
				ge = 2.4
			"attack":
				gl = BM_HOT_D
				ge = 2.2 + attack_glow * 0.9
			"retract":
				gl = BM_HOT_D
				ge = 4.2
			_:
				gl = BM_ORANGE_D
				ge = 2.0
		ring_mat.emission = gl
		ring_mat.emission_energy_multiplier = ge

	attack_glow = maxf(0.0, attack_glow - dt * 1.8)
	if role == "attack":
		var t := attack_t
		if attack_kind == 1 and t > 0.35 and t < 0.80:
			attack_glow = maxf(attack_glow, 0.75)
		elif attack_kind == 2 and t > 1.25 and t < 1.65:
			attack_glow = maxf(attack_glow, 0.75)
		elif attack_kind == 3 and t > 0.75 and t < 2.15:
			attack_glow = maxf(attack_glow, 0.45)


func _thrash_explode() -> void:
	# The dying limb whips its remaining length around the socket while the
	# break burns back through it: a violent, decaying mechanical flail.
	var tt := explode_t
	var ramp := smoothstep(0.0, 0.10, tt)
	var yaw := 0.52 * sin(tt * 8.2 + explode_seed) * ramp
	var lat := base_dir_w.cross(Vector3.UP)
	if lat.length_squared() < 1e-4:
		lat = Vector3.RIGHT
	lat = lat.normalized()
	var up2 := lat.cross(base_dir_w).normalized()
	for i in range(1, N):
		var f := float(i) / float(N - 1)
		var amp := (1.55 + 1.15 * absf(sin(tt * 2.7 + f * 4.0 + explode_seed))) * pow(f, 1.40)
		var off := lat * sin(tt * 10.5 + f * 7.0 + explode_seed) * amp
		off += up2 * sin(tt * 13.3 + f * 5.0 + explode_seed * 1.7) * amp * 0.55
		var p: Vector3 = base + explode_pose[i] + off
		var rel := p - base
		p = base + rel.rotated(Vector3.UP, yaw * f * f)
		p.y = maxf(p.y, 0.12)
		pts[i] = p
	pts[0] = base
	pts = _project(pts)
	_snap_socket()


func _snap_socket() -> void:
	# keep the first spine samples on the socket axis after dynamics/FABRIK
	var seg := actual_len / float(N - 1)
	for i in range(1, N):
		var s0 := seg * float(i)
		if s0 > 0.88:
			break
		pts[i] = base + base_dir_w * s0


# The "low band" used by attack 3: drop out of the socket, touch the sweep
# height once, then run the entire rest of the limb horizontally. The sweep
# rotates this whole band around the body.
func _low_band_path(az: float, Luse: float) -> Dictionary:
	var h := clampf(attack3_height, 0.25, 14.0)
	var radial := Vector3(sin(az), 0.0, cos(az))
	var B := base
	var br := Vector2(B.x - center.x, B.z - center.z).length()
	var knee_r := br + 1.65
	var K := center + radial * knee_r
	K.y = h
	var m := clampf((K - B).length() * 0.55, 0.75, 2.1)
	var c1 := B + base_dir_w * m
	var c2 := K - radial * m
	var S := 36
	var poly := PackedVector3Array()
	for i in S + 1:
		var u := float(i) / float(S)
		var a: Vector3 = B.lerp(c1, u)
		var b: Vector3 = c1.lerp(c2, u)
		var c: Vector3 = c2.lerp(K, u)
		var d: Vector3 = a.lerp(b, u)
		var e: Vector3 = b.lerp(c, u)
		poly.append(d.lerp(e, u))
	var ld := 0.0
	for i in S:
		ld += poly[i].distance_to(poly[i + 1])
	var rest := maxf(Luse - ld, 0.55)
	var T := K + radial * rest
	T.y = h
	var Sr := 22
	for i in range(1, Sr + 1):
		poly.append(K.lerp(T, float(i) / float(Sr)))
	return {"poly": poly, "T": T, "K": K, "descent": ld}


func _resample_poly(poly: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(N)
	var total := 0.0
	for i in range(1, poly.size()):
		total += poly[i - 1].distance_to(poly[i])
	out[0] = poly[0]
	out[N - 1] = poly[poly.size() - 1]
	var acc := 0.0
	var si := 0
	var seg_len := poly[0].distance_to(poly[1])
	for i in range(1, N - 1):
		var target_s := total * float(i) / float(N - 1)
		while acc + seg_len < target_s and si < poly.size() - 2:
			acc += seg_len
			si += 1
			seg_len = poly[si].distance_to(poly[si + 1])
		var f := clampf((target_s - acc) / maxf(seg_len, 1e-5), 0.0, 1.0)
		out[i] = poly[si].lerp(poly[si + 1], f)
	return out


func _point_at_len(s_len: float) -> Vector3:
	var cum := PackedFloat32Array()
	cum.resize(N)
	cum[0] = 0.0
	for i in range(1, N):
		cum[i] = cum[i - 1] + pts[i - 1].distance_to(pts[i])
	return _spine_at(clampf(s_len, 0.0, cum[N - 1]), cum, cum[N - 1])["p"]


func _limit_curvature(arr: PackedVector3Array) -> PackedVector3Array:
	if bend_radius <= 0.01 or arr.size() < 4:
		return arr
	var rmin := maxf(bend_radius, 0.20)
	var out := arr.duplicate()
	for pass_i in 2:
		var tmp := out.duplicate()
		for i in range(1, N - 2):
			var a := out[i - 1]
			var b := out[i]
			var c := out[i + 1]
			var ch := c - a
			var cl := ch.length()
			if cl < 1e-4:
				continue
			var mid := (a + c) * 0.5
			var dev := b - mid
			var h := dev.length()
			if h < 1e-4:
				continue
			var R := cl * cl / (8.0 * h) + h * 0.5
			if R < rmin:
				var h2 := cl * cl / (8.0 * rmin)
				if h2 < h:
					tmp[i] = mid + dev * (h2 / h)
		out = tmp
	return out


func _sector_clamp(arr: PackedVector3Array, u: Vector3) -> PackedVector3Array:
	if role != "idle" and role != "support":
		return arr
	var lim := 0.26
	var uc := u.normalized()
	var out := arr.duplicate()
	for i in range(2, N):
		var rel := out[i] - center
		rel.y = 0.0
		var rl := rel.length()
		if rl > 0.001:
			var ang := atan2(uc.cross(rel).y, uc.dot(rel))
			if absf(ang) > lim:
				var delta := clampf(ang, -lim, lim) - ang
				var rot := rel.rotated(Vector3.UP, delta)
				out[i] = center + rot + Vector3(0, out[i].y - center.y, 0)
	var tmp := out.duplicate()
	for i in range(2, N - 2):
		tmp[i] = out[i].lerp((out[i - 1] + out[i + 1]) * 0.5, 0.10)
	return tmp


func _apply_dynamics(dt: float, u: Vector3, _lat: Vector3) -> void:
	if dyn_pts.size() != N or not dyn_ready:
		dyn_pts = pts.duplicate()
		dyn_vel.resize(N)
		for i in N:
			dyn_vel[i] = Vector3.ZERO
		dyn_ready = true
	var A := maxf(max_accel, 1.0)
	var k := 10.0
	for i in range(1, N - 1):
		var err := pts[i] - dyn_pts[i]
		var acc := err * (k * k) - dyn_vel[i] * (2.0 * k)
		var al := acc.length()
		if al > A:
			acc *= A / al
		dyn_vel[i] += acc * dt
		dyn_pts[i] += dyn_vel[i] * dt
	dyn_pts[0] = base
	dyn_pts[N - 1] = pts[N - 1]
	var rest := PackedFloat32Array()
	rest.resize(N - 1)
	if role == "support" and L_target > 2.0:
		for i in N - 1:
			rest[i] = L_target / float(N - 1)
	else:
		for i in N - 1:
			rest[i] = pts[i].distance_to(pts[i + 1])
	# FABRIK with the base and tip pinned: stable, preserves the total rest
	# length (exact for support, target-length distribution otherwise).
	var tip_ref: Vector3 = pts[N - 1]
	for outer in 2:
		dyn_pts[N - 1] = tip_ref
		for i in range(N - 2, -1, -1):
			var d := dyn_pts[i] - dyn_pts[i + 1]
			if d.length_squared() < 1e-10:
				d = Vector3.DOWN
			dyn_pts[i] = dyn_pts[i + 1] + d.normalized() * rest[i]
		dyn_pts[0] = base
		for i in N - 1:
			var d2 := dyn_pts[i + 1] - dyn_pts[i]
			if d2.length_squared() < 1e-10:
				d2 = Vector3.UP
			dyn_pts[i + 1] = dyn_pts[i] + d2.normalized() * rest[i]
	dyn_pts = _project(dyn_pts)
	dyn_pts = _sector_clamp(dyn_pts, u)
	dyn_pts[0] = base
	dyn_pts[N - 1] = pts[N - 1]
	pts = dyn_pts
	actual_len = 0.0
	for i in range(1, N):
		actual_len += pts[i - 1].distance_to(pts[i])
	radii.resize(N)
	for i in N:
		radii[i] = _radius_at(actual_len * float(i) / float(N - 1), actual_len)


func _idle_plan(c: Vector3, u: Vector3, lat: Vector3, time: float, scale: float) -> Dictionary:
	var t := time
	# The tip rides a large arc around the socket: a low outward lash, then a
	# high overhead whip. Distance from the base stays near the 6 m idle length,
	# so the limb is never taut and never coils into itself.
	# The sockets point 52° below the equator: the limbs must keep flowing down
	# and outward. Tips stay below the socket ring, with a large vertical wave.
	var swing := -0.02 + 0.26 * sin(t * w1 + ph["h1"]) + 0.11 * sin(t * w2 + ph["h2"])
	swing = clampf(swing, -0.28, 0.26)
	if duck > 0.0:
		swing = lerpf(swing, -0.12, duck * 0.40)
	swing = swing + 0.035 * sin(t * 0.7 + ph["h5"]) * (1.0 - duck)
	var reach := idle_len * 0.90 + 0.45 * sin(t * w3 + ph["h3"]) + 0.15 * sin(t * 0.47 + ph["h6"])
	reach = lerpf(reach, idle_len * 0.78, duck * 0.75) * (0.94 + 0.06 * scale)
	var lean := 0.075 * sin(t * w3 + ph["h4"]) * (1.0 - duck * 0.8)
	# The two front sockets sit just under the aperture. They perform a fast low
	# scissor: large lateral sweeps below the optic, never across the eye.
	var front := clampf((u.z - 0.72) / 0.20, 0.0, 1.0)
	var face_lean := 0.40 * front * sin(t * 0.78 + ph["h5"] + 1.3) * (1.0 if u.x >= 0.0 else -1.0)
	lean += face_lean
	if front > 0.01:
		swing = lerpf(swing, -0.10 + 0.24 * sin(t * 0.95 + ph["h2"]), front)
		reach = lerpf(reach, idle_len * 0.78, front)
	var uu: Vector3 = (u * cos(lean) + lat * sin(lean)).normalized()
	var radial: Vector3 = uu * cos(swing) + Vector3.UP * sin(swing)
	var tip_p: Vector3 = base + radial * reach + lat * (0.26 * sin(t * 0.27 + ph["h4"])) * scale
	tip_p.y = maxf(tip_p.y, 1.65)
	var ang_vel := cos(t * w1 + ph["h1"])
	var tangent: Vector3 = (uu * (-sin(swing)) + Vector3.UP * cos(swing)) * signf(ang_vel)
	if tangent.length_squared() < 0.01:
		tangent = radial
	var appr: Vector3 = (tangent * 0.85 + radial * 0.35 + lat * 0.12 * sin(t * 0.52 + ph["h2"])).normalized()
	# Excess length is spent as a lateral S, not a vertical arch: the limb
	# leaves the socket flowing down and outward.
	var bow: Vector3 = (lat * 0.88 + Vector3.UP * 0.12).normalized()
	var Ld := idle_len + 0.30 * sin(t * 0.31 + ph["h5"])
	var wav := (0.60 + 0.20 * sin(t * 0.23 + ph["h6"])) * scale
	return {"tip": tip_p, "L": Ld, "approach": appr, "bow": bow, "wave": wav}


func _advance_attack(dt: float, ctx: Dictionary) -> void:
	attack_t += dt
	if attack_t < 0.0:
		return
	if attack_t >= attack_dur:
		var was := attack_kind
		role = "idle"
		attack_kind = 0
		attack_t = -1.0
		attack_glow = 0.0
		L_target = idle_len
		planted = false
		# no transition: the attack recovery already brought the tip toward idle
		if ctx.has("boss"):
			ctx["boss"].call("_on_attack_finished", idx, was)


func _attack_plan(time: float, u: Vector3) -> Dictionary:
	var t := attack_t
	var appr := attack_dir
	var bow := (Vector3.UP * 0.7 - attack_dir * 0.2).normalized()
	var wav := 0.0
	var tip_p := attack_target
	var Ld := attack_len
	var idle := _idle_plan(center, u, Vector3(u.z, 0.0, -u.x), time, 1.0)
	match attack_kind:
		1:
			var dist1 := attack_start_tip.distance_to(attack_target)
			var t1 := clampf(0.28 + dist1 * 0.025, 0.30, 0.60)
			var vmax := 2.0 * dist1 / t1
			var t2 := 2.0 * overshoot / maxf(vmax, 0.1)
			var total := dist1 + overshoot
			if t < 0.62:
				# orientation phase: the end of the limb points at the target
				tip_p = attack_start_tip
				appr = attack_dir
				bow = (Vector3.UP * 0.9 + attack_dir * 0.35).normalized()
				wav = 0.03
			elif t < 0.62 + t1 + t2:
				var uu := t - 0.62
				var s := 0.0
				if uu <= t1:
					s = 0.5 * (2.0 * dist1 / (t1 * t1)) * uu * uu
				else:
					s = dist1 + vmax * (uu - t1) - 0.5 * (vmax / t2) * (uu - t1) * (uu - t1)
				tip_p = attack_start_tip + attack_dir * s
				appr = attack_dir
				bow = (Vector3.UP * 0.25 - attack_dir * 0.15).normalized()
				wav = 0.0
				attack_glow = 0.9
			elif t < attack_rec_t:
				tip_p = attack_start_tip + attack_dir * total
				appr = attack_dir
				bow = Vector3.UP
				wav = 0.02
			else:
				var e := smoothstep(0.0, 1.0, (t - attack_rec_t) / (attack_dur - attack_rec_t))
				var end_p := attack_start_tip + attack_dir * total
				tip_p = end_p.lerp(idle["tip"], e)
				appr = attack_dir.lerp(idle["approach"], e)
				bow = idle["bow"]
				wav = 0.14 * e
				Ld = lerpf(attack_len, idle_len, e)
		2:
			var ctrl := attack_start_tip.lerp(attack_over, 0.45) + Vector3.UP * 3.2
			var dist2 := attack_over.distance_to(attack_target)
			var t1b := 0.26
			var vmax2 := 2.0 * dist2 / t1b
			var o2 := minf(0.9, maxf(attack_target.y - 0.2, 0.15))
			var t2b := 2.0 * o2 / maxf(vmax2, 0.1)
			if t < 0.90:
				var e := smoothstep(0.0, 1.0, (t - 0.15) / 0.75) if t > 0.15 else 0.0
				var a := attack_start_tip.lerp(ctrl, e)
				var b := ctrl.lerp(attack_over, e)
				tip_p = a.lerp(b, e)
				appr = (tip_p - ctrl).normalized() if t < 0.70 else Vector3.DOWN
				bow = (Vector3.UP * 0.55 + u * 0.5).normalized()
				wav = 0.03
			elif t < 1.20:
				# hold above the target with the end pointing straight down
				tip_p = attack_over
				appr = Vector3.DOWN
				bow = Vector3.UP
				wav = 0.015
			elif t < 1.20 + t1b + t2b:
				var uu2 := t - 1.20
				var s2 := 0.0
				if uu2 <= t1b:
					s2 = 0.5 * (2.0 * dist2 / (t1b * t1b)) * uu2 * uu2
				else:
					s2 = dist2 + vmax2 * (uu2 - t1b) - 0.5 * (vmax2 / t2b) * (uu2 - t1b) * (uu2 - t1b)
				tip_p = attack_over - Vector3(0.0, s2, 0.0)
				appr = Vector3.DOWN
				bow = (u * 0.4 + Vector3.UP * 0.2).normalized()
				wav = 0.0
				attack_glow = 0.9
			elif t < attack_rec_t:
				tip_p = attack_over - Vector3(0.0, dist2 + o2, 0.0)
				appr = Vector3.DOWN
				wav = 0.0
			else:
				var e2 := smoothstep(0.0, 1.0, (t - attack_rec_t) / (attack_dur - attack_rec_t))
				var end2 := attack_over - Vector3(0.0, dist2 + o2, 0.0)
				tip_p = end2.lerp(idle["tip"], e2)
				appr = Vector3.DOWN.lerp(idle["approach"], e2)
				bow = idle["bow"]
				wav = 0.14 * e2
				Ld = lerpf(attack_len, idle_len, e2)
		3:
			var start_pt: Vector3 = _low_band_path(attack_az0, attack_len)["T"]
			var end_az := attack_az0 + attack_sweep_dir * TAU
			var end_pt: Vector3 = _low_band_path(end_az, attack_len)["T"]
			attack_arc_end = end_pt
			if t < 0.95:
				# swing the limb down while it runs out to its full reach
				var e3 := smoothstep(0.0, 1.0, t / 0.95)
				tip_p = attack_start_tip.lerp(start_pt, e3) + Vector3.UP * (0.9 * sin(PI * e3))
				var tang0 := Vector3(cos(attack_az0), 0.0, -sin(attack_az0)) * attack_sweep_dir
				appr = (tang0 * 0.8 + (start_pt - center).normalized() * 0.2).normalized()
				bow = Vector3.UP
				wav = 0.04
			elif t < 1.75:
				tip_p = start_pt
				var tang1 := Vector3(cos(attack_az0), 0.0, -sin(attack_az0)) * attack_sweep_dir
				appr = tang1
				bow = Vector3.UP
				wav = 0.01
			elif t < 5.35:
				# full 360° sweep with the whole distal limb flat at 1 m
				var e4 := smoothstep(0.0, 1.0, (t - 1.75) / 3.60)
				var az := attack_az0 + attack_sweep_dir * TAU * e4
				tip_p = _low_band_path(az, attack_len)["T"]
				var tang := Vector3(cos(az), 0.0, -sin(az)) * attack_sweep_dir
				appr = tang
				bow = (Vector3.UP * 0.85 + tang * 0.15).normalized()
				wav = 0.01
				attack_glow = 0.55
			elif t < attack_rec_t:
				tip_p = end_pt
				var tang2 := Vector3(cos(end_az), 0.0, -sin(end_az)) * attack_sweep_dir
				appr = tang2
				wav = 0.01
			else:
				var e5 := smoothstep(0.0, 1.0, (t - attack_rec_t) / (attack_dur - attack_rec_t))
				tip_p = end_pt.lerp(idle["tip"], e5)
				appr = idle["approach"]
				bow = idle["bow"]
				wav = 0.15 * e5
				Ld = lerpf(attack_len, idle_len, e5)
	# hit windows (attack 3 is a 360° sweep at height; it has no single point hit)
	if not attack_hit_fired and attack_kind != 3:
		if t >= attack_hit_t:
			attack_hit_fired = true
			attack_hit = true
	return {"tip": tip_p, "L": Ld, "approach": appr, "bow": bow, "wave": wav,
		"appr_d": appr}


# =================================================================== geometry

func _build_curve(u: Vector3, lat: Vector3, time: float) -> void:
	var T := tip
	var B := base
	var chord := T - B
	var dist := chord.length()
	if dist < 1e-3:
		chord = Vector3.UP
		dist = 1e-3
		T = B + Vector3.UP * 0.01
	var dir := (T - B) / dist
	var Luse := maxf(L, dist + 0.35)
	var base_tan := base_dir_w
	var btan := (base_tan - dir * base_tan.dot(dir))
	if btan.length_squared() < 1e-4:
		btan = u
	btan = btan.normalized()
	var m0 := (btan * 0.75 + u * 0.25).normalized() * clampf(Luse * 0.30, 0.9, 3.2)
	var appr := approach
	if appr.length_squared() < 1e-5:
		appr = dir
	appr = appr.normalized()
	var m1 := appr * clampf(Luse * 0.24, 0.7, 2.8)
	var bowp := bow_dir - dir * bow_dir.dot(dir)
	if bowp.length_squared() < 1e-5:
		bowp = Vector3.UP - dir * dir.y
		if bowp.length_squared() < 1e-5:
			bowp = lat
	bowp = bowp.normalized()
	var latp := dir.cross(bowp)
	if latp.length_squared() < 1e-5:
		latp = lat
	latp = latp.normalized()
	var amp := wave_amp
	var f1 := 2.20 if role == "idle" else 1.05
	var f2 := 3.40 if role == "idle" else 1.75
	var wp := wave_phase + time * 1.15
	var ip := wave_phase2 - time * 0.85

	# Pre-compute the wave + Hermite part once per t. Only the bow term changes
	# during the bisection, so the expensive sin/pow work is done exactly once.
	var S := 48
	var bpts := PackedVector3Array()
	var envs := PackedFloat32Array()
	bpts.resize(S + 1)
	envs.resize(S + 1)
	for i in S + 1:
		var t := float(i) / float(S)
		bpts[i] = _sample_base(t, B, m0, T, m1, amp, latp, bowp, wp, ip, f1, f2)
		envs[i] = pow(sin(PI * t), 0.92)
	var lo := 0.0
	var hi := clampf(maxf(1.2, Luse * 0.55), 2.0, 14.0)
	var len0 := _len_pre(bpts, envs, bowp, 0.0)
	var bow := 0.0
	if len0 < Luse - 0.002:
		var len_hi := _len_pre(bpts, envs, bowp, hi)
		if len_hi < Luse - 0.002:
			hi = clampf(Luse * 0.85, 3.0, 22.0)
			len_hi = _len_pre(bpts, envs, bowp, hi)
		if len_hi < Luse - 0.002:
			bow = hi
		else:
			for k in 8:
				var mid := (lo + hi) * 0.5
				if _len_pre(bpts, envs, bowp, mid) < Luse:
					lo = mid
				else:
					hi = mid
			bow = (lo + hi) * 0.5
	# final dense sampling
	var S2 := 96
	var raw := PackedVector3Array()
	raw.resize(S2 + 1)
	var base2 := PackedVector3Array()
	var env2 := PackedFloat32Array()
	base2.resize(S2 + 1)
	env2.resize(S2 + 1)
	for i in S2 + 1:
		var t := float(i) / float(S2)
		base2[i] = _sample_base(t, B, m0, T, m1, amp, latp, bowp, wp, ip, f1, f2)
		env2[i] = pow(sin(PI * t), 0.92)
		raw[i] = base2[i] + bowp * bow * env2[i]
	var total := 0.0
	for i in S2:
		total += raw[i].distance_to(raw[i + 1])
	actual_len = total
	# resample (arc-length uniform, keeps exact B and T)
	var out := PackedVector3Array()
	out.resize(N)
	out[0] = B
	out[N - 1] = T
	var acc := 0.0
	var si := 0
	var seg_start := raw[0]
	var seg_end := raw[1]
	var seg_len := seg_start.distance_to(seg_end)
	for i in range(1, N - 1):
		var target_s := total * float(i) / float(N - 1)
		while acc + seg_len < target_s and si < S2 - 1:
			acc += seg_len
			si += 1
			seg_start = raw[si]
			seg_end = raw[si + 1]
			seg_len = seg_start.distance_to(seg_end)
		var need := target_s - acc
		var f := clampf(need / maxf(seg_len, 1e-5), 0.0, 1.0)
		out[i] = seg_start.lerp(seg_end, f)
	# Socket throat: the chain must leave through the centre of its hole. The
	# first part of the spine follows the socket axis exactly, then blends into
	# the planned curve, so it can never clip the hole's upper lip.
	var seg0 := total / float(N - 1)
	for i in range(1, N):
		var s0 := seg0 * float(i)
		if s0 <= 0.88:
			out[i] = B + base_dir_w * s0
		elif s0 < 1.75:
			var k0 := smoothstep(0.0, 1.0, (s0 - 0.88) / 0.87)
			out[i] = (B + base_dir_w * s0).lerp(out[i], k0)
	# idle/support limbs stay inside their own vertical sector. This is a hard
	# geometric guarantee against adjacent limbs crossing near the base.
	if role == "idle" or role == "support":
		var lim := 0.26
		var uc := u.normalized()
		for i in range(2, N):
			var rel := out[i] - center
			rel.y = 0.0
			var rl := rel.length()
			if rl > 0.001:
				var ang := atan2(uc.cross(rel).y, uc.dot(rel))
				if absf(ang) > lim:
					var delta := clampf(ang, -lim, lim) - ang
					var rot := rel.rotated(Vector3.UP, delta)
					out[i] = center + rot + Vector3(0, out[i].y - center.y, 0)
		# one gentle smoothing pass so the clamp does not leave a hard step
		var tmp := out.duplicate()
		for i in range(2, N - 2):
			tmp[i] = out[i].lerp((out[i - 1] + out[i + 1]) * 0.5, 0.10)
		out = tmp
	# attack 3: over the first second the shape morphs into the low band; from
	# the sweep on, the whole distal limb is exactly flat at attack3_height
	if role == "attack" and attack_kind == 3 and alive:
		var e3 := smoothstep(0.30, 1.0, clampf(attack_t / 1.15, 0.0, 1.0))
		if e3 > 0.0:
			var az3 := atan2(tip.x - center.x, tip.z - center.z)
			var lp := _low_band_path(az3, maxf(L, 4.0))
			var low := _resample_poly(lp["poly"])
			for i in range(1, N - 1):
				out[i] = out[i].lerp(low[i], e3)
			T = lp["T"]
			out[N - 1] = T
			tip = T
	# project: floor + body sphere
	out = _project(out)
	out[0] = B
	out[N - 1] = T
	pts = out
	var flen := 0.0
	for i in range(1, N):
		flen += pts[i - 1].distance_to(pts[i])
	actual_len = flen
	radii.resize(N)
	for i in N:
		var s := actual_len * float(i) / float(N - 1)
		radii[i] = _radius_at(s, actual_len)


func _len_pre(bpts: PackedVector3Array, envs: PackedFloat32Array, bowp: Vector3, bow: float) -> float:
	var total := 0.0
	var prev := bpts[0] + bowp * bow * envs[0]
	var S := bpts.size() - 1
	for i in range(1, S + 1):
		var p := bpts[i] + bowp * bow * envs[i]
		total += prev.distance_to(p)
		prev = p
	return total


func _sample_base(t: float, B: Vector3, m0: Vector3, T: Vector3, m1: Vector3,
		amp: float, latp: Vector3, bowp: Vector3, wp: float, ip: float,
		f1: float, f2: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	var h00 := 2.0 * t3 - 3.0 * t2 + 1.0
	var h10 := t3 - 2.0 * t2 + t
	var h01 := -2.0 * t3 + 3.0 * t2
	var h11 := t3 - t2
	var p := B * h00 + m0 * h10 + T * h01 + m1 * h11
	var env := pow(sin(PI * t), 0.92)
	p += latp * amp * sin(TAU * f1 * t + wp) * env
	p += bowp * amp * 0.72 * sin(TAU * f2 * t + ip) * env
	return p


func _curve_len(bow: float, B: Vector3, m0: Vector3, T: Vector3, m1: Vector3,
		bowp: Vector3, amp: float, latp: Vector3, wp: float, ip: float,
		f1: float, f2: float) -> float:
	var S := 40
	var total := 0.0
	var prev := _sample(0.0, B, m0, T, m1, bowp, bow, amp, latp, wp, ip, f1, f2)
	for i in range(1, S + 1):
		var tt := float(i) / float(S)
		var p := _sample(tt, B, m0, T, m1, bowp, bow, amp, latp, wp, ip, f1, f2)
		total += prev.distance_to(p)
		prev = p
	return total


func _sample(t: float, B: Vector3, m0: Vector3, T: Vector3, m1: Vector3,
		bowp: Vector3, bow: float, amp: float, latp: Vector3,
		wp: float, ip: float, f1: float, f2: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	var h00 := 2.0 * t3 - 3.0 * t2 + 1.0
	var h10 := t3 - 2.0 * t2 + t
	var h01 := -2.0 * t3 + 3.0 * t2
	var h11 := t3 - t2
	var p := B * h00 + m0 * h10 + T * h01 + m1 * h11
	var env := pow(sin(PI * t), 0.92)
	p += bowp * bow * env
	var w := sin(TAU * f1 * t + wp) * env
	var w2 := sin(TAU * f2 * t + ip) * env
	p += latp * amp * w + bowp * amp * 0.72 * w2
	return p


func _project(arr: PackedVector3Array) -> PackedVector3Array:
	var out := arr.duplicate()
	var R := 2.035
	var cin := center
	for i in range(2, N - 1):
		var p := out[i]
		var rr := radii_at_index(i)
		var d := p - cin
		var dl := d.length()
		var minr := R + rr + 0.02
		if dl < minr and dl > 1e-5:
			out[i] = cin + d / dl * minr
	# floor (never the pinned tip - it already sits on the floor)
	for i in range(1, N - 1):
		var r2 := radii_at_index(i)
		if out[i].y < r2 + 0.075:
			out[i].y = r2 + 0.075
	# gentle smoothing of the projections
	for pass_i in 2:
		var tmp := out.duplicate()
		for i in range(2, N - 2):
			tmp[i] = out[i].lerp((out[i - 1] + out[i + 1]) * 0.5, 0.16)
		out = tmp
	# body + floor again after smoothing
	for i in range(2, N - 1):
		var rr2 := radii_at_index(i)
		var d2 := out[i] - cin
		var dl2 := d2.length()
		if dl2 < R + rr2 + 0.02 and dl2 > 1e-5:
			out[i] = cin + d2 / dl2 * (R + rr2 + 0.02)
		if out[i].y < rr2 + 0.075:
			out[i].y = rr2 + 0.075
	return out


func radii_at_index(i: int) -> float:
	var s := actual_len * float(i) / float(N - 1)
	return _radius_at(s, actual_len)


func _radius_at(s: float, total: float) -> float:
	var t := clampf(s / maxf(total, 0.001), 0.0, 1.0)
	# Collision proxy: ball-joint radius over the chain, thin claw at the tip.
	if t > 0.94:
		return 0.060
	return BALL_R


# ====================================================================== mesh

func build_mesh() -> void:
	if root == null:
		return
	root.visible = alive
	mi.visible = alive
	tip_ring.visible = alive
	var planted_now: bool = alive and role == "support" and planted and foot_valid
	foot_mi.visible = planted_now
	foot_shadow.visible = planted_now
	if planted_now:
		foot_mi.position = Vector3(foot.x, 0.075, foot.z)
		foot_mi.scale = Vector3.ONE * 0.95
		foot_shadow.position = Vector3(foot.x, 0.050, foot.z)
		foot_shadow.scale = Vector3.ONE * 1.55
	if not alive:
		rod_mm.visible_instance_count = 0
		ball_mm.visible_instance_count = 0
		ring_mm.visible_instance_count = 0
		return
	# arc-length lookup over the solver spine
	var cum := PackedFloat32Array()
	cum.resize(N)
	cum[0] = 0.0
	for i in range(1, N):
		cum[i] = cum[i - 1] + pts[i - 1].distance_to(pts[i])
	var total := maxf(cum[N - 1], 0.01)
	actual_len = total

	# Joint pattern is anchored to the TIP. As the limb extends, the extra length
	# is gained between the socket and the first visible joint: the chain
	# telescopes out of the socket, and new links appear at the root.
	# Joint pattern is anchored to the TIP. The socket pod hides the links that
	# are still inside; only links that have emerged are visible, so the limb
	# never shows a compressed/stretched long link outside the hole.
	var smax := total
	var exploding: bool = role == "explode"
	if exploding:
		smax = clampf(explode_cut, 0.0, total)
	var joints: Array = []
	var s := total - JOINT_OFFSET
	while s > 0.18 and joints.size() < MAX_LINKS:
		if s <= smax:
			var j := _spine_at(s, cum, total)
			joints.append({"s": s, "p": j["p"], "t": j["t"]})
		s -= JOINT_SPACING
	joints.reverse()

	var nb := 0
	for j in joints:
		var p: Vector3 = j["p"]
		var tan: Vector3 = j["t"]
		p.y = maxf(p.y, BALL_R + 0.045)
		j["p"] = p
		var b := SK.basis_y(tan)
		ball_mm.set_instance_transform(nb, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * BALL_R), p))
		ring_mm.set_instance_transform(nb, Transform3D(b.scaled(Vector3.ONE * BALL_R), p))
		nb += 1
	ball_mm.visible_instance_count = nb
	ring_mm.visible_instance_count = nb

	# rods between the ball surfaces (and from the socket to the first ball)
	var nr := 0
	var prev_p: Vector3 = base
	for j in joints:
		var p: Vector3 = j["p"]
		var tan: Vector3 = j["t"]
		var surf: Vector3 = p - tan * BALL_R
		surf.y = maxf(surf.y, ROD_R + 0.045)
		_put_rod(nr, prev_p, surf)
		if prev_p.distance_to(surf) > 0.035:
			nr += 1
		prev_p = p + tan * BALL_R
	var tip_p: Vector3 = pts[N - 1]
	var tip_t: Vector3 = (pts[N - 1] - pts[N - 2]).normalized()
	if exploding:
		# the cut point is the visible end of the chain while it burns back
		tip_p = _spine_at(smax, cum, total)["p"]
		var back: Vector3 = _spine_at(maxf(smax - 0.12, 0.0), cum, total)["p"]
		if back.distance_to(tip_p) > 1e-4:
			tip_t = (tip_p - back).normalized()
		mi.visible = false
		tip_ring.visible = false
		cut_ember.visible = true
		cut_ember.position = tip_p
		var pulse := 0.10 + 0.035 * sin(explode_t * 47.0) + 0.02 * sin(explode_t * 91.0)
		cut_ember.scale = Vector3.ONE * pulse
	var tip_base: Vector3 = tip_p - tip_t * 0.06
	tip_base.y = maxf(tip_base.y, ROD_R + 0.045)
	_put_rod(nr, prev_p, tip_base)
	if prev_p.distance_to(tip_base) > 0.035:
		nr += 1
	rod_mm.visible_instance_count = nr

	# claw tip + its lit collar
	var ax := SK.basis_y(tip_t)
	if not exploding:
		cut_ember.visible = false
		mi.transform = Transform3D(ax * Basis.from_scale(Vector3(0.085, 0.26, 0.085)), tip_p - tip_t * 0.13)
		tip_ring.transform = Transform3D(ax * Basis.from_scale(Vector3(0.105, 0.105, 0.105)), tip_p - tip_t * 0.26)


func _put_rod(slot: int, a: Vector3, b: Vector3) -> void:
	if slot >= rod_mm.instance_count:
		return
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var mid := (a + b) * 0.5
	var xf := Transform3D(SK.basis_y(d / l) * Basis.from_scale(Vector3(ROD_R, l, ROD_R)), mid)
	rod_mm.set_instance_transform(slot, xf)


func _spine_at(s: float, cum: PackedFloat32Array, total: float) -> Dictionary:
	var seg := 0
	while seg < N - 2 and cum[seg + 1] < s:
		seg += 1
	var denom := maxf(cum[seg + 1] - cum[seg], 1e-5)
	var f := clampf((s - cum[seg]) / denom, 0.0, 1.0)
	var p := pts[seg].lerp(pts[seg + 1], f)
	var tan := (pts[seg + 1] - pts[seg]).normalized()
	return {"p": p, "t": tan}


func _add_tri(vs: PackedVector3Array, out: PackedInt32Array, a: int, b: int, c: int,
		guide: Vector3) -> void:
	var g := (vs[b] - vs[a]).cross(vs[c] - vs[a])
	if g.length_squared() < 1e-14:
		return
	if g.dot(guide) > 0.0:
		out.append(a)
		out.append(c)
		out.append(b)
	else:
		out.append(a)
		out.append(b)
		out.append(c)


# ==================================================================== metrics

func spine_length() -> float:
	var s := 0.0
	for i in range(1, N):
		s += pts[i - 1].distance_to(pts[i])
	return s


func min_ground_clearance() -> float:
	var m := 1e9
	for i in range(1, N):
		m = minf(m, pts[i].y - radii_at_index(i))
	return m


func max_radius() -> float:
	return _radius_at(actual_len * 0.15, actual_len)


func body_clearance(body_center: Vector3, body_r: float) -> float:
	var m := 1e9
	for i in range(2, N):
		m = minf(m, (pts[i] - body_center).length() - body_r - radii_at_index(i))
	return m


const BM_ORANGE_D := Color(1.0, 0.20, 0.028)
const BM_AMBER_D := Color(1.0, 0.42, 0.10)
const BM_HOT_D := Color(1.0, 0.075, 0.010)

func bound() -> Dictionary:
	var mn := pts[0]
	var mx := pts[0]
	for i in range(1, N):
		mn = Vector3(minf(mn.x, pts[i].x), minf(mn.y, pts[i].y), minf(mn.z, pts[i].z))
		mx = Vector3(maxf(mx.x, pts[i].x), maxf(mx.y, pts[i].y), maxf(mx.z, pts[i].z))
	var c := (mn + mx) * 0.5
	return {"c": c, "r": mn.distance_to(mx) * 0.5 + 0.20,
		"mn": mn - Vector3.ONE * 0.24, "mx": mx + Vector3.ONE * 0.24}


# ==================================================================== repair

## Called by the boss collision-relaxation pass: smooth the pushed points and
## re-pin the two ends, keeping the limb a clean cable.
func relax_clean() -> void:
	if pts.size() < N:
		return
	for pass_i in 2:
		var tmp := pts.duplicate()
		for i in range(1, N - 1):
			tmp[i] = pts[i].lerp((pts[i - 1] + pts[i + 1]) * 0.5, 0.35)
		pts = tmp
	rebuild_radii()
	pts = _project(pts)
	pts[0] = base
	if role == "support" and planted and foot_valid:
		pts[N - 1] = foot
	else:
		pts[N - 1] = tip
	rebuild_radii()


func rebuild_radii() -> void:
	if pts.size() < N:
		return
	actual_len = spine_length()
	radii.resize(N)
	for i in N:
		var s := actual_len * float(i) / float(N - 1)
		radii[i] = _radius_at(s, actual_len)
