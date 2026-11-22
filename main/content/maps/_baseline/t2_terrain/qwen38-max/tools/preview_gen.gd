extends SceneTree
## Headless preview: generate terrain data and dump top-down maps for inspection.
## Run: godot --headless --path . -s res://tools/preview_gen.gd

const TerrainGen := preload("res://scripts/terrain_gen.gd")

func _init() -> void:
	var t := TerrainGen.new()
	var t0 := Time.get_ticks_msec()
	t.generate()
	var dt := Time.get_ticks_msec() - t0
	print("generated in %d ms  verts=%d" % [dt, TerrainGen.VX * TerrainGen.VZ])

	# stats
	var hmin := 1e9
	var hmax := -1e9
	for i in range(t.height.size()):
		hmin = minf(hmin, t.height[i])
		hmax = maxf(hmax, t.height[i])
	print("height range: %.1f .. %.1f" % [hmin, hmax])

	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)

	# heightmap preview (grayscale) + biome preview (rgb from splat)
	var img_h := Image.create(TerrainGen.VX, TerrainGen.VZ, false, Image.FORMAT_RGB8)
	var img_b := Image.create(TerrainGen.VX, TerrainGen.VZ, false, Image.FORMAT_RGB8)
	for iz in range(TerrainGen.VZ):
		for ix in range(TerrainGen.VX):
			var i := iz * TerrainGen.VX + ix
			var h := t.height[i]
			var g := clampf((h - hmin) / (hmax - hmin), 0.0, 1.0)
			img_h.set_pixel(ix, iz, Color(g, g, g))
			var s := t.splat_at(ix * TerrainGen.CELL, iz * TerrainGen.CELL)
			# grass=green rock=gray snow=white sand=yellow
			var c := Color(0, 0, 0)
			c += Color(0.15, 0.55, 0.15) * s.x
			c += Color(0.35, 0.32, 0.30) * s.y
			c += Color(0.95, 0.97, 1.0) * s.z
			c += Color(0.85, 0.75, 0.45) * s.w
			img_b.set_pixel(ix, iz, c)
	img_h.flip_y()
	img_b.flip_y()
	img_h.save_png(dir + "/_preview_height.png")
	img_b.save_png(dir + "/_preview_biome.png")
	print("previews saved")
	quit()
