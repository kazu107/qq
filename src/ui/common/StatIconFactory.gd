extends RefCounted
class_name StatIconFactory

static var _texture_cache: Dictionary = {}


static func get_icon(stat_id: String) -> Texture2D:
	if _texture_cache.has(stat_id):
		return _texture_cache[stat_id] as Texture2D

	var texture: Texture2D = _build_icon(stat_id)
	_texture_cache[stat_id] = texture
	return texture


static func _build_icon(stat_id: String) -> Texture2D:
	match stat_id:
		"attack":
			return _build_attack_icon()
		"speed":
			return _build_speed_icon()
		_:
			return _build_generic_icon(stat_id)


static func _build_attack_icon() -> Texture2D:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shadow: Color = Color(0.18, 0.08, 0.02, 0.95)
	var gold: Color = Color(1.0, 0.68, 0.18, 1.0)
	var bright: Color = Color(1.0, 0.92, 0.38, 1.0)
	image.fill_rect(Rect2i(28, 8, 8, 44), shadow)
	image.fill_rect(Rect2i(12, 26, 40, 8), shadow)
	image.fill_rect(Rect2i(30, 6, 6, 44), gold)
	image.fill_rect(Rect2i(13, 28, 39, 6), gold)
	image.fill_rect(Rect2i(24, 10, 18, 8), bright)
	image.fill_rect(Rect2i(44, 20, 10, 22), bright)
	image.fill_rect(Rect2i(20, 42, 24, 8), shadow)
	return ImageTexture.create_from_image(image)


static func _build_speed_icon() -> Texture2D:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shadow: Color = Color(0.02, 0.12, 0.18, 0.92)
	var cyan: Color = Color(0.28, 0.88, 1.0, 1.0)
	var bright: Color = Color(0.75, 1.0, 1.0, 1.0)
	_draw_chevron(image, Vector2i(10, 18), shadow)
	_draw_chevron(image, Vector2i(24, 18), shadow)
	_draw_chevron(image, Vector2i(8, 16), cyan)
	_draw_chevron(image, Vector2i(22, 16), bright)
	image.fill_rect(Rect2i(12, 42, 34, 5), cyan.darkened(0.15))
	image.fill_rect(Rect2i(22, 49, 24, 4), bright)
	return ImageTexture.create_from_image(image)


static func _draw_chevron(image: Image, origin: Vector2i, color: Color) -> void:
	for offset in range(16):
		var width: int = maxi(2, 16 - abs(offset - 8))
		image.fill_rect(Rect2i(origin.x + offset, origin.y + offset, width, 4), color)
		image.fill_rect(Rect2i(origin.x + offset, origin.y + 32 - offset, width, 4), color)


static func _build_generic_icon(stat_id: String) -> Texture2D:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var hue: float = float(abs(stat_id.hash()) % 1000) / 1000.0
	var base_color: Color = Color.from_hsv(hue, 0.58, 0.82, 1.0)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	image.fill_rect(Rect2i(10, 10, 44, 44), base_color.darkened(0.22))
	image.fill_rect(Rect2i(18, 18, 28, 28), base_color.lightened(0.18))
	return ImageTexture.create_from_image(image)
