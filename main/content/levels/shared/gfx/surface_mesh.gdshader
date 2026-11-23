shader_type spatial;
// 程序化表面：世界坐标噪声 -> 脏污、粗糙度变化、法线扰动。
// 目的：把纯色盒子（纸箱、货架、墙板、货柜）压出粗糙感，不依赖贴图。

uniform vec3 albedo : source_color = vec3(0.35, 0.28, 0.19);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float noise_scale = 1.8;
uniform float grime : hint_range(0.0, 1.0) = 0.30;
uniform float bump : hint_range(0.0, 1.0) = 0.50;
uniform float tint_var : hint_range(0.0, 1.0) = 0.10;
uniform float streak : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dirt_col : source_color = vec3(0.05, 0.045, 0.04);

varying vec3 wp;
varying vec3 wn;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.11 + vec2(5.3, 1.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 三向投影：竖直面不能用 wp.xz（那样沿 y 不变，会拉成一条条竖纹）
	vec3 an = abs(normalize(wn));
	vec2 uv;
	if (an.y > max(an.x, an.z)) {
		uv = wp.xz;
	} else if (an.x > an.z) {
		uv = vec2(wp.z, wp.y);
	} else {
		uv = vec2(wp.x, wp.y);
	}
	float base = fbm(uv * noise_scale);

	// 远处淡化高频细节，避免细噪声在远表面上闪烁成噪点
	float dist = length(wp - CAMERA_POSITION_WORLD);
	float fade = clamp(1.0 - dist / 40.0, 0.10, 1.0);
	float fine = mix(0.5, fbm(uv * noise_scale * 6.5), fade);
	// 法线扰动只在近处生效：远处保留高频扰动会在掠射角炸出高光噪点
	float bfade = clamp(1.0 - dist / 16.0, 0.0, 1.0);
	bfade *= bfade;

	// 法线扰动：世界空间梯度 -> 视图空间（NORMAL 在 fragment 里是视图空间）
	float e = 0.012;
	float hx = fbm((uv + vec2(e, 0.0)) * noise_scale * 6.5);
	float hz = fbm((uv + vec2(0.0, e)) * noise_scale * 6.5);
	vec3 grad = vec3(hx - fine, 0.0, hz - fine) / e;
	grad *= bfade;
	vec3 gv = (VIEW_MATRIX * vec4(grad, 0.0)).xyz;
	gv -= NORMAL * dot(gv, NORMAL);
	NORMAL = normalize(NORMAL - gv * bump * 0.06);

	// 颜色：轻微色差 + 脏污 + 竖向流痕
	vec3 col = albedo * (1.0 + tint_var * (base - 0.5) * 2.0);
	if (streak > 0.001) {
		float st = fbm(vec2(uv.x * 5.0, wp.y * 0.35));
		col = mix(col, dirt_col, streak * smoothstep(0.50, 0.92, st) * 0.55);
	}
	float g = clamp(grime * (0.65 * fine + 0.35 * base), 0.0, 1.0);
	col = mix(col, dirt_col, g * 0.5);

	ALBEDO = col;
	ROUGHNESS = clamp(roughness + (base - 0.5) * 0.22, 0.04, 1.0);
	METALLIC = metallic;
}
