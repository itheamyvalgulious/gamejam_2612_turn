shader_type spatial;
render_mode specular_schlick_ggx;

// Bar grating / trench covers (engine deck, catwalks). Bars run along world X.
// u_under tints the "void" beneath (reactor glow).

uniform vec3 u_bar = vec3(0.2, 0.205, 0.22);
uniform vec3 u_under = vec3(0.02, 0.018, 0.015);
uniform float u_under_gain = 1.0;
uniform float u_rust = 0.3;
uniform float u_pitch = 0.22;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

void fragment() {
	vec3 n = normalize(wnorm);
	vec3 camw = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dfade = 1.0 - smoothstep(4.0, 14.0, distance(wpos, camw));
	// grating pattern in the horizontal plane perpendicular to bars (bars along x)
	float across = fract(wpos.z / u_pitch);
	float bar = smoothstep(0.0, 0.08, across) * smoothstep(1.0, 0.62, across);
	// cross-member every 0.9m
	float crossm = 1.0 - smoothstep(0.03, 0.05, abs(fract(wpos.x / 0.9) - 0.5) - 0.44);
	bar = max(bar, crossm * 0.9);
	float rust = smoothstep(0.6, 0.9, vnoise(wpos.xz * 1.4)) * u_rust;
	float oil = smoothstep(0.72, 0.95, vnoise(wpos.xz * 0.5 + 9.0)) * u_rust;

	vec3 barcol = u_bar * COLOR.rgb * (0.8 + 0.4 * vnoise(wpos.xz * 30.0));
	barcol = mix(barcol, vec3(0.34, 0.21, 0.12), rust * 0.5);
	barcol = mix(barcol, vec3(0.03, 0.025, 0.02), oil * 0.8);
	// fake top-lit highlight on bar shoulders
	float shoulder = smoothstep(0.0, 0.12, across) * smoothstep(0.62, 0.5, across);
	barcol *= (1.0 + shoulder * 0.25);

	vec3 undercol = u_under * (0.5 + 0.5 * vnoise(wpos.xz * 3.0 + 2.0)) * u_under_gain;
	bar = mix(0.55, bar, dfade);
	vec3 alb = mix(undercol, barcol, bar);

	ALBEDO = clamp(alb, vec3(0.0), vec3(2.0));
	ROUGHNESS = clamp(0.5 - bar * 0.08 + rust * 0.25, 0.1, 0.95);
	METALLIC = 0.5 * bar;
	SPECULAR = 0.5;
	EMISSION = (1.0 - bar) * u_under * (u_under_gain - 1.0) * 0.55;
}
