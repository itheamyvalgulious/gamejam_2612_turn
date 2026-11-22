extends SceneTree

## Offline map preview (no rendering): hillshaded biome map + height stats.
## godot --headless --path . --script tools/preview_map.gd

const Field := preload("res://scripts/terrain_field.gd")

func _init() -> void:
	var f := Field.new()
	var n := 800
	var step := 3200.0 / float(n)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var hmin := 99999.0
	var hmax := -99999.0
	var counts := {"snow": 0, "forest": 0, "rock": 0, "grass": 0}
	var t0 := Time.get_ticks_msec()
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			var x := -1600.0 + (i + 0.5) * step
			var z := -1600.0 + (j + 0.5) * step
			var h := f.height(x, z)
			heights[j * n + i] = h
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
	for j in n:
		for i in n:
			var x := -1600.0 + (i + 0.5) * step
			var z := -1600.0 + (j + 0.5) * step
			var h := heights[j * n + i]
			var hl := heights[j * n + maxi(i - 1, 0)]
			var hr := heights[j * n + mini(i + 1, n - 1)]
			var hd := heights[maxi(j - 1, 0) * n + i]
			var hu := heights[mini(j + 1, n - 1) * n + i]
			var nx := (hl - hr) / (2.0 * step)
			var nz := (hd - hu) / (2.0 * step)
			var shade := clampf(0.55 - nx * 0.55 - nz * 0.35, 0.1, 1.35)
			var sl := 1.0 - 1.0 / sqrt(1.0 + nx * nx + nz * nz)
			var sn := f.snow(x, z, h, sl)
			var fo := f.forest(x, z, h, sl)
			var rk := f.rock(x, z, h, sl)
			var col: Color
			if sn > 0.5:
				col = Color(0.92, 0.95, 1.0)
				counts.snow += 1
			elif rk > 0.5:
				col = Color(0.44, 0.42, 0.40)
				counts.rock += 1
			elif fo > 0.45:
				col = Color(0.07, 0.26, 0.09)
				counts.forest += 1
			else:
				col = Color(0.30, 0.40, 0.18)
				counts.grass += 1
			col = col.lerp(Color(0.62, 0.60, 0.57), clampf((h - 700.0) / 600.0, 0.0, 0.5) * (1.0 - sn))
			if h < f.water_level(z) + 0.6 and f.river_dist(x, z) < f.river_halfwidth(z) * 1.4:
				col = Color(0.12, 0.38, 0.52)
			img.set_pixel(i, j, Color(col.r * shade, col.g * shade, col.b * shade))
	img.save_png(ProjectSettings.globalize_path("res://docs/map_preview.png"))
	print("height min/max: ", hmin, " / ", hmax, "  build ", Time.get_ticks_msec() - t0, " ms")
	print("counts: ", counts)
	var total := float(n * n)
	print("snow %.1f%%  forest %.1f%%  rock %.1f%%" % [counts.snow / total * 100.0, counts.forest / total * 100.0, counts.rock / total * 100.0])
	print("waterfall lip y=", f.height(f.river_x(f.LIP_Z), f.LIP_Z), " pool y=", f.height(f.river_x(f.POOL_Z), f.POOL_Z))
	print("peak h=", f.height(620.0, -900.0), " lowland h=", f.height(-300.0, 900.0))
	quit()