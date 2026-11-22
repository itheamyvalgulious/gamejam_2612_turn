extends Node3D

## Landmarks: twist tower, hyperboloid cooling tower (cosh section),
## ferris wheel, elevated rail ring, fan cable-stayed bridge.
## Each is its own procedural mesh — the signatures of the skyline.

const CityLayout = preload("res://src/city.gd")

var _hf: RefCounted


func build(city: RefCounted, hf: RefCounted) -> void:
	_hf = hf
	_twist_tower(city)
	_cooling_tower(city)
	_ferris_wheel(city)
	_sky_rail(city)
	_cable_bridge(city)


func _cosh(x: float) -> float:
	return (exp(x) + exp(-x)) * 0.5


func _mat(shader: String, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://gfx/" + shader)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


func _mesh(name: String, st: SurfaceTool, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	return mi


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color, uv_scale := 0.02) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n); st.set_color(col)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 1)); st.add_vertex(d)


# ------------------------------------------------------------ twist ----
## A tower whose floor plate rotates linearly with height: 0.55°/m over
## 190 m = a full ~105° corkscrew. Real floors, real corners — the
## silhouette torques against the skyline.
func _twist_tower(city: RefCounted) -> void:
	var cx := -80.0
	var cz := -140.0
	var gy: float = _hf.h(cx, cz)
	var H := 190.0
	var floors := 44
	var W := 34.0
	var D := 26.0
	var twist := deg_to_rad(105.0)   # total twist over the height
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.11, 0.13, 0.19)
	# corners of the base plate
	var corner := [Vector2(-W / 2, -D / 2), Vector2(W / 2, -D / 2),
		Vector2(W / 2, D / 2), Vector2(-W / 2, D / 2)]
	for f in floors:
		var y0 := gy + H * float(f) / float(floors)
		var y1 := gy + H * float(f + 1) / float(floors)
		var a0 := twist * float(f) / float(floors)
		var a1 := twist * float(f + 1) / float(floors)
		for k in 4:
			var c0: Vector2 = corner[k]
			var c1: Vector2 = corner[(k + 1) % 4]
			var p00 := Vector2(cx + c0.x * cos(a0) - c0.y * sin(a0),
				cz + c0.x * sin(a0) + c0.y * cos(a0))
			var p01 := Vector2(cx + c1.x * cos(a0) - c1.y * sin(a0),
				cz + c1.x * sin(a0) + c1.y * cos(a0))
			var p10 := Vector2(cx + c0.x * cos(a1) - c0.y * sin(a1),
				cz + c0.x * sin(a1) + c0.y * cos(a1))
			var p11 := Vector2(cx + c1.x * cos(a1) - c1.y * sin(a1),
				cz + c1.x * sin(a1) + c1.y * cos(a1))
			_quad(st,
				Vector3(p00.x, y0, p00.y), Vector3(p01.x, y0, p01.y),
				Vector3(p11.x, y1, p11.y), Vector3(p10.x, y1, p10.y), col)
	# crown: a lit blade
	st.set_color(Color(0.9, 0.3, 0.6))
	var top := gy + H
	var aw := twist
	for k in 4:
		var c0: Vector2 = corner[k]
		var c1: Vector2 = corner[(k + 1) % 4]
		var r0 := Vector2(cx + c0.x * cos(aw) - c0.y * sin(aw),
			cz + c0.x * sin(aw) + c0.y * cos(aw))
		var r1 := Vector2(cx + c1.x * cos(aw) - c1.y * sin(aw),
			cz + c1.x * sin(aw) + c1.y * cos(aw))
		_quad(st, Vector3(r0.x, top, r0.y), Vector3(r1.x, top, r1.y),
			Vector3(r1.x, top + 14.0, r1.y), Vector3(r0.x, top + 14.0, r0.y),
			Color(0.9, 0.3, 0.6))
	_mesh("TwistTower", st, _mat("tower.gdshader"))


# ----------------------------------------------------------- cooling ----
## Hyperboloid of one sheet: r(z) = r0 * _cosh((z - z0)/a) — the waist
## pinches, the lip flares. The section is a real cosh curve.
func _cooling_tower(city: RefCounted) -> void:
	var cx := 1700.0
	var cz := -950.0
	var gy: float = _hf.h(cx, cz)
	var H := 95.0
	var r_top := 30.0
	var r_base := 40.0
	var r_waist := 21.0
	var z_waist := H * 0.62           # waist sits above mid-height
	# solve a so r(H) = r_top: r_waist*_cosh((H-z_w)/a) = r_top;
	# GDScript has no acosh — expand it: acosh(x)=ln(x+sqrt(x²-1))
	var ac := log(r_top / r_waist + sqrt(r_top * r_top / (r_waist * r_waist) - 1.0))
	var a := (H - z_waist) / ac
	var segs := 40
	var rings := 26
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.42, 0.38, 0.34)
	for i in rings:
		var y0 := H * float(i) / float(rings)
		var y1 := H * float(i + 1) / float(rings)
		var r0 := r_waist * _cosh((y0 - z_waist) / a)
		var r1 := r_waist * _cosh((y1 - z_waist) / a)
		# widen the skirt below the throat back toward r_base
		r0 = maxf(r0, r_base - (r_base - r_waist) * (y0 / z_waist))
		r1 = maxf(r1, r_base - (r_base - r_waist) * (y1 / z_waist))
		for s in segs:
			var t0 := TAU * float(s) / float(segs)
			var t1 := TAU * float(s + 1) / float(segs)
			_quad(st,
				Vector3(cx + cos(t0) * r0, gy + y0, cz + sin(t0) * r0),
				Vector3(cx + cos(t1) * r0, gy + y0, cz + sin(t1) * r0),
				Vector3(cx + cos(t1) * r1, gy + y1, cz + sin(t1) * r1),
				Vector3(cx + cos(t0) * r1, gy + y1, cz + sin(t0) * r1), col)
	# rim band
	for s in segs:
		var t0 := TAU * float(s) / float(segs)
		var t1 := TAU * float(s + 1) / float(segs)
		var rt := r_waist * _cosh((H - z_waist) / a)
		_quad(st,
			Vector3(cx + cos(t0) * rt, gy + H, cz + sin(t0) * rt),
			Vector3(cx + cos(t1) * rt, gy + H, cz + sin(t1) * rt),
			Vector3(cx + cos(t1) * rt + cos(t1) * 3.0, gy + H + 1.5, cz + sin(t1) * rt + sin(t1) * 3.0),
			Vector3(cx + cos(t0) * rt + cos(t0) * 3.0, gy + H + 1.5, cz + sin(t0) * rt + sin(t0) * 3.0),
			Color(0.30, 0.27, 0.24))
	_mesh("CoolingTower", st, _mat("landmark.gdshader"))


# ------------------------------------------------------------- wheel ----
## Ferris wheel: rim ring, 16 cabins, spokes, A-frame legs.
func _ferris_wheel(city: RefCounted) -> void:
	var cx := -1400.0
	var cz := 1100.0
	var gy: float = _hf.h(cx, cz)
	var R := 42.0
	var hub_y := gy + R + 8.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := Color(0.95, 0.35, 0.65)   # neon rim
	var strut := Color(0.30, 0.32, 0.40)
	var N := 48
	# rim as a segmented tube — a real torus section with depth so it
	# reads as a glowing ring from any angle, not a paper arc
	var tube := 1.4
	var depth := 2.2
	for i in N:
		var t0 := TAU * float(i) / float(N)
		var t1 := TAU * float(i + 1) / float(N)
		for zz in [-depth, depth]:
			_quad(st,
				Vector3(cx + cos(t0) * (R - tube), hub_y + sin(t0) * (R - tube), cz + zz),
				Vector3(cx + cos(t1) * (R - tube), hub_y + sin(t1) * (R - tube), cz + zz),
				Vector3(cx + cos(t1) * (R + tube), hub_y + sin(t1) * (R + tube), cz + zz),
				Vector3(cx + cos(t0) * (R + tube), hub_y + sin(t0) * (R + tube), cz + zz),
				rim)
		# outer edge strip
		_quad(st,
			Vector3(cx + cos(t0) * (R + tube), hub_y + sin(t0) * (R + tube), cz - depth),
			Vector3(cx + cos(t1) * (R + tube), hub_y + sin(t1) * (R + tube), cz - depth),
			Vector3(cx + cos(t1) * (R + tube), hub_y + sin(t1) * (R + tube), cz + depth),
			Vector3(cx + cos(t0) * (R + tube), hub_y + sin(t0) * (R + tube), cz + depth),
			rim)
	# spokes: radial bars hub → rim, one every other segment; each is a
	# proper quad with width across the wheel plane so it reads at range
	for i in range(0, N, 2):
		var t := TAU * float(i) / float(N)
		var dir := Vector2(cos(t), sin(t))
		var per := Vector2(-dir.y, dir.x)
		var sw := 0.7                      # half-width of the spoke bar
		var p_hub_a := Vector2(cx, hub_y) + per * sw
		var p_hub_b := Vector2(cx, hub_y) - per * sw
		var p_rim_a := Vector2(cx, hub_y) + dir * (R - tube) + per * sw
		var p_rim_b := Vector2(cx, hub_y) + dir * (R - tube) - per * sw
		_quad(st,
			Vector3(p_hub_a.x, p_hub_a.y, cz),
			Vector3(p_rim_a.x, p_rim_a.y, cz),
			Vector3(p_rim_b.x, p_rim_b.y, cz),
			Vector3(p_hub_b.x, p_hub_b.y, cz), strut)
	# hub disc
	for i in N:
		var t0 := TAU * float(i) / float(N)
		var t1 := TAU * float(i + 1) / float(N)
		_quad(st,
			Vector3(cx, hub_y, cz),
			Vector3(cx + cos(t0) * 3.0, hub_y + sin(t0) * 3.0, cz),
			Vector3(cx + cos(t1) * 3.0, hub_y + sin(t1) * 3.0, cz),
			Vector3(cx, hub_y, cz), strut)
	# cabins — hanging pods on the rim, capsule silhouette
	for i in range(0, N, 3):
		var t := TAU * float(i) / float(N)
		var px := cx + cos(t) * R
		var py := hub_y + sin(t) * R
		# pod: a small box hanging below the rim point
		_quad(st,
			Vector3(px - 2.0, py - 4.6, cz - 1.4), Vector3(px + 2.0, py - 4.6, cz - 1.4),
			Vector3(px + 2.0, py - 0.4, cz - 1.4), Vector3(px - 2.0, py - 0.4, cz - 1.4),
			Color(0.9, 0.7, 0.3))
		# hanger arm
		_quad(st,
			Vector3(px - 0.18, py - 0.4, cz), Vector3(px + 0.18, py - 0.4, cz),
			Vector3(px + 0.18, py, cz), Vector3(px - 0.18, py, cz), strut)
	# A-frame legs — two splayed pairs meeting at the hub
	for s in [-1.0, 1.0]:
		# front leg + back leg per side
		for zz in [-6.0, 6.0]:
			_quad(st,
				Vector3(cx + s * 24.0, gy, cz + zz), Vector3(cx + s * 21.0, gy, cz + zz),
				Vector3(cx + s * 2.5, hub_y, cz + zz * 0.3), Vector3(cx + s * 4.5, hub_y, cz + zz * 0.3),
				strut)
	_mesh("FerrisWheel", st, _mat("landmark.gdshader"))


# -------------------------------------------------------------- rail ----
## Sky rail: an elevated guideway loop over the avenue grid — a thin
## deck on pylons with a glowing maglev ribbon.
func _sky_rail(city: RefCounted) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck := Color(0.10, 0.12, 0.16)
	var beam := Color(0.15, 0.95, 0.95)
	var h_deck := 17.0
	var dw := 5.0
	# the loop follows diag_a then swings back along the waterfront
	var loop := PackedVector2Array()
	for i in _city_diag(city):
		loop.append(i)
	for i in range(loop.size() - 1):
		var p0 := loop[i]
		var p1 := loop[i + 1]
		var t: Vector2 = (p1 - p0).normalized()
		var n := Vector2(-t.y, t.x)
		var w := dw * 0.5
		var a := Vector3(p0.x + n.x * w, h_deck, p0.y + n.y * w)
		var b := Vector3(p1.x + n.x * w, h_deck, p1.y + n.y * w)
		var c := Vector3(p1.x - n.x * w, h_deck, p1.y - n.y * w)
		var d := Vector3(p0.x - n.x * w, h_deck, p0.y - n.y * w)
		_quad(st, a, b, c, d, deck)
		# side skirts under the deck edge — a real box section, not a
		# floating ribbon; the beam sits inside a shallow trough
		var skirt := 1.6
		for s in [-1.0, 1.0]:
			_quad(st,
				Vector3(p0.x + n.x * w * s, h_deck - skirt, p0.y + n.y * w * s),
				Vector3(p1.x + n.x * w * s, h_deck - skirt, p1.y + n.y * w * s),
				Vector3(p1.x + n.x * w * s, h_deck, p1.y + n.y * w * s),
				Vector3(p0.x + n.x * w * s, h_deck, p0.y + n.y * w * s), deck)
		# glow ribbon on the deck centreline — the maglev light line;
		# deck side-walls so the guideway has a silhouette
		var g := 1.4
		_quad(st,
			Vector3(p0.x + n.x * g, h_deck + 0.5, p0.y + n.y * g),
			Vector3(p1.x + n.x * g, h_deck + 0.5, p1.y + n.y * g),
			Vector3(p1.x - n.x * g, h_deck + 0.5, p1.y - n.y * g),
			Vector3(p0.x - n.x * g, h_deck + 0.5, p0.y - n.y * g), beam)
		# deck edge parapets — a lit rim each side
		for s in [-1.0, 1.0]:
			_quad(st,
				Vector3(p0.x + n.x * w * s, h_deck, p0.y + n.y * w * s),
				Vector3(p1.x + n.x * w * s, h_deck, p1.y + n.y * w * s),
				Vector3(p1.x + n.x * w * s, h_deck + 1.1, p1.y + n.y * w * s),
				Vector3(p0.x + n.x * w * s, h_deck + 1.1, p0.y + n.y * w * s), deck)
		# pylon every ~4th segment
		if i % 4 == 0:
			var py: float = _hf.h(p0.x, p0.y)
			_quad(st,
				Vector3(p0.x - 1.6, py, p0.y - 1.6), Vector3(p0.x + 1.6, py, p0.y - 1.6),
				Vector3(p0.x + 1.6, h_deck, p0.y - 1.6), Vector3(p0.x - 1.6, h_deck, p0.y - 1.6), deck)
			_quad(st,
				Vector3(p0.x + 1.6, py, p0.y + 1.6), Vector3(p0.x - 1.6, py, p0.y + 1.6),
				Vector3(p0.x - 1.6, h_deck, p0.y + 1.6), Vector3(p0.x + 1.6, h_deck, p0.y + 1.6), deck)
	# a train on the loop: lit capsule mid-segment so the rail reads as
	# a working line, not just a ribbon
	var ti := int(loop.size() * 0.35)
	var tp0 := loop[ti]
	var tp1 := loop[ti + 1]
	var tt: Vector2 = (tp1 - tp0).normalized()
	var tn := Vector2(-tt.y, tt.x)
	var tlen := 26.0
	var tmid := (tp0 + tp1) * 0.5
	var tw := 2.6
	var th2 := 2.4
	var ta := tmid - tt * tlen * 0.5
	var tb := tmid + tt * tlen * 0.5
	# body
	_quad(st,
		Vector3(ta.x + tn.x * tw / 2, h_deck + 0.6, ta.y + tn.y * tw / 2),
		Vector3(tb.x + tn.x * tw / 2, h_deck + 0.6, tb.y + tn.y * tw / 2),
		Vector3(tb.x + tn.x * tw / 2, h_deck + 0.6 + th2, tb.y + tn.y * tw / 2),
		Vector3(ta.x + tn.x * tw / 2, h_deck + 0.6 + th2, ta.y + tn.y * tw / 2),
		Color(0.7, 0.75, 0.85))
	_quad(st,
		Vector3(ta.x - tn.x * tw / 2, h_deck + 0.6, ta.y - tn.y * tw / 2),
		Vector3(ta.x - tn.x * tw / 2, h_deck + 0.6 + th2, ta.y - tn.y * tw / 2),
		Vector3(tb.x - tn.x * tw / 2, h_deck + 0.6 + th2, tb.y - tn.y * tw / 2),
		Vector3(tb.x - tn.x * tw / 2, h_deck + 0.6, tb.y - tn.y * tw / 2),
		Color(0.7, 0.75, 0.85))
	# window band
	_quad(st,
		Vector3(ta.x + tn.x * (tw / 2 + 0.05), h_deck + 1.5, ta.y + tn.y * (tw / 2 + 0.05)),
		Vector3(tb.x + tn.x * (tw / 2 + 0.05), h_deck + 1.5, tb.y + tn.y * (tw / 2 + 0.05)),
		Vector3(tb.x + tn.x * (tw / 2 + 0.05), h_deck + 2.1, tb.y + tn.y * (tw / 2 + 0.05)),
		Vector3(ta.x + tn.x * (tw / 2 + 0.05), h_deck + 2.1, ta.y + tn.y * (tw / 2 + 0.05)),
		Color(0.9, 0.85, 0.5))
	_mesh("SkyRail", st, _mat("landmark.gdshader"))


func _city_diag(city: RefCounted) -> PackedVector2Array:
	return city.diag_a


# ------------------------------------------------------------ bridge ----
## Fan cable-stayed bridge: a deck across the canal, one pylon, cables
## fanning from the mast head to deck anchors.
func _cable_bridge(city: RefCounted) -> void:
	# pick a crossing on the river near the CBD edge
	var pts: PackedVector2Array = _hf.river_pts
	var ci := int(pts.size() * 0.42)
	var p0 := pts[ci]
	var p1 := pts[ci + 1]
	var t: Vector2 = (p1 - p0).normalized()
	var n := Vector2(-t.y, t.x)
	var span := 190.0
	var deck_y := 3.0
	# deck along the normal — a chord crossing the channel
	var d0 := Vector2(p0.x - n.x * span * 0.55, p0.y - n.y * span * 0.55)
	var d1 := Vector2(p0.x + n.x * span * 0.45, p0.y + n.y * span * 0.45)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck := Color(0.16, 0.17, 0.20)
	var cable := Color(0.85, 0.35, 0.9)
	var mast_p := Vector2(p0.x + n.x * span * 0.28, p0.y + n.y * span * 0.28)
	var mast_h := 78.0
	# deck
	var w := 9.0
	var dt: Vector2 = (d1 - d0).normalized()
	var dn := Vector2(-dt.y, dt.x)
	_quad(st,
		Vector3(d0.x + dn.x * w, deck_y, d0.y + dn.y * w),
		Vector3(d1.x + dn.x * w, deck_y, d1.y + dn.y * w),
		Vector3(d1.x - dn.x * w, deck_y, d1.y - dn.y * w),
		Vector3(d0.x - dn.x * w, deck_y, d0.y - dn.y * w), deck)
	# pylon: tapered vertical
	var pb: float = _hf.h(mast_p.x, mast_p.y)
	for s in 6:
		var f0 := float(s) / 6.0
		var f1 := float(s + 1) / 6.0
		var w0 := lerpf(4.2, 2.0, f0)
		var w1 := lerpf(4.2, 2.0, f1)
		_quad(st,
			Vector3(mast_p.x - w0, pb + mast_h * f0, mast_p.y - w0),
			Vector3(mast_p.x + w0, pb + mast_h * f0, mast_p.y - w0),
			Vector3(mast_p.x + w1, pb + mast_h * f1, mast_p.y - w1),
			Vector3(mast_p.x - w1, pb + mast_h * f1, mast_p.y - w1), deck)
		_quad(st,
			Vector3(mast_p.x - w0, pb + mast_h * f0, mast_p.y + w0),
			Vector3(mast_p.x + w0, pb + mast_h * f0, mast_p.y + w0),
			Vector3(mast_p.x + w1, pb + mast_h * f1, mast_p.y + w1),
			Vector3(mast_p.x - w1, pb + mast_h * f1, mast_p.y + w1), deck)
	# fan cables: mast head → deck anchors along both sides
	var top := Vector3(mast_p.x, pb + mast_h, mast_p.y)
	for k in range(1, 7):
		var f := float(k) / 7.0
		for side in [-1.0, 1.0]:
			var ax: float = d0.x + (d1.x - d0.x) * (0.28 + side * f * 0.30)
			var az: float = d0.y + (d1.y - d0.y) * (0.28 + side * f * 0.30)
			var aw := 0.22
			_quad(st,
				Vector3(top.x - aw, top.y, top.z),
				Vector3(top.x + aw, top.y, top.z),
				Vector3(ax + aw, deck_y, az),
				Vector3(ax - aw, deck_y, az), cable)
	_mesh("CableBridge", st, _mat("landmark.gdshader"))
