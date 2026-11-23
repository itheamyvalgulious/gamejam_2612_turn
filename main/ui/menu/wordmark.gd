extends Control

const FONT_SIZE := 153
const BASELINE := 128.0
const WIDTH := 460.0


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 151.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var display := FontVariation.new()
	display.base_font = get_theme_default_font()
	display.variation_embolden = 2.25
	display.spacing_glyph = -5
	_add_slice(display, PackedVector2Array([
		Vector2.ZERO, Vector2(WIDTH, 0), Vector2(WIDTH, 82), Vector2(284, 93), Vector2(0, 93),
	]), 0.0, Color("#f6f3ff"))
	_add_slice(display, PackedVector2Array([
		Vector2(0, 94), Vector2(284, 94), Vector2(WIDTH, 83),
		Vector2(WIDTH, 88), Vector2(284, 99), Vector2(0, 99),
	]), -5.0, Color("#ef91db"))
	_add_slice(display, PackedVector2Array([
		Vector2(0, 100), Vector2(284, 100), Vector2(WIDTH, 89),
		Vector2(WIDTH, 150), Vector2(0, 150),
	]), 5.0, Color("#e7c7fa"))


func _add_slice(font: Font, points: PackedVector2Array, offset: float, tone: Color) -> void:
	var mask := Polygon2D.new()
	mask.polygon = points
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	add_child(mask)
	var lettering := Node2D.new()
	lettering.draw.connect(func() -> void:
		lettering.draw_string(font, Vector2(offset + 1.0, BASELINE), "TURN",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, tone))
	mask.add_child(lettering)
