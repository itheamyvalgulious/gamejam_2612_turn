extends Node3D
## Standalone preview. Run this scene to compare identical drives against different geometry.

const Drive = preload("res://tools/weapon_physics/weapon_drive.gd")
const Vesper = preload("res://runtime/characters/vesper/design/integration/campaign_rig.gd")
const Duelist = preload("res://runtime/enemies/mobs/mech_duelist/design/src/enemies/duelist/duelist_model.gd")
const UiFont = preload("res://runtime/fonts/galleria/ui_font.tres")
const ATTACK_LENGTH := 2.78
const ATTACK_MASS := 2.65
const GRIP := Vector3(-2.05, 1.73, 0.0)
const WALL_FACE := 0.37
const WALL_CENTER_Z := 0.55
const WALL_SIZE := Vector3(0.24, 4.8, 3.25)
const CASES := [
	{"label": "空挥", "guard": false},
	{"label": "正面格挡", "guard": true, "point": Vector3(0.14, 1.73, -2.05),
		"axis": Vector3(0, 0, 1), "length": 2.70, "mass": 2.60},
	{"label": "斜向擦刀", "guard": true, "point": Vector3(-0.75, 1.71, -1.75),
		"axis": Vector3(0.69, 0.035, 0.72), "length": 2.70, "mass": 2.60},
	{"label": "贴墙格挡", "guard": true, "point": Vector3(0.14, 1.73, -2.05),
		"axis": Vector3(0, 0, 1), "length": 2.70, "mass": 2.60, "wall": true},
	{"label": "换一把短重刀", "guard": true, "point": Vector3(0.07, 1.73, -1.94),
		"axis": Vector3(0, 0, 1), "length": 2.02, "mass": 4.00},
]

var _player_model: Node3D
var _duelist_model: Node3D
var _attack: Drive
var _guard: Drive
var _case_root: Node3D
var _time := 0.0
var _index := -1
var _blade_contacts := 0
var _wall_contacts := 0
var _first_blade_time := -1.0
var _first_wall_time := -1.0
var _attack_error := 0.0
var _guard_error := 0.0
var _grip_error := 0.0
var _grip_gap := 0.0
var _wrist_bend := 0.0
var _wrist_twist := 0.0
var _wall_depth := 0.0
var _all_passed := true
var _verify := false
var _changing := false

var _title: Label
var _readout: Label
var _target_lines := ImmediateMesh.new()
var _line_material := StandardMaterial3D.new()
var _flash: MeshInstance3D
var _flash_left := 0.0


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	_verify = "--verify" in arguments
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 12
	Engine.time_scale = 0.64 if "--slow" in arguments or not _verify else 1.0
	_build_stage()
	_build_overlay()
	_player_model = Vesper.new()
	_player_model.set("auto_step", false)
	add_child(_player_model)
	_player_model.hide()
	_duelist_model = Duelist.new()
	add_child(_duelist_model)
	_duelist_model.hide()
	_next_case()


func _physics_process(delta: float) -> void:
	if _changing or not is_instance_valid(_attack):
		return
	_time += delta
	_attack.follow(_grip_pose(_swing(_time), _attack.blade_start), delta)
	_attack_error = maxf(_attack_error, rad_to_deg(_attack.direction_error))
	_grip_error = maxf(_grip_error, _attack.grip_error)
	_grip_gap = maxf(_grip_gap, _attack.grip_gap)
	_wrist_bend = maxf(_wrist_bend, _attack.wrist_bend)
	_wrist_twist = maxf(_wrist_twist, _attack.wrist_twist)
	if _guard != null:
		_guard_error = maxf(_guard_error, rad_to_deg(_guard.direction_error))
		_grip_error = maxf(_grip_error, _guard.grip_error)
		_grip_gap = maxf(_grip_gap, _guard.grip_gap)
		_wrist_bend = maxf(_wrist_bend, _guard.wrist_bend)
		_wrist_twist = maxf(_wrist_twist, _guard.wrist_twist)
	if CASES[_index].get("wall", false):
		_wall_depth = maxf(_wall_depth, _depth_past_wall(_attack, ATTACK_LENGTH))
		_wall_depth = maxf(_wall_depth, _depth_past_wall(_guard, CASES[_index]["length"]))
	if _time >= 1.58:
		_finish_case()


func _process(delta: float) -> void:
	if _attack == null or _changing:
		return
	_flash_left = maxf(0.0, _flash_left - delta)
	_flash.visible = _flash_left > 0.0
	_flash.scale = Vector3.ONE * (0.45 + 0.55 * _flash_left / 0.095)
	_target_lines.clear_surfaces()
	_target_lines.surface_begin(Mesh.PRIMITIVE_LINES, _line_material)
	_draw_target(_attack, ATTACK_LENGTH)
	if _guard != null:
		_draw_target(_guard, CASES[_index]["length"])
	_target_lines.surface_end()
	_readout.text = "刀身 " + ("已相碰" if _blade_contacts > 0 else "—")
	if CASES[_index].get("wall", false):
		_readout.text += "    墙面 " + ("已接触" if _wall_contacts > 0 else "—")


func _next_case() -> void:
	if is_instance_valid(_case_root):
		_case_root.free()
	_index = (_index + 1) % CASES.size()
	var take: Dictionary = CASES[_index]
	_time = 0.0
	_blade_contacts = 0
	_wall_contacts = 0
	_first_blade_time = -1.0
	_first_wall_time = -1.0
	_attack_error = 0.0
	_guard_error = 0.0
	_grip_error = 0.0
	_grip_gap = 0.0
	_wrist_bend = 0.0
	_wrist_twist = 0.0
	_wall_depth = 0.0
	_flash_left = 0.0
	_case_root = Node3D.new()
	add_child(_case_root)
	_attack = _make_blade(_player_model, ATTACK_LENGTH, ATTACK_MASS, _swing(0.0))
	_guard = null
	if take["guard"]:
		var pose := Transform3D(_blade_basis(take["axis"]), take["point"])
		_guard = _make_blade(_duelist_model, take["length"], take["mass"], pose)
	if take.get("wall", false):
		_add_wall()
	_title.text = take["label"]
	_changing = false


func _finish_case() -> void:
	_changing = true
	var expects_guard: bool = CASES[_index]["guard"]
	var expects_wall: bool = CASES[_index].get("wall", false)
	var passed := (_blade_contacts > 0) == expects_guard and (_wall_contacts > 0) == expects_wall
	passed = passed and (_guard_error > 0.6 and _attack_error > 23.0 if expects_guard else _attack_error < 24.0)
	passed = passed and _wall_depth < 0.08 and _grip_gap < 0.08
	passed = passed and _wrist_bend < Drive.WRIST_BEND + 3.0 and _wrist_twist < 4.0
	passed = passed and (not expects_wall or _first_wall_time >= _first_blade_time)
	_all_passed = _all_passed and passed
	print("WEAPON_PHYSICS %d blades=%d wall=%d attack_deg=%.2f guard_deg=%.2f grip_error=%.3f grip_gap=%.3f bend=%.2f twist=%.2f wall_overlap=%.3f pass=%s" %
		[_index + 1, _blade_contacts, _wall_contacts, _attack_error, _guard_error, _grip_error, _grip_gap,
			_wrist_bend, _wrist_twist, _wall_depth, passed])
	if _verify and _index == CASES.size() - 1:
		get_tree().quit(0 if _all_passed else 1)
		return
	_next_case.call_deferred()


func _swing(time: float) -> Transform3D:
	var strike := smoothstep(0.25, 0.93, time)
	var recover := smoothstep(1.04, 1.45, time)
	var angle := deg_to_rad(lerpf(-64.0, 65.0, strike) - 29.0 * recover)
	var axis := Vector3(cos(angle), 0.040 * sin(strike * PI), sin(angle))
	return Transform3D(_blade_basis(axis), GRIP + Vector3.RIGHT * (0.31 * sin(strike * PI)))


func _make_blade(source: Node3D, length: float, blade_mass: float, pose: Transform3D) -> Drive:
	var spin := source.get("weapon_spin") as Node3D
	var visual := spin.duplicate() as Node3D
	var original_length := Duelist.BLADE_LENGTH
	var start := Duelist.BLADE_START
	if source == _player_model:
		var tip := source.get("blade_tip") as Marker3D
		var base := source.get("blade_base") as Marker3D
		original_length = (tip.position.y - base.position.y) / 0.16
		start = tip.position.y - original_length * 0.96
	var factor := length / original_length
	start *= factor
	var defender := source == _duelist_model
	var blade := Drive.new()
	blade.configure(length, blade_mass, start, _grip_pose(pose, start))
	blade.angular_strength = 0.45 if defender else 1.0
	_case_root.add_child(blade)
	var forearm := blade.attach_grip()
	visual.transform = Transform3D(Basis.from_scale(Vector3.ONE * factor), Vector3.ZERO)
	blade.add_child(visual)
	_show_hand(blade, forearm, defender)
	if defender:
		_box(blade, Vector3(0, start + length * 0.48, 0), Vector3(0.049, length * 0.94, 0.075), Color("ffa75a"), true)
	blade.contact.connect(_on_contact.bind(blade))
	return blade


static func _grip_pose(blade_pose: Transform3D, start: float) -> Transform3D:
	return blade_pose.translated_local(Vector3.DOWN * start)


static func _show_hand(blade: Drive, forearm: Node3D, defender: bool) -> void:
	var shell := Color("997557") if defender else Color("6695bc")
	var hinge := Color("242a35")
	var sleeve := Node3D.new()
	forearm.add_child(sleeve)
	var elbow := Vector3(0.18, -0.57, 0.47).normalized()
	var across := Vector3.RIGHT.slide(elbow).normalized()
	sleeve.basis = Basis(across, elbow, across.cross(elbow))
	_box(sleeve, Vector3(0, 0.49, 0), Vector3(0.33, 0.67, 0.28), shell)
	_box(sleeve, Vector3(0, 0.15, 0), Vector3(0.23, 0.29, 0.21), hinge)
	_box(blade, Vector3(0, -0.036, 0.025), Vector3(0.265, 0.29, 0.21), shell)
	for finger in 4:
		var y := -0.134 + finger * 0.064
		_box(blade, Vector3(0.069, y, -0.070), Vector3(0.17, 0.052, 0.09), Color("cad4dd"))
	_box(blade, Vector3(-0.10, 0.077, -0.060), Vector3(0.082, 0.145, 0.105), hinge)


func _on_contact(point: Vector3, other: Object, blade: Drive) -> void:
	if other is Drive:
		if blade != _attack:
			return
		if _blade_contacts == 0:
			_first_blade_time = _time
		_blade_contacts += 1
	else:
		if _wall_contacts == 0:
			_first_wall_time = _time
		_wall_contacts += 1
	_flash.global_position = point
	_flash_left = 0.095


static func _blade_basis(axis: Vector3) -> Basis:
	var blade := axis.normalized()
	var face := Vector3.UP.cross(blade).normalized()
	return Basis(face, blade, face.cross(blade))


static func _depth_past_wall(blade: Drive, length: float) -> float:
	var pose := blade.global_transform
	var from := pose * (Vector3.UP * blade.blade_start)
	var to := from + pose.basis.y * length
	var half_width := (pose.basis.x.abs() * Drive.WIDTH + pose.basis.z.abs() * Drive.THICKNESS) * 0.5
	var low := WALL_CENTER_Z - WALL_SIZE.z * 0.5 - half_width.z
	var high := WALL_CENTER_Z + WALL_SIZE.z * 0.5 + half_width.z
	if maxf(from.z, to.z) < low or minf(from.z, to.z) > high:
		return 0.0
	var left := from.x
	var right := to.x
	if not is_equal_approx(from.z, to.z):
		left = lerpf(from.x, to.x, clampf(inverse_lerp(from.z, to.z, low), 0.0, 1.0))
		right = lerpf(from.x, to.x, clampf(inverse_lerp(from.z, to.z, high), 0.0, 1.0))
	return maxf(0.0, maxf(left, right) + half_width.x - WALL_FACE)


func _add_wall() -> void:
	var wall := StaticBody3D.new()
	wall.position = Vector3(WALL_FACE + WALL_SIZE.x * 0.5, WALL_SIZE.y * 0.5, WALL_CENTER_Z)
	wall.collision_layer = Drive.WORLD_LAYER
	wall.collision_mask = Drive.BLADE_LAYER
	_case_root.add_child(wall)
	var shape := BoxShape3D.new()
	shape.size = WALL_SIZE
	var collider := CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	_box(wall, Vector3.ZERO, WALL_SIZE, Color("344252"))
	_box(wall, Vector3(-0.122, 0.09, 0), Vector3(0.025, 0.035, WALL_SIZE.z), Color("eb9a55"))


func _draw_target(blade: Drive, length: float) -> void:
	for i in 10:
		var from := float(i) / 10.0
		var to := from + 0.047
		_target_lines.surface_add_vertex(blade.target * Vector3(0, blade.blade_start + length * from, 0))
		_target_lines.surface_add_vertex(blade.target * Vector3(0, blade.blade_start + length * to, 0))


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var scene := Environment.new()
	scene.background_mode = Environment.BG_COLOR
	scene.background_color = Color("101720")
	scene.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	scene.ambient_light_color = Color("bbc8e0")
	scene.ambient_light_energy = 0.63
	scene.glow_enabled = true
	environment.environment = scene
	add_child(environment)
	_box(self, Vector3(0, -0.11, 0), Vector3(10, 0.2, 9), Color("243142"))
	for i in range(-4, 5):
		_box(self, Vector3(i, 0.001, 0), Vector3(0.009, 0.004, 8.5), Color("425164"))
		_box(self, Vector3(0, 0.001, i), Vector3(8.6, 0.004, 0.009), Color("425164"))
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(-3.1, 8.0, -6.9)
	camera.fov = 38
	camera.look_at(Vector3(-0.24, 1.30, -0.33))
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -38, 0)
	light.light_energy = 1.65
	light.shadow_enabled = true
	add_child(light)
	var lines := MeshInstance3D.new()
	lines.mesh = _target_lines
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.albedo_color = Color("a1b4cc")
	add_child(lines)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("fff6b6")
	glow.emission_enabled = true
	glow.emission = Color("ffad60")
	glow.emission_energy_multiplier = 2.5
	var dot := SphereMesh.new()
	dot.radius = 0.08
	dot.height = 0.16
	_flash = MeshInstance3D.new()
	_flash.mesh = dot
	_flash.material_override = glow
	_flash.hide()
	add_child(_flash)


func _build_overlay() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var text := VBoxContainer.new()
	text.position = Vector2(24, 20)
	canvas.add_child(text)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	text.add_child(_title)
	_readout = Label.new()
	text.add_child(_readout)
	var legend := Label.new()
	legend.text = "虚线为目标刀路"
	legend.modulate = Color("9fb4cd")
	text.add_child(legend)
	for label in [_title, _readout, legend]:
		label.add_theme_font_override("font", UiFont)


static func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color, glow := false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.75
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
