class_name RockFace
extends RefCounted

## Loads the offline-baked cliff face mesh (tools/gen_rockface.py).
## Binary layout: "RFM2", int32 nverts, int32 nindices, int32 gridw, int32 gridh,
##   float32[nv*3] positions, float32[nv*3] normals,
##   float32[nv*4] colour+roughness, uint32[ni] indices.

static func load_mesh(path: String) -> ArrayMesh:
	if not FileAccess.file_exists(path):
		push_error("RockFace: missing baked mesh " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var magic := f.get_buffer(4).get_string_from_ascii()
	if magic != "RFM2":
		push_error("RockFace: bad header in " + path)
		return null
	var nv := f.get_32()
	var ni := f.get_32()
	var gnx := f.get_32()
	var gny := f.get_32()
	var pos := f.get_buffer(nv * 12).to_float32_array()
	var nrm := f.get_buffer(nv * 12).to_float32_array()
	var colf := f.get_buffer(nv * 16).to_float32_array()
	var idx := f.get_buffer(ni * 4).to_int32_array()
	f.close()

	var verts := PackedVector3Array()
	verts.resize(nv)
	var norms := PackedVector3Array()
	norms.resize(nv)
	var cols := PackedColorArray()
	cols.resize(nv)
	for i in nv:
		verts[i] = Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])
		norms[i] = Vector3(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2])
		cols[i] = Color(colf[i * 4], colf[i * 4 + 1], colf[i * 4 + 2], colf[i * 4 + 3])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh