extends Control

var _summary_label: RichTextLabel
var _achievement_box: VBoxContainer
var _starter_box: VBoxContainer
var _card_box: VBoxContainer
var _relic_box: VBoxContainer
var _developer_panel: DeveloperPanel


func _ready() -> void:
	Game.current_screen_hint = "meta"
	SaveManager.save_game("meta")

	_build_ui()
	_refresh_ui()
	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 32.0
	margin.offset_top = 24.0
	margin.offset_right = -32.0
	margin.offset_bottom = -24.0
	add_child(margin)

	var root: HBoxContainer = HBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var summary_panel: VBoxContainer = _create_panel(root, Localization.get_text("meta.title", "Meta Progress"))
	_summary_label = RichTextLabel.new()
	_summary_label.fit_content = true
	summary_panel.add_child(_summary_label)

	var back_button: Button = Button.new()
	back_button.text = Localization.get_text("meta.return_hub", "Return to Hub")
	back_button.pressed.connect(func() -> void:
		Game.current_screen_hint = "hub"
		SaveManager.save_game("hub")
		SceneRouter.go_to_hub()
	)
	summary_panel.add_child(back_button)

	var library_button: Button = Button.new()
	library_button.text = Localization.get_text("meta.open_library", "Open Card Library")
	library_button.pressed.connect(func() -> void:
		Game.current_screen_hint = "library"
		SaveManager.save_game("library")
		SceneRouter.go_to_card_library()
	)
	summary_panel.add_child(library_button)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	scroll.add_child(content)

	var achievements_panel: VBoxContainer = _create_panel(content, Localization.get_text("meta.achievements", "Achievements"))
	_achievement_box = VBoxContainer.new()
	_achievement_box.name = "MetaAchievementBox"
	_achievement_box.add_theme_constant_override("separation", 10)
	achievements_panel.add_child(_achievement_box)

	var starters_panel: VBoxContainer = _create_panel(content, Localization.get_text("meta.starters", "Starter Unlocks"))
	_starter_box = VBoxContainer.new()
	_starter_box.name = "MetaStarterBox"
	_starter_box.add_theme_constant_override("separation", 10)
	starters_panel.add_child(_starter_box)

	var cards_panel: VBoxContainer = _create_panel(content, Localization.get_text("meta.cards", "Card Unlocks"))
	_card_box = VBoxContainer.new()
	_card_box.name = "MetaCardBox"
	_card_box.add_theme_constant_override("separation", 10)
	cards_panel.add_child(_card_box)

	var relics_panel: VBoxContainer = _create_panel(content, Localization.get_text("meta.relics", "Relic Unlocks"))
	_relic_box = VBoxContainer.new()
	_relic_box.name = "MetaRelicBox"
	_relic_box.add_theme_constant_override("separation", 10)
	relics_panel.add_child(_relic_box)


func _create_panel(parent: Control, title: String) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var label: Label = Label.new()
	label.text = title
	box.add_child(label)
	return box


func _refresh_ui() -> void:
	var starter_entries: Array[Dictionary] = Game.get_meta_starter_entries()
	var card_entries: Array[Dictionary] = Game.get_meta_card_entries()
	var relic_entries: Array[Dictionary] = Game.get_meta_relic_entries()
	var achievement_entries: Array[Dictionary] = Game.get_meta_achievement_entries()
	_summary_label.text = "\n".join([
		Localization.get_textf("meta.summary.points", "Points: {value}", {"value": Game.get_meta_points()}),
		Localization.get_textf("meta.summary.best_clear", "Best Clear: {value}", {"value": Game.get_best_clear()}),
		Localization.get_textf("meta.summary.steps", "Unlocked Steps: 1-{end}", {"end": Game.get_unlocked_step_tier() * 7}),
		Localization.get_textf("meta.summary.infinite_mode", "Infinite Mode: {value}", {
			"value": Localization.get_text("meta.unlocked", "Unlocked") if Game.is_infinite_mode_unlocked() else Localization.get_text("meta.locked", "Locked"),
		}),
		Localization.get_textf("meta.summary.starters", "Starters: {current} / {total}", {
			"current": _count_bool_entries(starter_entries, "unlocked"),
			"total": starter_entries.size(),
		}),
		Localization.get_textf("meta.summary.cards", "Cards: {current} / {total}", {
			"current": _count_bool_entries(card_entries, "unlocked"),
			"total": card_entries.size(),
		}),
		Localization.get_textf("meta.summary.relics", "Relics: {current} / {total}", {
			"current": _count_bool_entries(relic_entries, "unlocked"),
			"total": relic_entries.size(),
		}),
		Localization.get_textf("meta.summary.achievements", "Achievements: {current} / {total}", {
			"current": _count_bool_entries(achievement_entries, "claimed"),
			"total": achievement_entries.size(),
		}),
		Localization.get_textf("meta.summary.claimable", "Achievement Rewards Ready: {value}", {
			"value": _count_bool_entries(achievement_entries, "claimable"),
		}),
		Localization.get_textf("meta.summary.permanent_bonuses", "Permanent Bonuses: {value}", {
			"value": Game.get_permanent_bonus_summary(),
		}),
	])
	_rebuild_achievements(achievement_entries)
	_rebuild_starters(starter_entries)
	_rebuild_cards(card_entries)
	_rebuild_relics(relic_entries)


func _count_bool_entries(entries: Array[Dictionary], key: String) -> int:
	var count: int = 0
	for entry in entries:
		if bool(entry.get(key, false)):
			count += 1
	return count


func _rebuild_achievements(entries: Array[Dictionary]) -> void:
	_clear_box(_achievement_box)
	for entry in entries:
		var achievement_id: String = String(entry.get("id", ""))

		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		_achievement_box.add_child(row)

		var info: VBoxContainer = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var name_label: Label = Label.new()
		name_label.text = String(entry.get("name", achievement_id))
		info.add_child(name_label)

		var desc_label: Label = Label.new()
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.text = String(entry.get("description", ""))
		info.add_child(desc_label)

		var progress_label: Label = Label.new()
		progress_label.name = "AchievementProgress_%s" % achievement_id
		progress_label.text = Localization.get_textf("meta.achievement_progress", "Progress: {current} / {target}", {
			"current": int(entry.get("current", 0)),
			"target": int(entry.get("target", 0)),
		})
		info.add_child(progress_label)

		var reward_label: Label = Label.new()
		reward_label.name = "AchievementReward_%s" % achievement_id
		reward_label.text = Localization.get_textf("meta.achievement_reward", "Reward: {value}", {
			"value": String(entry.get("reward_text", "")),
		})
		info.add_child(reward_label)

		var status_label: Label = Label.new()
		status_label.name = "AchievementStatus_%s" % achievement_id
		if bool(entry.get("claimed", false)):
			status_label.text = Localization.get_text("meta.claimed", "Claimed")
		elif bool(entry.get("claimable", false)):
			status_label.text = Localization.get_text("meta.ready", "Ready")
		else:
			status_label.text = Localization.get_text("meta.locked", "Locked")
		info.add_child(status_label)

		var claim_button: Button = Button.new()
		claim_button.name = "ClaimAchievement_%s" % achievement_id
		claim_button.text = Localization.get_text("meta.claim", "Claim")
		claim_button.disabled = not bool(entry.get("claimable", false))
		claim_button.pressed.connect(_on_claim_achievement.bind(achievement_id))
		row.add_child(claim_button)


func _rebuild_starters(entries: Array[Dictionary]) -> void:
	_clear_box(_starter_box)
	var meta_points: int = Game.get_meta_points()
	for entry in entries:
		var starter_id: String = String(entry.get("id", ""))

		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		_starter_box.add_child(row)

		var info: VBoxContainer = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var name_label: Label = Label.new()
		name_label.text = Localization.get_textf("meta.cost_line", "{name} | Cost {cost}", {
			"name": String(entry.get("name", starter_id)),
			"cost": int(entry.get("cost", 0)),
		})
		info.add_child(name_label)

		var desc_label: Label = Label.new()
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.text = String(entry.get("description", ""))
		info.add_child(desc_label)

		var status_label: Label = Label.new()
		status_label.name = "StatusStarter_%s" % starter_id
		status_label.text = Localization.get_text("meta.%s" % ("unlocked" if bool(entry.get("unlocked", false)) else "locked"), "Unlocked" if bool(entry.get("unlocked", false)) else "Locked")
		info.add_child(status_label)

		var unlock_button: Button = Button.new()
		unlock_button.name = "UnlockStarter_%s" % starter_id
		unlock_button.text = Localization.get_text("meta.unlock", "Unlock")
		unlock_button.disabled = bool(entry.get("unlocked", false)) or meta_points < int(entry.get("cost", 0))
		unlock_button.pressed.connect(_on_unlock_starter.bind(starter_id))
		row.add_child(unlock_button)


func _rebuild_cards(entries: Array[Dictionary]) -> void:
	_clear_box(_card_box)
	var rarity_order: Array[String] = ["common", "rare", "epic"]
	var meta_points: int = Game.get_meta_points()
	for rarity in rarity_order:
		var section_label: Label = Label.new()
		section_label.text = Localization.get_rarity_name(rarity)
		_card_box.add_child(section_label)

		for entry in entries:
			if String(entry.get("rarity", "")) != rarity:
				continue
			var card_id: String = String(entry.get("id", ""))
			var card_def: CardDef = Database.get_card(card_id)
			if card_def == null:
				continue

			var row: HBoxContainer = HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_theme_constant_override("separation", 10)
			row.name = "MetaCardRow_%s" % card_id
			_card_box.add_child(row)

			var info: VBoxContainer = VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)

			var name_label: Label = Label.new()
			name_label.name = "MetaCard_%s" % card_id
			name_label.text = Localization.get_textf("meta.cost_line", "{name} | Cost {cost}", {
				"name": card_def.name,
				"cost": int(entry.get("cost", 0)),
			})
			name_label.tooltip_text = "%s\n%s\n%s" % [
				card_def.name,
				card_def.description,
				CardInfoFormatter.build_effect_summary(card_def),
			]
			info.add_child(name_label)

			var desc_label: Label = Label.new()
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_label.text = "%s\n%s" % [card_def.description, CardInfoFormatter.build_effect_summary(card_def)]
			info.add_child(desc_label)

			var status_label: Label = Label.new()
			status_label.name = "StatusCard_%s" % card_id
			status_label.text = Localization.get_text("meta.%s" % ("unlocked" if bool(entry.get("unlocked", false)) else "locked"), "Unlocked" if bool(entry.get("unlocked", false)) else "Locked")
			info.add_child(status_label)

			var unlock_button: Button = Button.new()
			unlock_button.name = "UnlockCard_%s" % card_id
			unlock_button.text = Localization.get_text("meta.unlock", "Unlock")
			unlock_button.disabled = bool(entry.get("unlocked", false)) or meta_points < int(entry.get("cost", 0))
			unlock_button.pressed.connect(_on_unlock_card.bind(card_id))
			row.add_child(unlock_button)


func _rebuild_relics(entries: Array[Dictionary]) -> void:
	_clear_box(_relic_box)
	var meta_points: int = Game.get_meta_points()
	for entry in entries:
		var relic_id: String = String(entry.get("id", ""))

		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		_relic_box.add_child(row)

		var relic_icon: RelicIcon = RelicIcon.new()
		relic_icon.set_icon_size(Vector2(72.0, 72.0))
		relic_icon.bind_relic_id(relic_id, not bool(entry.get("unlocked", false)))
		relic_icon.name = "MetaRelic_%s" % relic_id
		row.add_child(relic_icon)

		var info: VBoxContainer = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var name_label: Label = Label.new()
		name_label.text = Localization.get_textf("meta.cost_line", "{name} | Cost {cost}", {
			"name": String(entry.get("name", relic_id)),
			"cost": int(entry.get("cost", 0)),
		})
		info.add_child(name_label)

		var desc_label: Label = Label.new()
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.text = String(entry.get("description", ""))
		info.add_child(desc_label)

		var status_label: Label = Label.new()
		status_label.name = "StatusRelic_%s" % relic_id
		status_label.text = Localization.get_text("meta.%s" % ("unlocked" if bool(entry.get("unlocked", false)) else "locked"), "Unlocked" if bool(entry.get("unlocked", false)) else "Locked")
		info.add_child(status_label)

		var unlock_button: Button = Button.new()
		unlock_button.name = "UnlockRelic_%s" % relic_id
		unlock_button.text = Localization.get_text("meta.unlock", "Unlock")
		unlock_button.disabled = bool(entry.get("unlocked", false)) or meta_points < int(entry.get("cost", 0))
		unlock_button.pressed.connect(_on_unlock_relic.bind(relic_id))
		row.add_child(unlock_button)


func _clear_box(box: VBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _on_unlock_starter(starter_id: String) -> void:
	if Game.unlock_meta_starter(starter_id):
		_refresh_ui()


func _on_unlock_card(card_id: String) -> void:
	if Game.unlock_meta_card(card_id):
		_refresh_ui()


func _on_unlock_relic(relic_id: String) -> void:
	if Game.unlock_meta_relic(relic_id):
		_refresh_ui()


func _on_claim_achievement(achievement_id: String) -> void:
	if Game.claim_meta_achievement(achievement_id):
		_refresh_ui()


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right()
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevMetaAddPoints", "label": Localization.get_text("hub.dev.add_points", "Add 5 Points"), "callback": Callable(self, "_on_dev_add_points")},
			{"id": "DevMetaUnlockTier2", "label": Localization.get_text("meta.dev.unlock_tier_2", "Unlock Steps 8-14"), "callback": Callable(self, "_on_dev_unlock_tier_2")},
			{"id": "DevMetaUnlockTier3", "label": Localization.get_text("meta.dev.unlock_tier_3", "Unlock Steps 15-21"), "callback": Callable(self, "_on_dev_unlock_tier_3")},
			{"id": "DevMetaUnlockTier4", "label": Localization.get_text("meta.dev.unlock_tier_4", "Unlock Steps 22-28"), "callback": Callable(self, "_on_dev_unlock_tier_4")},
			{"id": "DevMetaUnlockInfinite", "label": Localization.get_text("meta.dev.unlock_infinite", "Unlock Infinite Mode"), "callback": Callable(self, "_on_dev_unlock_infinite")},
			{"id": "DevMetaUnlockAll", "label": Localization.get_text("meta.dev.unlock_all", "Unlock All"), "callback": Callable(self, "_on_dev_unlock_all")},
			{"id": "DevMetaReset", "label": Localization.get_text("hub.dev.reset_meta", "Reset Meta"), "callback": Callable(self, "_on_dev_reset_meta")},
			{"id": "DevMetaLibrary", "label": Localization.get_text("meta.dev.open_library", "Open Library"), "callback": Callable(self, "_on_dev_open_library")},
		],
		Localization.get_text("meta.dev.summary", "Testing shortcuts for progression data.")
	)


func _on_dev_add_points() -> void:
	Game.developer_add_points(5)
	_refresh_ui()


func _on_dev_unlock_tier_2() -> void:
	Game.developer_unlock_step_tier(2)
	_refresh_ui()


func _on_dev_unlock_tier_3() -> void:
	Game.developer_unlock_step_tier(3)
	_refresh_ui()


func _on_dev_unlock_tier_4() -> void:
	Game.developer_unlock_step_tier(4)
	_refresh_ui()


func _on_dev_unlock_infinite() -> void:
	Game.developer_unlock_infinite_mode()
	_refresh_ui()


func _on_dev_unlock_all() -> void:
	Game.developer_unlock_all_meta()
	_refresh_ui()


func _on_dev_reset_meta() -> void:
	Game.developer_reset_meta_progress()
	_refresh_ui()


func _on_dev_open_library() -> void:
	Game.current_screen_hint = "library"
	SaveManager.save_game("library")
	SceneRouter.go_to_card_library()
