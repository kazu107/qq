extends Control

const PAGE_SIZE: int = 24
const CATEGORIES: Dictionary = {
	"all": ["すべて", "All"], "card": ["カード", "Cards"],
	"relic": ["遺物", "Relics"], "model": ["3Dモデル", "3D models"],
	"portrait": ["キャラクター画像", "Portraits"], "status": ["状態", "Status"],
	"ui": ["UI", "UI"], "effect": ["効果", "Effects"], "map": ["マップ", "Map"],
	"control": ["操作部品", "Controls"], "background": ["背景", "Backgrounds"],
	"branding": ["ロゴ", "Branding"], "environment": ["フィールド", "Field"],
}

var _catalog: Array[Dictionary] = []
var _filtered: Array[Dictionary] = []
var _grid: GridContainer
var _category: OptionButton
var _search: LineEdit
var _summary: Label
var _page_label: Label
var _previous: Button
var _next: Button
var _page: int = 0
var _generation: int = 0
var _overlay: ColorRect
var _previous_focus: Control


func _ready() -> void:
	if not Game.is_developer_mode_enabled():
		SceneRouter.call_deferred("go_to_hub")
		return
	_catalog = ArtCatalog.get_entries()
	_build_ui()
	_apply_filter()
	resized.connect(_update_columns)
	_update_columns()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _overlay != null:
			_close_preview()
		else:
			SceneRouter.return_from_debug_lab()
		get_viewport().set_input_as_handled()


func _localized(ja: String, en: String) -> String:
	return ja if Localization.get_language() == "ja" else en


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	var header: HBoxContainer = HBoxContainer.new()
	root.add_child(header)
	var title: Label = Label.new()
	title.text = _localized("アート確認ラボ", "Art Review Lab")
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back: Button = Button.new()
	back.name = "ArtLabBack"
	back.text = _localized("戻る", "Back")
	back.pressed.connect(SceneRouter.return_from_debug_lab)
	header.add_child(back)
	var filters: HBoxContainer = HBoxContainer.new()
	filters.add_theme_constant_override("separation", 14)
	root.add_child(filters)
	_category = OptionButton.new()
	_category.name = "ArtLabCategory"
	_category.custom_minimum_size.x = 180.0
	for category: String in CATEGORIES:
		var labels: Array = CATEGORIES[category]
		_category.add_item(_localized(String(labels[0]), String(labels[1])))
		_category.set_item_metadata(_category.item_count - 1, category)
	_category.item_selected.connect(func(_index: int) -> void: _apply_filter())
	filters.add_child(_category)
	_search = LineEdit.new()
	_search.name = "ArtLabSearch"
	_search.placeholder_text = _localized("名前・IDを検索", "Search name / ID")
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String) -> void: _apply_filter())
	filters.add_child(_search)
	_summary = Label.new()
	_summary.name = "ArtLabSummary"
	root.add_child(_summary)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ArtLabScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "ArtLabGrid"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)
	var pages: HBoxContainer = HBoxContainer.new()
	pages.alignment = BoxContainer.ALIGNMENT_CENTER
	pages.add_theme_constant_override("separation", 16)
	root.add_child(pages)
	_previous = Button.new()
	_previous.text = _localized("前へ", "Previous")
	_previous.pressed.connect(func() -> void: _page -= 1; _build_page())
	pages.add_child(_previous)
	_page_label = Label.new()
	pages.add_child(_page_label)
	_next = Button.new()
	_next.text = _localized("次へ", "Next")
	_next.pressed.connect(func() -> void: _page += 1; _build_page())
	pages.add_child(_next)


func _update_columns() -> void:
	if _grid != null:
		_grid.columns = maxi(1, mini(6, int((size.x - 60.0) / 220.0)))


func _asset_name(entry: Dictionary) -> String:
	var id: String = String(entry.get("asset_id", ""))
	var visual_id: String = String(entry.get("visual_id", id))
	match String(entry.get("category", "")):
		"card":
			var card: CardDef = _card_definition(id)
			return card.name if card != null else id
		"relic":
			var relic: RelicDef = Database.get_relic(id)
			return relic.name if relic != null else id
		"portrait":
			visual_id = id.trim_prefix("portrait_")
	return Localization.get_text("enemy.%s.name" % visual_id, Localization.get_text("starter.%s.name" % visual_id, id))


func _card_definition(id: String) -> CardDef:
	return FatigueRules.get_card(FatigueRules.DAMAGE_STEP) if id == FatigueRules.CARD_ID else Database.get_card(id)


func _apply_filter() -> void:
	_filtered.clear()
	var category: String = String(_category.get_selected_metadata())
	var query: String = _search.text.strip_edges().to_lower()
	for entry: Dictionary in _catalog:
		var kind: String = String(entry.get("category", ""))
		var matches: bool = category == "all" or category == kind
		if category == "model":
			matches = kind in ["character_3d", "enemy_3d"]
		if matches and (query == "" or (String(entry.get("asset_id", "")) + " " + _asset_name(entry)).to_lower().contains(query)):
			_filtered.append(entry)
	_page = 0
	_build_page()


func _build_page() -> void:
	_generation += 1
	var generation: int = _generation
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var page_count: int = maxi(1, ceili(float(_filtered.size()) / PAGE_SIZE))
	_page = clampi(_page, 0, page_count - 1)
	_summary.text = _localized("Blender制作済み %d点 / 表示 %d点", "%d Blender-authored assets / %d matches") % [_catalog.size(), _filtered.size()]
	_page_label.text = "%d / %d" % [_page + 1, page_count]
	_previous.disabled = _page == 0
	_next.disabled = _page >= page_count - 1
	# Only the current page is imported, four thumbnails per frame on Web.
	for index: int in range(_page * PAGE_SIZE, mini((_page + 1) * PAGE_SIZE, _filtered.size())):
		if generation != _generation or not is_inside_tree():
			return
		_add_tile(_filtered[index])
		if index % 4 == 3:
			await get_tree().process_frame


func _add_tile(entry: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = 200.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var category: String = String(entry.get("category", ""))
	var id: String = String(entry.get("asset_id", ""))
	var center: CenterContainer = CenterContainer.new()
	box.add_child(center)
	if category == "card":
		var card: CardButton = CardButton.new()
		card.set_tile_size(Vector2(148, 148))
		center.add_child(card)
		var state: CardRuntimeState = CardRuntimeState.new()
		state.card_id = id
		state.runtime_id = "art_lab_" + id
		card.bind(_card_definition(id), state, true)
	elif category == "relic":
		var relic: RelicIcon = RelicIcon.new()
		relic.set_icon_size(Vector2(144, 144))
		center.add_child(relic)
		relic.bind_relic_id(id)
	else:
		var path: String = String(entry.get("runtime_path", ""))
		if category in ["character_3d", "enemy_3d"]:
			path = "assets/portraits/%s.png" % id
		elif category == "environment":
			path = "assets/backgrounds/hub.png"
		var image: TextureRect = TextureRect.new()
		image.texture = ArtCatalog.get_texture(path) if path.ends_with(".png") or path.ends_with(".svg") else null
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(152, 152)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(image)
	var label: Label = Label.new()
	label.text = _asset_name(entry)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(label)
	var inspect: Button = Button.new()
	inspect.name = "ArtInspect_" + id
	inspect.text = id
	inspect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inspect.tooltip_text = String(entry.get("source_path", ""))
	inspect.pressed.connect(_open_preview.bind(entry))
	box.add_child(inspect)


func _open_preview(entry: Dictionary) -> void:
	_close_preview()
	_previous_focus = get_viewport().gui_get_focus_owner()
	_overlay = ColorRect.new()
	_overlay.name = "ArtPreviewOverlay"
	_overlay.color = Color(0.0, 0.0, 0.0, 0.8)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.z_index = 100
	add_child(_overlay)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 38)
	_overlay.add_child(margin)
	var panel: PanelContainer = PanelContainer.new()
	margin.add_child(panel)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var title: Label = Label.new()
	title.text = _asset_name(entry)
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ArtPreviewScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	if String(entry.get("category", "")) in ["character_3d", "enemy_3d"]:
		var model: StarterModelPreview = StarterModelPreview.new()
		model.size_flags_vertical = Control.SIZE_EXPAND_FILL
		model.custom_minimum_size.y = 240.0
		content.add_child(model)
		model.show_starter(String(entry.get("asset_id", "")))
		model.set_auto_frame(true)
	elif String(entry.get("category", "")) == "environment":
		var field: BattleStage3D = BattleStage3D.new()
		field.custom_minimum_size.y = 240.0
		field.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(field)
		field.configure_combatants("player", "enemy", "player", "balanced", "scout")
	else:
		var image: TextureRect = TextureRect.new()
		image.texture = ArtCatalog.get_texture(String(entry.get("runtime_path", "")))
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		image.custom_minimum_size.y = 160.0
		content.add_child(image)
		var sizes: HBoxContainer = HBoxContainer.new()
		sizes.alignment = BoxContainer.ALIGNMENT_CENTER
		sizes.add_theme_constant_override("separation", 24)
		content.add_child(sizes)
		for extent: int in [24, 48, 96, 168]:
			var sample: TextureRect = TextureRect.new()
			sample.texture = image.texture
			sample.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sample.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			sample.custom_minimum_size = Vector2.ONE * extent
			sample.tooltip_text = "%dpx" % extent
			sizes.add_child(sample)
	var details: Label = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	details.text = "%s\n%s\nSHA-256: %s" % [entry.get("runtime_path", ""), entry.get("source_path", ""), String(entry.get("export_sha256", "")).left(16)]
	content.add_child(details)
	var close: Button = Button.new()
	close.name = "ArtPreviewClose"
	close.text = _localized("閉じる", "Close")
	close.pressed.connect(_close_preview)
	root.add_child(close)
	close.grab_focus()
	close.focus_next = close.get_path()
	close.focus_previous = close.get_path()


func _close_preview() -> void:
	if _overlay != null:
		remove_child(_overlay)
		_overlay.queue_free()
		_overlay = null
		if is_instance_valid(_previous_focus):
			_previous_focus.grab_focus()
		_previous_focus = null
