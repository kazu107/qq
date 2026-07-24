extends Control

const CATEGORY_ORDER: Array[String] = [
	"all",
	"ui",
	"run",
	"reward",
	"online",
	"battle",
	"timeline",
	"status",
	"result",
	"card",
	"relic",
]
const CATEGORY_LABELS: Dictionary = {
	"all": {"ja": "すべて", "en": "All"},
	"ui": {"ja": "UI", "en": "UI"},
	"run": {"ja": "ラン / マップ", "en": "Run / Map"},
	"reward": {"ja": "報酬 / 施設", "en": "Reward / Facility"},
	"online": {"ja": "オンライン", "en": "Online"},
	"battle": {"ja": "戦闘", "en": "Battle"},
	"timeline": {"ja": "タイムライン", "en": "Timeline"},
	"status": {"ja": "状態", "en": "Status"},
	"result": {"ja": "結果 / リプレイ", "en": "Result / Replay"},
	"card": {"ja": "カード固有", "en": "Card specific"},
	"relic": {"ja": "遺物固有", "en": "Relic specific"},
}
const TILE_MINIMUM_SIZE: Vector2 = Vector2(0.0, 116.0)
const PLAY_INTERVAL_SECONDS: float = 1.35

var _catalog: Array[Dictionary] = []
var _tiles: Array[Dictionary] = []
var _category_option: OptionButton
var _search_edit: LineEdit
var _grid: GridContainer
var _summary_label: Label
var _status_label: Label
var _volume_slider: HSlider
var _volume_value: Label
var _play_visible_button: Button
var _playlist_timer: Timer
var _playlist: Array[String] = []
var _playlist_labels: Dictionary = {}
var _playlist_waits: Dictionary = {}
var _playlist_index: int = 0


func _ready() -> void:
	if not Game.is_developer_mode_enabled():
		SceneRouter.go_to_hub()
		return
	_catalog = AudioManager.get_sfx_catalog()
	_build_ui()
	_build_tiles()
	_apply_filter()


func _exit_tree() -> void:
	if _playlist_timer != null:
		_playlist_timer.stop()
	AudioManager.stop_all_sfx()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _build_ui() -> void:
	var page_margin: MarginContainer = MarginContainer.new()
	page_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_margin.add_theme_constant_override("margin_left", 48)
	page_margin.add_theme_constant_override("margin_top", 34)
	page_margin.add_theme_constant_override("margin_right", 48)
	page_margin.add_theme_constant_override("margin_bottom", 34)
	add_child(page_margin)

	var page_root: VBoxContainer = VBoxContainer.new()
	page_root.add_theme_constant_override("separation", 14)
	page_margin.add_child(page_root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	page_root.add_child(header)

	var title_group: VBoxContainer = VBoxContainer.new()
	title_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_group.add_theme_constant_override("separation", 2)
	header.add_child(title_group)

	var title: Label = Label.new()
	title.text = _localized("SE再生ラボ", "SFX Lab")
	title.add_theme_font_size_override("font_size", 30)
	title_group.add_child(title)

	_summary_label = Label.new()
	_summary_label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	title_group.add_child(_summary_label)

	var stop_button: Button = Button.new()
	stop_button.name = "SfxLabStopButton"
	stop_button.text = _localized("停止", "Stop")
	stop_button.custom_minimum_size = Vector2(110.0, 44.0)
	stop_button.pressed.connect(_on_stop_pressed)
	header.add_child(stop_button)

	_play_visible_button = Button.new()
	_play_visible_button.name = "SfxLabPlayVisibleButton"
	_play_visible_button.text = _localized("表示中を順番に再生", "Play visible")
	_play_visible_button.custom_minimum_size = Vector2(190.0, 44.0)
	_play_visible_button.pressed.connect(_on_play_visible_pressed)
	header.add_child(_play_visible_button)

	var back_button: Button = Button.new()
	back_button.name = "SfxLabBackButton"
	back_button.text = _localized("戻る", "Back")
	back_button.custom_minimum_size = Vector2(110.0, 44.0)
	back_button.pressed.connect(_on_back_pressed)
	header.add_child(back_button)

	var controls_panel: PanelContainer = PanelContainer.new()
	controls_panel.name = "SfxLabControls"
	page_root.add_child(controls_panel)

	var controls_margin: MarginContainer = MarginContainer.new()
	controls_margin.add_theme_constant_override("margin_left", 16)
	controls_margin.add_theme_constant_override("margin_top", 12)
	controls_margin.add_theme_constant_override("margin_right", 16)
	controls_margin.add_theme_constant_override("margin_bottom", 12)
	controls_panel.add_child(controls_margin)

	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	controls_margin.add_child(controls)

	_category_option = OptionButton.new()
	_category_option.name = "SfxLabCategory"
	_category_option.custom_minimum_size = Vector2(210.0, 42.0)
	for category: String in CATEGORY_ORDER:
		_category_option.add_item(_category_label(category))
		_category_option.set_item_metadata(_category_option.item_count - 1, category)
	_category_option.item_selected.connect(_on_filter_changed)
	controls.add_child(_category_option)

	_search_edit = LineEdit.new()
	_search_edit.name = "SfxLabSearch"
	_search_edit.placeholder_text = _localized("SE名・IDを検索", "Search by name or ID")
	_search_edit.clear_button_enabled = true
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.custom_minimum_size = Vector2(360.0, 42.0)
	_search_edit.text_changed.connect(_on_search_changed)
	controls.add_child(_search_edit)

	var volume_label: Label = Label.new()
	volume_label.text = _localized("SE音量", "SFX volume")
	volume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls.add_child(volume_label)

	_volume_slider = HSlider.new()
	_volume_slider.name = "SfxLabVolume"
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_slider.value = Game.get_sfx_volume()
	_volume_slider.custom_minimum_size = Vector2(180.0, 0.0)
	_volume_slider.value_changed.connect(_on_volume_changed)
	controls.add_child(_volume_slider)

	_volume_value = Label.new()
	_volume_value.custom_minimum_size = Vector2(54.0, 0.0)
	_volume_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_volume_value.text = "%d%%" % int(round(_volume_slider.value * 100.0))
	controls.add_child(_volume_value)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "SfxLabScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_root.add_child(scroll)

	_grid = GridContainer.new()
	_grid.name = "SfxLabGrid"
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)

	_status_label = Label.new()
	_status_label.name = "SfxLabStatus"
	_status_label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	page_root.add_child(_status_label)

	_playlist_timer = Timer.new()
	_playlist_timer.name = "SfxLabPlaylistTimer"
	_playlist_timer.one_shot = true
	_playlist_timer.wait_time = PLAY_INTERVAL_SECONDS
	_playlist_timer.timeout.connect(_play_next)
	add_child(_playlist_timer)


func _build_tiles() -> void:
	for entry: Dictionary in _catalog:
		var sfx_id: String = String(entry.get("sfx_id", entry.get("id", "")))
		if sfx_id == "":
			continue
		var panel: PanelContainer = PanelContainer.new()
		panel.name = "SfxTile_%s" % sfx_id
		panel.custom_minimum_size = TILE_MINIMUM_SIZE
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", _make_tile_style(String(entry.get("category", "ui"))))
		_grid.add_child(panel)

		var margin: MarginContainer = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		panel.add_child(margin)

		var content: VBoxContainer = VBoxContainer.new()
		content.add_theme_constant_override("separation", 5)
		margin.add_child(content)

		var top_row: HBoxContainer = HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 8)
		content.add_child(top_row)

		var category_label: Label = Label.new()
		category_label.text = _category_label(String(entry.get("category", "ui")))
		category_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		category_label.add_theme_color_override("font_color", _category_color(String(entry.get("category", "ui"))))
		top_row.add_child(category_label)

		var available: bool = bool(entry.get("available", false))
		var play_button: Button = Button.new()
		play_button.name = "Play_%s" % sfx_id
		play_button.text = _localized("再生", "Play")
		play_button.custom_minimum_size = Vector2(76.0, 34.0)
		play_button.disabled = not available
		play_button.pressed.connect(_on_play_pressed.bind(sfx_id, _entry_name(entry)))
		top_row.add_child(play_button)

		var display_name: Label = Label.new()
		display_name.text = _entry_name(entry)
		display_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		display_name.add_theme_font_size_override("font_size", 18)
		content.add_child(display_name)

		var id_label: Label = Label.new()
		id_label.text = sfx_id
		id_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		id_label.add_theme_font_size_override("font_size", 13)
		id_label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED if available else Color(1.0, 0.38, 0.32, 1.0))
		content.add_child(id_label)

		_tiles.append({
			"entry": entry,
			"panel": panel,
			"available": available,
		})


func _apply_filter() -> void:
	var selected_category: String = "all"
	if _category_option.selected >= 0:
		selected_category = String(_category_option.get_item_metadata(_category_option.selected))
	var query: String = _search_edit.text.strip_edges().to_lower()
	var visible_count: int = 0
	var missing_count: int = 0
	for tile: Dictionary in _tiles:
		var entry: Dictionary = Dictionary(tile.get("entry", {}))
		var category: String = String(entry.get("category", ""))
		var haystack: String = ("%s %s" % [
			_entry_name(entry),
			String(entry.get("sfx_id", entry.get("id", ""))),
		]).to_lower()
		var visible: bool = (selected_category == "all" or category == selected_category) and (query == "" or haystack.contains(query))
		var panel: PanelContainer = tile.get("panel") as PanelContainer
		if panel != null:
			panel.visible = visible
		if visible:
			visible_count += 1
			if not bool(tile.get("available", false)):
				missing_count += 1
	_summary_label.text = _localized(
		"登録 %d種 / 表示 %d種 / 未生成 %d種" % [_tiles.size(), visible_count, missing_count],
		"%d registered / %d visible / %d missing" % [_tiles.size(), visible_count, missing_count]
	)
	_play_visible_button.disabled = visible_count <= missing_count


func _on_play_pressed(sfx_id: String, display_name: String) -> void:
	_stop_playlist()
	AudioManager.stop_all_sfx()
	if AudioManager.play_sfx(sfx_id):
		_status_label.text = _localized("再生中: %s (%s)" % [display_name, sfx_id], "Playing: %s (%s)" % [display_name, sfx_id])
	else:
		_status_label.text = _localized("再生できません: %s" % sfx_id, "Unable to play: %s" % sfx_id)


func _on_play_visible_pressed() -> void:
	_stop_playlist()
	AudioManager.stop_all_sfx()
	_playlist_labels.clear()
	_playlist_waits.clear()
	for tile: Dictionary in _tiles:
		var panel: PanelContainer = tile.get("panel") as PanelContainer
		if panel == null or not panel.visible or not bool(tile.get("available", false)):
			continue
		var entry: Dictionary = Dictionary(tile.get("entry", {}))
		var sfx_id: String = String(entry.get("sfx_id", entry.get("id", "")))
		_playlist.append(sfx_id)
		_playlist_labels[sfx_id] = _entry_name(entry)
		_playlist_waits[sfx_id] = maxf(0.4, float(entry.get("seconds", _default_entry_seconds(entry))) + 0.15)
	_playlist_index = 0
	_play_next()


func _play_next() -> void:
	if _playlist_index >= _playlist.size():
		_status_label.text = _localized("表示中のSEをすべて再生しました。", "Finished playing visible SFX.")
		_stop_playlist()
		return
	var sfx_id: String = _playlist[_playlist_index]
	_playlist_index += 1
	AudioManager.play_sfx(sfx_id)
	_status_label.text = _localized(
		"連続再生 %d / %d: %s" % [_playlist_index, _playlist.size(), String(_playlist_labels.get(sfx_id, sfx_id))],
		"Playlist %d / %d: %s" % [_playlist_index, _playlist.size(), String(_playlist_labels.get(sfx_id, sfx_id))]
	)
	_playlist_timer.wait_time = float(_playlist_waits.get(sfx_id, PLAY_INTERVAL_SECONDS))
	_playlist_timer.start()


func _on_stop_pressed() -> void:
	_stop_playlist()
	AudioManager.stop_all_sfx()
	_status_label.text = _localized("再生を停止しました。", "Playback stopped.")


func _stop_playlist() -> void:
	if _playlist_timer != null:
		_playlist_timer.stop()
	_playlist.clear()
	_playlist_labels.clear()
	_playlist_waits.clear()
	_playlist_index = 0


func _on_filter_changed(_index: int) -> void:
	AudioManager.play_sfx("ui_tab")
	_apply_filter()


func _on_search_changed(_text: String) -> void:
	_apply_filter()


func _on_volume_changed(value: float) -> void:
	Game.set_sfx_volume(value)
	_volume_value.text = "%d%%" % int(round(value * 100.0))


func _on_back_pressed() -> void:
	_stop_playlist()
	AudioManager.play_sfx("ui_back")
	SceneRouter.return_from_sfx_lab()


func _entry_name(entry: Dictionary) -> String:
	var language_key: String = "name_ja" if Game.get_language() == "ja" else "name_en"
	return String(entry.get(language_key, entry.get("name_en", entry.get("id", ""))))


func _default_entry_seconds(entry: Dictionary) -> float:
	return 1.0 if String(entry.get("category", "")) == "relic" else 1.15


func _category_label(category: String) -> String:
	var labels: Dictionary = Dictionary(CATEGORY_LABELS.get(category, {"ja": category, "en": category}))
	return String(labels.get("ja" if Game.get_language() == "ja" else "en", category))


func _localized(japanese: String, english: String) -> String:
	return japanese if Game.get_language() == "ja" else english


func _category_color(category: String) -> Color:
	match category:
		"ui":
			return Color(0.42, 0.78, 1.0, 1.0)
		"run":
			return Color(0.48, 0.90, 0.70, 1.0)
		"reward":
			return Color(1.0, 0.76, 0.30, 1.0)
		"online":
			return Color(0.46, 0.90, 0.96, 1.0)
		"battle":
			return Color(1.0, 0.46, 0.32, 1.0)
		"timeline":
			return Color(0.62, 0.74, 1.0, 1.0)
		"status":
			return Color(0.90, 0.62, 0.96, 1.0)
		"result":
			return Color(0.98, 0.86, 0.46, 1.0)
		"card":
			return Color(0.34, 0.68, 1.0, 1.0)
		"relic":
			return Color(1.0, 0.66, 0.26, 1.0)
		_:
			return UiTheme.TEXT_MAIN


func _make_tile_style(category: String) -> StyleBoxFlat:
	var accent: Color = _category_color(category)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.058, 0.94)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0.0, 3.0)
	return style
