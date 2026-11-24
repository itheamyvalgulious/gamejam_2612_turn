extends RefCounted
## Shared, mip-filtered rolled coating normal map; generated in memory only.
static var cached: ImageTexture
static func texture() -> ImageTexture:
	if cached != null:
		return cached
	const RES := 512
	var pixels := PackedByteArray()
	pixels.resize(RES*RES*3)
	for y in RES:
		var v := float(y)/RES
		for x in RES:
			var u := float(x)/RES
			var dx := 0.055*cos(TAU*64*u)+0.045*sin(TAU*127*u)*sin(TAU*83*v)
			var dy := 0.025*cos(TAU*96*v)+0.04*cos(TAU*83*v)*sin(TAU*127*u)
			var n := Vector3(-dx,-dy,1).normalized()*0.5+Vector3.ONE*0.5
			var i := (y*RES+x)*3
			pixels[i] = int(n.x*255)
			pixels[i+1] = int(n.y*255)
			pixels[i+2] = int(n.z*255)
	var img := Image.create_from_data(RES,RES,false,Image.FORMAT_RGB8,pixels)
	img.generate_mipmaps(true)
	cached = ImageTexture.create_from_image(img)
	return cached
