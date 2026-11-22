extends RefCounted
## 人形机甲的招式数据。时间为秒，位移为场景单位。

const FAST := &"fast"
const DELAYED := &"delayed"
const DASH := &"dash"

# 姿态列：时间、刀柄位置（机体局部）、刀身方位角、刀身仰角、
# 躯干扭转角、前倾角、下沉量。刀身角度均为度，-Z 为前。
const MOVES := {
	FAST: {
		"title": "快横斩", "damage": 18.0, "active": Vector2(0.27, 0.41),
		"duration": 0.84, "travel": Vector2(0.22, 0.41), "advance": 1.2,
		"keys": [
			[0.15, Vector3(1.04, 3.02, -0.32), 116.0, 17.0, -32.0, -5.0, 0.12],
			[0.27, Vector3(0.90, 2.95, -0.68), 76.0, 5.0, -19.0, 4.0, 0.15],
			[0.33, Vector3(0.12, 2.87, -0.94), 0.0, -3.0, 2.0, 11.0, 0.20],
			[0.41, Vector3(-0.70, 2.88, -0.75), -100.0, -10.0, 44.0, 12.0, 0.23],
			[0.53, Vector3(-0.78, 2.90, -0.65), -115.0, -19.0, 48.0, 13.0, 0.24],
		],
	},
	DELAYED: {
		"title": "延迟重斩", "damage": 30.0, "active": Vector2(0.85, 1.01),
		"duration": 1.67, "travel": Vector2(0.76, 1.05), "advance": 1.75,
		"keys": [
			[0.31, Vector3(0.60, 3.86, -0.32), 15.0, 142.0, -23.0, -13.0, 0.10],
			[0.70, Vector3(0.61, 3.88, -0.30), 15.0, 148.0, -24.0, -11.0, 0.10],
			[0.81, Vector3(0.55, 3.69, -0.58), 13.0, 110.0, -12.0, 0.0, 0.19],
			[0.85, Vector3(0.48, 3.43, -0.75), 12.0, 68.0, -7.0, 10.0, 0.28],
			[0.91, Vector3(0.30, 3.08, -0.93), 5.0, 2.0, 2.0, 18.0, 0.38],
			[1.01, Vector3(0.16, 2.33, -1.12), -4.0, -62.0, 9.0, 28.0, 0.48],
			[1.25, Vector3(0.16, 2.33, -1.12), -4.0, -62.0, 9.0, 28.0, 0.48],
		],
	},
	DASH: {
		"title": "红闪突进斩", "damage": 35.0, "active": Vector2(0.55, 0.73),
		"duration": 1.48, "travel": Vector2(0.40, 0.80), "advance": 8.8,
		"cue_at": 0.20, "cue_length": 0.11,
		"keys": [
			[0.20, Vector3(0.84, 2.60, 0.08), 140.0, 8.0, -31.0, 16.0, 0.30],
			[0.39, Vector3(0.93, 2.45, 0.19), 144.0, 5.0, -36.0, 26.0, 0.45],
			[0.55, Vector3(0.87, 2.37, -0.69), 68.0, 3.0, -18.0, 32.0, 0.46],
			[0.62, Vector3(0.11, 2.41, -1.03), 0.0, -2.0, 5.0, 30.0, 0.43],
			[0.73, Vector3(-0.76, 2.51, -0.67), -103.0, -11.0, 52.0, 26.0, 0.42],
			[1.00, Vector3(-0.81, 2.60, -0.57), -124.0, -12.0, 55.0, 17.0, 0.40],
		],
	},
}

const NEUTRAL_GRIP := Vector3(0.86, 2.88, -0.64)
const NEUTRAL_ANGLES := Vector2(38.0, 34.0)


static func pose(move: Dictionary, elapsed: float) -> Dictionary:
	var from: Array = [0.0, NEUTRAL_GRIP, NEUTRAL_ANGLES.x, NEUTRAL_ANGLES.y, 0.0, 0.0, 0.0]
	var to := from
	if not move.is_empty():
		for key: Array in move["keys"]:
			to = key
			if elapsed <= float(key[0]):
				break
			from = key
		if to == from:
			to = [move["duration"], NEUTRAL_GRIP, NEUTRAL_ANGLES.x, NEUTRAL_ANGLES.y, 0.0, 0.0, 0.0]
	var u := smoothstep(float(from[0]), maxf(float(to[0]), float(from[0]) + 0.001), elapsed)
	return {
		"grip": (from[1] as Vector3).lerp(to[1], u),
		"azimuth": deg_to_rad(lerpf(from[2], to[2], u)),
		"elevation": deg_to_rad(lerpf(from[3], to[3], u)),
		"twist": deg_to_rad(lerpf(from[4], to[4], u)),
		"lean": deg_to_rad(lerpf(from[5], to[5], u)),
		"drop": lerpf(from[6], to[6], u),
	}
