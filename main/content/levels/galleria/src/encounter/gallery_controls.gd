extends RefCounted

const Geometry = preload("res://core/level_geometry.gd")
const USE_REACH := 5.6
const SCAN_TIME := 0.78
const MAP_SCALE := 0.039
const CONTACT_DEPTH := 0.10

var directory: Dictionary
var supply: Dictionary
var interlock: Dictionary
var wall_interlock: Label3D
var wall_interlock_material: ShaderMaterial
var _wall_interlock_state := -1
var door_actuator: Dictionary
var _actuator_percent := -1
var _prompt: Label3D
var _scan_left := 0.0
var _door_open := false


func attach(root: Node3D) -> void:
	_prompt = Label3D.new()
	_prompt.name = "WorldInteractHint"
	_prompt.font_size = 44
	_prompt.pixel_size = 0.0047
	_prompt.modulate = Color("dedfe3")
	_prompt.outline_size = 7
	_prompt.outline_modulate = Color("24272d")
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(_prompt)
	reset()


func reset() -> void:
	_prompt.hide()
	_scan_left = 0.0
	_door_open = false
	directory["model"].hide()
	for contact: Dictionary in directory["contacts"]:
		contact["dot"].hide()
		contact["cross"].hide()
	supply["open"] = false
	supply["cover"].position.y = 0.0
	supply["status"].text = "货舱 02  /  补给查验"
	interlock["screen"].hide()
	interlock["trace"].hide()
	_set_wall_interlock("安全闭锁", Color("cfb18b"), 0)
	_update_actuator(0.0)


func step(dt: float, eye: Transform3D, geometry: Geometry, enabled: bool,
		enemies: Array, door_open: bool, door_travel: float) -> void:
	_door_open = door_open
	_step_supply(dt)
	if directory["model"].visible:
		_update_deck_contacts(enemies)
	_update_interlock(enemies)
	_update_actuator(door_travel)
	var key := B.event_text("interact")
	if not enabled or key == "—":
		_prompt.hide()
		return
	var selected: Dictionary = {}
	var distance := USE_REACH
	for station in [directory, supply, interlock]:
		var at: Vector3 = station["at"]
		var normal: Vector3 = station["normal"]
		var toward := at - eye.origin
		var length := toward.length()
		if length < 0.05 or length >= distance or toward.dot(normal) >= 0.0:
			continue
		if toward.dot(-eye.basis.z) < length * 0.76 or not geometry.segment_clear(eye.origin, at + normal * 0.12):
			continue
		selected = station
		distance = length
	if selected.is_empty():
		_prompt.hide()
		return
	if B.just("interact"):
		_activate(selected["id"])
		Snd.play_at("chime", selected["at"], {"gain": 0.22})
	_prompt.text = key
	_prompt.position = selected["at"] + Vector3.UP * 0.34
	_prompt.show()


func _activate(id: String) -> void:
	match id:
		"directory":
			var map: Node3D = directory["model"]
			map.visible = not map.visible
		"supply":
			supply["open"] = not supply["open"]
			_scan_left = SCAN_TIME if supply["open"] else 0.0
			supply["status"].text = "读取运输标签" if supply["open"] else "货舱 02  /  补给查验"
		"interlock":
			interlock["screen"].visible = not interlock["screen"].visible
			if not interlock["screen"].visible:
				interlock["trace"].hide()


static func map_point(at: Vector3, depth: float) -> Vector3:
	return Vector3(at.x * MAP_SCALE, -at.z * MAP_SCALE, depth)


func mark_defeat(index: int, at: Vector3) -> void:
	var contacts: Array = directory["contacts"]
	if index < 0 or index >= contacts.size():
		return
	var contact: Dictionary = contacts[index]
	contact["anchor"].position = map_point(at, CONTACT_DEPTH)
	contact["dot"].hide()
	contact["cross"].show()


func _update_deck_contacts(enemies: Array) -> void:
	var contacts: Array = directory["contacts"]
	for i in contacts.size():
		var contact: Dictionary = contacts[i]
		var alive: bool = i < enemies.size() and enemies[i].alive
		contact["dot"].visible = alive
		if alive:
			var at: Vector3 = enemies[i].ground_position()
			contact["anchor"].position = map_point(at, CONTACT_DEPTH)


func _step_supply(dt: float) -> void:
	var cover: Node3D = supply["cover"]
	var scan := _scan_left > 0.0
	_scan_left = maxf(0.0, _scan_left - dt)
	if scan and _scan_left == 0.0:
		supply["status"].text = "货舱 02  →  中庭\n减振件  /  备用电芯"
	var target := 0.93 if supply["open"] else 0.0
	cover.position.y = move_toward(cover.position.y, target, dt * 1.85)


func _update_interlock(enemies: Array) -> void:
	var live := 0
	for enemy in enemies:
		if enemy.alive:
			live += 1
	if _door_open:
		_set_wall_interlock("允许通行", Color("b3d3cf"), 2)
	elif live == 0:
		_set_wall_interlock("舱门开启中", Color("d3c4a1"), 1)
	else:
		_set_wall_interlock("安全闭锁", Color("cfb18b"), 0)
	if not interlock["screen"].visible:
		return
	var status: Label3D = interlock["status"]
	if _door_open:
		status.text = "联锁解除\n通往回廊实验舱"
	elif live == 0:
		status.text = "警戒解除\n舱门开启中"
	else:
		status.text = "安全联锁  /  舱门闭锁\n中庭警戒目标  %02d" % live
	var trace: Node3D = interlock["trace"]
	trace.visible = live > 0 and not _door_open


func _set_wall_interlock(message: String, tint: Color, state: int) -> void:
	if state == _wall_interlock_state:
		return
	_wall_interlock_state = state
	wall_interlock.text = message
	wall_interlock.modulate = tint
	wall_interlock_material.set_shader_parameter("signal_state", state)


func _update_actuator(travel: float) -> void:
	var percent := roundi(clampf(travel, 0.0, 1.0) * 100.0)
	if percent == _actuator_percent:
		return
	_actuator_percent = percent
	var label: Label3D = door_actuator["position_label"]
	var material: ShaderMaterial = door_actuator["material"]
	label.text = "%02d %%" % percent
	material.set_shader_parameter("travel", percent * 0.01)
