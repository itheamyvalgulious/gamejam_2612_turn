shader_type spatial;
// "Volumetric explosion" by Duke -- exact port of shadertoy.com/view/lsySzd
// (CC BY-NC-SA 3.0). iChannel0 = RGBA noise medium (256x256),
// iChannel2 = grey noise small (64x64), both shipped unmodified.
//
// The ray-march core is a 1:1 copy of the original mainImage(); the only
// changes are: the ray is built in the quad's local frame (so the burst can be
// placed anywhere in the world), the timer is driven by `lt` instead of
// iTime, and `seed`/`fade`/`intensity` are added for gameplay.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D noise2_tex : filter_linear, repeat_enable;
uniform float lt = 0.0;          // local age of this burst (seconds)
uniform float seed = 0.0;        // per-burst variation
uniform float intensity = 1.0;
uniform float fade = 1.0;
uniform float time_scale = 2.2;  // burst lifetime vs. the demo's 10 s cycle
uniform int split_mode = 0;      // 0 = original BOTH, 1 = always abs(d), 2 = plain

varying vec2 qpos;

// iq's noise
float noise(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	vec2 uv = (p.xy + vec2(37.0, 17.0) * p.z) + f.xy;
	vec2 rg = texture(noise_tex, (uv + 0.5) / 256.0).yx;
	return 1.0 - 0.82 * mix(rg.x, rg.y, f.z);
}

float fbm(vec3 p) {
	return noise(p * 0.06125) * 0.5 + noise(p * 0.125) * 0.25
		+ noise(p * 0.25) * 0.125 + noise(p * 0.4) * 0.2;
}

float sphere_sdf(vec3 p, float r) {
	return length(p) - r;
}

const float nudge = 4.0;
const float normalizer = 1.0 / sqrt(1.0 + nudge * nudge);

float spiral_noise(vec3 p, float tt) {
	float n = -mod(tt * 0.2, -2.0);
	float iter = 2.0;
	for (int i = 0; i < 8; i++) {
		n += -abs(sin(p.y * iter) + cos(p.x * iter)) / iter;
		p.xy += vec2(p.y, -p.x) * nudge;
		p.xy *= normalizer;
		p.xz += vec2(p.z, -p.x) * nudge;
		p.xz *= normalizer;
		iter *= 1.733733;
	}
	return n;
}

float volumetric_explosion(vec3 p, float tt, float sd) {
	float final_d = sphere_sdf(p, 4.0);
	final_d += fbm(p * 50.0);
	final_d += spiral_noise(p.zxy * 0.4132 + 333.0 + sd, tt) * 3.0;
	return final_d;
}

// random per-burst orientation (identity when sd = 0, so the reference port is
// bit-identical at seed 0)
mat3 seed_rot(float a) {
	float cx = cos(a * 1.71), sx = sin(a * 1.71);
	float cy = cos(a * 2.33), sy = sin(a * 2.33);
	float cz = cos(a * 0.93), sz = sin(a * 0.93);
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cx, -sx), vec3(0.0, sx, cx));
	mat3 ry = mat3(vec3(cy, 0.0, sy), vec3(0.0, 1.0, 0.0), vec3(-sy, 0.0, cy));
	mat3 rz = mat3(vec3(cz, -sz, 0.0), vec3(sz, cz, 0.0), vec3(0.0, 0.0, 1.0));
	return rz * ry * rx;
}

float map(vec3 p, float tt, float sd) {
	p = seed_rot(sd) * p;
	p.xz = cos(tt * 0.1 + sd) * p.xz + sin(tt * 0.1 + sd) * vec2(p.z, -p.x);
	return volumetric_explosion(p / 0.5, tt, sd) * 0.5;
}

// assign color to the media
vec3 compute_color(float density, float radius) {
	vec3 result = mix(vec3(1.0, 0.9, 0.8), vec3(0.4, 0.15, 0.1), density);
	vec3 col_center = 7.0 * vec3(0.8, 1.0, 1.0);
	vec3 col_edge = 1.5 * vec3(0.48, 0.53, 0.5);
	result *= mix(col_center, col_edge, min((radius + 0.05) / 0.9, 1.15));
	return result;
}

bool ray_sphere(vec3 org, vec3 dir, out float near, out float far) {
	float b = dot(dir, org);
	float c = dot(org, org) - 8.0;
	float delta = b * b - c;
	if (delta < 0.0) {
		return false;
	}
	float ds = sqrt(delta);
	near = -b - ds;
	far = -b + ds;
	return far > 0.0;
}

void vertex() {
	qpos = VERTEX.xy;
	mat4 bb = mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// clamp before the 10 s cycle wraps (a burst must not re-ignite)
	float tt = min(lt * time_scale, 8.5);
	vec2 uv = qpos + vec2(0.5);
	vec3 rd = normalize(vec3(qpos * 2.0, 1.55));
	vec3 ro = vec3(0.0, 0.0, -6.0);

	float ld = 0.0;
	float td = 0.0;
	float w = 0.0;
	// The original declares `float d = map(pos);` INSIDE the loop, shadowing
	// this outer d, so the `d < 0.12*t` break always tests the initial 1.0.
	float d = 1.0;
	float t = 0.0;
	const float h = 0.1;
	vec4 sum = vec4(0.0);
	float min_dist = 0.0;
	float max_dist = 0.0;

	if (ray_sphere(ro, rd, min_dist, max_dist)) {
		t = min_dist * step(t, min_dist);
		for (int i = 0; i < 86; i++) {
			vec3 pos = ro + rd * t;
			if (td > 0.9 || d < 0.12 * t || t > 10.0 || sum.a > 0.99 || t > max_dist) {
				break;
			}
			float dl = map(pos, tt, seed);
			if (split_mode == 0) {
				dl = cos(tt) * uv.x < 0.1 ? abs(dl) + 0.07 : dl;
			} else if (split_mode == 1) {
				dl = abs(dl) + 0.07;
			}
			dl = max(dl, 0.03);

			vec3 ldst = vec3(0.0) - pos;
			float ldist = max(length(ldst), 0.001);
			vec3 light_col = vec3(1.0, 0.5, 0.25);
			sum.rgb += light_col / exp(ldist * ldist * ldist * 0.08) / 30.0;

			if (dl < h) {
				ld = h - dl;
				w = (1.0 - td) * ld;
				td += w + 1.0 / 200.0;
				vec4 col = vec4(compute_color(td, ldist), td);
				sum += sum.a * vec4(sum.rgb, 0.0) * 0.2 / ldist;
				col.a *= 0.2;
				col.rgb *= col.a;
				sum = sum + col * (1.0 - sum.a);
			}

			td += 1.0 / 70.0;
			// DITHERING: iChannel2 = grey noise small (64x64)
			vec2 uvd = uv;
			uvd.y *= 120.0;
			uvd.x *= 280.0;
			dl = abs(dl) * (0.8 + 0.08 * texture(noise2_tex,
				vec2(uvd.y, -uvd.x + 0.5 * sin(4.0 * tt + uvd.y * 4.0))).r);

			t += max(dl * 0.08 * max(min(length(ldst), dl), 2.0), 0.01);
		}

		sum *= 1.0 / exp(ld * 0.2) * 0.8;
		sum = clamp(sum, 0.0, 1.0);
		sum.xyz = sum.xyz * sum.xyz * (3.0 - 2.0 * sum.xyz);
	}

	// the 3D pipeline tonemaps + converts linear->sRGB, while the original
	// shader wrote display-space values straight to the framebuffer.
	ALBEDO = pow(max(sum.rgb, vec3(0.0)), vec3(2.2)) * intensity * fade;
	ALPHA = clamp(sum.a * 2.2, 0.0, 0.95) * fade;
}