extends RefCounted
## 几何工具：只负责「往场景里加一块几何」。
## 全部用 Godot 内置图元或 SurfaceTool 生成，不依赖外部模型。

## 所有实心材质走程序化表面 shader（世界坐标噪声：脏污 / 粗糙度抖动 / 法线扰动），
## 这样盒子表面不再是纯色高光塑料感。opts:
##   noise  噪声频率（纸箱细一点，墙面粗一点）
##   grime  脏污量 0..1
##   bump   法线扰动强度 0..1
##   tint   色差 0..1
##   streak 竖向流痕 0..1
##   dirt   脏污颜色
static var _surf: Shader = null

static func _surface() -> Shader:
	if _surf == null:
		_surf = load("res://gfx/warehouse/surface.gdshader")
	return _surf

static func std(color: Color, rough := 0.7, metal := 0.0, opts := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _surface()
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("roughness", clampf(rough, 0.0, 1.0))
	m.set_shader_parameter("metallic", clampf(metal, 0.0, 1.0))
	m.set_shader_parameter("noise_scale", float(opts.get("noise", 1.8)))
	m.set_shader_parameter("grime", float(opts.get("grime", 0.24)))
	# 金属面法线扰动太强会在掠射角炸出高光噪点，默认压低
	var def_bump := 0.30 if metal < 0.3 else 0.10
	m.set_shader_parameter("bump", float(opts.get("bump", def_bump)))
	m.set_shader_parameter("tint_var", float(opts.get("tint", 0.10)))
	m.set_shader_parameter("streak", float(opts.get("streak", 0.0)))
	m.set_shader_parameter("dirt_col", opts.get("dirt", Color(0.05, 0.045, 0.04)))
	return m


static func emissive(color: Color, energy := 4.0, albedo_scale := 0.12) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, 1.0) * albedo_scale
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	m.metallic = 0.0
	return m


static func glass(color: Color, alpha := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = 0.08
	m.metallic = 0.4
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 20
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func cone(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func quad(parent: Node3D, size: Vector2, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var qm := QuadMesh.new()
	qm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func torus(parent: Node3D, radius: float, tube_radius: float, pos: Vector3, mat: Material, rings := 72) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = maxf(radius - tube_radius, 0.01)
	tm.outer_radius = radius + tube_radius
	tm.rings = rings
	tm.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## 两点之间一根圆柱（用作灯管、拉索、管件）。
static func tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return null
	var mi := cylinder(parent, radius, length, (a + b) * 0.5, mat)
	mi.basis = Basis(Quaternion(Vector3.UP, d / length))
	return mi


## 水平圆环（可在贴花、环形车道、围栏基座等地方用）。
static func annulus(parent: Node3D, inner: float, outer: float, segments: int, y: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var i0 := Vector3(cos(a0) * inner, y, sin(a0) * inner)
		var o0 := Vector3(cos(a0) * outer, y, sin(a0) * outer)
		var i1 := Vector3(cos(a1) * inner, y, sin(a1) * inner)
		var o1 := Vector3(cos(a1) * outer, y, sin(a1) * outer)
		# 两个三角形，绕序保证法线朝 +Y
		_annulus_vert(st, i0, a0, inner)
		_annulus_vert(st, o1, a1, outer)
		_annulus_vert(st, o0, a0, outer)
		_annulus_vert(st, i0, a0, inner)
		_annulus_vert(st, i1, a1, inner)
		_annulus_vert(st, o1, a1, outer)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _annulus_vert(st: SurfaceTool, p: Vector3, angle: float, radius: float) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(cos(angle), sin(angle)) * (radius / maxf(radius, 0.001)))
	st.add_vertex(p)


## 一条虚线（沿 x/z 平面），每段是一块薄盒子。
static func dashed_line(parent: Node3D, a: Vector2, b: Vector2, width: float, dash: float, gap: float, y: float, mat: Material) -> void:
	var dir := (b - a)
	var total := dir.length()
	if total < 0.01:
		return
	dir /= total
	var n := int(total / (dash + gap))
	for i in n:
		var s := float(i) * (dash + gap) + dash * 0.5
		var c := a + dir * s
		var center := Vector3(c.x, y, c.y)
		box(parent, Vector3(dash, 0.02, width), center, mat, Vector3(0.0, atan2(dir.y, dir.x), 0.0))


## 从地面斜拉起的一根悬索（分段折线，带一点下垂）。
static func cable(parent: Node3D, a: Vector3, b: Vector3, sag: float, radius: float, mat: Material, segments := 12) -> void:
	var prev := a
	for i in range(1, segments + 1):
		var t := float(i) / float(segments)
		var p := a.lerp(b, t)
		p.y -= sin(PI * t) * sag
		tube(parent, prev, p, radius, mat)
		prev = p
