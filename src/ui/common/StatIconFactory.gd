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
		"shield":
			return _build_shield_icon()
		"hp":
			return _build_hp_icon()
		"gold":
			return _build_gold_icon()
		"step":
			return _build_step_icon()
		"time":
			return _build_time_icon()
		"relic":
			return _build_relic_icon()
		"card_owned":
			return _build_card_owned_icon()
		"card_equipped":
			return _build_card_equipped_icon()
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


static func _build_shield_icon() -> Texture2D:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shadow: Color = Color(0.02, 0.10, 0.14, 0.94)
	var blue: Color = Color(0.33, 0.86, 1.0, 1.0)
	var bright: Color = Color(0.82, 1.0, 1.0, 1.0)
	_draw_shield_shape(image, Vector2i(6, 4), shadow)
	_draw_shield_shape(image, Vector2i(4, 2), blue)
	image.fill_rect(Rect2i(29, 14, 6, 32), bright)
	image.fill_rect(Rect2i(17, 25, 30, 5), bright)
	image.fill_rect(Rect2i(20, 48, 24, 4), blue.darkened(0.22))
	return ImageTexture.create_from_image(image)


static func _build_hp_icon() -> Texture2D:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shadow: Color = Color(0.20, 0.02, 0.05, 0.96)
	var red: Color = Color(1.0, 0.22, 0.34, 1.0)
	var bright: Color = Color(1.0, 0.58, 0.64, 1.0)
	image.fill_rect(Rect2i(14, 18, 15, 14), shadow)
	image.fill_rect(Rect2i(35, 18, 15, 14), shadow)
	image.fill_rect(Rect2i(10, 28, 44, 14), shadow)
	image.fill_rect(Rect2i(18, 42, 30, 8), shadow)
	image.fill_rect(Rect2i(16, 15, 14, 14), red)
	image.fill_rect(Rect2i(34, 15, 14, 14), red)
	image.fill_rect(Rect2i(12, 25, 40, 15), red)
	image.fill_rect(Rect2i(20, 40, 24, 8), red.darkened(0.05))
	image.fill_rect(Rect2i(18, 19, 8, 5), bright)
	image.fill_rect(Rect2i(36, 19, 8, 5), bright)
	return ImageTexture.create_from_image(image)


static func _build_gold_icon() -> Texture2D:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shadow: Color = Color(0.20, 0.12, 0.02, 0.95)
	var gold: Color = Color(1.0, 0.76, 0.22, 1.0)
	var bright: Color = Color(1.0, 0.96, 0.50, 1.0)
	image.fill_rect(Rect2i(18, 19, 30, 30), shadow)
	image.fill_rect(Rect2i(14, 25, 38, 18), shadow)
	image.fill_rect(Rect2i(16, 17, 30, 30), gold.darkened(0.04))
	image.fill_rect(Rect2i(12, 23, 38, 18), gold)
	image.fill_rect(Rect2i(20, 21, 20, 5), bright)
	image.fill_rect(Rect2i(18, 42, 28, 4), gold.darkened(0.22))
	return ImageTexture.create_from_image(image)


static func _build_step_icon() -> Texture2D:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shadow: Color = Color(0.03, 0.06, 0.08, 0.94)
	var cyan: Color = Color(0.34, 0.78, 0.96, 1.0)
	var bright: Color = Color(0.84, 1.0, 1.0, 1.0)
	image.fill_rect(Rect2i(13, 43, 40, 9), shadow)
	image.fill_rect(Rect2i(21, 32, 32, 9), shadow)
	image.fill_rect(Rect2i(29, 21, 24, 9), shadow)
	image.fill_rect(Rect2i(37, 10, 16, 9), shadow)
	image.fill_rect(Rect2i(11, 41, 40, 8), cyan.darkened(0.10))
	image.fill_rect(Rect2i(19, 30, 32, 8), cyan)
	image.fill_rect(Rect2i(27, 19, 24, 8), cyan.lightened(0.05))
	image.fill_rect(Rect2i(35, 8, 16, 8), bright)
	return ImageTexture.create_from_image(image)


static func _build_relic_icon() -> Texture2D:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shadow: Color = Color(0.18, 0.10, 0.03, 0.94)
	var amber: Color = Color(1.0, 0.70, 0.24, 1.0)
	var bright: Color = Color(1.0, 0.95, 0.54, 1.0)
	_draw_diamond(image, Vector2i(33, 34), 25, shadow)
	_draw_diamond(image, Vector2i(31, 32), 25, amber)
	_draw_diamond(image, Vector2i(31, 30), 12, bright)
	image.fill_rect(Rect2i(29, 12, 4, 39), amber.darkened(0.24))
	image.fill_rect(Rect2i(14, 30, 35, 4), bright)
	return ImageTexture.create_from_image(image)


static func _build_time_icon() -> Texture2D:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shadow: Color = Color(0.03, 0.05, 0.09, 0.94)
	var blue: Color = Color(0.38, 0.78, 1.0, 1.0)
	var bright: Color = Color(0.86, 1.0, 1.0, 1.0)
	_draw_diamond(image, Vector2i(34, 34), 27, shadow)
	_draw_diamond(image, Vector2i(32, 32), 26, blue.darkened(0.08))
	_draw_diamond(image, Vector2i(32, 32), 20, Color(0.04, 0.10, 0.16, 0.92))
	image.fill_rect(Rect2i(30, 14, 5, 20), bright)
	image.fill_rect(Rect2i(32, 30, 16, 5), bright)
	image.fill_rect(Rect2i(18, 30, 9, 4), blue)
	image.fill_rect(Rect2i(37, 44, 8, 4), blue)
	return ImageTexture.create_from_image(image)


static func _build_card_owned_icon() -> Texture2D:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shadow: Color = Color(0.02, 0.04, 0.08, 0.95)
	var blue: Color = Color(0.24, 0.66, 1.0, 1.0)
	var bright: Color = Color(0.78, 0.94, 1.0, 1.0)
	image.fill_rect(Rect2i(19, 11, 28, 40), shadow)
	image.fill_rect(Rect2i(14, 16, 28, 40), blue.darkened(0.18))
	image.fill_rect(Rect2i(20, 10, 28, 40), blue)
	image.fill_rect(Rect2i(24, 15, 20, 6), bright)
	image.fill_rect(Rect2i(24, 26, 20, 4), bright.darkened(0.08))
	image.fill_rect(Rect2i(24, 36, 16, 4), bright.darkened(0.18))
	return ImageTexture.create_from_image(image)


static func _build_card_equipped_icon() -> Texture2D:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shadow: Color = Color(0.04, 0.07, 0.05, 0.95)
	var green: Color = Color(0.28, 0.92, 0.52, 1.0)
	var bright: Color = Color(0.84, 1.0, 0.78, 1.0)
	image.fill_rect(Rect2i(17, 12, 30, 40), shadow)
	image.fill_rect(Rect2i(15, 10, 30, 40), green.darkened(0.12))
	image.fill_rect(Rect2i(20, 16, 20, 6), bright)
	image.fill_rect(Rect2i(20, 28, 20, 4), bright.darkened(0.10))
	image.fill_rect(Rect2i(26, 38, 8, 8), shadow)
	image.fill_rect(Rect2i(38, 37, 14, 7), shadow)
	image.fill_rect(Rect2i(25, 35, 8, 8), green)
	image.fill_rect(Rect2i(33, 39, 16, 5), green)
	return ImageTexture.create_from_image(image)


static func _draw_shield_shape(image: Image, origin: Vector2i, color: Color) -> void:
	image.fill_rect(Rect2i(origin.x + 12, origin.y + 10, 40, 8), color)
	image.fill_rect(Rect2i(origin.x + 10, origin.y + 18, 44, 14), color)
	image.fill_rect(Rect2i(origin.x + 14, origin.y + 32, 36, 8), color)
	image.fill_rect(Rect2i(origin.x + 20, origin.y + 40, 24, 8), color)
	image.fill_rect(Rect2i(origin.x + 27, origin.y + 48, 10, 6), color)


static func _draw_diamond(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	for y in range(-radius, radius + 1):
		var half_width: int = radius - abs(y)
		image.fill_rect(Rect2i(center.x - half_width, center.y + y, half_width * 2 + 1, 1), color)


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
