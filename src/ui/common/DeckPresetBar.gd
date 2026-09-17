extends VBoxContainer
class_name DeckPresetBar

signal apply_requested(cards: Array[String])

var get_cards: Callable
var get_run: Callable
var max_cards: int = DeckPresetService.MAX_CARDS
var _select: OptionButton
var _name: LineEdit
var _message: Label
var _presets: Array[Dictionary] = []


func _ready() -> void:
	name = "DeckPresets"
	var row: HBoxContainer = HBoxContainer.new()
	add_child(row)
	_select = OptionButton.new()
	_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_select.clip_text = true
	_select.item_selected.connect(func(_index: int) -> void: _show_selection())
	row.add_child(_select)
	_button(row, "presets.apply", "Apply", _apply)
	_button(row, "presets.delete", "Delete", _delete)
	var save_row: HBoxContainer = HBoxContainer.new()
	add_child(save_row)
	_name = LineEdit.new()
	_name.placeholder_text = Localization.get_text("presets.name", "Deck name")
	_name.max_length = 32
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_name)
	_button(save_row, "presets.save", "Save deck", _save)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)
	_reload()


func _button(parent: Control, key: String, fallback: String, callback: Callable) -> void:
	var button: Button = Button.new()
	button.text = Localization.get_text(key, fallback)
	button.pressed.connect(callback)
	parent.add_child(button)


func _reload() -> void:
	_presets = DeckPresetService.list_presets()
	_select.clear()
	for preset in _presets:
		_select.add_item(String(preset.get("name", "")))
	_select.disabled = _presets.is_empty()
	_show_selection()


func selected_cards() -> Array[String]:
	var cards: Array[String] = []
	if _select.selected >= 0 and _select.selected < _presets.size():
		for card: Variant in _presets[_select.selected].get("cards", []):
			cards.append(String(card))
	return cards


func _show_selection() -> void:
	var cards: Array[String] = selected_cards()
	var names: PackedStringArray = []
	for card in cards:
		var definition: CardDef = Database.get_card(card)
		names.append(definition.name if definition != null else card)
	_message.text = " / ".join(names)
	_message.modulate = Color.WHITE
	if get_run.is_valid() and not cards.is_empty():
		var check: Dictionary = DeckPresetService.validate(get_run.call() as RunState, cards)
		_message.text += "\n" + String(check.get("reason", ""))
		if not bool(check.get("ok", false)):
			_message.modulate = Color("ef7979")


func _apply() -> void:
	_show_selection()
	var cards: Array[String] = selected_cards()
	if not DeckPresetService.valid_cards(cards) or cards.size() > max_cards:
		_message.text = Localization.get_text("presets.invalid", "Empty deck or too many cards for this screen.")
		return
	if get_run.is_valid() and not bool(DeckPresetService.validate(get_run.call() as RunState, cards).get("ok", false)):
		return
	apply_requested.emit(cards)


func _save() -> void:
	if get_cards.is_valid() and DeckPresetService.save_preset(_name.text, get_cards.call()):
		_reload()
	else:
		_message.text = Localization.get_text("presets.save_failed", "Enter a name and a valid deck (up to 20 presets).")


func _delete() -> void:
	if _select.selected >= 0:
		DeckPresetService.delete_preset(String(_presets[_select.selected].get("name", "")))
		_reload()
