extends RefCounted
## VESPER v2 body builder — all geometry in metres, model faces -Z.
##
## The rig (mech_rig.gd) owns motion; this file only creates the node hierarchy
## and the meshes.  P is the single source of truth for joint dimensions.

const MK = preload("res://scripts/mech/mesh_kit.gd")
const MAT = preload("res://scripts/mech/materials.gd")
const HS = preload("res://scripts/mech/head_shape.gd")

const P := {
	"hip_y": 1.235, "hip_r": 0.30, "femur": 0.60, "tibia": 0.66,
	"foot_r": 0.50, "ankle_h": 0.08, "waist_y": 0.12,
	"torso_scale": 0.82, "upper_scale": 1.35, "lower_scale": 0.78,
	"upper": 0.452, "fore": 0.422, "grip": 0.16,
	# Arm cross-section scale: refined slender profile (~26% slimmer than old 0.62 build).
	"arm_w": 0.74,
	"shoulder": Vector3(0.295, 0.38, -0.02),
	"blade_y0": 0.28, "blade_len": 1.28,
	"leg_az": [45.0, 135.0, 225.0, 315.0],
}


static func params() -> Dictionary:
	return P.duplicate(true)


static func build(rig: Node3D) -> void:
	rig.body = Node3D.new()
	rig.body.name = "Body"
	rig.body.position = Vector3(0, float(P["hip_y"]) * float(P["lower_scale"]), 0)
	rig.add_child(rig.body)

	# Lower body (pelvis + legs) scales down uniformly so the upper half can
	# read bigger/taller while the lower half shrinks.  The torso stays a
	# sibling of LowerBody under Body so the two halves resize independently.
	var lower := Node3D.new()
	lower.name = "LowerBody"
	lower.scale = Vector3.ONE * float(P["lower_scale"])
	rig.body.add_child(lower)
	rig.lower_body = lower

	_build_pelvis(rig)
	_build_torso(rig)
	for i in 4:
		_build_leg(rig, i, deg_to_rad(float(P["leg_az"][i])))
	_build_arms(rig)
	_build_weapon(rig)

	var shadow := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.4, 1.4)
	shadow.mesh = qm
	shadow.material_override = MAT.contact_shadow()
	shadow.rotation_degrees = Vector3(-90, 0, 0)
	shadow.position = Vector3(0, 0.008, 0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(shadow)
	rig.contact_shadow = shadow

	# Leave the arms closed on the hilt so a static build already reads as a
	# two-handed ready stance (mech_rig re-solves this every frame anyway).
	_pose_arms_to_grip(rig)


# ------------------------------------------------------------------ pelvis
static func _build_pelvis(rig: Node3D) -> void:
	var body: Node3D = rig.lower_body
	# 4-way symmetric sculpted quadruped chassis hub + articulated waist socket cup
	var hub_prof := [
		[-0.115, 0.088], [-0.072, 0.146], [-0.015, 0.188],
		[0.042, 0.200], [0.080, 0.182], [0.106, 0.158],
	]
	MK.add(body, MK.smooth_lathe(hub_prof, 36, "y"), MAT.armor_white(), Vector3.ZERO)
	MK.add(body, MK.smooth_lathe([[-0.132, 0.002], [-0.122, 0.048], [-0.102, 0.095], [-0.080, 0.120]], 32, "y", false, true),
		MAT.armor_blue(), Vector3.ZERO)
	MK.add(body, MK.smooth_lathe([[-0.098, 0.102], [-0.088, 0.114]], 32, "y", false, false),
		MAT.armor_silver(), Vector3.ZERO)
	MK.add(body, MK.smooth_lathe([[0.040, 0.202], [0.050, 0.202]], 36, "y", false, false),
		MAT.emissive(Color(0.14, 0.40, 0.94), 0.8), Vector3.ZERO)
	# Articulated waist-socket column rising smoothly to embrace the torso waist gimbal
	MK.add(body, MK.smooth_lathe([[0.092, 0.165], [0.132, 0.152], [0.165, 0.144]], 36, "y"),
		MAT.armor_blue(), Vector3.ZERO)
	MK.add(body, MK.smooth_lathe([[0.146, 0.154], [0.165, 0.146]], 36, "y"),
		MAT.armor_silver(), Vector3.ZERO)

	# 4 identical symmetric curved hip-arch bridges linking the chassis hub to each leg mount
	var br_core := [
		[0.0, 0.056, 0.056, 0.054, 1.08, 0.025, 0.0],
		[0.50, 0.052, 0.050, 0.050, 1.08, 0.024, 0.0],
		[1.0, 0.052, 0.052, 0.052, 1.05, 0.014, 0.0],
	]
	var br_cowl := [
		[0.0, 0.052, 0.048, 0.062, 1.15, 0.028, 0.0],
		[0.50, 0.048, 0.044, 0.058, 1.14, 0.026, 0.0],
		[1.0, 0.046, 0.042, 0.056, 1.12, 0.016, 0.0],
	]
	for i in 4:
		var az := deg_to_rad(float(P["leg_az"][i]))
		var dir := Vector3(cos(az), 0, sin(az))
		var hip_bridge := Node3D.new()
		hip_bridge.position = dir * 0.135
		hip_bridge.rotation.y = -az
		body.add_child(hip_bridge)
		MK.add(hip_bridge, MK.loft_x(0.170, br_core, 20, 3), MAT.armor_blue(), Vector3.ZERO)
		MK.add(hip_bridge, MK.shell_x(0.145, br_cowl, -PI * 0.72, PI * 0.72, 0.008, 16, 3),
			MAT.armor_white(), Vector3(0.012, 0.0, 0.0))
		MK.add(hip_bridge, MK.smooth_lathe([[0.140, 0.068], [0.165, 0.065]], 24, "x"),
			MAT.armor_silver(), Vector3(0.0, 0.014, 0.0))


# ------------------------------------------------------------------- torso
static func _build_torso(rig: Node3D) -> void:
	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0, float(P["waist_y"]), 0)
	torso.scale = Vector3.ONE * float(P["torso_scale"]) * float(P["upper_scale"])
	rig.body.add_child(torso)
	rig.torso = torso

	# 1. 参数化连续女性机甲上身曲面（从腰部 y=0.035 到领口 y=0.575）
	var shells := HS.build_feminine_torso_shell()
	MK.add(torso, shells["white"], MAT.armor_white(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "TorsoCuirassWhite")
	MK.add(torso, shells["blue"], MAT.armor_blue(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "TorsoBodysuitBlue")

	# 2. 实心腰部云台枢轴柱（深入底盘腰臼内部）+ 顺滑腰座衔接环
	MK.add(torso, MK.smooth_lathe([[-0.045, 0.074], [-0.015, 0.098], [0.012, 0.112], [0.040, 0.126]], 32, "y"),
		MAT.armor_blue(), Vector3.ZERO, Vector3.ZERO, Vector3(1.06, 1.0, 0.88))
	MK.add(torso, MK.smooth_lathe([[-0.006, 0.112], [0.008, 0.116]], 32, "y"),
		MAT.armor_silver(), Vector3.ZERO, Vector3.ZERO, Vector3(1.06, 1.0, 0.88))
	var waist_prof := [
		[0.006, 0.120], [0.022, 0.158], [0.048, 0.164], [0.068, 0.145],
	]
	MK.add(torso, MK.smooth_lathe(waist_prof, 32, "y"), MAT.armor_white(),
		Vector3.ZERO, Vector3.ZERO, Vector3(1.11, 1.0, 0.84))
	MK.add(torso, MK.smooth_lathe([[0.050, 0.168], [0.072, 0.149]], 32, "y"), MAT.armor_silver(),
		Vector3.ZERO, Vector3.ZERO, Vector3(1.11, 1.0, 0.84))

	# 3. 双肩锁骨连桥：将上臂肩球与躯干侧壁牢固连接，消除悬空缝隙
	var clv_core := [
		[0.0, 0.060, 0.054, 0.056, 1.12, 0.010, 0.0],
		[0.50, 0.046, 0.040, 0.048, 1.10, 0.014, 0.0],
		[1.0, 0.046, 0.046, 0.048, 1.06, 0.0, 0.0],
	]
	var clv_cowl := [
		[0.0, 0.052, 0.044, 0.060, 1.18, 0.022, 0.0],
		[0.55, 0.044, 0.038, 0.052, 1.16, 0.024, 0.0],
		[1.0, 0.040, 0.034, 0.046, 1.12, 0.012, 0.0],
	]
	for side in [-1.0, 1.0]:
		var clv := Node3D.new()
		clv.name = "ShoulderBridgeR" if side > 0 else "ShoulderBridgeL"
		clv.position = Vector3(0.130 * side, 0.380, -0.020)
		if side < 0.0:
			clv.rotation_degrees = Vector3(0, 180, 0)
		torso.add_child(clv)
		MK.add(clv, MK.loft_x(0.168, clv_core, 20, 3), MAT.armor_blue(), Vector3.ZERO)
		MK.add(clv, MK.shell_x(0.145, clv_cowl, -PI * 0.65, PI * 0.65, 0.008, 16, 3),
			MAT.armor_white(), Vector3(0.006, 0.0, 0.0))
		MK.add(clv, MK.smooth_lathe([[0.032, 0.056], [0.048, 0.052]], 22, "x"),
			MAT.armor_silver(), Vector3(0.0, 0.012, 0.0))
		MK.add(clv, MK.smooth_lathe([[0.110, 0.050], [0.128, 0.054]], 22, "x"),
			MAT.armor_silver(), Vector3(0.0, 0.004, 0.0))

	# 腹部正面流线型曲线护板与深钴蓝导光缝
	var ab_st := [
		[0.0, 0.012, 0.010, 0.028, 1.15, 0.0, 0.0],
		[0.50, 0.016, 0.012, 0.036, 1.20, 0.0, 0.0],
		[1.0, 0.010, 0.008, 0.024, 1.15, 0.0, 0.0],
	]
	MK.add(torso, MK.shell_x(0.110, ab_st, -PI * 0.45, PI * 0.45, 0.006, 16, 2), MAT.armor_blue(),
		Vector3(0, 0.150, -0.104), Vector3(0, -90, 95))
	MK.add(torso, MK.ellipsoid(Vector3(0.006, 0.040, 0.006), 10, 16),
		MAT.emissive(Color(0.14, 0.40, 0.94), 1.2), Vector3(0, 0.205, -0.115), Vector3(5, 0, 0))

	# 胸甲下方流线光带、肋侧贴合护翼与锁骨光带
	var rib_st := [
		[0.0, 0.014, 0.012, 0.034, 1.18, 0.0, 0.0],
		[0.5, 0.020, 0.016, 0.042, 1.22, 0.0, 0.0],
		[1.0, 0.012, 0.010, 0.028, 1.18, 0.0, 0.0],
	]
	for side in [-1.0, 1.0]:
		MK.add(torso, MK.ellipsoid(Vector3(0.034, 0.004, 0.0055), 8, 14), MAT.emissive(Color(0.14, 0.40, 0.94), 1.2),
			Vector3(0.056 * side, 0.304, -0.125), Vector3(14, -18 * side, -16 * side))
		var rib_rot := Vector3(6, 0, -90) if side > 0 else Vector3(6, 180, -90)
		MK.add(torso, MK.shell_x(0.125, rib_st, -PI * 0.46, PI * 0.46, 0.006, 16, 2), MAT.armor_white(),
			Vector3(0.122 * side, 0.252, -0.016), rib_rot)
		MK.add(torso, MK.shell_x(0.090, rib_st, -PI * 0.40, PI * 0.40, 0.005, 14, 2), MAT.armor_blue(),
			Vector3(0.128 * side, 0.232, -0.024), rib_rot)
		MK.add(torso, MK.ellipsoid(Vector3(0.038, 0.0055, 0.0065), 8, 14), MAT.emissive(Color(0.16, 0.44, 0.96), 1.3),
			Vector3(0.084 * side, 0.506, -0.086), Vector3(18, -12 * side, -8 * side))
		MK.add(torso, MK.pauldron_shell(0.042, 0.022, 0.048, 0.007, 0.008, 10, 16), MAT.armor_silver(),
			Vector3(0.158 * side, 0.422, -0.034), Vector3(0, -14 * side, -78 * side))

	# 胸口中央核心徽记（流线水滴银饰 + 深钴蓝核心）
	MK.add(torso, MK.ellipsoid(Vector3(0.022, 0.036, 0.016), 12, 20), MAT.armor_silver(),
		Vector3(0, 0.425, -0.142), Vector3(-8, 0, 0))
	MK.add(torso, MK.ellipsoid(Vector3(0.007, 0.024, 0.008), 8, 16), MAT.emissive(Color(0.16, 0.44, 0.96), 1.4),
		Vector3(0, 0.425, -0.154), Vector3(-8, 0, 0))

	# 领口装甲环与纤细机甲脖颈（统一深钴蓝 + 银白回转曲面）
	MK.add(torso, MK.ellipsoid(Vector3(0.135, 0.026, 0.118), 14, 40, 0.0, PI * 0.62),
		MAT.armor_blue(), Vector3(0, 0.555, -0.004))
	MK.add(torso, MK.ellipsoid(Vector3(0.112, 0.018, 0.100), 12, 36, 0.0, PI * 0.55),
		MAT.armor_silver(), Vector3(0, 0.574, -0.004))
	var neck_prof := [
		[0.515, 0.056], [0.555, 0.052], [0.570, 0.072], [0.585, 0.068], [0.600, 0.058],
	]
	MK.add(torso, MK.smooth_lathe(neck_prof, 28, "y"), MAT.armor_blue(), Vector3(0, 0, -0.005))
	MK.add(torso, MK.smooth_lathe([[0.568, 0.074], [0.580, 0.070]], 28, "y"), MAT.armor_silver(), Vector3(0, 0, -0.005))

	# 背部精密流线护甲
	var back_cowl_st := [
		[0.0, 0.014, 0.010, 0.058, 1.25, 0.0, 0.0],
		[0.45, 0.026, 0.016, 0.105, 1.32, 0.0, 0.0],
		[1.0, 0.018, 0.012, 0.088, 1.25, 0.0, 0.0],
	]
	MK.add(torso, MK.shell_x(0.18, back_cowl_st, -PI * 0.52, PI * 0.52, 0.009, 18, 3), MAT.armor_blue(),
		Vector3(0, 0.34, 0.114), Vector3(0, 90, 96))
	var back_crest_st := [
		[0.0, 0.012, 0.008, 0.036, 1.22, 0.0, 0.0],
		[0.60, 0.018, 0.012, 0.062, 1.28, 0.0, 0.0],
		[1.0, 0.010, 0.008, 0.042, 1.20, 0.0, 0.0],
	]
	MK.add(torso, MK.shell_x(0.13, back_crest_st, -PI * 0.46, PI * 0.46, 0.007, 14, 2), MAT.armor_white(),
		Vector3(0, 0.40, 0.126), Vector3(0, 90, 98))
	_build_backpack(rig, torso)
	_build_head(rig, torso)


## Engine plume cone with its BASE BAKED onto the mesh origin and its tip on +Y.
static func _plume_mesh(radius: float, height: float) -> ArrayMesh:
	var src := MK.prism(12, radius, 0.0, height)
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = verts[i] + Vector3(0.0, height * 0.5, 0.0)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func _build_backpack(rig: Node3D, torso: Node3D) -> void:
	var pack := Node3D.new()
	pack.name = "VectorPack"
	pack.position = Vector3(0, 0.155, 0.112)
	torso.add_child(pack)

	# 紧贴背脊线条的纤薄流线核心脊包
	var spine_st := [
		[0.0, 0.012, 0.010, 0.022, 1.25, 0.0, 0.0],
		[0.35, 0.028, 0.022, 0.052, 1.28, 0.0, 0.0],
		[0.75, 0.032, 0.026, 0.058, 1.28, 0.0, 0.0],
		[1.0, 0.014, 0.012, 0.026, 1.20, 0.0, 0.0],
	]
	MK.add(pack, MK.shell_x(0.20, spine_st, -PI * 0.56, PI * 0.56, 0.008, 18, 3), MAT.armor_silver(),
		Vector3(0, -0.08, 0.016), Vector3(0, 90, 90))
	MK.add(pack, MK.shell_x(0.12, spine_st, -PI * 0.42, PI * 0.42, 0.006, 14, 2), MAT.armor_white(),
		Vector3(0, -0.02, 0.022), Vector3(0, 90, 92))
	MK.add(pack, MK.ellipsoid(Vector3(0.016, 0.048, 0.010), 10, 16), MAT.armor_blue(),
		Vector3(0, 0.040, 0.034))
	MK.add(pack, MK.ellipsoid(Vector3(0.0065, 0.030, 0.006), 8, 14),
		MAT.emissive(Color(0.14, 0.40, 0.94), 1.1), Vector3(0, 0.040, 0.042))

	# 紧凑贴身的对称双侧流线矢量推进器（缩短摇臂，贴合腰背）
	var nacelle_prof := [
		[-0.078, 0.002], [-0.066, 0.018], [-0.040, 0.040],
		[-0.008, 0.054], [0.026, 0.058], [0.058, 0.054],
		[0.074, 0.050],
	]
	var nozzle_inner := [
		[0.024, 0.038], [0.048, 0.045], [0.072, 0.048],
	]
	var plume_specs := [
		["flame_core", 0.024, 0.0],
		["flame", 0.038, 0.25],
		["flame_outer", 0.058, 0.70],
	]

	for side in [-1.0, 1.0]:
		var arm_st := [
			[0.0, 0.020, 0.020, 0.016, 1.20, 0.0, 0.0],
			[0.55, 0.024, 0.020, 0.018, 1.20, 0.0, 0.0],
			[1.0, 0.016, 0.015, 0.014, 1.20, 0.0, 0.0],
		]
		var arm_rot := Vector3(0, -14, -8) if side > 0.0 else Vector3(0, 194, -8)
		MK.add(pack, MK.loft_x(0.112, arm_st, 16, 2), MAT.armor_blue(),
			Vector3(0.042 * side, 0.004, 0.002), arm_rot)
		MK.add(pack, MK.smooth_lathe([[-0.010, 0.020], [0.010, 0.018]], 16, "y"),
			MAT.armor_silver(), Vector3(0.146 * side, -0.008, 0.024))

		var nozzle := Node3D.new()
		nozzle.name = "ThrusterR" if side > 0.0 else "ThrusterL"
		nozzle.position = Vector3(0.162 * side, -0.012, 0.028)
		nozzle.set_meta("side", side)
		pack.add_child(nozzle)

		# 银白流线水滴推进舱外壳 + 统一深海蓝进气环 + 深钛内喷管 + 亮银喷口唇环
		MK.add(nozzle, MK.smooth_lathe(nacelle_prof, 28, "z"), MAT.armor_silver(), Vector3.ZERO)
		MK.add(nozzle, MK.smooth_lathe([[-0.034, 0.044], [-0.018, 0.051], [0.005, 0.056]], 28, "z", false, false),
			MAT.armor_blue(), Vector3.ZERO)
		MK.add(nozzle, MK.smooth_lathe([[0.056, 0.055], [0.074, 0.051]], 28, "z", false, false),
			MAT.trim(), Vector3.ZERO)
		MK.add(nozzle, MK.smooth_lathe(nozzle_inner, 24, "z", true, false),
			MAT.armor_dark(), Vector3.ZERO)
		MK.add(nozzle, MK.prism(16, 0.039, 0.039, 0.006, 0),
			MAT.emissive(Color(0.24, 0.56, 1.0), 1.4), Vector3(0, 0, 0.028), Vector3(90, 0, 0))

		# 分层矢量蓝焰
		for spec in plume_specs:
			var flame := MeshInstance3D.new()
			flame.name = String(spec[0])
			flame.mesh = _plume_mesh(float(spec[1]), 0.58)
			flame.material_override = MAT.thruster().duplicate()
			(flame.material_override as ShaderMaterial).set_shader_parameter("boost", float(spec[2]) * 0.15)
			flame.position = Vector3(0, 0, 0.076)
			flame.rotation_degrees = Vector3(90, 0, 0)
			flame.scale = Vector3(0.1, 0.1, 0.1)
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			nozzle.add_child(flame)
		rig.thruster_nodes.append(nozzle)

		# 8片中性拉丝钛银虹膜光圈阀门
		var cover := Node3D.new()
		cover.name = "EngineIris"
		cover.position = Vector3(0, 0, 0.078)
		nozzle.add_child(cover)
		var bezel := TorusMesh.new()
		bezel.inner_radius = 0.047
		bezel.outer_radius = 0.061
		bezel.rings = 28
		bezel.ring_segments = 8
		MK.add(cover, bezel, MAT.trim(), Vector3.ZERO, Vector3(90, 0, 0), Vector3(1, 1, 0.75), "IrisBezel")
		for i in 8:
			var a := TAU * float(i) / 8.0
			var pivot := Node3D.new()
			pivot.name = "IrisBlade%d" % i
			pivot.position = Vector3(cos(a) * 0.047, sin(a) * 0.047, 0.0008 * float(i))
			pivot.rotation.z = a
			pivot.set_meta("base_z", a)
			cover.add_child(pivot)
			var plate := MeshInstance3D.new()
			plate.name = "Plate"
			plate.mesh = MK.slab(0.072, 0.058, 0.0028, 0.0008)
			plate.material_override = MAT.engine_petal()
			plate.rotation_degrees = Vector3(90, 0, 0)
			plate.position = Vector3(-0.036, 0, 0)
			plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(plate)
			rig.engine_petals.append(pivot)
		MK.add(cover, MK.smooth_lathe([[0.0, 0.013], [0.007, 0.009]], 16, "z"),
			MAT.trim(), Vector3(0, 0, 0.005), Vector3.ZERO, Vector3.ONE, "IrisHub")

	var tl := OmniLight3D.new()
	tl.name = "ThrusterLight"
	tl.light_color = Color(0.24, 0.56, 1.0)
	tl.light_energy = 0.0
	tl.omni_range = 3.0
	tl.shadow_enabled = false
	tl.position = Vector3(0, -0.03, 0.20)
	pack.add_child(tl)
	rig.thruster_light = tl


static func _build_head(rig: Node3D, torso: Node3D) -> void:
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.720, -0.006)
	head.scale = Vector3.ONE
	torso.add_child(head)
	rig.head = head

	var lens_mat: ShaderMaterial = (MAT.lens_blue() as ShaderMaterial).duplicate()
	lens_mat.set_shader_parameter("lens_radius", 0.062)
	rig.lens_material = lens_mat
	var blue_eye := MK.add(head, MK.dome(0.062, 24, 64), lens_mat,
		Vector3(0.0, -0.012, -0.026), Vector3(-90, 0, 0), Vector3.ONE, "BlueBossEye")
	blue_eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var lens_light := OmniLight3D.new()
	lens_light.name = "EyeGlow"
	lens_light.light_color = Color(0.24, 0.55, 1.0)
	lens_light.light_energy = 0.9
	lens_light.omni_range = 0.32
	lens_light.shadow_enabled = false
	lens_light.position = Vector3(0.0, 0.002, -0.095)
	head.add_child(lens_light)
	rig.lens_light = lens_light

	var cam_pod := Node3D.new()
	cam_pod.name = "HeadCamera"
	cam_pod.position = Vector3(0.0, 0.002, -0.085)
	cam_pod.set_meta("lens_diameter", 0.24)
	cam_pod.set_meta("forward_axis", "-Z")
	head.add_child(cam_pod)
	rig.head_camera = cam_pod

	var green_dot := MK.add(head, MK.dome(0.0042, 6, 16), MAT.indicator_green(),
		Vector3(-0.048, -0.044, -0.064), Vector3(-90, 0, 0), Vector3.ONE, "GreenIndicator")
	rig.head_green_dot = green_dot

	MK.add(head, HS.build_cavity_liner(0.965), MAT.cavity_black(),
		Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "CavityLiner")

	var visor_mi := MK.add(head, HS.build_front_visor(0.0034),
		MAT.visor_glass(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "FrontVisorShell")
	visor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var scalp := MK.add(head, HS.build_scalp_hair_base(), MAT.hair_cap(),
		Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "ScalpHairBase")
	scalp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var anchor := Node3D.new()
	anchor.name = "HairAnchor"
	anchor.position = Vector3(0, 0.115, 0.045)
	head.add_child(anchor)
	rig.hair_anchor = anchor

	var hl := OmniLight3D.new()
	hl.light_color = Color(0.35, 0.65, 1.0)
	hl.light_energy = 0.22
	hl.omni_range = 0.75
	hl.shadow_enabled = false
	hl.position = Vector3(0.09, 0.03, -0.11)
	head.add_child(hl)


# -------------------------------------------------------------------- legs
static func _build_leg(rig: Node3D, index: int, az: float) -> void:
	var dir := Vector3(cos(az), 0, sin(az))
	var root := Node3D.new()
	root.name = "Leg%d" % index
	root.position = dir * float(P["hip_r"])
	root.rotation.y = -az
	rig.lower_body.add_child(root)

	var mount := Node3D.new()
	mount.position = dir * (float(P["hip_r"]) - 0.008)
	mount.rotation.y = -az
	rig.lower_body.add_child(mount)
	MK.add(mount, MK.smooth_lathe([[-0.028, 0.072], [0.005, 0.074], [0.032, 0.064]], 24, "x"),
		MAT.armor_blue(), Vector3(0.004, 0.012, 0))
	MK.add(mount, MK.smooth_lathe([[0.026, 0.062], [0.042, 0.056]], 24, "x"),
		MAT.armor_silver(), Vector3(0.004, 0.012, 0))

	var yaw := Node3D.new()
	yaw.name = "HipYaw"
	root.add_child(yaw)
	var hip := Node3D.new()
	hip.name = "HipPitch"
	yaw.add_child(hip)
	MK.add(hip, MK.smooth_lathe([[-0.010, 0.066], [0.014, 0.070], [0.028, 0.058]], 24, "x"),
		MAT.armor_silver(), Vector3.ZERO)
	MK.add(hip, MK.smooth_lathe([[0.018, 0.056], [0.040, 0.050]], 22, "x"),
		MAT.armor_blue(), Vector3.ZERO)

	# femur (0.60 m) — 优雅弧形雕塑曲面股骨（统一深海蓝内骨 + 珍珠白银外甲，四足完全一致）
	var femur: float = float(P["femur"])
	var femur_core := [
		[0.0, 0.044, 0.044, 0.044, 1.05, 0.0, 0.0],
		[0.22, 0.054, 0.048, 0.052, 1.12, 0.022, 0.0],
		[0.58, 0.048, 0.042, 0.046, 1.10, 0.018, 0.0],
		[0.86, 0.038, 0.036, 0.038, 1.06, 0.006, 0.0],
		[1.0, 0.034, 0.034, 0.034, 1.02, 0.0, 0.0],
	]
	MK.add(hip, MK.loft_x(femur, femur_core, 24, 4), MAT.armor_blue(), Vector3.ZERO)
	var femur_shell := [
		[0.0, 0.040, 0.036, 0.064, 1.16, 0.004, 0.0],
		[0.22, 0.052, 0.044, 0.088, 1.24, 0.026, 0.0],
		[0.58, 0.046, 0.040, 0.078, 1.22, 0.022, 0.0],
		[0.88, 0.034, 0.030, 0.058, 1.16, 0.008, 0.0],
		[1.0, 0.028, 0.026, 0.048, 1.12, 0.002, 0.0],
	]
	MK.add(hip, MK.shell_x(femur * 0.90, femur_shell, -PI * 0.78, PI * 0.78, 0.010, 22, 4),
		MAT.armor_white(), Vector3(0.028, 0.010, 0))
	var femur_crest := [
		[0.0, 0.030, 0.028, 0.048, 1.16, 0.004, 0.0],
		[0.14, 0.040, 0.036, 0.060, 1.20, 0.016, 0.0],
		[0.22, 0.056, 0.044, 0.072, 1.24, 0.026, 0.0],
		[0.58, 0.050, 0.040, 0.064, 1.22, 0.022, 0.0],
		[0.68, 0.032, 0.030, 0.046, 1.18, 0.014, 0.0],
		[1.0, 0.020, 0.020, 0.036, 1.12, 0.002, 0.0],
	]
	MK.add(hip, MK.shell_x(femur * 0.90, femur_crest, -PI * 0.26, PI * 0.26, 0.008, 16, 4),
		MAT.armor_blue(), Vector3(0.028, 0.010, 0))

	# knee — 无论正视或侧视均为统一白圈+深海蓝关节（抑制侧向天空反光发灰）
	var knee := Node3D.new()
	knee.name = "Knee"
	knee.position = Vector3(femur, 0, 0)
	hip.add_child(knee)
	MK.add(knee, MK.smooth_lathe([[-0.056, 0.058], [0.056, 0.058]], 26, "z"), MAT.joint_blue(), Vector3.ZERO)
	for zs in [-1.0, 1.0]:
		MK.add(knee, MK.smooth_lathe([[-0.007, 0.052], [0.0, 0.057], [0.007, 0.052]], 24, "z", false, false),
			MAT.armor_white(), Vector3(0, 0, 0.054 * zs))
		MK.add(knee, MK.ellipsoid(Vector3(0.048, 0.048, 0.020), 12, 24),
			MAT.joint_blue(), Vector3(0, 0, 0.056 * zs))
	MK.add(knee, MK.pauldron_shell(0.066, 0.036, 0.068, 0.008, 0.012, 12, 22), MAT.armor_white(),
		Vector3(0.012, 0.046, 0.0), Vector3(0, 0, -18))
	MK.add(knee, MK.pauldron_shell(0.044, 0.022, 0.046, 0.006, 0.008, 10, 18), MAT.joint_blue(),
		Vector3(0.015, 0.063, 0.0), Vector3(0, 0, -18))

	# tibia (0.66 m) — 反曲纤细S型参数化曲面小腿（无灰黑内壁与尖刺，无等距银环）
	var tibia: float = float(P["tibia"])
	var tibia_core := [
		[0.0, 0.038, 0.038, 0.038, 1.04, 0.0, 0.0],
		[0.22, 0.048, 0.042, 0.044, 1.12, 0.022, 0.0],
		[0.55, 0.038, 0.034, 0.036, 1.10, 0.008, 0.0],
		[0.82, 0.028, 0.026, 0.028, 1.06, -0.005, 0.0],
		[1.0, 0.024, 0.024, 0.024, 1.02, 0.0, 0.0],
	]
	MK.add(knee, MK.loft_x(tibia, tibia_core, 22, 4), MAT.armor_blue(), Vector3.ZERO)
	var tibia_shell := [
		[0.0, 0.034, 0.030, 0.056, 1.16, 0.002, 0.0],
		[0.22, 0.044, 0.038, 0.074, 1.22, 0.024, 0.0],
		[0.58, 0.036, 0.032, 0.062, 1.20, 0.010, 0.0],
		[0.86, 0.026, 0.024, 0.046, 1.14, -0.004, 0.0],
		[1.0, 0.022, 0.020, 0.038, 1.10, 0.0, 0.0],
	]
	MK.add(knee, MK.shell_x(tibia * 0.88, tibia_shell, -PI * 0.78, PI * 0.78, 0.009, 20, 4),
		MAT.armor_white(), Vector3(0.032, 0.008, 0))
	var tibia_crest := [
		[0.0, 0.026, 0.024, 0.042, 1.16, 0.002, 0.0],
		[0.14, 0.034, 0.030, 0.052, 1.19, 0.014, 0.0],
		[0.22, 0.048, 0.038, 0.060, 1.22, 0.024, 0.0],
		[0.58, 0.040, 0.032, 0.050, 1.20, 0.010, 0.0],
		[0.68, 0.025, 0.023, 0.038, 1.16, 0.002, 0.0],
		[1.0, 0.016, 0.016, 0.028, 1.10, 0.0, 0.0],
	]
	MK.add(knee, MK.shell_x(tibia * 0.88, tibia_crest, -PI * 0.26, PI * 0.26, 0.007, 16, 4),
		MAT.armor_blue(), Vector3(0.032, 0.008, 0))

	# ankle + 银白流线脚部结构直接着地（无底盘浅蓝结构，无黑胶片）
	var ankle := Node3D.new()
	ankle.name = "Ankle"
	ankle.position = Vector3(tibia, 0, 0)
	knee.add_child(ankle)
	MK.add(ankle, MK.ellipsoid(Vector3(0.040, 0.040, 0.040), 12, 20), MAT.armor_silver(), Vector3.ZERO)
	MK.add(ankle, MK.smooth_lathe([[-0.012, 0.044], [0.008, 0.040]], 20, "y"),
		MAT.armor_blue(), Vector3(0.0, -0.010, 0))
	MK.add(ankle, MK.pauldron_shell(0.082, 0.040, 0.072, 0.009, 0.010, 12, 22), MAT.armor_white(),
		Vector3(0.032, -0.020, 0), Vector3(0, 0, -5))
	# 银色金属脚掌底盘直接稳固接地（最低点 local y = -0.077 -> world y ≈ +0.0023 m）
	var sole_prof := [
		[-0.077, 0.056], [-0.072, 0.066], [-0.058, 0.066], [-0.042, 0.054], [-0.024, 0.038],
	]
	MK.add(ankle, MK.smooth_lathe(sole_prof, 26, "y"), MAT.armor_silver(),
		Vector3(0.032, 0.0, 0), Vector3.ZERO, Vector3(1.20, 1.0, 0.94))
	var claw_dirs := [Vector3(1.0, -0.30, 0.0), Vector3(1.0, -0.30, 0.54), Vector3(1.0, -0.30, -0.54)]
	var talon_prof := [[0.0, 0.016], [0.040, 0.011], [0.078, 0.002]]
	for k in 3:
		var claw := MeshInstance3D.new()
		claw.mesh = MK.smooth_lathe(talon_prof, 14, "y")
		claw.material_override = MAT.armor_silver()
		claw.position = Vector3(0.064, -0.036, 0.038 * (k - 1))
		claw.quaternion = Quaternion(Vector3.UP, claw_dirs[k].normalized())
		ankle.add_child(claw)
	var heel := MeshInstance3D.new()
	heel.mesh = MK.smooth_lathe([[0.0, 0.014], [0.046, 0.002]], 12, "y")
	heel.material_override = MAT.armor_silver()
	heel.position = Vector3(-0.036, -0.028, 0)
	heel.rotation_degrees = Vector3(180, 0, -28)
	ankle.add_child(heel)

	rig.legs.append({
		"root": root, "yaw": yaw, "hip": hip, "knee": knee, "ankle": ankle,
		"az": az, "down": true, "phase": 0.0, "target": Vector3.ZERO,
	})

	# Static rest pose: solve the same two-bone IK the rig uses
	var f: float = float(P["femur"])
	var t: float = float(P["tibia"])
	var d := float(P["foot_r"]) - float(P["hip_r"])
	var h := float(P["ankle_h"]) - float(P["hip_y"])
	var reach := sqrt(d * d + h * h)
	var base := atan2(h, d)
	var aa := acos(clampf((f * f + reach * reach - t * t) / (2.0 * f * reach), -1.0, 1.0))
	var bb := acos(clampf((f * f + t * t - reach * reach) / (2.0 * f * t), -1.0, 1.0))
	var femur_angle := base + aa
	hip.rotation.z = femur_angle
	knee.rotation.z = -(PI - bb)
	ankle.rotation.z = -(femur_angle + knee.rotation.z)


# -------------------------------------------------------------------- arms
static func _build_arms(rig: Node3D) -> void:
	for side in [1.0, -1.0]:
		_build_arm(rig, side)


static func _build_arm(rig: Node3D, side: float) -> void:
	var torso: Node3D = rig.torso
	var shoulder := Node3D.new()
	shoulder.name = "ShoulderR" if side > 0 else "ShoulderL"
	shoulder.position = Vector3(float(P["shoulder"].x) * side, float(P["shoulder"].y), float(P["shoulder"].z))
	torso.add_child(shoulder)

	# 精致小巧的弧面肩甲壳 + 银色肩球（嵌套于躯干肩桥臼杯内）
	var pauldron := Node3D.new()
	pauldron.name = "PauldronR" if side > 0 else "PauldronL"
	pauldron.position = shoulder.position
	pauldron.rotation_degrees = Vector3(0, 0, -10 * side)
	torso.add_child(pauldron)
	MK.add(pauldron, MK.ellipsoid(Vector3(0.054, 0.054, 0.054), 14, 24), MAT.armor_silver(), Vector3.ZERO)
	MK.add(pauldron, MK.pauldron_shell(0.095, 0.056, 0.092, 0.009, 0.018, 14, 24), MAT.armor_white(),
		Vector3(0.018 * side, 0.028, 0.0), Vector3(0, 0, -6 * side))
	MK.add(pauldron, MK.pauldron_shell(0.064, 0.038, 0.062, 0.007, 0.012, 10, 20), MAT.armor_blue(),
		Vector3(0.024 * side, 0.046, 0.0), Vector3(0, 0, -6 * side))
	MK.add(pauldron, MK.ellipsoid(Vector3(0.042, 0.0045, 0.0065), 8, 14),
		MAT.emissive(Color(0.14, 0.40, 0.94), 1.3),
		Vector3(0.048 * side, 0.036, -0.056), Vector3(0, -10 * side, -8 * side))
	MK.add(pauldron, MK.ellipsoid(Vector3(0.009, 0.009, 0.009), 8, 12), MAT.trim(),
		Vector3(0.036 * side, 0.048, -0.064))
	rig.pauldrons.append(pauldron)

	var upper: float = float(P["upper"])
	var fore: float = float(P["fore"])
	var w: float = float(P["arm_w"])

	# 上臂：统一深海蓝内柱 + 珍珠白银弧面外壳 + 深钴蓝导流条
	var up_core := [
		[0.0, 0.045 * w, 0.045 * w, 0.044 * w, 1.02, 0.0, 0.0],
		[0.35, 0.048 * w, 0.048 * w, 0.046 * w, 1.06, 0.0, 0.0],
		[0.80, 0.038 * w, 0.038 * w, 0.036 * w, 1.04, 0.0, 0.0],
		[1.0, 0.033 * w, 0.033 * w, 0.033 * w, 1.0, 0.0, 0.0],
	]
	MK.add(shoulder, MK.loft_x(upper, up_core, 20, 3), MAT.armor_blue(), Vector3.ZERO, Vector3(0, 0, -90))
	var up_shell := [
		[0.0, 0.040 * w, 0.036 * w, 0.058 * w, 1.15, 0.0, 0.0],
		[0.24, 0.050 * w, 0.044 * w, 0.070 * w, 1.22, 0.0, 0.0],
		[0.68, 0.044 * w, 0.038 * w, 0.062 * w, 1.18, 0.0, 0.0],
		[1.0, 0.034 * w, 0.030 * w, 0.048 * w, 1.14, 0.0, 0.0],
	]
	MK.add(shoulder, MK.shell_x(upper * 0.78, up_shell, -PI * 0.72, PI * 0.72, 0.008 * w, 16, 3),
		MAT.armor_white(), Vector3(0.0, -0.045 * upper, 0), Vector3(0, 0, -90))
	var up_crest := [
		[0.0, 0.022 * w, 0.018 * w, 0.042 * w, 1.15, 0.0, 0.0],
		[0.45, 0.026 * w, 0.020 * w, 0.048 * w, 1.18, 0.0, 0.0],
		[1.0, 0.018 * w, 0.014 * w, 0.034 * w, 1.12, 0.0, 0.0],
	]
	MK.add(shoulder, MK.shell_x(upper * 0.34, up_crest, -PI * 0.42, PI * 0.42, 0.006 * w, 12, 2),
		MAT.armor_blue(), Vector3(0.042 * w, -0.084 * upper, 0), Vector3(0, 0, -90))
	MK.add(shoulder, MK.shell_x(upper * 0.66, up_crest, PI * 0.56, PI * 1.44, 0.006 * w, 12, 2),
		MAT.armor_blue(), Vector3(0.0, -0.226 * upper, 0), Vector3(0, 0, -90))
	for zs in [-1.0, 1.0]:
		MK.add(shoulder, MK.loft_x(upper * 0.34, [[0.0, 0.005 * w, 0.005 * w, 0.005 * w, 1.0, 0.0, 0.0], [1.0, 0.004 * w, 0.004 * w, 0.004 * w, 1.0, 0.0, 0.0]], 10, 2),
			MAT.emissive(Color(0.14, 0.40, 0.94), 1.3),
			Vector3(0.0, -0.36 * upper, 0.064 * w * zs), Vector3(0, 0, -90))

	# 肘关节：对称银蓝伺服鼓 + 弧面肘甲
	var elbow := Node3D.new()
	elbow.name = "Elbow"
	elbow.position = Vector3(0, -upper, 0)
	shoulder.add_child(elbow)
	MK.add(elbow, MK.smooth_lathe([[-0.050 * w, 0.056 * w], [0.050 * w, 0.056 * w]], 22, "z"),
		MAT.armor_blue(), Vector3.ZERO)
	MK.add(elbow, MK.pauldron_shell(0.054 * w, 0.034 * w, 0.060 * w, 0.007 * w, 0.010 * w, 10, 18),
		MAT.armor_blue(), Vector3(0.0, 0.010 * upper, -0.044 * w), Vector3(-86, 0, 0))
	MK.add(elbow, MK.pauldron_shell(0.040 * w, 0.024 * w, 0.044 * w, 0.006 * w, 0.008 * w, 8, 16),
		MAT.armor_white(), Vector3(0.0, 0.010 * upper, -0.062 * w), Vector3(-86, 0, 0))
	MK.add(elbow, MK.smooth_lathe([[-0.004 * w, 0.026 * w], [0.004 * w, 0.026 * w]], 18, "z"),
		MAT.emissive(Color(0.14, 0.40, 0.94), 1.2), Vector3(0, 0, 0.052 * w))
	for zs in [-1.0, 1.0]:
		MK.add(elbow, MK.smooth_lathe([[-0.010 * w, 0.038 * w], [0.0, 0.044 * w], [0.010 * w, 0.038 * w]], 18, "z"),
			MAT.armor_silver(), Vector3(0, 0, 0.048 * w * zs))

	# 前臂：深海蓝内柱 + 白银弧面壳 + 状态灯
	var plate_len: float = fore * 0.88
	var plate_off: float = 0.043 * fore
	var fore_core := [
		[0.0, 0.040 * w, 0.040 * w, 0.038 * w, 1.02, 0.0, 0.0],
		[0.30, 0.038 * w, 0.038 * w, 0.036 * w, 1.04, 0.0, 0.0],
		[0.80, 0.028 * w, 0.028 * w, 0.028 * w, 1.02, 0.0, 0.0],
		[1.0, 0.025 * w, 0.025 * w, 0.025 * w, 1.0, 0.0, 0.0],
	]
	MK.add(elbow, MK.loft_x(fore, fore_core, 20, 3), MAT.armor_blue(), Vector3.ZERO, Vector3(0, 0, -90))
	var fore_stations := [
		[0.0, 0.036 * w, 0.034 * w, 0.048 * w, 1.15, 0.0, 0.0],
		[0.18, 0.044 * w, 0.040 * w, 0.056 * w, 1.20, 0.0, 0.0],
		[0.65, 0.036 * w, 0.032 * w, 0.046 * w, 1.18, 0.0, 0.0],
		[1.0, 0.026 * w, 0.024 * w, 0.036 * w, 1.12, 0.0, 0.0],
	]
	MK.add(elbow, MK.shell_x(plate_len, fore_stations, -PI * 0.74, PI * 0.74, 0.007 * w, 16, 3),
		MAT.armor_white(), Vector3(0.0, -plate_off, 0), Vector3(0, 0, -90))
	var fore_crest := [
		[0.0, 0.020 * w, 0.016 * w, 0.034 * w, 1.14, 0.0, 0.0],
		[0.50, 0.022 * w, 0.018 * w, 0.038 * w, 1.16, 0.0, 0.0],
		[1.0, 0.015 * w, 0.012 * w, 0.026 * w, 1.10, 0.0, 0.0],
	]
	MK.add(elbow, MK.shell_x(fore * 0.44, fore_crest, -PI * 0.42, PI * 0.42, 0.005 * w, 12, 2),
		MAT.armor_blue(), Vector3(0.030 * w, -0.115 * fore, 0), Vector3(0, 0, -90))
	MK.add(elbow, MK.shell_x(fore * 0.46, fore_crest, PI * 0.56, PI * 1.44, 0.005 * w, 12, 2),
		MAT.armor_blue(), Vector3(0.0, -0.26 * fore, 0), Vector3(0, 0, -90))
	MK.add(elbow, MK.loft_x(fore * 0.48, [[0.0, 0.005 * w, 0.005 * w, 0.005 * w, 1.0, 0.0, 0.0], [1.0, 0.004 * w, 0.004 * w, 0.004 * w, 1.0, 0.0, 0.0]], 10, 2),
		MAT.emissive(Color(0.14, 0.40, 0.94), 1.0), Vector3(0.0, -0.345 * fore, 0.048 * w), Vector3(0, 0, -90))
	MK.add(elbow, MK.ellipsoid(Vector3(0.009 * w, 0.009 * w, 0.009 * w), 8, 12), MAT.trim(),
		Vector3(0.034 * w, -0.086 * fore, 0.030 * w))

	# 腕部与纤巧机甲拳（银白 + 统一深海蓝）
	var wrist := Node3D.new()
	wrist.name = "Wrist"
	wrist.position = Vector3(0, -fore, 0)
	elbow.add_child(wrist)
	MK.add(wrist, MK.smooth_lathe([[-0.038, 0.034], [0.002, 0.035], [0.028, 0.031]], 20, "y"),
		MAT.armor_silver(), Vector3(0, -0.005, 0))
	MK.add(wrist, MK.ellipsoid(Vector3(0.032, 0.024, 0.032), 12, 18), MAT.armor_white(), Vector3(0.002 * side, -0.028, 0.0))
	MK.add(wrist, MK.ellipsoid(Vector3(0.028, 0.018, 0.020), 10, 16), MAT.armor_blue(), Vector3(0.0, -0.040, -0.020))
	for i in 3:
		MK.add(wrist, MK.ellipsoid(Vector3(0.007, 0.009, 0.014), 8, 12), MAT.armor_blue(), Vector3(-0.015 + i * 0.015, -0.054, -0.018))
	MK.add(wrist, MK.smooth_lathe([[-0.004, 0.012], [0.004, 0.010]], 16, "z"),
		MAT.emissive(Color(0.14, 0.40, 0.94), 1.4), Vector3(0.0, -0.054, 0.028))
	MK.add(wrist, MK.smooth_lathe([[-0.009, 0.028], [0.009, 0.025]], 20, "y"), MAT.trim(), Vector3(0.0, 0.024, 0.0))

	# 左前臂状态灯：精确贴合在弧面外壳上（3 深钴蓝 + 1 绿）
	if side < 0:
		for i in 4:
			var col := Color(0.14, 0.40, 0.94) if i < 3 else Color(0.20, 1.0, 0.45)
			var d: float = (0.055 + 0.095 * float(i)) * fore
			var half_w: float = MK.loft_half_w(d, plate_len, fore_stations)
			var y: float = -(plate_off + d)
			MK.add(elbow, MK.smooth_lathe([[-0.002, 0.0125], [0.002, 0.0125]], 16, "z"), MAT.trim(),
				Vector3(0, y, -(half_w - 0.0004)))
			var ind := MK.add(elbow, MK.dome(0.0088, 6, 14), MAT.emissive(col, 1.6),
				Vector3(0, y, -(half_w + 0.0002)), Vector3(-90, 0, 0))
			ind.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rig.left_indicator_meshes.append(ind)

	rig.arms.append({
		"side": side, "shoulder": shoulder, "elbow": elbow, "wrist": wrist,
		"upper": upper, "fore": fore,
	})


# ------------------------------------------------------------------ weapon
static func _build_weapon(rig: Node3D) -> void:
	var torso: Node3D = rig.torso
	var root := Node3D.new()
	root.name = "Greatsword"
	# Static build-time pose must match mech_rig.BASE_POSE (low-ready grip,
	# hilt ~20 deg above horizontal) or the very first frame pops.
	root.position = Vector3(0.18, 0.15, -0.40)
	root.rotation = Vector3(-1.222, 0.0, 0.08)
	root.scale = Vector3.ONE / (float(P["torso_scale"]) * float(P["upper_scale"]))
	torso.add_child(root)
	rig.weapon_root = root
	var spin := Node3D.new()
	spin.name = "BladeRoll"
	spin.rotation.y = 2.35
	root.add_child(spin)
	rig.weapon_spin = spin

	var grip: float = float(P["grip"])
	var blade_y0: float = float(P["blade_y0"])
	var blade_len: float = float(P["blade_len"])

	# 流线雕刻剑柄与配重尾锤（统一深海蓝金属配饰）
	var hilt_prof := [
		[-0.200, 0.018], [-0.150, 0.020], [0.0, 0.020], [0.145, 0.022],
	]
	MK.add(spin, MK.smooth_lathe(hilt_prof, 20, "y"), MAT.armor_blue(), Vector3.ZERO)
	for i in 3:
		MK.add(spin, MK.smooth_lathe([[-0.005, 0.024], [0.005, 0.024]], 20, "y"),
			MAT.trim(), Vector3(0, -0.16 + i * 0.08, 0))
	for gy in [grip, -grip]:
		MK.add(spin, MK.smooth_lathe([[-0.042, 0.022], [0.042, 0.022]], 20, "y"),
			MAT.rubber(), Vector3(0, gy, 0))
		MK.add(spin, MK.smooth_lathe([[-0.003, 0.024], [0.003, 0.024]], 20, "y"),
			MAT.emissive(Color(0.14, 0.40, 0.94), 0.7), Vector3(0, gy - 0.040, 0))
	MK.add(spin, MK.smooth_lathe([[-0.032, 0.034], [0.010, 0.036], [0.032, 0.022]], 20, "y"),
		MAT.armor_blue(), Vector3(0, -0.195, 0))
	MK.add(spin, MK.ellipsoid(Vector3(0.022, 0.024, 0.022), 10, 16),
		MAT.emissive(Color(0.18, 0.48, 0.98), 0.8), Vector3(0, -0.225, 0))

	# 短巧流线金属横护手（移除两侧等离子短刃，总跨度精简至 0.28 m）
	MK.add(spin, MK.ellipsoid(Vector3(0.040, 0.038, 0.028), 12, 20), MAT.armor_silver(), Vector3(0, 0.184, 0))
	var guard_st := [
		[0.0, 0.013, 0.013, 0.016, 1.2, 0.012, 0.0],
		[0.25, 0.017, 0.016, 0.020, 1.2, 0.003, 0.0],
		[0.50, 0.022, 0.020, 0.024, 1.2, 0.0, 0.0],
		[0.75, 0.017, 0.016, 0.020, 1.2, 0.003, 0.0],
		[1.0, 0.013, 0.013, 0.016, 1.2, 0.012, 0.0],
	]
	MK.add(spin, MK.loft_x(0.28, guard_st, 18, 2), MAT.armor_white(), Vector3(-0.14, 0.192, 0))
	for side in [-1.0, 1.0]:
		var fin := MK.add(spin, MK.smooth_lathe([[0.0, 0.020], [0.022, 0.014]], 16, "x"),
			MAT.armor_blue(), Vector3(0.136 * side, 0.204, 0))
		if side < 0.0:
			fin.rotation_degrees = Vector3(0, 180, 0)
		MK.add(spin, MK.energy_blade(0.068, 0.024, 0.008, 0.50, 10), MAT.crossguard(),
			Vector3(0.156 * side, 0.204, 0), Vector3(0, 0, -90 * side))
		MK.add(spin, MK.smooth_lathe([[-0.006, 0.022], [0.006, 0.022]], 16, "x"),
			MAT.armor_silver(), Vector3(0.132 * side, 0.204, 0))
		MK.add(spin, MK.ellipsoid(Vector3(0.013, 0.020, 0.013), 8, 14), MAT.trim(),
			Vector3(0.048 * side, 0.214, 0), Vector3(0, 0, -32 * side))
	# 中央光剑发射口（银质流线喉环 + 内嵌深钴蓝光环）
	MK.add(spin, MK.smooth_lathe([[0.0, 0.036], [0.026, 0.031]], 24, "y"),
		MAT.armor_silver(), Vector3(0, 0.214, 0))
	MK.add(spin, MK.smooth_lathe([[0.0, 0.026], [0.012, 0.024]], 24, "y"),
		MAT.emissive(Color(0.18, 0.52, 0.98), 1.4), Vector3(0, 0.236, 0))

	# 脉冲蓝色等离子主剑刃：4层结构（刃宽减半 ~0.10 m，细长西洋剑轮廓）
	MK.add(spin, MK.energy_blade(blade_len, 0.105, 0.022, 0.78, 28), MAT.blade_core(), Vector3(0, blade_y0, 0))
	MK.add(spin, MK.energy_blade(blade_len, 0.135, 0.030, 0.78, 28), MAT.blade_glow(),
		Vector3(0, blade_y0, 0), Vector3.ZERO, Vector3(1.06, 1.0, 1.10), "BladeGlow1")
	var aura_mat: ShaderMaterial = (MAT.blade_glow() as ShaderMaterial).duplicate()
	aura_mat.set_shader_parameter("strength", 0.42)
	aura_mat.set_shader_parameter("color", Color(0.10, 0.40, 1.0))
	MK.add(spin, MK.energy_blade(blade_len * 1.01, 0.185, 0.042, 0.78, 26), aura_mat,
		Vector3(0, blade_y0, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.0), "BladeAura")
	MK.add(spin, MK.energy_blade(blade_len * 0.94, 0.024, 0.016, 0.24, 20),
		MAT.emissive(Color(0.85, 0.96, 1.0), 2.6), Vector3(0, blade_y0 + 0.006, 0))

	var base := Marker3D.new()
	base.position = Vector3(0, blade_y0 + blade_len * 0.80, 0)
	spin.add_child(base)
	rig.blade_base = base
	var tip := Marker3D.new()
	tip.position = Vector3(0, blade_y0 + blade_len * 0.96, 0)
	spin.add_child(tip)
	rig.blade_tip = tip

	var wl := OmniLight3D.new()
	wl.light_color = Color(0.30, 0.60, 1.0)
	wl.light_energy = 0.30
	wl.omni_range = 1.8
	wl.shadow_enabled = false
	wl.position = Vector3(0, 0.75, 0)
	spin.add_child(wl)
	rig.weapon_light = wl

	# torso chest light
	var cl := OmniLight3D.new()
	cl.light_color = Color(0.30, 0.58, 1.0)
	cl.light_energy = 0.35
	cl.omni_range = 1.4
	cl.shadow_enabled = false
	cl.position = Vector3(0, 0.42, -0.20)
	torso.add_child(cl)
	rig.chest_light = cl


# ------------------------------------------------------------------ helpers

## Z half-width of a MK.beam_x cross-section, `d` metres along the beam.
## Mirrors the ring layout inside MK.beam_x so a surface detail (the forearm
## indicator lamps) can be planted exactly on the outer armour skin instead of
## guessing an offset that ends up floating next to the arm.
static func _beam_half_w(d: float, length: float, w0: float, w1: float) -> float:
	var xs := [0.0, minf(0.055, length * 0.06), maxf(length - 0.055, length * 0.94), length]
	var ws := [w0 * 0.82, w0, w1, w1 * 0.82]
	var t := clampf(d, 0.0, length)
	for i in 3:
		if t <= xs[i + 1]:
			var u := clampf((t - xs[i]) / maxf(xs[i + 1] - xs[i], 1e-5), 0.0, 1.0)
			return lerpf(ws[i], ws[i + 1], u) * 0.5
	return ws[3] * 0.5


## Two-bone arm IK onto the sword grips, identical maths to the rig solver.
static func _pose_arms_to_grip(rig: Node3D) -> void:
	if rig.weapon_root == null or rig.arms.size() < 2:
		return
	var hilt_y: Vector3 = rig.weapon_root.basis.y.normalized()
	var hilt_x: Vector3 = rig.weapon_spin.basis.x.normalized()
	var grip: float = float(P["grip"])
	var targets := [
		rig.weapon_root.transform * Vector3(0, grip, 0),
		rig.weapon_root.transform * Vector3(0, -grip, 0),
	]
	for k in 2:
		_solve_arm(rig.arms[k], targets[k], hilt_y, hilt_x)


static func _solve_arm(arm: Dictionary, target: Vector3, hilt_y: Vector3, hilt_x: Vector3) -> void:
	var shoulder: Node3D = arm["shoulder"]
	var elbow: Node3D = arm["elbow"]
	var wrist: Node3D = arm["wrist"]
	var side: float = arm["side"]
	var upper: float = arm["upper"]
	var fore: float = arm["fore"]
	var S := shoulder.position
	var delta := target - S
	var dist := clampf(delta.length(), 0.24, upper + fore - 0.012)
	var dir := delta.normalized()
	var pole := Vector3(side * 0.55, -0.55, 0.45)
	var perp := pole - dir * pole.dot(dir)
	if perp.length_squared() < 0.001:
		perp = Vector3(side, 0, 0)
	perp = perp.normalized()
	var a := (upper * upper - fore * fore + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(upper * upper - a * a, 0.0))
	var elbow_pos := S + dir * a + perp * h
	var Teff := S + dir * dist
	var up_dir := (elbow_pos - S).normalized()
	var fore_dir := (Teff - elbow_pos).normalized()
	var x_axis := up_dir.cross(fore_dir)
	if x_axis.length_squared() < 0.0001:
		x_axis = perp
	x_axis = x_axis.normalized()
	var y_axis := -up_dir
	var z_axis := x_axis.cross(y_axis).normalized()
	x_axis = y_axis.cross(z_axis).normalized()
	shoulder.basis = Basis(x_axis, y_axis, z_axis)
	var ang := acos(clampf(up_dir.dot(fore_dir), -1.0, 1.0))
	elbow.rotation = Vector3(ang, 0.0, 0.0)
	var parent_basis := shoulder.basis * elbow.transform.basis
	var hy := hilt_y.normalized()
	var hx := hilt_x - hy * hilt_x.dot(hy)
	if hx.length_squared() < 0.0001:
		hx = x_axis
	hx = hx.normalized()
	var hz := hx.cross(hy).normalized()
	hx = hy.cross(hz).normalized()
	wrist.basis = parent_basis.inverse() * Basis(hx, hy, hz)
const TAU := PI * 2.0