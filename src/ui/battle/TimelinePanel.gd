extends VBoxContainer
class_name TimelinePanel

const TIMELINE_TILE_SIZE: Vector2 = Vector2(168.0, 168.0)
const TIMELINE_PANEL_MIN_HEIGHT: float = 264.0
const TIMELINE_SCROLL_MIN_HEIGHT: float = 188.0
const TIMELINE_CARD_SEPARATION: int = 12
const TIMELINE_SCALE_MARK_COUNT: int = 4

var _title_label: Label
var _summary_label: Label
var _scale_row: HBoxContainer
var _cards_scroll: ScrollContainer
var _cards_row: HBoxContainer
var _empty_label: Label
var _cards: Array[CardButton] = []


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, TIMELINE_PANEL_MIN_HEIGHT)

	_title_label = Label.new()
	_title_label.text = Localization.get_text("battle.timeline", "Timeline")
	add_child(_title_label)

	_summary_label = Label.new()
	_summary_label.text = Localization.get_text("timeline.summary", "Soonest cast resolves first")
	add_child(_summary_label)

	_scale_row = HBoxContainer.new()
	_scale_row.name = "TimelineScale"
	_scale_row.add_theme_constant_override("separation", 8)
	add_child(_scale_row)

	_cards_scroll = ScrollContainer.new()
	_cards_scroll.name = "TimelineScroll"
	_cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_scroll.custom_minimum_size = Vector2(0.0, TIMELINE_SCROLL_MIN_HEIGHT)
	_cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_cards_scroll)

	_cards_row = HBoxContainer.new()
	_cards_row.name = "TimelineCards"
	_cards_row.add_theme_constant_override("separation", TIMELINE_CARD_SEPARATION)
	_cards_scroll.add_child(_cards_row)

	_empty_label = Label.new()
	_empty_label.text = Localization.get_text("timeline.empty", "No scheduled actions")
	add_child(_empty_label)


func refresh_timeline(entries: Array[TimelineEntry], battle_time: float, run_state: RunState = null) -> void:
	var sorted_entries: Array[TimelineEntry] = entries.duplicate()
	sorted_entries.sort_custom(_compare_entries)
	_summary_label.text = Localization.get_textf("timeline.queued", "Queued {count}", {
		"count": sorted_entries.size(),
	})
	_empty_label.visible = sorted_entries.is_empty()
	_refresh_scale(sorted_entries, battle_time)
	_ensure_card_count(sorted_entries.size())

	for index in range(_cards.size()):
		var button: CardButton = _cards[index]
		if index >= sorted_entries.size():
			button.visible = false
			continue

		var entry: TimelineEntry = sorted_entries[index]
		var card_def: CardDef = _resolve_card_def(entry, run_state)
		if card_def == null:
			button.visible = false
			continue

		button.visible = true
		button.bind_timeline(card_def, entry, battle_time, index == 0)


func _refresh_scale(sorted_entries: Array[TimelineEntry], battle_time: float) -> void:
	for child in _scale_row.get_children():
		_scale_row.remove_child(child)
		child.queue_free()

	_scale_row.visible = not sorted_entries.is_empty()
	if sorted_entries.is_empty():
		return

	var max_remaining: float = 0.0
	for entry in sorted_entries:
		max_remaining = maxf(max_remaining, maxf(0.0, entry.scheduled_time - battle_time))
	var horizon: int = maxi(3, int(ceil(max_remaining)))
	var step: int = maxi(1, int(ceil(float(horizon) / float(TIMELINE_SCALE_MARK_COUNT - 1))))

	for scale_index in range(TIMELINE_SCALE_MARK_COUNT):
		var label: Label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if scale_index == 0:
			label.text = Localization.get_text("timeline.now", "NOW")
		else:
			label.text = "+%ds" % (step * scale_index)
		_scale_row.add_child(label)


func _ensure_card_count(count: int) -> void:
	while _cards.size() < count:
		var button: CardButton = CardButton.new()
		button.set_tile_size(TIMELINE_TILE_SIZE)
		_cards_row.add_child(button)
		_cards.append(button)


func _compare_entries(a: TimelineEntry, b: TimelineEntry) -> bool:
	if not is_equal_approx(a.scheduled_time, b.scheduled_time):
		return a.scheduled_time < b.scheduled_time
	if a.actor_speed != b.actor_speed:
		return a.actor_speed > b.actor_speed
	return a.instance_id < b.instance_id


func _resolve_card_def(entry: TimelineEntry, run_state: RunState) -> CardDef:
	if entry.owner_side == "player" and run_state != null:
		return CardUpgradeResolver.build_effective_card(entry.card_id, run_state)
	return Database.get_card(entry.card_id)
