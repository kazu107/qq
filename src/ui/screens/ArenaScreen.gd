extends Control

const PORTRAIT_PATH_TEMPLATE := "res://assets/portraits/%s.png"
const OFFER_CARD_SIZE: Vector2 = Vector2(104.0, 104.0)
const OFFER_RELIC_SIZE: Vector2 = Vector2(72.0, 72.0)
const LOADOUT_PREVIEW_SIZE: Vector2 = Vector2(76.0, 76.0)
const LOADOUT_COUNT_ICON_SIZE: Vector2 = Vector2(20.0, 20.0)
const REWARD_MODAL_WIDTH: float = 760.0

var _run_info_banner: RunInfoBanner
var _status_label: Label
var _next_enemy_label: Label
var _enemy_portrait: TextureRect
var _card_offers_box: VBoxContainer
var _relic_offers_box: VBoxContainer
var _loadout_summary_label: Label
var _deck_panel: CardHandPanel
var _inventory_box: VBoxContainer
var _relic_row: RelicIconRow
var _reroll_button: Button
var _abandon_button: Button
var _start_battle_button: Button
var _reward_overlay: ColorRect
var _reward_modal: PanelContainer
var _reward_options_box: HBoxContainer
var _reward_title_label: Label
var _reward_hint_label: Label
var _developer_panel: DeveloperPanel
var _lan_mode: bool = false


func _ready() -> void:
	_lan_mode = NetworkManager.is_lan_arena_session_active()
	if _lan_mode:
		if NetworkManager.get_lan_arena_phase() == "battle" and NetworkManager.has_active_match():
			SceneRouter.go_to_battle()
			return
		_connect_lan_signals()
	else:
		if Game.current_run == null:
			SceneRouter.go_to_hub()
			return
		if not Game.current_run.arena_mode:
			SceneRouter.go_to_map()
			return
		if Game.current_run.run_complete:
			SceneRouter.go_to_result()
			return

	_build_ui()
	_refresh_ui()
	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _connect_lan_signals() -> void:
	if not NetworkManager.arena_preparation_changed.is_connected(_on_lan_arena_changed):
		NetworkManager.arena_preparation_changed.connect(_on_lan_arena_changed)
	if not NetworkManager.arena_action_result_received.is_connected(_on_lan_arena_action_result):
		NetworkManager.arena_action_result_received.connect(_on_lan_arena_action_result)
	if not NetworkManager.match_started.is_connected(_on_lan_match_started):
		NetworkManager.match_started.connect(_on_lan_match_started)
	if not NetworkManager.arena_session_finished.is_connected(_on_lan_arena_finished):
		NetworkManager.arena_session_finished.connect(_on_lan_arena_finished)
	if not NetworkManager.session_ended.is_connected(_on_lan_session_ended):
		NetworkManager.session_ended.connect(_on_lan_session_ended)


func _build_ui() -> void:
	var background: AtmosphereBackground = AtmosphereBackground.new()
	add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 38)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 38)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	_run_info_banner = RunInfoBanner.new()
	root.add_child(_run_info_banner)

	var header: HBoxContainer = HBoxContainer.new()
	header.name = "ArenaHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)

	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)

	var title: Label = Label.new()
	title.text = Localization.get_text("arena.title", "Arena Progression")
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.96, 0.90, 0.72, 1.0))
	title_box.add_child(title)

	_status_label = Label.new()
	_status_label.name = "ArenaStatusLabel"
	_status_label.add_theme_color_override("font_color", Color(0.70, 0.82, 0.90, 1.0))
	title_box.add_child(_status_label)

	_abandon_button = Button.new()
	_abandon_button.name = "ArenaAbandonButton"
	_abandon_button.text = Localization.get_text("arena.abandon", "Abandon To Hub")
	_abandon_button.custom_minimum_size = Vector2(190.0, 42.0)
	_abandon_button.pressed.connect(_on_abandon)
	header.add_child(_abandon_button)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)

	_build_status_panel(body)
	_build_shop_panel(body)
	_build_loadout_panel(body)
	_build_reward_modal()


func _build_status_panel(parent: Control) -> void:
	var box: VBoxContainer = _create_panel(parent, Localization.get_text("arena.panel.match", "Next Match"), Vector2(300.0, 0.0))
	box.add_theme_constant_override("separation", 12)

	var portrait_frame: PanelContainer = PanelContainer.new()
	portrait_frame.name = "ArenaEnemyPortraitFrame"
	portrait_frame.custom_minimum_size = Vector2(220.0, 220.0)
	portrait_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait_frame.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.030, 0.038, 0.96), Color(0.82, 0.36, 0.28, 0.88), 2))
	box.add_child(portrait_frame)

	_enemy_portrait = TextureRect.new()
	_enemy_portrait.name = "ArenaNextEnemyPortrait"
	_enemy_portrait.custom_minimum_size = Vector2(214.0, 214.0)
	_enemy_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_enemy_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_enemy_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(_enemy_portrait)

	_next_enemy_label = Label.new()
	_next_enemy_label.name = "ArenaNextEnemyLabel"
	_next_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next_enemy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_enemy_label.add_theme_font_size_override("font_size", 20)
	box.add_child(_next_enemy_label)

	var rules: Label = Label.new()
	rules.text = Localization.get_text("arena.rules", "Win enough battles before your losses fill up. Use preparation gold to tune the deck between matches.")
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_color_override("font_color", Color(0.66, 0.72, 0.78, 1.0))
	box.add_child(rules)

	_reroll_button = Button.new()
	_reroll_button.name = "ArenaRerollShopButton"
	_reroll_button.pressed.connect(_on_reroll_shop)
	box.add_child(_reroll_button)


func _build_shop_panel(parent: Control) -> void:
	var box: VBoxContainer = _create_panel(parent, Localization.get_text("arena.panel.prep_shop", "Preparation Shop"), Vector2(660.0, 0.0))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	var shop_root: VBoxContainer = VBoxContainer.new()
	shop_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_root.add_theme_constant_override("separation", 14)
	scroll.add_child(shop_root)

	var card_title: Label = Label.new()
	card_title.text = Localization.get_text("arena.cards_for_sale", "Cards")
	card_title.add_theme_font_size_override("font_size", 19)
	shop_root.add_child(card_title)

	_card_offers_box = VBoxContainer.new()
	_card_offers_box.name = "ArenaCardOffers"
	_card_offers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_offers_box.add_theme_constant_override("separation", 10)
	shop_root.add_child(_card_offers_box)

	var relic_title: Label = Label.new()
	relic_title.text = Localization.get_text("arena.relics_for_sale", "Relics")
	relic_title.add_theme_font_size_override("font_size", 19)
	shop_root.add_child(relic_title)

	_relic_offers_box = VBoxContainer.new()
	_relic_offers_box.name = "ArenaRelicOffers"
	_relic_offers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_relic_offers_box.add_theme_constant_override("separation", 10)
	shop_root.add_child(_relic_offers_box)


func _build_loadout_panel(parent: Control) -> void:
	var box: VBoxContainer = _create_panel(parent, Localization.get_text("arena.panel.loadout", "Arena Loadout"), Vector2(420.0, 0.0))
	box.name = "ArenaLoadoutPanelBody"
	box.add_theme_constant_override("separation", 12)

	_loadout_summary_label = Label.new()
	_loadout_summary_label.name = "ArenaLoadoutSummary"
	_loadout_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_loadout_summary_label)

	_deck_panel = CardHandPanel.new()
	_deck_panel.name = "ArenaEquippedDeck"
	_deck_panel.set_interactive(false)
	_deck_panel.set_tile_size(Vector2(86.0, 86.0))
	box.add_child(_deck_panel)

	var inventory_title: Label = Label.new()
	inventory_title.text = Localization.get_text("arena.card_inventory", "Card Inventory")
	box.add_child(inventory_title)

	var inventory_scroll: ScrollContainer = ScrollContainer.new()
	inventory_scroll.name = "ArenaLoadoutInventoryScroll"
	inventory_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(inventory_scroll)

	_inventory_box = VBoxContainer.new()
	_inventory_box.name = "ArenaLoadoutInventory"
	_inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_box.custom_minimum_size = Vector2(0.0, 0.0)
	_inventory_box.add_theme_constant_override("separation", 8)
	inventory_scroll.add_child(_inventory_box)

	var relic_title: Label = Label.new()
	relic_title.text = Localization.get_text("arena.owned_relics", "Owned Relics")
	box.add_child(relic_title)

	_relic_row = RelicIconRow.new()
	_relic_row.name = "ArenaOwnedRelics"
	_relic_row.set_icon_size(Vector2(42.0, 42.0))
	box.add_child(_relic_row)

	_start_battle_button = Button.new()
	_start_battle_button.name = "ArenaStartBattleButton"
	_start_battle_button.text = Localization.get_text("arena.start_battle", "Start Next Battle")
	_start_battle_button.custom_minimum_size = Vector2(0.0, 44.0)
	_start_battle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_battle_button.pressed.connect(_on_start_battle)
	box.add_child(_start_battle_button)


func _create_panel(parent: Control, title: String, min_size: Vector2) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.035, 0.045, 0.94), Color(0.24, 0.52, 0.64, 0.72), 1))
	parent.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var header: Label = Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0, 1.0))
	box.add_child(header)
	return box


func _build_reward_modal() -> void:
	_reward_overlay = ColorRect.new()
	_reward_overlay.name = "ArenaRewardOverlay"
	_reward_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reward_overlay.color = Color(0.0, 0.0, 0.0, 0.62)
	_reward_overlay.visible = false
	_reward_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_reward_overlay.z_index = 120
	add_child(_reward_overlay)

	_reward_modal = PanelContainer.new()
	_reward_modal.name = "ArenaRewardModal"
	_reward_modal.custom_minimum_size = Vector2(REWARD_MODAL_WIDTH, 0.0)
	_reward_modal.anchor_left = 0.5
	_reward_modal.anchor_top = 0.5
	_reward_modal.anchor_right = 0.5
	_reward_modal.anchor_bottom = 0.5
	_reward_modal.offset_left = -REWARD_MODAL_WIDTH * 0.5
	_reward_modal.offset_right = REWARD_MODAL_WIDTH * 0.5
	_reward_modal.offset_top = -230.0
	_reward_modal.offset_bottom = 230.0
	_reward_modal.visible = false
	_reward_modal.z_index = 130
	_reward_modal.add_theme_stylebox_override("panel", _make_panel_style(Color(0.030, 0.038, 0.050, 0.98), Color(0.95, 0.76, 0.38, 0.90), 2))
	add_child(_reward_modal)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	_reward_modal.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	_reward_title_label = Label.new()
	_reward_title_label.name = "ArenaRewardTitle"
	_reward_title_label.text = Localization.get_text("arena.reward.title", "Victory Reward")
	_reward_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_title_label.add_theme_font_size_override("font_size", 30)
	_reward_title_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.48, 1.0))
	root.add_child(_reward_title_label)

	_reward_hint_label = Label.new()
	_reward_hint_label.text = Localization.get_text("arena.reward.hint", "Choose one reward before the next match.")
	_reward_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_hint_label.add_theme_color_override("font_color", Color(0.74, 0.80, 0.86, 1.0))
	root.add_child(_reward_hint_label)

	_reward_options_box = HBoxContainer.new()
	_reward_options_box.name = "ArenaRewardOptions"
	_reward_options_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_reward_options_box.add_theme_constant_override("separation", 12)
	root.add_child(_reward_options_box)


func _refresh_ui() -> void:
	var run_state: RunState = _get_active_run()
	if run_state == null or not run_state.arena_mode:
		return
	if _run_info_banner != null:
		if _lan_mode:
			var network_label: String = "ONLINE" if NetworkManager.is_online_session() else "LAN"
			_run_info_banner.refresh_run(run_state, -1, -1, "%s R%d" % [network_label, run_state.arena_round])
		else:
			_run_info_banner.refresh()
	var status: Dictionary = _get_arena_status()
	_status_label.text = Localization.get_textf("arena.status", "Round {round} | Wins {wins}/{target} | Losses {losses}/{max_losses}", {
		"round": int(status.get("round", 1)),
		"wins": int(status.get("wins", 0)),
		"target": int(status.get("target_wins", 1)),
		"losses": int(status.get("losses", 0)),
		"max_losses": int(status.get("max_losses", 1)),
	})
	if _lan_mode:
		_status_label.text += "\n%s / %s" % [
			Localization.get_text("lan.arena.ready", "Ready") if bool(status.get("local_ready", false)) else Localization.get_text("lan.arena.preparing", "Preparing"),
			Localization.get_text("lan.arena.opponent_ready", "Opponent ready") if bool(status.get("opponent_ready", false)) else Localization.get_text("lan.arena.opponent_preparing", "Opponent preparing"),
		]
	_next_enemy_label.text = Localization.get_textf("arena.next_enemy", "Next: {enemy}", {
		"enemy": String(status.get("next_enemy_name", "")),
	})
	_refresh_enemy_portrait(String(status.get("next_enemy_id", "")))
	_reroll_button.text = Localization.get_textf("arena.reroll_shop", "Refresh Shop ({cost}G)", {
		"cost": int(status.get("reroll_cost", 0)),
	})
	_reroll_button.disabled = not bool(status.get("can_reroll", false)) or _is_preparation_locked()
	if _start_battle_button != null:
		if _lan_mode:
			var local_ready: bool = NetworkManager.is_local_arena_ready()
			_start_battle_button.text = Localization.get_text("lan.arena.cancel_ready", "Cancel Ready") if local_ready else Localization.get_text("lan.arena.finish_prep", "Finish Preparation")
			_start_battle_button.disabled = _get_equipped_cards().is_empty() or not _get_pending_rewards().is_empty() or NetworkManager.is_waiting_for_reconnect()
		else:
			_start_battle_button.text = Localization.get_text("arena.start_battle", "Start Next Battle")
			_start_battle_button.disabled = Game.get_equipped_cards().is_empty() or Game.has_pending_arena_reward()

	_refresh_offer_list(_card_offers_box, _get_card_offers(), true)
	_refresh_offer_list(_relic_offers_box, _get_relic_offers(), false)
	_loadout_summary_label.text = Localization.get_textf("map.loadout_cost", "Loadout Cost {used} / {limit}", {
		"used": RunState.get_total_loadout_cost(run_state.equipped_cards),
		"limit": run_state.loadout_limit,
	})
	_deck_panel.refresh_card_ids(_get_equipped_cards(), false, "EQUIP", run_state)
	_rebuild_loadout_rows()
	_relic_row.refresh_relic_ids(run_state.relics, Localization.get_text("status.none", "None"))
	_refresh_reward_modal()
	_refresh_developer_panel()


func _get_active_run() -> RunState:
	return NetworkManager.get_local_arena_run() if _lan_mode else Game.current_run


func _get_arena_status() -> Dictionary:
	return NetworkManager.get_local_arena_status() if _lan_mode else Game.get_arena_status()


func _get_card_offers() -> Array[Dictionary]:
	return NetworkManager.get_local_arena_card_offers() if _lan_mode else Game.get_arena_card_offers()


func _get_relic_offers() -> Array[Dictionary]:
	return NetworkManager.get_local_arena_relic_offers() if _lan_mode else Game.get_arena_relic_offers()


func _get_pending_rewards() -> Array[Dictionary]:
	return NetworkManager.get_local_arena_pending_rewards() if _lan_mode else Game.get_arena_pending_rewards()


func _get_loadout_entries() -> Array[Dictionary]:
	return NetworkManager.get_local_arena_loadout_entries() if _lan_mode else Game.get_loadout_entries()


func _get_equipped_cards() -> Array[String]:
	var run_state: RunState = _get_active_run()
	return [] if run_state == null else run_state.equipped_cards.duplicate()


func _is_preparation_locked() -> bool:
	return _lan_mode and (NetworkManager.is_local_arena_ready() or NetworkManager.is_waiting_for_reconnect())


func _refresh_offer_list(parent: VBoxContainer, offers: Array[Dictionary], is_card: bool) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	for offer_index in range(offers.size()):
		var offer_data: Dictionary = offers[offer_index]
		var row: Control = _build_card_offer(offer_data, offer_index) if is_card else _build_relic_offer(offer_data, offer_index)
		parent.add_child(row)
	if offers.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = Localization.get_text("arena.shop_empty", "No offers available.")
		parent.add_child(empty_label)


func _build_card_offer(offer_data: Dictionary, offer_index: int) -> Control:
	var card_id: String = String(offer_data.get("card_id", ""))
	var card_def: CardDef = CardUpgradeResolver.build_effective_card(card_id, _get_active_run())
	var row: HBoxContainer = _create_offer_row(offer_data, "CardOffer_%d" % offer_index)
	if card_def != null:
		var preview: CardButton = CardButton.new()
		preview.name = "ArenaCardOfferPreview_%d" % offer_index
		preview.set_tile_size(OFFER_CARD_SIZE)
		preview.bind_preview(card_def, card_id, false, "SHOP")
		row.add_child(preview)
		_add_offer_info(row, card_def.name, CardInfoFormatter.build_effect_summary(card_def), int(offer_data.get("price", 0)), bool(offer_data.get("held", false)))
	else:
		_add_offer_info(row, card_id, "", int(offer_data.get("price", 0)), bool(offer_data.get("held", false)))
	_add_offer_buttons(row, offer_data, offer_index, true)
	return row.get_parent().get_parent() as Control


func _build_relic_offer(offer_data: Dictionary, offer_index: int) -> Control:
	var relic_id: String = String(offer_data.get("relic_id", ""))
	var relic_def: RelicDef = Database.get_relic(relic_id)
	var row: HBoxContainer = _create_offer_row(offer_data, "RelicOffer_%d" % offer_index)
	var preview: RelicIcon = RelicIcon.new()
	preview.name = "ArenaRelicOfferPreview_%d" % offer_index
	preview.set_icon_size(OFFER_RELIC_SIZE)
	preview.bind_relic_id(relic_id)
	row.add_child(preview)
	if relic_def != null:
		_add_offer_info(row, relic_def.name, relic_def.description, int(offer_data.get("price", 0)), bool(offer_data.get("held", false)))
	else:
		_add_offer_info(row, relic_id, "", int(offer_data.get("price", 0)), bool(offer_data.get("held", false)))
	_add_offer_buttons(row, offer_data, offer_index, false)
	return row.get_parent().get_parent() as Control


func _create_offer_row(offer_data: Dictionary, node_name: String) -> HBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Arena%sFrame" % node_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_offer_style(bool(offer_data.get("held", false)), bool(offer_data.get("bought", false))))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Arena%sRow" % node_name
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	return row


func _add_offer_info(parent: HBoxContainer, title_text: String, description_text: String, price: int, held: bool) -> void:
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	parent.add_child(info)

	var title: Label = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	info.add_child(title)

	var price_row: HBoxContainer = HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 5)
	info.add_child(price_row)
	_add_stat_icon(price_row, "gold")
	var price_label: Label = Label.new()
	price_label.text = "%d" % price
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_row.add_child(price_label)
	if held:
		var held_label: Label = Label.new()
		held_label.text = Localization.get_text("arena.held_badge", "Held")
		held_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.32, 1.0))
		price_row.add_child(held_label)

	var description: Label = Label.new()
	description.text = description_text
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color(0.66, 0.72, 0.76, 1.0))
	info.add_child(description)


func _add_offer_buttons(parent: HBoxContainer, offer_data: Dictionary, offer_index: int, is_card: bool) -> void:
	var actions: VBoxContainer = VBoxContainer.new()
	actions.custom_minimum_size = Vector2(116.0, 0.0)
	actions.add_theme_constant_override("separation", 8)
	parent.add_child(actions)

	var bought: bool = bool(offer_data.get("bought", false))
	var price: int = int(offer_data.get("price", 0))
	var run_state: RunState = _get_active_run()
	var can_buy: bool = not bought and run_state != null and run_state.gold >= price and not _is_preparation_locked()
	var buy_button: Button = Button.new()
	buy_button.text = Localization.get_text("arena.sold", "Sold") if bought else Localization.get_text("arena.buy", "Buy")
	buy_button.disabled = not can_buy
	if is_card:
		buy_button.pressed.connect(Callable(self, "_on_buy_card_offer").bind(offer_index))
	else:
		buy_button.pressed.connect(Callable(self, "_on_buy_relic_offer").bind(offer_index))
	actions.add_child(buy_button)

	var hold_button: Button = Button.new()
	hold_button.text = Localization.get_text("arena.unhold", "Unhold") if bool(offer_data.get("held", false)) else Localization.get_text("arena.hold", "Hold")
	hold_button.disabled = bought or _is_preparation_locked()
	if is_card:
		hold_button.pressed.connect(Callable(self, "_on_toggle_card_hold").bind(offer_index))
	else:
		hold_button.pressed.connect(Callable(self, "_on_toggle_relic_hold").bind(offer_index))
	actions.add_child(hold_button)


func _add_stat_icon(parent: Control, icon_id: String) -> void:
	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(22.0, 22.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = StatIconFactory.get_icon(icon_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)


func _rebuild_loadout_rows() -> void:
	if _inventory_box == null:
		return
	for child in _inventory_box.get_children():
		_inventory_box.remove_child(child)
		child.queue_free()

	var run_state: RunState = _get_active_run()
	for entry in _get_loadout_entries():
		var card_id: String = String(entry.get("card_id", ""))
		var card_def: CardDef = CardUpgradeResolver.build_effective_card(card_id, run_state)
		if card_def == null:
			continue
		_inventory_box.add_child(_build_loadout_row(entry, card_def))


func _build_loadout_row(entry: Dictionary, card_def: CardDef) -> PanelContainer:
	var card_id: String = String(entry.get("card_id", ""))
	var frame: PanelContainer = PanelContainer.new()
	frame.name = "ArenaLoadoutCardFrame_%s" % card_id
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	frame.add_theme_stylebox_override("panel", _make_offer_style(false, false))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	frame.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var preview: CardButton = CardButton.new()
	preview.name = "ArenaLoadoutPreview_%s" % card_id
	preview.set_tile_size(LOADOUT_PREVIEW_SIZE)
	preview.bind_preview(card_def, card_id, false, "LOAD")
	row.add_child(preview)

	var info_box: VBoxContainer = VBoxContainer.new()
	info_box.name = "ArenaLoadoutCardInfo_%s" % card_id
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	info_box.add_theme_constant_override("separation", 7)
	row.add_child(info_box)

	var counts_row: HBoxContainer = HBoxContainer.new()
	counts_row.name = "ArenaLoadoutCountRow_%s" % card_id
	counts_row.alignment = BoxContainer.ALIGNMENT_CENTER
	counts_row.add_theme_constant_override("separation", 8)
	info_box.add_child(counts_row)
	counts_row.add_child(_build_loadout_count_pill("card_owned", int(entry.get("owned_count", 0)), "ArenaOwnedCount_%s" % card_id))
	counts_row.add_child(_build_loadout_count_pill("card_equipped", int(entry.get("equipped_count", 0)), "ArenaEquippedCount_%s" % card_id))

	var actions: HBoxContainer = HBoxContainer.new()
	actions.name = "ArenaLoadoutActions_%s" % card_id
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 7)
	info_box.add_child(actions)

	var equip_button: Button = Button.new()
	equip_button.name = "ArenaEquipButton_%s" % card_id
	equip_button.text = Localization.get_text("map.equip", "Equip")
	equip_button.disabled = not bool(entry.get("can_equip", false)) or _is_preparation_locked()
	equip_button.pressed.connect(_on_equip_card.bind(card_id))
	actions.add_child(equip_button)

	var unequip_button: Button = Button.new()
	unequip_button.name = "ArenaUnequipButton_%s" % card_id
	unequip_button.text = Localization.get_text("map.unequip", "Unequip")
	unequip_button.disabled = not bool(entry.get("can_unequip", false)) or _is_preparation_locked()
	unequip_button.pressed.connect(_on_unequip_card.bind(card_id))
	actions.add_child(unequip_button)

	var sell_value: int = int(entry.get("sell_value", 0))
	var sell_button: Button = Button.new()
	sell_button.name = "ArenaSellButton_%s" % card_id
	sell_button.icon = StatIconFactory.get_icon("gold")
	sell_button.text = Localization.get_textf("map.sell_for", "Sell {amount}", {"amount": sell_value})
	sell_button.disabled = not bool(entry.get("can_sell", false)) or _is_preparation_locked()
	sell_button.pressed.connect(_on_sell_card.bind(card_id))
	actions.add_child(sell_button)
	return frame


func _build_loadout_count_pill(icon_id: String, count: int, node_name: String) -> HBoxContainer:
	var pill: HBoxContainer = HBoxContainer.new()
	pill.name = node_name
	pill.alignment = BoxContainer.ALIGNMENT_CENTER
	pill.add_theme_constant_override("separation", 4)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon: TextureRect = TextureRect.new()
	icon.name = "%sIcon" % node_name
	icon.custom_minimum_size = LOADOUT_COUNT_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = StatIconFactory.get_icon(icon_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(icon)

	var value_label: Label = Label.new()
	value_label.name = "%sValue" % node_name
	value_label.text = str(count)
	value_label.add_theme_font_size_override("font_size", 17)
	value_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.88, 1.0))
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(value_label)
	return pill


func _refresh_reward_modal() -> void:
	if _reward_overlay == null or _reward_modal == null or _reward_options_box == null:
		return
	var rewards: Array[Dictionary] = _get_pending_rewards()
	var show_modal: bool = not rewards.is_empty()
	_reward_overlay.visible = show_modal
	_reward_modal.visible = show_modal
	for child in _reward_options_box.get_children():
		_reward_options_box.remove_child(child)
		child.queue_free()
	if not show_modal:
		return
	var special_reward: bool = bool(rewards[0].get("special", false))
	if _reward_title_label != null:
		_reward_title_label.text = Localization.get_text("arena.special.title", "Special Reward") if special_reward else Localization.get_text("arena.reward.title", "Victory Reward")
	if _reward_hint_label != null:
		_reward_hint_label.text = Localization.get_text("arena.special.hint", "Choose one milestone reward. Its effect lasts for this Arena run.") if special_reward else Localization.get_text("arena.reward.hint", "Choose one reward before the next match.")
	for reward_data in rewards:
		_reward_options_box.add_child(_build_reward_choice(reward_data))


func _build_reward_choice(reward_data: Dictionary) -> Button:
	var reward_id: String = String(reward_data.get("id", ""))
	var reward_kind: String = String(reward_data.get("kind", ""))
	var button: Button = Button.new()
	button.name = "ArenaRewardChoice_%s" % reward_id
	button.text = ""
	button.custom_minimum_size = Vector2(164.0, 244.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _make_offer_style(false, false))
	button.add_theme_stylebox_override("hover", _make_offer_style(true, false))
	button.pressed.connect(_on_choose_reward.bind(reward_id))

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_add_reward_visual(box, reward_data, reward_kind)

	var title: Label = Label.new()
	title.text = String(reward_data.get("label", reward_id))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 17)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)

	var description: Label = Label.new()
	description.text = String(reward_data.get("description", ""))
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 13)
	description.add_theme_color_override("font_color", Color(0.68, 0.74, 0.78, 1.0))
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(description)
	return button


func _add_reward_visual(parent: Control, reward_data: Dictionary, reward_kind: String) -> void:
	if bool(reward_data.get("special", false)) and reward_kind != "special_legendary_card":
		var special_group: VBoxContainer = VBoxContainer.new()
		special_group.alignment = BoxContainer.ALIGNMENT_CENTER
		special_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(special_group)
		_add_stat_icon(special_group, String(reward_data.get("visual_icon", "step")))
		return
	match reward_kind:
		"card", "special_legendary_card":
			var card_id: String = String(reward_data.get("card_id", ""))
			var card_def: CardDef = Database.get_card(card_id)
			if card_def == null:
				return
			var preview: CardButton = CardButton.new()
			preview.set_tile_size(Vector2(96.0, 96.0))
			preview.bind_preview(card_def, card_id, false, "GET")
			preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(preview)
		"relic":
			var relic_icon: RelicIcon = RelicIcon.new()
			relic_icon.set_icon_size(Vector2(82.0, 82.0))
			relic_icon.bind_relic_id(String(reward_data.get("relic_id", "")))
			relic_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(relic_icon)
		"upgrade":
			var upgrade_card_id: String = String(reward_data.get("card_id", ""))
			var next_tier: int = int(reward_data.get("next_tier", 0))
			var upgraded_def: CardDef = CardUpgradeResolver.build_card_at_tier(upgrade_card_id, next_tier)
			if upgraded_def == null:
				return
			var upgrade_preview: CardButton = CardButton.new()
			upgrade_preview.set_tile_size(Vector2(96.0, 96.0))
			upgrade_preview.bind_preview(upgraded_def, upgrade_card_id, false, CardInfoFormatter.format_grade_label(next_tier))
			upgrade_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(upgrade_preview)
		"gold":
			var gold_group: VBoxContainer = VBoxContainer.new()
			gold_group.alignment = BoxContainer.ALIGNMENT_CENTER
			gold_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(gold_group)
			_add_stat_icon(gold_group, "gold")
			var amount_label: Label = Label.new()
			amount_label.text = "+%d" % int(reward_data.get("amount", 0))
			amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			amount_label.add_theme_font_size_override("font_size", 24)
			amount_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.34, 1.0))
			amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gold_group.add_child(amount_label)
		_:
			pass


func _refresh_enemy_portrait(enemy_id: String) -> void:
	if _enemy_portrait == null:
		return
	var portrait_path: String = PORTRAIT_PATH_TEMPLATE % enemy_id
	if ResourceLoader.exists(portrait_path):
		var resource: Resource = load(portrait_path)
		_enemy_portrait.texture = resource as Texture2D
	else:
		_enemy_portrait.texture = null


func _make_panel_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.36)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 4.0)
	return style


func _make_offer_style(held: bool, bought: bool) -> StyleBoxFlat:
	var fill: Color = Color(0.045, 0.055, 0.068, 0.94)
	var border: Color = Color(0.28, 0.42, 0.52, 0.74)
	if held:
		border = Color(1.0, 0.76, 0.28, 0.90)
	if bought:
		fill = Color(0.035, 0.036, 0.040, 0.78)
		border = Color(0.22, 0.24, 0.26, 0.70)
	return _make_panel_style(fill, border, 2 if held else 1)


func _on_buy_card_offer(offer_index: int) -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("buy_card", {"index": offer_index})
	else:
		Game.buy_arena_card_offer(offer_index)
		_refresh_ui()


func _on_buy_relic_offer(offer_index: int) -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("buy_relic", {"index": offer_index})
	else:
		Game.buy_arena_relic_offer(offer_index)
		_refresh_ui()


func _on_toggle_card_hold(offer_index: int) -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("toggle_card_hold", {"index": offer_index})
	else:
		Game.toggle_arena_card_hold(offer_index)
		_refresh_ui()


func _on_toggle_relic_hold(offer_index: int) -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("toggle_relic_hold", {"index": offer_index})
	else:
		Game.toggle_arena_relic_hold(offer_index)
		_refresh_ui()


func _on_reroll_shop() -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("reroll")
	else:
		Game.reroll_arena_shop_for_gold()
		_refresh_ui()


func _on_equip_card(card_id: String) -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("equip", {"card_id": card_id})
	elif Game.equip_card(card_id):
		_refresh_ui()


func _on_unequip_card(card_id: String) -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("unequip", {"card_id": card_id})
	elif Game.unequip_card(card_id):
		_refresh_ui()


func _on_sell_card(card_id: String) -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("sell", {"card_id": card_id})
	elif Game.sell_loadout_card(card_id):
		_refresh_ui()


func _on_choose_reward(reward_id: String) -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("choose_reward", {"reward_id": reward_id})
	elif Game.choose_arena_victory_reward(reward_id):
		_refresh_ui()


func _on_start_battle() -> void:
	if _lan_mode:
		NetworkManager.set_local_arena_ready(not NetworkManager.is_local_arena_ready())
	elif Game.start_next_arena_battle():
		SceneRouter.go_to_battle()


func _on_abandon() -> void:
	if _lan_mode:
		NetworkManager.leave_session("arena_abandoned")
	else:
		Game.abandon_run_to_hub()
	SceneRouter.go_to_hub()


func _on_lan_arena_changed(_snapshot: Dictionary) -> void:
	if _lan_mode and is_inside_tree():
		_refresh_ui()


func _on_lan_arena_action_result(action: String, accepted: bool, result: Dictionary) -> void:
	if not _lan_mode:
		return
	if not accepted:
		AudioManager.play_sfx("ui_error")
		_refresh_ui()
		return
	var gold_delta: int = int(result.get("gold_delta", 0))
	if gold_delta != 0:
		SceneRouter.show_gold_delta(gold_delta)
	match action:
		"buy_card", "reroll":
			AudioManager.play_sfx("shop_buy")
		"buy_relic", "dev_grant_relic":
			AudioManager.play_sfx("relic_gain")
		"toggle_card_hold", "toggle_relic_hold", "set_ready":
			AudioManager.play_sfx("ui_toggle")
		"equip":
			AudioManager.play_sfx("loadout_equip")
		"unequip":
			AudioManager.play_sfx("loadout_unequip")
		"sell", "dev_add_gold":
			AudioManager.play_sfx("gold_gain")
		"choose_reward":
			AudioManager.play_sfx("reward_pick")
		"dev_restore_hp":
			AudioManager.play_sfx("heal_use")
	_refresh_ui()


func _on_lan_match_started(_payload: Dictionary) -> void:
	if _lan_mode:
		SceneRouter.go_to_battle()


func _on_lan_arena_finished(_result: Dictionary) -> void:
	if _lan_mode:
		_go_to_network_lobby()


func _on_lan_session_ended(_reason: String) -> void:
	if _lan_mode:
		SceneRouter.go_to_hub()


func _go_to_network_lobby() -> void:
	SceneRouter.go_to_online_lobby()


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
		[
			{"id": "DevArenaAddGold", "label": Localization.get_text("map.dev.add_gold", "Add 50 Gold"), "callback": Callable(self, "_on_dev_add_gold")},
			{"id": "DevArenaRestoreHp", "label": Localization.get_text("map.dev.restore_hp", "Restore HP"), "callback": Callable(self, "_on_dev_restore_hp")},
			{"id": "DevArenaGrantRelic", "label": Localization.get_text("map.dev.grant_relic", "Grant Relic"), "callback": Callable(self, "_on_dev_grant_relic")},
			{"id": "DevArenaStartBattle", "label": Localization.get_text("arena.dev.start_battle", "Start Battle"), "callback": Callable(self, "_on_start_battle")},
		],
		Localization.get_text("arena.dev.summary", "Arena preparation and progression shortcuts.")
	)


func _on_dev_add_gold() -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("dev_add_gold", {"amount": 50})
	else:
		Game.developer_add_gold(50)
		_refresh_ui()


func _on_dev_restore_hp() -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("dev_restore_hp")
	else:
		Game.developer_restore_hp()
		_refresh_ui()


func _on_dev_grant_relic() -> void:
	if _lan_mode:
		NetworkManager.submit_arena_action("dev_grant_relic")
	else:
		Game.developer_grant_random_relic()
		_refresh_ui()
