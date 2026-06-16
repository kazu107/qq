extends Control

var _developer_panel: DeveloperPanel


func _ready() -> void:
	var summary_data := Game.get_run_summary()

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 100.0
	margin.offset_top = 80.0
	margin.offset_right = -100.0
	margin.offset_bottom = -80.0
	add_child(margin)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var title := Label.new()
	title.text = Localization.get_text("result.title", "Run Result")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var summary := RichTextLabel.new()
	var relic_names: Array = Array(summary_data.get("relic_names", []))
	var relic_ids: Array[String] = _to_string_array(summary_data.get("relic_ids", []))
	var relic_text: String = Localization.get_text("status.none", "None")
	var replay_path: String = Game.get_last_replay_export_path()
	var replay_text: String = Localization.get_text("result.replay_none", "none")
	if not relic_names.is_empty():
		relic_text = ", ".join(relic_names)
	if replay_path != "":
		replay_text = replay_path
	summary.fit_content = true
	summary.text = "\n".join([
		Localization.get_textf("result.summary.starter", "Starter: {value}", {
			"value": String(summary_data.get("starter_name", summary_data.get("starter_id", ""))),
		}),
		Localization.get_textf("result.summary.seed", "Seed: {value}", {"value": int(summary_data.get("seed", 0))}),
		Localization.get_textf("result.summary.area", "Reached Area: {value}", {"value": int(summary_data.get("current_area", 0))}),
		Localization.get_textf("result.summary.encounters", "Encounters Cleared: {value}", {"value": int(summary_data.get("encounters_cleared", 0))}),
		Localization.get_textf("result.summary.hp", "Remaining HP: {value}", {"value": int(summary_data.get("remaining_hp", 0))}),
		Localization.get_textf("result.summary.gold", "Gold: {value}", {"value": int(summary_data.get("gold", 0))}),
		Localization.get_textf("result.summary.relics", "Relics ({count}): {value}", {
			"count": int(summary_data.get("relic_count", 0)),
			"value": relic_text,
		}),
		Localization.get_textf("result.summary.last_enemy", "Last Enemy: {value}", {
			"value": String(summary_data.get("last_enemy", "")),
		}),
		Localization.get_textf("result.summary.result", "Result: {value}", {
			"value": Localization.get_winner_name(String(summary_data.get("last_winner", ""))),
		}),
		Localization.get_textf("result.summary.replay", "Replay JSON: {value}", {"value": replay_text}),
	])
	root.add_child(summary)

	var relic_icon_row: RelicIconRow = RelicIconRow.new()
	relic_icon_row.name = "ResultRelicIconRow"
	relic_icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	relic_icon_row.set_icon_size(Vector2(52.0, 52.0))
	relic_icon_row.refresh_relic_ids(relic_ids)
	root.add_child(relic_icon_row)

	var replay_button := Button.new()
	replay_button.name = "ResultReplayViewerButton"
	replay_button.text = Localization.get_text("result.view_replay", "View Replay")
	replay_button.disabled = replay_path == ""
	replay_button.pressed.connect(_on_open_replay_viewer)
	root.add_child(replay_button)

	var retry_button := Button.new()
	retry_button.name = "ResultRetrySameSeedButton"
	retry_button.text = Localization.get_text("result.retry", "Retry Same Seed")
	retry_button.disabled = not Game.can_retry_last_seed_run()
	retry_button.pressed.connect(_on_retry_same_seed)
	root.add_child(retry_button)

	var hub_button := Button.new()
	hub_button.text = Localization.get_text("result.return_hub", "Return to Hub")
	hub_button.pressed.connect(_on_return_to_hub)
	root.add_child(hub_button)

	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for raw_value in Array(value):
		result.append(String(raw_value))
	return result


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
