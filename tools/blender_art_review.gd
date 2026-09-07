extends Control

const CARDS: Array[String] = ["quick_slash", "guard", "delay_step", "repair_burst", "auto_turret", "event_horizon"]
const RELICS: Array[String] = ["iron_plating", "auxiliary_core", "chrono_shard", "salvage_magnet"]


func _ready() -> void:
	get_window().size = Vector2i(1440, 940)
	get_window().content_scale_size = Vector2i(1440, 940)
	Database.load_all()
	call_deferred("_build")


func _label(value: String, at: Vector2, font_size: int = 18) -> void:
	var label: Label = Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)


func _image(texture: Texture2D, at: Vector2, extent: float) -> void:
	var art: TextureRect = TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture = texture
	art.position = at
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size = Vector2.ONE * extent
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)


func _build() -> void:
	_label("QQ / ART REVISION 02", Vector2(36, 22), 28)
	_label("Card illustration + real 168px card UI   |   Relic alpha + real 48px icon UI", Vector2(36, 62))
	for index: int in CARDS.size():
		var card_id: String = CARDS[index]
		var origin: Vector2 = Vector2(36 + index % 3 * 468, 108 + index / 3 * 278)
		_label(card_id, origin)
		_image(load("res://assets/icons/cards/%s.png" % card_id), origin + Vector2(0, 30), 224)
		var state: CardRuntimeState = CardRuntimeState.new()
		state.card_id = card_id
		state.runtime_id = "art_review_%s" % card_id
		var card: CardButton = CardButton.new()
		card.set_tile_size(Vector2(168, 168))
		card.size = Vector2(168, 168)
		card.position = origin + Vector2(246, 34)
		add_child(card)
		card.bind(Database.get_card(card_id), state, true)
		_label("168 px / hover for details", origin + Vector2(236, 220), 15)
	_label("RELICS / no display stand, transparent background", Vector2(36, 681), 22)
	for index: int in RELICS.size():
		var relic_id: String = RELICS[index]
		var origin: Vector2 = Vector2(36 + index * 350, 729)
		_label(relic_id, origin, 16)
		for y: int in 8:
			for x: int in 8:
				var tile: ColorRect = ColorRect.new()
				tile.position = origin + Vector2(x * 16, 26 + y * 16)
				tile.size = Vector2(16, 16)
				tile.color = Color("ced7d7") if (x + y) % 2 == 0 else Color("8f9eab")
				add_child(tile)
		_image(load("res://assets/icons/relics/%s.png" % relic_id), origin + Vector2(0, 26), 128)
		var relic: RelicIcon = RelicIcon.new()
		relic.set_icon_size(Vector2(48, 48))
		relic.position = origin + Vector2(160, 50)
		add_child(relic)
		relic.bind_relic_id(relic_id)
		_label("48 px", origin + Vector2(160, 112), 16)
	await get_tree().process_frame
	await get_tree().process_frame
	var capture_path: String = OS.get_environment("QQ_ART_REVIEW_CAPTURE")
	if not capture_path.is_empty():
		RenderingServer.force_draw(false, 0.0)
		var capture: Image = get_viewport().get_texture().get_image()
		if capture == null or capture.save_png(capture_path) != OK:
			push_error("Could not capture the art review screen")
			get_tree().quit(1)
			return
		print("ART_REVIEW_CAPTURE_OK %s" % capture_path)
		get_tree().quit()
