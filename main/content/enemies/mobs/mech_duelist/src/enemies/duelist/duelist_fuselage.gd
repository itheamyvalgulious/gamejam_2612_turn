extends RefCounted
## Carapace and frame for the helmet, chest and pelvis.

const MeshKit = preload("res://src/vesper/mesh_kit.gd")
const Shell = preload("res://src/enemies/duelist/duelist_shell.gd")
const Parts = preload("res://src/enemies/duelist/duelist_parts.gd")
const Casing = preload("res://src/enemies/duelist/duelist_casing.gd")
const Armor = preload("res://src/enemies/duelist/duelist_armor.gd")


static func helmet(head: Node3D, mat: Dictionary) -> void:
	# Each half-profile runs from the forward keel to the nape. Matching corners
	# form continuous facets across the crown, temple and tapered lower face.
	var contours: Array[PackedVector3Array] = [
		PackedVector3Array([
			Vector3(0, 0.032, -0.195), Vector3(0.064, 0.042, -0.175), Vector3(0.091, 0.064, -0.061),
			Vector3(0.077, 0.092, 0.084), Vector3(0, 0.108, 0.141),
		]),
		PackedVector3Array([
			Vector3(0, 0.077, -0.239), Vector3(0.089, 0.099, -0.208), Vector3(0.129, 0.132, -0.054),
			Vector3(0.112, 0.135, 0.125), Vector3(0, 0.142, 0.181),
		]),
		PackedVector3Array([
			Vector3(0, 0.159, -0.269), Vector3(0.103, 0.176, -0.224), Vector3(0.176, 0.194, -0.079),
			Vector3(0.145, 0.205, 0.145), Vector3(0, 0.208, 0.221),
		]),
		PackedVector3Array([
			Vector3(0, 0.258, -0.276), Vector3(0.109, 0.263, -0.243), Vector3(0.192, 0.278, -0.097),
			Vector3(0.161, 0.273, 0.161), Vector3(0, 0.274, 0.235),
		]),
		PackedVector3Array([
			Vector3(0, 0.321, -0.280), Vector3(0.112, 0.329, -0.247), Vector3(0.209, 0.346, -0.100),
			Vector3(0.175, 0.346, 0.188), Vector3(0, 0.344, 0.254),
		]),
		PackedVector3Array([
			Vector3(0, 0.353, -0.307), Vector3(0.127, 0.362, -0.269), Vector3(0.233, 0.379, -0.100),
			Vector3(0.191, 0.373, 0.192), Vector3(0, 0.359, 0.251),
		]),
		PackedVector3Array([
			Vector3(0, 0.451, -0.231), Vector3(0.115, 0.457, -0.198), Vector3(0.218, 0.448, -0.017),
			Vector3(0.157, 0.455, 0.192), Vector3(0, 0.437, 0.257),
		]),
		PackedVector3Array([
			Vector3(0, 0.536, -0.070), Vector3(0.078, 0.535, -0.049), Vector3(0.125, 0.528, 0.058),
			Vector3(0.088, 0.516, 0.155), Vector3(0, 0.497, 0.190),
		]),
	]
	var stock: Array[PackedVector3Array] = contours.duplicate()
	for i in contours.size():
		contours[i] = _helmet_bevel(contours[i])
	MeshKit.add(head, Shell.loft([
		[-0.061, 0.066, 0.063, 0, 0.020], [-0.022, 0.084, 0.080, 0, 0.013],
		[0.026, 0.089, 0.084, 0, 0.014], [0.091, 0.072, 0.071, 0, 0.014],
	]), mat["frame"])
	var surfaces: Array[SurfaceTool] = []
	for i in 5:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces.append(surface)
	for side: float in [-1.0, 1.0]:
		var mirror := Vector3(side, 1, 1)
		for level in range(contours.size() - 1):
			var bottom := contours[level]
			var top := contours[level + 1]
			for edge in range(bottom.size() - 1):
				var material_slot := 0
				match level:
					1, 2:
						material_slot = 1 if edge < 5 else 2
					3:
						material_slot = 3 if edge < 5 else 0
					4:
						material_slot = 2
					5, 6:
						material_slot = 4
				var a := bottom[edge] * mirror
				var b := bottom[edge + 1] * mirror
				var c := top[edge + 1] * mirror
				var d := top[edge] * mirror
				var outward := (a + b + c + d) * Vector3(1, 0.18, 1)
				var normal := (c - a).cross(b - a).normalized()
				if normal.dot(outward) < 0.0:
					normal = -normal
				var na := normal
				var nb := normal
				var nc := normal
				var nd := normal
				if material_slot == 4:
					na = _hood_normal(a, normal)
					nb = _hood_normal(b, normal)
					nc = _hood_normal(c, normal)
					nd = _hood_normal(d, normal)
				Shell.soft_tri(surfaces[material_slot], a, b, c, na, nb, nc)
				Shell.soft_tri(surfaces[material_slot], a, c, d, na, nc, nd)
		for level in [0, contours.size() - 1]:
			var ring := contours[level]
			var upper: bool = level != 0
			var center := Vector3(0, 0.540, 0.066) if upper else Vector3(0, 0.056, -0.023)
			for edge in range(ring.size() - 1):
				Shell.tri(surfaces[4 if upper else 0], center, ring[edge] * mirror, ring[edge + 1] * mirror,
					Vector3.UP if upper else Vector3.DOWN)
	var mesh := ArrayMesh.new()
	var surfaces_material: Array = [mat["frame"], mat["coat"], mat["steel"], mat["sensor"], mat["hood"]]
	for i in surfaces.size():
		surfaces[i].commit(mesh)
		mesh.surface_set_material(i, surfaces_material[i])
	MeshKit.add(head, mesh, null)

	# Place the rangefinder on the narrow front facet, leaving the rest of the smoked visor dark.
	var port := PackedVector3Array()
	for uv: Vector2 in [Vector2(0.14, 0.53), Vector2(0.26, 0.68), Vector2(0.86, 0.68),
			Vector2(0.93, 0.52), Vector2(0.82, 0.46), Vector2(0.21, 0.46)]:
		var point: Vector3 = stock[3][0].lerp(stock[3][1], uv.x).lerp(stock[4][0].lerp(stock[4][1], uv.x), uv.y)
		port.append(point * Vector3(-1, 1, 1) + Vector3(0, 0, -0.007))
	Casing.panel(head, port, Vector3(-0.28, 0, -1), 0.004, mat["optic"], mat["sensor"])
	for i in 2:
		var u := 0.43 + 0.14 * i
		var point: Vector3 = stock[3][0].lerp(stock[3][1], u).lerp(stock[4][0].lerp(stock[4][1], u), 0.38)
		MeshKit.add(head, MeshKit.slab(0.005, 0.005, 0.005, 0.001), mat["status"],
			point + Vector3(0, 0, -0.006), Vector3(0, -17, 0))
	for side: float in [-1.0, 1.0]:
		_helmet_inlay(head, contours, PackedVector2Array([
			Vector2(3.72, 4.23), Vector2(4.61, 5.02), Vector2(7.11, 5.53),
			Vector2(9.15, 5.40), Vector2(8.51, 4.55), Vector2(6.88, 4.14), Vector2(4.85, 3.85),
		]), side, mat["frame"], 0.003)
		_helmet_inlay(head, contours, PackedVector2Array([
			Vector2(4.05, 4.30), Vector2(4.83, 4.89), Vector2(7.23, 5.34),
			Vector2(8.86, 5.26), Vector2(8.37, 4.67), Vector2(6.81, 4.32), Vector2(4.93, 4.04),
		]), side, mat["steel"], 0.005)
		_helmet_inlay(head, contours, PackedVector2Array([
			Vector2(2.77, 1.69), Vector2(4.31, 2.53), Vector2(6.23, 2.59),
			Vector2(7.26, 2.37), Vector2(6.32, 2.32), Vector2(4.06, 2.26),
		]), side, mat["frame"], 0.003)

	# A shallow service cover holds the rear diagnostics, within the shell profile.
	Casing.panel(head, PackedVector3Array([
		Vector3(-0.053, 0.215, 0.205), Vector3(-0.064, 0.276, 0.225), Vector3(-0.035, 0.346, 0.243),
		Vector3(0.035, 0.346, 0.243), Vector3(0.064, 0.276, 0.225), Vector3(0.053, 0.215, 0.205),
	]), Vector3.BACK, 0.017, mat["steel"], mat["frame"], mat["frame"], 0.34)
	for i in 3:
		var y := 0.250 + i * 0.023
		MeshKit.add(head, MeshKit.slab(0.032, 0.007, 0.006, 0.001), mat["status"],
			Vector3(0, y, 0.231 + i * 0.011))


static func _helmet_bevel(contour: PackedVector3Array) -> PackedVector3Array:
	var rounded := PackedVector3Array([contour[0]])
	for i in range(1, contour.size() - 1):
		var before := contour[i].lerp(contour[i - 1], 0.17)
		var after := contour[i].lerp(contour[i + 1], 0.17)
		rounded.append(before)
		rounded.append(contour[i].lerp((before + after) / 2, 0.27))
		rounded.append(after)
	rounded.append(contour[contour.size() - 1])
	return rounded


static func _hood_normal(at: Vector3, face: Vector3) -> Vector3:
	var curve := Vector3(at.x, (at.y - 0.412) * 1.35, at.z - 0.038).normalized()
	return face.lerp(curve, 0.42).normalized()


static func _helmet_inlay(head: Node3D, contours: Array[PackedVector3Array], outline: PackedVector2Array,
		side: float, material: Material, height: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mirror := Vector3(side, 1, 1)
	var first_row := floori(outline[0].y)
	for point in outline:
		first_row = mini(first_row, floori(point.y))
	for y in range(first_row, contours.size() - 1):
		for x in range(contours[y].size() - 1):
			var a := Vector2(x, y)
			var b := a + Vector2.RIGHT
			var c := a + Vector2.ONE
			var d := a + Vector2.DOWN
			var corners := PackedVector3Array([contours[y][x] * mirror, contours[y][x + 1] * mirror,
				contours[y + 1][x + 1] * mirror, contours[y + 1][x] * mirror])
			for tri: PackedVector2Array in [PackedVector2Array([a, b, c]), PackedVector2Array([a, c, d])]:
				var upper := tri[1] == c
				var normal := ((corners[2] - corners[0]).cross(corners[1] - corners[0])
					if not upper else (corners[3] - corners[0]).cross(corners[2] - corners[0])).normalized()
				if normal.dot(Vector3(side, 0, 0)) < 0:
					normal = -normal
				for clipped: PackedVector2Array in Geometry2D.intersect_polygons(outline, tri):
					var indices := Geometry2D.triangulate_polygon(clipped)
					var vertices := PackedVector3Array()
					for point in clipped:
						var uv := point - a
						var position := corners[0] * (1.0 - uv.y) + corners[2] * uv.x + corners[3] * (uv.y - uv.x) if upper \
							else corners[0] * (1.0 - uv.x) + corners[1] * (uv.x - uv.y) + corners[2] * uv.y
						vertices.append(position + normal * height)
					for i in range(0, indices.size(), 3):
						Shell.tri(surface, vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]], normal)
	MeshKit.add(head, surface.commit(), material)


static func thorax(torso: Node3D, mat: Dictionary) -> void:
	for side: float in [-1.0, 1.0]:
		# Two sweeping chest plates leave the sternum and the shoulder sockets exposed.
		Armor.fit(torso, [
			[0.505, 0.31, 0.215, 0.017, -0.019, 18, 64, 0.132],
			[0.577, 0.39, 0.246, 0.012, -0.021, 11, 79, 0.164],
			[0.657, 0.45, 0.263, 0.009, -0.022, 7, 84, 0.182],
			[0.763, 0.474, 0.266, 0.009, -0.025, 8, 83, 0.178],
			[0.841, 0.461, 0.248, 0.010, -0.020, 13, 75, 0.139],
			[0.927, 0.331, 0.200, 0.011, -0.014, 35, 67, 0.078],
		], mat["ceramic"], mat["coat"], mat["frame"], 0.038, side)
		Casing.panel(torso, PackedVector3Array([
			Vector3(side * 0.022, 0.888, -0.191), Vector3(side * 0.091, 1.063, -0.098),
			Vector3(side * 0.184, 1.049, -0.102), Vector3(side * 0.332, 0.966, -0.069),
			Vector3(side * 0.413, 0.923, -0.032), Vector3(side * 0.344, 0.895, -0.107),
			Vector3(side * 0.197, 0.934, -0.169), Vector3(side * 0.072, 0.859, -0.209),
		]), Vector3(0, 0.50, -0.86), 0.028, mat["steel"], mat["frame"])
		Armor.fit(torso, [
			[0.250, 0.219, 0.170, 0.018, -0.009, 48, 96, 0.087],
			[0.323, 0.269, 0.197, 0.017, -0.008, 34, 119, 0.097],
			[0.414, 0.328, 0.225, 0.016, -0.002, 31, 127, 0.112],
			[0.511, 0.379, 0.242, 0.017, 0.005, 42, 122, 0.116],
			[0.603, 0.395, 0.240, 0.014, 0.013, 74, 119, 0.080],
		], mat["coat"], mat["steel"], mat["frame"], 0.029, side)
		Armor.fit(torso, [
			[0.241, 0.214, 0.156, 0.020, 0.037, 131, 170, -0.038],
			[0.330, 0.264, 0.186, 0.021, 0.043, 119, 177, -0.049],
			[0.432, 0.330, 0.210, 0.016, 0.048, 115, 174, -0.080],
			[0.521, 0.361, 0.232, 0.017, 0.051, 112, 166, -0.083],
			[0.597, 0.385, 0.213, 0.014, 0.051, 109, 153, -0.045],
		], mat["steel"], mat["coat"], mat["frame"], 0.024, side)
		Parts.tube(torso, PackedVector3Array([
			Vector3(side * 0.12, -0.052, 0.119), Vector3(side * 0.173, 0.108, 0.138),
			Vector3(side * 0.210, 0.245, 0.147), Vector3(side * 0.275, 0.346, 0.157),
			Vector3(side * 0.304, 0.509, 0.175),
		]), 0.016, mat["steel"])
		for i in 3:
			var y := 0.360 + 0.047 * i
			var x := side * (0.193 + 0.026 * i)
			MeshKit.add(torso, MeshKit.slab(0.090, 0.024, 0.010, 0.002), mat["frame"],
				Vector3(x, y, -0.175 - i * 0.022), Vector3(0, side * -33, side * 26))
	var spine := mat["steel"] as Material
	for i in 6:
		var y := 0.12 + 0.138 * i
		var z := 0.172 + (0.138 * smoothstep(0.12, 0.67, y))
		Casing.panel(torso, PackedVector3Array([
			Vector3(-0.059, y - 0.020, z), Vector3(0.0, y - 0.043, z + 0.019),
			Vector3(0.059, y - 0.020, z), Vector3(0.041, y + 0.058, z + 0.013),
			Vector3(-0.041, y + 0.058, z + 0.013),
		]), Vector3.BACK, 0.030, spine, mat["frame"])
	Casing.panel(torso, PackedVector3Array([
		Vector3(0.0, 0.501, -0.198), Vector3(-0.046, 0.568, -0.235),
		Vector3(-0.032, 0.811, -0.249), Vector3(0.0, 0.875, -0.231),
		Vector3(0.032, 0.815, -0.248), Vector3(0.046, 0.566, -0.232),
	]), Vector3.FORWARD, 0.025, mat["coat"], mat["frame"], mat["steel"], 0.30)
	for i in 3:
		MeshKit.add(torso, MeshKit.slab(0.017, 0.009, 0.012, 0.002), mat["status"],
			Vector3(0.006, 0.724 + i * 0.023, -0.264), Vector3(0, 0, 3))


static func pelvis(body: Node3D, mat: Dictionary) -> void:
	for side: float in [-1.0, 1.0]:
		Armor.fit(body, [
			[-0.161, 0.214, 0.215, 0.022, -0.015, 19, 66, 0.066],
			[-0.118, 0.336, 0.235, 0.017, -0.020, 12, 87, 0.108],
			[-0.040, 0.386, 0.257, 0.017, -0.020, 9, 94, 0.136],
			[0.042, 0.370, 0.245, 0.016, -0.013, 17, 89, 0.145],
			[0.100, 0.257, 0.202, 0.015, -0.010, 40, 71, 0.090],
		], mat["coat"], mat["steel"], mat["frame"], 0.027, side)
		Armor.fit(body, [
			[-0.134, 0.271, 0.178, 0.012, 0.046, 126, 172, -0.094],
			[-0.063, 0.359, 0.201, 0.013, 0.046, 103, 177, -0.103],
			[0.023, 0.355, 0.215, 0.013, 0.049, 106, 174, -0.087],
			[0.099, 0.261, 0.190, 0.012, 0.042, 128, 161, -0.049],
		], mat["steel"], mat["frame"], mat["frame"], 0.034, side)
