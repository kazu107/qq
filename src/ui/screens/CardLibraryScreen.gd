extends Control

var _summary_label: Label
var _cards_box: VBoxContainer
var _developer_panel: DeveloperPanel


func _ready() -> void:
	Game.current_screen_hint = "library"
	SaveManager.save_game("library")

	_build_ui()
	_refresh_ui()
	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 28.0
	margin.offset_top = 24.0
	margin.offset_right = -28.0
	margin.offset_bottom = -24.0
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title: Label = Label.new()
	title.text = Localization.get_text("library.title", "Card Library")
	root.add_child(title)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_summary_label)

	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	root.add_child(action_row)

	var meta_button: Button = Button.new()
	meta_button.text = Localization.get_text("library.open_meta", "Open Meta Progress")
	meta_button.pressed.connect(func() -> void:
		Game.current_screen_hint = "meta"
		SceneRouter.go_to_meta_progress()
	)
	action_row.add_child(meta_button)

	var hub_button: Button = Button.new()
	hub_button.text = Localization.get_text("library.return_hub", "Return to Hub")
	hub_button.pressed.connect(func() -> void:
		Game.current_screen_hint = "hub"
		SaveManager.save_game("hub")
		SceneRouter.go_to_hub()
	)
	action_row.add_child(hub_button)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_cards_box = VBoxContainer.new()
	_cards_box.name = "LibraryCards"
	_cards_box.add_theme_constant_override("separation", 12)
	scroll.add_child(_cards_box)


func _refresh_ui() -> void:
	var summary: Dictionary = Game.get_meta_summary()
	_summary_label.text = Localization.get_textf(
		"library.summary",
		"Unlocked {current} / {total} cards. Locked cards stay visible here so you can plan purchases.",
		{
			"current": int(summary.get("card_unlocked", 0)),
			"total": int(summary.get("card_total", 0)),
		}
	)
	_rebuild_card_rows()


func _rebuild_card_rows() -> void:
	for child in _cards_box.get_children():
		_cards_box.remove_child(child)
		child.queue_free()

	var rarity_order: Array[String] = ["common", "rare", "epic"]
	for rarity in rarity_order:
		var section_label: Label = Label.new()
		section_label.text = Localization.get_rarity_name(rarity)
		_cards_box.add_child(section_label)

		for entry in Game.get_meta_card_entries():
			if String(entry.get("rarity", "")) != rarity:
				continue
			var card_id: String = String(entry.get("id", ""))
			var card_def: CardDef = Database.get_card(card_id)
			if card_def == null:
				continue

			var row: HBoxContainer = HBoxContainer.new()
			row.name = "LibraryRow_%s" % card_id
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_theme_constant_override("separation", 10)
			_cards_box.add_child(row)

			var preview: CardButton = CardButton.new()
			preview.name = "LibraryCard_%s" % card_id
			preview.set_tile_size(Vector2(96.0, 96.0))
			preview.bind_preview(card_def, card_id, false, "LIB")
			if not bool(entry.get("unlocked", false)):
				preview.modulate = Color(0.55, 0.55, 0.55, 1.0)
			row.add_child(preview)

			var info: VBoxContainer = VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)

			var name_label: Label = Label.new()
			name_label.text = "%s | %s" % [card_def.name, Localization.get_rarity_name(rarity)]
			info.add_child(name_label)

			var status_label: Label = Label.new()
			status_label.name = "LibraryStatus_%s" % card_id
			if bool(entry.get("unlocked", false)):
				status_label.text = Localization.get_text("meta.unlocked", "Unlocked")
			else:
				status_label.text = Localization.get_textf("library.locked_cost", "Locked | Unlock cost {cost}", {
					"cost": int(entry.get("cost", 0)),
				})
			info.add_child(status_label)

			var desc_label: Label = Label.new()
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_label.text = "%s\n%s" % [card_def.description, CardInfoFormatter.build_effect_summary(card_def)]
			info.add_child(desc_label)


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right()
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevLibraryAddPoints", "label": Localization.get_text("hub.dev.add_points", "Add 5 Points"), "callback": Callable(self, "_on_dev_add_points")},
			{"id": "DevLibraryUnlockAll", "label": Localization.get_text("meta.dev.unlock_all", "Unlock All"), "callback": Callable(self, "_on_dev_unlock_all")},
			{"id": "DevLibraryReset", "label": Localization.get_text("hub.dev.reset_meta", "Reset Meta"), "callback": Callable(self, "_on_dev_reset_meta")},
			{"id": "DevLibraryMeta", "label": Localization.get_text("library.dev.open_meta", "Open Meta"), "callback": Callable(self, "_on_dev_open_meta")},
		],
		Localization.get_text("library.dev.summary", "Manual helpers for library and unlock verification.")
	)


func _on_dev_add_points() -> void:
	Game.developer_add_points(5)
	_refresh_ui()


func _on_dev_unlock_all() -> void:
	Game.developer_unlock_all_meta()
	_refresh_ui()


func _on_dev_reset_meta() -> void:
	Game.developer_reset_meta_progress()
	_refresh_ui()


func _on_dev_open_meta() -> void:
	Game.current_screen_hint = "meta"
	SceneRouter.go_to_meta_progress()
