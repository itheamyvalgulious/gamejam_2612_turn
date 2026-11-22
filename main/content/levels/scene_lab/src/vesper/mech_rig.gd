extends Node3D
## T4 // VESPER — procedural bio-mechanical assault frame.
##
## Generated 100% from code: meshes, materials, rig, motion.  No imported assets
## and no AnimationPlayer keyframes.  Every pose is a closed-form function of
## time, velocity, gait phase and combat timeline.
##
## Architecture
##   four radial "tail fibre" legs, 4-fold symmetric at rest like a T4 phage
##   humanoid upper chassis on a rotating waist ring
##   one two-handed laser greatsword, gripped by both hands
##
## Locomotion
##   analytic gait clock + two-bone leg IK (law of cosines)
## Combat
##   weapon-space pose keys, two-bone arm IK solved every frame so both fists
##   track the hilt, 360-degree waist spin, blade ribbons from swept transforms.
## 尺度：本文件里的硬编码距离 / 速度都是**世界单位**（1 u = 0.547 m，见 src/core/units.gd）；
## 玩家可见的数值一律走 P.getm()（真实米）。

const MK = preload("res://src/vesper/mesh_kit.gd")
const MAT = preload("res://src/vesper/materials.gd")
const PAL = preload("res://src/vesper/material_palette.gd")
const Trail = preload("res://src/vesper/blade_trail.gd")
const FX = preload("res://src/vesper/fx.gd")
const PathPlan = preload("res://src/vesper/blade_path.gd")

signal footstep(world_pos: Vector3, strength: float)
signal impact(world_pos: Vector3, strength: float)
signal attack_started(label: String, heavy: bool)

const HIP_Y := 1.95
const HIP_R := 0.58
const FEMUR := 1.50
const TIBIA := 1.95
const FOOT_R := 2.00
const ANKLE_H := 0.30
const WAIST_Y := 0.52
const UPPER := 0.98
const FORE := 0.88
const WALK_SPEED := 3.2
const RUN_SPEED := 8.4
const SPRINT_SPEED := 12.0
const TAU := PI * 2.0
const GRIP := 0.24
const GRAVITY := 22.0
const JUMP_SPEED := 8.2
const TAKEOFF_TIME := 0.14
const LAND_TIME := 0.56

const LEG_AZ := [45.0, 135.0, 225.0, 315.0]

# 刀身：从护手到刀尖的那一段（刀自身空间的 y 区间），格挡规划/几何判定共用
const BLADE_Y0 := 0.58
const BLADE_LEN := 2.35
const TORSO_SCALE := 1.45
const SHOULDER_MID := Vector3(0.0, 0.565, -0.01)

# ---------------------------------------------------------------- public state
var move_command := Vector3.ZERO       # desired world-space velocity (XZ)
var speed := 0.0
var display_speed := 0.0
var heading := 0.0
var angular_velocity := 0.0
var gait_phase := 0.0
var locomotion_state := "IDLE"
var attack_name := ""
var combo_step := 0
var is_attacking := false
var attack_time := 0.0
var dash_time := 0.0
var jump_state := "GROUND"
var ground_y := 0.0
var jump_t := 0.0
var vertical_velocity := 0.0
var air_time := 0.0
var time := 0.0
var auto_step := true
var vfx_root: Node3D

# ---------------------------------------------------------------- node refs
var body: Node3D
var torso: Node3D
var head: Node3D
var reactor_ring: Node3D
var chest_light: OmniLight3D
var weapon_root: Node3D
var weapon_spin: Node3D
var weapon_light: OmniLight3D
var blade_base: Marker3D
var blade_tip: Marker3D
var blade_trail
var contact_shadow: MeshInstance3D
var legs: Array = []
var arms: Array = []
var pauldrons: Array = []

var _attack: Dictionary = {}
var _attack_queue: Array = []
var _attack_label := ""
var _dash_dir := Vector3.FORWARD
var _dash_cooldown := 0.0
var _yaw_rate := 0.0
var _shake_sent := {}
var _lunge_prev := 0.0
var _carry_w := 0.0
var _fx: Node3D

# ======================================================= [ACT PATCH] integration
var palette: Dictionary = {}          # 配色（交给 materials.gd 的 Palette 解释）
var has_weapon := true                # 远程怪不生成刀（但保留握把位姿让手臂 IK 有目标）
var arena_bounds := Vector2.ZERO      # (半宽, 半深)，0 = 不限制
var facing_override := false          # AI 用：强制朝向
var facing_heading := 0.0
var face_rate := 7.0
var timing: Dictionary = {}           # 攻击名/别名 -> {duration, windup, active, recovery}
var timing_key := ""                  # 本次攻击用的参数键（方向斩用别名，各自独立调参）
var _warp_info: Dictionary = {}
var attack_elapsed := 0.0
var attack_total := 0.0
var attack_hit_from := 0.0            # 判定窗口（warp 到 clip 时间轴）
var attack_hit_to := 0.0
var vfx_enabled := true
var weapon_meshes: Array = []         # 刀的 MeshInstance3D（真实碰撞剖面用）
var blade_discs: Array = []           # [{y, r}] 由剑的网格顶点算出的圆盘剖面
var weapon_xf: Transform3D = Transform3D.IDENTITY
var weapon_prev_xf: Transform3D = Transform3D.IDENTITY
var weapon_scale := 1.0
var spin_local := Transform3D.IDENTITY   # weapon_spin 相对 weapon_root 的固定位姿
var blade_path                         # BladePath：刀位姿过渡规划（弹反拦截用）
var _path_pose: Dictionary = {}
var last_dt := 1.0 / 60.0
# 手感参数（由玩家控制器/AI 每帧从参数表写入）
var jump_vel := JUMP_SPEED
var grav := GRAVITY
var takeoff_time := TAKEOFF_TIME
var land_time := LAND_TIME
var dash_distance := 3.0
var dash_duration := 0.30
var dash_cd := 0.55
var accel_rate := 18.0
var decel_rate := 26.0
var turn_rate := 12.0
var guard := 0.0            # 0..1 举刀/格挡姿态混合
var attack_yaw := 0.0       # 方向斩：整段姿势绕 Y 轴偏转
# [ACT PATCH] 程序化挥砍（单手横斩 / 反手后刺）：直接按方位角驱动刀，而不是靠姿势关键帧
var proc_active := false
var proc_a0 := 0.0          # 起始方位角（0=正前, +左, -右, ±π=正后）
var proc_a1 := 0.0          # 结束方位角
var proc_reach := 0.62      # 刀柄离躯干中心的水平半径
var proc_h := 0.12          # 刀柄高度
var proc_lift := 0.12       # 刀身相对水平面的抬升
var proc_thrust := 0.0      # 沿刀轴额外伸出（后刺用）
var proc_torso := 0.55      # 躯干跟随比例（剩下的给手臂/刀）
var proc_lean := 0.10       # 侧倾
var offhand := 0.0          # 0=双手握刀 1=松开左手（单手持刀）
var aim_active := false     # 弹反瞄准：把刀伸向指定方向
var aim_dir := Vector3.FORWARD
var fp_mode := false          # 第一人称：只显示刀，并改成手持观感位
var blade_core_mats: Array = []
var attack_lunge_scale := 1.0

const BASE_POSE := {
	"ty": -0.12, "tx": 0.0, "tz": 0.0, "hy": 0.05, "hx": -0.02, "crouch": 0.0, "lean": 0.0,
	"wpx": 0.62, "wpy": 0.32, "wpz": -0.95,
	"wrx": -0.05, "wry": 0.0, "wrz": 0.10,
}

# Combat clips.  The sword lives in torso space; both hands are solved onto its
# hilt every frame, so every pose below is automatically a two-handed hold.
# Weapon positions deliberately travel far from the chest so the arms open up
# and the hilt/guard stay outside the torso volume.
const ATTACK_LIGHT_1 := {
	"name": "RIFT CLEAVE",
	"duration": 0.86,
	"trail": [0.18, 0.46],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.20, "p": {"ty": -0.70, "tz": 0.10, "tx": 0.02, "hy": 0.45, "crouch": 0.02,
			"wpx": 0.55, "wpy": 0.64, "wpz": -1.00, "wrx": -1.35, "wry": -1.15, "wrz": 0.10}},
		{"t": 0.36, "p": {"ty": 0.72, "tz": -0.18, "tx": -0.16, "hy": -0.45, "crouch": 0.10, "lean": 0.08,
			"wpx": -0.40, "wpy": 0.52, "wpz": -1.02, "wrx": -1.58, "wry": 0.55, "wrz": -0.12}},
		{"t": 0.56, "p": {"ty": 0.92, "tz": -0.08, "tx": -0.10, "hy": -0.50, "crouch": 0.06, "lean": 0.05,
			"wpx": -0.58, "wpy": 0.46, "wpz": -0.96, "wrx": -1.68, "wry": 1.12, "wrz": -0.25}},
		{"t": 0.86, "p": {}},
	],
	"lunge": [[0.00, 0.0], [0.16, 0.0], [0.36, 0.75], [0.60, 1.05], [0.86, 1.05]],
	"hit_at": 0.345, "hit_kind": "air",
}
const ATTACK_LIGHT_2 := {
	"name": "ASCENDING FANG",
	"duration": 0.80,
	"trail": [0.16, 0.44],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.20, "p": {"ty": 0.52, "tz": -0.10, "tx": -0.10, "hy": -0.35, "crouch": 0.16,
			"wpx": 0.34, "wpy": 0.14, "wpz": -1.00, "wrx": -2.75, "wry": -0.50, "wrz": 0.18}},
		{"t": 0.34, "p": {"ty": -0.52, "tz": 0.16, "tx": 0.10, "hy": 0.40, "crouch": 0.02, "lean": 0.06,
			"wpx": -0.10, "wpy": 0.80, "wpz": -1.02, "wrx": -0.42, "wry": 0.70, "wrz": -0.32}},
		{"t": 0.52, "p": {"ty": -0.70, "tz": 0.08, "tx": 0.14, "hy": 0.45, "crouch": -0.04,
			"wpx": -0.02, "wpy": 0.94, "wpz": -0.96, "wrx": -0.10, "wry": 1.10, "wrz": -0.38}},
		{"t": 0.80, "p": {}},
	],
	"lunge": [[0.00, 0.0], [0.16, 0.0], [0.36, 0.70], [0.58, 1.00], [0.80, 1.00]],
	"hit_at": 0.325, "hit_kind": "air",
}
const ATTACK_HEAVY := {
	"name": "GUILLOTINE",
	"duration": 1.46,
	"trail": [0.0, 0.0],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.36, "p": {"tx": 0.26, "ty": 0.06, "crouch": -0.08, "lean": -0.08, "hx": -0.20,
			"wpx": 0.18, "wpy": 1.00, "wpz": -0.92, "wrx": 0.15, "wry": 0.0, "wrz": 0.05}},
		{"t": 0.50, "p": {"tx": 0.32, "ty": 0.02, "crouch": -0.12, "lean": -0.14, "hx": -0.24,
			"wpx": 0.16, "wpy": 1.06, "wpz": -0.90, "wrx": 0.28, "wry": 0.0, "wrz": 0.0}},
		{"t": 0.63, "p": {"tx": -0.52, "ty": 0.0, "crouch": 0.34, "lean": 0.24, "hx": 0.30,
			"wpx": 0.02, "wpy": 0.16, "wpz": -1.12, "wrx": -2.95, "wry": 0.0, "wrz": 0.02}},
		{"t": 0.80, "p": {"tx": -0.30, "ty": 0.0, "crouch": 0.20, "lean": 0.12, "hx": 0.16,
			"wpx": 0.10, "wpy": 0.34, "wpz": -1.00, "wrx": -2.55, "wry": 0.05, "wrz": 0.06}},
		{"t": 1.14, "p": {"tx": -0.04, "crouch": 0.03, "lean": 0.0,
			"wpx": 0.56, "wpy": 0.38, "wpz": -0.95, "wrx": 0.02, "wry": 0.0, "wrz": -0.15}},
		{"t": 1.46, "p": {}},
	],
	"lunge": [[0.0, 0.0], [0.46, 0.0], [0.56, 0.45], [0.80, 1.15], [1.46, 1.15]],
	"hit_at": 0.610, "hit_kind": "ground",
}
const ATTACK_SPIN := {
	"name": "HELIX STORM",
	"duration": 1.58,
	"trail": [0.30, 0.90],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.22, "p": {"ty": -0.60, "tz": 0.08, "crouch": 0.12, "lean": 0.05,
			"wpx": 0.55, "wpy": 0.52, "wpz": -0.90, "wrx": -1.50, "wry": -1.10, "wrz": 0.05}},
		{"t": 0.42, "p": {"ty": TAU * 0.30, "tz": 0.04, "crouch": 0.15, "lean": 0.07,
			"wpx": 0.12, "wpy": 0.60, "wpz": -1.02, "wrx": -1.60, "wry": 0.0, "wrz": 0.0}},
		{"t": 0.74, "p": {"ty": TAU * 0.74, "tz": 0.0, "crouch": 0.13, "lean": 0.07,
			"wpx": 0.12, "wpy": 0.60, "wpz": -1.02, "wrx": -1.60, "wry": 0.0, "wrz": 0.0}},
		{"t": 1.04, "p": {"ty": TAU - 0.35, "tz": -0.06, "crouch": 0.08, "lean": 0.03,
			"wpx": -0.12, "wpy": 0.52, "wpz": -0.96, "wrx": -1.62, "wry": 0.45, "wrz": -0.08}},
		{"t": 1.28, "p": {"ty": TAU, "crouch": 0.03, "lean": 0.0,
			"wpx": 0.56, "wpy": 0.38, "wpz": -0.95, "wrx": 0.02, "wry": 0.0, "wrz": -0.15}},
		{"t": 1.58, "p": {"ty": TAU}},
	],
	"lunge": [[0.0, 0.0], [0.24, 0.05], [0.52, 0.55], [0.84, 1.10], [1.10, 1.30], [1.58, 1.30]],
	"hit_at": 0.620, "hit_kind": "air",
}

func _ready() -> void:
	_fx = FX.new()
	_fx.name = "FX"
	_fx.top_level = true
	add_child(_fx)
	_fx.global_transform = Transform3D.IDENTITY
	vfx_root = _fx
	_build()
	# [ACT PATCH] 刀的真实碰撞剖面：直接读建模出来的网格顶点
	if has_weapon and weapon_spin != null:
		for c in weapon_spin.get_children():
			if c is MeshInstance3D:
				weapon_meshes.append(c)
		blade_discs = build_blade_discs()
	for mi in weapon_meshes:
		var mm = mi.material_override
		if mm is ShaderMaterial:
			blade_core_mats.append(mm)
	if has_weapon:
		blade_trail = Trail.new()
		blade_trail.name = "GreatswordTrail"
		_fx.add_child(blade_trail)
	weapon_scale = weapon_spin.global_transform.basis.get_scale().x if weapon_spin != null else 1.0
	# weapon_spin 在 weapon_root 空间里是固定挂点（固定绕 Y 偏转），记下来给规划器换算
	if weapon_spin != null:
		spin_local = weapon_spin.transform
	blade_path = PathPlan.new()
	heading = rotation.y
	_update_legs(1.0 / 60.0, 0.0)
	_update_arms(BASE_POSE)
	if auto_step:
		set_process(true)


func _process(delta: float) -> void:
	if auto_step:
		advance(minf(delta, 0.05))


# =============================================================== construction
func _build() -> void:
	body = Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, HIP_Y, 0)
	add_child(body)

	_build_pelvis()
	_build_torso()
	_build_legs()
	_build_arms()
	# [ACT PATCH] 武器可选（远程怪不拿刀，但保留握把节点让双臂继续解算）
	_build_weapon()

	contact_shadow = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.2, 3.2)
	contact_shadow.mesh = qm
	contact_shadow.material_override = MAT.contact_shadow()
	contact_shadow.rotation_degrees = Vector3(-90, 0, 0)
	contact_shadow.position = Vector3(0, 0.012, 0)
	contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(contact_shadow)


func _build_pelvis() -> void:
	var m := PAL.for_palette(palette)
	MK.add(body, MK.prism(8, 0.70, 0.58, 0.20, PI / 8.0), m.armor_shadow(), Vector3(0, 0.06, 0))
	MK.add(body, MK.prism(8, 0.34, 0.64, 0.28, PI / 8.0), m.frame(), Vector3(0, -0.17, 0))
	MK.add(body, MK.prism(16, 0.575, 0.575, 0.035, 0.0), m.emissive(Color(1.0, 0.30, 0.05), 2.2), Vector3(0, -0.04, 0))
	MK.add(body, MK.prism(8, 0.68, 0.68, 0.040, PI / 8.0), m.copper(), Vector3(0, 0.17, 0))
	MK.add(body, MK.slab(0.98, 0.82, 0.14, 0.034), m.armor(), Vector3(0, 0.245, 0))
	MK.add(body, MK.slab(0.70, 0.60, 0.085, 0.022), m.armor_edge(), Vector3(0, 0.32, 0))
	# front / rear tail plates
	MK.add(body, MK.slab(0.34, 0.26, 0.30, 0.020), m.paint(), Vector3(0, -0.10, -0.34), Vector3(18, 0, 0))
	MK.add(body, MK.slab(0.24, 0.18, 0.22, 0.016), m.frame(), Vector3(0, -0.07, 0.34), Vector3(-16, 0, 0))
	# four short baseplate fibres between the legs
	for i in 4:
		var a := deg_to_rad(90.0 * i)
		var dir := Vector3(cos(a), 0, sin(a))
		var pos := dir * 0.56 + Vector3(0, -0.06, 0)
		var claw := MeshInstance3D.new()
		claw.mesh = MK.prism(4, 0.045, 0.0, 0.24)
		claw.material_override = m.frame_light()
		claw.position = pos
		claw.quaternion = Quaternion(Vector3.UP, (dir + Vector3(0, -0.45, 0)).normalized())
		body.add_child(claw)
		MK.bolt(body, pos + dir * 0.035 + Vector3(0, 0.08, 0), 0.035, 0.03, m.emissive(Color(1.0, 0.3, 0.05), 3.4))
	# tail sheath / exposed spine between pelvis and chest
	MK.add(body, MK.prism(8, 0.16, 0.12, 0.58, PI / 8.0), m.frame(), Vector3(0, 0.42, 0))
	for i in 4:
		var y := 0.24 + 0.10 * i
		var r := 0.245 - 0.010 * i
		MK.add(body, MK.prism(8, r, r - 0.012, 0.075, PI / 8.0), m.frame_light(), Vector3(0, y, 0))
		MK.add(body, MK.prism(8, r + 0.010, r + 0.010, 0.010, PI / 8.0), m.emissive(Color(1.0, 0.28, 0.045), 2.2), Vector3(0, y - 0.04, 0))
	for i in 4:
		var a := PI / 4.0 + TAU * i / 4.0
		var d := Vector3(cos(a), 0, sin(a))
		MK.add(body, MK.prism(6, 0.028, 0.024, 0.40, 0), m.armor_shadow(), d * 0.245 + Vector3(0, 0.39, 0), Vector3(0, -rad_to_deg(a), 0))
	# waist reactor collar
	reactor_ring = Node3D.new()
	reactor_ring.position = Vector3(0, 0.44, 0)
	body.add_child(reactor_ring)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.30
	tor.outer_radius = 0.345
	tor.rings = 24
	tor.ring_segments = 6
	MK.add(reactor_ring, tor, m.emissive(Color(1.0, 0.24, 0.035), 2.0), Vector3.ZERO, Vector3(90, 0, 0), Vector3(1, 1, 0.7))
	for i in 3:
		var a := TAU * i / 3.0
		MK.add(reactor_ring, MK.prism(5, 0.020, 0.0, 0.16), m.emissive(Color(1.0, 0.35, 0.06), 2.6), Vector3(cos(a) * 0.33, 0, sin(a) * 0.33))


func _build_torso() -> void:
	var m := PAL.for_palette(palette)
	torso = Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0, WAIST_Y, 0)
	torso.scale = Vector3.ONE * TORSO_SCALE
	body.add_child(torso)

	MK.add(torso, MK.prism(8, 0.19, 0.205, 0.34, PI / 8.0), m.frame(), Vector3(0, 0.10, 0))
	MK.add(torso, MK.prism(8, 0.30, 0.37, 0.52, PI / 8.0), m.frame(), Vector3(0, 0.40, 0), Vector3.ZERO, Vector3(1.34, 1.0, 0.82))
	# abdomen carapace
	MK.add(torso, MK.slab(0.52, 0.36, 0.12, 0.024), m.armor(), Vector3(0, 0.13, -0.15), Vector3(-8, 0, 0))
	MK.add(torso, MK.slab(0.44, 0.28, 0.085, 0.018), m.armor_shadow(), Vector3(0, 0.23, -0.17), Vector3(-10, 0, 0))
	for side in [-1.0, 1.0]:
		MK.add(torso, MK.slab(0.11, 0.32, 0.21, 0.014), m.armor_shadow(), Vector3(0.26 * side, 0.20, 0.02), Vector3(0, 0, -12 * side))
	# broad layered pectoral petals
	for side in [-1.0, 1.0]:
		MK.add(torso, MK.slab(0.47, 0.24, 0.44, 0.038), m.armor(),
			Vector3(0.275 * side, 0.45, -0.175), Vector3(6, -18 * side, -7 * side))
		MK.add(torso, MK.slab(0.36, 0.17, 0.32, 0.026), m.armor_edge(),
			Vector3(0.26 * side, 0.49, -0.27), Vector3(3, -18 * side, -7 * side))
		MK.add(torso, MK.slab(0.17, 0.038, 0.060, 0.008), m.paint(),
			Vector3(0.32 * side, 0.57, -0.34), Vector3(0, -18 * side, 38 * side))
		# layered vent slats
		for i in 3:
			MK.add(torso, MK.slab(0.13, 0.020, 0.018, 0.003), m.frame(),
				Vector3(0.36 * side, 0.38 + i * 0.035, -0.24), Vector3(0, -18 * side, 0))
	# sternum energy core
	MK.add(torso, MK.slab(0.12, 0.27, 0.27, 0.018), m.frame_light(), Vector3(0, 0.43, -0.275))
	MK.add(torso, MK.prism(8, 0.11, 0.09, 0.03, PI / 8.0), m.frame(), Vector3(0, 0.47, -0.35), Vector3(90, 0, 0))
	MK.add(torso, MK.slab(0.05, 0.17, 0.19, 0.008), m.emissive(Color(1.0, 0.34, 0.07), 4.2), Vector3(0, 0.44, -0.345))
	MK.add(torso, MK.slab(0.14, 0.11, 0.15, 0.018), m.armor_shadow(), Vector3(0, 0.50, -0.355))
	MK.add(torso, MK.slab(0.038, 0.075, 0.115, 0.006), m.frame(), Vector3(0, 0.50, -0.408))
	MK.add(torso, MK.slab(0.018, 0.045, 0.075, 0.003), m.emissive(Color(1.0, 0.40, 0.09), 3.6), Vector3(0, 0.50, -0.425))
	# chest chevrons
	for side in [-1.0, 1.0]:
		MK.add(torso, MK.beam_x(0.20, 0.032, 0.075, 0.020, 0.055), m.paint(),
			Vector3(0.06 * side, 0.535, -0.345), Vector3(0, -38 * side, -28 * side))
	# neck collar lights
	for side in [-1.0, 1.0]:
		MK.add(torso, MK.slab(0.06, 0.035, 0.026, 0.005), m.emissive(Color(1.0, 0.3, 0.05), 3.4), Vector3(0.19 * side, 0.725, -0.14))
	# armpit vents
	for side in [-1.0, 1.0]:
		for i in 2:
			MK.add(torso, MK.slab(0.045, 0.06, 0.018, 0.003), m.frame(), Vector3(0.385 * side, 0.40 + i * 0.055, -0.18), Vector3(0, -18 * side, 0))
	for side in [-1.0, 1.0]:
		MK.add(torso, MK.beam_x(0.31, 0.055, 0.11, 0.035, 0.075), m.armor_edge(),
			Vector3(0.0, 0.53, -0.31), Vector3(0, -38 * side, -36 * side))
	# collar / shoulder yoke
	MK.add(torso, MK.slab(0.96, 0.36, 0.16, 0.026), m.armor_shadow(), Vector3(0, 0.615, 0.00))
	MK.add(torso, MK.slab(0.60, 0.22, 0.095, 0.018), m.armor(), Vector3(0, 0.685, -0.08))
	for side in [-1.0, 1.0]:
		MK.add(torso, MK.slab(0.16, 0.11, 0.06, 0.010), m.paint(), Vector3(0.33 * side, 0.675, -0.112), Vector3(0, 0, 4 * side))
		MK.add(torso, MK.slab(0.04, 0.10, 0.02, 0.003), m.emissive(Color(1.0, 0.26, 0.04), 1.6), Vector3(0.40 * side, 0.60, -0.12))
	# neck
	MK.add(torso, MK.prism(8, 0.085, 0.075, 0.16, PI / 8.0), m.frame_light(), Vector3(0, 0.735, -0.015))
	MK.add(torso, MK.prism(8, 0.14, 0.115, 0.045, PI / 8.0), m.copper(), Vector3(0, 0.685, -0.015))
	_build_backpack()
	_build_head()


func _build_backpack() -> void:
	var m := PAL.for_palette(palette)
	var pack := Node3D.new()
	pack.position = Vector3(0, 0.62, 0.34)
	pack.name = "PhageCapsid"
	torso.add_child(pack)
	# big hexagonal capsid, the icon of the T4
	MK.add(pack, MK.prism(6, 0.46, 0.39, 0.42, PI / 6.0), m.armor_shadow(), Vector3.ZERO, Vector3(90, 0, 0))
	MK.add(pack, MK.prism(6, 0.38, 0.35, 0.06, PI / 6.0), m.frame(), Vector3(0, 0, 0.235), Vector3(90, 0, 0))
	MK.add(pack, MK.prism(6, 0.33, 0.27, 0.045, PI / 6.0), m.armor(), Vector3(0, 0, 0.27), Vector3(90, 0, 0))
	# six bright collar nodes
	for i in 6:
		var a := PI / 6.0 + TAU * i / 6.0
		MK.bolt(pack, Vector3(cos(a) * 0.31, sin(a) * 0.31, 0.26), 0.028, 0.025, m.copper())
	# glowing sensor eye
	MK.add(pack, MK.prism(12, 0.095, 0.095, 0.03, 0), m.frame(), Vector3(0, 0, 0.29), Vector3(90, 0, 0))
	MK.add(pack, MK.prism(12, 0.070, 0.070, 0.018, 0), m.emissive(Color(1.0, 0.30, 0.05), 5.5), Vector3(0, 0, 0.305), Vector3(90, 0, 0))
	# radial panel seams on the capsid face
	for i in 6:
		var a := TAU * i / 6.0
		MK.add(pack, MK.beam_x(0.24, 0.018, 0.026, 0.010, 0.016), m.frame(),
			Vector3(cos(a) * 0.12, sin(a) * 0.12, 0.313), Vector3(0, 0, rad_to_deg(a)))
	# glowing collar around the eye
	var eye_ring := TorusMesh.new()
	eye_ring.inner_radius = 0.115
	eye_ring.outer_radius = 0.145
	eye_ring.rings = 20
	eye_ring.ring_segments = 5
	MK.add(pack, eye_ring, m.emissive(Color(1.0, 0.30, 0.05), 2.6), Vector3(0, 0, 0.315), Vector3(90, 0, 0))
	# collar ring + whiskers
	var tor := TorusMesh.new()
	tor.inner_radius = 0.30
	tor.outer_radius = 0.35
	tor.rings = 20
	tor.ring_segments = 6
	MK.add(pack, tor, m.copper(), Vector3(0, 0, 0.03), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.8))
	for i in 6:
		var a := TAU * i / 6.0
		var dir := Vector3(cos(a), sin(a), -0.25).normalized()
		var spike := MeshInstance3D.new()
		spike.mesh = MK.prism(4, 0.028, 0.0, 0.20)
		spike.material_override = m.frame_light()
		spike.position = Vector3(cos(a) * 0.36, sin(a) * 0.36, 0.03)
		spike.quaternion = Quaternion(Vector3.UP, dir)
		pack.add_child(spike)
	# thrusters: two hot nozzles at the lower back
	for side in [-1.0, 1.0]:
		MK.add(pack, MK.prism(8, 0.075, 0.055, 0.16, 0), m.frame(), Vector3(0.22 * side, -0.30, 0.18), Vector3(90, 0, 0))
		MK.add(pack, MK.prism(8, 0.055, 0.045, 0.02, 0), m.emissive(Color(1.0, 0.32, 0.05), 4.5), Vector3(0.22 * side, -0.30, 0.27), Vector3(90, 0, 0))
	# spine link
	for i in 3:
		var y := -0.26 - i * 0.16
		MK.add(pack, MK.prism(6, 0.11 - i * 0.012, 0.10 - i * 0.012, 0.10, PI / 6.0), m.frame_light(), Vector3(0, y, 0.02), Vector3(90, 0, 0))
		MK.add(pack, MK.prism(6, 0.085 - i * 0.01, 0.085 - i * 0.01, 0.02, PI / 6.0), m.emissive(Color(1.0, 0.26, 0.04), 2.2), Vector3(0, y - 0.055, 0.10), Vector3(90, 0, 0))
	chest_light = OmniLight3D.new()
	chest_light.light_color = Color(1.0, 0.35, 0.08)
	chest_light.light_energy = 0.7
	chest_light.omni_range = 2.6
	chest_light.shadow_enabled = false
	chest_light.position = Vector3(0, 0.45, 0.2)
	torso.add_child(chest_light)


func _build_head() -> void:
	var m := PAL.for_palette(palette)
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.82, -0.02)
	head.scale = Vector3(1.42, 1.42, 1.42)
	torso.add_child(head)
	MK.add(head, MK.slab(0.245, 0.33, 0.20, 0.022), m.armor_shadow(), Vector3(0, 0.10, -0.015), Vector3(4, 0, 0))
	MK.add(head, MK.slab(0.225, 0.29, 0.075, 0.014), m.armor_edge(), Vector3(0, 0.205, -0.03), Vector3(6, 0, 0))
	MK.add(head, MK.slab(0.215, 0.055, 0.13, 0.012), m.frame(), Vector3(0, 0.075, -0.175), Vector3(7, 0, 0))
	MK.add(head, MK.slab(0.195, 0.020, 0.028, 0.003), m.emissive(Color(1.0, 0.33, 0.05), 6.0), Vector3(0, 0.096, -0.214), Vector3(7, 0, 0))
	MK.add(head, MK.slab(0.205, 0.045, 0.045, 0.006), m.frame_light(), Vector3(0, 0.132, -0.196), Vector3(9, 0, 0))
	for side in [-1.0, 1.0]:
		MK.add(head, MK.slab(0.05, 0.09, 0.09, 0.010), m.armor(), Vector3(0.10 * side, 0.035, -0.16), Vector3(12, 0, 8 * side))
	MK.add(head, MK.slab(0.28, 0.12, 0.085, 0.014), m.armor_edge(), Vector3(0, 0.165, -0.175), Vector3(12, 0, 0))
	MK.add(head, MK.slab(0.205, 0.13, 0.055, 0.009), m.frame_light(), Vector3(0, 0.005, -0.155), Vector3(14, 0, 0))
	MK.add(head, MK.slab(0.19, 0.10, 0.085, 0.012), m.armor_shadow(), Vector3(0, -0.025, -0.135), Vector3(-9, 0, 0))
	MK.add(head, MK.slab(0.13, 0.025, 0.022, 0.004), m.paint(), Vector3(0, -0.062, -0.178))
	for side in [-1.0, 1.0]:
		MK.add(head, MK.slab(0.055, 0.05, 0.022, 0.004), m.emissive(Color(1.0, 0.28, 0.04), 3.0), Vector3(0.095 * side, 0.085, -0.198), Vector3(0, 22 * side, 0))
	for side in [-1.0, 1.0]:
		MK.add(head, MK.prism(8, 0.050, 0.038, 0.065, 0), m.frame_light(), Vector3(0.14 * side, 0.065, -0.045), Vector3(0, 0, 90))
		MK.add(head, MK.prism(8, 0.022, 0.016, 0.010, 0), m.emissive(Color(1.0, 0.32, 0.05), 4.5), Vector3(0.177 * side, 0.065, -0.045), Vector3(0, 0, 90))
		MK.add(head, MK.beam_x(0.46, 0.060, 0.13, 0.018, 0.045), m.armor(),
			Vector3(0.075 * side, 0.17, 0.05), Vector3(-8, 90, -32 * side))
		MK.add(head, MK.beam_x(0.30, 0.020, 0.06, 0.008, 0.022), m.paint(),
			Vector3(0.105 * side, 0.165, 0.075), Vector3(-8, 90, -32 * side))
	MK.add(head, MK.beam_x(0.30, 0.065, 0.05, 0.012, 0.02), m.armor_edge(), Vector3(0, 0.23, -0.02), Vector3(0, 0, 14))
	MK.add(head, MK.prism(4, 0.015, 0.0, 0.18), m.copper(), Vector3(0, 0.30, 0.02), Vector3(0, 0, 8))
	MK.add(head, MK.slab(0.075, 0.03, 0.018, 0.004), m.emissive(Color(1.0, 0.3, 0.04), 3.5), Vector3(0, -0.015, -0.20))


# --------------------------------------------------------------------- legs
func _build_legs() -> void:
	for i in 4:
		_build_leg(i, deg_to_rad(LEG_AZ[i]))


func _build_leg(index: int, az: float) -> void:
	var m := PAL.for_palette(palette)
	var dir := Vector3(cos(az), 0, sin(az))
	var leg_root := Node3D.new()
	leg_root.name = "Leg%d" % index
	leg_root.position = dir * HIP_R
	leg_root.rotation.y = -az
	body.add_child(leg_root)

	var mount := Node3D.new()
	mount.position = dir * (HIP_R - 0.02)
	mount.rotation.y = -az
	body.add_child(mount)
	MK.add(mount, MK.prism(6, 0.235, 0.215, 0.14, 0), m.armor_shadow(), Vector3(0.015, 0.02, 0), Vector3(0, 0, 90))
	MK.add(mount, MK.prism(12, 0.165, 0.165, 0.028, 0), m.frame(), Vector3(0.095, 0.02, 0), Vector3(0, 0, 90))
	MK.add(mount, MK.prism(12, 0.128, 0.118, 0.014, 0), m.emissive(Color(1.0, 0.28, 0.05), 2.6), Vector3(0.11, 0.02, 0), Vector3(0, 0, 90))

	var yaw := Node3D.new()
	yaw.name = "HipYaw"
	leg_root.add_child(yaw)
	var hip := Node3D.new()
	hip.name = "HipPitch"
	yaw.add_child(hip)
	MK.add(hip, MK.gem(0.17, 4, 8), m.frame_light(), Vector3.ZERO)
	var hip_tor := TorusMesh.new()
	hip_tor.inner_radius = 0.16
	hip_tor.outer_radius = 0.215
	hip_tor.rings = 16
	hip_tor.ring_segments = 6
	MK.add(hip, hip_tor, m.copper(), Vector3(0.02, 0, 0), Vector3(0, 90, 0))
	MK.add(hip, MK.prism(10, 0.05, 0.05, 0.020, 0), m.emissive(Color(1.0, 0.3, 0.05), 3.8), Vector3(0.14, 0, 0.14), Vector3(90, 0, 0))

	# femur
	MK.add(hip, MK.beam_x(FEMUR, 0.27, 0.23, 0.18, 0.15, 0.38), m.frame(), Vector3.ZERO)
	MK.add(hip, MK.beam_x(FEMUR * 0.86, 0.16, 0.36, 0.10, 0.23, 0.42), m.armor(), Vector3(0.06, 0.08, 0))
	MK.add(hip, MK.beam_x(FEMUR * 0.70, 0.19, 0.055, 0.09, 0.035), m.armor_edge(), Vector3(0.12, 0.02, 0.155))
	MK.add(hip, MK.beam_x(FEMUR * 0.68, 0.17, 0.045, 0.08, 0.030), m.armor_shadow(), Vector3(0.12, 0.02, -0.155))
	MK.add(hip, MK.beam_x(FEMUR * 0.30, 0.035, 0.08, 0.028, 0.06), m.paint(), Vector3(0.30, 0.15, 0.10))
	MK.add(hip, MK.beam_x(FEMUR * 0.46, 0.055, 0.20, 0.040, 0.13, 0.40), m.armor_edge(), Vector3(0.24, 0.155, 0))
	MK.add(hip, MK.beam_x(FEMUR * 0.54, 0.014, 0.030, 0.009, 0.022), m.emissive(Color(1.0, 0.27, 0.04), 3.4), Vector3(0.18, 0.0, 0.115))
	MK.add(hip, MK.beam_x(FEMUR * 0.62, 0.035, 0.065, 0.026, 0.048), m.copper(), Vector3(0.16, -0.12, 0.045))
	MK.add(hip, MK.beam_x(FEMUR * 0.20, 0.06, 0.28, 0.05, 0.24), m.paint(), Vector3(0.05, 0.065, 0.0))
	MK.add(hip, MK.slab(0.28, 0.32, 0.11, 0.02), m.armor(), Vector3(0.10, 0.16, 0.0), Vector3(0, 0, -8))
	MK.add(hip, MK.beam_x(FEMUR * 0.24, 0.025, 0.06, 0.020, 0.045), m.frame(), Vector3(0.42, 0.02, 0.135))
	for j in 2:
		MK.bolt(hip, Vector3(0.18 + j * 0.72, 0.125, 0.14), 0.026, 0.024, m.copper())

	var knee := Node3D.new()
	knee.name = "Knee"
	knee.position = Vector3(FEMUR, 0, 0)
	hip.add_child(knee)
	MK.add(knee, MK.prism(12, 0.165, 0.165, 0.34, 0), m.frame(), Vector3(0, 0, 0), Vector3(90, 0, 0))
	for side in [-1.0, 1.0]:
		MK.add(knee, MK.prism(6, 0.195, 0.17, 0.06, 0), m.armor_shadow(), Vector3(0, 0, 0.175 * side), Vector3(90, 0, 0))
		MK.add(knee, MK.prism(10, 0.095, 0.095, 0.018, 0), m.emissive(Color(1.0, 0.28, 0.045), 2.4), Vector3(0, 0, 0.21 * side), Vector3(90, 0, 0))
	# knee guard plate facing forward
	MK.add(knee, MK.prism(6, 0.255, 0.215, 0.10, 0), m.armor_shadow(), Vector3(0.03, 0.02, -0.17), Vector3(90, 0, 0))
	MK.add(knee, MK.prism(6, 0.225, 0.18, 0.07, 0), m.armor(), Vector3(0.03, 0.02, -0.225), Vector3(90, 0, 0))
	MK.add(knee, MK.prism(6, 0.10, 0.075, 0.025, 0), m.paint(), Vector3(0.03, 0.02, -0.265), Vector3(90, 0, 0))
	# tibia
	MK.add(knee, MK.beam_x(TIBIA, 0.22, 0.19, 0.125, 0.135, 0.38), m.frame(), Vector3.ZERO)
	MK.add(knee, MK.beam_x(TIBIA * 0.82, 0.10, 0.28, 0.06, 0.13, 0.42), m.armor(), Vector3(0.09, 0.07, 0))
	MK.add(knee, MK.beam_x(TIBIA * 0.40, 0.055, 0.16, 0.04, 0.10, 0.38), m.armor_edge(), Vector3(0.28, 0.13, 0))
	MK.add(knee, MK.beam_x(TIBIA * 0.52, 0.014, 0.030, 0.008, 0.018), m.emissive(Color(1.0, 0.28, 0.045), 3.6), Vector3(0.22, 0.005, 0.115))
	MK.add(knee, MK.beam_x(TIBIA * 0.34, 0.022, 0.050, 0.016, 0.032), m.copper(), Vector3(0.30, -0.10, 0.0))
	# dark mechanical bands + red shin decal
	for i in 2:
		MK.add(knee, MK.beam_x(0.055, 0.245, 0.31, 0.245, 0.31, 0.38), m.frame_light(), Vector3(TIBIA * (0.34 + i * 0.28), 0, 0))
	MK.add(knee, MK.beam_x(TIBIA * 0.14, 0.035, 0.20, 0.030, 0.16), m.paint(), Vector3(0.42, 0.11, 0.0))
	MK.add(knee, MK.beam_x(TIBIA * 0.17, 0.085, 0.23, 0.055, 0.13, 0.38), m.armor_edge(), Vector3(TIBIA * 0.80, 0.02, 0.0))
	MK.add(knee, MK.beam_x(TIBIA * 0.09, 0.032, 0.06, 0.024, 0.04), m.paint(), Vector3(0.62, 0.13, 0.095))
	MK.add(knee, MK.beam_x(TIBIA * 0.44, 0.028, 0.06, 0.018, 0.04), m.frame(), Vector3(0.45, -0.06, 0.15))
	MK.add(knee, MK.beam_x(TIBIA * 0.34, 0.018, 0.035, 0.012, 0.024), m.copper(), Vector3(0.50, -0.06, 0.155))
	MK.add(knee, MK.beam_x(TIBIA * 0.30, 0.045, 0.03, 0.03, 0.02), m.emissive(Color(1.0, 0.3, 0.05), 2.0), Vector3(0.18, 0.02, 0.155))
	# long tibial spur
	MK.add(knee, MK.blade(0.56, 0.09, 0.026, 0.05, 8), m.armor_edge(),
		Vector3(TIBIA * 0.66, 0.12, 0.0), Vector3(0, 0, 90))
	MK.add(knee, MK.blade(0.40, 0.036, 0.013, 0.02, 6), m.emissive(Color(1.0, 0.25, 0.04), 1.8),
		Vector3(TIBIA * 0.70, 0.135, 0.0), Vector3(0, 0, 90))

	var ankle := Node3D.new()
	ankle.name = "Ankle"
	ankle.position = Vector3(TIBIA, 0, 0)
	knee.add_child(ankle)
	MK.add(ankle, MK.gem(0.125, 3, 8), m.frame_light(), Vector3.ZERO)
	MK.add(ankle, MK.slab(0.50, 0.38, 0.13, 0.026), m.armor_shadow(), Vector3(0.08, -0.13, 0), Vector3(0, 0, -7))
	MK.add(ankle, MK.slab(0.35, 0.25, 0.065, 0.014), m.armor_edge(), Vector3(0.09, -0.195, 0), Vector3(0, 0, -7))
	MK.add(ankle, MK.slab(0.17, 0.15, 0.016, 0.004), m.emissive(Color(1.0, 0.27, 0.04), 2.5), Vector3(0.06, -0.215, 0), Vector3(0, 0, -7))
	for side in [-1.0, 1.0]:
		var claw := MeshInstance3D.new()
		claw.mesh = MK.prism(4, 0.075, 0.0, 0.24)
		claw.material_override = m.armor_edge()
		claw.position = Vector3(0.15, -0.18, 0.10 * side)
		claw.rotation_degrees = Vector3(180, 0, 8)
		ankle.add_child(claw)
	var claw_c := MeshInstance3D.new()
	claw_c.mesh = MK.prism(4, 0.045, 0.0, 0.16)
	claw_c.material_override = m.frame_light()
	claw_c.position = Vector3(0.20, -0.19, 0.0)
	claw_c.rotation_degrees = Vector3(180, 0, 18)
	ankle.add_child(claw_c)
	var heel := MeshInstance3D.new()
	heel.mesh = MK.prism(4, 0.042, 0.0, 0.15)
	heel.material_override = m.frame_light()
	heel.position = Vector3(-0.07, -0.18, 0)
	heel.rotation_degrees = Vector3(180, 0, -24)
	ankle.add_child(heel)

	legs.append({
		"root": leg_root, "yaw": yaw, "hip": hip, "knee": knee, "ankle": ankle,
		"az": az, "down": true, "phase": 0.0, "target": Vector3.ZERO,
	})


# --------------------------------------------------------------------- 支撑
func foot_points_xz() -> Array:
	## 四只脚（ankle）在世界空间的水平投影，用于平台支撑凸包。
	var pts: Array = []
	for l in legs:
		var n: Node3D = l.get("ankle", null)
		if n != null and is_instance_valid(n):
			var p := n.global_position
			pts.append(Vector2(p.x, p.z))
	return pts


# --------------------------------------------------------------------- arms
func _build_arms() -> void:
	# right first, so arms[0] always receives the upper (right) grip
	for side in [1.0, -1.0]:
		_build_arm(side)


func _build_arm(side: float) -> void:
	var m := PAL.for_palette(palette)
	var shoulder := Node3D.new()
	shoulder.name = "ShoulderR" if side > 0 else "ShoulderL"
	shoulder.position = Vector3(0.76 * side, 0.565, -0.01)
	torso.add_child(shoulder)

	# pauldron is mounted to the torso so it stays proud when the arm solves IK
	var pauldron := Node3D.new()
	pauldron.name = "PauldronR" if side > 0 else "PauldronL"
	pauldron.position = shoulder.position
	pauldron.rotation_degrees = Vector3(0, 0, -16 * side)
	torso.add_child(pauldron)
	MK.add(pauldron, MK.gem(0.165, 4, 8), m.frame(), Vector3.ZERO)
	MK.add(pauldron, MK.slab(0.46, 0.52, 0.10, 0.026), m.armor_shadow(),
		Vector3(0.04 * side, 0.04, 0.0))
	MK.add(pauldron, MK.prism(6, 0.35, 0.30, 0.10, PI / 6.0), m.armor(),
		Vector3(0.06 * side, 0.14, 0.0), Vector3.ZERO, Vector3(1.2, 1.0, 1.35))
	MK.add(pauldron, MK.prism(6, 0.26, 0.20, 0.055, PI / 6.0), m.armor_edge(),
		Vector3(0.08 * side, 0.215, 0.0), Vector3.ZERO, Vector3(1.2, 1.0, 1.35))
	MK.add(pauldron, MK.slab(0.18, 0.16, 0.035, 0.006), m.paint(),
		Vector3(0.19 * side, 0.245, -0.10), Vector3(0, 0, -10 * side))
	MK.add(pauldron, MK.beam_x(0.34, 0.055, 0.10, 0.014, 0.04), m.armor_shadow(),
		Vector3(0.0, 0.22, 0.14), Vector3(-26, 0, 90))
	MK.add(pauldron, MK.prism(12, 0.055, 0.055, 0.018, 0), m.emissive(Color(1.0, 0.27, 0.04), 3.2),
		Vector3(0.23 * side, 0.0, 0.0), Vector3(0, 0, 90))
	MK.bolt(pauldron, Vector3(0.02 * side, 0.15, -0.205), 0.026, 0.03, m.copper())
	pauldrons.append(pauldron)

	# upper arm: built down -Y, then driven by IK
	MK.add(shoulder, MK.beam_x(UPPER, 0.17, 0.16, 0.13, 0.12), m.frame(),
		Vector3.ZERO, Vector3(0, 0, -90))
	MK.add(shoulder, MK.beam_x(UPPER * 0.72, 0.155, 0.235, 0.125, 0.18), m.armor(),
		Vector3(0.0, -0.06, 0), Vector3(0, 0, -90))
	MK.add(shoulder, MK.beam_x(UPPER * 0.30, 0.035, 0.245, 0.028, 0.21), m.paint(),
		Vector3(0.0, -0.10, 0), Vector3(0, 0, -90))
	MK.add(shoulder, MK.beam_x(UPPER * 0.28, 0.012, 0.06, 0.010, 0.045), m.emissive(Color(1.0, 0.28, 0.05), 3.0),
		Vector3(0.13, -0.35, 0.0), Vector3(0, 0, -90))
	MK.add(shoulder, MK.beam_x(UPPER * 0.22, 0.012, 0.022, 0.008, 0.014), m.emissive(Color(1.0, 0.27, 0.04), 3.0),
		Vector3(0.085, -0.10, 0.0), Vector3(0, 0, -90))

	var elbow := Node3D.new()
	elbow.name = "Elbow"
	elbow.position = Vector3(0, -UPPER, 0)
	shoulder.add_child(elbow)
	MK.add(elbow, MK.prism(10, 0.12, 0.12, 0.27, 0), m.frame(), Vector3.ZERO, Vector3(0, 0, 90))
	MK.add(elbow, MK.prism(6, 0.155, 0.13, 0.09, 0), m.armor(), Vector3(0.0, 0.02, -0.13), Vector3(90, 0, 0))
	MK.add(elbow, MK.prism(10, 0.075, 0.075, 0.018, 0), m.emissive(Color(1.0, 0.27, 0.04), 2.2),
		Vector3(0, 0, 0.145), Vector3(90, 0, 0))

	MK.add(elbow, MK.beam_x(FORE, 0.155, 0.15, 0.105, 0.11), m.frame(),
		Vector3.ZERO, Vector3(0, 0, -90))
	MK.add(elbow, MK.beam_x(FORE * 0.9, 0.125, 0.235, 0.080, 0.135), m.armor(),
		Vector3(0.0, -0.055, 0), Vector3(0, 0, -90))
	MK.add(elbow, MK.beam_x(FORE * 0.45, 0.040, 0.175, 0.024, 0.10), m.armor_edge(),
		Vector3(0.0, -0.20, 0), Vector3(0, 0, -90))
	MK.add(elbow, MK.beam_x(FORE * 0.35, 0.012, 0.02, 0.008, 0.012), m.emissive(Color(1.0, 0.28, 0.05), 4.0),
		Vector3(0.06, -0.12, -0.09), Vector3(0, 0, -90))
	for i in 3:
		MK.add(elbow, MK.slab(0.035, 0.07, 0.012, 0.003), m.emissive(Color(1.0, 0.25, 0.04), 1.4),
			Vector3(0.09, -0.20 - 0.035 * i, 0.02))
	MK.bolt(elbow, Vector3(0.10, -0.10, 0.06), 0.022, 0.02, m.copper())

	var wrist := Node3D.new()
	wrist.name = "Wrist"
	wrist.position = Vector3(0, -FORE, 0)
	elbow.add_child(wrist)
	# fist: the grip axis is local Y; the IK aligns it to the sword hilt
	MK.add(wrist, MK.prism(8, 0.094, 0.086, 0.19, PI / 8.0), m.frame_light(), Vector3(0, -0.01, 0))
	MK.add(wrist, MK.slab(0.19, 0.21, 0.12, 0.020), m.armor_shadow(), Vector3(0.005 * side, -0.06, 0.0))
	for i in 4:
		var fx := -0.057 + i * 0.038
		MK.add(wrist, MK.slab(0.036, 0.095, 0.052, 0.008), m.frame(), Vector3(fx * 1.15, -0.11, -0.052))
	MK.add(wrist, MK.slab(0.055, 0.10, 0.07, 0.010), m.armor(), Vector3(0.0, -0.075, -0.065))
	MK.add(wrist, MK.prism(8, 0.042, 0.032, 0.024, 0), m.emissive(Color(1.0, 0.28, 0.04), 3.4), Vector3(0.0, -0.14, 0.075), Vector3(90, 0, 0))
	MK.add(wrist, MK.slab(0.10, 0.045, 0.02, 0.004), m.armor_edge(), Vector3(0.0, 0.075, -0.04))
	for i in 3:
		MK.add(wrist, MK.slab(0.043, 0.032, 0.025, 0.004), m.armor_edge(), Vector3(-0.042 + i * 0.043, -0.115, -0.09))
	MK.add(wrist, MK.prism(8, 0.088, 0.082, 0.05, PI / 8.0), m.copper(), Vector3(0.0, 0.045, 0.0))
	MK.add(wrist, MK.slab(0.09, 0.075, 0.035, 0.006), m.paint(), Vector3(0.0, 0.01, -0.085))

	arms.append({
		"side": side, "shoulder": shoulder, "elbow": elbow, "wrist": wrist,
		"upper": UPPER, "fore": FORE,
	})


# ------------------------------------------------------------------- weapon
func _build_weapon() -> void:
	var m := PAL.for_palette(palette)
	weapon_root = Node3D.new()
	weapon_root.name = "Greatsword"
	weapon_root.position = Vector3(BASE_POSE["wpx"], BASE_POSE["wpy"], BASE_POSE["wpz"])
	weapon_root.rotation = Vector3(BASE_POSE["wrx"], BASE_POSE["wry"], BASE_POSE["wrz"])
	torso.add_child(weapon_root)
	weapon_spin = Node3D.new()
	weapon_spin.name = "BladeRoll"
	weapon_spin.rotation.y = 2.35
	weapon_root.add_child(weapon_spin)

	# [ACT PATCH] 无刀单位：只留握把位姿与刀锋标记，手臂 IK 照常解算
	if not has_weapon:
		blade_base = Marker3D.new()
		blade_base.position = Vector3(0, BLADE_Y0 + BLADE_LEN * 0.4, 0)
		weapon_spin.add_child(blade_base)
		blade_tip = Marker3D.new()
		blade_tip.position = Vector3(0, BLADE_Y0 + BLADE_LEN * 0.6, 0)
		weapon_spin.add_child(blade_tip)
		return

	# hilt: origin sits between the two fists
	MK.add(weapon_spin, MK.prism(8, 0.050, 0.055, 0.86, PI / 8.0), m.frame(), Vector3(0, -0.06, 0))
	for i in 3:
		MK.add(weapon_spin, MK.prism(12, 0.061, 0.061, 0.022, 0), m.copper(), Vector3(0, -0.36 + i * 0.16, 0))
	# grip sleeves around each fist
	for gy in [GRIP, -GRIP]:
		MK.add(weapon_spin, MK.prism(8, 0.052, 0.052, 0.19, PI / 8.0), m.rubber(), Vector3(0, gy, 0))
		MK.add(weapon_spin, MK.prism(12, 0.057, 0.057, 0.012, 0), m.emissive(Color(1.0, 0.28, 0.05), 1.6), Vector3(0, gy - 0.09, 0))
	# pommel counterweight
	MK.add(weapon_spin, MK.prism(6, 0.095, 0.045, 0.18, PI / 6.0), m.armor_shadow(), Vector3(0, -0.52, 0))
	MK.add(weapon_spin, MK.gem(0.055, 3, 6), m.emissive(Color(1.0, 0.3, 0.05), 3.2), Vector3(0, -0.62, 0))
	# crossguard: angular, forward-swept prongs
	MK.add(weapon_spin, MK.slab(0.38, 0.28, 0.15, 0.028), m.frame_light(), Vector3(0, 0.36, 0))
	MK.add(weapon_spin, MK.prism(10, 0.105, 0.105, 0.045, 0), m.emissive(Color(1.0, 0.30, 0.05), 3.4), Vector3(0, 0.37, -0.10), Vector3(90, 0, 0))
	for side in [-1.0, 1.0]:
		MK.add(weapon_spin, MK.beam_x(0.38, 0.09, 0.15, 0.032, 0.06), m.armor(),
			Vector3(0.02 * side, 0.40, 0), Vector3(0, -85 * side, 12 * side))
		MK.add(weapon_spin, MK.beam_x(0.24, 0.020, 0.05, 0.008, 0.02), m.emissive(Color(1.0, 0.28, 0.05), 2.6),
			Vector3(0.04 * side, 0.41, -0.005), Vector3(0, -85 * side, 12 * side))
		MK.add(weapon_spin, MK.prism(6, 0.075, 0.055, 0.05, 0), m.armor_edge(), Vector3(0.28 * side, 0.44, 0.0))
	# emitter assembly
	MK.add(weapon_spin, MK.prism(8, 0.115, 0.085, 0.11, PI / 8.0), m.armor_shadow(), Vector3(0, 0.44, 0))
	MK.add(weapon_spin, MK.prism(12, 0.085, 0.06, 0.055, 0), m.emissive(Color(1.0, 0.34, 0.06), 4.6), Vector3(0, 0.50, 0))
	MK.add(weapon_spin, MK.prism(8, 0.06, 0.05, 0.16, PI / 8.0), m.copper(), Vector3(0, 0.56, 0))

	# blade: 2.55 m of faceted plasma
	var blade_len := BLADE_LEN
	MK.add(weapon_spin, MK.blade(blade_len, 0.380, 0.105, 0.06, 20), m.blade_core(), Vector3(0, BLADE_Y0, 0))
	MK.add(weapon_spin, MK.blade(blade_len, 0.450, 0.15, 0.06, 20), m.blade_glow(), Vector3(0, BLADE_Y0, 0), Vector3.ZERO, Vector3(1.15, 1.0, 1.15), "BladeGlow1")
	MK.add(weapon_spin, MK.blade(blade_len * 0.99, 0.60, 0.27, 0.06, 16), m.blade_glow(), Vector3(0, BLADE_Y0 + 0.01, 0), Vector3.ZERO, Vector3(1.45, 1.0, 1.45), "BladeGlow2")
	# fuller line (thin hot blade inset)
	MK.add(weapon_spin, MK.blade(blade_len * 0.94, 0.085, 0.12, 0.06, 14), m.emissive(Color(1.0, 0.56, 0.20), 2.0), Vector3(0, BLADE_Y0 + 0.04, 0))

	blade_base = Marker3D.new()
	blade_base.position = Vector3(0, BLADE_Y0 + blade_len * 0.82, 0)
	weapon_spin.add_child(blade_base)
	blade_tip = Marker3D.new()
	blade_tip.position = Vector3(0, BLADE_Y0 + blade_len * 0.95, 0)
	weapon_spin.add_child(blade_tip)

	weapon_light = OmniLight3D.new()
	weapon_light.light_color = Color(1.0, 0.38, 0.10)
	weapon_light.light_energy = 1.4
	weapon_light.omni_range = 4.2
	weapon_light.shadow_enabled = false
	weapon_light.position = Vector3(0, 1.4, 0)
	weapon_spin.add_child(weapon_light)


# =============================================================== animation API
func request_light_attack() -> void:
	if jump_state != "GROUND":
		return
	if is_attacking and attack_name == "GUILLOTINE":
		return
	if is_attacking:
		if combo_step < 3 and _attack_queue.is_empty():
			_attack_queue.append(combo_step + 1)
		return
	combo_step = 1
	_begin_attack(ATTACK_LIGHT_1, false)


func request_heavy_attack() -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	combo_step = 0
	_begin_attack(ATTACK_HEAVY, true)


func request_spin_attack() -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	combo_step = 0
	_begin_attack(ATTACK_SPIN, true)


func request_dash() -> void:
	if jump_state != "GROUND" or _dash_cooldown > 0.0 or is_attacking:
		return
	_dash_dir = -global_transform.basis.z
	if move_command.length() > 0.1:
		_dash_dir = move_command.normalized()
	dash_time = dash_duration
	_dash_cooldown = dash_cd
	impact.emit(global_position + Vector3(0, 0.2, 0), 0.2)


func request_jump() -> void:
	if jump_state != "GROUND" or is_attacking or dash_time > 0.0:
		return
	jump_state = "TAKEOFF"
	jump_t = 0.0
	vertical_velocity = 0.0
	air_time = 0.0


func _advance_jump(dt: float) -> void:
	if jump_state == "GROUND":
		if position.y > ground_y + 0.02:
			jump_state = "AIR"
			vertical_velocity = 0.0
			air_time = 0.0
		elif position.y < ground_y:
			position.y = ground_y
	match jump_state:
		"TAKEOFF":
			jump_t += dt
			if jump_t >= takeoff_time:
				jump_state = "AIR"
				jump_t = 0.0
				vertical_velocity = jump_vel
				air_time = 0.0
				_fx.footstep(global_position, 0.45)
		"AIR":
			air_time += dt
			vertical_velocity -= grav * dt
			position.y += vertical_velocity * dt
			if position.y <= ground_y and vertical_velocity < 0.0:
				position.y = ground_y
				jump_state = "LANDING"
				jump_t = 0.0
				vertical_velocity = 0.0
				_fx.land(global_position, 1.0)
				impact.emit(global_position + Vector3(0, 0.12, 0), 0.75)
		"LANDING":
			jump_t += dt
			if jump_t >= land_time:
				jump_state = "GROUND"
				jump_t = 0.0


func _begin_attack(data: Dictionary, heavy: bool) -> void:
	_attack = data
	is_attacking = true
	attack_name = data["name"]
	attack_time = 0.0
	attack_elapsed = 0.0
	# [ACT PATCH] 时序来自参数表（前摇/判定/后摇/总时长），动画只提供姿势形状
	var ti := _timing_for(String(data["name"]))
	_warp_info = ti
	attack_total = float(ti["duration"])
	attack_hit_from = float(ti["windup"])
	attack_hit_to = float(ti["windup"]) + float(ti["active"])
	_lunge_prev = 0.0
	_shake_sent.clear()
	attack_started.emit(attack_name, heavy)
	var tw: Array = data.get("trail", [0.0, 1.0])
	if blade_trail != null:
		blade_trail.begin(self, blade_base, blade_tip, tw[0], tw[1])


func advance(dt: float) -> void:
	dt = clampf(dt, 0.0, 0.05)
	var start_pos := position
	time += dt
	last_dt = dt
	_dash_cooldown = maxf(0.0, _dash_cooldown - dt)
	_advance_jump(dt)
	# 刀位姿过渡规划：每帧采样一次，_current_pose 把结果写进刀位姿
	if blade_path != null and blade_path.active:
		_path_pose = blade_path.sample(dt)
	elif not _path_pose.is_empty():
		_path_pose = {}

	# ---------------- locomotion
	var moving := move_command.length() > 0.05
	var target_speed := move_command.length()
	if is_attacking:
		target_speed *= 0.10
		moving = false
	if dash_time > 0.0:
		target_speed = 0.0
		moving = false
	var accel := accel_rate if speed < target_speed else decel_rate
	speed = move_toward(speed, target_speed, accel * dt)
	if dash_time > 0.0:
		speed = 0.0

	if moving:
		var desired := move_command.normalized()
		var target_heading := atan2(-desired.x, -desired.z)
		if facing_override:
			target_heading = facing_heading
		var turn_speed := lerpf(turn_rate * 0.42, turn_rate, clampf(speed / RUN_SPEED, 0.0, 1.0))
		if facing_override:
			turn_speed = face_rate
		var before := heading
		heading = lerp_angle(heading, target_heading, 1.0 - exp(-turn_speed * dt))
		angular_velocity = wrapf(heading - before, -PI, PI) / maxf(dt, 0.0001)
	else:
		if facing_override:
			var before_f := heading
			heading = lerp_angle(heading, facing_heading, 1.0 - exp(-face_rate * dt))
			angular_velocity = wrapf(heading - before_f, -PI, PI) / maxf(dt, 0.0001)
		else:
			angular_velocity = lerpf(angular_velocity, 0.0, 1.0 - exp(-8.0 * dt))
	rotation.y = heading
	_yaw_rate = lerpf(_yaw_rate, angular_velocity, 1.0 - exp(-6.0 * dt))

	var forward := -global_transform.basis.z
	# [ACT PATCH] 位移沿「输入方向」，而不是沿朝向 —— 否则 A/D/S 全都变成往前走
	var vel := forward * speed
	if move_command.length() > 0.05 and not facing_override:
		vel = move_command.normalized() * speed
	elif move_command.length() > 0.05:
		# 朝向被外部接管（玩家朝相机 / 敌人朝玩家）时，位移仍然听输入
		vel = move_command.normalized() * speed
	if is_attacking and _attack.has("lunge"):
		var lunge := _eval_curve(_attack["lunge"], attack_time) * attack_lunge_scale
		var d := lunge - _lunge_prev
		_lunge_prev = lunge
		position += forward * d
		vel += forward * (d / maxf(dt, 0.0001))
	if dash_time > 0.0:
		var dash_t := 1.0 - dash_time / maxf(dash_duration, 0.01)
		# 原曲线整段积分为 9.923（单位速度·秒），按目标距离反算缩放
		var dash_speed := (18.0 * pow(1.0 - dash_t, 1.6) + 3.0) \
			* (dash_distance / maxf(9.923 * dash_duration, 0.001))
		_dash_dir = _dash_dir.slerp(forward, 1.0 - exp(-10.0 * dt)).normalized()
		# [ACT PATCH] 位移只能算一次（以前 position += 和 vel += 各算一遍 → 距离翻倍）；
		# 最后一步也不能越过 dash_duration，否则冲刺实际距离会比参数多出 1~2%。
		var dash_step := minf(dt, dash_time)
		position += _dash_dir * dash_speed * dash_step
		dash_time = maxf(0.0, dash_time - dash_step)
	if not is_attacking:
		position += vel * dt

	# [ACT PATCH] 原版是 15 m 圆形决斗台限制；这里改为竞技场矩形边界（0 = 不限制）
	if arena_bounds.x > 0.1 and arena_bounds.y > 0.1:
		position.x = clampf(position.x, -arena_bounds.x, arena_bounds.x)
		position.z = clampf(position.z, -arena_bounds.y, arena_bounds.y)

	# ---------------- gait clock
	var run_amt := clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	var freq := lerpf(1.45, 2.65, clampf(speed / RUN_SPEED, 0.0, 1.0))
	if speed > 0.08 and jump_state != "AIR" and jump_state != "LANDING":
		gait_phase = fmod(gait_phase + freq * dt, 1.0)
	locomotion_state = "IDLE"
	if speed > 0.4:
		locomotion_state = "WALK"
	if speed > WALK_SPEED:
		locomotion_state = "RUN"
	if speed > RUN_SPEED + 0.6:
		locomotion_state = "SPRINT"
	if is_attacking:
		locomotion_state = "STRIKE"
	if dash_time > 0.0:
		locomotion_state = "DASH"
	if jump_state == "TAKEOFF":
		locomotion_state = "JUMP"
	elif jump_state == "AIR":
		locomotion_state = "AIRBORNE"
	elif jump_state == "LANDING":
		locomotion_state = "LANDING"

	# ---------------- attack timeline
	if is_attacking:
		attack_elapsed += dt
		# [ACT PATCH] 把「参数化时间轴」映射回动画自己的相位，姿势不会错位
		attack_time = _warp_time(attack_elapsed)
		if not _attack_queue.is_empty() and attack_elapsed >= attack_total * 0.72:
			var nxt: int = _attack_queue.pop_front()
			combo_step = nxt
			var data: Dictionary = ATTACK_LIGHT_1 if nxt == 1 else (ATTACK_LIGHT_2 if nxt == 2 else ATTACK_HEAVY)
			_begin_attack(data, false)
		elif attack_elapsed >= attack_total:
			is_attacking = false
			attack_name = ""
			combo_step = 0
			_attack_queue.clear()
			_lunge_prev = 0.0

	# ---------------- body mechanics
	var lean_speed := clampf(speed / RUN_SPEED, 0.0, 1.2) * 0.19
	var bob_amp := lerpf(0.012, 0.055, run_amt) * clampf(speed / 1.2, 0.0, 1.0)
	var bob := sin((gait_phase * 2.0 + 0.13) * TAU) * bob_amp
	if speed < 0.4:
		bob = sin(time * 1.35) * 0.014
	if jump_state == "AIR" or jump_state == "LANDING":
		bob = 0.0
	var stance_count := 0
	for leg in legs:
		if leg["down"]:
			stance_count += 1
	if jump_state != "AIR" and jump_state != "LANDING":
		bob += (1.0 - clampf(stance_count / 4.0, 0.0, 1.0)) * lerpf(0.010, 0.035, run_amt)
	var bank := clampf(_yaw_rate * speed * 0.030, -0.28, 0.28)
	var sway := sin(gait_phase * TAU) * lerpf(0.006, 0.012, run_amt)

	var carry_target := smoothstep(0.0, 1.0, clampf((speed - 0.5) / 2.0, 0.0, 1.0))
	_carry_w = lerpf(_carry_w, carry_target, 1.0 - exp(-3.2 * dt))
	var pose := _current_pose(dt)
	var body_y := HIP_Y - float(pose["crouch"]) + bob
	if dash_time > 0.0:
		body_y -= 0.22
	body.position = Vector3(0, body_y, 0)
	body.rotation = Vector3(-(lean_speed + float(pose["lean"])), sway, bank)
	torso.rotation = Vector3(pose["tx"], pose["ty"], pose["tz"])
	head.rotation = Vector3(pose["hx"], pose["hy"], 0)
	_update_weapon(pose)
	_update_arms(pose)
	# [ACT PATCH] 记录刀在武器空间的扫掠变换（真实网格碰撞用）
	if weapon_spin != null:
		weapon_prev_xf = weapon_xf
		weapon_xf = weapon_spin.global_transform
		weapon_scale = weapon_spin.global_transform.basis.get_scale().x
	if contact_shadow != null:
		contact_shadow.position.y = 0.012 - position.y
		var hgt := maxf(position.y, 0.0)
		var sh_scale := 1.0 + hgt * 0.08
		contact_shadow.scale = Vector3(sh_scale, 1.0, sh_scale)
		contact_shadow.transparency = clampf(hgt * 0.12, 0.0, 0.55)

	# head look / idle life
	if not is_attacking:
		var look := clampf(_yaw_rate * 0.16, -0.22, 0.22)
		head.rotation.y = lerpf(head.rotation.y, look + sin(time * 0.7) * 0.035, 1.0 - exp(-4.0 * dt))
		head.rotation.x += sin(time * 0.9 + 1.0) * 0.012

	reactor_ring.rotation.y += dt * lerpf(0.25, 2.4, clampf(speed / RUN_SPEED, 0.0, 1.0))
	reactor_ring.rotation.x = sin(time * 0.6) * 0.05

	_update_legs(dt, run_amt)
	_update_trail(dt)
	_update_fx(dt)
	_fx.advance(dt)
	var moved := position.distance_to(start_pos)
	display_speed = lerpf(display_speed, moved / maxf(dt, 0.0001), 0.55)


func _current_pose(dt: float) -> Dictionary:
	var pose := BASE_POSE.duplicate()
	var breath := sin(time * 1.25)
	pose["tx"] = float(pose["tx"]) + breath * 0.012
	pose["wpx"] = float(pose["wpx"]) + sin(time * 0.8) * 0.008
	pose["wrx"] = float(pose["wrx"]) + sin(time * 1.05) * 0.018
	pose["wrz"] = float(pose["wrz"]) + sin(time * 0.9) * 0.012
	if _carry_w > 0.01 and not is_attacking:
		var w := clampf(_carry_w, 0.0, 1.0)
		# heavy blade trails out to the side while sprinting
		pose["wpx"] = lerpf(0.62, 0.54, w)
		pose["wpy"] = lerpf(0.32, 0.40, w) + sin(gait_phase * TAU) * 0.022 * w
		pose["wpz"] = lerpf(-0.95, -1.00, w)
		pose["wrx"] = lerpf(-0.05, 0.10, w)
		pose["wry"] = lerpf(0.0, -0.10, w)
		pose["wrz"] = lerpf(0.10, 0.02, w)
		pose["ty"] = float(pose["ty"]) + sin(gait_phase * TAU) * 0.05 * w
		pose["tx"] = float(pose["tx"]) + 0.05 * w
	if dash_time > 0.0:
		var t := 1.0 - dash_time / maxf(dash_duration, 0.01)
		pose["wrx"] = lerpf(-2.2, -1.8, sin(PI * t))
		pose["wpz"] = float(pose["wpz"]) - 0.10
	if jump_state == "TAKEOFF":
		var u := clampf(jump_t / maxf(takeoff_time, 0.001), 0.0, 1.0)
		var c := sin(PI * u)
		pose["crouch"] = float(pose["crouch"]) + 0.22 * c
		pose["tx"] = float(pose["tx"]) - 0.09 * c
		pose["wpy"] = float(pose["wpy"]) - 0.08 * c
		pose["wpz"] = float(pose["wpz"]) - 0.04 * c
	elif jump_state == "AIR":
		var fall := clampf(-vertical_velocity / 8.0, 0.0, 1.0)
		pose["crouch"] = -0.04
		pose["tx"] = 0.10 * clampf(vertical_velocity / 8.0, -1.0, 1.0)
		pose["ty"] = -0.06
		pose["hy"] = 0.02
		pose["wpx"] = 0.28
		pose["wpy"] = 0.40 + 0.03 * sin(air_time * 5.0)
		pose["wpz"] = -1.00
		pose["wrx"] = -1.22 + 0.20 * fall
		pose["wry"] = 0.06
		pose["wrz"] = 0.16
		pose["lean"] = 0.03
	elif jump_state == "LANDING":
		var u2 := clampf(jump_t / maxf(land_time, 0.001), 0.0, 1.0)
		var c2 := 1.0 - smoothstep(0.0, 1.0, u2)
		pose["crouch"] = float(pose["crouch"]) + 0.36 * c2
		pose["tx"] = float(pose["tx"]) - 0.30 * c2
		pose["lean"] = float(pose["lean"]) + 0.10 * c2
		pose["wpx"] = lerpf(0.28, 0.62, u2)
		pose["wpy"] = lerpf(0.40, 0.32, u2)
		pose["wpz"] = lerpf(-1.00, -0.95, u2)
		pose["wrx"] = lerpf(-1.22, -0.05, u2)
		pose["wry"] = lerpf(0.06, 0.0, u2)
		pose["wrz"] = lerpf(0.16, 0.10, u2)
	if is_attacking:
		var kp := _evaluate_keys(attack_time)
		for k in kp.keys():
			pose[k] = kp[k]
		_apply_attack_overrides(pose, attack_time, attack_elapsed)

	# [ACT PATCH] 弹反瞄准：把刀瞬间伸到来袭方向
	if aim_active:
		var ad := aim_dir
		ad.y = 0.0
		if ad.length_squared() < 0.01:
			ad = Vector3.FORWARD
		ad = ad.normalized()
		var ay: Vector3 = (ad + Vector3.UP * 0.10).normalized()
		var az: Vector3 = ay.cross(Vector3.UP)
		if az.length_squared() < 0.01:
			az = Vector3.FORWARD
		az = az.normalized()
		var ax: Vector3 = ay.cross(az).normalized()
		var ae := Basis(ax, ay, az).get_euler()
		pose["wrx"] = ae.x
		pose["wry"] = ae.y
		pose["wrz"] = ae.z
		var ah: Vector3 = ad * 0.55 + Vector3(0, 0.55, 0)
		pose["wpx"] = ah.x
		pose["wpy"] = ah.y
		pose["wpz"] = ah.z
		pose["ty"] = float(pose["ty"]) + atan2(ad.x, ad.z) * 0.25
		offhand = 0.35

	# [ACT PATCH] 第一人称手持位（只露刀的时候把它摆到画面右下、刀尖朝前）
	if fp_mode:
		for bm in blade_core_mats:
			if is_instance_valid(bm):
				bm.set_shader_parameter("energy", 1.5)
	elif blade_core_mats.size() > 0:
		for bm in blade_core_mats:
			if is_instance_valid(bm):
				bm.set_shader_parameter("energy", 4.2)
	if fp_mode and not is_attacking and guard < 0.01 and not aim_active:
		var fdir := Vector3(0.20, -0.22, -0.95).normalized()
		var fz: Vector3 = fdir.cross(Vector3.UP)
		if fz.length_squared() < 0.01:
			fz = Vector3.RIGHT
		fz = fz.normalized()
		var fx: Vector3 = fdir.cross(fz).normalized()
		var fe := Basis(fx, fdir, fz).get_euler()
		pose["wrx"] = fe.x
		pose["wry"] = fe.y
		pose["wrz"] = fe.z
		pose["wpx"] = 0.62
		pose["wpy"] = -0.42
		pose["wpz"] = -1.10
		pose["ty"] = float(pose["ty"]) + 0.06

	# [ACT PATCH] 举刀/格挡姿态混合
	if guard > 0.001:
		var g := clampf(guard, 0.0, 1.0)
		pose["wpx"] = lerpf(float(pose["wpx"]), 0.26, g)
		pose["wpy"] = lerpf(float(pose["wpy"]), 0.80, g)
		pose["wpz"] = lerpf(float(pose["wpz"]), -0.92, g)
		pose["wrx"] = lerpf(float(pose["wrx"]), -1.62, g)
		pose["wry"] = lerpf(float(pose["wry"]), 0.02, g)
		pose["wrz"] = lerpf(float(pose["wrz"]), 0.10, g)
		pose["ty"] = lerpf(float(pose["ty"]), 0.16, g)
		pose["tx"] = lerpf(float(pose["tx"]), -0.06, g)
		pose["crouch"] = float(pose["crouch"]) + 0.05 * g
	# [ACT PATCH] 弹反拦截：按规划好的位姿过渡走，手臂 IK 每帧跟到刀柄上
	if not _path_pose.is_empty():
		var pp: Vector3 = _path_pose["pos"]
		var pb: Basis = _path_pose["basis"]
		var pe := pb.get_euler()
		pose["wpx"] = pp.x
		pose["wpy"] = pp.y
		pose["wpz"] = pp.z
		pose["wrx"] = pe.x
		pose["wry"] = pe.y
		pose["wrz"] = pe.z
		pose["ty"] = _path_pose["yaw"]
		offhand = 0.0
	return pose


## 攻击时间轴上与「姿势关键帧」无关的修正（螺旋斩连续旋转 / 方向斩偏转 / 程序化挥砍）
func _apply_attack_overrides(pose: Dictionary, t: float, elapsed: float) -> void:
	# Helix Storm: the torso yaw must not ease to a stop at every key.
	# Use one continuous 360+ spin profile between the windup and the
	# recovery, matching the authored key values at both ends.
	if attack_name == "HELIX STORM" and t >= 0.22 and t <= 1.04:
		var su := clampf((t - 0.22) / 0.82, 0.0, 1.0)
		pose["ty"] = lerpf(-0.60, TAU - 0.35, _spin_progress(su))
	# [ACT PATCH] 方向斩：只转躯干（武器挂在躯干下，跟着一起转）
	# 注意：不能再单独旋转 wpx/wpz —— 那会把偏转应用两次（180° 变成 0°）
	if absf(attack_yaw) > 0.0001:
		pose["ty"] = float(pose["ty"]) + attack_yaw
	# [ACT PATCH] 程序化挥砍：方位角驱动，刀身水平平伸，够得着也更像样
	if proc_active:
		var w0 := attack_hit_from
		var span := maxf(attack_hit_to - attack_hit_from, 0.02)
		var u0: float = clampf((elapsed - w0) / span, 0.0, 1.0)
		var ease := u0 * u0 * (3.0 - 2.0 * u0)
		var ang: float = lerpf(proc_a0, proc_a1, ease)
		pose["ty"] = float(pose["ty"]) + ang * proc_torso
		var la: float = ang * (1.0 - proc_torso)
		var dir := Vector3(-sin(la), 0.0, -cos(la))
		var ydir: Vector3 = (dir * cos(proc_lift) + Vector3.UP * sin(proc_lift)).normalized()
		var zdir: Vector3 = ydir.cross(Vector3.UP)
		if zdir.length_squared() < 0.01:
			zdir = Vector3.FORWARD
		zdir = zdir.normalized()
		var xdir: Vector3 = ydir.cross(zdir).normalized()
		var eb := Basis(xdir, ydir, zdir).get_euler()
		pose["wrx"] = eb.x
		pose["wry"] = eb.y
		pose["wrz"] = eb.z
		var hilt: Vector3 = dir * proc_reach + ydir * (proc_thrust * ease) + Vector3(0, proc_h, 0)
		pose["wpx"] = hilt.x
		pose["wpy"] = hilt.y
		pose["wpz"] = hilt.z
		pose["tz"] = float(pose["tz"]) + proc_lean * sin(PI * u0) * (1.0 if proc_a1 > proc_a0 else -1.0)
		pose["hy"] = float(pose["hy"]) - ang * 0.25


func _evaluate_keys(t: float) -> Dictionary:
	var keys: Array = _attack["keys"]
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[0]
	for i in keys.size() - 1:
		if t >= float(keys[i]["t"]) and t <= float(keys[i + 1]["t"]):
			a = keys[i]
			b = keys[i + 1]
			break
	var span: float = maxf(float(b["t"]) - float(a["t"]), 0.0001)
	var u: float = clampf((t - float(a["t"])) / span, 0.0, 1.0)
	u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
	var out := {}
	var pa: Dictionary = BASE_POSE.duplicate()
	var pb: Dictionary = BASE_POSE.duplicate()
	pa.merge(a.get("p", {}), true)
	pb.merge(b.get("p", {}), true)
	for key in pa.keys():
		out[key] = lerpf(float(pa[key]), float(pb[key]), u)
	return out


func preview_weapon_pose(override: Dictionary) -> void:
	var pose := BASE_POSE.duplicate()
	for k in override.keys():
		pose[k] = override[k]
	torso.rotation = Vector3(float(pose["tx"]), float(pose["ty"]), float(pose["tz"]))
	_update_weapon(pose)
	_update_arms(pose)


func _update_weapon(pose: Dictionary) -> void:
	if weapon_root == null:
		return
	# hard clearance: the hilt must sit in front of the torso, otherwise the
	# pommel/guard can enter the chest at extreme attack angles.
	var wz := minf(float(pose["wpz"]), -0.88)
	weapon_root.position = Vector3(float(pose["wpx"]), float(pose["wpy"]), wz)
	weapon_root.rotation = Vector3(float(pose["wrx"]), float(pose["wry"]), float(pose["wrz"]))


func _update_arms(pose: Dictionary) -> void:
	if weapon_root == null or arms.size() < 2:
		return
	var hilt_y := weapon_root.basis.y.normalized()
	var hilt_x := weapon_spin.basis.x.normalized()
	var grip_r: Vector3 = weapon_root.transform * Vector3(0, GRIP, 0)
	var grip_l: Vector3 = weapon_root.transform * Vector3(0, -GRIP, 0)
	_solve_arm(arms[0], grip_r, hilt_y, hilt_x)
	var target_l := grip_l
	if offhand > 0.01:
		# 松左手：把手放到体侧待机位（单手持刀的观感）
		var rest: Vector3 = arms[1]["shoulder"].position + Vector3(-0.18, -1.05, 0.30)
		target_l = grip_l.lerp(rest, clampf(offhand, 0.0, 1.0))
	_solve_arm(arms[1], target_l, hilt_y, hilt_x)


func _solve_arm(arm: Dictionary, target: Vector3, hilt_y: Vector3, hilt_x: Vector3) -> void:
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
	var pole := Vector3(side * 1.0, -0.15, 0.72)
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
	var basis := Basis(x_axis, y_axis, z_axis)
	shoulder.basis = basis
	var ang := acos(clampf(up_dir.dot(fore_dir), -1.0, 1.0))
	elbow.rotation = Vector3(ang, 0.0, 0.0)
	# align the fist's grip axis (local Y) with the sword hilt
	var parent_basis := basis * elbow.transform.basis
	var hy := hilt_y.normalized()
	var hx := hilt_x - hy * hilt_x.dot(hy)
	if hx.length_squared() < 0.0001:
		hx = x_axis
	hx = hx.normalized()
	var hz := hx.cross(hy).normalized()
	hx = hy.cross(hz).normalized()
	var target_basis := Basis(hx, hy, hz)
	wrist.basis = parent_basis.inverse() * target_basis


# --------------------------------------------------------------------- legs
func _leg_phase_offset(index: int, run_amt: float) -> float:
	var wave := [0.0, 0.25, 0.5, 0.75]
	var trot := [0.0, 0.5, 0.0, 0.5]
	return lerpf(wave[index], trot[index], smoothstep(0.0, 1.0, run_amt))


func _update_legs(dt: float, run_amt: float) -> void:
	var duty := lerpf(0.68, 0.44, smoothstep(0.0, 1.0, run_amt))
	var freq := lerpf(1.45, 2.65, clampf(speed / RUN_SPEED, 0.0, 1.0))
	var stride := 0.0
	if speed > 0.08:
		stride = speed * duty / freq
	stride = minf(stride, 1.55)
	var lift_amt := lerpf(0.16, 0.52, smoothstep(0.0, 1.0, run_amt))
	var gait_w := clampf(speed / 1.6, 0.0, 1.0)
	var body_inv := body.transform.affine_inverse()

	for i in 4:
		var leg: Dictionary = legs[i]
		if jump_state == "AIR":
			var fall := clampf(-vertical_velocity / 8.0, 0.0, 1.0)
			var tuck := smoothstep(0.0, 0.22, air_time) * (1.0 - 0.88 * fall)
			var rr := lerpf(1.95, 1.05, tuck)
			var yy := lerpf(-2.0, -0.72, tuck)
			var wob := sin(air_time * 4.5 + i * 1.7) * 0.05 * tuck
			var az: float = float(leg["az"])
			var target_body := Vector3(cos(az) * (rr + wob), yy, sin(az) * (rr + wob))
			_solve_leg_ik(leg, target_body, dt, 0.28 + 0.16 * fall)
			leg["down"] = false
			leg["phase"] = 0.0
			continue
		var off := _leg_phase_offset(i, run_amt)
		var q := fmod(gait_phase + off, 1.0)
		var foot := Vector3(cos(leg["az"]) * FOOT_R, ANKLE_H, sin(leg["az"]) * FOOT_R)
		var down := true
		var lift := 0.0
		var radial := 0.0
		if speed > 0.08:
			if q < duty:
				var ts := q / duty
				var s := lerpf(stride * 0.5, -stride * 0.5, ts)
				foot.z -= s
			else:
				var ts := (q - duty) / (1.0 - duty)
				var s := lerpf(-stride * 0.5, stride * 0.5, smoothstep(0.0, 1.0, ts))
				s += sin(PI * ts) * lerpf(0.02, 0.10, run_amt)
				foot.z -= s
				lift = sin(PI * ts) * lift_amt
				radial = -sin(PI * ts) * lerpf(0.05, 0.16, run_amt)
				down = false
		if gait_w < 0.99:
			var idle_w := 1.0 - gait_w
			var ph := time * 0.55 + i * 1.7
			foot.x += cos(ph) * 0.012 * idle_w
			foot.z += sin(ph) * 0.012 * idle_w
		if dash_time > 0.0:
			var d := 1.0 - dash_time / maxf(dash_duration, 0.01)
			var tuck := sin(PI * clampf(d, 0.0, 1.0))
			foot.z += tuck * 0.28
			foot.x *= (1.0 - tuck * 0.10)
			lift = maxf(lift, tuck * 0.42)
			down = false
		var radial_dir := Vector3(cos(leg["az"]), 0, sin(leg["az"]))
		foot += radial_dir * radial
		foot.y = ANKLE_H + lift
		if down and not bool(leg["down"]) and speed > 0.4:
			var wp := global_transform * Vector3(foot.x, 0.02, foot.z)
			footstep.emit(wp, clampf(speed / RUN_SPEED, 0.2, 1.0))
			if i >= 2:
				_fx.footstep(wp, clampf(speed / RUN_SPEED, 0.2, 1.0) * 0.7)
		leg["down"] = down
		leg["phase"] = q
		leg["target"] = foot

		var target := body_inv * foot
		var foot_pitch := 0.0
		if not down:
			var ts := clampf((q - duty) / maxf(1.0 - duty, 0.001), 0.0, 1.0)
			foot_pitch = sin(PI * ts) * lerpf(0.10, 0.30, run_amt)
		_solve_leg_ik(leg, target, dt, foot_pitch)


func _solve_leg_ik(leg: Dictionary, target: Vector3, dt: float, foot_pitch: float) -> void:
	var hip_pos: Vector3 = leg["root"].position
	var v := target - hip_pos
	var d := Vector2(v.x, v.z).length()
	var h := v.y
	d = maxf(d, 0.05)
	var reach := sqrt(d * d + h * h)
	var max_reach := FEMUR + TIBIA - 0.015
	if reach > max_reach:
		var k := max_reach / reach
		d *= k
		h *= k
		reach = max_reach
	var base := atan2(h, d)
	var cos_a := (FEMUR * FEMUR + reach * reach - TIBIA * TIBIA) / (2.0 * FEMUR * reach)
	var aa := acos(clampf(cos_a, -1.0, 1.0))
	var femur_angle := base + aa
	var cos_b := (FEMUR * FEMUR + TIBIA * TIBIA - reach * reach) / (2.0 * FEMUR * TIBIA)
	var bb := acos(clampf(cos_b, -1.0, 1.0))
	var knee_angle := -(PI - bb)
	var yaw_angle: float = atan2(-v.z, v.x) + float(leg["az"])
	leg["yaw"].rotation.y = lerp_angle(leg["yaw"].rotation.y, yaw_angle, 1.0 - exp(-28.0 * dt))
	leg["hip"].rotation.z = femur_angle
	leg["knee"].rotation.z = knee_angle
	leg["ankle"].rotation.z = -(femur_angle + knee_angle) + foot_pitch
	leg["ankle"].rotation.x = clampf(_yaw_rate * 0.08, -0.12, 0.12)


func _update_trail(dt: float) -> void:
	if blade_trail == null:
		return
	var active := is_attacking
	var window: Array = [0.0, 999.0]
	if not _attack.is_empty():
		window = _attack.get("trail", [0.0, 999.0])
	var now_active: bool = active and attack_time >= float(window[0]) and attack_time <= float(window[1])
	if proc_active and active:
		now_active = attack_elapsed >= attack_hit_from and attack_elapsed <= attack_hit_to
	blade_trail.tick(dt, now_active)
	if now_active:
		blade_trail.add_sample(blade_base.global_position, blade_tip.global_position, Color(1.0, 0.36, 0.07, 1.0))


func _update_fx(dt: float) -> void:
	if not vfx_enabled:
		return
	if is_attacking and not _attack.is_empty():
		var hit_at: float = float(_attack.get("hit_at", -1.0))
		if hit_at >= 0.0 and attack_time >= hit_at and not _shake_sent.has("hit"):
			_shake_sent["hit"] = true
			var kind: String = String(_attack.get("hit_kind", "air"))
			var tip := blade_tip.global_position
			if kind == "ground":
				tip.y = 0.06
			var blade_dir := weapon_root.global_transform.basis.y.normalized()
			impact.emit(tip, 1.0)
			_fx.blade_hit(tip, blade_dir, kind, 1.0)
	if weapon_light != null:
		weapon_light.light_energy = 1.2 + 0.25 * sin(time * 8.0)
	if chest_light != null:
		chest_light.light_energy = 0.62 + 0.10 * sin(time * 3.2)


func reset_demo(pos: Vector3, new_heading: float) -> void:
	position = pos
	heading = new_heading
	rotation.y = new_heading
	speed = 0.0
	display_speed = 0.0
	move_command = Vector3.ZERO
	is_attacking = false
	attack_name = ""
	_attack = {}
	_attack_queue.clear()
	attack_time = 0.0
	combo_step = 0
	dash_time = 0.0
	_dash_cooldown = 0.0
	jump_state = "GROUND"
	jump_t = 0.0
	vertical_velocity = 0.0
	air_time = 0.0
	_carry_w = 0.0
	time = 0.0
	gait_phase = 0.0
	clear_blade_path()
	position.y = 0.0
	body.position = Vector3(0, HIP_Y, 0)
	body.rotation = Vector3.ZERO
	torso.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	var base := BASE_POSE.duplicate()
	_update_weapon(base)
	_update_arms(base)
	_update_legs(1.0 / 60.0, 0.0)
	if blade_trail != null:
		blade_trail.clear()
	if _fx != null:
		_fx.clear_effects()


func _spin_progress(u: float) -> float:
	# Trapezoidal angular velocity: smooth 24% ramps at both ends, constant
	# velocity through the middle.  This avoids the stop-start feel of easing
	# each authored key while keeping a lower peak speed than smootherstep.
	var r := 0.24
	var v := 1.0 / (1.0 - r)
	if u < r:
		var x := u / r
		return v * r * (x * x * x - 0.5 * x * x * x * x)
	elif u > 1.0 - r:
		var x := (1.0 - u) / r
		return 1.0 - v * r * (x * x * x - 0.5 * x * x * x * x)
	return v * r * 0.5 + v * (u - r)


func _eval_curve(curve: Array, t: float) -> float:
	if curve.is_empty():
		return 0.0
	if t <= float(curve[0][0]):
		return float(curve[0][1])
	for i in curve.size() - 1:
		if t >= float(curve[i][0]) and t <= float(curve[i + 1][0]):
			var u: float = (t - float(curve[i][0])) / maxf(float(curve[i + 1][0]) - float(curve[i][0]), 0.0001)
			u = u * u * (3.0 - 2.0 * u)
			return lerpf(float(curve[i][1]), float(curve[i + 1][1]), u)
	return float(curve[curve.size() - 1][1])


func get_diagnostics() -> Dictionary:
	return {
		"speed": speed,
		"state": locomotion_state,
		"attack": attack_name,
		"combo": combo_step,
		"gait": gait_phase,
		"heading": heading,
		"display_speed": display_speed,
	}


# ============================================ [ACT PATCH] 第一人称隐藏机身
func set_first_person_view(on: bool, show_weapon := false) -> void:
	var meshes: Array = []
	_collect_meshes(self, meshes)
	fp_mode = on
	if not on:
		visible = true
		for mi in meshes:
			if is_instance_valid(mi):
				mi.visible = true
		if head != null:
			head.visible = true
		return
	if show_weapon:
		# 只留刀：机身整体可见性不能关，只能逐个 mesh 关
		visible = true
		for mi in meshes:
			if not is_instance_valid(mi):
				continue
			var keep := weapon_spin != null and weapon_spin.is_ancestor_of(mi)
			if keep and String(mi.name).begins_with("BladeGlow"):
				keep = false      # 第一人称不画外层辉光，避免贴脸爆白
			mi.visible = keep
		if head != null:
			head.visible = false
	else:
		# 最稳：整台机甲隐藏（第一人称）
		visible = false


func _collect_meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		if c is Node3D:
			_collect_meshes(c, out)


# ================================================= [ACT PATCH] 直接发起指定动作
## 程序化单手横斩 / 反手后刺 / 弹反指向
func force_swing(a0: float, a1: float, opts := {}) -> void:
	var data: Dictionary = ATTACK_LIGHT_1
	attack_yaw = 0.0
	attack_lunge_scale = float(opts.get("lunge", 0.25))
	is_attacking = false
	_attack_queue.clear()
	clear_blade_path()
	_begin_attack(data, false)
	proc_active = true
	proc_a0 = a0
	proc_a1 = a1
	proc_reach = float(opts.get("reach", 0.62))
	proc_h = float(opts.get("height", 0.12))
	proc_lift = float(opts.get("lift", 0.12))
	proc_thrust = float(opts.get("thrust", 0.0))
	proc_torso = float(opts.get("torso", 0.55))
	proc_lean = float(opts.get("lean", 0.10))
	offhand = float(opts.get("offhand", 0.0))


func clear_proc() -> void:
	proc_active = false
	proc_thrust = 0.0
	offhand = 0.0
	aim_active = false


func aim_blade(local_dir: Vector3) -> void:
	aim_dir = local_dir
	aim_active = true


func clear_aim() -> void:
	aim_active = false


# ============================================ [ACT PATCH] 刀位姿过渡规划（弹反拦截）
## 刀身（护手 → 刀尖）在刀自身空间的 y 区间
func blade_span() -> Vector2:
	return Vector2(BLADE_Y0, BLADE_Y0 + BLADE_LEN)


## 受击判定件（[ACT PATCH]）：每帧用真实关节世界坐标拼出的多段胶囊。
##
## 单一「躯干大胶囊」会漏掉四条展开的腿、手臂和肩甲 —— 打腿等于打空气。
## 所以把机体拆成：骨盆 / 胸口 / 背包 / 头 / 肩甲×2 / 四条腿(股骨+胫骨+足) /
## 双臂(上臂+前臂+拳)。返回 [{a, b, r, label}]，世界坐标，r 已含机体缩放。
## 只做粗粒度包围，不追求网格级精确；每段都是关节到关节的胶囊。
func hit_parts() -> Array:
	var parts: Array = []
	if body == null:
		return parts
	var s := global_transform.basis.get_scale().x
	if s < 0.001:
		s = 1.0
	# 骨盆（腰环以下，四条腿的挂点都在这圈上）
	parts.append({"a": body.global_position - Vector3(0, 0.18 * s, 0),
		"b": body.global_position + Vector3(0, 0.20 * s, 0), "r": 0.56 * s, "label": "pelvis"})
	# 胸口 / 头 / 背包 / 肩甲：跟着腰环转
	if torso != null:
		parts.append({"a": torso.global_transform * Vector3(0, 0.12, 0),
			"b": torso.global_transform * Vector3(0, 0.60, 0), "r": 0.44 * s, "label": "chest"})
		parts.append({"a": torso.global_transform * Vector3(0, 0.30, 0.14),
			"b": torso.global_transform * Vector3(0, 0.34, 0.46), "r": 0.42 * s, "label": "pack"})
	if head != null:
		var hc: Vector3 = head.global_position
		var hs := head.global_transform.basis.get_scale().x
		parts.append({"a": hc, "b": hc + Vector3(0, 0.18 * hs, 0), "r": 0.22 * hs, "label": "head"})
	for p in pauldrons:
		if not is_instance_valid(p):
			continue
		var ps: float = p.global_transform.basis.get_scale().x
		parts.append({"a": p.global_position, "b": p.global_position + Vector3(0, 0.10 * ps, 0),
			"r": 0.30 * ps, "label": "pauldron"})
	# 四条腿：关节到关节（腿骨在世界里是斜着撑开的，所以必须跟着关节走）
	for leg in legs:
		var hip = leg.get("hip")
		var knee = leg.get("knee")
		var ankle = leg.get("ankle")
		if hip == null or knee == null or ankle == null:
			continue
		if not (is_instance_valid(hip) and is_instance_valid(knee) and is_instance_valid(ankle)):
			continue
		parts.append({"a": hip.global_position, "b": knee.global_position,
			"r": 0.30 * s, "label": "leg"})
		parts.append({"a": knee.global_position, "b": ankle.global_position,
			"r": 0.25 * s, "label": "leg"})
		var toe: Vector3 = ankle.global_position \
			+ ankle.global_transform.basis.x.normalized() * 0.34 * s
		parts.append({"a": ankle.global_position, "b": toe, "r": 0.24 * s, "label": "foot"})
	# 双臂：肩→肘→腕，最后给拳头一个球
	for arm in arms:
		var sh = arm.get("shoulder")
		var el = arm.get("elbow")
		var wr = arm.get("wrist")
		if sh == null or el == null or wr == null:
			continue
		if not (is_instance_valid(sh) and is_instance_valid(el) and is_instance_valid(wr)):
			continue
		parts.append({"a": sh.global_position, "b": el.global_position,
			"r": 0.24 * s, "label": "arm"})
		parts.append({"a": el.global_position, "b": wr.global_position,
			"r": 0.21 * s, "label": "arm"})
		parts.append({"a": wr.global_position, "b": wr.global_position,
			"r": 0.20 * s, "label": "hand"})
	return parts


func body_world() -> Transform3D:
	if body == null:
		return global_transform
	return global_transform * Transform3D(Basis.from_euler(body.rotation), body.position)


func torso_world(tx: float, ty: float, tz: float) -> Transform3D:
	var b := Basis.from_euler(Vector3(tx, ty, tz)).scaled(Vector3.ONE * TORSO_SCALE)
	return body_world() * Transform3D(b, Vector3(0.0, WAIST_Y, 0.0))


## 规划一次拦截：世界坐标里的落点 + 刀轴 + 刀面朝向 → 一条到该位姿的过渡路径。
##
## torso_turn = 腰环愿意为目标方位转多少（0 = 不转，1 = 完全转过去）：
## 剩下没转到的角度由手臂补上。刀柄沿刀轴滑动到离「舒适握把区」最近的位置，
## 所以同一套算法既能架正前的横斩，也能架侧面的横扫。
## deadline = 最晚多久内要把刀送到（秒），实际时长按刀柄要走的路程 / speed 反算。
func plan_blade_intercept(point: Vector3, axis: Vector3, face: Vector3,
		torso_turn: float, deadline: float, speed := 26.0) -> Dictionary:
	if weapon_root == null or blade_path == null:
		return {}
	if axis.length_squared() < 1e-6:
		return {}
	var up := axis.normalized()
	var body_xf := body_world()
	var rel: Vector3 = body_xf.basis.inverse() * (point - body_xf.origin)
	# 机体朝向是 -Z，所以「转到目标方位」用 atan2(-x, -z)（与 face_target 同一套）
	# 腰环能转很大角度（回旋斩就是整圈），所以到背后的刀也架得住
	var yaw := clampf(atan2(-rel.x, -rel.z) * clampf(torso_turn, 0.0, 1.0), -2.80, 2.80)
	var to_torso: Transform3D = torso_world(torso.rotation.x, yaw, torso.rotation.z).affine_inverse()
	var p: Vector3 = to_torso * point
	var u: Vector3 = (to_torso.basis * up).normalized()
	# 刀柄：刀身压住落点，同时沿刀轴滑动到离「舒适握把区」最近的位置。
	# 刀轴正反两个方向都试（同一个落点，刀柄可以在两头，所以刀身朝向也跟着翻），
	# 打分里带「离当前刀柄多远」的连续性项 —— 否则两个方向分数接近时会逐帧来回翻，
	# 刀就会左右横跳，永远停不到落点上。
	var anchor: Vector3 = SHOULDER_MID + Vector3(0.0, 0.0, -0.55)
	var span := blade_span()
	var here: Vector3 = weapon_root.position
	var hilt := Vector3.ZERO
	var t := 0.0
	var s_best := 1.0
	var best_score := 1e9
	for s in [1.0, -1.0]:
		var uv: Vector3 = u * s
		var tt := clampf((p - anchor).dot(uv), span.x, span.y * 0.96)
		var h: Vector3 = p - uv * tt
		var score := (h - anchor).length() + 0.45 * (h - here).length()
		if score < best_score:
			best_score = score
			t = tt
			hilt = h
			s_best = s
	# 关键：刀身必须沿「选中的那一头」伸出去（u 翻号时刀身朝向也要翻），
	# 否则刀柄在落点上方、刀却往上伸，落点其实没被刀身盖住。
	var ucu: Vector3 = u * s_best
	var fc: Vector3 = to_torso.basis * face
	fc -= ucu * fc.dot(ucu)
	if fc.length_squared() < 0.0001:
		fc = Vector3.UP.cross(ucu)
	if fc.length_squared() < 0.0001:
		fc = Vector3.RIGHT
	fc = fc.normalized()
	var xc: Vector3 = ucu.cross(fc).normalized()
	var spin_basis := Basis(xc, ucu, fc)
	hilt.x = clampf(hilt.x, -1.9, 1.9)
	hilt.y = clampf(hilt.y, -1.10, 1.90)
	hilt.z = minf(hilt.z, -0.90)
	var reach := hilt - SHOULDER_MID
	if reach.length() > 1.80:
		hilt = SHOULDER_MID + reach.normalized() * 1.80
	var root_basis := (spin_basis * spin_local.basis.inverse()).orthonormalized()
	# 时长 = 刀柄要走的路程 / 出刀速度，且不晚于 deadline
	var travel: float = weapon_root.position.distance_to(hilt) * weapon_scale
	var dur := clampf(travel / maxf(speed, 1.0), 0.03, maxf(deadline, 0.03))
	blade_path.plan(weapon_root.position, weapon_root.basis, hilt, root_basis, dur,
		torso.rotation.y, yaw)
	return {"hilt": hilt, "yaw": yaw, "t": t, "dur": dur, "travel": travel}


## 收势：规划一条「回到自然持刀位」的过渡
func plan_blade_return(dur: float) -> void:
	if weapon_root == null or blade_path == null:
		return
	var hilt := Vector3(float(BASE_POSE["wpx"]), float(BASE_POSE["wpy"]), float(BASE_POSE["wpz"]))
	var basis := Basis.from_euler(Vector3(float(BASE_POSE["wrx"]), float(BASE_POSE["wry"]),
		float(BASE_POSE["wrz"])))
	blade_path.plan(weapon_root.position, weapon_root.basis, hilt, basis, dur,
		torso.rotation.y, float(BASE_POSE["ty"]))


func clear_blade_path() -> void:
	if blade_path != null:
		blade_path.cancel()
	_path_pose = {}


func blade_path_active() -> bool:
	return blade_path != null and blade_path.active


## 读招：把这一刀的时间轴推到 elapsed，解出那一刻刀在世界里的位姿（只读，不动节点）。
##
## 姿势是闭式的（关键帧 + 方位角驱动），所以不用真的跑动画 ——
## 弹反可以在敌人的刀扫到身上之前，就把它未来几帧的刀路读出来。
func predict_weapon_xf(elapsed: float) -> Transform3D:
	if weapon_root == null or not is_attacking:
		return weapon_xf
	var t := _warp_time(elapsed)
	var pose := _evaluate_keys(t)
	_apply_attack_overrides(pose, t, elapsed)
	var wz := minf(float(pose["wpz"]), -0.88)
	var weapon := Transform3D(
		Basis.from_euler(Vector3(float(pose["wrx"]), float(pose["wry"]), float(pose["wrz"]))),
		Vector3(float(pose["wpx"]), float(pose["wpy"]), wz))
	var xf := torso_world(float(pose["tx"]), float(pose["ty"]), float(pose["tz"])) * weapon * spin_local
	# 前冲位移也要算进去（挥砍时整个机体在往前顶）
	if _attack.has("lunge"):
		var d: float = (_eval_curve(_attack["lunge"], t) - _eval_curve(_attack["lunge"], attack_time)) \
			* attack_lunge_scale
		xf.origin += (-global_transform.basis.z) * d
	return xf


func force_attack(clip: String, yaw_rad := 0.0, lunge_scale := 1.0) -> void:
	clear_proc()
	var data: Dictionary = ATTACK_LIGHT_1
	match clip:
		"fang":
			data = ATTACK_LIGHT_2
		"heavy":
			data = ATTACK_HEAVY
		"spin":
			data = ATTACK_SPIN
	attack_yaw = yaw_rad
	attack_lunge_scale = lunge_scale
	is_attacking = false
	_attack_queue.clear()
	clear_blade_path()
	_begin_attack(data, clip == "heavy" or clip == "spin")


# ===================================================== [ACT PATCH] 时序参数化
## 攻击时序参数表：默认按动画自身的相位推导，外部给了 timing 就完全听外部的
func _timing_for(clip_name: String) -> Dictionary:
	var key := timing_key if timing_key != "" else clip_name
	var d: Dictionary = timing.get(key, {})
	if d.is_empty():
		var ha := float(_attack.get("hit_at", 0.3))
		var dur := float(_attack.get("duration", 0.8))
		var tr: Array = _attack.get("trail", [0.0, 0.0])
		var act := dur * 0.18
		if tr.size() == 2 and float(tr[1]) > float(tr[0]):
			act = float(tr[1]) - float(tr[0])
		act = clampf(act, 0.05, maxf(0.06, dur - ha - 0.01))
		return {"duration": dur, "windup": ha, "active": act,
			"recovery": maxf(0.0, dur - ha - act)}
	return {
		"duration": maxf(0.10, float(d.get("duration", 0.8))),
		"windup": maxf(0.0, float(d.get("windup", 0.2))),
		"active": maxf(0.02, float(d.get("active", 0.2))),
		"recovery": maxf(0.0, float(d.get("recovery", 0.2))),
	}


## 参数化时间轴 -> 动画相位时间的三段映射
func _warp_time(elapsed: float) -> float:
	if _attack.is_empty() or _warp_info.is_empty():
		return elapsed
	var pb := _authored_phases()
	var ha: float = pb["start"]
	var act_a: float = pb["span"]
	var rec_a: float = pb["recovery"]
	var w := float(_warp_info["windup"])
	var a := maxf(0.02, float(_warp_info["active"]))
	var r := maxf(0.01, float(_warp_info["recovery"]))
	if elapsed < w:
		return (elapsed / maxf(w, 0.0001)) * ha
	if elapsed < w + a:
		return ha + ((elapsed - w) / a) * act_a
	return ha + act_a + ((elapsed - w - a) / r) * rec_a


## 动画自身的三段相位基准。判定/挥砍对应「刀真正在动的区间」：
## 优先用刀光窗口 trail（作者就是按它做拖尾的），没给就用 hit_at 前后各留一点。
func _authored_phases() -> Dictionary:
	var ha := float(_attack.get("hit_at", 0.3))
	var dur_a := float(_attack.get("duration", 0.8))
	var tr: Array = _attack.get("trail", [0.0, 0.0])
	var start := 0.0
	var span := 0.0
	if tr.size() == 2 and float(tr[1]) > float(tr[0]) + 0.02:
		start = float(tr[0])
		span = float(tr[1]) - float(tr[0])
	else:
		start = maxf(0.02, ha - 0.14)
		span = 0.22
	span = clampf(span, 0.06, maxf(0.08, dur_a - start - 0.01))
	var rec := maxf(0.01, dur_a - start - span)
	return {"start": start, "span": span, "recovery": rec}


## 当前是否处在「判定窗口」内（真实碰撞只在窗口内生效）
func in_hit_window() -> bool:
	return is_attacking and attack_elapsed >= attack_hit_from and attack_elapsed <= attack_hit_to


## 判定窗口的归一化进度（0→1），给特效/拖尾用
func hit_progress() -> float:
	var span := maxf(attack_hit_to - attack_hit_from, 0.0001)
	return clampf((attack_elapsed - attack_hit_from) / span, 0.0, 1.0)


func face_target(pos: Vector3) -> void:
	var d := pos - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	facing_override = true
	facing_heading = atan2(-d.x, -d.z)


func set_timings(d: Dictionary) -> void:
	timing = d


# ==================================================== [ACT PATCH] 刀的网格剖面
## 直接读建模出来的网格顶点，按 Y 分桶算出圆盘剖面 [{y, r}]（刀身/护手/柄都算）
func build_blade_discs(buckets := 30) -> Array:
	var pts: Array = []
	var ymin := INF
	var ymax := -INF
	for mi in weapon_meshes:
		var mesh: Mesh = mi.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var arrays := mesh.surface_get_arrays(0)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var xf: Transform3D = mi.transform
		for v in verts:
			var p: Vector3 = xf * v
			pts.append(p)
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
	if pts.is_empty():
		return []
	var out: Array = []
	var span := maxf(ymax - ymin, 0.001)
	for b in buckets:
		var y0 := ymin + span * float(b) / float(buckets)
		var y1 := ymin + span * float(b + 1) / float(buckets)
		var r := 0.0
		var found := false
		for p in pts:
			if p.y >= y0 and p.y <= y1:
				found = true
				r = maxf(r, Vector2(p.x, p.z).length())
		if found and r > 0.002:
			out.append({"y": (y0 + y1) * 0.5, "r": r})
	return out
