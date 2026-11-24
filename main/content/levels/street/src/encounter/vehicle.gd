extends RefCounted
## Layered armored utility vehicle. Body, wheels and protrusions share one envelope.
var art
var kit
func _init(builder) -> void:
	art = builder
	kit = builder.kit

func build(pos: Vector3) -> void:
	art.solid_box(pos+Vector3(0,1.5875,0),Vector3(5.5,2.475,9.9))
	art.solid_box(pos+Vector3(0,3.53,-1.4),Vector3(4.5,1.8,4.65))
	art.solid_box(pos+Vector3(0,3.275,2.3),Vector3(3.65,0.95,3.2))
	art.solid_box(pos+Vector3(0,4.63,-1.5),Vector3(0.92,0.4,0.92))
	art.solid_box(pos+Vector3(1.65,4.9,0.1),Vector3(0.08,1.0,0.08))
	part("dark",Vector3(4.6,0.65,8.7),pos+Vector3(0,0.75,0))
	part("panel_rust",Vector3(5.0,1.6,9.0),pos+Vector3(0,1.85,0))
	part("frame",Vector3(4.65,0.25,8.8),pos+Vector3(0,2.7,0))
	part("panel_rust",Vector3(4.25,1.65,4.4),pos+Vector3(0,3.45,-1.4))
	part("dark",Vector3(4.5,0.18,4.65),pos+Vector3(0,4.34,-1.4))
	# Angled windshield with opaque backing and real frame thickness.
	kit.push_xf(Transform3D(Basis(Vector3.RIGHT,-0.17),pos+Vector3(0,3.5,-3.64)))
	kit.box_bevel("glass",Vector3(3.78,1.15,0.14),Vector3.ZERO,0.04)
	for x in [-1.95,0.0,1.95]:
		kit.box_bevel("metal",Vector3(0.09,1.3,0.18),Vector3(x,0,-0.035),0.015)
	kit.pop_xf()
	for side in [-1.0,1.0]:
		art.solid_box(pos+Vector3(side*2.35,3.0,-3.5),Vector3(0.45,0.4,0.65))
		for z in [-2.85,2.85]:
			art.solid_box(pos+Vector3(side*2.9,1.12,z),Vector3(0.9,2.24,2.3))
			wheel(pos+Vector3(side*2.45,1.12,z),side)
			part("frame",Vector3(0.48,0.3,2.55),pos+Vector3(side*2.65,2.35,z))
		for z in [-2.2,-0.55]:
			part("glass",Vector3(0.11,0.85,1.3),pos+Vector3(side*2.18,3.58,z))
			part("metal",Vector3(0.15,0.065,1.4),pos+Vector3(side*2.21,3.1,z))
			part("dark",Vector3(0.12,0.12,0.46),pos+Vector3(side*2.25,2.9,z+0.25))
		for z in [-3.8,-1.3,1.2,3.7]:
			part("panel_rust",Vector3(0.16,0.9,1.8),pos+Vector3(side*2.56,1.9,z))
			for dz in [-0.68,0.68]:
				for y in [1.6,2.2]:
					kit.sphere("metal",0.055,8,pos+Vector3(side*2.68,y,z+dz))
			part("dark",Vector3(0.12,0.2,0.32),pos+Vector3(side*2.68,1.9,z))
		# Steps, cable conduits, front sensor pod and side marker housing.
		part("dark",Vector3(0.55,0.14,2.0),pos+Vector3(side*2.67,0.62,-0.4))
		kit.tube("metal",[pos+Vector3(side*2.56,1.15,-1.5),pos+Vector3(side*2.56,1.15,1.7)],0.075,12)
		part("dark",Vector3(0.45,0.4,0.65),pos+Vector3(side*2.35,3.0,-3.5))
		art.tube("amber",pos+Vector3(side*2.71,1.9,-0.6),pos+Vector3(side*2.71,1.9,0.2),0.025,false)
	# Removable rear power pack: inset radiator fins and protective metal cage.
	part("dark",Vector3(3.65,0.9,3.2),pos+Vector3(0,3.25,2.3))
	for i in 15:
		part("metal",Vector3(3.3,0.09,0.075),pos+Vector3(0,3.73,0.9+i*0.2))
	for x in [-1.75,1.75]:
		kit.tube("metal",[pos+Vector3(x,2.8,0.6),pos+Vector3(x,4.05,0.6),pos+Vector3(x,4.05,4),pos+Vector3(x,2.8,4)],0.095,12)
	for z in [-4.63,4.63]:
		part("dark",Vector3(5.2,0.4,0.3),pos+Vector3(0,1.0,z))
		for x in [-2.0,2.0]:
			part("metal",Vector3(0.28,0.42,0.32),pos+Vector3(x,1.0,z+signf(z)*0.13))
	for x in [-1.65,1.65]:
		part("dark",Vector3(1.25,0.42,0.2),pos+Vector3(x,2.12,-4.58))
		art.tube("white",pos+Vector3(x-0.5,2.12,-4.72),pos+Vector3(x+0.5,2.12,-4.72),0.055,false)
		art.tube("magenta",pos+Vector3(x-0.5,1.95,4.65),pos+Vector3(x+0.5,1.95,4.65),0.055)
		var headlamp := SpotLight3D.new()
		art.root.add_child(headlamp)
		headlamp.position = pos+Vector3(x,2.1,-4.8)
		headlamp.rotation_degrees.x = -12
		headlamp.light_color = Color("c4d9e9")
		headlamp.light_energy = 2.0
		headlamp.spot_range = 15
		headlamp.spot_angle = 38
		headlamp.spot_attenuation = 1.8
		headlamp.shadow_enabled = true
	# Sensor mast and protective antenna, attached to the closed roof.
	kit.cyl("dark",0.46,0.42,0.22,24,pos+Vector3(0,4.43,-1.5))
	kit.cyl("metal",0.32,0.32,0.18,24,pos+Vector3(0,4.65,-1.5))
	art.neon_ring("cyan",0.32,0.025,32,8,pos+Vector3(0,4.79,-1.5))
	kit.tube("metal",[pos+Vector3(1.65,4.4,0.1),pos+Vector3(1.65,5.4,0.1)],0.027,8)
	for x in [-1.7,1.7]:
		for z in [-3.3,0.4]:
			kit.cyl("metal",0.07,0.07,0.05,8,pos+Vector3(x,4.43,z))

func part(key: String, size: Vector3, pos: Vector3) -> void:
	art.block(key,size,pos,false,false,0.08)

func wheel(pos: Vector3, side: float) -> void:
	kit.push_xf(Transform3D(Basis(Quaternion(Vector3.UP,Vector3(side,0,0))),pos))
	kit.cyl("rubber",1.08,1.08,0.68,40,Vector3.ZERO)
	kit.torus("rubber",0.85,0.20,40,10,Vector3(0,0.68,0))
	kit.cyl("frame",0.66,0.66,0.075,24,Vector3(0,0.68,0))
	kit.cyl("metal",0.28,0.28,0.09,16,Vector3(0,0.76,0))
	for i in 10:
		var angle := TAU*i/10.0
		kit.cyl("metal",0.055,0.055,0.04,6,Vector3(cos(angle)*0.48,0.77,sin(angle)*0.48))
	for i in 32:
		var angle := TAU*i/32.0
		kit.push_xf(Transform3D(Basis(Vector3.UP,-angle),Vector3(cos(angle)*1.06,0.32,sin(angle)*1.06)))
		kit.box_bevel("rubber",Vector3(0.12,0.62,0.1),Vector3.ZERO,0.02)
		kit.pop_xf()
	kit.pop_xf()
