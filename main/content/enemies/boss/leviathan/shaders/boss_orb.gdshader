shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

// Red containment plasma. Added over the scene, shaped by fresnel and
// scrolling filament noise. `energy` is driven by the phase-2 transformation.

uniform vec4 color : source_color = vec4(1.0, 0.10, 0.020, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.72, 0.46, 1.0);
uniform float energy = 1.0;
uniform float seed = 0.0;
uniform float opacity = 1.0;
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
	return vnoise3(p) * 0.62 + vnoise3(p * 2.13 + vec3(4.1, 9.2, 1.7)) * 0.28
		+ vnoise3(p * 4.31 + vec3(8.7, 2.9, 5.3)) * 0.10;
}

void vertex() {
	opos = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 vdir = normalize(VIEW);
	float fres = pow(1.0 - abs(dot(n, vdir)), 2.2);
	float rim = pow(1.0 - abs(dot(n, vdir)), 4.5);

	vec3 p = opos * 1.65 + vec3(seed * 3.1, TIME * 0.22, seed);
	float a = fbm3(p * 1.4);
	float b = fbm3(p * 3.1 - vec3(0.0, TIME * 0.30, 0.0));
	float veins = pow(1.0 - abs(a - b), 3.5);
	float swirl = 0.5 + 0.5 * sin(opos.y * 5.0 + opos.x * 2.2 + a * 9.0 - TIME * 2.3);
	float band = pow(swirl, 3.0);

	vec3 col = color.rgb * (0.40 + fres * 1.35 + veins * 0.85 + band * 0.55);
	col += hot_color.rgb * (veins * 0.75 + rim * 0.55 + charge * 0.7) * (0.35 + energy * 0.35);
	ALBEDO = col * energy * (0.85 + charge * 1.6);
	EMISSION = vec3(0.0);
	ALPHA = clamp((0.30 + fres * 0.70 + veins * 0.18 + band * 0.08) * opacity, 0.0, 1.0);
}
