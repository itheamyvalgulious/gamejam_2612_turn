shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

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
float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.02 + vec2(5.3, 1.9);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	if (!FRONT_FACING) { n = -n; }
	float h = wpos.y;
	float slope = 1.0 - clamp(abs(n.y), 0.0, 1.0);
	float snow_line = 280.0 + 55.0 * fbm3(wpos.xz * 0.0008);
	snow_line += 85.0 * (fbm3(wpos.xz * 0.006 + wpos.y * 0.012 + 3.0) - 0.5);
	float patch = 0.5 + 0.5 * fbm3(wpos.xz * 0.020 + wpos.y * 0.03 + 7.0);
	float snow = smoothstep(snow_line, snow_line + 90.0, h) * smoothstep(0.82, 0.42, slope + (patch - 0.5) * 0.22);
	snow *= mix(1.0, smoothstep(0.28, 0.72, patch), 0.75);
	vec3 rock = mix(vec3(0.13, 0.17, 0.22), vec3(0.26, 0.29, 0.33), fbm3(wpos.xz * 0.004));
	vec3 col = mix(rock, vec3(0.62, 0.70, 0.80), snow * 0.85);
	// distance haze toward the sky
	float dist = distance(wpos, CAMERA_POSITION_WORLD);
	col = mix(col, vec3(0.52, 0.60, 0.72), clamp((dist - 1500.0) / 6000.0, 0.0, 0.78));
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
}
