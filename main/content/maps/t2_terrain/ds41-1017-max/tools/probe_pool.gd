extends SceneTree
func _initialize() -> void:
	var f := TerrainField.new()
	for z in [-180.0, -175.0, -170.0, -165.0, -160.0, -155.0, -150.0]:
		var cx: float = f.river_x(z)
		var hw: float = f.river_halfwidth(z)
		print("z=%.0f cx=%.1f hw=%.1f tree_limit=%.1f  h(x-15)=%.1f h(x-20)=%.1f" % [z, cx, hw, hw*1.15, f.height(cx-15.0,z), f.height(cx-20.0,z)])
	for p in [Vector2(-195,-170), Vector2(-195,-165), Vector2(-190,-160), Vector2(-200,-160), Vector2(-182,-176)]:
		print(p, " dist=", f.river_dist(p.x,p.y), " hw=", f.river_halfwidth(p.y), " h=", f.height(p.x,p.y))
	quit()
