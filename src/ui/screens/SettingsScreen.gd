extends Control

var _master_volume_value: Label
var _master_volume_slider: HSlider
var _sfx_volume_value: Label
var _sfx_volume_slider: HSlider
var _language_option: OptionButton
var _language_codes: Array[String] = []
var _resolution_option: OptionButton
var _resolution_codes: Array[String] = []
var _replay_toggle: CheckButton
var _developer_toggle: CheckButton
var _status_label: Label
var _developer_panel: DeveloperPanel


func _ready() -> void:
	Game.current_screen_hint = "settings"
	SaveManager.save_game("settings")
	if not Localization.language_changed.is_connected(_on_language_changed):
		Localization.language_changed.connect(_on_language_changed)
	_rebuild_ui()


func _exit_tree() -> void:
	if Localization.language_changed.is_connected(_on_language_changed):
		Localization.language_changed.disconnect(_on_language_changed)


func _rebuild_ui() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_master_volume_value = null
	_master_volume_slider = null
	_sfx_volume_value = null
	_sfx_volume_slider = null
	_language_option = null
	_language_codes.clear()
	_resolution_option = null
	_resolution_codes.clear()
	_replay_toggle = null
	_developer_toggle = null
	_status_label = null
	_developer_panel = null

	_build_ui()
	_refresh_ui()
	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 80.0
	margin.offset_top = 60.0
	margin.offset_right = -80.0
	margin.offset_bottom = -60.0
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	var title: Label = Label.new()
	title.text = Localization.get_text("settings.title", "Settings")
	root.add_child(title)

	var summary: Label = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = Localization.get_text(
		"settings.summary",
		"Adjust global settings used by Title, Hub, battle replay export, and global audio playback."
	)
	root.add_child(summary)

	var volume_row: HBoxContainer = HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	root.add_child(volume_row)

	var volume_label: Label = Label.new()
	volume_label.text = Localization.get_text("settings.master_volume", "Master Volume")
	volume_label.custom_minimum_size = Vector2(160.0, 0.0)
	volume_row.add_child(volume_label)

	_master_volume_slider = HSlider.new()
	_master_volume_slider.name = "MasterVolumeSlider"
	_master_volume_slider.min_value = 0.0
	_master_volume_slider.max_value = 1.0
	_master_volume_slider.step = 0.05
	_master_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_master_volume_slider.value_changed.connect(_on_master_volume_changed)
	volume_row.add_child(_master_volume_slider)

	_master_volume_value = Label.new()
	_master_volume_value.name = "MasterVolumeValue"
	_master_volume_value.custom_minimum_size = Vector2(56.0, 0.0)
	volume_row.add_child(_master_volume_value)

	var sfx_row: HBoxContainer = HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 12)
	root.add_child(sfx_row)

	var sfx_label: Label = Label.new()
	sfx_label.text = Localization.get_text("settings.sfx_volume", "SFX Volume")
	sfx_label.custom_minimum_size = Vector2(160.0, 0.0)
	sfx_row.add_child(sfx_label)

	_sfx_volume_slider = HSlider.new()
	_sfx_volume_slider.name = "SfxVolumeSlider"
	_sfx_volume_slider.min_value = 0.0
	_sfx_volume_slider.max_value = 1.0
	_sfx_volume_slider.step = 0.05
	_sfx_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	sfx_row.add_child(_sfx_volume_slider)

	_sfx_volume_value = Label.new()
	_sfx_volume_value.name = "SfxVolumeValue"
	_sfx_volume_value.custom_minimum_size = Vector2(56.0, 0.0)
	sfx_row.add_child(_sfx_volume_value)

	var language_row: HBoxContainer = HBoxContainer.new()
	language_row.add_theme_constant_override("separation", 12)
	root.add_child(language_row)

	var language_label: Label = Label.new()
	language_label.text = Localization.get_text("settings.language", "Language")
	language_label.custom_minimum_size = Vector2(160.0, 0.0)
	language_row.add_child(language_label)

	_language_option = OptionButton.new()
	_language_option.name = "LanguageOptionButton"
	_language_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_language_option.item_selected.connect(_on_language_selected)
	language_row.add_child(_language_option)

	for language_entry in Game.get_available_languages():
		var language_code: String = String(language_entry.get("code", Localization.DEFAULT_LANGUAGE))
		var label: String = String(language_entry.get("label", language_code))
		_language_codes.append(language_code)
		_language_option.add_item(label)

	var resolution_row: HBoxContainer = HBoxContainer.new()
	resolution_row.add_theme_constant_override("separation", 12)
	root.add_child(resolution_row)

	var resolution_label: Label = Label.new()
	resolution_label.text = Localization.get_text("settings.resolution", "Resolution")
	resolution_label.custom_minimum_size = Vector2(160.0, 0.0)
	resolution_row.add_child(resolution_label)

	_resolution_option = OptionButton.new()
	_resolution_option.name = "ResolutionOptionButton"
	_resolution_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resolution_option.item_selected.connect(_on_resolution_selected)
	resolution_row.add_child(_resolution_option)

	for resolution_entry in Game.get_available_resolutions():
		var resolution_code: String = String(resolution_entry.get("code", Game.DEFAULT_RESOLUTION))
		var resolution_label_text: String = String(resolution_entry.get("label", resolution_code))
		_resolution_codes.append(resolution_code)
		_resolution_option.add_item(resolution_label_text)

	_replay_toggle = CheckButton.new()
	_replay_toggle.name = "ReplayAutoExportToggle"
	_replay_toggle.text = Localization.get_text("settings.replay_auto_export", "Auto-export replay JSON after each battle")
	_replay_toggle.toggled.connect(_on_replay_toggle_changed)
	root.add_child(_replay_toggle)

	_developer_toggle = CheckButton.new()
	_developer_toggle.name = "DeveloperModeToggle"
	_developer_toggle.text = Localization.get_text("settings.developer_mode", "Enable developer mode")
	_developer_toggle.toggled.connect(_on_developer_toggle_changed)
	root.add_child(_developer_toggle)

	_status_label = Label.new()
	_status_label.name = "SettingsStatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	root.add_child(buttons)

	var back_button: Button = Button.new()
	back_button.name = "SettingsBackButton"
	back_button.text = Localization.get_text("settings.back", "Back")
	back_button.pressed.connect(_on_back)
	buttons.add_child(back_button)

	var reset_button: Button = Button.new()
	reset_button.name = "ResetSettingsButton"
	reset_button.text = Localization.get_text("settings.reset", "Reset to Defaults")
	reset_button.pressed.connect(_on_reset_settings)
	buttons.add_child(reset_button)


func _refresh_ui() -> void:
	var master_volume: float = Game.get_master_volume()
	var sfx_volume: float = Game.get_sfx_volume()
	_master_volume_slider.set_value_no_signal(master_volume)
	_master_volume_value.text = "%d%%" % int(round(master_volume * 100.0))
	_sfx_volume_slider.set_value_no_signal(sfx_volume)
	_sfx_volume_value.text = "%d%%" % int(round(sfx_volume * 100.0))
	var current_language: String = Game.get_language()
	for language_index in range(_language_codes.size()):
		if _language_codes[language_index] == current_language:
			_language_option.select(language_index)
			break
	var current_resolution: String = Game.get_resolution()
	for resolution_index in range(_resolution_codes.size()):
		if _resolution_codes[resolution_index] == current_resolution:
			_resolution_option.select(resolution_index)
			break
	_replay_toggle.set_pressed_no_signal(Game.is_replay_auto_export_enabled())
	_developer_toggle.set_pressed_no_signal(Game.is_developer_mode_enabled())
	var replay_path: String = Game.get_last_replay_export_path()
	if replay_path == "":
		_status_label.text = Localization.get_text("settings.replay_none", "Replay export path: none yet")
	else:
		_status_label.text = Localization.get_textf("settings.replay_path", "Replay export path: {path}", {
			"path": replay_path,
		})


func _on_master_volume_changed(value: float) -> void:
	Game.set_master_volume(value)
	_master_volume_value.text = "%d%%" % int(round(value * 100.0))
	AudioManager.play_sfx("ui_toggle")


func _on_sfx_volume_changed(value: float) -> void:
	Game.set_sfx_volume(value)
	_sfx_volume_value.text = "%d%%" % int(round(value * 100.0))
	AudioManager.play_sfx("ui_toggle")


func _on_language_selected(index: int) -> void:
	if index < 0 or index >= _language_codes.size():
		return
	AudioManager.play_sfx("ui_toggle")
	Game.set_language(_language_codes[index])


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= _resolution_codes.size():
		return
	AudioManager.play_sfx("ui_toggle")
	Game.set_resolution(_resolution_codes[index])


func _on_replay_toggle_changed(enabled: bool) -> void:
	Game.set_replay_auto_export_enabled(enabled)
	AudioManager.play_sfx("ui_toggle")
	_refresh_ui()


func _on_developer_toggle_changed(enabled: bool) -> void:
	Game.set_developer_mode_enabled(enabled)
	AudioManager.play_sfx("ui_toggle")
	if enabled and _developer_panel == null:
		_build_developer_panel()
	elif not enabled and _developer_panel != null:
		_developer_panel.queue_free()
		_developer_panel = null
	_refresh_ui()


func _on_back() -> void:
	match Game.get_settings_return_hint():
		"hub":
			Game.current_screen_hint = "hub"
			SaveManager.save_game("hub")
			SceneRouter.go_to_hub()
		_:
			Game.current_screen_hint = "title"
			SaveManager.save_game("title")
			SceneRouter.go_to_title()


func _on_reset_settings() -> void:
	Game.reset_settings_to_defaults()
	AudioManager.play_sfx("ui_toggle")
	_refresh_ui()


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right()
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevMuteVolume", "label": Localization.get_text("settings.dev.mute", "Mute"), "callback": Callable(self, "_on_dev_mute")},
			{"id": "DevMaxVolume", "label": Localization.get_text("settings.dev.max_volume", "Max Volume"), "callback": Callable(self, "_on_dev_max_volume")},
			{"id": "DevResetSettings", "label": Localization.get_text("settings.dev.reset", "Reset Settings"), "callback": Callable(self, "_on_reset_settings")},
		],
		Localization.get_text("settings.dev.summary", "Settings shortcuts for save and UI verification.")
	)


func _on_dev_mute() -> void:
	Game.set_master_volume(0.0)
	_refresh_ui()


func _on_dev_max_volume() -> void:
	Game.set_master_volume(1.0)
	_refresh_ui()


func _on_language_changed(_language_code: String) -> void:
	_rebuild_ui()
