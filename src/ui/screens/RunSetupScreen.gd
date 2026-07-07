extends Control

const PORTRAIT_PATH_TEMPLATE := "res://assets/portraits/%s.png"

var _selected_starter_id: String = ""
var _details_label: RichTextLabel
var _start_button: Button
var _starter_cards_panel: CardHandPanel
var _developer_panel: DeveloperPanel
var _starter_stats_row: HBoxContainer
var _portrait_rect: TextureRect
var _hp_value_label: Label
var _attack_value_label: Label
var _speed_value_label: Label
var _is_arena_setup: bool = false


func _ready() -> void:
	_is_arena_setup = Game.get_run_setup_mode() == Game.RUN_SETUP_MODE_ARENA
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

	var portrait_frame: PanelContainer = PanelContainer.new()
	portrait_frame.name = "StarterPortraitFrame"
	portrait_frame.custom_minimum_size = Vector2(260.0, 260.0)
	right.add_child(portrait_frame)

	_portrait_rect = TextureRect.new()
	_portrait_rect.name = "StarterPortrait"
	_portrait_rect.custom_minimum_size = Vector2(252.0, 252.0)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(_portrait_rect)

	_details_label = RichTextLabel.new()
	_details_label.fit_content = true
	right.add_child(_details_label)

	_starter_stats_row = HBoxContainer.new()
	_starter_stats_row.name = "StarterStatsIconRow"
	_starter_stats_row.add_theme_constant_override("separation", 16)
	right.add_child(_starter_stats_row)
	_hp_value_label = _add_text_stat_item("HP")
	_attack_value_label = _add_icon_stat_item("Attack", "attack")
	_speed_value_label = _add_icon_stat_item("Speed", "speed")

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

	if not _is_arena_setup:
		_start_button = Button.new()
		_start_button.name = "RunStartSelectedButton"
		_start_button.text = Localization.get_text("run_setup.start", "Start")
		_start_button.pressed.connect(_on_start)
		button_row.add_child(_start_button)

	var arena_button: Button = Button.new()
	arena_button.name = "ArenaStartSelectedButton"
	arena_button.text = Localization.get_text("run_setup.start_arena", "Start Arena")
	arena_button.pressed.connect(_on_start_arena)
	button_row.add_child(arena_button)

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
		_refresh_portrait("")
		_starter_stats_row.visible = false
		_starter_cards_panel.refresh_card_ids([], false, "KIT")
		if _start_button != null:
			_start_button.disabled = true
		return
	var cards: Array[String] = _to_string_array(starter.get("cards", []))
	_details_label.text = "\n".join([
		String(starter.get("name", "")),
		String(starter.get("description", "")),
	])
	_refresh_portrait(_selected_starter_id)
	_starter_stats_row.visible = true
	_hp_value_label.text = "%d" % int(starter.get("max_hp", 0))
	_attack_value_label.text = "%d" % int(starter.get("attack", 0))
	_speed_value_label.text = "%d" % int(starter.get("speed", 0))
	_starter_cards_panel.refresh_card_ids(cards, false, "KIT")
	if _start_button != null:
		_start_button.disabled = false


func _add_text_stat_item(label_text: String) -> Label:
	var item: HBoxContainer = HBoxContainer.new()
	item.name = "%sStatItem" % label_text
	item.add_theme_constant_override("separation", 5)
	_starter_stats_row.add_child(item)

	var text_label: Label = Label.new()
	text_label.name = "%sLabel" % label_text
	text_label.text = label_text
	item.add_child(text_label)

	var value_label: Label = Label.new()
	value_label.name = "%sValue" % label_text
	item.add_child(value_label)
	return value_label


func _add_icon_stat_item(node_prefix: String, stat_id: String) -> Label:
	var item: HBoxContainer = HBoxContainer.new()
	item.name = "%sStatItem" % node_prefix
	item.add_theme_constant_override("separation", 5)
	_starter_stats_row.add_child(item)

	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.name = "%sIcon" % node_prefix
	icon_rect.custom_minimum_size = Vector2(22.0, 22.0)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = StatIconFactory.get_icon(stat_id)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(icon_rect)

	var value_label: Label = Label.new()
	value_label.name = "%sValue" % node_prefix
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item.add_child(value_label)
	return value_label


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(String(item))
	return result


func _refresh_portrait(starter_id: String) -> void:
	if _portrait_rect == null:
		return
	var portrait_path: String = PORTRAIT_PATH_TEMPLATE % starter_id
	if not ResourceLoader.exists(portrait_path):
		_portrait_rect.texture = null
		return
	var texture_resource: Resource = load(portrait_path)
	_portrait_rect.texture = texture_resource as Texture2D


func _on_start() -> void:
	Game.start_new_run(_selected_starter_id)
	SceneRouter.go_to_map()


func _on_start_arena() -> void:
	if Game.start_arena_run(_selected_starter_id):
		SceneRouter.go_to_arena()


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right(20.0, 20.0)
	var actions: Array = []
	for starter in Database.starters:
		var starter_id: String = String(starter.get("id", ""))
		if starter_id == "":
			continue
		var starter_name: String = String(starter.get("name", starter_id))
		actions.append({
			"id": "DevStart_%s" % starter_id,
			"label": Localization.get_textf("run_setup.dev.start_starter", "{name} Start", {"name": starter_name}),
			"callback": Callable(self, "_on_dev_start_starter").bind(starter_id),
		})
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		actions,
		Localization.get_text("run_setup.dev.summary", "Skip selection and start a test run immediately.")
	)


func _on_dev_start_starter(starter_id: String) -> void:
	Game.developer_start_run(starter_id)
	SceneRouter.go_to_map()
