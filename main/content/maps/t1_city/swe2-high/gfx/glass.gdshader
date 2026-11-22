shader_type spatial;
render_mode cull_back, blend_mix;

// Curtain-wall glass: reflective panes with interior parallax — a fake
// room depth (floor slab + furniture silhouette) so windows don't look
// like flat stickers up close.

varying vec3 wpos;
varying vec3 wnorm;
varying vec2 fuv;
varying vec4 custom;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	fuv = UV;
	custom = INSTANCE_CUSTOM;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	float seed = custom.r * 997.0;
	float floors = max(custom.g, 1.0);
	float zone = custom.b;
	vec3 an = abs(wnorm);
	float across = (an.x > an.z) ? wpos.z : wpos.x;
	float cols = floor(6.0 + h21(vec2(seed, 1.0)) * 10.0);
	float col_w = 2.6 + h21(vec2(seed, 3.0)) * 1.4;
	vec2 cell = vec2(across / col_w, fuv.y * floors);
	vec2 cf = fract(cell);
	vec2 ci = floor(cell);
	// footprint in cells — discard the pane plane entirely once the
	// window grid goes sub-pixel; the wall shader takes over with a
	// blended average so there's no speckle band where glass fades
	float fp = max(fwidth(cell.x), fwidth(cell.y));
	if (fp > 0.85) { discard; }
	float lod = 1.0 - smoothstep(0.45, 0.85, fp);
	float win = step(0.22, cf.x) * step(cf.x, 0.78) *
		step(0.30, cf.y) * step(cf.y, 0.70);
	if (win < 0.5) { discard; }   // no pane fragment outside apertures
	vec2 pane = vec2(cf.x, cf.y);
	float mull = step(abs(pane.x - 0.40), 0.016) +
		step(abs(pane.x - 0.60), 0.016) +
		step(abs(pane.y - 0.55), 0.03);
	win *= 1.0 - clamp(mull, 0.0, 1.0) * 0.85;

	// interior parallax: pretend the room is 0.35 of the cell deep —
	// view direction shifts what's visible through the pane
	vec3 vd = normalize(CAMERA_POSITION_WORLD - wpos);
	float par = clamp(dot(vd, wnorm), 0.0, 1.0);
	vec2 room_uv = cf + vd.xz * 0.18;

	// interior scene: back wall + furniture blobs at parallax depth
	float lit = h21(ci + vec2(seed, 5.0));
	float room_lit = step(0.72, lit);
	vec3 interior = mix(vec3(0.04, 0.05, 0.08),
		vec3(0.9, 0.75, 0.5) * (0.5 + 0.5 * h21(ci + seed)),
		room_lit * win);
	// floor slab line inside the window
	float slab = smoothstep(0.46, 0.44, room_uv.y) * smoothstep(0.34, 0.36, room_uv.y);
	interior *= 1.0 - slab * 0.5;
	// furniture silhouettes: dark blobs against the lit wall
	float furn = h21(ci + vec2(seed, 11.0)) * room_lit;
	if (furn > 0.5 && room_uv.y < 0.42 && room_uv.x > 0.3 && room_uv.x < 0.7)
		interior *= 0.35;

	// pane reflections: sky sheen + neighbouring tower streak
	float fres = pow(1.0 - abs(dot(vd, wnorm)), 3.0);
	vec3 refl = mix(vec3(0.05, 0.08, 0.12), vec3(0.4, 0.5, 0.65), fres);

	// pane fragments only — the wall carries the dark facade; glass
	// exists solely as lit/reflective pane faces inside the apertures.
	// Dark panes stay dark — a curtain wall reads as glazing bands,
	// not as a glowing cage around the tower
	ALBEDO = mix(interior, refl, 0.45);
	ALPHA = win * (0.35 + room_lit * 0.55) * lod;
	ROUGHNESS = 0.15;
	SPECULAR = 0.7;
	METALLIC = 0.2;
	EMISSION = interior * room_lit * 0.42;
}
