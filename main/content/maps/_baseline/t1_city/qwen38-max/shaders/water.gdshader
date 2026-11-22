shader_type spatial;
// River / harbor water: analytic sine-sum normals, fake neon city reflection.
uniform vec4 haze_col : source_color = vec4(0.055, 0.04, 0.105, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.5;
varying float vdist;
varying vec3 vworld;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vworld = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vworld.xz;
	float t = TIME * 0.6;
	// wave height field: 3 directional sines + detail
	float h = 0.0;
	vec2 grad = vec2(0.0);
	vec2 k1 = vec2(0.08, 0.05);
	vec2 k2 = vec2(-0.06, 0.09);
	vec2 k3 = vec2(0.13, -0.11);
	h += sin(dot(k1, p) * 3.0 + t * 1.7);
	grad += k1 * 3.0 * cos(dot(k1, p) * 3.0 + t * 1.7);
	h += 0.6 * sin(dot(k2, p) * 4.0 - t * 1.3);
	grad += k2 * 2.4 * cos(dot(k2, p) * 4.0 - t * 1.3);
	h += 0.35 * sin(dot(k3, p) * 7.0 + t * 2.3);
	grad += k3 * 2.45 * cos(dot(k3, p) * 7.0 + t * 2.3);
	vec3 n = normalize(vec3(-grad.x * 0.06, 1.0, -grad.y * 0.06));
	NORMAL = n;

	vec3 deep = vec3(0.008, 0.02, 0.028);
	ALBEDO = deep;
	ROUGHNESS = 0.07;
	METALLIC = 0.25;

	// fake reflection: sky gradient + neon streak columns from the city
	float fr = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	float fres = clamp(0.25 + 0.75 * fr, 0.0, 1.0);
	vec3 skyref = mix(vec3(0.05, 0.03, 0.09), vec3(0.14, 0.08, 0.24), fres);
	float colid = floor(p.x / 47.0 + hash11(floor(p.y / 90.0)) * 3.0);
	vec3 neon = mix(vec3(1.0, 0.3, 0.55), vec3(0.25, 0.85, 1.0), hash11(colid));
	neon = mix(neon, vec3(1.0, 0.7, 0.2), step(0.75, hash11(colid * 3.7)));
	float streak = smoothstep(0.55, 0.95, sin(p.x * 0.35 + hash11(colid) * 9.0)) *
			(0.4 + 0.6 * sin(p.y * 0.8 + t * 2.0 + h * 2.0));
	streak = max(streak, 0.0) * 0.5;
		float ripple = 0.55 + 0.45 * sin(p.y * 1.7 + t * 1.4 + h * 1.5);
	EMISSION = skyref * (0.10 + 0.5 * fres) * ripple + neon * streak * 1.3 * (0.3 + 0.7 * fres);

	// aerial perspective haze (Environment fog replacement)
	float hz = 1.0 - exp(-vdist * haze_den);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis, hz);
}
