extends Control

var _starter: OptionButton
var _enemy: OptionButton
var _count: SpinBox
var _limit: SpinBox
var _seed: SpinBox
var _progress: ProgressBar
var _output: RichTextLabel
var _start: Button
var _replay: Button
var _cards: Array[String] = []
var _compare_cards: Array[String] = []
var _compare_toggle: CheckButton
var _compare_row: HBoxContainer
var _compare_presets: DeckPresetBar
var _compare_starter: OptionButton
var _compare_enemy: OptionButton
var _simulation: BattleSimulation
var _completed: int = 0
var _wins: int = 0
var _draws: int = 0
var _unresolved: int = 0
var _duration: float = 0.0
var _running: bool = false
var _run: RunState
var _enemy_id: String
var _total: int
var _cap: float
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_summary: Dictionary = {}
var _aggregate: Dictionary = {}
var _configuration_index: int = 0
var _reports: Array[Dictionary] = []


func _ready() -> void:
	if not Game.is_developer_mode_enabled():
		SceneRouter.go_to_hub()
		return
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var title: Label = Label.new()
	title.text = Localization.get_text("analysis.lab", "Automated battle lab")
	root.add_child(title)
	var note: Label = Label.new()
	note.text = Localization.get_text("analysis.lab_note", "Bot estimates, not human win rates. No run progress or rewards are changed. The time cap is for simulations only.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)
	var row: HBoxContainer = HBoxContainer.new()
	root.add_child(row)
	_starter = _option(row, Game.get_debug_battle_starter_entries())
	_enemy = _option(row, Game.get_debug_battle_enemy_entries())
	var presets: DeckPresetBar = DeckPresetBar.new()
	presets.get_cards = func() -> Array[String]: return _cards
	presets.apply_requested.connect(func(cards: Array[String]) -> void: _cards = cards.duplicate())
	root.add_child(presets)
	_starter.item_selected.connect(func(_i: int) -> void: _select_starter())
	_select_starter()
	_compare_toggle = CheckButton.new()
	_compare_toggle.text = Localization.get_text("analysis.compare", "Compare A/B with the same seeds")
	_compare_toggle.toggled.connect(_set_compare_visible)
	root.add_child(_compare_toggle)
	_compare_row = HBoxContainer.new()
	root.add_child(_compare_row)
	_compare_starter = _option(_compare_row, Game.get_debug_battle_starter_entries())
	_compare_enemy = _option(_compare_row, Game.get_debug_battle_enemy_entries())
	_compare_presets = DeckPresetBar.new()
	_compare_presets.get_cards = func() -> Array[String]: return _compare_cards
	_compare_presets.apply_requested.connect(func(cards: Array[String]) -> void: _compare_cards = cards.duplicate())
	root.add_child(_compare_presets)
	_compare_starter.item_selected.connect(func(_i: int) -> void: _select_compare_starter())
	_select_compare_starter()
	_set_compare_visible(false)
	var settings: HBoxContainer = HBoxContainer.new()
	root.add_child(settings)
	_count = _spin(settings, "analysis.matches", "Matches", 1, 200, 20)
	_limit = _spin(settings, "analysis.limit", "Test cap (s)", 30, 1800, 300)
	_seed = _spin(settings, "analysis.seed", "Seed", 1, 2147483647, 12345)
	var actions: HBoxContainer = HBoxContainer.new()
	root.add_child(actions)
	_start = _button(actions, "analysis.start", "Run", _begin)
	_button(actions, "analysis.cancel", "Cancel", _cancel)
	_replay = _button(actions, "analysis.replay", "Replay last battle", _open_replay)
	_replay.disabled = true
	_button(actions, "analysis.back", "Back", SceneRouter.return_from_debug_lab)
	_progress = ProgressBar.new()
	root.add_child(_progress)
	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_output)


func _option(parent: Control, entries: Array[Dictionary]) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(option)
	for entry in entries:
		option.add_item(String(entry.get("label", entry.get("name", entry["id"]))))
		option.set_item_metadata(option.item_count - 1, String(entry["id"]))
	return option


func _spin(parent: Control, key: String, fallback: String, minimum: int, maximum: int, initial: int) -> SpinBox:
	var label: Label = Label.new()
	label.text = Localization.get_text(key, fallback)
	parent.add_child(label)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = initial
	parent.add_child(spin)
	return spin


func _button(parent: Control, key: String, fallback: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = Localization.get_text(key, fallback)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _select_starter() -> void:
	_cards = RunState.from_starter(Database.get_starter(String(_starter.get_selected_metadata())), 1).equipped_cards


func _select_compare_starter() -> void:
	_compare_cards = RunState.from_starter(Database.get_starter(String(_compare_starter.get_selected_metadata())), 1).equipped_cards


func _set_compare_visible(enabled: bool) -> void:
	if _compare_row != null:
		_compare_row.visible = enabled
	if _compare_presets != null:
		_compare_presets.visible = enabled


func _begin() -> void:
	if _running or not DeckPresetService.valid_cards(_cards):
		return
	if _compare_toggle.button_pressed and not DeckPresetService.valid_cards(_compare_cards):
		return
	_total = int(_count.value)
	_cap = _limit.value
	_configuration_index = 0
	_reports.clear()
	_running = true
	_start.disabled = true
	_replay.disabled = true
	_activate_configuration(0)
	_start_match()


func _activate_configuration(index: int) -> void:
	_configuration_index = index
	var use_compare: bool = index == 1
	var starter_option: OptionButton = _compare_starter if use_compare else _starter
	var enemy_option: OptionButton = _compare_enemy if use_compare else _enemy
	var cards: Array[String] = _compare_cards if use_compare else _cards
	_run = RunState.from_starter(Database.get_starter(String(starter_option.get_selected_metadata())), int(_seed.value))
	_run.player_cards = cards.duplicate()
	_run.equipped_cards = cards.duplicate()
	_enemy_id = String(enemy_option.get_selected_metadata())
	_rng.seed = int(_seed.value)
	_completed = 0
	_wins = 0
	_draws = 0
	_unresolved = 0
	_duration = 0.0
	_aggregate.clear()


func _start_match() -> void:
	_simulation = BattleSimulation.new()
	_simulation.setup(_run, _enemy_id, _cap, _rng.randf_range(0.0, 2.4))


func _process(_delta: float) -> void:
	if not _running:
		return
	# Budget work by wall time so input, the progress bar and cancellation stay live.
	var deadline: int = Time.get_ticks_usec() + 5000
	while _running and Time.get_ticks_usec() < deadline:
		_simulation.advance(1)
		if not _simulation.finished:
			continue
		_last_summary = _simulation.result()
		_completed += 1
		_wins += 1 if String(_last_summary.get("winner", "")) == "player" else 0
		_draws += 1 if String(_last_summary.get("winner", "")) == "draw" else 0
		_unresolved += 1 if bool(_last_summary.get("unresolved", false)) else 0
		_duration += float(_last_summary.get("battle_time", 0.0))
		_merge_analysis(Dictionary(_last_summary.get("analysis", {})))
		_simulation.dispose()
		if _completed >= _total:
			_reports.append(_current_report())
			if _compare_toggle.button_pressed and _configuration_index == 0:
				_activate_configuration(1)
				_start_match()
			else:
				_running = false
				_start.disabled = false
		else:
			_start_match()
		_replay.disabled = false
		var configuration_count: int = 2 if _compare_toggle.button_pressed else 1
		var overall_completed: int = _configuration_index * _total + _completed
		_progress.value = float(overall_completed) / float(_total * configuration_count) * 100.0
		_output.text = _format_reports()


func _current_report() -> Dictionary:
	return {
		"label": "B" if _configuration_index == 1 else "A",
		"completed": _completed,
		"wins": _wins,
		"draws": _draws,
		"unresolved": _unresolved,
		"duration": _duration,
		"analysis": _aggregate.duplicate(true),
	}


func _format_reports() -> String:
	var display_reports: Array[Dictionary] = _reports.duplicate(true)
	if _running or display_reports.is_empty():
		display_reports.append(_current_report())
	var blocks: PackedStringArray = []
	for report: Dictionary in display_reports:
		var completed: int = maxi(1, int(report.get("completed", 0)))
		blocks.append("[ %s ]  %d / %d wins (%.1f%%) | draw %d | unresolved %d | mean %.1fs\n%s" % [
			String(report.get("label", "A")),
			int(report.get("wins", 0)),
			completed,
			100.0 * float(report.get("wins", 0)) / completed,
			int(report.get("draws", 0)),
			int(report.get("unresolved", 0)),
			float(report.get("duration", 0.0)) / completed,
			BattleAnalysis.describe(Dictionary(report.get("analysis", {}))),
		])
	if display_reports.size() == 2 and not _running:
		var a: Dictionary = display_reports[0]
		var b: Dictionary = display_reports[1]
		var a_count: float = maxf(1.0, float(a.get("completed", 0)))
		var b_count: float = maxf(1.0, float(b.get("completed", 0)))
		blocks.append("[ B - A ]  win rate %+0.1f pt | mean duration %+0.1fs" % [
			100.0 * float(b.get("wins", 0)) / b_count - 100.0 * float(a.get("wins", 0)) / a_count,
			float(b.get("duration", 0.0)) / b_count - float(a.get("duration", 0.0)) / a_count,
		])
	return "\n\n".join(blocks)


func _merge_analysis(data: Dictionary) -> void:
	var rows: Dictionary = Dictionary(_aggregate.get("rows", {}))
	for row: Dictionary in data.get("cards", []):
		var key: String = String(row["actor"]) + ":" + String(row["card_id"])
		if not rows.has(key):
			rows[key] = row.duplicate()
		else:
			for metric: String in ["casts", "damage", "absorbed", "shield", "heal"]:
				rows[key][metric] += int(row[metric])
	_aggregate["rows"] = rows
	_aggregate["cards"] = rows.values()
	for metric: String in ["fatigue_hits", "fatigue_hp_damage", "fatigue_shield_damage"]:
		_aggregate[metric] = int(_aggregate.get(metric, 0)) + int(data.get(metric, 0))


func _cancel() -> void:
	_running = false
	_start.disabled = false
	if _simulation != null:
		_simulation.dispose()


func _open_replay() -> void:
	if _last_summary.is_empty():
		return
	_cancel()
	var path: String = SaveManager.export_replay(ReplayData.from_summary(_last_summary), "simulation")
	if Game.open_replay_view(path, "hub"):
		SceneRouter.go_to_replay_viewer()


func _exit_tree() -> void:
	if _simulation != null:
		_simulation.dispose()
