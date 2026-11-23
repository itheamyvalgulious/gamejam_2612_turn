extends Node3D
## SHARD // PHANTOM — modular teleporting enemy.
##
## Contract (README_kit.md): anim_names / play_anim / set_playing / is_playing /
## anim_time / set_anim_time / anim_duration / set_anim_speed / anim_speed /
## set_loop / is_looping / param_specs / set_param / get_param / joint_specs /
## set_joint / get_joint / rig_debug.
##
## State machine:
##   ASSEMBLED  <->  DISPERSING  ->  FLYING  ->  REFORMING  ->  ASSEMBLED
## `disperse_to(world_ground_target)` splits the body, flies the chunks to a
## cloud at the target and holds there; `reform()` converges them onto the body
## at the same target.  `disperse` / `reform` animation clips are scrubbable
## from the snapshot taken at trigger time (documented in README.md).

const RigScript := preload("res://scripts/phantom/phantom_rig.gd")
const FieldScript := preload("res://scripts/phantom/module_field.gd")
const ShurikenScript := preload("res://scripts/phantom/energy_shuriken.gd")
const PK := preload("res://scripts/phantom/phantom_kit.gd")
const MK := preload("res://scripts/kit/mesh_kit.gd")
const MAT := preload("res://scripts/kit/mat_lib.gd")
const PM := preload("res://scripts/phantom/phantom_materials.gd")
const ORB_SHADER := preload("res://shaders/charge_orb.gdshader")

const ANIMS := ["idle", "walk", "attack", "disperse", "reform"]
const IDLE_DUR := 6.0
const WALK_DUR := 2.8
const BODY_CENTER_H := 1.02
const STAGE_TOP := 0.047
# lowest point of the foot geometry below the design sole plane, measured by
# scripts/sole_audit.gd; the rig is lifted by this so hover_height is the real
# sole-to-stage gap.
const SOLE_DROP := 0.0288

var encounter_projectile := false
var encounter_target := Vector3.ZERO
var current_anim := "idle"
var _t := 0.0
var _playing := true
var _loop := true
var _speed := 1.0
var _wall := 0.0

var rig: PhantomRig
var field: ModuleField
var shurikens: Array = []
var wrist_light: OmniLight3D
var charge_orb: MeshInstance3D
var shadow: MeshInstance3D
var shadow_mat: ShaderMaterial
var ring_node: MeshInstance3D
var ring_mat: ShaderMaterial
var glow_node: MeshInstance3D
var hover_wash: SpotLight3D
var glow_mat: ShaderMaterial
var gaze_toggle: CheckBox
var status_label: Label
var overlay_layer: CanvasLayer
var overlay_panel: PanelContainer

var P := {
	# body
	"height": 1.60, "hover_height": 0.20, "shoulder_width": 0.52,
	"limb_girth": 1.0, "head_size": 1.08, "module_count": 90,
	"module_size": 0.10, "module_gap": 0.018, "frame_visibility": 0.70,
	# idle / walk
	"hover_bob": 0.011, "module_breath": 0.0030, "idle_head_turn": 1.0,
	"walk_stride": 1.0, "walk_speed": 1.20, "walk_lean": 0.0,
	# attack
	"raise_time": 0.26, "charge_time": 0.20, "fire_time": 0.16, "retract_time": 0.40,
	"attack_anticipation": 0.70, "attack_overshoot": 0.10,
	"shuriken_speed": 14.0, "shuriken_size": 0.15, "shuriken_spin": 480.0,
	"burst_count": 1.0, "shuriken_spread": 7.0,
	"aim_at_camera": 1.0,
	# swarm
	"spread_radius": 1.80, "fly_time": 0.75, "stagger": 0.26, "arc_height": 0.55,
	"spin_speed": 480.0, "reform_time": 0.65, "settle_overshoot": 0.06,
	"teleport_distance": 5.0,
	# fx
	"thruster_size": 0.011, "thruster_intensity": 1.0, "glow_intensity": 1.0,
	"hover_thrust_power": 1.0, "hover_glow": 1.0,
	"trail_life": 0.20,
	# gaze
	"gaze_reactive": 0.0, "gaze_distance": 9.0, "gaze_interval": 3.0,
}

var _specs: Array = []
var _home_xz := Vector2.ZERO
var _side_toggle := 1.0
var _frozen_pose: Dictionary = {}
var _last_pose: Dictionary = {}
var _resume_anim := "idle"
var _resume_t := 0.0
var _auto_reform_at := -1.0
var _auto_resume := false
var _resume_countdown := -1.0
var _pending_anim := ""
var _disp_dur := 1.6
var _ref_dur := 1.0
var _fast_swarm := false
var _gaze_next := 0.0
var _gaze_seen := false
var _swarm_retract := 0.0
var _muzzle := Transform3D.IDENTITY
var _shot_age := -1.0
var _muzzle_ok := false
var _charge := 0.0
var _orb_scale := 0.0
var _shot_flash := 0.0
var _manual := false


func _ready() -> void:
	_build_specs()
	_build_rig_and_field()
	_build_fx()
	_build_shurikens()
	if not encounter_projectile:
		_build_overlay()
	set_process_unhandled_input(not encounter_projectile)
	_apply_anim_pose(0.0)
	rig.set_frame_visibility(P["frame_visibility"])
	set_process(true)


func _rig_base_y() -> float:
	return P["hover_height"] + STAGE_TOP + SOLE_DROP


# ------------------------------------------------------------------- params

func _build_specs() -> void:
	_specs = [
		# BODY
		{"group": "BODY", "key": "height", "label": "height (m)", "min": 1.35, "max": 1.90, "step": 0.01},
		{"group": "BODY", "key": "hover_height", "label": "hover height", "min": 0.00, "max": 0.60, "step": 0.01},
		{"group": "BODY", "key": "shoulder_width", "label": "shoulder width", "min": 0.34, "max": 0.62, "step": 0.01},
		{"group": "BODY", "key": "limb_girth", "label": "limb girth", "min": 0.70, "max": 1.40, "step": 0.02},
		{"group": "BODY", "key": "head_size", "label": "head size", "min": 0.80, "max": 1.30, "step": 0.02},
		{"group": "BODY", "key": "module_count", "label": "module count", "min": 60, "max": 90, "step": 2},
		{"group": "BODY", "key": "module_size", "label": "module size (m)", "min": 0.04, "max": 0.16, "step": 0.005},
		{"group": "BODY", "key": "module_gap", "label": "module gap (m)", "min": 0.008, "max": 0.030, "step": 0.002},
		{"group": "BODY", "key": "frame_visibility", "label": "frame visibility", "min": 0.0, "max": 1.0, "step": 0.05},
		# IDLE / WALK
		{"group": "IDLE / WALK", "key": "hover_bob", "label": "hover bob", "min": 0.0, "max": 0.035, "step": 0.001},
		{"group": "IDLE / WALK", "key": "module_breath", "label": "module breath", "min": 0.0, "max": 0.010, "step": 0.0005},
		{"group": "IDLE / WALK", "key": "idle_head_turn", "label": "idle head turn", "min": 0.0, "max": 1.5, "step": 0.05},
		{"group": "IDLE / WALK", "key": "walk_stride", "label": "walk stride", "min": 0.3, "max": 2.0, "step": 0.05},
		{"group": "IDLE / WALK", "key": "walk_speed", "label": "walk glide (m/s)", "min": 0.4, "max": 2.6, "step": 0.05},
		{"group": "IDLE / WALK", "key": "walk_lean", "label": "walk lean", "min": -4.0, "max": 8.0, "step": 0.5},
		# ATTACK
		{"group": "ATTACK", "key": "raise_time", "label": "raise time", "min": 0.12, "max": 0.55, "step": 0.01},
		{"group": "ATTACK", "key": "charge_time", "label": "charge time", "min": 0.08, "max": 0.55, "step": 0.01},
		{"group": "ATTACK", "key": "fire_time", "label": "fire hold", "min": 0.05, "max": 0.45, "step": 0.01},
		{"group": "ATTACK", "key": "retract_time", "label": "retract time", "min": 0.15, "max": 0.75, "step": 0.01},
		{"group": "ATTACK", "key": "attack_anticipation", "label": "anticipation", "min": 0.0, "max": 1.0, "step": 0.05},
		{"group": "ATTACK", "key": "attack_overshoot", "label": "overshoot", "min": 0.0, "max": 0.3, "step": 0.01},
		{"group": "ATTACK", "key": "shuriken_speed", "label": "shuriken speed", "min": 4.0, "max": 30.0, "step": 0.5},
		{"group": "ATTACK", "key": "shuriken_size", "label": "shuriken size", "min": 0.08, "max": 0.30, "step": 0.01},
		{"group": "ATTACK", "key": "shuriken_spin", "label": "shuriken spin", "min": 300.0, "max": 1800.0, "step": 30.0},
		{"group": "ATTACK", "key": "burst_count", "label": "burst count", "min": 1, "max": 3, "step": 1},
		{"group": "ATTACK", "key": "aim_at_camera", "label": "aim at camera", "min": 0, "max": 1, "step": 1},
		{"group": "ATTACK", "key": "shuriken_spread", "label": "burst spread deg", "min": 0.0, "max": 24.0, "step": 1.0},
		# SWARM
		{"group": "SWARM", "key": "spread_radius", "label": "spread radius", "min": 1.0, "max": 2.8, "step": 0.05},
		{"group": "SWARM", "key": "fly_time", "label": "fly time", "min": 0.35, "max": 1.40, "step": 0.01},
		{"group": "SWARM", "key": "stagger", "label": "stagger", "min": 0.0, "max": 0.60, "step": 0.01},
		{"group": "SWARM", "key": "arc_height", "label": "arc height", "min": 0.0, "max": 1.40, "step": 0.02},
		{"group": "SWARM", "key": "spin_speed", "label": "chunk spin", "min": 60.0, "max": 900.0, "step": 10.0},
		{"group": "SWARM", "key": "reform_time", "label": "reform time", "min": 0.35, "max": 1.40, "step": 0.01},
		{"group": "SWARM", "key": "settle_overshoot", "label": "settle overshoot", "min": 0.0, "max": 0.20, "step": 0.005},
		{"group": "SWARM", "key": "teleport_distance", "label": "teleport dist", "min": 0.0, "max": 12.0, "step": 0.1},
		# FX
		{"group": "FX", "key": "hover_thrust_power", "label": "hover thrust", "min": 0.0, "max": 3.0, "step": 0.05},
		{"group": "FX", "key": "hover_glow", "label": "hover glow", "min": 0.0, "max": 3.0, "step": 0.05},
		{"group": "FX", "key": "thruster_size", "label": "thruster size", "min": 0.004, "max": 0.030, "step": 0.001},
		{"group": "FX", "key": "thruster_intensity", "label": "thruster power", "min": 0.0, "max": 3.0, "step": 0.05},
		{"group": "FX", "key": "glow_intensity", "label": "glow intensity", "min": 0.0, "max": 3.0, "step": 0.05},
		{"group": "FX", "key": "trail_life", "label": "trail life", "min": 0.04, "max": 0.50, "step": 0.01},
		# GAZE
		{"group": "GAZE", "key": "gaze_reactive", "label": "gaze reactive", "min": 0.0, "max": 1.0, "step": 1.0},
		{"group": "GAZE", "key": "gaze_distance", "label": "gaze distance", "min": 3.0, "max": 16.0, "step": 0.5},
		{"group": "GAZE", "key": "gaze_interval", "label": "gaze interval", "min": 0.5, "max": 8.0, "step": 0.1},
	]


func param_specs() -> Array:
	var out: Array = []
	for s in _specs:
		var d: Dictionary = s.duplicate()
		d["value"] = P[d["key"]]
		out.append(d)
	return out


func set_param(key: String, value: float) -> void:
	if not P.has(key):
		return
	var old: float = P[key]
	P[key] = value
	match key:
		"height", "shoulder_width", "limb_girth", "head_size":
			if absf(old - value) > 0.0001:
				_rebuild_rig()
				_rebuild_field()
		"module_count", "module_size", "module_gap":
			if absf(old - value) > 0.0001:
				_rebuild_field()
		"frame_visibility":
			rig.set_frame_visibility(value)
		"thruster_size", "thruster_intensity", "glow_intensity":
			_apply_fx_params()
		"gaze_reactive":
			if gaze_toggle:
				gaze_toggle.set_pressed_no_signal(value > 0.5)
	_update_overlay()


func get_param(key: String) -> float:
	return float(P.get(key, 0.0))


# --------------------------------------------------------------- construction

func _build_rig_and_field() -> void:
	rig = RigScript.new()
	rig.name = "Rig"
	add_child(rig)
	rig.module_size = P["module_size"]
	rig.module_gap = P["module_gap"]
	rig.build(P["height"], P["shoulder_width"], P["limb_girth"], P["head_size"])
	rig.apply_pose(_base_pose())
	rig.position = Vector3(_home_xz.x, _rig_base_y(), _home_xz.y)
	field = FieldScript.new()
	field.name = "Modules"
	add_child(field)
	field.build(rig, rig.slots, int(P["module_count"]))
	field.thruster_size = P["thruster_size"]
	field.set_thruster_intensity(P["thruster_intensity"])
	rig.set_thruster_intensity(P["thruster_intensity"])
	rig.set_hover_power(P["hover_thrust_power"])
	field.update_assembled(P["module_breath"], 0.0, 6.0)


func _rebuild_rig() -> void:
	var pose := rig.joint_values.duplicate()
	rig.module_size = P["module_size"]
	rig.module_gap = P["module_gap"]
	rig.build(P["height"], P["shoulder_width"], P["limb_girth"], P["head_size"])
	rig.set_frame_visibility(P["frame_visibility"])
	rig.apply_pose(pose)
	rig.position = Vector3(_home_xz.x, _rig_base_y(), _home_xz.y)
	_attach_hand_fx()
	if field:
		field.rig = rig
		field.state = FieldScript.State.ASSEMBLED


func _rebuild_field() -> void:
	if field == null:
		return
	rig.module_size = P["module_size"]
	rig.module_gap = P["module_gap"]
	rig.regenerate_slots()
	field.build(rig, rig.slots, int(P["module_count"]))
	field.thruster_size = P["thruster_size"]
	field.set_thruster_intensity(P["thruster_intensity"])
	rig.set_thruster_intensity(P["thruster_intensity"])
	rig.set_hover_power(P["hover_thrust_power"])
	field.update_assembled(P["module_breath"], _t, anim_duration())
	_swarm_retract = 0.0
	_auto_reform_at = -1.0
	_auto_resume = false


func _build_fx() -> void:
	# hover contact shadow
	shadow = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.05, 1.05)
	shadow.mesh = qm
	shadow_mat = PM.soft_shadow(0.85)
	shadow.material_override = shadow_mat
	shadow.rotation_degrees = Vector3(-90, 0, 0)
	shadow.position = Vector3(0, STAGE_TOP + 0.002, 0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	# assembly guide ring
	ring_node = MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(4.4, 4.4)
	ring_node.mesh = rq
	ring_mat = PM.assembly_ring()
	ring_node.material_override = ring_mat
	ring_node.rotation_degrees = Vector3(-90, 0, 0)
	ring_node.position = Vector3(0, STAGE_TOP + 0.012, 0)
	ring_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_node.visible = false
	add_child(ring_node)
	# ground glow
	glow_node = MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(1.8, 1.8)
	glow_node.mesh = gq
	glow_mat = PM.ground_glow()
	glow_node.material_override = glow_mat
	glow_node.rotation_degrees = Vector3(-90, 0, 0)
	glow_node.position = Vector3(0, STAGE_TOP + 0.006, 0)
	glow_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow_node)
	# warm downward wash from the hover jets: lights only the stage floor (layer 2)
	hover_wash = SpotLight3D.new()
	hover_wash.light_color = Color(1.0, 0.18, 0.03)
	hover_wash.light_energy = 0.0
	hover_wash.spot_range = 2.6
	hover_wash.spot_angle = 50.0
	hover_wash.spot_angle_attenuation = 1.0
	hover_wash.light_cull_mask = 2
	hover_wash.shadow_enabled = false
	hover_wash.rotation_degrees = Vector3(-90, 0, 0)
	hover_wash.position = Vector3(0, 0.70, 0)
	add_child(hover_wash)

	# palm charge orb + wrist light
	charge_orb = _new_charge_orb()
	_attach_hand_fx()


func _attach_hand_fx() -> void:
	var wr: Node3D = rig.joints.get("Wrist_R")
	if wr == null:
		return
	if charge_orb == null or not is_instance_valid(charge_orb):
		charge_orb = _new_charge_orb()
	if charge_orb.get_parent() != wr:
		if charge_orb.get_parent():
			charge_orb.get_parent().remove_child(charge_orb)
		wr.add_child(charge_orb)
	if wrist_light == null or not is_instance_valid(wrist_light):
		wrist_light = OmniLight3D.new()
		wrist_light.light_color = Color(1.0, 0.28, 0.06)
		wrist_light.light_energy = 0.0
		wrist_light.omni_range = 1.3
		wrist_light.shadow_enabled = false
		wrist_light.position = Vector3(0, -0.05, 0.09)
	if wrist_light.get_parent() != wr:
		if wrist_light.get_parent():
			wrist_light.get_parent().remove_child(wrist_light)
		wr.add_child(wrist_light)


func _new_charge_orb() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MK.sphere(0.045, 10, 16)
	var mat := ShaderMaterial.new()
	mat.shader = ORB_SHADER
	mat.set_shader_parameter("hot_color", Color(1.0, 0.92, 0.72))
	mat.set_shader_parameter("energy_color", Color(1.0, 0.22, 0.035))
	mat.set_shader_parameter("intensity", 2.6)
	mi.material_override = mat
	mi.position = Vector3(0, -0.050, 0.050)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * 0.001
	mi.visible = false
	return mi


func _build_shurikens() -> void:
	for i in 3:
		var s := ShurikenScript.new()
		s.name = "Shuriken%d" % i
		add_child(s)
		s.setup(float(i) * 3.7 + 1.3)
		var li := OmniLight3D.new()
		li.light_color = Color(1.0, 0.30, 0.05)
		li.light_energy = 0.8
		li.omni_range = 2.0
		li.shadow_enabled = false
		s.blade.add_child(li)
		shurikens.append(s)


func _apply_fx_params() -> void:
	if field:
		field.thruster_size = P["thruster_size"]
		field.set_thruster_intensity(P["thruster_intensity"])
	if rig:
		rig.set_thruster_intensity(P["thruster_intensity"])
		rig.set_hover_power(P["hover_thrust_power"])
		glow_mat.set_shader_parameter("intensity", 0.55 * P["glow_intensity"])
		ring_mat.set_shader_parameter("intensity", 1.15 * P["glow_intensity"])


# ------------------------------------------------------------------ contract

func anim_names() -> PackedStringArray:
	return PackedStringArray(ANIMS)


func play_anim(name: String) -> void:
	if not name in ANIMS:
		return
	_manual = false
	_pending_anim = ""
	if name == "disperse":
		_resume_anim = current_anim if current_anim in ["idle", "walk"] else "idle"
		_resume_t = _t
		_frozen_pose = _pose_for_anim(_resume_anim, _resume_t)
		_do_disperse(_target_local(_side_toggle), false, 0.0)
		_auto_resume = false
		_auto_reform_at = -1.0
		current_anim = "disperse"
		_loop = false
		_t = 0.0
		_playing = true
		field.eval_disperse(0.0)
		return
	if name == "reform":
		if field.state == FieldScript.State.ASSEMBLED:
			current_anim = "idle"
			_t = 0.0
			return
		_begin_reform(1.0, 0.0)
		_auto_resume = true
		current_anim = "reform"
		_loop = false
		_t = 0.0
		_playing = true
		return
	if not field.is_assembled():
		# attacking / walking while scattered: request reform first
		_pending_anim = name
		_begin_reform(1.0, 0.0)
		_auto_resume = true
		current_anim = "reform"
		_loop = false
		_t = 0.0
		_playing = true
		return
	current_anim = name
	_t = 0.0
	_playing = true
	_loop = name in ["idle", "walk"]
	_auto_reform_at = -1.0
	_auto_resume = false
	_hide_shurikens()
	if name == "attack":
		_muzzle_ok = false
		_shot_age = -1.0
	_apply_anim_pose(0.0)


func set_playing(v: bool) -> void:
	_playing = v


func is_playing() -> bool:
	return _playing


func anim_time() -> float:
	return _t


func set_anim_time(t: float) -> void:
	var d := anim_duration()
	_t = clampf(t, 0.0, d)
	_manual = false
	_hide_shurikens()
	_shot_age = -1.0
	match current_anim:
		"disperse":
			if field.state == FieldScript.State.ASSEMBLED:
				_resume_anim = "idle"
				_resume_t = 0.0
				_frozen_pose = _pose_for_anim("idle", 0.0)
				_do_disperse(_target_local(_side_toggle), false, 0.0)
				current_anim = "disperse"
			field.eval_disperse(_t)
		"reform":
			if field.state != FieldScript.State.REFORMING and field.state != FieldScript.State.ASSEMBLED:
				_begin_reform(1.0, 0.0)
			if field.state == FieldScript.State.REFORMING:
				field.eval_reform(_t)
		"attack":
			_shot_age = _t - _attack_moments()[2]
			_apply_anim_pose(_t)
		_:
			_apply_anim_pose(_t)


func anim_duration() -> float:
	match current_anim:
		"idle": return IDLE_DUR
		"walk": return maxf(WALK_DUR * 1.2 / maxf(P["walk_speed"], 0.1), 0.6)
		"attack": return _attack_total()
		"disperse": return _disp_dur
		"reform": return _ref_dur
	return 1.0


func set_anim_speed(v: float) -> void:
	_speed = clampf(v, 0.02, 8.0)


func anim_speed() -> float:
	return _speed


func set_loop(v: bool) -> void:
	_loop = v


func is_looping() -> bool:
	return _loop


func joint_specs() -> Array:
	return rig.joint_specs() if rig else []


func set_joint(key: String, v: float) -> void:
	_manual = true
	_playing = false
	rig.set_joint(key, v)


func get_joint(key: String) -> float:
	return rig.get_joint(key) if rig else 0.0


# --------------------------------------------------------------- module swarm

func _disperse_params(fast: bool) -> Dictionary:
	var k := 0.55 if fast else 1.0
	return {
		"fly": P["fly_time"] * k, "stagger": P["stagger"] * k,
		"spread": P["spread_radius"] * (0.7 if fast else 1.0),
		"arc": P["arc_height"] * k, "spin": P["spin_speed"],
		"reform": P["reform_time"] * k,
	}


func _do_disperse(target_local: Vector3, fast: bool, hold: float) -> void:
	var old_home := _home_xz
	_fast_swarm = fast
	var dp := _disperse_params(fast)
	_disp_dur = dp["stagger"] + dp["fly"] * 1.16 + 0.45
	_ref_dur = dp["reform"] * 1.1 + 0.33
	var center_local := Vector3(target_local.x, BODY_CENTER_H * rig.height_scale + _rig_base_y(), target_local.z)
	var center_world := global_transform * center_local
	# 1. snapshot the current (old-position) module transforms, start the burst
	field.begin_disperse(center_world, dp["spread"], dp["fly"], dp["stagger"],
		dp["arc"], dp["spin"])
	# 2. move the whole rig to the destination so reform targets are correct
	_home_xz = Vector2(target_local.x, target_local.z)
	rig.position = Vector3(_home_xz.x, _rig_base_y(), _home_xz.y)
	field.set_disperse_params(center_world, dp["spread"], dp["fly"], dp["stagger"],
		dp["arc"], dp["spin"])
	_swarm_retract = 0.0
	_reframe_studio(old_home, Vector2(target_local.x, target_local.z))
	if hold > 0.0:
		_auto_reform_at = _wall + _disp_dur + hold
	else:
		_auto_reform_at = -1.0


## The studio camera is not a follow cam; when the enemy blinks several metres
## the view is widened once so both ends stay framed.  Skipped in shot mode.
func _reframe_studio(old_home: Vector2, new_home: Vector2) -> void:
	var par := get_parent()
	if par == null or not par.has_method("set_view"):
		return
	if par.get("_shot_mode") == true:
		return
	var d := old_home.distance_to(new_home)
	if d < 1.6:
		return
	var mid := (old_home + new_home) * 0.5
	var yaw: float = float(par.get("_yaw"))
	var pitch: float = float(par.get("_pitch"))
	var dist: float = float(par.get("_dist"))
	par.set_view(yaw, maxf(pitch, 5.0), maxf(dist, 3.4 + d), Vector3(mid.x, 0.95, mid.y))


func _target_local(side: float) -> Vector3:
	var d: float = P["teleport_distance"]
	if d < 0.05:
		return Vector3(_home_xz.x, 0, _home_xz.y)
	var dirx := 1.0
	if _home_xz.x > 0.25:
		dirx = -1.0
	elif _home_xz.x < -0.25:
		dirx = 1.0
	else:
		dirx = side
	return Vector3(_home_xz.x + dirx * d, 0, _home_xz.y)


func disperse_to(target: Vector3) -> void:
	var local := global_transform.affine_inverse() * target
	_resume_anim = current_anim if current_anim in ["idle", "walk"] else "idle"
	_resume_t = _t
	_frozen_pose = _pose_for_anim(_resume_anim, _resume_t)
	_do_disperse(Vector3(local.x, 0, local.z), false, 0.0)
	current_anim = "disperse"
	_t = 0.0
	field.eval_disperse(0.0)


func rebase_encounter() -> void:
	var body := rig.global_position
	global_position = Vector3(body.x, global_position.y, body.z)
	_home_xz = Vector2.ZERO
	_apply_rig_placement()


func reform() -> void:
	if field.state == FieldScript.State.ASSEMBLED:
		return
	_begin_reform(1.0, 0.0)
	current_anim = "reform"
	_t = 0.0
	_playing = true
	_auto_resume = true


func _begin_reform(scale: float, hold: float) -> void:
	var dp := _disperse_params(_fast_swarm)
	_ref_dur = dp["reform"] * 1.1 * scale + 0.33
	field.begin_reform(dp["reform"] * scale, P["settle_overshoot"])
	if _frozen_pose.is_empty():
		_frozen_pose = _pose_for_anim(_resume_anim, _resume_t)
	rig.apply_pose(_frozen_pose)
	rig.position = Vector3(_home_xz.x, _rig_base_y(), _home_xz.y)
	_auto_reform_at = -1.0
	_resume_countdown = -1.0


func is_assembled() -> bool:
	return field != null and field.is_assembled()


func blink() -> void:
	if not _can_swarm():
		return
	_resume_anim = current_anim if current_anim in ["idle", "walk"] else "idle"
	_resume_t = _t
	_frozen_pose = _pose_for_anim(_resume_anim, _resume_t)
	_do_disperse(_target_local(_side_toggle), true, 0.22)
	current_anim = "disperse"
	_t = 0.0
	_playing = true
	_auto_resume = true
	_side_toggle *= -1.0


func _button_disperse() -> void:
	if not _can_swarm():
		return
	_resume_anim = current_anim if current_anim in ["idle", "walk"] else "idle"
	_resume_t = _t
	_frozen_pose = _pose_for_anim(_resume_anim, _resume_t)
	_do_disperse(_target_local(_side_toggle), false, 1.0)
	current_anim = "disperse"
	_t = 0.0
	_playing = true
	_auto_resume = true
	_side_toggle *= -1.0


func _can_swarm() -> bool:
	return field != null and field.is_assembled()


# ------------------------------------------------------------------ animation

func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	_wall += dt
	if _playing:
		var d := anim_duration()
		var nt := _t + dt * _speed
		var loops := _loop and current_anim in ["idle", "walk"] and d > 0.0
		if loops:
			_t = fmod(nt, d)
		else:
			nt = minf(nt, d)
			if nt != _t:
				_t = nt
				if current_anim == "disperse":
					field.eval_disperse(_t)
				elif current_anim == "reform":
					field.eval_reform(_t)
	# auto reform (button / blink / gaze sequences)
	if _auto_reform_at > 0.0 and _wall >= _auto_reform_at:
		_auto_reform_at = -1.0
		if field.state == FieldScript.State.DISPERSING or field.state == FieldScript.State.FLYING:
			reform()
	# resume idle after reform
	if field.state == FieldScript.State.ASSEMBLED and current_anim == "reform":
		if _resume_countdown < 0.0 and _playing:
			_resume_countdown = 0.22
		if _resume_countdown > 0.0:
			_resume_countdown -= dt
			if _resume_countdown <= 0.0:
				_resume_countdown = -1.0
				_auto_resume = false
				current_anim = _resume_anim
				_t = _resume_t
				_playing = true
				_loop = true
				if _pending_anim != "":
					var pn := _pending_anim
					_pending_anim = ""
					play_anim(pn)
	# place the rig before driving joints/modules so a scrub has no frame lag
	_apply_rig_placement()
	# pose + modules
	if field.state == FieldScript.State.ASSEMBLED:
		if _manual:
			rig.set_frame_visibility(P["frame_visibility"])
		else:
			_apply_anim_pose(_t)
		field.update_assembled(P["module_breath"], _t, anim_duration())
	else:
		if _frozen_pose.is_empty():
			_frozen_pose = _pose_for_anim(_resume_anim, _resume_t)
		rig.apply_pose(_frozen_pose)
		rig.position = Vector3(_home_xz.x, _rig_base_y(), _home_xz.y)
	_update_retract(dt)
	# projectile clock: follows the anim clock inside the clip, keeps flying
	# in world space for its full life once the clip has clamped at its end.
	if current_anim == "attack" and field.is_assembled():
		var m := _attack_moments()
		var fire: float = m[2]
		var d: float = m[4]
		if _playing and _t >= d - 0.0001 and d > 0.0 and _shot_age >= 0.0:
			_shot_age += dt * _speed
		elif _playing or _shot_age < 0.0:
			_shot_age = _t - fire
	if not encounter_projectile:
		_update_shurikens()
	_update_swarm_fx(dt)
	_update_charge(dt)
	_update_gaze(dt)
	_update_overlay()
	_update_auto_sequence()


func _apply_rig_placement() -> void:
	# hover + bob + glide timing (modules are driven separately)
	var y: float = _rig_base_y()
	if field.state == FieldScript.State.ASSEMBLED:
		if current_anim == "idle":
			var ph := TAU * _t / IDLE_DUR
			y += P["hover_bob"] * (sin(ph) * 0.8 + sin(ph * 2.0 + 1.1) * 0.2)
		elif current_anim == "walk":
			var ph := TAU * _t / anim_duration()
			y += 0.012 + P["hover_bob"] * 0.55 * sin(ph * 2.0 + 0.6)
		elif current_anim == "attack":
			y += P["hover_bob"] * 0.25 * sin(TAU * _t * 1.7)
	rig.position = Vector3(_home_xz.x, y, _home_xz.y)


func _pose_for_anim(name: String, t: float) -> Dictionary:
	match name:
		"walk": return _pose_walk(t)
		"attack": return _pose_attack(t)
		"disperse", "reform": return _frozen_pose if not _frozen_pose.is_empty() else _base_pose()
	return _pose_idle(t)


func _apply_anim_pose(t: float) -> void:
	var p := _pose_for_anim(current_anim, t)
	_last_pose = p
	rig.apply_pose(p)


func _base_pose() -> Dictionary:
	return {
		"pelvis_pitch": 1.5, "pelvis_yaw": 0.0, "pelvis_roll": 0.0, "pelvis_height": 0.0,
		"spine_pitch": 1.0, "spine_yaw": 0.0, "spine_roll": 0.0,
		"chest_pitch": -0.8, "chest_yaw": 0.0, "chest_roll": 0.0,
		"neck_pitch": 1.0, "neck_yaw": 0.0,
		"head_pitch": 0.0, "head_yaw": 0.0, "head_roll": 0.0,
		"shoulder_L_pitch": 31.4, "shoulder_L_yaw": 13.4, "shoulder_L_roll": 13.2,
		"elbow_L_pitch": 22.8, "elbow_L_roll": -91.6,
		"wrist_L_pitch": 4.0, "wrist_L_yaw": 174.0, "wrist_L_roll": 0.0, "finger_L_curl": 30.0,
		"shoulder_R_pitch": 31.4, "shoulder_R_yaw": -13.4, "shoulder_R_roll": -13.2,
		"elbow_R_pitch": 22.8, "elbow_R_roll": 91.6,
		"wrist_R_pitch": 4.0, "wrist_R_yaw": -174.0, "wrist_R_roll": 0.0, "finger_R_curl": 30.0,
		"hip_L_pitch": -2.0, "hip_L_yaw": 3.0, "hip_L_roll": 4.5,
		"knee_L_pitch": 8.0, "ankle_L_pitch": -4.0, "toe_L_pitch": 6.0,
		"hip_R_pitch": -2.0, "hip_R_yaw": -3.0, "hip_R_roll": -4.5,
		"knee_R_pitch": 8.0, "ankle_R_pitch": -4.0, "toe_R_pitch": 6.0,
	}


func _servo(t: float, keys: Array) -> float:
	# keys: [[time, value], ...] over one loop
	var n := keys.size()
	for i in n - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t >= a[0] and t < b[0]:
			var u: float = (t - a[0]) / maxf(b[0] - a[0], 0.001)
			var e := smoothstep(0.0, 1.0, u)
			# tiny mechanical settle at the end of each move
			e = e - 0.06 * sin(PI * e) * (1.0 - e)
			return lerpf(a[1], b[1], e)
	return keys[n - 1][1]


func _pose_idle(t: float) -> Dictionary:
	var p := _base_pose()
	var ph := TAU * t / IDLE_DUR
	p["pelvis_pitch"] += 0.7 * sin(ph + 0.4)
	p["pelvis_roll"] += 0.5 * sin(ph + 0.2)
	p["spine_pitch"] += 0.55 * sin(ph + 1.1)
	p["chest_pitch"] += 0.45 * sin(ph + 1.7)
	p["chest_yaw"] += 0.6 * sin(ph + 0.9)
	p["neck_pitch"] += 0.5 * sin(ph + 2.2)
	var keys := [
		[0.0, 0.0], [1.35, 0.0], [1.62, -9.0], [3.05, -9.0],
		[3.32, 5.5], [4.55, 5.5], [4.95, 0.0], [6.0, 0.0],
	]
	var look := 0.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		var dv := global_transform.basis.inverse() * (cam.global_position - rig.chest_center())
		look = clampf(rad_to_deg(atan2(dv.x, dv.z)), -32.0, 32.0)
	p["head_yaw"] += _servo(t, keys) * P["idle_head_turn"] * 0.55 + look * 0.60
	p["neck_yaw"] += look * 0.18
	p["head_pitch"] += 1.1 * sin(ph + 1.2) - 1.6 * absf(_servo(t, keys)) / 9.0 * P["idle_head_turn"]
	p["head_roll"] += 0.7 * sin(ph + 0.6)
	p["shoulder_L_pitch"] += 1.1 * sin(ph + 1.9)
	p["shoulder_R_pitch"] += 1.1 * sin(ph + 2.2)
	p["elbow_L_pitch"] += 1.3 * sin(ph + 2.4)
	p["elbow_R_pitch"] += 1.3 * sin(ph + 2.6)
	p["finger_L_curl"] += 3.0 * sin(ph + 0.8)
	p["finger_R_curl"] += 3.0 * sin(ph + 1.0)
	p["hip_L_pitch"] += 0.4 * sin(ph + 0.5)
	p["hip_R_pitch"] += 0.4 * sin(ph + 0.5)
	p["knee_L_pitch"] += 0.7 * sin(ph + 1.0)
	p["knee_R_pitch"] += 0.7 * sin(ph + 1.0)
	p["ankle_L_pitch"] += 0.6 * sin(ph + 2.0)
	p["ankle_R_pitch"] += 0.6 * sin(ph + 2.0)
	return p


func _pose_walk(t: float) -> Dictionary:
	var p := _base_pose()
	var dur := anim_duration()
	var ph := TAU * t / dur
	var st: float = P["walk_stride"]
	var sL := sin(ph)
	var sR := sin(ph + PI)
	p["pelvis_pitch"] = P["walk_lean"] * 0.5
	p["spine_pitch"] = 0.6
	p["chest_pitch"] = -0.6
	p["pelvis_yaw"] += 4.0 * sin(ph)
	p["chest_yaw"] += -2.4 * sin(ph)
	p["spine_roll"] += 1.6 * sin(ph + 0.4)
	p["pelvis_roll"] += 2.0 * sin(ph + 0.4)
	p["head_yaw"] += 1.8 * sin(ph + 0.9)
	p["head_pitch"] += 1.2 * sin(ph * 2.0 + 0.3)
	p["head_roll"] += -1.2 * sin(ph + 0.4)
	p["hip_L_pitch"] += -14.0 * sL * st
	p["hip_R_pitch"] += -14.0 * sR * st
	p["knee_L_pitch"] += (10.0 + 15.0 * maxf(0.0, sin(ph + 1.4))) * st
	p["knee_R_pitch"] += (10.0 + 15.0 * maxf(0.0, sin(ph + PI + 1.4))) * st
	p["ankle_L_pitch"] += -7.0 * sL * st - 4.0 * maxf(0.0, sin(ph + 1.4)) * st
	p["ankle_R_pitch"] += -7.0 * sR * st - 4.0 * maxf(0.0, sin(ph + PI + 1.4)) * st
	p["toe_L_pitch"] += 6.0 + 5.0 * maxf(0.0, -sL) * st
	p["toe_R_pitch"] += 6.0 + 5.0 * maxf(0.0, -sR) * st
	p["hip_L_yaw"] += 2.0 * sin(ph + 0.4)
	p["hip_R_yaw"] += 2.0 * sin(ph + PI + 0.4)
	p["hip_L_roll"] += 1.5 * maxf(0.0, sL)
	p["hip_R_roll"] += -1.5 * maxf(0.0, sR)
	p["shoulder_L_pitch"] += 2.0 * sin(ph + 0.2)
	p["shoulder_R_pitch"] += 2.0 * sin(ph + 0.6)
	p["elbow_L_pitch"] += 1.5 * sin(ph + 0.9)
	p["elbow_R_pitch"] += 1.5 * sin(ph + 1.1)
	return p


# --------------------------------------------------------------- attack math

func _attack_moments() -> Array:
	var t0 := 0.0
	var t1: float = P["raise_time"]
	var t2: float = t1 + P["charge_time"]
	var t3: float = t2 + P["fire_time"]
	var t4: float = t3 + P["retract_time"]
	return [t0, t1, t2, t3, t4]


func _attack_total() -> float:
	var m := _attack_moments()
	return m[4]


func _aim_dir_local() -> Vector3:
	var sh: Vector3 = rig.joints["Shoulder_R"].global_position
	var cam := get_viewport().get_camera_3d()
	var d: Vector3
	if encounter_projectile:
		d = encounter_target - sh
	elif cam and P["aim_at_camera"] > 0.5:
		d = cam.global_position - sh
	elif cam:
		d = global_transform.basis * Vector3(0.10, 0.03, 1.0)
	else:
		d = global_transform.basis * Vector3(0, 0.05, 1)
	var local := global_transform.basis.inverse() * d
	local.y = clampf(local.y, -0.28, 0.30)
	if local.length_squared() < 1e-4:
		local = Vector3(0, 0, 1)
	return local.normalized()


func _arm_to_dir(p: Dictionary, d: Vector3, tag: String) -> void:
	var rz := rad_to_deg(asin(clampf(d.x, -1.0, 1.0)))
	var rx := rad_to_deg(atan2(-d.z, -d.y))
	p["shoulder_%s_pitch" % tag] = rx
	p["shoulder_%s_yaw" % tag] = 0.0
	p["shoulder_%s_roll" % tag] = rz
	p["elbow_%s_pitch" % tag] = 3.0
	p["elbow_%s_roll" % tag] = 0.0
	p["wrist_%s_pitch" % tag] = 90.0
	p["wrist_%s_yaw" % tag] = 0.0
	p["wrist_%s_roll" % tag] = 0.0
	p["finger_%s_curl" % tag] = 8.0


func _blend_dicts(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = lerpf(float(a[k]), float(b.get(k, a[k])), u)
	return out


func _pose_attack(t: float) -> Dictionary:
	var m := _attack_moments()
	var t_raise: float = m[1]
	var t_charge: float = m[2]
	var t_recoil: float = m[3]
	var base := _base_pose()
	var d := _aim_dir_local()
	var aim := _base_pose()
	_arm_to_dir(aim, d, "R")
	var o: float = P["attack_overshoot"]
	var p: Dictionary
	if t < t_raise:
		var u := clampf(t / maxf(t_raise, 0.001), 0.0, 1.0)
		# anticipation: pull the arm back before the swing
		var ant: float = P["attack_anticipation"]
		var coil := sin(minf(u / 0.32, 1.0) * PI) * ant
		var swing := smoothstep(0.22, 1.0, u)
		var over := sin(clampf((u - 0.62) / 0.38, 0.0, 1.0) * PI) * o * 0.9
		var e := clampf(swing + over * (1.0 - swing * 0.4), 0.0, 1.3)
		p = _blend_dicts(base, aim, e)
		p["shoulder_R_pitch"] += 9.0 * coil
		p["shoulder_R_roll"] += 5.0 * coil
		p["elbow_R_pitch"] += 14.0 * coil
		p["chest_yaw"] += 7.0 * coil - 5.0 * e
		p["pelvis_yaw"] += 3.0 * coil
		p["head_yaw"] += 10.0 * e
		p["spine_pitch"] += -1.2 * e
		p["knee_L_pitch"] += 4.0 * e
		p["knee_R_pitch"] += 4.0 * e
	elif t < t_charge:
		var u := (t - t_raise) / maxf(t_charge - t_raise, 0.001)
		var conv := sin(u * PI * 0.5)
		p = _blend_dicts(aim, aim, 1.0)
		p["shoulder_R_pitch"] += 2.2 * conv + 0.7 * sin(t * 37.0) * conv
		p["shoulder_R_roll"] += 1.8 * conv
		p["elbow_R_pitch"] += 2.0 * conv
		p["wrist_R_pitch"] += -2.0 * conv
		p["chest_pitch"] += -1.6 * conv
		p["spine_pitch"] += -1.0 * conv
		p["head_yaw"] += 4.0
		p["head_pitch"] += -1.5 * conv
	elif t < t_recoil:
		var u := (t - t_charge) / maxf(t_recoil - t_charge, 0.001)
		var kick := sin(minf(u * 2.4, 1.0) * PI) * (1.0 - u * 0.55)
		p = _blend_dicts(aim, aim, 1.0)
		p["shoulder_R_pitch"] += 9.0 * kick
		p["elbow_R_pitch"] += 16.0 * kick
		p["wrist_R_pitch"] += -9.0 * kick
		p["chest_pitch"] += -4.0 * kick
		p["spine_pitch"] += -2.0 * kick
		p["pelvis_pitch"] += 1.6 * kick
		p["head_pitch"] += 2.0 * kick
		p["head_yaw"] += 3.0
		p["knee_L_pitch"] += 3.0 * kick
		p["knee_R_pitch"] += 3.0 * kick
	else:
		var u := clampf((t - t_recoil) / maxf(m[4] - t_recoil, 0.001), 0.0, 1.0)
		var e := smoothstep(0.0, 1.0, u)
		p = _blend_dicts(aim, base, e)
		p["shoulder_R_pitch"] += 2.0 * sin(e * PI) * (1.0 - e)
		p["elbow_R_pitch"] += 6.0 * sin(e * PI) * (1.0 - e)
		p["chest_yaw"] += 4.0 * e
		p["head_yaw"] += 6.0 * (1.0 - e)
	# support arm: clasps a little tighter during the shot
	p["elbow_L_pitch"] += 3.0 * sin(clampf(t / maxf(m[4], 0.001), 0.0, 1.0) * PI)
	# keep the legs braced
	p["hip_L_roll"] += 1.5
	p["hip_R_roll"] += -1.5
	return p


# --------------------------------------------------------------------- shoot

func _update_shurikens() -> void:
	if current_anim != "attack" or not field.is_assembled():
		_hide_shurikens()
		return
	var m := _attack_moments()
	var fire: float = m[2]
	var count := int(P["burst_count"])
	if _shot_age < -0.02:
		_hide_shurikens()
		return
	if not _muzzle_ok:
		_muzzle = _compute_muzzle(fire)
		_muzzle_ok = true
	for i in 3:
		var s: EnergyShuriken = shurikens[i]
		if i >= count:
			s.hide_all()
			continue
		var off := (float(i) - float(count - 1) * 0.5) * float(P["shuriken_spread"])
		var age := _shot_age - 0.055 * float(i)
		if age < 0.0:
			s.hide_all()
			continue
		if age > s.life:
			s.hide_all()
			continue
		if s.active == false or absf(s.size - P["shuriken_size"]) > 1e-4:
			s.launch(_muzzle.origin, _muzzle.basis.z, P["shuriken_speed"], P["shuriken_size"],
				P["shuriken_spin"], P["trail_life"], off)
		s.update(age)


func _compute_muzzle(fire_t: float) -> Transform3D:
	var save := _last_pose
	var p := _pose_attack(fire_t)
	rig.apply_pose(p)
	var xf := rig.hand_emitter_xform("R")
	if not save.is_empty():
		rig.apply_pose(save)
	_last_pose = save
	return xf


func _hide_shurikens() -> void:
	for s in shurikens:
		s.hide_all()


# ----------------------------------------------------------------- swarm FX

func _update_swarm_fx(dt: float) -> void:
	var st := field.state
	var body_pos := Vector3(_home_xz.x, 0, _home_xz.y)
	shadow.position = Vector3(body_pos.x, STAGE_TOP + 0.002, body_pos.z)
	var hover := rig.position.y
	var sh_scale := clampf(1.15 - hover * 0.9, 0.55, 1.15)
	if st != FieldScript.State.ASSEMBLED:
		sh_scale = 0.0
	shadow.scale = Vector3(sh_scale * 0.50, sh_scale * 0.50, 1.0)
	shadow_mat.set_shader_parameter("strength", 0.46 * clampf(1.25 - hover, 0.28, 1.0))
	# ring + ground glow follow the swarm centre while scattered
	var center := field.centroid()
	if st == FieldScript.State.ASSEMBLED:
		center = global_transform * (Vector3(_home_xz.x, 1.05, _home_xz.y))
	var prog := 0.0
	var alpha := 0.0
	if st == FieldScript.State.DISPERSING:
		prog = lerpf(0.82, 0.55, clampf(field.sim_t / maxf(field.fly_time + field.stagger, 0.01), 0.0, 1.0))
		alpha = 0.55
	elif st == FieldScript.State.FLYING:
		prog = 0.75
		alpha = 0.50 + 0.08 * sin(_wall * 1.7)
	elif st == FieldScript.State.REFORMING:
		var ru := clampf(field.sim_t / maxf(field.reform_time, 0.01), 0.0, 1.0)
		prog = 0.25 + 0.75 * ru
		alpha = 0.50 * (1.0 - ru)
	else:
		alpha = 0.0
	ring_node.visible = alpha > 0.01
	if ring_node.visible:
		ring_node.position = Vector3(center.x, STAGE_TOP + 0.012, center.z)
		ring_mat.set_shader_parameter("progress", prog)
		ring_mat.set_shader_parameter("alpha", alpha)
	glow_node.visible = true
	glow_node.position = Vector3(center.x, STAGE_TOP + 0.006, center.z)
	var gprog := 0.0
	if st == FieldScript.State.DISPERSING or st == FieldScript.State.FLYING or st == FieldScript.State.REFORMING:
		gprog = 1.0
	glow_mat.set_shader_parameter("progress", 0.12 + 0.88 * gprog)
	var flick := 0.90 + 0.06 * sin(_wall * 11.0) + 0.04 * sin(_wall * 27.0 + 1.3)
	if st == FieldScript.State.ASSEMBLED:
		glow_mat.set_shader_parameter("intensity", 0.30 * P["hover_glow"] * flick)
	else:
		glow_mat.set_shader_parameter("intensity", (0.28 + 0.10 * gprog) * P["glow_intensity"])
	if hover_wash:
		var hover_on := st == FieldScript.State.ASSEMBLED
		hover_wash.visible = hover_on and P["hover_thrust_power"] > 0.02 and P["hover_glow"] > 0.02
		hover_wash.position = Vector3(_home_xz.x, 0.70, _home_xz.y)
		hover_wash.light_energy = (9.0 * P["hover_thrust_power"] * P["hover_glow"] * flick) if hover_wash.visible else 0.0
	glow_mat.set_shader_parameter("progress", 0.10 + 0.9 * gprog)


func _update_retract(dt: float) -> void:
	var st := field.state
	if st == FieldScript.State.ASSEMBLED:
		_swarm_retract = 0.0
	elif st == FieldScript.State.DISPERSING or st == FieldScript.State.FLYING:
		_swarm_retract = 1.0
	else:
		var u := clampf(field.sim_t / maxf(field.reform_time, 0.01), 0.0, 1.0)
		_swarm_retract = 1.0 - smoothstep(0.55, 1.0, u)
	rig.set_retract(_swarm_retract)


func _update_charge(dt: float) -> void:
	var target := 0.0
	var orb := 0.0
	if current_anim == "attack" and field.is_assembled():
		var m := _attack_moments()
		if _t >= m[1] and _t < m[2]:
			var u: float = (_t - m[1]) / maxf(m[2] - m[1], 0.001)
			target = 0.15 + 0.85 * u * u
			orb = 0.25 + 0.75 * u
		elif _t >= m[2] and _t < m[2] + 0.18:
			var u: float = (_t - m[2]) / 0.18
			target = 1.0 - u
			orb = 1.55 - u
	_charge = lerpf(_charge, target, clampf(dt * 18.0, 0.0, 1.0))
	_orb_scale = lerpf(_orb_scale, orb, clampf(dt * 22.0, 0.0, 1.0))
	if rig.optic_mat:
		rig.optic_mat.set_shader_parameter("alert", _charge * 0.9)
	if rig.emitter_mat:
		rig.emitter_mat.set_shader_parameter("charge", _charge)
	if rig.core_mat:
		rig.core_mat.emission_energy_multiplier = 0.85 + _charge * 1.6 + 0.08 * sin(_wall * 2.0)
	var attacking := current_anim == "attack" and field.is_assembled()
	if wrist_light:
		wrist_light.light_energy = (0.15 + _charge * 2.6) if attacking else 0.0
	if charge_orb:
		charge_orb.visible = attacking and _orb_scale > 0.02
		charge_orb.scale = Vector3.ONE * maxf(_orb_scale, 0.001) * (1.0 + 0.06 * sin(_wall * 40.0))


# ---------------------------------------------------------------------- gaze

func _update_gaze(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not field.is_assembled():
		_gaze_seen = false
		return
	var chest := rig.chest_center()
	var dist := cam.global_position.distance_to(chest)
	var seen: bool = dist < P["gaze_distance"] and cam.is_position_in_frustum(chest)
	_gaze_seen = seen
	if P["gaze_reactive"] < 0.5:
		return
	if seen and _wall >= _gaze_next and _can_swarm():
		if current_anim in ["idle", "walk"]:
			_gaze_next = _wall + P["gaze_interval"]
			blink()


# ------------------------------------------------------------- auto sequence

func _update_auto_sequence() -> void:
	if _auto_reform_at > 0.0 and field.state == FieldScript.State.REFORMING:
		_auto_reform_at = -1.0


func _on_blink() -> void:
	blink()


func _on_disperse() -> void:
	_button_disperse()


func _on_reform() -> void:
	reform()


func _on_gaze_toggled(on: bool) -> void:
	P["gaze_reactive"] = 1.0 if on else 0.0
	_gaze_next = _wall + 0.4


# ------------------------------------------------------------------- overlay

func _build_overlay() -> void:
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 3
	add_child(overlay_layer)
	overlay_panel = PanelContainer.new()
	overlay_panel.anchor_left = 0.5
	overlay_panel.anchor_right = 0.5
	overlay_panel.anchor_top = 0.0
	overlay_panel.anchor_bottom = 0.0
	overlay_panel.offset_left = -318
	overlay_panel.offset_right = 318
	overlay_panel.offset_top = 18
	overlay_panel.offset_bottom = 58
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.016, 0.018, 0.025, 0.88)
	sb.border_color = Color(0.55, 0.16, 0.05, 0.65)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	overlay_panel.add_theme_stylebox_override("panel", sb)
	overlay_layer.add_child(overlay_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	overlay_panel.add_child(row)
	status_label = Label.new()
	status_label.text = "ASSEMBLED"
	status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.28))
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.custom_minimum_size = Vector2(146, 0)
	row.add_child(status_label)
	var b1 := Button.new()
	b1.text = "BLINK  [B]"
	b1.focus_mode = Control.FOCUS_NONE
	b1.pressed.connect(_on_blink)
	row.add_child(b1)
	var b2 := Button.new()
	b2.text = "DISPENSE  [N]"
	b2.focus_mode = Control.FOCUS_NONE
	b2.pressed.connect(_on_disperse)
	row.add_child(b2)
	var b3 := Button.new()
	b3.text = "REFORM  [M]"
	b3.focus_mode = Control.FOCUS_NONE
	b3.pressed.connect(_on_reform)
	row.add_child(b3)
	gaze_toggle = CheckBox.new()
	gaze_toggle.text = "GAZE REACTIVE"
	gaze_toggle.button_pressed = P["gaze_reactive"] > 0.5
	gaze_toggle.focus_mode = Control.FOCUS_NONE
	gaze_toggle.toggled.connect(_on_gaze_toggled)
	row.add_child(gaze_toggle)
	var hint := Label.new()
	hint.text = "G: gaze"
	hint.add_theme_color_override("font_color", Color(0.45, 0.48, 0.56))
	hint.add_theme_font_size_override("font_size", 10)
	row.add_child(hint)


func _update_overlay() -> void:
	if overlay_panel == null:
		return
	var parent := get_parent()
	var hide := false
	if parent and parent.has_method("snap"):
		var shot_mode = parent.get("_shot_mode")
		if shot_mode == true:
			hide = true
		var ui = parent.get("ui_root")
		if ui is Control and not (ui as Control).visible:
			hide = true
	overlay_panel.visible = not hide
	var st := field.state_name()
	var extra := ""
	match field.state:
		FieldScript.State.DISPERSING:
			extra = " %d%%" % int(100.0 * clampf(field.sim_t / maxf(field.fly_time + field.stagger, 0.01), 0.0, 1.0))
		FieldScript.State.FLYING:
			extra = "  r=%.1fm" % field.swarm_radius()
		FieldScript.State.REFORMING:
			extra = " %d%%" % int(100.0 * clampf(field.sim_t / maxf(field.ref_dur_est(), 0.01), 0.0, 1.0))
	status_label.text = "%s%s" % [st, extra]
	status_label.add_theme_color_override("font_color",
		Color(1.0, 0.55, 0.28) if st == "ASSEMBLED" else Color(1.0, 0.32, 0.15))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_B:
				blink()
			KEY_N:
				_button_disperse()
			KEY_M:
				reform()
			KEY_G:
				P["gaze_reactive"] = 0.0 if P["gaze_reactive"] > 0.5 else 1.0
				gaze_toggle.set_pressed_no_signal(P["gaze_reactive"] > 0.5)
				_gaze_next = _wall + 0.4


# -------------------------------------------------------------------- debug

func rig_debug() -> Dictionary:
	var d := {
		"STATE": "%s" % field.state_name(),
		"MODULES": "%d" % field.mods.size(),
		"SWARM R": "%.2f m" % field.swarm_radius() if field.state != FieldScript.State.ASSEMBLED else "—",
		"HOVER GAP": "%.3f m (min)" % P["hover_height"],
		"SOLE Y": "%.3f m" % (rig.position.y - SOLE_DROP - STAGE_TOP),
		"GAZE": "ON" if P["gaze_reactive"] > 0.5 else "OFF",
		"SEEN": "YES" if _gaze_seen else "NO",
		"ANIM T": "%.2f / %.2f" % [_t, anim_duration()],
		"DRAW CALLS": "%d" % RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
	}
	return d
