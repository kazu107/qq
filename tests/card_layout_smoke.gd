extends Control


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	for width: float in [74.0, 78.0, 82.0, 86.0, 88.0, 92.0, 104.0, 112.0, 128.0, 168.0, 180.0]:
		for card_id: String in ["quick_slash", "repair_burst", "deus_ex_machina"]:
			var card: CardButton = CardButton.new()
			card.set_tile_size(Vector2.ONE * width)
			add_child(card)
			var card_def: CardDef = Database.get_card(card_id)
			card.bind_preview(card_def, "layout")
			await get_tree().process_frame
			if not _valid_layout(card, width):
				_fail("preview layout at %spx: %s" % [width, card_id])
				return
			var original_size: Vector2 = card.size
			var state: CardRuntimeState = CardRuntimeState.new()
			state.runtime_id = "layout"
			state.card_id = card_id
			for mode: int in 3:
				if mode == 1:
					state.begin_cooldown(card_def.recast_time * 0.5)
				elif mode == 2:
					state.begin_prepare()
				card.bind(card_def, state, mode == 0)
				await get_tree().process_frame
				if card.size != original_size or not _valid_layout(card, width):
					_fail("live state changed bounds or misplaced information: %s/%s/%s" % [width, card_id, mode])
					return
				var shade: ColorRect = card.get_node("CooldownShade") as ColorRect
				if shade.visible and not card.get_art_rect().encloses(shade.get_rect()):
					_fail("cooldown shade escaped artwork")
					return
			if width >= 168.0:
				var entry: TimelineEntry = TimelineEntry.new()
				entry.card_id = card_id
				entry.runtime_id = "layout"
				entry.scheduled_time = 4.0
				for is_next: bool in [true, false]:
					card.bind_timeline(card_def, entry, 1.0, is_next)
					await get_tree().process_frame
					if card.size != original_size or not _valid_layout(card, width):
						_fail("timeline badges overlap: %s/%s/%s" % [width, card_id, is_next])
						return
			card.free()
	print("CARD_LAYOUT_SMOKE_OK square art, external effects/names, overlay cost/timing, stable states, masks, 11 sizes")
	get_tree().quit()


func _valid_layout(card: CardButton, width: float) -> bool:
	var art: Rect2 = card.get_art_rect()
	var bounds: Rect2 = Rect2(Vector2.ZERO, card.size)
	if art.size != Vector2.ONE * width or not bounds.encloses(art):
		return false
	if card.has_node("NameBar/CardTypeIcon"):
		return false
	var name_bar: Control = card.get_node("NameBar") as Control
	if name_bar.position.y < art.end.y or not bounds.encloses(name_bar.get_rect()):
		return false
	for path: String in ["EffectStrip/EffectChip1", "EffectStrip/EffectChip2", "EffectStrip/EffectRemainder"]:
		var control: Control = card.get_node(path) as Control
		if not control.is_visible_in_tree():
			continue
		var rect: Rect2 = Rect2(control.global_position - card.global_position, control.size)
		if rect.end.y > art.position.y or not bounds.encloses(rect):
			return false
	var overlays: Array[Rect2] = []
	for path: String in ["CostBadge", "MetaBadge", "TimingBadge", "TimelineNextBadge"]:
		var control: Control = card.get_node(path) as Control
		if not control.is_visible_in_tree():
			continue
		var rect: Rect2 = control.get_rect()
		if not bounds.encloses(rect) or not art.intersects(rect):
			return false
		if path != "CostBadge" and not art.encloses(rect):
			return false
		for other: Rect2 in overlays:
			if rect.intersects(other):
				return false
		overlays.append(rect)
	return true


func _fail(reason: String) -> void:
	push_error("Card layout smoke failed: %s" % reason)
	get_tree().quit(1)
