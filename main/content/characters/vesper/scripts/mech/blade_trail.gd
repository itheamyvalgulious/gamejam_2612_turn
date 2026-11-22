extends MeshInstance3D
## Swept blade ribbon.  Samples the world-space blade base/tip every frame and
## builds a fading triangle strip from the history.  This is 100% procedural
## geometry; no textures or particles involved.

const MAT = preload("res://scripts/mech/materials.gd")

var lifetime := 0.10
var max_samples := 30
var min_sample_dist := 0.03

var _samples: Array = []   # each: {b: Vector3, t: Vector3, age: float, tone: Color}
var _active := false
var _window := Vector2.ZERO
var _owner_rig: Node3D
var _base_marker: Marker3D
var _tip_marker: Marker3D
var _surface := ArrayMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _surface
	material_override = MAT.trail()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	set_process(false)


func clear() -> void:
	_samples.clear()
	_active = false
	visible = false
	_surface.clear_surfaces()


func begin(rig: Node3D, base_marker: Marker3D, tip_marker: Marker3D, start_t: float, end_t: float) -> void:
	_owner_rig = rig
	_base_marker = base_marker
	_tip_marker = tip_marker
	_window = Vector2(start_t, end_t)
	_samples.clear()
	_active = true
	visible = true


func add_sample(base_pos: Vector3, tip_pos: Vector3, tone: Color) -> void:
	if not _active:
		return
	if not _samples.is_empty():
		var last: Dictionary = _samples[_samples.size() - 1]
		if (last["t"] as Vector3).distance_to(tip_pos) < min_sample_dist:
			return
	_samples.append({"b": base_pos, "t": tip_pos, "age": 0.0, "tone": tone})
	while _samples.size() > max_samples:
		_samples.pop_front()


func tick(dt: float, active_now: bool) -> void:
	_active = active_now
	for s in _samples:
		s["age"] = float(s["age"]) + dt
	while not _samples.is_empty() and float(_samples[0]["age"]) > lifetime:
		_samples.pop_front()
	if _samples.size() < 2 and not _active:
		visible = false
		return
	visible = _samples.size() >= 2
	_rebuild()


func _rebuild() -> void:
	_surface.clear_surfaces()
	if _samples.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _samples.size() - 1:
		var s0: Dictionary = _samples[i]
		var s1: Dictionary = _samples[i + 1]
		var a0 := float(s0["age"]) / lifetime
		var a1 := float(s1["age"]) / lifetime
		var a0v := pow(clampf(1.0 - a0, 0.0, 1.0), 1.6)
		var a1v := pow(clampf(1.0 - a1, 0.0, 1.0), 1.6)
		var c0: Color = s0["tone"]
		var c1: Color = s1["tone"]
		var ca := Color(c0.r, c0.g, c0.b, a0v * 0.38)
		var cb := Color(c1.r, c1.g, c1.b, a1v * 0.52)
		var b0: Vector3 = s0["b"]
		var t0: Vector3 = s0["t"]
		var b1: Vector3 = s1["b"]
		var t1: Vector3 = s1["t"]
		# Quad from base to tip between two samples.  The trailing (older) edge
		# fades out, the leading edge at the blade stays sharp.
		_quad(st, b0, t0, t1, b1, Color(ca.r, ca.g, ca.b, ca.a * 0.15),
			Color(ca.r, ca.g, ca.b, ca.a), Color(cb.r, cb.g, cb.b, cb.a),
			Color(cb.r, cb.g, cb.b, cb.a * 0.15))
	var m := st.commit()
	if m != null:
		mesh = m
		_surface = m


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	# Two-sided ribbon; no normals needed (unshaded additive shader).
	var verts := [
		[ a, ca, Vector2(0.0, 0.0) ], [ b, cb, Vector2(1.0, 0.0) ], [ c, cc, Vector2(1.0, 1.0) ],
		[ a, ca, Vector2(0.0, 0.0) ], [ c, cc, Vector2(1.0, 1.0) ], [ d, cd, Vector2(0.0, 1.0) ],
	]
	for v in verts:
		st.set_color(v[1])
		st.set_uv(v[2])
		st.set_normal(Vector3.UP)
		st.add_vertex(v[0])