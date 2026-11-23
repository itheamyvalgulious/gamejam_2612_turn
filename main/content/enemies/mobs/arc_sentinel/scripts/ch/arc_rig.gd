extends Node3D
class_name ArcRig3
## ARC // GRINDER v3 — procedural skeleton + geometry.
##
## Two triangular track units flank a chamfered cube turret.  The cube carries
## a shallow socketed red optic on its front face (fixed metal shell, rotating
## inner ball) and a single 3-ball-joint arm rising from its top deck, ending in
## an arc-blade emitter.  Everything is generated from code; geometry is merged
## per (node, material) to keep draw calls low.
##
## Track belts / wheels are a separate locomotion layer: body clips never touch
## them, and each side integrates its own ground speed (differential steering).

const MK := preload("res://scripts/kit/mesh_kit.gd")
const SK := preload("res://scripts/kit/shape_kit.gd")
const AM := preload("res://scripts/ch/arc_materials.gd")
const KIN := preload("res://scripts/ch/arc_kin.gd")
const D2R := PI / 180.0
const TAU := PI * 2.0
## Hard ground-speed cap for one track (m/s). The 1.56 m chassis only needs
## 3 m/s; anything above reads as an RC toy.
const MAX_TRACK_SPEED := 3.0

var J: Dictionary = {}
var P: Dictionary = {}
var kin: ArcKin3

## Locomotion is its own layer, independent of the body/arm clips. Each side
## integrates its own signed ground speed; the belt phase and the wheel angle
## are both derived from that distance, so they can never disagree.
var track_vel := Vector2.ZERO      # (left, right) m/s, +Z forward
var track_dist := Vector2.ZERO     # (left, right) metres travelled forward

var marker_tip: Node3D
var marker_base: Node3D
var blade_fx: Node3D
var blade_light: OmniLight3D
var eye_light: OmniLight3D

var _belts: Dictionary = {}

var cube := 0.56
var cube_half := 0.28
var body_y := 0.80
var shoulder_local := Vector3.ZERO
var L1 := 0.44
var L2 := 0.38
var L3 := 0.115
var cam_z := 0.245
var cam_face := 0.260
var cam_ap := 0.1733
var cam_r := 0.145
var cam_shell_z := 0.302
var cam_shell_r := 0.192
var _leds: Array = []
var track_x := 0.44
var track_hw := 0.10
var wheel_r := 0.142
var track_r := 0.192


# ================================================================== build

func build(p: Dictionary) -> void:
	P = p.duplicate()
	kin = KIN.new(P)
	_dims()
	for c in get_children():
		c.free()
	J.clear()
	_belts.clear()
	_leds.clear()
	_build_skeleton()
	_build_chassis()
	_build_track(1)
	_build_track(-1)
	_build_turret()
	_build_optic()
	_build_arm()
	_build_blade_fx()
	_build_lights()
	apply_pose({})
	_apply_tracks()


func _dims() -> void:
	cube = kin.cube
	cube_half = kin.cube_half
	body_y = kin.body_y
	shoulder_local = kin.shoulder_local
	L1 = kin.L1
	L2 = kin.L2
	L3 = kin.L3
	cam_z = kin.cam_z
	cam_face = kin.cam_face
	cam_ap = kin.cam_ap
	cam_r = kin.cam_r
	cam_shell_z = kin.cam_shell_z
	cam_shell_r = kin.cam_shell_r
	track_x = kin.track_x
	track_hw = kin.track_hw
	wheel_r = kin.wheel_r
	track_r = kin.track_r


func _node(parent: Node3D, nm: String, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	J[nm] = n
	return n


func _build_skeleton() -> void:
	var root := _node(self, "root", Vector3.ZERO)
	var body := _node(root, "body", Vector3(0, body_y, 0))
	var eye := _node(body, "eye_aim", Vector3(0, 0, cam_z))
	_node(body, "optic_shell", Vector3.ZERO)
	var sh := _node(body, "sh", shoulder_local)
	var elb := _node(sh, "elb", Vector3(0, -L1, 0))
	var wr := _node(elb, "wr", Vector3(0, -L2, 0))
	var tool := _node(wr, "tool", Vector3(0, -L3, 0))
	var bfx := _node(tool, "blade_fx", Vector3.ZERO)
	bfx.rotation.x = PI
	blade_fx = bfx
	marker_base = _node(tool, "marker_base", Vector3.ZERO)
	marker_tip = _node(tool, "marker_tip", Vector3(0, -kin.blade_len, 0))
	eye.name = "eye_aim"
	_belt_node(root, 1)
	_belt_node(root, -1)


func _belt_node(root: Node3D, side: int) -> void:
	var nm := "trackL" if side > 0 else "trackR"
	var n := _node(root, nm, Vector3(float(side) * track_x, 0.0, 0.0))
	n.set_meta("side", side)
	for i in 3:
		var w := _node(n, "wheel_%s%d" % [nm, i], Vector3.ZERO)
		w.set_meta("side", side)


# ================================================================== geo utils

func _bake(node: Node3D, parts: Array) -> void:
	for e in SK.bake(parts):
		var mi := MeshInstance3D.new()
		mi.mesh = e["mesh"]
		mi.material_override = e["mat"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.add_child(mi)


func _p(parts: Array, mesh: Mesh, mat: Material, pos := Vector3.ZERO,
		rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> void:
	if mesh == null:
		return
	var b := Basis.from_euler(rot_deg * D2R)
	if scl != Vector3.ONE:
		b = b * Basis.from_scale(scl)
	parts.append({"mesh": mesh, "mat": mat, "xf": Transform3D(b, pos)})


func _disc(parts: Array, r: float, t: float, sides: int, pos: Vector3,
		axis: Vector3, mat: Material, bevel := 0.0, hint := Vector3.RIGHT) -> void:
	parts.append({"mesh": MK.disc(r, t, sides, bevel), "mat": mat,
		"xf": Transform3D(SK.basis_y(axis, hint), pos)})


func _ring(parts: Array, r_in: float, r_out: float, t: float, sides: int,
		pos: Vector3, axis: Vector3, mat: Material, bevel := 0.0,
		hint := Vector3.RIGHT) -> void:
	parts.append({"mesh": MK.ring(r_in, r_out, t, sides, bevel), "mat": mat,
		"xf": Transform3D(SK.basis_y(axis, hint), pos)})


func _tri3(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, guide: Vector3) -> void:
	var g := (b - a).cross(c - a)
	if g.length_squared() < 1e-14:
		return
	if g.dot(guide) < 0.0:
		var t := b
		b = c
		c = t
		g = -g
	var n := g.normalized()
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_normal(n)
	st.add_vertex(b)


func _quad3(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		guide: Vector3) -> void:
	_tri3(st, a, b, c, guide)
	_tri3(st, a, c, d, guide)


## Extrude a convex polygon given in the (z, y) plane along X.
func _extrude_x(pts: Array, thick: float, bevel: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	if n < 3:
		return st.commit()
	var cz := 0.0
	var cy := 0.0
	for p in pts:
		cz += p.x
		cy += p.y
	cz /= float(n)
	cy /= float(n)
	var b := clampf(bevel, 0.0, 0.02)
	var xs := [-thick * 0.5, -thick * 0.5 + b, thick * 0.5 - b, thick * 0.5]
	var ks := [0.94, 1.0, 1.0, 0.94]
	var rings: Array = []
	for l in 4:
		var ring: Array[Vector3] = []
		for p in pts:
			var q: Vector2 = Vector2(cz, cy) + (p - Vector2(cz, cy)) * float(ks[l])
			ring.append(Vector3(xs[l], q.y, q.x))
		rings.append(ring)
	for l in 3:
		var r0: Array[Vector3] = rings[l]
		var r1: Array[Vector3] = rings[l + 1]
		for i in n:
			var j := (i + 1) % n
			var mid: Vector3 = (r0[i] + r0[j] + r1[j] + r1[i]) * 0.25
			var guide := Vector3(0.0, mid.y - cy, mid.z - cz)
			if guide.length_squared() < 1e-9:
				guide = Vector3.UP
			_quad3(st, r0[i], r0[j], r1[j], r1[i], guide.normalized())
	var c0 := Vector3(xs[0], cy, cz)
	var c1 := Vector3(xs[3], cy, cz)
	for i in n:
		var j := (i + 1) % n
		_tri3(st, c0, rings[0][i], rings[0][j], Vector3.LEFT)
		_tri3(st, c1, rings[3][i], rings[3][j], Vector3.RIGHT)
	return st.commit()


# ================================================================== track path

## Rounded-polygon belt centreline, uniformly resampled.
func _track_path(poly: Array, radius: float, step: float) -> Dictionary:
	var n := poly.size()
	var area := 0.0
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var ccw := area > 0.0
	var nrm: Array[Vector2] = []
	for i in n:
		var a2: Vector2 = poly[i]
		var b3: Vector2 = poly[(i + 1) % n]
		var d := (b3 - a2).normalized()
		nrm.append(Vector2(d.y, -d.x) if ccw else Vector2(-d.y, d.x))
	var dense: Array = []
	for i in n:
		var prev_n: Vector2 = nrm[(i - 1 + n) % n]
		var next_n: Vector2 = nrm[i]
		var a0 := atan2(prev_n.y, prev_n.x)
		var a1 := atan2(next_n.y, next_n.x)
		var sweep := a1 - a0
		if ccw:
			while sweep <= 0.0:
				sweep += TAU
		else:
			while sweep >= 0.0:
				sweep -= TAU
		var c: Vector2 = poly[i]
		var steps := maxi(2, int(ceil(absf(sweep) * radius / step)))
		for k in steps + 1:
			var ang := a0 + sweep * float(k) / float(steps)
			var nn := Vector2(cos(ang), sin(ang))
			var tt := Vector2(-nn.y, nn.x) if ccw else Vector2(nn.y, -nn.x)
			dense.append({"p": c + nn * radius, "n": nn, "t": tt})
		var pa: Vector2 = poly[i] + nrm[i] * radius
		var pb: Vector2 = poly[(i + 1) % n] + nrm[i] * radius
		var seg := pa.distance_to(pb)
		var ss := maxi(1, int(ceil(seg / step)))
		for k in range(1, ss + 1):
			dense.append({"p": pa.lerp(pb, float(k) / float(ss)), "n": nrm[i],
				"t": (pb - pa).normalized() if seg > 1e-6 else Vector2.RIGHT})
	var total := 0.0
	var cum: Array[float] = [0.0]
	for i in range(1, dense.size()):
		total += (dense[i]["p"] as Vector2).distance_to(dense[i - 1]["p"])
		cum.append(total)
	var count := maxi(16, int(round(total / step)))
	var spacing := total / float(count)
	var out: Array = []
	var j := 0
	for k in count:
		var s := spacing * float(k)
		while j < cum.size() - 2 and cum[j + 1] < s:
			j += 1
		var seg_len := maxf(cum[j + 1] - cum[j], 1e-6)
		var u := clampf((s - cum[j]) / seg_len, 0.0, 1.0)
		var a3: Dictionary = dense[j]
		var b4: Dictionary = dense[j + 1]
		out.append({"p": (a3["p"] as Vector2).lerp(b4["p"], u),
			"t": (a3["t"] as Vector2).lerp(b4["t"], u).normalized(),
			"n": (a3["n"] as Vector2).lerp(b4["n"], u).normalized()})
	return {"pts": out, "len": total, "spacing": spacing}


func _path_at(path: Dictionary, s: float) -> Dictionary:
	var pts: Array = path["pts"]
	var sp: float = path["spacing"]
	var n := pts.size()
	var fi: float = fposmod(s, float(n) * sp) / sp
	var i: int = int(floor(fi)) % n
	var f: float = fi - floor(fi)
	var a: Dictionary = pts[i]
	var b: Dictionary = pts[(i + 1) % n]
	var p: Vector2 = (a["p"] as Vector2).lerp(b["p"], f)
	var t: Vector2 = (a["t"] as Vector2).lerp(b["t"], f).normalized()
	var nn: Vector2 = (a["n"] as Vector2).lerp(b["n"], f).normalized()
	return {"p": p, "t": t, "n": nn}


# ================================================================== chassis

func _build_chassis() -> void:
	var root: Node3D = J["root"]
	var hull := AM.hull()
	var hull2 := AM.hull_soft()
	var steel := AM.steel()
	var steel_d := AM.steel_dark()
	var orange := AM.orange_panel()
	var orange_d := AM.orange_deep()
	var emis := AM.signal_orange()
	var joint := AM.joint()
	var parts: Array = []
	# deck block between the tracks
	_p(parts, SK.loft([
		{"y": 0.400, "w": 0.520, "d": 0.560, "c": 0.20},
		{"y": 0.432, "w": 0.590, "d": 0.620, "c": 0.18},
		{"y": 0.510, "w": 0.590, "d": 0.620, "c": 0.18},
		{"y": 0.538, "w": 0.510, "d": 0.540, "c": 0.22},
	]), AM.mat_black())
	# top plate + hazard strips
	_p(parts, MK.plate(0.440, 0.450, 0.022, 0.006), AM.mat_black(), Vector3(0, 0.546, 0),
		Vector3(90, 0, 0))
	for i in 3:
		_p(parts, MK.plate(0.300 - float(i) * 0.030, 0.030, 0.006, 0.002), joint,
			Vector3(0, 0.556, -0.135 + float(i) * 0.040), Vector3(90, 0, 0))
	_p(parts, MK.plate(0.130, 0.030, 0.006, 0.002), emis,
		Vector3(-0.170, 0.556, 0.150), Vector3(90, 0, 0))
	# tow hooks / clamps
	for sx in [1, -1]:
		for sz in [1, -1]:
			_p(parts, SK.beam(Vector3(float(sx) * 0.270, 0.476, float(sz) * 0.255),
				Vector3(float(sx) * 0.350, 0.476, float(sz) * 0.255),
				0.052, 0.046, 0.036, 0.030, 0.30, Vector3.UP, 0.004), steel)
			_p(parts, MK.sphere(0.026, 12, 8, true), orange_d,
				Vector3(float(sx) * 0.355, 0.476, float(sz) * 0.255))
	# waist column (fixed; the turret rotates above it)
	_p(parts, MK.prism(24, 0.180, 0.162, 0.320, 0.0), steel_d,
		Vector3(0, 0.620, 0))
	_ring(parts, 0.160, 0.188, 0.024, 32, Vector3(0, 0.520, 0), Vector3.UP, steel)
	_ring(parts, 0.150, 0.168, 0.012, 32, Vector3(0, 0.600, 0), Vector3.UP, orange)
	_ring(parts, 0.140, 0.158, 0.010, 28, Vector3(0, 0.690, 0), Vector3.UP, emis)
	# undercarriage skid
	_p(parts, MK.plate(0.300, 0.500, 0.030, 0.010), hull, Vector3(0, 0.400, 0),
		Vector3(90, 0, 0))
	# front driving headlights + grille slats
	var head_glow := AM.emissive(Color(1.0, 0.46, 0.12), 3.4)
	var tail_glow := AM.emissive(Color(1.0, 0.16, 0.03), 3.6)
	for sx in [1, -1]:
		var lx := float(sx) * 0.175
		_p(parts, MK.plate(0.118, 0.038, 0.018, 0.004), steel_d,
			Vector3(lx, 0.470, 0.308))
		_p(parts, MK.plate(0.092, 0.018, 0.008, 0.002), head_glow,
			Vector3(lx, 0.470, 0.316))
		_p(parts, MK.plate(0.118, 0.036, 0.018, 0.004), steel_d,
			Vector3(lx, 0.470, -0.308))
		_p(parts, MK.plate(0.092, 0.016, 0.008, 0.002), tail_glow,
			Vector3(lx, 0.470, -0.316))
	for i in 3:
		_p(parts, MK.plate(0.165, 0.010, 0.012, 0.002), steel,
			Vector3(0.0, 0.456 + float(i) * 0.014, 0.310))
		_p(parts, MK.plate(0.016, 0.052, 0.016, 0.003), steel,
			Vector3((float(i) - 1.0) * 0.052, 0.470, -0.310))
	_bake(root, parts)


## One track shoe: slab + two longitudinal grousers + end bosses.
func _shoe_mesh(w: float, l: float, t: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	SK.stack(st, MK.plate(w, l, t, 0.0045), Transform3D.IDENTITY)
	for sx in [-1.0, 1.0]:
		SK.stack(st, MK.plate(w * 0.195, l * 0.802, 0.016, 0.003),
			Transform3D(Basis.IDENTITY, Vector3(float(sx) * w * 0.265, 0, t * 0.5 + 0.006)))
		SK.stack(st, MK.plate(w * 0.055, l * 0.860, 0.008, 0.002),
			Transform3D(Basis.IDENTITY, Vector3(float(sx) * w * 0.395, 0, t * 0.5 + 0.003)))
		SK.stack(st, MK.prism(6, 0.012, 0.011, 0.014, 0.0),
			Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(float(sx) * w * 0.34, 0, t * 0.5 + 0.006)))
	return st.commit()


func _build_track(side: int) -> void:
	var nm := "trackL" if side > 0 else "trackR"
	var node: Node3D = J[nm]
	var hull := AM.hull()
	var hull2 := AM.hull_soft()
	var steel := AM.steel()
	var steel_d := AM.steel_dark()
	var orange := AM.orange_panel()
	var tread := AM.tread()
	var belt := AM.belt()
	var emis := AM.signal_orange()
	var joint := AM.joint()
	var path := _track_path(kin.track_poly, kin.track_belt_r, 0.016)
	_belts[nm] = path
	# --- belt band (closed loop, 4 faces)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = path["pts"]
	var cnt := pts.size()
	var wi := track_hw - 0.020
	var di := -0.016
	var dz := 0.016
	var prev := {}
	for k in cnt + 1:
		var o: Dictionary = pts[k % cnt]
		var pp: Vector2 = o["p"]
		var nn: Vector2 = o["n"]
		var tt: Vector2 = o["t"]
		var pin := pp + nn * di
		var pout := pp + nn * dz
		var cur := {
			"a": Vector3(-wi, pin.y, pin.x), "b": Vector3(wi, pin.y, pin.x),
			"c": Vector3(wi, pout.y, pout.x), "d": Vector3(-wi, pout.y, pout.x),
			"n": Vector3(0, nn.y, nn.x), "t": Vector3(0, tt.y, tt.x),
		}
		if not prev.is_empty():
			_quad3(st, prev["a"], prev["b"], cur["b"], cur["a"], -prev["n"])
			_quad3(st, prev["d"], prev["c"], cur["c"], cur["d"], prev["n"])
			_quad3(st, prev["a"], prev["d"], cur["d"], cur["a"], Vector3.LEFT)
			_quad3(st, prev["b"], prev["c"], cur["c"], cur["b"], Vector3.RIGHT)
		prev = cur
	var band := st.commit()
	var band_mi := MeshInstance3D.new()
	band_mi.mesh = band
	band_mi.material_override = belt
	band_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(band_mi)
	# --- tread shoes (MultiMesh, one draw call per track)
	var plates := maxi(8, int(round(float(path["len"]) / 0.0735)))
	var shoe_w := track_hw * 2.0 + 0.016
	var plate_mesh := _shoe_mesh(shoe_w, 0.060, 0.026)
	plate_mesh.surface_set_material(0, tread)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plate_mesh
	mm.instance_count = plates
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = tread
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(mmi)
	path["plates"] = plates
	path["mm"] = mm
	# a few orange shoes break up the long black belt and show the track motion
	var acc_step := 6
	var acc_count := maxi(3, int(plates / acc_step))
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = plate_mesh
	mm2.instance_count = acc_count
	var mmi2 := MultiMeshInstance3D.new()
	mmi2.multimesh = mm2
	mmi2.material_override = orange
	mmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(mmi2)
	path["mm_acc"] = mm2
	path["acc_step"] = acc_step
	path["acc_count"] = acc_count
	# --- open triangular frame: edge beams + aligned edge lights + hub + spokes + tensioner + bogie rollers
	var frame: Array = []
	var poly: Array = kin.track_poly
	var out_x := float(side)
	var track_glow := AM.emissive(AM.ORANGE, 3.4)
	var marker_glow := AM.emissive(Color(1.0, 0.42, 0.06), 3.6)
	var wheel_glow := AM.emissive(AM.ORANGE, 2.8)
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= float(poly.size())
	var ctr := Vector3(0.0, centroid.y, centroid.x)
	var inset: Array = []
	for p in poly:
		inset.append(centroid + (p - centroid) * 0.86)
	for i in 3:
		var a: Vector2 = inset[i]
		var b: Vector2 = inset[(i + 1) % 3]
		_p(frame, SK.beam(Vector3(0, a.y, a.x), Vector3(0, b.y, b.x),
			0.064, 0.056, 0.050, 0.046, 0.30, Vector3.RIGHT, 0.006), steel_d)
		# edge-aligned armored clamp housing + glowing orange side strips
		var p0 := a.lerp(b, 0.27)
		var p1 := a.lerp(b, 0.73)
		_p(frame, SK.beam(Vector3(0, p0.y, p0.x), Vector3(0, p1.y, p1.x),
			0.068, 0.064, 0.068, 0.064, 0.26, Vector3.RIGHT, 0.004), hull2)
		var l0 := a.lerp(b, 0.32)
		var l1 := a.lerp(b, 0.68)
		for sx in [1, -1]:
			var x_off := float(sx) * 0.035
			_p(frame, SK.beam(Vector3(x_off, l0.y, l0.x), Vector3(x_off, l1.y, l1.x),
				0.015, 0.010, 0.015, 0.010, 0.20, Vector3.RIGHT, 0.002), track_glow)
	# bottom beam side clearance marker LEDs (placed below the bottom edge light bar)
	for mz in [-0.25, 0.0, 0.25]:
		_p(frame, MK.plate(0.056, 0.020, 0.014, 0.003), steel_d,
			Vector3(out_x * 0.030, 0.206, mz), Vector3(0, 90, 0))
		_p(frame, MK.plate(0.038, 0.010, 0.008, 0.002), marker_glow,
			Vector3(out_x * 0.036, 0.206, mz), Vector3(0, 90, 0))
	# central hub (coaxial along X at triangle centroid, symmetric on both faces)
	_disc(frame, 0.104, 0.114, 28, ctr, Vector3.RIGHT, steel_d, 0.010)
	for sx in [1, -1]:
		var hs := float(sx)
		_ring(frame, 0.072, 0.098, 0.014, 28, ctr + Vector3(hs * 0.058, 0, 0),
			Vector3.RIGHT, steel, 0.002)
		_ring(frame, 0.052, 0.068, 0.010, 26, ctr + Vector3(hs * 0.062, 0, 0),
			Vector3.RIGHT, orange, 0.002)
		_disc(frame, 0.050, 0.012, 24, ctr + Vector3(hs * 0.062, 0, 0),
			Vector3.RIGHT, hull, 0.002)
		_disc(frame, 0.032, 0.012, 20, ctr + Vector3(hs * 0.068, 0, 0),
			Vector3.RIGHT, emis, 0.002)
		for b_idx in 6:
			var ba := TAU * float(b_idx) / 6.0 + 0.25
			_p(frame, MK.prism(6, 0.008, 0.007, 0.012, 0.0), steel,
				ctr + Vector3(hs * 0.066, cos(ba) * 0.085, sin(ba) * 0.085),
				Vector3(0, 0, -90.0 * hs))
	for i in 3:
		var c: Vector2 = poly[i]
		_p(frame, SK.beam(ctr, Vector3(0, c.y, c.x),
			0.054, 0.042, 0.038, 0.032, 0.30, Vector3.RIGHT, 0.005), steel)
		_disc(frame, 0.044, 0.140, 20, Vector3(0, c.y, c.x), Vector3.RIGHT, steel_d, 0.005)
	# rear hydraulic tensioner (collinear cylinder + piston, clear of rear wheel)
	var rear: Vector2 = poly[2]
	var tp0 := Vector3(out_x * 0.022, centroid.y - 0.020, -0.095)
	var tp1 := Vector3(out_x * 0.022, rear.y + 0.060, rear.x + 0.165)
	var tmid := tp0.lerp(tp1, 0.56)
	_p(frame, SK.beam(tp0, tmid, 0.036, 0.036, 0.034, 0.034, 0.32, Vector3.RIGHT, 0.003), steel_d)
	_p(frame, SK.beam(tp0.lerp(tp1, 0.52), tp0.lerp(tp1, 0.60),
		0.042, 0.042, 0.042, 0.042, 0.32, Vector3.RIGHT, 0.002), orange)
	_p(frame, SK.beam(tmid, tp1, 0.018, 0.018, 0.018, 0.018, 0.32, Vector3.RIGHT, 0.002), steel)
	_p(frame, MK.sphere(0.020, 12, 8, true), steel_d, tp1)
	# two bottom bogie / road rollers + suspension forks
	var rollers: Array = []
	for r_idx in 2:
		var rz := -0.17 if r_idx == 0 else 0.17
		_p(frame, SK.beam(Vector3(-0.070, 0.216, rz), Vector3(0.070, 0.216, rz),
			0.024, 0.022, 0.024, 0.022, 0.30, Vector3.UP, 0.002), steel_d)
		for sx in [1, -1]:
			var fx := float(sx) * 0.068
			_p(frame, SK.beam(Vector3(fx, 0.216, rz), Vector3(fx, 0.132, rz),
				0.022, 0.014, 0.020, 0.014, 0.30, Vector3.RIGHT, 0.002), steel_d)
			_disc(frame, 0.018, 0.012, 16, Vector3(float(sx) * 0.075, 0.132, rz),
				Vector3.RIGHT, steel, 0.002)
			_disc(frame, 0.009, 0.008, 12, Vector3(float(sx) * 0.081, 0.132, rz),
				Vector3.RIGHT, emis, 0.001)
		var rn := Node3D.new()
		rn.name = "roller_%s%d" % [nm, r_idx]
		rn.position = Vector3(0.0, 0.132, rz)
		node.add_child(rn)
		var rp: Array = []
		_ring(rp, 0.044, 0.060, 0.116, 28, Vector3.ZERO, Vector3.RIGHT, steel_d, 0.005)
		_disc(rp, 0.046, 0.040, 24, Vector3.ZERO, Vector3.RIGHT, joint, 0.003)
		for sx in [1, -1]:
			var rx := float(sx) * 0.032
			for spk in 4:
				var ra := TAU * float(spk) / 4.0
				_p(rp, SK.beam(Vector3(rx, 0, 0),
					Vector3(rx, cos(ra) * 0.046, sin(ra) * 0.046),
					0.012, 0.014, 0.010, 0.012, 0.30, Vector3.RIGHT, 0.002), steel)
		_bake(rn, rp)
		rollers.append(rn)
	path["rollers"] = rollers
	_bake(node, frame)
	# subtle warm interior track light
	var t_light := OmniLight3D.new()
	t_light.light_color = Color(1.0, 0.28, 0.05)
	t_light.light_energy = 0.50
	t_light.omni_range = 0.95
	t_light.shadow_enabled = false
	t_light.position = ctr + Vector3(out_x * 0.04, 0.0, 0.0)
	node.add_child(t_light)
	# --- corner wheels (hollow machined drums + recessed spokes + rim LED rings)
	for i in 3:
		var wn: Node3D = J["wheel_%s%d" % [nm, i]]
		var c2: Vector2 = poly[i]
		wn.position = Vector3(0, c2.y, c2.x)
		var wp: Array = []
		_ring(wp, wheel_r - 0.024, wheel_r, 0.170, 44, Vector3.ZERO, Vector3.RIGHT, steel_d, 0.008)
		_disc(wp, wheel_r - 0.020, 0.056, 36, Vector3.ZERO, Vector3.RIGHT, joint, 0.004)
		_disc(wp, 0.054, 0.172, 28, Vector3.ZERO, Vector3.RIGHT, hull, 0.005)
		for sx in [1, -1]:
			var sxf := float(sx)
			var x := sxf * 0.088
			_ring(wp, 0.112, 0.136, 0.012, 36, Vector3(sxf * 0.086, 0, 0),
				Vector3.RIGHT, steel, 0.002)
			_ring(wp, 0.100, 0.110, 0.008, 36, Vector3(sxf * 0.083, 0, 0),
				Vector3.RIGHT, wheel_glow, 0.001)
			_ring(wp, 0.056, 0.072, 0.010, 28, Vector3(x, 0, 0),
				Vector3.RIGHT, orange, 0.002)
			_disc(wp, 0.052, 0.018, 24, Vector3(sxf * 0.089, 0, 0),
				Vector3.RIGHT, hull2, 0.003)
			_ring(wp, 0.022, 0.032, 0.010, 20, Vector3(sxf * 0.097, 0, 0),
				Vector3.RIGHT, steel_d, 0.001)
			_disc(wp, 0.020, 0.010, 18, Vector3(sxf * 0.100, 0, 0),
				Vector3.RIGHT, emis, 0.002)
			for b in 6:
				var a2 := TAU * float(b) / 6.0 + 0.3
				_p(wp, MK.prism(6, 0.009, 0.007, 0.014, 0.0), steel,
					Vector3(sxf * 0.096, cos(a2) * 0.040, sin(a2) * 0.040),
					Vector3(0, 0, -90.0 * sxf))
			for b2 in 5:
				var a3 := TAU * float(b2) / 5.0 + 0.2
				_p(wp, SK.beam(Vector3(sxf * 0.052, cos(a3) * 0.044, sin(a3) * 0.044),
					Vector3(sxf * 0.052, cos(a3) * (wheel_r - 0.018), sin(a3) * (wheel_r - 0.018)),
					0.034, 0.038, 0.022, 0.030, 0.30, Vector3.RIGHT, 0.003), steel)
				if b2 == 0:
					_p(wp, SK.beam(Vector3(sxf * 0.070, cos(a3) * 0.054, sin(a3) * 0.054),
						Vector3(sxf * 0.070, cos(a3) * (wheel_r - 0.022), sin(a3) * (wheel_r - 0.022)),
						0.014, 0.008, 0.010, 0.008, 0.25, Vector3.RIGHT, 0.002), orange)
		_bake(wn, wp)


# ================================================================== turret

func _build_turret() -> void:
	var body: Node3D = J["body"]
	var hull := AM.hull()
	var hull2 := AM.hull_soft()
	var steel := AM.steel()
	var steel_d := AM.steel_dark()
	var orange := AM.orange_panel()
	var orange_d := AM.orange_deep()
	var emis := AM.signal_orange()
	var joint := AM.joint()
	var parts: Array = []

	# --- main chamfered cube shell
	_p(parts, SK.loft([
		{"y": -cube_half, "w": cube * 0.88, "d": cube * 0.88, "c": 0.16},
		{"y": -cube_half + 0.048, "w": cube, "d": cube, "c": 0.13},
		{"y": cube_half - 0.048, "w": cube, "d": cube, "c": 0.13},
		{"y": cube_half, "w": cube * 0.88, "d": cube * 0.88, "c": 0.16},
	]), hull)
	# top and bottom armour rims
	_p(parts, SK.loft([
		{"y": cube_half - 0.010, "w": cube + 0.010, "d": cube + 0.010, "c": 0.14},
		{"y": cube_half + 0.024, "w": cube - 0.030, "d": cube - 0.030, "c": 0.16},
	]), steel_d)
	_p(parts, SK.loft([
		{"y": -cube_half - 0.018, "w": cube - 0.030, "d": cube - 0.030, "c": 0.16},
		{"y": -cube_half + 0.012, "w": cube + 0.008, "d": cube + 0.008, "c": 0.14},
	]), steel_d)
	# turret ring at the cube bottom
	_ring(parts, 0.190, 0.300, 0.030, 44, Vector3(0, -cube_half - 0.010, 0),
		Vector3.UP, steel, 0.006)
	_ring(parts, 0.214, 0.234, 0.010, 44, Vector3(0, -cube_half - 0.026, 0),
		Vector3.UP, emis, 0.002)
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.2
		_p(parts, MK.prism(6, 0.016, 0.013, 0.014, 0.0), steel,
			Vector3(cos(a) * 0.272, -cube_half - 0.002, sin(a) * 0.272))
	# vertical chamfer strips (flush on the 45-deg chamfer face) + clamp collars
	var d_ch := cube_half * 0.942
	var d_ch_trim := d_ch + 0.004
	for sx in [1, -1]:
		for sz in [1, -1]:
			var pos := Vector3(float(sx) * d_ch, 0.0, float(sz) * d_ch)
			var pos_t := Vector3(float(sx) * d_ch_trim, 0.0, float(sz) * d_ch_trim)
			var rot_c := Vector3(0, 45.0 * float(sx * sz), 0)
			_p(parts, MK.plate(0.030, cube * 0.68, 0.010, 0.003), steel_d, pos, rot_c)
			_p(parts, MK.plate(0.010, cube * 0.52, 0.006, 0.002), orange_d, pos_t, rot_c)
			for cy_s in [1.0, -1.0]:
				_p(parts, MK.plate(0.038, 0.026, 0.014, 0.003), steel,
					Vector3(float(sx) * d_ch, cy_s * cube * 0.28, float(sz) * d_ch), rot_c)
	# --- front cheek strips beside the big optic
	for sx in [1, -1]:
		_p(parts, MK.plate(0.040, 0.360, 0.020, 0.006), steel_d,
			Vector3(float(sx) * 0.226, 0.0, cube_half + 0.002))
		_p(parts, MK.plate(0.010, 0.220, 0.010, 0.003), orange_d,
			Vector3(float(sx) * 0.244, 0.0, cube_half + 0.002))
		_p(parts, MK.plate(0.008, 0.130, 0.008, 0.002), emis,
			Vector3(float(sx) * 0.248, 0.020, cube_half + 0.002))
	# chin
	_p(parts, SK.loft([
		{"y": -cube_half - 0.020, "w": 0.420, "d": 0.110, "c": 0.24},
		{"y": -cube_half + 0.030, "w": 0.470, "d": 0.140, "c": 0.22},
	]), hull2, Vector3(0, 0, cube_half - 0.062))
	_p(parts, MK.plate(0.320, 0.012, 0.008, 0.002), emis,
		Vector3(0, -cube_half - 0.002, cube_half - 0.008))
	# side armor panels + framed heatsink louver bay + light bars + service port
	var vent_glow := AM.emissive(AM.ORANGE, 2.0)
	for sx in [1, -1]:
		var sxf := float(sx)
		# upper & lower armor panels + mid-channel rails
		_p(parts, MK.plate(cube * 0.68, cube * 0.17, 0.012, 0.004), hull2,
			Vector3(sxf * (cube_half + 0.004), cube * 0.265, -0.010), Vector3(0, 90, 0))
		_p(parts, MK.plate(cube * 0.68, cube * 0.17, 0.012, 0.004), hull2,
			Vector3(sxf * (cube_half + 0.004), -cube * 0.265, -0.010), Vector3(0, 90, 0))
		for ry in [0.092, -0.092]:
			_p(parts, MK.plate(cube * 0.64, 0.014, 0.014, 0.003), steel_d,
				Vector3(sxf * (cube_half + 0.007), ry, -0.010), Vector3(0, 90, 0))
		# framed 5-slat heatsink louver bay with subtle internal warm vent glow
		_p(parts, MK.plate(0.185, 0.165, 0.014, 0.004), steel_d,
			Vector3(sxf * (cube_half + 0.006), 0.0, -0.020), Vector3(0, 90, 0))
		_p(parts, MK.plate(0.158, 0.136, 0.008, 0.002), joint,
			Vector3(sxf * (cube_half + 0.011), 0.0, -0.020), Vector3(0, 90, 0))
		_p(parts, MK.plate(0.018, 0.118, 0.004, 0.001), vent_glow,
			Vector3(sxf * (cube_half + 0.014), 0.0, -0.020), Vector3(0, 90, 0))
		for i in 5:
			_p(parts, MK.plate(0.150, 0.013, 0.012, 0.003), steel,
				Vector3(sxf * (cube_half + 0.018), 0.052 - float(i) * 0.026, -0.020),
				Vector3(0, 90, 0))
		# front vertical side accent + light bar
		_p(parts, MK.plate(0.036, 0.270, 0.014, 0.004), steel_d,
			Vector3(sxf * (cube_half + 0.006), -0.010, 0.140), Vector3(0, 90, 0))
		_p(parts, MK.plate(0.020, 0.240, 0.010, 0.003), orange_d,
			Vector3(sxf * (cube_half + 0.010), -0.010, 0.140), Vector3(0, 90, 0))
		_p(parts, MK.plate(0.010, 0.180, 0.008, 0.002), emis,
			Vector3(sxf * (cube_half + 0.014), -0.010, 0.140), Vector3(0, 90, 0))
		# rear vertical rib + circular machined service port
		_p(parts, MK.plate(0.048, 0.340, 0.014, 0.004), steel_d,
			Vector3(sxf * (cube_half + 0.006), -0.020, -0.145), Vector3(0, 90, 0))
		_ring(parts, 0.020, 0.030, 0.010, 20,
			Vector3(sxf * (cube_half + 0.014), -0.115, -0.145), Vector3.RIGHT, steel, 0.002)
		_ring(parts, 0.013, 0.019, 0.008, 18,
			Vector3(sxf * (cube_half + 0.016), -0.115, -0.145), Vector3.RIGHT, orange, 0.001)
		_disc(parts, 0.013, 0.008, 16,
			Vector3(sxf * (cube_half + 0.015), -0.115, -0.145), Vector3.RIGHT, joint, 0.001)
		# upper side horizontal marker light
		_p(parts, MK.plate(0.092, 0.024, 0.010, 0.003), steel_d,
			Vector3(sxf * (cube_half + 0.009), cube * 0.265, 0.020), Vector3(0, 90, 0))
		_p(parts, MK.plate(0.075, 0.012, 0.008, 0.002), emis,
			Vector3(sxf * (cube_half + 0.013), cube * 0.265, 0.020), Vector3(0, 90, 0))
		# 4 corner hex fasteners on upper/lower side panels
		for fy in [cube * 0.265, -cube * 0.265]:
			for fz in [-0.095, 0.095]:
				_p(parts, MK.prism(6, 0.008, 0.006, 0.010, 0.0), steel,
					Vector3(sxf * (cube_half + 0.010), fy, fz), Vector3(0, 0, -90.0 * sxf))
	# --- top deck
	_p(parts, MK.plate(0.400, 0.380, 0.018, 0.006), AM.mat_black(),
		Vector3(0, cube_half + 0.030, -0.010), Vector3(90, 0, 0))
	for i in 3:
		_p(parts, MK.plate(0.300 - float(i) * 0.040, 0.024, 0.008, 0.002), joint,
			Vector3(0, cube_half + 0.040, -0.150 + float(i) * 0.038), Vector3(90, 0, 0))
	_p(parts, MK.plate(0.140, 0.024, 0.008, 0.002), emis,
		Vector3(0.0, cube_half + 0.041, 0.150), Vector3(90, 0, 0))
	# shoulder pedestal: tall socket neck above the cube
	_p(parts, SK.loft([
		{"y": cube_half + 0.016, "w": 0.250, "d": 0.250, "c": 0.22},
		{"y": cube_half + 0.090, "w": 0.200, "d": 0.200, "c": 0.24},
		{"y": cube_half + 0.190, "w": 0.168, "d": 0.168, "c": 0.26},
		{"y": cube_half + 0.236, "w": 0.150, "d": 0.150, "c": 0.28},
	]), hull2)
	_ring(parts, 0.090, 0.126, 0.024, 32, Vector3(0, cube_half + 0.030, 0),
		Vector3.UP, steel, 0.004)
	_ring(parts, 0.074, 0.092, 0.012, 30, Vector3(0, cube_half + 0.120, 0),
		Vector3.UP, orange, 0.002)
	_ring(parts, 0.064, 0.080, 0.012, 28, Vector3(0, cube_half + 0.200, 0),
		Vector3.UP, steel_d, 0.002)
	for i in 4:
		var a2 := TAU * float(i) / 4.0 + 0.785
		_p(parts, MK.prism(6, 0.012, 0.010, 0.014, 0.0), steel,
			Vector3(cos(a2) * 0.100, cube_half + 0.030, sin(a2) * 0.100))
	# --- rear power pack: core frame + twin armor pods + radiator + exhausts + grab bar + charge bar
	var rear_core_glow := AM.emissive(AM.ORANGE, 3.0)
	var rear_amber := AM.emissive(Color(1.0, 0.55, 0.12), 4.0)
	_p(parts, SK.loft([
		{"y": -0.200, "w": cube * 0.74, "d": 0.046, "c": 0.18},
		{"y": 0.185, "w": cube * 0.74, "d": 0.046, "c": 0.18},
	]), steel_d, Vector3(0, -0.005, -cube_half - 0.020))
	# twin vertical side battery/armor pods with clamp straps & bolts
	for sx in [1, -1]:
		var sxf := float(sx)
		_p(parts, SK.loft([
			{"y": -0.180, "w": 0.118, "d": 0.068, "c": 0.22},
			{"y": 0.165, "w": 0.118, "d": 0.068, "c": 0.22},
		]), hull2, Vector3(sxf * 0.122, -0.005, -cube_half - 0.042))
		_p(parts, MK.plate(0.024, 0.260, 0.012, 0.003), steel_d,
			Vector3(sxf * 0.162, 0.0, -cube_half - 0.074))
		_p(parts, MK.plate(0.012, 0.210, 0.008, 0.002), orange,
			Vector3(sxf * 0.162, 0.0, -cube_half - 0.078))
		for strap_y in [0.115, -0.085]:
			_p(parts, MK.plate(0.092, 0.024, 0.010, 0.003), steel,
				Vector3(sxf * 0.116, strap_y, -cube_half - 0.076))
			for bx in [-0.026, 0.026]:
				_p(parts, MK.prism(6, 0.007, 0.006, 0.010, 0.0), steel,
					Vector3(sxf * 0.116 + bx, strap_y, -cube_half - 0.081), Vector3(-90, 0, 0))
	# central recessed radiator core + horizontal cooling fins
	_p(parts, MK.plate(0.116, 0.230, 0.010, 0.002), joint,
		Vector3(0, 0.020, -cube_half - 0.046))
	_p(parts, MK.plate(0.026, 0.180, 0.008, 0.002), rear_core_glow,
		Vector3(0, 0.025, -cube_half - 0.050))
	for i in 6:
		_p(parts, MK.plate(0.118, 0.012, 0.024, 0.003), steel,
			Vector3(0, 0.110 - float(i) * 0.034, -cube_half - 0.060))
	# twin top exhaust manifolds + protective grab bar
	for sx in [1, -1]:
		var ex := float(sx) * 0.112
		_p(parts, MK.prism(10, 0.036, 0.030, 0.074, 0.0), steel_d,
			Vector3(ex, 0.175, -cube_half - 0.046))
		_ring(parts, 0.026, 0.036, 0.010, 20, Vector3(ex, 0.195, -cube_half - 0.046),
			Vector3.UP, orange, 0.002)
		_ring(parts, 0.022, 0.031, 0.010, 20, Vector3(ex, 0.214, -cube_half - 0.046),
			Vector3.UP, steel, 0.002)
		_disc(parts, 0.022, 0.008, 16, Vector3(ex, 0.215, -cube_half - 0.046),
			Vector3.UP, joint, 0.001)
	_p(parts, SK.beam(Vector3(-0.145, 0.148, -cube_half - 0.088),
		Vector3(0.145, 0.148, -cube_half - 0.088),
		0.016, 0.016, 0.016, 0.016, 0.30, Vector3.UP, 0.002), steel)
	for sx in [1, -1]:
		var gx := float(sx) * 0.140
		_p(parts, SK.beam(Vector3(gx, 0.148, -cube_half - 0.088),
			Vector3(gx, 0.148, -cube_half - 0.062),
			0.016, 0.016, 0.018, 0.018, 0.30, Vector3.UP, 0.002), steel)
		_p(parts, MK.sphere(0.009, 10, 8, true), steel,
			Vector3(gx, 0.148, -cube_half - 0.088))
	# lower rear telemetry & charge-level strip + rear valence
	_p(parts, MK.plate(0.280, 0.044, 0.014, 0.004), steel_d,
		Vector3(0, -0.132, -cube_half - 0.074))
	for i in 5:
		var cx := (float(i) - 2.0) * 0.048
		_p(parts, MK.plate(0.034, 0.014, 0.008, 0.002),
			rear_amber if i == 4 else emis,
			Vector3(cx, -0.132, -cube_half - 0.082))
	_p(parts, MK.plate(0.360, 0.026, 0.020, 0.005), steel_d,
		Vector3(0, -0.190, -cube_half - 0.056))
	for sx in [1, -1]:
		_p(parts, MK.plate(0.028, 0.012, 0.008, 0.002), emis,
			Vector3(float(sx) * 0.155, -0.190, -cube_half - 0.066))
	_bake(body, parts)


# ================================================================== status LEDs

## A row of small blinking indicators under the optic. Each LED gets its own
## material instance so they can blink out of phase.
func _build_status_leds(body: Node3D) -> void:
	var cols := [Color(0.20, 1.0, 0.35), Color(1.0, 0.42, 0.05),
		Color(0.25, 0.55, 1.0)]
	var y := -(cam_ap + 0.052)
	var n := 6
	var parts: Array = []
	for i in n:
		var x := (float(i) - float(n - 1) * 0.5) * 0.058
		_p(parts, MK.plate(0.038, 0.022, 0.010, 0.003), AM.mat_black(),
			Vector3(x, y, cube_half + 0.001))
		var m := StandardMaterial3D.new()
		var c: Color = cols[i % 3]
		m.albedo_color = c.darkened(0.7)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.0
		m.metallic = 0.05
		m.roughness = 0.45
		_p(parts, MK.plate(0.026, 0.012, 0.005, 0.0015), m,
			Vector3(x, y, cube_half + 0.008))
		_leds.append({"mat": m, "phase": float(i) * 0.9, "rate": 2.4 + 0.45 * float(i % 3)})
	_bake(body, parts)


# ================================================================== optic

func _build_optic() -> void:
	var body: Node3D = J["body"]
	var shell: Node3D = J["optic_shell"]
	var eye: Node3D = J["eye_aim"]
	var hull := AM.hull()
	var hull2 := AM.hull_soft()
	var steel := AM.steel()
	var steel_d := AM.steel_dark()
	var orange := AM.orange_panel()
	var orange_d := AM.orange_deep()
	var emis := AM.signal_orange()
	var joint := AM.joint()

	# socket floor + brow (turret body, fixed)
	var bp: Array = []
	_disc(bp, cam_ap * 1.16, 0.016, 44, Vector3(0, 0, cam_z - 0.012), Vector3.FORWARD,
		joint, 0.002)
	_ring(bp, cam_ap * 1.02, cam_ap * 1.20, 0.016, 44, Vector3(0, 0, cam_face + 0.004),
		Vector3.FORWARD, steel_d, 0.003)
	# brow hood over the optic
	_p(bp, MK.plate(0.330, 0.030, 0.056, 0.008), steel_d,
		Vector3(0, cam_ap + 0.036, cam_face + 0.012))
	_p(bp, MK.plate(0.230, 0.008, 0.010, 0.002), emis,
		Vector3(0, cam_ap + 0.018, cam_face + 0.040))
	for sx in [1, -1]:
		_p(bp, SK.beam(Vector3(float(sx) * 0.155, cam_ap + 0.036, cam_face + 0.006),
			Vector3(float(sx) * 0.168, -0.020, cam_face + 0.002),
			0.026, 0.026, 0.020, 0.020, 0.30, Vector3.FORWARD, 0.003), steel)
	_bake(body, bp)
	_build_status_leds(body)

	# fixed outer shell: bezel + collar + clamp tabs + glass
	var sp: Array = []
	_ring(sp, cam_ap, cam_ap * 1.115, 0.054, 48,
		Vector3(0, 0, cam_face + 0.024), Vector3.FORWARD, hull2, 0.004)
	_ring(sp, cam_ap * 1.10, cam_ap * 1.17, 0.014, 48,
		Vector3(0, 0, cam_face + 0.020), Vector3.FORWARD, steel, 0.003)
	_ring(sp, cam_ap * 1.14, cam_ap * 1.20, 0.007, 48,
		Vector3(0, 0, cam_face + 0.020), Vector3.FORWARD, orange, 0.001)
	_ring(sp, cam_ap * 0.965, cam_ap * 1.02, 0.012, 44,
		Vector3(0, 0, cam_shell_z - 0.006), Vector3.FORWARD, steel_d, 0.002)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		_p(sp, MK.plate(0.030, 0.050, 0.014, 0.004), steel,
			Vector3(cos(a) * cam_ap * 1.06, sin(a) * cam_ap * 1.06, cam_shell_z - 0.020),
			Vector3(0, 0, rad_to_deg(a) - 90.0))
		_p(sp, MK.prism(6, 0.006, 0.005, 0.012, 0.0), emis,
			Vector3(cos(a) * cam_ap * 1.06, sin(a) * cam_ap * 1.06, cam_shell_z - 0.010))
	# thin glass shell (fixed)
	_p(sp, MK.dome(cam_ap * 0.985, 0.010, 44, 12, true), AM.optic_glass(),
		Vector3(0, 0, cam_shell_z - 0.004), Vector3(90, 0, 0))
	_bake(shell, sp)

	# rotating inner ball
	var ep: Array = []
	_p(ep, MK.sphere(cam_r, 32, 22, true), AM.eye_ball())
	# pupil cap + iris band on the aim axis (+Z)
	_p(ep, MK.arc_shell(cam_r * 1.012, 0.002, 0.0, 0.40, 0.0, TAU, 3, 24, true, false),
		AM.emissive(Color(1.0, 0.42, 0.24), 0.32), Vector3.ZERO, Vector3(90, 0, 0))
	_p(ep, MK.arc_shell(cam_r * 1.012, 0.002, 0.46, 0.60, 0.0, TAU, 3, 24, true, false),
		AM.emissive(AM.ORANGE, 0.42), Vector3.ZERO, Vector3(90, 0, 0))
	# machined gimbal band across the ball
	_p(ep, MK.arc_shell(cam_r * 1.004, 0.004, 1.36, 1.52, 0.0, TAU, 3, 30, false, false),
		steel_d, Vector3.ZERO, Vector3(0, 0, 0))
	_bake(eye, ep)


# ================================================================== arm

func _build_arm() -> void:
	var sh: Node3D = J["sh"]
	var elb: Node3D = J["elb"]
	var wr: Node3D = J["wr"]
	var tool: Node3D = J["tool"]
	var hull := AM.hull()
	var hull2 := AM.hull_soft()
	var steel := AM.steel()
	var steel_d := AM.steel_dark()
	var orange := AM.orange_panel()
	var orange_d := AM.orange_deep()
	var emis := AM.signal_orange()
	var joint := AM.joint()

	# --- shoulder ball + rotating collar
	var sp: Array = []
	_p(sp, MK.sphere(0.098, 26, 18, true), hull2)
	_ring(sp, 0.070, 0.094, 0.020, 30, Vector3(0, 0.058, 0), Vector3.UP, orange, 0.003)
	_disc(sp, 0.044, 0.014, 22, Vector3(0, 0.066, 0), Vector3.UP, steel, 0.002)
	_p(sp, MK.plate(0.050, 0.040, 0.020, 0.004), joint,
		Vector3(-0.070, 0.0, 0.030), Vector3(0, 0, -90))
	_bake(sh, sp)
	# --- upper link
	var up: Array = []
	_p(up, SK.beam(Vector3(0, -0.072, 0), Vector3(0, -L1 + 0.072, 0),
		0.098, 0.104, 0.080, 0.086, 0.30, Vector3.FORWARD, 0.014), hull)
	_p(up, SK.beam(Vector3(0, -0.090, 0), Vector3(0, -L1 + 0.090, 0),
		0.058, 0.030, 0.052, 0.026, 0.30, Vector3.FORWARD, 0.004), steel_d)
	_p(up, MK.plate(0.062, L1 * 0.50, 0.020, 0.005), orange_d,
		Vector3(0, -L1 * 0.48, 0.056))
	_p(up, MK.plate(0.014, L1 * 0.40, 0.008, 0.002), emis,
		Vector3(0, -L1 * 0.48, 0.069))
	for sx in [1, -1]:
		_p(up, SK.beam(Vector3(float(sx) * 0.052, -0.115, -0.010),
			Vector3(float(sx) * 0.046, -L1 + 0.100, -0.010),
			0.020, 0.020, 0.017, 0.017, 0.30, Vector3.FORWARD, 0.002), steel)
		_p(up, MK.sphere(0.020, 12, 9, true), steel_d,
			Vector3(float(sx) * 0.052, -0.115, -0.010))
		_p(up, MK.sphere(0.018, 12, 9, true), steel_d,
			Vector3(float(sx) * 0.046, -L1 + 0.100, -0.010))
	_p(up, MK.plate(0.060, 0.050, 0.012, 0.003), joint,
		Vector3(0, -L1 * 0.75, -0.058))
	_bake(sh, up)
	# --- elbow ball
	var ep: Array = []
	_p(ep, MK.sphere(0.080, 24, 18, true), hull2)
	_ring(ep, 0.056, 0.078, 0.016, 28, Vector3(0, 0, 0.050), Vector3.BACK, orange, 0.003)
	_disc(ep, 0.038, 0.012, 20, Vector3(0, 0, 0.058), Vector3.BACK, steel, 0.002)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		_p(ep, MK.prism(6, 0.008, 0.007, 0.008, 0.0), emis,
			Vector3(cos(a) * 0.045, sin(a) * 0.045, 0.056))
	_bake(elb, ep)
	# --- forearm
	var fp: Array = []
	_p(fp, SK.beam(Vector3(0, -0.062, 0), Vector3(0, -L2 + 0.062, 0),
		0.084, 0.088, 0.062, 0.066, 0.30, Vector3.FORWARD, 0.012), hull)
	_p(fp, MK.plate(0.050, L2 * 0.48, 0.018, 0.004), orange_d,
		Vector3(0, -L2 * 0.50, 0.050))
	_p(fp, MK.plate(0.012, L2 * 0.38, 0.008, 0.002), emis,
		Vector3(0, -L2 * 0.50, 0.062))
	_p(fp, SK.beam(Vector3(-0.040, -0.080, -0.012), Vector3(-0.034, -L2 + 0.080, -0.012),
		0.018, 0.018, 0.015, 0.015, 0.30, Vector3.FORWARD, 0.002), steel)
	_p(fp, MK.plate(0.030, 0.070, 0.024, 0.004), joint,
		Vector3(0.048, -L2 * 0.68, 0.0), Vector3(0, 0, 0))
	_bake(elb, fp)
	# --- wrist ball + clamp
	var wp: Array = []
	_p(wp, MK.sphere(0.066, 24, 16, true), hull2)
	_ring(wp, 0.046, 0.064, 0.014, 26, Vector3(0, -0.020, 0), Vector3.UP, orange, 0.002)
	for sx in [1, -1]:
		_p(wp, MK.plate(0.028, 0.060, 0.026, 0.005), steel,
			Vector3(float(sx) * 0.056, -0.040, 0.0), Vector3(0, 0, 0))
		_p(wp, MK.prism(6, 0.009, 0.008, 0.012, 0.0), steel_d,
			Vector3(float(sx) * 0.056, -0.070, 0.0), Vector3(90, 0, 0))
	_bake(wr, wp)
	# --- emitter head (arc blade coil)
	var tp: Array = []
	# black emitter hilt: machined black body, steel collars, no red shell
	_p(tp, SK.beam(Vector3(0, 0, 0), Vector3(0, -L3, 0),
		0.098, 0.100, 0.070, 0.072, 0.32, Vector3.FORWARD, 0.006), hull2)
	for i in 3:
		_ring(tp, 0.040, 0.060, 0.012, 22,
			Vector3(0, -0.026 - float(i) * 0.030, 0), Vector3.UP, steel_d, 0.002)
		_ring(tp, 0.034, 0.044, 0.005, 22,
			Vector3(0, -0.026 - float(i) * 0.030, 0), Vector3.UP, steel, 0.001)
	_p(tp, SK.beam(Vector3(0, -L3 + 0.012, 0), Vector3(0, -L3 - 0.052, 0),
		0.058, 0.058, 0.042, 0.042, 0.30, Vector3.FORWARD, 0.004), steel_d)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.785
		_p(tp, SK.beam(Vector3(cos(a) * 0.040, -L3 - 0.030, sin(a) * 0.040),
			Vector3(cos(a) * 0.062, -L3 - 0.082, sin(a) * 0.062),
			0.018, 0.016, 0.010, 0.010, 0.30, Vector3.FORWARD, 0.002), steel)
		_p(tp, MK.sphere(0.012, 10, 8, true), steel_d,
			Vector3(cos(a) * 0.062, -L3 - 0.084, sin(a) * 0.062))
	# emitter mouth (black; the arc blade itself is the only light here)
	_disc(tp, 0.042, 0.016, 24, Vector3(0, -L3 - 0.010, 0), Vector3.DOWN, joint, 0.002)
	_ring(tp, 0.042, 0.052, 0.010, 24, Vector3(0, -L3 - 0.020, 0), Vector3.DOWN,
		steel, 0.001)
	_bake(tool, tp)


# ================================================================== blade FX

func _build_blade_fx() -> void:
	var fx_script = null
	if ResourceLoader.exists("res://scripts/ch/arc_sword_fx.gd"):
		fx_script = load("res://scripts/ch/arc_sword_fx.gd")
	if fx_script != null:
		var fx := Node3D.new()
		fx.set_script(fx_script)
		fx.name = "ArcSwordFX"
		blade_fx.add_child(fx)
	blade_light = OmniLight3D.new()
	blade_light.light_color = Color(1.0, 0.32, 0.06)
	blade_light.light_energy = 1.1
	blade_light.omni_range = 2.0
	blade_light.shadow_enabled = false
	blade_light.position = Vector3(0, -0.45, 0)
	J["tool"].add_child(blade_light)


func _build_lights() -> void:
	eye_light = OmniLight3D.new()
	eye_light.light_color = Color(1.0, 0.16, 0.035)
	eye_light.light_energy = 0.10
	eye_light.omni_range = 0.55
	eye_light.shadow_enabled = false
	eye_light.position = Vector3(0, 0, cam_z - 0.010)
	J["eye_aim"].add_child(eye_light)
	var under := OmniLight3D.new()
	under.light_color = Color(1.0, 0.22, 0.04)
	under.light_energy = 1.1
	under.omni_range = 1.6
	under.shadow_enabled = false
	under.position = Vector3(0, -0.22, 0.14)
	J["body"].add_child(under)


# ================================================================== apply

func apply_pose(pose: Dictionary) -> void:
	var root: Node3D = J["root"]
	root.rotation = Vector3(0, float(pose.get("root_yaw", 0.0)), 0)
	var body: Node3D = J["body"]
	body.position = Vector3(
		float(pose.get("body_sway", 0.0)),
		body_y + float(pose.get("body_lift", 0.0)),
		float(pose.get("body_shift", 0.0)))
	body.rotation = Vector3(
		float(pose.get("body_pitch", 0.0)),
		float(pose.get("body_yaw", 0.0)),
		float(pose.get("body_roll", 0.0)))
	# Rotating inner optic ball. The outer shell node is never touched.
	var yaw := clampf(float(pose.get("cam_yaw", 0.0)), -1.09, 1.09)
	var pitch := clampf(float(pose.get("cam_pitch", 0.0)), -0.74, 0.74)
	J["eye_aim"].rotation = Vector3(pitch, yaw, 0)
	_apply_joint("sh", pose)
	_apply_joint("elb", pose)
	_apply_joint("wr", pose)
	# Tracks are deliberately NOT part of the pose: they are driven by the
	# locomotion layer below, so body clips and steering stay independent.
	# blade FX on/off
	var on := clampf((float(pose.get("_blade_on", 1.0)) - 0.45) / 0.55, 0.0, 1.0)
	if blade_light:
		blade_light.light_energy = 1.0 * on
	if blade_fx:
		blade_fx.visible = on > 0.02
	var fx := get_node_or_null("root/body/sh/elb/wr/tool/blade_fx/ArcSwordFX")
	if fx:
		fx.visible = on > 0.02
		fx.external_intensity = on


func _apply_joint(j: String, pose: Dictionary) -> void:
	var node: Node3D = J[j]
	var q = pose.get(j + "_q")
	if q is Quaternion:
		node.quaternion = q
	else:
		node.rotation = Vector3(
			float(pose.get(j + "_pitch", 0.0)),
			float(pose.get(j + "_yaw", 0.0)),
			float(pose.get(j + "_roll", 0.0)))


func _update_belt(nm: String, travel: float) -> void:
	var path: Dictionary = _belts.get(nm, {})
	if path.is_empty():
		return
	var mm: MultiMesh = path.get("mm", null)
	if mm == null:
		return
	var plates := int(path["plates"])
	for i in plates:
		mm.set_instance_transform(i, belt_plate_xf(nm, i, travel))
	var mm2: MultiMesh = path.get("mm_acc", null)
	if mm2 != null:
		var step := int(path["acc_step"])
		for j in mm2.instance_count:
			mm2.set_instance_transform(j, belt_plate_xf(nm, j * step + 2, travel))
	# The wheels drive the belt: one wheel turn advances the belt by the wheel
	# circumference, so the angle is travel / wheel_r (sign: +X spin pushes the
	# contact patch backwards, i.e. the vehicle forward).
	var wrot := -travel / wheel_r
	for i in 3:
		var wn: Node3D = J["wheel_%s%d" % [nm, i]]
		wn.rotation = Vector3(wrot, 0, 0)
	var rollers: Array = path.get("rollers", [])
	if not rollers.is_empty():
		var rrot := -travel / 0.060
		for rn in rollers:
			(rn as Node3D).rotation = Vector3(rrot, 0, 0)


# ================================================================== locomotion

## Set the signed ground speed of each track (m/s, +Z = forward). This layer is
## independent of the body clips, so callers can steer with differential track
## speeds without touching the arm/body animation.
func set_track_speed(left_mps: float, right_mps: float) -> void:
	track_vel = Vector2(
		clampf(left_mps, -MAX_TRACK_SPEED, MAX_TRACK_SPEED),
		clampf(right_mps, -MAX_TRACK_SPEED, MAX_TRACK_SPEED))


func track_speeds() -> Vector2:
	return track_vel


## Move both belts to an absolute distance (metres travelled forward). Used by
## deterministic renderers and QA; wheels follow from the same distance.
func set_track_dist(left_m: float, right_m: float) -> void:
	track_dist = Vector2(left_m, right_m)
	_apply_tracks()


func track_distances() -> Vector2:
	return track_dist


## Integrate the current track speeds and refresh the belts / wheels.
func advance_tracks(dt: float) -> void:
	if track_vel == Vector2.ZERO:
		return
	track_dist += track_vel * dt
	_apply_tracks()


## Wheel angles in radians; always dist / wheel_r, never an independent value.
func wheel_angles() -> Vector2:
	return track_dist / wheel_r


func reset_tracks() -> void:
	track_vel = Vector2.ZERO
	track_dist = Vector2.ZERO
	_apply_tracks()


func _apply_tracks() -> void:
	_update_belt("trackL", -track_dist.x)
	_update_belt("trackR", -track_dist.y)


## Plate transform for one belt index at a given travel. Kept separate from the
## MultiMesh upload so headless QA can verify belt motion without a renderer.
func belt_plate_xf(nm: String, index: int, travel: float) -> Transform3D:
	var path: Dictionary = _belts.get(nm, {})
	if path.is_empty():
		return Transform3D.IDENTITY
	var plates := int(path["plates"])
	var total: float = path["len"]
	var spacing := total / float(plates)
	var s := fposmod(float(index) * spacing + travel, total)
	var o := _path_at(path, s)
	var pp: Vector2 = o["p"]
	var nn: Vector2 = o["n"]
	var tt: Vector2 = o["t"]
	var pos := Vector3(0.0, pp.y + nn.y * 0.024, pp.x + nn.x * 0.024)
	var basis := Basis(Vector3.RIGHT, Vector3(0, tt.y, tt.x), Vector3(0, nn.y, nn.x))
	return Transform3D(basis, pos)


func set_blade_params(intensity: float, _speed: float, _charge: float) -> void:
	var fx := get_node_or_null("root/body/sh/elb/wr/tool/blade_fx/ArcSwordFX")
	if fx:
		fx.external_intensity = clampf(intensity, 0.0, 3.0)
		var bs := clampf(float(P.get("blade_length", 1.03)) / 2.24, 0.05, 2.0)
		if fx.has_method("set_blade_scale"):
			fx.set_blade_scale(bs)


func set_lens_params(intensity: float, _x: float) -> void:
	var m := AM.eye_ball()
	m.set_shader_parameter("intensity", intensity)


## Blink the status LED row. `t` is the character clock.
func set_status_time(t: float) -> void:
	for led in _leds:
		var phase: float = led["phase"]
		var rate: float = led["rate"]
		var s := sin(t * rate + phase)
		var on := smoothstep(-0.15, 0.25, s)
		(led["mat"] as StandardMaterial3D).emission_energy_multiplier = 0.22 + 2.6 * on


func blade_world() -> Dictionary:
	var a: Vector3 = marker_base.global_position
	var b: Vector3 = marker_tip.global_position
	return {"a": a, "b": b, "dir": (b - a).normalized()}


func eye_world_dir() -> Vector3:
	var n: Node3D = J["eye_aim"]
	return (n.global_transform.basis * Vector3(0, 0, 1)).normalized()


func measure_radius(_include_weapons := true) -> float:
	var best := 0.0
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi: MeshInstance3D = n
			var gt: Transform3D = mi.global_transform if mi.is_inside_tree() else mi.transform
			var arr := mi.mesh.surface_get_arrays(0)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			for v in arr[Mesh.ARRAY_VERTEX]:
				var w: Vector3 = gt * v
				best = maxf(best, Vector2(w.x, w.z).length())
	return best