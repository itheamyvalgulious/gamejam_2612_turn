class_name TextureBank
extends RefCounted

## Loads the pre-baked procedural PBR maps as raw ImageTextures so normal /
## roughness / height maps are not sRGB-decoded.  Albedo maps are decoded
## explicitly in the shader.

static func load_raw(path: String) -> ImageTexture:
	var abs := ProjectSettings.globalize_path(path)
	var img := Image.load_from_file(abs)
	if img == null:
		push_error("TextureBank: cannot load " + abs)
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
