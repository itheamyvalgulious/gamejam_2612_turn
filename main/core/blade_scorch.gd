extends Node3D
## 能量刀划过地形留下的灼烧痕迹（MultiMesh 单次绘制，零节点分配，FIFO 环形覆盖）。

const MAX_MARKS := 180

static var _shader: Shader
static var _mat: ShaderMaterial

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _cursor := 0
var _count := 0
var _marks: Array = []    # [{xf: Transform3D, born_s: float, seed: float}]


static func ensure_material() -> ShaderMaterial:
	if _mat != null:
		return _mat
	_shader = Shader.new()
	_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

varying float v_heat;
varying float v_seed;

void vertex() {
	v_heat = INSTANCE_CUSTOM.r;
	v_seed = INSTANCE_CUSTOM.g;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float x = p.x;
	float y = p.y;
	// 两端收尖的刀痕轮廓 + 轻微不规则边缘
	float taper = smoothstep(1.0, 0.25, abs(x));
	float jitter = sin(x * 19.0 + v_seed * 6.2831) * 0.08 + sin(x * 37.0 - v_seed * 11.0) * 0.04;
	float w = max(0.08, taper * (0.85 + jitter));
	float dy = abs(y) / w;
	float body = 1.0 - smoothstep(0.45, 1.0, dy);
	if (body <= 0.005) {
		discard;
	}
	float core = 1.0 - smoothstep(0.0, 0.36, dy);
	float heat = clamp(v_heat, 0.0, 1.0);
	vec3 char_col = vec3(0.04, 0.035, 0.035);
	vec3 ember_col = mix(vec3(0.95, 0.34, 0.06), vec3(0.55, 0.90, 1.0), 0.35 * heat);
	vec3 col = mix(char_col, ember_col * (1.2 + 2.2 * heat), core * heat);
	ALBEDO = col;
	ALPHA = body * mix(0.72, 0.94, core * heat);
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	return _mat


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = false
	_mm.use_custom_data = true
	_mm.mesh = q
	_mm.instance_count = MAX_MARKS
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = ensure_material()
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	_marks.resize(MAX_MARKS)


func add_mark(point: Vector3, normal: Vector3, tangent: Vector3, length := 0.48, width := 0.14) -> void:
	if _mm == null:
		return
	var n := normal.normalized() if normal.length_squared() > 1e-6 else Vector3.UP
	var t := tangent.slide(n)
	if t.length_squared() < 1e-6:
		t = n.cross(Vector3.UP)
		if t.length_squared() < 1e-6:
			t = n.cross(Vector3.RIGHT)
	t = t.normalized()
	var b := n.cross(t).normalized()
	# QuadMesh 默认在 XY 平面（法线 +Z）；把局部 X 对齐刀痕切线、局部 Y 对齐副切线、局部 Z 对齐表面法线
	var basis := Basis(t * maxf(length, 0.16), b * maxf(width, 0.06), n)
	var xf := Transform3D(basis, point + n * 0.016)
	var idx := _cursor
	_cursor = (_cursor + 1) % MAX_MARKS
	_count = mini(_count + 1, MAX_MARKS)
	var now_s := Time.get_ticks_msec() / 1000.0
	var sd := fmod(float(idx) * 0.371 + now_s * 0.13, 1.0)
	_marks[idx] = {"xf": xf, "born_s": now_s, "seed": sd}
	_mm.set_instance_transform(idx, xf)
	_mm.set_instance_custom_data(idx, Color(1.0, sd, 0.0, 0.0))
	_mm.visible_instance_count = _count


func clear() -> void:
	_cursor = 0
	_count = 0
	if _mm != null:
		_mm.visible_instance_count = 0


func _process(_dt: float) -> void:
	if _count == 0 or _mm == null:
		return
	var now_s := Time.get_ticks_msec() / 1000.0
	for i in _count:
		var m: Variant = _marks[i]
		if not (m is Dictionary):
			continue
		var md: Dictionary = m
		var age := now_s - float(md["born_s"])
		var heat := clampf(1.0 - age / 1.8, 0.0, 1.0)
		if heat > 0.0 or age < 1.95:
			_mm.set_instance_custom_data(i, Color(heat, float(md["seed"]), 0.0, 0.0))
