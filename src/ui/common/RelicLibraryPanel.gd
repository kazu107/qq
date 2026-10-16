extends VBoxContainer
class_name RelicLibraryPanel

signal content_changed()

const PAGE_SIZE: int = 12
const BATCH_SIZE: int = 4
const RARITIES: Array[String] = ["common", "rare", "epic", "legendary"]

var cell_style_factory: Callable = Callable()
var _scroll: ScrollContainer
var _grid: GridContainer
var _rarity_filter: OptionButton
var _tag_filter: OptionButton
var _search_edit: LineEdit
var _search_timer: Timer
var _matching_label: Label
var _empty_label: Label
var _entries: Array[Dictionary] = []
var _filtered_entries: Array[Dictionary] = []
var _widgets: Dictionary = {}
var _rarity: String = "all"
var _tag: String = "all"
var _search: String = ""
var _active: bool = false
var _initialized: bool = false
var _ready_for_input: bool = false
var _building: bool = false
var _dirty: bool = false
var _awaiting_more: bool = false
var _next_index: int = 0
var _generation: int = 0


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var toolbar: VBoxContainer = UiTheme.add_section(self, "", "LibraryRelicToolbar")
	var filters: HBoxContainer = HBoxContainer.new()
	filters.add_theme_constant_override("separation", 10)
	toolbar.add_child(filters)
	filters.add_child(UiIconHelper.icon_node("filter"))
	var rarity_label: Label = Label.new()
	rarity_label.text = Localization.get_text("library.filter.rarity", "Rarity")
	filters.add_child(rarity_label)
	_rarity_filter = OptionButton.new()
	_rarity_filter.name = "LibraryRelicRarityFilter"
	_rarity_filter.custom_minimum_size.x = 150.0
	_rarity_filter.add_item(Localization.get_text("library.filter.all", "All"))
	_rarity_filter.set_item_metadata(0, "all")
	for rarity: String in RARITIES:
		_rarity_filter.add_item(Localization.get_rarity_name(rarity))
		_rarity_filter.set_item_metadata(_rarity_filter.item_count - 1, rarity)
	_rarity_filter.item_selected.connect(_on_rarity_selected)
	filters.add_child(_rarity_filter)
	var type_label: Label = Label.new()
	type_label.text = Localization.get_text("library.filter.type", "Type")
	filters.add_child(type_label)
	_tag_filter = OptionButton.new()
	_tag_filter.name = "LibraryRelicTypeFilter"
	_tag_filter.custom_minimum_size.x = 180.0
	_tag_filter.add_item(Localization.get_text("library.filter.all", "All"))
	_tag_filter.set_item_metadata(0, "all")
	_tag_filter.item_selected.connect(_on_tag_selected)
	filters.add_child(_tag_filter)
	filters.add_child(UiIconHelper.icon_node("search"))
	_search_edit = LineEdit.new()
	_search_edit.name = "LibraryRelicSearch"
	_search_edit.placeholder_text = Localization.get_text("library.relic.search", "Search relic names and effects")
	_search_edit.custom_minimum_size.x = 320.0
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_search_changed)
	filters.add_child(_search_edit)
	_matching_label = Label.new()
	_matching_label.name = "LibraryRelicMatchingCount"
	filters.add_child(_matching_label)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.18
	_search_timer.timeout.connect(_queue_rebuild)
	add_child(_search_timer)
	_empty_label = Label.new()
	_empty_label.name = "LibraryRelicEmptyNotice"
	_empty_label.text = Localization.get_text("library.relic.empty", "No relics match. Try another name or filter.")
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	add_child(_empty_label)
	_scroll = ScrollContainer.new()
	_scroll.name = "LibraryRelicsScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: _request_more.call_deferred())
	add_child(_scroll)
	_grid = GridContainer.new()
	_grid.name = "LibraryRelics"
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_scroll.add_child(_grid)


func activate(entries: Array[Dictionary]) -> void:
	_active = true
	_entries = entries
	if not _initialized:
		var tags: Array[String] = []
		for entry: Dictionary in entries:
			for tag: String in Database.get_relic(String(entry["id"])).tags:
				if not tags.has(tag): tags.append(tag)
		tags.sort()
		for tag: String in tags:
			_tag_filter.add_item(Localization.get_text("tag." + tag, tag.capitalize()))
			_tag_filter.set_item_metadata(_tag_filter.item_count - 1, tag)
		_initialized = true
		_dirty = true
	_update_rows()
	if _dirty:
		_queue_rebuild()
	else:
		_request_more.call_deferred()


func deactivate() -> void:
	_active = false


func is_content_ready() -> bool:
	return _ready_for_input


func _matches(relic: RelicDef) -> bool:
	return (_rarity == "all" or relic.rarity == _rarity) and (_tag == "all" or relic.tags.has(_tag)) and (
		_search == "" or ("%s %s %s" % [relic.name, relic.description, Localization.get_tags_text(relic.tags)]).to_lower().contains(_search))


func _queue_rebuild() -> void:
	_search_timer.stop()
	_dirty = true
	if not _active:
		return
	_dirty = false
	_generation += 1
	_next_index = 0
	_filtered_entries.clear()
	for rarity: String in RARITIES:
		for entry: Dictionary in _entries:
			var relic: RelicDef = Database.get_relic(String(entry["id"]))
			if relic.rarity == rarity and _matches(relic): _filtered_entries.append(entry)
	_matching_label.text = Localization.get_textf("library.relic.matching", "{count} relics", {"count": _filtered_entries.size()})
	_empty_label.visible = _filtered_entries.is_empty()
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_widgets.clear()
	_scroll.scroll_vertical = 0
	_ready_for_input = false
	_building = true
	_awaiting_more = false
	# Capture the generation before deferring, so rapid filter changes cannot start stale pages.
	_build_page.call_deferred(_generation)


func _build_page(generation: int) -> void:
	if generation != _generation: return
	var count: int = 0
	while _next_index < _filtered_entries.size() and count < PAGE_SIZE:
		var entry: Dictionary = _filtered_entries[_next_index]
		_build_row(entry)
		_next_index += 1
		count += 1
		if count % BATCH_SIZE == 0:
			await get_tree().process_frame
			if generation != _generation or not is_inside_tree(): return
	_building = false
	_ready_for_input = true
	_awaiting_more = _next_index < _filtered_entries.size()
	_update_rows()
	_request_more.call_deferred()


func _build_row(entry: Dictionary) -> void:
	var id: String = String(entry["id"])
	var relic: RelicDef = Database.get_relic(id)
	var row: PanelContainer = PanelContainer.new()
	row.name = "LibraryRelicRow_" + id
	row.custom_minimum_size.x = 360.0
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if cell_style_factory.is_valid(): row.add_theme_stylebox_override("panel", cell_style_factory.call(relic.rarity))
	_grid.add_child(row)
	var cell: VBoxContainer = VBoxContainer.new()
	cell.add_theme_constant_override("separation", 8)
	row.add_child(cell)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	cell.add_child(top)
	var icon: RelicIcon = RelicIcon.new()
	icon.set_icon_size(Vector2(112.0, 112.0))
	icon.bind(relic, not bool(entry["unlocked"]))
	icon.name = "LibraryRelic_" + id
	top.add_child(icon)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var title: Label = Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = relic.name
	title.add_theme_font_size_override("font_size", 20)
	info.add_child(title)
	var meta: Label = Label.new()
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.theme_type_variation = "MutedLabel"
	meta.text = "%s / %s" % [Localization.get_rarity_name(relic.rarity), Localization.get_tags_text(relic.tags)]
	info.add_child(meta)
	var status: Label = Label.new()
	status.name = "LibraryRelicStatus_" + id
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 15)
	info.add_child(status)
	var seal: CheckButton = CheckButton.new()
	seal.name = "SealRelic_" + id
	seal.text = Localization.get_text("progress.seal", "Seal")
	seal.tooltip_text = Localization.get_text("progress.seal_hint", "Seals affect random acquisitions in new normal/infinite runs only.")
	seal.toggled.connect(_on_seal_toggled.bind(id))
	cell.add_child(seal)
	var description: Label = Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.theme_type_variation = "MutedLabel"
	description.text = relic.description
	cell.add_child(description)
	_widgets[id] = {"row": row, "icon": icon, "status": status, "button": seal, "unlocked": bool(entry["unlocked"])}


func _update_rows() -> void:
	for entry: Dictionary in _entries:
		var id: String = String(entry["id"])
		if not _widgets.has(id): continue
		var widgets: Dictionary = _widgets[id]
		var unlocked: bool = bool(entry["unlocked"])
		var icon: RelicIcon = widgets["icon"]
		if bool(widgets["unlocked"]) != unlocked:
			icon.bind_relic_id(id, not unlocked)
			icon.name = "LibraryRelic_" + id
			widgets["unlocked"] = unlocked
		icon.refresh_tooltip()
		var status: Label = widgets["status"]
		status.text = Game.get_content_entry_status(entry)
		status.add_theme_color_override("font_color", Color(0.42, 0.82, 0.65) if unlocked else UiTheme.ACCENT_GOLD)
		var button: CheckButton = widgets["button"]
		button.visible = unlocked
		button.disabled = not bool(entry["can_seal"])
		button.set_pressed_no_signal(bool(entry["sealed"]))


func _request_more() -> void:
	if not _active or not is_visible_in_tree() or _building or not _awaiting_more: return
	await get_tree().process_frame
	if not _active or not is_visible_in_tree() or _building or not _awaiting_more: return
	var bar: ScrollBar = _scroll.get_v_scroll_bar()
	if bar.value + bar.page >= bar.max_value - 180.0:
		_awaiting_more = false
		_building = true
		_build_page.call_deferred(_generation)


func _on_rarity_selected(index: int) -> void:
	_rarity = String(_rarity_filter.get_item_metadata(index))
	_queue_rebuild()


func _on_tag_selected(index: int) -> void:
	_tag = String(_tag_filter.get_item_metadata(index))
	_queue_rebuild()


func _on_search_changed(text: String) -> void:
	_search = text.strip_edges().to_lower()
	_search_timer.start()


func _on_seal_toggled(sealed: bool, id: String) -> void:
	Game.set_content_sealed("relics", id, sealed)
	content_changed.emit()
