extends "res://src/encounter/art.gd"
const HALF_WIDTH := 36.0
const HALF_DEPTH := 32.0
const CEILING := 25.0

static func build() -> Dictionary:
	return new().build_scene()

func build_scene() -> Dictionary:
	root.name = "GalleriaAtrium"
	block("floor",Vector3(74,0.6,66),Vector3(0,-0.3,0))
	block("dark",Vector3(74,0.7,66),Vector3(0,25.35,0))
	for x in [-36.5,36.5]:
		block("wall",Vector3(1,25,66),Vector3(x,12.5,0))
	for z in [-32.5,32.5]:
		block("wall",Vector3(74,25,1),Vector3(0,12.5,z))
	# Back-wall entrance and layered upper glazing give the atrium a commercial scale.
	for x in [-26.0,-13.0,0.0,13.0,26.0]:
		block("frame",Vector3(10.8,10,0.5),Vector3(x,6,-31.7),false)
		block("glass",Vector3(10.1,8.8,0.18),Vector3(x,5.7,-31.37),false)
		for dx in [-4.8,0.0,4.8]:
			block("metal",Vector3(0.12,9,0.14),Vector3(x+dx,5.7,-31.2),false)
		tube("magenta",Vector3(x-4.8,10.8,-31.1),Vector3(x+4.8,10.8,-31.1))
		for y in [15.0,21.0]:
			block("glass",Vector3(10,3.8,0.22),Vector3(x,y,-31.7),false)
			block("metal",Vector3(10.5,0.18,0.35),Vector3(x,y-2,-31.4),false)
			for dx in [-4.9,0.0,4.9]:
				block("frame",Vector3(0.18,4,0.3),Vector3(x+dx,y,-31.4),false)
	for side in [-1.0,1.0]:
		block("frame",Vector3(2.6,0.55,62),Vector3(side*34.5,11.6,0))
		for z in range(-28,29,4):
			block("metal",Vector3(0.13,1.4,0.13),Vector3(side*33.3,12.55,z),false)
		kit.tube("metal",[Vector3(side*33.3,13.25,-30),Vector3(side*33.3,13.25,30)],0.07,12)
		for z in [-23.0,-6.0,11.0]:
			block("glass",Vector3(0.18,6,13),Vector3(side*35.8,17,z),false)
			for dz in [-6.0,0.0,6.0]:
				block("frame",Vector3(0.3,6.2,0.2),Vector3(side*35.6,17,z+dz),false)
	# High entry deck, solid underside, and an open attack ledge at the center.
	block("frame",Vector3(28,0.6,12),Vector3(0,7.7,23),true,true)
	block("frame",Vector3(18,0.6,11),Vector3(23,7.7,23.5),true,true)
	for x in [-12.0,12.0]:
		block("dark",Vector3(0.7,7.4,0.7),Vector3(x,3.7,27))
	for x in [-11.0,11.0]:
		block("dark",Vector3(6,1.2,0.3),Vector3(x,8.6,17.1))
		tube("white",Vector3(x-2.8,9.25,17.1),Vector3(x+2.8,9.25,17.1),0.045)
	block("dark",Vector3(0.3,1.2,12),Vector3(-14,8.6,23))
	tube("cyan",Vector3(-7.8,8.06,17.05),Vector3(7.8,8.06,17.05),0.055)
	for x in [-5.0,0.0,5.0]:
		for z in [18.0,20.0]:
			neon_path("cyan",[Vector3(x-0.5,8.04,z+0.4),Vector3(x,8.04,z),Vector3(x+0.5,8.04,z+0.4)],0.025)
	# 28 shallow solid treads form the return route; same boxes drive support and collision.
	for i in 28:
		var h := (i+1)*8.0/28.0
		var z := -9.5+i
		block("frame",Vector3(6,h,1),Vector3(29,h*0.5,z),true,true,0.02)
		block("metal",Vector3(5.8,0.025,0.09),Vector3(29,h+0.014,z-0.43),false,false,0.005)
		if i%4 == 0:
			for x in [26.35,31.65]:
				block("cyan",Vector3(0.15,0.03,0.65),Vector3(x,h+0.018,z),false,false,0.008)
	for x in [25.8,32.2]:
		for i in range(0,29,4):
			block("metal",Vector3(0.14,1.2,0.14),Vector3(x,0.6+i*8.0/28.0,-10+i),false)
		kit.tube("metal",[Vector3(x,1.25,-10),Vector3(x,9.25,18)],0.07,12)
		# Continuous thin guard volumes prevent slipping off the narrow stair edge.
		for i in 28:
			var h := (i+1)*8.0/28.0
			block("dark",Vector3(0.18,1.0,1),Vector3(x,h+0.5,-9.5+i))
	block("dark",Vector3(0.25,1.2,11),Vector3(32.2,8.6,23.5))
	for x in [-21.0,20.0]:
		for z in [-24.0,-7.0,11.0]:
			block("frame",Vector3(1.6,24.6,1.6),Vector3(x,12.3,z))
			block("metal",Vector3(2,0.35,2),Vector3(x,0.18,z))
			block("metal",Vector3(2,0.35,2),Vector3(x,23.7,z),false)
			tube("cyan",Vector3(x-signf(x)*0.85,5,z),Vector3(x-signf(x)*0.85,12,z))
	for z in [-25.0,-8.0,9.0,24.0]:
		block("frame",Vector3(72,0.7,0.65),Vector3(0,24,z))
		for x in [-16.0,0.0,16.0]:
			tube("white",Vector3(x-4,21,z),Vector3(x+4,21,z),0.075)
			for dx in [-4.0,4.0]:
				kit.tube("metal",[Vector3(x+dx,21.1,z),Vector3(x+dx,24,z)],0.035,8)
	for x in [-12.0,12.0]:
		for z in [-15.0,2.0,19.0]:
			block("glass",Vector3(20,0.2,14),Vector3(x,24.9,z),false)
	# Recessed shop fronts use backed glazing, mullions, plinths and illuminated fascias.
	for side in [-1.0,1.0]:
		for z in [-23.0,-6.0,11.0]:
			var x: float = side*35.7
			block("dark",Vector3(0.5,9,13),Vector3(x,4.5,z),false)
			block("glass",Vector3(0.18,6.8,11.8),Vector3(x-side*0.35,4.1,z),false)
			for dz in [-5.8,0.0,5.8]:
				block("metal",Vector3(0.24,7.2,0.14),Vector3(x-side*0.5,4.2,z+dz),false)
			tube("magenta",Vector3(x-side*0.65,8.6,z-5.8),Vector3(x-side*0.65,8.6,z+5.8))
			block("warm",Vector3(0.6,0.5,13),Vector3(x-side*0.25,0.3,z),false)
	# Sculptural display covers are fully solid, with a clear cross aisle between them.
	for p in [Vector3(-11,0,-5),Vector3(11,0,-7),Vector3(-11,0,10)]:
		cabinet(p,Vector3(5,2.8,4),"warm")
		block("glass",Vector3(4.7,0.22,3.7),p+Vector3(0,2.97,0),false)
		tube("amber",p+Vector3(-2,3.12,0),p+Vector3(2,3.12,0),0.04)
	# Focal installation is behind the fighting circle, not on the landing trajectory.
	block("dark",Vector3(6,1.1,5),Vector3(0,0.55,-24))
	block("ceramic",Vector3(1.8,8,1.8),Vector3(0,5,-24))
	for y in [3.0,5.0,7.0,9.0]:
		solid_box(Vector3(0,y,-24),Vector3(4.6,0.22,4.6))
		kit.torus("metal",2.2,0.09,64,12,Vector3(0,y,-24))
		neon_ring("cyan",2.08,0.025,64,8,Vector3(0,y,-24))
	for p in [Vector3(0,20.8,24),Vector3(-16,20.8,-8),Vector3(16,20.8,9)]:
		downlight(p,Color("d4dce6"),6.5,32)
	for radius in [3.5,5.5]:
		neon_ring("cyan",radius,0.028,96,8,Vector3(0,0.055,8))
	for x in [-17.0,17.0]:
		for z in [-17.0,0.0]:
			tube("cyan",Vector3(x,0.055,z-4),Vector3(x,0.055,z+4),0.03)
	interior_detail()
	environment()
	var result := finish("GALLERIA · 坠击中庭", "高台跃下 → 空中左键坠击 / 4 近战 + 2 远程 / 右侧阶梯可返回",Vector2(36,32),Vector3(0,8,25),[
		{"kind":"mob","pos":Vector3(0,0,10)}, {"kind":"mob","pos":Vector3(-6,0,5)},
		{"kind":"mob","pos":Vector3(7,0,2)}, {"kind":"mob","pos":Vector3(0,0,-12)},
		{"kind":"archer","pos":Vector3(-16,0,-20)}, {"kind":"archer","pos":Vector3(16,0,-20)}])
	result["vertical"] = true
	return result
