class_name TreeBuilder
extends RefCounted

## Procedural tree archetypes.  Trunks and branches are swept tubes
## (parametric surfaces), canopies are clusters of alpha-tested leaf cards.
## Everything is generated from seeded RNGs — no textures on disk.

var rng := RandomNumberGenerator.new()

func _init(seed: int) -> void:
	rng.seed = seed

# ---------------------------------------------------------------- primitives

func _frame(tangent: Vector3) -> Array:
	var ref := Vector3.UP
	if absf(tangent.dot(ref)) > 0.9:
		ref = Vector3.RIGHT
	var side := tangent.cross(ref).normalized()
	var up2 := side.cross(tangent).normalized()
	return [side, up2]

func _tube(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		idx: PackedInt32Array, path: PackedVector3Array, radii: PackedFloat32Array, sides: int, vscale: float) -> void:
	var base := verts.size()
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
		var fr := _frame(t)
		var side: Vector3 = fr[0]
		var up2: Vector3 = fr[1]
		for j in sides + 1:
			var a := TAU * float(j) / float(sides)
			var dir := side * cos(a) + up2 * sin(a)
			verts.append(path[i] + dir * radii[i])
			norms.append(dir)
			uvs.append(Vector2(float(j) / float(sides), vlen * vscale))
	for i in path.size() - 1:
		for j in sides:
			var a := base + i * (sides + 1) + j
			var b := a + 1
			var c := a + sides + 1
			var d := c + 1
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(b); idx.append(c); idx.append(d)

func _quad(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		cols: PackedColorArray, idx: PackedInt32Array, c: Vector3, n: Vector3, tg: Vector3, bt: Vector3,
		size: float, seed: float, tilt: float) -> void:
	var t2 := tg * cos(tilt) + bt * sin(tilt)
	var b2 := bt * cos(tilt) - tg * sin(tilt)
	var h := size * 0.5
	var base := verts.size()
	verts.append(c - t2 * h - b2 * h)
	verts.append(c + t2 * h - b2 * h)
	verts.append(c + t2 * h + b2 * h)
	verts.append(c - t2 * h + b2 * h)
	for k in 4:
		norms.append(n)
		cols.append(Color(seed, 0.0, 0.0, 1.0))
	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(1, 0))
	uvs.append(Vector2(1, 1))
	uvs.append(Vector2(0, 1))
	idx.append(base); idx.append(base + 1); idx.append(base + 2)
	idx.append(base); idx.append(base + 2); idx.append(base + 3)

func _mesh(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		cols: PackedColorArray, idx: PackedInt32Array, mat: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if cols.size() == verts.size():
		arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, mat)
	return m

# ---------------------------------------------------------------- broadleaf

func broadleaf(height: float, radius: float, crown: float, detail: bool) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	var trunk := PackedVector3Array()
	var radii := PackedFloat32Array()
	var lean := Vector3(rng.randf_range(-0.04, 0.04), 0.0, rng.randf_range(-0.04, 0.04))
	var segs := 7 if detail else 4
	for i in segs + 1:
		var t := float(i) / float(segs)
		trunk.append(Vector3(lean.x * height * t * t, height * t, lean.z * height * t * t))
		var rr := radius * (1.0 - t * 0.72)
		if i == 0:
			rr = radius * 1.9
		radii.append(rr)
	_tube(verts, norms, uvs, idx, trunk, radii, 12 if detail else 7, 0.12)

	# buttress roots
	if detail:
		for b in 5:
			var a := TAU * float(b) / 5.0 + rng.randf_range(-0.2, 0.2)
			var root := PackedVector3Array([
				Vector3(cos(a) * radius * 3.2, -0.4, sin(a) * radius * 3.2),
				Vector3(cos(a) * radius * 1.7, height * 0.03, sin(a) * radius * 1.7),
				Vector3(cos(a) * radius * 0.6, height * 0.14, sin(a) * radius * 0.6),
			])
			var rr := PackedFloat32Array([0.32, 0.45, radius * 0.55])
			_tube(verts, norms, uvs, idx, root, rr, 5, 0.2)

	# branches + canopy clusters
	var clusters: Array = []
	var nb := 7 if detail else 5
	for b in nb:
		var t := 0.58 + 0.34 * float(b) / float(nb - 1)
		var a := TAU * (float(b) * 0.618) + rng.randf_range(-0.3, 0.3)
		var origin := Vector3(lean.x * height * t * t, height * t, lean.z * height * t * t)
		var reach := crown * rng.randf_range(0.34, 0.52)
		var rise := crown * rng.randf_range(0.10, 0.26)
		var bend := Vector3(cos(a) * reach, rise, sin(a) * reach)
		var tip := origin + bend
		var mid := origin + bend * 0.55 + Vector3(0, rise * 0.45, 0)
		var bp := PackedVector3Array([origin, mid, tip])
		var br := PackedFloat32Array([radius * 0.34, radius * 0.18, radius * 0.06])
		_tube(verts, norms, uvs, idx, bp, br, 6 if detail else 4, 0.2)
		clusters.append([tip + Vector3(0, crown * 0.06, 0), crown * rng.randf_range(0.22, 0.34)])
		# secondary cluster
		var tip2 := mid + bend * 0.35 + Vector3(rng.randf_range(-1, 1) * crown * 0.12, rise * 0.5, rng.randf_range(-1, 1) * crown * 0.12)
		clusters.append([tip2, crown * rng.randf_range(0.18, 0.28)])
	# crown top
	clusters.append([Vector3(lean.x * height, height * 1.0, lean.z * height), crown * 0.30])

	var bark := _mesh(verts, norms, uvs, PackedColorArray(), idx, null)

	var cv := PackedVector3Array()
	var cn := PackedVector3Array()
	var cu := PackedVector2Array()
	var cc := PackedColorArray()
	var ci := PackedInt32Array()
	var cards := 30 if detail else 7
	for cl in clusters:
		var c: Vector3 = cl[0]
		var rad: float = cl[1]
		for k in cards:
			var phi := TAU * 0.61803398875 * float(k) + rng.randf_range(0.0, 0.4)
			var yy := 1.0 - 2.0 * (float(k) + 0.5) / float(cards)
			var rr := sqrt(maxf(0.0, 1.0 - yy * yy))
			var p := c + Vector3(cos(phi) * rr * rad * 1.25, yy * rad * 0.78, sin(phi) * rr * rad * 1.25)
			var n := (p - c).normalized()
			if n.length() < 0.1:
				n = Vector3.UP
			var tg := n.cross(Vector3.UP)
			if tg.length() < 0.1:
				tg = Vector3.RIGHT
			tg = tg.normalized()
			var bt := n.cross(tg).normalized()
			var s := rad * rng.randf_range(0.42, 0.68)
			_quad(cv, cn, cu, cc, ci, p, n, tg, bt, s, rng.randf(), rng.randf_range(0.0, TAU))
	var canvas := _mesh(cv, cn, cu, cc, ci, null)
	return {"bark": bark, "canopy": canvas, "height": height, "crown": crown}

# ---------------------------------------------------------------- emergent

func emergent(height: float, detail: bool) -> Dictionary:
	var d := broadleaf(height, height * 0.040, height * 0.72, detail)
	d["emergent"] = true
	return d

# ---------------------------------------------------------------- palm

func palm(height: float, detail: bool) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var trunk := PackedVector3Array()
	var radii := PackedFloat32Array()
	var segs := 12 if detail else 6
	for i in segs + 1:
		var t := float(i) / float(segs)
		var x := sin(t * 1.5) * height * 0.13
		var z := cos(t * 0.9) * height * 0.05
		trunk.append(Vector3(x, height * t, z))
		var rr := height * 0.014 * (1.0 - t * 0.25)
		if i == 0:
			rr *= 1.7
		radii.append(rr)
	_tube(verts, norms, uvs, idx, trunk, radii, 10 if detail else 6, 0.5)
	var top := trunk[trunk.size() - 1]
	var bark := _mesh(verts, norms, uvs, PackedColorArray(), idx, null)

	# fronds: curved ribbons
	var fv := PackedVector3Array()
	var fn := PackedVector3Array()
	var fu := PackedVector2Array()
	var fc := PackedColorArray()
	var fi := PackedInt32Array()
	var nf := 13 if detail else 8
	for f in nf:
		var a := TAU * float(f) / float(nf) + rng.randf_range(-0.15, 0.15)
		var droop := rng.randf_range(0.55, 1.0)
		var length := height * rng.randf_range(0.32, 0.45)
		var seg := 7
		var base := fv.size()
		for s in seg + 1:
			var t := float(s) / float(seg)
			var p := top + Vector3(cos(a) * length * t, length * (0.32 * t - droop * 0.55 * t * t), sin(a) * length * t)
			var n := Vector3(cos(a + PI * 0.5) * 0.35, 0.9, sin(a + PI * 0.5) * 0.35).normalized()
			var tg := Vector3(-sin(a), 0.0, cos(a)).normalized()
			var width := length * 0.20 * (1.0 - t * 0.78)
			var c0 := p - tg * width * 0.5
			var c1 := p + tg * width * 0.5
			fv.append(c0); fv.append(c1)
			fn.append(n); fn.append(n)
			fu.append(Vector2(0.0, t)); fu.append(Vector2(1.0, t))
			fc.append(Color(rng.randf(), 0.0, 0.0, 1.0)); fc.append(Color(rng.randf(), 0.0, 0.0, 1.0))
		for s in seg:
			var a0 := base + s * 2
			var a1 := a0 + 1
			var b0 := a0 + 2
			var b1 := a0 + 3
			fi.append(a0); fi.append(b0); fi.append(a1)
			fi.append(a1); fi.append(b0); fi.append(b1)
	var fronds := _mesh(fv, fn, fu, fc, fi, null)
	return {"bark": bark, "canopy": fronds, "height": height, "crown": height * 0.8}

# ---------------------------------------------------------------- conifer

func conifer(height: float, detail: bool) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var trunk := PackedVector3Array()
	var radii := PackedFloat32Array()
	var segs := 5
	for i in segs + 1:
		var t := float(i) / float(segs)
		trunk.append(Vector3(0, height * t, 0))
		radii.append(height * 0.012 * (1.0 - t * 0.9) + 0.05)
	_tube(verts, norms, uvs, idx, trunk, radii, 7 if detail else 5, 0.3)
	var bark := _mesh(verts, norms, uvs, PackedColorArray(), idx, null)

	var fv := PackedVector3Array()
	var fn := PackedVector3Array()
	var fu := PackedVector2Array()
	var fc := PackedColorArray()
	var fi := PackedInt32Array()
	var layers := 9 if detail else 5
	for l in layers:
		var t := 0.18 + 0.78 * float(l) / float(layers - 1)
		var rad := height * 0.24 * (1.0 - t) + 0.4
		var yy := height * t
		var seg := 10 if detail else 7
		var base := fv.size()
		for s in seg + 1:
			var a := TAU * float(s) / float(seg)
			fv.append(Vector3(cos(a) * rad, yy - height * 0.05, sin(a) * rad))
			fn.append(Vector3(cos(a) * 0.6, 0.8, sin(a) * 0.6).normalized())
			fu.append(Vector2(float(s) / float(seg), t))
			fc.append(Color(rng.randf(), 0.0, 0.0, 1.0))
		for s in seg:
			var apex := fv.size()
			fv.append(Vector3(0, yy + height * 0.055, 0))
			fn.append(Vector3(0, 1, 0))
			fu.append(Vector2(0.5, t + 0.02))
			fc.append(Color(0.5, 0.0, 0.0, 1.0))
			var a0 := base + s
			var a1 := a0 + 1
			fi.append(a0); fi.append(apex); fi.append(a1)
			# underside so the cone is not paper-thin
			fi.append(a0); fi.append(a1); fi.append(apex)
	var needles := _mesh(fv, fn, fu, fc, fi, null)
	return {"bark": bark, "canopy": needles, "height": height, "crown": height * 0.5}

# ---------------------------------------------------------------- far LOD

func far_blob(height: float, crown: float) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var trunk := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, height * 0.62, 0)
	])
	var radii := PackedFloat32Array([height * 0.035, height * 0.016])
	_tube(verts, norms, uvs, idx, trunk, radii, 5, 0.1)
	var bark := _mesh(verts, norms, uvs, PackedColorArray(), idx, null)

	var cv := PackedVector3Array()
	var cn := PackedVector3Array()
	var cu := PackedVector2Array()
	var cc := PackedColorArray()
	var ci := PackedInt32Array()
	for k in 9:
		var a := TAU * float(k) / 9.0 + rng.randf_range(-0.25, 0.25)
		var rad := crown * rng.randf_range(0.11, 0.27)
		var center := Vector3(cos(a) * crown * rng.randf_range(0.16, 0.32), height * rng.randf_range(0.58, 0.98), sin(a) * crown * rng.randf_range(0.16, 0.32))
		var sx := rng.randf_range(0.75, 1.4)
		var sy := rng.randf_range(0.55, 1.0)
		var sz := rng.randf_range(0.75, 1.4)
		var base := cv.size()
		for la in 5:
			var v := float(la) / 4.0
			var yy := cos(v * PI)
			var rr := sin(v * PI)
			for lo in 9:
				var u := float(lo) / 8.0
				var ang := u * TAU
				var wob := 1.0 + 0.20 * sin(ang * 3.0 + float(k)) + 0.12 * cos(v * 7.0 + ang * 2.0)
				var p := center + Vector3(cos(ang) * rr * rad * sx, yy * rad * 0.8 * sy, sin(ang) * rr * rad * sz) * wob
				cv.append(p)
				cn.append((p - center).normalized())
				cu.append(Vector2(u, v))
				cc.append(Color(rng.randf(), 0.0, 0.0, 1.0))
		for la in 4:
			for lo in 8:
				var a0 := base + la * 9 + lo
				var b0 := a0 + 1
				var c0 := a0 + 9
				var d0 := c0 + 1
				ci.append(a0); ci.append(c0); ci.append(b0)
				ci.append(b0); ci.append(c0); ci.append(d0)
	var canopy := _mesh(cv, cn, cu, cc, ci, null)
	return {"bark": bark, "canopy": canopy, "height": height, "crown": crown}