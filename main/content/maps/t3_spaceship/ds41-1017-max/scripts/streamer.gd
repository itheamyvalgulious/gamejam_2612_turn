extends Node

## Distance-based zone streamer. Baked zones + their lights are toggled as a
## unit, so far-away rooms cost neither draw calls nor shadow maps.

var main: Node
var radius := 46.0
var zones: Array = []
var timer := 0.0
var enabled := true


func _ready() -> void:
	call_deferred("_collect")


func _collect() -> void:
	zones.clear()
	if main == null or main.interior == null:
		return
	for z in main.interior.get_children():
		if z.has_meta("zone_key"):
			if not z.has_meta("zone_aabb") or z.get_meta("zone_aabb") == null:
				z.set_meta("zone_aabb", _aabb_of(z))
			zones.append(z)
	print("STREAMER: %d zones" % zones.size())


func _aabb_of(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [n]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var a: AABB = (node as MeshInstance3D).get_aabb()
			if first:
				box = a
				first = false
			else:
				box = box.merge(a)
		for c in node.get_children():
			stack.append(c)
	return box


func _process(dt: float) -> void:
	if not enabled or zones.is_empty() or main == null or main.cam == null:
		return
	timer += dt
	if timer < 0.2:
		return
	timer = 0.0
	var p: Vector3 = main.cam.global_position
	for z in zones:
		var box: AABB = z.get_meta("zone_aabb")
		var bmin := box.position
		var bmax := box.position + box.size
		var closest := p.clamp(bmin, bmax)
		var d: float = p.distance_to(closest)
		z.visible = d < radius
