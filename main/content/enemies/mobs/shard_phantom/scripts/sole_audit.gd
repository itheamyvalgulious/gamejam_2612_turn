extends SceneTree
## Samples idle/walk/attack and reports the lowest body vertex (modules + frame)
## as a sole-to-stage gap.  Stage plate top is 0.047 m in the studio.

const STAGE_TOP := 0.047

func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/character.tscn")
	var ch = ps.instantiate()
	root.add_child(ch)
	for i in 6:
		await process_frame
	for anim in ["idle", "walk", "attack"]:
		ch.play_anim(anim)
		ch.set_playing(false)
		var dur: float = ch.anim_duration()
		var best := 1e9
		var best_t := 0.0
		for i in 41:
			var t := dur * float(i) / 40.0
			ch.set_anim_time(t)
			var y: float = _lowest(ch)
			if y < best:
				best = y
				best_t = t
		print("[sole] %s min_world_y=%.4f gap=%.4f at t=%.3f" % [anim, best, best - STAGE_TOP, best_t])
	# default hover readout
	ch.play_anim("idle")
	ch.set_playing(false)
	ch.set_anim_time(0.0)
	await process_frame
	var dbg: Dictionary = ch.rig_debug()
	print("[sole] debug_hover_gap=", dbg.get("HOVER GAP"), " sole_y=", dbg.get("SOLE Y"))
	quit(0)


func _lowest(ch) -> float:
	var mn := 1e9
	var nodes: Array = []
	for m in ch.field.mods:
		nodes.append(m["node"])
	for e in ch.rig.frame_parts:
		nodes.append(e["node"])
	for n in nodes:
		if not is_instance_valid(n) or not n is MeshInstance3D or not n.visible:
			continue
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var box: AABB = mi.mesh.get_aabb()
		var xf: Transform3D = mi.global_transform
		for k in 8:
			var p := box.position + Vector3(
				box.size.x * (1.0 if (k & 1) else 0.0),
				box.size.y * (1.0 if (k & 2) else 0.0),
				box.size.z * (1.0 if (k & 4) else 0.0))
			var wy := (xf * p).y
			if wy < mn:
				mn = wy
	return mn
