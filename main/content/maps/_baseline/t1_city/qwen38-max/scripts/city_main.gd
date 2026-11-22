extends Node3D
## Entry scene: parses cmdline args, builds the city, adds a free-fly camera.

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			out["seed"] = int(a.trim_prefix("--seed="))
		elif a.begins_with("--focus="):
			var parts := a.trim_prefix("--focus=").split(",")
			if parts.size() == 2:
				out["focus"] = Vector3(float(parts[0]), 0, float(parts[1]))
	return out

func _ready() -> void:
	var args := _parse_args()
	print("[city] generating (seed=%s)..." % str(args.get("seed", 1337)))
	var t0 := Time.get_ticks_msec()
	var gen := CityGen.new()
	gen.params = args
	gen.build(self)
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	print("[city] built in %.1fs  buildings=%d  tris=%d" % [dt, gen.stat_buildings, gen.stat_tris])

	var cam := FreeCam.new()
	cam.name = "FreeCam"
	add_child(cam)
	var f: Vector3 = args.get("focus", Vector3.ZERO)
	cam.position = f + Vector3(-500, 420, 700)
	cam.look_at(f + Vector3(0, 60, 0), Vector3.UP)
