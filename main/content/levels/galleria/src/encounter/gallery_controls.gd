extends RefCounted

const Geometry = preload("res://core/level_geometry.gd")
const USE_REACH := 5.6
const SCAN_TIME := 1.20
const LAMP_POWER := 2.7

var directory: Dictionary
var supply: Dictionary
var lounge: Dictionary
var _prompt: Label3D
var _scan_left := 0.0


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
	_set_directory(false)
	_set_lounge(true)
	_scan_left = 0.0
	supply["beam"].hide()
	supply["status"].text = "等待验收"


func step(dt: float, eye: Transform3D, geometry: Geometry, enabled: bool) -> void:
	_step_scan(dt)
	_prompt.hide()
	var key := B.event_text("interact")
	if not enabled or key == "—":
		return
	var selected: Dictionary = {}
	var distance := USE_REACH
	for station in [directory, supply, lounge]:
		var at: Vector3 = station["at"]
		var normal: Vector3 = station["normal"]
		var toward := at - eye.origin
		var length := toward.length()
		if length < 0.05 or length >= distance or toward.dot(normal) >= 0.0:
			continue
		# The blade collision shell extends slightly in front of the button housing.
		if toward.dot(-eye.basis.z) < length * 0.76 or not geometry.segment_clear(eye.origin, at + normal * 0.12):
			continue
		selected = station
		distance = length
	if selected.is_empty():
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
			_set_directory(not directory["guide"].visible)
		"supply":
			if _scan_left <= 0.0:
				_scan_left = SCAN_TIME
				supply["status"].text = "正在验收"
				_step_scan(0.0)
		"lounge":
			var material: StandardMaterial3D = lounge["material"]
			_set_lounge(material.emission_energy_multiplier < 0.5)


func _set_directory(show_stairs: bool) -> void:
	directory["guide"].visible = show_stairs
	directory["status"].text = "返程楼梯 →" if show_stairs else "坠击入口"


func _set_lounge(on: bool) -> void:
	var material: StandardMaterial3D = lounge["material"]
	material.emission_energy_multiplier = 1.22 if on else 0.08
	for lamp: OmniLight3D in lounge["lamps"]:
		lamp.light_energy = LAMP_POWER if on else 0.0


func _step_scan(dt: float) -> void:
	if _scan_left <= 0.0:
		return
	_scan_left = maxf(0.0, _scan_left - dt)
	var beam: Node3D = supply["beam"]
	var home: Vector3 = supply["scan_start"]
	beam.position = home + Vector3.BACK * lerpf(-0.55, 0.55, 1.0 - _scan_left / SCAN_TIME)
	beam.visible = _scan_left > 0.0
	if _scan_left <= 0.0:
		supply["status"].text = "验收完成"
