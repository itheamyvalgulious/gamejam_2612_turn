extends RefCounted

const INK := Color("#0b141c")
const TEXT := Color("#edf4f7")
const MUTED := Color("#a9b9c4")
const FOCUS := Color("#71e2de")
const BLOCKED := Color("#ffbd82")
const DANGER := Color("#ec5364")
const PHASE := Color("#b4a5ff")

static func theme() -> Theme:
	var skin := Theme.new()
	skin.default_font = preload("res://runtime/fonts/act/ui_font.tres")
	skin.default_font_size = 18
	for state in ["normal", "hover", "pressed", "focus"]:
		var color_name := "font_color" if state == "normal" else "font_%s_color" % state
		skin.set_color(color_name, "Button", TEXT if state == "normal" else FOCUS)
	skin.set_stylebox("normal", "Button", surface(Color(INK, 0.55)))
	skin.set_stylebox("hover", "Button", surface(Color("#132b34"), FOCUS))
	skin.set_stylebox("pressed", "Button", surface(Color("#17353e"), FOCUS))
	skin.set_stylebox("focus", "Button", surface(Color.TRANSPARENT, FOCUS))
	return skin

static func surface(fill: Color, accent := Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = accent
	box.border_width_left = 0 if accent.a == 0.0 else 3
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 6
	box.content_margin_bottom = 6
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
