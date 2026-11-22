extends "res://src/encounter/art.gd"
const HALF_WIDTH := 36.0
const HALF_DEPTH := 36.0
const CEILING := 60.0

static func build() -> Dictionary:
	return new().build_scene()

func build_scene() -> Dictionary:
	root.name = "NeonDistrict"
	configure_city()
	block("floor",Vector3(74,0.6,74),Vector3(0,-0.3,0))
	# Three connected streets: the open avenue and two shopfront flanks.
	for side in [-1.0,1.0]:
		for z in [-27.0,-9.0,9.0,27.0]:
			facade(Vector3(side*38,0,z),Vector3(4,26+absf(z)*0.3,18),side)
		for z in [-27.0,-8.0,14.0,29.0]:
			block("dark",Vector3(0.3,9,0.3),Vector3(side*29,4.5,z))
			block("frame",Vector3(3,0.25,0.5),Vector3(side*28,9,z),false)
			tube("white",Vector3(side*28-1,8.8,z),Vector3(side*28+1,8.8,z))
			downlight(Vector3(side*28,8.7,z),Color("c8d8e5"),4.0,24)
		for z in range(-30,31,6):
			block("warm",Vector3(0.14,0.025,2.2),Vector3(side*6,0.023,z),false,false,0.005)
	for z in [-36.5,36.5]:
		block("wall",Vector3(74,15,1),Vector3(0,7.5,z))
		block("dark",Vector3(12,8,0.4),Vector3(0,4,z-signf(z)*0.7),false)
		for i in 16:
			block("frame",Vector3(11.4,0.28,0.15),Vector3(0,0.4+i*0.46,z-signf(z)*0.94),false)
		tube("amber",Vector3(-6,8.4,z-signf(z)),Vector3(6,8.4,z-signf(z)))
		for x in [-26.0,-16.0,16.0,26.0]:
			block("glass",Vector3(7,7,0.2),Vector3(x,9,z-signf(z)*0.65),false)
			for dx in [-3.4,0.0,3.4]:
				block("metal",Vector3(0.12,7,0.18),Vector3(x+dx,9,z-signf(z)*0.8),false)
	# Service kiosks are closed solids, with vents, canopy thickness and recessed screens.
	for p in [Vector3(-14,0,-10),Vector3(14,0,9)]:
		cabinet(p,Vector3(9,5.8,6),"teal")
		block("dark",Vector3(10,0.4,7),p+Vector3(0,6.1,0))
		for side in [-1.0,1.0]:
			block("glass",Vector3(6,2.8,0.12),p+Vector3(0,3.4,side*3.15),false)
			tube("magenta",p+Vector3(-4,6.34,side*3.35),p+Vector3(4,6.34,side*3.35))
			for j in 4:
				block("cyan",Vector3(1.0+j*0.7,0.055,0.04),p+Vector3(-0.8,2.5+j*0.45,side*3.23),false,false,0.008)
	preload("res://src/encounter/vehicle.gd").new(self).build(Vector3(-15,0,13))
	cabinet(Vector3(15,0,-14),Vector3(6,3.7,5),"warm")
	for p in [Vector3(-28,0,-14),Vector3(28,0,17)]:
		cabinet(p,Vector3(3,3.8,4),"frame")
	for x in [-8.0,8.0]:
		for z in [-28.0,-16.0,16.0,28.0]:
			tube("cyan",Vector3(x,0.07,z-2),Vector3(x,0.07,z+2),0.035)
	# Elevated service bridge and its suspension, above all actor movement.
	block("dark",Vector3(72,1,5),Vector3(0,18,-25))
	for x in range(-32,33,4):
		block("metal",Vector3(0.12,2,0.12),Vector3(x,19.5,-22.8),false)
	tube("magenta",Vector3(-34,20.5,-22.8),Vector3(34,20.5,-22.8),0.06)
	for x in [-24.0,0.0,24.0]:
		tube("white",Vector3(x-4,17.4,-24),Vector3(x+4,17.4,-24))
	for x in [-60.0,-45.0,45.0,60.0]:
		for z in [-60.0,-45.0,45.0,60.0]:
			block("wall",Vector3(10,45+absf(x)*0.25,10),Vector3(x,20,z),false)
			for y in range(10,50,4):
				block("cyan",Vector3(6,0.12,0.12),Vector3(x,y,z+5.1),false,false,0.02)
	var anchors: Array = [Vector3(-6,0,-20),Vector3(6,0,-20),Vector3(-24,0,10),Vector3(24,0,5)]
	for p: Vector3 in anchors:
		neon_ring("magenta",1.5,0.045,48,8,p+Vector3(0,0.06,0))
	street_detail()
	weather()
	environment(true)
	var result := finish("霓虹街区", "3 近战 · 2 远程 · 1 位移 / 掩体绕侧，肃清街区",Vector2(36,36),Vector3(0,0,29),[
		{"kind":"mob","pos":Vector3(0,0,10)}, {"kind":"mob","pos":Vector3(-25,0,-1)},
		{"kind":"mob","pos":Vector3(24,0,-8)}, {"kind":"archer","pos":Vector3(-23,0,-24)},
		{"kind":"archer","pos":Vector3(23,0,-24)}, {"kind":"phase","pad":0}],anchors)
	result["kind"] = "plaza"
	result["vertical"] = false
	return result

func facade(pos: Vector3, size: Vector3, side: float) -> void:
	block("wall",size,pos+Vector3(0,size.y*0.5,0))
	var x := pos.x-side*(size.x*0.5+0.1)
	for y in [2.0,9.0,16.0,23.0,30.0]:
		block("dark",Vector3(0.8,0.5,17.9),Vector3(x,y,pos.z),false)
		for dz in [-5.5,0.0,5.5]:
			block("glass",Vector3(0.14,4.6,4.5),Vector3(x-side*0.15,y+2.7,pos.z+dz),false)
			block("metal",Vector3(0.18,4.8,0.13),Vector3(x-side*0.25,y+2.7,pos.z+dz),false)
			if int(y+dz+pos.z)%3 != 0:
				block("amber",Vector3(0.1,0.08,4.2),Vector3(x-side*0.28,y+4.5,pos.z+dz),false,false,0.01)
	for dz in [-8.5,8.5]:
		block("frame",Vector3(0.6,size.y,0.5),Vector3(x, size.y/2,pos.z+dz),false)
		kit.tube("metal",[Vector3(x-side*0.35,1,pos.z+dz),Vector3(x-side*0.35,20,pos.z+dz)],0.13,12)
	block("dark",Vector3(0.5,1.8,11),Vector3(x-side*0.5,7.3,pos.z),false)
	tube("magenta",Vector3(x-side*0.8,7.3,pos.z-4.8),Vector3(x-side*0.8,7.3,pos.z+4.8))
	for dz in [-4.0,4.0]:
		block("frame",Vector3(1,1.4,2.2),Vector3(x-side*0.45,12,pos.z+dz),false)
		for j in 7:
			block("metal",Vector3(0.12,0.07,1.9),Vector3(x-side,11.5+j*0.15,pos.z+dz),false,false,0.01)

func street_detail() -> void:
	# Repairs and service hardware stay along walls, leaving all three routes open.
	for side in [-1.0,1.0]:
		for z in [-26.0,-8.0,10.0,28.0]:
			var x: float = side*35.1
			for y in [0.7,1.15]:
				kit.tube("metal",[Vector3(x,y,z-6.5),Vector3(x,y,z+6.5)],0.11,12)
			for dz in [-5.0,0.0,5.0]:
				block("dark",Vector3(0.4,0.8,0.16),Vector3(x,0.95,z+dz),false)
				block("panel_rust",Vector3(0.18,1.8,1.2),Vector3(x-side*0.3,2.1,z+dz),false)
				for y in [1.4,2.8]:
					kit.sphere("metal",0.055,8,Vector3(x-side*0.42,y,z+dz-0.4))
			# Bent conduit with a protected end; exposed metal, no free-floating wires.
			kit.tube("dark",[Vector3(x,8,z-7),Vector3(x-side*0.3,6,z-7),Vector3(x-side*0.3,5.7,z-5.5)],0.09,12)
			block("dark",Vector3(0.4,0.6,0.9),Vector3(x,5.6,z-5.3),false)
			# Small fixed debris piles behind the sidewalk collision margin.
			for j in 4:
				kit.push_xf(Transform3D(Basis(Vector3.UP,0.3*j),Vector3(side*35.0,0.12+j*0.04,z+5+j*0.3)))
				kit.box_bevel("frame",Vector3(0.6,0.12,0.45),Vector3.ZERO,0.025)
				kit.pop_xf()
	for p in [Vector3(-14,0,-10),Vector3(14,0,9)]:
		for side in [-1.0,1.0]:
			for x in [-3.8,3.8]:
				block("metal",Vector3(0.12,5.2,0.18),p+Vector3(x,2.9,side*3.15),false)
			maintenance_panel(p+Vector3(2.5,1.25,side*3.17),1.1,0.65,side)
			for j in 6:
				block("panel_rust",Vector3(0.5,0.08,0.06),p+Vector3(-2.0,0.8+j*0.16,side*3.22),false,false,0.01)
		for x in [-3.4,3.4]:
			block("frame",Vector3(1.3,0.45,2.4),p+Vector3(x,6.55,0))
			for j in 10:
				block("metal",Vector3(1.15,0.035,0.08),p+Vector3(x,6.79,-1+j*0.22),false,false,0.01)
	# Road repair panels have real edge thickness; fasteners are below foot clearance.
	for p in [Vector3(-5,0,-9),Vector3(7,0,19),Vector3(0,0,-28)]:
		block("frame",Vector3(3.5,0.035,2.6),p+Vector3(0,0.025,0),false,false,0.01)
		for x in [-1.55,1.55]:
			for z in [-1.1,1.1]:
				kit.cyl("metal",0.055,0.055,0.025,8,p+Vector3(x,0.05,z))
	# Sloping canopy ribs and lower ledges break up the monolithic building fronts.
	for side in [-1.0,1.0]:
		for z in [-27.0,-9.0,9.0,27.0]:
			for dz in [-7.0,-3.5,0.0,3.5,7.0]:
				block("metal",Vector3(0.4,0.08,0.2),Vector3(side*35.0,6.9,z+dz),false)
			block("dark",Vector3(0.7,0.3,15),Vector3(side*35.3,0.25,z),false)
