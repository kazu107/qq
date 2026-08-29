extends Control

var _selected_starter_id: String = ""
var _selected_name_label: Label
var _details_label: RichTextLabel
var _start_button: Button
var _starter_cards_panel: CardHandPanel
var _developer_panel: DeveloperPanel
var _starter_stats_grid: GridContainer
var _model_preview: StarterModelPreview
var _hp_value_label: Label
var _attack_value_label: Label
var _speed_value_label: Label
var _deck_count_label: Label
var _card_count_label: Label
var _starter_buttons: Dictionary = {}
var _starter_indicators: Dictionary = {}
var _starter_button_group: ButtonGroup
var _is_arena_setup: bool = false
var _compact_layout: bool = false


func _ready() -> void:
	_is_arena_setup = Game.get_run_setup_mode() == Game.RUN_SETUP_MODE_ARENA
	_compact_layout = get_viewport_rect().size.y < 850.0
	_build_page()
	_refresh_details()

	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _build_page() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "RunSetupPageMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var outer_margin: int = 20 if _compact_layout else 32
	margin.add_theme_constant_override("margin_left", outer_margin)
	margin.add_theme_constant_override("margin_top", 16 if _compact_layout else 24)
	margin.add_theme_constant_override("margin_right", outer_margin)
	margin.add_theme_constant_override("margin_bottom", 18 if _compact_layout else 28)
	add_child(margin)

	var page_root: VBoxContainer = VBoxContainer.new()
	page_root.name = "RunSetupPageRoot"
	page_root.add_theme_constant_override("separation", 14 if _compact_layout else 18)
	margin.add_child(page_root)

	_build_header(page_root)

	var columns: HBoxContainer = HBoxContainer.new()
	columns.name = "RunSetupColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14 if _compact_layout else 18)
	page_root.add_child(columns)

	_build_deck_list(columns)
	_build_model_column(columns)
	_build_detail_column(columns)


func _build_header(parent: VBoxContainer) -> void:
	var header: HBoxContainer = HBoxContainer.new()
	header.name = "RunSetupHeader"
	header.add_theme_constant_override("separation", 14)
	parent.add_child(header)

	var title_group: VBoxContainer = VBoxContainer.new()
	title_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_group.add_theme_constant_override("separation", 1)
	header.add_child(title_group)

	var title: Label = Label.new()
	title.name = "RunSetupTitle"
	title.text = Localization.get_text("run_setup.title", "Select Starter Loadout")
	title.add_theme_font_size_override("font_size", 27 if _compact_layout else 34)
	title.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	title_group.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.name = "RunSetupSubtitle"
	subtitle.text = Localization.get_text(
		"run_setup.subtitle",
		"Compare each frame, inspect its opening hand, then choose your combat loadout."
	)
	subtitle.add_theme_font_size_override("font_size", 14 if _compact_layout else 16)
	subtitle.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	title_group.add_child(subtitle)

	var mode_chip: PanelContainer = PanelContainer.new()
	mode_chip.name = "RunSetupModeChip"
	mode_chip.custom_minimum_size = Vector2(150.0, 44.0)
	mode_chip.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.06, 0.14, 0.20, 0.96), UiTheme.ACCENT_BLUE, 1, 14)
	)
	header.add_child(mode_chip)

	var mode_label: Label = Label.new()
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_label.text = Localization.get_text(
		"run_setup.mode.arena" if _is_arena_setup else "run_setup.mode.normal",
		"ARENA MODE" if _is_arena_setup else "NORMAL RUN"
	)
	mode_label.add_theme_color_override("font_color", Color(0.48, 0.86, 1.0, 1.0))
	mode_chip.add_child(mode_label)

	var back_button: Button = Button.new()
	back_button.name = "RunSetupBackButton"
	back_button.text = Localization.get_text("run_setup.back", "Back")
	back_button.custom_minimum_size = Vector2(118.0, 44.0)
	back_button.pressed.connect(func() -> void:
		SceneRouter.go_to_hub()
	)
	header.add_child(back_button)


func _build_deck_list(parent: HBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "StarterSelectionPanel"
	panel.custom_minimum_size = Vector2(270.0 if _compact_layout else 320.0, 0.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.78
	panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(UiTheme.PANEL_FILL_DEEP, Color(0.22, 0.40, 0.54, 0.88), 1, 18)
	)
	parent.add_child(panel)

	var margin: MarginContainer = _add_panel_margin(panel, 14 if _compact_layout else 18)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 9)
	margin.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	root.add_child(header)

	var title: Label = Label.new()
	title.text = Localization.get_text("run_setup.deck_list", "Available Decks")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 19 if _compact_layout else 22)
	header.add_child(title)

	_deck_count_label = Label.new()
	_deck_count_label.name = "StarterDeckCount"
	_deck_count_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	header.add_child(_deck_count_label)

	var guide: Label = Label.new()
	guide.text = Localization.get_text(
		"run_setup.deck_list_hint",
		"Select a deck to compare its frame and opening cards."
	)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.add_theme_font_size_override("font_size", 13 if _compact_layout else 15)
	guide.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	root.add_child(guide)

	var divider: ColorRect = ColorRect.new()
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.color = Color(0.24, 0.50, 0.68, 0.34)
	root.add_child(divider)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "StarterSelectionScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)

	var grid: GridContainer = GridContainer.new()
	grid.name = "StarterDeckGrid"
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("v_separation", 9)
	scroll.add_child(grid)

	_starter_button_group = ButtonGroup.new()
	_starter_button_group.allow_unpress = false
	var unlocked_starters: Array[Dictionary] = Game.get_unlocked_starters()
	for starter: Dictionary in unlocked_starters:
		var starter_id: String = String(starter.get("id", ""))
		if starter_id == "":
			continue
		_build_starter_button(grid, starter_id, starter)
		if _selected_starter_id == "":
			_selected_starter_id = starter_id

	_deck_count_label.text = "%d" % unlocked_starters.size()


func _build_starter_button(parent: GridContainer, starter_id: String, starter: Dictionary) -> void:
	var button: Button = Button.new()
	button.name = "StarterButton_%s" % starter_id
	button.custom_minimum_size = Vector2(0.0, 78.0 if _compact_layout else 88.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.button_group = _starter_button_group
	button.add_theme_stylebox_override(
		"normal",
		_make_deck_button_style(Color(0.055, 0.075, 0.098, 0.96), Color(0.20, 0.30, 0.38, 0.92), 1)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_deck_button_style(Color(0.075, 0.125, 0.165, 0.98), UiTheme.ACCENT_BLUE, 2)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_deck_button_style(Color(0.12, 0.16, 0.18, 1.0), UiTheme.ACCENT_GOLD, 2)
	)
	button.add_theme_stylebox_override(
		"focus",
		_make_deck_button_style(Color(0.10, 0.14, 0.17, 0.88), UiTheme.ACCENT_GOLD, 2)
	)
	button.pressed.connect(_select_starter.bind(starter_id))
	parent.add_child(button)

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 13)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 13)
	margin.add_theme_constant_override("margin_bottom", 8)
	button.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 4)
	margin.add_child(content)

	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_row)

	var name_label: Label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = String(starter.get("name", starter_id))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16 if _compact_layout else 18)
	name_row.add_child(name_label)

	var selected_label: Label = Label.new()
	selected_label.name = "StarterDeckSelected_%s" % starter_id
	selected_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selected_label.text = Localization.get_text("run_setup.selected", "SELECTED")
	selected_label.add_theme_font_size_override("font_size", 11 if _compact_layout else 12)
	selected_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	selected_label.visible = false
	name_row.add_child(selected_label)

	var stats: HBoxContainer = HBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("separation", 13)
	content.add_child(stats)
	_add_compact_stat(stats, "hp", int(starter.get("max_hp", 0)))
	_add_compact_stat(stats, "attack", int(starter.get("attack", 0)))
	_add_compact_stat(stats, "speed", int(starter.get("speed", 0)))

	_starter_buttons[starter_id] = button
	_starter_indicators[starter_id] = selected_label


func _build_model_column(parent: HBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "StarterModelPanel"
	panel.custom_minimum_size = Vector2(340.0 if _compact_layout else 430.0, 0.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.10
	panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.025, 0.045, 0.065, 0.98), Color(0.20, 0.66, 0.92, 0.82), 2, 18)
	)
	parent.add_child(panel)

	var margin: MarginContainer = _add_panel_margin(panel, 10 if _compact_layout else 12)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var preview_header: HBoxContainer = HBoxContainer.new()
	root.add_child(preview_header)

	var title: Label = Label.new()
	title.text = Localization.get_text("run_setup.preview_title", "Animated 3D Frame")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18 if _compact_layout else 21)
	preview_header.add_child(title)

	var live_label: Label = Label.new()
	live_label.text = "LIVE 3D"
	live_label.add_theme_font_size_override("font_size", 12)
	live_label.add_theme_color_override("font_color", Color(0.40, 0.92, 1.0, 1.0))
	preview_header.add_child(live_label)

	_model_preview = StarterModelPreview.new()
	_model_preview.name = "StarterModelPreview"
	_model_preview.custom_minimum_size = Vector2(0.0, 330.0 if _compact_layout else 430.0)
	_model_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_model_preview)

	var hint: Label = Label.new()
	hint.text = Localization.get_text(
		"run_setup.preview_hint",
		"The battle-ready stance and equipped frame are previewed in real time."
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12 if _compact_layout else 14)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	root.add_child(hint)


func _build_detail_column(parent: HBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "StarterDetailPanel"
	panel.custom_minimum_size = Vector2(410.0 if _compact_layout else 500.0, 0.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.22
	panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(UiTheme.PANEL_FILL, Color(0.42, 0.48, 0.52, 0.82), 1, 18)
	)
	parent.add_child(panel)

	var margin: MarginContainer = _add_panel_margin(panel, 14 if _compact_layout else 20)
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "StarterDetailContent"
	root.add_theme_constant_override("separation", 8 if _compact_layout else 11)
	margin.add_child(root)

	var kicker: Label = Label.new()
	kicker.text = Localization.get_text("run_setup.selected_deck", "SELECTED DECK")
	kicker.add_theme_font_size_override("font_size", 12 if _compact_layout else 14)
	kicker.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	root.add_child(kicker)

	_selected_name_label = Label.new()
	_selected_name_label.name = "StarterNameLabel"
	_selected_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_selected_name_label.add_theme_font_size_override("font_size", 25 if _compact_layout else 31)
	_selected_name_label.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0, 1.0))
	root.add_child(_selected_name_label)

	_details_label = RichTextLabel.new()
	_details_label.name = "StarterDescriptionLabel"
	_details_label.fit_content = true
	_details_label.scroll_active = false
	_details_label.custom_minimum_size = Vector2(0.0, 48.0 if _compact_layout else 64.0)
	_details_label.add_theme_font_size_override("normal_font_size", 14 if _compact_layout else 16)
	_details_label.add_theme_color_override("default_color", UiTheme.TEXT_MUTED)
	root.add_child(_details_label)

	var divider: ColorRect = ColorRect.new()
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.color = Color(0.52, 0.62, 0.68, 0.26)
	root.add_child(divider)

	var stats_title: Label = Label.new()
	stats_title.text = Localization.get_text("run_setup.frame_stats", "Frame Stats")
	stats_title.add_theme_font_size_override("font_size", 16 if _compact_layout else 18)
	root.add_child(stats_title)

	_starter_stats_grid = GridContainer.new()
	_starter_stats_grid.name = "StarterStatsGrid"
	_starter_stats_grid.columns = 3
	_starter_stats_grid.add_theme_constant_override("h_separation", 9)
	root.add_child(_starter_stats_grid)
	_hp_value_label = _add_stat_card("HP", "hp")
	_attack_value_label = _add_stat_card("Attack", "attack")
	_speed_value_label = _add_stat_card("Speed", "speed")

	var cards_header: HBoxContainer = HBoxContainer.new()
	root.add_child(cards_header)
	var cards_title: Label = Label.new()
	cards_title.text = Localization.get_text("run_setup.starter_cards", "Starter Cards")
	cards_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_title.add_theme_font_size_override("font_size", 16 if _compact_layout else 18)
	cards_header.add_child(cards_title)
	_card_count_label = Label.new()
	_card_count_label.name = "StarterCardCount"
	_card_count_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	cards_header.add_child(_card_count_label)

	_starter_cards_panel = CardHandPanel.new()
	_starter_cards_panel.name = "StarterCards"
	_starter_cards_panel.set_interactive(false)
	_starter_cards_panel.set_tile_size(Vector2(78.0, 78.0) if _compact_layout else Vector2(112.0, 112.0))
	_starter_cards_panel.custom_minimum_size = Vector2(0.0, 158.0 if _compact_layout else 242.0)
	_starter_cards_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_starter_cards_panel)

	_start_button = Button.new()
	_start_button.name = "ArenaStartSelectedButton" if _is_arena_setup else "RunStartSelectedButton"
	_start_button.text = Localization.get_text(
		"run_setup.start_arena" if _is_arena_setup else "run_setup.start",
		"Start Arena" if _is_arena_setup else "Start Run"
	)
	_start_button.custom_minimum_size = Vector2(0.0, 54.0 if _compact_layout else 64.0)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.add_theme_font_size_override("font_size", 18 if _compact_layout else 21)
	_start_button.pressed.connect(_on_start_arena if _is_arena_setup else _on_start)
	root.add_child(_start_button)


func _select_starter(starter_id: String) -> void:
	if _selected_starter_id == starter_id:
		_refresh_selection_state()
		return
	_selected_starter_id = starter_id
	AudioManager.play_sfx("ui_toggle")
	_refresh_details()


func _refresh_details() -> void:
	var starter: Dictionary = Database.get_starter(_selected_starter_id)
	if starter.is_empty():
		_selected_name_label.text = Localization.get_text("run_setup.none_selected", "No starter selected.")
		_details_label.text = ""
		_starter_stats_grid.visible = false
		_starter_cards_panel.refresh_card_ids([], false, "KIT")
		_card_count_label.text = "0"
		_start_button.disabled = true
		_refresh_selection_state()
		return

	var cards: Array[String] = _to_string_array(starter.get("cards", []))
	_selected_name_label.text = String(starter.get("name", ""))
	_details_label.text = String(starter.get("description", ""))
	_model_preview.show_starter(_selected_starter_id)
	_starter_stats_grid.visible = true
	_hp_value_label.text = "%d" % int(starter.get("max_hp", 0))
	_attack_value_label.text = "%d" % int(starter.get("attack", 0))
	_speed_value_label.text = "%d" % int(starter.get("speed", 0))
	_starter_cards_panel.refresh_card_ids(cards, false, "KIT")
	_card_count_label.text = "%d" % cards.size()
	_start_button.disabled = false
	_refresh_selection_state()


func _refresh_selection_state() -> void:
	for raw_starter_id: Variant in _starter_buttons.keys():
		var starter_id: String = String(raw_starter_id)
		var button: Button = _starter_buttons.get(starter_id) as Button
		var indicator: Label = _starter_indicators.get(starter_id) as Label
		var is_selected: bool = starter_id == _selected_starter_id
		if button != null:
			button.set_pressed_no_signal(is_selected)
		if indicator != null:
			indicator.visible = is_selected


func _add_compact_stat(parent: HBoxContainer, stat_id: String, value: int) -> void:
	var item: HBoxContainer = HBoxContainer.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_constant_override("separation", 4)
	parent.add_child(item)

	var icon: TextureRect = TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(18.0, 18.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = StatIconFactory.get_icon(stat_id)
	item.add_child(icon)

	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = "%d" % value
	label.add_theme_font_size_override("font_size", 13 if _compact_layout else 15)
	label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.90, 1.0))
	item.add_child(label)


func _add_stat_card(node_prefix: String, stat_id: String) -> Label:
	var card: PanelContainer = PanelContainer.new()
	card.name = "%sStatItem" % node_prefix
	card.custom_minimum_size = Vector2(0.0, 64.0 if _compact_layout else 78.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = Localization.get_text("stat.%s" % stat_id, node_prefix)
	card.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.035, 0.065, 0.085, 0.92), Color(0.18, 0.42, 0.58, 0.72), 1, 12)
	)
	_starter_stats_grid.add_child(card)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 9)
	card.add_child(row)

	var icon: TextureRect = TextureRect.new()
	icon.name = "%sIcon" % node_prefix
	icon.custom_minimum_size = Vector2(25.0, 25.0) if _compact_layout else Vector2(30.0, 30.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = StatIconFactory.get_icon(stat_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var value_label: Label = Label.new()
	value_label.name = "%sValue" % node_prefix
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 22 if _compact_layout else 27)
	value_label.add_theme_color_override("font_color", Color(0.91, 0.97, 1.0, 1.0))
	row.add_child(value_label)
	return value_label


func _add_panel_margin(panel: PanelContainer, amount: int) -> MarginContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", amount)
	margin.add_theme_constant_override("margin_top", amount)
	margin.add_theme_constant_override("margin_right", amount)
	margin.add_theme_constant_override("margin_bottom", amount)
	panel.add_child(margin)
	return margin


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item: Variant in value:
		result.append(String(item))
	return result


func _make_panel_style(
	fill_color: Color,
	border_color: Color,
	border_width: int,
	corner_radius: int
) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 4.0)
	return style


func _make_deck_button_style(fill_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.24)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


func _on_start() -> void:
	Game.start_new_run(_selected_starter_id)
	SceneRouter.go_to_map()


func _on_start_arena() -> void:
	if Game.start_arena_run(_selected_starter_id):
		SceneRouter.go_to_arena()


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right(20.0, 20.0)
	var actions: Array = []
	for starter: Dictionary in Database.starters:
		var starter_id: String = String(starter.get("id", ""))
		if starter_id == "":
			continue
		var starter_name: String = String(starter.get("name", starter_id))
		actions.append({
			"id": "DevStart_%s" % starter_id,
			"label": Localization.get_textf("run_setup.dev.start_starter", "{name} Start", {"name": starter_name}),
			"callback": Callable(self, "_on_dev_start_starter").bind(starter_id),
		})
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		actions,
		Localization.get_text("run_setup.dev.summary", "Skip selection and start a test run immediately.")
	)


func _on_dev_start_starter(starter_id: String) -> void:
	Game.developer_start_run(starter_id)
	SceneRouter.go_to_map()
