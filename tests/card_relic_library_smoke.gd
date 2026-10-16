extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all()
	Game.meta_progress = Database.meta_progress_template.duplicate(true)
	Game.ensure_meta_initialized()
	Game.set_language("ja")
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		push_error("Card/relic library: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _wait_ready(screen: Control) -> void:
	for _frame: int in 180:
		if bool(screen.call("is_content_ready")): return
		await get_tree().process_frame
	_check(false, "active tab did not finish loading")


func _search(panel: RelicLibraryPanel, text: String) -> void:
	(panel.get("_search_edit") as LineEdit).text = text
	panel.call("_on_search_changed", text)
	(panel.get("_search_timer") as Timer).timeout.emit()


func _run() -> void:
	var screen: Control = load("res://scenes/library/CardLibrary.tscn").instantiate() as Control
	add_child(screen)
	await _wait_ready(screen)
	var tabs: TabContainer = screen.get("_tabs") as TabContainer
	var panel: RelicLibraryPanel = screen.get("_relics_page") as RelicLibraryPanel
	var grid: GridContainer = panel.get("_grid") as GridContainer
	_check(tabs.get_tab_count() == 2 and tabs.get_tab_title(0) == "カード" and tabs.get_tab_title(1) == "遺物", "localized tabs are missing")
	_check(grid.get_child_count() == 0, "inactive relic tab eagerly built its rows")
	var card_count: int = Dictionary(screen.get("_card_widgets")).size()
	var first_card: Control = (screen.get("_cards_grid") as GridContainer).get_child(0) as Control
	var card_id: int = first_card.get_instance_id()
	tabs.current_tab = 1
	await _wait_ready(screen)
	_check(grid.columns == 3 and grid.get_child_count() >= 12 and grid.get_child_count() < Database.relics.size(), "relic tab should use a lazy three-column grid")
	_check(Dictionary(screen.get("_card_widgets")).size() == card_count, "hidden card tab continued loading")
	var iron: RelicIcon = panel.find_child("LibraryRelic_iron_plating", true, false) as RelicIcon
	var chrono: RelicIcon = panel.find_child("LibraryRelic_chrono_shard", true, false) as RelicIcon
	var chrono_button: CheckButton = panel.find_child("SealRelic_chrono_shard", true, false) as CheckButton
	_check(iron != null and iron.tooltip_text.contains(Database.get_relic("iron_plating").description), "relic icon tooltip is missing its effect")
	var tooltip: Control = iron.call("_make_custom_tooltip", iron.tooltip_text) as Control
	_check(tooltip.mouse_filter == Control.MOUSE_FILTER_IGNORE and (tooltip.find_child("RelicTooltipText", true, false) as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "relic tooltip must not consume control clicks")
	tooltip.free()
	_check(chrono != null and chrono.modulate.r < 0.7 and not chrono_button.visible, "locked relic is not visibly locked")
	var chrono_row_id: int = panel.find_child("LibraryRelicRow_chrono_shard", true, false).get_instance_id()
	Game.developer_unlock_all_meta()
	screen.call("_refresh_ui")
	_check(chrono.modulate.r == 1.0 and chrono_button.visible and not chrono_button.disabled, "unlock did not refresh the existing relic row")
	chrono_button.button_pressed = true
	_check(Array(Game.meta_progress["sealed_relics"]).has("chrono_shard") and SaveManager.has_pending_save(), "relic seal did not request persistence")
	chrono_button.button_pressed = false
	_check(not Array(Game.meta_progress["sealed_relics"]).has("chrono_shard") and panel.find_child("LibraryRelicRow_chrono_shard", true, false).get_instance_id() == chrono_row_id, "unsealing rebuilt the relic row")
	tabs.current_tab = 0
	await _wait_ready(screen)
	_check((screen.get("_cards_grid") as GridContainer).get_child(0).get_instance_id() == card_id, "switching tabs rebuilt the card page")
	tabs.current_tab = 1
	await _wait_ready(screen)
	_check(panel.find_child("LibraryRelicRow_chrono_shard", true, false).get_instance_id() == chrono_row_id, "switching tabs rebuilt the relic page")
	_search(panel, Database.get_relic("iron_plating").name)
	await _wait_ready(screen)
	_check(grid.get_child_count() == 1 and panel.find_child("LibraryRelic_iron_plating", true, false) != null, "relic name search did not filter correctly")
	var search_row_id: int = grid.get_child(0).get_instance_id()
	tabs.current_tab = 0
	tabs.current_tab = 1
	await _wait_ready(screen)
	_check(grid.get_child_count() == 1 and grid.get_child(0).get_instance_id() == search_row_id, "tab switching lost relic search or cached results")
	_search(panel, "no_match_000000000")
	await _wait_ready(screen)
	_check(grid.get_child_count() == 0 and (panel.get("_empty_label") as Label).visible, "empty search state is missing")
	_search(panel, "")
	var rarity: OptionButton = panel.get("_rarity_filter") as OptionButton
	panel.call("_on_rarity_selected", 4)
	rarity.select(4)
	await _wait_ready(screen)
	_check(grid.get_child_count() == 9, "relic rarity filter should show all nine legendary relics")
	for raw_id: Variant in Dictionary(panel.get("_widgets")).keys():
		_check(Database.get_relic(String(raw_id)).rarity == "legendary", "rarity filter leaked another rarity")
	panel.call("_on_rarity_selected", 0)
	rarity.select(0)
	var tag_filter: OptionButton = panel.get("_tag_filter") as OptionButton
	_check(tag_filter.item_count > 1, "relic effect tags were not loaded")
	tag_filter.select(1)
	panel.call("_on_tag_selected", 1)
	await _wait_ready(screen)
	var tag: String = String(tag_filter.get_item_metadata(1))
	for raw_id: Variant in Dictionary(panel.get("_widgets")).keys():
		_check(Database.get_relic(String(raw_id)).tags.has(tag), "relic tag filter leaked another type")
	tag_filter.select(0)
	panel.call("_on_tag_selected", 0)
	await _wait_ready(screen)
	var scroll: ScrollContainer = panel.get("_scroll") as ScrollContainer
	for _attempt: int in 50:
		if grid.get_child_count() == Database.relics.size(): break
		scroll.get_v_scroll_bar().value = scroll.get_v_scroll_bar().max_value
		for _frame: int in 6: await get_tree().process_frame
	_check(grid.get_child_count() == Database.relics.size(), "scrolling failed to load the full relic catalog")
	_check(not scroll.get_h_scroll_bar().visible, "relic grid has a horizontal scrollbar")
	Game.current_run = RunState.from_starter(Database.get_starter("balanced"), 42)
	Game.current_run.relic_state["solar_pinion"] = {"card_id": "strike"}
	screen.call("_refresh_ui")
	var engraved: RelicIcon = panel.find_child("LibraryRelic_solar_pinion", true, false) as RelicIcon
	_check(engraved.tooltip_text.contains(Database.get_card("strike").name), "cached relic tooltip did not refresh run-specific engraving")
	Game.current_run.relic_state["solar_pinion"]["card_id"] = "guard"
	screen.call("_refresh_ui")
	_check(engraved.tooltip_text.contains(Database.get_card("guard").name), "cached relic tooltip kept the previous engraved card")
	SaveManager.flush_requested_save()
	var meta: Control = load("res://scenes/meta/MetaProgress.tscn").instantiate() as Control
	add_child(meta)
	await _wait_ready(meta)
	_check(meta.find_child("MetaRelicBox", true, false) == null and meta.find_child("SealRelic_iron_plating", true, false) == null, "relic controls remain duplicated in Meta Progress")
	_check(Localization.get_text("library.title", "") == "カード・遺物図鑑", "library navigation was not renamed")
	print("CARD_RELIC_LIBRARY_SMOKE_OK %d checks: lazy tabs, cache, search, filters, seals, tooltips, migration" % _checks)
	get_tree().quit(0)
