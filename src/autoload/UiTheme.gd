extends Node

const BACKGROUND_SCRIPT: GDScript = preload("res://src/ui/common/AtmosphereBackground.gd")
const BACKGROUND_NODE_NAME: String = "GameAtmosphereBackground"

const TEXT_MAIN: Color = Color(0.93, 0.95, 0.94, 1.0)
const TEXT_MUTED: Color = Color(0.66, 0.72, 0.74, 1.0)
const TEXT_DISABLED: Color = Color(0.42, 0.45, 0.48, 1.0)
const ACCENT_BLUE: Color = Color(0.20, 0.62, 0.92, 1.0)
const ACCENT_GOLD: Color = Color(0.96, 0.68, 0.28, 1.0)
const PANEL_FILL: Color = Color(0.055, 0.065, 0.080, 0.90)
const PANEL_FILL_DEEP: Color = Color(0.025, 0.030, 0.040, 0.95)
const PANEL_STROKE: Color = Color(0.27, 0.37, 0.46, 0.72)
const BUTTON_FILL: Color = Color(0.105, 0.125, 0.155, 0.96)
const BUTTON_HOVER: Color = Color(0.145, 0.205, 0.250, 0.98)
const BUTTON_PRESSED: Color = Color(0.185, 0.250, 0.285, 1.0)
const BUTTON_DISABLED: Color = Color(0.070, 0.075, 0.085, 0.82)

var _theme: Theme
var _styled_scene: Control


func _ready() -> void:
	_theme = _build_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	call_deferred("_style_current_scene")


func _process(_delta: float) -> void:
	_style_current_scene()


func get_game_theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


func _style_current_scene() -> void:
	var current_scene: Node = get_tree().current_scene
	var scene_control: Control = current_scene as Control
	if scene_control == null:
		return

	if _styled_scene != scene_control:
		_styled_scene = scene_control
		scene_control.theme = get_game_theme()
		_ensure_background(scene_control)
		return

	if scene_control.theme == null:
		scene_control.theme = get_game_theme()
	_ensure_background(scene_control)


func _ensure_background(scene_control: Control) -> void:
	if scene_control.get_node_or_null(BACKGROUND_NODE_NAME) != null:
		return
	var background: Control = BACKGROUND_SCRIPT.new() as Control
	if background == null:
		return
	background.name = BACKGROUND_NODE_NAME
	scene_control.add_child(background)
	scene_control.move_child(background, 0)


func _build_theme() -> Theme:
	var theme: Theme = Theme.new()
	_apply_label_theme(theme)
	_apply_button_theme(theme, "Button")
	_apply_button_theme(theme, "OptionButton")
	_apply_check_theme(theme)
	_apply_panel_theme(theme)
	_apply_text_theme(theme)
	_apply_slider_theme(theme)
	_apply_container_theme(theme)
	return theme


func _apply_label_theme(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT_MAIN)
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.62))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_font_size("font_size", "Label", 17)


func _apply_text_theme(theme: Theme) -> void:
	theme.set_color("default_color", "RichTextLabel", TEXT_MAIN)
	theme.set_color("font_selected_color", "RichTextLabel", Color(0.05, 0.08, 0.10, 1.0))
	theme.set_color("selection_color", "RichTextLabel", Color(0.30, 0.62, 0.90, 0.36))
	theme.set_color("font_shadow_color", "RichTextLabel", Color(0.0, 0.0, 0.0, 0.52))
	theme.set_constant("shadow_offset_x", "RichTextLabel", 1)
	theme.set_constant("shadow_offset_y", "RichTextLabel", 2)
	theme.set_font_size("normal_font_size", "RichTextLabel", 17)


func _apply_button_theme(theme: Theme, theme_type: String) -> void:
	theme.set_stylebox("normal", theme_type, _make_button_style(BUTTON_FILL, Color(0.24, 0.35, 0.44, 0.88), 1, 14))
	theme.set_stylebox("hover", theme_type, _make_button_style(BUTTON_HOVER, ACCENT_BLUE, 2, 14))
	theme.set_stylebox("pressed", theme_type, _make_button_style(BUTTON_PRESSED, ACCENT_GOLD, 2, 14))
	theme.set_stylebox("disabled", theme_type, _make_button_style(BUTTON_DISABLED, Color(0.16, 0.17, 0.19, 0.75), 1, 14))
	theme.set_stylebox("focus", theme_type, _make_button_style(Color(0.10, 0.16, 0.20, 0.25), ACCENT_GOLD, 2, 14))
	theme.set_color("font_color", theme_type, TEXT_MAIN)
	theme.set_color("font_hover_color", theme_type, Color(0.98, 1.0, 0.98, 1.0))
	theme.set_color("font_pressed_color", theme_type, Color(1.0, 0.88, 0.62, 1.0))
	theme.set_color("font_disabled_color", theme_type, TEXT_DISABLED)
	theme.set_font_size("font_size", theme_type, 17)


func _apply_check_theme(theme: Theme) -> void:
	var check_theme_types: Array[String] = ["CheckButton", "CheckBox"]
	for theme_type: String in check_theme_types:
		theme.set_color("font_color", theme_type, TEXT_MAIN)
		theme.set_color("font_hover_color", theme_type, Color(0.98, 1.0, 0.98, 1.0))
		theme.set_color("font_disabled_color", theme_type, TEXT_DISABLED)
		theme.set_font_size("font_size", theme_type, 17)


func _apply_panel_theme(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", _make_panel_style(PANEL_FILL, PANEL_STROKE, 18, 8))
	theme.set_stylebox("panel", "TooltipPanel", _make_panel_style(Color(0.035, 0.042, 0.052, 0.98), Color(0.56, 0.66, 0.72, 0.80), 12, 8))
	theme.set_color("font_color", "TooltipLabel", TEXT_MAIN)


func _apply_slider_theme(theme: Theme) -> void:
	theme.set_stylebox("slider", "HSlider", _make_flat_style(Color(0.05, 0.07, 0.09, 1.0), Color(0.20, 0.25, 0.29, 0.95), 1, 8))
	theme.set_stylebox("grabber_area", "HSlider", _make_flat_style(Color(0.12, 0.46, 0.72, 1.0), ACCENT_BLUE, 1, 8))
	theme.set_icon("grabber", "HSlider", _make_grabber_texture(ACCENT_GOLD))
	theme.set_icon("grabber_highlight", "HSlider", _make_grabber_texture(Color(1.0, 0.82, 0.45, 1.0)))


func _apply_container_theme(theme: Theme) -> void:
	theme.set_constant("separation", "VBoxContainer", 12)
	theme.set_constant("separation", "HBoxContainer", 12)
	theme.set_constant("h_separation", "HFlowContainer", 12)
	theme.set_constant("v_separation", "HFlowContainer", 12)


func _make_button_style(fill_color: Color, border_color: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = _make_flat_style(fill_color, border_color, border_width, radius)
	style.content_margin_left = 16.0
	style.content_margin_top = 9.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 9.0
	style.shadow_size = 5
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	return style


func _make_panel_style(fill_color: Color, border_color: Color, radius: int, shadow_size: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = _make_flat_style(fill_color, border_color, 1, radius)
	style.content_margin_left = 14.0
	style.content_margin_top = 12.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 12.0
	style.shadow_size = shadow_size
	style.shadow_offset = Vector2(0.0, 4.0)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	return style


func _make_flat_style(fill_color: Color, border_color: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _make_grabber_texture(color: Color) -> Texture2D:
	var image: Image = Image.create(22, 22, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	image.fill_rect(Rect2i(6, 2, 10, 18), color)
	image.fill_rect(Rect2i(3, 6, 16, 10), color.lightened(0.12))
	return ImageTexture.create_from_image(image)
