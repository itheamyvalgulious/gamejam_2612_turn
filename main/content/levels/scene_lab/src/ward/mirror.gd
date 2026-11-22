extends Node3D
## 病房西墙的平面镜（纯代码，无外部资源）。
##
## 做法：把主相机按镜面反射一次，用这个「镜像相机」把房间渲进 SubViewport，
## 再用投影纹理贴回镜面四边形（见 mirror.gdshader）。
##   * 镜子自己 + 挂着镜子的那面墙不参与反射渲染（layer 3），否则镜像相机会被墙挡住；
##   * 镜像相机与主相机共用同一个 World3D，所以看到的确实是当前场景。

const MIRROR_SHADER := preload("res://gfx/ward/mirror.gdshader")
const NO_MIRROR_LAYER := 3          # 这一层的物体不进入镜子

var quad: MeshInstance3D
var vp: SubViewport
var cam: Camera3D
var mat: ShaderMaterial
var _main: Camera3D
var _world_linked := false


## w / h 是世界单位（u）下的镜面尺寸。
func setup(w: float, h: float, res := Vector2i(640, 360)) -> void:
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)

	quad = MeshInstance3D.new()
	quad.name = "MirrorSurface"
	quad.mesh = qm
	quad.layers = 1 << NO_MIRROR_LAYER
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat = ShaderMaterial.new()
	mat.shader = MIRROR_SHADER
	quad.material_override = mat
	add_child(quad)

	vp = SubViewport.new()
	vp.name = "MirrorViewport"
	vp.size = res
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)

	cam = Camera3D.new()
	cam.name = "MirrorCam"
	cam.near = 0.12
	cam.far = 320.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.cull_mask = 0xFFFFF & ~(1 << NO_MIRROR_LAYER)
	vp.add_child(cam)
	cam.current = true

	mat.set_shader_parameter("mirror_tex", vp.get_texture())
	mat.set_shader_parameter("mirror_matrix", Projection.IDENTITY)


func _process(_dt: float) -> void:
	if vp == null:
		return
	var host := get_viewport()
	if host == null:
		return
	if not _world_linked:
		vp.world_3d = host.world_3d
		_world_linked = true
	if _main == null or not is_instance_valid(_main):
		_main = host.get_camera_3d()
		if _main == null:
			return

	var n: Vector3 = (global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var origin: Vector3 = global_position
	var cx: Transform3D = _main.global_transform

	# 相机位置与朝向同时按镜面反射
	var o2: Vector3 = cx.origin - 2.0 * n * n.dot(cx.origin - origin)
	var f: Vector3 = -cx.basis.z
	var u: Vector3 = cx.basis.y
	var f2: Vector3 = (f - 2.0 * n * n.dot(f)).normalized()
	var u2: Vector3 = (u - 2.0 * n * n.dot(u)).normalized()

	cam.fov = _main.fov
	cam.near = _main.near
	cam.global_transform = Transform3D(Basis.looking_at(f2, u2), o2)
	mat.set_shader_parameter("mirror_matrix",
		cam.get_camera_projection() * Projection(cam.global_transform.affine_inverse()))
