extends Control

const DEBUG_CARD_SLOT_COUNT := 6

var _info_label: Label
var _developer_panel: DeveloperPanel
var _debug_enemy_option: OptionButton
var _debug_starter_option: OptionButton
var _debug_card_options: Array[CardIconPicker] = []
var _debug_card_grade_options: Array[OptionButton] = []
var _version_history_overlay: ColorRect
var _version_history_content: RichTextLabel


func _ready() -> void:
	Game.stash_active_run_for_hub()
	_build_top_right_actions()
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 80.0
	margin.offset_top = 60.0
	margin.offset_right = -80.0
	margin.offset_bottom = -60.0
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var title: Label = Label.new()
	title.text = Localization.get_text("hub.title", "Hub")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.text = Localization.get_textf("hub.meta_points", "Meta Points: {points}", {
		"points": Game.get_meta_points(),
	})
	root.add_child(_info_label)

	_add_run_mode_row(root, Game.RUN_SETUP_MODE_NORMAL)
	_add_run_mode_row(root, Game.RUN_SETUP_MODE_ARENA)

	if Game.WEB_MULTIPLAYER_ENABLED:
		var online_button: Button = Button.new()
		online_button.name = "WebMultiplayerButton"
		online_button.text = Localization.get_text("hub.web_multiplayer", "Web Multiplayer")
		online_button.pressed.connect(func() -> void:
			Game.current_screen_hint = "online"
			SceneRouter.go_to_online_lobby()
		)
		root.add_child(online_button)

	if Game.is_infinite_mode_unlocked():
		var infinite_button: Button = Button.new()
		infinite_button.name = "InfiniteModeStartButton"
		infinite_button.text = Localization.get_text("hub.infinite_mode", "Infinite Mode")
		infinite_button.pressed.connect(_on_start_infinite_mode)
		root.add_child(infinite_button)

	var meta_button: Button = Button.new()
	meta_button.text = Localization.get_text("hub.meta_progress", "Meta Progress")
	meta_button.pressed.connect(_on_open_meta_progress)
	root.add_child(meta_button)

	var library_button: Button = Button.new()
	library_button.text = Localization.get_text("hub.card_library", "Card Library")
	library_button.pressed.connect(_on_open_card_library)
	root.add_child(library_button)

	_build_version_history_overlay()

	if Game.is_developer_mode_enabled():
		_build_debug_battle_lab(root)
		_build_developer_panel()
		call_deferred("_warm_debug_card_pickers")


func _build_top_right_actions() -> void:
	var actions: HBoxContainer = HBoxContainer.new()
	actions.name = "HubTopActions"
	actions.anchor_left = 1.0
	actions.anchor_top = 0.0
	actions.anchor_right = 1.0
	actions.anchor_bottom = 0.0
	actions.offset_left = -390.0
	actions.offset_top = 22.0
	actions.offset_right = -22.0
	actions.offset_bottom = 76.0
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	actions.z_index = 40
	add_child(actions)

	var history_button: Button = Button.new()
	history_button.name = "VersionHistoryButton"
	history_button.custom_minimum_size = Vector2(270.0, 54.0)
	history_button.text = Localization.get_textf(
		"hub.version_history.button",
		"Version History {version}",
		{"version": GameVersion.get_current_version()}
	)
	history_button.tooltip_text = Localization.get_text(
		"hub.version_history.tooltip",
		"Open version history"
	)
	history_button.icon = StatIconFactory.get_icon("version_history")
	history_button.expand_icon = true
	history_button.pressed.connect(_open_version_history)
	actions.add_child(history_button)

	var settings_button: Button = Button.new()
	settings_button.name = "OpenSettingsButton"
	settings_button.custom_minimum_size = Vector2(58.0, 54.0)
	settings_button.tooltip_text = Localization.get_text("hub.settings.tooltip", "Open settings")
	settings_button.icon = StatIconFactory.get_icon("settings")
	settings_button.expand_icon = true
	settings_button.pressed.connect(_open_settings)
	actions.add_child(settings_button)


func _build_version_history_overlay() -> void:
	_version_history_overlay = ColorRect.new()
	_version_history_overlay.name = "VersionHistoryOverlay"
	_version_history_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_version_history_overlay.color = Color(0.01, 0.02, 0.035, 0.88)
	_version_history_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_version_history_overlay.z_index = 120
	_version_history_overlay.visible = false
	add_child(_version_history_overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 28.0
	center.offset_top = 28.0
	center.offset_right = -28.0
	center.offset_bottom = -28.0
	_version_history_overlay.add_child(center)

	var modal: PanelContainer = PanelContainer.new()
	modal.name = "VersionHistoryModal"
	modal.custom_minimum_size = Vector2(900.0, 700.0)
	center.add_child(modal)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	modal.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	root.add_child(header)

	var title: Label = Label.new()
	title.text = Localization.get_text("hub.version_history.title", "Version History")
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var current_version: Label = Label.new()
	current_version.name = "CurrentVersionLabel"
	current_version.text = Localization.get_textf(
		"hub.version_history.current",
		"Current: {version}",
		{"version": GameVersion.get_current_version()}
	)
	current_version.add_theme_font_size_override("font_size", 20)
	current_version.add_theme_color_override("font_color", Color(0.46, 0.88, 1.0))
	current_version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(current_version)

	var scheme: Label = Label.new()
	scheme.text = Localization.get_textf(
		"hub.version_history.scheme",
		"Version scheme: {scheme}",
		{"scheme": GameVersion.get_scheme()}
	)
	scheme.add_theme_color_override("font_color", Color(0.66, 0.72, 0.78))
	root.add_child(scheme)
	root.add_child(HSeparator.new())

	_version_history_content = RichTextLabel.new()
	_version_history_content.name = "VersionHistoryContent"
	_version_history_content.bbcode_enabled = true
	_version_history_content.fit_content = false
	_version_history_content.scroll_active = true
	_version_history_content.selection_enabled = true
	_version_history_content.custom_minimum_size = Vector2(820.0, 470.0)
	_version_history_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_version_history_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_version_history_content)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(footer)

	var close_button: Button = Button.new()
	close_button.name = "VersionHistoryCloseButton"
	close_button.custom_minimum_size = Vector2(220.0, 48.0)
	close_button.text = Localization.get_text("hub.version_history.close", "Close")
	close_button.pressed.connect(_close_version_history)
	footer.add_child(close_button)

	_refresh_version_history_content()


func _refresh_version_history_content() -> void:
	if _version_history_content == null:
		return
	var language_suffix: String = "ja" if Game.get_language() == "ja" else "en"
	var lines: PackedStringArray = []
	for release: Dictionary in GameVersion.get_releases():
		var version: String = String(release.get("version", ""))
		var date: String = String(release.get("date", ""))
		var title: String = String(release.get("title_%s" % language_suffix, release.get("title_en", "")))
		lines.append("[font_size=24][color=#f4c85c][b]%s[/b][/color]  [color=#7fdcff]%s[/color][/font_size]" % [version, date])
		lines.append("[font_size=20][b]%s[/b][/font_size]" % title)
		var raw_changes: Variant = release.get("changes_%s" % language_suffix, release.get("changes_en", []))
		if raw_changes is Array:
			for raw_change: Variant in raw_changes:
				lines.append("  [color=#c9d7e2]- %s[/color]" % String(raw_change))
		lines.append("")
	_version_history_content.text = "\n".join(lines)
	_version_history_content.scroll_to_line(0)


func _open_version_history() -> void:
	if _version_history_overlay == null:
		return
	_refresh_version_history_content()
	_version_history_overlay.visible = true
	AudioManager.play_sfx("ui_toggle")


func _close_version_history() -> void:
	if _version_history_overlay == null:
		return
	_version_history_overlay.visible = false
	AudioManager.play_sfx("ui_toggle")


func _open_settings() -> void:
	Game.open_settings("hub")
	SceneRouter.go_to_settings()


func _unhandled_input(event: InputEvent) -> void:
	if _version_history_overlay != null and _version_history_overlay.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_version_history()


func _add_run_mode_row(parent: VBoxContainer, mode: String) -> void:
	var is_arena: bool = mode == Game.RUN_SETUP_MODE_ARENA
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ArenaModeButtonRow" if is_arena else "NormalModeButtonRow"
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var start_button: Button = Button.new()
	start_button.name = "ArenaStartButton" if is_arena else "RunStartButton"
	start_button.text = Localization.get_text(
		"hub.arena_start" if is_arena else "hub.run_start",
		"Arena Mode" if is_arena else "Run Start"
	)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.pressed.connect(func() -> void:
		SceneRouter.go_to_run_setup(mode)
	)
	row.add_child(start_button)

	if not Game.has_suspended_run(mode):
		return
	var continue_button: Button = Button.new()
	continue_button.name = "ContinueArenaRunButton" if is_arena else "ContinueNormalRunButton"
	continue_button.text = Localization.get_text(
		"hub.continue_arena" if is_arena else "hub.continue_normal",
		"Continue Arena" if is_arena else "Continue Run"
	)
	continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	continue_button.pressed.connect(SceneRouter.continue_suspended_run.bind(mode))
	row.add_child(continue_button)


func _build_debug_battle_lab(parent: Control) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "DebugBattleLab"
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title: Label = Label.new()
	title.text = Localization.get_text("hub.debug_battle_lab", "Debug Battle Lab")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_debug_enemy_option = _create_debug_option(
		"DebugEnemyOption",
		Game.get_debug_battle_enemy_entries(),
		"scout",
		false
	)
	_add_option_row(box, Localization.get_text("hub.debug_enemy", "Enemy"), _debug_enemy_option)

	_debug_starter_option = _create_debug_option(
		"DebugStarterOption",
		Game.get_debug_battle_starter_entries(),
		"balanced",
		false
	)
	_add_option_row(box, Localization.get_text("hub.debug_starter", "Starter"), _debug_starter_option)

	var cards_label: Label = Label.new()
	cards_label.text = Localization.get_text("hub.debug_loadout", "Loadout")
	box.add_child(cards_label)

	var card_grid: GridContainer = GridContainer.new()
	card_grid.name = "DebugCardSlotGrid"
	card_grid.columns = 3
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_grid.add_theme_constant_override("h_separation", 10)
	card_grid.add_theme_constant_override("v_separation", 10)
	box.add_child(card_grid)

	var card_entries: Array[Dictionary] = Game.get_debug_battle_card_entries()
	var default_cards: Array[String] = ["quick_slash", "strike", "guard", "heavy_swing", "delay_step", "reload"]
	_debug_card_options.clear()
	_debug_card_grade_options.clear()
	for slot_index in range(DEBUG_CARD_SLOT_COUNT):
		var default_card_id: String = default_cards[slot_index] if slot_index < default_cards.size() else "quick_slash"
		var option: CardIconPicker = _create_debug_card_picker(
			"DebugCardSlot%d" % slot_index,
			card_entries,
			default_card_id,
			true
		)
		var grade_option: OptionButton = _create_debug_grade_option("DebugCardGradeSlot%d" % slot_index)
		_debug_card_options.append(option)
		_debug_card_grade_options.append(grade_option)
		_add_card_slot_row(
			card_grid,
			Localization.get_textf("hub.debug_card_slot", "Card {index}", {"index": slot_index + 1}),
			option,
			grade_option
		)

	var start_button: Button = Button.new()
	start_button.name = "DevCustomBattleStart"
	start_button.text = Localization.get_text("hub.debug_start_custom_battle", "Start Custom Battle")
	start_button.pressed.connect(_on_dev_start_custom_battle)
	box.add_child(start_button)


func _add_option_row(parent: Control, label_text: String, option: OptionButton) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label: Label = Label.new()
	label.custom_minimum_size = Vector2(120.0, 0.0)
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)


func _add_card_slot_row(parent: Control, label_text: String, card_option: CardIconPicker, grade_option: OptionButton) -> void:
	var slot_box: VBoxContainer = VBoxContainer.new()
	slot_box.name = "DebugCardSlotCell_%s" % card_option.name
	slot_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_box.add_theme_constant_override("separation", 5)
	parent.add_child(slot_box)

	var label: Label = Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_box.add_child(label)

	card_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_box.add_child(card_option)

	var grade_row: HBoxContainer = HBoxContainer.new()
	grade_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grade_row.add_theme_constant_override("separation", 6)
	slot_box.add_child(grade_row)

	var grade_label: Label = Label.new()
	grade_label.text = Localization.get_text("hub.debug_grade", "Grade")
	grade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grade_row.add_child(grade_label)

	grade_option.custom_minimum_size = Vector2(86.0, 0.0)
	grade_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grade_row.add_child(grade_option)


func _create_debug_option(name: String, entries: Array[Dictionary], default_id: String, include_empty: bool) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.name = name
	if include_empty:
		option.add_item(Localization.get_text("hub.debug_empty_slot", "Empty"))
		option.set_item_metadata(option.item_count - 1, "")
	for entry in entries:
		var entry_id: String = String(entry.get("id", ""))
		if entry_id == "":
			continue
		option.add_item("%s [%s]" % [String(entry.get("name", entry_id)), entry_id])
		option.set_item_metadata(option.item_count - 1, entry_id)
	_select_option_by_metadata(option, default_id)
	return option


func _create_debug_card_picker(name: String, entries: Array[Dictionary], default_id: String, include_empty: bool) -> CardIconPicker:
	var picker: CardIconPicker = CardIconPicker.new()
	picker.name = name
	picker.setup(entries, default_id, include_empty)
	return picker


func _create_debug_grade_option(name: String, default_tier: int = 0) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.name = name
	for tier in range(CardUpgradeResolver.MAX_TIER + 1):
		option.add_item(CardInfoFormatter.format_grade_label(tier))
		option.set_item_metadata(option.item_count - 1, tier)
	option.select(clampi(default_tier, 0, CardUpgradeResolver.MAX_TIER))
	return option


func _warm_debug_card_pickers() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	for picker in _debug_card_options:
		if picker == null or not is_instance_valid(picker):
			continue
		picker.warm_popup_choices()
		if not is_inside_tree():
			return
		await get_tree().process_frame


func _select_option_by_metadata(option: OptionButton, target_id: String) -> void:
	for index in range(option.item_count):
		if String(option.get_item_metadata(index)) == target_id:
			option.select(index)
			return
	if option.item_count > 0:
		option.select(0)


func _on_dev_start_custom_battle() -> void:
	var enemy_id: String = _get_selected_option_id(_debug_enemy_option)
	var starter_id: String = _get_selected_option_id(_debug_starter_option)
	var card_ids: Array[String] = []
	var card_tiers: Dictionary = {}
	for slot_index in range(_debug_card_options.size()):
		var option: CardIconPicker = _debug_card_options[slot_index]
		var card_id: String = option.get_selected_card_id()
		if card_id != "":
			card_ids.append(card_id)
			var selected_tier: int = _get_selected_grade(_debug_card_grade_options[slot_index])
			card_tiers[card_id] = maxi(int(card_tiers.get(card_id, 0)), selected_tier)
	Game.developer_open_custom_battle(enemy_id, starter_id, card_ids, card_tiers)
	SceneRouter.go_to_battle()


func _get_selected_option_id(option: OptionButton) -> String:
	if option == null or option.item_count == 0:
		return ""
	var selected_index: int = option.selected
	if selected_index < 0 or selected_index >= option.item_count:
		return ""
	return String(option.get_item_metadata(selected_index))


func _get_selected_grade(option: OptionButton) -> int:
	if option == null or option.item_count == 0:
		return 0
	var selected_index: int = option.selected
	if selected_index < 0 or selected_index >= option.item_count:
		return 0
	return clampi(int(option.get_item_metadata(selected_index)), 0, CardUpgradeResolver.MAX_TIER)


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right(92.0)
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevStartRun", "label": Localization.get_text("hub.dev.quick_run", "Quick Run"), "callback": Callable(self, "_on_dev_quick_run")},
			{"id": "DevStartArena", "label": Localization.get_text("hub.dev.quick_arena", "Quick Arena"), "callback": Callable(self, "_on_dev_quick_arena")},
			{"id": "DevOpenBattle", "label": Localization.get_text("hub.dev.open_battle", "Open Battle"), "callback": Callable(self, "_on_dev_open_battle")},
			{"id": "DevOpenReward", "label": Localization.get_text("hub.dev.open_reward", "Open Reward"), "callback": Callable(self, "_on_dev_open_reward")},
			{"id": "DevOpenResult", "label": Localization.get_text("hub.dev.open_result", "Open Result"), "callback": Callable(self, "_on_dev_open_result")},
			{"id": "DevAddPoints", "label": Localization.get_text("hub.dev.add_points", "Add 5 Points"), "callback": Callable(self, "_on_dev_add_points")},
			{"id": "DevUnlockAll", "label": Localization.get_text("hub.dev.unlock_all", "Unlock All Meta"), "callback": Callable(self, "_on_dev_unlock_all")},
			{"id": "DevResetMeta", "label": Localization.get_text("hub.dev.reset_meta", "Reset Meta"), "callback": Callable(self, "_on_dev_reset_meta")},
			{"id": "DevToggleOff", "label": Localization.get_text("hub.dev.turn_off", "Turn Off"), "callback": Callable(self, "_on_dev_turn_off")},
		],
		Localization.get_text("hub.dev.summary", "Quick scene access and meta control for manual testing.")
	)


func _on_dev_quick_run() -> void:
	Game.developer_start_run("balanced")
	SceneRouter.go_to_map()


func _on_dev_quick_arena() -> void:
	Game.developer_start_arena("balanced")
	SceneRouter.go_to_arena()


func _on_dev_open_battle() -> void:
	Game.developer_open_battle("scout")
	SceneRouter.go_to_battle()


func _on_dev_open_reward() -> void:
	Game.developer_open_reward()
	SceneRouter.go_to_reward()


func _on_dev_open_result() -> void:
	Game.developer_open_result()
	SceneRouter.go_to_result()


func _on_dev_add_points() -> void:
	Game.developer_add_points(5)
	_info_label.text = Localization.get_textf("hub.meta_points", "Meta Points: {points}", {
		"points": Game.get_meta_points(),
	})


func _on_dev_unlock_all() -> void:
	Game.developer_unlock_all_meta()
	_info_label.text = Localization.get_text("hub.meta_unlocked_all", "Unlocked all meta entries.")


func _on_dev_reset_meta() -> void:
	Game.developer_reset_meta_progress()
	_info_label.text = Localization.get_text("hub.meta_reset", "Meta progress reset.")


func _on_dev_turn_off() -> void:
	Game.set_developer_mode_enabled(false)
	SceneRouter.go_to_hub()


func _on_open_meta_progress() -> void:
	Game.current_screen_hint = "meta"
	SceneRouter.go_to_meta_progress()


func _on_open_card_library() -> void:
	Game.current_screen_hint = "library"
	SaveManager.request_save("library")
	SceneRouter.go_to_card_library()


func _on_start_infinite_mode() -> void:
	if Game.start_infinite_run():
		SceneRouter.go_to_map()
