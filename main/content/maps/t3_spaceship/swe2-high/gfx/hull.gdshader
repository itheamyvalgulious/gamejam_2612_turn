// hull.gdshader — exterior plating. UV in metres (arc-length mapped).
// Vertex COLOR: r = part seed, g = 0 at bow / 1 at stern (v param), a = wear.
shader_type spatial;
// cull_disabled: the hull is an analytic shell — top-cap quads land on both
// winding conventions and half of them get culled; interior never sees
// inside surfaces anyway since the inner shell occludes them
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://gfx/common.gdshaderinc"

uniform vec3 base : source_color = vec3(0.46, 0.48, 0.51);
uniform vec3 dark : source_color = vec3(0.30, 0.31, 0.34);
uniform vec3 stripe_col : source_color = vec3(0.75, 0.30, 0.12);
uniform float seed = 0.0;

varying vec4 vcol;

void vertex() { vcol = COLOR; }

void fragment() {
	vec2 uv = UV;   // x: around circumference, y: along hull
	float s = seed;
	float t = clamp(vcol.g, 0.0, 1.0);   // sternward coordinate

	// two-scale panel system, staggered
	vec2 cid; vec2 f; float rnd;
	float seam = panels(uv, vec2(3.8, 6.0), 0.0, s, cid, f, rnd);
	// staggered half-panels
	vec2 cid2; vec2 f2; float rnd2;
	float seam2 = panels(uv + vec2(1.9, 3.0), vec2(1.9, 6.0), 0.0, s + 4.0, cid2, f2, rnd2) * 0.5;
	seam = max(seam, seam2 * 0.6);

	// albedo bands: darker band near stern equipment zone + waterline stripe
	vec3 col = base * (0.88 + rnd * 0.24);
	col = mix(col, dark, smoothstep(0.75, 0.9, t) * 0.7);
	// broad accent stripe
	float band = stripe(abs(fract(uv.x / 21.0 + 0.31) - 0.5) * 21.0, 0.5, 0.1);
	col = mix(col, stripe_col, band * 0.55);

	// panel tint variation + subtle weathering streaks running bow->stern
	col *= 1.0 - fbm(vec2(uv.x * 1.8, uv.y * 0.3) + s, 4) * 0.14;
	col *= 1.0 - fbm(vec2(uv.x * 7.0, uv.y * 0.5), 3) * 0.08;   // fine soot streaks
	// edge grime accumulates on seams
	col *= 1.0 - seam * 0.45;

	// rivets every ~1.3 m inside panels
	float rv = rivets(uv + 0.4, 2.6, 0.018) * (1.0 - seam);
	col = mix(col, col * 1.1, rv * 0.4);

	float rough = 0.55 + rnd * 0.15 + seam * 0.35;
	float h = (1.0 - seam) * 0.8 + rv * 0.2 + fbm(uv * 9.0, 3) * 0.06;

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.45, 0.9);
	METALLIC = 0.08;
	SPECULAR = 0.35;
	NORMAL = bumpn(NORMAL, VERTEX, h, 0.0);
}
