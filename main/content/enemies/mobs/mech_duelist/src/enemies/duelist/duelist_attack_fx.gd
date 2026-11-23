extends Node3D
## The dash and slash effects follow the demo clock, including freeze and slow motion.

const Lunge = preload("res://src/enemies/duelist/duelist_lunge.gd")
const ReturnCut = preload("res://src/enemies/duelist/duelist_return_cut.gd")
const Pace = preload("res://src/enemies/duelist/duelist_pace.gd")
const Materials = preload("res://src/vesper/materials.gd")
const Spark = preload("res://gfx/fx_spark.gdshader")
const Mist = preload("res://gfx/fx_smoke.gdshader")
const SPARK_COUNT := 22
const MIST_COUNT := 13
const GUST_COUNT := 10
const WAKE_LIFE := 0.30
const LANDING_COUNT := 8
const LANDING_LIFE := 0.16
const TIP_SPARK_COUNT := 7
const TIP_SPARK_START := 0.242
const TIP_SPARK_INTERVAL := 0.014
const FACET_COUNT := 3
const FACET_START := 0.277
const FACET_INTERVAL := 0.017
const BLADE_DEBRIS_COUNT := TIP_SPARK_COUNT + FACET_COUNT

var _wake: Node3D
var _landing: Node3D
var _landing_debris: MultiMesh
var _ring: MeshInstance3D
var _ring_material: ShaderMaterial
var _sparks: MultiMesh
var _mist: MultiMesh
var _tip_sparks: MultiMesh
var _blade_facets: MultiMesh
var _tip_time := -1.0
var _tip_position := Vector3.ZERO
var _spark_origins := PackedVector3Array()
var _spark_velocities := PackedVector3Array()
var _kick_light: OmniLight3D
var _blade_light: OmniLight3D


func _ready() -> void:
	_wake = Node3D.new()
	add_child(_wake)
	var ground := PlaneMesh.new()
	ground.size = Vector2(2, 2)
	_ring = MeshInstance3D.new()
	_ring.mesh = ground
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_material = Materials.ring_fx().duplicate() as ShaderMaterial
	_ring_material.set_shader_parameter("color", Color("8ee7e7"))
	_ring_material.set_shader_parameter("inner_softness", 0.66)
	_ring.material_override = _ring_material
	_ring.position.y = 0.034
	_wake.add_child(_ring)
	_sparks = _particles(_wake, Spark, SPARK_COUNT + GUST_COUNT)
	_mist = _particles(_wake, Mist, MIST_COUNT)
	_landing = Node3D.new()
	add_child(_landing)
	_landing_debris = _particles(_landing, Spark, LANDING_COUNT)
	_landing.hide()
	var tip_wake := Node3D.new()
	tip_wake.name = "BladeTipSparks"
	tip_wake.top_level = true
	add_child(tip_wake)
	tip_wake.global_transform = Transform3D.IDENTITY
	_tip_sparks = _particles(tip_wake, Spark, TIP_SPARK_COUNT)
	_blade_facets = _particles(tip_wake, Spark, FACET_COUNT, true)
	_spark_origins.resize(BLADE_DEBRIS_COUNT)
	_spark_velocities.resize(BLADE_DEBRIS_COUNT)
	clear_tip_sparks()
	_kick_light = _light(_wake, Color("ffc27d"), 3.0)
	_kick_light.position.y = 0.22
	_blade_light = _light(self, Color("ff4731"), 5.8)
	_wake.hide()
	_blade_light.hide()


func apply(time: float, state: Dictionary, sword: Node3D, front_foot: Node3D) -> void:
	var age := time - Lunge.BURST_START
	_wake.visible = not state.is_empty() and age >= 0.0 and age < WAKE_LIFE
	if _wake.visible:
		var start: Vector3 = state["origin"]
		var power := lerpf(0.35, 1.0, smoothstep(0.0, 3.9, start.distance_to(state["end"])))
		var step_press: Vector3 = state["push_contact"]
		_wake.global_transform = Transform3D(Basis(Vector3.UP, state["aim"]), step_press)
		_pose_wake(age, power)

	var landing_age := time - Lunge.FRONT_LAND
	_landing.visible = not state.is_empty() and landing_age >= 0.0 and landing_age < LANDING_LIFE
	if _landing.visible:
		var distance: float = (state["origin"] as Vector3).distance_to(state["end"])
		_landing.global_position = front_foot.to_global(Pace.HEEL) + Vector3.UP * 0.035
		_pose_landing(landing_age, lerpf(0.25, 1.0, smoothstep(0.0, 4.8, distance)))

	var flash := smoothstep(Lunge.TRAIL_START, 0.295, time) * (1.0 - smoothstep(0.320, 0.385, time))
	var reverse_time := time - Lunge.DURATION
	var reverse_flash := smoothstep(ReturnCut.TRAIL_START, 0.272, reverse_time)
	flash += reverse_flash * (1.0 - smoothstep(0.302, 0.386, reverse_time)) * 0.66
	_blade_light.visible = flash > 0.0
	if _blade_light.visible:
		_blade_light.global_position = sword.to_global(Vector3(0, 1.28, 0))
		_blade_light.light_energy = 3.8 * flash


func _pose_landing(age: float, power: float) -> void:
	for i in LANDING_COUNT:
		var seed := fposmod(float(i) * 0.618, 1.0)
		var direction := Vector3.RIGHT.rotated(Vector3.UP, float(i) * 2.4)
		var launch := direction * lerpf(2.2, 5.4, seed) * power + Vector3.UP * lerpf(1.0, 2.5, seed)
		var position := launch * age
		position.y = maxf(0.0, position.y - 11.0 * age * age)
		var size := lerpf(0.043, 0.073, seed)
		var alpha := smoothstep(0.0, 0.012, age) * (1.0 - smoothstep(0.018, LANDING_LIFE, age))
		var motion := (launch - Vector3.UP * 22.0 * age).normalized() * 0.5 + Vector3.ONE * 0.5
		_landing_debris.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), position))
		_landing_debris.set_instance_color(i, Color(0.86, 0.64, 0.42, alpha * power))
		_landing_debris.set_instance_custom_data(i, Color(motion.x, motion.y, motion.z, 0.33))


func clear_tip_sparks() -> void:
	_tip_sparks.visible_instance_count = 0
	_blade_facets.visible_instance_count = 0
	_spark_velocities.fill(Vector3.ZERO)
	_tip_time = -1.0


func sample_tip_sparks(time: float, tip: Vector3) -> void:
	if _tip_time < 0.0:
		_tip_time = time
		_tip_position = tip
		return
	if time <= _tip_time:
		return
	var motion := (tip - _tip_position).normalized()
	var drawn_sparks := 0
	var drawn_facets := 0
	for i in BLADE_DEBRIS_COUNT:
		var facet := i >= TIP_SPARK_COUNT
		var release := FACET_START + float(i - TIP_SPARK_COUNT) * FACET_INTERVAL if facet \
			else TIP_SPARK_START + float(i) * TIP_SPARK_INTERVAL
		var seed := fposmod(float(i) * 0.618, 1.0)
		var life := lerpf(0.054, 0.105, seed)
		var age := time - release
		if age < 0.0 or age >= life:
			continue
		if _tip_time <= release:
			_spark_origins[i] = _tip_position.lerp(tip, inverse_lerp(_tip_time, time, release))
			var spread := motion.cross(Vector3.UP) * (seed - 0.5) * 2.7
			var speed := lerpf(-1.2, 2.8, seed) if facet else lerpf(1.2, 5.0, seed)
			_spark_velocities[i] = motion * speed + spread + Vector3.UP * lerpf(1.0, 3.1, seed)
		if _spark_velocities[i] == Vector3.ZERO:
			continue
		var start_velocity := _spark_velocities[i]
		var position := _spark_origins[i] + start_velocity * age - Vector3.UP * (12.0 * age * age)
		var direction := (start_velocity - Vector3.UP * (24.0 * age)).normalized() * 0.5 + Vector3.ONE * 0.5
		var alpha := smoothstep(0.0, 0.012, age) * (1.0 - smoothstep(0.017, life, age))
		var size := lerpf(0.075, 0.111, seed) if facet else lerpf(0.043, 0.068, seed)
		var batch := _blade_facets if facet else _tip_sparks
		var index := drawn_facets if facet else drawn_sparks
		var color := Color(0.49, 0.87, 1.0, 0.67 * alpha) if facet \
			else Color(1.0, lerpf(0.40, 0.66, seed), 0.17, 0.91 * alpha)
		var stretch := lerpf(0.18, 0.36, seed) if facet else lerpf(0.53, 0.84, seed)
		batch.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), position))
		batch.set_instance_color(index, color)
		batch.set_instance_custom_data(index, Color(direction.x, direction.y, direction.z, stretch))
		if facet:
			drawn_facets += 1
		else:
			drawn_sparks += 1
	_tip_sparks.visible_instance_count = drawn_sparks
	_blade_facets.visible_instance_count = drawn_facets
	_tip_time = time
	_tip_position = tip


func _pose_wake(age: float, power: float) -> void:
	var progress := clampf(age / 0.20, 0.0, 1.0)
	var radius := lerpf(0.18, 1.60, ease(progress, 0.50))
	_ring.visible = progress < 1.0
	_ring.scale = Vector3(radius, 1.0, radius * 1.38)
	_ring.position.z = radius * 0.27
	_ring_material.set_shader_parameter("energy", 1.4 * power * pow(1.0 - progress, 1.75))
	_kick_light.light_energy = 4.0 * power * (1.0 - smoothstep(0.018, 0.125, age))

	for i in SPARK_COUNT:
		var seed := fposmod(float(i) * 0.618, 1.0)
		var life := lerpf(0.13, 0.25, seed)
		var t := clampf(age - 0.041 * seed, 0.0, life)
		var scatter := sin(float(i) * 5.63)
		var velocity := Vector3(scatter * 5.9, lerpf(1.3, 3.1, absf(scatter)), lerpf(5.5, 12.5, seed))
		var p := velocity * t * (1.0 - 1.7 * t) * power
		p.y = maxf(0.032, p.y - 6.5 * t * t)
		var fade := (1.0 - t / life) * smoothstep(0.0, 0.014, t)
		var size := lerpf(0.044, 0.105, seed)
		_sparks.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), p))
		_sparks.set_instance_color(i, Color(1.0, lerpf(0.53, 0.88, seed), 0.37, fade * power))
		var motion := _wake.global_basis * (velocity - Vector3.UP * 13.0 * t)
		var direction := motion.normalized() * 0.5 + Vector3.ONE * 0.5
		_sparks.set_instance_custom_data(i, Color(direction.x, direction.y, direction.z, 0.84))

	var back := _wake.global_basis.z * 0.5 + Vector3.ONE * 0.5
	for i in GUST_COUNT:
		var seed := fposmod(float(i) * 0.618, 1.0)
		var u := clampf((age - lerpf(0.018, 0.059, seed)) / 0.15, 0.0, 1.0)
		var p := Vector3(sin(float(i) * 5.63) * (0.21 + 0.72 * u),
			0.14 + seed * 0.54, u * lerpf(1.65, 3.25, seed)) * power
		var size := 0.11 + 0.075 * seed
		var alpha := smoothstep(0.0, 0.16, u) * pow(1.0 - u, 1.55) * power
		_sparks.set_instance_transform(SPARK_COUNT + i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), p))
		_sparks.set_instance_color(SPARK_COUNT + i, Color(0.53, 0.86, 1.0, 0.68 * alpha))
		_sparks.set_instance_custom_data(SPARK_COUNT + i, Color(back.x, back.y, back.z, 1.0))

	for i in MIST_COUNT:
		var seed := fposmod(float(i) * 0.618, 1.0)
		var progress_mist := clampf((age - seed * 0.062) / 0.24, 0.0, 1.0)
		var scatter := sin(float(i) * 7.95)
		var travel := ease(progress_mist, 0.62) * power
		var p := Vector3(scatter * (0.15 + travel * 1.25), 0.10 + travel * 0.31, travel * (0.96 + seed * 1.66))
		var size := lerpf(0.35, 1.07, progress_mist) * lerpf(0.87, 1.2, seed)
		var fade := smoothstep(0.0, 0.14, progress_mist) * (1.0 - smoothstep(0.16, 1.0, progress_mist))
		_mist.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), p))
		_mist.set_instance_color(i, Color(0.52, 0.70, 0.76, 0.52 * fade * power))


func _particles(parent: Node3D, shader: Shader, count: int, faceted := false) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.use_custom_data = true
	instances.mesh = quad
	instances.instance_count = count
	var material := ShaderMaterial.new()
	material.shader = shader
	if faceted:
		material.set_shader_parameter("faceted", true)
	var emitter := MultiMeshInstance3D.new()
	emitter.multimesh = instances
	emitter.material_override = material
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(emitter)
	return instances


func _light(parent: Node3D, color: Color, radius: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = radius
	light.shadow_enabled = false
	parent.add_child(light)
	return light
