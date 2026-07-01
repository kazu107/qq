extends Button
class_name CardIconPicker

signal selection_changed(card_id: String)

const CARD_TILE_SIZE: Vector2 = Vector2(82.0, 82.0)
const POPUP_SIZE: Vector2i = Vector2i(560, 370)
const GRID_COLUMNS: int = 5

var _entries: Array[Dictionary] = []
var _include_empty: bool = false
var _selected_card_id: String = ""
var _popup: PopupPanel
var _grid: GridContainer


func _ready() -> void:
	custom_minimum_size = Vector2(260.0, 44.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_text = true
	pressed.connect(_on_pressed)
	_ensure_popup()
	_refresh_button()


func setup(entries: Array[Dictionary], default_id: String, include_empty: bool) -> void:
	_entries = entries.duplicate(true)
	_include_empty = include_empty
	_ensure_popup()
	_rebuild_grid()
	set_selected_card_id(default_id)


func set_selected_card_id(card_id: String) -> void:
	var resolved_id: String = card_id
	if resolved_id != "" and not _has_card_id(resolved_id):
		resolved_id = ""
	if resolved_id == "" and not _include_empty and not _entries.is_empty():
		resolved_id = String(_entries[0].get("id", ""))
	_selected_card_id = resolved_id
	_refresh_button()
	_update_choice_selection_frames()
	selection_changed.emit(_selected_card_id)


func get_selected_card_id() -> String:
	return _selected_card_id


func get_grid_column_count() -> int:
	_ensure_popup()
	return _grid.columns if _grid != null else 0


func get_choice_count() -> int:
	_ensure_popup()
	return _grid.get_child_count() if _grid != null else 0


func _on_pressed() -> void:
	_ensure_popup()
	if _popup == null:
		return
	var popup_position: Vector2i = Vector2i(roundi(global_position.x), roundi(global_position.y + size.y + 6.0))
	_popup.popup(Rect2i(popup_position, POPUP_SIZE))


func _ensure_popup() -> void:
	if _popup != null and is_instance_valid(_popup):
		return

	_popup = PopupPanel.new()
	_popup.name = "CardIconPickerPopup"
	_popup.min_size = POPUP_SIZE
	add_child(_popup)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_popup.add_child(margin)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "CardIconPickerScroll"
	scroll.custom_minimum_size = Vector2(POPUP_SIZE.x - 20.0, POPUP_SIZE.y - 20.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	_grid = GridContainer.new()
	_grid.name = "CardIconPickerGrid"
	_grid.columns = GRID_COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)


func _rebuild_grid() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	if _include_empty:
		var empty_button: Button = Button.new()
		empty_button.name = "CardIconChoice_empty"
		empty_button.custom_minimum_size = CARD_TILE_SIZE
		empty_button.text = Localization.get_text("hub.debug_empty_slot", "空き")
		empty_button.pressed.connect(_choose_card.bind(""))
		_grid.add_child(empty_button)

	for entry in _entries:
		var card_id: String = String(entry.get("id", ""))
		if card_id == "":
			continue
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null:
			continue
		var card_button: CardButton = CardButton.new()
		card_button.name = "CardIconChoice_%s" % card_id
		card_button.set_tile_size(CARD_TILE_SIZE)
		card_button.bind_preview(card_def, card_id, true, "")
		card_button.pressed.connect(_choose_card.bind(card_id))
		_grid.add_child(card_button)

	_update_choice_selection_frames()


func _choose_card(card_id: String) -> void:
	set_selected_card_id(card_id)
	if _popup != null:
		_popup.hide()


func _refresh_button() -> void:
	var selected_name: String = Localization.get_text("hub.debug_empty_slot", "空き")
	icon = null
	if _selected_card_id != "":
		var card_def: CardDef = Database.get_card(_selected_card_id)
		if card_def != null:
			selected_name = "%s [%s]" % [card_def.name, card_def.id]
			icon = _load_card_icon(card_def.id)
	text = selected_name


func _update_choice_selection_frames() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		var control: Control = child as Control
		if control == null:
			continue
		var selected: bool = control.name == "CardIconChoice_%s" % _selected_card_id
		if _selected_card_id == "" and control.name == "CardIconChoice_empty":
			selected = true
		if selected:
			control.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			control.modulate = Color(0.78, 0.78, 0.78, 0.92)


func _has_card_id(card_id: String) -> bool:
	for entry in _entries:
		if String(entry.get("id", "")) == card_id:
			return true
	return false


func _load_card_icon(card_id: String) -> Texture2D:
	var path: String = CardButton.ART_PATH_TEMPLATE % card_id
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	return resource as Texture2D
