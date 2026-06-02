extends VBoxContainer
class_name ActiveSlotPanel

var _title_label: Label
var _summary_label: Label
var _cards_row: HBoxContainer
var _empty_label: Label
var _cards: Array[CardButton] = []


func _ready() -> void:
	_title_label = Label.new()
	_title_label.text = "Active Slots"
	add_child(_title_label)

	_summary_label = Label.new()
	_summary_label.name = "Summary"
	add_child(_summary_label)

	_cards_row = HBoxContainer.new()
	_cards_row.name = "Cards"
	_cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_row.add_theme_constant_override("separation", 8)
	add_child(_cards_row)

	_empty_label = Label.new()
	_empty_label.name = "EmptyState"
	_empty_label.text = "No active cards"
	add_child(_empty_label)


func set_title(title: String) -> void:
	if _title_label != null:
		_title_label.text = title


func refresh_slots(instances: Array[ActiveCardInstance], battle_time: float, slot_max: int, slot_used: int) -> void:
	_summary_label.text = "Used %d / %d" % [slot_used, slot_max]
	_empty_label.visible = instances.is_empty()
	_ensure_card_count(max(slot_max, instances.size()))

	for index in range(_cards.size()):
		var button: CardButton = _cards[index]
		if index >= instances.size():
			button.visible = false
			continue

		var instance: ActiveCardInstance = instances[index]
		var card_def: CardDef = Database.get_card(instance.card_id)
		if card_def == null:
			button.visible = false
			continue

		button.visible = true
		button.bind_active(card_def, instance, battle_time)


func _ensure_card_count(count: int) -> void:
	while _cards.size() < count:
		var button: CardButton = CardButton.new()
		button.set_tile_size(Vector2(82.0, 82.0))
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		_cards_row.add_child(button)
		_cards.append(button)
