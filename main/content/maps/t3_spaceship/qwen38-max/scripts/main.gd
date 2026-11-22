extends Node3D
## ISV Meridian — fully procedural mall-scale starship interior.
## Run modes:
##   godot --path .                  interactive fly camera (WASD/mouse)
##   godot --path . -- --capture     render waypoint screenshots to shots/
##   godot --path . -- --seed=42     different layout jitter seed
##   godot --path . -- --novolfog    disable volumetric fog volumes
##   godot --path . -- --rebake      force geometry regeneration + cache rewrite
## Mesh batches are cached to res://cache/*.res after first generation and
## streamed in via threaded loading on later runs (stable frame times).

const BAKE_VERSION := 4
const CACHE := "res://cache/"

var pending := {}          # key -> path, threaded mesh loads in flight
var ship: Node3D
var mats: Dictionary
var lay: Layout
var lights_obj: Lights
var probe_i := 0
var booted := false

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var user := OS.get_cmdline_user_args()
	var lseed := 7
	for a in user:
		if a.begins_with("--seed="):
			lseed = int(a.substr(7))
	var capture_mode := user.has("--capture")
	lay = Layout.new(lseed)
	mats = Mats.build()
	ship = Node3D.new()
	ship.name = "Ship"
	add_child(ship)

	var loaded := false
	if not user.has("--rebake"):
		loaded = _try_cache(lseed)
	if not loaded:
		_generate()
		_save_cache(lseed)
	print("geometry ready ms: ", Time.get_ticks_msec() - t0)

	lights_obj = Lights.new(lay)
	if user.has("--novolfog"):
		lights_obj.volfog = false
	lights_obj.build(self)
	var route := RouteLine.new(lay)
	route.build(self, mats)
	print("BUILD TOTAL ms: ", Time.get_ticks_msec() - t0, "  cached=", loaded)
	_boot_sequence(capture_mode)

# --------------------------------------------------------------- cache / stream

func _manifest_path() -> String:
	return CACHE + "manifest.json"

func _try_cache(seed: int) -> bool:
	if not FileAccess.file_exists(_manifest_path()):
		return false
	var f := FileAccess.open(_manifest_path(), FileAccess.READ)
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	if doc == null or int(doc.get("version", -1)) != BAKE_VERSION or int(doc.get("seed", -2)) != seed:
		return false
	var keys: Array = doc.get("keys", [])
	if keys.is_empty():
		return false
	for k in keys:
		var path: String = CACHE + String(k) + ".res"
		if not FileAccess.file_exists(path):
			return false
	for k in keys:
		var path: String = CACHE + String(k) + ".res"
		ResourceLoader.load_threaded_request(path)
		pending[String(k)] = path
		var mi := MeshInstance3D.new()
		mi.name = String(k)
		ship.add_child(mi)
	print("cache hit: ", keys.size(), " mesh batches streaming")
	return true

func _save_cache(seed: int) -> void:
	var dir := DirAccess.open("res://")
	if dir and not dir.dir_exists("cache"):
		dir.make_dir("cache")
	var keys := []
	for mi in ship.get_children():
		if mi is MeshInstance3D and mi.mesh != null:
			var m: ArrayMesh = mi.mesh
			var mat: Material = m.surface_get_material(0)
			m.surface_set_material(0, null)
			var err := ResourceSaver.save(m, CACHE + mi.name + ".res")
			m.surface_set_material(0, mat)
			if err == OK:
				keys.append(mi.name)
	var f := FileAccess.open(_manifest_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": BAKE_VERSION, "seed": seed, "keys": keys}))
	f.close()
	print("cache written: ", keys.size(), " batches")

func _generate() -> void:
	var g := Geom.new()
	var st := Structure.new(g, lay)
	st.build_all()
	st.build_ramp(lay.get_room("CARGO RAMP R-1"))
	var hull := Hull.new(g, lay)
	hull.build()
	var props := Props.new(g, lay)
	props.build_all()
	g.commit_all(ship, mats, "")
	var tris := 0
	for mi in ship.get_children():
		if mi is MeshInstance3D:
			var arrs: Array = mi.mesh.surface_get_arrays(0)
			var idx: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3
	print("generated triangles: ", tris, "  batches: ", ship.get_child_count())

# --------------------------------------------------------------- boot / warmup

func _boot_sequence(capture_mode: bool) -> void:
	# shader warm-up gallery: one quad per material rendered off-ship so every
	# shader variant compiles before the first real frame (no first-sight hitch)
	var gal := Node3D.new()
	gal.name = "WarmupGallery"
	add_child(gal)
	var i := 0
	for k in mats.keys():
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		q.mesh = pm
		q.material_override = mats[k]
		q.position = Vector3(30.0 + float(i % 8) * 1.5, -160.0, float(i / 8) * 1.5)
		gal.add_child(q)
		i += 1
	var lbl := Label3D.new()
	lbl.text = "WARMUP 0123456789"
	lbl.position = Vector3(30.0, -159.0, 20.0)
	gal.add_child(lbl)
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(36.0, -152.0, 10.0)
	cam.look_at(Vector3(36.0, -160.0, 10.0), Vector3.UP)
	add_child(cam)
	for k in 4:
		await RenderingServer.frame_post_draw
	gal.queue_free()
	cam.queue_free()
	booted = true
	if capture_mode:
		var cap := Capture.new()
		add_child(cap)
	else:
		var p := PlayerCam.new(lay)
		add_child(p)

func _process(_delta: float) -> void:
	# stream cached meshes in as they finish loading
	if not pending.is_empty():
		var done := []
		for k in pending.keys():
			var prog: Array = []
			var st := ResourceLoader.load_threaded_get_status(pending[k], prog)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				var m: Resource = ResourceLoader.load_threaded_get(pending[k])
				if m is ArrayMesh:
					var mi: MeshInstance3D = ship.get_node_or_null(k)
					if mi:
						m.surface_set_material(0, mats.get(k))
						mi.mesh = m
				done.append(k)
			elif st == ResourceLoader.THREAD_LOAD_FAILED:
				done.append(k)
		for k in done:
			pending.erase(k)
	# stagger reflection-probe baking: one per frame keeps frame time flat
	if booted and lights_obj and probe_i < lights_obj.probe_count():
		lights_obj.spawn_probe(probe_i, self)
		probe_i += 1
