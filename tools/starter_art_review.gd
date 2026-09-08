extends Control

const IDS: Array[String] = ["balanced", "tempo", "fortress", "vanguard", "aegis", "chrono", "turret"]


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	get_window().content_scale_size = Vector2i(1600, 1000)
	Localization.set_language("ja", false)
	Database.load_all()
	call_deferred("_build")


func _build() -> void:
	var title := Label.new()
	title.text = "STARTER COLLECTION / 02"
	title.position = Vector2(24, 14)
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)
	for index: int in IDS.size():
		var starter_id: String = IDS[index]
		var origin := Vector2(24 + (index % 4) * 394, 66 + (index / 4) * 460)
		var model := StarterModelPreview.new()
		model.position = origin
		model.size = Vector2(368, 350)
		model.custom_minimum_size = model.size
		add_child(model)
		model.show_starter(starter_id)
		var portrait := TextureRect.new()
		portrait.texture = load("res://assets/portraits/%s.png" % starter_id) as Texture2D
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.position = origin + Vector2(0, 357)
		portrait.size = Vector2(84, 84)
		add_child(portrait)
		var label := Label.new()
		label.text = "%s\n%s" % [String(Database.get_starter(starter_id).get("name", starter_id)), starter_id]
		label.position = origin + Vector2(98, 366)
		label.add_theme_font_size_override("font_size", 18)
		add_child(label)
	await get_tree().create_timer(0.75).timeout
	var capture_path: String = OS.get_environment("QQ_STARTER_REVIEW_CAPTURE")
	if not capture_path.is_empty():
		RenderingServer.force_draw(false, 0.0)
		var capture: Image = get_viewport().get_texture().get_image()
		if capture == null or capture.save_png(capture_path) != OK:
			push_error("Could not capture starter art review")
			get_tree().quit(1)
			return
		print("STARTER_ART_REVIEW_OK ", capture_path)
		get_tree().quit()
