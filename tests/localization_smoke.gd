extends Node

var _failed: bool = false
var _original_language: String = Localization.DEFAULT_LANGUAGE


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	var save_data: SaveData = SaveManager.load_save()
	Game.apply_loaded_save(save_data)
	_original_language = Game.get_language()
	call_deferred("_run")


func _run() -> void:
	var has_japanese: bool = false
	for language_entry in Game.get_available_languages():
		if String(language_entry.get("code", "")) == "ja":
			has_japanese = true
			break
	if not has_japanese:
		_fail("Localization smoke failed: supported language list did not include ja")
		return

	Game.set_language("ja")
	if Game.get_language() != "ja":
		_fail("Localization smoke failed: Game did not switch to Japanese")
		return

	var strike_def: CardDef = Database.get_card("strike")
	if strike_def == null or strike_def.name != "ストライク":
		_fail("Localization smoke failed: card definitions were not reloaded in Japanese")
		return

	var settings_scene: Control = load("res://scenes/settings/Settings.tscn").instantiate() as Control
	add_child(settings_scene)
	await get_tree().process_frame

	var back_button: Button = settings_scene.find_child("SettingsBackButton", true, false) as Button
	var language_option: OptionButton = settings_scene.find_child("LanguageOptionButton", true, false) as OptionButton
	if back_button == null or back_button.text != "戻る":
		_fail("Localization smoke failed: settings scene did not render Japanese button text")
		return
	if language_option == null:
		_fail("Localization smoke failed: language selector was not created")
		return
	if language_option.get_item_text(language_option.selected) != "日本語":
		_fail("Localization smoke failed: settings scene did not select Japanese")
		return

	settings_scene.queue_free()
	await get_tree().process_frame

	_restore_from_disk()
	if _failed:
		return
	if Game.get_language() != "ja":
		_fail("Localization smoke failed: language setting was not restored from disk")
		return

	var guard_def: CardDef = Database.get_card("guard")
	if guard_def == null or guard_def.name != "ガード":
		_fail("Localization smoke failed: localized database content was not restored from disk")
		return

	Game.set_language(_original_language)
	print("Localization smoke passed")
	get_tree().quit()


func _restore_from_disk() -> void:
	Game.settings = {}
	Game.meta_progress = {}
	Game.current_screen_hint = "title"
	Game.pending_enemy_id = ""
	Game.reward_options.clear()
	Game.last_battle_summary.clear()
	Game.last_reward_bundle.clear()
	Game.last_replay_export_path = ""
	var save_data: SaveData = SaveManager.load_save()
	Game.apply_loaded_save(save_data)


func _fail(message: String) -> void:
	_failed = true
	Game.set_language(_original_language)
	push_error(message)
	get_tree().quit(1)
