extends ColorRect
class_name BattleResultAnalysisPanel

signal continue_requested()
signal replay_requested()

var _title: Label
var _subtitle: Label
var _metrics: VBoxContainer
var _cards: RichTextLabel
var _continue_button: Button
var _replay_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.006, 0.012, 0.020, 0.90)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 180
	_build_ui()
	visible = false


func show_result(summary: Dictionary, local_side: String, spectator: bool, replay_available: bool) -> void:
	var winner: String = String(summary.get("winner", "draw"))
	var outcome: String = Localization.get_text("battle.result.draw", "Draw")
	var outcome_color: Color = Color(0.84, 0.88, 0.92)
	if spectator:
		outcome = Localization.get_text("online.battle.match_complete", "MATCH COMPLETE")
	elif winner == local_side:
		outcome = Localization.get_text("battle.result.victory", "Victory")
		outcome_color = Color(0.30, 1.0, 0.62)
	elif winner != "draw":
		outcome = Localization.get_text("battle.result.defeat", "Defeat")
		outcome_color = Color(1.0, 0.36, 0.32)
	_title.text = outcome
	_title.add_theme_color_override("font_color", outcome_color)
	_subtitle.text = Localization.get_textf("battle.analysis.duration", "Battle time {seconds}s", {
		"seconds": "%.1f" % float(summary.get("battle_time", 0.0)),
	})
	_refresh_metrics(Dictionary(summary.get("analysis", {})), local_side)
	_replay_button.visible = replay_available
	visible = true


func set_replay_available(available: bool) -> void:
	_replay_button.visible = available


func _build_ui() -> void:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var modal: PanelContainer = PanelContainer.new()
	modal.custom_minimum_size = Vector2(760.0, 590.0)
	center.add_child(modal)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	modal.add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 38)
	root.add_child(_title)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", Color(0.66, 0.76, 0.84))
	root.add_child(_subtitle)
	root.add_child(HSeparator.new())
	_metrics = VBoxContainer.new()
	_metrics.add_theme_constant_override("separation", 10)
	root.add_child(_metrics)
	var card_heading: Label = Label.new()
	card_heading.text = Localization.get_text("battle.analysis.top_cards", "Key cards")
	card_heading.add_theme_font_size_override("font_size", 21)
	root.add_child(card_heading)
	_cards = RichTextLabel.new()
	_cards.bbcode_enabled = true
	_cards.fit_content = false
	_cards.custom_minimum_size = Vector2(0.0, 178.0)
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_cards)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)
	_replay_button = Button.new()
	_replay_button.custom_minimum_size = Vector2(220.0, 50.0)
	_replay_button.text = Localization.get_text("battle.analysis.replay", "WATCH REPLAY")
	_replay_button.pressed.connect(func() -> void: replay_requested.emit())
	actions.add_child(_replay_button)
	_continue_button = Button.new()
	_continue_button.custom_minimum_size = Vector2(260.0, 50.0)
	_continue_button.text = Localization.get_text("battle.analysis.continue", "CONTINUE")
	_continue_button.pressed.connect(func() -> void: continue_requested.emit())
	actions.add_child(_continue_button)


func _refresh_metrics(analysis: Dictionary, local_side: String) -> void:
	for child: Node in _metrics.get_children():
		child.queue_free()
	var totals: Dictionary = {
		"player": {"damage": 0, "shield": 0, "heal": 0},
		"enemy": {"damage": 0, "shield": 0, "heal": 0},
	}
	var rows: Array[Dictionary] = []
	for raw_row: Variant in Array(analysis.get("cards", [])):
		var row: Dictionary = Dictionary(raw_row)
		rows.append(row)
		var actor: String = String(row.get("actor", ""))
		if not totals.has(actor):
			continue
		for metric: String in ["damage", "shield", "heal"]:
			totals[actor][metric] = int(totals[actor][metric]) + int(row.get(metric, 0))
	var resolved_local_side: String = local_side if totals.has(local_side) else "player"
	var opponent_side: String = "enemy" if resolved_local_side == "player" else "player"
	for metric: String in ["damage", "shield", "heal"]:
		_add_metric_row(metric, int(totals[resolved_local_side][metric]), int(totals[opponent_side][metric]))
	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _row_score(left) > _row_score(right)
	)
	var lines: PackedStringArray = []
	for index in range(mini(6, rows.size())):
		var row: Dictionary = rows[index]
		var card: CardDef = Database.get_card(String(row.get("card_id", "")))
		var owner: String = Localization.get_text("battle.analysis.you", "YOU") if String(row.get("actor", "")) == resolved_local_side else Localization.get_text("battle.analysis.opponent", "OPPONENT")
		lines.append("[color=%s][b]%s[/b][/color]  %s  [color=#93a8b5]x%d[/color]  DMG %d  SH %d  HEAL %d" % [
			"#59d6ff" if String(row.get("actor", "")) == resolved_local_side else "#ff6961",
			owner,
			card.name if card != null else String(row.get("card_id", "")),
			int(row.get("casts", 0)),
			int(row.get("damage", 0)),
			int(row.get("shield", 0)),
			int(row.get("heal", 0)),
		])
	_cards.text = "\n".join(lines) if not lines.is_empty() else Localization.get_text("battle.analysis.no_cards", "No card actions were recorded.")


func _add_metric_row(metric: String, local_value: int, opponent_value: int) -> void:
	var row: VBoxContainer = VBoxContainer.new()
	_metrics.add_child(row)
	var caption: Label = Label.new()
	caption.text = "%s    %d  :  %d" % [_metric_name(metric), local_value, opponent_value]
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(caption)
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 4)
	row.add_child(split)
	var maximum: float = float(maxi(1, maxi(local_value, opponent_value)))
	var local_bar: ProgressBar = ProgressBar.new()
	local_bar.show_percentage = false
	local_bar.max_value = maximum
	local_bar.value = local_value
	local_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	local_bar.custom_minimum_size.y = 14.0
	split.add_child(local_bar)
	var enemy_bar: ProgressBar = ProgressBar.new()
	enemy_bar.show_percentage = false
	enemy_bar.max_value = maximum
	enemy_bar.value = opponent_value
	enemy_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_bar.custom_minimum_size.y = 14.0
	split.add_child(enemy_bar)


func _metric_name(metric: String) -> String:
	match metric:
		"damage": return Localization.get_text("battle.analysis.damage", "DAMAGE")
		"shield": return Localization.get_text("battle.analysis.shield", "SHIELD")
		"heal": return Localization.get_text("battle.analysis.heal", "HEAL")
	return metric.to_upper()


func _row_score(row: Dictionary) -> int:
	return int(row.get("damage", 0)) + int(row.get("shield", 0)) + int(row.get("heal", 0)) + int(row.get("casts", 0))
