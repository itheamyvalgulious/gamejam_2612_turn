extends Node
## 船坞二阶段灯光：关掉常规灯，只留东门投影墙的一盏投影灯 + 微弱环境光。
##
## 场景侧只负责“能不能切”和“切完什么样”；什么时候切由 Boss 流程决定。
## 用法：`arena["phase2"].set_phase2(true)`（arena 字典里返回的就是本节点）。

var aux_lights: Array = []
var aux_meshes: Array = []
var key_spot: SpotLight3D
var env: Environment
var normal_ambient := 0.40
var phase2_ambient := 0.09
var active := false


func setup(lights: Array, meshes: Array, spot: SpotLight3D, environment: Environment) -> void:
	aux_lights = lights
	aux_meshes = meshes
	key_spot = spot
	env = environment
	if env != null:
		normal_ambient = env.ambient_light_energy
	key_spot.visible = false


func set_phase2(on: bool) -> void:
	active = on
	for l in aux_lights:
		if is_instance_valid(l):
			l.visible = not on
	for m in aux_meshes:
		if is_instance_valid(m):
			m.visible = not on
	if is_instance_valid(key_spot):
		key_spot.visible = on
	if env != null:
		env.ambient_light_energy = phase2_ambient if on else normal_ambient
