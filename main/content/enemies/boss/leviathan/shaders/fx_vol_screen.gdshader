shader_type canvas_item;
// 1:1 port of "Volumetric explosion" by Duke
// https://www.shadertoy.com/view/lsySzd (CC BY-NC-SA 3.0)
// iChannel0 = the original 256x256 RGBA noise medium texture;
// iChannel2 = the original 64x64 grey noise texture. iChannel1 (keyboard) is
// not needed because no zoom key is pressed in the reference capture.
render_mode unshaded;

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D noise2_tex : filter_linear, repeat_enable;
uniform float t_override = -1.0;
uniform int variant = 0;   // 0 = original BOTH, 1 = plain d, 2 = abs(d)+0.07
uniform float zoom_key = 0.0;
uniform int debug_mode = 0;

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

float volumetric_explosion(vec3 p, float tt) {
	float final_d = sphere_sdf(p, 4.0);
	final_d += fbm(p * 50.0);
	final_d += spiral_noise(p.zxy * 0.4132 + 333.0, tt) * 3.0;
	return final_d;
}

float map(vec3 p, float tt) {
	float a = tt * 0.1;
	p.xz = cos(a) * p.xz + sin(a) * vec2(p.z, -p.x);
	return volumetric_explosion(p / 0.5, tt) * 0.5;
}

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

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 frag = FRAGCOORD.xy;
	vec2 uv = frag / res;
	float tt = t_override >= 0.0 ? t_override : TIME;

	vec3 rd = normalize(vec3((frag - 0.5 * res) / res.y, 1.0));
	vec3 ro = vec3(0.0, 0.0, -6.0 + zoom_key * 1.6);

	float min_dist = 0.0;
	float max_dist = 0.0;
	vec4 sum = vec4(0.0);
	float ld = 0.0;
	float td = 0.0;
	float w = 0.0;
	// NOTE: the original declares `float d = map(pos);` INSIDE the loop, which
	// shadows the outer d. The break test `d < 0.12*t` therefore always sees the
	// outer d = 1.0. Keeping that behaviour is what makes the volume fill up.
	float d = 1.0;
	float t = 0.0;
	const float h = 0.1;
	bool hit = ray_sphere(ro, rd, min_dist, max_dist);

	if (hit) {
		t = min_dist * step(t, min_dist);
		for (int i = 0; i < 86; i++) {
			vec3 pos = ro + rd * t;
			if (td > 0.9 || d < 0.12 * t || t > 10.0 || sum.a > 0.99 || t > max_dist) {
				break;
			}
			float dl = map(pos, tt);
			if (variant == 0) {
				dl = cos(tt) * uv.x < 0.1 ? abs(dl) + 0.07 : dl;
			} else if (variant == 2) {
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
			float dith = texture(noise2_tex, vec2(uvd.y,
				-uvd.x + 0.5 * sin(4.0 * tt + uvd.y * 4.0))).r;
			float dstep = abs(dl) * (0.8 + 0.08 * dith);
			t += max(dstep * 0.08 * max(min(length(ldst), dstep), 2.0), 0.01);
		}
		sum *= 1.0 / exp(ld * 0.2) * 0.8;
		sum = clamp(sum, 0.0, 1.0);
		sum.xyz = sum.xyz * sum.xyz * (3.0 - 2.0 * sum.xyz);
	}

	if (debug_mode == 1) {
		COLOR = vec4(uv, 0.0, 1.0);
	} else if (debug_mode == 2) {
		COLOR = vec4(vec3(hit ? 1.0 : 0.0), 1.0);
	} else if (debug_mode == 3) {
		float nz = noise(vec3(uv * 256.0, tt * 10.0));
		COLOR = vec4(vec3(nz), 1.0);
	} else {
		COLOR = vec4(sum.xyz, 1.0);
	}
}
