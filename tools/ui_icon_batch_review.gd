extends Control


func _ready() -> void:
	theme = UiTheme.get_game_theme()
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	margin.add_child(layout)
	var title: Label = Label.new()
	title.text = "Blender Small Icon Review | 3D / 24px / controls"
	title.theme_type_variation = "SectionTitle"
	layout.add_child(title)
	var controls: HBoxContainer = HBoxContainer.new()
	layout.add_child(controls)
	for theme_type: String in ["CheckBox", "CheckButton"]:
		for on: bool in [false, true]:
			var button: BaseButton = CheckBox.new() if theme_type == "CheckBox" else CheckButton.new()
			button.text = theme_type + (" ON" if on else " OFF")
			button.button_pressed = on
			controls.add_child(button)
	var slider: HSlider = HSlider.new()
	slider.value = 50
	slider.custom_minimum_size = Vector2(160, 32)
	controls.add_child(slider)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 8
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/blender/ui/qq_small_icons.manifest.json")) as Dictionary
	for raw_asset: Variant in manifest.get("assets", []):
		var asset: Dictionary = raw_asset as Dictionary
		var panel: PanelContainer = PanelContainer.new()
		panel.custom_minimum_size = Vector2(164, 126)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(panel)
		var box: VBoxContainer = VBoxContainer.new()
		panel.add_child(box)
		var image: TextureRect = TextureRect.new()
		image.texture = ResourceLoader.load("res://" + String(asset.get("runtime_path", ""))) as Texture2D
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(80, 80)
		box.add_child(image)
		var footer: HBoxContainer = HBoxContainer.new()
		box.add_child(footer)
		var small: TextureRect = TextureRect.new()
		small.texture = image.texture
		small.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		small.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		small.custom_minimum_size = Vector2(24, 24)
		footer.add_child(small)
		var label: Label = Label.new()
		label.text = String(asset.get("visual_id", ""))
		label.add_theme_font_size_override("font_size", 12)
		footer.add_child(label)
	if OS.get_cmdline_user_args().has("--capture-ui-icons"):
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png("res://tools/.local/ui_icon_batch_runtime.png")
		print("UI_ICON_BATCH_REVIEW_CAPTURE_OK")
		get_tree().quit()
