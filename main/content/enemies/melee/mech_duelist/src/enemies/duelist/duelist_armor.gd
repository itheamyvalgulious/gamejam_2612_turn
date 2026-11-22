extends RefCounted
## 曲面装甲。截面依次定义高度、横宽半径、前后半径、中心偏移、两侧角度和斜切高度。
## 0° 朝前，90° 朝右。外表面、窄倒角和背板使用独立的材质面。

const MeshKit = preload("res://src/vesper/mesh_kit.gd")
const Shell = preload("res://src/enemies/duelist/duelist_shell.gd")
const SPANS := 18


static func fit_split(bone: Node3D, rows: Array, face: Material, flank: Material,
		rim: Material, lining: Material, thickness: float, side: float) -> void:
	var main := []
	var wing := []
	for row: Array in rows:
		# Keep a physical seam between the load-bearing plate and its side cover.
		main.append(_arc_slice(row, 0.0, 0.685))
		wing.append(_arc_slice(row, 0.72, 1.0))
	fit(bone, main, face, rim, lining, thickness, side)
	fit(bone, wing, flank, rim, lining, thickness * 0.77, side)


static func _arc_slice(row: Array, from: float, to: float) -> Array:
	return [row[0] + ((from + to) * 0.5 - 0.5) * row[7], row[1], row[2], row[3], row[4],
		lerpf(row[5], row[6], from), lerpf(row[5], row[6], to), row[7] * (to - from)]


static func fit(bone: Node3D, rows: Array, face: Material, rim: Material, lining: Material,
		thickness: float, side := 1.0) -> void:
	var skin := SurfaceTool.new()
	var edge := SurfaceTool.new()
	var back := SurfaceTool.new()
	skin.begin(Mesh.PRIMITIVE_TRIANGLES)
	edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	back.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: Array[PackedVector3Array] = []
	var outer: Array[PackedVector3Array] = []
	var inset: Array[PackedVector3Array] = []
	for i in rows.size():
		var skin_row := PackedVector3Array()
		var edge_row := PackedVector3Array()
		var back_row := PackedVector3Array()
		for j in range(SPANS + 1):
			var u := float(j) / SPANS
			var point := _point(rows[i], u, side)
			var lip := _point(rows[i], lerpf(0.028, 0.972, u), side)
			if i == 0:
				lip = lip.lerp(_point(rows[1], lerpf(0.028, 0.972, u), side), 0.075)
			elif i == rows.size() - 1:
				lip = lip.lerp(_point(rows[i - 1], lerpf(0.028, 0.972, u), side), 0.075)
			var angle := deg_to_rad(lerpf(rows[i][5], rows[i][6], u))
			var radial := Vector3(side * sin(angle), 0, -cos(angle))
			skin_row.append(lip + radial * thickness * 0.29)
			edge_row.append(point)
			back_row.append(point - radial * thickness)
		inner.append(skin_row)
		outer.append(edge_row)
		inset.append(back_row)
	for i in range(rows.size() - 1):
		for j in SPANS:
			var a := inner[i][j]
			var b := inner[i][j + 1]
			var c := inner[i + 1][j + 1]
			var d := inner[i + 1][j]
			var na := _normal(inner, i, j, side)
			var nb := _normal(inner, i, j + 1, side)
			var nc := _normal(inner, i + 1, j + 1, side)
			var nd := _normal(inner, i + 1, j, side)
			Shell.soft_tri(skin, a, b, c, na, nb, nc)
			Shell.soft_tri(skin, a, c, d, na, nc, nd)
			_quad(back, inset[i][j], inset[i][j + 1], inset[i + 1][j + 1], inset[i + 1][j], -na)
		for j: int in [0, SPANS]:
			var across := outer[i][j] - outer[i][1 if j == 0 else SPANS - 1]
			_lip(edge, back, inner, outer, inset, Vector2i(i, j), Vector2i(i + 1, j), across)
	for i: int in [0, rows.size() - 1]:
		for j in SPANS:
			_lip(edge, back, inner, outer, inset, Vector2i(i, j), Vector2i(i, j + 1),
				Vector3.DOWN if i == 0 else Vector3.UP)
	var mesh := skin.commit()
	edge.commit(mesh)
	back.commit(mesh)
	var plate := MeshKit.add(bone, mesh, null)
	plate.set_surface_override_material(0, face)
	plate.set_surface_override_material(1, rim)
	plate.set_surface_override_material(2, lining)


static func _point(row: Array, u: float, side: float) -> Vector3:
	var angle := deg_to_rad(lerpf(row[5], row[6], u))
	return Vector3(side * (row[3] + sin(angle) * row[1]), row[0] + (u - 0.5) * row[7],
		row[4] - cos(angle) * row[2])


static func _normal(rows: Array[PackedVector3Array], i: int, j: int, side: float) -> Vector3:
	var across := rows[i][mini(j + 1, SPANS)] - rows[i][maxi(j - 1, 0)]
	var along := rows[mini(i + 1, rows.size() - 1)][j] - rows[maxi(i - 1, 0)][j]
	return (along.cross(across) * side).normalized()


static func _lip(edge: SurfaceTool, back: SurfaceTool, inner: Array[PackedVector3Array],
		outer: Array[PackedVector3Array], inset: Array[PackedVector3Array], a: Vector2i,
		b: Vector2i, facing: Vector3) -> void:
	_quad(edge, inner[a.x][a.y], inner[b.x][b.y], outer[b.x][b.y], outer[a.x][a.y], facing)
	_quad(back, outer[a.x][a.y], outer[b.x][b.y], inset[b.x][b.y], inset[a.x][a.y], facing)


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3) -> void:
	Shell.tri(tool, a, b, c, facing)
	Shell.tri(tool, a, c, d, facing)
