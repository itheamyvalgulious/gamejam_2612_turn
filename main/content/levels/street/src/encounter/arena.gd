extends "res://src/encounter/art.gd"
## 城市街道 P1 —— 160 m 主街 + 十字路口 + 装卸凹进 + 四车道车流。
## 无敌人，走到东端街角通关。
##
## 单位：全部是世界单位（1 u = 0.547 m），尺寸写成「米 × M」。
## 坐标：主街沿 X，x ∈ [-80, 80]（160 m）；街宽 26 m（z ∈ ±13 m）。
##   起点 x = -76 m，终点 x = +76 m；十字路口 x ∈ [20, 34] m。
##   支路南北各延伸 40 m，尽头有实体墙封住。

const M := 1.8281536
const HALF_WIDTH := 80.0 * M     # x ±80 m
const HALF_DEPTH := 60.0 * M     # z ±60 m（给支路留空间）
const CEILING := 32.0 * M
const ROAD_HALF := 8.0 * M
const WALK_TOP := 0.15 * M

const SPAWN := Vector3(-76.0 * M, WALK_TOP, 10.0 * M)
const GOAL := Vector3(76.0 * M, WALK_TOP, 10.0 * M)

# 关键 x 位置（米）
const DOCK_X0 := -40.0
const DOCK_X1 := -30.0
const DOCK_SETBACK := 6.0       # 北侧建筑内表面后退
const CROSS_X0 := 20.0
const CROSS_X1 := 34.0

static func build() -> Dictionary:
	return new().build_scene()

func build_scene() -> Dictionary:
	root.name = "CityStreet"
	configure_city()
	kit.material("window_cool", glow(Color("9ec8e8"), 0.9))
	kit.material("window_warm", glow(Color("e0b184"), 0.8))
	_ground()
	_sidewalks()
	_buildings()
	_dock()
	_road_markings()
	_crossing()
	_interchange()
	_street_lamps()
	_lane_signs()
	weather()
	environment(true)
	_brighten()
	var result := finish("霓虹街道",
		"读车流空档过街，穿过十字路口抵达东侧街角。",
		Vector2(HALF_WIDTH, HALF_DEPTH), SPAWN, [])
	result["kind"] = "street"
	result["vertical"] = false
	result["ceiling"] = CEILING
	result["goal"] = GOAL
	result["lanes"] = [
		{"z": 2.3 * M, "dir": 1.0, "speed": 9.0 * M},
		{"z": 5.7 * M, "dir": 1.0, "speed": 7.5 * M},
		{"z": -2.3 * M, "dir": -1.0, "speed": 9.0 * M},
		{"z": -5.7 * M, "dir": -1.0, "speed": 7.5 * M},
	]
	neon_ring("cyan", 1.9 * M, 0.05 * M, 48, 8, GOAL + Vector3(0, 0.02 * M, 0))
	return result


func _brighten() -> void:
	for child in root.get_children():
		if child is WorldEnvironment:
			var env: Environment = (child as WorldEnvironment).environment
			env.ambient_light_energy = 0.42
			env.fog_density = 0.0012
			env.ssao_intensity = 0.9


func _ground() -> void:
	# 主街车行道，顶面 y = 0
	block("floor", Vector3(HALF_WIDTH * 2.0, 0.4 * M, ROAD_HALF * 2.0),
		Vector3(0.0, -0.2 * M, 0.0))
	# 支路路面（十字路口南北向），与主街同高
	var cross_cx: float = (CROSS_X0 + CROSS_X1) * 0.5 * M
	var cross_w: float = (CROSS_X1 - CROSS_X0) * M
	block("floor", Vector3(cross_w, 0.4 * M, 80.0 * M),
		Vector3(cross_cx, -0.2 * M, 0.0))
	# 支路两端封墙
	for z in [-40.0, 40.0]:
		block("wall", Vector3(cross_w, 12.0 * M, 1.0 * M),
			Vector3(cross_cx, 6.0 * M, float(z) * M))


func _sidewalks() -> void:
	# 主街两侧人行道（路口段断开）
	for side in [-1.0, 1.0]:
		var walk_w: float = 5.0 * M
		var walk_z: float = side * (ROAD_HALF + walk_w * 0.5)
		for span in [[-80.0, CROSS_X0], [CROSS_X1, 80.0]]:
			var x0: float = float(span[0]) * M
			var x1: float = float(span[1]) * M
			block("metal", Vector3(x1 - x0, 0.3 * M, walk_w),
				Vector3((x0 + x1) * 0.5, WALK_TOP - 0.15 * M, walk_z), true, true)
			block("ceramic", Vector3(x1 - x0, 0.34 * M, 0.3 * M),
				Vector3((x0 + x1) * 0.5, WALK_TOP - 0.17 * M,
					side * (ROAD_HALF + 0.15 * M)), true, true)


func _buildings() -> void:
	# 北侧：装卸段内表面后退 6 m；路口段完全断开
	var north := [
		[-80.0, DOCK_X0, 13.0, 16.0],
		[DOCK_X0, DOCK_X1, 13.0 + DOCK_SETBACK, 12.0],
		[DOCK_X1, CROSS_X0, 13.0, 21.0],
		[CROSS_X1, 80.0, 13.0, 18.0],
	]
	for seg in north:
		_facade_block(float(seg[0]), float(seg[1]), 1.0, float(seg[2]), float(seg[3]))
	# 南侧：路口断开
	for seg in [[-80.0, CROSS_X0, 19.0], [CROSS_X1, 80.0, 15.0]]:
		_facade_block(float(seg[0]), float(seg[1]), -1.0, 13.0, float(seg[2]))
	# 支路两侧
	for side in [-1.0, 1.0]:
		for zs in [[13.0, 40.0], [-40.0, -13.0]]:
			for xs in [[CROSS_X0 - 10.0, CROSS_X0], [CROSS_X1, CROSS_X1 + 10.0]]:
				block("wall", Vector3(10.0 * M, 17.0 * M, (float(zs[1]) - float(zs[0])) * M),
					Vector3((float(xs[0]) + float(xs[1])) * 0.5 * M, 8.5 * M,
						(float(zs[0]) + float(zs[1])) * 0.5 * M))
	# 装卸凹进的两侧翼墙
	for x in [DOCK_X0, DOCK_X1]:
		block("wall", Vector3(1.0 * M, 12.0 * M, DOCK_SETBACK * M),
			Vector3(float(x) * M, 6.0 * M, (13.0 + DOCK_SETBACK * 0.5) * M))


func _facade_block(x0: float, x1: float, side: float, face: float, height: float) -> void:
	var a: float = x0 * M
	var b: float = x1 * M
	var depth := 10.0 * M
	var h: float = height * M
	var face_z: float = side * face * M
	block("wall", Vector3(b - a, h, depth),
		Vector3((a + b) * 0.5, h * 0.5, face_z + side * depth * 0.5))
	# 楼层分隔线
	var y := 4.2 * M
	while y < h - 2.0 * M:
		block("dark", Vector3(b - a - 1.1 * M, 0.22 * M, 0.32 * M),
			Vector3((a + b) * 0.5, y, face_z - side * 0.16 * M), false)
		y += 3.6 * M
	# 底层橱窗 + 招牌灯带（按 13 m 间距）
	var count := maxi(1, int(round((x1 - x0) / 13.0)))
	var step: float = (x1 - x0) / float(count)
	for i in count:
		var cx: float = (x0 + (float(i) + 0.5) * step) * M
		var lit: bool = i % 2 == 0
		block("window_cool" if lit else "window_warm",
			Vector3(minf(6.6, step * 0.72) * M, 2.6 * M, 0.1 * M),
			Vector3(cx, 2.0 * M, face_z - side * 0.22 * M), false)
		block("glass", Vector3(minf(7.2, step * 0.8) * M, 3.0 * M, 0.16 * M),
			Vector3(cx, 2.0 * M, face_z - side * 0.06 * M), false)
		for dx in [-0.9, 0.0, 0.9]:
			block("frame", Vector3(0.16 * M, 3.2 * M, 0.26 * M),
				Vector3(cx + float(dx) * minf(3.5, step * 0.4) * M, 2.0 * M,
					face_z - side * 0.12 * M), false)
		var key := "cyan" if i % 2 == 0 else "magenta"
		tube(key, Vector3(cx - 3.0 * M, 4.15 * M, face_z - side * 0.34 * M),
			Vector3(cx + 3.0 * M, 4.15 * M, face_z - side * 0.34 * M), 0.05 * M)
	# 高层窗格
	var row := 0
	var fy := 6.0 * M
	while fy < minf(h - 2.0 * M, 15.0 * M):
		for k in count:
			var wx: float = (x0 + (float(k) + 0.5) * step) * M
			if (row + k) % 3 != 0:
				block("window_warm" if (row + k) % 2 == 0 else "window_cool",
					Vector3(minf(3.2, step * 0.35) * M, 1.5 * M, 0.1 * M),
					Vector3(wx, fy, face_z - side * 0.18 * M), false)
		fy += 3.6 * M
		row += 1


func _dock() -> void:
	# 装卸平台：0.8 m 高，可跳上；两侧留 1.2 m 台阶
	var cx: float = (DOCK_X0 + DOCK_X1) * 0.5 * M
	block("metal", Vector3((DOCK_X1 - DOCK_X0) * M, 0.8 * M, 5.0 * M),
		Vector3(cx, 0.4 * M, 16.0 * M), true, true)
	# 平台边缘的缓冲块与两只货箱
	for x in [DOCK_X0 + 1.5, DOCK_X1 - 1.5]:
		block("dark", Vector3(1.6 * M, 0.6 * M, 1.6 * M),
			Vector3(float(x) * M, 1.1 * M, 16.0 * M), true, false)
	block("teal", Vector3(2.4 * M, 1.6 * M, 2.4 * M),
		Vector3((DOCK_X0 + 4.0) * M, 1.6 * M, 17.5 * M), true, false)
	block("teal", Vector3(2.0 * M, 1.2 * M, 2.0 * M),
		Vector3((DOCK_X1 - 4.0) * M, 1.4 * M, 17.0 * M), true, false)
	# 凹进上方的楼板，形成装卸门洞
	block("dark", Vector3((DOCK_X1 - DOCK_X0) * M, 0.6 * M, DOCK_SETBACK * M),
		Vector3(cx, 5.5 * M, (13.0 + DOCK_SETBACK * 0.5) * M), false)
	downlight(Vector3(cx, 5.0 * M, 17.5 * M), Color("ffd9a8"), 2.2, 8.0 * M)
	tube("amber", Vector3(DOCK_X0 * M, 1.0 * M, 18.6 * M),
		Vector3(DOCK_X1 * M, 1.0 * M, 18.6 * M), 0.04 * M)


func _road_markings() -> void:
	# 中央双黄线（路口处断开）
	for dz in [-0.18, 0.18]:
		for span in [[-80.0, CROSS_X0], [CROSS_X1, 80.0]]:
			var x0: float = float(span[0]) * M
			var x1: float = float(span[1]) * M
			block("warm", Vector3(x1 - x0, 0.02 * M, 0.12 * M),
				Vector3((x0 + x1) * 0.5, 0.012 * M, float(dz) * M), false)
	# 车道虚线：内侧/外侧之间 z = ±4.0 m
	for side in [-1.0, 1.0]:
		for x in range(-78, 80, 6):
			var xm: float = float(x)
			if xm > CROSS_X0 - 4.0 and xm < CROSS_X1 + 2.0:
				continue
			block("ceramic", Vector3(2.6 * M, 0.02 * M, 0.12 * M),
				Vector3((xm + 1.3) * M, 0.012 * M, side * 4.0 * M), false)


func _crossing() -> void:
	# 主街第一处斑马线（x = -60 m）+ 中央安全岛
	for i in 11:
		var z: float = (-7.6 + float(i) * 1.5) * M
		block("ceramic", Vector3(2.4 * M, 0.02 * M, 0.7 * M),
			Vector3(-60.0 * M, 0.012 * M, z), false)
	block("ceramic", Vector3(8.0 * M, 0.4 * M, 2.4 * M),
		Vector3(-60.0 * M, 0.0, 0.0), true, true)
	for x in [-63.6, -56.4]:
		block("amber", Vector3(0.5 * M, 0.1 * M, 2.4 * M),
			Vector3(float(x) * M, 0.24 * M, 0.0), false)


func _interchange() -> void:
	# 路口四条斑马线（东西向各一条，南北向各一条）
	for x in [CROSS_X0 - 4.0, CROSS_X1 + 4.0]:
		for i in 11:
			var z: float = (-7.6 + float(i) * 1.5) * M
			block("ceramic", Vector3(2.4 * M, 0.02 * M, 0.7 * M),
				Vector3(float(x) * M, 0.012 * M, z), false)
	for z in [13.0, -13.0]:
		for i in 9:
			var x: float = (CROSS_X0 + 1.6 + float(i) * 1.5) * M
			block("ceramic", Vector3(0.7 * M, 0.02 * M, 2.4 * M),
				Vector3(x, 0.012 * M, float(z) * M), false)


func _street_lamps() -> void:
	for x in [-72.0, -60.0, -48.0, -36.0, -24.0, -12.0, 0.0, 12.0, 24.0,
			36.0, 48.0, 60.0, 72.0]:
		if x > CROSS_X0 - 2.0 and x < CROSS_X1 + 2.0:
			continue
		for side in [-1.0, 1.0]:
			var z: float = side * (ROAD_HALF + 1.2 * M)
			block("dark", Vector3(0.26 * M, 7.0 * M, 0.26 * M),
				Vector3(float(x) * M, 3.5 * M, z))
			block("dark", Vector3(0.2 * M, 0.2 * M, 2.6 * M),
				Vector3(float(x) * M, 6.9 * M, z - side * 1.2 * M), false)
			downlight(Vector3(float(x) * M, 6.7 * M, z - side * 2.1 * M),
				Color("cfe3f2"), 3.0, 15.0 * M)


func _lane_signs() -> void:
	for side in [-1.0, 1.0]:
		for x in [-64.0, -28.0, 6.0, 40.0, 62.0]:
			var z: float = side * 12.0 * M
			block("dark", Vector3(0.18 * M, 3.4 * M, 0.18 * M),
				Vector3(float(x) * M, 1.7 * M, z))
			block("frame", Vector3(2.6 * M, 0.7 * M, 0.1 * M),
				Vector3(float(x) * M, 3.2 * M, z - side * 0.1 * M), false)
			tube("amber", Vector3((float(x) - 1.1) * M, 3.2 * M, z - side * 0.16 * M),
				Vector3((float(x) + 1.1) * M, 3.2 * M, z - side * 0.16 * M), 0.035 * M)
