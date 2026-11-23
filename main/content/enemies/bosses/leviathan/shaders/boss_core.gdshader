shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

// Solid energy heart inside the plasma shell: nearly opaque, white-hot
// filament core with red edges.

uniform vec4 color : source_color = vec4(1.0, 0.09, 0.015, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.86, 0.70, 1.0);
uniform float energy = 1.0;
uniform float seed = 0.0;
uniform float charge = 0.0;

varying vec3 opos;

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash31(i), hash31(i + vec3(1,0,0)), u.x),
			mix(hash31(i + vec3(0,1,0)), hash31(i + vec3(1,1,0)), u.x), u.y),
		mix(mix(hash31(i + vec3(0,0,1)), hash31(i + vec3(1,0,1)), u.x),
			mix(hash31(i + vec3(0,1,1)), hash31(i + vec3(1,1,1)), u.x), u.y), u.z);
}
float fbm3(vec3 p) {
	return vnoise3(p) * 0.60 + vnoise3(p * 2.07 + vec3(4.1, 9.2, 1.7)) * 0.28
		+ vnoise3(p * 4.23 + vec3(8.7, 2.9, 5.3)) * 0.12;
}

void vertex() {
	opos = VERTEX;
}

void fragment() {
	vec3 p = opos * 2.2 + vec3(seed, TIME * 0.42, seed * 2.0);
	float a = fbm3(p);
	float b = fbm3(p * 2.7 - vec3(TIME * 0.5, 0.0, 0.0));
	float fil = pow(1.0 - abs(a - b), 3.0);
	float cells = smoothstep(0.52, 0.86, a);
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.4);
	vec3 col = mix(color.rgb, hot_color.rgb, clamp(cells * 0.45 + fil * 0.65, 0.0, 1.0));
	col *= 1.15 + fres * 0.7 + fil * 1.1 + charge * 1.2;
	col += color.rgb * 0.55;
	ALBEDO = col * energy;
	METALLIC = 0.0;
	ROUGHNESS = 0.5;
	EMISSION = vec3(0.0);
}
