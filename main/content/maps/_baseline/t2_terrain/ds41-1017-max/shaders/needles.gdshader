shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

varying vec3 wpos;
varying vec3 wnrm;

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
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	if (!FRONT_FACING) { n = -n; }
	float v = vnoise(vec2(UV.x * 40.0, UV.y * 8.0));
	vec3 col = mix(vec3(0.035, 0.085, 0.045), vec3(0.10, 0.17, 0.075), v);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.18;
	BACKLIGHT = vec3(0.03, 0.08, 0.02);
	float snow = smoothstep(0.55, 0.85, n.y) * smoothstep(0.35, 0.75, vnoise(wpos.xz * 0.4));
	col = mix(col, vec3(0.82, 0.88, 0.94), snow * 0.55);
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
