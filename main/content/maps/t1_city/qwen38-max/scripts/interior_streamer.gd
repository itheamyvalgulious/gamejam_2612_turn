# ---------------------------------------------------------------- streaming
class_name InteriorStreamer
extends Node
## Budgeted on-demand interior generation around the camera. Chunks are built
## lazily (max ~10 ms per frame) and evicted when far away.

var gen: CityGen
var built := {}
var _timer := 0.0

func _process(delta: float) -> void:
	_timer += delta
	if _timer < 0.35:
		return
	_timer = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_step(cam.global_position, 10)

func _step(cp: Vector3, budget_ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	var ck := gen.chunk_of(cp)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var k := Vector2i(ck.x + dx, ck.y + dz)
			if built.has(k):
				continue
			if not gen.interior_by_chunk.has(k):
				built[k] = null
				continue
			_build_chunk(k, cp)
			if Time.get_ticks_msec() - t0 > budget_ms:
				return
	# eviction
	var dead := []
	for k in built:
		if built[k] == null:
			continue
		var cpos := Vector3(k.x * gen.CHUNK + 250.0, 0, k.y * gen.CHUNK + 250.0)
		if (cpos - cp).length() > 1600.0:
			dead.append(k)
	for k in dead:
		var mi: MeshInstance3D = built[k]
		mi.queue_free()
		built.erase(k)

func force_at(cp: Vector3, radius: float = 750.0) -> void:
	for k in gen.interior_by_chunk:
		if built.has(k) and built[k] != null:
			continue
		var cpos := Vector3(k.x * gen.CHUNK + 250.0, 0, k.y * gen.CHUNK + 250.0)
		if (cpos - cp).length() < radius:
			_build_chunk(k, cp)

func _build_chunk(k: Vector2i, cp: Vector3) -> void:
	var bgen := InteriorsGen.new()
	var mb := MeshBuf.new()
	for t in gen.interior_by_chunk[k]:
		var sub := bgen.build_building(gen, t, cp)
		if sub.is_empty():
			continue
		mb.V.append_array(sub.V)
		mb.N.append_array(sub.N)
		mb.U.append_array(sub.U)
		mb.U2.append_array(sub.U2)
		mb.C.append_array(sub.C)
		var off := mb.I.size()
		mb.I.append_array(sub.I)
		# offset indices
		var nsub := sub.V.size()
		if nsub > 0:
			for i in range(mb.I.size() - sub.I.size(), mb.I.size()):
				mb.I[i] = mb.I[i]  # placeholder, fixed below
		# (indices already appended un-offset; fix:)
		var start := mb.I.size() - sub.I.size()
		var vbase := mb.V.size() - nsub
		for i in range(start, mb.I.size()):
			mb.I[i] += vbase
	if mb.is_empty():
		built[k] = null
		return
	var mesh := ArrayMesh.new()
	mb.make_surface(mesh, gen.mats["interior"])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "interior_%d_%d" % [k.x, k.y]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gen._root.add_child(mi)
	built[k] = mi
	gen.stat_interior_tris += mb.tri_count()
