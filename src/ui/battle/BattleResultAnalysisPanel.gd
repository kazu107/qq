extends ColorRect
class_name BattleResultAnalysisPanel

signal continue_requested()
signal replay_requested()

const LOCAL_COLOR := Color("59d6ff")
const OPPONENT_COLOR := Color("ff786e")
var _title: Label
var _result_modal: PanelContainer
var _details_modal: PanelContainer
var _metrics: GridContainer
var _hp_chart: BattleHpChart
var _card_rows: VBoxContainer
var _replay_button: Button
var _summary: Dictionary = {}
var _analysis: Dictionary = {}
var _local_side: String = "player"
var _metric: String = "damage"
var _return_to_result: bool = true
var _metric_buttons: Dictionary = {}
var _duration: Label
var _hp_legend: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_game_theme()
	color = Color(0.006, 0.012, 0.020, 0.76)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 180
	_build_ui()
	resized.connect(_layout_modals)
	_layout_modals()
	visible = false


func show_result(summary: Dictionary, local_side: String, spectator: bool, replay_available: bool) -> void:
	_set_summary(summary, local_side)
	_return_to_result = true
	var winner: String = String(summary.get("winner", "draw"))
	var outcome: String = Localization.get_text("battle.result.draw", "Draw")
	var outcome_color: Color = Color(0.84, 0.88, 0.92)
	if spectator:
		outcome = Localization.get_text("online.battle.match_complete", "MATCH COMPLETE")
	elif winner == _local_side:
		outcome = Localization.get_text("battle.result.victory", "Victory")
		outcome_color = Color(0.30, 1.0, 0.62)
	elif winner != "draw":
		outcome = Localization.get_text("battle.result.defeat", "Defeat")
		outcome_color = Color(1.0, 0.36, 0.32)
	_title.text = outcome
	_title.add_theme_color_override("font_color", outcome_color)
	_replay_button.visible = replay_available
	_result_modal.show()
	_details_modal.hide()
	visible = true
	_layout_modals()


func show_details(summary: Dictionary = {}, local_side: String = "player") -> void:
	if not summary.is_empty():
		_set_summary(summary, local_side)
		_return_to_result = false
	_refresh_details()
	_result_modal.hide()
	_details_modal.show()
	show()
	_layout_modals()


func close_details() -> void:
	_details_modal.hide()
	if _return_to_result:
		_result_modal.show()
	else:
		hide()


func set_replay_available(available: bool) -> void:
	_replay_button.visible = available


func _set_summary(summary: Dictionary, local_side: String) -> void:
	_summary = summary.duplicate(false)
	_analysis = Dictionary(_summary.get("analysis", {}))
	if _analysis.is_empty() and _summary.has("battle_events"):
		_analysis = BattleAnalysis.from_events(Array(_summary["battle_events"]))
	_summary.erase("battle_events")
	_summary.erase("visual_replay")
	_local_side = "enemy" if local_side == "enemy" else "player"


func _build_ui() -> void:
	_result_modal = PanelContainer.new()
	_result_modal.name = "BattleOutcomeModal"
	add_child(_result_modal)
	var root: VBoxContainer = _padded_root(_result_modal)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 22)
	_title = Label.new()
	_title.name = "BattleOutcomeTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 48)
	root.add_child(_title)
	var secondary: HBoxContainer = HBoxContainer.new()
	secondary.alignment = BoxContainer.ALIGNMENT_CENTER
	secondary.add_theme_constant_override("separation", 12)
	root.add_child(secondary)
	var details: Button = _button(secondary, "BattleDetailsButton", _text("details", "Battle details"), show_details)
	details.custom_minimum_size.x = 190.0
	_replay_button = _button(secondary, "BattleReplayButton", _text("replay", "WATCH REPLAY"), func() -> void: replay_requested.emit())
	var next: Button = _button(root, "BattleContinueButton", _text("continue", "CONTINUE"), func() -> void: continue_requested.emit())
	next.theme_type_variation = &"PrimaryButton"
	next.custom_minimum_size.y = 52.0
	_details_modal = PanelContainer.new()
	_details_modal.name = "BattleDetailsModal"
	add_child(_details_modal)
	var details_root: VBoxContainer = _padded_root(_details_modal)
	var heading: HBoxContainer = HBoxContainer.new()
	details_root.add_child(heading)
	var title: Label = Label.new()
	title.text = _text("details", "Battle details")
	title.theme_type_variation = &"SectionTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_button(heading, "BattleDetailsClose", _text("close", "Back"), close_details)
	_duration = Label.new()
	_duration.theme_type_variation = &"MutedLabel"
	details_root.add_child(_duration)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "BattleDetailsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_root.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	scroll.add_child(content)
	_section_heading(content, _text("comparison", "Combat comparison"))
	_metrics = GridContainer.new()
	_metrics.name = "BattleComparisonTable"
	_metrics.columns = 3
	_metrics.add_theme_constant_override("h_separation", 30)
	_metrics.add_theme_constant_override("v_separation", 9)
	content.add_child(_metrics)
	content.add_child(HSeparator.new())
	_section_heading(content, _text("hp_history", "HP over time"))
	_hp_legend = HBoxContainer.new()
	_hp_legend.alignment = BoxContainer.ALIGNMENT_CENTER
	_hp_legend.add_theme_constant_override("separation", 28)
	content.add_child(_hp_legend)
	_hp_chart = BattleHpChart.new()
	_hp_chart.name = "BattleHpHistoryChart"
	_hp_chart.custom_minimum_size.y = 250.0
	content.add_child(_hp_chart)
	content.add_child(HSeparator.new())
	_section_heading(content, _text("contributions", "Card contributions"))
	var selectors: HBoxContainer = HBoxContainer.new()
	selectors.add_theme_constant_override("separation", 8)
	content.add_child(selectors)
	for metric: String in ["damage", "heal", "shield", "absorbed"]:
		var button: Button = _button(selectors, "Contribution_" + metric, _metric_name(metric), _select_metric.bind(metric))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_metric_buttons[metric] = button
	_card_rows = VBoxContainer.new()
	_card_rows.name = "BattleCardContributions"
	_card_rows.add_theme_constant_override("separation", 8)
	content.add_child(_card_rows)
	var note: Label = Label.new()
	note.text = _text("definition", "Damage is actual HP lost (excluding overkill); healing excludes overheal. Card bars show direct effects only. Status, relic, fatigue, and self-damage are not attributed to a card. Shield decay and shield costs are not blocked damage.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = &"MutedLabel"
	content.add_child(note)
	_details_modal.hide()


func _layout_modals() -> void:
	if _result_modal == null:
		return
	_result_modal.size = Vector2(minf(530.0, size.x - 48.0), 248.0)
	_result_modal.position = (size - _result_modal.size) * 0.5
	_details_modal.size = Vector2(minf(1020.0, size.x - 48.0), minf(900.0, size.y - 48.0))
	_details_modal.position = (size - _details_modal.size) * 0.5


func _padded_root(panel: PanelContainer) -> VBoxContainer:
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	panel.add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	return box


func _button(parent: Control, node_name: String, caption: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size.y = 44.0
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _section_heading(parent: Control, caption: String) -> void:
	var label: Label = Label.new()
	label.text = caption
	label.theme_type_variation = &"SectionTitle"
	parent.add_child(label)


func _refresh_details() -> void:
	_clear_children(_metrics)
	_duration.text = Localization.get_textf("battle.analysis.duration", "Battle time {seconds}s", {"seconds": "%.1f" % float(_summary.get("battle_time", 0.0))})
	var totals: Dictionary = BattleAnalysis.get_totals(_analysis)
	var opponent: String = "enemy" if _local_side == "player" else "player"
	_cell(_text("metric", "Metric"), Color.WHITE)
	_cell(_side_name(_local_side), LOCAL_COLOR)
	_cell(_side_name(opponent), OPPONENT_COLOR)
	for metric: String in ["damage", "absorbed", "damage_taken", "blocked", "shield", "heal", "casts"]:
		_cell(_metric_name(metric), UiTheme.TEXT_MUTED)
		for side: String in [_local_side, opponent]:
			var value: int = int(Dictionary(totals.get(side, {})).get(metric, 0))
			if metric == "casts":
				value = 0
				for row: Dictionary in Array(_analysis.get("cards", [])):
					if String(row.get("actor", "")) == side:
						value += int(row.get("casts", 0))
			_cell(str(value), LOCAL_COLOR if side == _local_side else OPPONENT_COLOR)
	_clear_children(_hp_legend)
	for side: String in [_local_side, opponent]:
		var label: Label = Label.new()
		label.text = _side_name(side)
		label.add_theme_color_override("font_color", LOCAL_COLOR if side == _local_side else OPPONENT_COLOR)
		_hp_legend.add_child(label)
	_hp_chart.set_history(Array(_analysis.get("hp_history", [])), _local_side, float(_summary.get("battle_time", 0.0)))
	_select_metric(_metric)


func _cell(caption: String, tint: Color) -> void:
	var label: Label = Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", tint)
	if _metrics.get_child_count() % 3 != 0:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_metrics.add_child(label)


func _select_metric(metric: String) -> void:
	_metric = metric
	for key: String in _metric_buttons:
		(_metric_buttons[key] as Button).set_pressed_no_signal(key == metric)
	_clear_children(_card_rows)
	for side: String in [_local_side, "enemy" if _local_side == "player" else "player"]:
		var tint: Color = LOCAL_COLOR if side == _local_side else OPPONENT_COLOR
		var heading: Label = Label.new()
		heading.text = _side_name(side)
		heading.add_theme_color_override("font_color", tint)
		_card_rows.add_child(heading)
		var rows: Array[Dictionary] = []
		var total: int = 0
		for row: Dictionary in Array(_analysis.get("cards", [])):
			if String(row.get("actor", "")) == side and int(row.get(metric, 0)) > 0:
				rows.append(row)
				total += int(row.get(metric, 0))
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get(metric, 0)) > int(b.get(metric, 0)))
		if rows.is_empty():
			var empty: Label = Label.new()
			empty.text = _text("no_contribution", "No contribution recorded for this metric.")
			empty.theme_type_variation = &"MutedLabel"
			_card_rows.add_child(empty)
		for row: Dictionary in rows:
			_add_contribution(row, total, tint)


func _add_contribution(row: Dictionary, total: int, tint: Color) -> void:
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	_card_rows.add_child(line)
	var card: CardDef = Database.get_card(String(row.get("card_id", "")))
	var label: Label = Label.new()
	label.text = card.name if card != null else String(row.get("card_id", ""))
	label.custom_minimum_size.x = 230.0
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(label)
	var value: int = int(row.get(_metric, 0))
	var bar: ProgressBar = ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = maxi(1, total)
	bar.value = value
	bar.custom_minimum_size.y = 22.0
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", _bar_style(Color("182b36")))
	bar.add_theme_stylebox_override("fill", _bar_style(tint))
	line.add_child(bar)
	var amount: Label = Label.new()
	amount.text = "%d  (%d%%)" % [value, roundi(float(value) / maxi(1, total) * 100.0)]
	amount.custom_minimum_size.x = 115.0
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.add_theme_color_override("font_color", tint)
	line.add_child(amount)
	line.tooltip_text = "%s: %d / %d" % [_metric_name(_metric), value, total]


func _bar_style(tint: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = tint
	style.set_corner_radius_all(5)
	return style


func _side_name(side: String) -> String:
	var combatant: Dictionary = Dictionary(Dictionary(_analysis.get("combatants", {})).get(side, {}))
	var fallback: String = _text("you", "YOU") if side == _local_side else _text("opponent", "OPPONENT")
	return String(combatant.get("name", fallback))


func _metric_name(metric: String) -> String:
	var fallback: Dictionary = {"damage": "HP damage dealt", "absorbed": "Shield damage dealt", "damage_taken": "HP damage taken", "blocked": "Damage blocked", "shield": "Shield gained", "heal": "HP restored", "casts": "Cards resolved"}
	return _text("stat_" + metric, String(fallback.get(metric, metric)))


func _text(key: String, fallback: String) -> String:
	return Localization.get_text("battle.analysis." + key, fallback)


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
