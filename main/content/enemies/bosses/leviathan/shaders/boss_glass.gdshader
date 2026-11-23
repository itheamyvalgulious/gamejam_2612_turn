shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

// Transparent containment wall that reveals itself at full shell extension.

uniform vec4 tint : source_color = vec4(1.0, 0.22, 0.06, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.62, 0.40, 1.0);
uniform float opacity = 0.0;
uniform float pattern = 1.0;
uniform float energy = 1.0;
uniform float seed = 0.0;

varying vec3 wpos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1,0)), u.x),
		mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - abs(dot(n, normalize(VIEW))), 2.0);
	float rim = pow(1.0 - abs(dot(n, normalize(VIEW))), 5.0);

	// faint mechanical panel lattice
	vec2 g = vec2(atan(n.x, n.z) / 6.2831853 * 36.0, acos(clamp(n.y, -1.0, 1.0)) / 3.14159 * 18.0);
	vec2 gg = abs(fract(g) - 0.5);
	float lines = smoothstep(0.46, 0.49, max(gg.x, gg.y)) * pattern;
	float cells = vnoise(floor(g) + seed) * 0.35;

	float scan = 0.5 + 0.5 * sin(n.y * 90.0 - TIME * 1.8 + seed);
	float flick = 0.86 + 0.14 * sin(TIME * 7.3 + seed * 5.0);

	ALBEDO = (tint.rgb * (0.22 + fres * 0.9 + lines * 0.55 + cells * 0.25)
		+ rim_color.rgb * rim * 0.55) * energy * flick;
	METALLIC = 0.0;
	ROUGHNESS = 0.2;
	EMISSION = vec3(0.0);
	ALPHA = clamp(opacity * (0.18 + fres * 0.9 + lines * 0.45 + scan * 0.03), 0.0, 0.9);
}
