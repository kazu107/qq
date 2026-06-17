extends Button
class_name MapNodeButton

signal node_selected(node_id: String)

const STATUS_COLORS := {
	"available": Color(0.28, 0.63, 0.42, 1.0),
	"selected": Color(0.22, 0.48, 0.88, 1.0),
	"completed": Color(0.80, 0.68, 0.28, 1.0),
	"skipped": Color(0.44, 0.44, 0.47, 1.0),
	"locked": Color(0.24, 0.25, 0.29, 1.0),
}

const TYPE_TINTS := {
	"normal_battle": Color(0.93, 0.51, 0.37, 1.0),
	"elite_battle": Color(0.90, 0.24, 0.55, 1.0),
	"boss": Color(0.86, 0.24, 0.24, 1.0),
	"shop": Color(0.28, 0.72, 0.77, 1.0),
	"forge": Color(0.90, 0.57, 0.22, 1.0),
	"heal": Color(0.34, 0.80, 0.54, 1.0),
	"event": Color(0.73, 0.66, 0.28, 1.0),
	"hazard": Color(0.72, 0.30, 0.20, 1.0),
}

static var _type_icon_cache: Dictionary = {}
static var _lock_icon_texture: Texture2D

var _node_id: String = ""
var _visual_root: Control
var _content_box: VBoxContainer
var _type_icon: TextureRect
var _name_label: Label
var _lock_overlay: CenterContainer
var _lock_icon: TextureRect


func _ready() -> void:
	custom_minimum_size = Vector2(170.0, 100.0)
	focus_mode = Control.FOCUS_NONE
	flat = true
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ensure_visuals()
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


func bind(node_data: Dictionary, step_label: String, is_current_step: bool) -> void:
	_ensure_visuals()
	_node_id = String(node_data.get("id", ""))

	var node_type: String = String(node_data.get("type", ""))
	var node_label: String = Localization.get_node_label(node_data)
	var status: String = String(node_data.get("status", "locked"))

	text = ""
	disabled = status != "available"
	_type_icon.texture = _get_type_icon_texture(node_type)
	_name_label.text = node_label
	_content_box.modulate = Color(1.0, 1.0, 1.0, 0.42) if status == "locked" else Color(1.0, 1.0, 1.0, 1.0)
	_lock_overlay.visible = status == "locked"
	tooltip_text = "\n".join([
		step_label,
		Localization.get_textf("map.node.tooltip.type", "Type: {value}", {"value": _type_text(node_type)}),
	])
	_apply_style(node_type, status, is_current_step)


func _on_pressed() -> void:
	if _node_id == "" or disabled:
		return
	node_selected.emit(_node_id)


func _ensure_visuals() -> void:
	if _visual_root != null:
		return

	_visual_root = Control.new()
	_visual_root.name = "MapNodeVisualRoot"
	_visual_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_visual_root)

	_content_box = VBoxContainer.new()
	_content_box.name = "MapNodeContent"
	_content_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_content_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content_box.add_theme_constant_override("separation", 8)
	_visual_root.add_child(_content_box)

	_type_icon = TextureRect.new()
	_type_icon.name = "MapNodeTypeIcon"
	_type_icon.custom_minimum_size = Vector2(42.0, 42.0)
	_type_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_type_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_type_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_box.add_child(_type_icon)

	_name_label = Label.new()
	_name_label.name = "MapNodeName"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_box.add_child(_name_label)

	_lock_overlay = CenterContainer.new()
	_lock_overlay.name = "MapNodeLockOverlay"
	_lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lock_overlay.visible = false
	_visual_root.add_child(_lock_overlay)

	_lock_icon = TextureRect.new()
	_lock_icon.name = "MapNodeLockIcon"
	_lock_icon.custom_minimum_size = Vector2(52.0, 52.0)
	_lock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lock_icon.texture = _get_lock_icon_texture()
	_lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_overlay.add_child(_lock_icon)


func _apply_style(node_type: String, status: String, is_current_step: bool) -> void:
	var base_color: Color = TYPE_TINTS.get(node_type, Color(0.55, 0.55, 0.60, 1.0))
	var status_color: Color = STATUS_COLORS.get(status, Color(0.24, 0.25, 0.29, 1.0))
	var border_color: Color = base_color.lerp(status_color, 0.45)
	var normal_fill: Color = status_color.darkened(0.25)
	var disabled_fill: Color = status_color.darkened(0.30)
	if status == "locked":
		normal_fill = Color(0.07, 0.08, 0.10, 0.94)
		disabled_fill = Color(0.05, 0.06, 0.08, 0.96)
		border_color = border_color.darkened(0.18)
	if is_current_step and status == "available":
		border_color = border_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.20)

	add_theme_stylebox_override("normal", _make_stylebox(normal_fill, border_color, 2))
	add_theme_stylebox_override("hover", _make_stylebox(status_color.darkened(0.15), border_color.lightened(0.20), 3))
	add_theme_stylebox_override("pressed", _make_stylebox(status_color.darkened(0.10), base_color.lightened(0.25), 3))
	add_theme_stylebox_override("disabled", _make_stylebox(disabled_fill, border_color.darkened(0.15), 2))
	add_theme_color_override("font_color", Color(0.96, 0.95, 0.92, 1.0))
	add_theme_color_override("font_disabled_color", Color(0.72, 0.72, 0.72, 1.0))


func _make_stylebox(fill_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.shadow_size = 4
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	return style


func _get_type_icon_texture(node_type: String) -> Texture2D:
	if _type_icon_cache.has(node_type):
		return _type_icon_cache[node_type] as Texture2D
	var tint: Color = TYPE_TINTS.get(node_type, Color(0.55, 0.55, 0.60, 1.0))
	var texture: Texture2D = _build_type_icon_texture(node_type, tint)
	_type_icon_cache[node_type] = texture
	return texture


func _build_type_icon_texture(node_type: String, tint: Color) -> Texture2D:
	var image: Image = Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var accent: Color = tint
	accent.a = 0.96
	var dark: Color = tint.darkened(0.48)
	dark.a = 0.86
	var light: Color = tint.lightened(0.34)
	light.a = 0.96

	match node_type:
		"shop":
			image.fill_rect(Rect2i(22, 34, 52, 36), accent)
			image.fill_rect(Rect2i(28, 24, 40, 14), light)
			image.fill_rect(Rect2i(28, 68, 10, 10), dark)
			image.fill_rect(Rect2i(58, 68, 10, 10), dark)
		"forge":
			image.fill_rect(Rect2i(24, 58, 46, 12), accent)
			image.fill_rect(Rect2i(54, 26, 12, 42), light)
			image.fill_rect(Rect2i(42, 22, 34, 14), accent)
			image.fill_rect(Rect2i(28, 66, 42, 10), dark)
		"heal":
			image.fill_rect(Rect2i(40, 20, 16, 56), light)
			image.fill_rect(Rect2i(20, 40, 56, 16), accent)
		"event":
			image.fill_rect(Rect2i(28, 22, 40, 12), light)
			image.fill_rect(Rect2i(58, 34, 12, 18), accent)
			image.fill_rect(Rect2i(42, 50, 16, 14), accent)
			image.fill_rect(Rect2i(42, 70, 16, 8), light)
		"hazard":
			image.fill_rect(Rect2i(42, 18, 14, 44), accent)
			image.fill_rect(Rect2i(40, 68, 18, 12), light)
		"boss":
			image.fill_rect(Rect2i(22, 52, 52, 20), accent)
			image.fill_rect(Rect2i(28, 34, 12, 22), light)
			image.fill_rect(Rect2i(44, 24, 12, 32), light)
			image.fill_rect(Rect2i(60, 34, 12, 22), light)
		"elite_battle":
			image.fill_rect(Rect2i(24, 42, 48, 14), accent)
			image.fill_rect(Rect2i(38, 28, 20, 40), light)
			image.fill_rect(Rect2i(34, 70, 28, 8), dark)
		_:
			image.fill_rect(Rect2i(44, 18, 12, 54), light)
			image.fill_rect(Rect2i(34, 28, 32, 12), accent)
			image.fill_rect(Rect2i(38, 70, 20, 8), dark)

	return ImageTexture.create_from_image(image)


func _get_lock_icon_texture() -> Texture2D:
	if _lock_icon_texture != null:
		return _lock_icon_texture
	_lock_icon_texture = _build_lock_icon_texture()
	return _lock_icon_texture


func _build_lock_icon_texture() -> Texture2D:
	var image: Image = Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var body: Color = Color(0.92, 0.94, 0.98, 0.84)
	var shadow: Color = Color(0.04, 0.05, 0.07, 0.34)
	var hole: Color = Color(0.06, 0.07, 0.10, 0.58)
	image.fill_rect(Rect2i(25, 45, 50, 35), shadow)
	image.fill_rect(Rect2i(22, 42, 50, 35), body)
	image.fill_rect(Rect2i(31, 20, 34, 10), body)
	image.fill_rect(Rect2i(24, 28, 10, 24), body)
	image.fill_rect(Rect2i(62, 28, 10, 24), body)
	image.fill_rect(Rect2i(42, 54, 12, 12), hole)
	image.fill_rect(Rect2i(45, 64, 6, 10), hole)
	return ImageTexture.create_from_image(image)


func _type_text(node_type: String) -> String:
	match node_type:
		"normal_battle":
			return Localization.get_node_type_name("normal_battle")
		"elite_battle":
			return Localization.get_node_type_name("elite_battle")
		"boss":
			return Localization.get_node_type_name("boss")
		"shop":
			return Localization.get_node_type_name("shop")
		"forge":
			return Localization.get_node_type_name("forge")
		"heal":
			return Localization.get_node_type_name("heal")
		"event":
			return Localization.get_node_type_name("event")
		"hazard":
			return Localization.get_node_type_name("hazard")
		_:
			return node_type.capitalize()
