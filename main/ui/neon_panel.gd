extends StyleBox

var fill := Color.TRANSPARENT
var rim := Color.TRANSPARENT
var signal_color := Color.TRANSPARENT


func _draw(item: RID, bounds: Rect2) -> void:
	var end := bounds.end
	var start := bounds.position
	var slant := minf(13.0, bounds.size.x * 0.16)
	var a := start + Vector2(slant, 0.5)
	var b := Vector2(end.x - 0.5, start.y + 0.5)
	var c := end - Vector2(slant, 0.5)
	var d := Vector2(start.x + 0.5, end.y - 0.5)
	if fill.a > 0.0:
		var upper := fill.darkened(0.08)
		var lower := fill.lerp(Color(Color("#664574"), fill.a), 0.22)
		RenderingServer.canvas_item_add_polygon(item, PackedVector2Array([a, b, c, d]),
			PackedColorArray([upper, upper, lower, lower]))
	if rim.a > 0.0:
		RenderingServer.canvas_item_add_polyline(item, PackedVector2Array([a, b, c, d, a]),
			PackedColorArray([rim]), 1.0, true)
	if signal_color.a > 0.0:
		var edge := PackedVector2Array([d + Vector2(4, -1), c + Vector2(-6, -1)])
		RenderingServer.canvas_item_add_polyline(item, edge,
			PackedColorArray([Color(signal_color, 0.18)]), 6.0, true)
		RenderingServer.canvas_item_add_polyline(item, edge,
			PackedColorArray([signal_color, Color(signal_color, 0.35)]), 2.0, true)
