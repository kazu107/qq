extends Control
class_name SettingsDialog

signal dismissed

const SETTINGS_SCENE: PackedScene = preload("res://scenes/settings/Settings.tscn")
var _frame: PanelContainer
var _content: Control
var _previous_focus: WeakRef


func _ready() -> void:
	name = "SettingsDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_game_theme()
	z_index = 200
	var shade: ColorRect = ColorRect.new()
	shade.name = "SettingsBackdrop"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.005, 0.012, 0.02, 0.76)
	shade.gui_input.connect(_on_backdrop_input)
	add_child(shade)
	_frame = PanelContainer.new()
	_frame.name = "SettingsModal"
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("101b25")
	style.border_color = UiTheme.ACCENT_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(24)
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)
	_content = SETTINGS_SCENE.instantiate() as Control
	_content.set("modal_mode", true)
	_content.connect("close_requested", close)
	_frame.add_child(_content)
	resized.connect(_layout)
	get_viewport().gui_focus_changed.connect(_keep_modal_focus)
	hide()
	_layout()


func open() -> void:
	if visible: return
	var focused: Control = get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focused) if focused != null else null
	_content.call("_refresh_ui")
	show()
	_layout()
	_content.call_deferred("focus_modal")
	AudioManager.play_sfx("ui_toggle")


func close() -> void:
	if not visible: return
	hide()
	SaveManager.flush_requested_save()
	var previous: Control = _previous_focus.get_ref() as Control if _previous_focus != null else null
	if is_instance_valid(previous) and previous.is_inside_tree() and previous.is_visible_in_tree(): previous.grab_focus()
	AudioManager.play_sfx("ui_toggle")
	dismissed.emit()


func _layout() -> void:
	if _frame == null: return
	_frame.size = Vector2(minf(1120, maxf(0, size.x - 48)), minf(700, maxf(0, size.y - 48)))
	_frame.position = (size - _frame.size) * 0.5


func _keep_modal_focus(control: Control) -> void:
	if visible and control != null and not is_ancestor_of(control): _content.call_deferred("focus_modal")


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		close()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
