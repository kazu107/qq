extends RefCounted
class_name CardEffectIconFactory

const STATUS_ICON_PATH_TEMPLATE := "res://assets/icons/status/%s.png"

static var _texture_cache: Dictionary = {}


static func warm_cache(status_ids: Array[String] = []) -> int:
	var icon_ids: Array[String] = [
		"attack",
		"shield",
		"shield_spend",
		"hp",
		"speed",
		"time",
		"delay",
		"haste",
		"recast",
		"interrupt",
		"cleanse",
		"empower",
		"auto_queue",
		"timeline_stop",
		"timeline_reverse",
		"status",
		"effect",
	]
	for status_id in status_ids:
		if status_id != "":
			icon_ids.append("status:%s" % status_id)

	for icon_id in icon_ids:
		get_icon(icon_id)
	return _texture_cache.size()


static func get_cached_icon_count() -> int:
	return _texture_cache.size()


static func get_icon(icon_id: String) -> Texture2D:
	if _texture_cache.has(icon_id):
		return _texture_cache[icon_id] as Texture2D

	var texture: Texture2D = _load_or_build_icon(icon_id)
	_texture_cache[icon_id] = texture
	return texture


static func _load_or_build_icon(icon_id: String) -> Texture2D:
	if icon_id.begins_with("status:"):
		var status_id: String = icon_id.trim_prefix("status:")
		var status_path: String = STATUS_ICON_PATH_TEMPLATE % status_id
		if ResourceLoader.exists(status_path):
			var status_resource: Resource = load(status_path)
			var status_texture: Texture2D = status_resource as Texture2D
			if status_texture != null:
				return status_texture
		return _build_status_icon()

	match icon_id:
		"attack", "shield", "hp", "speed", "time":
			return StatIconFactory.get_icon(icon_id)
		"shield_spend":
			return _build_shield_spend_icon()
		"delay":
			return _build_time_arrow_icon(false)
		"haste":
			return _build_time_arrow_icon(true)
		"recast":
			return _build_recast_icon()
		"interrupt":
			return _build_interrupt_icon()
		"cleanse":
			return _build_cleanse_icon()
		"empower":
			return _build_empower_icon()
		"auto_queue":
			return _build_auto_queue_icon()
		"timeline_stop":
			return _build_timeline_icon(false)
		"timeline_reverse":
			return _build_timeline_icon(true)
		"status":
			return _build_status_icon()
		_:
			return _build_effect_icon()


static func _new_image() -> Image:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	return image


static func _build_shield_spend_icon() -> Texture2D:
	var image: Image = _new_image()
	var dark: Color = Color(0.02, 0.08, 0.12, 0.96)
	var cyan: Color = Color(0.30, 0.82, 1.0, 1.0)
	var red: Color = Color(1.0, 0.34, 0.28, 1.0)
	_draw_shield(image, Vector2i(3, 1), dark)
	_draw_shield(image, Vector2i(1, 0), cyan)
	image.fill_rect(Rect2i(13, 28, 38, 10), dark)
	image.fill_rect(Rect2i(15, 29, 34, 7), red)
	return ImageTexture.create_from_image(image)


static func _build_time_arrow_icon(reverse: bool) -> Texture2D:
	var image: Image = _new_image()
	var dark: Color = Color(0.02, 0.08, 0.12, 0.96)
	var cyan: Color = Color(0.32, 0.86, 1.0, 1.0)
	var amber: Color = Color(1.0, 0.72, 0.22, 1.0)
	_draw_clock(image, Vector2i(24, 32), 19, dark)
	_draw_clock(image, Vector2i(22, 30), 18, cyan)
	image.fill_rect(Rect2i(20, 16, 5, 17), Color(0.86, 1.0, 1.0, 1.0))
	image.fill_rect(Rect2i(22, 28, 12, 5), Color(0.86, 1.0, 1.0, 1.0))
	if reverse:
		_draw_left_arrow(image, Vector2i(24, 42), amber)
	else:
		_draw_right_arrow(image, Vector2i(24, 42), amber)
	return ImageTexture.create_from_image(image)


static func _build_recast_icon() -> Texture2D:
	var image: Image = _new_image()
	var dark: Color = Color(0.02, 0.08, 0.12, 0.96)
	var blue: Color = Color(0.38, 0.78, 1.0, 1.0)
	var bright: Color = Color(0.88, 1.0, 1.0, 1.0)
	_draw_clock(image, Vector2i(34, 34), 24, dark)
	_draw_clock(image, Vector2i(32, 32), 22, blue)
	image.fill_rect(Rect2i(11, 13, 26, 6), bright)
	_draw_left_arrow(image, Vector2i(8, 10), bright)
	image.fill_rect(Rect2i(27, 45, 26, 6), bright)
	_draw_right_arrow(image, Vector2i(31, 42), bright)
	return ImageTexture.create_from_image(image)


static func _build_interrupt_icon() -> Texture2D:
	var image: Image = _new_image()
	var dark: Color = Color(0.16, 0.05, 0.03, 0.96)
	var orange: Color = Color(1.0, 0.54, 0.18, 1.0)
	var bright: Color = Color(1.0, 0.92, 0.46, 1.0)
	for row in range(22):
		image.fill_rect(Rect2i(34 - row, 5 + row, 10, 3), dark)
		image.fill_rect(Rect2i(32 - row, 4 + row, 9, 3), orange)
	for row in range(24):
		image.fill_rect(Rect2i(23 + row, 29 + row, 10, 3), dark)
		image.fill_rect(Rect2i(21 + row, 27 + row, 9, 3), orange)
	image.fill_rect(Rect2i(39, 9, 6, 24), bright)
	image.fill_rect(Rect2i(30, 18, 24, 6), bright)
	return ImageTexture.create_from_image(image)


static func _build_cleanse_icon() -> Texture2D:
	var image: Image = _new_image()
	var dark: Color = Color(0.02, 0.11, 0.10, 0.95)
	var green: Color = Color(0.42, 0.94, 0.68, 1.0)
	var bright: Color = Color(0.90, 1.0, 0.86, 1.0)
	_draw_spark(image, Vector2i(33, 31), 22, dark)
	_draw_spark(image, Vector2i(31, 29), 21, green)
	_draw_spark(image, Vector2i(49, 14), 8, bright)
	_draw_spark(image, Vector2i(14, 48), 7, bright)
	return ImageTexture.create_from_image(image)


static func _build_empower_icon() -> Texture2D:
	var image: Image = _new_image()
	var dark: Color = Color(0.16, 0.09, 0.02, 0.96)
	var amber: Color = Color(1.0, 0.68, 0.18, 1.0)
	var bright: Color = Color(1.0, 0.96, 0.54, 1.0)
	_draw_up_chevron(image, 8, 34, dark)
	_draw_up_chevron(image, 6, 32, amber)
	_draw_up_chevron(image, 20, 20, bright)
	image.fill_rect(Rect2i(29, 29, 7, 27), amber)
	return ImageTexture.create_from_image(image)


static func _build_auto_queue_icon() -> Texture2D:
	var image: Image = _new_image()
	var dark: Color = Color(0.02, 0.06, 0.10, 0.96)
	var blue: Color = Color(0.32, 0.72, 1.0, 1.0)
	var green: Color = Color(0.34, 0.92, 0.56, 1.0)
	image.fill_rect(Rect2i(8, 17, 27, 36), dark)
	image.fill_rect(Rect2i(13, 12, 27, 36), blue.darkened(0.15))
	image.fill_rect(Rect2i(19, 7, 27, 36), blue)
	image.fill_rect(Rect2i(24, 13, 17, 5), Color(0.80, 0.96, 1.0, 1.0))
	_draw_right_arrow(image, Vector2i(25, 41), green)
	return ImageTexture.create_from_image(image)


static func _build_timeline_icon(reverse: bool) -> Texture2D:
	var image: Image = _new_image()
	var dark: Color = Color(0.04, 0.06, 0.10, 0.96)
	var blue: Color = Color(0.34, 0.76, 1.0, 1.0)
	var bright: Color = Color(0.84, 1.0, 1.0, 1.0)
	image.fill_rect(Rect2i(7, 29, 50, 9), dark)
	image.fill_rect(Rect2i(7, 31, 50, 5), blue)
	for marker_x in [10, 24, 38, 52]:
		image.fill_rect(Rect2i(marker_x, 23, 4, 17), bright)
	if reverse:
		_draw_left_arrow(image, Vector2i(8, 7), Color(1.0, 0.70, 0.22, 1.0))
	else:
		image.fill_rect(Rect2i(25, 8, 7, 17), Color(1.0, 0.70, 0.22, 1.0))
		image.fill_rect(Rect2i(38, 8, 7, 17), Color(1.0, 0.70, 0.22, 1.0))
	return ImageTexture.create_from_image(image)


static func _build_status_icon() -> Texture2D:
	var image: Image = _new_image()
	var dark: Color = Color(0.12, 0.08, 0.02, 0.96)
	var amber: Color = Color(1.0, 0.74, 0.24, 1.0)
	_draw_spark(image, Vector2i(34, 34), 25, dark)
	_draw_spark(image, Vector2i(31, 31), 24, amber)
	_draw_disc(image, Vector2i(31, 31), 8, Color(0.08, 0.08, 0.10, 1.0))
	return ImageTexture.create_from_image(image)


static func _build_effect_icon() -> Texture2D:
	var image: Image = _new_image()
	var blue: Color = Color(0.40, 0.78, 1.0, 1.0)
	_draw_disc(image, Vector2i(32, 32), 24, blue.darkened(0.38))
	_draw_disc(image, Vector2i(32, 32), 16, blue)
	_draw_disc(image, Vector2i(32, 32), 6, Color(0.90, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(image)


static func _draw_shield(image: Image, origin: Vector2i, color: Color) -> void:
	image.fill_rect(Rect2i(origin.x + 11, origin.y + 9, 40, 8), color)
	image.fill_rect(Rect2i(origin.x + 9, origin.y + 17, 44, 14), color)
	image.fill_rect(Rect2i(origin.x + 13, origin.y + 31, 36, 9), color)
	image.fill_rect(Rect2i(origin.x + 19, origin.y + 40, 24, 8), color)
	image.fill_rect(Rect2i(origin.x + 26, origin.y + 48, 10, 6), color)


static func _draw_clock(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	var outer_squared: int = radius * radius
	var inner_radius: int = maxi(0, radius - 5)
	var inner_squared: int = inner_radius * inner_radius
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var distance_squared: int = x * x + y * y
			if distance_squared <= outer_squared and distance_squared >= inner_squared:
				image.set_pixel(center.x + x, center.y + y, color)


static func _draw_disc(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	var radius_squared: int = radius * radius
	for y in range(-radius, radius + 1):
		var half_width: int = int(sqrt(float(radius_squared - y * y)))
		image.fill_rect(Rect2i(center.x - half_width, center.y + y, half_width * 2 + 1, 1), color)


static func _draw_right_arrow(image: Image, origin: Vector2i, color: Color) -> void:
	image.fill_rect(Rect2i(origin.x, origin.y + 7, 29, 7), color)
	for row in range(11):
		image.fill_rect(Rect2i(origin.x + 25 + row, origin.y + row, 4, 22 - row * 2), color)


static func _draw_left_arrow(image: Image, origin: Vector2i, color: Color) -> void:
	image.fill_rect(Rect2i(origin.x + 8, origin.y + 7, 29, 7), color)
	for row in range(11):
		image.fill_rect(Rect2i(origin.x + 8 - row, origin.y + row, 4, 22 - row * 2), color)


static func _draw_spark(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	image.fill_rect(Rect2i(center.x - 4, center.y - radius, 8, radius * 2 + 1), color)
	image.fill_rect(Rect2i(center.x - radius, center.y - 4, radius * 2 + 1, 8), color)
	var diagonal_radius: int = int(radius / 2.0)
	for offset in range(-diagonal_radius, diagonal_radius + 1):
		image.fill_rect(Rect2i(center.x + offset - 2, center.y + offset - 2, 5, 5), color)
		image.fill_rect(Rect2i(center.x + offset - 2, center.y - offset - 2, 5, 5), color)


static func _draw_up_chevron(image: Image, x: int, y: int, color: Color) -> void:
	for offset in range(18):
		image.fill_rect(Rect2i(x + offset, y - offset, 5, 5), color)
		image.fill_rect(Rect2i(x + 35 - offset, y - offset, 5, 5), color)
