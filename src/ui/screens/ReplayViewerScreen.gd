extends Control

var _title_label: Label
var _summary_label: RichTextLabel
var _events_box: VBoxContainer
var _retry_button: Button
var _developer_panel: DeveloperPanel


func _ready() -> void:
	Game.current_screen_hint = "replay"
	SaveManager.save_game("replay")
	_build_ui()
	_refresh_ui()
	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 32.0
	margin.offset_top = 24.0
	margin.offset_right = -32.0
	margin.offset_bottom = -24.0
	add_child(margin)

	var root: HBoxContainer = HBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var summary_panel: VBoxContainer = _create_panel(root, Localization.get_text("replay.panel.summary", "Replay Summary"))
	_title_label = Label.new()
	_title_label.name = "ReplayTitle"
	summary_panel.add_child(_title_label)

	_summary_label = RichTextLabel.new()
	_summary_label.name = "ReplaySummary"
	_summary_label.fit_content = true
	summary_panel.add_child(_summary_label)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	summary_panel.add_child(button_row)

	var back_button: Button = Button.new()
	back_button.name = "ReplayBackButton"
	back_button.text = Localization.get_text("replay.back", "Back")
	back_button.pressed.connect(_on_back)
	button_row.add_child(back_button)

	_retry_button = Button.new()
	_retry_button.name = "ReplayRetrySeedButton"
	_retry_button.text = Localization.get_text("replay.retry", "Retry Same Seed")
	_retry_button.pressed.connect(_on_retry_same_seed)
	button_row.add_child(_retry_button)

	var events_panel: VBoxContainer = _create_panel(root, Localization.get_text("replay.panel.events", "Battle Events"))
	events_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	events_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	events_panel.add_child(scroll)

	_events_box = VBoxContainer.new()
	_events_box.name = "ReplayEvents"
	_events_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_events_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_events_box)


func _create_panel(parent: Control, title: String) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header: Label = Label.new()
	header.text = title
	box.add_child(header)
	return box


func _refresh_ui() -> void:
	var replay_data: Dictionary = Game.get_replay_view_data()
	if replay_data.is_empty():
		_title_label.text = Localization.get_text("replay.none_selected", "No replay selected")
		_summary_label.text = Localization.get_textf("replay.summary.path", "Replay path: {path}", {
			"path": Game.get_replay_view_path(),
		})
		_retry_button.disabled = not Game.can_retry_last_seed_run()
		return

	var summary: Dictionary = Dictionary(replay_data.get("summary", {}))
	var battle_events: Array = Array(replay_data.get("battle_events", []))
	var run_seed: int = int(summary.get("run_seed", 0))
	var starter_id: String = String(summary.get("starter_id", ""))

	_title_label.text = Localization.get_textf("replay.summary.title", "Replay {battle_id}", {
		"battle_id": String(replay_data.get("battle_id", "")),
	})
	_summary_label.text = "\n".join([
		Localization.get_textf("replay.summary.exported", "Exported: {value}", {"value": String(replay_data.get("exported_at", ""))}),
		Localization.get_textf("replay.summary.battle_id", "Battle ID: {value}", {"value": String(replay_data.get("battle_id", ""))}),
		Localization.get_textf("replay.summary.winner", "Winner: {value}", {
			"value": Localization.get_winner_name(String(summary.get("winner", ""))),
		}),
		Localization.get_textf("replay.summary.enemy", "Enemy: {value}", {
			"value": Localization.get_enemy_name(String(summary.get("enemy_id", "")), String(summary.get("enemy_name", summary.get("enemy_id", "")))),
		}),
		Localization.get_textf("replay.summary.battle_time", "Battle Time: {value}s", {"value": "%.1f" % float(summary.get("battle_time", 0.0))}),
		Localization.get_textf("replay.summary.player_hp", "Player HP: {value}", {"value": int(summary.get("player_hp", 0))}),
		Localization.get_textf("replay.summary.starter", "Starter: {value}", {"value": Localization.get_starter_name(starter_id)}),
		Localization.get_textf("replay.summary.seed", "Seed: {value}", {"value": run_seed}),
		Localization.get_textf("replay.summary.events", "Events: {value}", {"value": battle_events.size()}),
		Localization.get_textf("replay.summary.path", "Replay path: {path}", {"path": Game.get_replay_view_path()}),
	])
	_retry_button.disabled = run_seed <= 0 or starter_id == ""

	for child in _events_box.get_children():
		_events_box.remove_child(child)
		child.queue_free()

	for event_index in range(battle_events.size()):
		var event_data: Dictionary = Dictionary(battle_events[event_index])
		var row: VBoxContainer = VBoxContainer.new()
		row.name = "ReplayEvent_%d" % event_index
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_events_box.add_child(row)

		var header: Label = Label.new()
		header.text = Localization.get_textf("replay.event_header", "[{time}] {event_type} | actor={actor} | card={card} | target={target}", {
			"time": "%.1f" % float(event_data.get("time", 0.0)),
			"event_type": String(event_data.get("event_type", "")),
			"actor": String(event_data.get("actor_id", "")),
			"card": String(event_data.get("card_id", "")),
			"target": String(event_data.get("target_id", "")),
		})
		row.add_child(header)

		var body: Label = Label.new()
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.text = JSON.stringify(Dictionary(event_data.get("result", {})))
		row.add_child(body)


func _on_back() -> void:
	match Game.get_replay_view_return_hint():
		"reward":
			Game.current_screen_hint = "reward"
			SaveManager.save_game("reward")
			SceneRouter.go_to_reward()
		"settings":
			Game.current_screen_hint = "settings"
			SaveManager.save_game("settings")
			SceneRouter.go_to_settings()
		"map":
			Game.current_screen_hint = "map"
			SaveManager.save_game("map")
			SceneRouter.go_to_map()
		"hub":
			Game.current_screen_hint = "hub"
			SaveManager.save_game("hub")
			SceneRouter.go_to_hub()
		_:
			Game.current_screen_hint = "result"
			SaveManager.save_game("result")
			SceneRouter.go_to_result()


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
			{"id": "DevReplayRetry", "label": Localization.get_text("replay.retry", "Retry Same Seed"), "callback": Callable(self, "_on_retry_same_seed")},
			{"id": "DevReplayBack", "label": Localization.get_text("replay.back", "Back"), "callback": Callable(self, "_on_back")},
		],
		Localization.get_text("replay.dev.summary", "Replay inspection and deterministic reruns.")
	)
