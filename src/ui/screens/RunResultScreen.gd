extends Control

const CATEGORY_IDS: Array[String] = ["progress", "survival", "efficiency", "challenge"]
const CATEGORY_COLORS: Array[Color] = [
	Color(0.22, 0.68, 1.0, 1.0),
	Color(0.18, 0.86, 0.58, 1.0),
	Color(1.0, 0.66, 0.20, 1.0),
	Color(0.96, 0.32, 0.34, 1.0),
]
const RANK_COLORS: Dictionary = {
	"S": Color(1.0, 0.82, 0.30, 1.0),
	"A": Color(0.32, 0.88, 1.0, 1.0),
	"B": Color(0.42, 0.88, 0.62, 1.0),
	"C": Color(0.78, 0.82, 0.88, 1.0),
	"D": Color(0.78, 0.58, 0.40, 1.0),
	"E": Color(0.58, 0.48, 0.48, 1.0),
}

var _summary_data: Dictionary = {}
var _category_rows: Array[Dictionary] = []
var _total_score_label: Label
var _rank_label: Label
var _rank_caption: Label
var _rank_panel: PanelContainer
var _skip_hint: Label
var _score_tween: Tween
var _animation_complete: bool = false
var _rank_revealed: bool = false
var _developer_panel: DeveloperPanel


func _ready() -> void:
	_summary_data = Game.get_run_summary()
	_build_background()
	_build_ui()
	_start_score_animation()
	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _unhandled_input(event: InputEvent) -> void:
	if _animation_complete:
		return
	var should_skip: bool = false
	if event is InputEventKey:
		should_skip = (event as InputEventKey).pressed
	elif event is InputEventMouseButton:
		should_skip = (event as InputEventMouseButton).pressed
	if should_skip:
		_finish_score_animation()
		get_viewport().set_input_as_handled()


func _build_background() -> void:
	var background: TextureRect = TextureRect.new()
	background.name = "ResultBackground"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.texture = _build_background_texture()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(background)

	var top_line: ColorRect = ColorRect.new()
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_line.color = Color(0.18, 0.68, 1.0, 0.72)
	top_line.anchor_right = 1.0
	top_line.offset_bottom = 3.0
	add_child(top_line)

	var glow: ColorRect = ColorRect.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.color = Color(0.10, 0.42, 0.68, 0.10)
	glow.anchor_left = 0.08
	glow.anchor_top = 0.12
	glow.anchor_right = 0.92
	glow.anchor_bottom = 0.88
	add_child(glow)


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "ResultContentMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "ResultContent"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	_build_header(root)

	var body: HBoxContainer = HBoxContainer.new()
	body.name = "ResultBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	root.add_child(body)

	_build_score_panel(body)
	_build_detail_panel(body)
	_build_footer(root)


func _build_header(parent: VBoxContainer) -> void:
	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(header)

	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 1)
	header.add_child(title_box)

	var eyebrow: Label = Label.new()
	eyebrow.text = Localization.get_text("result.eyebrow", "OPERATION REPORT")
	eyebrow.add_theme_color_override("font_color", Color(0.34, 0.72, 0.96, 1.0))
	eyebrow.add_theme_font_size_override("font_size", 14)
	title_box.add_child(eyebrow)

	var title: Label = Label.new()
	title.name = "ResultTitle"
	title.text = Localization.get_text("result.title", "Run Result")
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
	title_box.add_child(title)

	var status: Label = Label.new()
	status.text = Localization.get_text(
		"result.status.clear" if bool(_summary_data.get("cleared", false)) else "result.status.ended",
		"MISSION CLEAR" if bool(_summary_data.get("cleared", false)) else "RUN ENDED"
	)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 20)
	status.add_theme_color_override(
		"font_color",
		Color(1.0, 0.78, 0.28, 1.0) if bool(_summary_data.get("cleared", false)) else Color(0.96, 0.38, 0.38, 1.0)
	)
	header.add_child(status)


func _build_score_panel(parent: HBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "ResultScorePanel"
	panel.custom_minimum_size = Vector2(660.0, 0.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.65
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.045, 0.065, 0.97), Color(0.16, 0.48, 0.68, 0.85), 2))
	parent.add_child(panel)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	panel.add_child(content)

	var heading: Label = Label.new()
	heading.text = Localization.get_text("result.score.breakdown", "SCORE BREAKDOWN")
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color(0.72, 0.84, 0.92, 1.0))
	content.add_child(heading)

	for index in range(CATEGORY_IDS.size()):
		_build_score_row(content, index)

	var divider: HSeparator = HSeparator.new()
	content.add_child(divider)

	var total_row: HBoxContainer = HBoxContainer.new()
	total_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(total_row)

	var total_caption: Label = Label.new()
	total_caption.text = Localization.get_text("result.score.total", "TOTAL SCORE")
	total_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_caption.add_theme_font_size_override("font_size", 21)
	total_caption.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	total_row.add_child(total_caption)

	_total_score_label = Label.new()
	_total_score_label.name = "ResultTotalScore"
	_total_score_label.text = "0 / %s" % _format_score(int(_summary_data.get("max_score", 10000)))
	_total_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_total_score_label.add_theme_font_size_override("font_size", 30)
	_total_score_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28, 1.0))
	total_row.add_child(_total_score_label)

	_skip_hint = Label.new()
	_skip_hint.text = Localization.get_text("result.score.skip_hint", "Click or press a key to skip")
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.add_theme_font_size_override("font_size", 13)
	_skip_hint.add_theme_color_override("font_color", Color(0.52, 0.62, 0.70, 1.0))
	content.add_child(_skip_hint)


func _build_score_row(parent: VBoxContainer, index: int) -> void:
	var category_id: String = CATEGORY_IDS[index]
	var max_points: int = int(_summary_data.get("%s_max" % category_id, 0))
	var row: VBoxContainer = VBoxContainer.new()
	row.name = "ResultScoreRow_%s" % category_id
	row.modulate = Color(1.0, 1.0, 1.0, 0.34)
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)

	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(header)

	var label: Label = Label.new()
	label.text = Localization.get_text("result.score.%s" % category_id, category_id.capitalize())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", CATEGORY_COLORS[index].lightened(0.18))
	header.add_child(label)

	var score_label: Label = Label.new()
	score_label.name = "ResultScoreValue_%s" % category_id
	score_label.text = "0 / %s" % _format_score(max_points)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 17)
	header.add_child(score_label)

	var bar: ProgressBar = ProgressBar.new()
	bar.name = "ResultScoreBar_%s" % category_id
	bar.custom_minimum_size.y = 20.0
	bar.min_value = 0.0
	bar.max_value = float(max_points)
	bar.value = 0.0
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.03, 0.055, 0.072, 1.0), Color(0.12, 0.20, 0.25, 1.0)))
	bar.add_theme_stylebox_override("fill", _make_bar_style(CATEGORY_COLORS[index].darkened(0.22), CATEGORY_COLORS[index]))
	row.add_child(bar)

	_category_rows.append({
		"id": category_id,
		"row": row,
		"bar": bar,
		"score_label": score_label,
		"points": int(_summary_data.get(category_id, 0)),
		"max_points": max_points,
	})


func _build_detail_panel(parent: HBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "ResultDetailPanel"
	panel.custom_minimum_size = Vector2(390.0, 0.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.042, 0.055, 0.97), Color(0.25, 0.29, 0.36, 0.95), 1))
	parent.add_child(panel)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

	_rank_panel = PanelContainer.new()
	_rank_panel.name = "ResultRankPanel"
	_rank_panel.custom_minimum_size.y = 174.0
	_rank_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_rank_panel.add_theme_stylebox_override("panel", _make_rank_style())
	content.add_child(_rank_panel)

	var rank_box: VBoxContainer = VBoxContainer.new()
	rank_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_rank_panel.add_child(rank_box)

	_rank_caption = Label.new()
	_rank_caption.text = Localization.get_text("result.score.rank", "RANK")
	_rank_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_caption.add_theme_font_size_override("font_size", 16)
	_rank_caption.add_theme_color_override("font_color", Color(0.66, 0.74, 0.80, 1.0))
	rank_box.add_child(_rank_caption)

	_rank_label = Label.new()
	_rank_label.name = "ResultRankLabel"
	_rank_label.text = "?"
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_label.add_theme_font_size_override("font_size", 92)
	_rank_label.add_theme_color_override("font_color", Color(0.48, 0.56, 0.62, 1.0))
	rank_box.add_child(_rank_label)

	var detail_heading: Label = Label.new()
	detail_heading.text = Localization.get_text("result.details", "RUN DETAILS")
	detail_heading.add_theme_font_size_override("font_size", 17)
	detail_heading.add_theme_color_override("font_color", Color(0.72, 0.84, 0.92, 1.0))
	content.add_child(detail_heading)

	var summary: RichTextLabel = RichTextLabel.new()
	summary.name = "ResultSummary"
	summary.fit_content = true
	summary.bbcode_enabled = true
	summary.text = _build_summary_text()
	content.add_child(summary)

	var relic_ids: Array[String] = _to_string_array(_summary_data.get("relic_ids", []))
	var relic_icon_row: RelicIconRow = RelicIconRow.new()
	relic_icon_row.name = "ResultRelicIconRow"
	relic_icon_row.set_icon_size(Vector2(48.0, 48.0))
	relic_icon_row.refresh_relic_ids(relic_ids)
	content.add_child(relic_icon_row)


func _build_footer(parent: VBoxContainer) -> void:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.name = "ResultActions"
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	parent.add_child(footer)

	var replay_button: Button = Button.new()
	replay_button.name = "ResultReplayViewerButton"
	replay_button.text = Localization.get_text("result.view_replay", "View Replay")
	replay_button.disabled = Game.get_last_replay_export_path() == ""
	replay_button.pressed.connect(_on_open_replay_viewer)
	footer.add_child(replay_button)

	var retry_button: Button = Button.new()
	retry_button.name = "ResultRetrySameSeedButton"
	retry_button.text = Localization.get_text("result.retry", "Retry Same Seed")
	retry_button.disabled = not Game.can_retry_last_seed_run()
	retry_button.pressed.connect(_on_retry_same_seed)
	footer.add_child(retry_button)

	var hub_button: Button = Button.new()
	hub_button.name = "ResultReturnHubButton"
	hub_button.text = Localization.get_text("result.return_hub", "Return to Hub")
	hub_button.pressed.connect(_on_return_to_hub)
	footer.add_child(hub_button)


func _build_summary_text() -> String:
	var relic_names: Array = Array(_summary_data.get("relic_names", []))
	var relic_text: String = Localization.get_text("status.none", "None")
	if not relic_names.is_empty():
		relic_text = ", ".join(relic_names)
	return "\n".join([
		Localization.get_textf("result.summary.starter", "Starter: {value}", {
			"value": String(_summary_data.get("starter_name", _summary_data.get("starter_id", ""))),
		}),
		Localization.get_textf("result.summary.seed", "Seed: {value}", {"value": int(_summary_data.get("seed", 0))}),
		Localization.get_textf("result.summary.area", "Reached Area: {value}", {"value": int(_summary_data.get("current_area", 0))}),
		Localization.get_textf("result.summary.encounters", "Encounters Cleared: {value}", {"value": int(_summary_data.get("encounters_cleared", 0))}),
		Localization.get_textf("result.summary.hp_detail", "HP: {current} / {maximum}", {
			"current": int(_summary_data.get("remaining_hp", 0)),
			"maximum": Game.current_run.max_hp if Game.current_run != null else 0,
		}),
		Localization.get_textf("result.summary.battle_time", "Battle Time: {value}s", {
			"value": "%.1f" % float(_summary_data.get("total_battle_time", 0.0)),
		}),
		Localization.get_textf("result.summary.damage_taken", "HP Damage Taken: {value}", {
			"value": int(_summary_data.get("hp_damage_taken", 0)),
		}),
		Localization.get_textf("result.summary.gold", "Gold: {value}", {"value": int(_summary_data.get("gold", 0))}),
		Localization.get_textf("result.summary.relics", "Relics ({count}): {value}", {
			"count": int(_summary_data.get("relic_count", 0)),
			"value": relic_text,
		}),
	])


func _start_score_animation() -> void:
	_score_tween = create_tween()
	_score_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_score_tween.tween_interval(0.35)
	for index in range(_category_rows.size()):
		_score_tween.tween_callback(_activate_category.bind(index))
		_score_tween.tween_method(
			_set_category_progress.bind(index),
			0.0,
			float(int(_category_rows[index].get("points", 0))),
			0.62
		).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_score_tween.tween_interval(0.08)
	_score_tween.tween_method(
		_set_total_progress,
		0.0,
		float(int(_summary_data.get("total_score", 0))),
		0.78
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_score_tween.tween_callback(_reveal_rank)


func _activate_category(index: int) -> void:
	if index < 0 or index >= _category_rows.size():
		return
	var row: Control = _category_rows[index].get("row") as Control
	if row != null:
		row.modulate = Color.WHITE
	AudioManager.play_sfx("battle_tick", 0.82 + float(index) * 0.08, -5.0)


func _set_category_progress(value: float, index: int) -> void:
	if index < 0 or index >= _category_rows.size():
		return
	var entry: Dictionary = _category_rows[index]
	var bar: ProgressBar = entry.get("bar") as ProgressBar
	var score_label: Label = entry.get("score_label") as Label
	var display_value: int = roundi(value)
	if bar != null:
		bar.value = value
	if score_label != null:
		score_label.text = "%s / %s" % [
			_format_score(display_value),
			_format_score(int(entry.get("max_points", 0))),
		]


func _set_total_progress(value: float) -> void:
	_total_score_label.text = "%s / %s" % [
		_format_score(roundi(value)),
		_format_score(int(_summary_data.get("max_score", 10000))),
	]


func _reveal_rank() -> void:
	if _rank_revealed:
		return
	_rank_revealed = true
	_animation_complete = true
	_skip_hint.visible = false
	var rank: String = String(_summary_data.get("rank", "E"))
	var rank_color: Color = Color(RANK_COLORS.get(rank, Color.WHITE))
	_rank_label.text = rank
	_rank_label.add_theme_color_override("font_color", rank_color)
	_rank_panel.add_theme_stylebox_override("panel", _make_rank_style(rank_color))
	var reveal: Tween = create_tween()
	reveal.set_parallel(true)
	reveal.tween_property(_rank_panel, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rank_panel.scale = Vector2(0.84, 0.84)
	reveal.tween_property(_rank_panel, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioManager.play_sfx("battle_victory" if bool(_summary_data.get("cleared", false)) else "battle_defeat", 1.0, -2.0)


func _finish_score_animation() -> void:
	if _animation_complete:
		return
	if _score_tween != null and _score_tween.is_valid():
		_score_tween.kill()
	for index in range(_category_rows.size()):
		var row: Control = _category_rows[index].get("row") as Control
		if row != null:
			row.modulate = Color.WHITE
		_set_category_progress(float(int(_category_rows[index].get("points", 0))), index)
	_set_total_progress(float(int(_summary_data.get("total_score", 0))))
	_reveal_rank()


func _format_score(value: int) -> String:
	var text: String = str(maxi(0, value))
	var result: String = ""
	while text.length() > 3:
		result = ",%s%s" % [text.right(3), result]
		text = text.left(text.length() - 3)
	return "%s%s" % [text, result]


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for raw_value in Array(value):
		result.append(String(raw_value))
	return result


func _make_panel_style(fill_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(18)
	style.content_margin_left = 24.0
	style.content_margin_top = 20.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 20.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0.0, 6.0)
	return style


func _make_bar_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	return style


func _make_rank_style(accent: Color = Color(0.24, 0.46, 0.62, 1.0)) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.026, 0.038, 0.98)
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.18)
	style.shadow_size = 10
	return style


func _build_background_texture() -> Texture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.48, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.012, 0.026, 0.042, 1.0),
		Color(0.028, 0.055, 0.078, 1.0),
		Color(0.025, 0.026, 0.038, 1.0),
	])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 1.0)
	return texture


func _on_return_to_hub() -> void:
	Game.abandon_run_to_hub()
	SceneRouter.go_to_hub()


func _on_open_replay_viewer() -> void:
	if not Game.open_last_replay_view("result"):
		AudioManager.play_sfx("ui_error")
		return
	SceneRouter.go_to_replay_viewer()


func _on_retry_same_seed() -> void:
	if not Game.retry_last_seed_run():
		AudioManager.play_sfx("ui_error")
		return
	SceneRouter.go_to_map()


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right()
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevFinishScoreAnimation", "label": Localization.get_text("result.dev.finish_score", "Finish Score Animation"), "callback": Callable(self, "_finish_score_animation")},
			{"id": "DevRestartRun", "label": Localization.get_text("result.dev.restart", "Restart Run"), "callback": Callable(self, "_on_dev_restart_run")},
			{"id": "DevOpenBattle", "label": Localization.get_text("hub.dev.open_battle", "Open Battle"), "callback": Callable(self, "_on_dev_open_battle")},
			{"id": "DevExportReplay", "label": Localization.get_text("reward.dev.export_replay", "Export Replay"), "callback": Callable(self, "_on_dev_export_replay")},
			{"id": "DevOpenReplay", "label": Localization.get_text("reward.dev.open_replay", "Open Replay"), "callback": Callable(self, "_on_open_replay_viewer")},
		],
		Localization.get_text("result.dev.summary", "Jump out of the result screen quickly while testing.")
	)


func _on_dev_restart_run() -> void:
	_on_retry_same_seed()


func _on_dev_open_battle() -> void:
	Game.developer_open_battle("scout")
	SceneRouter.go_to_battle()


func _on_dev_export_replay() -> void:
	Game.export_last_battle_replay()
