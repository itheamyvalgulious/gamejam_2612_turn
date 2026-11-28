shader_type sky;
// 近地轨道：黑底、细星、一条很淡的银河带，加一个极小的太阳盘。
// 星星用球面网格 + 格子内的圆形衰减，不再是一格一个方块。

uniform vec3 sun_dir = vec3(-0.55, 0.52, -0.65);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.86);
uniform float star_grid = 900.0;
uniform vec3 galaxy_normal = vec3(0.32, 0.86, 0.40);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = vec3(0.0016, 0.0028, 0.0064);

	// 银河带：很暗的一层灰蓝，不要抢星星
	vec3 gn = normalize(galaxy_normal);
	float band = 1.0 - smoothstep(0.0, 0.19, abs(dot(d, gn)));
	float dust = hash13(floor(d * 160.0));
	col += vec3(0.008, 0.012, 0.024) * band * (0.55 + 0.65 * dust);

	// 细星：高密度网格 + 格内圆形衰减
	vec3 gp = d * star_grid;
	vec3 cell = floor(gp);
	vec3 f = fract(gp) - 0.5;
	float h = hash13(cell);
	if (h > 0.99855) {
		float r = length(f);
		float core = smoothstep(0.46, 0.02, r);
		float b = (h - 0.99855) / 0.00145;
		vec3 tint = mix(vec3(0.76, 0.85, 1.0), vec3(1.0, 0.89, 0.74), hash13(cell + 7.0));
		col += tint * core * (0.30 + b * 1.25);
	}

	// 少量亮星
	vec3 gp2 = d * (star_grid * 0.29);
	vec3 cell2 = floor(gp2);
	vec3 f2 = fract(gp2) - 0.5;
	float h2 = hash13(cell2 + 19.0);
	if (h2 > 0.99965) {
		float r2 = length(f2);
		float core2 = smoothstep(0.40, 0.02, r2);
		vec3 tint2 = mix(vec3(0.72, 0.84, 1.0), vec3(1.0, 0.86, 0.70), hash13(cell2 + 3.0));
		col += tint2 * core2 * 1.15;
	}

	// 太阳：小盘 + 很弱的日冕
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_color * pow(sd, 4600.0) * 14.0;
	col += sun_color * pow(sd, 90.0) * 0.055;

	COLOR = col;
}
