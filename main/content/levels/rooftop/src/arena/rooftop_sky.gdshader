shader_type sky;
// 傍晚天空：上方纯蓝，地平线一圈暖橙带，太阳方向再加一层辉光。
// 用 smoothstep 把暖带压在低仰角，pow 渐变会把整片天都染成粉紫。

uniform vec3 top_color : source_color = vec3(0.150, 0.320, 0.700);
uniform vec3 horizon_color : source_color = vec3(0.980, 0.545, 0.250);
uniform vec3 ground_color : source_color = vec3(0.070, 0.062, 0.066);
uniform vec3 sun_color : source_color = vec3(1.0, 0.72, 0.44);
uniform vec3 sun_dir = vec3(-0.86, 0.32, -0.18);
uniform float horizon_height = 0.24;
uniform float sun_glow = 0.60;
uniform float sun_size = 0.9990;

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;

	// 暖带只在 horizon_height 以下，往上是纯蓝
	float band = 1.0 - smoothstep(0.0, max(horizon_height, 0.01), clamp(y, 0.0, 1.0));
	vec3 col = mix(top_color, horizon_color, band);

	// 地平线内侧再亮一点，形成一条“余晖”
	float rim = 1.0 - smoothstep(0.0, 0.06, abs(y));
	col = mix(col, horizon_color * 1.10, rim * 0.55);

	// 太阳方向的辉光 + 日轮
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_color * pow(sd, 8.0) * sun_glow;
	col += sun_color * smoothstep(sun_size, 0.99975, sd) * 2.4;

	// 地平线以下压暗
	if (y < 0.0) {
		col = mix(col, ground_color, clamp(-y * 7.0, 0.0, 1.0));
	}

	COLOR = col;
}
