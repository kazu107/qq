extends Control

const BUILD_BATCH_SIZE := 6
const CARD_GRID_COLUMNS: int = 3

var _summary_label: Label
var _cards_grid: GridContainer
var _rarity_filter: OptionButton
var _tag_filter: OptionButton
var _developer_panel: DeveloperPanel
var _content_ready: bool = false
var _content_building: bool = false
var _card_widgets: Dictionary = {}
var _selected_rarity: String = "all"
var _selected_tag: String = "all"


func _ready() -> void:
	Game.current_screen_hint = "library"
	SaveManager.request_save("library")

	_build_ui()
	_refresh_ui()
	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func is_content_ready() -> bool:
	return _content_ready


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
		SaveManager.request_save("hub")
		SceneRouter.go_to_hub()
	)
	action_row.add_child(hub_button)

	var filter_row: HBoxContainer = HBoxContainer.new()
	filter_row.name = "LibraryFilterRow"
	filter_row.add_theme_constant_override("separation", 10)
	root.add_child(filter_row)

	var rarity_label: Label = Label.new()
	rarity_label.text = Localization.get_text("library.filter.rarity", "レア度")
	rarity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	filter_row.add_child(rarity_label)

	_rarity_filter = OptionButton.new()
	_rarity_filter.name = "LibraryRarityFilter"
	_rarity_filter.custom_minimum_size = Vector2(150.0, 0.0)
	_rarity_filter.item_selected.connect(_on_rarity_filter_selected)
	filter_row.add_child(_rarity_filter)

	var tag_label: Label = Label.new()
	tag_label.text = Localization.get_text("library.filter.type", "種類")
	tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	filter_row.add_child(tag_label)

	_tag_filter = OptionButton.new()
	_tag_filter.name = "LibraryTypeFilter"
	_tag_filter.custom_minimum_size = Vector2(180.0, 0.0)
	_tag_filter.item_selected.connect(_on_tag_filter_selected)
	filter_row.add_child(_tag_filter)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_cards_grid = GridContainer.new()
	_cards_grid.name = "LibraryCards"
	_cards_grid.columns = CARD_GRID_COLUMNS
	_cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_grid.add_theme_constant_override("h_separation", 12)
	_cards_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_cards_grid)
	_populate_filters()


func _refresh_ui() -> void:
	var entries: Array[Dictionary] = Game.get_meta_card_entries()
	var unlocked_count: int = 0
	for entry in entries:
		if bool(entry.get("unlocked", false)):
			unlocked_count += 1
	_summary_label.text = Localization.get_textf(
		"library.summary",
		"Unlocked {current} / {total} cards. Locked cards stay visible here so you can plan purchases.",
		{
			"current": unlocked_count,
			"total": entries.size(),
		}
	)
	if not _content_ready:
		if not _content_building:
			_content_building = true
			_rebuild_card_rows.call_deferred()
		return
	_update_card_rows(entries)
	_apply_filters()


func _rebuild_card_rows() -> void:
	for child in _cards_grid.get_children():
		_cards_grid.remove_child(child)
		child.queue_free()
	_card_widgets.clear()

	var rarity_order: Array[String] = ["common", "rare", "epic"]
	var entries: Array[Dictionary] = Game.get_meta_card_entries()
	var built_count: int = 0
	for rarity in rarity_order:
		for entry in entries:
			if String(entry.get("rarity", "")) != rarity:
				continue
			var card_id: String = String(entry.get("id", ""))
			var card_def: CardDef = Database.get_card(card_id)
			if card_def == null:
				continue

			var row: PanelContainer = PanelContainer.new()
			row.name = "LibraryRow_%s" % card_id
			row.custom_minimum_size = Vector2(360.0, 0.0)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_theme_stylebox_override("panel", _make_card_cell_stylebox())
			_cards_grid.add_child(row)

			var cell: VBoxContainer = VBoxContainer.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_theme_constant_override("separation", 8)
			row.add_child(cell)

			var top_row: HBoxContainer = HBoxContainer.new()
			top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top_row.add_theme_constant_override("separation", 10)
			cell.add_child(top_row)

			var preview: CardButton = CardButton.new()
			preview.name = "LibraryCard_%s" % card_id
			preview.set_tile_size(Vector2(92.0, 92.0))
			preview.bind_preview(card_def, card_id, false, "LIB")
			if not bool(entry.get("unlocked", false)):
				preview.modulate = Color(0.55, 0.55, 0.55, 1.0)
			top_row.add_child(preview)

			var info: VBoxContainer = VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top_row.add_child(info)

			var name_label: Label = Label.new()
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name_label.text = card_def.name
			info.add_child(name_label)

			var meta_label: Label = Label.new()
			meta_label.name = "LibraryMeta_%s" % card_id
			meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			meta_label.text = "%s / %s" % [
				Localization.get_rarity_name(rarity),
				Localization.get_tags_text(card_def.tags),
			]
			info.add_child(meta_label)

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
			cell.add_child(desc_label)
			_card_widgets[card_id] = {
				"row": row,
				"preview": preview,
				"status": status_label,
				"rarity": rarity,
				"tags": card_def.tags.duplicate(),
			}
			built_count += 1
			if built_count % BUILD_BATCH_SIZE == 0:
				await get_tree().process_frame
				if not is_inside_tree():
					return
	_content_building = false
	_content_ready = true
	_refresh_ui()


func _update_card_rows(entries: Array[Dictionary]) -> void:
	for entry in entries:
		var card_id: String = String(entry.get("id", ""))
		var widgets: Dictionary = Dictionary(_card_widgets.get(card_id, {}))
		if widgets.is_empty():
			continue
		var unlocked: bool = bool(entry.get("unlocked", false))
		var preview: CardButton = widgets.get("preview") as CardButton
		var status_label: Label = widgets.get("status") as Label
		if preview == null or status_label == null:
			continue
		preview.modulate = Color(1.0, 1.0, 1.0, 1.0) if unlocked else Color(0.55, 0.55, 0.55, 1.0)
		if unlocked:
			status_label.text = Localization.get_text("meta.unlocked", "Unlocked")
		else:
			status_label.text = Localization.get_textf("library.locked_cost", "Locked | Unlock cost {cost}", {
				"cost": int(entry.get("cost", 0)),
			})


func _populate_filters() -> void:
	_rarity_filter.clear()
	_rarity_filter.add_item(Localization.get_text("library.filter.all", "すべて"))
	_rarity_filter.set_item_metadata(_rarity_filter.item_count - 1, "all")
	var rarity_options: Array[String] = ["common", "rare", "epic"]
	for rarity: String in rarity_options:
		_rarity_filter.add_item(Localization.get_rarity_name(rarity))
		_rarity_filter.set_item_metadata(_rarity_filter.item_count - 1, rarity)
	_rarity_filter.select(0)

	_tag_filter.clear()
	_tag_filter.add_item(Localization.get_text("library.filter.all", "すべて"))
	_tag_filter.set_item_metadata(_tag_filter.item_count - 1, "all")
	var tags: Array[String] = _collect_card_tags()
	for tag in tags:
		_tag_filter.add_item(Localization.get_text("tag.%s" % tag, tag.capitalize()))
		_tag_filter.set_item_metadata(_tag_filter.item_count - 1, tag)
	_tag_filter.select(0)


func _collect_card_tags() -> Array[String]:
	var seen: Dictionary = {}
	var tags: Array[String] = []
	for card_id in Database.get_all_card_ids():
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null:
			continue
		for tag in card_def.tags:
			if seen.has(tag):
				continue
			seen[tag] = true
			tags.append(tag)
	tags.sort()
	return tags


func _on_rarity_filter_selected(index: int) -> void:
	_selected_rarity = String(_rarity_filter.get_item_metadata(index))
	_apply_filters()


func _on_tag_filter_selected(index: int) -> void:
	_selected_tag = String(_tag_filter.get_item_metadata(index))
	_apply_filters()


func _apply_filters() -> void:
	if not _content_ready:
		return
	for raw_card_id in _card_widgets.keys():
		var card_id: String = String(raw_card_id)
		var widgets: Dictionary = Dictionary(_card_widgets.get(card_id, {}))
		var row: Control = widgets.get("row") as Control
		if row == null:
			continue
		var rarity: String = String(widgets.get("rarity", ""))
		var tags: Array = Array(widgets.get("tags", []))
		var rarity_matches: bool = _selected_rarity == "all" or rarity == _selected_rarity
		var tag_matches: bool = _selected_tag == "all" or tags.has(_selected_tag)
		row.visible = rarity_matches and tag_matches


func _make_card_cell_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.60)
	style.border_color = Color(0.28, 0.34, 0.42, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10.0
	style.content_margin_top = 10.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 10.0
	return style


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
