extends Control

const PORTRAIT_PATH_TEMPLATE := "res://assets/portraits/%s.png"
const OFFER_CARD_SIZE: Vector2 = Vector2(104.0, 104.0)
const OFFER_RELIC_SIZE: Vector2 = Vector2(72.0, 72.0)

var _run_info_banner: RunInfoBanner
var _status_label: Label
var _next_enemy_label: Label
var _enemy_portrait: TextureRect
var _card_offers_box: VBoxContainer
var _relic_offers_box: VBoxContainer
var _deck_panel: CardHandPanel
var _relic_row: RelicIconRow
var _reroll_button: Button
var _start_battle_button: Button
var _developer_panel: DeveloperPanel


func _ready() -> void:
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

	_start_battle_button = Button.new()
	_start_battle_button.name = "ArenaStartBattleButton"
	_start_battle_button.text = Localization.get_text("arena.start_battle", "Start Next Battle")
	_start_battle_button.custom_minimum_size = Vector2(190.0, 42.0)
	_start_battle_button.pressed.connect(_on_start_battle)
	header.add_child(_start_battle_button)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)

	_build_status_panel(body)
	_build_shop_panel(body)
	_build_loadout_panel(body)


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
	var box: VBoxContainer = _create_panel(parent, Localization.get_text("arena.panel.loadout", "Arena Loadout"), Vector2(360.0, 0.0))
	box.add_theme_constant_override("separation", 12)

	_deck_panel = CardHandPanel.new()
	_deck_panel.name = "ArenaEquippedDeck"
	_deck_panel.set_interactive(false)
	_deck_panel.set_tile_size(Vector2(86.0, 86.0))
	box.add_child(_deck_panel)

	var relic_title: Label = Label.new()
	relic_title.text = Localization.get_text("arena.owned_relics", "Owned Relics")
	box.add_child(relic_title)

	_relic_row = RelicIconRow.new()
	_relic_row.name = "ArenaOwnedRelics"
	_relic_row.set_icon_size(Vector2(42.0, 42.0))
	box.add_child(_relic_row)

	var back_button: Button = Button.new()
	back_button.text = Localization.get_text("arena.abandon", "Abandon To Hub")
	back_button.pressed.connect(_on_abandon)
	box.add_child(back_button)


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


func _refresh_ui() -> void:
	if Game.current_run == null or not Game.current_run.arena_mode:
		return
	if _run_info_banner != null:
		_run_info_banner.refresh()
	var status: Dictionary = Game.get_arena_status()
	_status_label.text = Localization.get_textf("arena.status", "Round {round} | Wins {wins}/{target} | Losses {losses}/{max_losses}", {
		"round": int(status.get("round", 1)),
		"wins": int(status.get("wins", 0)),
		"target": int(status.get("target_wins", 1)),
		"losses": int(status.get("losses", 0)),
		"max_losses": int(status.get("max_losses", 1)),
	})
	_next_enemy_label.text = Localization.get_textf("arena.next_enemy", "Next: {enemy}", {
		"enemy": String(status.get("next_enemy_name", "")),
	})
	_refresh_enemy_portrait(String(status.get("next_enemy_id", "")))
	_reroll_button.text = Localization.get_textf("arena.reroll_shop", "Refresh Shop ({cost}G)", {
		"cost": int(status.get("reroll_cost", 0)),
	})
	_reroll_button.disabled = not bool(status.get("can_reroll", false))
	_start_battle_button.disabled = Game.get_equipped_cards().is_empty()

	_refresh_offer_list(_card_offers_box, Game.get_arena_card_offers(), true)
	_refresh_offer_list(_relic_offers_box, Game.get_arena_relic_offers(), false)
	_deck_panel.refresh_card_ids(Game.get_equipped_cards(), false, "EQUIP", Game.current_run)
	_relic_row.refresh_relic_ids(Game.current_run.relics, Localization.get_text("status.none", "None"))
	_refresh_developer_panel()


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
	var card_def: CardDef = Database.get_card(card_id)
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
	var can_buy: bool = not bought and Game.current_run != null and Game.current_run.gold >= price
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
	hold_button.disabled = bought
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
	if Game.buy_arena_card_offer(offer_index):
		_refresh_ui()
	else:
		_refresh_ui()


func _on_buy_relic_offer(offer_index: int) -> void:
	if Game.buy_arena_relic_offer(offer_index):
		_refresh_ui()
	else:
		_refresh_ui()


func _on_toggle_card_hold(offer_index: int) -> void:
	Game.toggle_arena_card_hold(offer_index)
	_refresh_ui()


func _on_toggle_relic_hold(offer_index: int) -> void:
	Game.toggle_arena_relic_hold(offer_index)
	_refresh_ui()


func _on_reroll_shop() -> void:
	if Game.reroll_arena_shop_for_gold():
		_refresh_ui()
	else:
		_refresh_ui()


func _on_start_battle() -> void:
	if Game.start_next_arena_battle():
		SceneRouter.go_to_battle()


func _on_abandon() -> void:
	Game.abandon_run_to_hub()
	SceneRouter.go_to_hub()


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
	Game.developer_add_gold(50)
	_refresh_ui()


func _on_dev_restore_hp() -> void:
	Game.developer_restore_hp()
	_refresh_ui()


func _on_dev_grant_relic() -> void:
	Game.developer_grant_random_relic()
	_refresh_ui()
