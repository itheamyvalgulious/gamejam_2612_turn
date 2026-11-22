shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

// Rock / boulder / ice-crystal material.
// Set the `ice` uniform to 1.0 for the snowfield ice clusters.

uniform vec3 rock_hi : source_color = vec3(0.46, 0.44, 0.40);
uniform vec3 rock_lo : source_color = vec3(0.30, 0.29, 0.27);
uniform vec3 snow_color : source_color = vec3(0.90, 0.93, 0.97);
uniform float snow_line = 120.0;
uniform float snow_soft = 35.0;
uniform float ice = 0.0;
uniform vec3 ice_color : source_color = vec3(0.62, 0.80, 0.92);
uniform float ice_glow = 0.25;

varying vec3 v_world;
varying float v_var;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_var = COLOR.g;
}

void fragment() {
	float n = fbm(v_world.xz * 0.35 + v_world.y * 0.1);
	vec3 alb = mix(rock_lo, rock_hi, n * 0.5 + 0.5);
	float snow = smoothstep(snow_line - snow_soft, snow_line + snow_soft, v_world.y);
	snow = max(snow, smoothstep(-360.0, -560.0, v_world.z) * 0.85);
	snow = clamp(snow, 0.0, 1.0);
	alb = mix(alb, snow_color, snow);

	if (ice > 0.5) {
		ALBEDO = ice_color;
		ROUGHNESS = 0.18;
		SPECULAR = 0.5;
		EMISSION = ice_color * ice_glow * (0.6 + 0.4 * v_var);
	} else {
		ALBEDO = alb;
		ROUGHNESS = 0.92;
		SPECULAR = 0.03;
		EMISSION = vec3(0.0);
	}
}
