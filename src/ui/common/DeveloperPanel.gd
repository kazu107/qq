extends PanelContainer
class_name DeveloperPanel

var _title_label: Label
var _status_label: Label
var _actions_box: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	name = "DeveloperPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP


func configure(title: String, actions: Array, status_text: String = "") -> void:
	if _actions_box == null:
		_build_ui()
	_title_label.text = title
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

		var callback_value: Variant = action_data.get("callback", Callable())
		if callback_value is Callable:
			var callback: Callable = callback_value
			if callback.is_valid():
				button.pressed.connect(_on_action_pressed.bind(callback))

		_actions_box.add_child(button)


func pin_top_right(offset_top: float = 16.0, offset_right: float = 16.0) -> void:
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -276.0 - offset_right
	offset_top = offset_top
	offset_right = -offset_right
	offset_bottom = offset_top + 440.0
	size_flags_horizontal = Control.SIZE_FILL
	z_index = 50


func _build_ui() -> void:
	custom_minimum_size = Vector2(260.0, 0.0)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	_title_label = Label.new()
	root.add_child(_title_label)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)

	_actions_box = VBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_actions_box)


func _on_action_pressed(callback: Callable) -> void:
	AudioManager.play_sfx("ui_confirm")
	callback.call()
