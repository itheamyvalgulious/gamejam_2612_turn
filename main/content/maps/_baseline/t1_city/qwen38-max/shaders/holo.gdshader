shader_type spatial;
render_mode blend_add, cull_disabled;
// Holographic billboard: animated gradient art, scanlines, glitch bands.
varying vec2 vmeta;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vmeta = UV2;
}

void fragment() {
	float sd = floor(vmeta.x + 0.5);
	vec2 p = UV;
	float t = TIME * 0.35;
	// base flowing gradient
	float w = sin(p.y * 6.0 + t * 2.0 + sin(p.x * 4.0 - t) * 1.5);
	vec3 c1 = vec3(0.1, 0.8, 1.0);
	vec3 c2 = vec3(1.0, 0.15, 0.6);
	vec3 col = mix(c1, c2, 0.5 + 0.5 * w);
	// rotating rings
	vec2 q = p - 0.5;
	float r = length(q);
	float ring = smoothstep(0.02, 0.0, abs(sin(r * 24.0 - t * 3.0))) * (1.0 - smoothstep(0.3, 0.5, r));
	col += vec3(0.6, 0.9, 1.0) * ring * 0.8;
	// scanlines
	col *= 0.75 + 0.25 * sin(p.y * 320.0 + TIME * 12.0);
	// glitch bands
	float gb = floor(p.y * 14.0 + floor(TIME * 5.0) * 0.61);
	float gshift = step(0.86, hash21(vec2(gb, floor(TIME * 5.0)))) * 0.12;
	col = mix(col, col.gbr, step(0.9, hash21(vec2(gb * 3.1, 1.0))) * 0.7);
	col += gshift;
	// edge fade
	float edge = smoothstep(0.0, 0.06, p.x) * smoothstep(1.0, 0.94, p.x) *
			smoothstep(0.0, 0.06, p.y) * smoothstep(1.0, 0.94, p.y);
	ALBEDO = vec3(0.0);
	EMISSION = col * edge * 1.6;
	ALPHA = edge * 0.9;
}
