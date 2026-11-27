extends RefCounted
## Sweep a held blade against level geometry, then yield at the grip.
## Pose and collision always use the same hilt and blade axis.
##
## 纯解析实现：地形判定走 LevelGeometry（arena 元信息生成的凸体 + GJK），
## 本文件不再出现 PhysicsDirectSpaceState / ShapeQuery / 碰撞层。

const LevelGeometry = preload("res://core/level_geometry.gd")

const RECOVERY_TIME := 0.50
const SKIN := 0.025
const CAPSULE_RADIUS := 0.085        # 无 blade_proxy 时的外接胶囊半径（旧行为）

var impact: Dictionary = {}
var recovering: bool:
	get:
		return _age < RECOVERY_TIME

var _span := Vector2.ZERO
var _previous := Transform3D.IDENTITY
var _initialized := false
var _age := RECOVERY_TIME
var _contact_pose := Transform3D.IDENTITY
var _normal := Vector3.ZERO
var _slide := Vector3.ZERO
var _fold := Vector3.ZERO
var _last_strike := -1


func reset() -> void:
	_initialized = false
	_age = RECOVERY_TIME
	_last_strike = -1
	impact.clear()


## geometry: LevelGeometry（arena 元信息建的解析地形）。
## proxy: 可选 BladeProxy；给定时按真实凸体块判定，缺省退回外接胶囊。
func advance(geometry, authored: Transform3D, span: Vector2,
		shoulder: Vector3, dt: float, strike := -1, proxy = null) -> Transform3D:
	impact.clear()
	var scale := authored.basis.get_scale()
	_span = span * scale.y
	var desired := authored.orthonormalized()
	if geometry == null:
		_previous = desired
		_initialized = true
		_age = minf(_age + dt, RECOVERY_TIME)
		desired.basis = desired.basis.scaled_local(scale)
		return desired
	var pieces := _scaled_pieces(proxy, span, scale)
	var radius := 0.0
	if pieces.is_empty():
		# proxy 缺失或所有块都被 span 滤掉：退回旧胶囊，刀不能空判。
		pieces = [{"v": _capsule_piece(span, scale)}]
		radius = CAPSULE_RADIUS * scale.x
	if not _initialized:
		_previous = desired
		_initialized = true
	_age = minf(_age + dt, RECOVERY_TIME)
	var target := _recovery(desired) if recovering else desired
	var incoming := _sweep(geometry, _previous, target, pieces, radius, desired.origin - _previous.origin)
	var pose: Transform3D = incoming["pose"]
	if incoming.has("point") and not recovering and strike >= 0 and strike != _last_strike:
		_last_strike = strike
		_normal = incoming["normal"]
		var point: Vector3 = incoming["point"]
		var blade_point := pose.affine_inverse() * point
		var travel := (desired * blade_point - _previous * blade_point) / maxf(dt, 0.001)
		var incidence := clampf(-travel.normalized().dot(_normal), 0.0, 1.0)
		var tangent := travel.slide(_normal)
		_slide = tangent.limit_length(6.0) * lerpf(0.075, 0.012, smoothstep(0.24, 0.76, incidence))
		_fold = (shoulder - pose.origin).normalized()
		# The elbow may fold toward the shoulder, but never feed pressure back into the wall.
		if _fold.dot(_normal) < 0.0:
			_fold = _fold.slide(_normal)
		_contact_pose = pose
		_age = 0.0
		impact = {"point": point, "normal": _normal, "incidence": incidence,
			"strength": clampf(maxf(-travel.dot(_normal), tangent.length() * 0.2) / 6.0, 0.2, 1.0)}
	elif incoming.has("point"):
		if not _contact(geometry, pose, pieces, radius).is_empty():
			# A reset or a moving support can start inside a collider.
			pose = _clear_overlap(geometry, pose, shoulder, pieces, radius)
		elif not recovering and not _contact(geometry, target, pieces, radius).is_empty():
			# If idle carry is obstructed, tuck the hilt while the actor keeps moving.
			var tucked := _clear_overlap(geometry, target, shoulder, pieces, radius)
			pose = _sweep(geometry, pose, tucked, pieces, radius, tucked.origin - pose.origin)["pose"]
	_previous = pose
	pose.basis = pose.basis.scaled_local(scale)
	return pose


func shoulder_recoil() -> Vector3:
	var envelope := smoothstep(0.0, 0.105, _age) * (1.0 - smoothstep(0.14, 0.43, _age))
	return (_normal - _slide * 0.45) * envelope


func _recovery(desired: Transform3D) -> Transform3D:
	var early := smoothstep(0.0, 0.14, _age)
	var release := smoothstep(0.02, 0.23, _age)
	var settle := smoothstep(0.15, RECOVERY_TIME, _age)
	var pose := _contact_pose.interpolate_with(desired, settle)
	var withdraw := _slide * early + _normal * (0.18 * early + 0.18 * release) + _fold * (0.23 * release)
	pose.origin += withdraw * (1.0 - settle)
	return pose


## 把 blade_proxy 的 piece 顶点预乘缩放（authored 是带尺度的变换，
## sweep/接触都用去尺度正交 pose，所以顶点要自己带缩放）。
## 无 proxy 时退回旧胶囊：跨度 [span.x, span.y]、半径 CAPSULE_RADIUS。
func _scaled_pieces(proxy, span: Vector2, scale: Vector3) -> Array:
	if proxy == null or proxy.pieces.is_empty():
		return []
	var out: Array = []
	for piece in proxy.pieces:
		# 只取与刀身 span 重叠的块：柄件/护手在 span.x 之下，旧胶囊判定时
		# 就不算刀身 —— 不然贴地收刀时护手会先撞地。
		var ab: AABB = piece["aabb"]
		if ab.position.y > span.y or ab.end.y < span.x:
			continue
		var v := PackedVector3Array()
		for p: Vector3 in piece["v"]:
			v.append(p * scale)
		out.append({"v": v})
	return out


## 胶囊轴心段（两点凸包）+ CAPSULE_RADIUS → 等价旧 CapsuleShape3D 判定。
static func _capsule_piece(span: Vector2, scale: Vector3) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(0.0, span.x, 0.0) * scale,
		Vector3(0.0, span.y, 0.0) * scale])


func _sweep(geometry, from: Transform3D, to: Transform3D, pieces: Array,
		radius: float, hint: Vector3) -> Dictionary:
	# Subdivide both rotation and translation so a sword rotating around a stationary
	# hand can still hit a thin railing, even on a low frame rate.
	var result: Dictionary = geometry.sweep_blade(from, to, pieces, radius, _span.y, hint)
	var out := {"pose": result["pose"]}
	if result.has("point"):
		out["point"] = result["point"]
		out["normal"] = result["normal"]
	return out


func _contact(geometry, pose: Transform3D, pieces: Array, radius: float) -> Dictionary:
	return geometry.contact_at(LevelGeometry._world_pieces(pose, pieces), radius)


func _clear_overlap(geometry, pose: Transform3D, shoulder: Vector3,
		pieces: Array, radius: float) -> Transform3D:
	var tuck := pose
	tuck.origin = pose.origin.lerp(shoulder, 0.48)
	var up := pose.basis.y.cross(Vector3.UP).normalized()
	for turn: float in [0.0, 0.32, 0.64, 1.05, 1.57]:
		tuck.basis = Basis(up, turn) * pose.basis if not up.is_zero_approx() else pose.basis
		var hit := _contact(geometry, tuck, pieces, radius)
		if hit.is_empty():
			return tuck
		var normal: Vector3 = hit["normal"]
		var clear := tuck
		clear.origin += normal * (0.20 + SKIN)
		if _contact(geometry, clear, pieces, radius).is_empty():
			return clear
	return pose
