class_name TerrainChunks
extends Node3D
## terrain.gd — chunked heightfield with skirted LOD tiles.
## Each chunk: SIZE m × SIZE m, generated at one of four vertex steps.
## Vertex color packs splat weights (snow/rock/jungle/sand) for the shader.

const SIZE := 256.0            # chunk edge in metres
const STEPS := [4.0, 8.0, 16.0, 32.0]
const RADIUS := [3, 6, 12, 24] # rings per LOD

var hf: HeightField
var mat: ShaderMaterial
var chunks := {}               # Vector2i -> MeshInstance3D
var _queue := []               # pending (cell, lod)
var _want := {}                # last computed lod map for seam snapping
var _last_cell := Vector2i(1 << 20, 1 << 20)
var no_skirt := false          # debug flag set by main
var force_lod := -1            # debug: >=0 pins every chunk to this lod
var force_ring := -1           # debug: >=0 only builds cells within N rings


func setup(h: HeightField, m: ShaderMaterial) -> void:
	hf = h
	mat = m


func update(cam: Vector3) -> void:
	var cell := Vector2i(int(floor(cam.x / SIZE)), int(floor(cam.z / SIZE)))
	if cell == _last_cell:
		return
	_last_cell = cell
	# desired lod per cell — clamp to world bounds + 1 chunk margin
	var want := {}
	var c0 := Vector2i(int(floor(hf.X0 / SIZE)) - 1, int(floor(hf.Z0 / SIZE)) - 1)
	var c1 := Vector2i(int(floor(hf.X1 / SIZE)) + 1, int(floor(hf.Z1 / SIZE)) + 1)
	for r in range(RADIUS[3], -1, -1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var c := cell + Vector2i(dx, dz)
				if c.x < c0.x or c.y < c0.y or c.x > c1.x or c.y > c1.y:
					continue
				var lod := 0
				var d := maxi(absi(dx), absi(dz))
				if d <= RADIUS[0]: lod = 0
				elif d <= RADIUS[1]: lod = 1
				elif d <= RADIUS[2]: lod = 2
				else: lod = 3
				if force_lod >= 0:
					lod = force_lod
				if force_ring >= 0 and d > force_ring:
					continue
				if not want.has(c):
					want[c] = lod
	# drop chunks no longer wanted
	for c in chunks.keys():
		if not want.has(c):
			chunks[c].queue_free()
			chunks.erase(c)
	# queue missing / wrong-lod chunks
	for c in want.keys():
		if chunks.has(c) and chunks[c].get_meta("lod") == want[c]:
			continue
		if chunks.has(c):
			chunks[c].queue_free()
			chunks.erase(c)
		_queue.append([c, want[c]])
	_queue.sort_custom(func(a, b):
		return a[0].distance_squared_to(cell) < b[0].distance_squared_to(cell))
	_want = want
	print("TERR cell=", cell, " want=", want.size(), " queue=", _queue.size())


## Build up to `n` pending chunks per call (frame budget).
func build_some(n := 2) -> void:
	for i in mini(n, _queue.size()):
		var job: Array = _queue.pop_front()
		chunks[job[0]] = _make_chunk(job[0], job[1])


func _make_chunk(cell: Vector2i, lod: int) -> MeshInstance3D:
	var step: float = STEPS[lod]
	# NOTE: a per-chunk margin overlap was tried — it puts two co-planar
	# surfaces over every border and z-fights into a bright grid lattice
	# at distance. Exact grid coverage + T-snap + skirt only.
	var nv := int(SIZE / step) + 1
	var ox: float = cell.x * SIZE
	var oz: float = cell.y * SIZE
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(nv * nv)
	norms.resize(nv * nv)
	cols.resize(nv * nv)
	uvs.resize(nv * nv)
	# Fixed 4 m normal probe: step-based probing made far-LOD ground read
	# as cliffs (32 m differences amplify to huge slopes), so the whole
	# basin rendered as brown crag instead of jungle.
	var e := 4.0
	for iz in nv:
		for ix in nv:
			var x: float = ox + ix * step
			var z: float = oz + iz * step
			var y: float = hf.h(x, z)
			var i := iz * nv + ix
			verts[i] = Vector3(x, y, z)
			var sx: float = (hf.h(x + e, z) - hf.h(x - e, z)) / (2.0 * e)
			var sz: float = (hf.h(x, z + e) - hf.h(x, z - e)) / (2.0 * e)
			norms[i] = Vector3(-sx, 1.0, -sz).normalized()
			var sp: float = sqrt(sx * sx + sz * sz)
			var spl: Color = hf.splat(x, z, y, sp)
			cols[i] = spl
			uvs[i] = Vector2(x, z)
	# T-junction fix: snap each border vertex onto the coarse neighbour's
	# chord so adjacent LODs share the same edge height — no skirt cracks.
	var dirs := [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for d_i in 4:
		var nlod: int = _want.get(cell + dirs[d_i], lod)
		if nlod <= lod:
			continue
		var step_n: float = STEPS[nlod]
		for i in nv:
			var vi: int
			var edge_t: float
			match d_i:
				0: vi = i;                     edge_t = i * step          # top row, vary x
				1: vi = i * nv + nv - 1;       edge_t = i * step          # right col, vary z
				2: vi = (nv - 1) * nv + i;     edge_t = i * step          # bottom row
				_: vi = i * nv;                edge_t = i * step          # left col
			var pos: float = (ox if (d_i == 0 or d_i == 2) else oz) + edge_t
			var p0: float = floor(pos / step_n) * step_n
			var f2: float = (pos - p0) / step_n
			if f2 < 0.001:
				continue
			# endpoint heights along the outer edge line (with margin the
			# right/bottom edges sit at ox/oz + (nv-1)*step, not +SIZE)
			var edge_len: float = (nv - 1) * step
			var ep0: Vector2
			var ep1: Vector2
			if d_i == 0:
				ep0 = Vector2(p0, oz);             ep1 = Vector2(p0 + step_n, oz)
			elif d_i == 1:
				ep0 = Vector2(ox + edge_len, p0);  ep1 = Vector2(ox + edge_len, p0 + step_n)
			elif d_i == 2:
				ep0 = Vector2(p0, oz + edge_len);  ep1 = Vector2(p0 + step_n, oz + edge_len)
			else:
				ep0 = Vector2(ox, p0);             ep1 = Vector2(ox, p0 + step_n)
			var h0: float = hf.h(ep0.x, ep0.y)
			var h1: float = hf.h(ep1.x, ep1.y)
			verts[vi].y = h0 + (h1 - h0) * f2

	var k := 0
	idx.resize((nv - 1) * (nv - 1) * 6)
	for iz in range(nv - 1):
		for ix in nv - 1:
			var a := iz * nv + ix
			var b := a + 1
			var c := a + nv
			var d := c + 1
			# Godot front faces are CLOCKWISE — (a,b,c) winds CW viewed
			# from above; (a,c,b) culls the whole surface seen from the sky
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = c
			idx[k + 3] = b; idx[k + 4] = d; idx[k + 5] = c
			k += 6
	# No skirt: border verts are T-snapped to the coarse neighbour's chord,
	# so shared edges match to the metre — a skirt only ever painted a
	# bright wall lattice over every 256 m border line.
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	# splat weights duplicated into CUSTOM0 (RGBA_FLOAT → vec4 in shader):
	# COLOR is dropped by this driver on material_override + ArrayMesh.
	var cus := PackedFloat32Array()
	cus.resize(nv * nv * 4)
	for i in nv * nv:
		cus[i * 4] = cols[i].r
		cus[i * 4 + 1] = cols[i].g
		cus[i * 4 + 2] = cols[i].b
		cus[i * 4 + 3] = cols[i].a
	arr[Mesh.ARRAY_CUSTOM0] = cus
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	var fmt := Mesh.ARRAY_FORMAT_CUSTOM0 | \
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.set_meta("lod", lod)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi
