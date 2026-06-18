extends Control

const BOTTOM_PANEL_MIN_HEIGHT: float = 324.0
const BATTLE_INFO_MIN_WIDTH: float = 280.0
const BATTLE_CARD_TILE_SIZE: Vector2 = Vector2(100.0, 100.0)
const BATTLE_LOADOUT_WIDTH: float = 320.0
const BATTLE_SIDE_PANEL_WIDTH: float = BATTLE_LOADOUT_WIDTH + 34.0
const TIMELINE_PREVIEW_INSTANCE_ID: int = 999999

var _engine := RealtimeBattleEngine.new()
var _enemy_panel: UnitPanel
var _enemy_cards_panel: CardHandPanel
var _player_panel: UnitPanel
var _card_hand_panel: CardHandPanel
var _timeline_panel: TimelinePanel
var _log_button: Button
var _log_popup: PanelContainer
var _log_panel: LogPanel
var _battle_info_label: RichTextLabel
var _slow_mode_label: Label
var _result_label: Label
var _developer_panel: DeveloperPanel
var _transition_timer: float = -1.0
var _handled_finish: bool = false
var _hovered_player_runtime_id: String = ""
var _processed_battle_event_count: int = 0


func _ready() -> void:
	_build_ui()
	if Game.current_run == null:
		SceneRouter.go_to_title()
		return

	var enemy_id: String = Game.prepare_next_battle()
	_engine.setup(Game.current_run, enemy_id)
	_processed_battle_event_count = 0
	_timeline_panel.set_fixed_horizon(_compute_timeline_horizon())
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

	_log_button = Button.new()
	_log_button.name = "BattleLogButton"
	_log_button.text = Localization.get_text("battle.log_button", "LOG")
	_log_button.tooltip_text = Localization.get_text("battle.log_button_tooltip", "Show battle log")
	_log_button.custom_minimum_size = Vector2(56.0, 32.0)
	_log_button.z_index = 80
	_log_button.pressed.connect(_on_log_button_pressed)
	top_bar.add_child(_log_button)

	var main_split := HBoxContainer.new()
	main_split.name = "MainSplit"
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.alignment = BoxContainer.ALIGNMENT_CENTER
	main_split.add_theme_constant_override("separation", 16)
	outer.add_child(main_split)

	var left_panel := _create_section(main_split, Localization.get_text("battle.section.enemy", "Enemy"), false, true)
	left_panel.name = "EnemySection"
	_set_section_min_width(left_panel, BATTLE_SIDE_PANEL_WIDTH)
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
	_enemy_cards_panel.custom_minimum_size = Vector2(BATTLE_LOADOUT_WIDTH, 0.0)
	_enemy_cards_panel.set_tile_size(BATTLE_CARD_TILE_SIZE)
	left_panel.add_child(_enemy_cards_panel)

	var center_panel := _create_section(main_split, Localization.get_text("battle.section.battle", "Battle"), false, false)
	center_panel.name = "BattleInfoSection"
	center_panel.custom_minimum_size = Vector2(BATTLE_INFO_MIN_WIDTH, 0.0)
	_battle_info_label = RichTextLabel.new()
	_battle_info_label.name = "BattleInfoLabel"
	_battle_info_label.fit_content = true
	_battle_info_label.scroll_active = false
	_battle_info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_battle_info_label.custom_minimum_size = Vector2(BATTLE_INFO_MIN_WIDTH, 0.0)
	_battle_info_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_battle_info_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_panel.add_child(_battle_info_label)

	var right_panel := _create_section(main_split, Localization.get_text("battle.section.player", "Player"), false, true)
	right_panel.name = "PlayerSection"
	_set_section_min_width(right_panel, BATTLE_SIDE_PANEL_WIDTH)
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
	_card_hand_panel.custom_minimum_size = Vector2(BATTLE_LOADOUT_WIDTH, 0.0)
	_card_hand_panel.set_tile_size(BATTLE_CARD_TILE_SIZE)
	_card_hand_panel.card_requested.connect(_on_card_requested)
	_card_hand_panel.card_hovered.connect(_on_player_card_hovered)
	_card_hand_panel.card_unhovered.connect(_on_player_card_unhovered)
	right_panel.add_child(_card_hand_panel)

	var bottom_split := HBoxContainer.new()
	bottom_split.name = "BottomSplit"
	bottom_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_split.custom_minimum_size = Vector2(0.0, BOTTOM_PANEL_MIN_HEIGHT)
	bottom_split.add_theme_constant_override("separation", 16)
	outer.add_child(bottom_split)

	var timeline_section := _create_section(bottom_split, Localization.get_text("battle.timeline", "Timeline"), true, true, false)
	timeline_section.name = "TimelineSection"
	timeline_section.custom_minimum_size = Vector2(0.0, BOTTOM_PANEL_MIN_HEIGHT)
	_timeline_panel = TimelinePanel.new()
	_timeline_panel.name = "TimelinePanel"
	timeline_section.add_child(_timeline_panel)

	_build_log_popup()


func _build_log_popup() -> void:
	_log_popup = PanelContainer.new()
	_log_popup.name = "BattleLogPopup"
	_log_popup.visible = false
	_log_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_log_popup.z_index = 80
	_log_popup.anchor_left = 1.0
	_log_popup.anchor_right = 1.0
	_log_popup.anchor_top = 0.0
	_log_popup.anchor_bottom = 0.0
	_log_popup.offset_left = -520.0
	_log_popup.offset_top = 64.0
	_log_popup.offset_right = -24.0
	_log_popup.offset_bottom = 344.0
	add_child(_log_popup)

	var popup_margin: MarginContainer = MarginContainer.new()
	popup_margin.add_theme_constant_override("margin_left", 12)
	popup_margin.add_theme_constant_override("margin_top", 12)
	popup_margin.add_theme_constant_override("margin_right", 12)
	popup_margin.add_theme_constant_override("margin_bottom", 12)
	_log_popup.add_child(popup_margin)

	_log_panel = LogPanel.new()
	_log_panel.name = "BattleLogPanel"
	popup_margin.add_child(_log_panel)


func _create_section(parent: Control, title: String, expand_horizontal: bool = true, expand_vertical: bool = true, show_header: bool = true) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand_horizontal else Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if expand_vertical else Control.SIZE_SHRINK_CENTER
	parent.add_child(panel)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand_horizontal else Control.SIZE_SHRINK_CENTER
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL if expand_vertical else Control.SIZE_SHRINK_CENTER
	panel.add_child(box)

	if show_header:
		var header := Label.new()
		header.text = title
		box.add_child(header)
	return box


func _set_section_min_width(section_box: Control, min_width: float) -> void:
	section_box.custom_minimum_size = Vector2(min_width, section_box.custom_minimum_size.y)
	var frame: Control = section_box.get_parent() as Control
	if frame != null:
		frame.custom_minimum_size = Vector2(min_width, frame.custom_minimum_size.y)


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

	var preview_runtime_state: CardRuntimeState = _get_hovered_player_runtime_state(battle_state)
	var preview_card_def: CardDef = _get_hover_preview_card_def(preview_runtime_state)
	var preview_slot_cost: int = _get_hover_preview_slot_cost(preview_runtime_state, preview_card_def)
	var suppressed_shield_losses: Dictionary = _consume_suppressed_shield_decay_losses(battle_state)
	_enemy_panel.refresh_unit(battle_state.enemy, 0, int(suppressed_shield_losses.get(battle_state.enemy.unit_id, 0)))
	_player_panel.refresh_unit(battle_state.player, preview_slot_cost, int(suppressed_shield_losses.get(battle_state.player.unit_id, 0)))
	_enemy_cards_panel.refresh_cards(battle_state.enemy, null, "enemy")
	_card_hand_panel.refresh_cards(battle_state.player, Game.current_run, "player")
	var preview_entry: TimelineEntry = _build_hover_preview_entry(battle_state, preview_runtime_state, preview_card_def)
	_timeline_panel.refresh_timeline(battle_state.timeline, battle_state.battle_time, Game.current_run, preview_entry, preview_card_def)
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
	])


func _consume_suppressed_shield_decay_losses(battle_state: BattleState) -> Dictionary:
	var suppressed_by_unit: Dictionary = {}
	if battle_state == null:
		return suppressed_by_unit

	var battle_events: Array[Dictionary] = battle_state.battle_events
	var start_index: int = clampi(_processed_battle_event_count, 0, battle_events.size())
	for event_index in range(start_index, battle_events.size()):
		var event_data: Dictionary = Dictionary(battle_events[event_index])
		if String(event_data.get("event_type", "")) != "shield_decay":
			continue
		var target_id: String = String(event_data.get("target_id", ""))
		var shield_loss: int = max(0, -int(event_data.get("shield_delta", 0)))
		if target_id == "" or shield_loss <= 0:
			continue
		suppressed_by_unit[target_id] = int(suppressed_by_unit.get(target_id, 0)) + shield_loss
	_processed_battle_event_count = battle_events.size()
	return suppressed_by_unit


func _on_card_requested(runtime_id: String) -> void:
	var requested: bool = _engine.request_use_card("player", runtime_id)
	if not requested:
		AudioManager.play_sfx("ui_error")
	elif _hovered_player_runtime_id == runtime_id:
		_hovered_player_runtime_id = ""
	_refresh_ui(SlowModeController.get_time_scale(Input.is_key_pressed(KEY_SPACE)))


func _on_player_card_hovered(runtime_id: String) -> void:
	_hovered_player_runtime_id = runtime_id
	_refresh_ui(SlowModeController.get_time_scale(Input.is_key_pressed(KEY_SPACE)))


func _on_player_card_unhovered(runtime_id: String) -> void:
	if _hovered_player_runtime_id != runtime_id:
		return
	_hovered_player_runtime_id = ""
	_refresh_ui(SlowModeController.get_time_scale(Input.is_key_pressed(KEY_SPACE)))


func _get_hovered_player_runtime_state(battle_state: BattleState) -> CardRuntimeState:
	if _hovered_player_runtime_id == "":
		return null
	return battle_state.player.get_runtime_state(_hovered_player_runtime_id)


func _get_hover_preview_card_def(runtime_state: CardRuntimeState) -> CardDef:
	if runtime_state == null or Game.current_run == null:
		return null
	return CardUpgradeResolver.build_effective_card(runtime_state.card_id, Game.current_run)


func _get_hover_preview_slot_cost(runtime_state: CardRuntimeState, card_def: CardDef) -> int:
	if runtime_state == null or card_def == null:
		return 0
	if not runtime_state.can_use():
		return 0
	return card_def.active_slot_cost


func _build_hover_preview_entry(
	battle_state: BattleState,
	runtime_state: CardRuntimeState,
	card_def: CardDef
) -> TimelineEntry:
	if runtime_state == null or card_def == null:
		return null
	if not runtime_state.can_use():
		return null
	if battle_state.player.active_slots_used + card_def.active_slot_cost > battle_state.player.active_slot_max:
		return null

	var entry: TimelineEntry = TimelineEntry.new()
	entry.instance_id = TIMELINE_PREVIEW_INSTANCE_ID
	entry.owner_side = "player"
	entry.runtime_id = "preview_%s" % runtime_state.runtime_id
	entry.card_id = runtime_state.card_id
	entry.card_name = card_def.name
	entry.created_at = battle_state.battle_time
	entry.scheduled_time = battle_state.battle_time + card_def.cast_time * battle_state.player.get_cast_time_multiplier()
	entry.sort_key = entry.scheduled_time - card_def.priority_modifier
	entry.priority_modifier = card_def.priority_modifier
	entry.actor_speed = battle_state.player.speed
	entry.slot_cost = card_def.active_slot_cost
	entry.interruptible = card_def.interruptible
	return entry


func _compute_timeline_horizon() -> float:
	if _engine.battle_state == null:
		return TimelinePanel.DEFAULT_TIMELINE_HORIZON
	var max_cast_time: float = TimelinePanel.DEFAULT_TIMELINE_HORIZON
	max_cast_time = maxf(max_cast_time, _get_unit_loadout_max_cast_time(_engine.battle_state.player, true))
	max_cast_time = maxf(max_cast_time, _get_unit_loadout_max_cast_time(_engine.battle_state.enemy, false))
	return max_cast_time


func _get_unit_loadout_max_cast_time(unit: UnitState, use_player_upgrades: bool) -> float:
	var max_cast_time: float = 0.1
	for runtime_state in unit.card_runtime_states:
		var card_def: CardDef = null
		if use_player_upgrades and Game.current_run != null:
			card_def = CardUpgradeResolver.build_effective_card(runtime_state.card_id, Game.current_run)
		else:
			card_def = Database.get_card(runtime_state.card_id)
		if card_def != null:
			max_cast_time = maxf(max_cast_time, card_def.cast_time)
	return max_cast_time


func _on_log_button_pressed() -> void:
	_log_popup.visible = not _log_popup.visible
	AudioManager.play_sfx("ui_toggle")


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
