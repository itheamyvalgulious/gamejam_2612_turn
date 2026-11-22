shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D rock_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_height : filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_height : filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_height : filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_height : filter_linear_mipmap, repeat_enable;
uniform float detail_boost = 1.0;
uniform sampler2D rock_detail_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_detail_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_detail_height : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_detail_rough : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;
varying float wetv;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.7, 7.3);
		a *= 0.5;
	}
	return v;
}
float fbm4(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(31.4, 17.9);
		a *= 0.5;
	}
	return v;
}
float tri_fbm(vec3 p, vec3 w, float s, vec2 off) {
	return fbm3(p.zy * s + off) * w.x + fbm3(p.xz * s + off) * w.y + fbm3(p.xy * s + off) * w.z;
}
vec3 srgb2lin(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

// triplanar albedo, with an optional single-step parallax offset for close rock
vec3 tri_color(sampler2D t, sampler2D hmap, vec3 p, vec3 w, float s, vec2 off, vec3 vdir, float depth) {
	vec2 ux = p.zy * s + off;
	vec2 uy = p.xz * s + off;
	vec2 uz = p.xy * s + off;
	if (depth > 0.0) {
		ux -= vdir.zy * (texture(hmap, ux).r - 0.5) * depth * s;
		uy -= vdir.xz * (texture(hmap, uy).r - 0.5) * depth * s;
		uz -= vdir.xy * (texture(hmap, uz).r - 0.5) * depth * s;
	}
	return srgb2lin(texture(t, ux).rgb) * w.x + srgb2lin(texture(t, uy).rgb) * w.y + srgb2lin(texture(t, uz).rgb) * w.z;
}

vec3 tri_normal(sampler2D t, sampler2D hmap, vec3 p, vec3 w, float s, vec2 off, vec3 vdir, float depth) {
	vec2 ux = p.zy * s + off;
	vec2 uy = p.xz * s + off;
	vec2 uz = p.xy * s + off;
	if (depth > 0.0) {
		ux -= vdir.zy * (texture(hmap, ux).r - 0.5) * depth * s;
		uy -= vdir.xz * (texture(hmap, uy).r - 0.5) * depth * s;
		uz -= vdir.xy * (texture(hmap, uz).r - 0.5) * depth * s;
	}
	vec3 nx = texture(t, ux).xyz * 2.0 - 1.0;
	vec3 ny = texture(t, uy).xyz * 2.0 - 1.0;
	vec3 nz = texture(t, uz).xyz * 2.0 - 1.0;
	nx.y = -nx.y; ny.y = -ny.y; nz.y = -nz.y;
	// x: U=z,V=y,N=x   y: U=x,V=z,N=y   z: U=x,V=y,N=z
	vec3 wx = vec3(nx.z, nx.y, nx.x);
	vec3 wy = vec3(ny.x, ny.z, ny.y);
	vec3 wz = vec3(nz.x, nz.y, nz.z);
	return normalize(wx * w.x + wy * w.y + wz * w.z);
}

float tri_scalar(sampler2D t, vec3 p, vec3 w, float s, vec2 off) {
	return texture(t, p.zy * s + off).r * w.x + texture(t, p.xz * s + off).r * w.y + texture(t, p.xy * s + off).r * w.z;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wetv = COLOR.r;
}

void fragment() {
	vec3 p = wpos;
	vec3 n = normalize(wnrm);
	float h = p.y;
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float dist = distance(p, CAMERA_POSITION_WORLD);
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= max(tw.x + tw.y + tw.z, 1e-4);
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - p);

	// ---------------------------------------------------------------- masks
	float mott = tri_fbm(p, tw, 0.0022, vec2(4.0, 9.0));
	float snowline = 545.0 + 44.0 * (mott - 0.5) * 2.0;
	if (p.z < -260.0 && p.x < 300.0) { snowline = 502.0 + 28.0 * (mott - 0.5) * 2.0; }
	float fine_line = tri_fbm(p, tw, 0.010, vec2(3.0, 7.0));
	snowline += 58.0 * (fine_line - 0.5);
	float snow = smoothstep(snowline, snowline + 34.0, h);
	snow *= smoothstep(0.70, 0.40, slope);
	float north = max(0.0, -n.z);
	snow = max(snow, north * smoothstep(380.0, 500.0, h) * 0.55 * smoothstep(0.8, 0.45, slope));
	snow = clamp(snow + (mott - 0.5) * 0.35, 0.0, 1.0);
	float snow_patch = 0.5 + 0.5 * tri_fbm(p, tw, 0.030, vec2(11.0));
	float trans = smoothstep(snowline - 20.0, snowline + 35.0, h) * (1.0 - smoothstep(snowline + 45.0, snowline + 80.0, h));
	snow *= mix(1.0, smoothstep(0.28, 0.70, snow_patch * 0.72 + 0.28), trans * 0.75);
	snow *= smoothstep(0.70, 0.40, slope + (snow_patch - 0.5) * 0.22);
	float snow_rock = smoothstep(0.64, 0.90, tri_fbm(p, tw, 0.020, vec2(17.0)));
	snow *= 1.0 - snow_rock * smoothstep(snowline - 15.0, snowline + 75.0, h) * 0.35;

	float warm = smoothstep(-340.0, -80.0, p.z);
	float forest = warm * smoothstep(420.0, 255.0, h) * smoothstep(0.64, 0.34, slope);
	forest *= 0.62 + 0.55 * mott;

	float rock = smoothstep(0.30, 0.56, slope) + smoothstep(680.0, 830.0, h) * 0.55;
	rock = clamp(rock, 0.0, 1.0);
	rock = max(rock, smoothstep(0.35, 0.15, snow) * slope * 1.4);
	float rock_w = clamp(rock * smoothstep(0.15, 0.55, slope + rock * 0.25), 0.0, 1.0);
	float snow_w = snow * (1.0 - rock_w * 0.55);

	// ------------------------------------------------------------ rock PBR
	float pom_depth = 0.0;
	if (dist < 35.0 && rock_w > 0.35) { pom_depth = 0.018; }
	float rs = 0.25 * detail_boost;
	float rm = 1.20 * detail_boost;
	vec3 rock_a = tri_color(rock_albedo, rock_height, p, tw, rs, vec2(0.0), vdir, pom_depth);
	vec3 rock_b = tri_color(rock_albedo, rock_height, p, tw, rm, vec2(0.37, 0.71), vdir, pom_depth * 0.5);
	vec3 rock_col = rock_a * 0.65 + rock_b * 0.35;
	float macro = tri_fbm(p, tw, 0.011, vec2(0.0));
	rock_col *= 0.78 + 0.42 * macro;
	// horizontal bedding tint anchors the texture to world strata
	float bedding = 0.5 + 0.5 * sin(h * 0.20 + tri_fbm(p, tw, 0.006, vec2(9.0)) * 7.0);
	rock_col *= mix(1.0, 0.88 + 0.18 * bedding, smoothstep(0.30, 0.62, slope) * 0.5);
	rock_col = mix(rock_col, rock_col * 0.45, wetv * 0.85);
	vec3 rock_n = normalize(tri_normal(rock_normal, rock_height, p, tw, rs, vec2(0.0), vdir, pom_depth) +
		tri_normal(rock_normal, rock_height, p, tw, rm, vec2(0.37, 0.71), vdir, pom_depth * 0.5) * 0.8);
	float r_rough = mix(tri_scalar(rock_rough, p, tw, rs, vec2(0.0)), tri_scalar(rock_rough, p, tw, rm, vec2(0.37, 0.71)), 0.4);
	float dpx = max(max(fwidth(p.x), fwidth(p.y)), fwidth(p.z));
	float df = (1.0 - smoothstep(2.2, 4.8, dist)) * (1.0 - smoothstep(0.006, 0.020, dpx));
	if (df > 0.01) {
		vec3 d1 = tri_color(rock_detail_albedo, rock_detail_height, p, tw, 3.125, vec2(0.17, 0.43), vdir, 0.010);
		vec3 d2 = tri_color(rock_detail_albedo, rock_detail_height, p, tw, 9.10, vec2(0.63, 0.29), vdir, 0.004);
		rock_col = mix(rock_col, (d1 * 0.62 + d2 * 0.38) * 1.25, df * 0.55);
		vec3 dn = normalize(tri_normal(rock_detail_normal, rock_detail_height, p, tw, 3.125, vec2(0.17, 0.43), vdir, 0.010) +
			tri_normal(rock_detail_normal, rock_detail_height, p, tw, 9.10, vec2(0.63, 0.29), vdir, 0.004) * 0.7);
		rock_n = normalize(mix(rock_n, dn, df * 0.9));
		r_rough = mix(r_rough, 0.82, df * 0.3);
	}

	// At distance the 0.8 m strata tile lands under one pixel and moires into a
	// woven pattern: fade it into a mean tone.  (Kept exactly as approved -
	// stronger world-space beds were tried and they read as corduroy on the
	// wide shots.)
	float farf = smoothstep(10.0, 34.0, dist);
	vec3 rock_mean = vec3(0.255, 0.242, 0.222) * (0.78 + 0.42 * macro);
	rock_col = mix(rock_col, rock_mean, farf * 0.60);

	// ---- falls-local wall treatment -------------------------------------
	// A smooth weight built from the distance to the fall axis (lip->impact).
	// Only the gorge around the waterfall gets the sedimentary beds and the
	// stronger de-moire; everything else keeps the approved look exactly.
	// The fall runs from (-228.5, 500, -231) to (-203.4, 292.4, -198).
	vec3 fa = vec3(-228.5, 500.0, -231.0);
	vec3 fab = vec3(25.1, -207.6, 33.0);
	float ft = clamp(dot(p - fa, fab) / dot(fab, fab), 0.0, 1.0);
	float wf = 1.0 - smoothstep(62.0, 155.0, distance(p, fa + fab * ft));
	float bed_relief = 0.0;
	if (wf > 0.002) {
		float mm2 = tri_fbm(p, tw, 0.0065, vec2(31.0));
		float mm3 = tri_fbm(p, tw, 0.0019, vec2(53.0));
		float md1 = tri_fbm(p, tw, 0.0450, vec2(41.0));
		float ph = h * 0.155 + tri_fbm(p, tw, 0.0052, vec2(21.0)) * 16.0;
		float bd = 0.5 + 0.5 * sin(ph);
		float bd2 = 0.5 + 0.5 * sin(h * 0.430 + tri_fbm(p, tw, 0.0090, vec2(5.0)) * 8.0);
		vec3 rl = vec3(0.205, 0.193, 0.174);
		rl *= 0.66 + 0.52 * mm2 + 0.26 * (mm3 - 0.5);
		rl *= 0.76 + 0.38 * md1;
		rl *= 0.72 + 0.46 * bd + 0.16 * bd2;
		rock_col = mix(rock_col, rl, wf * 0.95);
		bed_relief = cos(ph) * 0.155;
	}

	// ------------------------------------------------------------ snow PBR
	float ss = 0.25 * detail_boost;
	float sm = 1.40 * detail_boost;
	vec3 snow_a = tri_color(snow_albedo, snow_height, p, tw, ss, vec2(0.0), vec3(0.0), 0.0);
	vec3 snow_b = tri_color(snow_albedo, snow_height, p, tw, sm, vec2(0.23, 0.59), vec3(0.0), 0.0);
	vec3 snow_col = snow_a * 0.62 + snow_b * 0.38;
	float sas = fbm4(p.xz * 0.045 + vec2(p.x * 0.003, p.z * 0.003));
	snow_col *= 0.92 + 0.10 * sas;
	vec3 snow_n = normalize(tri_normal(snow_normal, snow_height, p, tw, ss, vec2(0.0), vec3(0.0), 0.0) +
		tri_normal(snow_normal, snow_height, p, tw, sm, vec2(0.23, 0.59), vec3(0.0), 0.0) * 0.7);
	float s_rough = mix(tri_scalar(snow_rough, p, tw, ss, vec2(0.0)), tri_scalar(snow_rough, p, tw, sm, vec2(0.23, 0.59)), 0.4);

	// ------------------------------------------------------------ ground PBR
	float gs = 0.50 * detail_boost;
	float gm = 2.10 * detail_boost;
	vec3 ground_a = tri_color(ground_albedo, ground_height, p, tw, gs, vec2(0.0), vec3(0.0), 0.0);
	vec3 ground_b = tri_color(ground_albedo, ground_height, p, tw, gm, vec2(0.61, 0.29), vec3(0.0), 0.0);
	vec3 ground_tex = ground_a * 0.60 + ground_b * 0.40;
	vec3 ground_n = normalize(tri_normal(ground_normal, ground_height, p, tw, gs, vec2(0.0), vec3(0.0), 0.0) +
		tri_normal(ground_normal, ground_height, p, tw, gm, vec2(0.61, 0.29), vec3(0.0), 0.0) * 0.7);
	float g_rough = mix(tri_scalar(ground_rough, p, tw, gs, vec2(0.0)), tri_scalar(ground_rough, p, tw, gm, vec2(0.61, 0.29)), 0.4);

	vec3 soil = ground_tex * vec3(0.78, 0.96, 0.62);
	soil *= 0.72;
	soil = mix(soil, vec3(0.055, 0.110, 0.028), smoothstep(0.48, 0.72, fbm3(p.xz * 0.075 + 11.0)) * smoothstep(0.50, 0.18, slope) * 0.55);
	soil *= mix(1.0, 0.48, clamp(forest, 0.0, 1.0) * 0.9);

	float mead = fbm3(p.xz * 0.06 + 5.0);
	vec3 meadow = ground_tex * mix(vec3(0.55, 0.95, 0.38), vec3(1.10, 1.25, 0.62), mead);
	meadow = mix(meadow, vec3(0.20, 0.185, 0.115), smoothstep(430.0, 520.0, h) * 0.45);
	meadow *= mix(1.0, 0.72, clamp(forest, 0.0, 1.0));

	// ------------------------------------------------------------ river gravel
	float gvw = smoothstep(0.68, 0.95, wetv) * (1.0 - rock_w) * (1.0 - snow_w);
	float gvs = 0.66 * detail_boost;
	float gvm = 2.20 * detail_boost;
	vec3 gravel_col = tri_color(gravel_albedo, gravel_height, p, tw, gvs, vec2(0.0), vec3(0.0), 0.0) * 0.62 +
		tri_color(gravel_albedo, gravel_height, p, tw, gvm, vec2(0.47, 0.83), vec3(0.0), 0.0) * 0.38;
	vec3 gravel_n = normalize(tri_normal(gravel_normal, gravel_height, p, tw, gvs, vec2(0.0), vec3(0.0), 0.0) +
		tri_normal(gravel_normal, gravel_height, p, tw, gvm, vec2(0.47, 0.83), vec3(0.0), 0.0) * 0.7);
	float gr_rough = tri_scalar(gravel_rough, p, tw, gvs, vec2(0.0));

	// ---------------------------------------------------------------- blend
	float farf2 = smoothstep(10.0, 34.0, dist);
	meadow = mix(meadow, vec3(0.115, 0.155, 0.075) * (0.7 + 0.6 * mead), farf2 * 0.42);
	soil = mix(soil, vec3(0.075, 0.082, 0.052) * (0.8 + 0.5 * mott), farf2 * 0.7);
	vec3 col = meadow;
	col = mix(col, soil, clamp(forest, 0.0, 1.0));
	col = mix(col, rock_col, rock_w);
	col = mix(col, snow_col, snow_w);
	// shoreline: wet sand -> gravel -> mossy grass, soft transition
	float shore = smoothstep(0.10, 0.62, wetv);
	vec3 sand = mix(vec3(0.20, 0.17, 0.12), vec3(0.32, 0.30, 0.22), smoothstep(0.2, 0.8, wetv));
	sand = mix(sand, vec3(0.085, 0.175, 0.045), smoothstep(0.28, 0.72, wetv) * 0.85);
	col = mix(col, sand, shore * 0.78);
	col = mix(col, gravel_col * mix(1.0, 0.55, wetv), gvw);
	col = mix(col, col * 0.45, wetv * 0.6);
	col = mix(col, vec3(0.16, 0.175, 0.18), smoothstep(0.55, 0.95, wetv) * 0.18);

	vec3 ntex = n;
	ntex = normalize(mix(ntex, ground_n, (1.0 - rock_w) * (1.0 - snow_w) * (1.0 - gvw) * 0.85));
	ntex = normalize(mix(ntex, gravel_n, gvw * 0.9));
	// the tiled normal is what prints the diagonal weave at close range, so it
	// is faded hard inside the gorge; the beds supply the relief there instead
	ntex = normalize(mix(ntex, rock_n, rock_w * 0.92 * (1.0 - 0.70 * smoothstep(16.0, 50.0, dist)) * (1.0 - 0.90 * wf)));
	ntex = normalize(ntex + vec3(0.0, clamp(bed_relief * 3.4, -0.60, 0.60), 0.0) * rock_w * wf);

	ntex = normalize(mix(ntex, snow_n, snow_w * 0.85));

	float rough = mix(0.90, g_rough, (1.0 - rock_w) * (1.0 - snow_w));
	rough = mix(rough, gr_rough, gvw);
	rough = mix(rough, r_rough, rock_w);
	rough = mix(rough, 0.55, snow_w * 0.7);
	rough = mix(rough, 0.28, wetv * 0.6);

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = mix(0.18, 0.35, snow_w);
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(ntex, 0.0)).xyz);
}

