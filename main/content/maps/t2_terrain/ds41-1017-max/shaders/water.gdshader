shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 rock_a;
uniform vec4 rock_b;
uniform vec4 rock_c;
uniform sampler2D water_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_mask : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying float pool;
varying float rapid;
varying float speed;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.06 + vec2(9.3, 4.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	pool = COLOR.r;
	rapid = COLOR.g;
	speed = COLOR.b;
	// geometric waves: UV.y runs downstream along the channel tangent
	float t = TIME * (0.35 + speed * 1.4);
	// the plunge pool mesh is coarse: geometric waves there just alias into a
	// grid, so the pool stays flat and gets its relief from the normal map
	float gw = 1.0 - pool * 0.92;
	float w1 = sin(UV.y * 92.0 - t * 3.2 + UV.x * 9.0) * 0.090;
	float w2 = sin(UV.y * 36.0 - t * 1.7 + UV.x * 4.0) * 0.140;
	float w3 = sin(UV.y * 170.0 - t * 4.6 + UV.x * 17.0) * 0.030 * (0.4 + rapid);
	VERTEX.y += (w1 + w2 + w3) * (0.65 + rapid * 0.9) * gw;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = wpos;
	// ----------------------------------------------------------- depth
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float scene_z = -vpos.z;
	float thick = clamp(scene_z - (-VERTEX.z), 0.0, 80.0);

	// ----------------------------------------------------------- UV-aligned flow
	float t = TIME * (0.5 + speed * 1.8);
	// The pool is a wide, still surface: its baked maps have single dominant
	// frequencies that read as paving when tiled over 60 m.  Warp the lookup
	// so the same maps come out as slow swirling water.
	vec2 pwarp = vec2(fbm3(p.xz * 0.022), fbm3(p.xz * 0.022 + 13.7)) * 14.0;
	vec2 nuv = mix(vec2(UV.x * 85.0, UV.y * 135.0 - t * 1.6), (p.xz + pwarp) * 0.055 + vec2(0.0, -t * 0.08), pool);
	vec2 nuv2 = mix(vec2(UV.x * 40.0 + 0.27, UV.y * 56.0 - t * 0.8), (p.xz - pwarp * 0.6) * 0.145 + vec2(0.17, -t * 0.04), pool);
	vec3 nt = texture(water_normal, nuv).xyz * 2.0 - 1.0;
	vec3 nt2 = texture(water_normal, nuv2).xyz * 2.0 - 1.0;
	float hx = nt.x + 0.55 * nt2.x;
	float hz = nt.y + 0.55 * nt2.y;
	float bank = smoothstep(0.35, 0.0, thick);
	hx += sin(UV.y * 190.0 - TIME * 2.0 + UV.x * 24.0) * 0.12 * bank;
	vec3 nw = normalize(vec3(-hx * 1.7, 1.0, -hz * 1.7));
	// far pool: calm the normal so grazing waves do not moire into a grid
	float dst = distance(p, CAMERA_POSITION_WORLD);
	nw = normalize(mix(nw, vec3(0.0, 1.0, 0.0), smoothstep(18.0, 70.0, dst) * 0.65));

	// ----------------------------------------------------------- colour
	vec3 deep = vec3(0.009, 0.046, 0.045);
	vec3 shal = vec3(0.035, 0.140, 0.125);
	vec3 col = mix(shal, deep, smoothstep(0.4, 6.0, thick));
	col = mix(col, vec3(0.025, 0.090, 0.120), pool * 0.55);

	// ----------------------------------------------------------- rock foam + foam texture
	float rf = 0.0;
	for (int i = 0; i < 3; i++) {
		vec4 rr = i == 0 ? rock_a : (i == 1 ? rock_b : rock_c);
		vec2 d = p.xz - rr.xy;
		// teardrop whitewater: short upstream, long trail downstream
		float shape = length(vec2(d.x * 1.05, min(d.y, 0.0) * 0.72 + max(d.y, 0.0) * 0.26)) - rr.z;
		rf = max(rf, smoothstep(1.6, 0.0, shape));
	}
	vec2 fuv = mix(vec2(UV.x * 100.0, UV.y * 160.0 - t * 2.2), (p.xz + pwarp * 1.4) * 0.030 + vec2(0.0, -t * 0.10), pool);
	vec2 fuv2 = mix(vec2(UV.x * 260.0 + 0.21, UV.y * 390.0 - t * 4.0), (p.xz - pwarp * 0.9) * 0.082 + vec2(0.21, -t * 0.16), pool);
	float fm = texture(foam_mask, fuv).r;
	float fm2 = texture(foam_mask, fuv2).r;

	// ----------------------------------------------------------- fresnel / reflection
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - p);
	float fres = pow(1.0 - clamp(dot(nw, vdir), 0.0, 1.0), 5.0);
	vec3 rd = reflect(-vdir, nw);
	vec3 sky_refl = mix(vec3(0.54, 0.64, 0.76), vec3(0.20, 0.34, 0.55), clamp(rd.y, 0.0, 1.0));
	vec2 roff = nw.xz * (0.018 + 0.02 * fres);
	vec3 refl = texture(screen_tex, clamp(SCREEN_UV + roff, vec2(0.001), vec2(0.999))).rgb;
	refl = mix(refl, sky_refl, 0.42);
	col = mix(col, refl, clamp(0.07 + fres * 0.26, 0.0, 0.38));

	// ----------------------------------------------------------- foam
	float shore = smoothstep(0.42, 0.0, thick);
	float foam = smoothstep(0.58, 0.78, fm * 0.58 + fm2 * 0.32 + shore * 0.30 + rapid * 0.20);
	foam *= mix(1.0, 0.22, pool);
	foam = max(foam, pool * rf * 1.2);
	// the pool keeps its own lace: sparse patches, never a paving grid
	foam += pool * smoothstep(0.70, 0.97, fm * 0.45 + fm2 * 0.65) * 0.30;
	foam += smoothstep(0.78, 0.95, fm2) * 0.10;
	foam *= smoothstep(0.0, 0.2, thick + pool * 0.25);
	foam += pool * smoothstep(0.4, 0.72, fm) * 0.12;
	foam += rapid * smoothstep(0.45, 0.70, fm * 0.55 + fm2 * 0.45) * 0.35;
	foam += rf * smoothstep(0.18, 0.48, fm * 0.65 + fm2 * 0.35) * 1.35;
	// plunge-pool impact whitewater, integrated into the water surface
	float impact = smoothstep(46.0, 6.0, length(p.xz - vec2(-203.4, -198.0)));
	foam += impact * (0.26 + smoothstep(0.42, 0.78, fm * 0.62 + fm2 * 0.48) * 0.80);
	foam = clamp(foam, 0.0, 0.92);
	col = mix(col, vec3(0.96, 0.98, 0.98), clamp(foam * 1.8 + rf * 0.35, 0.0, 0.98));

	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = mix(0.12, 0.30, foam);
	SPECULAR = 0.36;
	METALLIC = 0.0;
	ALPHA = clamp(0.86 + foam * 0.15 + rf * 0.12, 0.74, 1.0);
}
