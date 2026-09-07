extends Control

const IDS: Array[String] = ["quick_slash", "guard", "delay_step", "repair_burst", "auto_turret", "event_horizon"]


func _ready() -> void:
	get_window().size = Vector2i(1440, 1000)
	get_window().content_scale_size = Vector2i(1440, 1000)
	Localization.set_language("ja", false)
	Database.load_all()
	call_deferred("_build")


func _label(value: String, at: Vector2, font_size: int = 18) -> void:
	var label: Label = Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)


func _card(id: String, art_width: float, at: Vector2, mode: int = 0) -> CardButton:
	var card: CardButton = CardButton.new()
	card.set_tile_size(Vector2.ONE * art_width)
	card.position = at
	add_child(card)
	var card_def: CardDef = Database.get_card(id)
	if mode == 0:
		card.bind_preview(card_def, "preview_" + id)
	else:
		var state: CardRuntimeState = CardRuntimeState.new()
		state.card_id = id
		state.runtime_id = "preview_" + id
		if mode == 2:
			state.begin_cooldown(card_def.recast_time * 0.6)
		elif mode == 3:
			state.begin_prepare()
		card.bind(card_def, state, mode == 1)
	return card


func _build() -> void:
	_label("CARD LAYOUT / 02", Vector2(40, 24), 30)
	_label("上：コスト・秒数・効果    下：カード名", Vector2(40, 70), 22)
	for index: int in IDS.size():
		_card(IDS[index], 180, Vector2(42 + index * 233, 118))
	_label("使用可能 / 再使用 / casting", Vector2(40, 408), 20)
	_card("quick_slash", 112, Vector2(42, 450), 1)
	_card("guard", 112, Vector2(196, 450), 2)
	_card("repair_burst", 112, Vector2(350, 450), 3)
	_label("小型カード / 74・88px", Vector2(584, 408), 20)
	_card("repair_burst", 74, Vector2(586, 450))
	_card("auto_turret", 88, Vector2(702, 450), 1)
	_card("event_horizon", 88, Vector2(832, 450), 2)
	_label("補正込みの効果", Vector2(1038, 408), 20)
	var boosted: CardDef = CardDef.from_dict(Database.get_card("quick_slash").to_dict())
	boosted.effects[0].amount = 7.0
	var buff_card: CardButton = _card("quick_slash", 112, Vector2(1040, 450))
	buff_card.bind_preview(boosted, "boosted", false, "", Database.get_card("quick_slash"))
	var weakened: CardDef = CardDef.from_dict(Database.get_card("guard").to_dict())
	weakened.effects[0].amount = 5.0
	var nerf_card: CardButton = _card("guard", 112, Vector2(1194, 450))
	nerf_card.bind_preview(weakened, "weakened", false, "", Database.get_card("guard"))

	var timeline: TimelinePanel = TimelinePanel.new()
	timeline.position = Vector2(40, 666)
	timeline.size = Vector2(1360, 322)
	timeline.set_fixed_horizon(8.0)
	add_child(timeline)
	var entries: Array[TimelineEntry] = []
	for index: int in 3:
		var entry: TimelineEntry = TimelineEntry.new()
		entry.instance_id = index + 1
		entry.runtime_id = "timeline_preview_%d" % index
		entry.card_id = IDS[index]
		entry.owner_side = "player" if index % 2 == 0 else "enemy"
		entry.scheduled_time = 1.0 + index * 2.5
		entries.append(entry)
	timeline.refresh_timeline(entries, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var capture_path: String = OS.get_environment("QQ_CARD_LAYOUT_CAPTURE")
	if not capture_path.is_empty():
		RenderingServer.force_draw(false, 0.0)
		var capture: Image = get_viewport().get_texture().get_image()
		if capture == null or capture.save_png(capture_path) != OK:
			push_error("Could not capture card layout preview")
			get_tree().quit(1)
			return
		print("CARD_LAYOUT_PREVIEW_OK %s" % capture_path)
		get_tree().quit()
