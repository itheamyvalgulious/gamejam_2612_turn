shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// The fall as a real volume.  The camera ray is marched through a box that
// contains the curtain; density is built from vertically stretched turbulence
// whose cross-section narrows at the lip and tears apart toward the impact.
// Everything (silhouette, holes, thickness, bottom burst) comes from the same
// field, so nothing can tile or band.

uniform vec3 bmin = vec3(-244.0, 291.0, -236.0);
uniform vec3 bmax = vec3(-178.0, 502.0, -184.0);
uniform vec3 top_pt = vec3(-228.5, 500.0, -231.0);
uniform vec3 bot_pt = vec3(-203.4, 292.4, -198.0);
uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform sampler2D sheet_tex : filter_linear_mipmap, repeat_enable;
uniform float sigma = 0.085;
uniform float steps = 30.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float exposure = 1.0;
uniform float mist_gain = 0.55;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float clamp01(float v) { return clamp(v, 0.0, 1.0); }
float sstep(float a, float b, float x) { return smoothstep(a, b, x); }

float noise3(vec3 p) {
	return texture(noise_tex, p).r;
}

// ---- curtain coordinate frame -------------------------------------------
// k = 0 at the lip, 1 at the impact
void frame(float y, out float k, out float cx, out float cz, out float w) {
	k = clamp01((top_pt.y - y) / max(top_pt.y - bot_pt.y, 1.0));
	float ky = pow(k, 1.0);
	cx = mix(top_pt.x, bot_pt.x, pow(k, 0.92));
	cz = mix(top_pt.z, bot_pt.z, pow(k, 0.55));
	w = mix(27.0, 49.0, pow(k, 0.75));
	// the jet bows forward as it falls
	cz += sin(k * 3.1 + 0.6) * 1.8 * k;
}

float density(vec3 p, out float spray) {
	float k;
	float cx;
	float cz;
	float w;
	frame(p.y, k, cx, cz, w);
	spray = 0.0;
	if (k < -0.02 || k > 1.02) return 0.0;

	// cross-section: a slab whose thickness grows with the fall
	float u = (p.x - cx) / (w * 0.5);
	float dv = p.z - cz;
	float th = mix(0.9, 2.4, pow(k, 0.8));
	// near the impact the whole thing balloons into a cloud
	float puff = sstep(0.86, 1.0, k);
	th += puff * 4.0;
	float sz = sstep(th, th * 0.25, abs(dv));
	// edges wobble and fray; the lip stays a clean arc
	float wob = (noise3(vec3(u * 1.1, p.y * 0.016, 3.7)) - 0.5) * 1.0;
	float eu = sstep(1.0, 0.60, abs(u) + wob * 0.26 * (0.6 + k));
	if (eu <= 0.0 || sz <= 0.0) return 0.0;

	// ---- turbulence: streaks stretched along the fall
	vec3 q1 = vec3(u * 0.19 + 0.31, p.y * 0.0011, dv * 0.020 + 11.0);
	vec3 q2 = vec3(u * 0.58 + 0.77, p.y * 0.0042, dv * 0.055 + 3.0);
	vec3 q3 = vec3(u * 1.70 + 0.13, p.y * 0.0140, dv * 0.140 + 7.0);
	float n1 = noise3(q1);
	float n2 = noise3(q2);
	float n3 = noise3(q3);
	float nf = n1 * 0.52 + n2 * 0.33 + n3 * 0.15;
	// ---- strand field: phase-warped bands give long ribbons of water whose
	// width wanders; no tiling, no isolated islands.
	float warp = (noise3(vec3(u * 0.55, p.y * 0.0035, 1.7)) - 0.5) * 2.0;
	float warp2 = (noise3(vec3(u * 1.70, p.y * 0.0120, 5.1)) - 0.5) * 2.0;
	float ph = u * 62.0 + warp * 3.4 + warp2 * 1.3 + dv * 0.85;
	float band = 0.5 + 0.5 * sin(ph);
	float ribbon = sstep(0.22, 0.80, band);
	// ribbons thin and thicken as they fall
	ribbon *= 0.45 + 0.85 * sstep(0.20, 0.80, noise3(vec3(u * 0.9, p.y * 0.0055, 9.3)));
	// a wider second family keeps the mass from looking combed
	float ph2 = u * 19.0 + warp * 2.2 + dv * 0.35;
	float wide = sstep(0.10, 0.72, 0.5 + 0.5 * sin(ph2));
	float dep = sstep(0.22, 0.82, noise3(vec3(u * 1.1, p.y * 0.004, dv * 0.55 + 21.0)));
	float n = (ribbon * 0.78 + wide * 0.42) * (0.55 + 0.85 * dep) + nf * 0.22;

	// aerated break-up grows downward; the lip is a coherent film
	float breakk = sstep(0.05, 0.62, k);
	// continuous strand density: no threshold, so no isolated cut-out shapes
	float body = sstep(0.44, 0.88, n * 1.06);
	body *= 0.40 + 0.95 * sstep(0.25, 0.80, n2 * 0.6 + n3 * 0.4);
	// the film at the lip
	float film = sstep(0.12, 0.0, k);
	body = mix(body, 0.95, film * 0.9);

	// the base bursts into spray: low-density cloud, wide
	spray = puff * (0.35 + 0.65 * n1);
	float dens = body * eu * sz;
	// dissolve into the pool instead of cutting on a straight line
	dens *= sstep(1.06, 0.93, k);
	dens *= mix(1.0, 0.28, puff * 0.75);
	dens += spray * 0.075 * eu * sz;
	return dens;
}

vec3 water_col(vec3 p, float k, float dens) {
	vec3 deep = vec3(0.105, 0.145, 0.180);
	vec3 mid = vec3(0.60, 0.67, 0.70);
	vec3 aer = vec3(0.96, 0.975, 0.965);
	vec3 c = mix(deep, mid, sstep(0.02, 0.35, dens));
	c = mix(c, aer, sstep(0.30, 0.85, dens));
	// the base is all whitewater
	c = mix(c, vec3(0.92, 0.95, 0.96), sstep(0.80, 1.0, k) * 0.55);
	return c * tint;
}

void fragment() {
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(wpos - ro);
	vec3 inv = 1.0 / max(abs(rd), vec3(1e-5)) * sign(rd);
	vec3 ta = (bmin - ro) * inv;
	vec3 tb = (bmax - ro) * inv;
	vec3 tmn = min(ta, tb);
	vec3 tmx = max(ta, tb);
	float t0 = max(max(max(tmn.x, tmn.y), tmn.z), 0.0);
	float t1 = min(min(tmx.x, tmx.y), tmx.z);
	if (t1 <= t0) discard;
	float len = t1 - t0;
	float dl = len / steps;

	// dither the start so banding never shows
	float jitter = 0.5;
	vec3 p = ro + rd * (t0 + dl * jitter);
	float T = 1.0;
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 40; i++) {
		if (float(i) >= steps || T < 0.02) break;
		float spray;
		float d = density(p, spray);
		if (d > 0.002) {
			// cheap self-shadow: is there water above this point?
			float ash;
			float above = density(p + vec3(0.0, 2.6, 0.0), ash);
			float lit = exp(-above * 2.2);
			float k;
			float cx;
			float cz;
			float w;
			frame(p.y, k, cx, cz, w);
			vec3 c = water_col(p, k, d) * (0.42 + 0.95 * lit);
			// spray scatters the sky into the volume
			c += vec3(0.55, 0.62, 0.68) * spray * mist_gain * 0.5;
			float a = 1.0 - exp(-d * dl * sigma);
			acc += T * a * c;
			T *= 1.0 - a;
		}
		p += rd * dl;
	}
	float alpha = 1.0 - T;
	if (alpha < 0.004) discard;
	ALBEDO = clamp(acc / max(alpha, 1e-4), 0.0, 4.0) * exposure;
	ALPHA = clamp(alpha, 0.0, 0.995);
	ROUGHNESS = 0.7;
}