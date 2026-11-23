// Arena lamp halo: camera-facing additive disc used for lamp bodies and neon bloom
// cores.  Pure maths (no texture): a tight core plus a wide soft halo so the
// engine glow pass has something to work with.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled,
	fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.94, 0.86);
uniform float strength = 1.0;
uniform float core = 0.10;
uniform float halo = 1.0;
uniform float flicker = 0.0;
uniform float seed = 0.0;

void vertex() {
	// 公告板：保留模型缩放，朝向相机
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float c = exp(-(r * r) / max(core, 0.004));
	float h = pow(max(1.0 - r, 0.0), 3.5);
	float fl = 1.0;
	if (flicker > 0.001) {
		float f1 = 0.5 + 0.5 * sin(TIME * 11.0 + seed * 31.0);
		float f2 = 0.5 + 0.5 * sin(TIME * 27.3 + seed * 7.0);
		fl = 1.0 - flicker * (0.35 * f1 + 0.65 * f1 * f2);
	}
	float m = (c * 2.4 + h * halo * 1.5) * strength * fl;
	ALBEDO = vec3(0.0);
	EMISSION = tint * m;
	ALPHA = clamp(c + h * halo, 0.0, 1.0);
}
