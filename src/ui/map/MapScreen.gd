extends Control

const LOADOUT_PREVIEW_SIZE: Vector2 = Vector2(92.0, 92.0)
const LOADOUT_COUNT_ICON_SIZE: Vector2 = Vector2(22.0, 22.0)
const RUN_SUMMARY_ICON_SIZE: Vector2 = Vector2(22.0, 22.0)

var _run_history_box: VBoxContainer
var _steps_scroll: ScrollContainer
var _route_canvas: MapRouteCanvas
var _root_row: HBoxContainer
var _loadout_frame: PanelContainer
var _loadout_box: VBoxContainer
var _loadout_overlay: Control
var _loadout_modal_body: VBoxContainer
var _history_overlay: Control
var _loadout_button: Button
var _chapter_label: Label
var _map_header: Label
var _previous_button: Button
var _next_button: Button
var _chapter_start: int = -1
var _traveling: bool = false
var _history_signature: String = ""
var _equipped_summary_label: Label
var _equipped_panel: CardHandPanel
var _inventory_box: LoadoutInventoryGrid
var _run_info_banner: RunInfoBanner
var _developer_panel: DeveloperPanel


func _ready() -> void:
	if Game.current_run == null:
		SceneRouter.go_to_hub()
		return
	if Game.current_run.run_complete:
		SceneRouter.go_to_result()
		return

	_build_ui()
	_refresh_ui()
	_schedule_current_step_card_preload()
	AudioManager.play_sfx("map_reveal", 1.0, -4.0)
	if Game.is_developer_mode_enabled():
		_build_developer_panel()
	get_viewport().size_changed.connect(_responsive_layout)
	if not get_window().size_changed.is_connected(_responsive_layout):
		get_window().size_changed.connect(_responsive_layout)
	call_deferred("_responsive_layout")


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
	_root_row = root
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 20)
	screen_root.add_child(root)

	var map_panel: VBoxContainer = _create_panel(root, Localization.get_text("map.panel.node_map", "マップ"))
	_map_header = map_panel.get_child(0) as Label
	(map_panel.get_parent() as Control).size_flags_stretch_ratio = 2.35
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	map_panel.add_child(toolbar)
	_previous_button = _map_button(toolbar, "MapPreviousChapter", "back", Localization.get_text("map.route.previous", "Previous chapter"), true)
	_previous_button.pressed.connect(_change_chapter.bind(-1))
	_chapter_label = Label.new()
	_chapter_label.name = "MapChapterLabel"
	_chapter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chapter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chapter_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toolbar.add_child(_chapter_label)
	_next_button = _map_button(toolbar, "MapNextChapter", "next", Localization.get_text("map.route.next", "Next chapter"), true)
	_next_button.pressed.connect(_change_chapter.bind(1))
	var history: Button = _map_button(toolbar, "MapHistoryButton", "log", Localization.get_text("map.route.history", "Run history"), true)
	history.pressed.connect(_show_history)
	_loadout_button = _map_button(toolbar, "MapLoadoutButton", "equip", Localization.get_text("map.panel.loadout", "Loadout"), true)
	_loadout_button.pressed.connect(func() -> void: _loadout_overlay.visible = true)
	var back: Button = _map_button(toolbar, "MapHubButton", "home", Localization.get_text("map.return_hub", "Return to Hub"), true)
	back.pressed.connect(_on_return_to_hub)

	_steps_scroll = ScrollContainer.new()
	_steps_scroll.name = "MapStepsScroll"
	_steps_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steps_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_steps_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	map_panel.add_child(_steps_scroll)
	_route_canvas = MapRouteCanvas.new()
	_route_canvas.node_selected.connect(_on_node_selected)
	_steps_scroll.add_child(_route_canvas)
	var legend: Label = Label.new()
	legend.name = "MapRouteLegend"
	legend.text = Localization.get_text("map.route.legend", "Gold: your trail   /   Glow: next destinations   /   Lines: available routes")
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.add_theme_font_size_override("font_size", 14)
	legend.add_theme_color_override("font_color", Color("acbfc2"))
	map_panel.add_child(legend)

	var loadout_panel: VBoxContainer = _create_panel(root, Localization.get_text("map.panel.loadout", "Loadout"))
	_loadout_box = loadout_panel
	_loadout_frame = loadout_panel.get_parent() as PanelContainer
	_loadout_frame.size_flags_stretch_ratio = 1.0
	loadout_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var presets: DeckPresetBar = DeckPresetBar.new()
	presets.get_cards = func() -> Array[String]: return Game.current_run.equipped_cards
	presets.get_run = func() -> RunState: return Game.current_run
	presets.apply_requested.connect(func(cards: Array[String]) -> void:
		if DeckPresetService.apply(Game.current_run, cards):
			SaveManager.save_game("map")
			_refresh_ui()
	)
	loadout_panel.add_child(presets)

	_equipped_summary_label = Label.new()
	_equipped_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loadout_panel.add_child(_equipped_summary_label)

	var equipped_title: Label = Label.new()
	equipped_title.text = Localization.get_text("map.equipped_deck", "Equipped Deck")
	loadout_panel.add_child(equipped_title)

	_equipped_panel = CardHandPanel.new()
	_equipped_panel.name = "EquippedDeck"
	_equipped_panel.set_interactive(false)
	_equipped_panel.set_unequip_enabled(true)
	_equipped_panel.card_unequip_requested.connect(_on_unequip_card)
	_equipped_panel.set_tile_size(Vector2(88.0, 88.0))
	loadout_panel.add_child(_equipped_panel)

	var inventory_title: Label = Label.new()
	inventory_title.text = Localization.get_text("map.card_inventory", "Card Inventory")
	loadout_panel.add_child(inventory_title)

	var inventory_scroll: ScrollContainer = ScrollContainer.new()
	inventory_scroll.name = "LoadoutInventoryScroll"
	inventory_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	loadout_panel.add_child(inventory_scroll)

	_inventory_box = LoadoutInventoryGrid.new()
	_inventory_box.name = "LoadoutInventory"
	_inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_scroll.add_child(_inventory_box)
	_build_map_modals()


func _map_button(parent: Control, id: String, icon: String, hint: String, compact: bool) -> Button:
	var button: Button = Button.new()
	button.name = id
	button.text = hint
	UiIconHelper.decorate(button, icon, hint, compact)
	parent.add_child(button)
	return button


func _make_modal(id: String, title: String) -> Dictionary:
	var overlay: Control = Control.new()
	overlay.name = id
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 160
	overlay.visible = false
	add_child(overlay)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var frame: PanelContainer = PanelContainer.new()
	frame.name = id + "Frame"
	frame.custom_minimum_size = Vector2(620, 660)
	center.add_child(frame)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	frame.add_child(body)
	var row: HBoxContainer = HBoxContainer.new()
	body.add_child(row)
	var heading: Label = Label.new()
	heading.text = title
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.theme_type_variation = "SectionTitle"
	row.add_child(heading)
	var close: Button = _map_button(row, id + "Close", "close", Localization.get_text("common.close", "Close"), true)
	close.pressed.connect(func() -> void: overlay.visible = false)
	return {"overlay": overlay, "body": body, "frame": frame}


func _build_map_modals() -> void:
	var history: Dictionary = _make_modal("MapHistory", Localization.get_text("map.panel.run_status", "Run history"))
	_history_overlay = history["overlay"]
	var history_scroll: ScrollContainer = ScrollContainer.new()
	history_scroll.name = "RunBattleSummaryScroll"
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	(history["body"] as VBoxContainer).add_child(history_scroll)
	_run_history_box = VBoxContainer.new()
	_run_history_box.name = "RunBattleSummary"
	_run_history_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_history_box.add_theme_constant_override("separation", 8)
	history_scroll.add_child(_run_history_box)
	var loadout: Dictionary = _make_modal("MapLoadout", Localization.get_text("map.panel.loadout", "Loadout"))
	_loadout_overlay = loadout["overlay"]
	_loadout_modal_body = loadout["body"]


func _responsive_layout() -> void:
	if not is_inside_tree() or not is_instance_valid(_loadout_frame): return
	var viewport_size: Vector2 = get_viewport_rect().size
	var narrow: bool = viewport_size.x < viewport_size.y * 1.15
	var density: float = 1.0 if DisplayServer.get_name() == "headless" else clampf(viewport_size.x / maxf(1.0, get_window().size.x), 0.75, 3.0)
	_chapter_label.add_theme_font_size_override("font_size", ceili(18 * density))
	_map_header.add_theme_font_size_override("font_size", ceili(22 * density))
	(find_child("MapRouteLegend", true, false) as Label).add_theme_font_size_override("font_size", ceili(14 * density))
	for button: Button in [_previous_button, _next_button, _loadout_button, find_child("MapHistoryButton", true, false), find_child("MapHubButton", true, false)]:
		button.custom_minimum_size = Vector2.ONE * 40.0 * density
		button.add_theme_constant_override("icon_max_width", ceili(22 * density))
	_loadout_button.visible = narrow
	if narrow and _loadout_frame.get_parent() != _loadout_modal_body:
		_loadout_frame.reparent(_loadout_modal_body)
		_loadout_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	elif not narrow and _loadout_frame.get_parent() != _root_row:
		_loadout_frame.reparent(_root_row)
		_loadout_frame.remove_theme_stylebox_override("panel")
		_loadout_overlay.visible = false
	_loadout_box.get_child(0).visible = not narrow
	_loadout_box.get_child(1).visible = not narrow
	for overlay: Control in [_history_overlay, _loadout_overlay]:
		var frame: PanelContainer = overlay.find_child(String(overlay.name) + "Frame", true, false) as PanelContainer
		frame.custom_minimum_size = Vector2(maxf(280, minf(680, viewport_size.x - 72)), maxf(300, minf(820, viewport_size.y - 88)))
	call_deferred("_scroll_to_current_step", Game.get_current_step_index())


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
	header.theme_type_variation = "SectionTitle"
	header.text = title
	box.add_child(header)
	box.add_child(HSeparator.new())
	return box


func _refresh_ui() -> void:
	var current_run: RunState = Game.current_run
	if _run_info_banner != null:
		_run_info_banner.refresh()
	_equipped_summary_label.text = Localization.get_textf("map.loadout_cost", "Loadout Cost {used} / {limit}", {
		"used": Game.get_current_loadout_cost(),
		"limit": Game.get_loadout_limit(),
	})

	_rebuild_steps()
	_equipped_panel.refresh_card_ids(Game.get_equipped_cards(), false, "EQUIP", current_run)
	_rebuild_loadout_rows()
	_refresh_developer_panel()


func _rebuild_steps() -> void:
	var current_step_index: int = Game.get_current_step_index()
	if _chapter_start < 0: _chapter_start = floori(float(current_step_index) / 7.0) * 7
	var steps: Array[Dictionary] = Game.get_map_steps()
	var previous_signature: String = _route_canvas._signature
	_route_canvas.configure(Game.current_run.map_state, _chapter_start)
	_chapter_label.text = Localization.get_textf("map.route.chapter", "Chapter {chapter} | Steps {start}-{end}", {"chapter": _chapter_start / 7 + 1, "start": _chapter_start + 1, "end": mini(_chapter_start + 7, steps.size())})
	_previous_button.disabled = _chapter_start == 0
	_next_button.disabled = _chapter_start + 7 >= steps.size()
	if _next_button.disabled and steps.size() < 28 and not Game.current_run.infinite_mode:
		_next_button.icon = MapNodeButton._load_lock_icon_texture()
		_next_button.tooltip_text = Localization.get_text("map.route.unlock_hint", "Claim the S-rank achievement to unlock the next chapter.")
	else:
		_next_button.icon = StatIconFactory.get_icon("next")
		_next_button.tooltip_text = Localization.get_text("map.route.next", "Next chapter")
	for id: String in _route_canvas._buttons:
		var button: MapNodeButton = _route_canvas._buttons[id]
		if not button.disabled and not button.has_meta("visual_preload"):
			button.set_meta("visual_preload", true)
			button.mouse_entered.connect(_preload_node_visual.bind(id))
	if previous_signature != _route_canvas._signature:
		call_deferred("_scroll_to_current_step", current_step_index)


func _show_history() -> void:
	var signature: String = JSON.stringify(Game.current_run.battle_history)
	if signature != _history_signature:
		_history_signature = signature
		_rebuild_run_history_summary(Game.current_run)
	_history_overlay.visible = true


func _preload_node_visual(id: String) -> void:
	for step: Dictionary in Game.get_map_steps():
		for node: Dictionary in step.get("nodes", []):
			if String(node["id"]) == id and node.get("type", "") in ["normal_battle", "elite_battle", "boss"]:
				SceneRouter.schedule_battle_visuals(Game.current_run.starter_id, String(node.get("enemy_id", "")))


func _change_chapter(direction: int) -> void:
	_chapter_start = clampi(_chapter_start + direction * 7, 0, maxi(0, floori(float(Game.get_map_step_count() - 1) / 7.0) * 7))
	_rebuild_steps()


func _schedule_current_step_card_preload() -> void:
	var card_ids: Array[String] = []
	for card_id: String in Game.current_run.equipped_cards:
		if not card_ids.has(card_id):
			card_ids.append(card_id)
	var step_data: Dictionary = Game.get_current_step_data()
	for raw_node: Variant in Array(step_data.get("nodes", [])):
		var node_data: Dictionary = Dictionary(raw_node)
		if String(node_data.get("status", "")) != "available": continue
		if String(node_data.get("type", "")) not in ["normal_battle", "elite_battle", "boss"]:
			continue
		var enemy: EnemyDef = Database.get_enemy(String(node_data.get("enemy_id", "")))
		if enemy == null:
			continue
		for card_id: String in enemy.cards:
			if not card_ids.has(card_id):
				card_ids.append(card_id)
	SceneRouter.schedule_battle_card_ids(card_ids)


func _rebuild_run_history_summary(current_run: RunState) -> void:
	for child in _run_history_box.get_children():
		_run_history_box.remove_child(child)
		child.queue_free()

	var battle_history: Array[Dictionary] = current_run.battle_history
	if battle_history.is_empty():
		var empty_label: Label = Label.new()
		empty_label.name = "RunBattleSummaryEmpty"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.text = Localization.get_text("map.battle_summary.empty", "まだ戦闘履歴はありません")
		_run_history_box.add_child(empty_label)
		return

	_run_history_box.add_child(_build_summary_total_row(battle_history))
	for battle_index in range(battle_history.size()):
		_run_history_box.add_child(_build_battle_summary_row(battle_index, battle_history[battle_index]))


func _build_summary_total_row(battle_history: Array[Dictionary]) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "RunBattleSummaryTotal"
	row.add_theme_constant_override("separation", 8)
	row.add_child(_build_icon_value("step", Localization.get_textf("map.battle_summary.count", "{count} 戦", {
		"count": battle_history.size(),
	})))
	row.add_child(_build_icon_value("time", Localization.get_textf("map.battle_summary.total_time", "合計 {time}s", {
		"time": "%.1f" % _get_total_battle_time(battle_history),
	})))
	return row


func _build_battle_summary_row(battle_index: int, battle_data: Dictionary) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "RunBattleSummaryStep_%d" % battle_index
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_battle_summary_stylebox())

	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_theme_constant_override("separation", 8)
	box.add_child(title_row)

	title_row.add_child(_build_icon_value("step", "%02d" % (battle_index + 1)))
	var enemy_label: Label = Label.new()
	enemy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_label.clip_text = true
	enemy_label.text = "%s / %s" % [
		_get_node_type_label(String(battle_data.get("node_type", "normal_battle"))),
		Localization.get_enemy_name(String(battle_data.get("enemy_id", ""))),
	]
	title_row.add_child(enemy_label)
	title_row.add_child(_build_icon_value("time", "%.1fs" % float(battle_data.get("battle_time", 0.0))))

	var gain_row: HBoxContainer = HBoxContainer.new()
	gain_row.name = "RunBattleSummaryGain_%d" % battle_index
	gain_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gain_row.add_theme_constant_override("separation", 8)
	box.add_child(gain_row)
	gain_row.add_child(_build_gain_label())

	var has_gain: bool = false
	var reward_gold: int = int(battle_data.get("reward_gold", 0))
	if reward_gold > 0:
		gain_row.add_child(_build_icon_value("gold", "+%d" % reward_gold))
		has_gain = true
	var reward_heal: int = int(battle_data.get("reward_heal", 0))
	if reward_heal > 0:
		gain_row.add_child(_build_icon_value("hp", "+%d" % reward_heal))
		has_gain = true
	var selected_card_id: String = String(battle_data.get("selected_reward_card_id", ""))
	if selected_card_id != "":
		gain_row.add_child(_build_icon_value("card_owned", _get_card_display_name(selected_card_id)))
		has_gain = true
	var bonus_relic_id: String = String(battle_data.get("bonus_relic_id", ""))
	if bonus_relic_id != "":
		gain_row.add_child(_build_icon_value("relic", _get_relic_display_name(bonus_relic_id)))
		has_gain = true
	if not has_gain:
		var none_label: Label = Label.new()
		none_label.text = Localization.get_text("map.battle_summary.no_gain", "なし")
		none_label.add_theme_color_override("font_color", Color(0.70, 0.72, 0.70, 1.0))
		gain_row.add_child(none_label)
	return panel


func _build_icon_value(icon_id: String, value: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "RunSummaryIconValue_%s" % icon_id
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.name = "RunSummaryIcon_%s" % icon_id
	icon_rect.custom_minimum_size = RUN_SUMMARY_ICON_SIZE
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = StatIconFactory.get_icon(icon_id)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_rect)

	var label: Label = Label.new()
	label.name = "RunSummaryValue_%s" % icon_id
	label.text = value
	label.clip_text = false
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row


func _build_gain_label() -> Label:
	var label: Label = Label.new()
	label.text = Localization.get_text("map.battle_summary.gain", "獲得")
	label.add_theme_color_override("font_color", Color(0.86, 0.80, 0.62, 1.0))
	return label


func _get_total_battle_time(battle_history: Array[Dictionary]) -> float:
	var total: float = 0.0
	for battle_data in battle_history:
		total += maxf(0.0, float(battle_data.get("battle_time", 0.0)))
	return total


func _get_node_type_label(node_type: String) -> String:
	match node_type:
		"elite_battle":
			return Localization.get_text("map.battle_summary.elite", "エリート")
		"boss":
			return Localization.get_text("map.battle_summary.boss", "ボス")
		"hazard":
			return Localization.get_text("map.battle_summary.hazard", "危険地帯")
		_:
			return Localization.get_text("map.battle_summary.normal", "戦闘")


func _get_card_display_name(card_id: String) -> String:
	var card_def: CardDef = Database.get_card(card_id)
	if card_def == null:
		return card_id
	return card_def.name


func _get_relic_display_name(relic_id: String) -> String:
	var relic_def: RelicDef = Database.get_relic(relic_id)
	if relic_def == null:
		return relic_id
	return relic_def.name


func _make_battle_summary_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.44)
	style.border_color = Color(0.34, 0.38, 0.45, 0.54)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	return style


func _scroll_to_current_step(step_index: int) -> void:
	if not is_inside_tree() or _steps_scroll == null or _route_canvas == null:
		return
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null:
		return
	await scene_tree.process_frame
	await scene_tree.process_frame
	if not is_inside_tree():
		return
	_steps_scroll.scroll_vertical = maxi(0, roundi(_route_canvas.get_focus_y() - _steps_scroll.size.y * 0.48))


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
		var tooltip_context: Dictionary = CardTooltipResolver.build_context(card_id, Game.current_run)
		var card_def: CardDef = tooltip_context.get("card") as CardDef
		if card_def == null:
			continue

		var frame: PanelContainer = PanelContainer.new()
		frame.name = "LoadoutCardFrame_%s" % card_id
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.custom_minimum_size.x = LoadoutInventoryGrid.MIN_CELL_WIDTH
		frame.mouse_filter = Control.MOUSE_FILTER_PASS
		frame.add_theme_stylebox_override("panel", _make_loadout_card_stylebox())
		_inventory_box.add_child(frame)

		var row: VBoxContainer = VBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		frame.add_child(row)

		var preview: CardButton = CardButton.new()
		preview.name = "LoadoutPreview_%s" % card_id
		preview.set_tile_size(LOADOUT_PREVIEW_SIZE)
		preview.bind_preview(
			card_def,
			card_id,
			false,
			"LOAD",
			tooltip_context.get("comparison") as CardDef
		)
		row.add_child(preview)
		preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

		var info_box: VBoxContainer = VBoxContainer.new()
		info_box.name = "LoadoutCardInfo_%s" % card_id
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_box.alignment = BoxContainer.ALIGNMENT_CENTER
		info_box.add_theme_constant_override("separation", 8)
		row.add_child(info_box)

		var counts_row: HBoxContainer = HBoxContainer.new()
		counts_row.name = "LoadoutCountRow_%s" % card_id
		counts_row.alignment = BoxContainer.ALIGNMENT_CENTER
		counts_row.add_theme_constant_override("separation", 10)
		info_box.add_child(counts_row)
		counts_row.add_child(_build_loadout_count_pill("card_owned", int(entry.get("owned_count", 0)), "OwnedCount_%s" % card_id))
		counts_row.add_child(_build_loadout_count_pill("card_equipped", int(entry.get("equipped_count", 0)), "EquippedCount_%s" % card_id))

		var actions: HBoxContainer = HBoxContainer.new()
		actions.name = "LoadoutActions_%s" % card_id
		actions.alignment = BoxContainer.ALIGNMENT_CENTER
		actions.add_theme_constant_override("separation", 8)
		actions.visible = false
		info_box.add_child(actions)

		var equip_button: Button = Button.new()
		equip_button.name = "EquipButton_%s" % card_id
		equip_button.text = Localization.get_text("map.equip", "Equip")
		UiIconHelper.decorate(equip_button, "equip", equip_button.text, true)
		equip_button.disabled = not bool(entry.get("can_equip", false))
		equip_button.pressed.connect(_on_equip_card.bind(card_id))
		actions.add_child(equip_button)

		var sell_value: int = int(entry.get("sell_value", 0))
		var sell_button: Button = Button.new()
		sell_button.name = "SellButton_%s" % card_id
		sell_button.icon = StatIconFactory.get_icon("gold")
		sell_button.text = Localization.get_textf("map.sell_for", "Sell {amount}", {"amount": sell_value})
		UiIconHelper.decorate(sell_button, "sell", sell_button.text, true, str(sell_value))
		sell_button.disabled = not bool(entry.get("can_sell", false))
		sell_button.pressed.connect(_on_sell_card.bind(card_id))
		actions.add_child(sell_button)
		HoverActionReveal.attach(frame, actions)


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
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.88, 1.0))
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(value_label)
	return pill


func _make_loadout_card_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.54)
	style.border_color = Color(0.28, 0.33, 0.40, 0.76)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	return style


func _on_node_selected(node_id: String) -> void:
	if _traveling or not MapRouteGraph.can_select(Game.current_run.map_state, node_id): return
	_traveling = true
	await _route_canvas.animate_travel(node_id)
	if not is_inside_tree(): return
	_traveling = false
	var destination: String = Game.select_map_node(node_id)
	match destination:
		"battle":
			SceneRouter.go_to_battle()
		"facility":
			SceneRouter.go_to_facility()
		_:
			AudioManager.play_sfx("ui_error")
			_route_canvas._layout()
			_refresh_ui()


func _on_equip_card(card_id: String) -> void:
	if Game.equip_card(card_id):
		_refresh_ui()


func _on_unequip_card(card_id: String) -> void:
	if Game.unequip_card(card_id):
		_refresh_ui()


func _on_sell_card(card_id: String) -> void:
	if Game.sell_loadout_card(card_id):
		_refresh_ui()


func _on_return_to_hub() -> void:
	Game.abandon_run_to_hub()
	SceneRouter.go_to_hub()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_history_overlay.visible or _loadout_overlay.visible):
		_history_overlay.visible = false
		_loadout_overlay.visible = false
		get_viewport().set_input_as_handled()


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
		{"id": "DevMapAdvance", "label": Localization.get_text("map.route.dev_advance", "Advance route (no rewards)"), "callback": Callable(self, "_on_dev_map_advance")},
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


func _on_dev_map_advance() -> void:
	if not Game.developer_advance_map_route(): return
	if Game.current_run.run_complete:
		SceneRouter.go_to_result()
	else:
		_chapter_start = -1
		_refresh_ui()
		_schedule_current_step_card_preload()


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
