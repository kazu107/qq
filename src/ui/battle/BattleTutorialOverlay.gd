extends Control
class_name BattleTutorialOverlay

signal continued
signal exit_requested

const CALLOUT_SIZE: Vector2 = Vector2(470.0, 188.0)
const TARGET_PADDING: float = 10.0
const SCREEN_MARGIN: float = 24.0

var _target_rect: Rect2 = Rect2()
var _callout: PanelContainer
var _progress_label: Label
var _title_label: Label
var _body_label: Label
var _waiting_label: Label
var _continue_button: Button


func _ready() -> void:
	name = "BattleTutorialOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 150
	_build_ui()
	resized.connect(_layout_callout)


func show_step(
	progress_text: String,
	title_text: String,
	body_text: String,
	target_rect: Rect2,
	button_text: String = "",
	waiting_text: String = ""
) -> void:
	_progress_label.text = progress_text
	_title_label.text = title_text
	_body_label.text = body_text
	_waiting_label.text = waiting_text
	_waiting_label.visible = waiting_text != ""
	_continue_button.text = button_text
	_continue_button.visible = button_text != ""
	visible = true
	set_target_rect(target_rect)
	call_deferred("_layout_callout")


func set_target_rect(value: Rect2) -> void:
	_target_rect = value
	queue_redraw()
	_layout_callout()


func _draw() -> void:
	var full_rect: Rect2 = Rect2(Vector2.ZERO, size)
	if _target_rect.size.x <= 1.0 or _target_rect.size.y <= 1.0:
		draw_rect(full_rect, Color(0.0, 0.015, 0.03, 0.46))
		return

	var focus: Rect2 = _target_rect.grow(TARGET_PADDING).intersection(full_rect)
	var shade: Color = Color(0.0, 0.015, 0.03, 0.58)
	draw_rect(Rect2(0.0, 0.0, size.x, focus.position.y), shade)
	draw_rect(Rect2(0.0, focus.end.y, size.x, maxf(0.0, size.y - focus.end.y)), shade)
	draw_rect(Rect2(0.0, focus.position.y, focus.position.x, focus.size.y), shade)
	draw_rect(Rect2(focus.end.x, focus.position.y, maxf(0.0, size.x - focus.end.x), focus.size.y), shade)
	draw_rect(focus, Color(1.0, 0.77, 0.22, 0.96), false, 4.0)

	if _callout != null:
		var callout_rect: Rect2 = Rect2(_callout.position, _callout.size)
		var line_start: Vector2 = callout_rect.get_center()
		var line_end: Vector2 = focus.get_center()
		if line_end.y < callout_rect.position.y:
			line_start.y = callout_rect.position.y
		elif line_end.y > callout_rect.end.y:
			line_start.y = callout_rect.end.y
		line_start.x = clampf(line_end.x, callout_rect.position.x + 24.0, callout_rect.end.x - 24.0)
		draw_line(line_start, line_end, Color(1.0, 0.77, 0.22, 0.92), 4.0, true)
		draw_circle(line_end, 7.0, Color(1.0, 0.77, 0.22, 1.0))


func _build_ui() -> void:
	_callout = PanelContainer.new()
	_callout.name = "TutorialCallout"
	_callout.custom_minimum_size = CALLOUT_SIZE
	_callout.mouse_filter = Control.MOUSE_FILTER_STOP
	_callout.add_theme_stylebox_override("panel", _make_callout_style())
	add_child(_callout)

	var margin := MarginContainer.new()
	for edge: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	for edge: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	_callout.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_progress_label = Label.new()
	_progress_label.name = "TutorialProgress"
	_progress_label.add_theme_font_size_override("font_size", 15)
	_progress_label.add_theme_color_override("font_color", Color(1.0, 0.77, 0.22, 1.0))
	box.add_child(_progress_label)

	_title_label = Label.new()
	_title_label.name = "TutorialCalloutTitle"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0, 1.0))
	box.add_child(_title_label)

	_body_label = Label.new()
	_body_label.name = "TutorialCalloutBody"
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("font_size", 17)
	_body_label.add_theme_color_override("font_color", Color(0.82, 0.90, 0.94, 1.0))
	box.add_child(_body_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	box.add_child(footer)
	_waiting_label = Label.new()
	_waiting_label.name = "TutorialWaitingHint"
	_waiting_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waiting_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_waiting_label.add_theme_color_override("font_color", Color(0.52, 0.88, 1.0, 1.0))
	footer.add_child(_waiting_label)
	_continue_button = Button.new()
	_continue_button.name = "TutorialContinueButton"
	_continue_button.custom_minimum_size = Vector2(128.0, 38.0)
	_continue_button.pressed.connect(func() -> void: continued.emit())
	footer.add_child(_continue_button)

	var exit_button := Button.new()
	exit_button.name = "TutorialExitButton"
	exit_button.text = Localization.get_text("tutorial.exit", "Exit tutorial")
	exit_button.tooltip_text = Localization.get_text("tutorial.exit_tooltip", "Return to the tutorial list")
	exit_button.anchor_left = 1.0
	exit_button.anchor_right = 1.0
	exit_button.offset_left = -174.0
	exit_button.offset_top = 18.0
	exit_button.offset_right = -24.0
	exit_button.offset_bottom = 56.0
	exit_button.mouse_filter = Control.MOUSE_FILTER_STOP
	exit_button.pressed.connect(func() -> void: exit_requested.emit())
	add_child(exit_button)


func _layout_callout() -> void:
	if _callout == null or size.x <= 1.0 or size.y <= 1.0:
		return
	var callout_size: Vector2 = CALLOUT_SIZE
	var focus_center: Vector2 = _target_rect.get_center() if _target_rect.size.length_squared() > 1.0 else size * 0.5
	var x: float = clampf(focus_center.x - callout_size.x * 0.5, SCREEN_MARGIN, size.x - callout_size.x - SCREEN_MARGIN)
	var y: float
	if focus_center.y > size.y * 0.53:
		y = _target_rect.position.y - callout_size.y - 28.0
	else:
		y = _target_rect.end.y + 28.0
	y = clampf(y, 76.0, size.y - callout_size.y - SCREEN_MARGIN)
	_callout.position = Vector2(x, y)
	_callout.size = callout_size
	queue_redraw()


func _make_callout_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.065, 0.98)
	style.border_color = Color(1.0, 0.72, 0.20, 0.96)
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.62)
	style.shadow_size = 16
	style.shadow_offset = Vector2(0.0, 7.0)
	return style
