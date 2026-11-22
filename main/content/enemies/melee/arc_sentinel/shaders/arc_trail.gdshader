shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// ARC SENTINEL — swept arc trail. Vertex colour carries tint and age.
// UV.y = 0 at the blade root, 1 at the tip; UV.x = age (1 newest).

uniform float energy = 0.9;
uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.18, 1.0);
uniform float streak_scale = 9.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	float a = COLOR.a;
	float across = UV.y;
	float streak = 0.72 + 0.28 * hash21(vec2(floor(UV.x * streak_scale), floor(across * 5.0)));
	// thin out toward the root, keep the tip bright
	float taper = smoothstep(0.0, 0.30, across);
	ALBEDO = COLOR.rgb * tint.rgb * a * energy * (1.0 + 0.9 * taper);
	ALPHA = clamp(a * streak * (0.35 + 0.75 * taper), 0.0, 1.0);
}