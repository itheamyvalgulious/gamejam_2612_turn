extends RefCounted
## Cargo Hold2 container geometry, adapted from SSV ORION props.gd.
var kit: CargoMeshKit
var refined_cargo := true
func _init(k: CargoMeshKit) -> void:
	kit = k

func container(origin: Vector3, key: String = "container_a", yaw: float = 0.0,
		size: Vector3 = Vector3(6.1, 2.6, 2.44)) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.UP, yaw), origin))
	kit.begin_part(0.33, 24.0)
	kit.set_height_range(0.0, size.y)
	kit.box("metal_dark", size - Vector3.ONE * 0.10, Vector3(0, size.y * 0.5, 0))
	kit.box_bevel(key, size, Vector3(0, size.y * 0.5, 0), 0.045)
	if refined_cargo:
		# Corrugation comes from a tangent-space normal texture; retain structural frames.
		for side in [-1.0, 1.0]:
			for yy in [0.12, size.y - 0.12]:
				kit.box_bevel("orion_frame", Vector3(size.x, 0.16, 0.14), Vector3(0, yy, side * size.z * 0.5), 0.025)
	# corner castings
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			for sy in [0.0, 1.0]:
				kit.box("metal_dark", Vector3(0.24, 0.28, 0.24),
					Vector3(sx * (size.x * 0.5 - 0.09), 0.14 + sy * (size.y - 0.28), sz * (size.z * 0.5 - 0.09)))
	# door bars on one end
	for k in 3:
		kit.box("metal", Vector3(0.06, size.y * 0.82, 0.07),
			Vector3(size.x * 0.5 + 0.03, size.y * 0.5, -0.6 + k * 0.6))
	# Raised structural ribs, backed by a closed shell and solid inner core.
	for side in [-1.0, 1.0]:
		for i in 7:
			var xx := -size.x*0.5 + 0.65 + i*(size.x-1.3)/6.0
			kit.box_bevel(key, Vector3(0.16,size.y-0.6,0.16), Vector3(xx,size.y*0.5,side*(size.z*0.5+0.025)),0.035)
		for xx in [-size.x*0.5+0.2,size.x*0.5-0.2]:
			kit.box_bevel("orion_frame",Vector3(0.24,size.y-0.3,0.22),Vector3(xx,size.y*0.5,side*(size.z*0.5)),0.04)
			for yy in [0.4,1.7,4.3,size.y-0.4]:
				kit.box_bevel("metal",Vector3(0.10,0.10,0.055),Vector3(xx,yy,side*(size.z*0.5+0.13)),0.018)
		# Both ends have thick double doors, external locks and hinge blocks.
		for half in [-1.0,1.0]:
			var zz: float = half*size.z*0.245
			kit.box_bevel(key,Vector3(0.12,size.y-0.4,size.z*0.47),Vector3(side*(size.x*0.5+0.025),size.y*0.5,zz),0.035)
			kit.box_bevel("metal",Vector3(0.09,size.y-1.0,0.10),Vector3(side*(size.x*0.5+0.13),size.y*0.5,zz),0.025)
			for yy in [0.8,size.y-0.8]:
				kit.box_bevel("orion_frame",Vector3(0.18,0.25,0.42),Vector3(side*(size.x*0.5+0.13),yy,zz),0.04)
			kit.box_bevel("metal_dark",Vector3(0.16,0.14,0.65),Vector3(side*(size.x*0.5+0.14),2.6,zz),0.035)
		kit.box("cyan",Vector3(0.045,0.1,0.55),Vector3(side*(size.x*0.5+0.24),size.y-0.55,0))
	kit.pop_xf()
