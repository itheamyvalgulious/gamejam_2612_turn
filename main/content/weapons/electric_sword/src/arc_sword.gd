extends Node3D

const ArcBoltScript = preload("res://src/arc_bolt3d.gd")
const ArcFieldScript = preload("res://src/arc_field.gd")
const BLADE_FIELD_SHADER: Shader = preload("res://shaders/blade_field.gdshader")

const SPAWN_INTERVAL := 0.016
const BOLT_LIFE := 0.150
const PARTIAL_SCALE := 0.90
const SCAFFOLD_INTERVAL := 0.045
const SCAFFOLD_LIFE := 0.090
const ESCAPE_WAVE_INTERVAL := 0.044
const ESCAPE_LIFE_MIN := 0.055
const ESCAPE_LIFE_MAX := 0.125

var external_intensity := 1.0
var charge := 0.0

var _field: RefCounted
var _rng := RandomNumberGenerator.new()
var _spawn_accum := 0.0
var _scaffold_accum := 0.0
var _time := 0.0
var _intensity := 1.0
var _avg_weight := 0.0
var _escape_accum := 0.0
var _sheet_mat: ShaderMaterial
var _tip_glow: MeshInstance3D
var _tip_light: OmniLight3D
var _mote_root: Node3D
var _motes: Array[MeshInstance3D] = []
var _mote_phase: Array[float] = []

func _ready() -> void:
	_field = ArcFieldScript.new()
	_rng.randomize()
	_build_sheet()
	_build_tip_glow()
	_build_motes()
	# Populate instantly so the first rendered frame already has a sword.
	for i in range(8):
		_spawn_bolt(1.0)
	_spawn_scaffold()
	_spawn_escape_batch()

func _process(delta: float) -> void:
	_time += delta

	# Slow, soft swells instead of sharp strobe pulses.
	var breath := 0.5 + 0.5 * sin(_time * 0.35 + 0.8)
	_intensity = external_intensity * (0.89 + 0.025 * breath)
	var hilt := get_node_or_null("GeneratorHilt")
	if hilt != null:
		hilt.energy = _intensity

	_update_sheet()
	_update_tip_glow()
	_update_motes()

	_spawn_accum += delta
	var budget := 8
	while _spawn_accum >= SPAWN_INTERVAL and budget > 0:
		_spawn_accum -= SPAWN_INTERVAL
		budget -= 1
		_spawn_bolt(_intensity * _rng.randf_range(0.97, 1.03))
	if _spawn_accum > SPAWN_INTERVAL * 8.0:
		_spawn_accum = 0.0

	_scaffold_accum += delta
	if _scaffold_accum >= SCAFFOLD_INTERVAL:
		_scaffold_accum = fmod(_scaffold_accum, SCAFFOLD_INTERVAL)
		_spawn_scaffold()

	_escape_accum += delta
	var escape_budget := 4
	while _escape_accum >= ESCAPE_WAVE_INTERVAL and escape_budget > 0:
		_escape_accum -= ESCAPE_WAVE_INTERVAL
		escape_budget -= 1
		_spawn_escape_batch()
	if _escape_accum > ESCAPE_WAVE_INTERVAL * 8.0:
		_escape_accum = 0.0

func _spawn_bolt(energy: float) -> void:
	var edges: Array = _field.grow(_rng, PARTIAL_SCALE)
	var weight := 0.0
	for e in edges:
		var length: float = (e["b"] as Vector3).distance_to(e["a"] as Vector3)
		weight += float(e["width"]) * float(e["energy"]) * maxf(length, 0.01)
	if _avg_weight <= 0.0:
		_avg_weight = weight
	else:
		_avg_weight = lerpf(_avg_weight, weight, 0.14)
	var norm := clampf(pow(_avg_weight / maxf(weight, 0.0001), 0.65), 0.82, 1.14)

	var bolt := ArcBoltScript.new()
	add_child(bolt)
	# A long crossfade with many staggered bolts hides the 16 ms restrikes.
	bolt.setup(edges, _rng, BOLT_LIFE * _rng.randf_range(0.92, 1.08), 0.30 * _rng.randf_range(0.95, 1.05), energy * norm)

func _spawn_scaffold() -> void:
	var edges: Array = _field.edge_scaffold(_rng, true)
	if edges.is_empty():
		return
	var bolt := ArcBoltScript.new()
	add_child(bolt)
	# The skeleton lives longer and brighter than the noise, but it still
	# restrikes: it is the containment field, not a painted outline.
	bolt.setup(edges, _rng, SCAFFOLD_LIFE * _rng.randf_range(0.94, 1.06),
		0.55 * _rng.randf_range(0.92, 1.06), 1.05 + charge * 0.5)

func _spawn_escape_batch() -> void:
	# Many short, unconstrained escape trees at once. They are independent
	# bolts with instant on/off (no fade), so they crackle around the blade
	# and vanish abruptly just like the other arcs. Sizes are exponential:
	# mostly small licks, occasionally a large forked tree.
	var count := _rng.randi_range(2, 4)
	for i in range(count):
		var edges: Array = _field.grow_escape_one(_rng)
		if edges.is_empty():
			continue
		var bolt := ArcBoltScript.new()
		add_child(bolt)
		var lifetime := _rng.randf_range(ESCAPE_LIFE_MIN, ESCAPE_LIFE_MAX)
		bolt.setup(edges, _rng, lifetime, 0.52 * _rng.randf_range(0.88, 1.12), 1.0, true)

# --------------------------------------------------------------- blade sheet

func _build_sheet() -> void:
	var bands := 56
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(bands + 1):
		var t := float(i) / float(bands)
		var y := lerpf(ArcFieldScript.BASE_Y, ArcFieldScript.TIP_Y, t)
		var w: float = _field.blade_half_width(y)
		verts.append(Vector3(-w, y, 0.0))
		uvs.append(Vector2(0.0, t))
		verts.append(Vector3(w, y, 0.0))
		uvs.append(Vector2(1.0, t))
	for i in range(bands):
		var b := i * 2
		indices.append_array([b, b + 1, b + 3, b, b + 3, b + 2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_sheet_mat = ShaderMaterial.new()
	_sheet_mat.shader = BLADE_FIELD_SHADER
	_sheet_mat.set_shader_parameter("time", 0.0)
	_sheet_mat.set_shader_parameter("fade", 1.0)
	_sheet_mat.set_shader_parameter("intensity", 1.0)
	_sheet_mat.set_shader_parameter("charge", 0.0)

	var mi := MeshInstance3D.new()
	mi.name = "BladeField"
	mi.mesh = mesh
	mi.material_override = _sheet_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	add_child(mi)

func _update_sheet() -> void:
	if _sheet_mat == null:
		return
	_sheet_mat.set_shader_parameter("time", _time)
	_sheet_mat.set_shader_parameter("intensity", _intensity)
	_sheet_mat.set_shader_parameter("charge", charge)
	_sheet_mat.set_shader_parameter("fade", 1.0)

func _build_tip_glow() -> void:
	var tip_y: float = ArcFieldScript.TIP_Y
	var tex := _make_dot_texture()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.30, 0.32)
	_tip_glow = MeshInstance3D.new()
	_tip_glow.name = "TipGlow"
	_tip_glow.mesh = quad
	_tip_glow.position = Vector3(0.0, tip_y, 0.0)
	_tip_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tip_glow.extra_cull_margin = 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 0.62, 0.22, 0.85)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_tip_glow.material_override = mat
	add_child(_tip_glow)

	_tip_light = OmniLight3D.new()
	_tip_light.position = Vector3(0.0, tip_y, 0.0)
	_tip_light.light_color = Color(1.0, 0.55, 0.18)
	_tip_light.light_energy = 1.2
	_tip_light.omni_range = 1.6
	_tip_light.shadow_enabled = false
	add_child(_tip_light)

func _update_tip_glow() -> void:
	if _tip_glow == null:
		return
	var pulse := 0.80 + 0.14 * sin(_time * 7.3) + 0.06 * sin(_time * 17.0 + 1.7)
	var s := (1.0 + charge * 0.55) * (0.9 + 0.1 * pulse)
	_tip_glow.scale = Vector3(s, s, s)
	if _tip_glow.material_override is StandardMaterial3D:
		var m := _tip_glow.material_override as StandardMaterial3D
		m.albedo_color = Color(1.0, 0.62, 0.22, clampf(0.55 + 0.35 * pulse + charge * 0.2, 0.0, 1.0))
	if _tip_light:
		_tip_light.light_energy = 0.9 + 0.5 * pulse + charge * 1.4

func _build_motes() -> void:
	# A handful of embers rising off the blade. GPU particles at this scale
	# are more expensive than they are worth; eight billboards read the same.
	_mote_root = Node3D.new()
	_mote_root.name = "BladeMotes"
	add_child(_mote_root)
	var tex := _make_dot_texture()
	for i in range(10):
		var quad := QuadMesh.new()
		var sz := _rng.randf_range(0.018, 0.042)
		quad.size = Vector2(sz, sz)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.albedo_texture = tex
		mat.albedo_color = Color(1.0, 0.52, 0.14, _rng.randf_range(0.35, 0.8))
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mi.material_override = mat
		_mote_root.add_child(mi)
		_motes.append(mi)
		_mote_phase.append(_rng.randf())
	_mote_root.set_process(false)

func _update_motes() -> void:
	var top: float = ArcFieldScript.TIP_Y * 0.94
	for i in range(_motes.size()):
		var phase := _mote_phase[i]
		var t := fmod(_time * (0.055 + 0.035 * phase) + phase, 1.0)
		var y := lerpf(-0.05, top, t)
		var w: float = _field.blade_half_width(y)
		var side := 1.0 if i % 2 == 0 else -1.0
		var x := side * w * (0.85 + 0.35 * sin(_time * 0.9 + float(i) * 2.3))
		var z := 0.02 * sin(_time * 1.3 + float(i) * 1.7)
		_motes[i].position = Vector3(x, y, z)
		var fade := sin(t * PI)
		var m := _motes[i].material_override as StandardMaterial3D
		if m:
			m.albedo_color.a = 0.55 * fade * (0.7 + 0.3 * sin(_time * 9.0 + float(i)))

func _make_dot_texture() -> Texture2D:
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var uv := Vector2(
				(float(x) + 0.5) / float(size) * 2.0 - 1.0,
				(float(y) + 0.5) / float(size) * 2.0 - 1.0
			)
			var d := clampf(uv.length(), 0.0, 1.0)
			var a := pow(maxf(1.0 - d, 0.0), 2.8)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(image)