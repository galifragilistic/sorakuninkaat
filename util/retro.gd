class_name Retro
extends RefCounted
## The retro graphics style (Settings.graphics_style): helpers that make the
## 3D views, menu previews and ground materials follow it.

const STYLE: RetroStyle = preload("res://env/retro_style.tres")
const PICTURE_SHADER: Shader = preload("res://ui/shaders/retro_picture.gdshader")

## Shader -> its copy that samples textures without filtering.
static var _nearest_shaders: Dictionary = {}
## Texture -> its shrunken copy.
static var _small_textures: Dictionary = {}
static var _picture_material: ShaderMaterial


static func is_on() -> bool:
	return Settings.graphics_style == Settings.GraphicsStyle.RETRO


## The whole window in the retro style: menus and HUD are drawn at their
## 1280x720 design resolution and scaled up with sharp pixels, and the fonts
## lose their smoothing. The modern style draws them at the screen's own
## resolution.
static func apply_window(window: Window) -> void:
	var on: bool = is_on()
	window.content_scale_mode = (
		Window.CONTENT_SCALE_MODE_VIEWPORT if on else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	)
	var antialiasing: TextServer.FontAntialiasing = (
		TextServer.FONT_ANTIALIASING_NONE if on else TextServer.FONT_ANTIALIASING_GRAY
	)
	for font: FontFile in UiStyle.ALL_FONTS:
		font.antialiasing = antialiasing


## Size of the 3D picture rendered for a view ui_size big (in UI units).
static func get_render_size(ui_size: Vector2) -> Vector2i:
	var pixels: Vector2 = (ui_size / STYLE.pixel_size).round()
	return Vector2i(maxi(2, int(pixels.x)), maxi(2, int(pixels.y)))


## Shows a view's picture with sharp, dithered pixels, or smoothly as before.
static func style_picture(picture: TextureRect, on: bool) -> void:
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if on else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	picture.material = _get_picture_material() if on else null


## In the retro style, a copy of the shader that samples without filtering.
static func shader(original: Shader) -> Shader:
	if not is_on():
		return original
	if not _nearest_shaders.has(original):
		var copy: Shader = Shader.new()
		copy.code = original.code.replace("filter_linear_mipmap", "filter_nearest_mipmap")
		_nearest_shaders[original] = copy
	return _nearest_shaders[original]


## In the retro style, a small blocky copy of the texture.
static func texture(original: Texture2D) -> Texture2D:
	if not is_on() or original == null:
		return original
	if not _small_textures.has(original):
		var image: Image = original.get_image().duplicate() as Image
		if image.is_compressed():
			image.decompress()
		image.resize(STYLE.texture_size, STYLE.texture_size, Image.INTERPOLATE_BILINEAR)
		image.generate_mipmaps()
		_small_textures[original] = ImageTexture.create_from_image(image)
	return _small_textures[original]


static func _get_picture_material() -> ShaderMaterial:
	if _picture_material == null:
		_picture_material = ShaderMaterial.new()
		_picture_material.shader = PICTURE_SHADER
		_picture_material.set_shader_parameter("levels", float((1 << STYLE.color_bits) - 1))
		_picture_material.set_shader_parameter("dither_strength", STYLE.dither_strength)
	return _picture_material
