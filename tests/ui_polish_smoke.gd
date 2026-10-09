extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Game.settings["developer_mode"] = false
	for language: String in ["en", "ja"]:
		Game.settings["language"] = language
		Localization.set_language(language, false)
		Database.load_all()
		Game.ensure_meta_initialized()
		for entry: Dictionary in Game.get_meta_achievement_entries():
			var description: String = String(entry.get("description", ""))
			if not _check(description != "" and not description.begins_with("achievement."), "an achievement displays an internal translation key"):
				return
		for achievement_id: String in Database.get_all_achievement_ids():
			for raw_tier: Variant in Array(Database.get_achievement(achievement_id).get("tiers", [])):
				if not _check(not String(Dictionary(raw_tier).get("description", "")).begins_with("achievement."), "a later achievement tier displays an internal translation key"):
					return
	if not _check_new_glyphs():
		return
	Game.start_new_run("balanced", 4242)
	Game.stash_active_run_for_hub()
	Game.start_arena_run("balanced")
	Game.stash_active_run_for_hub()
	var hub: Control = _open_screen("res://scenes/hub/Hub.tscn")
	await get_tree().process_frame
	for node_name: String in ["HubLogo", "HubModeGrid", "RunStartButton", "ArenaStartButton", "ContinueNormalRunButton", "ContinueArenaRunButton", "WebMultiplayerButton"]:
		if not _check(hub.find_child(node_name, true, false) != null, "Hub navigation is missing %s" % node_name):
			return
	hub.queue_free()
	await get_tree().process_frame
	var settings: Control = _open_screen("res://scenes/settings/Settings.tscn")
	await get_tree().process_frame
	for node_name: String in ["SettingsAudioSection", "SettingsDisplaySection", "SettingsToolsSection", "MasterVolumeSlider", "SettingsBackButton"]:
		if not _check(settings.find_child(node_name, true, false) != null, "Settings is missing %s" % node_name):
			return
	settings.queue_free()
	await get_tree().process_frame
	var library: Control = _open_screen("res://scenes/library/CardLibrary.tscn")
	if not await _wait_ready(library):
		return
	var search: LineEdit = library.find_child("LibrarySearch", true, false) as LineEdit
	var grid: GridContainer = library.get("_cards_grid") as GridContainer
	if not _check(search != null and grid.get_child_count() < Database.get_all_card_ids().size(), "library lost search or lazy loading"):
		return
	search.text = Database.get_card("quick_slash").name
	search.text_changed.emit(search.text)
	await get_tree().create_timer(0.25).timeout
	if not await _wait_ready(library):
		return
	if not _check(Dictionary(library.get("_card_widgets")).has("quick_slash"), "name search did not find the matching card"):
		return
	search.text = "__no_such_card__"
	search.text_changed.emit(search.text)
	await get_tree().create_timer(0.25).timeout
	if not await _wait_ready(library):
		return
	var empty: Label = library.find_child("LibraryEmptyNotice", true, false) as Label
	if not _check(grid.get_child_count() == 0 and empty.visible, "empty search state did not render"):
		return
	search.text = ""
	search.text_changed.emit(search.text)
	await get_tree().create_timer(0.25).timeout
	if not await _wait_ready(library):
		return
	if not _check(grid.get_child_count() >= 12 and not empty.visible, "clearing search did not restore the collection"):
		return
	var row_id: int = grid.get_child(0).get_instance_id()
	library.call("on_reenter")
	if not _check(grid.get_child(0).get_instance_id() == row_id, "reenter rebuilt cached library widgets"):
		return
	library.queue_free()
	await get_tree().process_frame
	print("UI_POLISH_SMOKE_OK bilingual achievements, navigation, continued runs, settings, search, caching, glyphs")
	get_tree().quit()


func _open_screen(path: String) -> Control:
	var screen: Control = (load(path) as PackedScene).instantiate() as Control
	screen.theme = UiTheme.get_game_theme()
	add_child(screen)
	return screen


func _wait_ready(screen: Control) -> bool:
	for _frame: int in range(120):
		if bool(screen.call("is_content_ready")):
			return true
		await get_tree().process_frame
	return _check(false, "library did not finish a page")


func _check_new_glyphs() -> bool:
	var font: FontFile = load("res://assets/fonts/NotoSansJP-GameSubset.ttf") as FontFile
	for key: String in ["hub.tagline", "hub.mode.normal_detail", "hub.mode.arena_detail", "hub.mode.online_detail", "hub.mode.infinite_detail", "settings.page_hint", "settings.section.audio", "settings.section.display", "settings.section.tools", "meta.page_hint", "meta.summary_heading", "library.search", "library.empty", "library.matching", "library.collection_summary"]:
		var text: String = Localization.get_text(key, "")
		for index: int in range(text.length()):
			if not _check(font.has_char(text.unicode_at(index)), "a new Japanese UI string has a missing glyph"):
				return false
	return true


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("UI polish smoke failed: %s" % message)
		get_tree().quit(1)
	return condition
