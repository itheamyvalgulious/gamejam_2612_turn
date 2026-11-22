extends RefCounted
class_name Vision
## 「你看见了吗」——本 demo 的核心判定。
##
## 规则（用户定的）：只按相机画面算，零余量。敌人包围球必须**完全落在画面之外**
## 才算「看不见」：只要球体有任何一个采样点进视锥，或者它在屏幕上的投影圆与
## 视口矩形有交集，就算被看见。
##
## 这个判定同时驱动三件事：
##   小怪  —— 被看见时 100% 格挡你的攻击
##   远程怪 —— 弹反瞬间正对它 → 它补射一箭打掉你的弹回箭
##   大怪  —— 被看见即激光秒杀

## 球面采样方向：6 轴 + 8 斜角（对球体来说这 14 个方向足以覆盖极值）
const DIRS := [
	Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0),
	Vector3(0, 0, 1), Vector3(0, 0, -1),
	Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(1, -1, 1), Vector3(1, -1, -1),
	Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, 1), Vector3(-1, -1, -1),
]


static func fully_offscreen(cam: Camera3D, center: Vector3, radius: float) -> bool:
	if cam == null:
		return true
	var vp := cam.get_viewport()
	if vp == null:
		return true
	var rect_size: Vector2 = vp.get_visible_rect().size
	# 相机在球里 → 当然看得见
	if cam.global_position.distance_to(center) <= radius:
		return false

	# 1) 球面极值采样点是否进视锥
	var k := radius / sqrt(3.0)
	for d in DIRS:
		if cam.is_position_in_frustum(center + d * k):
			return false
	if cam.is_position_in_frustum(center):
		return false

	# 2) 屏幕投影圆是否与视口矩形相交（处理"中心在画面外但球压到边缘"）
	var cam_to: Vector3 = center - cam.global_position
	if cam_to.dot(-cam.global_transform.basis.z) <= cam.near:
		# 在相机背后：只有整块都不在视锥里才算看不见（上面已经检查过采样点）
		return true
	var sp: Vector2 = cam.unproject_position(center)
	var edge_pt: Vector3 = center + cam.global_transform.basis.x * radius
	var sp2: Vector2 = cam.unproject_position(edge_pt)
	var r_px: float = sp.distance_to(sp2)
	if r_px < 1.0:
		r_px = 1.0
	var closest := Vector2(clampf(sp.x, 0.0, rect_size.x), clampf(sp.y, 0.0, rect_size.y))
	if sp.distance_to(closest) <= r_px:
		return false
	return true


## 反过来：「画面里有人能看见某个点」——给 boss 激光/小怪格挡用同一套
static func is_visible(cam: Camera3D, center: Vector3, radius: float) -> bool:
	return not fully_offscreen(cam, center, radius)


## 视线是否被墙段挡住（2D 俯视），可选功能，由 rules.vision_occlusion 开关
static func los_blocked_2d(a: Vector2, b: Vector2, wall_segments: Array) -> bool:
	for w in wall_segments:
		var p0: Vector2 = w["a"]
		var p1: Vector2 = w["b"]
		if _segments_cross(a, b, p0, p1):
			return true
	return false


static func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var r := b - a
	var s := d - c
	var denom := r.x * s.y - r.y * s.x
	if absf(denom) < 1e-6:
		return false
	var t := ((c - a).x * s.y - (c - a).y * s.x) / denom
	var u := ((c - a).x * r.y - (c - a).y * r.x) / denom
	return t > 0.001 and t < 0.999 and u > 0.001 and u < 0.999
