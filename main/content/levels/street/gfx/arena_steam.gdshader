// Arena steam / dust motes: camera-facing soft disc.  Unshaded (the palette tints
// it) so puffs stay readable in dark alleys; the particle color ramp drives the
// lifetime fade through COLOR.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float alpha = 0.30;
uniform float softness = 0.75;
uniform float lift = 0.0;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
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
	float s = 1.0 - smoothstep(softness, 1.0, r);
	float m = s * s * vcol.a * alpha;
	ALBEDO = vcol.rgb * 1.1;
	EMISSION = vcol.rgb * (0.10 + lift);
	ALPHA = clamp(m, 0.0, 1.0);
}
