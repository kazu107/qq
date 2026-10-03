extends Control
class_name LoadingLogo

const LOGO_TEXTURE: Texture2D = preload("res://assets/branding/queuequest-logo.svg")
const VIEWBOX_SIZE := Vector2(900.0, 240.0)
const PARTS: Array[String] = ["wordmark", "timeline", "card-back", "card-middle", "card-front"]
static var _part_texture_cache: Dictionary = {}

var _cards: Array[TextureRect] = []
var _light_layer: Control
var _intro_tween: Tween
var _elapsed: float = 0.0
var _completed: bool = false
var _light_phase: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if OS.has_feature("web"):
		_add_texture("StaticLogo", LOGO_TEXTURE)
		set_process(false)
		return
	for part: String in PARTS:
		if not _part_texture_cache.has(part):
			_part_texture_cache[part] = load("res://assets/branding/loading/%s.svg" % part) as Texture2D
		var texture: Texture2D = _part_texture_cache[part] as Texture2D
		var image: TextureRect = _add_texture(part, texture)
		if part.begins_with("card-"):
			_cards.append(image)
	_light_layer = Control.new()
	_light_layer.name = "TimelineLight"
	_light_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_light_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light_layer.draw.connect(_draw_timeline_light)
	add_child(_light_layer)
	_intro_tween = create_tween().set_parallel(true)
	for index: int in range(_cards.size()):
		var card: TextureRect = _cards[index]
		card.position.x = 24.0 * _fit_scale()
		card.modulate.a = 0.0
		_intro_tween.tween_property(card, "position:x", 0.0, 0.36).set_delay(0.12 * index).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_intro_tween.tween_property(card, "modulate:a", 1.0, 0.36).set_delay(0.12 * index)


func get_logo_texture() -> Texture2D:
	return LOGO_TEXTURE


func finish_loading() -> void:
	if _completed:
		return
	_completed = true
	set_process(false)
	if is_instance_valid(_intro_tween):
		_intro_tween.kill()
	for card: TextureRect in _cards:
		card.position = Vector2.ZERO
		card.modulate = Color.WHITE
		card.self_modulate = Color.WHITE
	if _light_layer != null:
		_light_layer.queue_redraw()
	if _cards.is_empty():
		return
	var front: TextureRect = _cards.back()
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(front, "position:y", -6.0 * _fit_scale(), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(front, "modulate", Color(1.25, 1.18, 1.08, 1.0), 0.18)
	tween.chain().tween_property(front, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(front, "modulate", Color.WHITE, 0.18)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.6:
		return
	_light_phase = fmod((_elapsed - 0.6) / 2.0, 1.0)
	var pulse: float = maxf(0.0, 1.0 - absf(_light_phase - 0.94) / 0.06)
	_cards.back().self_modulate = Color(1.0 + pulse * 0.15, 1.0 + pulse * 0.10, 1.0, 1.0)
	_light_layer.queue_redraw()


func _draw_timeline_light() -> void:
	if _completed or _elapsed < 0.6:
		return
	var fit_scale: float = _fit_scale()
	var origin: Vector2 = (size - VIEWBOX_SIZE * fit_scale) * 0.5
	var point: Vector2 = origin + Vector2(232.0 - 184.0 * _light_phase, 202.0) * fit_scale
	var alpha: float = clampf(minf(_light_phase / 0.05, (1.0 - _light_phase) / 0.1), 0.0, 1.0)
	_light_layer.draw_circle(point, 8.0 * fit_scale, Color(0.45, 0.84, 0.96, alpha * 0.16))
	_light_layer.draw_circle(point, 5.0 * fit_scale, Color(0.45, 0.84, 0.96, alpha))


func _fit_scale() -> float:
	return minf(maxf(size.x, custom_minimum_size.x) / VIEWBOX_SIZE.x, maxf(size.y, custom_minimum_size.y) / VIEWBOX_SIZE.y)


func _add_texture(part: String, texture: Texture2D) -> TextureRect:
	var image: TextureRect = TextureRect.new()
	image.name = part
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.set_anchors_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	return image
