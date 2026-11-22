extends Camera3D

## Free-flight camera for interactive exploration.
## WASD + mouse, Q/E down/up, Shift boost, 1-8 jump to showcase views, H HUD.

var speed := 45.0
var boost := 4.5
var sensitivity := 0.0022
var captured := true
var hud: CanvasLayer
var label: Label
var main: Node
var refresh := 0.0

func _ready() -> void:
	main = get_node_or_null("/root/Main")
	captured = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_hud()

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.03, 0.04, 0.55)
	panel.position = Vector2(24, 24)
	panel.size = Vector2(470, 196)
	hud.add_child(panel)
	label = Label.new()
	label.position = Vector2(42, 38)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.86, 0.91, 0.94))
	hud.add_child(label)

func toggle_capture() -> void:
	captured = not captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and captured:
		rotation.y -= event.relative.x * sensitivity
		rotation.x = clampf(rotation.x - event.relative.y * sensitivity, -1.45, 1.45)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				toggle_capture()
			KEY_H:
				hud.visible = not hud.visible
			KEY_1:
				_jump("hero_dusk")
			KEY_2:
				_jump("snow_edge")
			KEY_3:
				_jump("forest")
			KEY_4:
				_jump("gorge")
			KEY_5:
				_jump("waterfall")
			KEY_6:
				_jump("snow_dawn")
			KEY_7:
				_jump("panorama")
			KEY_8:
				_jump("hero")

func _jump(shot: String) -> void:
	if main != null and main.has_method("goto_shot"):
		main.goto_shot(shot)

func _process(dt: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		dir += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		dir += transform.basis.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	var sp := speed * (boost if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if dir.length() > 0.0:
		position += dir.normalized() * sp * dt
	refresh -= dt
	if refresh <= 0.0 and main != null and label != null:
		refresh = 0.2
		var p := position
		var h: float = main.terrain.sample_height(p.x, p.z)
		var biome := "Rainforest basin"
		if h > 505.0 and p.z < -200.0:
			biome = "Snowfield plateau"
		elif h > 380.0:
			biome = "Alpine / rock"
		elif p.z < -150.0:
			biome = "Upper hanging valley"
		elif h < 340.0:
			biome = "Tropical rainforest"
		label.text = "AETHER  ·  procedural wilds\n10.24 km²  |  seed 20261115\n\nWASD fly   Q/E down-up   Shift boost\nMouse look   Esc release   H hide UI\n1-8 showcase views\n\nX %.0f   Z %.0f   alt %.0f m\n%s" % [p.x, p.z, p.y, biome]