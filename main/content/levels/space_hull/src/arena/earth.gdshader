shader_type spatial;
// 近地轨道地球：海/陆/云 + 昼夜线 + 大气边缘光，无贴图，全程序化。
// 表面花纹用局部法线，昼夜和大气边缘用世界法线，避免相机转动时高光乱跑。

render_mode unshaded, cull_back;

uniform vec3 sun_dir = vec3(-0.55, 0.52, -0.65);
uniform vec3 ocean_color = vec3(0.006, 0.026, 0.080);
uniform vec3 land_color = vec3(0.045, 0.078, 0.040);
uniform vec3 desert_color = vec3(0.220, 0.175, 0.095);
uniform vec3 cloud_color = vec3(0.640, 0.675, 0.700);
uniform vec3 night_color = vec3(0.003, 0.006, 0.013);
uniform vec3 atmo_color = vec3(0.180, 0.400, 0.860);

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_wn;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_local = normalize(VERTEX);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_local);
	vec3 wn = normalize(v_wn);
	float c = fbm(n * 2.7);
	float land = smoothstep(0.50, 0.58, c);
	float desert = smoothstep(0.52, 0.66, fbm(n * 3.4 + 11.0));
	vec3 surface = mix(ocean_color, land_color, land);
	surface = mix(surface, desert_color, desert * land * 0.55);

	// 极冠
	float ice = smoothstep(0.74, 0.88, abs(n.y));
	surface = mix(surface, vec3(0.68, 0.74, 0.80), ice);

	// 云层
	float cl = smoothstep(0.53, 0.72, fbm(n * 5.2 + 23.0));
	surface = mix(surface, cloud_color, cl * 0.62);

	// 昼夜：世界空间，太阳在玩家背后，所以面向玩家的一侧是白天
	vec3 sun = normalize(sun_dir);
	float day = smoothstep(-0.14, 0.30, dot(wn, sun));
	vec3 lit = surface * (0.022 + 0.88 * day);

	// 夜面城市光
	float city = smoothstep(0.62, 0.70, fbm(n * 9.0 + 41.0)) * (1.0 - day) * (1.0 - cl);
	lit += vec3(1.0, 0.70, 0.34) * city * 0.45;

	// 大气边缘：用世界法线和真实视线方向
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - v_world);
	float fres = pow(1.0 - abs(dot(wn, vdir)), 3.0);
	lit += atmo_color * fres * (0.16 + 0.66 * day);

	ALBEDO = lit;
	EMISSION = vec3(0.0);
}
