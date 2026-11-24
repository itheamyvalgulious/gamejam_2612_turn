// Arena puddle: thin dark water film with rain rings, keeps mirror-ish neon
// reflections but far darker than open water (so puddles read as holes in the
// asphalt instead of pale patches).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 deep_col : source_color = vec3(0.006, 0.008, 0.012);
uniform vec3 sheen_col : source_color = vec3(0.02, 0.035, 0.045);
uniform float wetness : hint_range(0.0, 1.0) = 0.9;
uniform float ripple = 1.0;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	// 雨点涟漪：随机相位、扩散的环
	vec2 cell = floor(p * 2.3);
	vec2 fp = fract(p * 2.3) - 0.5;
	float ph = fract(t * 1.15 + h12(cell) * 7.0);
	float ring = sin((length(fp) - ph * 0.42) * 46.0) * smoothstep(0.42, 0.0, abs(length(fp) - ph * 0.42)) * (1.0 - ph);
	float h = vnoise(p * 0.7 + t * 0.05) * 0.35 + ring * 0.12 * wetness * ripple;
	vec3 nw = normalize(vec3(dFdx(h) * 0.6, 1.0, dFdy(h) * 0.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// 深色水膜：压暗但抬出纯黑；掠射角用 fresnel 加一层 palette 天光，读作"水面"而不是"洞"
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = deep_col * (0.85 + 0.3 * vnoise(p * 3.1)) + vec3(0.016, 0.021, 0.024);
	METALLIC = 0.12;
	ROUGHNESS = clamp(0.075 + 0.05 * (1.0 - ring) + 0.03 * vnoise(p * 9.0), 0.05, 0.4);
	SPECULAR = 0.62;
	EMISSION = sheen_col * (0.16 + 0.85 * fres) * (0.75 + 0.25 * ring);
}
