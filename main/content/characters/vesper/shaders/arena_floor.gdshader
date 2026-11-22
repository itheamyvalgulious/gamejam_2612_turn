shader_type spatial;
// Arena floor: machined graphite with an emissive combat grid, concentric
// range rings, and a soft amber pool under the fighter.  All procedural.
render_mode cull_back;

uniform vec4 base_color : source_color = vec4(0.010, 0.014, 0.022, 1.0);
uniform vec4 line_color : source_color = vec4(0.28, 0.55, 1.0, 1.0);
uniform vec4 cool_color : source_color = vec4(0.14, 0.36, 1.0, 1.0);
uniform float grid_glow = 0.28;
uniform float arena_radius = 16.0;

varying vec3 wpos;

float grid_line(vec2 p, float spacing) {
	vec2 q = p / spacing;
	vec2 d = abs(fract(q - 0.5) - 0.5) / max(fwidth(q), vec2(0.0001));
	float m = min(d.x, d.y);
	return 1.0 - smoothstep(0.0, 1.4, m);
}

float ring_line(float r, float spacing) {
	float q = r / spacing;
	float d = abs(fract(q - 0.5) - 0.5) / max(fwidth(q), 0.0001);
	return 1.0 - smoothstep(0.0, 1.6, d);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float r = length(p);
	float radial_fade = 1.0 - smoothstep(arena_radius, 46.0, r);
	float inner = 1.0 - smoothstep(3.0, arena_radius, r);

	float fine = grid_line(p, 1.0);
	float major = grid_line(p, 5.0);
	float rings = ring_line(r, 4.0);
	float outer_ring = 1.0 - smoothstep(0.0, 0.10, abs(r - arena_radius));
	float inner_ring = 1.0 - smoothstep(0.0, 0.085, abs(r - 7.6));
	float core_ring = 1.0 - smoothstep(0.0, 0.07, abs(r - 2.2));

	float glow = (fine * 0.10 + major * 0.55 + rings * 0.18) * radial_fade;
	glow += outer_ring * 1.6 + inner_ring * 0.7 + core_ring * 0.5;
	glow += 0.10 * exp(-r * 0.16);

	// Braking scars: strong radial wear lines near the center.
	float ang = atan(p.y, p.x);
	float scars = pow(max(0.0, sin(ang * 12.0 + 0.6)), 30.0) * (1.0 - smoothstep(1.0, 9.0, r));
	glow += scars * 0.10;

	vec3 col = base_color.rgb;
	col += vec3(0.020, 0.023, 0.030) * major;
	float brushed = 0.5 + 0.5 * sin(p.x * 2.3 + sin(p.y * 0.35) * 3.0);
	col *= 0.88 + 0.18 * brushed;
	// faint cool strip light reflected from the arena rim
	col += cool_color.rgb * 0.015 * (1.0 - inner) * (0.4 + 0.6 * brushed);

	ALBEDO = col;
	EMISSION = line_color.rgb * glow * grid_glow;
	METALLIC = 0.72;
	ROUGHNESS = 0.24 + 0.12 * fine;
}