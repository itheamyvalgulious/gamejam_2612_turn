class_name HeroTree
extends Node3D

## Close-up tree: a recursively branched wooden skeleton plus thousands of
## solid, curved, folded leaves with real thickness.  Used for the 1–3 m
## close-up views; the wide forest keeps its cheaper LOD.

var rng := RandomNumberGenerator.new()
var bark_mat: Material
var leaf_mat: Material
var bverts := PackedVector3Array()
var bnorms := PackedVector3Array()
var buvs := PackedVector2Array()
var bcols := PackedColorArray()
var bidx := PackedInt32Array()
var lverts := PackedVector3Array()
var lnorms := PackedVector3Array()
var luvs := PackedVector2Array()
var lcols := PackedColorArray()
var lidx := PackedInt32Array()
var leaf_count := 0

func build(pos: Vector3, height: float, bm: Material, lm: Material, seed: int, lean: Vector3 = Vector3.ZERO) -> void:
	bark_mat = bm
	leaf_mat = lm
	rng.seed = seed
	# buttress roots
	for i in 5:
		var a := TAU * float(i) / 5.0 + rng.randf_range(-0.15, 0.15)
		var r0 := height * 0.030
		var path := PackedVector3Array([
			Vector3(cos(a) * height * 0.060, 0.0, sin(a) * height * 0.060),
			Vector3(cos(a) * height * 0.030, height * 0.012, sin(a) * height * 0.030),
			Vector3(cos(a) * height * 0.010, height * 0.045, sin(a) * height * 0.010),
		])
		var radii := PackedFloat32Array([r0 * 0.55, r0 * 0.85, height * 0.026])
		_tube(path, radii, 6, 0.10)
	# trunk
	var trunk_top := Vector3(lean.x * height * 0.4, height * 0.64, lean.z * height * 0.4)
	var trunk := PackedVector3Array([
		Vector3.ZERO,
		Vector3(lean.x * height * 0.10, height * 0.20, lean.z * height * 0.10),
		Vector3(lean.x * height * 0.02, height * 0.40, lean.z * height * 0.02),
		trunk_top,
	])
	_tube(trunk, PackedFloat32Array([height * 0.050, height * 0.038, height * 0.030, height * 0.022]), 12, 0.08)
	# main branches
	var nb := 5
	for i in nb:
		var t := 0.48 + 0.32 * float(i) / float(nb - 1)
		var origin := Vector3(lean.x * height * 0.05 * t, height * t, lean.z * height * 0.05 * t)
		var a := TAU * (float(i) * 0.618) + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var dir := (out * 0.70 + Vector3(0, 0.72, 0) + lean * 0.3).normalized()
		_branch(origin, dir, height * rng.randf_range(0.28, 0.36), height * 0.019, 1, height)
	# low branch, for close-up foliage
	_branch(Vector3(lean.x * height * 0.05, height * 0.26, lean.z * height * 0.05), (Vector3(0.8, 0.35, 0.5)).normalized(), height * 0.22, height * 0.011, 2, height)
	# top continuation
	_branch(trunk_top, Vector3(lean.x * 0.4, 1.0, lean.z * 0.4).normalized(), height * 0.16, height * 0.020, 1, height)
	_make_meshes(pos)
	print("[hero-tree] ", leaf_count, " solid leaves, ", bverts.size() / 3, " bark tris")

func _branch(base: Vector3, dir: Vector3, length: float, radius: float, depth: int, tree_h: float) -> void:
	var d := dir.normalized()
	var side := d.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	side = side.normalized()
	var up2 := side.cross(d).normalized()
	var curve := (side * rng.randf_range(-0.25, 0.25) + up2 * rng.randf_range(-0.1, 0.35)) * length
	var p0 := base
	var p1 := base + d * length * 0.35 + curve * 0.25
	var p2 := base + d * length * 0.70 + curve * 0.55
	var p3 := base + d * length + curve
	var path := PackedVector3Array([p0, p1, p2, p3])
	var radii := PackedFloat32Array([radius, radius * 0.78, radius * 0.52, radius * 0.24])
	_tube(path, radii, 9 if depth == 1 else 6, 0.12)
	# side twigs
	var nchild := 2 if depth < 3 else 1
	for c in nchild:
		var a := TAU * rng.randf() + float(c) * 1.7
		var nn := (side * cos(a) + up2 * sin(a)).normalized()
		var nd := (d * 0.62 + nn * 0.55 + up2 * 0.22).normalized()
		var nl := length * rng.randf_range(0.45, 0.62)
		if depth < 3:
			_branch(p2 + nn * length * 0.08, nd, nl, radius * 0.45, depth + 1, tree_h)
	# foliage clusters at the tip + one along the branch
	_cluster(p3 + up2 * length * 0.06, length * rng.randf_range(0.45, 0.65), 95, up2)
	if depth >= 2:
		_cluster(p2 + d * length * 0.10, length * rng.randf_range(0.38, 0.56), 70, up2)
	# twig to the tip cluster
	_tube(PackedVector3Array([p2, p3]), PackedFloat32Array([radius * 0.22, radius * 0.06]), 4, 0.2)

func _cluster(center: Vector3, radius: float, count: int, up_hint: Vector3) -> void:
	for i in count:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.55, 1), rng.randf_range(-1, 1))
		if v.length() < 0.001:
			v = Vector3.UP
		v = v.normalized() * radius * pow(rng.randf(), 0.45)
		var pos := center + v
		var outward := v.normalized()
		var upv := up_hint
		if abs(outward.dot(upv)) > 0.92:
			upv = Vector3.RIGHT
		var right := outward.cross(upv).normalized()
		var up2 := right.cross(outward).normalized()
		var ang := rng.randf_range(0.0, TAU)
		var yax := (up2 * cos(ang) + right * sin(ang)).normalized()
		var zax := (outward * rng.randf_range(0.7, 1.0) + yax * rng.randf_range(-0.2, 0.2)).normalized()
		var xax := yax.cross(zax).normalized()
		yax = zax.cross(xax).normalized()
		var size := radius * rng.randf_range(0.28, 0.46)
		var hue := rng.randf()
		var ao := clampf(0.45 + 0.55 * (v.length() / maxf(radius, 0.001)), 0.35, 1.0)
		_leaf(pos, xax, yax, zax, size, hue, ao)
		leaf_count += 1

func _leaf(base: Vector3, xax: Vector3, yax: Vector3, zax: Vector3, size: float, hue: float, ao: float) -> void:
	var w := size * 0.78
	var l := size * 1.15
	var th := size * 0.016
	var outline := []
	for p in [
		Vector3(0, 0, 0),
		Vector3(-w * 0.34, l * 0.20, 0.0),
		Vector3(-w * 0.50, l * 0.44, 0.0),
		Vector3(-w * 0.38, l * 0.70, 0.0),
		Vector3(0, l, 0.0),
		Vector3(w * 0.38, l * 0.70, 0.0),
		Vector3(w * 0.50, l * 0.44, 0.0),
		Vector3(w * 0.34, l * 0.20, 0.0),
	]:
		var xr: float = abs(p.x) / maxf(w * 0.5, 0.001)
		var zz: float = -0.028 * size * xr * xr + 0.045 * size * (p.y / maxf(l, 0.001)) * (1.0 - xr * 0.4)
		outline.append(Vector3(p.x, p.y, zz))
	var n := outline.size()
	var mid := Vector3(0, l * 0.50, th * 1.6 + 0.035 * size)
	var ouv: Array = []
	for p in outline:
		ouv.append(Vector2(0.5 + p.x / maxf(w, 0.001) * 0.5, p.y / maxf(l, 0.001)))
	var uvm := Vector2(0.5, 0.5)
	var front: Array = []
	var back: Array = []
	for p in outline:
		front.append(base + xax * p.x + yax * p.y + zax * th)
		back.append(base + xax * p.x + yax * p.y - zax * th)
	front.append(base + xax * mid.x + yax * mid.y + zax * th)
	back.append(base + xax * mid.x + yax * mid.y - zax * th)
	var mf := n
	for i in n:
		var j := (i + 1) % n
		var p0: Vector3 = front[i]
		var p1: Vector3 = front[j]
		var p2: Vector3 = front[mf]
		var nn := (p1 - p0).cross(p2 - p0).normalized()
		if nn.dot(zax) < 0.0:
			nn = -nn
		var b := lverts.size()
		lverts.append(p0); lverts.append(p1); lverts.append(p2)
		lnorms.append(nn); lnorms.append(nn); lnorms.append(nn)
		luvs.append(ouv[i]); luvs.append(ouv[j]); luvs.append(uvm)
		for k in 3:
			lcols.append(Color(hue, ao, 0.0, 1.0))
		lidx.append(b); lidx.append(b + 1); lidx.append(b + 2)
	for i in n:
		var j := (i + 1) % n
		var p0: Vector3 = back[j]
		var p1: Vector3 = back[i]
		var p2: Vector3 = back[mf]
		var nn := (p1 - p0).cross(p2 - p0).normalized()
		if nn.dot(zax) > 0.0:
			nn = -nn
		var b := lverts.size()
		lverts.append(p0); lverts.append(p1); lverts.append(p2)
		lnorms.append(nn); lnorms.append(nn); lnorms.append(nn)
		luvs.append(ouv[j]); luvs.append(ouv[i]); luvs.append(uvm)
		for k in 3:
			lcols.append(Color(hue, ao * 0.92, 0.0, 1.0))
		lidx.append(b); lidx.append(b + 1); lidx.append(b + 2)
	# rim
	for i in n:
		var j := (i + 1) % n
		var a0: Vector3 = front[i]
		var a1: Vector3 = front[j]
		var b0: Vector3 = back[i]
		var b1: Vector3 = back[j]
		var nrm := (a1 - a0).cross(b0 - a0).normalized()
		var b := lverts.size()
		for q in [a0, a1, b1, b0]:
			lverts.append(q)
			lnorms.append(nrm)
			luvs.append(ouv[i])
			lcols.append(Color(hue, ao * 0.82, 0.0, 1.0))
		lidx.append(b); lidx.append(b + 1); lidx.append(b + 2)
		lidx.append(b); lidx.append(b + 2); lidx.append(b + 3)

func _tube(path: PackedVector3Array, radii: PackedFloat32Array, sides: int, vscale: float) -> void:
	var base := bverts.size()
	var vlen := 0.0
	for i in path.size():
		if i > 0:
			vlen += path[i].distance_to(path[i - 1])
		var t: Vector3
		if i == 0:
			t = (path[1] - path[0]).normalized()
		elif i == path.size() - 1:
			t = (path[i] - path[i - 1]).normalized()
		else:
			t = (path[i + 1] - path[i - 1]).normalized()
		var ref := Vector3.UP
		if absf(t.dot(ref)) > 0.9:
			ref = Vector3.RIGHT
		var side := t.cross(ref).normalized()
		var up2 := side.cross(t).normalized()
		for j in sides + 1:
			var a := TAU * float(j) / float(sides)
			var dir := side * cos(a) + up2 * sin(a)
			bverts.append(path[i] + dir * radii[i])
			bnorms.append(dir)
			buvs.append(Vector2(float(j) / float(sides), vlen * vscale))
			var ao := clampf(0.55 + 0.45 * float(i) / float(path.size() - 1), 0.5, 1.0)
			bcols.append(Color(ao, 0.0, 0.0, 1.0))
	for i in path.size() - 1:
		for j in sides:
			var a := base + i * (sides + 1) + j
			var b := a + 1
			var c := a + sides + 1
			var d := c + 1
			bidx.append(a); bidx.append(c); bidx.append(b)
			bidx.append(b); bidx.append(c); bidx.append(d)

func _make_meshes(pos: Vector3) -> void:
	var bark_arrays := []
	bark_arrays.resize(Mesh.ARRAY_MAX)
	bark_arrays[Mesh.ARRAY_VERTEX] = bverts
	bark_arrays[Mesh.ARRAY_NORMAL] = bnorms
	bark_arrays[Mesh.ARRAY_TEX_UV] = buvs
	bark_arrays[Mesh.ARRAY_COLOR] = bcols
	bark_arrays[Mesh.ARRAY_INDEX] = bidx
	var bm := ArrayMesh.new()
	bm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bark_arrays)
	var bmi := MeshInstance3D.new()
	bmi.mesh = bm
	bmi.material_override = bark_mat
	bmi.position = pos
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(bmi)
	var leaf_arrays := []
	leaf_arrays.resize(Mesh.ARRAY_MAX)
	leaf_arrays[Mesh.ARRAY_VERTEX] = lverts
	leaf_arrays[Mesh.ARRAY_NORMAL] = lnorms
	leaf_arrays[Mesh.ARRAY_TEX_UV] = luvs
	leaf_arrays[Mesh.ARRAY_COLOR] = lcols
	leaf_arrays[Mesh.ARRAY_INDEX] = lidx
	var lm := ArrayMesh.new()
	lm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaf_arrays)
	var lmi := MeshInstance3D.new()
	lmi.mesh = lm
	lmi.material_override = leaf_mat
	lmi.position = pos
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(lmi)