class_name Vegetation
extends Node3D
## veg.gd — procedural 3D vegetation + rocks + spores for the Vale.
## Every tree is a real ArrayMesh (frustum trunks, lobed canopies, conifer
## tiers); instances are scattered with MultiMeshInstance3D and grouped into
## CHUNK-sized cells so update() can cull by camera distance. Placement uses a
## deterministic integer hash over the grid — never re-scattered per frame.

const CHUNK := 128.0
const ACTIVE_RADIUS := 14    # ~1.8 km: visible from every shot camera
const SHADOW_RADIUS := 4     # ~512 m shadows

const X0 := -2048.0
const X1 := 2048.0
const Z0 := -1280.0
const Z1 := 1280.0

var _hf: HeightField
var _rng_noise: FastNoiseLite

var _types: Array = []
var _mesh_key: Dictionary = {}   # type -> mesh key
var _mat_key: Dictionary = {}    # type -> material key
var _caps: Dictionary = {}       # type -> int
var _counts: Dictionary = {}     # type -> int
var _tr: Dictionary = {}         # type -> Array of Transform3D
var _cl: Dictionary = {}         # type -> Array of Vector2i (chunk cell)

var _meshes: Dictionary = {}     # key -> ArrayMesh
var _materials: Dictionary = {}  # key -> ShaderMaterial
var _chunks: Dictionary = {}     # Vector2i -> Node3D
var _last_cell := Vector2i(1 << 20, 1 << 20)


func build(hf: HeightField) -> void:
	_hf = hf
	_rng_noise = FastNoiseLite.new()
	_rng_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_rng_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_rng_noise.fractal_octaves = 3
	_rng_noise.frequency = 1.4
	_rng_noise.seed = 6211

	_register("jungle", "jungle_tree", "leaf", 20000)
	_register("conifer", "conifer", "leaf", 500)
	_register("snowpine", "conifer", "leaf", 200)
	_register("broadleaf", "broadleaf", "leaf", 400)
	_register("bush", "bush", "leaf", 4000)
	_register("rock", "rock", "rock", 2000)
	_register("ice", "ice", "ice", 250)
	_register("spore", "spore", "spore", 400)

	_build_meshes()
	_build_materials()
	_scatter()
	_build_multimeshes()


func update(dt: float, cam_pos: Vector3) -> void:
	# force=true for shot pipeline: one-shot calls must never be a no-op
	var cc := Vector2i(int(floor(cam_pos.x / CHUNK)), int(floor(cam_pos.z / CHUNK)))
	if cc == _last_cell and dt > 0.0:
		return
	_last_cell = cc
	for cell in _chunks:
		var chunk: Node3D = _chunks[cell]
		var dx := absi(cell.x - cc.x)
		var dz := absi(cell.y - cc.y)
		var d := maxi(dx, dz)
		chunk.visible = d <= ACTIVE_RADIUS
		var near := d <= SHADOW_RADIUS
		for mi in chunk.get_children():
			var mii := mi as MultiMeshInstance3D
			if mii != null:
				mii.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------- registration
func _register(type: String, mesh_key: String, mat_key: String, cap: int) -> void:
	_types.append(type)
	_mesh_key[type] = mesh_key
	_mat_key[type] = mat_key
	_caps[type] = cap
	_counts[type] = 0
	_tr[type] = []
	_cl[type] = []


func _add(type: String, pos: Vector3, yaw: float, scl: float) -> void:
	var cap: int = _caps[type]
	if _counts[type] >= cap:
		return
	# sink the base into the ground so nothing hovers over an
	# LOD-smoothed surface — rocks on slopes sink deeper since LOD
	# terrain dips several metres below the analytic heightfield
	var sink := (0.4 + _hash2(int(pos.x), int(pos.z), 990) * 0.5) * scl
	if type == "spore":
		sink = _hash2(int(pos.x), int(pos.z), 991) * 2.0
	elif type == "rock":
		var sl: float = _hf.slope(pos.x, pos.z)
		sink += (0.5 + sl * 6.0) * scl
	pos.y -= sink
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl)
	var xf := Transform3D(b, pos)
	_tr[type].append(xf)
	var cell := Vector2i(int(floor(pos.x / CHUNK)), int(floor(pos.z / CHUNK)))
	_cl[type].append(cell)
	_counts[type] += 1


# ------------------------------------------------------------- scatter -----
func _scatter() -> void:
	_scatter_jungle()
	_scatter_mountain()
	_scatter_snow()
	_scatter_rocks()
	_scatter_spores()


func _scatter_jungle() -> void:
	var lake_c: Vector2 = _hf.lake["c"]
	var lake_r: float = _hf.lake["r"]
	var cs := 32.0
	var ix0 := int(floor(X0 / cs))
	var ix1 := int(floor(X1 / cs))
	var iz0 := int(floor(400.0 / cs))
	var iz1 := int(floor(Z1 / cs))
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			var base_h := _hash2(ix, iz, 11)
			# keep ~1-in-4 cells empty so canopy has gaps instead of a
			# uniform carpet
			if base_h < 0.12:
				continue
			var n := 1 + int(base_h * 3.5)          # 1..4 giants per 32 m cell
			# clumped placement: trees gather around a jittered cell
			# anchor (±12 m) so stands form instead of uniform scatter
			var cx: float = (ix + _hash2(ix, iz, 20)) * cs
			var cz: float = (iz + _hash2(ix, iz, 40)) * cs
			for k in n:
				var jx: float = (_hash2(ix, iz, 30 + k) - 0.5) * 22.0
				var jz: float = (_hash2(ix, iz, 50 + k) - 0.5) * 22.0
				var x: float = clampf(cx + jx, X0 + 4.0, X1 - 4.0)
				var z: float = clampf(cz + jz, Z0 + 4.0, Z1 - 4.0)
				if not _jungle_ok(x, z, lake_c, lake_r):
					continue
				var y: float = _hf.h(x, z)
				var yaw: float = _hash2(ix, iz, 60 + k) * TAU
				# rainforest giants 25–40 m: tall enough to read as canopy
				# from aerial shots, not shrubs
				var scl: float = 1.3 + _hash2(ix, iz, 80 + k) * 0.9
				_add("jungle", Vector3(x, y, z), yaw, scl)
			# bushes / saplings — denser understorey so the jungle floor
			# isn't bare green between the giants
			var nb := 1 + int(_hash2(ix, iz, 100) * 4.0)   # 1..4 per cell
			for k in nb:
				var hx: float = _hash2(ix, iz, 120 + k)
				var hz: float = _hash2(ix, iz, 140 + k)
				var x: float = clampf((ix + hx) * cs, X0 + 4.0, X1 - 4.0)
				var z: float = clampf((iz + hz) * cs, Z0 + 4.0, Z1 - 4.0)
				if z < 400.0:
					continue
				var y: float = _hf.h(x, z)
				if _hf.slope(x, z) > 0.7:
					continue
				if _hf.river_dist(Vector2(x, z)).x < 8.0:
					continue
				if Vector2(x, z).distance_to(lake_c) < lake_r + 10.0:
					continue
				if y < _hf.water_y(x, z) + 1.0:
					continue
				var yaw: float = _hash2(ix, iz, 160 + k) * TAU
				var scl: float = 0.5 + _hash2(ix, iz, 180 + k) * 0.7
				_add("bush", Vector3(x, y, z), yaw, scl)
			# fallen logs + mossy rocks on the forest floor — breaks up
			# the green carpet with dead wood / stone detail
			var nr := int(_hash2(ix, iz, 200) * 2.0)    # 0..1 per cell
			for k in nr:
				var rx: float = clampf((ix + _hash2(ix, iz, 210 + k)) * cs, X0 + 4.0, X1 - 4.0)
				var rz: float = clampf((iz + _hash2(ix, iz, 220 + k)) * cs, Z0 + 4.0, Z1 - 4.0)
				if rz < 420.0:
					continue
				if _hf.river_dist(Vector2(rx, rz)).x < 12.0:
					continue
				var ry: float = _hf.h(rx, rz)
				var ryaw: float = _hash2(ix, iz, 230 + k) * TAU
				var rscl: float = 0.4 + _hash2(ix, iz, 240 + k) * 0.5
				_add("rock", Vector3(rx, ry, rz), ryaw, rscl)


func _jungle_ok(x: float, z: float, lake_c: Vector2, lake_r: float) -> bool:
	if z < 400.0:
		return false
	if _hf.slope(x, z) > 0.5:
		return false
	if _hf.river_dist(Vector2(x, z)).x < 15.0:
		return false
	if Vector2(x, z).distance_to(lake_c) < lake_r + 30.0:
		return false
	if _hf.h(x, z) < _hf.water_y(x, z) + 1.5:
		return false
	return true


func _scatter_mountain() -> void:
	# conifers on gentle slopes
	var cs := 90.0
	var ix0 := int(floor(X0 / cs))
	var ix1 := int(floor(X1 / cs))
	var iz0 := int(floor(-350.0 / cs))
	var iz1 := int(floor(350.0 / cs))
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			var n := int(_hash2(ix, iz, 200) * 3.0)   # 0..2 sparse
			for k in n:
				var hx: float = _hash2(ix, iz, 220 + k)
				var hz: float = _hash2(ix, iz, 240 + k)
				var x: float = clampf((ix + hx) * cs, X0 + 4.0, X1 - 4.0)
				var z: float = clampf((iz + hz) * cs, Z0 + 4.0, Z1 - 4.0)
				var sl: float = _hf.slope(x, z)
				if sl > 0.6 or sl < 0.05:
					continue
				if _hf.river_dist(Vector2(x, z)).x < 25.0:
					continue
				var y: float = _hf.h(x, z)
				if y > 320.0:
					continue
				# never inside the gorge canyon — walls are bare rock
				var rd_g: float = _hf.river_dist(Vector2(x, z)).x
				if rd_g < 55.0 and y < _hf.water_y(x, z) + 80.0:
					continue
				var yaw: float = _hash2(ix, iz, 260 + k) * TAU
				var scl: float = 0.7 + _hash2(ix, iz, 280 + k) * 0.6
				_add("conifer", Vector3(x, y, z), yaw, scl)
	# broadleaf in the valley floor near the river
	cs = 60.0
	ix0 = int(floor(X0 / cs))
	ix1 = int(floor(X1 / cs))
	iz0 = int(floor(-350.0 / cs))
	iz1 = int(floor(350.0 / cs))
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			var n := int(_hash2(ix, iz, 300) * 2.0)   # 0..1
			for k in n:
				var hx: float = _hash2(ix, iz, 320 + k)
				var hz: float = _hash2(ix, iz, 340 + k)
				var x: float = clampf((ix + hx) * cs, X0 + 4.0, X1 - 4.0)
				var z: float = clampf((iz + hz) * cs, Z0 + 4.0, Z1 - 4.0)
				var rd: float = _hf.river_dist(Vector2(x, z)).x
				if rd < 10.0 or rd > 60.0:
					continue
				# valley floor trees only — canyon walls are bare rock
				if _hf.slope(x, z) > 0.28:
					continue
				if _hf.h(x, z) > _hf.water_y(x, z) + 45.0:
					continue
				var y: float = _hf.h(x, z)
				if y < _hf.water_y(x, z) + 0.5:
					continue
				var yaw: float = _hash2(ix, iz, 360 + k) * TAU
				var scl: float = 0.6 + _hash2(ix, iz, 380 + k) * 0.6
				_add("broadleaf", Vector3(x, y, z), yaw, scl)


func _scatter_snow() -> void:
	var cs := 140.0
	var ix0 := int(floor(X0 / cs))
	var ix1 := int(floor(X1 / cs))
	var iz0 := int(floor(Z0 / cs))
	var iz1 := int(floor(-400.0 / cs))
	# sparse snow firs
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			if _hash2(ix, iz, 400) < 0.45:
				continue
			var hx: float = _hash2(ix, iz, 420)
			var hz: float = _hash2(ix, iz, 440)
			var x: float = clampf((ix + hx) * cs, X0 + 4.0, X1 - 4.0)
			var z: float = clampf((iz + hz) * cs, Z0 + 4.0, Z1 - 4.0)
			if _hf.slope(x, z) > 0.35:
				continue
			var y: float = _hf.h(x, z)
			if y < 92.0:
				continue
			var yaw: float = _hash2(ix, iz, 460) * TAU
			var scl: float = 0.7 + _hash2(ix, iz, 480) * 0.6
			_add("snowpine", Vector3(x, y, z), yaw, scl)
	# ice crystal clusters
	cs = 200.0
	ix0 = int(floor(X0 / cs))
	ix1 = int(floor(X1 / cs))
	iz0 = int(floor(Z0 / cs))
	iz1 = int(floor(-400.0 / cs))
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			if _hash2(ix, iz, 500) < 0.30:
				continue
			var hx: float = _hash2(ix, iz, 520)
			var hz: float = _hash2(ix, iz, 540)
			var x: float = clampf((ix + hx) * cs, X0 + 4.0, X1 - 4.0)
			var z: float = clampf((iz + hz) * cs, Z0 + 4.0, Z1 - 4.0)
			if _hf.slope(x, z) > 0.3:
				continue
			var y: float = _hf.h(x, z)
			if y < 95.0:
				continue
			var yaw: float = _hash2(ix, iz, 560) * TAU
			var scl: float = 0.8 + _hash2(ix, iz, 580) * 0.8
			_add("ice", Vector3(x, y, z), yaw, scl)


func _scatter_rocks() -> void:
	# steep slopes in the mountain band
	var cs := 60.0
	var ix0 := int(floor(X0 / cs))
	var ix1 := int(floor(X1 / cs))
	var iz0 := int(floor(-350.0 / cs))
	var iz1 := int(floor(350.0 / cs))
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			var hx: float = _hash2(ix, iz, 600)
			var hz: float = _hash2(ix, iz, 610)
			var x: float = clampf((ix + hx) * cs, X0 + 4.0, X1 - 4.0)
			var z: float = clampf((iz + hz) * cs, Z0 + 4.0, Z1 - 4.0)
			if _hf.slope(x, z) < 0.5:
				continue
			var n := int(_hash2(ix, iz, 620) * 2.0)   # 0..1
			for k in n:
				var y: float = _hf.h(x, z)
				var yaw: float = _hash2(ix, iz, 630 + k) * TAU
				var scl: float = 0.5 + _hash2(ix, iz, 650 + k) * 1.5
				_add("rock", Vector3(x, y, z), yaw, scl)
	# riverbank boulders (gorge + jungle banks)
	cs = 80.0
	ix0 = int(floor(X0 / cs))
	ix1 = int(floor(X1 / cs))
	iz0 = int(floor(Z0 / cs))
	iz1 = int(floor(Z1 / cs))
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			var hx: float = _hash2(ix, iz, 700)
			var hz: float = _hash2(ix, iz, 710)
			var x: float = clampf((ix + hx) * cs, X0 + 4.0, X1 - 4.0)
			var z: float = clampf((iz + hz) * cs, Z0 + 4.0, Z1 - 4.0)
			var rd: float = _hf.river_dist(Vector2(x, z)).x
			if rd < 16.0 or rd > 30.0:
				continue
			# no boulders inside the gorge at all — LOD-smoothed walls
			# leave them hovering over the water
			if z > -340.0 and z < 260.0:
				continue
			if _hf.slope(x, z) < 0.25 or _hf.slope(x, z) > 0.55:
				continue
			if _hash2(ix, iz, 720) < 0.5:
				continue
			var y: float = _hf.h(x, z)
			var yaw: float = _hash2(ix, iz, 730) * TAU
			var scl: float = 0.6 + _hash2(ix, iz, 740) * 1.2
			# sink deeper so LOD-smoothed canyon ledges can't levitate
			y -= 0.8 * scl
			_add("rock", Vector3(x, y, z), yaw, scl)
	# big boulders on the snow plateau
	cs = 200.0
	ix0 = int(floor(X0 / cs))
	ix1 = int(floor(X1 / cs))
	iz0 = int(floor(Z0 / cs))
	iz1 = int(floor(-400.0 / cs))
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			if _hash2(ix, iz, 800) < 0.22:
				continue
			var hx: float = _hash2(ix, iz, 810)
			var hz: float = _hash2(ix, iz, 820)
			var x: float = clampf((ix + hx) * cs, X0 + 4.0, X1 - 4.0)
			var z: float = clampf((iz + hz) * cs, Z0 + 4.0, Z1 - 4.0)
			if _hf.slope(x, z) > 0.35:
				continue
			var y: float = _hf.h(x, z)
			var yaw: float = _hash2(ix, iz, 830) * TAU
			var scl: float = 2.0 + _hash2(ix, iz, 840) * 2.5
			y -= 1.2 * scl   # half-buried boulders, not hover-stones
			_add("rock", Vector3(x, y, z), yaw, scl)


func _scatter_spores() -> void:
	var lake_c: Vector2 = _hf.lake["c"]
	var lake_r: float = _hf.lake["r"]
	var cs := 40.0
	var ix0 := int(floor(X0 / cs))
	var ix1 := int(floor(X1 / cs))
	var iz0 := int(floor(400.0 / cs))
	var iz1 := int(floor(Z1 / cs))
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			if _hash2(ix, iz, 900) < 0.30:
				continue
			var hx: float = _hash2(ix, iz, 910)
			var hz: float = _hash2(ix, iz, 920)
			var x: float = clampf((ix + hx) * cs, X0 + 4.0, X1 - 4.0)
			var z: float = clampf((iz + hz) * cs, Z0 + 4.0, Z1 - 4.0)
			if Vector2(x, z).distance_to(lake_c) < lake_r + 20.0:
				continue
			# spores live in the humid basin — not over the gorge/river
			if z < 500.0:
				continue
			var rd2: float = _hf.river_dist(Vector2(x, z)).x
			if rd2 < 18.0:
				continue
			var y: float = _hf.h(x, z)
			if y < _hf.water_y(x, z) + 1.0:
				continue
			var float_h: float = 1.5 + _hash2(ix, iz, 930) * 3.5
			var yaw: float = _hash2(ix, iz, 940) * TAU
			# firefly-sized glow points, not floating cubes
			var scl: float = 0.10 + _hash2(ix, iz, 950) * 0.18
			_add("spore", Vector3(x, y + float_h, z), yaw, scl)


# ------------------------------------------------------------- multimesh ---
func _build_multimeshes() -> void:
	var per_type: Dictionary = {}   # type -> Dictionary(Vector2i -> Array)
	for type in _types:
		var cellmap: Dictionary = {}
		var tr_arr: Array = _tr[type]
		var cl_arr: Array = _cl[type]
		for i in tr_arr.size():
			var cell: Vector2i = cl_arr[i]
			var arr: Array = cellmap.get_or_add(cell, [])
			arr.append(tr_arr[i])
		per_type[type] = cellmap
	for type in _types:
		var cellmap: Dictionary = per_type[type]
		var mesh: ArrayMesh = _meshes[_mesh_key[type]]
		var mat: ShaderMaterial = _materials[_mat_key[type]]
		for cell in cellmap:
			var arr: Array = cellmap[cell]
			var chunk: Node3D = _chunk(cell)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = false
			mm.mesh = mesh
			mm.instance_count = arr.size()
			for i in arr.size():
				var tf: Transform3D = arr[i]
				mm.set_instance_transform(i, tf)
			var mi := MultiMeshInstance3D.new()
			mi.name = "Veg_%s_%d_%d" % [type, cell.x, cell.y]
			mi.multimesh = mm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.set_meta("type", type)
			chunk.add_child(mi)


func _chunk(cell: Vector2i) -> Node3D:
	var n: Node3D = _chunks.get(cell)
	if n == null:
		n = Node3D.new()
		n.name = "chunk_%d_%d" % [cell.x, cell.y]
		add_child(n)
		_chunks[cell] = n
	return n


# ------------------------------------------------------------- materials ---
func _load_shader(path: String, params: Dictionary) -> ShaderMaterial:
	var sh := load(path) as Shader
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


func _build_materials() -> void:
	_materials["leaf"] = _load_shader("res://gfx/leaf.gdshader", {})
	_materials["rock"] = _load_shader("res://gfx/rock.gdshader", {})
	_materials["ice"] = _load_shader("res://gfx/rock.gdshader", {"ice": 1.0})
	_materials["spore"] = _load_shader("res://gfx/spore.gdshader", {})


# ------------------------------------------------------------- hash -------
## Deterministic 0..1 hash of two integer grid coords + a salt. Safe 64-bit.
func _hash2(ix: int, iz: int, s: int) -> float:
	var h: int = (ix * 73856093) ^ (iz * 19349663) ^ (s * 83492791)
	h = h & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7fffffff) / 2147483647.0


# ------------------------------------------------------------- mesh gen ----
func _finish(V: PackedVector3Array, N: PackedVector3Array, C: PackedColorArray) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = C
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Emit a flat-shaded triangle; auto-orients the winding so the normal points
## away from `ref` (works for any convex / star-shaped surface).
func _emit(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, ref: Vector3, V: PackedVector3Array, N: PackedVector3Array, C: PackedColorArray) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.0000001:
		return
	n = n.normalized()
	var cen := (a + b + c) / 3.0
	if n.dot(cen - ref) < 0.0:
		var tb := b
		b = c
		c = tb
		var tcol := cb
		cb = cc
		cc = tcol
		n = -n
	V.append(a)
	V.append(b)
	V.append(c)
	N.append(n)
	N.append(n)
	N.append(n)
	C.append(ca)
	C.append(cb)
	C.append(cc)


func _foliage(y: float, lo: float, hi: float) -> Color:
	# r=1 foliage, g unused, b = vertical tip factor (0 base → 1 crown)
	var tip := clampf((y - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)
	return Color(1.0, 0.5, tip, 1.0)


func _frustum(y0: float, y1: float, r0: float, r1: float, sides: int, col_lo: Color, col_hi: Color, V: PackedVector3Array, N: PackedVector3Array, C: PackedColorArray) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var b0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var t1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var ref := Vector3(0.0, (y0 + y1) * 0.5, 0.0)
		_emit(b0, t0, b1, col_lo, col_hi, col_lo, ref, V, N, C)
		_emit(b1, t0, t1, col_lo, col_hi, col_hi, ref, V, N, C)


## Frustum whose bottom/top centres are offset — a leaning trunk
## section. o0/o1 are the XZ centres at y0/y1.
func _frustum_off(y0: float, y1: float, r0: float, r1: float, sides: int,
		o0: Vector2, o1: Vector2, col: Color,
		V: PackedVector3Array, N: PackedVector3Array, C: PackedColorArray) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var b0 := Vector3(cos(a0) * r0 + o0.x, y0, sin(a0) * r0 + o0.y)
		var b1 := Vector3(cos(a1) * r0 + o0.x, y0, sin(a1) * r0 + o0.y)
		var t0 := Vector3(cos(a0) * r1 + o1.x, y1, sin(a0) * r1 + o1.y)
		var t1 := Vector3(cos(a1) * r1 + o1.x, y1, sin(a1) * r1 + o1.y)
		var ref := Vector3((o0.x + o1.x) * 0.5, (y0 + y1) * 0.5, (o0.y + o1.y) * 0.5)
		_emit(b0, t0, b1, col, col, col, ref, V, N, C)
		_emit(b1, t0, t1, col, col, col, ref, V, N, C)


## Scatter `n` small lobes inside an ellipsoid volume — each lobe is a
## ~0.7–1.3 m tuft so the crown reads as clustered foliage, not a shell.
func _crown_cluster(center: Vector3, rx: float, ry: float, rz: float,
		n: int, tip_hi: float, seed: float,
		V: PackedVector3Array, N: PackedVector3Array, C: PackedColorArray) -> void:
	for i in n:
		var h := _hash2(int(seed) + i * 7, i * 13, 17)
		var u := _hash2(int(seed), i * 11, 23) * TAU
		var v := (_hash2(int(seed), i * 5, 29) - 0.5) * PI
		var rad := pow(_hash2(int(seed), i * 3, 37), 0.33)   # fill volume
		var px := cos(v) * cos(u) * rx * rad
		var py := sin(v) * ry * rad
		var pz := cos(v) * sin(u) * rz * rad
		var c2 := center + Vector3(px, py, pz)
		var lr := 0.7 + h * 0.7          # lobe radius 0.7–1.4 m
		_ellipsoid(c2, lr, lr * (0.55 + h * 0.3), lr, 4, 6,
			maxf(0.0, tip_hi - 3.0), tip_hi, 0.35, seed + i * 1.31, V, N, C)


func _ep(center: Vector3, rx: float, ry: float, rz: float, t: float, p: float, displace: float, seed: float) -> Vector3:
	var d := Vector3(cos(p) * cos(t), sin(p), cos(p) * sin(t))
	var base := center + Vector3(d.x * rx, d.y * ry, d.z * rz)
	if displace > 0.0:
		# two octaves: broad dent + fine shatter so the canopy surface
		# breaks into tufts, not smooth dents
		var n := _rng_noise.get_noise_3d(base.x * 0.7 + seed, base.y * 0.7, base.z * 0.7)
		var n2 := _rng_noise.get_noise_3d(base.x * 1.9 + seed * 1.7, base.y * 1.9, base.z * 1.9)
		base += (base - center).normalized() * (n * 0.7 + n2 * 0.5) * displace
	return base


func _ellipsoid(center: Vector3, rx: float, ry: float, rz: float, rings: int, segs: int, tip_lo: float, tip_hi: float, displace: float, seed: float, V: PackedVector3Array, N: PackedVector3Array, C: PackedColorArray) -> void:
	for iy in rings:
		var p0 := -PI * 0.5 + PI * iy / rings
		var p1 := -PI * 0.5 + PI * (iy + 1) / rings
		for ix in segs:
			var t0 := TAU * ix / segs
			var t1 := TAU * (ix + 1) / segs
			var p00 := _ep(center, rx, ry, rz, t0, p0, displace, seed)
			var p10 := _ep(center, rx, ry, rz, t1, p0, displace, seed)
			var p01 := _ep(center, rx, ry, rz, t0, p1, displace, seed)
			var p11 := _ep(center, rx, ry, rz, t1, p1, displace, seed)
			var c00 := _foliage(p00.y, tip_lo, tip_hi)
			var c10 := _foliage(p10.y, tip_lo, tip_hi)
			var c01 := _foliage(p01.y, tip_lo, tip_hi)
			var c11 := _foliage(p11.y, tip_lo, tip_hi)
			_emit(p00, p01, p10, c00, c01, c10, center, V, N, C)
			_emit(p10, p01, p11, c10, c01, c11, center, V, N, C)


func _build_meshes() -> void:
	_meshes["jungle_tree"] = _make_jungle_tree()
	_meshes["conifer"] = _make_conifer()
	_meshes["broadleaf"] = _make_broadleaf()
	_meshes["bush"] = _make_bush()
	_meshes["rock"] = _make_rock()
	_meshes["ice"] = _make_ice()
	_meshes["spore"] = _make_spore()


func _make_jungle_tree() -> ArrayMesh:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var bark := Color(0.0, 0.5, 0.0, 1.0)
	var th := 22.0
	# flared buttress trunk that leans and kinks: stacked off-axis
	# frusta read as a living trunk, not a column
	_frustum_off(0.0, 8.0, 1.6, 0.9, 6, Vector2(0.0, 0.0), Vector2(0.35, 0.15), bark, V, N, C)
	_frustum_off(8.0, 14.5, 0.9, 0.5, 6, Vector2(0.35, 0.15), Vector2(0.9, 0.4), bark, V, N, C)
	# second leader, thinner, split earlier
	_frustum_off(5.5, 12.5, 0.55, 0.28, 5, Vector2(-0.3, 0.4), Vector2(-1.1, 0.8), bark, V, N, C)
	# buttress root bumps
	for i in 5:
		var ang := TAU * i / 5.0 + 0.3
		var bx := cos(ang) * 1.35
		var bz := sin(ang) * 1.35
		_ellipsoid(Vector3(bx, 0.45, bz), 1.1, 0.9, 0.45, 3, 6, 0.0, 2.0, 0.3, 11.0 + i, V, N, C)
	# emergent rainforest crown: broad flattened dome + smaller pads on
	# branch tips — heavy noise displacement breaks the shell silhouette
	# into a ragged cluster of crowns, not stacked balloons
	# many small clumps (~1–1.5 m facets) over a crown volume — the
	# silhouette shatters into foliage tufts instead of a shell
	_crown_cluster(Vector3(0.0, 15.0, 0.0), 6.4, 2.4, 5.8, 26, th, 21.0, V, N, C)
	_crown_cluster(Vector3(-4.0, 16.8, 2.2), 4.0, 1.7, 3.4, 16, th, 31.0, V, N, C)
	_crown_cluster(Vector3(4.2, 17.2, -1.6), 4.2, 1.9, 3.6, 16, th, 41.0, V, N, C)
	_crown_cluster(Vector3(-1.6, 19.4, -3.0), 3.2, 1.5, 2.8, 12, th, 51.0, V, N, C)
	_crown_cluster(Vector3(2.0, 20.2, 2.6), 2.8, 1.3, 2.6, 12, th, 61.0, V, N, C)
	# drooping under-crown pads
	_crown_cluster(Vector3(-2.4, 13.4, -0.8), 1.9, 1.1, 1.7, 8, th, 71.0, V, N, C)
	_crown_cluster(Vector3(2.6, 13.6, 1.4), 1.7, 1.0, 1.5, 8, th, 81.0, V, N, C)
	return _finish(V, N, C)


func _make_conifer() -> ArrayMesh:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var bark := Color(0.0, 0.5, 0.0, 1.0)
	var th := 14.4
	_frustum(0.0, 2.2, 0.35, 0.16, 8, bark, bark, V, N, C)
	_frustum(1.2, 6.0, 2.6, 0.5, 8, _foliage(1.2, 0.0, th), _foliage(6.0, 0.0, th), V, N, C)
	_frustum(4.8, 9.4, 2.0, 0.4, 8, _foliage(4.8, 0.0, th), _foliage(9.4, 0.0, th), V, N, C)
	_frustum(8.2, 12.4, 1.45, 0.3, 8, _foliage(8.2, 0.0, th), _foliage(12.4, 0.0, th), V, N, C)
	_frustum(11.0, 14.4, 0.9, 0.05, 8, _foliage(11.0, 0.0, th), _foliage(14.4, 0.0, th), V, N, C)
	return _finish(V, N, C)


func _make_broadleaf() -> ArrayMesh:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var bark := Color(0.0, 0.5, 0.0, 1.0)
	_frustum(0.0, 4.0, 0.32, 0.2, 6, bark, bark, V, N, C)
	_ellipsoid(Vector3(0.0, 5.4, 0.0), 2.8, 2.6, 2.8, 6, 8, 3.5, 8.0, 0.5, 51.0, V, N, C)
	_ellipsoid(Vector3(1.8, 4.8, 0.8), 2.0, 1.8, 2.0, 5, 7, 3.5, 8.0, 0.4, 61.0, V, N, C)
	_ellipsoid(Vector3(-1.4, 4.6, -0.6), 1.7, 1.6, 1.7, 5, 7, 3.5, 8.0, 0.35, 71.0, V, N, C)
	return _finish(V, N, C)


func _make_bush() -> ArrayMesh:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	# tangled shrub: five small lobes + a bare twig frustum so the
	# silhouette reads as undergrowth, not a green ball
	_ellipsoid(Vector3(0.0, 0.7, 0.0), 1.0, 0.6, 0.9, 5, 7, 0.0, 1.4, 0.55, 71.0, V, N, C)
	_ellipsoid(Vector3(0.8, 0.5, 0.4), 0.65, 0.45, 0.6, 5, 7, 0.0, 1.4, 0.45, 81.0, V, N, C)
	_ellipsoid(Vector3(-0.65, 0.55, -0.45), 0.6, 0.45, 0.6, 5, 7, 0.0, 1.4, 0.45, 91.0, V, N, C)
	_ellipsoid(Vector3(0.2, 0.9, -0.6), 0.55, 0.4, 0.5, 4, 6, 0.0, 1.4, 0.4, 101.0, V, N, C)
	_ellipsoid(Vector3(-0.3, 0.35, 0.7), 0.5, 0.35, 0.45, 4, 6, 0.0, 1.4, 0.35, 111.0, V, N, C)
	# short twig trunk poking through
	var bark := Color(0.0, 0.5, 0.0, 1.0)
	_frustum(0.0, 0.5, 0.06, 0.03, 4, bark, bark, V, N, C)
	return _finish(V, N, C)


func _make_rock() -> ArrayMesh:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0).normalized(), Vector3(1, t, 0).normalized(),
		Vector3(-1, -t, 0).normalized(), Vector3(1, -t, 0).normalized(),
		Vector3(0, -1, t).normalized(), Vector3(0, 1, t).normalized(),
		Vector3(0, -1, -t).normalized(), Vector3(0, 1, -t).normalized(),
		Vector3(t, 0, -1).normalized(), Vector3(t, 0, 1).normalized(),
		Vector3(-t, 0, -1).normalized(), Vector3(-t, 0, 1).normalized(),
	]
	var faces: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	var sub := 2
	var cache := {}
	for si in sub:
		var newf: Array = []
		for f in faces:
			var a: int = f[0]
			var b: int = f[1]
			var c: int = f[2]
			var ab := _mid(a, b, verts, cache)
			var bc := _mid(b, c, verts, cache)
			var ca := _mid(c, a, verts, cache)
			newf.append([a, ab, ca])
			newf.append([b, bc, ab])
			newf.append([c, ca, bc])
			newf.append([ab, bc, ca])
		faces = newf
	for f in faces:
		var a: int = f[0]
		var b: int = f[1]
		var c: int = f[2]
		var pa := _rock_vert(verts[a])
		var pb := _rock_vert(verts[b])
		var pc := _rock_vert(verts[c])
		var col := Color(0.5, 0.5, 0.5, 1.0)
		_emit(pa, pb, pc, col, col, col, Vector3.ZERO, V, N, C)
	return _finish(V, N, C)


func _mid(i: int, j: int, verts: Array[Vector3], cache: Dictionary) -> int:
	var key := mini(i, j) * 100000 + maxi(i, j)
	if cache.has(key):
		return cache[key]
	var v: Vector3 = ((verts[i] + verts[j]) * 0.5).normalized()
	verts.append(v)
	var idx := verts.size() - 1
	cache[key] = idx
	return idx


func _rock_vert(v: Vector3) -> Vector3:
	var n := _rng_noise.get_noise_3d(v.x * 1.8 + 10.0, v.y * 1.8, v.z * 1.8)
	var r := 1.0 + n * 0.35
	return v * r


func _make_ice() -> ArrayMesh:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var col := Color(0.5, 0.5, 0.5, 1.0)
	_ice_shard(0.0, 0.0, 0.0, 2.4, 0.55, 0.04, 0.1, 0.0, col, V, N, C)
	_ice_shard(0.5, 0.3, 0.0, 1.5, 0.4, 0.04, 0.2, -0.2, col, V, N, C)
	_ice_shard(-0.5, 0.25, 0.0, 1.8, 0.42, 0.04, -0.15, 0.1, col, V, N, C)
	_ice_shard(0.0, -0.5, 0.0, 1.0, 0.35, 0.04, 0.0, -0.25, col, V, N, C)
	return _finish(V, N, C)


func _ice_shard(cx: float, cz: float, y0: float, y1: float, r0: float, r1: float, tx: float, tz: float, col: Color, V: PackedVector3Array, N: PackedVector3Array, C: PackedColorArray) -> void:
	var sides := 5
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var b0 := Vector3(cx + cos(a0) * r0, y0, cz + sin(a0) * r0)
		var b1 := Vector3(cx + cos(a1) * r0, y0, cz + sin(a1) * r0)
		var t0 := Vector3(tx + cos(a0) * r1, y1, tz + sin(a0) * r1)
		var t1 := Vector3(tx + cos(a1) * r1, y1, tz + sin(a1) * r1)
		var ref := Vector3((cx + tx) * 0.5, (y0 + y1) * 0.5, (cz + tz) * 0.5)
		_emit(b0, t0, b1, col, col, col, ref, V, N, C)
		_emit(b1, t0, t1, col, col, col, ref, V, N, C)


func _make_spore() -> ArrayMesh:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	_ellipsoid(Vector3.ZERO, 0.12, 0.12, 0.12, 6, 8, 0.0, 0.1, 0.0, 0.0, V, N, C)
	return _finish(V, N, C)
