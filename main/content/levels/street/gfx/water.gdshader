// Canal water: dark reflective surface, wind ripples, rain rings, neon sheen.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 1.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.9;
uniform vec3 deep_col : source_color = vec3(0.020, 0.055, 0.062);
uniform vec3 shallow_col : source_color = vec3(0.035, 0.10, 0.10);

varying vec3 wpos;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), u.x),
		mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p = p * 2.05 + vec2(11.3, 7.7);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// two scrolling wave layers + rain rings
	vec2 p = wpos.xz;
	float t = TIME;
	float w1 = fbm(p * 0.45 + vec2(t * 0.05, t * 0.03));
	float w2 = fbm(p * 1.6 - vec2(t * 0.09, t * 0.06));
	float h = w1 * 0.6 + w2 * 0.4;
	vec2 cell = floor(p * 1.8 - t * 0.3);
	vec2 fp = fract(p * 1.8 - t * 0.3) - 0.5;
	float rt = fract(t * 1.1 + h12(cell) * 7.0);
	float ring = sin((length(fp) - rt * 0.45) * 55.0) * smoothstep(0.45, 0.0, abs(length(fp) - rt * 0.45)) * (1.0 - rt);
	h += ring * 0.25 * wetness;

	vec3 nw = normalize(vec3(dFdx(h) * 0.5, 1.0, dFdy(h) * 0.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	vec3 alb = mix(deep_col, shallow_col, smoothstep(0.2, 0.9, h));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = alb;
	METALLIC = 0.92;
	ROUGHNESS = clamp(0.035 + 0.10 * h + 0.05 * fres, 0.02, 0.5);
	SPECULAR = 0.9;
	// faint self glow from canal lights
	EMISSION = vec3(0.02, 0.06, 0.075) * (0.4 + 0.8 * night) * (0.6 + 0.4 * h);
}