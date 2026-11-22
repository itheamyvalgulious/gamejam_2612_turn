extends SceneTree
const Field := preload("res://scripts/terrain_field.gd")
func _init() -> void:
	var f := Field.new()
	for x in [-500.0, -420.0, -350.0, -250.0, 0.0]:
		print("=== x=", x)
		for z in range(-220, 80, 20):
			var h = f.height(x, float(z))
			var sl = f.slope(x, float(z))
			print("z=%d h=%.1f slope=%.2f" % [z, h, sl])
	print("=== forest / river")
	for z in [520.0, 600.0, 700.0, 760.0, 820.0]:
		print("z=", z, " river_x=", f.river_x(z), " hw=", f.river_halfwidth(z), " wl=", f.water_level(z))
		for x in [-60.0, -40.0, -20.0, 0.0, 30.0]:
			print(" x=", x, " h=", f.height(x, z), " sl=", f.slope(x, z))
	quit()
