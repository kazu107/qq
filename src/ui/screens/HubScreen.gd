extends Control

const DEBUG_CARD_SLOT_COUNT := 6

var _info_label: Label
var _developer_panel: DeveloperPanel
var _debug_enemy_option: OptionButton
var _debug_starter_option: OptionButton
var _debug_card_options: Array[OptionButton] = []
var _debug_card_grade_options: Array[OptionButton] = []


func _ready() -> void:
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

	var start_button: Button = Button.new()
	start_button.text = Localization.get_text("hub.run_start", "Run Start")
	start_button.pressed.connect(func() -> void:
		SceneRouter.go_to_run_setup()
	)
	root.add_child(start_button)

	var meta_button: Button = Button.new()
	meta_button.text = Localization.get_text("hub.meta_progress", "Meta Progress")
	meta_button.pressed.connect(_on_open_meta_progress)
	root.add_child(meta_button)

	var library_button: Button = Button.new()
	library_button.text = Localization.get_text("hub.card_library", "Card Library")
	library_button.pressed.connect(_on_open_card_library)
	root.add_child(library_button)

	var settings_button: Button = Button.new()
	settings_button.name = "OpenSettingsButton"
	settings_button.text = Localization.get_text("hub.settings", "Settings")
	settings_button.pressed.connect(func() -> void:
		Game.open_settings("hub")
		SceneRouter.go_to_settings()
	)
	root.add_child(settings_button)

	if Game.is_developer_mode_enabled():
		_build_debug_battle_lab(root)
		_build_developer_panel()


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

	var card_entries: Array[Dictionary] = Game.get_debug_battle_card_entries()
	var default_cards: Array[String] = ["quick_slash", "strike", "guard", "heavy_swing", "delay_step", "reload"]
	_debug_card_options.clear()
	_debug_card_grade_options.clear()
	for slot_index in range(DEBUG_CARD_SLOT_COUNT):
		var default_card_id: String = default_cards[slot_index] if slot_index < default_cards.size() else "quick_slash"
		var option: OptionButton = _create_debug_option(
			"DebugCardSlot%d" % slot_index,
			card_entries,
			default_card_id,
			true
		)
		var grade_option: OptionButton = _create_debug_grade_option("DebugCardGradeSlot%d" % slot_index)
		_debug_card_options.append(option)
		_debug_card_grade_options.append(grade_option)
		_add_card_slot_row(
			box,
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


func _add_card_slot_row(parent: Control, label_text: String, card_option: OptionButton, grade_option: OptionButton) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label: Label = Label.new()
	label.custom_minimum_size = Vector2(120.0, 0.0)
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	card_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(card_option)

	var grade_label: Label = Label.new()
	grade_label.custom_minimum_size = Vector2(58.0, 0.0)
	grade_label.text = Localization.get_text("hub.debug_grade", "Grade")
	grade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(grade_label)

	grade_option.custom_minimum_size = Vector2(96.0, 0.0)
	row.add_child(grade_option)


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


func _create_debug_grade_option(name: String, default_tier: int = 0) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.name = name
	for tier in range(CardUpgradeResolver.MAX_TIER + 1):
		option.add_item(CardInfoFormatter.format_grade_label(tier))
		option.set_item_metadata(option.item_count - 1, tier)
	option.select(clampi(default_tier, 0, CardUpgradeResolver.MAX_TIER))
	return option


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
		var option: OptionButton = _debug_card_options[slot_index]
		var card_id: String = _get_selected_option_id(option)
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
	_developer_panel.pin_top_right()
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevStartRun", "label": Localization.get_text("hub.dev.quick_run", "Quick Run"), "callback": Callable(self, "_on_dev_quick_run")},
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
