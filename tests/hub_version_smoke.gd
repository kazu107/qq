extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.settings["language"] = "ja"
	Game.settings["developer_mode"] = false
	Localization.set_language("ja", false)
	call_deferred("_run")


func _run() -> void:
	var current_version: String = GameVersion.get_current_version()
	var version_pattern: RegEx = RegEx.new()
	if version_pattern.compile("^QQ-[0-9]+\\.[0-9]+\\.[0-9]+$") != OK:
		_fail("Hub version smoke failed: version validation pattern could not be compiled")
		return
	if version_pattern.search(current_version) == null:
		_fail("Hub version smoke failed: current version has an invalid format: %s" % current_version)
		return
	if GameVersion.get_scheme() != "QQ-MAJOR.MINOR.PATCH":
		_fail("Hub version smoke failed: custom version scheme is missing")
		return

	var releases: Array[Dictionary] = GameVersion.get_releases()
	if releases.size() < 28 or String(releases[0].get("version", "")) != current_version:
		_fail("Hub version smoke failed: latest history entry does not match the current version")
		return
	var seen_versions: Dictionary = {}
	var previous_date: String = "9999-99-99"
	for release: Dictionary in releases:
		var release_version: String = String(release.get("version", ""))
		var release_date: String = String(release.get("date", ""))
		if version_pattern.search(release_version) == null or seen_versions.has(release_version):
			_fail("Hub version smoke failed: historical versions are invalid or duplicated")
			return
		if release_date == "" or release_date.naturalnocasecmp_to(previous_date) > 0:
			_fail("Hub version smoke failed: release history is not newest-first")
			return
		var changes_ja: Variant = release.get("changes_ja", [])
		var changes_en: Variant = release.get("changes_en", [])
		if String(release.get("title_ja", "")) == "" or String(release.get("title_en", "")) == "":
			_fail("Hub version smoke failed: bilingual release titles are incomplete")
			return
		if changes_ja is not Array or changes_en is not Array or Array(changes_ja).is_empty() or Array(changes_en).is_empty():
			_fail("Hub version smoke failed: bilingual release changes are incomplete")
			return
		seen_versions[release_version] = true
		previous_date = release_date
	var initial_release: Dictionary = releases[releases.size() - 1]
	if String(initial_release.get("version", "")) != "QQ-0.1.0" or not bool(initial_release.get("estimated", false)):
		_fail("Hub version smoke failed: reconstructed initial release is missing")
		return
	var latest_title: String = String(releases[0].get("title_ja", ""))
	if latest_title == "":
		_fail("Hub version smoke failed: latest Japanese release title is missing")
		return

	var hub_scene: PackedScene = load("res://scenes/hub/Hub.tscn") as PackedScene
	if hub_scene == null:
		_fail("Hub version smoke failed: Hub scene could not be loaded")
		return
	var hub: Control = hub_scene.instantiate() as Control
	add_child(hub)
	await get_tree().process_frame

	var top_actions: HBoxContainer = hub.find_child("HubTopActions", true, false) as HBoxContainer
	var settings_button: Button = hub.find_child("OpenSettingsButton", true, false) as Button
	var history_button: Button = hub.find_child("VersionHistoryButton", true, false) as Button
	var history_overlay: ColorRect = hub.find_child("VersionHistoryOverlay", true, false) as ColorRect
	var history_content: RichTextLabel = hub.find_child("VersionHistoryContent", true, false) as RichTextLabel
	var history_note: Label = hub.find_child("VersionHistoryNote", true, false) as Label
	var close_button: Button = hub.find_child("VersionHistoryCloseButton", true, false) as Button
	if top_actions == null or settings_button == null or history_button == null:
		_fail("Hub version smoke failed: top-right Hub actions are incomplete")
		return
	if history_overlay == null or history_content == null or history_note == null or close_button == null:
		_fail("Hub version smoke failed: version history modal is incomplete")
		return
	if history_note.text == "" or history_note.text.find("推定") == -1:
		_fail("Hub version smoke failed: reconstructed history notice is missing")
		return

	var settings_buttons: Array[Node] = hub.find_children("OpenSettingsButton", "Button", true, false)
	if settings_buttons.size() != 1 or settings_button.get_parent() != top_actions:
		_fail("Hub version smoke failed: settings should only exist in the top-right action row")
		return
	if top_actions.anchor_left != 1.0 or top_actions.anchor_right != 1.0 or top_actions.anchor_top != 0.0:
		_fail("Hub version smoke failed: action row is not anchored to the top-right")
		return
	if settings_button.text != "" or settings_button.tooltip_text == "":
		_fail("Hub version smoke failed: settings button should be an accessible icon-only control")
		return
	if not _has_valid_icon(settings_button.icon) or not _has_valid_icon(history_button.icon):
		_fail("Hub version smoke failed: top-right action icons are invalid")
		return
	if history_button.text.find(current_version) == -1:
		_fail("Hub version smoke failed: current version is not shown on the history button")
		return
	if history_overlay.visible:
		_fail("Hub version smoke failed: version history should start closed")
		return

	history_button.emit_signal("pressed")
	await get_tree().process_frame
	if not history_overlay.visible:
		_fail("Hub version smoke failed: version history did not open")
		return
	if history_content.text.find(current_version) == -1 or history_content.text.find(latest_title) == -1 or history_content.text.find("推定") == -1:
		_fail("Hub version smoke failed: version history content is incomplete")
		return

	close_button.emit_signal("pressed")
	await get_tree().process_frame
	if history_overlay.visible:
		_fail("Hub version smoke failed: version history did not close")
		return
	if not _has_valid_icon(StatIconFactory.get_icon("settings")) or not _has_valid_icon(StatIconFactory.get_icon("version_history")):
		_fail("Hub version smoke failed: generated Hub icons are unavailable")
		return

	hub.queue_free()
	print("Hub version smoke passed: %s" % current_version)
	get_tree().quit()


func _has_valid_icon(texture: Texture2D) -> bool:
	return texture != null and texture.get_width() > 0 and texture.get_height() > 0


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
