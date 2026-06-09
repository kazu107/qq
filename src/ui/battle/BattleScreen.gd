extends Control

const BOTTOM_PANEL_MIN_HEIGHT: float = 324.0

var _engine := RealtimeBattleEngine.new()
var _enemy_panel: UnitPanel
var _enemy_cards_panel: CardHandPanel
var _player_panel: UnitPanel
var _card_hand_panel: CardHandPanel
var _timeline_panel: TimelinePanel
var _log_panel: LogPanel
var _battle_info_label: RichTextLabel
var _slow_mode_label: Label
var _result_label: Label
var _developer_panel: DeveloperPanel
var _transition_timer: float = -1.0
var _handled_finish: bool = false


func _ready() -> void:
	_build_ui()
	if Game.current_run == null:
		SceneRouter.go_to_title()
		return

	var enemy_id: String = Game.prepare_next_battle()
	_engine.setup(Game.current_run, enemy_id)
	_player_panel.configure_visual("player", Game.current_run.starter_id)
	_enemy_panel.configure_visual("enemy", enemy_id)
	set_process(true)
	_refresh_ui(SlowModeController.NORMAL_SCALE)
	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _process(delta: float) -> void:
	if _engine.battle_state == null:
		return

	var time_scale := SlowModeController.get_time_scale(Input.is_key_pressed(KEY_SPACE))
	_engine.update(delta * time_scale)
	_refresh_ui(time_scale)

	if _engine.battle_state.winner != "" and not _handled_finish:
		_handled_finish = true
		Game.complete_battle(_engine.build_summary())
		_transition_timer = 1.2
		_result_label.visible = true
		match _engine.battle_state.winner:
			"player":
				_result_label.text = Localization.get_text("battle.result.victory", "Victory")
			"enemy":
				_result_label.text = Localization.get_text("battle.result.defeat", "Defeat")
			_:
				_result_label.text = Localization.get_text("battle.result.draw", "Draw")

	if _transition_timer > 0.0:
		_transition_timer -= delta
		if _transition_timer <= 0.0:
			_advance_after_battle()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 24.0
	margin.offset_top = 24.0
	margin.offset_right = -24.0
	margin.offset_bottom = -24.0
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(outer)

	var top_bar := HBoxContainer.new()
	outer.add_child(top_bar)

	_slow_mode_label = Label.new()
	_slow_mode_label.text = Localization.get_text("battle.slow_mode_hold", "Hold Space for Slow Mode")
	top_bar.add_child(_slow_mode_label)

	_result_label = Label.new()
	_result_label.visible = false
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_result_label)

	var main_split := HBoxContainer.new()
	main_split.name = "MainSplit"
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.add_theme_constant_override("separation", 16)
	outer.add_child(main_split)

	var left_panel := _create_section(main_split, Localization.get_text("battle.section.enemy", "Enemy"))
	left_panel.name = "EnemySection"
	_enemy_panel = UnitPanel.new()
	_enemy_panel.name = "EnemyUnitPanel"
	left_panel.add_child(_enemy_panel)
	_enemy_panel.set_title(Localization.get_text("battle.enemy_status", "Enemy Status"))

	var enemy_cards_title := Label.new()
	enemy_cards_title.text = Localization.get_text("battle.enemy_loadout", "Enemy Loadout")
	left_panel.add_child(enemy_cards_title)

	_enemy_cards_panel = CardHandPanel.new()
	_enemy_cards_panel.name = "EnemyLoadoutPanel"
	_enemy_cards_panel.set_interactive(false)
	_enemy_cards_panel.set_tile_size(Vector2(88.0, 88.0))
	left_panel.add_child(_enemy_cards_panel)

	var center_panel := _create_section(main_split, Localization.get_text("battle.section.battle", "Battle"))
	center_panel.name = "BattleInfoSection"
	_battle_info_label = RichTextLabel.new()
	_battle_info_label.fit_content = true
	center_panel.add_child(_battle_info_label)

	var right_panel := _create_section(main_split, Localization.get_text("battle.section.player", "Player"))
	right_panel.name = "PlayerSection"
	_player_panel = UnitPanel.new()
	_player_panel.name = "PlayerUnitPanel"
	right_panel.add_child(_player_panel)
	_player_panel.set_title(Localization.get_text("battle.player_status", "Player Status"))

	var hand_title := Label.new()
	hand_title.text = Localization.get_text("battle.cards", "Cards")
	right_panel.add_child(hand_title)

	_card_hand_panel = CardHandPanel.new()
	_card_hand_panel.name = "PlayerHandPanel"
	_card_hand_panel.set_interactive(true)
	_card_hand_panel.set_tile_size(Vector2(100.0, 100.0))
	_card_hand_panel.card_requested.connect(_on_card_requested)
	right_panel.add_child(_card_hand_panel)

	var bottom_split := HBoxContainer.new()
	bottom_split.name = "BottomSplit"
	bottom_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_split.custom_minimum_size = Vector2(0.0, BOTTOM_PANEL_MIN_HEIGHT)
	bottom_split.add_theme_constant_override("separation", 16)
	outer.add_child(bottom_split)

	var timeline_section := _create_section(bottom_split, Localization.get_text("battle.timeline", "Timeline"))
	timeline_section.name = "TimelineSection"
	timeline_section.custom_minimum_size = Vector2(0.0, BOTTOM_PANEL_MIN_HEIGHT)
	_timeline_panel = TimelinePanel.new()
	_timeline_panel.name = "TimelinePanel"
	timeline_section.add_child(_timeline_panel)

	var log_section := _create_section(bottom_split, Localization.get_text("battle.log", "Log"))
	log_section.name = "LogSection"
	log_section.custom_minimum_size = Vector2(0.0, BOTTOM_PANEL_MIN_HEIGHT)
	_log_panel = LogPanel.new()
	_log_panel.name = "LogPanel"
	log_section.add_child(_log_panel)


func _create_section(parent: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(box)

	var header := Label.new()
	header.text = title
	box.add_child(header)
	return box


func _refresh_ui(time_scale: float) -> void:
	var battle_state := _engine.battle_state
	if battle_state == null:
		return

	if time_scale < 1.0:
		_slow_mode_label.text = Localization.get_textf("battle.slow_mode_rate", "Slow Mode {rate}%", {
			"rate": int(round(time_scale * 100.0)),
		})
	else:
		_slow_mode_label.text = Localization.get_text("battle.slow_mode_hold", "Hold Space for Slow Mode")

	_enemy_panel.refresh_unit(battle_state.enemy)
	_player_panel.refresh_unit(battle_state.player)
	_enemy_cards_panel.refresh_cards(battle_state.enemy, null, "enemy")
	_card_hand_panel.refresh_cards(battle_state.player, Game.current_run, "player")
	_timeline_panel.refresh_timeline(battle_state.timeline, battle_state.battle_time, Game.current_run)
	_log_panel.refresh_logs(battle_state.logs)
	var total_steps: int = max(1, Game.get_map_step_count())
	var display_step: int = min(total_steps, Game.get_current_step_index() + 1)
	_battle_info_label.text = "\n".join([
		Localization.get_textf("battle.info.time", "Battle Time {value}s", {"value": "%.1f" % battle_state.battle_time}),
		Localization.get_textf("battle.info.map_step", "Map Step {current} / {total}", {
			"current": display_step,
			"total": total_steps,
		}),
		Localization.get_textf("battle.info.current_enemy", "Current Enemy: {value}", {"value": battle_state.enemy.display_name}),
		Localization.get_textf("battle.info.player_slots", "Player Slots: {used} / {total}", {
			"used": battle_state.player.active_slots_used,
			"total": battle_state.player.active_slot_max,
		}),
		Localization.get_textf("battle.info.enemy_slots", "Enemy Slots: {used} / {total}", {
			"used": battle_state.enemy.active_slots_used,
			"total": battle_state.enemy.active_slot_max,
		}),
		Localization.get_textf("battle.info.timeline_entries", "Timeline Entries: {value}", {
			"value": battle_state.timeline.size(),
		}),
		"",
		Localization.get_text("battle.info.controls", "Controls:"),
		Localization.get_text("battle.info.click_card", "- Click a player card to commit it"),
		Localization.get_text("battle.info.hover_card", "- Hover any card for details"),
		Localization.get_text("battle.info.slow_mode", "- Hold Space to slow time to 30%"),
	])


func _on_card_requested(runtime_id: String) -> void:
	if not _engine.request_use_card("player", runtime_id):
		AudioManager.play_sfx("ui_error")
	_refresh_ui(SlowModeController.get_time_scale(Input.is_key_pressed(KEY_SPACE)))


func _advance_after_battle() -> void:
	if Game.current_run == null:
		SceneRouter.go_to_title()
		return
	match Game.current_screen_hint:
		"result":
			SceneRouter.go_to_result()
		"facility":
			SceneRouter.go_to_facility()
		"map":
			SceneRouter.go_to_map()
		"reward":
			SceneRouter.go_to_reward()
		_:
			if Game.current_run.run_complete:
				SceneRouter.go_to_result()
			else:
				SceneRouter.go_to_reward()


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right()
	_refresh_developer_panel()


func _refresh_developer_panel() -> void:
	if _developer_panel == null:
		return
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevWinBattle", "label": Localization.get_text("battle.dev.force_victory", "Force Victory"), "callback": Callable(self, "_on_dev_force_victory")},
			{"id": "DevLoseBattle", "label": Localization.get_text("battle.dev.force_defeat", "Force Defeat"), "callback": Callable(self, "_on_dev_force_defeat")},
			{"id": "DevRestoreHp", "label": Localization.get_text("map.dev.restore_hp", "Restore HP"), "callback": Callable(self, "_on_dev_restore_hp")},
		],
		Localization.get_text("battle.dev.summary", "Battle shortcuts for deterministic manual testing.")
	)


func _on_dev_force_victory() -> void:
	_force_battle_result("player")


func _on_dev_force_defeat() -> void:
	_force_battle_result("enemy")


func _on_dev_restore_hp() -> void:
	if _engine.battle_state == null:
		return
	_engine.battle_state.player.hp = _engine.battle_state.player.max_hp
	_refresh_ui(SlowModeController.get_time_scale(Input.is_key_pressed(KEY_SPACE)))


func _force_battle_result(winner: String) -> void:
	if _engine.battle_state == null or _handled_finish:
		return
	_handled_finish = true
	var summary: Dictionary = _engine.build_summary()
	summary["winner"] = winner
	if winner == "player":
		summary["player_hp"] = max(1, _engine.battle_state.player.hp)
		_result_label.text = Localization.get_text("battle.result.victory", "Victory")
	else:
		summary["player_hp"] = 0
		_result_label.text = Localization.get_text("battle.result.defeat", "Defeat")
	var events: Array = Array(summary.get("battle_events", []))
	events.append({
		"time": float(summary.get("battle_time", 0.0)),
		"event_type": "developer_forced_result",
		"actor_id": "developer_mode",
		"card_id": "",
		"target_id": winner,
		"result": {
			"winner": winner,
		},
		"hp_delta": 0,
		"shield_delta": 0,
		"timeline_before": [],
		"timeline_after": [],
	})
	summary["battle_events"] = events
	Game.complete_battle(summary)
	_result_label.visible = true
	_transition_timer = -1.0
	_advance_after_battle()
