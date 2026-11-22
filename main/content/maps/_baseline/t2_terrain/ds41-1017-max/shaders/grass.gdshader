shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

varying vec3 wpos;
varying vec4 inst;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	inst = INSTANCE_CUSTOM;
	float ph = INSTANCE_CUSTOM.g * 6.2831;
	float sway = sin(TIME * 1.6 + wpos.x * 0.35 + wpos.z * 0.22 + ph) * 0.10;
	sway += sin(TIME * 3.1 + wpos.x * 0.9 + ph * 2.0) * 0.03;
	VERTEX.x += sway * UV.y;
	VERTEX.z += sway * 0.55 * UV.y;
}

void fragment() {
	vec3 n = normalize(vec3(0.0, 0.75, 0.0) + vec3(vnoise(UV * 5.0 + inst.r * 9.0) - 0.5, 0.0, 0.0) * 0.5);
	if (!FRONT_FACING) { n = -n; }
	n = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float tip = UV.y;
	float v = vnoise(vec2(UV.x * 3.0, UV.y * 1.5) + inst.r * 7.0);
	vec3 base = mix(vec3(0.035, 0.075, 0.020), vec3(0.085, 0.150, 0.035), v);
	base = mix(base, vec3(0.145, 0.165, 0.055), smoothstep(0.55, 1.0, tip) * 0.45);
	base *= mix(0.45, 1.0, tip);
	base *= 0.8 + 0.4 * inst.b;
	ALBEDO = base;
	ROUGHNESS = 0.72;
	SPECULAR = 0.18;
	BACKLIGHT = vec3(0.10, 0.14, 0.03) * tip;
	NORMAL = n;
}
