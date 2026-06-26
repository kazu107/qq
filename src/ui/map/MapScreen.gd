extends Control

var _summary_label: RichTextLabel
var _help_label: Label
var _relics_label: Label
var _relics_icon_row: RelicIconRow
var _steps_box: VBoxContainer
var _steps_scroll: ScrollContainer
var _steps_scroll_tail: Control
var _equipped_summary_label: Label
var _equipped_panel: CardHandPanel
var _inventory_box: VBoxContainer
var _run_info_banner: RunInfoBanner
var _developer_panel: DeveloperPanel


func _ready() -> void:
	if Game.current_run == null:
		SceneRouter.go_to_title()
		return
	if Game.current_run.run_complete:
		SceneRouter.go_to_result()
		return

	_build_ui()
	_refresh_ui()
	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 28.0
	margin.offset_top = 20.0
	margin.offset_right = -28.0
	margin.offset_bottom = -20.0
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

	var info_panel: VBoxContainer = _create_panel(root, Localization.get_text("map.panel.run_status", "Run Status"))
	_summary_label = RichTextLabel.new()
	_summary_label.fit_content = true
	info_panel.add_child(_summary_label)

	_help_label = Label.new()
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_panel.add_child(_help_label)

	_relics_label = Label.new()
	_relics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_panel.add_child(_relics_label)

	_relics_icon_row = RelicIconRow.new()
	_relics_icon_row.name = "MapRelicIconRow"
	_relics_icon_row.set_icon_size(Vector2(42.0, 42.0))
	info_panel.add_child(_relics_icon_row)

	var back_button: Button = Button.new()
	back_button.text = Localization.get_text("map.return_hub", "Return to Hub")
	back_button.pressed.connect(_on_return_to_hub)
	info_panel.add_child(back_button)

	var map_panel: VBoxContainer = _create_panel(root, Localization.get_text("map.panel.node_map", "Node Map"))
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_steps_scroll = ScrollContainer.new()
	_steps_scroll.name = "MapStepsScroll"
	_steps_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steps_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_child(_steps_scroll)

	_steps_box = VBoxContainer.new()
	_steps_box.name = "MapSteps"
	_steps_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steps_box.add_theme_constant_override("separation", 14)
	_steps_scroll.add_child(_steps_box)

	var loadout_panel: VBoxContainer = _create_panel(root, Localization.get_text("map.panel.loadout", "Loadout"))
	loadout_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_equipped_summary_label = Label.new()
	_equipped_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loadout_panel.add_child(_equipped_summary_label)

	var equipped_title: Label = Label.new()
	equipped_title.text = Localization.get_text("map.equipped_deck", "Equipped Deck")
	loadout_panel.add_child(equipped_title)

	_equipped_panel = CardHandPanel.new()
	_equipped_panel.name = "EquippedDeck"
	_equipped_panel.set_interactive(false)
	_equipped_panel.set_tile_size(Vector2(88.0, 88.0))
	loadout_panel.add_child(_equipped_panel)

	var inventory_title: Label = Label.new()
	inventory_title.text = Localization.get_text("map.card_inventory", "Card Inventory")
	loadout_panel.add_child(inventory_title)

	var inventory_scroll: ScrollContainer = ScrollContainer.new()
	inventory_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loadout_panel.add_child(inventory_scroll)

	_inventory_box = VBoxContainer.new()
	_inventory_box.name = "LoadoutInventory"
	_inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_box.add_theme_constant_override("separation", 10)
	inventory_scroll.add_child(_inventory_box)


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


func _refresh_ui() -> void:
	var current_run: RunState = Game.current_run
	if _run_info_banner != null:
		_run_info_banner.refresh()
	var step_count: int = Game.get_map_step_count()
	var step_index: int = Game.get_current_step_index()
	var current_step: Dictionary = Game.get_current_step_data()
	var next_label: String = Localization.get_step_label(current_step)
	if next_label == "":
		next_label = Localization.get_text("map.run_complete", "Run Complete")
	var relic_names: Array[String] = Game.get_relic_names()
	var relic_text: String = Localization.get_text("map.relics_none", "Relics: None")
	if not relic_names.is_empty():
		relic_text = Localization.get_textf("map.relics_text", "Relics: {value}", {
			"value": ", ".join(relic_names),
		})

	_summary_label.text = "\n".join([
		Localization.get_textf("map.summary.hp", "HP {current} / {max}", {
			"current": current_run.player_hp,
			"max": current_run.max_hp,
		}),
		Localization.get_textf("map.summary.gold", "Gold {value}", {"value": current_run.gold}),
		Localization.get_textf("map.summary.area", "Area {value}", {"value": current_run.current_area}),
		Localization.get_textf("map.summary.progress", "Progress {current} / {total}", {
			"current": min(step_count, step_index + 1),
			"total": max(1, step_count),
		}),
	])
	_help_label.text = Localization.get_textf("map.help_choose", "Choose one available node.\nNext: {next_label}", {
		"next_label": next_label,
	})
	_relics_label.text = relic_text
	_relics_icon_row.refresh_relic_ids(current_run.relics)
	_equipped_summary_label.text = Localization.get_textf("map.loadout_cost", "Loadout Cost {used} / {limit}", {
		"used": Game.get_current_loadout_cost(),
		"limit": Game.get_loadout_limit(),
	})

	_rebuild_steps()
	_equipped_panel.refresh_card_ids(Game.get_equipped_cards(), false, "EQUIP", current_run)
	_rebuild_loadout_rows()
	_refresh_developer_panel()


func _rebuild_steps() -> void:
	for child in _steps_box.get_children():
		_steps_box.remove_child(child)
		child.queue_free()

	var steps: Array[Dictionary] = Game.get_map_steps()
	var current_step_index: int = Game.get_current_step_index()
	for step_index in range(steps.size()):
		var step_data: Dictionary = steps[step_index]
		var nodes: Array = Array(step_data.get("nodes", []))
		var step_locked: bool = _is_step_locked(nodes)
		var is_current_step: bool = step_index == current_step_index
		var panel: PanelContainer = PanelContainer.new()
		panel.name = "MapStep_%d" % step_index
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", _make_step_stylebox(step_locked, is_current_step))
		_steps_box.add_child(panel)

		var box: VBoxContainer = VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 10)
		panel.add_child(box)

		var header: Label = Label.new()
		header.name = "MapStepHeader_%d" % step_index
		header.text = Localization.get_textf("map.step_header", "Step {step} | {label}", {
			"step": step_index + 1,
			"area": int(step_data.get("area", 1)),
			"label": Localization.get_step_label(step_data),
		})
		box.add_child(header)

		var row: HFlowContainer = HFlowContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("h_separation", 12)
		row.add_theme_constant_override("v_separation", 12)
		box.add_child(row)

		for raw_node in nodes:
			var node_data: Dictionary = Dictionary(raw_node)
			var node_button: MapNodeButton = MapNodeButton.new()
			node_button.name = String(node_data.get("id", "Node"))
			node_button.bind(node_data, Localization.get_step_label(step_data), is_current_step)
			node_button.node_selected.connect(_on_node_selected)
			row.add_child(node_button)

	_steps_scroll_tail = Control.new()
	_steps_scroll_tail.name = "MapStepsScrollTail"
	_steps_box.add_child(_steps_scroll_tail)
	call_deferred("_scroll_to_current_step", current_step_index)


func _scroll_to_current_step(step_index: int) -> void:
	if _steps_scroll == null or _steps_box == null:
		return
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null:
		return
	await scene_tree.process_frame
	if not is_inside_tree():
		return
	var current_panel: Control = _steps_box.find_child("MapStep_%d" % step_index, false, false) as Control
	if current_panel == null or _steps_scroll_tail == null:
		return
	_steps_scroll_tail.custom_minimum_size.y = maxf(0.0, _steps_scroll.size.y - current_panel.size.y - 14.0)
	await scene_tree.process_frame
	if not is_inside_tree():
		return
	_steps_scroll.scroll_vertical = maxi(0, roundi(current_panel.position.y))


func _is_step_locked(nodes: Array) -> bool:
	if nodes.is_empty():
		return false
	for raw_node in nodes:
		var node_data: Dictionary = Dictionary(raw_node)
		if String(node_data.get("status", "locked")) != "locked":
			return false
	return true


func _make_step_stylebox(locked: bool, is_current_step: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.54) if locked else Color(0.08, 0.09, 0.12, 0.22)
	style.border_color = Color(0.20, 0.22, 0.27, 0.72) if locked else Color(0.36, 0.39, 0.47, 0.50)
	var border_width: int = 1
	if is_current_step:
		style.border_color = Color(1.0, 0.78, 0.24, 1.0)
		border_width = 3
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 10.0
	style.content_margin_top = 10.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 10.0
	return style


func _rebuild_loadout_rows() -> void:
	for child in _inventory_box.get_children():
		_inventory_box.remove_child(child)
		child.queue_free()

	for entry in Game.get_loadout_entries():
		var card_id: String = String(entry.get("card_id", ""))
		var card_def: CardDef = CardUpgradeResolver.build_effective_card(card_id, Game.current_run)
		if card_def == null:
			continue

		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		_inventory_box.add_child(row)

		var preview: CardButton = CardButton.new()
		preview.set_tile_size(Vector2(92.0, 92.0))
		preview.bind_preview(card_def, card_id, false, "LOAD")
		row.add_child(preview)

		var info_box: VBoxContainer = VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info_box)

		var count_label: Label = Label.new()
		count_label.text = Localization.get_textf("map.inventory_counts", "{name} | Owned {owned} | Equipped {equipped} | Cost {cost}", {
			"name": card_def.name,
			"owned": int(entry.get("owned_count", 0)),
			"equipped": int(entry.get("equipped_count", 0)),
			"cost": int(entry.get("loadout_cost", 0)),
		})
		info_box.add_child(count_label)

		var effect_label: Label = Label.new()
		effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_label.text = CardInfoFormatter.build_effect_summary(card_def)
		info_box.add_child(effect_label)

		var actions: VBoxContainer = VBoxContainer.new()
		row.add_child(actions)

		var equip_button: Button = Button.new()
		equip_button.text = Localization.get_text("map.equip", "Equip")
		equip_button.disabled = not bool(entry.get("can_equip", false))
		equip_button.pressed.connect(_on_equip_card.bind(card_id))
		actions.add_child(equip_button)

		var unequip_button: Button = Button.new()
		unequip_button.text = Localization.get_text("map.unequip", "Unequip")
		unequip_button.disabled = not bool(entry.get("can_unequip", false))
		unequip_button.pressed.connect(_on_unequip_card.bind(card_id))
		actions.add_child(unequip_button)


func _on_node_selected(node_id: String) -> void:
	var destination: String = Game.select_map_node(node_id)
	match destination:
		"battle":
			SceneRouter.go_to_battle()
		"facility":
			SceneRouter.go_to_facility()
		_:
			AudioManager.play_sfx("ui_error")
			_help_label.text = Localization.get_text("map.help_invalid_loadout", "Equip at least one valid loadout before entering battles.")
			_refresh_ui()


func _on_equip_card(card_id: String) -> void:
	if Game.equip_card(card_id):
		_refresh_ui()


func _on_unequip_card(card_id: String) -> void:
	if Game.unequip_card(card_id):
		_refresh_ui()


func _on_return_to_hub() -> void:
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
		_build_developer_actions(),
		Localization.get_text("map.dev.summary", "Use these shortcuts to probe run systems quickly.")
	)


func _build_developer_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = [
		{"id": "DevAddGold", "label": Localization.get_text("map.dev.add_gold", "Add 50 Gold"), "callback": Callable(self, "_on_dev_add_gold")},
		{"id": "DevRestoreHp", "label": Localization.get_text("map.dev.restore_hp", "Restore HP"), "callback": Callable(self, "_on_dev_restore_hp")},
		{"id": "DevGrantRelic", "label": Localization.get_text("map.dev.grant_relic", "Grant Relic"), "callback": Callable(self, "_on_dev_grant_relic")},
		{"id": "DevOpenBattle", "label": Localization.get_text("map.dev.debug_battle", "Debug Battle"), "callback": Callable(self, "_on_dev_open_battle")},
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


func _on_dev_open_battle() -> void:
	Game.developer_open_battle("scout")
	SceneRouter.go_to_battle()


func _on_dev_open_reward() -> void:
	Game.developer_open_reward()
	SceneRouter.go_to_reward()


func _on_dev_open_event(event_id: String) -> void:
	Game.developer_open_event(event_id)
	SceneRouter.go_to_facility()
