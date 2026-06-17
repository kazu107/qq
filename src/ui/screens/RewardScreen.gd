extends Control

var _summary_label: Label
var _reward_relic_label: Label
var _reward_relic_icon_row: RelicIconRow
var _reward_cards_panel: CardHandPanel
var _reroll_button: Button
var _developer_panel: DeveloperPanel


func _ready() -> void:
	if Game.current_run == null:
		SceneRouter.go_to_title()
		return
	if Game.reward_options.is_empty():
		if Game.current_run.run_complete:
			SceneRouter.go_to_result()
		else:
			SceneRouter.go_to_map()
		return

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 80.0
	margin.offset_top = 60.0
	margin.offset_right = -80.0
	margin.offset_bottom = -60.0
	add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var title := Label.new()
	title.text = Localization.get_text("reward.title", "Reward")
	root.add_child(title)

	_summary_label = Label.new()
	_summary_label.text = _build_summary_text()
	root.add_child(_summary_label)

	_reward_relic_label = Label.new()
	_reward_relic_label.name = "RewardRelicLabel"
	_reward_relic_label.text = Localization.get_text("reward.relic_bonus", "Bonus Relic")
	root.add_child(_reward_relic_label)

	_reward_relic_icon_row = RelicIconRow.new()
	_reward_relic_icon_row.name = "RewardRelicIconRow"
	_reward_relic_icon_row.set_icon_size(Vector2(56.0, 56.0))
	root.add_child(_reward_relic_icon_row)

	var info := Label.new()
	info.text = Localization.get_text("reward.choose_one", "Choose one card. Hover to inspect details.")
	root.add_child(info)

	_reward_cards_panel = CardHandPanel.new()
	_reward_cards_panel.name = "RewardCards"
	_reward_cards_panel.set_interactive(true)
	_reward_cards_panel.set_tile_size(Vector2(110.0, 110.0))
	_reward_cards_panel.card_requested.connect(_on_reward_selected)
	root.add_child(_reward_cards_panel)
	_reward_cards_panel.refresh_card_ids(Game.reward_options, true, "PICK", Game.current_run)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	root.add_child(button_row)

	_reroll_button = Button.new()
	_reroll_button.name = "RewardRerollButton"
	_reroll_button.pressed.connect(_on_paid_reroll)
	button_row.add_child(_reroll_button)

	var skip_button := Button.new()
	skip_button.text = Localization.get_text("reward.skip", "Skip")
	skip_button.pressed.connect(_on_skip)
	button_row.add_child(skip_button)

	var replay_button: Button = Button.new()
	replay_button.name = "OpenReplayViewerButton"
	replay_button.text = Localization.get_text("reward.view_replay", "View Replay")
	replay_button.disabled = Game.get_last_replay_export_path() == ""
	replay_button.pressed.connect(_on_open_replay_viewer)
	button_row.add_child(replay_button)

	_refresh_reward_ui()

	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _build_summary_text() -> String:
	var summary_lines: Array[String] = [
		Localization.get_textf("reward.summary.victory", "Victory over {enemy_name} | HP {hp} | Gold {gold}", {
			"enemy_name": Game.get_last_battle_enemy_name(),
			"hp": Game.current_run.player_hp,
			"gold": Game.current_run.gold,
		})
	]
	var reward_bundle: Dictionary = Game.get_last_reward_bundle()
	if not reward_bundle.is_empty():
		summary_lines.append(
			Localization.get_textf("reward.summary.bundle", "Reward {reward_name} | Area {area} | +{gold} Gold | +{hp} HP", {
				"reward_name": Localization.get_reward_name(String(reward_bundle.get("reward_key", "normal"))),
				"area": int(reward_bundle.get("area", 1)),
				"gold": int(reward_bundle.get("gold", 0)),
				"hp": int(reward_bundle.get("heal", 0)),
			})
		)
	var bonus_text: String = String(Game.last_battle_summary.get("bonus_text", ""))
	if bonus_text != "":
		summary_lines.append(bonus_text)
	var replay_path: String = Game.get_last_replay_export_path()
	if replay_path != "":
		summary_lines.append(Localization.get_textf("reward.summary.replay", "Replay JSON: {path}", {
			"path": replay_path,
		}))
	return "\n".join(summary_lines)


func _refresh_reward_ui() -> void:
	if _summary_label != null:
		_summary_label.text = _build_summary_text()
	if _reward_cards_panel != null:
		_reward_cards_panel.refresh_card_ids(Game.reward_options, true, "PICK", Game.current_run)
	_refresh_reward_relics()
	_refresh_reroll_button()


func _refresh_reward_relics() -> void:
	if _reward_relic_icon_row == null or _reward_relic_label == null:
		return
	var relic_ids: Array[String] = _get_reward_relic_ids()
	_reward_relic_label.visible = not relic_ids.is_empty()
	_reward_relic_icon_row.visible = not relic_ids.is_empty()
	_reward_relic_icon_row.refresh_relic_ids(relic_ids)


func _get_reward_relic_ids() -> Array[String]:
	var relic_id: String = String(Game.last_battle_summary.get("bonus_relic_id", ""))
	if relic_id == "":
		return []
	return [relic_id]


func _refresh_reroll_button() -> void:
	if _reroll_button == null:
		return
	var cost: int = Game.get_reward_reroll_cost()
	_reroll_button.text = Localization.get_textf("reward.reroll", "Reroll ({cost}G)", {"cost": cost})
	_reroll_button.disabled = not Game.can_reroll_rewards()


func _on_reward_selected(card_id: String) -> void:
	Game.choose_reward(card_id)
	if Game.current_run != null and Game.current_run.run_complete:
		SceneRouter.go_to_result()
	else:
		SceneRouter.go_to_map()


func _on_skip() -> void:
	Game.skip_reward()
	if Game.current_run != null and Game.current_run.run_complete:
		SceneRouter.go_to_result()
	else:
		SceneRouter.go_to_map()


func _on_open_replay_viewer() -> void:
	if not Game.open_last_replay_view("reward"):
		AudioManager.play_sfx("ui_error")
		return
	SceneRouter.go_to_replay_viewer()


func _on_paid_reroll() -> void:
	if Game.reroll_rewards_for_gold():
		_refresh_reward_ui()
		return
	_refresh_reroll_button()


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right()
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevTakeFirstReward", "label": Localization.get_text("reward.dev.take_first", "Take First"), "callback": Callable(self, "_on_dev_take_first_reward")},
			{"id": "DevSkipReward", "label": Localization.get_text("reward.dev.skip", "Skip Reward"), "callback": Callable(self, "_on_skip")},
			{"id": "DevRerollRewards", "label": Localization.get_text("reward.dev.reroll", "Reroll Rewards"), "callback": Callable(self, "_on_dev_reroll_rewards")},
			{"id": "DevPreviewEliteReward", "label": Localization.get_text("reward.dev.preview_elite", "Preview Elite"), "callback": Callable(self, "_on_dev_preview_elite")},
			{"id": "DevExportReplay", "label": Localization.get_text("reward.dev.export_replay", "Export Replay"), "callback": Callable(self, "_on_dev_export_replay")},
			{"id": "DevOpenReplay", "label": Localization.get_text("reward.dev.open_replay", "Open Replay"), "callback": Callable(self, "_on_dev_open_replay")},
		],
		Localization.get_text("reward.dev.summary", "Fast reward inspection and selection.")
	)


func _on_dev_take_first_reward() -> void:
	if Game.reward_options.is_empty():
		return
	_on_reward_selected(Game.reward_options[0])


func _on_dev_reroll_rewards() -> void:
	Game.developer_reroll_rewards()
	_refresh_reward_ui()


func _on_dev_preview_elite() -> void:
	Game.developer_open_reward_preview("elite", Game.current_run.current_area)
	_refresh_reward_ui()


func _on_dev_export_replay() -> void:
	Game.export_last_battle_replay()


func _on_dev_open_replay() -> void:
	_on_open_replay_viewer()
