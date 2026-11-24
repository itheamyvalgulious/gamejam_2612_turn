extends Node3D
## VESPER hair — Multi-tiered concentric arched hair cards driven by
## SpringBoneSimulator3D with root-anchored cranial stiffness, strict radial
## tier clearance (zero rest-pose clipping), and explicit tangent emission for
## Kajiya-Kay anisotropic lighting.
##
## Public API (preserved for mech_rig / qa_v2 / test_hair):
##   setup(head: Node3D, opts := {})
##   update(dt: float, rig: Node3D)
##   set_wind(world_force: Vector3)
##   get_tip_positions() -> Array[Vector3]      (world space)
##   reset_sim()

const HAIR_SHADER := preload("res://shaders/vesper_hair.gdshader")
const HS := preload("res://scripts/mech/head_shape.gd")

const SEGMENTS := 10
const POINTS := SEGMENTS + 1
const SUB_STEPS := 2
const RENDER_SEGMENTS := SEGMENTS * SUB_STEPS
const RENDER_POINTS := RENDER_SEGMENTS + 1
const CARD_COLS := 5   # gently C-curved arched hair card cross-section
const TAU := PI * 2.0

const HAIR_ROOT := Color(0.055, 0.180, 0.420)
const HAIR_MID := Color(0.160, 0.470, 0.840)
const HAIR_TIP := Color(0.580, 0.840, 0.980)

# Head-local coords (torso_scale=0.82) -> world-metre (hairstyle skeleton frame).
const HEAD_TO_METRE := 1.107
const HEAD_SCALE := 1.35

var _head: Node3D
var _skeleton: Skeleton3D
var _sim: SpringBoneSimulator3D
var _mesh_inst: MeshInstance3D
var _mesh := ArrayMesh.new()
var _material: ShaderMaterial

var _strands: Array[Dictionary] = []
var _base_bone := -1
var _colliders: Array[Node3D] = []

var _wind := Vector3.ZERO
var _tip_world: Array[Vector3] = []
var _time := 0.0
var _rig_vel := Vector3.ZERO
var _prev_rig_pos := Vector3.ZERO
var _has_prev_rig := false
var _configured := false
var _last_dt := 1.0 / 60.0
var _advance_frame := -1

var _barriers: Array[Dictionary] = []

# Uniform scale carried by the skeleton node.  The hair cards are authored in
# real metres (torso_scale * upper_scale already folded in via HEAD_TO_METRE),
# so the torso's authored scale must be stripped — but an EXTERNAL scale set on
# the rig (e.g. the campaign's Units.to_units(1.0) world-unit conversion) has
# to be preserved or the hair renders at a fraction of the body's size.
var _skel_scale := 1.0

const HR_NY := 48
const HR_NPHI := 64
var _hr_table := PackedFloat32Array()
var _hr_ready := false


# ================================================================== setup
func setup(head: Node3D, opts := {}) -> void:
	_head = head
	_wind = opts.get("wind", _wind)
	_init_head_radius_table()
	_init_barriers()
	_build_skeleton()
	_build_material()
	_build_collisions()
	_build_sim_settings()
	_align_skeleton()
	_skeleton.reset_bone_poses()
	_skeleton.force_update_all_bone_transforms()
	_configured = true
	if is_inside_tree() and _sim != null:
		_sim.reset()
	_build_skinned_mesh()
	_update_tips()


func _init_head_radius_table() -> void:
	if _hr_ready:
		return
	_hr_table.resize(HR_NY * HR_NPHI)
	var y0: float = HS.Y_BOTTOM
	var y1: float = HS.Y_TOP
	for iy in HR_NY:
		var y := lerpf(y0, y1, float(iy) / float(HR_NY - 1))
		for ip in HR_NPHI:
			var phi := TAU * float(ip) / float(HR_NPHI)
			var s: Vector3 = HS.surface_point(y, phi, 1.0, 0.0)
			_hr_table[iy * HR_NPHI + ip] = Vector2(s.x, s.z).length()
	_hr_ready = true


func _head_radius_fast(y: float, phi: float) -> float:
	if not _hr_ready:
		return 0.10
	var fy := clampf((y - HS.Y_BOTTOM) / (HS.Y_TOP - HS.Y_BOTTOM), 0.0, 1.0) * float(HR_NY - 1)
	var fp := wrapf(phi, 0.0, TAU) / TAU * float(HR_NPHI)
	var iy := mini(int(fy), HR_NY - 2)
	var ip := int(fp) % HR_NPHI
	var ip1 := (ip + 1) % HR_NPHI
	var ty := fy - float(iy)
	var tp := fp - floorf(fp)
	var r00: float = _hr_table[iy * HR_NPHI + ip]
	var r10: float = _hr_table[iy * HR_NPHI + ip1]
	var r01: float = _hr_table[(iy + 1) * HR_NPHI + ip]
	var r11: float = _hr_table[(iy + 1) * HR_NPHI + ip1]
	return lerpf(lerpf(r00, r10, tp), lerpf(r01, r11, tp), ty)


func _push_head_fast(p: Vector3, clear: float) -> Vector3:
	if p.y > HS.Y_TOP - 0.012:
		var center := Vector3(0.0, 0.025, 0.005)
		var rx := 0.092 + clear
		var ry := 0.117 + clear
		var rz := 0.112 + clear
		var q := Vector3((p.x - center.x) / rx, (p.y - center.y) / ry, (p.z - center.z) / rz)
		var l := q.length()
		if l < 1.0 and l > 1e-6:
			q /= l
			return Vector3(center.x + q.x * rx, center.y + q.y * ry, center.z + q.z * rz)
		return p
	if p.y < HS.Y_BOTTOM:
		return p
	var phi := atan2(p.x, p.z)
	var want := _head_radius_fast(p.y, phi) + clear
	var rp := Vector2(p.x, p.z).length()
	if rp < want:
		if rp < 1e-6:
			return Vector3(0.0, p.y, want)
		var k := want / rp
		return Vector3(p.x * k, p.y, p.z * k)
	return p


func _init_barriers() -> void:
	_barriers.clear()
	# 1. Head & face protection
	_barriers.append({"type": "sphere", "c": Vector3(0.0, 0.018, 0.004) * HEAD_SCALE, "r": 0.092 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(0.0, -0.028, -0.020) * HEAD_SCALE, "r": 0.080 * HEAD_SCALE})
	# 2. Neck & collar
	_barriers.append({"type": "capsule", "a": Vector3(0.0, -0.04, 0.0) * HEAD_SCALE, "b": Vector3(0.0, -0.17, 0.0) * HEAD_SCALE, "r": 0.078 * HEAD_SCALE})
	# 3. Chest & upper back
	_barriers.append({"type": "capsule", "a": Vector3(0.0, -0.18, 0.045) * HEAD_SCALE, "b": Vector3(0.0, -0.52, 0.055) * HEAD_SCALE, "r": 0.190 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(0.065, -0.23, -0.085) * HEAD_SCALE, "r": 0.088 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(-0.065, -0.23, -0.085) * HEAD_SCALE, "r": 0.088 * HEAD_SCALE})
	# 4. Compact shoulders
	_barriers.append({"type": "sphere", "c": Vector3(0.255, -0.24, 0.005) * HEAD_SCALE, "r": 0.066 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(-0.255, -0.24, 0.005) * HEAD_SCALE, "r": 0.066 * HEAD_SCALE})
	# 5. Slim dorsal spine + tightened dual wing-pod thrusters
	_barriers.append({"type": "sphere", "c": Vector3(0.0, -0.44, 0.125) * HEAD_SCALE, "r": 0.088 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(0.14, -0.45, 0.13) * HEAD_SCALE, "r": 0.065 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(-0.14, -0.45, 0.13) * HEAD_SCALE, "r": 0.065 * HEAD_SCALE})


func _build_skeleton() -> void:
	_skeleton = Skeleton3D.new()
	_skeleton.name = "HairSkeleton"
	_skeleton.top_level = true
	_skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	add_child(_skeleton)

	_base_bone = _skeleton.add_bone("hair_base")
	_skeleton.set_bone_parent(_base_bone, -1)
	_skeleton.set_bone_rest(_base_bone, Transform3D.IDENTITY)

	var layout := _make_layout()
	_strands.clear()
	if not _skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	for s in layout.size():
		var spec: Dictionary = layout[s]
		var points: PackedVector3Array = _grow_rest(spec)
		var lens: PackedFloat32Array = spec["lens_exact"]
		var bones := PackedInt32Array()
		var prev_basis := Basis.IDENTITY
		for i in SEGMENTS:
			var idx := _skeleton.add_bone("hair_%02d_%02d" % [s, i])
			_skeleton.set_bone_parent(idx, _base_bone if i == 0 else bones[i - 1])
			var from_p := points[i]
			var to_p := points[i + 1]
			var seg := lens[i]
			var dir := (to_p - from_p).normalized()
			var global_basis := _basis_from_y(dir)
			if i == 0:
				_skeleton.set_bone_rest(idx, Transform3D(global_basis, from_p))
			else:
				_skeleton.set_bone_rest(idx, Transform3D(prev_basis.inverse() * global_basis, Vector3(0, seg, 0)))
			prev_basis = global_basis
			bones.append(idx)

		var blend := float(spec["color_blend"])
		_strands.append({
			"bones": bones,
			"rest_points": points.duplicate(),
			"points": points,
			"lens": lens,
			"radial": spec["radial"],
			"normal_hint": spec["normal_hint"],
			"width": float(spec["width"]),
			"arch": float(spec["arch"]),
			"phase": float(spec["phase"]),
			"twist": float(spec["twist"]),
			"role": String(spec["role"]),
			"stiff": float(spec["stiff"]),
			"drag": float(spec["drag"]),
			"grav": float(spec["grav"]),
			"grav_radial": float(spec["grav_radial"]),
			"ao": float(spec["ao"]),
			"color_blend": blend,
		})


func _build_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = HAIR_SHADER
	_material.set_shader_parameter("is_scalp", false)
	_material.set_shader_parameter("energy", 0.025)

	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "HairCards"
	_mesh_inst.mesh = _mesh
	_mesh_inst.material_override = _material
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.extra_cull_margin = 1.0
	_skeleton.add_child(_mesh_inst)


func _build_collisions() -> void:
	_sim = SpringBoneSimulator3D.new()
	_sim.name = "SpringBone"
	_skeleton.add_child(_sim)
	_colliders.clear()

	var head_c := SpringBoneCollisionSphere3D.new()
	head_c.name = "HeadCol"
	head_c.position = Vector3(0.0, 0.015, 0.002) * HEAD_SCALE
	head_c.radius = 0.092 * HEAD_SCALE
	_sim.add_child(head_c)
	_colliders.append(head_c)

	var face_c := SpringBoneCollisionSphere3D.new()
	face_c.name = "FaceCol"
	face_c.position = Vector3(0.0, -0.025, -0.030) * HEAD_SCALE
	face_c.radius = 0.084 * HEAD_SCALE
	_sim.add_child(face_c)
	_colliders.append(face_c)

	var torso_c := SpringBoneCollisionCapsule3D.new()
	torso_c.name = "TorsoCol"
	torso_c.position = Vector3(0.0, -0.32, 0.045) * HEAD_SCALE
	torso_c.radius = 0.188 * HEAD_SCALE
	torso_c.height = 0.46 * HEAD_SCALE
	_sim.add_child(torso_c)
	_colliders.append(torso_c)

	for side in [-1.0, 1.0]:
		var sh_c := SpringBoneCollisionSphere3D.new()
		sh_c.name = "ShoulderColR" if side > 0.0 else "ShoulderColL"
		sh_c.position = Vector3(0.250 * side, -0.25, -0.01) * HEAD_SCALE
		sh_c.radius = 0.072 * HEAD_SCALE
		_sim.add_child(sh_c)
		_colliders.append(sh_c)

	var pack_c := SpringBoneCollisionSphere3D.new()
	pack_c.name = "PackCenter"
	pack_c.position = Vector3(0.0, -0.44, 0.125) * HEAD_SCALE
	pack_c.radius = 0.088 * HEAD_SCALE
	_sim.add_child(pack_c)
	_colliders.append(pack_c)

	for side in [-1.0, 1.0]:
		var pod_c := SpringBoneCollisionSphere3D.new()
		pod_c.name = "PackPodR" if side > 0.0 else "PackPodL"
		pod_c.position = Vector3(0.14 * side, -0.45, 0.13) * HEAD_SCALE
		pod_c.radius = 0.065 * HEAD_SCALE
		_sim.add_child(pod_c)
		_colliders.append(pod_c)


func _build_sim_settings() -> void:
	_sim.set_setting_count(_strands.size())
	for s in _strands.size():
		var strand: Dictionary = _strands[s]
		var bones: PackedInt32Array = strand["bones"]
		var lens: PackedFloat32Array = strand["lens"]
		var root_name := _skeleton.get_bone_name(bones[0])
		var end_name := _skeleton.get_bone_name(bones[SEGMENTS - 1])

		_sim.set_root_bone_name(s, root_name)
		_sim.set_end_bone_name(s, end_name)
		_sim.set_extend_end_bone(s, true)
		_sim.set_end_bone_length(s, lens[SEGMENTS - 1])
		_sim.set_center_from(s, SpringBoneSimulator3D.CENTER_FROM_BONE)
		_sim.set_center_bone_name(s, "hair_base")
		_sim.set_rotation_axis(s, SkeletonModifier3D.ROTATION_AXIS_ALL)
		_sim.set_individual_config(s, true)
		_sim.set_collision_count(s, _colliders.size())
		for ci in _colliders.size():
			_sim.set_collision_path(s, ci, NodePath(_colliders[ci].name))

		var base_stiff: float = strand["stiff"]
		var base_drag: float = strand["drag"]
		var base_grav: float = strand["grav"]
		var radial: Vector3 = strand["radial"]
		var gr: float = float(strand["grav_radial"])
		var grav_dir := (Vector3.DOWN + radial * gr).normalized()

		# Root-anchored cranial stiffness profile: j=0..2 grip the scalp tightly
		# so movement never exposes a bald skull, while j=3..9 flow silky and soft.
		for j in SEGMENTS:
			var stiff := base_stiff
			if j == 0:
				stiff = 0.985
			elif j == 1:
				stiff = 0.93
			elif j == 2:
				stiff = 0.78
			else:
				var tf := float(j - 2) / float(SEGMENTS - 3)
				stiff = lerpf(base_stiff * 0.85, base_stiff * 0.28, tf)
			var t := float(j) / float(SEGMENTS - 1)
			_sim.set_joint_stiffness(s, j, stiff)
			_sim.set_joint_drag(s, j, lerpf(base_drag, base_drag * 1.65, t))
			_sim.set_joint_gravity(s, j, lerpf(base_grav * 0.85, base_grav * 1.15, t))
			_sim.set_joint_gravity_direction(s, j, grav_dir)
			_sim.set_joint_radius(s, j, 0.008)
	_sim.set_external_force(Vector3.ZERO)


# ================================================================== layout
func _scalp_point_m(y_head: float, phi: float, lift_head := 0.0040) -> Array:
	var p := HS.surface_point(y_head, phi, 1.0, lift_head) * HEAD_TO_METRE
	var n := HS.surface_normal(y_head, phi)
	return [p, n]


func _make_layout() -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261122

	# ------------------------------------------------------------------
	# Concentric multi-tier back & crown hair cards with strictly separated
	# radial clearance shells so rest-pose cards NEVER interpenetrate.
	# Indices 0..51 remain long back locks for test_hair.gd sampling (0, 13, 26).
	# ------------------------------------------------------------------
	var back_tiers := [
		# Tier 0: Inner Nape Curtain (22 long draped cards, clear = 0.000)
		{"count": 22, "y0": 0.025, "y1": 0.058, "az_max": 112.0, "len": 0.54, "w": 0.056, "arch": 0.0022, "clear": 0.000, "grav_r": 0.04, "stiff": 0.54, "ao": 0.84, "out": 0.16},
		# Tier 1: Mid-Crown Long Volume covering shoulders & back (30 cards, clear = 0.004)
		{"count": 30, "y0": 0.094, "y1": 0.118, "az_max": 134.0, "len": 0.62, "w": 0.048, "arch": 0.0024, "clear": 0.004, "grav_r": 0.06, "stiff": 0.46, "ao": 0.92, "out": 0.24},
		# Tier 2: Upper Crown Long Canopy (28 cards, clear = 0.008)
		{"count": 28, "y0": 0.122, "y1": 0.132, "az_max": 122.0, "len": 0.66, "w": 0.042, "arch": 0.0022, "clear": 0.008, "grav_r": 0.08, "stiff": 0.42, "ao": 0.98, "out": 0.30},
		# Tier 3: Outer Silky Flyaway Strands (16 cards, clear = 0.011)
		{"count": 16, "y0": 0.125, "y1": 0.134, "az_max": 110.0, "len": 0.60, "w": 0.030, "arch": 0.0020, "clear": 0.011, "grav_r": 0.10, "stiff": 0.38, "ao": 1.02, "out": 0.35},
	]

	for ti in back_tiers.size():
		var tier: Dictionary = back_tiers[ti]
		var n: int = int(tier["count"])
		for i in n:
			var u := float(i) / float(maxi(n - 1, 1))
			var az_deg := lerpf(-float(tier["az_max"]), float(tier["az_max"]), u)
			var phi := deg_to_rad(az_deg + rng.randf_range(-1.2, 1.2))
			var edge_arch := 1.0 - pow(absf(u - 0.5) * 2.0, 1.6)
			var y_h := lerpf(float(tier["y0"]), float(tier["y1"]), edge_arch)
			var stagger := 0.0014 if (i % 2 == 0) else -0.0014
			var tier_clear: float = float(tier["clear"]) + stagger
			var sp := _scalp_point_m(y_h, phi, 0.0045 + tier_clear * 0.45)
			var root: Vector3 = sp[0]
			var radial := Vector3(sin(phi), 0.0, cos(phi)).normalized()
			var out_w: float = float(tier["out"])
			var start_dir := (radial * out_w + Vector3.DOWN * sqrt(maxf(1.0 - out_w * out_w, 0.12))).normalized()
			var center_falloff := 1.0 - 0.10 * absf(u - 0.5) * 2.0
			var len_wave := 0.86 + 0.14 * (0.5 + 0.5 * sin(phi * 2.3 + float(ti) * 1.9))
			var length := float(tier["len"]) * center_falloff * len_wave * rng.randf_range(0.95, 1.05)
			var c_blend := 0.40 + 0.24 * (0.5 + 0.5 * sin(phi * 3.0 + float(ti) * 1.4))
			out.append({
				"root": root,
				"dir": start_dir,
				"radial": radial,
				"normal_hint": radial,
				"length": length,
				"width": float(tier["w"]) * rng.randf_range(0.95, 1.06),
				"arch": float(tier["arch"]),
				"tier_clear": tier_clear,
				"color_blend": c_blend,
				"phase": u * 5.7 + float(ti) * 2.7 + rng.randf() * 1.3,
				"twist": (u - 0.5) * 0.12,
				"role": "back",
				"stiff": float(tier["stiff"]),
				"drag": 0.44,
				"grav": 1.02,
				"grav_radial": float(tier["grav_r"]),
				"ao": float(tier["ao"]),
			})

	# ------------------------------------------------------------------
	# 2. Long face-framing cheek & shoulder locks (12 sleek strands)
	# ------------------------------------------------------------------
	for side in [-1.0, 1.0]:
		var side_specs := [
			{"az": 112.0, "y": 0.122, "len": 0.52, "w": 0.034, "clear": 0.002, "ao": 0.92},
			{"az": 118.0, "y": 0.118, "len": 0.50, "w": 0.032, "clear": 0.004, "ao": 0.96},
			{"az": 124.0, "y": 0.124, "len": 0.47, "w": 0.030, "clear": 0.002, "ao": 0.95},
			{"az": 130.0, "y": 0.114, "len": 0.43, "w": 0.028, "clear": 0.005, "ao": 1.00},
			{"az": 136.0, "y": 0.104, "len": 0.38, "w": 0.026, "clear": 0.002, "ao": 0.94},
			{"az": 141.0, "y": 0.090, "len": 0.32, "w": 0.024, "clear": 0.004, "ao": 0.98},
		]
		for k in side_specs.size():
			var sc: Dictionary = side_specs[k]
			var phi := deg_to_rad(side * float(sc["az"]))
			var sp := _scalp_point_m(float(sc["y"]), phi, 0.0045 + float(sc["clear"]) * 0.40)
			var root: Vector3 = sp[0]
			var radial := Vector3(sin(phi), 0.0, cos(phi)).normalized()
			var start_dir := (radial * 0.16 + Vector3(side * 0.02, -0.90, -0.04)).normalized()
			var c_blend := 0.44 + 0.18 * (0.5 + 0.5 * sin(phi * 4.0 + float(k)))
			out.append({
				"root": root,
				"dir": start_dir,
				"radial": radial,
				"normal_hint": Vector3(side * 0.42, -0.10, -0.50).normalized(),
				"length": float(sc["len"]),
				"width": float(sc["w"]),
				"arch": 0.0020,
				"tier_clear": float(sc["clear"]),
				"color_blend": c_blend,
				"phase": float(k) * 2.1 + (0.4 if side < 0.0 else 3.9),
				"twist": side * 0.05,
				"role": "side",
				"stiff": 0.44,
				"drag": 0.46,
				"grav": 1.15,
				"grav_radial": 0.06,
				"ao": float(sc["ao"]),
			})

	# ------------------------------------------------------------------
	# 3. Delicate Soft Forehead Fringe (18 inner + 16 outer wispy bangs)
	# ------------------------------------------------------------------
	var fringe_tiers := [
		{"count": 18, "y": 0.123, "w": 0.040, "clear": 0.0005, "len_mul": 0.96, "ao": 0.90, "stiff": 0.68},
		{"count": 16, "y": 0.129, "w": 0.032, "clear": 0.0020, "len_mul": 1.04, "ao": 1.00, "stiff": 0.60},
	]
	for ft in fringe_tiers.size():
		var fspec: Dictionary = fringe_tiers[ft]
		var nf: int = int(fspec["count"])
		for i in nf:
			var u := float(i) / float(nf - 1)
			var front_offset_deg := lerpf(-54.0, 54.0, u)
			var phi := PI - deg_to_rad(front_offset_deg)
			var sp := _scalp_point_m(float(fspec["y"]), phi, 0.0045 + float(fspec["clear"]) * 0.35)
			var root: Vector3 = sp[0]
			var cam_zone := exp(-pow((front_offset_deg - 16.0) / 16.0, 2.0))
			var base_len := lerpf(0.162, 0.140, u) * float(fspec["len_mul"])
			var length := base_len * (1.0 - 0.26 * cam_zone)
			if absf(front_offset_deg) > 28.0:
				length += 0.028 * ((absf(front_offset_deg) - 28.0) / 14.0)
			var radial := Vector3(sin(phi), 0.0, cos(phi)).normalized()
			var sweep_x := -0.04 - 0.05 * cam_zone + 0.07 * (u - 0.5)
			var start_dir := (radial * 0.22 + Vector3(sweep_x * 0.60, -0.94, -0.02)).normalized()
			out.append({
				"root": root,
				"dir": start_dir,
				"radial": radial,
				"normal_hint": Vector3(sin(phi) * 0.58, 0.20, -0.85).normalized(),
				"length": length,
				"width": float(fspec["w"]) * (1.04 - 0.08 * cam_zone),
				"arch": 0.0020,
				"tier_clear": float(fspec["clear"]),
				"color_blend": 0.46 + 0.16 * sin(u * PI * 2.0 + float(ft)),
				"phase": u * 6.3 + float(ft) * 3.1 + 0.7,
				"twist": -0.03,
				"role": "fringe",
				"stiff": float(fspec["stiff"]),
				"drag": 0.50,
				"grav": 0.90,
				"grav_radial": 0.03,
				"ao": float(fspec["ao"]),
			})

	return out


func _grow_rest(spec: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	var p: Vector3 = spec["root"]
	var dir: Vector3 = spec["dir"]
	var radial: Vector3 = spec["radial"]
	var total: float = spec["length"]
	var role: String = spec["role"]
	var tier_clear: float = float(spec.get("tier_clear", 0.0))
	var lens := PackedFloat32Array()
	for i in SEGMENTS:
		lens.append(total / float(SEGMENTS))

	points.append(p)
	for i in SEGMENTS:
		var t := float(i + 1) / float(SEGMENTS)
		var prev_p := p
		if role == "fringe":
			dir = (dir + Vector3.DOWN * 0.24 + Vector3(0.0, 0.0, 0.03 * t)).normalized()
		elif role == "side":
			var hug := 0.40 * smoothstep(0.55, 0.0, t)
			dir = (dir + Vector3.DOWN * 0.56 - radial * hug).normalized()
		else:
			var flare := 0.03 * smoothstep(0.35, 0.95, t)
			dir = (dir + Vector3.DOWN * 0.44 + radial * flare).normalized()
		p = prev_p + dir * lens[i]
		p = _clamp_point_outside_barriers(p, role, t, tier_clear)
		var actual_dir := p - prev_p
		if actual_dir.length_squared() > 1e-10:
			dir = actual_dir.normalized()
			p = prev_p + dir * lens[i]
		points.append(p)
	spec["lens_exact"] = lens
	return points


func _clamp_point_outside_barriers(p: Vector3, role: String, t: float, tier_clear := 0.0) -> Vector3:
	if p.y < -0.70 * HEAD_SCALE or p.y > 0.22 * HEAD_SCALE or absf(p.x) > 0.38 * HEAD_SCALE or p.z < -0.22 * HEAD_SCALE or p.z > 0.34 * HEAD_SCALE:
		return p
	var p_head := p / HEAD_TO_METRE
	var max_clear := (0.0068 if role == "fringe" else 0.0085) + tier_clear * 0.72
	var head_clear := lerpf(0.0042 + tier_clear * 0.45, max_clear, smoothstep(0.0, 0.28, t))
	p_head = _push_head_fast(p_head, head_clear)
	p = p_head * HEAD_TO_METRE

	var extra := (0.003 if role == "fringe" else 0.008) + tier_clear * 0.82
	for b in _barriers:
		if b["type"] == "sphere":
			var c: Vector3 = b["c"]
			var r: float = float(b["r"]) + extra
			var d := p - c
			var dl2 := d.length_squared()
			if dl2 < r * r and dl2 > 1e-12:
				p = c + d * (r / sqrt(dl2))
		elif b["type"] == "capsule":
			var a: Vector3 = b["a"]
			var cb: Vector3 = b["b"]
			var r2: float = float(b["r"]) + extra
			var ab := cb - a
			var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
			var closest := a + ab * u
			var d2 := p - closest
			var dl2 := d2.length()
			if dl2 < r2 and dl2 > 1e-6:
				p = closest + d2 * (r2 / dl2)

	if role == "back" and t > 0.05:
		var s := 1.0 - smoothstep(-0.28 * HEAD_SCALE, -0.16 * HEAD_SCALE, p.y)
		var half_w := lerpf(0.105 * HEAD_SCALE, 0.175 * HEAD_SCALE, s)
		var apex_z := lerpf(0.025 * HEAD_SCALE, -0.02 * HEAD_SCALE, s) + tier_clear * 0.5
		var z_min := apex_z * (1.0 - clampf(absf(p.x) / maxf(half_w, 1e-6), 0.0, 1.0))
		if absf(p.x) < half_w and p.z < z_min:
			p.z = z_min
	elif role == "side" and t > 0.05:
		if p.y > -0.10 * HEAD_SCALE and p.z < 0.02 * HEAD_SCALE:
			var min_abs_x := (0.066 * HEAD_SCALE + tier_clear * 0.6) * (1.0 - clampf((-0.02 * HEAD_SCALE - p.y) / (0.10 * HEAD_SCALE), 0.0, 1.0))
			if absf(p.x) < min_abs_x:
				p.x = signf(p.x if absf(p.x) > 1e-5 else 1.0) * min_abs_x
	elif role == "fringe":
		if p.y > -0.06 * HEAD_SCALE:
			var p_h := p / HEAD_TO_METRE
			var phi := atan2(p_h.x, p_h.z)
			var surf := HS.surface_point(clampf(p_h.y, HS.Y_BOTTOM, HS.Y_TOP), phi, 1.0, 0.0050 + tier_clear * 0.6) * HEAD_TO_METRE
			if p.z > surf.z:
				p.z = surf.z
	return p


func _basis_from_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# ================================================================== runtime
func _align_skeleton() -> void:
	if _head == null or _skeleton == null:
		return
	var xf := _head.global_transform
	var b := xf.basis.orthonormalized()
	# head_world_scale = authored torso scale (HEAD_TO_METRE) * external rig
	# scale; divide the authored part back out and keep the external one.
	_skel_scale = maxf(xf.basis.get_scale().x / HEAD_TO_METRE, 1e-4)
	_skeleton.global_transform = Transform3D(b.scaled(Vector3.ONE * _skel_scale), xf.origin)


func update(dt: float, rig: Node3D) -> void:
	if not is_finite(dt) or _head == null or _skeleton == null:
		return
	dt = maxf(dt, 0.0)
	_align_skeleton()
	if dt <= 0.0:
		return
	_time += dt
	_last_dt = dt

	if rig != null and is_instance_valid(rig):
		var rp := rig.global_position
		if _has_prev_rig:
			# world units -> hair metres, so the slip force keeps its authored strength
			var v := (rp - _prev_rig_pos) / (dt * _skel_scale)
			if v.length() > 24.0:
				v = v.limit_length(24.0)
			_rig_vel = _rig_vel.lerp(v, 1.0 - exp(-12.0 * dt))
		_prev_rig_pos = rp
		_has_prev_rig = true

	# Direction vectors must be unit: the skeleton transform now carries the
	# external rig scale, and every force below is authored in metres.
	var skel_basis := _skeleton.global_transform.basis.orthonormalized()
	var head_fwd := -skel_basis.z
	var head_back := skel_basis.z

	var force := _wind
	force += skel_basis.x * (sin(_time * 0.85) * 0.05) + head_back * (0.04 + 0.03 * cos(_time * 0.6))
	# Moderate aerodynamic slip: hair streams naturally behind motion without
	# throwing all locks laterally off the scalp.
	var slip := -_rig_vel * 0.20
	var fwd_comp := slip.dot(head_fwd)
	if fwd_comp > 0.0:
		slip -= head_fwd * fwd_comp
		var side_split := sin(_time * 2.2) * 0.30 + (1.0 if slip.dot(skel_basis.x) >= 0.0 else -1.0) * 0.70
		slip += skel_basis.x * (fwd_comp * 0.32 * side_split) + Vector3.UP * (fwd_comp * 0.08)
	var lat_comp := slip.dot(skel_basis.x)
	if absf(lat_comp) > 0.95:
		slip -= skel_basis.x * (lat_comp - signf(lat_comp) * 0.95)
		slip += head_back * (absf(lat_comp) * 0.25)
	force += slip

	if rig != null and is_instance_valid(rig):
		var dash := float(rig.get("dash_time")) if rig.get("dash_time") != null else 0.0
		if dash > 0.0:
			force += head_back * 0.85
		var attacking := bool(rig.get("is_attacking")) if rig.get("is_attacking") != null else false
		if attacking:
			var at := float(rig.get("attack_time")) if rig.get("attack_time") != null else _time
			force += skel_basis.x * sin(at * 11.0) * 0.28
			force += head_back * (0.24 + 0.12 * sin(at * 7.0))
			force += Vector3.UP * 0.06
	force = force.limit_length(2.6)
	if _sim != null:
		_sim.set_external_force(skel_basis.inverse() * force)

	if is_inside_tree():
		var pf := Engine.get_process_frames()
		if pf != _advance_frame:
			_advance_frame = pf
			_skeleton.advance(dt)


func set_wind(world_force: Vector3) -> void:
	_wind = world_force


func get_tip_positions() -> Array[Vector3]:
	if _tip_world.size() == _strands.size():
		return _tip_world.duplicate()
	var out: Array[Vector3] = []
	for s in _strands.size():
		var pts: PackedVector3Array = _strands[s]["points"]
		out.append(_skeleton.global_transform * pts[POINTS - 1])
	_tip_world = out
	return _tip_world.duplicate()


func reset_sim() -> void:
	if _skeleton == null:
		return
	_align_skeleton()
	_skeleton.reset_bone_poses()
	_skeleton.force_update_all_bone_transforms()
	if is_inside_tree() and _sim != null:
		_sim.reset()
	_rig_vel = Vector3.ZERO
	_has_prev_rig = false
	_time = 0.0
	_tip_world.clear()
	_update_tips()


# ================================================================== readback & spline smoothing
func _subdivide_smooth(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(RENDER_POINTS)
	for i in SEGMENTS:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, POINTS - 1)]
		out[i * 2] = p1
		var mid := 0.5 * ((2.0 * p1) + (-p0 + p2) * 0.5 + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * 0.25 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * 0.125)
		out[i * 2 + 1] = mid
	out[RENDER_POINTS - 1] = pts[POINTS - 1]
	return out


func _relax_render_points(pts: PackedVector3Array, role: String, tier_clear: float) -> void:
	var n := pts.size()
	if n < 3:
		return
	for _pass in 2:
		var disp := PackedVector3Array()
		disp.resize(n)
		for i in n:
			var t := float(i) / float(n - 1)
			disp[i] = _clamp_point_outside_barriers(pts[i], role, t, tier_clear) - pts[i]
		for i in range(1, n - 1):
			var d: Vector3 = disp[i]
			if d.length_squared() < 1e-10:
				continue
			pts[i] += d * 0.5
			if i > 1:
				pts[i - 1] += d * 0.25
			if i < n - 2:
				pts[i + 1] += d * 0.25
	for _iter in 3:
		var moved := false
		for i in range(3, n - 3):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			var c: Vector3 = pts[i + 1]
			var d0 := (b - a).normalized()
			var d1 := (c - b).normalized()
			if rad_to_deg(d0.angle_to(d1)) > 16.0:
				pts[i] = b.lerp((a + c) * 0.5, 0.55)
				moved = true
		if not moved:
			break
	for i in n:
		pts[i] = _clamp_point_outside_barriers(pts[i], role, float(i) / float(n - 1), tier_clear)


func _on_skeleton_updated() -> void:
	if not _configured:
		return
	_update_tips()


func _update_tips() -> void:
	if _skeleton == null or _strands.is_empty():
		return
	var world_xf := _skeleton.global_transform
	var tips: Array[Vector3] = []
	tips.resize(_strands.size())
	for s in _strands.size():
		var chain: PackedInt32Array = _strands[s]["bones"]
		var last: int = chain[SEGMENTS - 1]
		var pose := _skeleton.get_bone_global_pose(last)
		tips[s] = world_xf * (pose.origin + pose.basis.y * float(_strands[s]["lens"][SEGMENTS - 1]))
	_tip_world = tips


## Build all hair cards ONCE as a GPU-skinned mesh with broad arched card
## geometry + explicit ARRAY_TANGENT along the hair growth vector.
func _build_skinned_mesh() -> void:
	var n := _strands.size()
	var r_pts := RENDER_POINTS
	var r_segs := RENDER_SEGMENTS
	var cc := CARD_COLS
	var verts_per_card := r_pts * cc
	var tris_per_card := r_segs * (cc - 1) * 2
	var total_verts := n * verts_per_card
	var total_indices := n * tris_per_card * 3

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()

	verts.resize(total_verts)
	normals.resize(total_verts)
	tangents.resize(total_verts * 4)
	colors.resize(total_verts)
	uvs.resize(total_verts)
	uv2s.resize(total_verts)
	bones.resize(total_verts * 4)
	weights.resize(total_verts * 4)
	idx.resize(total_indices)

	var vi := 0
	var ii := 0

	for s in n:
		var strand: Dictionary = _strands[s]
		var rest_pts: PackedVector3Array = strand["rest_points"]
		var role := String(strand["role"])
		var tier_clear := float(strand.get("tier_clear", 0.0))
		var pts := _subdivide_smooth(rest_pts)
		_relax_render_points(pts, role, tier_clear)
		strand["render_points"] = pts

		var chain: PackedInt32Array = strand["bones"]
		var w0: float = strand["width"]
		var arch_d: float = strand["arch"]
		var phase: float = strand["phase"]
		var twist: float = strand["twist"]
		var nhint: Vector3 = strand["normal_hint"]
		var ao: float = strand["ao"]
		var c_bias: float = strand["color_blend"]
		var base_v := vi

		var tang_vec := PackedVector3Array()
		tang_vec.resize(r_pts)
		for j in r_pts:
			var t_vec: Vector3
			if j == 0:
				t_vec = pts[1] - pts[0]
			elif j == r_pts - 1:
				t_vec = pts[r_pts - 1] - pts[r_pts - 2]
			else:
				t_vec = pts[j + 1] - pts[j - 1]
			if t_vec.length_squared() < 1e-10:
				t_vec = Vector3.DOWN
			tang_vec[j] = t_vec.normalized()

		var prev_nrm := nhint - tang_vec[0] * nhint.dot(tang_vec[0])
		if prev_nrm.length_squared() < 1e-6:
			prev_nrm = tang_vec[0].cross(Vector3.RIGHT)
		prev_nrm = prev_nrm.normalized()

		for j in r_pts:
			var t := float(j) / float(r_pts - 1)
			var tang := tang_vec[j]
			var nrm := prev_nrm - tang * prev_nrm.dot(tang)
			if nrm.length_squared() < 1e-6:
				nrm = tang.cross(Vector3.RIGHT)
			nrm = nrm.normalized()
			prev_nrm = nrm
			var bnr := tang.cross(nrm).normalized()
			var tw_ang := twist * t
			var b_rot := bnr * cos(tw_ang) + nrm * sin(tw_ang)
			var n_rot := -bnr * sin(tw_ang) + nrm * cos(tw_ang)

			# Broad non-tentacle card width envelope: narrows gracefully at the
			# crown apex (0.26 -> 1.0) so card corners never poke through the
			# scalp silhouette, stays full through mid-lengths, gently softens at tip.
			var root_taper := lerpf(0.26, 1.0, smoothstep(0.0, 0.24, t))
			var width_env := root_taper * (0.92 + 0.14 * sin(clampf(t / 0.85, 0.0, 1.0) * PI)) * (1.0 - 0.22 * smoothstep(0.84, 1.0, t))
			var half_w := w0 * 0.5 * width_env
			var arch_cur := arch_d * (0.15 + 0.85 * smoothstep(0.0, 0.25, t))

			var bf := clampf(t * float(SEGMENTS), 0.0, float(SEGMENTS))
			var bi := mini(int(bf), SEGMENTS - 1)
			var f := bf - float(bi)
			if bi == SEGMENTS - 1:
				f = 0.0
			var bone_a := chain[bi]
			var bone_b := chain[mini(bi + 1, SEGMENTS - 1)]

			for k in cc:
				var uk := float(k) / float(cc - 1) # 0..1 across card width
				var xc := uk * 2.0 - 1.0           # -1..+1
				var arch := (1.0 - xc * xc) * arch_cur
				var vp := pts[j] + b_rot * (xc * half_w) + n_rot * arch
				var vn := (n_rot + b_rot * (xc * 0.45)).normalized()
				var ao_col := clampf(ao * (0.92 + 0.08 * (1.0 - xc * xc)), 0.65, 1.10)

				verts[vi] = vp
				normals[vi] = vn
				var t4 := vi * 4
				tangents[t4] = tang.x
				tangents[t4 + 1] = tang.y
				tangents[t4 + 2] = tang.z
				tangents[t4 + 3] = 1.0
				colors[vi] = Color(ao_col, ao_col, ao_col, 1.0)
				uvs[vi] = Vector2(uk, t)
				uv2s[vi] = Vector2(phase, c_bias)
				bones[t4] = bone_a
				bones[t4 + 1] = bone_b
				weights[t4] = 1.0 - f
				weights[t4 + 1] = f
				vi += 1

		for j in r_segs:
			var r0 := base_v + j * cc
			var r1 := base_v + (j + 1) * cc
			for k in cc - 1:
				var a0 := r0 + k
				var a1 := r0 + k + 1
				var b1 := r1 + k + 1
				var b0 := r1 + k
				var g := (verts[a1] - verts[a0]).cross(verts[b1] - verts[a0])
				if g.dot(normals[a0]) > 0.0:
					idx[ii] = a0; idx[ii + 1] = b1; idx[ii + 2] = a1
					idx[ii + 3] = a0; idx[ii + 4] = b0; idx[ii + 5] = b1
				else:
					idx[ii] = a0; idx[ii + 1] = a1; idx[ii + 2] = b1
					idx[ii + 3] = a0; idx[ii + 4] = b1; idx[ii + 5] = b0
				ii += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_inst.skeleton = _skeleton.get_path()
	_mesh_inst.visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _skeleton != null and _configured:
		if _sim != null:
			_sim.reset()
		_align_skeleton()
		_update_tips()
