shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled;

// Rising spray/mist billboard: soft radial falloff * scrolling noise, fades with height.

varying vec2 v_uv;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1,0,0)), f.x),
			mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x),
			mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p, int oct) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= oct) break;
		s += a * vnoise(p);
		p = p * 2.11 + vec3(4.4);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_uv = UV;
}

void fragment() {
	// vertical band falloff (sphere UVs) * scrolling noise
	float band = smoothstep(0.0, 0.35, v_uv.y) * smoothstep(1.0, 0.55, v_uv.y);
	float n = fbm(vec3(v_uv * 3.5 + vec2(0.0, -TIME * 0.35), TIME * 0.25), 3);
	float a = band * smoothstep(0.25, 0.75, n + 0.2) * 0.07;
	ALBEDO = vec3(0.92, 0.95, 0.98);
	ALPHA = a;
}
