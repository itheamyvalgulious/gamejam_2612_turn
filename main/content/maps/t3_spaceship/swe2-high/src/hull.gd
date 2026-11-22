extends RefCounted

const GeoKit = preload("res://src/kit.gd")
const ShipLayout = preload("res://src/layout.gd")

## Exterior hull shell, engine bells, greebles, running lights and the
## inner pressure-shell lining (what you see when a room opens to space).

var k: GeoKit


func _init(kit: GeoKit) -> void:
	k = kit


# Section angle convention: ang=0 -> +X (starboard), PI/2 -> +Y(top).
static func _hull_pt(z: float, ang: float, grow := 0.0) -> Vector3:
	return ShipLayout.hull_pt(z, ang, grow)


func build_exterior(ship: Node3D) -> void:
	var nz := 110
	var na := 72
	# skip quads inside window apertures (bow viewport + skylight strip)
	var f := func(u: float, v: float) -> Vector3:
		return _hull_pt(-150.0 + u * ShipLayout.LEN, v * TAU)
	var eu := 1.0 / nz * 0.5
	var ev := TAU / na * 0.5
	for i in nz:
		var u0 := float(i) / nz
		var u1 := float(i + 1) / nz
		for j in na:
			var v0 := float(j) / na
			var v1 := float(j + 1) / na
			var um := (u0 + u1) * 0.5
			var vm := (v0 + v1) * 0.5
			if _hole(um, vm):
				continue
			var z0 := -150.0 + u0 * ShipLayout.LEN
			var z1 := -150.0 + u1 * ShipLayout.LEN
			var a0 := v0 * TAU
			var a1 := v1 * TAU
			var n := func(z: float, a: float) -> Vector3:
				var p0 := _hull_pt(z, a)
				var pt_ := _hull_pt(z, a + 0.01) - p0
				var pz := _hull_pt(z + 0.2, a) - p0
				return pt_.cross(pz).normalized()
			# submit every quad in BOTH windings: skip based on facing is
			# impossible at build time and the interior is hidden anyway —
			# a doubled surface at 90k tris costs less than the culling
			# asymmetry that killed the whole upper hull
			var qpts := [_hull_pt(z0, a0), _hull_pt(z0, a1),
				_hull_pt(z1, a1), _hull_pt(z1, a0)]
			k.quad_n("hull", [qpts[0], qpts[3], qpts[2], qpts[1]],
				[n.call(z0, a0), n.call(z0, a1), n.call(z1, a1), n.call(z1, a0)],
				[Vector2(a0 * 30.0, z0), Vector2(a1 * 30.0, z0),
				 Vector2(a1 * 30.0, z1), Vector2(a0 * 30.0, z1)])
	# stern transom plate
	var ring := []
	for j in na:
		var a := TAU * j / na
		ring.append(_hull_pt(150.0, a))
	k.part(0.3, 0.0, 1.0)
	k.poly("hull", ring, Vector3.BACK)
	# nose cap
	var nose := []
	for j in na:
		var a := TAU * j / na
		nose.append(_hull_pt(-150.0, a))
	k.poly("hull", nose, Vector3.FORWARD)

	_engine_cluster()
	_hull_greebles()
	var node := k.commit(ship, "Hull", true, 2)
	node.name = "Hull"


## Aperture test on the hull surface (u = z fraction, v = section angle).
func _hole(u: float, v: float) -> bool:
	var z := -150.0 + u * ShipLayout.LEN
	var ang := v * TAU
	# bow bridge viewport: top-front glass, ang ~ PI/2 ± 0.42, z in [-138,-108]
	if z > -138.0 and z < -106.0:
		var da := absf(ang - PI * 0.5)
		if da < 0.40:
			return true
	# atrium skylight: top centre, ang ~ PI/2 ± 0.33, z in [10,32]
	if z > 10.0 and z < 32.0:
		var da2 := absf(ang - PI * 0.5)
		if da2 < 0.33:
			return true
	# porthole rows along habitat (z -36..6) at ang ~ 0.9 and PI-0.9
	if z > -36.0 and z < 6.0:
		for centre in [0.9, PI - 0.9, PI + 0.9, TAU - 0.9]:
			var d := absf(ang - centre)
			if d < 0.07 and fposmod(z * 0.5 + 10.0, 1.0) > 0.25:
				return true
	return false


func _engine_cluster() -> void:
	# 5 bells: one centre + four at ±7x / ±4.5y
	var offs := [Vector2(0, -3), Vector2(-8, -4), Vector2(8, -4), Vector2(-7, 2.5), Vector2(7, 2.5)]
	for i in offs.size():
		var o: Vector2 = offs[i]
		var c := Vector3(o.x, o.y, 150.0)
		# bell: lathe profile, opening pointing +Z (stern). Build axis +Y then rotate.
		var prof := [
			Vector2(0.9, 0.0), Vector2(1.15, 2.0), Vector2(1.5, 4.5),
			Vector2(2.2, 7.5), Vector2(3.3, 10.5), Vector2(4.4, 12.5), Vector2(4.6, 12.9)]
		k.push(Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), c))
		k.part(0.2 + i * 0.13, 0.0, 1.1)
		k.lathe("metal_d", prof, 24)
		# inner glow face
		var prof_in := [
			Vector2(0.75, 0.1), Vector2(1.0, 2.0), Vector2(1.35, 4.4),
			Vector2(2.05, 7.4), Vector2(3.1, 10.4)]
		k.lathe("u_light_o", prof_in, 24, Vector3.ZERO, TAU, 0.0, true)
		# gimbal mount
		k.cyl("metal_a", 0.55, 0.55, 1.6, 10, Vector3(0, -1.6, 0), true)
		k.pop()
	# engine deck vents / thruster quads on hull flanks
	for sgn in [-1, 1]:
		for j in 6:
			var zz := 118.0 + j * 5.0
			var a: float = PI + sgn * 0.5
			var p := _hull_pt(zz, a, 0.05)
			var tang := _hull_pt(zz, a + 0.03) - _hull_pt(zz, a - 0.03)
			var nn := tang.cross(Vector3.FORWARD).normalized()
			k.part(0.5 + j * 0.07, 0.0, 1.0)
			k.quad("metal_a",
				[p - Vector3(0, 1.0, 0) - Vector3(0, 0, 1.4),
				 p - Vector3(0, 1.0, 0) + Vector3(0, 0, 1.4),
				 p + Vector3(0, 0.6, 0) + Vector3(0, 0, 1.4),
				 p + Vector3(0, 0.6, 0) - Vector3(0, 0, 1.4)],
				nn)


func _hull_greebles() -> void:
	var r := k.rng
	# keel + dorsal spines
	k.push(Transform3D(Basis(), Vector3.ZERO))
	for z in range(-70, 60, 10):
		var a := PI / 2.0
		var p := _hull_pt(z + 5.0, a, 0.4)
		k.part(0.4 + z * 0.01, 0.0, 0.9)
		k.box("metal_a", Vector3(2.2, 1.6, 9.6), Vector3(0, p.y + 0.4, z + 5.0))
	for z in range(-40, 100, 14):
		var a2 := -PI / 2.0
		var p2 := _hull_pt(z + 7.0, a2, 0.4)
		k.part(0.6 + z * 0.008, 0.0, 1.0)
		k.box("metal_a", Vector3(3.4, 1.2, 12.0), Vector3(0, p2.y - 0.3, z + 7.0))
	# radiator fins flanks
	for sgn in [-1, 1]:
		for j in 5:
			var z0 := 40.0 + j * 9.0
			var a3: float = PI + sgn * 0.32
			var pp := _hull_pt(z0 + 4.0, a3, 0.25)
			var out := Vector3(sgn * 1.0, 0.2, 0).normalized()
			k.part(0.33 + j * 0.11, 0.0, 0.8)
			k.box("dark", Vector3(0.25, 5.5, 7.5), pp + out * 0.4)
	# comms masts near bow
	for j in 3:
		var zm := -60.0 + j * 8.0
		var pm := _hull_pt(zm, PI / 2.0 - 0.35, 0.1)
		k.part(0.8, 0.0, 0.9)
		k.cyl("metal_d", 0.05, 0.02, 6.0 + j * 1.5, 6, pm, true)
		k.sphere("u_light_r", 0.12, 8, pm + Vector3(0, 6.0 + j * 1.5, 0))
	# running lights
	for z in range(-100, 140, 24):
		for a4 in [0.15, PI - 0.15]:
			var pl := _hull_pt(z, a4, 0.15)
			k.part(0.9, 0.0, 1.0)
			k.sphere("u_light_c", 0.1, 8, pl)
	# name text: raised plates reading ISV MERIDIAN on both flanks (block glyphs)
	_ship_name(-1)
	_ship_name(1)
	k.pop()


const GLYPH := {
	"I": [[0,0],[1,0],[0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[1,6],[2,6],[2,5],[2,4],[2,3],[2,2],[2,1],[2,0]],
	"S": [[0,0],[1,0],[2,0],[2,1],[0,2],[0,3],[1,3],[2,4],[2,5],[2,6],[1,6],[0,6],[0,5],[1,5],[2,3],[1,3],[0,3],[0,4]],
	"V": [[0,6],[0,5],[0,4],[0,3],[1,2],[1,1],[2,3],[2,4],[2,5],[2,6]],
	"M": [[0,0],[0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[1,5],[1,4],[2,6],[2,5],[2,4],[2,3],[2,2],[2,1],[2,0],[1,1],[1,2]],
	"E": [[0,0],[0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[1,0],[2,0],[1,3],[2,3],[1,6],[2,6]],
	"R": [[0,0],[0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[1,6],[2,6],[2,5],[2,4],[1,3],[1,2],[2,2],[2,1],[2,0],[1,1],[1,0]],
	"D": [[0,0],[0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[1,0],[2,0],[2,1],[2,2],[2,3],[2,4],[2,5],[1,6]],
	"N": [[0,0],[0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[1,5],[1,4],[2,0],[2,1],[2,2],[2,3],[2,4],[2,5],[2,6],[1,2],[1,3]],
	"A": [[0,0],[1,0],[2,0],[0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[2,1],[2,2],[2,3],[2,4],[2,5],[2,6],[1,3],[1,6]],
}


func _ship_name(side: int) -> void:
	var text := "ISV MERIDIAN"
	var cell := 0.55
	var x0 := -((text.length() * 3 - 1) * cell) * 0.5
	var zz := -8.0
	var ang := PI * 0.5 + side * 1.05
	var p0 := _hull_pt(zz, ang, 0.55)
	var along := Vector3(0, 0, 1.0)  # letters along z
	var up := Vector3(0, 1, 0)
	var out := Vector3(side, 0.35, 0).normalized()
	var cx := 0.0
	for ch in text:
		if ch == " ":
			cx += 4.0 * cell
			continue
		if not GLYPH.has(ch):
			cx += 3.0 * cell
			continue
		for gpos in GLYPH[ch]:
			var pt: Vector3 = p0 + Vector3(0, -gpos[0] * cell - 2.0 * cell, 0) + along * (cx + gpos[1] * cell)
			k.part(0.5, 0.0, 1.0)
			k.box("u_light_c", Vector3(0.12, cell * 0.92, cell * 0.92),
				pt + out * 0.06)
		cx += 3.0 * cell


## Inner pressure shell (inward normals) — backdrop behind window cutouts and
## the visible inner face above/below the built zones. Sparse + cheap.
func build_inner_shell(ship: Node3D) -> void:
	var nz := 90
	var na := 48
	var f := func(u: float, v: float) -> Vector3:
		return _hull_pt(-148.0 + u * 296.0, v * TAU, -1.1)
	# reuse grid but flipped
	var eu := 1.0 / nz * 0.5
	var ev := TAU / na * 0.5
	for i in nz:
		var u0 := float(i) / nz
		var u1 := float(i + 1) / nz
		for j in na:
			var v0 := float(j) / na
			var v1 := float(j + 1) / na
			var z0 := -148.0 + u0 * 296.0
			var z1 := -148.0 + u1 * 296.0
			var a0 := v0 * TAU
			var a1 := v1 * TAU
			var n := func(z: float, a: float) -> Vector3:
				var p0 := _hull_pt(z, a, -1.1)
				var pt_ := _hull_pt(z, a + 0.01, -1.1) - p0
				var pz := _hull_pt(z + 0.2, a, -1.1) - p0
				return -pt_.cross(pz).normalized()
			var qpts := [_hull_pt(z0, a0, -1.1), _hull_pt(z0, a1, -1.1),
				_hull_pt(z1, a1, -1.1), _hull_pt(z1, a0, -1.1)]
			k.quad_n("metal_a", [qpts[0], qpts[3], qpts[2], qpts[1]],
				[n.call(z0, a0), n.call(z0, a1), n.call(z1, a1), n.call(z1, a0)],
				[Vector2(a0 * 30.0, z0), Vector2(a1 * 30.0, z0),
				 Vector2(a1 * 30.0, z1), Vector2(a0 * 30.0, z1)])
	# (material stays metal_a — dark structural look)
	var nose_ring := []
	for j in na:
		var a2 := TAU * j / na
		nose_ring.append(_hull_pt(-148.0, a2, -1.1))
	k.poly("metal_a", nose_ring, Vector3.BACK)
	var stern_ring := []
	for j in na:
		var a3 := TAU * j / na
		stern_ring.append(_hull_pt(148.0, a3, -1.1))
	k.poly("metal_a", stern_ring, Vector3.FORWARD)
	k.commit(ship, "InnerShell", false, 1)
