extends Control

var draft: BalanceDraft = BalanceDraft.new()
var runner: BalanceTrialRunner = BalanceTrialRunner.new()
var _kind: String = "card"
var _selected: String = "quick_slash"
var _ready_catalog: bool = false
var _search: LineEdit
var _rarity: OptionButton
var _tag: OptionButton
var _only_changes: CheckButton
var _catalog_grid: GridContainer
var _catalog_widgets: Dictionary = {}
var _field_widgets: Dictionary = {}
var _fields_box: VBoxContainer
var _preview: VBoxContainer
var _heading: Label
var _grade_tabs: TabBar
var _editor_grade: int = 0
var _status: Label
var _columns: BoxContainer
var _list_frame: PanelContainer
var _scroll: ScrollContainer
var _save_timer: Timer
var _filter_timer: Timer
var _starter: OptionButton
var _enemy: OptionButton
var _hp: SpinBox
var _attack: SpinBox
var _speed: SpinBox
var _grade: SpinBox
var _mode: OptionButton
var _power: SpinBox
var _count: SpinBox
var _seed: SpinBox
var _limit: SpinBox
var _deck_label: Label
var _test_cards: Array[String] = []
var _test_relics: Array[String] = []
var _results: RichTextLabel
var _progress: ProgressBar
var _modal: PanelContainer
var _manual: BalanceBattlePreview
var _manual_count: int = 0
var _bulk_excluded: Dictionary = {"card": {}, "relic": {}}


func _t(ja: String, en: String) -> String:
	return ja if Localization.get_language() == "ja" else en


func _ready() -> void:
	if not Game.is_developer_mode_enabled() or NetworkManager.is_session_connected():
		SceneRouter.go_to_hub()
		return
	BalanceDraft.warm_catalog()
	draft.load_draft()
	_build_ui()
	draft.changed.connect(_on_draft_changed)
	resized.connect(_responsive)
	AccountSession.changed.connect(_check_permission)
	call_deferred("_build_catalog")
	_starter_changed(0)
	_responsive()


func is_content_ready() -> bool:
	return _ready_catalog


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 24; margin.offset_top = 20; margin.offset_right = -24; margin.offset_bottom = -20
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var heading: HBoxContainer = HBoxContainer.new()
	root.add_child(heading)
	var title: Label = Label.new()
	title.text = _t("バランス調整ラボ", "Balance Lab")
	title.tooltip_text = _t("開発者専用 / 端末内の下書き。通常プレイ・セーブ・ランキングには適用しません。カード変更は模擬戦の両者、遺物変更は試験遺物に適用します。", "Developer sandbox / device-local draft. No live save, ranking or season changes. Card edits apply to both combatants; relic edits apply to your selected test relics.")
	title.theme_type_variation = "PageTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_button(heading, "BalanceBack", _t("戻る", "Back"), _back)
	var filters: HFlowContainer = HFlowContainer.new()
	root.add_child(filters)
	_button(filters, "BalanceCardsTab", _t("カード", "Cards"), _switch_kind.bind("card"))
	_button(filters, "BalanceRelicsTab", _t("遺物", "Relics"), _switch_kind.bind("relic"))
	_search = LineEdit.new()
	_search.name = "BalanceSearch"
	_search.placeholder_text = _t("名前・ID・タグで検索", "Search name, ID, tags")
	_search.custom_minimum_size.x = 230
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(_search)
	_rarity = OptionButton.new()
	_rarity.name = "BalanceRarity"
	for rarity: String in ["all", "common", "rare", "epic", "legendary"]:
		_rarity.add_item(_t("全レア度", "All rarities") if rarity == "all" else Localization.get_rarity_name(rarity))
		_rarity.set_item_metadata(_rarity.item_count - 1, rarity)
	filters.add_child(_rarity)
	_tag = OptionButton.new()
	_tag.name = "BalanceTag"
	_tag.add_item(_t("全種類", "All types")); _tag.set_item_metadata(0, "all")
	var tags: Dictionary = {}
	for kind: String in ["card", "relic"]:
		for id: String in BalanceDraft.ids(kind):
			for tag: String in BalanceDraft.original(kind, id).get("tags", []): tags[tag] = true
	for tag: String in tags:
		_tag.add_item(Localization.get_text("tag." + tag, tag.capitalize()))
		_tag.set_item_metadata(_tag.item_count - 1, tag)
	filters.add_child(_tag)
	_only_changes = CheckButton.new()
	_only_changes.name = "BalanceChangedOnly"
	_only_changes.text = _t("変更済みのみ", "Changed only")
	filters.add_child(_only_changes)
	_filter_timer = Timer.new(); _filter_timer.one_shot = true; _filter_timer.wait_time = 0.18
	add_child(_filter_timer); _filter_timer.timeout.connect(_filter_catalog)
	_search.text_changed.connect(func(_text: String) -> void: _filter_timer.start())
	_rarity.item_selected.connect(func(_i: int) -> void: _filter_catalog())
	_tag.item_selected.connect(func(_i: int) -> void: _filter_catalog())
	_only_changes.toggled.connect(func(_v: bool) -> void: _filter_catalog())
	_scroll = ScrollContainer.new()
	_scroll.name = "BalanceMainScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	_columns = BoxContainer.new()
	_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 12)
	_scroll.add_child(_columns)
	_scroll.resized.connect(_responsive)
	var catalog: VBoxContainer = _panel(_columns, _t("対象一覧", "Catalog"))
	_list_frame = catalog.get_parent() as PanelContainer
	_list_frame.size_flags_stretch_ratio = 0.7
	var list_scroll: ScrollContainer = _inner_scroll(catalog, "BalanceCatalogScroll")
	_catalog_grid = GridContainer.new()
	_catalog_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_grid.add_theme_constant_override("v_separation", 8)
	list_scroll.add_child(_catalog_grid)
	var edit: VBoxContainer = _panel(_columns, _t("数値を編集", "Edit values"))
	_heading = Label.new(); _heading.name = "BalanceSelection"; _heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	edit.add_child(_heading)
	_grade_tabs = TabBar.new(); _grade_tabs.name = "BalanceGradeTabs"
	for tier: int in range(CardUpgradeResolver.MAX_TIER + 1): _grade_tabs.add_tab(CardInfoFormatter.format_grade_label(tier))
	edit.add_child(_grade_tabs)
	_grade_tabs.tab_changed.connect(_on_editor_grade_changed)
	_grade_tabs.tooltip_text = _t("基本は全Grade共通の元値。+1以降はそのGradeだけの実数値を編集します。", "Base values feed all grades. Higher tabs override only that grade's actual values.")
	var editor_scroll: ScrollContainer = _inner_scroll(edit, "BalanceEditorScroll")
	_fields_box = VBoxContainer.new(); _fields_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields_box.add_theme_constant_override("separation", 8)
	editor_scroll.add_child(_fields_box)
	_button(edit, "BalanceAddTest", _t("試験デッキ / 試験遺物に追加・外す", "Add/remove from test setup"), _toggle_test)
	_button(edit, "BalanceResetSelected", _t("この対象を元に戻す", "Reset selected"), _reset_selected)
	_button(edit, "BalanceResetGrade", _t("このGradeの個別変更を戻す", "Reset this grade's overrides"), _reset_grade)
	var preview: VBoxContainer = _panel(_columns, _t("変更前 / 変更後", "Before / After"))
	var preview_scroll: ScrollContainer = _inner_scroll(preview, "BalancePreviewScroll")
	_preview = VBoxContainer.new(); _preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(_preview)
	var conditions: HFlowContainer = HFlowContainer.new(); root.add_child(conditions)
	_starter = _option(conditions, "BalanceStarter", Game.get_debug_battle_starter_entries())
	_enemy = _option(conditions, "BalanceEnemy", Game.get_debug_battle_enemy_entries())
	_hp = _spin(conditions, "BalanceHP", "HP", 1, 10000, 60, 1)
	_attack = _spin(conditions, "BalanceAttack", _t("攻撃", "Attack"), 0, 1000, 3, 1)
	_speed = _spin(conditions, "BalanceSpeed", _t("速度", "Speed"), 0, 1000, 5, 1)
	_grade = _spin(conditions, "BalanceGrade", "Grade", 0, CardUpgradeResolver.MAX_TIER, 0, 1)
	_mode = OptionButton.new(); _mode.name = "BalanceMode"
	for mode: String in [_t("通常条件", "Normal"), _t("危険地帯", "Hazard"), _t("アリーナ条件", "Arena"), _t("無限条件", "Infinite")]: _mode.add_item(mode)
	conditions.add_child(_mode)
	_power = _spin(conditions, "BalancePower", _t("周回/ウェーブ", "Cycle/wave"), 1, 50, 1, 1)
	_starter.item_selected.connect(_starter_changed)
	for spin: SpinBox in [_hp, _attack, _speed, _grade]: spin.value_changed.connect(func(_v: float) -> void: _refresh_preview())
	_grade.value_changed.connect(func(value: float) -> void:
		if _grade_tabs.current_tab != int(value): _grade_tabs.current_tab = int(value)
	)
	_deck_label = Label.new(); _deck_label.name = "BalanceTestSetup"; _deck_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_deck_label)
	var actions: HFlowContainer = HFlowContainer.new(); root.add_child(actions)
	_button(actions, "BalanceManualBefore", _t("変更前で模擬戦", "Play before"), _open_manual.bind(false))
	_button(actions, "BalanceManualAfter", _t("変更後で模擬戦", "Play after"), _open_manual.bind(true))
	_count = _spin(actions, "BalanceMatches", _t("比較回数", "Matches"), 1, 200, 10, 1)
	_limit = _spin(actions, "BalanceTimeLimit", _t("上限秒", "Time cap"), 10, 1800, 180, 10)
	_seed = _spin(actions, "BalanceSeed", "Seed", 1, 2147483647, 12345, 1)
	_button(actions, "BalanceCompare", _t("同条件でA/B自動比較", "Run matched A/B"), _compare)
	_button(actions, "BalanceChanges", _t("変更一覧", "Changes"), _show_changes)
	_button(actions, "BalanceBulk", _t("絞り込み対象を一括編集", "Bulk edit filtered"), _open_bulk)
	_button(actions, "BalanceExport", _t("差分を書き出し", "Export diff"), _export)
	_button(actions, "BalanceResetAll", _t("すべて元に戻す", "Reset all"), _confirm_reset)
	_status = Label.new(); _status.name = "BalanceStatus"; _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	_save_timer = Timer.new(); _save_timer.one_shot = true; _save_timer.wait_time = 0.4
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)


func _panel(parent: Control, title: String) -> VBoxContainer:
	var frame: PanelContainer = PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var body: VBoxContainer = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10); frame.add_child(body)
	var label: Label = Label.new(); label.text = title; label.theme_type_variation = "SectionTitle"; body.add_child(label)
	return body


func _inner_scroll(parent: Control, node_name: String) -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = node_name; scroll.custom_minimum_size.y = 220; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return scroll


func _button(parent: Control, id: String, text: String, action: Callable) -> Button:
	var button: Button = Button.new(); button.name = id; button.text = text; button.pressed.connect(action); parent.add_child(button)
	return button


func _spin(parent: Control, id: String, text: String, minimum: float, maximum: float, value: float, step: float) -> SpinBox:
	var group: HBoxContainer = HBoxContainer.new(); parent.add_child(group)
	var label: Label = Label.new(); label.text = text; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; group.add_child(label)
	var spin: SpinBox = SpinBox.new(); spin.name = id; spin.min_value = minimum; spin.max_value = maximum; spin.step = step; spin.value = value; spin.custom_minimum_size.x = 84
	_enable_live_input(spin)
	group.add_child(spin)
	return spin


func _enable_live_input(spin: SpinBox) -> void:
	# SpinBox's built-in live mode clamps partial text (typing 10 can become 100).
	# Apply valid values immediately, but leave the user's text/caret untouched.
	var line: LineEdit = spin.get_line_edit()
	line.text_changed.connect(func(text: String) -> void:
		if not text.is_valid_float(): return
		var value: float = float(text)
		if not is_finite(value) or value < spin.min_value or value > spin.max_value: return
		var caret: int = line.caret_column
		var before: float = spin.value
		spin.set_value_no_signal(value)
		spin.apply() # Refresh SpinBox's formatting cache before restoring partial text.
		line.text = text
		line.caret_column = caret
		if not is_equal_approx(before, spin.value): spin.value_changed.emit(spin.value)
	)


func _option(parent: Control, id: String, entries: Array[Dictionary]) -> OptionButton:
	var option: OptionButton = OptionButton.new(); option.name = id; option.custom_minimum_size.x = 170; parent.add_child(option)
	for entry: Dictionary in entries:
		option.add_item(String(entry["name"]))
		option.set_item_metadata(option.item_count - 1, entry["id"])
	return option


func _build_catalog() -> void:
	var built: int = 0
	for kind: String in ["card", "relic"]:
		for id: String in BalanceDraft.ids(kind):
			if not is_inside_tree(): return
			var button: Button = Button.new()
			button.name = "BalanceEntry_" + kind + "_" + id
			button.custom_minimum_size = Vector2(0, 62)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.visible = kind == _kind
			var margin: MarginContainer = MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
			margin.offset_left = 8; margin.offset_right = -8; margin.offset_top = 6; margin.offset_bottom = -6
			button.add_child(margin)
			var row: HBoxContainer = HBoxContainer.new(); row.mouse_filter = Control.MOUSE_FILTER_IGNORE; margin.add_child(row)
			var icon: TextureRect = TextureRect.new(); icon.texture = _texture(kind, id); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.custom_minimum_size = Vector2(44, 44); icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(icon)
			var label: Label = Label.new(); label.text = _name(kind, id); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(label)
			button.pressed.connect(_select.bind(kind, id))
			_catalog_grid.add_child(button)
			_catalog_widgets[kind + ":" + id] = {"button": button, "label": label, "kind": kind, "id": id}
			built += 1
			if built % 10 == 0: await get_tree().process_frame
	_ready_catalog = true
	_filter_catalog()
	_select(_kind, _selected)
	_status.text = draft.error_text
	_on_draft_changed()


func _texture(kind: String, id: String) -> Texture2D:
	return CardButton._load_card_texture(id) if kind == "card" else RelicIcon._load_relic_texture(id)


func _name(kind: String, id: String) -> String:
	return Database.get_card(id).name if kind == "card" else Database.get_relic(id).name


func _switch_kind(kind: String) -> void:
	_kind = kind
	_selected = ""
	_filter_catalog()


func _filter_catalog() -> void:
	if not _ready_catalog: return
	(_catalog_grid.get_parent() as ScrollContainer).scroll_vertical = 0
	var first: String = ""
	for key: String in _catalog_widgets:
		var widget: Dictionary = _catalog_widgets[key]
		var row: Dictionary = BalanceDraft.original(widget["kind"], widget["id"])
		var match_text: String = (_name(widget["kind"], widget["id"]) + " " + widget["id"] + " " + " ".join(row.get("tags", []))).to_lower()
		var visible_entry: bool = widget["kind"] == _kind and (_search.text.is_empty() or match_text.contains(_search.text.to_lower())) and (_rarity.get_selected_metadata() == "all" or row.get("rarity", "common") == _rarity.get_selected_metadata()) and (_tag.get_selected_metadata() == "all" or Array(row.get("tags", [])).has(_tag.get_selected_metadata())) and (not _only_changes.button_pressed or draft.edits.has(key))
		(widget["button"] as Button).visible = visible_entry
		if visible_entry and first == "": first = widget["id"]
	if _selected == "" or not _catalog_widgets.has(_kind + ":" + _selected) or not (_catalog_widgets[_kind + ":" + _selected]["button"] as Button).visible:
		_select(_kind, first)


func _select(kind: String, id: String) -> void:
	_kind = kind; _selected = id
	_grade_tabs.visible = kind == "card"
	(find_child("BalanceResetGrade", true, false) as Button).visible = kind == "card"
	(_fields_box.get_parent() as ScrollContainer).scroll_vertical = 0
	_clear(_fields_box); _field_widgets.clear()
	if id == "": _heading.text = _t("該当する対象がありません", "No matching entries"); _clear(_preview); return
	_heading.text = _name(kind, id)
	for field: Dictionary in BalanceDraft.fields_for_grade(kind, id, _editor_grade):
		var row: VBoxContainer = VBoxContainer.new(); row.add_theme_constant_override("separation", 3); _fields_box.add_child(row)
		var label: Label = Label.new(); label.text = field["label"]; label.tooltip_text = field["path"]; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; row.add_child(label)
		var values: HBoxContainer = HBoxContainer.new(); row.add_child(values)
		var before: Label = Label.new(); before.text = "%s  >" % String.num(float(field["before"]), 3).trim_suffix(".000"); before.size_flags_horizontal = Control.SIZE_EXPAND_FILL; before.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; values.add_child(before)
		var spin: SpinBox = SpinBox.new(); spin.name = "BalanceValue_" + String(field["path"]).replace(".", "_"); spin.min_value = field["min"]; spin.max_value = field["max"]; spin.step = 1 if field["integer"] else 0.001; spin.custom_minimum_size.x = 120
		spin.value = draft.value(kind, id, field["path"])
		_enable_live_input(spin)
		values.add_child(spin)
		spin.value_changed.connect(_edit_value.bind(kind, id, field["path"]))
		spin.get_line_edit().focus_exited.connect(func() -> void: call_deferred("_filter_after_typing"))
		_field_widgets[field["path"]] = spin
		if not field["combat"]:
			var note: Label = Label.new(); note.text = _t("戦闘外・構造値：差分出力用（模擬戦では固定）", "Overworld/structural: export only, fixed in battle tests"); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.add_theme_font_size_override("font_size", 13); note.modulate = UiTheme.ACCENT_GOLD; row.add_child(note)
	_refresh_preview()
	if _only_changes.button_pressed and not _is_number_editing(): _filter_catalog()


func _on_editor_grade_changed(tier: int) -> void:
	_editor_grade = tier
	if _grade != null and int(_grade.value) != tier: _grade.value = tier
	if _ready_catalog and _kind == "card": _select(_kind, _selected)


func _edit_value(value: float, kind: String, id: String, path: String) -> void:
	if not draft.set_value(kind, id, path, value): _status.text = _t("入力値が範囲外です。", "Value is outside its range."); return
	if kind == "relic" and not _test_relics.has(id) and _test_relics.size() < 8: _test_relics.append(id)
	if kind == "card" and not _test_cards.has(id) and _test_cards.size() < 12: _test_cards.append(id)
	_update_test_label()


func _on_draft_changed() -> void:
	_save_timer.start()
	for key: String in _catalog_widgets:
		var widget: Dictionary = _catalog_widgets[key]
		(widget["label"] as Label).text = ("* " if draft.edits.has(key) else "") + _name(widget["kind"], widget["id"])
	_refresh_preview()
	_status.text = _t("変更: %d / 自動保存", "Changes: %d / Auto-save") % draft.changes().size()
	if draft.error_text != "": _status.text += "\n" + draft.error_text
	if _only_changes.button_pressed and not _is_number_editing(): _filter_catalog()


func _is_number_editing() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is LineEdit and focus.get_parent() is SpinBox


func _filter_after_typing() -> void:
	if _only_changes.button_pressed and not _is_number_editing(): _filter_catalog()


func _refresh_preview() -> void:
	if _preview == null or _selected == "": return
	_clear(_preview)
	var images: HBoxContainer = HBoxContainer.new(); images.alignment = BoxContainer.ALIGNMENT_CENTER; _preview.add_child(images)
	for index: int in 2:
		var box: VBoxContainer = VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; images.add_child(box)
		var label: Label = Label.new(); label.text = _t("変更前", "Before") if index == 0 else _t("変更後", "After"); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(label)
		if _kind == "card":
			var base: CardDef = BalanceDraft.new().card(_selected, int(_grade.value) if _grade != null else 0)
			var current: CardDef = draft.card(_selected, int(_grade.value) if _grade != null else 0) if index == 1 else CardDef.from_dict(base.to_dict())
			CardTooltipResolver._apply_attack_to_damage(base, int(_attack.value) if _attack != null else 0)
			CardTooltipResolver._apply_attack_to_damage(current, int(_attack.value) if _attack != null else 0)
			var unit: UnitState = UnitState.new(); unit.speed = int(_speed.value) if _speed != null else 5
			base.cast_time *= unit.get_cast_time_multiplier(); current.cast_time *= unit.get_cast_time_multiplier()
			var card: CardButton = CardButton.new(); card.name = "BalanceCardBefore" if index == 0 else "BalanceCardAfter"; card.set_tile_size(Vector2(108, 108)); card.bind_balance_preview(current, base); card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; box.add_child(card)
		else:
			var image: TextureRect = TextureRect.new(); image.texture = _texture(_kind, _selected); image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; image.custom_minimum_size = Vector2(0, 110); box.add_child(image)
	if _kind == "card":
		for tier: int in range(CardUpgradeResolver.MAX_TIER + 1):
			var before: CardDef = BalanceDraft.new().card(_selected, tier)
			var after: CardDef = draft.card(_selected, tier)
			CardTooltipResolver._apply_attack_to_damage(before, int(_attack.value) if _attack != null else 0)
			CardTooltipResolver._apply_attack_to_damage(after, int(_attack.value) if _attack != null else 0)
			var unit: UnitState = UnitState.new(); unit.speed = int(_speed.value) if _speed != null else 5
			before.cast_time *= unit.get_cast_time_multiplier(); after.cast_time *= unit.get_cast_time_multiplier()
			var text: RichTextLabel = RichTextLabel.new(); text.name = "BalancePreviewGrade%d" % tier; text.bbcode_enabled = true; text.fit_content = true; text.scroll_active = false; text.custom_minimum_size.x = 0
			text.text = "[b]%s[/b]\n%s %.2f > %.2fs / %s %.2f > %.2fs\n%s" % [CardInfoFormatter.format_grade_label(tier), _t("詠唱", "Cast"), before.cast_time, after.cast_time, _t("再使用", "Recast"), before.recast_time, after.recast_time, "\n".join(CardInfoFormatter.build_effect_lines(after, before, true))]
			_preview.add_child(text)
	else:
		var description: Label = Label.new(); description.text = _t("元の説明（変更後の数値は下の対照表）\n", "Original description (edited values below)\n") + Database.get_relic(_selected).description; description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _preview.add_child(description)
		for field: Dictionary in BalanceDraft.fields("relic", _selected):
			var line: Label = Label.new(); line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.text = "%s: %s > %s" % [field["label"], str(field["before"]), str(BalanceDraft.read(draft.data("relic", _selected), field["path"]))]
			_preview.add_child(line)
	_preview.tooltip_text = _t("プレビューは攻撃・速度込みの基礎性能です。戦闘では再使用4秒などの下限と、状態・遺物の条件を適用します。", "Preview shows base performance with attack/speed. Combat also applies existing floors (e.g. 4s recast) and conditional effects.")


func _starter_changed(_index: int) -> void:
	if _hp == null: return
	var source: RunState = RunState.from_starter(Database.get_starter(String(_starter.get_selected_metadata())), 1)
	_hp.value = source.max_hp; _attack.value = source.attack; _speed.value = source.speed
	_test_cards = source.equipped_cards.duplicate()
	_update_test_label()


func _toggle_test() -> void:
	if _selected == "": return
	var target: Array[String] = _test_cards if _kind == "card" else _test_relics
	if target.has(_selected): target.erase(_selected)
	elif target.size() < (12 if _kind == "card" else 8): target.append(_selected)
	else: _status.text = _t("試験セットの上限です。カード12枚・遺物8個まで。先に別の対象を外してください。", "Test set full: up to 12 cards / 8 relics. Remove another entry first.")
	_update_test_label()


func _update_test_label() -> void:
	if _deck_label == null: return
	var cards: Array[String] = []; var relics: Array[String] = []
	for id: String in _test_cards: cards.append(_name("card", id))
	for id: String in _test_relics: relics.append(_name("relic", id))
	_deck_label.text = _t("試験デッキ: ", "Test deck: ") + ", ".join(cards) + "\n" + _t("試験遺物: ", "Test relics: ") + ", ".join(relics)


func _config() -> Dictionary:
	return {"starter": _starter.get_selected_metadata(), "enemy": _enemy.get_selected_metadata(), "hp": int(_hp.value), "attack": int(_attack.value), "speed": int(_speed.value), "grade": int(_grade.value), "mode": _mode.selected, "power": int(_power.value), "count": int(_count.value), "seed": int(_seed.value), "limit": _limit.value, "cards": _test_cards.duplicate(), "relics": _test_relics.duplicate()}


func _open_manual(after: bool) -> void:
	if _test_cards.is_empty(): _status.text = _t("試験デッキを選んでください。", "Select a test deck."); return
	_close_modal()
	_modal = _modal_frame()
	_manual = BalanceBattlePreview.new()
	_modal.add_child(_manual)
	_manual.closed.connect(func() -> void: _manual = null; _modal.queue_free(); _modal = null)
	_manual.open(_config(), draft if after else BalanceDraft.new())
	_manual_count += 1


func _modal_frame() -> PanelContainer:
	var frame: PanelContainer = PanelContainer.new(); frame.name = "BalanceModal"; frame.z_index = 80; frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 24; frame.offset_right = -24; frame.offset_top = 24; frame.offset_bottom = -24
	var style: StyleBoxFlat = StyleBoxFlat.new(); style.bg_color = Color(0.035, 0.045, 0.06, 0.985); style.border_color = Color(0.33, 0.47, 0.55); style.set_border_width_all(1); style.set_corner_radius_all(12)
	style.content_margin_left = 16; style.content_margin_right = 16; style.content_margin_top = 16; style.content_margin_bottom = 16
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)
	return frame


func _compare() -> void:
	if runner.running: return
	_close_modal()
	if not runner.begin(_config(), draft): _status.text = _t("試験条件を確認してください。", "Check the test setup."); return
	_modal = _modal_frame()
	var root: VBoxContainer = VBoxContainer.new(); _modal.add_child(root)
	root.tooltip_text = _t("A = 変更前 / B = 開始時の下書き。同じデッキ・遺物・Seedで比較。勝率はBot同士の参考値です。", "A = original / B = frozen draft. Same deck, relics and seeds. Bot win rates are estimates.")
	_progress = ProgressBar.new(); _progress.name = "BalanceComparisonProgress"; root.add_child(_progress)
	_results = RichTextLabel.new(); _results.name = "BalanceComparisonResults"; _results.bbcode_enabled = true; _results.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(_results)
	_button(root, "BalanceCancelCompare", _t("中止 / 閉じる", "Cancel / Close"), _close_modal)


func _process(_delta: float) -> void:
	if runner.running:
		runner.advance()
		if _results != null and is_instance_valid(_results):
			_progress.value = runner.progress() * 100
			var lines: Array[String] = []
			for report: Dictionary in runner.reports:
				var n: float = maxf(1, float(report["completed"]))
				lines.append("[b]%s[/b] %d/%d | %s %.1f%% | %s %.1fs\n%s %.1f / %s %.1f / %s %.1f | %s %d" % [report["label"], report["completed"], int(runner._config["count"]), _t("勝率", "Win"), 100 * float(report["wins"]) / n, _t("平均時間", "Mean time"), float(report["time"]) / n, _t("平均ダメージ", "Mean damage"), float(report["damage"]) / n, _t("シールド", "Shield"), float(report["shield"]) / n, _t("回復", "Heal"), float(report["heal"]) / n, _t("未決着", "Unresolved"), report["unresolved"]])
			if not runner.running and runner.reports.size() == 2:
				var a: Dictionary = runner.reports[0]; var b: Dictionary = runner.reports[1]
				var an: float = maxf(1, float(a["completed"])); var bn: float = maxf(1, float(b["completed"]))
				lines.append("B - A | %s %+0.1fpt / %s %+0.1fs" % [_t("勝率", "Win rate"), 100 * float(b["wins"]) / bn - 100 * float(a["wins"]) / an, _t("平均時間", "Mean time"), float(b["time"]) / bn - float(a["time"]) / an])
			_results.text = "\n\n".join(lines)


func _close_modal() -> void:
	runner.cancel()
	if _manual != null: _manual.engine.dispose(); _manual.engine = null; _manual = null
	if _modal != null: _modal.queue_free(); _modal = null
	_results = null


func _show_changes() -> void:
	_close_modal(); _modal = _modal_frame()
	var root: VBoxContainer = VBoxContainer.new(); _modal.add_child(root)
	var text: TextEdit = TextEdit.new(); text.name = "BalanceChangeDocument"; text.editable = false; text.text = _describe_changes(draft); text.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(text)
	_button(root, "BalanceCloseChanges", _t("閉じる", "Close"), _close_modal)


func _describe_changes(candidate: BalanceDraft) -> String:
	var lines: Array[String] = []
	for change: Dictionary in candidate.changes():
		var label: String = change["path"]
		for field: Dictionary in BalanceDraft.fields(change["kind"], change["id"]):
			if field["path"] == change["path"]: label = field["label"]; break
		lines.append("%s / %s\n    %s > %s" % [_name(change["kind"], change["id"]), label, str(change["before"]), str(change["after"])])
	return "\n\n".join(lines) if not lines.is_empty() else _t("変更はありません。", "No changes.")


func _open_bulk() -> void:
	if _selected == "": return
	_close_modal(); _modal = _modal_frame()
	var kind: String = _kind
	var scope: Array[String] = []
	var field_maps: Dictionary = {}
	for widget: Dictionary in _catalog_widgets.values():
		if widget["kind"] != kind or not (widget["button"] as Button).visible: continue
		var id: String = widget["id"]
		scope.append(id)
		var available: Dictionary = {}
		for field: Dictionary in BalanceDraft.fields_for_grade(kind, id, _editor_grade): available[field["path"]] = field["label"]
		field_maps[id] = available
	var excluded: Dictionary = _bulk_excluded[kind]
	var root: VBoxContainer = VBoxContainer.new(); _modal.add_child(root)
	root.tooltip_text = _t("現在の絞り込み対象だけを変更します。整数は四捨五入、小数は0.001単位。範囲外・項目なしは除外します。", "Edit visible filtered entries only. Round integers; decimals use 0.001 units. Invalid/missing fields are skipped.")
	var field_option: OptionButton = OptionButton.new(); field_option.name = "BalanceBulkField"; root.add_child(field_option)
	for field: Dictionary in BalanceDraft.fields_for_grade(kind, _selected, _editor_grade):
		field_option.add_item(field["label"]); field_option.set_item_metadata(field_option.item_count - 1, field["path"])
	var operation: OptionButton = OptionButton.new(); operation.name = "BalanceBulkOperation"; root.add_child(operation)
	for value: String in [_t("倍率（例: 0.9 = 10%減）", "Multiply (0.9 = -10%)"), _t("加算", "Add"), _t("固定値にする", "Set")]: operation.add_item(value)
	var amount: SpinBox = _spin(root, "BalanceBulkAmount", _t("値", "Value"), -10000, 10000, 0.9, 0.01)
	var columns: BoxContainer = BoxContainer.new(); columns.name = "BalanceBulkColumns"; columns.vertical = size.x < size.y * 1.15; columns.add_theme_constant_override("separation", 16); columns.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(columns)
	var selection: VBoxContainer = VBoxContainer.new(); selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL; selection.size_flags_vertical = Control.SIZE_EXPAND_FILL; selection.size_flags_stretch_ratio = 0.9; columns.add_child(selection)
	var summary: Label = Label.new(); summary.name = "BalanceBulkTargetCount"; selection.add_child(summary)
	var search: LineEdit = LineEdit.new(); search.name = "BalanceBulkSearch"; search.placeholder_text = _t("名前・IDで検索", "Search name / ID"); selection.add_child(search)
	var actions: HBoxContainer = HBoxContainer.new(); selection.add_child(actions)
	var include_all: Button = Button.new(); include_all.name = "BalanceBulkIncludeAll"; include_all.text = _t("すべて対象", "Include all"); actions.add_child(include_all)
	var exclude_all: Button = Button.new(); exclude_all.name = "BalanceBulkExcludeAll"; exclude_all.text = _t("すべて除外", "Exclude all"); actions.add_child(exclude_all)
	for button: Button in [include_all, exclude_all]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = _t("一覧内の検索に関係なく、今回の対象すべてに適用します。", "Applies to this entire batch scope, regardless of the list search.")
	var scroll: ScrollContainer = ScrollContainer.new(); scroll.name = "BalanceBulkTargetScroll"; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.custom_minimum_size.y = 120; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; selection.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	var toggles: Dictionary = {}
	for id: String in scope:
		var toggle: CheckBox = CheckBox.new(); toggle.name = "BalanceBulkTarget_" + id; toggle.set_meta("target_id", id)
		toggle.text = _name(kind, id); toggle.icon = _texture(kind, id); toggle.expand_icon = true; toggle.add_theme_constant_override("icon_max_width", 32); toggle.custom_minimum_size.y = 44
		toggle.button_pressed = not excluded.has(id); toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL; toggle.clip_text = true
		list.add_child(toggle); toggles[id] = toggle
	var details: TextEdit = TextEdit.new(); details.name = "BalanceBulkPreview"; details.editable = false; details.size_flags_horizontal = Control.SIZE_EXPAND_FILL; details.size_flags_vertical = Control.SIZE_EXPAND_FILL; details.size_flags_stretch_ratio = 1.3; details.custom_minimum_size.y = 120; columns.add_child(details)
	details.add_theme_color_override("font_readonly_color", UiTheme.TEXT_MAIN)
	var candidate: Dictionary = {}
	var original_hash: String = JSON.stringify(draft.document()).sha256_text()
	var apply: Button = _button(root, "BalanceBulkApply", _t("このプレビューを適用", "Apply this preview"), func() -> void:
		if JSON.stringify(draft.document()).sha256_text() != original_hash:
			_status.text = _t("下書きが変わったため中止しました。", "Draft changed; bulk edit cancelled.")
			details.text = _status.text
			return
		var result: BalanceDraft = candidate["draft"]
		draft.import_document(result.document())
		_close_modal(); _select(_kind, _selected)
	)
	var rebuild: Callable = func() -> void:
		var path: String = field_option.get_selected_metadata()
		var ids: Array[String] = []
		var eligible: int = 0
		for id: String in scope:
			var toggle: CheckBox = toggles[id]
			toggle.disabled = not field_maps[id].has(path)
			toggle.tooltip_text = id if not toggle.disabled else _t("この数値項目はありません。", "This numeric field is unavailable.")
			toggle.set_pressed_no_signal(not excluded.has(id))
			if toggle.disabled: continue
			eligible += 1
			if not excluded.has(id): ids.append(id)
		var result: BalanceDraft = draft.batch_candidate(kind, ids, path, operation.selected, amount.value)
		candidate["draft"] = result
		var lines: Array[String] = []
		for id: String in ids:
			var before: float = draft.value(kind, id, path)
			var after: float = result.value(kind, id, path)
			if not is_equal_approx(before, after): lines.append("%s / %s\n    %s > %s" % [_name(kind, id), field_maps[id][path], String.num(before, 3), String.num(after, 3)])
		details.text = "\n\n".join(lines) if not lines.is_empty() else _t("変更はありません。", "No changes.")
		summary.text = _t("対象 %d / %d", "Targets %d / %d") % [ids.size(), eligible]
		summary.set_meta("selected_count", ids.size()); summary.set_meta("eligible_count", eligible)
		apply.disabled = lines.is_empty()
	for id: String in scope:
		(toggles[id] as CheckBox).toggled.connect(func(enabled: bool) -> void:
			if enabled: excluded.erase(id)
			else: excluded[id] = true
			rebuild.call()
		)
	include_all.pressed.connect(func() -> void:
		for id: String in scope: excluded.erase(id)
		rebuild.call()
	)
	exclude_all.pressed.connect(func() -> void:
		for id: String in scope: excluded[id] = true
		rebuild.call()
	)
	search.text_changed.connect(func(text: String) -> void:
		for id: String in scope: (toggles[id] as CheckBox).visible = text.is_empty() or (_name(kind, id) + " " + id).to_lower().contains(text.to_lower())
	)
	columns.resized.connect(func() -> void: columns.vertical = size.x < size.y * 1.15)
	field_option.item_selected.connect(func(_i: int) -> void: rebuild.call())
	operation.item_selected.connect(func(_i: int) -> void: rebuild.call())
	amount.value_changed.connect(func(_v: float) -> void: rebuild.call())
	_button(root, "BalanceBulkCancel", _t("キャンセル", "Cancel"), _close_modal)
	rebuild.call()


func _export() -> void:
	_save()
	var text: String = JSON.stringify(draft.document(), "\t")
	var name: String = "queuequest-balance-%d-%s.json" % [int(Time.get_unix_time_from_system()), Crypto.new().generate_random_bytes(4).hex_encode()]
	var directory: String = "user://balance_lab_exports"
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	if file == null: _status.text = _t("書き出しに失敗しました。", "Export failed."); return
	file.store_string(text); file.close()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(()=>{const blob=new Blob([%s],{type:'application/json;charset=utf-8'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=%s;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000)})()" % [JSON.stringify(text), JSON.stringify(name)])
	_status.text = _t("書き出しました: ", "Exported: ") + (name if OS.has_feature("web") else ProjectSettings.globalize_path(directory.path_join(name)))


func _reset_selected() -> void:
	draft.reset(_kind, _selected); _select(_kind, _selected)


func _reset_grade() -> void:
	if _kind == "card" and _selected != "": draft.reset_grade(_selected, _editor_grade); _select(_kind, _selected)


func _confirm_reset() -> void:
	var dialog: ConfirmationDialog = ConfirmationDialog.new(); dialog.dialog_text = _t("すべての下書きの変更を元に戻しますか？", "Reset all draft changes?"); add_child(dialog)
	dialog.confirmed.connect(func() -> void: draft.reset(); _select(_kind, _selected); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered()


func _save() -> void:
	if not draft.save_draft(): _status.text = _t("下書きの保存に失敗しました。", "Draft save failed.")


func _responsive() -> void:
	if _columns == null: return
	var narrow: bool = size.x < size.y * 1.15
	_columns.vertical = narrow
	_columns.custom_minimum_size.y = 0 if narrow else maxf(240, _scroll.size.y)
	_list_frame.custom_minimum_size.x = 0 if narrow else 240
	for child: Control in _columns.get_children(): child.custom_minimum_size.y = 300 if narrow else 0


func _check_permission() -> void:
	if not Game.is_developer_mode_enabled(): _back()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _modal != null: _close_modal()
		else: _back()
		get_viewport().set_input_as_handled()


func _back() -> void:
	_close_modal(); _save(); SceneRouter.return_from_debug_lab()


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children(): parent.remove_child(child); child.queue_free()


func _exit_tree() -> void:
	runner.cancel()
	if _manual != null and _manual.engine != null: _manual.engine.dispose()
	if _ready_catalog: draft.save_draft()
