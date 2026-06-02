extends Control

var _selected_starter_id: String = ""
var _details_label: RichTextLabel
var _start_button: Button
var _starter_cards_panel: CardHandPanel
var _developer_panel: DeveloperPanel


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 40.0
	margin.offset_top = 40.0
	margin.offset_right = -40.0
	margin.offset_bottom = -40.0
	add_child(margin)

	var root := HBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)

	var title := Label.new()
	title.text = Localization.get_text("run_setup.title", "Select Starter Loadout")
	left.add_child(title)

	for starter in Game.get_unlocked_starters():
		var starter_id := String(starter.get("id", ""))
		var button := Button.new()
		button.name = "StarterButton_%s" % starter_id
		button.text = String(starter.get("name", starter_id))
		button.pressed.connect(_select_starter.bind(starter_id))
		left.add_child(button)
		if _selected_starter_id == "":
			_selected_starter_id = starter_id

	_details_label = RichTextLabel.new()
	_details_label.fit_content = true
	right.add_child(_details_label)

	var cards_title := Label.new()
	cards_title.text = Localization.get_text("run_setup.starter_cards", "Starter Cards")
	right.add_child(cards_title)

	_starter_cards_panel = CardHandPanel.new()
	_starter_cards_panel.name = "StarterCards"
	_starter_cards_panel.set_interactive(false)
	_starter_cards_panel.set_tile_size(Vector2(96.0, 96.0))
	right.add_child(_starter_cards_panel)

	var button_row := HBoxContainer.new()
	right.add_child(button_row)

	_start_button = Button.new()
	_start_button.text = Localization.get_text("run_setup.start", "Start")
	_start_button.pressed.connect(_on_start)
	button_row.add_child(_start_button)

	var back_button := Button.new()
	back_button.text = Localization.get_text("run_setup.back", "Back")
	back_button.pressed.connect(func() -> void:
		SceneRouter.go_to_hub()
	)
	button_row.add_child(back_button)

	_refresh_details()

	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _select_starter(starter_id: String) -> void:
	_selected_starter_id = starter_id
	AudioManager.play_sfx("ui_toggle")
	_refresh_details()


func _refresh_details() -> void:
	var starter: Dictionary = Database.get_starter(_selected_starter_id)
	if starter.is_empty():
		_details_label.text = Localization.get_text("run_setup.none_selected", "No starter selected.")
		_starter_cards_panel.refresh_card_ids([], false, "KIT")
		_start_button.disabled = true
		return
	var cards: Array[String] = _to_string_array(starter.get("cards", []))
	_details_label.text = "\n".join([
		String(starter.get("name", "")),
		String(starter.get("description", "")),
		"",
		Localization.get_textf("run_setup.stats", "HP {hp} | ATK {attack} | DEF {defense} | SPD {speed}", {
			"hp": int(starter.get("max_hp", 0)),
			"attack": int(starter.get("attack", 0)),
			"defense": int(starter.get("defense", 0)),
			"speed": int(starter.get("speed", 0)),
		}),
	])
	_starter_cards_panel.refresh_card_ids(cards, false, "KIT")
	_start_button.disabled = false


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(String(item))
	return result


func _on_start() -> void:
	Game.start_new_run(_selected_starter_id)
	SceneRouter.go_to_map()


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right(20.0, 20.0)
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevStartBalanced", "label": Localization.get_text("run_setup.dev.start_balanced", "Start Balanced"), "callback": Callable(self, "_on_dev_start_balanced")},
			{"id": "DevStartTempo", "label": Localization.get_text("run_setup.dev.start_tempo", "Start Tempo"), "callback": Callable(self, "_on_dev_start_tempo")},
			{"id": "DevStartFortress", "label": Localization.get_text("run_setup.dev.start_fortress", "Start Fortress"), "callback": Callable(self, "_on_dev_start_fortress")},
		],
		Localization.get_text("run_setup.dev.summary", "Skip selection and start a test run immediately.")
	)


func _on_dev_start_balanced() -> void:
	Game.developer_start_run("balanced")
	SceneRouter.go_to_map()


func _on_dev_start_tempo() -> void:
	Game.developer_start_run("tempo")
	SceneRouter.go_to_map()


func _on_dev_start_fortress() -> void:
	Game.developer_start_run("fortress")
	SceneRouter.go_to_map()
