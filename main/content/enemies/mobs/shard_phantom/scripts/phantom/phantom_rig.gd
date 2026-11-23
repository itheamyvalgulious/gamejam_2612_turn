extends Node3D
class_name PhantomRig
## PhantomRig — skeleton, inner frame, hands and the authored module slot map
## for SHARD // PHANTOM.
##
## Design space is a 1.60 m tall figure standing with its sole plane at y = 0.
## The whole rig is scaled by height/1.60 and lifted by `hover_height`; the
## sole plane therefore sits exactly hover_height above the stage.
##
## Joint rotation convention (consistent for every joint):
##     B = Rx(pitch) * Ry(yaw) * Rz(roll)
## Positive pitch tips a downward limb backwards (-Z), positive roll swings a
## left-side limb outward (+X).  `hand` joints are called wrist_* to match the
## rig vocabulary (hand modules live on the wrist joint).
##
## Module slots: every slot is authored on the LEFT side and mirrored across
## X, so the body is perfectly symmetric at any module count.  Each entry has
## {joint, pos, quat, size, mesh, tint, edge, signal, seed, prio}.

const MK := preload("res://scripts/kit/mesh_kit.gd")
const PK := preload("res://scripts/phantom/phantom_kit.gd")
const PM := preload("res://scripts/phantom/phantom_materials.gd")

const HIP_Y := 0.92
const THIGH := 0.34
const SHIN := 0.42
const ANKLE_Y := HIP_Y - THIGH - SHIN
const UPPER := 0.26
const FORE := 0.24
const SHOULDER_Y := 0.165    # chest local
const NECK_Y := 0.205
const HEAD_Y := 0.035

var joints: Dictionary = {}
var frame_parts: Array = []
var slots: Array = []
var optic_glass: MeshInstance3D
var optic_mat: ShaderMaterial
var emitter_mat: ShaderMaterial
var core_mat: StandardMaterial3D
var vent_mat: ShaderMaterial
var hover_mat: ShaderMaterial
var hover_parts: Array = []
var hover_power := 1.0
var core_light: OmniLight3D

var height_scale := 1.0
var shoulder_x := 0.21
var limb_girth := 1.0
var head_scale := 1.0
var frame_vis := 0.7
var retract := 0.0
var module_size := 0.10
var module_gap := 0.018

var _rng := RandomNumberGenerator.new()


func build(h: float, sw: float, girth: float, hsize: float) -> void:
	height_scale = clampf(h / 1.60, 0.80, 1.25)
	shoulder_x = clampf(sw, 0.26, 0.62) * 0.5
	limb_girth = clampf(girth, 0.6, 1.6)
	head_scale = clampf(hsize, 0.7, 1.35)
	_rng.seed = 26011217
	for c in get_children():
		remove_child(c)
		c.queue_free()
	joints.clear()
	frame_parts.clear()
	hover_parts.clear()
	slots.clear()
	node_axis.clear()
	_build_skeleton()
	_build_axis_map()
	_build_frame()
	_build_head_optic()
	_generate_slots()
	scale = Vector3.ONE * height_scale
	_apply_frame_visibility()


## Re-evaluates module sizes after module_size / module_gap changed.
func regenerate_slots() -> void:
	slots.clear()
	_generate_slots()


# ------------------------------------------------------------------ skeleton

func _j(parent: Node3D, key: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = key
	n.position = pos
	parent.add_child(n)
	joints[key] = n
	return n


func _build_skeleton() -> void:
	var pelvis := _j(self, "Pelvis", Vector3(0, HIP_Y, 0))
	var spine := _j(pelvis, "Spine", Vector3(0, 0.09, 0))
	var chest := _j(spine, "Chest", Vector3(0, 0.12, 0))
	var neck := _j(chest, "Neck", Vector3(0, NECK_Y, 0))
	_j(neck, "Head", Vector3(0, HEAD_Y, 0))
	for side in [1.0, -1.0]:
		var tag := "L" if side > 0.0 else "R"
		var sh := _j(chest, "Shoulder_" + tag, Vector3(shoulder_x * side, SHOULDER_Y, 0.0))
		var el := _j(sh, "Elbow_" + tag, Vector3(0, -UPPER, 0))
		var wr := _j(el, "Wrist_" + tag, Vector3(0, -FORE, 0))
		_j(wr, "Finger_" + tag, Vector3(0, -0.085, 0))
		var hip := _j(pelvis, "Hip_" + tag, Vector3(0.105 * side, 0.0, 0))
		var kn := _j(hip, "Knee_" + tag, Vector3(0, -THIGH, 0))
		var an := _j(kn, "Ankle_" + tag, Vector3(0, -SHIN, 0))
		_j(an, "Toe_" + tag, Vector3(0, -0.075, 0.070))


# --------------------------------------------------------------------- frame

func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO,
		rot_deg := Vector3.ZERO, n := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if n != "":
		mi.name = n
	parent.add_child(mi)
	return mi


func _part(mi: MeshInstance3D, kind: String) -> MeshInstance3D:
	frame_parts.append({"node": mi, "kind": kind, "base": mi.scale})
	return mi


func _beam(parent: Node3D, a: Vector3, b: Vector3, h: float, w: float,
		mat: Material, n := "") -> MeshInstance3D:
	var d := b - a
	var l := d.length()
	var mi := MeshInstance3D.new()
	mi.mesh = MK.beam(l, h, w, h * 0.86, w * 0.86)
	mi.material_override = mat
	var q := Quaternion(Vector3.RIGHT, d.normalized())
	mi.transform = Transform3D(Basis(q), a)
	if n != "":
		mi.name = n
	parent.add_child(mi)
	frame_parts.append({"node": mi, "kind": "rod", "base": Vector3.ONE})
	return mi


func _build_frame() -> void:
	var f := PM.frame()
	var fl := PM.frame_light()
	var tr := PM.trim()
	var shm := PM.inner_shell()
	var p: Node3D = joints["Pelvis"]
	var sp: Node3D = joints["Spine"]
	var ch: Node3D = joints["Chest"]
	var nk: Node3D = joints["Neck"]
	var hd: Node3D = joints["Head"]

	# ---- pelvis core
	_part(_mi(p, MK.prism(8, 0.115, 0.10, 0.20, PI / 8.0), f, Vector3(0, -0.02, 0)), "blob")
	_part(_mi(p, MK.prism(16, 0.116, 0.116, 0.010, 0.0), PM.seam(),
		Vector3(0, -0.055, 0)), "blob")
	# pelvis top belt: four dark segments, visible gaps
	for bi in 4:
		var ba := TAU * float(bi) / 4.0 + PI * 0.25
		var bp := Vector3(sin(ba) * 0.128, 0.048, cos(ba) * 0.094)
		var bn := Vector3(sin(ba), 0.28, cos(ba)).normalized()
		var bx := Vector3.UP.cross(bn).normalized()
		var by := bn.cross(bx).normalized()
		var bb := Basis(bx, by, bn)
		_part(_mi(p, PK.extrude_poly(PK.plate_poly(0.078, 0.062, 0.80, 0.80, 0.18), 0.020, 0.004),
			PM.frame_light(), bp, Vector3.ZERO), "blob").transform.basis = bb * Basis().scaled(Vector3(1, 1, 1))
	# pelvis rear keel
	_part(_mi(p, PK.extrude_poly(PK.plate_poly(0.055, 0.17, 0.45, 0.9, 0.2), 0.028, 0.006),
		f, Vector3(0, -0.03, -0.105), Vector3(18, 0, 0)), "blob")
	# hip cups
	for side in [1.0, -1.0]:
		_part(_mi(p, MK.disc(0.052, 0.042, 16, 0.008), tr,
			Vector3(0.105 * side, 0.0, 0), Vector3(90, 0, 0)), "blob")

	# ---- spine: telescoping stack
	for i in 3:
		var y := 0.012 + 0.042 * i
		var r := 0.048 - 0.004 * i
		_part(_mi(sp, MK.prism(8, r, r * 0.94, 0.046, PI / 8.0), f if i % 2 == 0 else fl,
			Vector3(0, y, 0)), "rodY")
		_part(_mi(sp, MK.prism(8, r + 0.008, r + 0.008, 0.008, PI / 8.0),
			PM.seam(), Vector3(0, y + 0.022, 0)), "blob")
	# abdomen central plate
	_part(_mi(sp, PK.extrude_poly(PK.plate_poly(0.10, 0.115, 0.62, 0.85, 0.18), 0.026, 0.005),
		f, Vector3(0, 0.065, 0.078), Vector3(-6, 0, 0)), "blob")

	# ---- back carapace (dark structural shell behind the shoulder plates)
	var backplate := _mi(ch, PK.extrude_poly(PK.plate_poly(0.250, 0.260, 0.72, 0.62, 0.14), 0.030, 0.006),
		PM.frame_light(), Vector3(0, 0.095, -0.096), Vector3(8, 0, 0), "BackCarapace")
	_part(backplate, "blob")
	for i in 3:
		_part(_mi(ch, MK.plate(0.012, 0.16 - i * 0.02, 0.010, 0.002), PM.seam(),
			Vector3(-0.045 + i * 0.045, 0.09, -0.114), Vector3(8, 0, 0)), "blob")
	var backpelvis := _mi(p, PK.extrude_poly(PK.plate_poly(0.200, 0.160, 0.80, 0.60, 0.16), 0.026, 0.006),
		PM.frame(), Vector3(0, -0.020, -0.092), Vector3(-8, 0, 0), "BackPelvis")
	_part(backpelvis, "blob")

	# ---- inner shell (dark under-suit so module gaps read as seams, not voids)
	var shel := PM.inner_shell()
	var chest_shell := _mi(ch, MK.prism(8, 0.130, 0.150, 0.265, PI / 8.0), shel, Vector3(0, 0.085, -0.005))
	chest_shell.scale = Vector3(1.0, 1.0, 0.72)
	_part(chest_shell, "blob")
	var ab_shell := _mi(sp, MK.prism(8, 0.085, 0.095, 0.135, PI / 8.0), shel, Vector3(0, 0.062, 0.0))
	ab_shell.scale = Vector3(1.0, 1.0, 0.78)
	_part(ab_shell, "blob")
	var pelvis_shell := _mi(p, MK.prism(8, 0.122, 0.105, 0.185, PI / 8.0), shel, Vector3(0, -0.018, 0.0))
	pelvis_shell.scale = Vector3(1.0, 1.0, 0.76)
	_part(pelvis_shell, "blob")

	# ---- chest frame
	_part(_mi(ch, MK.prism(8, 0.075, 0.095, 0.23, PI / 8.0), f, Vector3(0, 0.10, -0.005)), "blob")
	# sternum block + energy slit
	_part(_mi(ch, PK.extrude_poly(PK.plate_poly(0.105, 0.20, 0.72, 0.55, 0.16), 0.035, 0.008),
		fl, Vector3(0, 0.105, 0.088), Vector3(-5, 0, 0)), "blob")
	core_mat = PM.emissive(Color(1.0, 0.16, 0.035), 0.75)
	_part(_mi(ch, MK.plate(0.010, 0.100, 0.012, 0.002), core_mat,
		Vector3(0, 0.09, 0.096), Vector3(-5, 0, 0)), "blob")
	# clavicle rods
	for side in [1.0, -1.0]:
		# rib rods down the side
		_beam(ch, Vector3(0.11 * side, 0.13, -0.01), Vector3(0.135 * side, -0.02, -0.01),
			0.030, 0.026, f)
		# back scapula blades
		_part(_mi(ch, PK.extrude_poly(PK.plate_poly(0.075, 0.20, 0.35, 0.75, 0.12), 0.022, 0.005),
			f, Vector3(0.085 * side, 0.11, -0.098), Vector3(10, 24 * side, 8 * side)), "blob")
	# back ridge
	_part(_mi(ch, MK.prism(6, 0.032, 0.026, 0.30, PI / 6.0), fl, Vector3(0, 0.10, -0.075)), "blob")
	for i in 3:
		_part(_mi(ch, MK.prism(6, 0.026, 0.024, 0.012, PI / 6.0), PM.seam(),
			Vector3(0, 0.02 + 0.07 * i, -0.079)), "blob")

	# ---- neck + collar yoke
	_part(_mi(ch, PK.extrude_poly(PK.plate_poly(0.255, 0.070, 0.80, 0.55, 0.16), 0.042, 0.006),
		fl, Vector3(0, 0.182, 0.006), Vector3(-6, 0, 0)), "blob")
	_part(_mi(nk, MK.prism(8, 0.042, 0.036, 0.080, PI / 8.0), fl, Vector3(0, 0.035, 0)), "rodY")
	_part(_mi(nk, MK.prism(12, 0.046, 0.040, 0.016, 0), PM.frame_light(), Vector3(0, 0.010, 0)), "blob")
	_part(_mi(nk, MK.prism(12, 0.038, 0.036, 0.010, 0), PM.seam(),
		Vector3(0, 0.065, 0)), "blob")

	# ---- head core: faceted skull, brow, cheek rails, crest
	_part(_mi(hd, MK.prism(8, 0.074, 0.036, 0.155, PI / 8.0), shm,
		Vector3(0, 0.072, -0.020), Vector3(0, 0, 0), "Skull"), "blob")
	_part(_mi(hd, PK.extrude_poly(PK.plate_poly(0.050, 0.135, 0.20, 0.70, 0.10), 0.022, 0.004),
		fl, Vector3(0, 0.092, -0.062), Vector3(-16, 0, 0)), "blob")
	# solid crown cap (no see-through top)
	_part(_mi(hd, PK.extrude_poly(PK.plate_poly(0.115, 0.075, 0.55, 0.80, 0.20), 0.030, 0.005),
		PM.frame_light(), Vector3(0, 0.176, -0.015), Vector3(-8, 0, 0), "CrownCap"), "blob")
	# side shell covers (close the head cage)
	for side in [1.0, -1.0]:
		var sc = _mi(hd, PK.extrude_poly(PK.plate_poly(0.052, 0.165, 0.55, 0.45, 0.22), 0.024, 0.004),
			shm, Vector3(0.074 * side, 0.080, -0.006), Vector3(0, 14 * side, 0), "HeadSide")
		frame_parts.append({"node": sc, "kind": "blob", "base": sc.scale})
	# back-swept crest: one tall centre fin + two smaller flankers
	_part(_mi(hd, PK.extrude_poly(PK.plate_poly(0.032, 0.140, 0.12, 0.55, 0.10), 0.013, 0.003),
		tr, Vector3(0, 0.128, -0.082), Vector3(-58, 0, 0)), "blob")
	for side in [1.0, -1.0]:
		_part(_mi(hd, PK.extrude_poly(PK.plate_poly(0.024, 0.100, 0.10, 0.65, 0.10), 0.011, 0.003),
			fl, Vector3(0.047 * side, 0.118, -0.070), Vector3(-48, 12 * side, 0)), "blob")
	# neck collar
	_part(_mi(hd, MK.ring(0.026, 0.042, 0.012, 20, 0.003), fl,
		Vector3(0, 0.000, 0.0), Vector3(0, 0, 0)), "blob")

	# ---- arms
	for tag in ["L", "R"]:
		var sh: Node3D = joints["Shoulder_" + tag]
		var el: Node3D = joints["Elbow_" + tag]
		var wr: Node3D = joints["Wrist_" + tag]
		_part(_mi(sh, MK.prism(8, 0.032, 0.029, UPPER - 0.01, PI / 8.0), shm,
			Vector3(0, -UPPER * 0.5, 0)), "rodY")
		_part(_mi(sh, MK.prism(8, 0.022, 0.020, UPPER - 0.02, PI / 8.0), f,
			Vector3(0, -UPPER * 0.5, 0)), "rodY")
		_part(_mi(sh, MK.prism(8, 0.048, 0.036, 0.046, 0), fl, Vector3(0, -0.008, 0)), "blob")
		_part(_mi(el, MK.disc(0.033, 0.054, 14, 0.006), tr, Vector3(0, 0, 0), Vector3(90, 0, 0)), "blob")
		_part(_mi(el, MK.prism(8, 0.026, 0.023, FORE - 0.04, PI / 8.0), shm,
			Vector3(0, -FORE * 0.5, 0)), "rodY")
		_part(_mi(el, MK.prism(8, 0.018, 0.016, FORE - 0.055, PI / 8.0), f,
			Vector3(0, -FORE * 0.5, 0)), "rodY")
		_part(_mi(wr, MK.disc(0.027, 0.040, 12, 0.005), fl, Vector3(0, 0, 0), Vector3(90, 0, 0)), "blob")
		_build_hand(wr, tag)
		_part(_mi(sh, MK.prism(12, 0.019, 0.017, 0.014, 0), PM.seam(),
			Vector3(0.0, -0.115, 0.030), Vector3(90, 0, 0)), "blob")

	# ---- legs
	for tag in ["L", "R"]:
		var hip: Node3D = joints["Hip_" + tag]
		var kn: Node3D = joints["Knee_" + tag]
		var an: Node3D = joints["Ankle_" + tag]
		var to: Node3D = joints["Toe_" + tag]
		_part(_mi(hip, MK.prism(8, 0.040, 0.033, THIGH - 0.01, PI / 8.0), shm,
			Vector3(0, -THIGH * 0.5, 0)), "rodY")
		_part(_mi(hip, MK.prism(8, 0.026, 0.022, THIGH - 0.02, PI / 8.0), f,
			Vector3(0, -THIGH * 0.5, 0)), "rodY")
		_part(_mi(hip, MK.prism(8, 0.052, 0.046, 0.075, PI / 8.0), fl,
			Vector3(0, -0.035, 0)), "blob")
		_part(_mi(kn, MK.disc(0.042, 0.060, 16, 0.007), tr, Vector3(0, 0, 0), Vector3(0, 0, 90)), "blob")
		_part(_mi(kn, MK.prism(8, 0.031, 0.025, SHIN - 0.03, PI / 8.0), shm,
			Vector3(0, -SHIN * 0.5, 0)), "rodY")
		_part(_mi(kn, MK.prism(8, 0.020, 0.017, SHIN - 0.045, PI / 8.0), f,
			Vector3(0, -SHIN * 0.5, 0)), "rodY")
		_part(_mi(an, MK.disc(0.026, 0.044, 12, 0.005), fl, Vector3(0, 0, 0), Vector3(0, 0, 90)), "blob")
		# foot blade (down + forward) and heel spur
		_beam(an, Vector3(0, 0, 0), Vector3(0, -0.135, 0.120), 0.104, 0.062, shm)
		_beam(an, Vector3(0, -0.006, -0.004), Vector3(0, -0.078, -0.090), 0.052, 0.034, fl)
		# toe claw on the toe joint
		_beam(to, Vector3(0, 0, 0), Vector3(0, -0.088, 0.060), 0.070, 0.044, tr)
		_part(_mi(an, MK.prism(8, 0.024, 0.020, 0.012, 0), PM.seam(),
			Vector3(0, -0.02, 0.035), Vector3(70, 0, 0)), "blob")

	# ---- visible attitude jets (frame-mounted micro-thrusters)
	var plume_mesh := PK.plume_cross(1.0, 1.0)
	vent_mat = PM.vent()
	_add_vent(ch, Vector3(0.232, 0.190, -0.105), Vector3(0.35, 0.05, -0.94), 0.020, 0.021, plume_mesh, vent_mat)
	_add_vent(ch, Vector3(-0.232, 0.190, -0.105), Vector3(-0.35, 0.05, -0.94), 0.020, 0.041, plume_mesh, vent_mat)
	_add_vent(ch, Vector3(0.070, 0.020, -0.128), Vector3(0.22, -0.62, -0.75), 0.018, 0.061, plume_mesh, vent_mat)
	_add_vent(ch, Vector3(-0.070, 0.020, -0.128), Vector3(-0.22, -0.62, -0.75), 0.018, 0.081, plume_mesh, vent_mat)
	for side in [1.0, -1.0]:
		var tag := "L" if side > 0 else "R"
		var el: Node3D = joints["Elbow_" + tag]
		_add_vent(el, Vector3(0.044 * side, -0.130, -0.020), Vector3(0.78 * side, -0.35, -0.52), 0.015, 0.21 + side * 0.1, plume_mesh, vent_mat)
		var kn: Node3D = joints["Knee_" + tag]
		_add_vent(kn, Vector3(0.060 * side, -0.200, -0.040), Vector3(0.66 * side, -0.60, -0.45), 0.021, 0.31 + side * 0.1, plume_mesh, vent_mat)
		var an: Node3D = joints["Ankle_" + tag]
		_add_hover(an, Vector3(0.0, -0.146, 0.030), Vector3(0.02 * side, -1.0, 0.03), 0.040, 0.140, 0.61 + side * 0.1)
	# main lift jets on the back (down/outward), plus small rear-calf jets
	_add_hover(ch, Vector3(0.105, 0.010, -0.118), Vector3(0.30, -0.86, -0.42), 0.052, 0.190, 0.71)
	_add_hover(ch, Vector3(-0.105, 0.010, -0.118), Vector3(-0.30, -0.86, -0.42), 0.052, 0.190, 0.73)
	for side in [1.0, -1.0]:
		var tag2 := "L" if side > 0 else "R"
		var kn2: Node3D = joints["Knee_" + tag2]
		_add_hover(kn2, Vector3(0.030 * side, -0.300, -0.050), Vector3(0.16 * side, -0.92, -0.36), 0.028, 0.090, 0.81 + side * 0.1)

	# hip attitude jets
	_add_vent(p, Vector3(0.135, 0.010, -0.070), Vector3(0.60, 0.05, -0.80), 0.018, 0.51, plume_mesh, vent_mat)
	_add_vent(p, Vector3(-0.135, 0.010, -0.070), Vector3(-0.60, 0.05, -0.80), 0.018, 0.53, plume_mesh, vent_mat)

	# ---- chest core light
	core_light = OmniLight3D.new()
	core_light.light_color = Color(1.0, 0.24, 0.05)
	core_light.light_energy = 0.0
	core_light.omni_range = 1.9
	core_light.omni_attenuation = 1.6
	core_light.position = Vector3(0, 0.10, 0.16)
	core_light.shadow_enabled = false
	ch.add_child(core_light)


func _add_hover(parent: Node3D, pos: Vector3, dir: Vector3, w: float, length: float, seed_v: float) -> void:
	var d := dir.normalized()
	var mesh := PK.plume_cross(1.0, 1.0)
	if hover_mat == null:
		hover_mat = PM.vent()
		hover_mat.set_shader_parameter("hot_color", Color(1.0, 0.82, 0.55))
		hover_mat.set_shader_parameter("flame_color", Color(1.0, 0.14, 0.02))
		hover_mat.set_shader_parameter("intensity", 3.8)
	var plume := MeshInstance3D.new()
	plume.mesh = mesh
	plume.material_override = hover_mat
	plume.transform = Transform3D(Basis.looking_at(d, Vector3.UP) * Basis().scaled(Vector3(w, w, length)), pos)
	plume.set_instance_shader_parameter("fx_seed", seed_v)
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(plume)
	hover_parts.append({"node": plume, "base": Vector3(w, w, length)})
	# nozzle housing + hot lip
	var housing := MeshInstance3D.new()
	housing.mesh = MK.prism(8, w * 0.55, w * 0.38, w * 0.85, 0.0)
	housing.material_override = PM.frame()
	housing.transform = Transform3D(Basis(Quaternion(Vector3.UP, d)), pos - d * w * 0.15)
	housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(housing)
	frame_parts.append({"node": housing, "kind": "blob", "base": housing.scale})
	var lip := MeshInstance3D.new()
	lip.mesh = MK.ring(w * 0.20, w * 0.46, w * 0.22, 16, 0.002)
	lip.material_override = PM.emissive(Color(1.0, 0.20, 0.03), 3.0)
	lip.transform = Transform3D(Basis(Quaternion(Vector3.UP, d)), pos)
	lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(lip)
	frame_parts.append({"node": lip, "kind": "blob", "base": lip.scale})


func _add_vent(parent: Node3D, pos: Vector3, dir: Vector3, w: float, seed_v: float,
		mesh: Mesh, mat: Material) -> void:
	var b := Basis.looking_at(dir.normalized(), Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.top_level = false
	mi.transform = Transform3D(b * Basis().scaled(Vector3(w, w, w * 1.55)), pos + dir.normalized() * w * 0.9)
	mi.set_instance_shader_parameter("fx_seed", seed_v)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	frame_parts.append({"node": mi, "kind": "blob", "base": mi.scale})
	var noz := MeshInstance3D.new()
	noz.mesh = MK.ring(w * 0.30, w * 0.62, w * 0.34, 16, 0.002)
	noz.material_override = PM.seam()
	var nb := Basis(Quaternion(Vector3.UP, dir.normalized()))
	noz.transform = Transform3D(nb, pos + dir.normalized() * 0.002)
	var housing := MeshInstance3D.new()
	housing.mesh = MK.prism(8, w * 0.78, w * 0.55, w * 1.6, 0.0)
	housing.material_override = PM.frame()
	housing.transform = Transform3D(nb * Basis(Vector3.RIGHT, PI * 0.5), pos - dir.normalized() * w * 0.7)
	housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(housing)
	frame_parts.append({"node": housing, "kind": "blob", "base": housing.scale})
	noz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(noz)
	frame_parts.append({"node": noz, "kind": "blob", "base": noz.scale})


func _build_hand(wr: Node3D, tag: String) -> void:
	var f := PM.frame()
	var fl := PM.frame_light()
	var tr := PM.trim()
	# palm wedge: local +Z is the palm/emitter face
	_part(_mi(wr, PK.extrude_poly(PK.plate_poly(0.075, 0.085, 0.72, 0.90, 0.16), 0.026, 0.005),
		f, Vector3(0, -0.048, 0)), "blob")
	# back-of-hand armour lip
	_part(_mi(wr, PK.extrude_poly(PK.plate_poly(0.060, 0.055, 0.80, 0.60, 0.18), 0.014, 0.004),
		fl, Vector3(0, -0.038, -0.019), Vector3(0, 0, 0)), "blob")
	# emitter ring + iris on the palm face
	_part(_mi(wr, MK.ring(0.0155, 0.027, 0.007, 28, 0.002), f,
		Vector3(0, -0.046, 0.016), Vector3(90, 0, 0)), "blob")
	_part(_mi(wr, MK.ring(0.0115, 0.0145, 0.005, 24, 0.001), PM.emissive(PM.ENERGY, 5.0),
		Vector3(0, -0.046, 0.0195), Vector3(90, 0, 0)), "blob")
	emitter_mat = PM.emitter()
	var iris := _mi(wr, MK.dome(0.0165, 0.005, 24, 8), emitter_mat,
		Vector3(0, -0.046, 0.0155), Vector3(90, 0, 0))
	_part(iris, "blob")
	# knuckle guard
	_part(_mi(wr, MK.beam(0.062, 0.022, 0.050, 0.016, 0.038), f,
		Vector3(0, -0.082, 0.0), Vector3(0, 0, 90)), "rod")
	# finger claw on the finger joint
	var fj: Node3D = wr.get_node("Finger_" + tag)
	for i in 3:
		var x := (float(i) - 1.0) * 0.018
		_beam(fj, Vector3(x, 0, 0.008), Vector3(x * 1.25, -0.058, 0.030), 0.011, 0.009, fl)


func _build_head_optic() -> void:
	var hd: Node3D = joints["Head"]
	# solid machined camera housing (the face is one big optic, no facial features)
	var housing := _mi(hd, PK.extrude_poly(PK.plate_poly(0.178, 0.200, 0.82, 0.46, 0.20), 0.115, 0.012),
		PM.frame_light(), Vector3(0, 0.086, -0.002), Vector3.ZERO, "CameraHousing")
	frame_parts.append({"node": housing, "kind": "blob", "base": housing.scale})
	# deep barrel: dark outer sleeve, inner wall, machined front lip
	var barrel := _mi(hd, MK.ring(0.064, 0.081, 0.062, 40, 0.004), PM.trim(),
		Vector3(0, 0.092, 0.078), Vector3(90, 0, 0), "OpticBarrel")
	frame_parts.append({"node": barrel, "kind": "blob", "base": barrel.scale})
	var collar := _mi(hd, MK.ring(0.080, 0.093, 0.014, 40, 0.003), PM.frame_light(),
		Vector3(0, 0.092, 0.104), Vector3(90, 0, 0), "OpticCollar")
	frame_parts.append({"node": collar, "kind": "blob", "base": collar.scale})
	# dark inner cavity behind the glass
	var cavity := _mi(hd, MK.disc(0.064, 0.012, 32, 0.002), PM.dark_glass(),
		Vector3(0, 0.092, 0.050), Vector3(90, 0, 0), "OpticCavity")
	frame_parts.append({"node": cavity, "kind": "blob", "base": cavity.scale})
	# flat-ish front glass: a large orange-red camera iris
	optic_mat = PM.head_optic()
	optic_glass = _mi(hd, MK.dome(0.061, 0.008, 44, 12), optic_mat,
		Vector3(0, 0.092, 0.072), Vector3(90, 0, 0), "HeadOptic")
	frame_parts.append({"node": optic_glass, "kind": "blob", "base": optic_glass.scale})
	# aperture ring + a very thin hot rim inside the barrel
	var aperture := _mi(hd, MK.ring(0.049, 0.060, 0.007, 40, 0.001), PM.trim(),
		Vector3(0, 0.092, 0.084), Vector3(90, 0, 0), "Aperture")
	frame_parts.append({"node": aperture, "kind": "blob", "base": aperture.scale})
	var iris_rim := _mi(hd, MK.ring(0.0615, 0.0655, 0.004, 44, 0.001), PM.emissive(Color(1.0, 0.18, 0.03), 1.6),
		Vector3(0, 0.092, 0.079), Vector3(90, 0, 0), "IrisRim")
	frame_parts.append({"node": iris_rim, "kind": "blob", "base": iris_rim.scale})
	# hood over the optic + lower housing lip
	var hood := _mi(hd, PK.extrude_poly(PK.plate_poly(0.190, 0.045, 0.80, 0.60, 0.16), 0.050, 0.007),
		PM.frame_light(), Vector3(0, 0.170, 0.068), Vector3(-32, 0, 0), "OpticHood")
	frame_parts.append({"node": hood, "kind": "blob", "base": hood.scale})
	var chin := _mi(hd, PK.extrude_poly(PK.plate_poly(0.165, 0.038, 0.70, 0.55, 0.16), 0.045, 0.006),
		PM.frame_light(), Vector3(0, 0.014, 0.048), Vector3(18, 0, 0), "OpticLip")
	frame_parts.append({"node": chin, "kind": "blob", "base": chin.scale})


# ----------------------------------------------------------------- slots

func _mirror_basis(b: Basis) -> Basis:
	var x := Vector3(b.x.x, -b.x.y, -b.x.z)
	var y := Vector3(-b.y.x, b.y.y, b.y.z)
	var z := Vector3(-b.z.x, b.z.y, b.z.z)
	return Basis(x, y, z)


func _mk_slot(joint: String, pos: Vector3, nrm: Vector3, up: Vector3,
		w: float, h: float, t: float, mesh_id: int, tint: int, prio: float,
		seed: float, yaw: float, pitch: float, edge: float, sig: float) -> Dictionary:
	var z := nrm.normalized()
	var x := up.cross(z)
	if x.length_squared() < 1e-8:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	var b := Basis(x, y, z)
	b = b * Basis(Vector3.BACK, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	var mesh_id2 := mesh_id
	if mesh_id2 < 0:
		var mh := fmod(absf(sin(seed * 7.717 + 1.3) * 24634.6345), 1.0)
		mesh_id2 = 0
		if mh >= 0.42 and mh < 0.66:
			mesh_id2 = 2
		elif mh >= 0.66 and mh < 0.78:
			mesh_id2 = 1
		elif mh >= 0.78 and mh < 0.90:
			mesh_id2 = 4
	var tint_id := tint
	if tint_id < 0:
		var hv := fmod(absf(sin(seed * 12.9898) * 43758.5453), 1.0)
		if hv < 0.085:
			tint_id = 3
		elif hv < 0.16:
			tint_id = 4
		elif hv < 0.30:
			tint_id = 5
		elif hv < 0.62:
			tint_id = 0
		else:
			tint_id = 1 + int(hv * 7.0) % 2
	var jit := (fmod(absf(sin(seed * 3.917 + 0.7) * 17341.2), 1.0) - 0.5) * 0.007
	pos += z * jit
	var sc := module_size / 0.10
	var gapk := 1.0 + (module_gap - 0.018) * 12.0
	var sw := clampf(w * sc * gapk, 0.040, 0.160)
	var sh := clampf(h * sc * gapk, 0.040, 0.160)
	var st := clampf(t * (0.75 + 0.25 * sc), 0.011, 0.032)
	return {
		"joint": joint, "pos": pos, "quat": b.get_rotation_quaternion(),
		"size": Vector3(sw, sh, st), "mesh": mesh_id2, "tint": tint_id,
		"prio": prio, "seed": seed, "edge": edge, "signal": sig,
	}


func _pair(joint: String, pos: Vector3, nrm: Vector3, up: Vector3,
		w: float, h: float, t: float, mesh_id: int, tint: int, prio: float,
		seed: float, yaw := 0.0, pitch := 0.0, edge := 0.55, sig := 0.0,
		joint_r := "") -> void:
	if joint_r == "":
		joint_r = joint
	var a := _mk_slot(joint, pos, nrm, up, w, h, t, mesh_id, tint, prio, seed, yaw, pitch, edge, sig)
	slots.append(a)
	var b := a.duplicate()
	b["joint"] = joint_r
	b["pos"] = Vector3(-pos.x, pos.y, pos.z)
	b["quat"] = _mirror_basis(Basis(a["quat"])).get_rotation_quaternion()
	b["seed"] = seed + 17.31
	slots.append(b)


func _band(joint: String, y: float, rx: float, rzf: float, rzb: float,
		angles: Array, h: float, prio: float, tint_a := -1, tint_b := -1,
		edge := 0.55) -> void:
	for ent in angles:
		var adeg: float = ent[0]
		var w: float = ent[1]
		var a := deg_to_rad(adeg)
		var rz := rzf if cos(a) >= 0.0 else rzb
		var pos := Vector3(sin(a) * rx, y, cos(a) * rz)
		var nrm := Vector3(sin(a) / rx, 0.0, cos(a) / rz).normalized()
		var tint := tint_a
		if tint_b >= 0 and int(adeg) % 3 == 2:
			tint = tint_b
		var sd := 11.0 + float(adeg) * 1.7 + float(int(prio * 100.0))
		_pair(joint, pos, nrm, Vector3.UP, w, h, 0.020, -1, tint, prio, sd,
			sin(sd * 7.13) * 6.5, cos(sd * 3.71) * 5.0, edge)


func _limb_ring(joint: String, joint_r: String, y: float, radius: float, items: Array,
		prio: float, base_seed: float, up := Vector3.UP) -> void:
	for ent in items:
		var adeg: float = ent[0]
		var w: float = ent[1]
		var h: float = ent[2]
		var a := deg_to_rad(adeg)
		var nrm := Vector3(sin(a), 0.0, cos(a))
		var pos := nrm * radius + Vector3(0, y, 0)
		var sd2 := base_seed + adeg * 0.9
		_pair(joint, pos, nrm, up, w, h, 0.019, -1, -1, prio, sd2,
			sin(sd2 * 5.31) * 7.0, cos(sd2 * 2.77) * 4.0, 0.45, 0.0, joint_r)


## Full-circumference faceted tube: rows x cols plates on the left joint,
## mirrored onto the right joint.  Gaps are measured in arc length so the
## assembled limb reads as a solid tiled column, not a bare rod.
func _tube(joint: String, joint_r: String, y0: float, y1: float,
		r0: float, r1: float, rows: int, cols: int, prio: float, seed_base: float,
		gap := 0.015, off := 0.004) -> void:
	var gapk := 1.0 + (module_gap - 0.018) * 10.0
	var gp := clampf(gap * gapk, 0.008, 0.030)
	for row in rows:
		var t := (float(row) + 0.5) / float(rows)
		var y := lerpf(y0, y1, t)
		var r := lerpf(r0, r1, t)
		var ph := absf(y1 - y0) / float(rows) - gp
		var pw := TAU * r / float(cols) - gp
		for col in cols:
			var a := TAU * float(col) / float(cols)
			var nrm := Vector3(sin(a), 0.0, cos(a))
			var pos := nrm * (r + off) + Vector3(0, y, 0)
			var sd := seed_base + row * 13.0 + col * 7.3
			_pair(joint, pos, nrm, Vector3.UP, pw, ph, 0.020, -1, -1,
				prio + row * 0.03 + col * 0.008, sd,
				sin(sd * 4.13) * 3.4, cos(sd * 2.71) * 2.4, 0.45, 0.0, joint_r)


func _generate_slots() -> void:
	# ================================================================ chest
	# two solid tile bands; the centre seam carries the sternum signal
	_band("Chest", 0.012, 0.135, 0.105, 0.095,
		[[17.0, 0.120], [78.0, 0.118], [148.0, 0.132]], 0.112, 0.03, -1, -1, 0.5)
	_band("Chest", 0.140, 0.170, 0.118, 0.100,
		[[31.0, 0.140], [86.0, 0.134], [144.0, 0.140]], 0.100, 0.04, -1, -1, 0.5)

	# ================================================================ abdomen
	_band("Spine", 0.062, 0.108, 0.088, 0.078,
		[[34.0, 0.090], [100.0, 0.086]], 0.098, 0.045, -1, -1, 0.4)

	# ================================================================ pelvis
	_band("Pelvis", -0.022, 0.135, 0.100, 0.090,
		[[28.0, 0.120], [88.0, 0.118], [150.0, 0.112]], 0.095, 0.05, -1, -1, 0.4)

	# ================================================================ head
	var hd := "Head"
	var sp := head_scale
	var hs := func(v: Vector3) -> Vector3: return v * sp
	_pair(hd, hs.call(Vector3(0.045, 0.172, 0.045)), Vector3(0.30, 0.62, 0.72), Vector3.UP,
		0.056, 0.042, 0.017, 0, 0, 0.012, 3.1, 7.0, -12.0, 0.9, 0.0)
	_pair(hd, hs.call(Vector3(0.096, 0.100, -0.005)), Vector3(0.98, 0.12, 0.14), Vector3.UP,
		0.040, 0.116, 0.019, 1, 1, 0.016, 5.3, 0.0, -6.0, 0.65, 0.0)
	_pair(hd, hs.call(Vector3(0.088, 0.030, 0.020)), Vector3(0.90, -0.20, 0.38), Vector3.UP,
		0.048, 0.082, 0.017, 2, 0, 0.020, 7.9, -10.0, 0.0, 0.55, 0.0)
	_pair(hd, hs.call(Vector3(0.048, 0.100, -0.076)), Vector3(0.40, 0.12, -0.91), Vector3.UP,
		0.068, 0.098, 0.019, 0, 0, 0.019, 9.7, 0.0, 0.0, 0.45, 0.0)
	_pair(hd, hs.call(Vector3(0.030, 0.172, -0.020)), Vector3(0.30, 0.93, 0.22), Vector3.UP,
		0.050, 0.052, 0.015, 2, 3, 0.024, 13.3, 12.0, 0.0, 0.85, 0.0)

	# ================================================================ arms
	var g := limb_girth
	var shL := "Shoulder_L"
	var shR := "Shoulder_R"
	var elL := "Elbow_L"
	var elR := "Elbow_R"
	var wrL := "Wrist_L"
	var wrR := "Wrist_R"
	# upper arm / forearm: 3-sided tiled tubes
	_tube(shL, shR, -0.055, -0.248, 0.046 * g, 0.041 * g, 2, 3, 0.10, 21.0, 0.014)
	_tube(elL, elR, -0.012, -0.228, 0.041 * g, 0.035 * g, 2, 3, 0.17, 37.0, 0.013)
	# hand plate
	_pair(wrL, Vector3(0.0, -0.040, -0.020), Vector3(0.0, 0.2, -0.98), Vector3.UP,
		0.052, 0.064, 0.015, 1, 1, 0.16, 43.0, 0.0, 0.0, 0.7, 0.0, wrR)

	# ================================================================ legs
	var hipL := "Hip_L"
	var hipR := "Hip_R"
	var knL := "Knee_L"
	var knR := "Knee_R"
	var anL := "Ankle_L"
	var anR := "Ankle_R"
	_tube(hipL, hipR, -0.018, -0.322, 0.072 * g, 0.056 * g, 2, 3, 0.10, 51.0, 0.015)
	_tube(knL, knR, -0.010, -0.410, 0.056 * g, 0.036 * g, 3, 3, 0.16, 61.0, 0.015)
	# foot plates (ankle space; foot points down/forward)
	_pair(anL, Vector3(0.0, -0.058, 0.052), Vector3(0.0, 0.52, 0.85), Vector3.UP,
		0.098, 0.125, 0.020, 1, 1, 0.12, 73.0, 0.0, 0.0, 0.6, 0.0, anR)
	_pair(anL, Vector3(0.0, -0.110, 0.088), Vector3(0.0, -0.05, 0.99), Vector3.UP,
		0.078, 0.100, 0.018, 2, 3, 0.95, 79.0, 0.0, 0.0, 0.55, 0.0, anR)

	# make the hidden abdomen side pair the first casualty at low module counts
	for sl in slots:
		if sl["joint"] == "Spine" and sl["prio"] > 0.044 and sl["prio"] < 0.048:
			sl["prio"] = 0.95
	slots.sort_custom(func(a, b): return a["prio"] < b["prio"])


func select_slots(count: int) -> Array:
	var out: Array = []
	var i := 0
	while i < slots.size() and out.size() + 2 <= count:
		# include priority-equal pairs together
		var g: Array = [slots[i]]
		var j := i + 1
		while j < slots.size() and is_equal_approx(slots[j]["prio"], slots[i]["prio"]) and g.size() < 2:
			g.append(slots[j])
			j += 1
		if out.size() + g.size() <= count:
			out.append_array(g)
		i = j
	return out


# --------------------------------------------------------------------- pose

const JOINT_DEFS := [
	{"k": "pelvis_yaw", "n": "Pelvis", "ax": "y", "g": "PELVIS", "lab": "pelvis yaw", "min": -80.0, "max": 80.0, "v": 0.0},
	{"k": "pelvis_pitch", "n": "Pelvis", "ax": "x", "g": "PELVIS", "lab": "pelvis pitch", "min": -35.0, "max": 35.0, "v": 0.0},
	{"k": "pelvis_roll", "n": "Pelvis", "ax": "z", "g": "PELVIS", "lab": "pelvis roll", "min": -35.0, "max": 35.0, "v": 0.0},
	{"k": "pelvis_height", "n": "Pelvis", "ax": "h", "g": "PELVIS", "lab": "pelvis height", "min": -0.20, "max": 0.20, "v": 0.0},
	{"k": "spine_pitch", "n": "Spine", "ax": "x", "g": "SPINE", "lab": "spine pitch", "min": -30.0, "max": 30.0, "v": 0.0},
	{"k": "spine_yaw", "n": "Spine", "ax": "y", "g": "SPINE", "lab": "spine yaw", "min": -40.0, "max": 40.0, "v": 0.0},
	{"k": "spine_roll", "n": "Spine", "ax": "z", "g": "SPINE", "lab": "spine roll", "min": -25.0, "max": 25.0, "v": 0.0},
	{"k": "chest_pitch", "n": "Chest", "ax": "x", "g": "CHEST", "lab": "chest pitch", "min": -30.0, "max": 30.0, "v": 0.0},
	{"k": "chest_yaw", "n": "Chest", "ax": "y", "g": "CHEST", "lab": "chest yaw", "min": -45.0, "max": 45.0, "v": 0.0},
	{"k": "chest_roll", "n": "Chest", "ax": "z", "g": "CHEST", "lab": "chest roll", "min": -25.0, "max": 25.0, "v": 0.0},
	{"k": "neck_pitch", "n": "Neck", "ax": "x", "g": "HEAD", "lab": "neck pitch", "min": -35.0, "max": 35.0, "v": 0.0},
	{"k": "neck_yaw", "n": "Neck", "ax": "y", "g": "HEAD", "lab": "neck yaw", "min": -45.0, "max": 45.0, "v": 0.0},
	{"k": "head_pitch", "n": "Head", "ax": "x", "g": "HEAD", "lab": "head pitch", "min": -40.0, "max": 40.0, "v": 0.0},
	{"k": "head_yaw", "n": "Head", "ax": "y", "g": "HEAD", "lab": "head yaw", "min": -60.0, "max": 60.0, "v": 0.0},
	{"k": "head_roll", "n": "Head", "ax": "z", "g": "HEAD", "lab": "head roll", "min": -35.0, "max": 35.0, "v": 0.0},
	{"k": "shoulder_L_pitch", "n": "Shoulder_L", "ax": "x", "g": "ARM L", "lab": "shoulder L pitch", "min": -170.0, "max": 80.0, "v": 0.0},
	{"k": "shoulder_L_yaw", "n": "Shoulder_L", "ax": "y", "g": "ARM L", "lab": "shoulder L yaw", "min": -90.0, "max": 90.0, "v": 0.0},
	{"k": "shoulder_L_roll", "n": "Shoulder_L", "ax": "z", "g": "ARM L", "lab": "shoulder L roll", "min": -40.0, "max": 150.0, "v": 0.0},
	{"k": "elbow_L_pitch", "n": "Elbow_L", "ax": "x", "g": "ARM L", "lab": "elbow L pitch", "min": -10.0, "max": 150.0, "v": 0.0},
	{"k": "elbow_L_roll", "n": "Elbow_L", "ax": "z", "g": "ARM L", "lab": "elbow L roll", "min": -110.0, "max": 110.0, "v": 0.0},
	{"k": "wrist_L_pitch", "n": "Wrist_L", "ax": "x", "g": "ARM L", "lab": "wrist L pitch", "min": -110.0, "max": 110.0, "v": 0.0},
	{"k": "wrist_L_yaw", "n": "Wrist_L", "ax": "y", "g": "ARM L", "lab": "wrist L yaw", "min": -180.0, "max": 180.0, "v": 0.0},
	{"k": "wrist_L_roll", "n": "Wrist_L", "ax": "z", "g": "ARM L", "lab": "wrist L roll", "min": -60.0, "max": 60.0, "v": 0.0},
	{"k": "finger_L_curl", "n": "Finger_L", "ax": "x", "g": "ARM L", "lab": "finger L curl", "min": -20.0, "max": 95.0, "v": 0.0},
	{"k": "shoulder_R_pitch", "n": "Shoulder_R", "ax": "x", "g": "ARM R", "lab": "shoulder R pitch", "min": -170.0, "max": 80.0, "v": 0.0},
	{"k": "shoulder_R_yaw", "n": "Shoulder_R", "ax": "y", "g": "ARM R", "lab": "shoulder R yaw", "min": -90.0, "max": 90.0, "v": 0.0},
	{"k": "shoulder_R_roll", "n": "Shoulder_R", "ax": "z", "g": "ARM R", "lab": "shoulder R roll", "min": -150.0, "max": 40.0, "v": 0.0},
	{"k": "elbow_R_pitch", "n": "Elbow_R", "ax": "x", "g": "ARM R", "lab": "elbow R pitch", "min": -10.0, "max": 150.0, "v": 0.0},
	{"k": "elbow_R_roll", "n": "Elbow_R", "ax": "z", "g": "ARM R", "lab": "elbow R roll", "min": -110.0, "max": 110.0, "v": 0.0},
	{"k": "wrist_R_pitch", "n": "Wrist_R", "ax": "x", "g": "ARM R", "lab": "wrist R pitch", "min": -110.0, "max": 110.0, "v": 0.0},
	{"k": "wrist_R_yaw", "n": "Wrist_R", "ax": "y", "g": "ARM R", "lab": "wrist R yaw", "min": -180.0, "max": 180.0, "v": 0.0},
	{"k": "wrist_R_roll", "n": "Wrist_R", "ax": "z", "g": "ARM R", "lab": "wrist R roll", "min": -60.0, "max": 60.0, "v": 0.0},
	{"k": "finger_R_curl", "n": "Finger_R", "ax": "x", "g": "ARM R", "lab": "finger R curl", "min": -20.0, "max": 95.0, "v": 0.0},
	{"k": "hip_L_pitch", "n": "Hip_L", "ax": "x", "g": "LEG L", "lab": "hip L pitch", "min": -80.0, "max": 65.0, "v": 0.0},
	{"k": "hip_L_yaw", "n": "Hip_L", "ax": "y", "g": "LEG L", "lab": "hip L yaw", "min": -40.0, "max": 40.0, "v": 0.0},
	{"k": "hip_L_roll", "n": "Hip_L", "ax": "z", "g": "LEG L", "lab": "hip L roll", "min": -25.0, "max": 50.0, "v": 0.0},
	{"k": "knee_L_pitch", "n": "Knee_L", "ax": "x", "g": "LEG L", "lab": "knee L pitch", "min": -5.0, "max": 110.0, "v": 0.0},
	{"k": "ankle_L_pitch", "n": "Ankle_L", "ax": "x", "g": "LEG L", "lab": "ankle L pitch", "min": -45.0, "max": 55.0, "v": 0.0},
	{"k": "toe_L_pitch", "n": "Toe_L", "ax": "x", "g": "LEG L", "lab": "toe L pitch", "min": -30.0, "max": 60.0, "v": 0.0},
	{"k": "hip_R_pitch", "n": "Hip_R", "ax": "x", "g": "LEG R", "lab": "hip R pitch", "min": -80.0, "max": 65.0, "v": 0.0},
	{"k": "hip_R_yaw", "n": "Hip_R", "ax": "y", "g": "LEG R", "lab": "hip R yaw", "min": -40.0, "max": 40.0, "v": 0.0},
	{"k": "hip_R_roll", "n": "Hip_R", "ax": "z", "g": "LEG R", "lab": "hip R roll", "min": -50.0, "max": 25.0, "v": 0.0},
	{"k": "knee_R_pitch", "n": "Knee_R", "ax": "x", "g": "LEG R", "lab": "knee R pitch", "min": -5.0, "max": 110.0, "v": 0.0},
	{"k": "ankle_R_pitch", "n": "Ankle_R", "ax": "x", "g": "LEG R", "lab": "ankle R pitch", "min": -45.0, "max": 55.0, "v": 0.0},
	{"k": "toe_R_pitch", "n": "Toe_R", "ax": "x", "g": "LEG R", "lab": "toe R pitch", "min": -30.0, "max": 60.0, "v": 0.0},
]

var joint_values: Dictionary = {}
var node_axis: Dictionary = {}


func _build_axis_map() -> void:
	node_axis = {
		"Pelvis": {"x": "pelvis_pitch", "y": "pelvis_yaw", "z": "pelvis_roll"},
		"Spine": {"x": "spine_pitch", "y": "spine_yaw", "z": "spine_roll"},
		"Chest": {"x": "chest_pitch", "y": "chest_yaw", "z": "chest_roll"},
		"Neck": {"x": "neck_pitch", "y": "neck_yaw"},
		"Head": {"x": "head_pitch", "y": "head_yaw", "z": "head_roll"},
	}
	for tag in ["L", "R"]:
		node_axis["Shoulder_" + tag] = {"x": "shoulder_%s_pitch" % tag, "y": "shoulder_%s_yaw" % tag, "z": "shoulder_%s_roll" % tag}
		node_axis["Elbow_" + tag] = {"x": "elbow_%s_pitch" % tag, "z": "elbow_%s_roll" % tag}
		node_axis["Wrist_" + tag] = {"x": "wrist_%s_pitch" % tag, "y": "wrist_%s_yaw" % tag, "z": "wrist_%s_roll" % tag}
		node_axis["Finger_" + tag] = {"x": "finger_%s_curl" % tag}
		node_axis["Hip_" + tag] = {"x": "hip_%s_pitch" % tag, "y": "hip_%s_yaw" % tag, "z": "hip_%s_roll" % tag}
		node_axis["Knee_" + tag] = {"x": "knee_%s_pitch" % tag}
		node_axis["Ankle_" + tag] = {"x": "ankle_%s_pitch" % tag}
		node_axis["Toe_" + tag] = {"x": "toe_%s_pitch" % tag}


func joint_specs() -> Array:
	var out: Array = []
	for d in JOINT_DEFS:
		out.append({
			"group": d["g"], "key": d["k"], "label": d["lab"],
			"min": d["min"], "max": d["max"], "step": 1.0,
			"value": joint_values.get(d["k"], d["v"]),
		})
	return out


func set_joint(key: String, v: float) -> void:
	for d in JOINT_DEFS:
		if d["k"] == key:
			joint_values[key] = clampf(v, d["min"], d["max"])
			_apply_one(d)
			return


func get_joint(key: String) -> float:
	return float(joint_values.get(key, 0.0))


func apply_pose(p: Dictionary) -> void:
	for d in JOINT_DEFS:
		var v := clampf(float(p.get(d["k"], 0.0)), d["min"], d["max"])
		joint_values[d["k"]] = v
		_apply_one(d)
	joints["Pelvis"].position.y = HIP_Y + float(joint_values.get("pelvis_height", 0.0))


func _apply_one(d: Dictionary) -> void:
	var n: Node3D = joints.get(d["n"])
	if n == null:
		return
	if d["ax"] == "h":
		n.position.y = HIP_Y + float(joint_values.get(d["k"], 0.0))
		return
	var ax: Dictionary = node_axis.get(d["n"], {})
	var kx: String = ax.get("x", "")
	var ky: String = ax.get("y", "")
	var kz: String = ax.get("z", "")
	var rx := deg_to_rad(float(joint_values.get(kx, 0.0))) if kx != "" else 0.0
	var ry := deg_to_rad(float(joint_values.get(ky, 0.0))) if ky != "" else 0.0
	var rz := deg_to_rad(float(joint_values.get(kz, 0.0))) if kz != "" else 0.0
	n.basis = Basis(Vector3.RIGHT, rx) * Basis(Vector3.UP, ry) * Basis(Vector3.BACK, rz)


# ------------------------------------------------------------- frame show

func set_frame_visibility(v: float) -> void:
	frame_vis = clampf(v, 0.0, 1.0)
	_apply_frame_visibility()


func set_hover_power(v: float) -> void:
	hover_power = clampf(v, 0.0, 3.0)
	if hover_mat:
		hover_mat.set_shader_parameter("intensity", 3.8 * hover_power)
	_apply_frame_visibility()


func set_thruster_intensity(v: float) -> void:
	if vent_mat:
		vent_mat.set_shader_parameter("intensity", 3.4 * clampf(v, 0.0, 3.0))


func set_retract(v: float) -> void:
	retract = clampf(v, 0.0, 1.0)
	_apply_frame_visibility()


func _apply_frame_visibility() -> void:
	var alive := frame_vis > 0.015 and retract < 0.92
	for e in frame_parts:
		var mi = e["node"]
		if not (mi is MeshInstance3D) or not is_instance_valid(mi):
			continue
		mi.visible = alive
		if not alive:
			continue
		var radial := (0.42 + 0.58 * frame_vis) * (1.0 - 0.72 * retract)
		var along := 1.0 - 0.55 * retract
		var base: Vector3 = e["base"]
		match e["kind"]:
			"rodY":
				mi.scale = Vector3(base.x * radial, base.y * along, base.z * radial)
			"rod":
				mi.scale = Vector3(base.x * along, base.y * radial, base.z * radial)
			_:
				mi.scale = Vector3(base.x * radial, base.y * radial, base.z * radial)
	var hsc := 0.001
	if hover_power > 0.02:
		hsc = 0.55 + 0.45 * minf(hover_power, 3.0)
	for e in hover_parts:
		var hp = e["node"]
		if not (hp is MeshInstance3D) or not is_instance_valid(hp):
			continue
		hp.visible = alive and hover_power > 0.02
		var hb: Vector3 = e["base"]
		hp.scale = hb * (hsc if hp.visible else 0.001)


func hand_emitter_xform(tag: String) -> Transform3D:
	var wr: Node3D = joints["Wrist_" + tag]
	# palm emitter sits at local (0,-0.046,0.02), facing +Z
	return wr.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.046, 0.022))


func head_center() -> Vector3:
	return joints["Head"].global_transform * Vector3(0, 0.085, 0.02)


func chest_center() -> Vector3:
	return joints["Chest"].global_transform * Vector3(0, 0.09, 0.02)