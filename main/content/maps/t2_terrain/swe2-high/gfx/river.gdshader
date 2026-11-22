shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, blend_mix;

// River strip. Per-vertex: UV.x = across (0..1), UV.y = arc distance (m),
// UV2.x = downstream fraction t (0..1). COLOR.rg = encoded tangent (0..1).

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(11.7, 3.1);
		a *= 0.5;
	}
	return s;
}

varying vec3 wpos;
varying vec2 flow_dir;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 tang2 = (COLOR.rg - vec2(0.5)) * 2.0;
	flow_dir = tang2;
	vec3 tang = normalize(vec3(tang2.x, 0.0, tang2.y));
	float u = UV.x;
	float v = UV.y;
	// low-frequency swell only — short wavelengths alias into a zipper
	// at 1.5 m vertex spacing, so keep vertex motion slow and broad
	float amp = mix(0.35, 0.55, UV2.x);
	float p1 = v * 0.06 - TIME * 0.7 + u * 2.0;
	float p2 = v * 0.03 - TIME * 0.35 + u * 4.0;
	VERTEX.y += (sin(p1) * 0.25 + sin(p2) * 0.18) * amp;
	VERTEX.xz += tang.xz * (cos(p1) * 0.18 * amp);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float t = UV2.x;
	// metric-space flow: noise sampled in metres, not UV — the field
	// bends with the channel instead of stretching across a fixed grid
	vec2 tang2 = flow_dir;
	vec2 fwd = normalize(vec2(tang2.x, tang2.y));
	vec2 sdw = vec2(-fwd.y, fwd.x);
	// along-channel metres: project world offset onto the flow tangent
	// anisotropic flow field: compressed along-channel so stripes
	// stretch downstream, spread across for cross-current variation
	float s_along = dot(wpos.xz, fwd) * 0.16 - TIME * 0.5;
	float x_across = dot(wpos.xz, sdw) * 0.40;
	float streak = fbm(vec2(x_across * 0.6 + fbm(vec2(s_along, x_across)) * 2.5, s_along));
	float streak2 = fbm(vec2(x_across * 0.9 - s_along * 0.5, s_along * 1.4));
	// thin foam hugging the very banks — wide white rails read as a bug
	float bank = pow(1.0 - abs(u * 2.0 - 1.0), 2.5);
	// foam only on shoals + rapids — never a white rim at the banks
	float foam_edge = smoothstep(0.045, 0.0, u) + smoothstep(0.955, 1.0, u);
	float banknoise = fbm(vec2(u * 20.0, v * 0.8 + TIME * 1.4));
	float foam = foam_edge * (0.10 + 0.15 * banknoise);
	// exposed gravel bars — broken, drifting flecks not hard polygons;
	// a second high-frequency field chops each bar into fragments
	float shoal_base = fbm(vec2(dot(wpos.xz, sdw) * 0.30 + s_along * 0.4, s_along * 0.25 + 7.0));
	float shoal_frag = fbm(vec2(dot(wpos.xz, sdw) * 1.4, s_along * 1.1 + 3.0));
	// two thresholds carve shoal into broken blotches instead of
	// continuous polygons — wide blend band so edges dissolve
	float shoal = smoothstep(0.58, 0.88, shoal_base) *
		smoothstep(0.25, 0.65, shoal_frag) *
		smoothstep(0.95, 0.65, shoal_frag);
	float shoal_band = smoothstep(0.30, 0.45, u) * smoothstep(0.70, 0.55, u);
	// colour: clear blue-green upstream -> amber-green lowland
	vec3 col_up = vec3(0.03, 0.11, 0.14);
	vec3 col_low = vec3(0.05, 0.12, 0.09);
	vec3 base = mix(col_up, col_low, smoothstep(0.15, 0.85, t));
	base = mix(base * 0.72, base, smoothstep(0.0, 0.5, bank));
	float glint = pow(streak, 2.0) * 0.28;
	vec3 col = base + vec3(glint) + vec3(0.04, 0.07, 0.05) * streak2 * 1.4;
	// gravel shoals poke through — wet pebbles with speckle, not a void
	vec3 gravel = vec3(0.38, 0.33, 0.22) * (0.8 + fbm(vec2(u * 18.0, v * 1.5)) * 0.4);
	col = mix(col, gravel, shoal * shoal_band * 0.45);
	// foam at banks + river-mouth delta
	float mouth = smoothstep(0.70, 0.80, t);
	col = mix(col, vec3(0.78, 0.84, 0.82), clamp(foam + mouth * 0.35, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(0.85 + streak * 0.08 + foam * 0.12, 0.0, 1.0);
	ROUGHNESS = 0.85;
	SPECULAR = 0.10;
	METALLIC = 0.0;
	// noise-driven wave normal — 4–8 m facets catch the sky in patches
	vec3 tang = normalize(vec3(tang2.x, 0.0, tang2.y));
	vec3 bitan = vec3(-tang.z, 0.0, tang.x);
	float sn = dot(wpos.xz, fwd) * 0.10 - TIME * 1.2;
	float xn = dot(wpos.xz, sdw) * 0.55;
	float h0 = fbm(vec2(xn, sn));
	float hx = fbm(vec2(xn + 0.06, sn)) - h0;
	float hz = fbm(vec2(xn, sn + 0.06)) - h0;
	float amp = mix(0.8, 1.3, UV2.x);
	NORMAL = normalize(vec3(-bitan.x * hx * amp - tang.x * hz * amp,
		1.0, -bitan.z * hx * amp - tang.z * hz * amp));
}
