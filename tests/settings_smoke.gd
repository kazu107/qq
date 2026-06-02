extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.set_developer_mode_enabled(true)
	Game.set_master_volume(1.0)
	Game.set_replay_auto_export_enabled(true)
	call_deferred("_run")


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/title/Title.tscn")
	var title_scene: Node = await _wait_for_scene("Title")
	if _failed or title_scene == null:
		return

	var settings_button: Button = title_scene.find_child("OpenSettingsButton", true, false) as Button
	if settings_button == null:
		_fail("Settings smoke failed: title screen settings button was missing")
		return
	settings_button.emit_signal("pressed")

	var settings_scene: Node = await _wait_for_scene("Settings")
	if _failed or settings_scene == null:
		return

	var developer_panel: DeveloperPanel = settings_scene.find_child("DeveloperPanel", true, false) as DeveloperPanel
	if developer_panel == null:
		_fail("Settings smoke failed: developer panel did not render on the settings scene")
		return

	var volume_slider: HSlider = settings_scene.find_child("MasterVolumeSlider", true, false) as HSlider
	var sfx_slider: HSlider = settings_scene.find_child("SfxVolumeSlider", true, false) as HSlider
	var replay_toggle: CheckButton = settings_scene.find_child("ReplayAutoExportToggle", true, false) as CheckButton
	var back_button: Button = settings_scene.find_child("SettingsBackButton", true, false) as Button
	if volume_slider == null or sfx_slider == null or replay_toggle == null or back_button == null:
		_fail("Settings smoke failed: one or more settings controls were missing")
		return

	AudioManager.clear_play_history()
	volume_slider.value = 0.35
	volume_slider.emit_signal("value_changed", 0.35)
	sfx_slider.value = 0.45
	sfx_slider.emit_signal("value_changed", 0.45)
	replay_toggle.button_pressed = false
	replay_toggle.emit_signal("toggled", false)
	await get_tree().process_frame

	if absf(Game.get_master_volume() - 0.35) > 0.001:
		_fail("Settings smoke failed: master volume did not update in Game settings")
		return
	if absf(AudioManager.get_master_volume() - 0.35) > 0.001:
		_fail("Settings smoke failed: master volume did not update in AudioManager")
		return
	if absf(Game.get_sfx_volume() - 0.45) > 0.001:
		_fail("Settings smoke failed: SFX volume did not update in Game settings")
		return
	if absf(AudioManager.get_sfx_volume() - 0.45) > 0.001:
		_fail("Settings smoke failed: SFX volume did not update in AudioManager")
		return
	if Game.is_replay_auto_export_enabled():
		_fail("Settings smoke failed: replay auto export toggle did not persist")
		return
	if not AudioManager.has_played_sfx("ui_toggle"):
		_fail("Settings smoke failed: settings changes should trigger UI toggle SFX")
		return

	_restore_from_disk()
	if _failed:
		return
	if absf(Game.get_master_volume() - 0.35) > 0.001 or absf(Game.get_sfx_volume() - 0.45) > 0.001 or Game.is_replay_auto_export_enabled():
		_fail("Settings smoke failed: settings were not restored from disk")
		return

	back_button.emit_signal("pressed")
	var returned_scene: Node = await _wait_for_scene("Title")
	if _failed or returned_scene == null:
		return

	print("Settings smoke passed")
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


func _wait_for_scene(scene_name: String) -> Node:
	var timeout_frames: int = 180
	while timeout_frames > 0:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and String(scene.name) == scene_name:
			return scene
		timeout_frames -= 1
	_fail("Settings smoke failed: scene %s did not open" % scene_name)
	return null


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
