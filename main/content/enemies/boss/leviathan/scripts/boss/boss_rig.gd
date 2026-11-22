extends Node3D
## LEVIATHAN body rig.
##
## Body local frame: +Z = face / aperture axis, +Y = up, +X = right.
##  - fixed rear armour shell (theta 100..180 deg around +Z, r=3.005)
##  - eight raised tentacle sockets on a lower ring (52 deg below the equator)
##  - eight iris blades at r=2.945 (inside the rear shell) that slide outward
##    under the raised sockets and disappear beneath the rear armour at full
##    extension. The aperture grows from 9 deg to 100 deg per side.
##  - gimballed camera eye, free to aim inside the shell
##  - plasma core + transparent containment wall for phase 2

const MK := preload("res://scripts/kit/mesh_kit.gd")
const SK := preload("res://scripts/kit/shape_kit.gd")
const BM := preload("res://scripts/boss/boss_materials.gd")
const D2R := PI / 180.0
const TAU := PI * 2.0
const R := 3.0
const SOCKET_BETA := 52.0 * PI / 180.0
const SOCKET_Y := -cos(SOCKET_BETA)

var body: Node3D
var blade_nodes: Array[Node3D] = []
var blade_base: Array[Basis] = []
var eye_yaw: Node3D
var eye_pitch: Node3D
var eye_slide: Node3D
var eye_lens_mat: ShaderMaterial
var orb_mi: MeshInstance3D
var orb_outer_mi: MeshInstance3D
var core_mi: MeshInstance3D
var glass_mi: MeshInstance3D
var core_spin: Node3D
var core_light: OmniLight3D
var eye_light: OmniLight3D
var rim_light: OmniLight3D
var gate_light: OmniLight3D
var orb_mat: ShaderMaterial
var orb_outer_mat: ShaderMaterial
var core_mat: ShaderMaterial
var glass_mat: ShaderMaterial

var aperture := 0.30
var aperture_ring: MeshInstance3D
var aperture_glow: MeshInstance3D
var phase2_t := 0.0
var yaw := 0.0
var pitch := -0.12
var spin := 0.0


func build() -> void:
	for c in get_children():
		c.free()
	blade_nodes.clear()
	blade_base.clear()
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	_build_rear_shell()
	_build_sockets()
	_build_cage()
	_build_eye()
	_build_core()
	_build_blades()
	_build_aperture_ring()
	_build_lights()
	set_shell(0.30)
	set_phase2(0.0)


# ------------------------------------------------------------------ helpers

func _add_parts(host: Node3D, parts: Array) -> void:
	for e in SK.bake(parts):
		var mi := MeshInstance3D.new()
		mi.mesh = e["mesh"]
		mi.material_override = e["mat"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		host.add_child(mi)


func _p(parts: Array, mesh: Mesh, mat: Material, xf := Transform3D.IDENTITY) -> void:
	if mesh == null:
		return
	parts.append({"mesh": mesh, "mat": mat, "xf": xf})


func _p_pos(parts: Array, mesh: Mesh, mat: Material, pos: Vector3,
		basis := Basis.IDENTITY) -> void:
	_p(parts, mesh, mat, Transform3D(basis, pos))


func _ring_at(parts: Array, r_in: float, r_out: float, t: float, sides: int,
		pos: Vector3, axis: Vector3, mat: Material, bevel := 0.0) -> void:
	var b := SK.basis_y(axis)
	_p_pos(parts, MK.ring(r_in, r_out, t, sides, bevel), mat, pos, b)


func _disc_at(parts: Array, r: float, t: float, sides: int, pos: Vector3,
		axis: Vector3, mat: Material, bevel := 0.0) -> void:
	var b := SK.basis_y(axis)
	_p_pos(parts, MK.disc(r, t, sides, bevel), mat, pos, b)


func _front_basis() -> Basis:
	# maps mesh-local +Y to body +Z, local +Z to body +X, local +X to body +Y
	return Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))


static func socket_dir(k: int) -> Vector3:
	var phi := (22.5 + 45.0 * float(k)) * D2R
	var sb := sin(SOCKET_BETA)
	return Vector3(sb * cos(phi), SOCKET_Y, sb * sin(phi)).normalized()


func _socket_dir(k: int) -> Vector3:
	return socket_dir(k)

	var phi := (22.5 + 45.0 * float(k)) * D2R
	var sb := sin(SOCKET_BETA)
	return Vector3(sb * cos(phi), SOCKET_Y, sb * sin(phi)).normalized()


# --------------------------------------------------------------- rear shell

func _build_rear_shell() -> void:
	var parts: Array = []
	var fb := _front_basis()
	var h := BM.hull()
	var hs := BM.hull_soft()
	var trim := BM.steel_dark()
	var steel := BM.steel()
	var glow := BM.emissive(Color(1.0, 0.26, 0.05), 3.2)
	var glow2 := BM.emissive(Color(1.0, 0.55, 0.16), 2.2)

	# main spherical rear armour (single surface: the iris slides in the cavity
	# between this shell and the liner below)
	_p(parts, MK.arc_shell(R + 0.005, 0.0, 100.0 * D2R, PI, 0.0, TAU, 34, 96, true, false),
		h, Transform3D(fb, Vector3.ZERO))
	# inner liner: faces the aperture, closes the cavity from inside
	_p(parts, MK.arc_shell(2.76, 0.06, 100.0 * D2R, PI, 0.0, TAU, 30, 88, true, true),
		hs, Transform3D(fb, Vector3.ZERO))
	# liner edge ring (flat, sits behind the blade path)
	_ring_at(parts, 2.66, 2.80, 0.06, 96, Vector3(0, 0, 2.76 * cos(100.0 * D2R)),
		Vector3(0, 0, 1), trim, 0.01)

	# raised latitude bands
	for th in [108.0, 121.0, 137.0, 155.0, 171.0]:
		var t0: float = float(th) * D2R
		_p(parts, MK.arc_shell(R + 0.022, 0.026, t0, t0 + 1.6 * D2R, 0.0, TAU, 4, 96, true, true),
			hs, Transform3D(fb, Vector3.ZERO))
	# meridian seams
	for k in 16:
		var ph := (float(k) * 22.5) * D2R
		_p(parts, MK.arc_shell(R + 0.020, 0.018, 103.0 * D2R, 178.0 * D2R,
			ph - 0.5 * D2R, ph + 0.5 * D2R, 24, 2, true, false),
			trim, Transform3D(fb, Vector3.ZERO))

	# aperture lip: a thin spherical band on the OUTER shell edge, never in the
	# path of the recessed iris blades
	var zr := (R + 0.005) * cos(100.0 * D2R)
	var rr := (R + 0.005) * sin(100.0 * D2R)
	_p(parts, MK.arc_shell(3.018, 0.030, 98.2 * D2R, 101.2 * D2R, 0.0, TAU, 5, 96, true, true),
		steel, Transform3D(fb, Vector3.ZERO))
	_p(parts, MK.arc_shell(3.030, 0.014, 99.2 * D2R, 100.1 * D2R, 0.0, TAU, 3, 96, true, true),
		glow, Transform3D(fb, Vector3.ZERO))
	# bolts round the lip (outside the blade radius)
	for k in 32:
		var ph := TAU * float(k) / 32.0
		var th := 97.4 * D2R
		var n := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
		_disc_at(parts, 0.045, 0.025, 8, n * (R + 0.030), n, trim, 0.006)

	# frame struts across the rear cap (mechanical ribs)
	for k in 8:
		var ph2 := (22.5 + 45.0 * float(k)) * D2R
		var d := Vector3(cos(ph2), sin(ph2), 0.0)
		_p(parts, SK.beam(d * 1.15, d * 2.92, 0.15, 0.18, 0.09, 0.12, 0.3),
			steel, Transform3D(Basis.IDENTITY, Vector3(0, 0, zr - 1.15)))
	# small running lights on rear shell
	for k in 12:
		var th := (112.0 + 6.0 * float(k % 5)) * D2R
		var ph3 := (float(k) * 30.0 + 15.0) * D2R
		var n := Vector3(sin(th) * cos(ph3), cos(th), sin(th) * sin(ph3))
		var pos := n * (R + 0.035)
		_disc_at(parts, 0.075, 0.03, 10, pos, n, glow2 if k % 2 == 0 else glow, 0.0)
	# eight larger reactor vents, still on the rear armour
	for k in 8:
		var th2 := 124.0 * D2R
		var ph4 := (float(k) * 45.0 + 22.5) * D2R
		var n2 := Vector3(sin(th2) * cos(ph4), cos(th2), sin(th2) * sin(ph4))
		_disc_at(parts, 0.135, 0.045, 12, n2 * (R + 0.048), n2, glow, 0.012)
		_disc_at(parts, 0.185, 0.035, 12, n2 * (R + 0.026), n2, steel, 0.0)
	# rear reactor ring / exhaust
	_ring_at(parts, 0.56, 0.86, 0.12, 64, Vector3(0, 0, -R + 0.01), Vector3(0, 0, 1), steel, 0.02)
	_ring_at(parts, 0.60, 0.66, 0.035, 64, Vector3(0, 0, -R + 0.08), Vector3(0, 0, 1), glow, 0.0)
	_p_pos(parts, MK.disc(0.66, 0.10, 48, 0.02), trim, Vector3(0, 0, -R + 0.06), fb)
	_p_pos(parts, MK.disc(0.30, 0.06, 32, 0.01), glow2, Vector3(0, 0, -R + 0.12), fb)

	_add_parts(body, parts)


# ------------------------------------------------------------------ sockets

func _build_sockets() -> void:
	var parts: Array = []
	var boot := BM.rubber()
	var hull := BM.hull()
	var steel := BM.steel()
	var trim := BM.steel_dark()
	var glow := BM.emissive(Color(1.0, 0.30, 0.06), 3.6)
	for k in 8:
		var dir := _socket_dir(k)
		var b := SK.basis_y(dir)
		var base := dir * R
		# tapered socket drum
		_p_pos(parts, MK.prism(14, 0.56, 0.47, 0.38), hull, base + dir * 0.16, b)
		# outer clamp collar
		_ring_at(parts, 0.40, 0.55, 0.09, 40, base + dir * 0.35, dir, steel, 0.015)
		# flexible boot
		_p_pos(parts, MK.prism(14, 0.40, 0.36, 0.26), boot, base + dir * 0.49, b)
		_ring_at(parts, 0.365, 0.44, 0.045, 32, base + dir * 0.60, dir, glow, 0.0)
		# clamp ears
		var tangent := dir.cross(Vector3.UP)
		if tangent.length_squared() < 1e-4:
			tangent = dir.cross(Vector3.RIGHT)
		tangent = tangent.normalized()
		var bit := tangent.cross(dir).normalized()
		for e in 4:
			var a := TAU * float(e) / 4.0 + 0.4
			var off := tangent * cos(a) * 0.47 + bit * sin(a) * 0.47
			var bb := Basis(tangent, a)
			_p_pos(parts, MK.plate(0.22, 0.20, 0.07, 0.012), trim,
				base + dir * 0.34 + off, bb)
			_disc_at(parts, 0.035, 0.03, 6, base + dir * 0.39 + off * 1.02, dir, steel, 0.0)
		# inner recess
		_disc_at(parts, 0.39, 0.03, 28, base + dir * 0.62, dir, BM.joint(), 0.0)
	_add_parts(body, parts)


# --------------------------------------------------------------------- cage

func _build_cage() -> void:
	var parts: Array = []
	var steel := BM.steel_dark()
	var trim := BM.trim()
	var glow := BM.emissive(Color(1.0, 0.22, 0.04), 2.6)
	var fb := _front_basis()
	# meridian ribs
	for k in 8:
		var ph := (22.5 + 45.0 * float(k) + 22.5) * D2R
		_p(parts, MK.arc_shell(2.74, 0.035, 12.0 * D2R, 165.0 * D2R,
			ph - 1.4 * D2R, ph + 1.4 * D2R, 28, 2, true, false),
			steel, Transform3D(fb, Vector3.ZERO))
	# latitude rings
	for th in [38.0, 72.0, 108.0, 143.0]:
		var t0: float = float(th) * D2R
		_p(parts, MK.arc_shell(2.73, 0.030, t0, t0 + 1.2 * D2R, 0.0, TAU, 3, 72, true, false),
			trim, Transform3D(fb, Vector3.ZERO))
	# front gimbal frame ring
	_ring_at(parts, 2.22, 2.40, 0.14, 96, Vector3(0, 0, 0.10), Vector3(0, 0, 1), trim, 0.02)
	_ring_at(parts, 2.29, 2.33, 0.020, 96, Vector3(0, 0, 0.18), Vector3(0, 0, 1), BM.emissive(Color(1.0, 0.20, 0.04), 0.5), 0.0)
	# radial spokes to the ring
	for k in 6:
		var a := TAU * float(k) / 6.0 + 0.2
		var d := Vector3(cos(a), sin(a), 0.0)
		_p(parts, SK.beam(d * 2.35, d * 2.66 + Vector3(0, 0, -0.55),
			0.10, 0.12, 0.07, 0.09, 0.3), steel, Transform3D.IDENTITY)
	# rear hub
	var zr := R * cos(100.0 * D2R)
	_ring_at(parts, 0.62, 1.02, 0.22, 48, Vector3(0, 0, zr - 0.95), Vector3(0, 0, 1), steel, 0.02)
	_p_pos(parts, MK.prism(20, 0.55, 0.42, 1.0), trim, Vector3(0, 0, zr - 1.55), fb)
	_ring_at(parts, 0.44, 0.56, 0.06, 40, Vector3(0, 0, zr - 2.05), Vector3(0, 0, 1), glow, 0.0)
	# conduits
	for k in 6:
		var a := TAU * float(k) / 6.0 + 0.35
		var d := Vector3(cos(a), sin(a), 0.0)
		var p0 := d * 0.65 + Vector3(0, 0, zr - 1.70)
		var p1 := d * 2.30 + Vector3(0, 0, zr - 0.60)
		_p(parts, SK.beam(p0, p1, 0.11, 0.11, 0.07, 0.07, 0.3), BM.rubber(), Transform3D.IDENTITY)
	_add_parts(body, parts)


# ---------------------------------------------------------------------- eye

func _build_eye() -> void:
	eye_yaw = Node3D.new()
	eye_yaw.name = "EyeYaw"
	body.add_child(eye_yaw)

	var parts: Array = []
	var hull := BM.hull()
	var hulls := BM.hull_soft()
	var steel := BM.steel()
	var trim := BM.steel_dark()
	var glow := BM.emissive(Color(1.0, 0.16, 0.03), 3.0)
	var fb := _front_basis()

	# big horizontal gimbal ring (fixed to yaw)
	_ring_at(parts, 1.56, 1.74, 0.12, 72, Vector3.ZERO, Vector3.UP, steel, 0.02)
	_ring_at(parts, 1.60, 1.66, 0.028, 72, Vector3.ZERO, Vector3.UP, glow, 0.0)
	for s in [1.0, -1.0]:
		_disc_at(parts, 0.17, 0.16, 12, Vector3(1.62 * s, 0, 0), Vector3.RIGHT, trim, 0.01)
		_disc_at(parts, 0.09, 0.03, 10, Vector3(1.70 * s, 0, 0), Vector3.RIGHT, steel, 0.0)
	_add_parts(eye_yaw, parts)

	eye_pitch = Node3D.new()
	eye_pitch.name = "EyePitch"
	eye_yaw.add_child(eye_pitch)
	var pp: Array = []
	# pitch ring (axis X)
	var bx := Basis(Vector3(0, 0, 1), -PI * 0.5)
	_p_pos(pp, MK.ring(1.44, 1.58, 0.10, 64, 0.02), steel, Vector3.ZERO, bx)
	_p_pos(pp, MK.ring(1.47, 1.52, 0.025, 64, 0.0), glow, Vector3.ZERO, bx)

	# pod: dark sphere + barrel + lens
	_p_pos(pp, MK.sphere(1.16, 26, 40, true), hull, Vector3.ZERO)
	_p_pos(pp, MK.sphere(1.185, 18, 32, false), hulls, Vector3.ZERO, Basis.IDENTITY)
	# rear counterweight
	_p_pos(pp, MK.prism(20, 0.68, 0.44, 0.55), trim, Vector3(0, 0, -1.38), fb)
	_p_pos(pp, MK.ring(0.40, 0.62, 0.10, 32, 0.02), steel, Vector3(0, 0, -1.05), fb)
	# barrel stages
	_p_pos(pp, MK.prism(32, 1.14, 1.10, 0.28), hulls, Vector3(0, 0, 0.95), fb)
	_p_pos(pp, MK.ring(1.06, 1.19, 0.10, 48, 0.02), trim, Vector3(0, 0, 1.12), fb)
	_p_pos(pp, MK.prism(40, 1.02, 1.01, 0.34), hull, Vector3(0, 0, 1.30), fb)
	_p_pos(pp, MK.ring(0.94, 1.10, 0.13, 56, 0.025), steel, Vector3(0, 0, 1.50), fb)
	# bolt ring around the lens
	for k in 18:
		var a := TAU * float(k) / 18.0
		var pos := Vector3(cos(a) * 1.035, sin(a) * 1.035, 1.585)
		_disc_at(pp, 0.065, 0.03, 6, pos, Vector3(0, 0, 1), trim, 0.006)
	# lens
	var lens := MK.dome(1.00, 0.34, 48, 12, true)
	eye_lens_mat = BM.lens()
	var lens_mi := MeshInstance3D.new()
	lens_mi.mesh = lens
	lens_mi.material_override = eye_lens_mat
	lens_mi.transform = Transform3D(fb, Vector3(0, 0, 1.56))
	lens_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eye_pitch.add_child(lens_mi)
	# inner iris trim behind the glass
	_p_pos(pp, MK.disc(0.98, 0.05, 48), BM.joint(), Vector3(0, 0, 1.54), fb)
	_add_parts(eye_pitch, pp)

	# slide node for phase 2 retraction (contains the whole eye visuals? pitch
	# already does; we instead move eye_yaw's visual scale via pod offset)
	# eye_pitch is translated backwards in set_phase2.
	eye_slide = eye_pitch

	# gimbal support struts from the cage to the yaw ring
	var sp: Array = []
	for k in 4:
		var a3 := TAU * float(k) / 4.0 + 0.78
		var d := Vector3(cos(a3), sin(a3), 0.0)
		_p(sp, SK.beam(d * 1.72, d * 2.42 + Vector3(0, 0, -0.35), 0.08, 0.08, 0.05, 0.05, 0.3),
			BM.steel_dark(), Transform3D.IDENTITY)
	_add_parts(body, sp)


# --------------------------------------------------------------------- core

func _build_core() -> void:
	orb_mat = BM.orb()
	orb_outer_mat = BM.orb().duplicate() as ShaderMaterial
	orb_outer_mat.set_shader_parameter("energy", 0.6)
	orb_outer_mat.set_shader_parameter("opacity", 0.55)
	core_mat = BM.core()

	orb_mi = MeshInstance3D.new()
	orb_mi.mesh = MK.sphere(1.0, 32, 48, true)
	orb_mi.material_override = orb_mat
	orb_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(orb_mi)

	orb_outer_mi = MeshInstance3D.new()
	orb_outer_mi.mesh = MK.sphere(1.22, 24, 36, true)
	orb_outer_mi.material_override = orb_outer_mat
	orb_outer_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(orb_outer_mi)

	core_mi = MeshInstance3D.new()
	core_mi.mesh = MK.sphere(0.78, 24, 36, true)
	core_mi.material_override = core_mat
	core_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(core_mi)

	# rotating containment rings
	core_spin = Node3D.new()
	body.add_child(core_spin)
	var sp: Array = []
	var bx := Basis(Vector3(0, 0, 1), 0.4)
	var bz := Basis(Vector3(1, 0, 0), 0.9)
	_p_pos(sp, MK.ring(1.86, 1.94, 0.055, 80, 0.01), BM.steel(), Vector3.ZERO, bx)
	_p_pos(sp, MK.ring(2.02, 2.08, 0.035, 80, 0.0), BM.emissive(Color(1.0, 0.22, 0.04), 2.6), Vector3.ZERO, bz)
	_add_parts(core_spin, sp)

	# fixed core cage arcs
	var cp: Array = []
	var fb := _front_basis()
	for k in 5:
		var ph := (float(k) * 72.0 + 18.0) * D2R
		_p(cp, MK.arc_shell(2.16, 0.03, 26.0 * D2R, 154.0 * D2R,
			ph - 1.2 * D2R, ph + 1.2 * D2R, 22, 2, true, false),
			BM.steel_dark(), Transform3D(fb, Vector3.ZERO))
	_add_parts(body, cp)

	# transparent containment wall
	glass_mat = BM.glass()
	glass_mi = MeshInstance3D.new()
	glass_mi.mesh = MK.sphere(3.58, 32, 64, true)
	glass_mi.material_override = glass_mat
	glass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass_mi.visible = false
	body.add_child(glass_mi)

	# faint inner energy shell visible at partial open
	set_phase2(0.0)


# -------------------------------------------------------------------- blades

func _build_blades() -> void:
	var base_basis := _front_basis()
	for k in 8:
		var phi := (float(k) * 45.0) * D2R
		var pivot := Node3D.new()
		pivot.name = "Blade%d" % k
		body.add_child(pivot)
		var bb := Basis(
			Vector3(-sin(phi), cos(phi), 0.0),
			Vector3(0.0, 0.0, 1.0),
			Vector3(cos(phi), sin(phi), 0.0))
		pivot.basis = bb
		blade_base.append(bb)
		blade_nodes.append(pivot)

		var rr := 2.880 + 0.005 * float(k)
		var parts: Array = []
		var hull := BM.hull()
		var trim := BM.steel_dark()
		var steel := BM.steel()
		var glow := BM.emissive(Color(1.0, 0.26, 0.05), 2.5)
		# main curved plate
		_p(parts, MK.arc_shell(rr, 0.045, 9.0 * D2R, 100.0 * D2R,
			-24.0 * D2R, 24.0 * D2R, 28, 12, true, true),
			hull, Transform3D.IDENTITY)


		# meridian ribs (start outside the aperture)
		for j in [-15.0, 0.0, 15.0]:
			_p(parts, MK.arc_shell(rr + 0.032, 0.026, 36.0 * D2R, 96.0 * D2R,
				(j - 0.9) * D2R, (j + 0.9) * D2R, 22, 2, true, false),
				steel, Transform3D.IDENTITY)
		# side edge trims
		for j in [-22.6, 22.6]:
			_p(parts, MK.arc_shell(rr + 0.028, 0.022, 12.0 * D2R, 98.0 * D2R,
				(j - 0.7) * D2R, (j + 0.7) * D2R, 26, 2, true, false),
				trim, Transform3D.IDENTITY)
		# one glowing seam per blade; starts outside the aperture so the rim
		# never reads as lit teeth
		_p(parts, MK.arc_shell(rr + 0.044, 0.010, 34.0 * D2R, 94.0 * D2R,
			22.2 * D2R, 22.8 * D2R, 20, 2, true, false),
			BM.emissive(Color(1.0, 0.18, 0.030), 1.0), Transform3D.IDENTITY)
		# outer lip
		_p(parts, MK.arc_shell(rr + 0.016, 0.030, 96.0 * D2R, 100.0 * D2R,
			-24.0 * D2R, 24.0 * D2R, 3, 12, true, true),
			trim, Transform3D.IDENTITY)
		# panel band
		_p(parts, MK.arc_shell(rr + 0.014, 0.012, 60.0 * D2R, 63.0 * D2R,
			-23.0 * D2R, 23.0 * D2R, 2, 12, true, false),
			trim, Transform3D.IDENTITY)

		_add_parts(pivot, parts)


func _build_aperture_ring() -> void:
	# A continuous machined guide ring at the iris aperture edge. It hides the
	# stepped blade edges and gives the shell a clean camera-iris lip.
	aperture_ring = MeshInstance3D.new()
	aperture_ring.mesh = MK.ring(0.975, 1.13, 0.09, 96, 0.02)
	aperture_ring.material_override = BM.steel_dark()
	aperture_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(aperture_ring)
	aperture_glow = MeshInstance3D.new()
	aperture_glow.mesh = MK.ring(0.962, 0.994, 0.028, 96, 0.0)
	aperture_glow.material_override = BM.emissive(Color(1.0, 0.20, 0.035), 1.35)
	aperture_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(aperture_glow)


# -------------------------------------------------------------------- lights

func _build_lights() -> void:
	core_light = OmniLight3D.new()
	core_light.position = Vector3(0, 0, 0)
	core_light.light_color = Color(1.0, 0.13, 0.03)
	core_light.light_energy = 0.0
	core_light.omni_range = 16.0
	core_light.omni_attenuation = 1.6
	core_light.shadow_enabled = false
	body.add_child(core_light)

	eye_light = OmniLight3D.new()
	eye_light.position = Vector3(0, 0, 1.8)
	eye_light.light_color = Color(1.0, 0.20, 0.05)
	eye_light.light_energy = 1.8
	eye_light.omni_range = 7.0
	eye_light.shadow_enabled = false
	eye_yaw.add_child(eye_light)

	rim_light = OmniLight3D.new()
	rim_light.position = Vector3(0, -0.6, -3.4)
	rim_light.light_color = Color(0.45, 0.10, 0.04)
	rim_light.light_energy = 2.2
	rim_light.omni_range = 9.0
	rim_light.shadow_enabled = false
	body.add_child(rim_light)

	gate_light = OmniLight3D.new()
	gate_light.position = Vector3(0, 0, 1.2)
	gate_light.light_color = Color(1.0, 0.24, 0.06)
	gate_light.light_energy = 1.2
	gate_light.omni_range = 11.0
	gate_light.shadow_enabled = false
	body.add_child(gate_light)


# --------------------------------------------------------------------- state

func set_shell(a: float) -> void:
	aperture = clampf(a, 0.0, 1.0)
	var alpha: float = deg_to_rad(lerpf(1.4, 88.0, aperture))
	for k in blade_nodes.size():
		var stag := 1.0 + 0.018 * sin(float(k) * 1.31 + 0.4)
		blade_nodes[k].basis = blade_base[k] * Basis(Vector3(1, 0, 0), alpha * stag)
	if aperture_ring:
		var th := deg_to_rad(9.0) + alpha
		var ra := 2.880 * sin(th)
		var za := 2.880 * cos(th) + 0.10
		var sb := Basis(Vector3(1, 0, 0), PI * 0.5)
		var xf := Transform3D(sb * Basis.from_scale(Vector3.ONE * ra), Vector3(0, 0, za))
		aperture_ring.transform = xf
		aperture_glow.transform = xf


func set_phase2(t: float) -> void:
	phase2_t = clampf(t, 0.0, 1.0)
	var s := phase2_t
	# eye retracts into the core, lens dims
	if eye_pitch:
		eye_pitch.position = Vector3(0, 0, -0.34 * s)
	if eye_lens_mat:
		eye_lens_mat.set_shader_parameter("intensity", lerpf(3.6, 0.55, s))
		eye_lens_mat.set_shader_parameter("alert", lerpf(0.38, 0.05, s))
	if eye_light:
		eye_light.light_energy = lerpf(3.0, 0.5, s)
		eye_light.position = Vector3(0, 0, lerpf(1.8, 0.8, s))
	if orb_mi:
		var sc := lerpf(0.30, 2.08, s)
		orb_mi.scale = Vector3.ONE * sc
		orb_mi.visible = s > 0.015
		orb_mat.set_shader_parameter("energy", lerpf(0.15, 1.15, s))
		orb_mat.set_shader_parameter("opacity", smoothstep(0.0, 0.25, s))
		orb_outer_mi.scale = Vector3.ONE * lerpf(0.40, 2.34, s)
		orb_outer_mi.visible = s > 0.015
		orb_outer_mat.set_shader_parameter("opacity", 0.20 + 0.45 * s)
		orb_outer_mat.set_shader_parameter("energy", lerpf(0.2, 0.75, s))
	if core_mi:
		core_mi.scale = Vector3.ONE * lerpf(0.42, 2.45, s)
		core_mi.visible = s > 0.01
		core_mat.set_shader_parameter("energy", lerpf(0.4, 1.45, s))
	if core_light:
		core_light.light_energy = 18.0 * smoothstep(0.05, 0.95, s)
	if glass_mi:
		glass_mi.visible = s > 0.02
		glass_mat.set_shader_parameter("opacity", 0.16 * smoothstep(0.05, 0.85, s))
		glass_mat.set_shader_parameter("energy", 0.35 + 0.65 * s)
	if gate_light:
		gate_light.light_energy = lerpf(1.6, 5.0, s)


func update_eye(local_dir: Vector3, dt: float) -> void:
	var d := local_dir.normalized()
	var ty := atan2(d.x, d.z)
	var tp := asin(clampf(d.y, -1.0, 1.0))
	ty = clampf(ty, deg_to_rad(-78.0), deg_to_rad(78.0))
	tp = clampf(tp, deg_to_rad(-62.0), deg_to_rad(58.0))
	var k := 1.0 - exp(-6.0 * dt)
	yaw = lerp_angle(yaw, ty, k)
	pitch = lerpf(pitch, tp, k)
	eye_yaw.rotation.y = yaw
	eye_pitch.rotation.x = -pitch


func tick_core(dt: float) -> void:
	spin += dt * 0.45
	core_spin.rotation.z = spin * 0.7
	core_spin.rotation.x = spin * 0.35


func lens_target(target_local: Vector3) -> Vector3:
	return target_local


func blade_radius(k: int) -> float:
	return 2.945 + 0.006 * float(k)


func aperture_half_angle() -> float:
	return lerpf(9.0, 100.0, aperture)