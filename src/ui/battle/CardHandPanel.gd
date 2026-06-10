extends HFlowContainer
class_name CardHandPanel

signal card_requested(runtime_id: String)
signal card_hovered(runtime_id: String)
signal card_unhovered(runtime_id: String)

var _interactive: bool = true
var _buttons: Array[CardButton] = []
var _tile_size: Vector2 = Vector2(100.0, 100.0)


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("h_separation", 10)
	add_theme_constant_override("v_separation", 10)


func set_interactive(value: bool) -> void:
	_interactive = value


func set_tile_size(size: Vector2) -> void:
	_tile_size = size
	for button in _buttons:
		button.set_tile_size(size)


func refresh_cards(unit: UnitState, run_state: RunState = null, owner_side: String = "") -> void:
	var runtime_states: Array[CardRuntimeState] = unit.get_sorted_runtime_states()
	_ensure_button_count(runtime_states.size())

	for index in range(_buttons.size()):
		var button: CardButton = _buttons[index]
		if index >= runtime_states.size():
			button.visible = false
			continue

		var runtime_state: CardRuntimeState = runtime_states[index]
		var resolved_side: String = owner_side
		if resolved_side == "":
			resolved_side = unit.unit_id
		var card_def: CardDef = _resolve_card_def(runtime_state.card_id, run_state, resolved_side)
		if card_def == null:
			button.visible = false
			continue

		var can_use: bool = runtime_state.can_use() and unit.active_slots_used + card_def.active_slot_cost <= unit.active_slot_max
		button.visible = true
		button.bind(card_def, runtime_state, can_use, _interactive)


func refresh_card_ids(card_ids: Array[String], interactive: bool = false, badge_text: String = "CARD", run_state: RunState = null) -> void:
	_ensure_button_count(card_ids.size())

	for index in range(_buttons.size()):
		var button: CardButton = _buttons[index]
		if index >= card_ids.size():
			button.visible = false
			continue

		var card_id: String = card_ids[index]
		var card_def: CardDef = _resolve_card_def(card_id, run_state, "player")
		if card_def == null:
			button.visible = false
			continue

		button.visible = true
		button.bind_preview(card_def, card_id, interactive, badge_text)


func _resolve_card_def(card_id: String, run_state: RunState, owner_side: String) -> CardDef:
	if owner_side == "player" and run_state != null:
		return CardUpgradeResolver.build_effective_card(card_id, run_state)
	return Database.get_card(card_id)


func _ensure_button_count(count: int) -> void:
	while _buttons.size() < count:
		var button: CardButton = CardButton.new()
		button.set_tile_size(_tile_size)
		button.card_requested.connect(_on_card_requested)
		button.card_hovered.connect(_on_card_hovered)
		button.card_unhovered.connect(_on_card_unhovered)
		add_child(button)
		_buttons.append(button)


func _on_card_requested(runtime_id: String) -> void:
	card_requested.emit(runtime_id)


func _on_card_hovered(runtime_id: String) -> void:
	if not _interactive:
		return
	card_hovered.emit(runtime_id)


func _on_card_unhovered(runtime_id: String) -> void:
	if not _interactive:
		return
	card_unhovered.emit(runtime_id)
