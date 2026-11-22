class_name RouteLine
extends RefCounted
## Glowing route strip along the main path (scrolling chevrons point toward the
## bridge) + Label3D signage above doors and at key decision points.

var lay: Layout
var g: Geom

func _init(layout: Layout) -> void:
	lay = layout
	g = Geom.new()

func build(root: Node, mats: Dictionary) -> void:
	var route: Array = lay.route
	var dist := 0.0
	for i in route.size() - 1:
		var p0: Vector3 = route[i]
		var p1: Vector3 = route[i + 1]
		var d := p1 - p0
		var flat := Vector3(d.x, 0, d.z)
		if flat.length() < 0.001:
			continue
		var side := Vector3.UP.cross(flat.normalized()) * 0.15
		var d0 := dist
		dist += d.length()
		var q0 := p0 + side + Vector3(0, 0.025, 0)
		var q1 := p1 + side + Vector3(0, 0.025, 0)
		var q2 := p1 - side + Vector3(0, 0.025, 0)
		var q3 := p0 - side + Vector3(0, 0.025, 0)
		var t := g.tool("emit_route")
		var pts := [q0, q1, q2, q0, q2, q3]
		var uvs := [Vector2(d0 / 1.25, 0), Vector2(dist / 1.25, 0), Vector2(dist / 1.25, 1),
			Vector2(d0 / 1.25, 0), Vector2(dist / 1.25, 1), Vector2(d0 / 1.25, 1)]
		for k in 6:
			t.set_color(Color.WHITE)
			t.set_normal(Vector3.UP)
			t.set_uv(uvs[k])
			t.add_vertex(pts[k])
	var route_root := Node3D.new()
	route_root.name = "RouteLine"
	root.add_child(route_root)
	g.commit_all(route_root, {"emit_route": mats["emit_route"]})
	for mi in route_root.get_children():
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_signage(root)

func _signage(root: Node) -> void:
	var sig := Node3D.new()
	sig.name = "Signage"
	root.add_child(sig)
	var placed := {}
	for r in lay.rooms:
		var accent: Color = Layout.STYLE_TINT.get(r["style"], Color(0.5, 0.8, 1.0))
		accent = accent.lightened(0.35)
		for d in r["doors"]:
			if d["kind"] == "airlock" and d["w"] < 2.4:
				continue
			var side: String = d["side"]
			var key := "%d|%s|%.1f|%.1f" % [r["deck"], side, d["pos"], d["w"]]
			var key2 := "%d|%s|%.1f|%.1f" % [r["deck"], _opp(side), d["pos"], d["w"]]
			if placed.has(key) or placed.has(key2):
				continue
			placed[key] = true
			# decide which face gets the label: neighbor room across this wall
			var nb := _neighbor_across(r, side, d["pos"])
			if nb.is_empty():
				continue
			var pos: Vector3
			var facing: Vector3
			var ylbl: float = r["y0"] + d["h"] + 0.55
			match side:
				"N":
					pos = Vector3(d["pos"], ylbl, r["z0"] - 0.28)
					facing = Vector3(0, 0, -1)
				"S":
					pos = Vector3(d["pos"], ylbl, r["z1"] + 0.28)
					facing = Vector3(0, 0, 1)
				"W":
					pos = Vector3(r["x0"] - 0.28, ylbl, d["pos"])
					facing = Vector3(-1, 0, 0)
				"E":
					pos = Vector3(r["x1"] + 0.28, ylbl, d["pos"])
					facing = Vector3(1, 0, 0)
			var text: String = r["name"]
			if r["style"] == "shaft":
				text = "STAIR %s · DECK %d" % [String(r["name"]).right(2), r["deck"]]
			_add_label(sig, text, pos, facing, accent, 40)

	# big directional signs at key decision points
	_add_label(sig, "DECK 0 · ENGINEERING", Vector3(80.0, 4.6, -9.6), Vector3(0, 0, -1), Color(1.0, 0.8, 0.4), 56)
	_add_label(sig, "DECK 1 · MAIN", Vector3(118.0, 11.6, -9.9), Vector3(0, 0, -1), Color(1.0, 0.85, 0.5), 56)
	_add_label(sig, "RAMP R-1 → DECK 1", Vector3(81.0, 4.4, -9.6), Vector3(0, 0, -1), Color(0.9, 0.75, 0.35), 44)
	_add_label(sig, "BRIDGE →", Vector3(240.0, 19.2, -2.6), Vector3(0, 0, -1), Color(0.6, 0.85, 1.0), 52)
	_add_label(sig, "← HANGAR BAY", Vector3(132.0, 13.4, -2.6), Vector3(0, 0, -1), Color(0.95, 0.85, 0.4), 44)
	_add_label(sig, "AIRLOCK A-1", Vector3(70.0, 4.0, 5.75), Vector3(0, 0, 1), Color(1.0, 0.55, 0.25), 44)
	_add_label(sig, "ISV MERIDIAN · BRIDGE", Vector3(253.0, 19.6, 0.0), Vector3(1, 0, 0), Color(0.65, 0.85, 1.0), 52)
	_add_label(sig, "EVA", Vector3(64.0, 10.0, -23.6), Vector3(0, 0, 1), Color(1.0, 0.6, 0.3), 48)

func _opp(side: String) -> String:
	match side:
		"N": return "S"
		"S": return "N"
		"E": return "W"
	return "E"

func _neighbor_across(r: Dictionary, side: String, pos: float) -> Dictionary:
	for q in lay.rooms:
		if q == r or q["deck"] != r["deck"]:
			continue
		match side:
			"N":
				if absf(q["z1"] - r["z0"]) < 0.05 and pos > q["x0"] and pos < q["x1"]:
					return q
			"S":
				if absf(q["z0"] - r["z1"]) < 0.05 and pos > q["x0"] and pos < q["x1"]:
					return q
			"W":
				if absf(q["x1"] - r["x0"]) < 0.05 and pos > q["z0"] and pos < q["z1"]:
					return q
			"E":
				if absf(q["x0"] - r["x1"]) < 0.05 and pos > q["z0"] and pos < q["z1"]:
					return q
	return {}

func _add_label(parent: Node, text: String, pos: Vector3, facing: Vector3, color: Color, font_size: int) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.011
	l.modulate = color
	l.outline_size = 16
	l.outline_modulate = Color(0.02, 0.025, 0.04, 0.92)
	l.position = pos
	l.rotation = Vector3.ZERO
	# Label3D front faces -Z after look_at convention; orient via yaw so text
	# reads from `facing` direction. Verified empirically: front is +Z? We use
	# basis so that local +Z maps to facing.
	var yaw := atan2(facing.x, facing.z) + PI
	l.rotation.y = yaw
	l.no_depth_test = false
	l.render_priority = 2
	parent.add_child(l)
