extends Node3D

## A cutaway interior: one tower's mid-floor cross-section — slab,
## partitions, furniture, occupants' clutter. Rendered as a real room
## at real scale, positioned where the interior preset's camera lives.

var _hf: RefCounted
var floor_y := 0.0          # exposed so the shot preset can aim at it
var floor_y2 := 0.0


func build(hf: RefCounted) -> void:
	_hf = hf
	_room()
	_apartment()


func _mat(c: Color, rough := 0.9, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color,
		rough := 0.9, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(col, rough, emit)
	parent.add_child(mi)
	return mi


## A three-room apartment-office hybrid on a tower's 12th floor,
## cut open on the south face so the camera sees in. Three programs —
## the seed picks one: studio apartment, open office, or corner suite.
func _room() -> void:
	var ox := 12.0          # room origin — inside the CBD block
	var oz := 8.0
	var gy: float = _hf.h(ox, oz)
	var fy := gy + 12 * 3.3            # floor 12
	floor_y = fy
	var kind := 0           # program: 0 loft-studio (default build)
	var W := 14.0                      # room width  (x)
	var D := 9.0                       # depth       (z)
	var H := 3.0                       # ceiling
	var T := 0.18                      # slab thickness

	var root := Node3D.new()
	root.name = "Interior"
	add_child(root)

	# host shell: opaque mass below the room's floor + walls on the
	# non-cut faces + a roof cap — reads as "a floor of a building",
	# not a floating box. The S face stays open (the glazing wall).
	var sw := W + 2.0
	var sd := D + 2.0
	var sx := ox - 1.0
	var sz := oz - 1.0
	var shell := Color(0.10, 0.11, 0.15)
	# mass below the cut floor
	_box(root, Vector3(sx + sw / 2, (gy + fy) / 2, sz + sd / 2),
		Vector3(sw, fy - gy, sd), shell)
	# N wall above room to roof cap
	_box(root, Vector3(sx + sw / 2, fy + (H + 6.0) / 2, sz),
		Vector3(sw, H + 6.0, 0.4), shell)
	# E wall
	_box(root, Vector3(sx + sw, fy + (H + 6.0) / 2, sz + sd / 2),
		Vector3(0.4, H + 6.0, sd), shell)
	# W wall
	_box(root, Vector3(sx, fy + (H + 6.0) / 2, sz + sd / 2),
		Vector3(0.4, H + 6.0, sd), shell)
	# roof cap slab
	_box(root, Vector3(sx + sw / 2, fy + H + 6.0, sz + sd / 2),
		Vector3(sw, 0.5, sd), Color(0.08, 0.09, 0.12))

	# floor + ceiling slabs
	_box(root, Vector3(ox + W / 2, fy - T / 2, oz + D / 2),
		Vector3(W, T, D), Color(0.16, 0.14, 0.12))
	_box(root, Vector3(ox + W / 2, fy + H + T / 2, oz + D / 2),
		Vector3(W, T, D), Color(0.13, 0.12, 0.11))

	# walls: north solid, east solid, west solid, south = glass
	# (the cut face the camera looks through)
	_box(root, Vector3(ox + W / 2, fy + H / 2, oz),           # north
		Vector3(W, H, T), Color(0.22, 0.21, 0.20))
	_box(root, Vector3(ox + W, fy + H / 2, oz + D / 2),       # east
		Vector3(T, H, D), Color(0.22, 0.21, 0.20))
	_box(root, Vector3(ox, fy + H / 2, oz + D / 2),           # west
		Vector3(T, H, D), Color(0.22, 0.21, 0.20))
	# south glazing: two mullions + panes (alpha-blended)
	_box(root, Vector3(ox + W / 2, fy + H - 0.35, oz + D),
		Vector3(W, 0.7, T), Color(0.22, 0.21, 0.20))
	_box(root, Vector3(ox + W / 2, fy + 0.25, oz + D),
		Vector3(W, 0.5, T), Color(0.22, 0.21, 0.20))
	for i in 4:
		_box(root, Vector3(ox + W * float(i) / 4.0, fy + H / 2, oz + D),
			Vector3(0.08, H, 0.08), Color(0.1, 0.1, 0.11))

	# ---- zone A: desk bay (west end) ----------------------------------
	# desk slab on legs
	_box(root, Vector3(ox + 2.6, fy + 0.74, oz + 2.2),
		Vector3(3.2, 0.08, 1.1), Color(0.30, 0.24, 0.16), 0.7)
	for dx in [-1.4, 1.4]:
		for dz in [-0.4, 0.4]:
			_box(root, Vector3(ox + 2.6 + dx, fy + 0.36, oz + 2.2 + dz),
				Vector3(0.07, 0.72, 0.07), Color(0.18, 0.16, 0.13))
	# monitor + glow
	_box(root, Vector3(ox + 2.6, fy + 1.15, oz + 1.85),
		Vector3(1.1, 0.6, 0.05), Color(0.02, 0.02, 0.03), 0.3)
	_box(root, Vector3(ox + 2.6, fy + 1.15, oz + 1.83),
		Vector3(0.9, 0.42, 0.02), Color(0.25, 0.65, 0.85), 0.3, 1.6)
	_box(root, Vector3(ox + 2.6, fy + 0.82, oz + 1.9),
		Vector3(0.08, 0.3, 0.08), Color(0.15, 0.15, 0.16))
	# chair
	_box(root, Vector3(ox + 2.6, fy + 0.45, oz + 3.4),
		Vector3(0.7, 0.09, 0.7), Color(0.10, 0.10, 0.12))
	_box(root, Vector3(ox + 2.6, fy + 0.95, oz + 3.75),
		Vector3(0.7, 0.9, 0.09), Color(0.10, 0.10, 0.12))
	_box(root, Vector3(ox + 2.6, fy + 0.22, oz + 3.4),
		Vector3(0.09, 0.45, 0.09), Color(0.14, 0.14, 0.15))

	# ---- zone B: shelving wall (north) --------------------------------
	for s in 3:
		_box(root, Vector3(ox + 7.5, fy + 0.7 + s * 0.75, oz + 0.45),
			Vector3(4.6, 0.06, 0.55), Color(0.24, 0.20, 0.15))
	for i in 9:
		var bx := ox + 5.6 + i * 0.48
		var bh := 0.28 + _h(i * 7) * 0.3
		_box(root, Vector3(bx, fy + 0.72 + bh / 2, oz + 0.45),
			Vector3(0.16, bh, 0.3),
			Color(0.3 + _h(i) * 0.3, 0.15 + _h(i * 3) * 0.15, 0.1), 0.85)

	# ---- zone C: lounge (east end) ------------------------------------
	_box(root, Vector3(ox + 11.6, fy + 0.4, oz + 6.6),
		Vector3(2.6, 0.45, 1.1), Color(0.16, 0.13, 0.19))   # sofa seat
	_box(root, Vector3(ox + 11.6, fy + 0.85, oz + 7.05),
		Vector3(2.6, 0.9, 0.25), Color(0.16, 0.13, 0.19))  # sofa back
	_box(root, Vector3(ox + 10.6, fy + 0.3, oz + 4.6),
		Vector3(0.8, 0.3, 0.8), Color(0.10, 0.09, 0.11))   # side table
	_box(root, Vector3(ox + 10.6, fy + 0.62, oz + 4.6),
		Vector3(0.3, 0.34, 0.3), Color(0.9, 0.5, 0.2), 0.5, 0.9)  # lamp

	# rug
	_box(root, Vector3(ox + 10.4, fy + 0.01, oz + 6.2),
		Vector3(4.2, 0.02, 3.0), Color(0.18, 0.09, 0.14), 1.0)

	# partition: partial divider between desk bay and lounge
	_box(root, Vector3(ox + 6.4, fy + H / 2, oz + 4.6),
		Vector3(0.12, H, 3.4), Color(0.2, 0.19, 0.18))

	# pendant lights: two glowing bars under the ceiling
	_box(root, Vector3(ox + 3.0, fy + H - 0.55, oz + 3.0),
		Vector3(1.6, 0.06, 0.14), Color(0.95, 0.85, 0.6), 0.4, 2.2)
	_box(root, Vector3(ox + 3.0, fy + H - 0.3, oz + 3.0),
		Vector3(0.03, 0.5, 0.03), Color(0.1, 0.1, 0.1))
	_box(root, Vector3(ox + 10.8, fy + H - 0.55, oz + 6.0),
		Vector3(1.6, 0.06, 0.14), Color(0.95, 0.85, 0.6), 0.4, 2.2)
	_box(root, Vector3(ox + 10.8, fy + H - 0.3, oz + 6.0),
		Vector3(0.03, 0.5, 0.03), Color(0.1, 0.1, 0.1))

	# a point light inside so the room actually lights
	var pl := OmniLight3D.new()
	pl.position = Vector3(ox + W / 2, fy + H - 0.6, oz + D / 2)
	pl.light_color = Color(1.0, 0.82, 0.55)
	pl.light_energy = 1.6
	pl.omni_range = 12.0
	root.add_child(pl)


func _h(i: int) -> float:
	var s := sin(float(i) * 127.1 + 311.7) * 43758.5453
	return s - floor(s)


## A walk-up apartment: bedroom nook + galley kitchen + living end.
## Different floor (6th), different district (residential SE), a door
## onto a lit stair landing so the floor relationship is explicit.
func _apartment() -> void:
	var ox := 980.0
	var oz := 720.0
	var gy: float = _hf.h(ox, oz)
	var fy := gy + 6 * 3.1
	floor_y2 = fy
	var W := 11.0
	var D := 8.0
	var H := 2.9
	var T := 0.16

	var root := Node3D.new()
	root.name = "InteriorApt"
	add_child(root)

	# host block: mass below + walls + cap, same cutaway scheme
	var sw := W + 1.6
	var sd := D + 1.6
	var sx := ox - 0.8
	var sz := oz - 0.8
	var shell := Color(0.20, 0.16, 0.13)
	_box(root, Vector3(sx + sw / 2, (gy + fy) / 2, sz + sd / 2),
		Vector3(sw, fy - gy, sd), shell)
	_box(root, Vector3(sx + sw / 2, fy + (H + 5.0) / 2, sz),
		Vector3(sw, H + 5.0, 0.35), shell)
	_box(root, Vector3(sx + sw, fy + (H + 5.0) / 2, sz + sd / 2),
		Vector3(0.35, H + 5.0, sd), shell)
	_box(root, Vector3(sx, fy + (H + 5.0) / 2, sz + sd / 2),
		Vector3(0.35, H + 5.0, sd), shell)
	_box(root, Vector3(sx + sw / 2, fy + H + 5.0, sz + sd / 2),
		Vector3(sw, 0.45, sd), Color(0.16, 0.13, 0.11))

	# floor + ceiling
	_box(root, Vector3(ox + W / 2, fy - T / 2, oz + D / 2),
		Vector3(W, T, D), Color(0.24, 0.18, 0.12))
	_box(root, Vector3(ox + W / 2, fy + H + T / 2, oz + D / 2),
		Vector3(W, T, D), Color(0.2, 0.17, 0.14))

	# walls: N solid, E solid, W solid; S = glazing + entry door
	_box(root, Vector3(ox + W / 2, fy + H / 2, oz),
		Vector3(W, H, T), Color(0.33, 0.27, 0.20))
	_box(root, Vector3(ox + W, fy + H / 2, oz + D / 2),
		Vector3(T, H, D), Color(0.33, 0.27, 0.20))
	_box(root, Vector3(ox, fy + H / 2, oz + D / 2),
		Vector3(T, H, D), Color(0.33, 0.27, 0.20))
	# S face: header + sill + two mullions, panes implied by glazing gaps
	_box(root, Vector3(ox + W / 2, fy + H - 0.3, oz + D),
		Vector3(W, 0.6, T), Color(0.33, 0.27, 0.20))
	_box(root, Vector3(ox + W / 2, fy + 0.22, oz + D),
		Vector3(W, 0.44, T), Color(0.33, 0.27, 0.20))
	for i in 3:
		_box(root, Vector3(ox + W * (float(i) + 0.5) / 3.0, fy + H / 2, oz + D),
			Vector3(0.07, H, 0.07), Color(0.12, 0.10, 0.08))

	# entry door on the E wall + a lit stair-landing slit beyond it
	_box(root, Vector3(ox + W - 0.06, fy + 1.05, oz + 1.2),
		Vector3(0.1, 2.1, 0.9), Color(0.12, 0.10, 0.08))
	_box(root, Vector3(ox + W + 0.35, fy + 1.1, oz + 1.2),
		Vector3(0.7, 2.2, 1.1), Color(0.9, 0.75, 0.45), 0.8, 1.2)

	# ---- kitchenette (N wall, west half) ------------------------------
	_box(root, Vector3(ox + 1.9, fy + 0.45, oz + 0.5),
		Vector3(3.4, 0.9, 0.6), Color(0.28, 0.24, 0.20))     # counter
	_box(root, Vector3(ox + 1.9, fy + 0.92, oz + 0.5),
		Vector3(3.5, 0.05, 0.66), Color(0.35, 0.31, 0.26))   # worktop
	_box(root, Vector3(ox + 0.7, fy + 1.7, oz + 0.35),
		Vector3(0.7, 0.8, 0.35), Color(0.24, 0.21, 0.18))    # wall cabinet
	_box(root, Vector3(ox + 3.0, fy + 0.55, oz + 0.55),
		Vector3(0.55, 1.1, 0.55), Color(0.22, 0.23, 0.25))   # fridge
	# under-cabinet light strip
	_box(root, Vector3(ox + 1.9, fy + 1.28, oz + 0.42),
		Vector3(2.4, 0.03, 0.05), Color(1.0, 0.8, 0.5), 0.4, 2.4)

	# ---- bed nook (E end) ----------------------------------------------
	_box(root, Vector3(ox + 8.6, fy + 0.3, oz + 2.2),
		Vector3(3.0, 0.5, 2.0), Color(0.20, 0.15, 0.18))     # bed base
	_box(root, Vector3(ox + 8.6, fy + 0.62, oz + 2.2),
		Vector3(2.8, 0.14, 1.85), Color(0.55, 0.5, 0.55))    # mattress
	_box(root, Vector3(ox + 9.9, fy + 0.75, oz + 2.2),
		Vector3(0.25, 0.8, 1.9), Color(0.42, 0.36, 0.42))    # headboard
	_box(root, Vector3(ox + 7.4, fy + 0.85, oz + 1.5),
		Vector3(0.5, 0.4, 0.35), Color(0.7, 0.65, 0.6))      # pillow
	_box(root, Vector3(ox + 7.3, fy + 0.68, oz + 3.6),
		Vector3(0.5, 0.5, 0.5), Color(0.3, 0.2, 0.14))       # nightstand
	_box(root, Vector3(ox + 7.3, fy + 1.0, oz + 3.6),
		Vector3(0.22, 0.26, 0.22), Color(1.0, 0.65, 0.3), 0.5, 1.8)  # lamp

	# ---- living end (W end) --------------------------------------------
	_box(root, Vector3(ox + 1.6, fy + 0.35, oz + 5.9),
		Vector3(2.4, 0.4, 1.0), Color(0.30, 0.18, 0.22))     # sofa
	_box(root, Vector3(ox + 1.6, fy + 0.75, oz + 6.35),
		Vector3(2.4, 0.8, 0.2), Color(0.30, 0.18, 0.22))     # back
	_box(root, Vector3(ox + 4.2, fy + 0.35, oz + 6.2),
		Vector3(0.9, 0.4, 0.9), Color(0.16, 0.12, 0.15))     # ottoman
	_box(root, Vector3(ox + 3.4, fy + 1.4, oz + 0.35),
		Vector3(1.6, 0.9, 0.12), Color(0.05, 0.05, 0.07))    # wall screen
	_box(root, Vector3(ox + 3.4, fy + 1.4, oz + 0.41),
		Vector3(1.3, 0.66, 0.02), Color(0.35, 0.5, 0.8), 0.4, 1.3)

	# rug
	_box(root, Vector3(ox + 3.2, fy + 0.01, oz + 5.6),
		Vector3(4.0, 0.02, 2.6), Color(0.3, 0.16, 0.20), 1.0)

	# pendant over kitchen
	_box(root, Vector3(ox + 1.9, fy + H - 0.5, oz + 1.2),
		Vector3(0.9, 0.05, 0.12), Color(1.0, 0.85, 0.55), 0.4, 2.0)
	_box(root, Vector3(ox + 1.9, fy + H - 0.27, oz + 1.2),
		Vector3(0.02, 0.45, 0.02), Color(0.1, 0.1, 0.1))

	var pl := OmniLight3D.new()
	pl.position = Vector3(ox + W / 2, fy + H - 0.5, oz + D / 2)
	pl.light_color = Color(1.0, 0.8, 0.5)
	pl.light_energy = 1.4
	pl.omni_range = 11.0
	root.add_child(pl)
