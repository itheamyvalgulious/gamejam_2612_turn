// crate.gdshader — cargo containers: painted shell + stencil labels + dents.
// UV metres; COLOR.r = per-container seed drives colour/label.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://gfx/common.gdshaderinc"

uniform float seed = 0.0;

varying vec4 vcol;

void vertex() { vcol = COLOR; }

void fragment() {
	vec2 uv = UV;
	float s = seed + vcol.r * 100.0;
	float rnd = h11(s);

	// container paint colour: logistics palette
	vec3 paint = mix(
		mix(vec3(0.55, 0.20, 0.10), vec3(0.15, 0.35, 0.45), step(0.33, rnd)),
		mix(vec3(0.45, 0.45, 0.30), vec3(0.30, 0.32, 0.36), step(0.66, rnd)),
		step(0.66, rnd));
	vec3 col = paint;

	// corner castings & rails darkened
	vec2 cid; vec2 f; float r2;
	float seam = panels(uv, vec2(0.55, 0.7), 0.0, s, cid, f, r2);
	col = mix(col, col * 0.55, seam * 0.8);
	// corrugation
	float cor = sin(uv.x * 11.0) * 0.5 + 0.5;
	col *= 0.95 + cor * 0.05;
	float h = cor * 0.18 - seam * 0.4;

	// stencil label band: light block + dark glyph cells
	float band = stripe(abs(fract(uv.y / 0.9) - 0.5) * 0.9 - 0.0, 0.05, 0.01);
	if (band > 0.0 && h21(floor(uv * 8.0) + s) > 0.4) {
		vec2 g = floor(vec2(uv.x * 10.0, uv.y * 11.0));
		vec2 gf = fract(vec2(uv.x * 10.0, uv.y * 11.0));
		float glyph = step(0.35, h21(g + s)) * step(0.2, gf.x) * step(gf.x, 0.8) * step(0.25, gf.y) * step(gf.y, 0.75);
		col = mix(col, vec3(0.85), band * glyph * 0.8);
	}
	// hazard ticks on some boxes
	if (rnd > 0.82) {
		float hz = step(0.5, fract(uv.x * 9.0 + uv.y * 3.0));
		col = mix(col, mix(vec3(0.8, 0.6, 0.05), vec3(0.1), hz), stripe(abs(uv.y - 0.12), 0.06, 0.02) * 0.9);
	}

	// dent field + edge wear
	float dent = fbm(uv * 2.0 + s, 4);
	h -= smoothstep(0.6, 0.9, dent) * 0.4 * vcol.a;
	col *= 1.0 - smoothstep(0.6, 0.85, dent) * 0.25;
	float edge = smoothstep(0.42, 0.5, abs(f - 0.5).x) + smoothstep(0.42, 0.5, abs(f - 0.5).y);
	col = mix(col, vec3(0.4, 0.4, 0.4), edge * 0.3 * vcol.a);

	ALBEDO = col;
	ROUGHNESS = 0.45 + dent * 0.25;
	METALLIC = 0.2;
	SPECULAR = 0.3;
	NORMAL = bumpn(NORMAL, VERTEX, h, 0.8);
}
