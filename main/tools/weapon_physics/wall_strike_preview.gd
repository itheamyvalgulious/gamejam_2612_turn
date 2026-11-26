extends Node3D
## Preview one physical blade against a solid wall, with the campaign rig holding it.

const Drive = preload("res://tools/weapon_physics/weapon_drive.gd")
const Vesper = preload("res://runtime/characters/vesper/design/integration/campaign_rig.gd")
const UiFont = preload("res://runtime/fonts/galleria/ui_font.tres")
const WINDUP_AT := 0.24
const DURATION := 2.55

var _rig: Vesper
var _blade: Drive
var _wall: StaticBody3D
var _normal := Vector3.BACK
var _distance := 3.25
var _wall_height := 5.10
var _glance := false
var _verify := false
var _time := 0.0
var _hit_time := -1.0
var _last_touch := -1.0
var _hit_pose := Transform3D.IDENTITY
var _hit_torso := Basis.IDENTITY
var _rest_torso := Basis.IDENTITY
var _torso_scale := Vector3.ONE
var _rest_pose := Transform3D.IDENTITY
var _opening_pose := Transform3D.IDENTITY
var _raised_pose := Transform3D.IDENTITY
var _cut_target := Transform3D.IDENTITY
var _current_blade_pose := Transform3D.IDENTITY
var _previous_blade_pose := Transform3D.IDENTITY
var _tangent := Vector3.ZERO
var _shoulder_relief := Vector3.ZERO
var _span := Vector2.ZERO
var _scale := Vector3.ONE
var _done := false
var _flash: OmniLight3D
var _phase: Label
var _worst_overlap := 0.0
var _hand_gap := 0.0
var _extended_elbow := 0.0
var _elbow_fold := 0.0
var _shoulder_turn := 0.0
var _slide_distance := 0.0
var _separated_after := -1.0
var _contact_point := Vector3.ZERO
var _approach := 0.0
var _shoulder_anchors: Array[Vector3] = []


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	_glance = "--glance" in arguments
	_verify = "--verify" in arguments
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 12
	Engine.time_scale = 1.0 if "--full-speed" in arguments else 0.64
	if _glance:
		_normal = Vector3(-0.50, 0.0, 0.866).normalized()
		_distance = 4.02
	_build_stage()
	_rig = Vesper.new()
	_rig.auto_step = false
	_rig.scale = Vector3.ONE * 1.83
	add_child(_rig)
	_rig.set_process(false)
	for frame in 20:
		_rig.advance(1.0 / 120.0)
	_scale = _rig.weapon_spin.global_basis.get_scale()
	_span = _rig.blade_span() * _scale.y
	_torso_scale = _rig.torso.basis.get_scale()
	_rest_torso = _rig.torso.basis.orthonormalized()
	for arm: Dictionary in _rig.arms:
		_shoulder_anchors.append(arm["shoulder"].position)
	_rest_pose = _ready_pose(_rig.weapon_spin.global_position)
	_opening_pose = _rest_pose
	_raised_pose = _sword_pose(Vector3(0.68, 2.65, -0.53), Vector3(0.82, 0.39, -0.39))
	_cut_target = _sword_pose(Vector3(0.08, 2.32, -1.07), Vector3(-0.14, -0.09, -0.98))
	_current_blade_pose = _opening_pose
	_previous_blade_pose = _opening_pose
	_blade = Drive.new()
	_blade.configure(_span.y - _span.x, 2.75, _span.x, _opening_pose)
	add_child(_blade)
	_blade.attach_grip()
	_blade.contact.connect(_on_contact)
	_pose_to_weapon()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_time += delta
	_previous_blade_pose = _current_blade_pose
	_current_blade_pose = _blade.global_transform
	_rig.advance(delta)
	var target := _strike_pose()
	if _hit_time >= 0.0:
		var after := _time - _hit_time
		target = _recovery_pose(after)
		_yield_shoulder(after)
		_flash.light_energy = 3.5 * (1.0 - smoothstep(0.0, 0.085, _time - _last_touch))
		_phase.text = "擦开" if _glance and after < 0.23 else ("卸力" if after < 0.27 else "收刀")
	_blade.follow(target, delta)
	_pose_to_weapon()
	if _hit_time >= 0.0:
		_record_recovery(_time - _hit_time)
	_hand_gap = maxf(_hand_gap, _measure_grip_gap())
	_worst_overlap = maxf(_worst_overlap, -_wall_gap(_blade.global_transform, true))
	if _time >= DURATION:
		_finish()


func _process(_delta: float) -> void:
	if is_instance_valid(_blade):
		_pose_to_weapon()


func _strike_pose() -> Transform3D:
	var load := smoothstep(WINDUP_AT, 0.57, _time)
	var cut := smoothstep(0.57, 1.0, _time)
	var torso := Basis(Vector3.UP, 0.22 * load - 0.37 * cut) * Basis(Vector3.RIGHT, -0.09 * cut)
	_rig.torso.basis = (torso * _rest_torso).scaled_local(_torso_scale)
	return _opening_pose.interpolate_with(_raised_pose, load).interpolate_with(_cut_target, cut)


func _pose_to_weapon() -> void:
	var pose := _blade.global_transform
	pose.basis = pose.basis.orthonormalized().scaled_local(_scale)
	_rig.weapon_root.global_transform = pose * _rig.weapon_spin.transform.affine_inverse()
	for index in _rig.arms.size():
		var arm: Dictionary = _rig.arms[index]
		var shoulder: Node3D = arm["shoulder"]
		var grip := Vesper.GRIP if index == 1 else -Vesper.GRIP
		var reach := (_rig.weapon_root.transform * (Vector3.UP * grip)) - _shoulder_anchors[index]
		var extension := clampf(reach.length() - float(arm["upper"]) - float(arm["fore"]) + 0.009, 0.0, 0.068)
		shoulder.position = _shoulder_anchors[index] + reach.normalized() * extension
	_rig._update_arms(_rig._smooth_pose)


func _on_contact(point: Vector3, other: Object) -> void:
	if other != _wall:
		return
	_last_touch = _time
	_flash.global_position = point + _normal * 0.10
	if _hit_time >= 0.0 or _time < 0.57:
		return
	_hit_time = _time
	_hit_pose = _blade.global_transform.orthonormalized()
	_contact_point = point
	_hit_torso = _rig.torso.basis.orthonormalized()
	_extended_elbow = _rig.arms[0]["elbow"].rotation.x
	var shoulder: Node3D = _rig.arms[0]["shoulder"]
	_shoulder_relief = (shoulder.global_position - _hit_pose.origin).normalized()
	var blade_point := _hit_pose.affine_inverse() * point
	var incoming := (_current_blade_pose * blade_point) - (_previous_blade_pose * blade_point)
	_approach = -incoming.normalized().dot(_normal)
	var flow := incoming.slide(_normal)
	flow.y = clampf(flow.y, -0.48 * flow.slide(Vector3.UP).length(), 0.20)
	_tangent = flow.normalized()
	if _tangent.is_zero_approx():
		_tangent = _normal.cross(Vector3.UP)
	print("WALL_CONTACT mode=", "glance" if _glance else "front", " time=", _time,
		" point=", point, " approach=", snappedf(_approach, 0.01))


func _recovery_pose(after: float) -> Transform3D:
	var release := _hit_pose
	var retreat := 0.32
	var release_end := 0.23
	var fold := smoothstep(0.0, 0.20, after)
	if _glance:
		var along := smoothstep(0.0, 0.20, after)
		var off := smoothstep(0.12, 0.40, after)
		release.origin += _tangent * (0.40 * along) + _normal * (0.027 * along + 0.32 * off)
		retreat = 0.15
		release_end = 0.38
		fold = smoothstep(0.08, 0.32, after)
	var yield_amount := smoothstep(0.0, 0.19, after)
	release.origin += _normal * (retreat * yield_amount) + Vector3.DOWN * (0.11 * yield_amount)
	release.origin += _shoulder_relief * ((0.65 if _glance else 0.25) * fold)
	release.basis = release.basis.slerp(_rest_pose.basis, 0.19 * yield_amount)
	var settle := smoothstep(release_end, release_end + 0.55, after)
	var pose := release.interpolate_with(_rest_pose, settle)
	var clearance := lerpf(0.012, 0.078, smoothstep(0.05, 0.37, after))
	pose.origin += _normal * maxf(0.0, clearance - _wall_gap(pose))
	return pose


func _yield_shoulder(after: float) -> void:
	var recoil := smoothstep(0.0, 0.14, after) * (1.0 - smoothstep(0.23, 0.72, after))
	var release := smoothstep(0.08, 0.75, after)
	var torso_pose := _hit_torso.slerp(_rest_torso, release)
	var normal: Vector3 = _rig.body.global_basis.orthonormalized().inverse() * _normal
	var lean_axis := Vector3.UP.cross(normal).normalized()
	var turn := Vector3.UP if _tangent.dot(Vector3.RIGHT) > 0.0 else Vector3.DOWN
	var pitch := deg_to_rad(5.0 if _glance else 10.0)
	var yaw := deg_to_rad(9.0 if _glance else 3.0)
	_rig.torso.basis = (Basis(lean_axis, pitch * recoil) * Basis(turn, yaw * recoil) * torso_pose).scaled_local(_torso_scale)


func _ready_pose(at: Vector3) -> Transform3D:
	return _sword_pose(at + Vector3(-0.14, -0.12, 0.095), Vector3(-0.48, 0.85, -0.22))


static func _sword_pose(at: Vector3, axis: Vector3) -> Transform3D:
	var direction := axis.normalized()
	var edge := Vector3.RIGHT.slide(direction).normalized()
	return Transform3D(Basis(edge, direction, edge.cross(direction)), at)


func _wall_gap(pose: Transform3D, finite_wall := false) -> float:
	var start := pose * (Vector3.UP * _span.x)
	var end := pose * (Vector3.UP * _span.y)
	if finite_wall:
		var top := _wall_height + 0.12
		if minf(start.y, end.y) > top:
			return 0.0
		if start.y > top:
			start = start.lerp(end, inverse_lerp(start.y, end.y, top))
		elif end.y > top:
			end = end.lerp(start, inverse_lerp(end.y, start.y, top))
	var low := minf(_normal.dot(start), _normal.dot(end))
	var bevel := absf(_normal.dot(pose.basis.x)) * Drive.WIDTH * 0.5 + absf(_normal.dot(pose.basis.z)) * Drive.THICKNESS * 0.5
	return low + _distance - bevel


func _measure_grip_gap() -> float:
	var gap := 0.0
	for index in _rig.arms.size():
		var hand: Node3D = _rig.arms[index]["wrist"]
		var grip := Vesper.GRIP if index == 1 else -Vesper.GRIP
		gap = maxf(gap, hand.global_position.distance_to(_rig.weapon_root.to_global(Vector3.UP * grip)))
	return gap


func _record_recovery(after: float) -> void:
	if _separated_after < 0.0 and _wall_gap(_blade.global_transform, true) > 0.085:
		_separated_after = after
	if after < 0.42:
		var elbow: Node3D = _rig.arms[0]["elbow"]
		_extended_elbow = minf(_extended_elbow, elbow.rotation.x)
		_elbow_fold = maxf(_elbow_fold, rad_to_deg(elbow.rotation.x - _extended_elbow))
		var torso_pose := _rig.torso.basis.orthonormalized().get_rotation_quaternion()
		_shoulder_turn = maxf(_shoulder_turn, rad_to_deg(torso_pose.angle_to(_hit_torso.get_rotation_quaternion())))
		var blade_point := _hit_pose.affine_inverse() * _contact_point
		var movement := (_blade.global_transform * blade_point) - _contact_point
		_slide_distance = maxf(_slide_distance, movement.dot(_tangent))


func _finish() -> void:
	_done = true
	var release_delay := _last_touch - _hit_time
	var rest_error := _blade.global_position.distance_to(_rest_pose.origin)
	var passed := _hit_time >= 0.57 and _hit_time < 1.19
	passed = passed and release_delay < 0.38 and _separated_after >= 0.0 and _separated_after < 0.48 and rest_error < 0.16
	passed = passed and _hand_gap < 0.12 and _elbow_fold > 3.0 and _shoulder_turn > 5.0 and _worst_overlap < 0.10
	passed = passed and (_approach > 0.1 and _approach < 0.58 and _slide_distance > 0.35 if _glance else _approach > 0.53)
	print("WALL_STRIKE mode=", "glance" if _glance else "front", " contact=", _hit_time,
		" touch_duration=", release_delay, " clear_after=", _separated_after, " elbow_fold_deg=", _elbow_fold, " hand_gap=", _hand_gap,
		" shoulder_turn_deg=", _shoulder_turn, " slide=", _slide_distance, " room_plane_overlap=", _worst_overlap,
		" rest_error=", rest_error, " pass=", passed)
	if _verify:
		get_tree().quit(0 if passed else 1)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var look := Environment.new()
	look.background_mode = Environment.BG_COLOR
	look.background_color = Color("111923")
	look.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	look.ambient_light_color = Color("c1d2f2")
	look.ambient_light_energy = 0.63
	look.glow_enabled = true
	environment.environment = look
	add_child(environment)
	_box(self, Vector3(0, -0.105, -0.55), Vector3(15, 0.2, 13), Color("253343"))
	for i in range(-6, 7):
		_box(self, Vector3(i, 0.002, -0.55), Vector3(0.009, 0.004, 12.8), Color("455466"))
		_box(self, Vector3(0, 0.002, i), Vector3(14.8, 0.004, 0.009), Color("455466"))
	_wall = StaticBody3D.new()
	_wall.collision_layer = Drive.WORLD_LAYER
	_wall.collision_mask = Drive.BLADE_LAYER
	_wall.position = -_normal * (_distance + 0.18) + Vector3.UP * (_wall_height * 0.5)
	var along := Vector3.UP.cross(_normal)
	_wall.basis = Basis(along, Vector3.UP, _normal)
	add_child(_wall)
	var size := Vector3(8.0, _wall_height, 0.36)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	_wall.add_child(collider)
	_box(_wall, Vector3.ZERO, size, Color("394a60"))
	_box(_wall, Vector3(0, _wall_height * 0.5 - 0.06, 0.187), Vector3(8, 0.035, 0.014), Color("96aeca"))
	for i in range(-3, 4):
		_box(_wall, Vector3(float(i), 0, 0.182), Vector3(0.015, _wall_height - 0.15, 0.006), Color("546377"))
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(6.6, 4.1, 3.0) if _glance else Vector3(6.8, 4.17, 2.35)
	camera.fov = 43.0
	camera.look_at(Vector3(0.0, 2.13, -1.55))
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -42, 0)
	light.light_energy = 1.85
	light.shadow_enabled = true
	add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.5, 4.5, -1.3)
	fill.light_color = Color("a7c6f4")
	fill.light_energy = 1.9
	fill.omni_range = 10.0
	add_child(fill)
	_flash = OmniLight3D.new()
	_flash.light_color = Color("ffb168")
	_flash.light_energy = 0.0
	_flash.omni_range = 2.5
	add_child(_flash)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var note := VBoxContainer.new()
	note.position = Vector2(28, 21)
	canvas.add_child(note)
	var label := Label.new()
	label.text = "斜向擦墙" if _glance else "正面砍墙"
	label.add_theme_font_override("font", UiFont)
	label.add_theme_font_size_override("font_size", 27)
	note.add_child(label)
	_phase = Label.new()
	_phase.add_theme_font_override("font", UiFont)
	_phase.modulate = Color("b2c3db")
	note.add_child(_phase)


static func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
