shader_type spatial;
render_mode cull_back;

varying vec3 wpos;
varying vec2 fuv;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	fuv = UV;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// gravel tar + HVAC boxes + parapet rim — dark so it never reads
	// as a lit cap
	vec3 base = COLOR.rgb * 0.38;
	float gr = h21(floor(fuv * 40.0));
	// fade gravel noise with footprint — same speckle treatment as
	// the facade; distant roofs must read as flat tar, not dither
	float gr_lod = 1.0 - smoothstep(0.25, 0.8, fwidth(fuv.x * 40.0));
	base *= 1.0 - (1.0 - (0.80 + gr * 0.35)) * gr_lod;
	float rim = max(step(0.94, fuv.x) + step(fuv.x, 0.06),
		step(0.94, fuv.y) + step(fuv.y, 0.06));
	base *= 1.0 - rim * 0.25;
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	METALLIC = 0.0;
}
