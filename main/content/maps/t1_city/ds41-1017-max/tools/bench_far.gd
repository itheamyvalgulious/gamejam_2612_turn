extends SceneTree

func _init() -> void:
	var plan := CityPlan.new()
	plan.generate(1337)
	Builder.setup(plan)
	Mats.build()
	var keys: Array = []
	for c in plan.blocks:
		pass
	var t0 := Time.get_ticks_usec()
	var n := 0
	var tris := 0
	for cx in 20:
		for cz in 20:
			var c := Vector2i(cx, cz)
			var blds := plan.bld_in_chunk(c)
			var mb := MB.new()
			for b in blds:
				Builder.far(b, mb)
			tris += mb.tri_count()
			var mesh := mb.commit(Mats.surface, Mats.glass)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			n += 1
			mi.free()
	print("400 far chunks: ", (Time.get_ticks_usec() - t0) / 1000.0, " ms tris=", tris)
	quit()