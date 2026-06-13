extends VBoxContainer
class_name TimelinePanel

const TIMELINE_TILE_SIZE: Vector2 = Vector2(168.0, 168.0)
const TIMELINE_PANEL_MIN_HEIGHT: float = 264.0
const TIMELINE_SCROLL_MIN_HEIGHT: float = 188.0
const TIMELINE_SCALE_MARK_COUNT: int = 5
const DEFAULT_TIMELINE_HORIZON: float = 3.0
const FALLBACK_TRACK_WIDTH: float = 960.0
const PREVIEW_ALPHA: float = 0.68
const PREVIEW_BLEACH_AMOUNT: float = 0.36
const PREVIEW_Z_INDEX: int = 1000

var _title_label: Label
var _summary_label: Label
var _scale_row: HBoxContainer
var _cards_scroll: Control
var _cards_track: Control
var _empty_label: Label
var _cards: Array[CardButton] = []
var _card_layouts: Array[Dictionary] = []
var _preview_button: CardButton
var _preview_remaining: float = 0.0
var _timeline_horizon: float = DEFAULT_TIMELINE_HORIZON
var _fixed_horizon: float = DEFAULT_TIMELINE_HORIZON


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

	_cards_scroll = Control.new()
	_cards_scroll.name = "TimelineScroll"
	_cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_scroll.custom_minimum_size = Vector2(0.0, TIMELINE_SCROLL_MIN_HEIGHT)
	_cards_scroll.clip_contents = true
	_cards_scroll.resized.connect(_layout_cards)
	add_child(_cards_scroll)

	_cards_track = Control.new()
	_cards_track.name = "TimelineCards"
	_cards_track.anchor_right = 1.0
	_cards_track.anchor_bottom = 1.0
	_cards_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_scroll.add_child(_cards_track)

	_empty_label = Label.new()
	_empty_label.text = Localization.get_text("timeline.empty", "No scheduled actions")
	add_child(_empty_label)
	_timeline_horizon = _fixed_horizon
	_refresh_scale(_timeline_horizon)


func set_fixed_horizon(horizon: float) -> void:
	_fixed_horizon = maxf(0.1, horizon)
	_timeline_horizon = _fixed_horizon
	if _scale_row != null:
		_refresh_scale(_timeline_horizon)
	if _cards_scroll != null:
		_layout_cards()


func refresh_timeline(
	entries: Array[TimelineEntry],
	battle_time: float,
	run_state: RunState = null,
	preview_entry: TimelineEntry = null,
	preview_card_def: CardDef = null
) -> void:
	var sorted_entries: Array[TimelineEntry] = entries.duplicate()
	sorted_entries.sort_custom(_compare_entries)
	_summary_label.text = Localization.get_textf("timeline.queued", "Queued {count}", {
		"count": sorted_entries.size(),
	})
	var has_preview: bool = preview_entry != null and preview_card_def != null
	_empty_label.visible = sorted_entries.is_empty() and not has_preview
	_timeline_horizon = _fixed_horizon
	_refresh_scale(_timeline_horizon)
	_ensure_card_count(sorted_entries.size())
	_card_layouts.clear()

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
		_card_layouts.append({
			"button": button,
			"remaining": maxf(0.0, entry.scheduled_time - battle_time),
		})
	_refresh_preview(preview_entry, preview_card_def, battle_time)
	_layout_cards()


func _refresh_scale(horizon: float) -> void:
	for child in _scale_row.get_children():
		_scale_row.remove_child(child)
		child.queue_free()

	var resolved_horizon: float = maxf(0.1, horizon)

	for scale_index in range(TIMELINE_SCALE_MARK_COUNT):
		var label: Label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if scale_index == 0:
			label.text = Localization.get_text("timeline.now", "NOW")
		else:
			var seconds: float = resolved_horizon * float(scale_index) / float(TIMELINE_SCALE_MARK_COUNT - 1)
			label.text = "+%s" % _format_scale_seconds(seconds)
		_scale_row.add_child(label)


func _ensure_card_count(count: int) -> void:
	while _cards.size() < count:
		var button: CardButton = CardButton.new()
		button.set_tile_size(TIMELINE_TILE_SIZE)
		button.size = TIMELINE_TILE_SIZE
		_cards_track.add_child(button)
		if _preview_button != null:
			_cards_track.move_child(button, _cards.size())
		_cards.append(button)


func _ensure_preview_button() -> void:
	if _preview_button != null:
		return
	_preview_button = CardButton.new()
	_preview_button.name = "TimelinePreviewCard"
	_preview_button.set_tile_size(TIMELINE_TILE_SIZE)
	_preview_button.size = TIMELINE_TILE_SIZE
	_preview_button.visible = false
	_preview_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_button.z_index = PREVIEW_Z_INDEX
	_cards_track.add_child(_preview_button)


func _refresh_preview(preview_entry: TimelineEntry, preview_card_def: CardDef, battle_time: float) -> void:
	if preview_entry == null or preview_card_def == null:
		if _preview_button != null:
			_preview_button.visible = false
		_preview_remaining = 0.0
		return

	_ensure_preview_button()
	_preview_button.visible = true
	_preview_button.bind_timeline(preview_card_def, preview_entry, battle_time, false)
	_preview_button.modulate = Color(1.0, 1.0, 1.0, PREVIEW_ALPHA)
	_preview_button.set_bleach_enabled(true, PREVIEW_BLEACH_AMOUNT)
	_preview_button.z_index = PREVIEW_Z_INDEX
	_preview_remaining = maxf(0.0, preview_entry.scheduled_time - battle_time)


func _layout_cards() -> void:
	var track_width: float = _cards_scroll.size.x
	if track_width <= TIMELINE_TILE_SIZE.x:
		track_width = FALLBACK_TRACK_WIDTH
	var usable_width: float = maxf(1.0, track_width - TIMELINE_TILE_SIZE.x)
	var horizon: float = maxf(0.1, _timeline_horizon)
	var y_position: float = maxf(0.0, (_cards_scroll.custom_minimum_size.y - TIMELINE_TILE_SIZE.y) * 0.5)

	for layout_index in range(_card_layouts.size()):
		var layout_data: Dictionary = _card_layouts[layout_index]
		var button: CardButton = layout_data.get("button") as CardButton
		if button == null:
			continue
		var remaining: float = clampf(float(layout_data.get("remaining", 0.0)), 0.0, horizon)
		_position_timeline_card(button, remaining, usable_width, y_position, horizon, _card_layouts.size() - layout_index)

	if _preview_button != null and _preview_button.visible:
		_position_timeline_card(_preview_button, _preview_remaining, usable_width, y_position, horizon, PREVIEW_Z_INDEX)


func _position_timeline_card(
	button: CardButton,
	remaining: float,
	usable_width: float,
	y_position: float,
	horizon: float,
	z_index: int
) -> void:
	var clamped_remaining: float = clampf(remaining, 0.0, horizon)
	var ratio: float = clamped_remaining / horizon
	button.position = Vector2(usable_width * ratio, y_position)
	button.size = TIMELINE_TILE_SIZE
	button.z_index = z_index


func _format_scale_seconds(seconds: float) -> String:
	if is_equal_approx(seconds, roundf(seconds)):
		return "%ds" % int(roundf(seconds))
	return "%.1fs" % seconds


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
