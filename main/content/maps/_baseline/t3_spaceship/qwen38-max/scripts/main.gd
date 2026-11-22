extends Node3D
## ISV Meridian — fully procedural mall-scale starship interior.
## Run modes:
##   godot --path .                  interactive fly camera (WASD/mouse)
##   godot --path . -- --capture     render waypoint screenshots to shots/
##   godot --path . -- --seed=42     different layout jitter seed
##   godot --path . -- --novolfog    disable volumetric fog

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var user := OS.get_cmdline_user_args()
	var lseed := 7
	for a in user:
		if a.begins_with("--seed="):
			lseed = int(a.substr(7))
	var capture_mode := user.has("--capture")

	var lay := Layout.new(lseed)
	var mats := Mats.build()
	var g := Geom.new()

	var ship := Node3D.new()
	ship.name = "Ship"
	add_child(ship)

	var st := Structure.new(g, lay)
	st.build_all()
	st.build_ramp(lay.get_room("CARGO RAMP R-1"))
	print("structure ms: ", Time.get_ticks_msec() - t0)

	var hull := Hull.new(g, lay)
	hull.build()
	print("hull ms: ", Time.get_ticks_msec() - t0)

	var props := Props.new(g, lay)
	props.build_all()
	print("props ms: ", Time.get_ticks_msec() - t0)

	g.commit_all(ship, mats, "")
	print("geometry baked ms: ", Time.get_ticks_msec() - t0)

	var lights := Lights.new(lay)
	if user.has("--novolfog"):
		lights.volfog = false
	lights.build(self)

	var route := RouteLine.new(lay)
	route.build(self, mats)

	# stats
	var tris := 0
	var surfaces := 0
	for mi in find_children("*", "MeshInstance3D", true, false):
		var mesh: ArrayMesh = mi.mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			surfaces += 1
			var arrs: Array = mesh.surface_get_arrays(si)
			var idx: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
			var vtx: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
			tris += (idx.size() / 3) if idx.size() > 0 else (vtx.size() / 3)
	var nl := 0
	for l in find_children("*", "Light3D", true, false):
		nl += 1
	print("rooms: ", lay.rooms.size(), "  surfaces: ", surfaces, "  triangles: ", tris, "  lights: ", nl)
	print("BUILD TOTAL ms: ", Time.get_ticks_msec() - t0)

	if capture_mode:
		var cap := Capture.new()
		add_child(cap)
	else:
		var p := PlayerCam.new(lay)
		add_child(p)
