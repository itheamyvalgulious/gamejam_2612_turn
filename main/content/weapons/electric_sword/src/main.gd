extends Node3D

@onready var sword = $ArcSword
@onready var camera: Camera3D = $Camera3D
@onready var hint: Label = $Overlay/Hint
@onready var charge_fill: ColorRect = $Overlay/ChargeBar/Fill
@onready var charge_bar: Control = $Overlay/ChargeBar

const SKY_SHADER: Shader = preload("res://shaders/sky.gdshader")
const BLADE_TIP_Y := 2.20

var _target := Vector3(0.0, 0.72, 0.0)
var _distance := 5.35
var _base_yaw := 0.50
var _base_pitch := 0.13
var _user_yaw := 0.0
var _user_pitch := 0.0
var _auto_weight := 1.0
var _drag := false
var _charge := 0.0
var _charging := false
var _shock := 0.0
var _recoil := 0.0
var _input_hold := 0.0
var _time := 0.0
var _hint_alpha := 0.0
var _hint_timer := 0.0
var _halo_root: Node3D
var _contact_glow: MeshInstance3D
var _charge_ring_mat: StandardMaterial3D
var _debug_face_on := false
var _debug_view_yaw := 0.0

var _capture_path := ""
var _capture_delay := 2.2
var _capture_count := 1

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	get_window().title = "VOLTAIC EDGE  ·  a sword of arcs"
	var _args := OS.get_cmdline_user_args()
	_debug_face_on = _args.has("--face-on") or _args.has("--view-yaw")
	var yaw_idx := _args.find("--view-yaw")
	if yaw_idx >= 0 and yaw_idx + 1 < _args.size():
		_debug_view_yaw = deg_to_rad(float(_args[yaw_idx + 1]))
	_rng.randomize()
	_setup_environment()
	_build_stage()
	_setup_halo()
	_setup_dust()
	_update_camera(0.0)
	_update_halo()
	_parse_capture_args()
	if _capture_path != "":
		_capture_soon()

func _process(delta: float) -> void:
	_time += delta
	_input_hold = maxf(0.0, _input_hold - delta)
	_auto_weight = lerpf(_auto_weight, 1.0 if _input_hold <= 0.0 else 0.0, clampf(delta * 1.4, 0.0, 1.0))
	_shock = maxf(0.0, _shock - delta * 3.2)
	_recoil = maxf(0.0, _recoil - delta * 4.5)

	# Orbit input.
	if not _debug_face_on:
		var key_yaw := (1.0 if (Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)) else 0.0) - (1.0 if (Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)) else 0.0)
		var key_pitch := (1.0 if (Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)) else 0.0) - (1.0 if (Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)) else 0.0)
		if key_yaw != 0.0 or key_pitch != 0.0:
			_user_yaw = wrapf(_user_yaw + key_yaw * delta * 1.25, -PI, PI)
			_user_pitch = clampf(_user_pitch + key_pitch * delta * 0.85, -0.28, 0.78)
			_input_hold = 2.0
			_auto_weight = lerpf(_auto_weight, 0.0, clampf(delta * 5.0, 0.0, 1.0))

	# Charge on space. Releasing above the threshold fires a strike.
	if not _debug_face_on:
		var want := Input.is_key_pressed(KEY_SPACE)
		if want:
			_charging = true
			_charge = minf(1.0, _charge + delta / 0.95)
			_auto_weight = minf(_auto_weight, 0.35)
		elif _charging:
			_charging = false
			_release_strike()
	if not _charging:
		_charge = maxf(0.0, _charge - delta * 2.6)

	# Sword floats and slowly turns, presenting its thin 3D cross-section.
	if _debug_face_on:
		sword.position = Vector3.ZERO
		sword.rotation = Vector3.ZERO
	else:
		var lift := 0.10 * _charge + 0.012 * sin(_time * 1.9)
		sword.position = Vector3(0.0, sin(_time * 0.72) * 0.020 + lift, 0.0)
		sword.rotation.y = 0.06 + 0.14 * sin(_time * 0.31) + 0.045 * sin(_time * 0.79 + 1.3)
		sword.rotation.z = 0.022 * sin(_time * 0.43 + 0.5) - 0.035
		sword.rotation.x = 0.020 * sin(_time * 0.57 + 2.0)
		# Lean back while charging, then kick forward on release.
		sword.rotation.x += -0.16 * _charge + 0.30 * _recoil
		sword.rotation.z += 0.10 * _charge

	var auto_yaw := 0.0 if _debug_face_on else sin(_time * 0.105) * 0.16 * _auto_weight
	var auto_pitch := 0.0 if _debug_face_on else (0.5 + 0.5 * sin(_time * 0.073 + 1.1)) * 0.025 * _auto_weight
	var yaw := (_debug_view_yaw if _debug_face_on else _base_yaw) + auto_yaw + (0.0 if _debug_face_on else _user_yaw)
	var pitch := (0.05 if _debug_face_on else clampf(_base_pitch + auto_pitch + _user_pitch, -0.22, 0.95))

	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	) * _distance
	var shake := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * (0.030 * _shock)
	camera.position = _target + offset + shake
	camera.look_at(_target + shake * 0.4, Vector3.UP)
	_update_halo()

	var focus := 1.0 + _charge * 1.05 + _shock * 0.8 + 0.04 * sin(_time * 2.3)
	sword.external_intensity = focus
	sword.charge = _charge

	if _charge_ring_mat:
		_charge_ring_mat.emission_energy_multiplier = 0.8 + 5.0 * _charge + 3.0 * _shock
	if _contact_glow:
		_contact_glow.scale = Vector3(1.0 + 0.18 * _charge, 1.0 + 0.18 * _charge, 1.0)
	_update_charge_ui()
	_update_hint(delta)

func _update_camera(_delta: float) -> void:
	var yaw := _base_yaw
	var pitch := _base_pitch
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	) * _distance
	camera.position = _target + offset
	camera.look_at(_target, Vector3.UP)

func _update_charge_ui() -> void:
	if charge_bar == null or charge_fill == null:
		return
	var show := _charge > 0.015
	charge_bar.visible = show
	if show:
		charge_fill.size.x = charge_bar.size.x * _charge
		charge_fill.color = Color(1.0, 0.42 + 0.4 * _charge, 0.10, 0.85)

func _update_hint(delta: float) -> void:
	_hint_timer += delta
	if _hint_timer < 1.0:
		_hint_alpha = move_toward(_hint_alpha, 0.0, delta * 0.8)
	elif _hint_timer < 8.5:
		_hint_alpha = move_toward(_hint_alpha, 0.46, delta * 0.35)
	else:
		_hint_alpha = move_toward(_hint_alpha, 0.0, delta * 0.3)
	hint.modulate.a = _hint_alpha

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
			_input_hold = 5.0
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(3.9, _distance - 0.28)
			_input_hold = 5.0
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(7.4, _distance + 0.28)
			_input_hold = 5.0
	elif event is InputEventMouseMotion and _drag:
		_user_yaw = wrapf(_user_yaw + event.relative.x * 0.0042, -PI, PI)
		_user_pitch = clampf(_user_pitch - event.relative.y * 0.0030, -0.40, 0.72)
		_input_hold = 5.0
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_user_yaw = 0.0
		_user_pitch = 0.0
		_distance = 5.35
		_input_hold = 0.0
		_auto_weight = 1.0

# --------------------------------------------------------------------- strike

func _release_strike() -> void:
	var strength := _charge
	_charge = 0.0
	if strength < 0.18:
		return
	_shock = strength
	_recoil = 1.0
	# Fire from the blade tip into a fixed contact plate on the stage, so the
	# bolt always has a readable start and end instead of pointing at nothing.
	var tip_world: Vector3 = sword.to_global(Vector3(0.0, BLADE_TIP_Y, 0.0))
	var target_world := Vector3(
		-0.75 + _rng.randf_range(-0.10, 0.10),
		0.02,
		1.35 + _rng.randf_range(-0.10, 0.10)
	)
	var local_from: Vector3 = sword.to_local(tip_world)
	var local_to: Vector3 = sword.to_local(target_world)
	var edges := _make_strike_edges(local_from, local_to, strength)
	var bolt := preload("res://src/arc_bolt3d.gd").new()
	sword.add_child(bolt)
	bolt.setup(edges, _rng, 0.17, 1.0, 2.0 + strength * 0.8)
	_spawn_impact(target_world, strength)

func _make_strike_edges(from: Vector3, to: Vector3, strength: float) -> Array:
	var edges: Array = []
	var segments := 30
	var prev := from
	var points: Array[Vector3] = [from]
	for i in range(segments):
		var t := float(i + 1) / float(segments)
		var p := from.lerp(to, t)
		var env := sin(t * PI)
		p += Vector3(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0)
		) * (0.16 * env * (0.7 + 0.5 * strength))
		points.append(p)
		edges.append(_strike_edge(prev, p, 0.020 * (0.55 + 0.45 * (1.0 - t))))
		prev = p
	# Two or three forked branches peeling off the main channel.
	for b in range(2 + int(round(strength * 2.0))):
		var idx := _rng.randi_range(4, points.size() - 7)
		var start := points[idx]
		var dir := (points[mini(idx + 3, points.size() - 1)] - start).normalized()
		var side := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
		var q := start
		for s in range(6):
			var np := q + (dir * 0.55 + side * 0.45).normalized() * _rng.randf_range(0.09, 0.17)
			edges.append(_strike_edge(q, np, 0.011 * (1.0 - 0.12 * float(s))))
			q = np
	return edges

func _strike_edge(a: Vector3, b: Vector3, width: float) -> Dictionary:
	return {
		"a": a,
		"b": b,
		"depth": 0,
		"width": width,
		"energy": 1.9,
		"hue": 0.15,
		"phase": _rng.randf() * TAU,
		"leader": true,
	}

func _spawn_impact(at: Vector3, strength: float) -> void:
	var light := OmniLight3D.new()
	light.position = at + Vector3(0.0, 0.22, 0.0)
	light.light_color = Color(1.0, 0.60, 0.22)
	light.light_energy = 9.0 + 9.0 * strength
	light.omni_range = 4.5
	light.shadow_enabled = false
	add_child(light)

	var dot := _make_soft_dot_texture()
	var sprite := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	sprite.mesh = quad
	sprite.position = at + Vector3(0.0, 0.20, 0.0)
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = dot
	mat.albedo_color = Color(1.0, 0.72, 0.35, 0.90)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sprite.material_override = mat
	add_child(sprite)

	# Expanding floor ring.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position = at
	ring.scale = Vector3(0.3, 0.3, 0.3)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.albedo_color = Color(1.0, 0.55, 0.16, 0.85)
	ring.material_override = ring_mat
	add_child(ring)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(light, "light_energy", 0.0, 0.42).set_ease(Tween.EASE_OUT)
	t.tween_property(sprite, "scale", Vector3(2.6, 2.6, 1.0) * (0.8 + 0.4 * strength), 0.32)
	t.tween_method(func(a: float) -> void: mat.albedo_color.a = a, 0.90, 0.0, 0.34)
	t.tween_property(ring, "scale", Vector3(2.2, 1.0, 2.2), 0.48).set_ease(Tween.EASE_OUT)
	t.tween_method(func(a: float) -> void: ring_mat.albedo_color.a = a, 0.85, 0.0, 0.50)
	t.chain().tween_callback(func() -> void:
		light.queue_free()
		sprite.queue_free()
		ring.queue_free()
	)

# ---------------------------------------------------------------- environment

func _setup_environment() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.28, 0.40)
	env.ambient_light_energy = 0.14
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_strength = 1.0
	env.glow_bloom = 0.015
	env.glow_hdr_threshold = 0.92
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var glow_weights := {1: 0.70, 2: 1.0, 3: 0.55, 4: 0.22, 5: 0.08, 6: 0.0, 7: 0.0}
	for i in range(1, 8):
		env.set("glow_levels/%d" % i, glow_weights[i])
	env.ssao_enabled = true
	env.ssao_radius = 0.75
	env.ssao_intensity = 1.3
	env.fog_enabled = true
	env.fog_light_color = Color(0.045, 0.034, 0.030)
	env.fog_light_energy = 0.6
	env.fog_density = 0.018
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.03

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func _build_stage() -> void:
	# Dark polished plate: the sword sits in a pool of amber light instead of
	# in an empty void.
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.018, 0.017, 0.019)
	floor_mat.metallic = 0.72
	floor_mat.roughness = 0.34
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(70.0, 70.0)
	floor_mi.mesh = plane
	floor_mi.material_override = floor_mat
	floor_mi.position = Vector3(0.0, -1.02, 0.0)
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mi)

	# Raised dais.
	var dais_mat := StandardMaterial3D.new()
	dais_mat.albedo_color = Color(0.030, 0.031, 0.036)
	dais_mat.metallic = 0.80
	dais_mat.roughness = 0.42
	var dais := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.10
	cyl.bottom_radius = 2.22
	cyl.height = 0.12
	cyl.radial_segments = 64
	cyl.rings = 2
	dais.mesh = cyl
	dais.material_override = dais_mat
	dais.position = Vector3(0.0, -0.96, 0.0)
	add_child(dais)

	# Inlaid containment ring + charge ring.
	var inlay := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.62
	torus.outer_radius = 1.655
	torus.rings = 80
	torus.ring_segments = 6
	inlay.mesh = torus
	inlay.position = Vector3(0.0, -0.897, 0.0)
	inlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inlay_mat := StandardMaterial3D.new()
	inlay_mat.albedo_color = Color(0.20, 0.09, 0.02)
	inlay_mat.emission_enabled = true
	inlay_mat.emission = Color(1.0, 0.36, 0.07)
	inlay_mat.emission_energy_multiplier = 0.55
	inlay.material_override = inlay_mat
	add_child(inlay)

	_charge_ring_mat = StandardMaterial3D.new()
	_charge_ring_mat.albedo_color = Color(0.30, 0.14, 0.03)
	_charge_ring_mat.emission_enabled = true
	_charge_ring_mat.emission = Color(1.0, 0.40, 0.08)
	_charge_ring_mat.emission_energy_multiplier = 0.8
	var ring2 := MeshInstance3D.new()
	var torus2 := TorusMesh.new()
	torus2.inner_radius = 0.86
	torus2.outer_radius = 0.895
	torus2.rings = 64
	torus2.ring_segments = 6
	ring2.mesh = torus2
	ring2.position = Vector3(0.0, -0.893, 0.0)
	ring2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring2.material_override = _charge_ring_mat
	add_child(ring2)

	# Four clamp pads around the dais.
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.055, 0.056, 0.062)
	pad_mat.metallic = 0.86
	pad_mat.roughness = 0.30
	var slot_mat := StandardMaterial3D.new()
	slot_mat.albedo_color = Color(0.18, 0.08, 0.02)
	slot_mat.emission_enabled = true
	slot_mat.emission = Color(1.0, 0.34, 0.06)
	slot_mat.emission_energy_multiplier = 1.4
	for i in range(4):
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var pad := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.46, 0.045, 0.20)
		pad.mesh = box
		pad.material_override = pad_mat
		pad.position = Vector3(cos(a) * 1.92, -0.885, sin(a) * 1.92)
		pad.rotation.y = -a + PI * 0.5
		add_child(pad)
		var slot := MeshInstance3D.new()
		var slot_box := BoxMesh.new()
		slot_box.size = Vector3(0.30, 0.006, 0.022)
		slot.mesh = slot_box
		slot.material_override = slot_mat
		slot.position = pad.position + Vector3(0.0, 0.026, 0.0)
		slot.rotation.y = pad.rotation.y
		add_child(slot)

	# Distant monoliths: kill the horizon and give the stage depth.
	var mono_mat := StandardMaterial3D.new()
	mono_mat.albedo_color = Color(0.010, 0.011, 0.014)
	mono_mat.metallic = 0.6
	mono_mat.roughness = 0.55
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color(0.20, 0.08, 0.02)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(1.0, 0.30, 0.05)
	strip_mat.emission_energy_multiplier = 1.1
	for i in range(11):
		var a := TAU * float(i) / 11.0 + 0.17
		var r := 9.5 + 2.6 * float(i % 3)
		var h := 4.2 + 3.8 * float((i * 7) % 5) / 4.0
		var mono := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.5 + 0.4 * float(i % 3), h, 0.55)
		mono.mesh = box
		mono.material_override = mono_mat
		mono.position = Vector3(cos(a) * r, h * 0.5 - 1.02, sin(a) * r)
		mono.rotation.y = -a + PI * 0.5
		add_child(mono)
		if i % 2 == 0:
			var strip := MeshInstance3D.new()
			var sbox := BoxMesh.new()
			sbox.size = Vector3(0.035, h * 0.42, 0.02)
			strip.mesh = sbox
			strip.material_override = strip_mat
			strip.position = mono.position + Vector3(-sin(a), -h * 0.10, cos(a)) * 0.79
			strip.rotation.y = mono.rotation.y
			add_child(strip)

	# Lights.
	var key := SpotLight3D.new()
	key.position = Vector3(3.6, 5.4, 4.2)
	key.look_at_from_position(key.position, Vector3(0.0, 0.85, 0.0), Vector3.UP)
	key.light_color = Color(1.0, 0.88, 0.74)
	key.light_energy = 17.0
	key.spot_range = 22.0
	key.spot_angle = 30.0
	key.spot_angle_attenuation = 1.1
	key.shadow_enabled = true
	key.shadow_bias = 0.02
	key.shadow_blur = 1.4
	add_child(key)

	var rim_cool := OmniLight3D.new()
	rim_cool.position = Vector3(-3.2, 2.4, -2.8)
	rim_cool.light_color = Color(0.30, 0.50, 1.0)
	rim_cool.light_energy = 2.4
	rim_cool.omni_range = 12.0
	add_child(rim_cool)

	var rim_warm := OmniLight3D.new()
	rim_warm.position = Vector3(3.0, 1.0, -3.0)
	rim_warm.light_color = Color(1.0, 0.28, 0.08)
	rim_warm.light_energy = 1.8
	rim_warm.omni_range = 10.0
	add_child(rim_warm)

	var under := OmniLight3D.new()
	under.position = Vector3(0.0, -0.55, 0.35)
	under.light_color = Color(1.0, 0.45, 0.12)
	under.light_energy = 1.4
	under.omni_range = 5.0
	add_child(under)

	# Soft pool of light under the sword.
	_contact_glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_contact_glow.mesh = q
	_contact_glow.position = Vector3(0.0, -0.889, 0.0)
	_contact_glow.rotation.x = -PI * 0.5
	_contact_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.albedo_texture = _make_soft_dot_texture()
	glow_mat.albedo_color = Color(1.0, 0.42, 0.10, 0.22)
	glow_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_contact_glow.material_override = glow_mat
	_contact_glow.scale = Vector3(2.6, 2.0, 1.0)
	add_child(_contact_glow)

func _setup_halo() -> void:
	_halo_root = Node3D.new()
	add_child(_halo_root)
	var dot := _make_soft_dot_texture()
	_add_halo_quad(dot, Vector3(0.0, 0.0, 0.0), Vector2(2.6, 3.9), Color(1.0, 0.40, 0.07, 0.020))
	_add_halo_quad(dot, Vector3(0.0, 0.30, -0.8), Vector2(5.2, 7.2), Color(1.0, 0.30, 0.045, 0.009))

func _update_halo() -> void:
	if _halo_root == null:
		return
	var forward := -camera.global_transform.basis.z
	_halo_root.global_position = _target - forward * 2.2 + Vector3(0.0, 0.02, 0.0)

func _add_halo_quad(dot: Texture2D, position: Vector3, size: Vector2, tint: Color) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.position = position
	mi.scale = Vector3(size.x, size.y, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 3.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = dot
	mat.albedo_color = tint
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = mat
	_halo_root.add_child(mi)

func _setup_dust() -> void:
	var dot := _make_soft_dot_texture()
	_add_particle_layer(dot, 110, 12.0, 0.007, 0.030, 0.008, 0.040, Color(1.0, 0.58, 0.20, 0.60), 1.1)
	_add_particle_layer(dot, 52, 4.6, 0.0035, 0.012, 0.045, 0.170, Color(1.0, 0.70, 0.30, 0.85), 1.8)

func _add_particle_layer(
	dot: Texture2D,
	amount: int,
	lifetime: float,
	scale_min: float,
	scale_max: float,
	vel_min: float,
	vel_max: float,
	tint: Color,
	emission_energy: float
) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.explosiveness = 0.0
	particles.randomness = 0.65
	particles.fixed_fps = 30
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-3.0, -2.0, -3.0), Vector3(6.0, 7.0, 6.0))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(1.90, 2.60, 1.60)
	process.direction = Vector3.UP
	process.spread = 48.0
	process.initial_velocity_min = vel_min
	process.initial_velocity_max = vel_max
	process.gravity = Vector3(0.0, 0.004, 0.0)
	process.scale_min = scale_min
	process.scale_max = scale_max
	process.color = tint
	particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = dot
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.16)
	mat.emission_energy_multiplier = emission_energy
	quad.material = mat
	particles.draw_pass_1 = quad
	particles.position = Vector3(0.0, 0.75, 0.0)
	add_child(particles)

func _make_soft_dot_texture() -> Texture2D:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var uv := Vector2(
				(float(x) + 0.5) / float(size) * 2.0 - 1.0,
				(float(y) + 0.5) / float(size) * 2.0 - 1.0
			)
			var d := clampf(uv.length(), 0.0, 1.0)
			var a := pow(maxf(1.0 - d, 0.0), 2.6)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(image)

func _parse_capture_args() -> void:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--capture")
	if idx >= 0 and idx + 1 < args.size():
		_capture_path = args[idx + 1]
	var d_idx := args.find("--capture-delay")
	if d_idx >= 0 and d_idx + 1 < args.size():
		_capture_delay = maxf(0.1, float(args[d_idx + 1]))
	var c_idx := args.find("--capture-count")
	if c_idx >= 0 and c_idx + 1 < args.size():
		_capture_count = maxi(1, int(args[c_idx + 1]))

func _capture_soon() -> void:
	await get_tree().create_timer(_capture_delay).timeout
	if _capture_count <= 1:
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var err := image.save_png(_capture_path)
		print("CAPTURE path=", _capture_path, " err=", err, " image=", image.get_width(), "x", image.get_height())
		get_tree().quit()
		return
	var base := _capture_path
	if base.ends_with(".png"):
		base = base.substr(0, base.length() - 4)
	for i in range(_capture_count):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("%s%03d.png" % [base, i])
		if i == 0:
			print("BURST ", base, " count=", _capture_count, " err=", err)
	print("BURST DONE")
	get_tree().quit()