extends RefCounted
## Seamless tangent-space normal texture, generated once and shared by all crates.
## Four corrugations per 1.12 m tile; no external bitmap or test artifact required.
static var cached: ImageTexture

static func texture() -> ImageTexture:
	if cached != null:
		return cached
	const RES := 512
	var pixels := PackedByteArray()
	pixels.resize(RES * RES * 3)
	for y in RES:
		var v := float(y) / RES
		for x in RES:
			var u := float(x) / RES
			# Smooth pressed ribs plus finer rolled-metal grooves and shallow dents.
			var dx := 0.68*cos(TAU*4*u) + 0.055*cos(TAU*8*u)
			dx += 0.018*cos(TAU*64*u)*sin(TAU*3*v)
			var dy := 0.012*sin(TAU*32*v) + 0.025*sin(TAU*7*u)*cos(TAU*5*v)
			var n := Vector3(-dx,-dy,1).normalized()*0.5 + Vector3.ONE*0.5
			var index := (y*RES+x)*3
			pixels[index] = int(n.x*255)
			pixels[index+1] = int(n.y*255)
			pixels[index+2] = int(n.z*255)
	var img := Image.create_from_data(RES,RES,false,Image.FORMAT_RGB8,pixels)
	img.generate_mipmaps(true)
	cached = ImageTexture.create_from_image(img)
	return cached
