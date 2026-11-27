extends RefCounted

const NeonPanel = preload("res://ui/neon_panel.gd")
const INK := Color("#100e1d")
const TEXT := Color("#f1effa")
const MUTED := Color("#b9b5ce")
const FOCUS := Color("#efa4e5")
const BATTLE_CUE := Color("#71e2de")
const BLOCKED := Color("#ffbd82")
const DANGER := Color("#ec5364")
const PHASE := Color("#b4a5ff")

static func theme() -> Theme:
	var skin := Theme.new()
	skin.default_font = load("res://runtime/fonts/act/ui_font.tres") as Font
	skin.default_font_size = 18
	var normal := surface()
	var hover := surface(Color("#392747"), FOCUS, FOCUS)
	var pressed := surface(Color("#281834"), Color("#ca78c0"), FOCUS)
	for control in ["Button", "CheckButton"]:
		skin.set_color("font_color", control, TEXT)
		skin.set_color("font_hover_color", control, TEXT)
		skin.set_color("font_pressed_color", control, TEXT)
		skin.set_color("font_hover_pressed_color", control, TEXT)
		skin.set_color("font_focus_color", control, TEXT)
		skin.set_color("font_disabled_color", control, Color("#858195"))
		skin.set_stylebox("normal", control, normal)
		skin.set_stylebox("hover", control, hover)
		skin.set_stylebox("pressed", control, pressed)
		skin.set_stylebox("hover_pressed", control, hover)
		skin.set_stylebox("focus", control, surface(Color.TRANSPARENT, Color("#c47ec4")))
		skin.set_stylebox("disabled", control, surface(Color("#161421"), Color("#444257")))
	skin.set_stylebox("pressed", "CheckButton", normal)
	skin.set_color("button_checked_color", "CheckButton", FOCUS)
	skin.set_color("button_unchecked_color", "CheckButton", MUTED)
	skin.set_stylebox("slider", "HSlider", _slider_track(Color("#36304b")))
	skin.set_stylebox("grabber_area", "HSlider", _slider_track(Color("#9d5ca8")))
	skin.set_stylebox("grabber_area_highlight", "HSlider", _slider_track(FOCUS))
	return skin

static func surface(fill := Color("#171727dc"), rim := Color("#756984ab"),
		signal_color := Color.TRANSPARENT) -> StyleBox:
	var box := NeonPanel.new()
	box.fill = fill
	box.rim = rim
	box.signal_color = signal_color
	box.content_margin_left = 26
	box.content_margin_right = 23
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

static func active_surface() -> StyleBox:
	return surface(Color("#30213adb"), Color("#be7cb9"), Color("#d082c4"))

static func primary_surface() -> StyleBox:
	return surface(Color("#251b32eb"), Color("#9978a7"))

static func _slider_track(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	box.set_corner_radius_all(2)
	return box

static func label(value: String, size: int, color := TEXT) -> Label:
	var result := Label.new()
	result.text = value
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result

static func button(title: String, action := Callable()) -> Button:
	var result := Button.new()
	result.text = title
	result.alignment = HORIZONTAL_ALIGNMENT_LEFT
	result.custom_minimum_size.y = 47
	if action.is_valid():
		result.pressed.connect(action)
	return result

static func minimize_button(action: Callable) -> Button:
	var result := button("最小化", action)
	result.name = "MinimizeWindow"
	result.tooltip_text = "最小化到任务栏"
	result.accessibility_name = "最小化窗口"
	result.custom_minimum_size.x = 140
	result.add_theme_color_override("font_color", MUTED)
	return result

static func shade(colors: PackedColorArray, offsets: PackedFloat32Array, end := Vector2.RIGHT) -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = end
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture
