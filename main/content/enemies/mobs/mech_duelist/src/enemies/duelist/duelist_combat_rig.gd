extends "res://src/enemies/duelist/duelist_model.gd"
## Adapts the humanoid sword and articulated model to the shared combat and parry code.

const Sight = preload("res://src/core/vision.gd")
const BodyColliders = preload("res://core/body_colliders.gd")
const Lunge = preload("res://src/enemies/duelist/duelist_lunge.gd")
const Sequence = preload("res://src/enemies/duelist/duelist_sequence.gd")
const ReturnCut = preload("res://src/enemies/duelist/duelist_return_cut.gd")
const HIT_START := 0.188
const HIT_END := Lunge.CUT_END
const PREDICTION_STEPS := 20
const SWEEP_SAMPLES := 9

var attack_hit_from := Sequence.attack_seconds(HIT_START)
var attack_hit_to := Sequence.attack_seconds(HIT_END)
var attack_elapsed := 0.0
var is_attacking := false
var last_dt := 1.0 / 60.0
var weapon_scale := 1.0
var weapon_prev_xf := Transform3D.IDENTITY
var weapon_xf := Transform3D.IDENTITY
var _hit_window := false
var _strike_start := 0.0
var _hit_start := HIT_START
var _hit_end := HIT_END
var _prediction: Array[Transform3D] = []
var _opening_clock := true
var _normal_rate := 1.0
var _normal_windup_end := 0.0
var _normal_windup_extension := Sequence.NORMAL_WINDUP_EXTENSION
var _opening_discs: Array = []
var _metal_discs: Array = []
var _opening_proxy: BladeProxy
var _metal_proxy: BladeProxy
var _body_geometry: Array[Dictionary] = []
var _terrain_window := Vector2(0.0, 1.0)


func _ready() -> void:
	super()
	_cache_body_geometry()
	_metal_discs = blade_discs.duplicate()
	# Both damage and guard prediction use the visible sweep beyond the metal blade.
	var metal_end := BLADE_START + BLADE_LENGTH
	for i in range(1, SWEEP_SAMPLES + 1):
		var progress := float(i) / SWEEP_SAMPLES
		var radius := lerpf(Blade.TIP_OFFSET, 0.045, progress)
		blade_discs.append({"y": lerpf(metal_end, SWEEP_END, progress), "r": radius})
	_opening_discs = blade_discs
	_build_blade_proxies(metal_end)


## 少顶点凸体拟合：金属段由 ResonatingBlade 网格拟合，扫掠延伸段用
## 16 棱柱 loft（上口内接 TIP_OFFSET，下口收成 0.045 的能量尾流）。
func _build_blade_proxies(metal_end: float) -> void:
	var groups: Array = []
	for child in _blade_mount.get_children():
		if child is not MeshInstance3D or child.name in [&"BladeInlay", &"EnergizedEdge"]:
			continue
		var part := child as MeshInstance3D
		if part.mesh.get_surface_count() < 2:
			continue    # 装饰条（channels）只有单面：刃体网格才有 body+edge 双 surface
		var points := PackedVector3Array()
		var tris := PackedInt32Array()
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var base := points.size()
			for v in verts:
				points.append(part.transform * v)
			if idx.is_empty():
				for i in verts.size():
					tris.append(base + i)
			else:
				for i in idx:
					tris.append(base + i)
		groups.append({"points": points, "tris": tris})
	_metal_proxy = BladeProxy.fit_groups(groups, 9)   # 3D 凸包段：≈0.5% 富余、0 漏判
	var sweep := BladeProxy.loft(
		BladeProxy.regular_ring(16, Blade.TIP_OFFSET),
		BladeProxy.regular_ring(16, 0.045),
		metal_end, SWEEP_END)
	_opening_proxy = BladeProxy.new(_metal_proxy.pieces + [sweep])
	blade_proxy = _opening_proxy


func _cache_body_geometry() -> void:
	for attachment: BoneAttachment3D in _skeleton.get_children():
		if attachment.bone_name == &"Blade":
			continue
		var from_world := attachment.global_transform.affine_inverse()
		var bounds := AABB()
		var faces := PackedVector3Array()
		for mesh: MeshInstance3D in attachment.find_children("*", "MeshInstance3D", true, false):
			var local := from_world * mesh.global_transform
			var mesh_bounds := local * mesh.get_aabb()
			bounds = mesh_bounds if faces.is_empty() else bounds.merge(mesh_bounds)
			faces.append_array(local * mesh.mesh.get_faces())
		if not faces.is_empty():
			_body_geometry.append({
				"target": _skeleton.pose_target(attachment.bone_idx), "bounds": bounds, "faces": faces,
			})


func body_in_view(camera: Camera3D) -> bool:
	if camera == null or not is_visible_in_tree():
		return false
	var frustum := camera.get_frustum()
	for piece in _body_geometry:
		var target := piece["target"] as Node3D
		var from_world := target.global_transform.affine_inverse()
		var local_planes: Array[Plane] = []
		for plane in frustum:
			local_planes.append(from_world * plane)
		if Sight.faces_in_frustum(piece["bounds"], piece["faces"], local_planes):
			return true
	return false


var _routed_opening := false


func start_strike(dash: Dictionary, time: float) -> void:
	_routed_opening = dash.get("route_cut", false)
	var live_position := position
	_prepare_strike(0.0, HIT_START, HIT_END,
		func(sample: float) -> void: Lunge.apply(self, dash, sample))
	Lunge.apply(self, dash, time, live_position)


func start_return(pose: Dictionary, time: float) -> void:
	_prepare_strike(Lunge.DURATION, ReturnCut.HIT_START, ReturnCut.HIT_END,
		func(sample: float) -> void: ReturnCut.apply(self, pose, sample))
	ReturnCut.apply(self, pose, time - Lunge.DURATION)


func start_normal(move: GDScript, pose: Dictionary, time: float, rate: float, index := 0, extension := Sequence.NORMAL_WINDUP_EXTENSION) -> void:
	var strike: Vector4 = move.STRIKES[index]
	_normal_rate = rate
	_normal_windup_extension = extension
	_normal_windup_end = move.WINDUP_END
	_prepare_strike(0.0, strike.z, strike.w,
		func(sample: float) -> void: move.apply(self, pose, sample), false)
	move.apply(self, pose, time)


func cancel_strike() -> void:
	is_attacking = false
	_hit_window = false
	_prediction.clear()


func _prepare_strike(start: float, from: float, to: float, sample_pose: Callable, opening := true) -> void:
	_opening_clock = opening
	blade_discs = _opening_discs if opening else _metal_discs
	blade_proxy = _opening_proxy if opening else _metal_proxy
	_strike_start = start
	_hit_start = start + from
	_hit_end = start + to
	attack_hit_from = _strike_seconds(_hit_start)
	attack_hit_to = _strike_seconds(_hit_end)
	_prediction.clear()
	weapon_scale = global_basis.get_scale().x
	sampling_attack = true
	for i in range(PREDICTION_STEPS + 1):
		sample_pose.call(lerpf(from, to, float(i) / PREDICTION_STEPS))
		_prediction.append(weapon_spin.global_transform)
	sampling_attack = false



func _strike_seconds(time: float) -> float:
	if _opening_clock:
		return Sequence.attack_seconds(time, _routed_opening)
	return Sequence.normal_seconds(time, _normal_windup_end, _normal_rate, _normal_windup_extension)


func update_strike(t0: float, t1: float, dt: float, live_previous := Transform3D.IDENTITY) -> void:
	last_dt = dt
	attack_elapsed = _strike_seconds(t1)
	is_attacking = t1 >= _strike_start and t0 < _hit_end and not _prediction.is_empty()
	_hit_window = is_attacking and t1 >= _hit_start and t0 < t1
	if _hit_window:
		_terrain_window = Vector2(clampf(inverse_lerp(t0, t1, _hit_start), 0.0, 1.0),
			clampf(inverse_lerp(t0, t1, _hit_end), 0.0, 1.0))
		weapon_prev_xf = predict_weapon_xf(_strike_seconds(t0))
		weapon_xf = predict_weapon_xf(attack_elapsed)
		if has_attack_lane(global_position):
			# The predicted sweep guides a parry, while damage follows the actual
			# stair-adjusted blade between the first and last active frames.
			if t0 >= _hit_start:
				weapon_prev_xf = live_previous
			if t1 <= _hit_end:
				weapon_xf = weapon_spin.global_transform


func use_terrain_sweep(previous: Transform3D, interrupted: bool) -> void:
	if interrupted:
		is_attacking = false
		_hit_window = false
	elif _hit_window:
		var actual := weapon_spin.global_transform
		weapon_prev_xf = previous.interpolate_with(actual, _terrain_window.x)
		weapon_xf = previous.interpolate_with(actual, _terrain_window.y)


func in_hit_window() -> bool:
	return _hit_window


func blade_span() -> Vector2:
	return Vector2(BLADE_START, SWEEP_END if _opening_clock else BLADE_START + BLADE_LENGTH)


func predict_weapon_xf(elapsed: float) -> Transform3D:
	if _prediction.is_empty():
		return weapon_spin.global_transform
	var sample := clampf(inverse_lerp(attack_hit_from, attack_hit_to, elapsed), 0.0, 1.0) * PREDICTION_STEPS
	var index := mini(floori(sample), PREDICTION_STEPS - 1)
	return _prediction[index].interpolate_with(_prediction[index + 1], sample - index)


var _body_colliders: Dictionary = {}

## Multi-cylinder hit volumes (requirement #2): one anchor per articulated
## pose target / BoneAttachment, capsules fitted in anchor-local space — the
## union fully contains every body mesh vertex (verify_body_parts.gd checks
## vertex by vertex). The Blade attachment is the weapon, not the body.
func hit_parts() -> Array:
	if _body_colliders.is_empty():
		_body_colliders = _build_body_colliders()
	return BodyColliders.world_parts(_body_colliders)["parts"]


const _FINGER_BONES := ["Index_", "Middle_", "Ring_", "Little_", "Thumb_"]

## Articulaciones pequeñas que comparten cápsula con el joint padre que las
## mueve: sin este mapa cada BoneAttachment emitiría su propia pieza (~70).
const _MERGE_BONES := {
	"Patella_L": "Shin_L", "Patella_R": "Shin_R",
	"Forefoot_L": "Ankle_L", "Forefoot_R": "Ankle_R",
	"Scapula_L": "Clavicle_L", "Scapula_R": "Clavicle_R",
	"Pauldron_L": "UpperArm_L", "Pauldron_R": "UpperArm_R",
	"ForearmRoll_L": "Elbow_L", "ForearmRoll_R": "Elbow_R",
	"Palm_L": "Wrist_L", "Palm_R": "Wrist_R",
	"Lumbar_1": "Pelvis", "Lumbar_2": "Pelvis",
}

func _build_body_colliders() -> Dictionary:
	var by_bone := {}
	var anchors: Array = []
	for attachment: BoneAttachment3D in _skeleton.get_children():
		by_bone[String(attachment.bone_name)] = attachment
		if attachment.bone_name == &"Blade":
			continue
		anchors.append(attachment)
	# Merges semánticos: dedos → wrist del mismo lado (cadena vía Palm),
	# piezas pequeñas (rótula, escápula, hombrera, twist, palma, lumbares)
	# → la articulación funcional que las transporta.
	var anchor_map := {}
	for bone: String in by_bone:
		var target := ""
		for pref in _FINGER_BONES:
			if bone.begins_with(pref):
				target = "Palm" + bone.right(2)
		if _MERGE_BONES.has(bone):
			target = _MERGE_BONES[bone]
		if target != "" and by_bone.has(target):
			anchor_map[by_bone[bone]] = by_bone[target]
	# Los pose targets NO son hijos del skeleton: sus meshes sueltos (lámparas,
	# pivotes decorativos) suben por la jerarquía hasta el root. Para que caigan
	# en el cluster del joint que los mueve, se añaden como anchors y se mapean
	# a su BoneAttachment (mismo transform → misma cápsula, sin duplicar pieza).
	for i in _skeleton.get_bone_count():
		var bone := String(_skeleton.get_bone_name(i))
		var t: Node3D = _skeleton.pose_target(i)
		if t != null and bone != "Blade":
			anchors.append(t)
			if by_bone.has(bone):
				anchor_map[t] = by_bone[bone]
	return BodyColliders.build({
		"root": self,
		"anchors": anchors,
		"anchor_map": anchor_map,
		"k_max": 3,
		"b_max": 1,          # 22 clusters × 1 cápsula: tope hard por pieza (spec ≤30)
		"budget": 30,
		"mesh_filter": func(mi: MeshInstance3D) -> bool:
			var n: Node = mi
			while n != null and n != self:
				if n == weapon_spin or n == weapon_root:
					return false
				n = n.get_parent()
			return true,
	})


func sync_replay_pose() -> void:
	_skeleton.sync()
