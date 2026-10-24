extends Node

const REMOVED_COPY: Array[Array] = [
	["hub.tagline", "Every card has its moment. Make yours count."],
	["hub.mode.normal_detail", "Choose a route, gather cards and relics, and challenge the boss."],
	["settings.page_hint", "Changes are saved automatically and used throughout the game."],
	["meta.page_hint", "Achievements and automatic unlocks. Manage seals in the Card & Relic Library."],
	["meta.stat_upgrade.hint", "Spend Meta Points to strengthen future Normal and Infinite runs. Current/suspended runs and Arena/Web matches are unchanged."],
	["run_setup.subtitle", "Compare each frame, inspect its opening hand, then choose your combat loadout."],
	["run_setup.deck_list_hint", "Select a deck to compare its frame and opening cards."],
	["run_setup.preview_hint", "The battle-ready stance and equipped frame are previewed in real time."],
	["tutorial.catalog.subtitle", "Choose a lesson. More tutorials can be added to this list later."],
]
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("UI copy: " + message)
		get_tree().quit(1)
		assert(value, message)


func _run() -> void:
	Game.settings["developer_mode"] = false
	for language: String in ["ja", "en"]:
		Game.set_language(language)
		Game.ensure_meta_initialized()
		for path: String in ["hub/Hub", "settings/Settings", "meta/MetaProgress", "run_setup/RunSetup", "tutorial/BattleTutorial"]:
			var screen: Control = load("res://scenes/%s.tscn" % path).instantiate() as Control
			screen.theme = UiTheme.get_game_theme()
			add_child(screen)
			for frame: int in 180:
				await get_tree().process_frame
				if not screen.has_method("is_content_ready") or screen.call("is_content_ready"): break
			var captions: Array[String] = []
			_collect(screen, captions)
			for pair: Array in REMOVED_COPY:
				_check(not captions.has(Localization.get_text(pair[0], pair[1])), "redundant caption remains: %s / %s" % [path, pair[0]])
			_check(not captions.has("LIVE 3D"), "decorative preview caption remains")
			if path == "hub/Hub":
				var history: RichTextLabel = screen.find_child("VersionHistoryContent", true, false) as RichTextLabel
				screen.call("_open_version_history")
				await get_tree().process_frame
				_check(history.language == language and history.text.contains("[table=2]"), "history language or hanging list missing")
				var parsed: String = history.get_parsed_text()
				var suffix: String = "changes_" + language
				for release: Dictionary in GameVersion.get_releases():
					for change: String in Array(release[suffix]):
						var offset: int = parsed.find(change)
						_check(offset >= 0, "release note missing")
						for index: int in change.length():
							var code: int = change.unicode_at(index)
							if code >= 0x3000 and code <= 0x9fff: _check(UiTheme.GAME_FONT.has_char(code), "history glyph missing: " + change[index])
				_check(history.text.count("[table=2]") == GameVersion.get_releases().size(), "not every release uses a hanging list")
				_check(screen.find_child("VersionHistoryNote", true, false) == null, "history subtitle remains")
			if path == "run_setup/RunSetup":
				_check(screen.find_child("RunSetupSubtitle", true, false) == null and screen.find_child("StarterModelPreview", true, false) != null, "setup lost model or retained subtitle")
			if path == "meta/MetaProgress":
				_check(screen.find_child("MetaStatUpgradeHint", true, false) == null and screen.find_child("BuyMetaStatUpgrade_max_hp", true, false) != null, "meta lost controls or retained hint")
			screen.queue_free()
			await get_tree().process_frame
	print("UI_COPY_SMOKE_OK checks=%d bilingual captions, history lists, preserved controls" % _checks)
	get_tree().quit()


func _collect(node: Node, captions: Array[String]) -> void:
	if node is Label: captions.append(node.text)
	elif node is RichTextLabel: captions.append(node.get_parsed_text())
	for child: Node in node.get_children(): _collect(child, captions)
