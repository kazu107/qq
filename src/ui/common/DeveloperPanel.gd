extends PanelContainer
class_name DeveloperPanel

const EXPANDED_HEIGHT: float = 440.0
const COLLAPSED_HEIGHT: float = 54.0

var _title_label: Label
var _toggle_button: Button
var _status_label: Label
var _actions_box: VBoxContainer
var _scroll: ScrollContainer
var _content_root: VBoxContainer
var _title_text: String = ""
var _collapsed: bool = false
var _is_pinned: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	name = "DeveloperPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(title: String, actions: Array, status_text: String = "") -> void:
	if _actions_box == null:
		_build_ui()
	_title_text = title
	_refresh_title()
	set_status_text(status_text)
	set_actions(actions)


func set_status_text(status_text: String) -> void:
	if _status_label == null:
		return
	_status_label.text = status_text
	_status_label.visible = status_text != ""


func set_actions(actions: Array) -> void:
	if _actions_box == null:
		return
	for child in _actions_box.get_children():
		_actions_box.remove_child(child)
		child.queue_free()

	for raw_action in actions:
		var action_data: Dictionary = Dictionary(raw_action)
		var button: Button = Button.new()
		button.name = String(action_data.get("id", "DevAction"))
		button.text = String(action_data.get("label", "Action"))
		button.disabled = bool(action_data.get("disabled", false))
		button.tooltip_text = String(action_data.get("tooltip", ""))
		button.mouse_filter = Control.MOUSE_FILTER_STOP

		var callback_value: Variant = action_data.get("callback", Callable())
		if callback_value is Callable:
			var callback: Callable = callback_value
			if callback.is_valid():
				button.pressed.connect(_on_action_pressed.bind(callback))

		_actions_box.add_child(button)


func pin_top_right(offset_top: float = 16.0, offset_right: float = 16.0) -> void:
	_is_pinned = true
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -276.0 - offset_right
	self.offset_top = offset_top
	self.offset_right = -offset_right
	size_flags_horizontal = Control.SIZE_FILL
	z_index = 50
	_update_pinned_height()


func set_collapsed(collapsed: bool, persist: bool = true) -> void:
	_collapsed = collapsed
	if _content_root != null:
		_content_root.visible = not _collapsed
	_refresh_title()
	_update_pinned_height()
	if persist:
		Game.set_developer_panel_collapsed(_collapsed)


func is_collapsed() -> bool:
	return _collapsed


func _build_ui() -> void:
	custom_minimum_size = Vector2(260.0, 0.0)

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.name = "DeveloperPanelHeader"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 6)
	root.add_child(header)

	_title_label = Label.new()
	_title_label.name = "DeveloperPanelTitle"
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_title_label)

	_toggle_button = Button.new()
	_toggle_button.name = "DeveloperPanelToggle"
	_toggle_button.custom_minimum_size = Vector2(30.0, 28.0)
	_toggle_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_toggle_button.focus_mode = Control.FOCUS_NONE
	_toggle_button.flat = true
	_toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_toggle_button.pressed.connect(_on_toggle_pressed)
	header.add_child(_toggle_button)

	_content_root = VBoxContainer.new()
	_content_root.name = "DeveloperPanelContent"
	_content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_root.add_theme_constant_override("separation", 8)
	root.add_child(_content_root)

	_status_label = Label.new()
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_root.add_child(_status_label)

	_scroll = ScrollContainer.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_root.add_child(_scroll)

	_actions_box = VBoxContainer.new()
	_actions_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_actions_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_actions_box)
	set_collapsed(Game.is_developer_panel_collapsed(), false)


func _on_toggle_pressed() -> void:
	AudioManager.play_sfx("ui_toggle")
	set_collapsed(not _collapsed, true)


func _refresh_title() -> void:
	if _title_label == null or _toggle_button == null:
		return
	_title_label.text = _title_text
	_toggle_button.text = "+" if _collapsed else "-"
	_toggle_button.tooltip_text = Localization.get_text("developer.expand", "Expand") if _collapsed else Localization.get_text("developer.collapse", "Collapse")


func _update_pinned_height() -> void:
	if not _is_pinned:
		return
	offset_bottom = offset_top + (COLLAPSED_HEIGHT if _collapsed else EXPANDED_HEIGHT)


func _on_action_pressed(callback: Callable) -> void:
	AudioManager.play_sfx("ui_confirm")
	callback.call()
