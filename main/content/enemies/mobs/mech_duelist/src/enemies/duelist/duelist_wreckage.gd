extends RefCounted
## Fatal damage uses the actual armor meshes. Only the frame stays on the rig.

const MeshKit = preload("res://src/vesper/mesh_kit.gd")
const Casing = preload("res://src/enemies/duelist/duelist_casing.gd")
const Parts = preload("res://src/enemies/duelist/duelist_parts.gd")
const DefeatBody = preload("res://src/enemies/duelist/duelist_defeat_body.gd")

var breach: Node3D
var age := 0.0
var _plates: Array[DefeatBody] = []


func begin(model, contact: Vector3, impulse: Vector3, part: String, side: float, rate: float) -> bool:
	var right: bool = side > 0.0 if not is_zero_approx(side) else model.to_local(contact).x > 0.0
	var covers := _hit_covers(model, part, right)
	if covers.is_empty():
		return false
	var cover := covers[0] as Node3D
	var facing := Vector3(0.35 if right else -0.35, 0.0, -0.94)
	match part:
		"head", "upper_arm", "forearm":
			facing = Vector3.RIGHT if right else Vector3.LEFT
		"foot":
			facing = Vector3(0.05, 0.86, -0.51)
	var outward := (cover.global_basis * facing).normalized()
	var travel := (impulse.normalized() + outward * 0.73).normalized()
	_expose_frame(cover, contact, facing)
	for i in covers.size():
		var scatter := outward.cross(Vector3.UP) * (float(i) - 0.75) * 1.55
		var velocity := travel * (6.3 - 0.70 * i) + Vector3.UP * (3.55 + 0.68 * i) + scatter
		var spin_axis := Vector3(0.83 - 0.48 * i, 0.37 - 0.43 * i, -0.41 + 0.53 * i)
		_detach(model, covers[i], velocity, spin_axis.normalized() * (9.6 + 1.45 * i), rate)
	model.armor_breached = true
	model.set_knockdown_power(0.065)
	return true


func _hit_covers(model, part: String, right: bool) -> Array[Node3D]:
	var side := 1 if right else 0
	var leg: Dictionary = model.legs[side]
	var arm: Dictionary = model.arms[side]
	var key := &"right_cover" if right else &"left_cover"
	match part:
		"thigh":
			return [leg["thigh_cover"], leg["thigh_armor"], leg["thigh_flank"]]
		"shin":
			return [leg["greave"], leg["shin_armor"], leg["patella_armor"]]
		"foot":
			return [leg["toe_cover"], leg["heel_cover"]]
		"upper_arm":
			return [arm["breakaway_cap"]]
		"forearm":
			return [arm["breakaway_forearm"]]
		"pelvis":
			return [model.body.get_meta(key)]
		"chest":
			return [model.torso.get_meta(key)]
		"head":
			return [model.head.get_meta(key)]
	return []


func _expose_frame(cover: Node3D, contact: Vector3, facing: Vector3) -> void:
	var anchor := cover.get_parent() as Node3D
	var bounds := _plate_bounds(cover)
	var touch := cover.to_local(contact)
	var spot := bounds.get_center().lerp(touch.clamp(bounds.position, bounds.end), 0.57)
	var armor_opening := cover.to_global(spot - facing * 0.08)
	breach = MeshKit.pivot(anchor, anchor.to_local(armor_opening), "ArmorBreach")
	var orientation := anchor.global_transform.basis.inverse() * cover.global_basis
	breach.basis = orientation * Basis.looking_at(facing, Vector3.UP)
	var width := clampf(maxf(bounds.size.x, bounds.size.z) * 2.6, 0.42, 1.0)
	var length := clampf(bounds.size.y * 2.1, 0.45, 1.5)
	breach.scale = Vector3(width, length, width)
	var charred := StandardMaterial3D.new()
	charred.albedo_color = Color("141519")
	charred.roughness = 0.88
	var warped := StandardMaterial3D.new()
	warped.albedo_color = Color("514340")
	warped.metallic = 0.7
	warped.roughness = 0.53
	var copper := StandardMaterial3D.new()
	copper.albedo_color = Color("a56a42")
	copper.metallic = 0.65
	copper.roughness = 0.47
	var rim := PackedVector3Array([
		Vector3(-0.21, 0.12, 0.021), Vector3(-0.15, 0.20, 0.029),
		Vector3(-0.03, 0.15, -0.041), Vector3(0.08, 0.19, -0.015),
		Vector3(0.18, 0.09, -0.035), Vector3(0.14, 0.012, -0.007),
		Vector3(0.22, -0.061, -0.012), Vector3(0.08, -0.17, 0.007),
		Vector3(0.015, -0.12, -0.037), Vector3(-0.11, -0.21, -0.008),
		Vector3(-0.17, -0.072, -0.037),
	])
	Casing.panel(breach, rim, Vector3.FORWARD, 0.048, charred, warped)
	for i in 3:
		var x := float(i - 1) * 0.071
		Parts.tube(breach, PackedVector3Array([
			Vector3(x - 0.048, -0.112, -0.033),
			Vector3(x - 0.021, -0.066, -0.097 - 0.017 * i),
			Vector3(x + 0.056, 0.036 + 0.019 * i, -0.105),
		]), 0.011, copper)


func _plate_bounds(plate: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	var inverse := plate.global_transform.affine_inverse()
	for mesh: MeshInstance3D in plate.find_children("*", "MeshInstance3D", true, false):
		var local := inverse * mesh.global_transform * mesh.get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
	return bounds


func _detach(model: Node3D, plate: Node3D, velocity: Vector3, spin: Vector3, rate: float) -> void:
	var bounds := _plate_bounds(plate)
	var pose := Transform3D(plate.global_basis.orthonormalized(), plate.to_global(bounds.get_center()))
	var from_world := pose.affine_inverse()
	var points := PackedVector3Array()
	for mesh: MeshInstance3D in plate.find_children("*", "MeshInstance3D", true, false):
		var to_fragment := from_world * mesh.global_transform
		points.append_array(to_fragment * mesh.mesh.get_faces())
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	var fragment := DefeatBody.new()
	fragment.name = String(plate.name) + "Fragment"
	model.add_child(fragment)
	fragment.launch(pose, hull, velocity, spin, rate)
	plate.reparent(fragment, true)
	_plates.append(fragment)


func step(delta: float, rate: float) -> void:
	age += delta
	for plate in _plates:
		plate.simulation_rate = rate
