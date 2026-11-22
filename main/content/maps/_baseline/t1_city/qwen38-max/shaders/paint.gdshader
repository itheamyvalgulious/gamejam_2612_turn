shader_type spatial;
render_mode blend_mix, depth_draw_opaque;
uniform vec4 haze_col : source_color = vec4(0.055, 0.04, 0.105, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.5;
varying float vdist;
// Road paint markings: COLOR.rgb = paint color, worn by noise.

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float wear = 0.5 + 0.5 * vnoise(UV * vec2(1.5, 3.0));
	wear = smoothstep(0.25, 0.75, wear);
	ALBEDO = COLOR.rgb * (0.5 + 0.4 * wear);
	ROUGHNESS = 0.55;
	ALPHA = 0.35 + 0.65 * wear;
	EMISSION = COLOR.rgb * 0.04;
	// aerial perspective haze (Environment fog replacement)
	float hz = 1.0 - exp(-vdist * haze_den);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis, hz);
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

