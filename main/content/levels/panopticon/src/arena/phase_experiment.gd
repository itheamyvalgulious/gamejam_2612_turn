extends Node3D
## A shielded test fixture. The beam, armor response and both scopes share the shutter's occlusion result.

const Kit = preload("res://src/arena/kit.gd")
const PhantomModel = preload("res://team/shard/scripts/character.gd")
const SHUTTER_X := 1.55
const SHUTTER_HALF_HEIGHT := 1.96
const SHUTTER_DEPTH := 4.55
const SHUTTER_WIDTH := 0.42
const SHUTTER_TRAVEL := 4.25
const SHUTTER_SECONDS := 0.88
const SAMPLE_STEP := 0.05
const SAMPLE_COUNT := 83

var palette: Dictionary
var scope_mesh := ImmediateMesh.new()
var _requested_open := false
var _open_fraction := 0.0
var _spread := 0.0
var _lever: Node3D
var _open_lamp: MeshInstance3D
var _closed_lamp: MeshInstance3D
var _plates: Array[MeshInstance3D] = []
var _plate_rest: Array[Transform3D] = []
var _plate_push: Array[Vector3] = []
var _plate_turn: PackedFloat32Array = []
var _clock := 0.0
var _sample_elapsed := 0.0
var _write_index := 0
var _observation := PackedFloat32Array()
var _response := PackedFloat32Array()
var _optic := Vector3.ZERO
var _source := Vector3.ZERO
var _shutter: Node3D
var _beam: MeshInstance3D
var _stop_hit: MeshInstance3D
var _eye_light: OmniLight3D
var _red_eye: ShaderMaterial
var _cyan: StandardMaterial3D
var _scope_red: StandardMaterial3D
var _contact := false


func _ready() -> void:
	_cyan = _trace_material(Color("9af8ff"))
	_scope_red = _trace_material(Color("ffc27e"))
	_build_specimen()
	_build_observer()
	_build_shutter()
	_build_monitor()
	_observation.resize(SAMPLE_COUNT)
	_response.resize(SAMPLE_COUNT)
	reset_experiment()


func _process(dt: float) -> void:
	_clock += dt
	var target := 1.0 if _requested_open else 0.0
	_open_fraction = move_toward(_open_fraction, target, dt / SHUTTER_SECONDS)
	_update_optics()
	var before := _spread
	var response_target := 1.0 if _contact else 0.0
	_spread = move_toward(_spread, response_target, dt / (0.50 if _contact else 0.64))
	if before != _spread:
		_update_armor()
	_update_controls()
	_sample_elapsed += dt
	if _sample_elapsed < SAMPLE_STEP:
		return
	_sample_elapsed = fmod(_sample_elapsed, SAMPLE_STEP)
	var power := 1.0 if _contact else 0.0
	_observation[_write_index] = power
	_response[_write_index] = 0.11 + _spread * (0.42 + 0.29 * sin(_clock * 31.0) + 0.09 * sin(_clock * 67.0))
	_write_index = (_write_index + 1) % SAMPLE_COUNT
	_update_scope()


func connect_console(lever: Node3D, open_lamp: MeshInstance3D, closed_lamp: MeshInstance3D) -> void:
	_lever = lever
	_open_lamp = open_lamp
	_closed_lamp = closed_lamp


func toggle_shutter() -> void:
	_requested_open = not _requested_open


func reset_experiment() -> void:
	_requested_open = false
	_open_fraction = 0.0
	_spread = 0.0
	_clock = 0.0
	_write_index = 0
	_sample_elapsed = 0.0
	_observation.fill(0.0)
	_response.fill(0.11)
	_update_optics()
	_update_armor()
	_update_controls()
	_update_scope()


func _update_controls() -> void:
	if _lever == null:
		return
	_lever.rotation.x = lerpf(deg_to_rad(-29.0), deg_to_rad(34.0), smoothstep(0.0, 1.0, _open_fraction))
	_open_lamp.material_override = palette["cyan"] if _contact else palette["teal"]
	_closed_lamp.material_override = palette["amber_paint"] if _contact else palette["amber"]


func _update_armor() -> void:
	var clearance := smoothstep(0.0, 1.0, _spread)
	for i in _plates.size():
		var rest := _plate_rest[i]
		var axis := rest.basis.x.normalized()
		var leaned := Basis(axis, _plate_turn[i] * clearance) * rest.basis
		_plates[i].global_transform = Transform3D(leaned, rest.origin + _plate_push[i] * clearance)
		_plates[i].set_instance_shader_parameter("fx_phase", clearance * 0.19)


func _build_specimen() -> void:
	var mount := Vector3(-7.1, 0, 0.0)
	_box("dark", Vector3(6.05, 0.48, 5.20), mount + Vector3.UP * 0.24)
	_box("frame", Vector3(5.34, 0.49, 4.61), mount + Vector3.UP * 0.71)
	_box("metal", Vector3(4.90, 0.16, 4.31), mount + Vector3.UP * 1.04)
	for side in [-1.0, 1.0]:
		var carrier: Vector3 = mount + Vector3(-2.0, 0, side * 1.72)
		_box("frame", Vector3(0.53, 5.33, 0.67), carrier + Vector3.UP * 3.48)
		_box("metal", Vector3(0.17, 3.89, 0.32), carrier + Vector3(-0.28, 3.57, 0))
		_box("frame", Vector3(1.75, 0.63, 0.73), carrier + Vector3(0.58, 4.65, 0))
		_box("amber_paint", Vector3(0.32, 0.51, 0.70), carrier + Vector3(1.49, 4.65, 0))
		_box("rubber", Vector3(0.22, 0.49, 0.69), carrier + Vector3(1.70, 4.65, 0))
		_box("cyan", Vector3(0.49, 0.065, 0.056), mount + Vector3(1.64, 0.85, side * 2.36))
		Kit.tube(self, carrier + Vector3(0, 1.05, 0.0), carrier + Vector3(-0.13, 3.74, 0), 0.12, palette["metal"])
	var model := PhantomModel.new()
	model.name = "PhantomTestArticle"
	model.encounter_projectile = true
	model.scale = Vector3.ONE * 4.44
	model.rotation.y = PI * 0.50
	model.position = mount + Vector3.UP * 1.14
	add_child(model)
	model.set_process(false)
	model.rig.set_frame_visibility(1.0)
	model.shadow.hide()
	model.ring_node.hide()
	model.glow_node.hide()
	model.field.set_thruster_intensity(0.0)
	model.rig.set_thruster_intensity(0.0)
	# Cache the actual assembled transforms. Only the removable modules move on this fixture.
	for module: Dictionary in model.field.mods:
		var slot: Dictionary = module["slot"]
		var plate: MeshInstance3D = module["node"]
		var rest := plate.global_transform
		# ModuleField places its detached meshes in world space. Match the fixture's enlarged body.
		rest.basis = rest.basis.scaled(Vector3.ONE * model.scale.x)
		plate.global_transform = rest
		if slot["joint"] == "Head":
			continue
		var variation := 0.5 + 0.5 * sin(float(module["seed"]) * 7.3)
		_plates.append(plate)
		_plate_rest.append(rest)
		_plate_push.append(rest.basis.z.normalized() * (0.32 + 0.34 * variation))
		_plate_turn.append(lerpf(-0.19, 0.19, variation))
	var head: Node3D = model.rig.joints["Head"]
	model.rig.set_joint("head_yaw", -19.0)
	_red_eye = model.rig.optic_glass.material_override
	# The stock iris sits recessed in its barrel, with an illuminated front lip on this fixture.
	var rim: MeshInstance3D = model.rig.optic_glass.duplicate()
	rim.name = "DiagnosticIris"
	rim.position.z += 0.035
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(rim)
	_optic = to_local(rim.global_position)
	_eye_light = _lamp(_optic + Vector3(0.42, 0.03, 0.26), Color("ff734e"), 0.30, 3.3)
	_lamp(mount + Vector3(2.05, 7.46, 3.55), Color("f6e5db"), 7.70, 12.6)
	_lamp(mount + Vector3(-1.3, 5.40, -3.3), Color("afcfdf"), 3.70, 10.9)


func _build_observer() -> void:
	_source = Vector3(9.38, _optic.y, _optic.z)
	var pedestal := Vector3(11.16, 0, _optic.z)
	_box("dark", Vector3(4.46, 0.48, 4.18), pedestal + Vector3.UP * 0.24)
	_box("frame", Vector3(3.93, 0.42, 3.75), pedestal + Vector3.UP * 0.64)
	for side in [-1.0, 1.0]:
		var leg: Vector3 = pedestal + Vector3(0, _optic.y * 0.5, side * 1.08)
		_box("frame", Vector3(0.87, _optic.y, 0.90), leg)
		_box("metal", Vector3(0.17, _optic.y - 1.18, 0.43), leg + Vector3(0.47, 0.42, 0))
		Kit.tube(self, leg + Vector3(0.48, -2.53, side * 0.59),
			pedestal + Vector3(0.48, _optic.y - 0.7, side * 0.48), 0.15, palette["metal"])
	_box("frame", Vector3(2.30, 1.72, 2.87), _source + Vector3(1.79, 0.00, 0.0))
	_box("metal", Vector3(1.97, 1.29, 2.94), _source + Vector3(1.84, 0.17, 0))
	_box("cyan", Vector3(0.64, 0.118, 0.056), _source + Vector3(2.14, 0.29, 1.50))
	_cylinder("dark", 0.73, 0.97, _source + Vector3(0.42, 0, 0), Vector3(0, 0, PI / 2.0))
	_cylinder("metal", 0.63, 0.19, _source + Vector3(0.03, 0, 0), Vector3(0, 0, PI / 2.0))
	_cylinder("dark", 0.52, 0.18, _source + Vector3(-0.08, 0, 0), Vector3(0, 0, PI / 2.0))
	_cylinder("cyan", 0.38, 0.13, _source + Vector3(-0.15, 0, 0), Vector3(0, 0, PI / 2.0))
	_source.x -= 0.23
	_beam = _cylinder("cyan", 0.075, 1.0, _source)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stop_hit = _cylinder("cyan", 0.20, 0.025, _source, Vector3(0, 0, PI / 2.0))
	_stop_hit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_shutter() -> void:
	var base := Vector3(SHUTTER_X, 0, _optic.z)
	var top := _optic.y + SHUTTER_TRAVEL + SHUTTER_HALF_HEIGHT + 0.46
	for side in [-1.0, 1.0]:
		var pillar: Vector3 = base + Vector3(0, 0, side * (SHUTTER_DEPTH * 0.5 + 0.15))
		_box("dark", Vector3(1.49, 0.39, 1.20), pillar + Vector3.UP * 0.20)
		_box("frame", Vector3(0.63, top, 0.49), pillar + Vector3.UP * (top * 0.5))
		_box("metal", Vector3(0.23, top - 1.03, 0.15), pillar + Vector3(0.27, top * 0.52, 0))
		for fraction in [0.16, 0.56, 0.91]:
			_box("dark", Vector3(0.84, 0.44, 0.67), pillar + Vector3.UP * (top * float(fraction)))
	_box("frame", Vector3(1.64, 0.66, SHUTTER_DEPTH + 1.15), base + Vector3.UP * top)
	_box("metal", Vector3(0.74, 0.23, SHUTTER_DEPTH + 0.78), base + Vector3.UP * (top - 0.40))
	_shutter = Node3D.new()
	_shutter.name = "OpticalShutter"
	_shutter.position = base
	add_child(_shutter)
	_box("dark", Vector3(SHUTTER_WIDTH, SHUTTER_HALF_HEIGHT * 2.0, SHUTTER_DEPTH), Vector3.ZERO, _shutter)
	for side in [-1.0, 1.0]:
		_box("metal", Vector3(0.10, 3.39, 3.50), Vector3(side * 0.224, 0, 0), _shutter)
		_box("frame", Vector3(0.10, 3.03, 3.16), Vector3(side * 0.278, 0, 0), _shutter)
		for y in [-1.34, 1.34]:
			_box("metal", Vector3(0.083, 0.076, 2.98), Vector3(side * 0.328, y, 0), _shutter)
		for y in [-0.69, 0.69]:
			_box("dark", Vector3(0.055, 0.095, 2.90), Vector3(side * 0.328, y, 0), _shutter)
		for z in [-1.27, 1.27]:
			_box("amber_paint", Vector3(0.056, 0.24, 0.37), Vector3(side * 0.332, -1.22, z), _shutter)
		for i in 4:
			var strip := _box("amber_paint", Vector3(0.057, 0.13, 0.62),
				Vector3(side * 0.334, 0.0, -1.16 + i * 0.77), _shutter)
			strip.rotation.x = deg_to_rad(38.0)
	_box("amber", Vector3(0.13, 0.076, 3.54), Vector3(0, -1.74, 0.00), _shutter)
	_box("amber_paint", Vector3(0.50, 0.10, 0.09), Vector3(0.0, 1.80, 1.96), _shutter)


func _build_monitor() -> void:
	var first_part := get_child_count()
	var at := Vector3(3.96, 2.16, 14.10)
	for side in [-1.0, 1.0]:
		var foot: Vector3 = Vector3(at.x + side * 3.83, 0, at.z - 0.42)
		_box("dark", Vector3(1.46, 0.25, 1.45), foot + Vector3.UP * 0.13)
		_box("frame", Vector3(0.73, 1.51, 0.74), foot + Vector3.UP * 0.86)
	_box("frame", Vector3(10.05, 3.61, 0.66), at)
	_box("metal", Vector3(9.65, 3.22, 0.16), at + Vector3(0, 0, 0.40))
	_box("dark", Vector3(9.31, 3.02, 0.079), at + Vector3(0, 0, 0.51))
	var chart_at := at + Vector3(0.49, 0.02, 0.568)
	for i in 13:
		_box("teal", Vector3(0.020, 2.52, 0.014),
			chart_at + Vector3(-3.83 + i * 0.638, 0, 0.008))
	for i in 7:
		_box("teal", Vector3(7.66, 0.018, 0.014),
			chart_at + Vector3(0, -1.26 + 0.42 * i, 0.008))
	_box("metal", Vector3(0.32, 0.22, 0.073), at + Vector3(-4.07, 0.70, 0.571))
	_box("cyan", Vector3(0.32, 0.074, 0.037), at + Vector3(-3.78, 0.70, 0.618))
	_cylinder("dark", 0.20, 0.08, at + Vector3(-3.98, -0.66, 0.58), Vector3(PI / 2.0, 0, 0))
	_cylinder("red", 0.119, 0.085, at + Vector3(-3.98, -0.66, 0.63), Vector3(PI / 2.0, 0, 0))
	var chart := MeshInstance3D.new()
	chart.position = chart_at + Vector3(0, 0, 0.025)
	chart.mesh = scope_mesh
	chart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chart)
	# Keep the monitor below the optical axis and let the specimen stay visible from the walkway.
	var base := Vector3(at.x, 0, at.z)
	var fitted := Basis.from_scale(Vector3(0.80, 0.62, 0.82))
	var move := Transform3D(fitted, Vector3(5.08, 0, 10.25) - fitted * base)
	for i in range(first_part, get_child_count()):
		var part: Node3D = get_child(i)
		part.transform = move * part.transform


func _update_optics() -> void:
	_shutter.position.y = _optic.y + SHUTTER_TRAVEL * smoothstep(0.0, 1.0, _open_fraction)
	var blocked := absf(_optic.y - _shutter.position.y) <= SHUTTER_HALF_HEIGHT
	_contact = not blocked
	var target := _optic if _contact else Vector3(SHUTTER_X + 0.372, _optic.y, _optic.z)
	var delta := target - _source
	var core := Basis(Quaternion(Vector3.UP, delta.normalized()))
	_beam.transform = Transform3D(core, (_source + target) * 0.5)
	_beam.scale.y = delta.length()
	_stop_hit.position = target
	_stop_hit.visible = blocked
	_eye_light.light_energy = 1.48 if _contact else 0.32
	_red_eye.set_shader_parameter("alert", 1.0 if _contact else 0.36)


func _update_scope() -> void:
	scope_mesh.clear_surfaces()
	_channel(_observation, 0.12, 0.91, _cyan)
	_channel(_response, -1.19, 0.92, _scope_red)


func _channel(values: PackedFloat32Array, baseline: float, gain: float, ink: Material) -> void:
	scope_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, ink)
	var dx := 7.66 / float(SAMPLE_COUNT - 1)
	for i in SAMPLE_COUNT - 1:
		var left := Vector3(-3.83 + dx * i, baseline + gain * values[(_write_index + i) % SAMPLE_COUNT], 0)
		var right := Vector3(left.x + dx, baseline + gain * values[(_write_index + i + 1) % SAMPLE_COUNT], 0)
		var edge := Vector3(-(right.y - left.y), dx, 0).normalized() * 0.036
		for point in [left - edge, left + edge, right + edge, left - edge, right + edge, right - edge]:
			scope_mesh.surface_add_vertex(point)
	scope_mesh.surface_end()


func _box(key: String, size: Vector3, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	return Kit.box(self if parent == null else parent, size, at, palette[key])


func _cylinder(key: String, radius: float, height: float, at: Vector3,
		rotation := Vector3.ZERO) -> MeshInstance3D:
	return Kit.cylinder(self, radius, height, at, palette[key], rotation)


func _lamp(at: Vector3, tint: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = reach
	add_child(light)
	return light


func _trace_material(color: Color) -> StandardMaterial3D:
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	ink.albedo_color = color
	return ink
