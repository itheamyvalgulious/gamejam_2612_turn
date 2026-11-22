shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

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

float ridge(vec2 p) {
	return 1.0 - abs(vnoise(p) * 2.0 - 1.0);
}

// Triplanar fBm: x uses the yz plane, y uses xz, z uses xy.
float tri_fbm(vec3 p, vec3 w, float s, vec2 off) {
	return fbm3(p.zy * s + off) * w.x + fbm3(p.xz * s + off) * w.y + fbm3(p.xy * s + off) * w.z;
}

float worley(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d = 1.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j)) + vec2(hash12(ip + vec2(float(i), float(j))), hash12(ip + vec2(float(i), float(j)) + 17.0)) - fp;
			d = min(d, dot(g, g));
		}
	}
	return sqrt(d);
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
	// break up the snowline / bare rock transition
	float snow_patch = 0.5 + 0.5 * tri_fbm(p, tw, 0.030, vec2(11.0));
	float trans = smoothstep(snowline - 25.0, snowline + 45.0, h) * (1.0 - smoothstep(snowline + 70.0, snowline + 150.0, h));
	snow *= mix(1.0, smoothstep(0.28, 0.70, snow_patch * 0.72 + 0.28), trans);
	snow *= smoothstep(0.70, 0.40, slope + (snow_patch - 0.5) * 0.22);
	float snow_rock = smoothstep(0.56, 0.86, tri_fbm(p, tw, 0.020, vec2(17.0)));
	snow *= 1.0 - snow_rock * smoothstep(snowline - 20.0, snowline + 160.0, h) * 0.55;

	float warm = smoothstep(-340.0, -80.0, p.z);
	float forest = warm * smoothstep(420.0, 255.0, h) * smoothstep(0.64, 0.34, slope);
	forest *= 0.62 + 0.55 * mott;

	float rock = smoothstep(0.30, 0.56, slope) + smoothstep(680.0, 830.0, h) * 0.55;
	rock = clamp(rock, 0.0, 1.0);
	rock = max(rock, smoothstep(0.35, 0.15, snow) * slope * 1.4);

	// ---------------------------------------------------------------- rock
	float macro = tri_fbm(p, tw, 0.011, vec2(0.0));
	vec3 r1 = vec3(0.100, 0.105, 0.110);
	vec3 r2 = vec3(0.205, 0.200, 0.190);
	vec3 rock_col = mix(r1, r2, smoothstep(0.12, 0.85, macro));
	float macro2 = tri_fbm(p, tw, 0.004, vec2(4.0));
	rock_col = mix(rock_col, vec3(0.165, 0.150, 0.130), smoothstep(0.55, 0.9, macro2) * 0.45);
	float grain = tri_fbm(p, tw, 0.060, vec2(7.0));
	rock_col *= 0.80 + 0.38 * grain;
	// horizontal bedding on steep faces, triplanar-warped
	float bedding = 0.5 + 0.5 * sin(h * 0.20 + tri_fbm(p, tw, 0.006, vec2(9.0)) * 7.0);
	float steep = smoothstep(0.35, 0.62, slope);
	rock_col *= mix(1.0, 0.84 + 0.22 * bedding, steep * 0.55);
	// triplanar crack network: no vertically stretched worley on cliffs
	float vc_x = worley(vec2(p.z, h) * 0.05);
	float vc_y = worley(vec2(p.x, p.z) * 0.05);
	float vc_z = worley(vec2(p.x, h) * 0.05);
	float vcrack = vc_x * tw.x + vc_y * tw.y + vc_z * tw.z;
	rock_col *= 0.68 + 0.32 * smoothstep(0.02, 0.20, vcrack);
	float crack = worley(vec2(p.x * 0.07 + p.z * 0.07, h * 0.07));
	rock_col *= 0.80 + 0.20 * smoothstep(0.03, 0.22, crack);
	float lichen = smoothstep(0.58, 0.80, tri_fbm(p, tw, 0.030, vec2(7.0)));
	rock_col = mix(rock_col, vec3(0.155, 0.190, 0.095), lichen * 0.5 * smoothstep(0.4, 0.1, slope));
	rock_col = mix(rock_col, rock_col * 0.45, wetv * 0.85);

	// ---------------------------------------------------------------- snow
	float sas = fbm4(p.xz * 0.045 + vec2(p.x * 0.003, p.z * 0.003));
	float sas2 = fbm3(vec2(p.x * 0.22, p.z * 0.06) + 3.0);
	vec3 snow_col = mix(vec3(0.60, 0.66, 0.76), vec3(0.82, 0.87, 0.94), smoothstep(0.15, 0.75, sas));
	snow_col = mix(snow_col, vec3(0.86, 0.91, 0.98), sas2 * 0.4);
	snow_col *= 0.95 + 0.08 * sas2;
	// wind-carved sastrugi shading
	float sas_ridge = fbm3(vec2(p.x * 0.09, p.z * 0.026) + 4.0);
	snow_col *= 0.90 + 0.16 * smoothstep(0.35, 0.7, sas_ridge);

	// --------------------------------------------------------- forest floor
	float soil_n = fbm4(p.xz * 0.11);
	float litter = fbm3(p.xz * 0.55 + 2.0);
	vec3 soil = mix(vec3(0.030, 0.026, 0.018), vec3(0.085, 0.068, 0.040), soil_n);
	soil = mix(soil, vec3(0.115, 0.088, 0.045), smoothstep(0.50, 0.80, litter) * 0.6);
	float moss = smoothstep(0.48, 0.72, fbm3(p.xz * 0.075 + 11.0)) * smoothstep(0.50, 0.18, slope);
	soil = mix(soil, vec3(0.055, 0.110, 0.028), moss * 0.85);
	float peb = smoothstep(0.22, 0.10, worley(p.xz * 1.1));
	soil = mix(soil, vec3(0.26, 0.24, 0.20), peb * 0.35);
	// canopy shade keeps the understorey dark and humid
	soil *= mix(1.0, 0.45, clamp(forest, 0.0, 1.0) * 0.85);

	// ------------------------------------------------------- meadow / alpine
	float mead = fbm3(p.xz * 0.06 + 5.0);
	vec3 meadow = mix(vec3(0.075, 0.120, 0.032), vec3(0.195, 0.255, 0.075), mead);
	meadow = mix(meadow, vec3(0.125, 0.190, 0.045), fbm3(p.xz * 0.35) * 0.5);
	meadow = mix(meadow, vec3(0.155, 0.145, 0.065), smoothstep(0.55, 0.85, fbm3(p.xz * 0.85 + 4.0)) * 0.35);
	meadow = mix(meadow, vec3(0.20, 0.185, 0.115), smoothstep(430.0, 520.0, h) * 0.55);
	meadow *= mix(1.0, 0.66, clamp(forest, 0.0, 1.0));
	float flower = smoothstep(0.94, 1.0, hash12(floor(p.xz * 5.0))) * smoothstep(0.25, 0.05, slope);
	meadow = mix(meadow, vec3(0.72, 0.60, 0.18), flower * 0.6);

	// ------------------------------------------------------------- blending
	vec3 col = meadow;
	col = mix(col, soil, clamp(forest, 0.0, 1.0));
	float rock_w = clamp(rock * smoothstep(0.15, 0.55, slope + rock * 0.25), 0.0, 1.0);
	col = mix(col, rock_col, rock_w);
	float snow_w = snow * (1.0 - rock_w * 0.55);
	col = mix(col, snow_col, snow_w);
	// wet darkening on rock and soil
	col = mix(col, col * 0.42, wetv * 0.85);
	col = mix(col, vec3(0.16, 0.175, 0.18), smoothstep(0.55, 0.95, wetv) * 0.25);

	// --------------------------------------------------------- detail normal
	vec3 tg;
	vec3 bt;
	vec2 uv;
	if (abs(n.y) > 0.55) {
		tg = vec3(1.0, 0.0, 0.0);
		bt = vec3(0.0, 0.0, 1.0);
		uv = p.xz;
	} else if (abs(n.x) > abs(n.z)) {
		tg = vec3(0.0, 0.0, 1.0);
		bt = vec3(0.0, 1.0, 0.0);
		uv = p.zy;
	} else {
		tg = vec3(1.0, 0.0, 0.0);
		bt = vec3(0.0, 1.0, 0.0);
		uv = p.xy;
	}
	float e = 0.22;
	float fade = 1.0 - smoothstep(180.0, 900.0, dist);
	vec2 uv2 = uv * 1.0;
	float d0 = snow_w * fbm3(uv2 * 0.8) * 0.7 + rock_w * fbm3(uv2 * 0.35 + 9.0) * 0.5 + forest * fbm3(uv2 * 1.3) * 0.4;
	float du = snow_w * fbm3((uv2 + vec2(e, 0.0)) * 0.8) * 0.7 + rock_w * fbm3((uv2 + vec2(e, 0.0)) * 0.35 + 9.0) * 0.5 + forest * fbm3((uv2 + vec2(e, 0.0)) * 1.3) * 0.4;
	float dv = snow_w * fbm3((uv2 + vec2(0.0, e)) * 0.8) * 0.7 + rock_w * fbm3((uv2 + vec2(0.0, e)) * 0.35 + 9.0) * 0.5 + forest * fbm3((uv2 + vec2(0.0, e)) * 1.3) * 0.4;
	vec3 bump = tg * ((du - d0) / e) + bt * ((dv - d0) / e);
	vec3 n2 = normalize(n - bump * (0.55 * fade + 0.08));
	// horizontal bedding relief on cliff faces
	float bed_relief = cos(h * 0.22 + tri_fbm(p, tw, 0.006, vec2(9.0)) * 7.0);
	n2 = normalize(n2 - vec3(0.0, bed_relief * 0.09 * steep * fade, 0.0));

	ALBEDO = col;
	ROUGHNESS = mix(0.94, 0.42, snow_w);
	ROUGHNESS = mix(ROUGHNESS, 0.28, wetv);
	ROUGHNESS = mix(ROUGHNESS, 0.82, rock_w * 0.5);
	SPECULAR = mix(0.18, 0.35, snow_w);
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(n2, 0.0)).xyz);
}
