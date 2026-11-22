shader_type spatial;
render_mode unshaded, cull_disabled, specular_disabled;

// Animated sci-fi displays, pure math. u_style:
// 0 = data/text columns, 1 = vitals waveform, 2 = radar sweep, 3 = status bars
uniform int u_style = 0;
uniform vec3 u_color = vec3(0.35, 0.85, 1.0);
uniform float u_gain = 1.7;
uniform float u_time_scale = 1.0;
uniform float u_seed = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7) + u_seed);
	p += dot(p, p + 34.27);
	return fract(p.x * p.y * 95.43);
}

float style_data(vec2 uv, float t) {
	float v = 0.0;
	vec2 cell = vec2(floor(uv.x * 26.0), floor(uv.y * 18.0));
	vec2 cf = vec2(fract(uv.x * 26.0), fract(uv.y * 18.0));
	float scroll = floor(t * 1.6 + cell.y * 0.37);
	float on = step(0.42, hash21(vec2(cell.x, cell.y * 3.1 + scroll)));
	// glyph-ish inner blocks
	float glyph = step(0.18, cf.x) * step(cf.x, 0.82) * step(0.22, cf.y) * step(cf.y, 0.7);
	float subbar = step(0.5, hash21(vec2(cell.x * 1.7, scroll)));
	v = on * mix(glyph, glyph * step(fract(cf.x * 3.0), 0.55), subbar);
	// header band
	float head = step(0.9, uv.y) * step(fract(uv.x * 8.0 - t * 0.15), 0.62);
	v = max(v * 0.85, head * 0.7);
	return v;
}

float style_wave(vec2 uv, float t) {
	float v = 0.0;
	// grid
	float grid = (step(0.965, fract(uv.x * 12.0)) + step(0.95, fract(uv.y * 8.0))) * 0.16;
	// ecg waveform
	float x = fract(uv.x - t * 0.23);
	float q = fract(x * 3.0);
	float spike = 0.0;
	spike += exp(-pow((q - 0.42) * 22.0, 2.0)) * 0.62;
	spike -= exp(-pow((q - 0.52) * 30.0, 2.0)) * 0.3;
	spike += exp(-pow((q - 0.66) * 14.0, 2.0)) * 0.16;
	float base = 0.5 + spike + 0.02 * sin(uv.x * 90.0 + t * 7.0);
	float line = smoothstep(0.014, 0.0, abs(uv.y - base));
	float trace = smoothstep(0.05, 0.0, abs(uv.y - base)) * 0.22;
	v = grid + line + trace;
	// second slow wave (respiration)
	float b2 = 0.2 + 0.09 * sin(uv.x * 9.0 - t * 1.4);
	v += smoothstep(0.012, 0.0, abs(uv.y - b2)) * 0.8;
	return v;
}

float style_radar(vec2 uv, float t) {
	vec2 p = (uv - 0.5) * 2.0;
	p.x *= 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float v = 0.0;
	// rings + cross
	v += smoothstep(0.012, 0.0, abs(r - 0.33)) * 0.4;
	v += smoothstep(0.012, 0.0, abs(r - 0.66)) * 0.4;
	v += smoothstep(0.012, 0.0, abs(r - 0.95)) * 0.55;
	v += (smoothstep(0.008, 0.0, abs(p.x)) + smoothstep(0.008, 0.0, abs(p.y))) * 0.2 * step(r, 0.96);
	// sweep
	float sweep_a = fract(t * 0.18) * 6.28318 - 3.14159;
	float da = mod(a - sweep_a + 6.28318, 6.28318);
	float sweep = (1.0 - smoothstep(0.0, 1.1, da)) * step(r, 0.95) * 0.55;
	v += sweep;
	// blips
	vec2 bid = floor((p + 1.0) * 7.0);
	float bh = hash21(bid);
	if (bh > 0.86) {
		vec2 bp = (bh * 0.8 + 0.1) * vec2(cos(bh * 43.0), sin(bh * 27.0)) ;
		float blipd = length(p - bp);
		float age = mod(t * 0.18 - atan(bp.y, bp.x) / 6.28318 + 1.0, 1.0);
		float blip = smoothstep(0.05, 0.0, blipd) * (1.0 - age) * step(0.0, age);
		v += blip * 1.4;
	}
	v *= step(r, 1.0);
	return v;
}

float style_bars(vec2 uv, float t) {
	float v = 0.0;
	float row = floor(uv.y * 9.0);
	float rf = fract(uv.y * 9.0);
	float target = hash21(vec2(row, floor(t * 0.5) * 1.3));
	float anim = mix(hash21(vec2(row, floor(t * 0.5 - 1.0) * 1.3)), target, fract(t * 0.5));
	float bar = step(0.2, rf) * step(rf, 0.8) * step(uv.x, 0.08 + anim * 0.84);
	float frame = step(uv.x, 0.94) * step(0.16, rf) * step(rf, 0.84) * 0.1;
	v = bar * (0.7 + 0.3 * hash21(vec2(row, 7.0))) + frame;
	// numeric column
	if (uv.x > 0.945) {
		v = step(0.35, hash21(vec2(floor(uv.y * 27.0), floor(t * 2.0)))) * 0.8;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * u_time_scale;
	float v = 0.0;
	if (u_style == 0) { v = style_data(uv, t); }
	else if (u_style == 1) { v = style_wave(uv, t); }
	else if (u_style == 2) { v = style_radar(uv, t); }
	else { v = style_bars(uv, t); }
	// scanlines + flicker + vignette + frame
	float scan = 0.88 + 0.12 * sin(uv.y * 460.0 + t * 4.0);
	float roll = 0.97 + 0.03 * sin(uv.y * 6.0 - t * 1.2);
	float hf = hash21(vec2(floor(t * 17.0), u_seed));
	float flick = 1.0 - 0.06 * step(0.93, hf);
	vec2 vb = min(uv, 1.0 - uv);
	float vig = smoothstep(0.0, 0.06, min(vb.x, vb.y));
	float border = (1.0 - smoothstep(0.0, 0.012, min(vb.x, vb.y))) * 0.9;
	vec3 col = u_color * (v * scan * roll * flick * vig + 0.03 * vig) + u_color * border;
	ALBEDO = vec3(0.0);
	EMISSION = col * u_gain;
}
