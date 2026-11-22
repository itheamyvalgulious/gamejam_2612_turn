extends SceneTree

func _initialize() -> void:
	var f := TerrainField.new()
	print("river_x pool/z: ", f.river_x(-232.0), " ", f.river_x(-220.0), " ", f.river_x(-200.0), " ", f.river_x(-180.0), " ", f.river_x(-168.0), " ", f.river_x(-150.0), " ", f.river_x(-120.0), " ", f.river_x(-90.0))
	print("water: lip ", f.water_level(-232.0), " pool ", f.water_level(-168.0), " z-200 ", f.water_level(-200.0), " z-150 ", f.water_level(-150.0))
	for z in [-260.0, -232.0, -220.0, -210.0, -200.0, -190.0, -180.0, -168.0, -150.0, -130.0, -110.0, -90.0, -60.0, -30.0, 0.0, 40.0, 80.0]:
		var cx: float = f.river_x(z)
		var row := "z=%7.1f cx=%7.1f cx+55=%7.1f cx+90=%7.1f cx-55=%7.1f cx-90=%7.1f  h(center)=%7.1f" % [z, cx, f.height(cx+55.0,z), f.height(cx+90.0,z), f.height(cx-55.0,z), f.height(cx-90.0,z), f.height(cx,z)]
		print(row)
	# vertical curtain footprint samples
	for z in [-225.0, -210.0, -195.0, -180.0, -165.0]:
		var cx2: float = f.river_x(z)
		var line := "z=%.0f " % z
		for dx in [-40.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 40.0]:
			line += "%6.0f" % f.height(cx2+dx, z)
		print(line)
	quit()
