extends Control

var _tutorials: Array[Dictionary] = []


func _ready() -> void:
	Database.load_all()
	_tutorials = BattleTutorialCatalog.get_all()
	_build_ui()


func get_tutorial_count() -> int:
	return _tutorials.size()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.012, 0.026, 0.042, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 52)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_bottom", 52)
	add_child(margin)

	var root := VBoxContainer.new()
	root.name = "TutorialCatalog"
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)
	var heading_box := VBoxContainer.new()
	heading_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading_box)
	var title := Label.new()
	title.text = Localization.get_text("tutorial.catalog.title", "Tutorials")
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	heading_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = Localization.get_text("tutorial.catalog.subtitle", "Choose a lesson. More tutorials can be added to this list later.")
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82, 1.0))
	heading_box.add_child(subtitle)
	var back := Button.new()
	back.name = "TutorialBackButton"
	back.text = Localization.get_text("common.back_hub", "Back to Hub")
	back.custom_minimum_size = Vector2(160.0, 42.0)
	back.pressed.connect(SceneRouter.go_to_hub)
	header.add_child(back)

	var divider := HSeparator.new()
	root.add_child(divider)

	var scroll := ScrollContainer.new()
	scroll.name = "TutorialScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "TutorialList"
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for index: int in range(_tutorials.size()):
		list.add_child(_build_tutorial_item(_tutorials[index], index))


func _build_tutorial_item(tutorial: Dictionary, index: int) -> Control:
	var panel := PanelContainer.new()
	panel.name = "TutorialItem_%s" % String(tutorial["id"])
	panel.custom_minimum_size = Vector2(0.0, 154.0)
	panel.add_theme_stylebox_override("panel", _make_item_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	margin.add_child(row)

	var number := Label.new()
	number.text = "%02d" % (index + 1)
	number.custom_minimum_size = Vector2(66.0, 0.0)
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size", 30)
	number.add_theme_color_override("font_color", Color(1.0, 0.74, 0.22, 1.0))
	row.add_child(number)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 6)
	row.add_child(copy)
	var item_title := Label.new()
	item_title.text = Localization.get_text(String(tutorial["title_key"]), String(tutorial["title_fallback"]))
	item_title.add_theme_font_size_override("font_size", 25)
	item_title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
	copy.add_child(item_title)
	var description := Label.new()
	description.text = Localization.get_text(String(tutorial["description_key"]), String(tutorial["description_fallback"]))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 17)
	description.add_theme_color_override("font_color", Color(0.74, 0.82, 0.88, 1.0))
	copy.add_child(description)
	var topics := Label.new()
	topics.text = Localization.get_text(String(tutorial["topics_key"]), String(tutorial["topics_fallback"]))
	topics.add_theme_color_override("font_color", Color(0.42, 0.82, 1.0, 1.0))
	copy.add_child(topics)

	var action := VBoxContainer.new()
	action.custom_minimum_size = Vector2(180.0, 0.0)
	action.alignment = BoxContainer.ALIGNMENT_CENTER
	action.add_theme_constant_override("separation", 8)
	row.add_child(action)
	var duration := Label.new()
	duration.text = Localization.get_text(String(tutorial["duration_key"]), String(tutorial["duration_fallback"]))
	duration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	duration.add_theme_color_override("font_color", Color(0.68, 0.72, 0.76, 1.0))
	action.add_child(duration)
	var difficulty := Label.new()
	difficulty.text = Localization.get_text(String(tutorial["difficulty_key"]), String(tutorial["difficulty_fallback"]))
	difficulty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty.add_theme_color_override("font_color", Color(1.0, 0.74, 0.24, 1.0))
	action.add_child(difficulty)
	var start := Button.new()
	start.name = "TutorialStart_%s" % String(tutorial["id"])
	start.text = Localization.get_text("tutorial.catalog.start", "Start")
	start.custom_minimum_size = Vector2(180.0, 46.0)
	start.pressed.connect(SceneRouter.start_battle_tutorial.bind(String(tutorial["id"])))
	action.add_child(start)
	return panel


func _make_item_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.060, 0.082, 0.96)
	style.border_color = Color(0.22, 0.50, 0.65, 0.86)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.36)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 4.0)
	return style
