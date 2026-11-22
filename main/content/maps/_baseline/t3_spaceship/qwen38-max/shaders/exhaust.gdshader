shader_type spatial;
render_mode unshaded, cull_disabled, specular_disabled, blend_add;

// Engine exhaust plume: additive cone, noise flicker, blue-white core to cyan edge.

uniform vec3 u_core = vec3(0.75, 0.88, 1.0);
uniform vec3 u_edge = vec3(0.25, 0.55, 1.0);
uniform float u_gain = 2.6;
uniform float u_speed = 5.0;
uniform float u_len = 20.0;

varying vec3 v_uv;

void vertex() {
	v_uv = vec3(UV, 0.0);
}

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.27);
	return fract(p.x * p.y * 95.43);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.11 + vec2(5.3, 1.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	// UV.x = around, UV.y = along (0 at nozzle, 1 at tip)
	float along = clamp(UV.y / u_len, 0.0, 1.0);
	float fade = pow(max(1.0 - along, 0.0), 1.7);
	float turb = fbm(vec2(UV.x * 5.0, along * 9.0 - TIME * u_speed));
	float streak = fbm(vec2(UV.x * 17.0, along * 3.0 - TIME * u_speed * 1.6));
	float core = pow(max(1.0 - abs(along - 0.06) * 1.2, 0.0), 2.0) * (0.7 + 0.3 * turb);
	vec3 col = mix(u_edge, u_core, clamp(core + turb * 0.4 * fade + streak * 0.3, 0.0, 1.0));
	float i = fade * (0.35 + 0.65 * turb) * (0.75 + 0.5 * streak);
	// view-facing softening: thinner at silhouette
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	i *= mix(0.35, 1.0, facing);
	ALBEDO = vec3(0.0);
	EMISSION = col * i * u_gain;
}
