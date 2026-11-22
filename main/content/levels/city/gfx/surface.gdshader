// Uber procedural surface shader.
// Every material in the city is expressed as maths evaluated in the fragment shader:
// no textures, no normal maps, no imported assets.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 1.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.85;
uniform float dirt : hint_range(0.0, 2.0) = 1.0;
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.26;
uniform float exposure_boost = 1.0;
uniform vec3 fog_col : source_color = vec3(0.24, 0.16, 0.3);

varying vec3 wpos;
varying vec3 wnrm;
varying vec2 suv;
varying vec4 par;  // decoded (mat, style, seed01, emissive)
varying vec3 vtint;

void vertex() {
	par = CUSTOM0 * 255.0;
	par.z /= 255.0;
	par.w /= 50.0;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	suv = UV;
	vtint = COLOR.rgb;
}

// ------------------------------------------------------------------ hashes
float h11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}
float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float h13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
vec2 h22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = h12(i);
	float b = h12(i + vec2(1.0, 0.0));
	float c = h12(i + vec2(0.0, 1.0));
	float d = h12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return s;
}

float fbm2(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 2; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(5.1, 13.7);
		a *= 0.5;
	}
	return s * 1.33;
}

// surface gradient bump mapping (no tangents required)
vec3 bump_map(vec3 n_world, vec3 p, float hgt, float strength) {
	vec3 dpx = dFdx(p);
	vec3 dpy = dFdy(p);
	vec3 r1 = cross(dpy, n_world);
	vec3 r2 = cross(n_world, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(hgt) * r1 + dFdy(hgt) * r2);
	return normalize(abs(det) * n_world - grad * strength);
}

// window field: returns rgb = window emissive, a = window mask, b via mask
// styled procedural facade for far LOD shell geometry
void facade_windows(vec2 uv, float style, float seedv, out vec3 emis, out float mask, out float frame) {
	// per-style bay / floor grammar
	vec2 bay = vec2(2.7, 3.6);
	float open_x = 0.46;   // glass width fraction of a bay
	float open_y = 0.46;   // glass height fraction of a floor
	float sill = 0.55;     // sill height (m) above floor line
	float frame_w = 0.10;  // mullion width (m)
	if (style > 0.5 && style < 1.5) { bay = vec2(1.62, 3.9); open_x = 0.94; open_y = 0.80; sill = 0.25; frame_w = 0.06; }
	if (style > 1.5 && style < 2.5) { bay = vec2(3.3, 3.25); open_x = 0.38; open_y = 0.42; sill = 0.75; frame_w = 0.14; }
	if (style > 2.5 && style < 3.5) { bay = vec2(3.6, 3.9); open_x = 0.62; open_y = 0.50; sill = 0.55; frame_w = 0.10; }
	if (style > 3.5 && style < 4.5) { bay = vec2(3.0, 3.7); open_x = 0.88; open_y = 0.30; sill = 1.05; frame_w = 0.05; }
	if (style > 4.5 && style < 5.5) { bay = vec2(1.4, 3.9); open_x = 0.82; open_y = 0.66; sill = 0.45; frame_w = 0.22; }
	if (style > 5.5) { bay = vec2(6.5, 5.2); open_x = 0.30; open_y = 0.20; sill = 3.2; frame_w = 0.08; }

	vec2 cell = uv / bay;
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	// window rect in cell space: sill offsets in metres
	float fy0 = sill / bay.y;
	float fy1 = clamp(fy0 + open_y, 0.0, 0.97);
	float fx0 = 0.5 - open_x * 0.5;
	float fx1 = 0.5 + open_x * 0.5;
	vec2 lo = vec2(fx0, fy0);
	vec2 hi = vec2(fx1, fy1);
	vec2 w = smoothstep(lo, lo + 0.006, f) * (1.0 - smoothstep(hi - 0.006, hi, f));
	mask = w.x * w.y;
	vec2 e = min(f, 1.0 - f);
	frame = (1.0 - smoothstep(frame_w / bay.x * 0.5, frame_w / bay.x, min(e.x, e.y))) * step(0.5, style);
	// recess depth shade: darker toward the inner edge
	float ex = min(f.x - lo.x, hi.x - f.x);
	float ey = min(f.y - lo.y, hi.y - f.y);
	float recess = smoothstep(0.0, 0.035, min(ex * bay.x, ey * bay.y));

	// window state
	float r = h12(id + vec2(seedv * 71.3, seedv * 13.7));
	float r2 = h12(id * 3.1 + vec2(seedv * 11.0));
	float r3 = h12(id * 7.7 + vec2(seedv * 3.0));
	float lr = lit_ratio * (0.25 + 1.5 * fract(seedv * 3.71 + 0.13));
	float lit = step(1.0 - lr, r);
	float flick = step(0.985, fract(TIME * 0.35 + r * 9.1));
	lit *= (1.0 - flick);
	// a few windows are pure black (empty rooms / screens off)
	float black = step(0.93, r3);
	lit *= (1.0 - black);

	vec3 warm = vec3(1.0, 0.70, 0.42);
	vec3 cool = vec3(0.52, 0.70, 0.94);
	vec3 neutral = vec3(0.86, 0.84, 0.76);
	vec3 c = mix(warm, neutral, step(0.56, r2));
	c = mix(c, cool, step(0.80, r2));
	c = mix(c, vec3(0.95, 0.30, 0.55), step(0.965, r3) * 0.55);
	float bright = 0.18 + 0.85 * r2;
	// interior occlusion: 1 = ceiling-lit top, blinds, curtains
	float g = clamp((f.y - lo.y) / max(hi.y - lo.y, 0.001), 0.0, 1.0);
	float grad = mix(0.08, 1.0, smoothstep(0.1, 1.0, g));
	float blind = step(0.62, r3);
	float stripes = mix(1.0, 0.35 + 0.65 * step(0.5, fract(g * 4.0 + r)), blind);
	float curtain = step(0.78, r2) * smoothstep(0.35, 0.0, min(f.x - lo.x, hi.x - f.x));
	grad *= stripes * (1.0 - curtain * 0.65);
	emis = c * lit * bright * grad * mix(0.22, 1.0, recess);
	// faint cold glass reflection on dark windows
	emis += vec3(0.030, 0.038, 0.055) * (1.0 - lit) * (0.25 + 0.75 * g) * recess;

	// ---- style-specific overlays
	if (style > 0.5 && style < 1.5) {
		// curtain wall: spandrel band + thin vertical mullions + uneven pane reflection
		float band = step(f.y, 0.22);
		mask *= (1.0 - band);
		float mull = 1.0 - smoothstep(0.015, 0.03, min(f.x, 1.0 - f.x));
		mask *= (1.0 - mull);
		emis *= (0.75 + 0.5 * h12(id * 5.3 + 2.0));
		emis += vec3(0.018, 0.022, 0.03) * (1.0 - lit) * (0.4 + 0.6 * f.y);
	} else if (style > 4.5 && style < 5.5) {
		// vertical fins: hard shadow stripes at bay edges
		float fin = smoothstep(0.08, 0.0, min(f.x, 1.0 - f.x));
		emis *= (1.0 - fin * 0.75);
		mask *= (1.0 - fin * 0.5);
	} else if (style > 5.5) {
		// industrial: small high windows, dusty
		emis *= 0.8;
	}
	// external AC unit under a fraction of punched windows
	float acm = step(0.94, h12(id * 1.7 + seedv * 13.0)) * step(style, 3.5) * step(0.5, style);
	// (masked area drawn by the caller as a dark box: encoded in emis negative? noop)
	// lintel shadow above every window group
	emis *= 1.0 - 0.5 * smoothstep(0.02, 0.0, hi.y - f.y);
	// sill highlight (thin bright line under the opening)
	emis += vec3(0.32, 0.34, 0.38) * smoothstep(0.010, 0.0, f.y - lo.y) * mask * 0.5;

	mask *= (1.0 - frame * 0.85);
}

void fragment() {
	int mid = int(par.x + 0.5);
	float sty = par.y;
	float styb = sty >= 50.0 ? sty - 50.0 : sty;
	float sd = par.z;
	float pemis = par.w;
	vec3 tint = vtint;
	vec3 n_w = normalize(wnrm);
	vec3 alb = tint;
	float rough = 0.6;
	float metal = 0.0;
	vec3 emis = vec3(0.0);
	float ao = 1.0;
	float alpha = 1.0;
	float hgt = 0.0;
	float bump = 0.0;
	vec2 uv = suv;

	// generic soot / rain streaks / mottling every material gets
	float streak = vnoise(vec2(uv.x * 2.1, uv.y * 0.16 + sd * 37.0));
	float mottle = fbm(uv * 0.42 + sd * 5.0);
	float grime = clamp(mottle * 0.75 + streak * 0.45, 0.0, 1.0) * dirt;

	if (mid == 0) {
		// ------------------------------------------------ facades
		float shader_windows = step(sty, 9.5) * step(-0.5, sty);
		float mask = 0.0;
		float frame = 0.0;
		vec3 wem = vec3(0.0);
		if (shader_windows > 0.5) {
			facade_windows(uv, sty, sd, wem, mask, frame);
		}
		vec3 wall = alb;
		// brick / panel / concrete surface grammar
		if (styb > 1.5 && styb < 2.5) {
			vec2 b = uv / vec2(0.24, 0.075);
			b.x += floor(b.y) * 0.5;
			vec2 bb = abs(fract(b) - 0.5);
			float mortar = smoothstep(0.44, 0.48, max(bb.x, bb.y));
			wall *= (0.86 + 0.24 * h12(floor(b))) * (1.0 - 0.35 * mortar);
			hgt = mortar * 0.5;
			bump = 0.6;
		} else if (styb > 2.5 && styb < 3.5) {
			vec2 g = fract(uv / vec2(1.05, 0.62));
			float seam = smoothstep(0.0, 0.02, min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y)));
			wall *= mix(0.78, 1.06, seam) * (0.93 + 0.14 * h12(floor(uv / vec2(1.05, 0.62))));
			hgt = seam;
			bump = 0.35;
		} else if (styb > 5.5 && styb < 6.5) {
			float rib = 0.5 + 0.5 * sin(uv.x * 18.0);
			wall *= 0.8 + 0.25 * rib;
			hgt = rib;
			bump = 0.5;
		} else if (styb > 4.5 && styb < 5.5) {
			float fin = abs(fract(uv.x / 0.85) - 0.5);
			wall *= mix(0.7, 1.0, smoothstep(0.3, 0.5, fin));
			hgt = 1.0 - fin;
			bump = 0.7;
		} else if (sty > 59.5 && sty < 60.5) {
			// interior latex paint: macro tone drift + fine orange-peel grain
			wall *= 0.955 + 0.07 * fbm2(uv * 0.18 + sd * 5.0);
			wall *= 1.0 - 0.025 * fbm2(uv * 0.9 + sd * 2.0);
			hgt = vnoise(uv * 60.0) * 0.10 + fbm2(uv * 2.4) * 0.08;
			bump = 0.07;
			rough = 0.55;
		} else if (sty > 60.5 && sty < 61.5) {
			// wallpaper: low-contrast vertical repeat + paper tooth
			float st = 0.5 + 0.5 * sin(uv.x * 24.0);
			wall *= 0.975 + 0.045 * st;
			wall *= 0.985 + 0.03 * fbm2(uv * 5.0 + sd * 3.0);
			hgt = vnoise(uv * 26.0) * 0.18;
			bump = 0.16;
			rough = 0.8;
		} else if (sty > 61.5 && sty < 62.5) {
			// interior wall tile
			vec2 t2 = uv / vec2(0.45, 0.25);
			vec2 fw2 = fwidth(t2);
			float lod2 = clamp(max(fw2.x, fw2.y) * 2.5, 0.0, 1.0);
			vec2 f2 = fract(t2);
			vec2 e2 = min(f2, 1.0 - f2);
			float grout2 = (1.0 - smoothstep(0.015, 0.06, min(e2.x, e2.y))) * (1.0 - lod2);
			wall *= mix(0.94 + 0.10 * h12(floor(t2)), 1.0, lod2);
			wall = mix(wall, wall * 0.74, grout2 * 0.85);
			hgt = (1.0 - grout2) * (1.0 - lod2);
			bump = 0.22;
			rough = mix(0.16, 0.72, grout2);
		} else if (sty > 62.5 && sty < 63.5) {
			// wood veneer
			float gr = fbm(vec2(uv.x * 2.0, uv.y * 0.35 + sd * 12.0));
			wall *= 0.90 + 0.16 * (0.5 + 0.5 * sin(uv.y * 12.0 + gr * 4.0));
			hgt = gr * 0.3;
			bump = 0.22;
			rough = 0.45;
		} else if (sty > 63.5 && sty < 64.5) {
			// upholstered wall panel
			float wv = 0.5 + 0.5 * sin(uv.x * 160.0) * sin(uv.y * 160.0);
			wall *= 0.86 + 0.2 * wv;
			wall *= 0.94 + 0.1 * fbm2(uv * 3.0);
			hgt = wv * 0.5;
			bump = 0.45;
			rough = 0.9;
		} else if (sty >= 49.5) {
			// interior default skin: nearly flat painted plaster
			wall *= 0.97 + 0.05 * fbm2(uv * 0.5 + sd * 2.0);
			hgt = vnoise(uv * 40.0) * 0.08;
			bump = 0.05;
			rough = 0.6;
		} else {
			hgt = fbm2(uv * 1.7) * 0.4 + fbm2(uv * 0.21) * 0.6;
			bump = 0.25;
		}
		// spandrel bands for curtain walls
		if (styb > 0.5 && styb < 1.5) {
			float band = step(fract(uv.y / 4.0), 0.18);
			wall = mix(wall * 1.06, alb * 0.22, band);
			metal = mix(0.0, 0.8, band);
		}
		float lowgrime = smoothstep(7.0, 0.0, uv.y) * 0.35;
		float dirtamt = clamp(grime * 0.55 + lowgrime, 0.0, 1.0);
		wall *= 1.0 - dirtamt * 0.42;
		wall = mix(wall, wall * vec3(0.72, 0.68, 0.6), dirtamt * 0.5);
		// window recess darkening + glass reflection
		float glass = mask * step(0.5, shader_windows);
		wall = mix(wall, tint * 0.06, glass * 0.92);
		alb = wall;
		emis = wem * night * 1.25;
		float glass_ref = glass * 0.9;
		metal = mix(metal, 0.65, glass_ref);
		rough = mix(0.55, 0.12, glass_ref);
		// mullions slightly proud, metal
		alb = mix(alb, alb * 1.6, frame * 0.5);
		hgt += mask * 0.0;
		bump = mix(bump, 0.15, glass);
		ao = 1.0 - lowgrime * 0.6;
	} else if (mid == 1) {
		// ------------------------------------------------ detailed glass pane
		vec2 q = floor(wpos.xz * 2.3 + wpos.y * 1.7);
		float r = h13(vec3(q, sd * 10.0));
		float r2 = h13(vec3(q.yx, sd * 3.0 + 7.0));
		float lit = step(1.0 - lit_ratio, r) * (1.0 - step(0.99, fract(TIME * 0.4 + r2 * 7.0)));
		vec3 warm = vec3(1.0, 0.74, 0.42);
		vec3 cool = vec3(0.5, 0.78, 1.0);
		vec3 c = mix(warm, cool, step(0.6, r2));
		float bright = (0.35 + 1.5 * r2) * mix(0.4, 1.0, smoothstep(0.0, 1.0, fract(wpos.y * 3.1)));
		float blinds = mix(1.0, 0.25 + 0.75 * step(0.45, fract(wpos.y * 9.0 + r)), step(0.75, r2));
		alb = vec3(0.06, 0.075, 0.09) * (0.7 + 0.6 * mottle);
		emis = c * lit * bright * blinds * 1.1 * night;
		rough = 0.045 + 0.05 * mottle;
		metal = 0.85;
		alpha = 0.30 + 0.35 * lit;
		// smudges + rain water film
		alb *= 1.0 - 0.35 * smoothstep(0.2, 0.8, vnoise(vec2(wpos.x, wpos.y * 0.2) * 3.0));
	} else if (mid == 2) {
		// ------------------------------------------------ metal
		float brush = vnoise(vec2(uv.x * 0.25, uv.y * 26.0));
		alb *= 0.86 + 0.22 * brush;
		float rust = smoothstep(0.55, 0.92, fbm(uv * vec2(1.2, 0.9) + sd * 9.0)) * clamp(1.2 - uv.y * 0.12, 0.15, 1.0);
		alb = mix(alb, vec3(0.24, 0.10, 0.045), rust * 0.85);
		rough = mix(0.28, 0.75, rust) + 0.12 * brush;
		metal = 0.85 * (1.0 - rust * 0.6);
		// rivets / panel seams
		vec2 g = abs(fract(uv / vec2(1.2, 0.8)) - 0.5);
		float seam = smoothstep(0.47, 0.5, max(g.x, g.y));
		alb *= 1.0 - seam * 0.45;
		hgt = seam * 0.6 + brush * 0.2;
		bump = 0.35;
	} else if (mid == 3) {
		// ------------------------------------------------ wood
		float grain = fbm(vec2(uv.x * 0.6, uv.y * 6.0 + sd * 20.0));
		float rings = 0.5 + 0.5 * sin(uv.y * 34.0 + grain * 6.0);
		alb *= 0.78 + 0.3 * rings + 0.1 * grain;
		rough = 0.42 + 0.2 * grain;
		hgt = rings * 0.3;
		bump = 0.3;
	} else if (mid == 4) {
		// ------------------------------------------------ fabric
		float weave = 0.5 + 0.5 * sin(uv.x * 190.0) * sin(uv.y * 190.0);
		alb *= 0.82 + 0.2 * weave + 0.12 * vnoise(uv * 4.0);
		rough = 0.92;
		hgt = weave;
		bump = 0.35;
	} else if (mid == 5) {
		// ------------------------------------------------ tiles
		// 0.45 m tiles, soft joint, fades out before it can alias
		vec2 t = uv / vec2(0.45, 0.45);
		vec2 fw = fwidth(t);
		float lod = clamp(max(fw.x, fw.y) * 2.5, 0.0, 1.0);
		vec2 f = fract(t);
		vec2 e = min(f, 1.0 - f);
		float grout = (1.0 - smoothstep(0.015, 0.06, min(e.x, e.y))) * (1.0 - lod);
		float vary = h12(floor(t));
		alb *= mix(0.96 + 0.07 * vary, 1.0, lod);
		alb = mix(alb, alb * 0.72, grout * 0.8);
		rough = mix(0.22, 0.7, grout);
		hgt = (1.0 - grout) * (1.0 - lod);
		bump = 0.25;
	} else if (mid == 6) {
		// ------------------------------------------------ asphalt
		float agg = fbm2(uv * 9.0) * 0.6 + vnoise(uv * 41.0) * 0.4;
		alb *= 0.62 + 0.55 * agg;
		float patch = smoothstep(0.62, 0.72, fbm2(uv * 0.14 + 12.0));
		alb = mix(alb, alb * vec3(0.55, 0.54, 0.56), patch * 0.7);
		// tar cracks
		float cr = vnoise(uv * vec2(0.9, 0.9));
		float crack = smoothstep(0.72, 0.80, cr);
		alb *= 1.0 - crack * 0.5;
		float pud = smoothstep(0.55, 0.78, fbm2(uv * 0.075 + sd * 3.0)) * wetness;
		float wet = wetness * (0.35 + 0.65 * (1.0 - smoothstep(0.0, 3.0, uv.y)));
		float rainrip = 0.0;
		if (pud > 0.5) {
			vec2 rp = uv * 2.2;
			vec2 cellp = floor(rp);
			vec2 fp = fract(rp) - 0.5;
			float t = fract(TIME * 1.7 + h12(cellp) * 9.0);
			float ring = sin((length(fp) - t * 0.45) * 42.0) * smoothstep(0.45, 0.0, abs(length(fp) - t * 0.45));
			rainrip = ring * (1.0 - t) * 0.55;
		}
		alb *= mix(1.0, 0.62, wet);
		alb = mix(alb, vec3(0.02, 0.03, 0.035), pud * 0.6);
		rough = mix(0.78, 0.09, wet * (0.55 + 0.45 * pud)) - rainrip * 0.15;
		metal = mix(0.0, 0.55, wet * pud);
		// faint oil sheen
		float sheen = smoothstep(0.7, 0.9, fbm2(uv * 0.35 + 33.0)) * wet;
		emis += vec3(0.08, 0.05, 0.12) * sheen * (0.3 + 0.7 * night);
		hgt = agg * 0.7 + crack * 0.2 + rainrip * 0.25;
		bump = 0.55;
	} else if (mid == 7) {
		// ------------------------------------------------ concrete pavement / slabs
		vec2 t = uv / vec2(2.2, 2.2);
		vec2 f = abs(fract(t) - 0.5);
		float joint = smoothstep(0.475, 0.5, max(f.x, f.y));
		float slab = h12(floor(t) + sd * 3.0);
		// per-slab tone + uneven settlement
		alb *= 0.80 + 0.30 * slab;
		alb *= 0.88 + 0.24 * fbm2(uv * 0.16 + sd * 7.0);
		alb *= 1.0 - joint * 0.55;
		// damp patches and long-term staining (large scale, low frequency)
		float damp = smoothstep(0.50, 0.80, fbm(uv * 0.085 + sd * 5.0));
		alb *= 1.0 - damp * 0.34;
		float stain = smoothstep(0.55, 0.88, fbm(uv * 0.3 + sd * 11.0));
		alb = mix(alb, alb * vec3(0.62, 0.60, 0.55), stain * 0.5);
		// hairline cracks + gum spots
		float cr2 = smoothstep(0.88, 0.94, fbm2(uv * 2.1 + 4.0));
		alb *= 1.0 - cr2 * 0.3;
		alb *= 1.0 - 0.22 * smoothstep(0.82, 0.96, vnoise(uv * 3.1));
		// wet / damp areas get glossy
		float pud = smoothstep(0.68, 0.88, fbm2(uv * 0.11 + 5.0) + damp * 0.2) * wetness;
		rough = mix(0.74, 0.12, max(pud, damp * 0.5 * wetness));
		// height: joints + per-slab tilt + aggregate
		hgt = joint * 0.55 + slab * 0.18 + fbm2(uv * 0.55) * 0.45 + cr2 * 0.1;
		bump = 0.5;
		metal = pud * 0.25;
	} else if (mid == 8) {
		// ------------------------------------------------ emissive neon / sign
		float pulse = 0.82 + 0.18 * sin(TIME * 2.4 + sd * 30.0);
		float flick = 1.0 - 0.9 * step(0.995, fract(TIME * 0.7 + sd * 5.0 + uv.x * 0.02));
		alb = tint * 0.5;
		emis = tint * pemis * pulse * flick * (0.55 + 0.9 * night);
		rough = 0.35;
	} else if (mid == 9) {
		// ------------------------------------------------ animated advertising screen
		vec2 g = uv * vec2(0.9, 1.6);
		float glyph_cells = 0.0;
		vec2 gc = floor(g);
		vec2 gf = fract(g);
		float gid = h12(gc + floor(vec2(TIME * 0.6, 0.0)));
		float glyph = 0.0;
		if (gf.x > 0.12 && gf.x < 0.88 && gf.y > 0.1 && gf.y < 0.9) {
			float bar1 = step(0.35, h11(gid * 13.0)) * step(abs(gf.y - 0.3), 0.07);
			float bar2 = step(0.4, h11(gid * 7.0)) * step(abs(gf.y - 0.6), 0.06) * step(0.2, gf.x) * step(gf.x, 0.8);
			float bar3 = step(0.5, h11(gid * 3.0)) * step(abs(gf.x - 0.5), 0.05) * step(0.25, gf.y) * step(gf.y, 0.78);
			glyph = clamp(bar1 + bar2 + bar3, 0.0, 1.0);
		}
		float scan = 0.75 + 0.25 * sin(uv.y * 240.0 + TIME * 6.0);
		float sweep = smoothstep(0.0, 0.12, abs(fract(uv.x * 0.08 - TIME * 0.09) - 0.5));
		vec3 base = tint * (0.12 + 0.9 * glyph * sweep) * scan;
		vec3 glow = mix(vec3(1.0, 0.25, 0.7), vec3(0.25, 0.8, 1.0), 0.5 + 0.5 * sin(TIME * 0.5 + sd * 12.0));
		emis = (base + glow * 0.16 * (1.0 - glyph)) * (0.4 + 1.2 * night) * 2.2;
		alb = base * 0.1;
		rough = 0.25;
		metal = 0.1;
	} else if (mid == 10) {
		// ------------------------------------------------ ceramic
		alb *= 0.96 + 0.05 * fbm2(uv * 3.0);
		rough = 0.13;
		metal = 0.0;
	} else if (mid == 11) {
		// ------------------------------------------------ foliage
		float leaf = fbm(uv * 2.6 + sd * 4.0);
		float clump = smoothstep(0.42, 0.72, leaf);
		alb = mix(alb * 0.55, alb * 1.25, clump);
		alb *= 0.8 + 0.3 * vnoise(uv * 7.0);
		rough = 0.85;
		emis = alb * 0.05 * night;
		hgt = clump;
		bump = 1.2;
	} else if (mid == 12) {
		// ------------------------------------------------ soil / gravel
		float gn = fbm2(uv * 6.0) * 0.7 + vnoise(uv * 30.0) * 0.3;
		alb *= 0.66 + 0.55 * gn;
		rough = 0.92;
		float pud = smoothstep(0.7, 0.9, fbm2(uv * 0.5)) * wetness;
		alb *= 1.0 - pud * 0.4;
		rough = mix(rough, 0.15, pud);
		hgt = gn;
		bump = 0.6;
	} else if (mid == 13) {
		// ------------------------------------------------ rubber
		alb *= 0.85 + 0.15 * vnoise(uv * 14.0);
		rough = 0.85;
	} else if (mid == 14) {
		// ------------------------------------------------ painted plastic
		alb *= 0.94 + 0.08 * fbm2(uv * 2.0);
		rough = 0.32;
	} else {
		// ------------------------------------------------ road paint
		float wear = smoothstep(0.35, 0.62, fbm2(uv * 1.4 + sd * 3.0));
		alb = mix(tint, tint * 0.55, wear * 0.8);
		rough = mix(0.55, 0.3, wear);
		emis = tint * 0.04 * night * (1.0 - wear);
	}

	// rain streaks running down every vertical surface
	if (abs(n_w.y) < 0.4) {
		float rs = vnoise(vec2(uv.x * 18.0, uv.y * 0.7 + TIME * 0.35));
		alb *= 1.0 - 0.10 * smoothstep(0.6, 0.9, rs) * wetness;
		rough = mix(rough, rough * 0.55, smoothstep(0.6, 0.9, rs) * wetness);
	}

	// global wet darkening + reflection boost
	float wfac = wetness * (1.0 - 0.6 * smoothstep(0.3, 0.9, n_w.y));
	alb *= mix(1.0, 0.80, wfac * 0.5);
	rough = mix(rough, 0.06, wfac * 0.28 * (1.0 - smoothstep(0.0, 0.25, rough)));
	metal = max(metal, wfac * 0.12);

	// global soot (city air)
	alb *= 1.0 - 0.16 * grime * dirt;

	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	METALLIC = metal;
	SPECULAR = 0.45 + 0.25 * wetness;
	EMISSION = emis * exposure_boost;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;

	if (mid == 0 || mid == 7 || mid == 2 || mid == 6 || mid == 5) {
		vec3 nb = bump_map(n_w, wpos, hgt, bump * 0.06);
		NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
	}
}