extends Control

var _info_label: Label
var _developer_panel: DeveloperPanel


func _ready() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 80.0
	margin.offset_top = 60.0
	margin.offset_right = -80.0
	margin.offset_bottom = -60.0
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var title: Label = Label.new()
	title.text = Localization.get_text("hub.title", "Hub")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.text = Localization.get_textf("hub.meta_points", "Meta Points: {points}", {
		"points": Game.get_meta_points(),
	})
	root.add_child(_info_label)

	var start_button: Button = Button.new()
	start_button.text = Localization.get_text("hub.run_start", "Run Start")
	start_button.pressed.connect(func() -> void:
		SceneRouter.go_to_run_setup()
	)
	root.add_child(start_button)

	var meta_button: Button = Button.new()
	meta_button.text = Localization.get_text("hub.meta_progress", "Meta Progress")
	meta_button.pressed.connect(_on_open_meta_progress)
	root.add_child(meta_button)

	var library_button: Button = Button.new()
	library_button.text = Localization.get_text("hub.card_library", "Card Library")
	library_button.pressed.connect(_on_open_card_library)
	root.add_child(library_button)

	var settings_button: Button = Button.new()
	settings_button.name = "OpenSettingsButton"
	settings_button.text = Localization.get_text("hub.settings", "Settings")
	settings_button.pressed.connect(func() -> void:
		Game.open_settings("hub")
		SceneRouter.go_to_settings()
	)
	root.add_child(settings_button)

	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right()
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevStartRun", "label": Localization.get_text("hub.dev.quick_run", "Quick Run"), "callback": Callable(self, "_on_dev_quick_run")},
			{"id": "DevOpenBattle", "label": Localization.get_text("hub.dev.open_battle", "Open Battle"), "callback": Callable(self, "_on_dev_open_battle")},
			{"id": "DevOpenReward", "label": Localization.get_text("hub.dev.open_reward", "Open Reward"), "callback": Callable(self, "_on_dev_open_reward")},
			{"id": "DevOpenResult", "label": Localization.get_text("hub.dev.open_result", "Open Result"), "callback": Callable(self, "_on_dev_open_result")},
			{"id": "DevAddPoints", "label": Localization.get_text("hub.dev.add_points", "Add 5 Points"), "callback": Callable(self, "_on_dev_add_points")},
			{"id": "DevUnlockAll", "label": Localization.get_text("hub.dev.unlock_all", "Unlock All Meta"), "callback": Callable(self, "_on_dev_unlock_all")},
			{"id": "DevResetMeta", "label": Localization.get_text("hub.dev.reset_meta", "Reset Meta"), "callback": Callable(self, "_on_dev_reset_meta")},
			{"id": "DevToggleOff", "label": Localization.get_text("hub.dev.turn_off", "Turn Off"), "callback": Callable(self, "_on_dev_turn_off")},
		],
		Localization.get_text("hub.dev.summary", "Quick scene access and meta control for manual testing.")
	)


func _on_dev_quick_run() -> void:
	Game.developer_start_run("balanced")
	SceneRouter.go_to_map()


func _on_dev_open_battle() -> void:
	Game.developer_open_battle("scout")
	SceneRouter.go_to_battle()


func _on_dev_open_reward() -> void:
	Game.developer_open_reward()
	SceneRouter.go_to_reward()


func _on_dev_open_result() -> void:
	Game.developer_open_result()
	SceneRouter.go_to_result()


func _on_dev_add_points() -> void:
	Game.developer_add_points(5)
	_info_label.text = Localization.get_textf("hub.meta_points", "Meta Points: {points}", {
		"points": Game.get_meta_points(),
	})


func _on_dev_unlock_all() -> void:
	Game.developer_unlock_all_meta()
	_info_label.text = Localization.get_text("hub.meta_unlocked_all", "Unlocked all meta entries.")


func _on_dev_reset_meta() -> void:
	Game.developer_reset_meta_progress()
	_info_label.text = Localization.get_text("hub.meta_reset", "Meta progress reset.")


func _on_dev_turn_off() -> void:
	Game.set_developer_mode_enabled(false)
	SceneRouter.go_to_hub()


func _on_open_meta_progress() -> void:
	Game.current_screen_hint = "meta"
	SaveManager.save_game("meta")
	SceneRouter.go_to_meta_progress()


func _on_open_card_library() -> void:
	Game.current_screen_hint = "library"
	SaveManager.save_game("library")
	SceneRouter.go_to_card_library()
