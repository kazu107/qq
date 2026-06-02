extends Control

var _continue_button: Button
var _status_label: Label
var _developer_button: Button


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 120.0
	margin.offset_top = 80.0
	margin.offset_right = -120.0
	margin.offset_bottom = -80.0
	add_child(margin)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var title := Label.new()
	title.text = Localization.get_text("title.game_title", "Realtime Card Tactics")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_status_label = Label.new()
	_status_label.text = Localization.get_text("title.subtitle", "Spec-driven MVP build")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status_label)

	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(320.0, 0.0)
	root.add_child(buttons)

	var new_game_button := Button.new()
	new_game_button.text = Localization.get_text("title.new_game", "New Game")
	new_game_button.pressed.connect(_on_new_game)
	buttons.add_child(new_game_button)

	_continue_button = Button.new()
	_continue_button.text = Localization.get_text("title.continue", "Continue")
	_continue_button.disabled = not SaveManager.has_save() or (Game.current_run == null and Game.current_screen_hint == "title")
	_continue_button.pressed.connect(_on_continue)
	buttons.add_child(_continue_button)

	_developer_button = Button.new()
	_developer_button.name = "DeveloperModeButton"
	_developer_button.pressed.connect(_on_toggle_developer_mode)
	buttons.add_child(_developer_button)

	var settings_button := Button.new()
	settings_button.name = "OpenSettingsButton"
	settings_button.text = Localization.get_text("title.settings", "Settings")
	settings_button.pressed.connect(func() -> void:
		Game.open_settings("title")
		SceneRouter.go_to_settings()
	)
	buttons.add_child(settings_button)

	var quit_button := Button.new()
	quit_button.text = Localization.get_text("title.quit", "Quit")
	quit_button.pressed.connect(func() -> void:
		get_tree().quit()
	)
	buttons.add_child(quit_button)

	_refresh_buttons()


func _on_new_game() -> void:
	Game.current_run = null
	Game.pending_enemy_id = ""
	Game.reward_options.clear()
	Game.last_battle_summary.clear()
	Game.current_screen_hint = "hub"
	SaveManager.save_game("hub")
	SceneRouter.go_to_hub()


func _on_continue() -> void:
	SceneRouter.go_to_continue_target()


func _on_toggle_developer_mode() -> void:
	var enabled: bool = Game.toggle_developer_mode()
	AudioManager.play_sfx("ui_toggle")
	_status_label.text = Localization.get_textf("title.dev_status", "Developer mode {state}", {
		"state": Localization.get_text("common.%s" % ("on" if enabled else "off"), "ON" if enabled else "OFF"),
	})
	_refresh_buttons()


func _refresh_buttons() -> void:
	_continue_button.disabled = not SaveManager.has_save() or (Game.current_run == null and Game.current_screen_hint == "title")
	_developer_button.text = Localization.get_textf("title.developer_mode", "Developer Mode: {state}", {
		"state": Localization.get_text("common.%s" % ("on" if Game.is_developer_mode_enabled() else "off"), "ON" if Game.is_developer_mode_enabled() else "OFF"),
	})
