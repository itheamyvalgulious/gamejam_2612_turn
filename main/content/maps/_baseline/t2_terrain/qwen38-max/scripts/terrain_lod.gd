class_name TerrainLOD
extends Node3D
## Chunked level-of-detail terrain mesher. Builds each 250 m chunk at one of four
## resolutions chosen by camera distance, with downward skirts to hide LOD seams.
## Vertex COLOR carries the 4-way biome splat (grass, rock, snow, sand).

const TerrainGen := preload("res://scripts/terrain_gen.gd")

const CHUNK := 250.0
const CX := int(TerrainGen.WORLD_X / CHUNK)   # 16
const CZ := int(TerrainGen.WORLD_Z / CHUNK)   # 10
const CELLS_PER_CHUNK := int(CHUNK / TerrainGen.CELL)  # 50
const LOD_STEPS := [1, 2, 5, 10]              # cells per vertex at LOD 0..3
const LOD_DIST := [420.0, 900.0, 1800.0, 3600.0]
const SKIRT := 12.0

var data: TerrainGen
var _chunks: Array = []          # MeshInstance3D grid CX*CZ
var _lod := PackedInt32Array()   # current lod per chunk
var material: ShaderMaterial

func setup(d: TerrainGen, mat: ShaderMaterial) -> void:
	data = d
	material = mat
	_lod.resize(CX * CZ)
	_lod.fill(-1)
	for cz in range(CZ):
		for cx in range(CX):
			var mi := MeshInstance3D.new()
			mi.name = "chunk_%d_%d" % [cx, cz]
			add_child(mi)
			_chunks.push_back(mi)

func chunk_center(cx: int, cz: int) -> Vector3:
	return Vector3((cx + 0.5) * CHUNK, 0.0, (cz + 0.5) * CHUNK)

## Rebuild any chunk whose LOD changed for the given camera position.
func update(cam_pos: Vector3, force := false) -> void:
	for cz in range(CZ):
		for cx in range(CX):
			var i := cz * CX + cx
			var c := chunk_center(cx, cz)
			var dist := Vector2(cam_pos.x - c.x, cam_pos.z - c.z).length()
			var lod := 3
			if dist < LOD_DIST[0]:
				lod = 0
			elif dist < LOD_DIST[1]:
				lod = 1
			elif dist < LOD_DIST[2]:
				lod = 2
			if force or _lod[i] != lod:
				_chunks[i].mesh = _build_chunk(cx, cz, lod)
				_lod[i] = lod

func _build_chunk(cx: int, cz: int, lod: int) -> ArrayMesh:
	var step: int = LOD_STEPS[lod]
	var n := CELLS_PER_CHUNK / step            # quads per side
	var vcount := n + 1
	var ox := cx * CHUNK
	var oz := cz * CHUNK

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(vcount * vcount)
	norms.resize(vcount * vcount)
	cols.resize(vcount * vcount)

	for j in range(vcount):
		for i in range(vcount):
			var wx := ox + i * step * TerrainGen.CELL
			var wz := oz + j * step * TerrainGen.CELL
			var gi := clampi(int(roundf(wx / TerrainGen.CELL)), 0, TerrainGen.NX)
			var gj := clampi(int(roundf(wz / TerrainGen.CELL)), 0, TerrainGen.NZ)
			var idx := gj * TerrainGen.VX + gi
			var h := data.height[idx]
			var k := j * vcount + i
			verts[k] = Vector3(wx, h, wz)
			norms[k] = _normal_idx(gi, gj)
			cols[k] = Color(data.splat[idx * 4], data.splat[idx * 4 + 1], data.splat[idx * 4 + 2], data.splat[idx * 4 + 3])

	var idxs := PackedInt32Array()
	idxs.resize(n * n * 6)
	var p := 0
	for j in range(n):
		for i in range(n):
			var a := j * vcount + i
			var b := a + 1
			var c := a + vcount
			var d := c + 1
			idxs[p] = a; idxs[p + 1] = b; idxs[p + 2] = c
			idxs[p + 3] = b; idxs[p + 4] = d; idxs[p + 5] = c
			p += 6

	_add_skirt(verts, norms, cols, idxs, vcount, n)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

## Append a closed downward skirt loop around the chunk boundary to hide T-junctions.
func _add_skirt(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, idxs: PackedInt32Array, vcount: int, nn: int) -> void:
	var border: Array = []
	for i in range(vcount):
		border.push_back(i)                       # j=0
	for j in range(1, vcount):
		border.push_back(j * vcount + nn)         # i=n
	for i in range(nn - 1, -1, -1):
		border.push_back(nn * vcount + i)         # j=n
	for j in range(vcount - 1, 0, -1):
		border.push_back(j * vcount)              # i=0
	var m := border.size()
	var base := v.size()
	v.resize(base + m * 2)
	nrm.resize(base + m * 2)
	col.resize(base + m * 2)
	for k in range(m):
		var src: int = border[k]
		var pos: Vector3 = v[src]
		var c: Color = col[src]
		v[base + k * 2] = pos
		nrm[base + k * 2] = nrm[src]
		col[base + k * 2] = c
		v[base + k * 2 + 1] = Vector3(pos.x, pos.y - SKIRT, pos.z)
		nrm[base + k * 2 + 1] = Vector3(0, -1, 0)
		col[base + k * 2 + 1] = c
	var old := idxs.size()
	idxs.resize(old + m * 6)
	var p := old
	for k in range(m):
		var t0 := base + k * 2
		var t1 := base + ((k + 1) % m) * 2
		idxs[p] = t0; idxs[p + 1] = t1; idxs[p + 2] = t0 + 1
		idxs[p + 3] = t0 + 1; idxs[p + 4] = t1; idxs[p + 5] = t1 + 1
		p += 6

func _normal_idx(gi: int, gj: int) -> Vector3:
	var here := gj * TerrainGen.VX + gi
	var xl := data.height[here - 1] if gi > 0 else data.height[here]
	var xr := data.height[here + 1] if gi < TerrainGen.NX else data.height[here]
	var zd := data.height[here - TerrainGen.VX] if gj > 0 else data.height[here]
	var zu := data.height[here + TerrainGen.VX] if gj < TerrainGen.NZ else data.height[here]
	var cell := TerrainGen.CELL
	return Vector3(xl - xr, 2.0 * cell, zd - zu).normalized()
