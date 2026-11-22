shader_type spatial;
render_mode cull_disabled;

// Landmark material: clean structural surface with a faint scale
// gradient and panel seams — NO window grid (these are structures,
// not buildings).

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
	vec3 base = COLOR.rgb;
	// vertical weathering: darker at the base, catching sky at the rim
	float lift = clamp(wpos.y / 60.0, 0.0, 1.0);
	base *= 0.75 + lift * 0.4;
	// subtle panel seams every ~4 m so surfaces aren't featureless
	float seam = smoothstep(0.96, 1.0, fract(wpos.y / 4.0));
	base *= 1.0 - seam * 0.15;
	ALBEDO = base;
	ROUGHNESS = 0.85;
	// neon elements carry their own glow: a channel far above the
	// material's others flags a lit element (rail cyan, rim pink,
	// cables magenta, crown blade)
	float hi = max(COLOR.r, max(COLOR.g, COLOR.b));
	float lo = min(COLOR.r, min(COLOR.g, COLOR.b));
	float neon = step(0.30, hi - lo) * step(0.5, hi);
	// big glowing surfaces (rail beam, deck rims) blow out to a blank
	// white plate if every fragment emits the same — segment them into
	// running bands along the world axes so a lit surface reads as a
	// strip of panels, not a slab of light
	float along = max(abs(wpos.x), abs(wpos.z));
	float band_id = floor(along / 14.0);
	float seg = 0.62 + 0.38 * h21(vec2(band_id, 7.0));
	// soften segment edges so a narrow beam doesn't alias into grain
	float fseg = fract(along / 14.0);
	seg *= 0.85 + 0.15 * smoothstep(0.0, 0.12, fseg)
		* smoothstep(1.0, 0.88, fseg);
	EMISSION = base * neon * seg * 0.6;
}
