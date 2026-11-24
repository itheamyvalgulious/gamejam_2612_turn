extends MeshInstance3D
class_name FpVisionMask
## 第三人称「第一人称视野黑幕」（Tab）：第一人称相机看不到的一切 —— 画面外的墙、
## 背后的空间、脚下的地面、天空、以及第一人称下本来就不画的自机 —— 全部涂成纯黑，
## 只留下第一人称真正能看到的画面。
##
## 实现：一块贴在相机前的全屏四边形（顶点直接写 clip 空间，不用跟 FOV 缩放），
## fragment 里用**场景深度**说明这个像素看到的是哪个世界点，再把这个点投进第一人称
## 相机的视锥 —— 见 gfx/fp_vision_mask.gdshader。
##
## 判定与 Vision（零余量视野）同源：GameCam.fp_sees_point() 就是 shader 里那个式子，
## QA 拿它和真相机 is_position_in_frustum() 对照。

const SHADER := preload("res://gfx/fp_vision_mask.gdshader")

var active := false
var _mat: ShaderMaterial


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)          # VERTEX.xy ∈ [-1, 1]，shader 里直接当 clip 空间用
	mesh = q
	# 只影响视锥剔除：顶点位置由 shader 覆盖，但 AABB 得留在视锥里才不会被剔掉
	position = Vector3(0, 0, -0.5)
	extra_cull_margin = 8.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	# 压在世界里的半透明内容（雨幕 / 刀光 / 冲击环）之上：画面外的东西不许透出来
	_mat.render_priority = 100
	material_override = _mat
	visible = false


func set_active(on: bool) -> void:
	active = on
	visible = on


## 每帧：把第一人称视锥（projection * view）交给 shader；soft = 边界柔化
func step(fp_proj_view: Projection, soft := 0.008) -> void:
	if not visible:
		return
	_mat.set_shader_parameter("fp_proj_view", fp_proj_view)
	_mat.set_shader_parameter("edge_soft", clampf(soft, 0.0, 0.25))
