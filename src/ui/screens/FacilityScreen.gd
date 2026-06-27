extends Control

var _title_label: Label
var _facility_frame: PanelContainer
var _facility_header_label: Label
var _summary_label: RichTextLabel
var _status_label: Label
var _relics_icon_row: RelicIconRow
var _options_box: VBoxContainer
var _leave_button: Button
var _deck_frame: PanelContainer
var _deck_header_label: Label
var _deck_summary_label: Label
var _deck_panel: CardHandPanel
var _run_info_banner: RunInfoBanner
var _developer_panel: DeveloperPanel


func _ready() -> void:
	if Game.current_run == null:
		SceneRouter.go_to_title()
		return
	if Game.get_active_facility_type() == "":
		SceneRouter.go_to_map()
		return

	_build_ui()
	_refresh_ui()
	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 44.0
	margin.offset_top = 34.0
	margin.offset_right = -44.0
	margin.offset_bottom = -34.0
	add_child(margin)

	var screen_root: VBoxContainer = VBoxContainer.new()
	screen_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_root.add_theme_constant_override("separation", 14)
	margin.add_child(screen_root)

	_run_info_banner = RunInfoBanner.new()
	screen_root.add_child(_run_info_banner)

	var root: HBoxContainer = HBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 20)
	screen_root.add_child(root)

	var facility_panel: VBoxContainer = _create_panel(root, Localization.get_text("facility.panel.node_detail", "Node Detail"))
	facility_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_facility_frame = facility_panel.get_parent() as PanelContainer
	_facility_header_label = facility_panel.get_child(0) as Label

	_title_label = Label.new()
	facility_panel.add_child(_title_label)

	_summary_label = RichTextLabel.new()
	_summary_label.fit_content = true
	facility_panel.add_child(_summary_label)

	_relics_icon_row = RelicIconRow.new()
	_relics_icon_row.name = "FacilityRelicIconRow"
	_relics_icon_row.set_icon_size(Vector2(42.0, 42.0))
	facility_panel.add_child(_relics_icon_row)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facility_panel.add_child(_status_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	facility_panel.add_child(scroll)

	_options_box = VBoxContainer.new()
	_options_box.name = "FacilityOptions"
	_options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_box.add_theme_constant_override("separation", 12)
	scroll.add_child(_options_box)

	var leave_button: Button = Button.new()
	leave_button.text = Localization.get_text("facility.leave_node", "Leave Node")
	leave_button.pressed.connect(_on_leave_facility)
	facility_panel.add_child(leave_button)
	_leave_button = leave_button

	var deck_box: VBoxContainer = _create_panel(root, Localization.get_text("facility.panel.battle_loadout", "Battle Loadout"))
	deck_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_frame = deck_box.get_parent() as PanelContainer
	_deck_header_label = deck_box.get_child(0) as Label

	_deck_summary_label = Label.new()
	deck_box.add_child(_deck_summary_label)

	_deck_panel = CardHandPanel.new()
	_deck_panel.name = "FacilityDeck"
	_deck_panel.set_interactive(false)
	_deck_panel.set_tile_size(Vector2(92.0, 92.0))
	deck_box.add_child(_deck_panel)


func _create_panel(parent: Control, title: String) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var header: Label = Label.new()
	header.text = title
	box.add_child(header)
	return box


func _uses_choice_layout(node_type: String) -> bool:
	return ["shop", "forge", "heal", "event", "hazard"].has(node_type)


func _apply_facility_layout_state(uses_choice_layout: bool) -> void:
	if _facility_header_label != null:
		_facility_header_label.visible = not uses_choice_layout
	if _summary_label != null:
		_summary_label.visible = not uses_choice_layout
	if _status_label != null:
		_status_label.visible = not uses_choice_layout
	if _relics_icon_row != null:
		_relics_icon_row.visible = not uses_choice_layout
	if _leave_button != null:
		_leave_button.visible = not uses_choice_layout
	if _deck_frame != null:
		_deck_frame.visible = not uses_choice_layout
	if _deck_header_label != null:
		_deck_header_label.visible = not uses_choice_layout
	if _options_box != null:
		_options_box.alignment = BoxContainer.ALIGNMENT_CENTER if uses_choice_layout else BoxContainer.ALIGNMENT_BEGIN
	if _title_label != null:
		_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if uses_choice_layout else HORIZONTAL_ALIGNMENT_LEFT
		_title_label.add_theme_font_size_override("font_size", 34 if uses_choice_layout else 18)
		_title_label.add_theme_color_override("font_color", Color(0.96, 0.91, 0.78, 1.0) if uses_choice_layout else Color(0.96, 0.96, 0.96, 1.0))
	if _facility_frame == null:
		return
	if uses_choice_layout:
		_facility_frame.custom_minimum_size = Vector2(780.0, 0.0)
		_facility_frame.add_theme_stylebox_override("panel", _make_event_panel_stylebox())
	else:
		_facility_frame.custom_minimum_size = Vector2.ZERO
		_facility_frame.remove_theme_stylebox_override("panel")


func _refresh_ui() -> void:
	var current_run: RunState = Game.current_run
	if _run_info_banner != null:
		_run_info_banner.refresh()
	var active_node: Dictionary = Game.get_active_map_node()
	var node_type: String = Game.get_active_facility_type()
	var uses_choice_layout: bool = _uses_choice_layout(node_type)
	_apply_facility_layout_state(uses_choice_layout)

	if uses_choice_layout:
		var event_data: Dictionary = Game.get_active_event_data()
		if node_type == "event":
			_title_label.text = String(event_data.get("title", Localization.get_text("event.default_title", "Event")))
		else:
			_title_label.text = _facility_title(node_type)
		_summary_label.text = ""
		_status_label.text = ""
	else:
		_title_label.text = Localization.get_textf("facility.title", "{title} | Area {area}", {
			"title": _facility_title(node_type),
			"area": int(active_node.get("area", current_run.current_area)),
		})
		_summary_label.text = "\n".join([
			Localization.get_textf("map.summary.gold", "Gold {value}", {"value": current_run.gold}),
			Localization.get_textf("map.summary.hp", "HP {current} / {max}", {
				"current": current_run.player_hp,
				"max": current_run.max_hp,
			}),
			Localization.get_textf("facility.summary.selected_node", "Selected Node: {label}", {
				"label": Localization.get_node_label(active_node),
			}),
			Localization.get_textf("map.relics_text", "Relics: {value}", {"value": _relic_text()}),
		])
		_deck_summary_label.text = Localization.get_textf("map.loadout_cost", "Loadout Cost {used} / {limit}", {
			"used": Game.get_current_loadout_cost(),
			"limit": Game.get_loadout_limit(),
		})
		_relics_icon_row.refresh_relic_ids(current_run.relics)

	for child in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()

	match node_type:
		"shop":
			_status_label.text = Localization.get_text("facility.status.shop", "Buy cards with gold. New cards auto-equip only if room remains in the loadout.")
			_render_shop_offers()
		"forge":
			_status_label.text = Localization.get_text("facility.status.forge", "Upgrade one card by one tier. Tier 3 cards cannot be upgraded further.")
			_render_forge_options(bool(active_node.get("forge_used", false)))
		"heal":
			_status_label.text = Localization.get_text("facility.status.heal", "Recover HP, then move on.")
			_render_heal_option(int(active_node.get("heal_amount", 0)))
		"event":
			_render_event_options()
		"hazard":
			_status_label.text = Localization.get_text("facility.status.hazard", "Each cleared wave pays immediately. You can withdraw between waves.")
			_render_hazard_options()
		_:
			_status_label.text = Localization.get_text("facility.status.none", "No facility data.")

	if not uses_choice_layout:
		_deck_panel.refresh_card_ids(Game.get_equipped_cards(), false, "EQUIP", current_run)
	_refresh_developer_panel()


func _render_shop_offers() -> void:
	var offers: Array[Dictionary] = Game.get_shop_offers()
	var choice_list: VBoxContainer = _create_choice_list("ShopChoiceList")

	for offer_index in range(offers.size()):
		var offer_data: Dictionary = offers[offer_index]
		var card_id: String = String(offer_data.get("card_id", ""))
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null:
			continue
		var price: int = int(offer_data.get("price", 0))
		var bought: bool = bool(offer_data.get("bought", false))
		var enabled: bool = not bought and Game.current_run.gold >= price
		var disabled_reason: String = ""
		if bought:
			disabled_reason = Localization.get_text("shop.sold", "Sold")
		elif not enabled:
			disabled_reason = Localization.get_text("event.disabled.not_enough_gold", "Not enough gold.")
		var choice_data: Dictionary = {
			"id": "offer_%d" % offer_index,
			"name_prefix": "ShopChoiceButton",
			"label": Localization.get_textf("shop.choice.buy_card.label", "Buy {card_name} ({price}G)", {
				"card_name": card_def.name,
				"price": price,
			}),
			"description": CardInfoFormatter.build_effect_summary(card_def),
			"effects": [
				{"type": "lose_gold", "amount": price},
				{"type": "grant_random_card", "card_id": card_id},
			],
			"enabled": enabled,
			"disabled_reason": disabled_reason,
		}
		if bought:
			choice_data["effects"] = [{"type": "grant_random_card", "card_id": card_id}]
		choice_list.add_child(_build_event_choice_button(choice_data, Callable(self, "_on_buy_offer").bind(offer_index)))

	for service_choice in Game.get_shop_service_choices():
		var choice_data: Dictionary = Dictionary(service_choice)
		choice_data["name_prefix"] = "ShopChoiceButton"
		choice_list.add_child(_build_event_choice_button(choice_data, Callable(self, "_on_use_shop_service").bind(String(choice_data.get("id", "")))))

	choice_list.add_child(_build_event_choice_button({
		"id": "leave_shop",
		"name_prefix": "ShopChoiceButton",
		"label": Localization.get_text("facility.leave_node", "Leave Node"),
		"description": Localization.get_text("shop.choice.leave.description", "Leave the shop and continue the run."),
		"effects": [],
		"enabled": true,
		"disabled_reason": "",
	}, Callable(self, "_on_leave_facility")))


func _render_forge_options(forge_used: bool) -> void:
	var options: Array[String] = Game.get_forge_options()
	var choice_list: VBoxContainer = _create_choice_list("ForgeChoiceList")

	if forge_used:
		var done_label: Label = Label.new()
		done_label.text = Localization.get_text("forge.used", "Forge already used for this visit.")
		done_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		choice_list.add_child(done_label)

	for card_id in options:
		var card_def: CardDef = CardUpgradeResolver.build_effective_card(card_id, Game.current_run)
		if card_def == null:
			continue
		var current_tier: int = CardUpgradeResolver.get_tier(Game.current_run, card_id)
		var next_tier: int = current_tier + 1
		var choice_data: Dictionary = {
			"id": "upgrade_%s" % card_id,
			"name_prefix": "ForgeChoiceButton",
			"label": Localization.get_textf("forge.choice.upgrade_card.label", "Upgrade {card_name} to {grade}", {
				"card_name": card_def.name,
				"grade": CardInfoFormatter.format_grade_label(next_tier),
			}),
			"description": CardInfoFormatter.build_effect_summary(CardUpgradeResolver.build_card_at_tier(card_id, next_tier)),
			"effects": [
				{"type": "upgrade_random_card", "card_id": card_id, "next_tier": next_tier},
			],
			"enabled": not forge_used and current_tier < CardUpgradeResolver.MAX_TIER,
			"disabled_reason": Localization.get_text("forge.used", "Forge already used for this visit.") if forge_used else Localization.get_text("forge.unavailable", "Unavailable"),
		}
		choice_list.add_child(_build_event_choice_button(choice_data, Callable(self, "_on_upgrade_card").bind(card_id)))

	for service_choice in Game.get_forge_service_choices():
		var choice_data: Dictionary = Dictionary(service_choice)
		choice_data["name_prefix"] = "ForgeChoiceButton"
		choice_list.add_child(_build_event_choice_button(choice_data, Callable(self, "_on_use_forge_service").bind(String(choice_data.get("id", "")))))

	choice_list.add_child(_build_event_choice_button({
		"id": "leave_forge",
		"name_prefix": "ForgeChoiceButton",
		"label": Localization.get_text("facility.leave_node", "Leave Node"),
		"description": Localization.get_text("forge.choice.leave.description", "Leave without using more forge services."),
		"effects": [],
		"enabled": true,
		"disabled_reason": "",
	}, Callable(self, "_on_leave_facility")))


func _render_heal_option(heal_amount: int) -> void:
	var _unused_heal_amount: int = heal_amount
	var choice_list: VBoxContainer = _create_choice_list("HealChoiceList")
	for heal_choice in Game.get_heal_node_choices():
		var choice_data: Dictionary = Dictionary(heal_choice)
		choice_data["name_prefix"] = "HealChoiceButton"
		choice_list.add_child(_build_event_choice_button(choice_data, Callable(self, "_on_use_heal_choice").bind(String(choice_data.get("id", "")))))


func _render_event_options() -> void:
	var event_data: Dictionary = Game.get_active_event_data()
	var choices: Array = Array(event_data.get("choices", []))

	var choice_list: VBoxContainer = _create_choice_list("EventChoiceList")

	for raw_choice in choices:
		var choice_data: Dictionary = Dictionary(raw_choice)
		choice_list.add_child(_build_event_choice_button(choice_data, Callable(self, "_on_resolve_event").bind(String(choice_data.get("id", "")))))


func _create_choice_list(list_name: String) -> VBoxContainer:
	var choice_list: VBoxContainer = VBoxContainer.new()
	choice_list.name = list_name
	choice_list.custom_minimum_size = Vector2(680.0, 0.0)
	choice_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	choice_list.add_theme_constant_override("separation", 14)
	_options_box.add_child(choice_list)
	return choice_list


func _build_event_choice_button(choice_data: Dictionary, pressed_callback: Callable = Callable()) -> Button:
	var choice_id: String = String(choice_data.get("id", ""))
	var disabled: bool = not bool(choice_data.get("enabled", true))
	var button: Button = Button.new()
	var name_prefix: String = String(choice_data.get("name_prefix", "EventChoiceButton"))
	button.name = "%s_%s" % [name_prefix, choice_id]
	button.text = ""
	button.custom_minimum_size = Vector2(0.0, 94.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	button.disabled = disabled
	button.tooltip_text = String(choice_data.get("disabled_reason", ""))
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _make_event_choice_stylebox(false, false))
	button.add_theme_stylebox_override("hover", _make_event_choice_stylebox(false, true))
	button.add_theme_stylebox_override("pressed", _make_event_choice_stylebox(false, true))
	button.add_theme_stylebox_override("disabled", _make_event_choice_stylebox(true, false))
	if not disabled and pressed_callback.is_valid():
		button.pressed.connect(pressed_callback)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 18.0
	margin.offset_top = 10.0
	margin.offset_right = -18.0
	margin.offset_bottom = -10.0
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)

	var body_row: HBoxContainer = HBoxContainer.new()
	body_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body_row.add_theme_constant_override("separation", 12)
	body_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(body_row)

	var content: VBoxContainer = VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_row.add_child(content)

	var title_label: Label = Label.new()
	title_label.text = String(choice_data.get("label", ""))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.88, 0.82, 0.63, 1.0) if not disabled else Color(0.48, 0.48, 0.48, 1.0))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title_label)

	_add_event_effect_chips(content, choice_data, choice_id, disabled)
	var preview_card_id: String = _get_choice_card_id(choice_data)
	if preview_card_id != "":
		var card_def: CardDef = Database.get_card(preview_card_id)
		if card_def != null:
			var preview: CardButton = CardButton.new()
			preview.name = "ChoiceCardPreview_%s_%s" % [choice_id, preview_card_id]
			preview.set_tile_size(Vector2(74.0, 74.0))
			preview.custom_minimum_size = Vector2(74.0, 74.0)
			preview.mouse_filter = Control.MOUSE_FILTER_PASS
			preview.bind_preview(card_def, preview_card_id, false, "CARD")
			body_row.add_child(preview)
	return button


func _make_event_panel_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.034, 0.050, 0.96)
	style.border_color = Color(0.72, 0.64, 0.45, 0.88)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0.0, 8.0)
	style.content_margin_left = 24.0
	style.content_margin_top = 24.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 24.0
	return style


func _make_event_choice_stylebox(disabled: bool, highlighted: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	if disabled:
		style.bg_color = Color(0.08, 0.08, 0.075, 0.82)
		style.border_color = Color(0.30, 0.30, 0.28, 0.80)
	elif highlighted:
		style.bg_color = Color(0.16, 0.145, 0.105, 0.96)
		style.border_color = Color(0.95, 0.82, 0.52, 0.92)
	else:
		style.bg_color = Color(0.105, 0.105, 0.090, 0.94)
		style.border_color = Color(0.70, 0.67, 0.58, 0.86)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _add_event_effect_chips(parent: Control, choice_data: Dictionary, choice_id: String, disabled: bool) -> void:
	var effects_row: HBoxContainer = HBoxContainer.new()
	effects_row.alignment = BoxContainer.ALIGNMENT_CENTER
	effects_row.add_theme_constant_override("separation", 12)
	effects_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(effects_row)

	var added_chip: bool = false
	for raw_effect in Array(choice_data.get("effects", [])):
		var effect_data: Dictionary = Dictionary(raw_effect)
		if _add_event_effect_chip(effects_row, effect_data, choice_id, disabled):
			added_chip = true

	if added_chip:
		return

	var description_label: Label = Label.new()
	description_label.text = String(choice_data.get("description", ""))
	description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_color_override("font_color", Color(0.68, 0.64, 0.54, 1.0) if not disabled else Color(0.40, 0.40, 0.40, 1.0))
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effects_row.add_child(description_label)


func _add_event_effect_chip(parent: Control, effect_data: Dictionary, choice_id: String, disabled: bool) -> bool:
	var effect_type: String = String(effect_data.get("type", ""))
	var chip: HBoxContainer = HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text: String = ""

	match effect_type:
		"grant_gold":
			_add_event_stat_icon(chip, "gold")
			text = "+%d" % _get_event_effect_amount(effect_data)
		"lose_gold":
			_add_event_stat_icon(chip, "gold")
			text = "-%d" % _get_event_effect_amount(effect_data)
		"heal":
			_add_event_stat_icon(chip, "hp")
			text = "+%d" % _get_event_effect_amount(effect_data)
		"lose_hp":
			_add_event_stat_icon(chip, "hp")
			text = "-%d" % _get_event_effect_amount(effect_data)
		"modify_max_hp":
			_add_event_stat_icon(chip, "hp")
			text = Localization.get_textf("event.effect.max_hp", "Max +{amount}", {"amount": _get_signed_amount_text(effect_data)})
		"modify_attack":
			_add_event_stat_icon(chip, "attack")
			text = _get_signed_amount_text(effect_data)
		"modify_speed":
			_add_event_stat_icon(chip, "speed")
			text = _get_signed_amount_text(effect_data)
		"modify_loadout_limit":
			_add_event_stat_icon(chip, "card")
			text = Localization.get_textf("event.effect.loadout", "Loadout {amount}", {"amount": _get_signed_amount_text(effect_data)})
		"grant_random_card":
			_add_event_stat_icon(chip, "card")
			text = _get_effect_card_name(effect_data)
		"upgrade_random_card":
			_add_event_stat_icon(chip, "card")
			text = "%s -> %s" % [
				_get_effect_card_name(effect_data),
				CardInfoFormatter.format_grade_label(int(effect_data.get("next_tier", 0))),
			]
		"grant_random_relic":
			var relic_id: String = String(effect_data.get("relic_id", ""))
			if relic_id == "":
				return false
			var relic_icon: RelicIcon = RelicIcon.new()
			relic_icon.set_icon_size(Vector2(30.0, 30.0))
			relic_icon.bind_relic_id(relic_id, disabled)
			relic_icon.name = "EventChoiceRelicIcon_%s_%s" % [choice_id, relic_id]
			relic_icon.mouse_filter = Control.MOUSE_FILTER_PASS
			chip.add_child(relic_icon)
			text = _get_relic_name(relic_id)
		_:
			return false

	var text_label: Label = Label.new()
	text_label.text = text
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.add_theme_font_size_override("font_size", 15)
	text_label.add_theme_color_override("font_color", Color(0.78, 0.74, 0.62, 1.0) if not disabled else Color(0.42, 0.42, 0.42, 1.0))
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(text_label)
	parent.add_child(chip)
	return true


func _add_event_stat_icon(parent: Control, icon_id: String) -> void:
	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(24.0, 24.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = StatIconFactory.get_icon(icon_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)


func _get_event_effect_amount(effect_data: Dictionary) -> int:
	return int(effect_data.get("amount", 0))


func _get_signed_amount_text(effect_data: Dictionary) -> String:
	var amount: int = _get_event_effect_amount(effect_data)
	if amount >= 0:
		return "+%d" % amount
	return "%d" % amount


func _get_effect_card_name(effect_data: Dictionary) -> String:
	var card_id: String = String(effect_data.get("card_id", ""))
	var card_def: CardDef = Database.get_card(card_id)
	if card_def != null:
		return card_def.name
	if card_id != "":
		return card_id
	return Localization.get_text("event.effect.card", "Card")


func _get_relic_name(relic_id: String) -> String:
	var relic_def: RelicDef = Database.get_relic(relic_id)
	if relic_def != null:
		return relic_def.name
	return relic_id


func _get_choice_card_id(choice_data: Dictionary) -> String:
	for raw_effect in Array(choice_data.get("effects", [])):
		var effect_data: Dictionary = Dictionary(raw_effect)
		var card_id: String = String(effect_data.get("card_id", ""))
		if card_id != "" and Database.get_card(card_id) != null:
			return card_id
	return ""


func _render_hazard_options() -> void:
	var hazard_status: Dictionary = Game.get_hazard_status()
	var choice_list: VBoxContainer = _create_choice_list("HazardChoiceList")
	var cleared_waves: int = int(hazard_status.get("waves_cleared", 0))
	var total_waves: int = int(hazard_status.get("waves_total", 0))
	var next_enemy: String = String(hazard_status.get("next_enemy", Localization.get_text("hazard.cleared", "Cleared")))
	var continue_label: String = Localization.get_text("hazard.enter", "Enter Hazard")
	if cleared_waves > 0:
		continue_label = Localization.get_text("hazard.continue", "Continue Hazard")
	var can_continue: bool = cleared_waves < total_waves

	choice_list.add_child(_build_event_choice_button({
		"id": "continue_hazard",
		"name_prefix": "HazardChoiceButton",
		"label": continue_label,
		"description": Localization.get_textf("hazard.choice.continue.description", "Wave {current} / {total}. Next: {next_enemy}", {
			"current": min(cleared_waves + 1, total_waves),
			"total": total_waves,
			"next_enemy": next_enemy,
		}),
		"effects": [
			{"type": "grant_gold", "amount": int(hazard_status.get("wave_gold", 0))},
			{"type": "heal", "amount": int(hazard_status.get("wave_heal", 0))},
		],
		"enabled": can_continue,
		"disabled_reason": "" if can_continue else Localization.get_text("hazard.cleared", "Cleared"),
	}, Callable(self, "_on_continue_hazard")))

	if cleared_waves > 0:
		choice_list.add_child(_build_event_choice_button({
			"id": "withdraw_hazard",
			"name_prefix": "HazardChoiceButton",
			"label": Localization.get_text("hazard.withdraw", "Withdraw With Current Rewards"),
			"description": Localization.get_text("hazard.choice.withdraw.description", "Leave the hazard zone and keep the rewards already earned."),
			"effects": [],
			"enabled": true,
			"disabled_reason": "",
		}, Callable(self, "_on_withdraw_hazard")))


func _on_buy_offer(offer_index: int) -> void:
	if Game.buy_shop_offer(offer_index):
		_refresh_ui()


func _on_use_shop_service(choice_id: String) -> void:
	if Game.use_shop_service_choice(choice_id):
		_refresh_ui()


func _on_upgrade_card(card_id: String) -> void:
	Game.upgrade_forge_card(card_id)
	_refresh_ui()


func _on_use_forge_service(choice_id: String) -> void:
	if Game.use_forge_service_choice(choice_id):
		_refresh_ui()


func _on_use_heal_node() -> void:
	Game.use_heal_node()
	SceneRouter.go_to_map()


func _on_use_heal_choice(choice_id: String) -> void:
	Game.use_heal_node_choice(choice_id)
	SceneRouter.go_to_map()


func _on_resolve_event(choice_id: String) -> void:
	Game.resolve_event_choice(choice_id)
	SceneRouter.go_to_map()


func _on_continue_hazard() -> void:
	if Game.continue_hazard():
		SceneRouter.go_to_battle()


func _on_withdraw_hazard() -> void:
	Game.withdraw_hazard()
	SceneRouter.go_to_map()


func _apply_forge_preview_state(preview: CardButton, tier_label: Label, details_label: Label, card_id: String, tier: int) -> void:
	var card_def: CardDef = CardUpgradeResolver.build_card_at_tier(card_id, tier)
	if card_def == null:
		return
	preview.bind_preview(card_def, card_id, false, "FORGE")
	tier_label.text = "%s | %s" % [card_def.name, CardInfoFormatter.format_grade_label(tier)]
	details_label.text = "\n".join([
		Localization.get_textf("forge.card_timing", "Cast {cast_time}s | Recast {recast_time}s", {
			"cast_time": "%.1f" % card_def.cast_time,
			"recast_time": "%.1f" % card_def.recast_time,
		}),
		CardInfoFormatter.build_effect_summary(card_def),
	])


func _on_leave_facility() -> void:
	Game.leave_facility()
	if Game.current_run != null and Game.current_run.run_complete:
		SceneRouter.go_to_result()
	else:
		SceneRouter.go_to_map()


func _facility_title(facility_type: String) -> String:
	match facility_type:
		"shop":
			return Localization.get_text("map.type.shop", "Shop")
		"forge":
			return Localization.get_text("map.type.forge", "Forge")
		"heal":
			return Localization.get_text("map.node.repair_bay", "Repair Bay")
		"event":
			return Localization.get_text("map.type.event", "Event")
		"hazard":
			return Localization.get_text("hazard.title", "Hazard Zone")
		_:
			return Localization.get_text("facility.node", "Node")


func _relic_text() -> String:
	var relic_names: Array[String] = Game.get_relic_names()
	if relic_names.is_empty():
		return Localization.get_text("status.none", "None")
	return ", ".join(relic_names)


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right()
	_refresh_developer_panel()


func _refresh_developer_panel() -> void:
	if _developer_panel == null:
		return
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		_build_developer_actions(),
		Localization.get_text("facility.dev.summary", "Manual test helpers for facility and node flows.")
	)


func _build_developer_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = [
		{"id": "DevAddGold", "label": Localization.get_text("map.dev.add_gold", "Add 50 Gold"), "callback": Callable(self, "_on_dev_add_gold")},
		{"id": "DevRestoreHp", "label": Localization.get_text("map.dev.restore_hp", "Restore HP"), "callback": Callable(self, "_on_dev_restore_hp")},
		{"id": "DevGrantRelic", "label": Localization.get_text("map.dev.grant_relic", "Grant Relic"), "callback": Callable(self, "_on_dev_grant_relic")},
		{"id": "DevOpenReward", "label": Localization.get_text("map.dev.debug_reward", "Debug Reward"), "callback": Callable(self, "_on_dev_open_reward")},
	]
	for entry in Game.get_available_event_debug_entries():
		var event_id: String = String(entry.get("id", ""))
		var title: String = String(entry.get("title", event_id))
		actions.append({
			"id": "DevEvent_%s" % event_id,
			"label": Localization.get_textf("map.dev.event", "Event: {title}", {"title": title}),
			"callback": Callable(self, "_on_dev_open_event").bind(event_id),
		})
	return actions


func _on_dev_add_gold() -> void:
	Game.developer_add_gold(50)
	_refresh_ui()


func _on_dev_restore_hp() -> void:
	Game.developer_restore_hp()
	_refresh_ui()


func _on_dev_grant_relic() -> void:
	Game.developer_grant_random_relic()
	_refresh_ui()


func _on_dev_open_reward() -> void:
	Game.developer_open_reward()
	SceneRouter.go_to_reward()


func _on_dev_open_event(event_id: String) -> void:
	Game.developer_open_event(event_id)
	_refresh_ui()
