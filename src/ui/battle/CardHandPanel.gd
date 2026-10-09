extends HFlowContainer
class_name CardHandPanel

signal card_requested(runtime_id: String)
signal card_hovered(runtime_id: String)
signal card_unhovered(runtime_id: String)
signal card_unequip_requested(card_id: String)

var _interactive: bool = true
var _buttons: Array[CardButton] = []
var _tile_size: Vector2 = Vector2(100.0, 100.0)
var _unequip_enabled: bool = false


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
		_position_unequip_button(button)


func set_unequip_enabled(enabled: bool) -> void:
	_unequip_enabled = enabled
	for button: CardButton in _buttons:
		_sync_unequip_button(button)


func get_button_for_runtime_id(runtime_id: String) -> CardButton:
	for button in _buttons:
		if button.visible and button.runtime_id == runtime_id:
			return button
	return null


func refresh_cards(unit: UnitState, run_state: RunState = null, _owner_side: String = "") -> void:
	var runtime_states: Array[CardRuntimeState] = unit.get_sorted_runtime_states()
	_ensure_button_count(runtime_states.size())

	for index in range(_buttons.size()):
		var button: CardButton = _buttons[index]
		if index >= runtime_states.size():
			button.visible = false
			continue

		var runtime_state: CardRuntimeState = runtime_states[index]
		var tooltip_context: Dictionary = CardTooltipResolver.build_context(runtime_state.card_id, run_state, unit)
		var card_def: CardDef = tooltip_context.get("card") as CardDef
		if card_def == null:
			button.visible = false
			continue

		var has_slots: bool = unit.active_slots_used + card_def.active_slot_cost <= unit.active_slot_max
		var has_shield: bool = CardEffectResolver.can_pay_shield_cost(unit, card_def)
		var can_use: bool = runtime_state.can_use() and has_slots and has_shield
		var blocked_reason: String = ""
		if runtime_state.can_use() and not has_slots:
			blocked_reason = Localization.get_text("card.blocked_slots", "Blocked: active slots full")
		elif runtime_state.can_use() and not has_shield:
			blocked_reason = Localization.get_text("card.blocked_shield", "Blocked: not enough shield")
		button.visible = true
		button.bind(
			card_def,
			runtime_state,
			can_use,
			_interactive,
			blocked_reason,
			tooltip_context.get("comparison") as CardDef
		)


func refresh_card_ids(card_ids: Array[String], interactive: bool = false, badge_text: String = "CARD", run_state: RunState = null) -> void:
	_ensure_button_count(card_ids.size())

	for index in range(_buttons.size()):
		var button: CardButton = _buttons[index]
		if index >= card_ids.size():
			button.visible = false
			continue

		var card_id: String = card_ids[index]
		var tooltip_context: Dictionary = CardTooltipResolver.build_context(card_id, run_state)
		var card_def: CardDef = tooltip_context.get("card") as CardDef
		if card_def == null:
			button.visible = false
			continue

		button.visible = true
		button.bind_preview(
			card_def,
			card_id,
			interactive,
			badge_text,
			tooltip_context.get("comparison") as CardDef
		)
		_sync_unequip_button(button)
		var remove: Button = button.get_node_or_null("DeckUnequipButton") as Button
		if remove != null:
			remove.disabled = not _unequip_enabled or card_ids.size() <= 1
			remove.tooltip_text = Localization.get_text("map.unequip_last", "Keep at least one card equipped") if card_ids.size() <= 1 else Localization.get_text("map.unequip", "Unequip")


func _sync_unequip_button(card: CardButton) -> void:
	var remove: Button = card.get_node_or_null("DeckUnequipButton") as Button
	if remove == null:
		if not _unequip_enabled:
			return
		remove = Button.new()
		remove.name = "DeckUnequipButton"
		remove.text = "\u00d7"
		remove.focus_mode = Control.FOCUS_NONE
		remove.custom_minimum_size = Vector2(26.0, 26.0)
		remove.add_theme_font_size_override("font_size", 22)
		remove.add_theme_color_override("font_color", Color.WHITE)
		remove.z_index = 101
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = Color("bc3b46") if state in ["hover", "pressed"] else Color(0.045, 0.065, 0.09, 0.94)
			style.border_color = Color("ff867b")
			style.set_border_width_all(1)
			style.set_corner_radius_all(6)
			style.set_content_margin_all(1.0)
			remove.add_theme_stylebox_override(state, style)
		remove.pressed.connect(func() -> void:
			if _unequip_enabled and not remove.disabled:
				card_unequip_requested.emit(card.runtime_id)
		)
		card.add_child(remove)
		HoverActionReveal.attach(card, remove, false)
		card.resized.connect(_position_unequip_button.bind(card))
	var reveal: HoverActionReveal = card.get_node("HoverActionReveal") as HoverActionReveal
	reveal.enabled = _unequip_enabled
	if not _unequip_enabled:
		remove.hide()
	_position_unequip_button(card)


func _position_unequip_button(card: CardButton) -> void:
	var remove: Button = card.get_node_or_null("DeckUnequipButton") as Button
	if remove == null:
		return
	var art: Rect2 = card.get_art_rect()
	remove.position = Vector2(art.end.x - 28.0, art.position.y + 2.0)
	remove.size = Vector2(26.0, 26.0)


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
