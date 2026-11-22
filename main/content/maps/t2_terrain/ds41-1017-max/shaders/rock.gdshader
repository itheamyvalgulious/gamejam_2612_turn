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
		p = p * 2.04 + vec2(9.1, 4.3);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = wpos;
	vec3 n = normalize(wnrm);
	float h = p.y;
	float band = h * 0.55 + fbm3(p.xz * 0.22) * 2.4;
	float bf = fract(band);
	vec3 r1 = vec3(0.115, 0.118, 0.118);
	vec3 r2 = vec3(0.225, 0.220, 0.205);
	vec3 r3 = vec3(0.180, 0.155, 0.125);
	vec3 col = mix(r1, r2, smoothstep(0.15, 0.8, bf) * 0.55);
	col = mix(col, r3, smoothstep(0.6, 0.95, fract(band * 0.23 + 0.4)) * 0.4);
	float grain = fbm3(p.xz * 1.3 + p.y * 0.8);
	col *= 0.75 + 0.5 * grain;
	float crack = 1.0 - smoothstep(0.0, 0.12, abs(vnoise(p.xz * 0.9 + p.y * 0.3) - 0.5));
	col *= 0.62 + 0.38 * smoothstep(0.02, 0.16, abs(fbm3(p.xz * 0.8) - 0.5) + 0.02);
	float moss = smoothstep(0.55, 0.8, fbm3(p.xz * 0.35 + 6.0)) * smoothstep(0.55, 0.85, n.y);
	col = mix(col, vec3(0.075, 0.135, 0.035), moss * 0.7);
	float snow = smoothstep(0.55, 0.82, n.y) * smoothstep(430.0, 530.0, h) * smoothstep(0.35, 0.6, fbm3(p.xz * 0.25));
	col = mix(col, vec3(0.82, 0.87, 0.94), snow * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.16;
	// strong surface bump
	vec3 tg;
	vec3 bt;
	vec2 uv;
	if (abs(n.y) > 0.55) { tg = vec3(1,0,0); bt = vec3(0,0,1); uv = p.xz; }
	else if (abs(n.x) > abs(n.z)) { tg = vec3(0,0,1); bt = vec3(0,1,0); uv = p.zy; }
	else { tg = vec3(1,0,0); bt = vec3(0,1,0); uv = p.xy; }
	float e = 0.15;
	float d0 = fbm3(uv * 2.2) + 0.5 * fbm3(uv * 7.0);
	float du = fbm3((uv + vec2(e, 0.0)) * 2.2) + 0.5 * fbm3((uv + vec2(e, 0.0)) * 7.0);
	float dv = fbm3((uv + vec2(0.0, e)) * 2.2) + 0.5 * fbm3((uv + vec2(0.0, e)) * 7.0);
	vec3 nb = tg * ((du - d0) / e) + bt * ((dv - d0) / e);
	vec3 n2 = normalize(n - nb * 0.22);
	NORMAL = normalize((VIEW_MATRIX * vec4(n2, 0.0)).xyz);
}
