shader_type spatial;
render_mode cull_back;

// Twist-tower skin: the same window-grid language as the city facades,
// but driven by world height (one row per real floor) so the corkscrew
// reads as genuine floors, not texture noise.

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec3 base = COLOR.rgb;
	// horizontal window band every floor (3.3 m); a thin column of
	// mullions every ~2.4 m along the face's horizontal axis
	vec3 an = abs(wnorm);
	float across = (an.x > an.z) ? wpos.z : wpos.x;
	float rowf = fract(wpos.y / 3.3);
	float band = smoothstep(0.18, 0.24, rowf) * smoothstep(0.82, 0.76, rowf);
	float colf = fract(across / 2.4);
	float pane = step(0.12, colf) * step(colf, 0.88);
	float win = band * pane;
	vec2 ci = vec2(floor(across / 2.4), floor(wpos.y / 3.3));
	float lit = h21(ci + 17.0);
	float litwin = win * step(0.6, lit);
	// diagonal spandrel seam — the floor plates' rotation telegraphs
	// as a slowly rising line up the facade
	float seam = smoothstep(0.94, 1.0, fract((wpos.y * 0.18 + across * 0.02)));
	base *= 1.0 - seam * 0.2;

	ALBEDO = mix(base, base * 0.35, win);
	ROUGHNESS = 0.5;
	SPECULAR = 0.5;
	float warm = h21(ci + 31.0);
	vec3 litcol = mix(vec3(1.0, 0.7, 0.35), vec3(0.7, 0.85, 1.0), step(0.75, warm));
	EMISSION = litcol * litwin * (0.4 + 0.5 * h21(ci + 43.0));
	// crown face glows magenta
	float crown = step(196.0, wpos.y);
	EMISSION += vec3(0.95, 0.3, 0.6) * crown;
}
