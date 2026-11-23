extends Node3D
## Recessed dorsal mount. The bore points along the barrel's local -Z axis.

const Kit = preload("res://scripts/mech/mesh_kit.gd")
const Armor = preload("res://src/geometry/armor_panel.gd")
const Palette = preload("res://scripts/mech/materials.gd")

var muzzle: Marker3D
var _doors: Array[Node3D] = []
var _diodes: Array[StandardMaterial3D] = []
var _lens: StandardMaterial3D
var _carriage: Node3D
var _aim: Node3D
var _receiver: Node3D
var _slide: Node3D


func build(plate: Material, edge: Material, frame: Material, steel: Material, copper: Material,
		spine_light: Material) -> void:
	var barrel_steel := steel.duplicate() as StandardMaterial3D
	barrel_steel.albedo_color = Color("353e43")
	barrel_steel.roughness = 0.72
	var rail_copper := copper.duplicate() as StandardMaterial3D
	rail_copper.roughness = 0.70
	_lens = Palette.emissive(Color("ffc565"), 0.3).duplicate()
	for i in 4:
		_diodes.append(Palette.emissive(Color("ff9b46"), 0.3).duplicate())
	Kit.add(self, Kit.slab(1.78, 3.09, 0.20, 0.055), frame, Vector3(0, -0.68, -0.04))
	for side: float in [-1.0, 1.0]:
		var door := Kit.pivot(self, Vector3(side * 0.93, -0.15, 0), "HatchL" if side < 0 else "HatchR")
		_doors.append(door)
		Armor.panel(door, PackedVector3Array([
			Vector3(-side * 0.90, 0.23, -1.49), Vector3(-side * 0.90, 0.15, 1.34),
			Vector3(-side * 0.53, 0.06, 1.37), Vector3(side * 0.03, -0.12, 1.00),
			Vector3(side * 0.06, -0.04, -1.16), Vector3(-side * 0.53, 0.08, -1.54),
		]), Vector3.UP, 0.18, frame, edge)
		for i in 3:
			var z: float = [-1.08, -0.25, 0.52][i]
			var crest: float = [0.33, 0.47, 0.40][i]
			Armor.panel(door, PackedVector3Array([
				Vector3(-side * 0.905, crest - 0.13, z - 0.43),
				Vector3(-side * 0.905, crest + 0.11, z + 0.48),
				Vector3(-side * 0.54, crest - 0.018, z + 0.32),
				Vector3(side * 0.16, -0.035, z + 0.20),
				Vector3(-side * 0.12, -0.018, z - 0.16),
				Vector3(-side * 0.47, crest - 0.14, z - 0.34),
			]), Vector3.UP, 0.20, plate, edge)
			if i != 1:
				Kit.add(door, Kit.slab(0.055, 0.24, 0.018, 0.007), spine_light,
					Vector3(-side * 0.75, crest + 0.006, z + 0.07), Vector3(-12.0, side * 26.0, -side * 15.0))
		Kit.add(self, Kit.slab(0.24, 2.65, 0.17, 0.06), edge, Vector3(side * 0.91, -0.27, 0.01))
		Kit.add(self, Kit.slab(0.24, 1.62, 0.49, 0.052), frame, Vector3(side * 0.59, -0.37, 0.36))

	_carriage = Kit.pivot(self, Vector3(0, -0.37, 0.36), "Lift")
	# The box-section pedestal slides inside a fixed saddle and stays seated at full lift.
	Kit.add(_carriage, Kit.slab(0.91, 1.42, 0.89, 0.10), barrel_steel, Vector3(0, -0.57, 0))
	Kit.add(_carriage, Kit.slab(1.04, 1.65, 0.22, 0.066), frame, Vector3(0, -0.14, 0))
	for side: float in [-1.0, 1.0]:
		Armor.panel(_carriage, PackedVector3Array([
			Vector3(side * 0.44, -0.17, -0.76), Vector3(side * 0.51, -0.25, -0.46),
			Vector3(side * 0.51, -0.24, 0.64), Vector3(side * 0.43, -0.45, 0.76),
			Vector3(side * 0.40, -0.75, 0.49), Vector3(side * 0.43, -0.84, -0.44),
			Vector3(side * 0.43, -0.55, -0.68),
		]), Vector3(side, 0, 0), 0.095, plate, edge, frame, 0.44)
		for z: float in [-0.45, 0.48]:
			Kit.add(_carriage, Kit.slab(0.070, 0.105, 0.082, 0.018), steel,
				Vector3(side * 0.52, -0.40, z))
	_aim = Kit.pivot(_carriage, Vector3.ZERO, "Elevation")
	_receiver = Kit.pivot(_aim, Vector3.ZERO, "RecoilSlide")
	Kit.add(_receiver, Kit.beam_x(1.99, 0.49, 0.93, 0.40, 0.74), frame,
		Vector3(0, 0.02, 0.82), Vector3(0, 90, 0))
	for side: float in [-1.0, 1.0]:
		Armor.panel(_receiver, PackedVector3Array([
			Vector3(side * 0.41, 0.14, 0.72), Vector3(side * 0.50, 0.02, 0.42),
			Vector3(side * 0.44, 0.10, -0.76), Vector3(side * 0.36, 0.02, -1.11),
			Vector3(side * 0.41, -0.14, -0.74), Vector3(side * 0.45, -0.16, 0.52)
		]), Vector3(side, 0, 0), 0.11, plate, edge, frame, 0.57)
		for i in _diodes.size():
			Kit.add(_receiver, Kit.slab(0.047, 0.19, 0.07, 0.015), _diodes[i],
				Vector3(side * 0.515, -0.012, 0.37 - 0.30 * i), Vector3(0, 0, side * 19))
		Kit.add(_receiver, Kit.prism(8, 0.09, 0.09, 0.49), copper,
			Vector3(side * 0.32, -0.18, 0.53), Vector3(90, 0, 0))

	_slide = Kit.pivot(_receiver, Vector3.ZERO, "TelescopicBarrel")
	Kit.add(_slide, Kit.beam_x(1.55, 0.28, 0.45, 0.23, 0.35), barrel_steel,
		Vector3(0, 0, 0.79), Vector3(0, 90, 0))
	for side: float in [-1.0, 1.0]:
		Kit.add(_slide, Kit.slab(0.097, 0.93, 0.087, 0.019), rail_copper, Vector3(side * 0.172, 0.05, -0.23))
		Kit.add(_slide, Kit.slab(0.069, 0.70, 0.030, 0.009), _lens, Vector3(side * 0.14, 0.158, -0.22))
	Kit.add(_slide, Kit.beam_x(0.46, 0.44, 0.80, 0.55, 0.71), frame,
		Vector3(0, 0, -0.44), Vector3(0, 90, 0))
	Armor.panel(_slide, PackedVector3Array([
		Vector3(-0.36, 0.16, -0.91), Vector3(-0.25, 0.28, -0.91),
		Vector3(0.25, 0.28, -0.91), Vector3(0.36, 0.16, -0.91),
		Vector3(0.18, -0.26, -0.91), Vector3(-0.18, -0.26, -0.91),
	]), Vector3.FORWARD, 0.11, plate, edge, _lens, 0.56)
	for side: float in [-1.0, 1.0]:
		Armor.panel(_slide, PackedVector3Array([
			Vector3(side * 0.26, 0.23, -0.55), Vector3(side * 0.38, 0.15, -1.04),
			Vector3(side * 0.31, -0.09, -0.92), Vector3(side * 0.28, -0.17, -0.57),
			Vector3(side * 0.39, 0.03, -0.42),
		]), Vector3(side, 0, 0), 0.13, edge, steel)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position.z = -1.00
	_slide.add_child(muzzle)
	pose(0, 0, 0, 0, 0)


func pose(hatches: float, raise: float, extend: float, pitch: float, recoil: float, yaw := 0.0) -> void:
	_doors[0].rotation_degrees.z = 61.0 * hatches
	_doors[1].rotation_degrees.z = -61.0 * hatches
	_carriage.position.y = lerpf(-0.37, 0.75, raise)
	_aim.rotation_degrees = Vector3(pitch, yaw, 0)
	_receiver.position.z = recoil * 0.31
	_slide.position.z = lerpf(-0.23, -1.79, extend)


func light_charge(power: float, shot: float) -> void:
	for i in _diodes.size():
		var fill := clampf(power * _diodes.size() - i, 0.0, 1.0)
		_diodes[i].emission_energy_multiplier = 0.25 + fill * 4.2 + shot * 5.0
	_lens.emission = Color("ffad42").lerp(Color("fff4d5"), maxf(power * power, shot))
	_lens.emission_energy_multiplier = 0.25 + power * power * 6.8 + shot * 11.0


func replay_nodes() -> Array:
	return [_doors[0], _doors[1], _carriage, _aim, _receiver, _slide]
