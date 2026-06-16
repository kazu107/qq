extends PanelContainer
class_name RelicIcon

const ART_PATH_TEMPLATE := "res://assets/icons/relics/%s.png"
const FRAME_FILL := Color(0.06, 0.07, 0.09, 0.94)
const BORDER_UNLOCKED := Color(0.94, 0.78, 0.42, 1.0)
const BORDER_LOCKED := Color(0.36, 0.37, 0.40, 1.0)
const TOOLTIP_WIDTH: float = 340.0

static var _texture_cache: Dictionary = {}

var relic_id: String = ""
var _icon_size: Vector2 = Vector2(48.0, 48.0)
var _icon_rect: TextureRect


func _ready() -> void:
	_ensure_visuals()


func set_icon_size(size: Vector2) -> void:
	_icon_size = size
	custom_minimum_size = size
	if _icon_rect != null:
		_icon_rect.custom_minimum_size = size


func bind_relic_id(id: String, locked: bool = false) -> void:
	var relic_def: RelicDef = Database.get_relic(id)
	bind(relic_def, locked)


func bind(relic_def: RelicDef, locked: bool = false) -> void:
	_ensure_visuals()
	if relic_def == null:
		relic_id = ""
		name = "RelicIcon_missing"
		tooltip_text = ""
		_icon_rect.texture = _build_placeholder_texture("missing")
		_apply_frame(true)
		return

	relic_id = relic_def.id
	name = "RelicIcon_%s" % relic_id
	_icon_rect.texture = _get_relic_texture(relic_id)
	tooltip_text = _build_tooltip(relic_def)
	modulate = Color(0.58, 0.58, 0.58, 1.0) if locked else Color(1.0, 1.0, 1.0, 1.0)
	_apply_frame(locked)


func _make_custom_tooltip(for_text: String) -> Object:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "RelicTooltipPopup"
	panel.custom_minimum_size = Vector2(TOOLTIP_WIDTH, 0.0)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var label: RichTextLabel = RichTextLabel.new()
	label.name = "RelicTooltipText"
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(TOOLTIP_WIDTH - 20.0, 0.0)
	label.text = for_text
	margin.add_child(label)
	return panel


func _ensure_visuals() -> void:
	if _icon_rect != null:
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = 0
	size_flags_vertical = 0
	custom_minimum_size = _icon_size

	_icon_rect = TextureRect.new()
	_icon_rect.name = "RelicArt"
	_icon_rect.custom_minimum_size = _icon_size
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_rect)
	_apply_frame(false)


func _apply_frame(locked: bool) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = FRAME_FILL
	style.border_color = BORDER_LOCKED if locked else BORDER_UNLOCKED
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 2.0
	style.content_margin_top = 2.0
	style.content_margin_right = 2.0
	style.content_margin_bottom = 2.0
	add_theme_stylebox_override("panel", style)


func _build_tooltip(relic_def: RelicDef) -> String:
	return "%s\n%s" % [relic_def.name, relic_def.description]


func _get_relic_texture(id: String) -> Texture2D:
	if _texture_cache.has(id):
		return _texture_cache[id] as Texture2D

	var path: String = ART_PATH_TEMPLATE % id
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var resource: Resource = load(path)
		texture = resource as Texture2D
	if texture == null:
		texture = _build_placeholder_texture(id)
	_texture_cache[id] = texture
	return texture


func _build_placeholder_texture(id: String) -> Texture2D:
	var image: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var hue: float = float(abs(id.hash()) % 1000) / 1000.0
	var base_color: Color = Color.from_hsv(hue, 0.52, 0.76, 1.0)
	image.fill(base_color.darkened(0.26))
	image.fill_rect(Rect2i(16, 16, 96, 96), base_color)
	image.fill_rect(Rect2i(36, 36, 56, 56), base_color.lightened(0.22))
	return ImageTexture.create_from_image(image)
