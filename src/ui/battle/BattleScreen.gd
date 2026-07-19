extends Control

const BOTTOM_PANEL_MIN_HEIGHT: float = 324.0
const BATTLE_INFO_MIN_WIDTH: float = 280.0
const BATTLE_CARD_TILE_SIZE: Vector2 = Vector2(100.0, 100.0)
const BATTLE_LOADOUT_WIDTH: float = 320.0
const BATTLE_SIDE_PANEL_WIDTH: float = BATTLE_LOADOUT_WIDTH + 34.0
const TIMELINE_PREVIEW_INSTANCE_ID: int = 999999
const LAN_SNAPSHOT_INTERVAL: float = 1.0 / 12.0

var _engine := RealtimeBattleEngine.new()
var _enemy_panel: UnitPanel
var _enemy_cards_panel: CardHandPanel
var _player_panel: UnitPanel
var _card_hand_panel: CardHandPanel
var _timeline_panel: TimelinePanel
var _vfx_layer: BattleVfxLayer
var _run_info_banner: RunInfoBanner
var _log_button: Button
var _log_popup: PanelContainer
var _log_panel: LogPanel
var _start_battle_button: Button
var _battle_ready_count_label: Label
var _reserved_seat_toggle: CheckButton
var _countdown_label: Label
var _battle_info_label: RichTextLabel
var _slow_mode_label: Label
var _result_label: Label
var _developer_panel: DeveloperPanel
var _transition_timer: float = -1.0
var _handled_finish: bool = false
var _hovered_player_runtime_id: String = ""
var _processed_battle_event_count: int = 0
var _processed_vfx_event_count: int = 0
var _lan_battle_event_total: int = 0
var _lan_snapshot_initialized: bool = false
var _lan_mode: bool = false
var _spectator_mode: bool = false
var _local_side: String = "player"
var _local_run: RunState
var _opponent_run: RunState
var _lan_snapshot_elapsed: float = 0.0
var _network_clock: NetworkBattleClock = NetworkBattleClock.new()
var _lan_finish_submitted: bool = false


func _ready() -> void:
	_build_ui()
	_lan_mode = NetworkManager.has_active_match()
	if _lan_mode:
		_connect_lan_signals()
		if not _setup_lan_battle():
			_go_to_network_lobby()
			return
		set_process(true)
		_refresh_ui(1.0)
		if Game.is_developer_mode_enabled():
			_build_developer_panel()
		return
	if Game.current_run == null:
		SceneRouter.go_to_hub()
		return

	var enemy_id: String = Game.prepare_next_battle()
	_engine.setup(Game.current_run, enemy_id)
	_processed_battle_event_count = 0
	_processed_vfx_event_count = 0
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
	if _lan_mode:
		_process_lan_battle(delta)
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


func _setup_lan_battle() -> bool:
	var payload: Dictionary = NetworkManager.get_match_payload()
	var player_run: RunState = NetworkManager.get_match_run("player")
	var enemy_run: RunState = NetworkManager.get_match_run("enemy")
	if payload.is_empty() or player_run == null or enemy_run == null:
		return false
	_spectator_mode = NetworkManager.is_local_match_spectator() or not NetworkManager.can_local_control_match()
	_local_side = "player" if _spectator_mode else NetworkManager.get_local_side()
	_local_run = player_run if _local_side == "player" else enemy_run
	_opponent_run = enemy_run if _local_side == "player" else player_run
	_engine.setup_pvp(
		player_run,
		enemy_run,
		String(payload.get("player_name", "Player 1")),
		String(payload.get("enemy_name", "Player 2"))
	)
	_processed_battle_event_count = 0
	_processed_vfx_event_count = 0
	_lan_battle_event_total = 0
	_lan_snapshot_initialized = false
	_network_clock.reset()
	var last_snapshot: Dictionary = NetworkManager.get_last_snapshot()
	if not last_snapshot.is_empty():
		_apply_lan_snapshot(last_snapshot)
	elif NetworkManager.has_battle_countdown_finished():
		_engine.start_battle()
	_timeline_panel.set_fixed_horizon(_compute_timeline_horizon())
	_player_panel.configure_visual("player", _local_run.starter_id)
	_enemy_panel.configure_visual("enemy", _opponent_run.starter_id)
	_card_hand_panel.set_interactive(not _spectator_mode)
	if _spectator_mode:
		_slow_mode_label.text = Localization.get_text("online.battle.spectating", "SPECTATING")
	else:
		_slow_mode_label.text = Localization.get_text("online.battle.host", "WEB HOST") if NetworkManager.is_host() else Localization.get_text("online.battle.client", "WEB GUEST")
	return true


func _process_lan_battle(delta: float) -> void:
	if NetworkManager.is_host():
		if not NetworkManager.is_waiting_for_reconnect():
			_engine.update(delta)
		_lan_snapshot_elapsed += delta
		if _lan_snapshot_elapsed >= LAN_SNAPSHOT_INTERVAL:
			_lan_snapshot_elapsed = fmod(_lan_snapshot_elapsed, LAN_SNAPSHOT_INTERVAL)
			_publish_lan_snapshot(false)
	else:
		var state: BattleState = _engine.battle_state
		if not NetworkManager.is_waiting_for_reconnect() and _engine.has_battle_started() and state.winner == "":
			state.battle_time = _network_clock.advance(delta, NetworkManager.get_connection_ping_ms())

	_refresh_ui(1.0)
	if NetworkManager.is_host() and _engine.battle_state.winner != "" and not _lan_finish_submitted:
		_lan_finish_submitted = true
		_publish_lan_snapshot(true)
		NetworkManager.finish_lan_match(_engine.build_summary(false), NetworkManager.get_last_snapshot())
	if _transition_timer > 0.0:
		_transition_timer -= delta
		if _transition_timer <= 0.0:
			_advance_after_battle()


func _publish_lan_snapshot(reliable: bool) -> void:
	var snapshot: Dictionary = BattleStateCodec.encode(
		_engine.battle_state,
		_engine.has_battle_started(),
		true
	)
	NetworkManager.publish_battle_snapshot(snapshot, reliable)


func _connect_lan_signals() -> void:
	if not NetworkManager.battle_snapshot_received.is_connected(_on_lan_snapshot_received):
		NetworkManager.battle_snapshot_received.connect(_on_lan_snapshot_received)
	if not NetworkManager.battle_command_received.is_connected(_on_lan_battle_command_received):
		NetworkManager.battle_command_received.connect(_on_lan_battle_command_received)
	if not NetworkManager.command_result_received.is_connected(_on_lan_command_result_received):
		NetworkManager.command_result_received.connect(_on_lan_command_result_received)
	if not NetworkManager.battle_start_state_changed.is_connected(_on_lan_battle_start_state_changed):
		NetworkManager.battle_start_state_changed.connect(_on_lan_battle_start_state_changed)
	if not NetworkManager.battle_countdown_finished.is_connected(_on_lan_battle_countdown_finished):
		NetworkManager.battle_countdown_finished.connect(_on_lan_battle_countdown_finished)
	if not NetworkManager.match_finished.is_connected(_on_lan_match_finished):
		NetworkManager.match_finished.connect(_on_lan_match_finished)
	if not NetworkManager.connection_state_changed.is_connected(_on_lan_connection_state_changed):
		NetworkManager.connection_state_changed.connect(_on_lan_connection_state_changed)
	if not NetworkManager.session_ended.is_connected(_on_lan_session_ended):
		NetworkManager.session_ended.connect(_on_lan_session_ended)


func _on_lan_snapshot_received(snapshot: Dictionary) -> void:
	_apply_lan_snapshot(snapshot)


func _apply_lan_snapshot(snapshot: Dictionary) -> void:
	var decoded_state: BattleState = BattleStateCodec.decode(snapshot)
	if decoded_state == null:
		return
	var snapshot_started: bool = bool(snapshot.get("battle_started", false))
	var display_battle_time: float = decoded_state.battle_time
	if not NetworkManager.is_host():
		display_battle_time = _network_clock.apply_snapshot(
			decoded_state.battle_time,
			snapshot_started,
			decoded_state.winner != ""
		)
	_lan_battle_event_total = maxi(
		decoded_state.battle_events.size(),
		int(snapshot.get("battle_event_total", decoded_state.battle_events.size()))
	)
	if not NetworkManager.is_host() and not _lan_snapshot_initialized:
		_processed_battle_event_count = _lan_battle_event_total
		_processed_vfx_event_count = _lan_battle_event_total
	_lan_snapshot_initialized = true
	_engine.apply_network_snapshot(decoded_state, snapshot_started)
	if not NetworkManager.is_host() and _engine.battle_state != null:
		_engine.battle_state.battle_time = display_battle_time


func _on_lan_battle_command_received(
	peer_id: int,
	side: String,
	kind: String,
	runtime_id: String,
	sequence: int
) -> void:
	if not _lan_mode or not NetworkManager.is_host():
		return
	var accepted: bool = false
	if kind == "card":
		accepted = _engine.request_use_card(side, runtime_id)
	elif kind == "relic_toggle_on" or kind == "relic_toggle_off":
		accepted = _engine.set_relic_enabled(side, runtime_id, kind == "relic_toggle_on")
	_publish_lan_snapshot(true)
	NetworkManager.send_command_result(peer_id, sequence, accepted, NetworkManager.get_last_snapshot())


func _on_lan_command_result_received(_sequence: int, accepted: bool, _snapshot: Dictionary) -> void:
	if not accepted:
		AudioManager.play_sfx("ui_error")


func _on_lan_battle_start_state_changed(_state: Dictionary) -> void:
	if _lan_mode and is_inside_tree():
		_refresh_ui(1.0)


func _on_lan_battle_countdown_finished() -> void:
	if not _lan_mode or _engine.battle_state == null or _engine.has_battle_started():
		return
	_engine.start_battle()
	if NetworkManager.is_host():
		_publish_lan_snapshot(true)
	_refresh_ui(1.0)


func _on_lan_match_finished(result: Dictionary) -> void:
	if not _lan_mode or _handled_finish:
		return
	_handled_finish = true
	_transition_timer = 1.4
	_result_label.visible = true
	var winner: String = String(result.get("winner", "draw"))
	if _spectator_mode:
		_result_label.text = Localization.get_text("online.battle.match_complete", "MATCH COMPLETE")
	elif winner == "draw":
		_result_label.text = Localization.get_text("battle.result.draw", "Draw")
	elif winner == _local_side:
		_result_label.text = Localization.get_text("battle.result.victory", "Victory")
	else:
		_result_label.text = Localization.get_text("battle.result.defeat", "Defeat")


func _on_lan_connection_state_changed(_state: int, message: String) -> void:
	if not _lan_mode or _slow_mode_label == null:
		return
	if NetworkManager.is_waiting_for_reconnect():
		_slow_mode_label.text = message


func _on_lan_session_ended(_reason: String) -> void:
	if not _lan_mode or _handled_finish:
		return
	_handled_finish = true
	_result_label.visible = true
	_result_label.text = Localization.get_text("lan.battle.disconnected", "Connection lost")
	_transition_timer = 0.8


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
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	_run_info_banner = RunInfoBanner.new()
	outer.add_child(_run_info_banner)

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

	var left_panel := _create_section(main_split, Localization.get_text("battle.section.enemy", "Enemy"), false, true, false)
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
	_set_section_min_width(center_panel, BATTLE_INFO_MIN_WIDTH)
	_start_battle_button = Button.new()
	_start_battle_button.name = "BattleStartButton"
	_start_battle_button.text = Localization.get_text("battle.start_button", "START")
	_start_battle_button.tooltip_text = Localization.get_text("battle.start_button_tooltip", "Start battle without committing a card")
	_start_battle_button.custom_minimum_size = Vector2(BATTLE_INFO_MIN_WIDTH - 20.0, 38.0)
	_start_battle_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_battle_button.clip_text = true
	_start_battle_button.pressed.connect(_on_start_battle_pressed)
	center_panel.add_child(_start_battle_button)
	_battle_ready_count_label = Label.new()
	_battle_ready_count_label.name = "BattleReadyCountLabel"
	_battle_ready_count_label.custom_minimum_size = Vector2(BATTLE_INFO_MIN_WIDTH, 24.0)
	_battle_ready_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_ready_count_label.add_theme_color_override("font_color", Color(0.42, 0.95, 0.70, 1.0))
	_battle_ready_count_label.visible = false
	center_panel.add_child(_battle_ready_count_label)
	_reserved_seat_toggle = CheckButton.new()
	_reserved_seat_toggle.name = "ReservedSeatToggle"
	_reserved_seat_toggle.text = Localization.get_text("battle.relic.reserved_seat_toggle", "Reserve last slot for interrupts")
	_reserved_seat_toggle.tooltip_text = Localization.get_text("battle.relic.reserved_seat_tooltip", "Toggle Reserved Seat Tag during this battle")
	_reserved_seat_toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reserved_seat_toggle.toggled.connect(_on_reserved_seat_toggled)
	_reserved_seat_toggle.visible = false
	center_panel.add_child(_reserved_seat_toggle)
	_countdown_label = Label.new()
	_countdown_label.name = "BattleCountdownLabel"
	_countdown_label.visible = false
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.clip_text = true
	_countdown_label.custom_minimum_size = Vector2(BATTLE_INFO_MIN_WIDTH, 54.0)
	_countdown_label.add_theme_font_size_override("font_size", 38)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32, 1.0))
	_countdown_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.04, 0.96))
	_countdown_label.add_theme_constant_override("outline_size", 6)
	center_panel.add_child(_countdown_label)
	_battle_info_label = RichTextLabel.new()
	_battle_info_label.name = "BattleInfoLabel"
	_battle_info_label.bbcode_enabled = true
	_battle_info_label.fit_content = true
	_battle_info_label.scroll_active = false
	_battle_info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_battle_info_label.custom_minimum_size = Vector2(BATTLE_INFO_MIN_WIDTH, 0.0)
	_battle_info_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_battle_info_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_panel.add_child(_battle_info_label)

	var right_panel := _create_section(main_split, Localization.get_text("battle.section.player", "Player"), false, true, false)
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

	_vfx_layer = BattleVfxLayer.new()
	_vfx_layer.name = "BattleVfxLayer"
	_vfx_layer.z_index = 70
	_vfx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vfx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_vfx_layer)


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

	if _lan_mode:
		if NetworkManager.is_waiting_for_reconnect():
			_slow_mode_label.text = Localization.get_text("lan.battle.reconnecting", "Connection interrupted - battle paused")
		elif _spectator_mode:
			_slow_mode_label.text = Localization.get_text("online.battle.spectating", "SPECTATING")
		else:
			var ping_key: String = "online.battle.ping" if NetworkManager.is_online_session() else "lan.battle.ping"
			var ping_fallback: String = "ONLINE | Ping {ping} ms" if NetworkManager.is_online_session() else "LAN | Ping {ping} ms"
			_slow_mode_label.text = Localization.get_textf(ping_key, ping_fallback, {
				"ping": NetworkManager.get_connection_ping_ms(),
			})
	elif time_scale < 1.0:
		_slow_mode_label.text = Localization.get_textf("battle.slow_mode_rate", "Slow Mode {rate}%", {
			"rate": int(round(time_scale * 100.0)),
		})
	else:
		_slow_mode_label.text = Localization.get_text("battle.slow_mode_hold", "Hold Space for Slow Mode")
	if _start_battle_button != null:
		var can_start: bool = not _engine.has_battle_started() and battle_state.winner == ""
		if _lan_mode:
			if _spectator_mode:
				_start_battle_button.visible = false
				_battle_ready_count_label.visible = false
				if _countdown_label != null:
					_countdown_label.visible = can_start
					_countdown_label.text = Localization.get_text("online.battle.waiting_players", "Waiting for both players")
			else:
				var local_ready: bool = NetworkManager.is_local_battle_ready()
				var countdown_active: bool = NetworkManager.is_battle_countdown_active()
				_start_battle_button.visible = can_start and not countdown_active
				_start_battle_button.disabled = not can_start or NetworkManager.is_waiting_for_reconnect()
				_start_battle_button.text = Localization.get_text("lan.battle.cancel_start", "CANCEL START") if local_ready else Localization.get_text("lan.battle.start_ready", "BATTLE START")
				_battle_ready_count_label.visible = can_start
				_battle_ready_count_label.text = Localization.get_textf("network.ready_count", "READY {ready}/{total}", {
					"ready": NetworkManager.get_battle_ready_count(),
					"total": 2,
				})
				if _countdown_label != null:
					_countdown_label.visible = can_start
					if countdown_active:
						_countdown_label.text = str(maxi(1, ceili(NetworkManager.get_battle_countdown_remaining())))
					elif local_ready:
						_countdown_label.text = Localization.get_text("lan.battle.waiting_start", "WAITING FOR OPPONENT")
						_countdown_label.add_theme_font_size_override("font_size", 20)
					else:
						_countdown_label.text = Localization.get_text("lan.battle.both_start", "BOTH PLAYERS MUST START")
						_countdown_label.add_theme_font_size_override("font_size", 20)
					if countdown_active:
						_countdown_label.add_theme_font_size_override("font_size", 38)
		else:
			_battle_ready_count_label.visible = false
			_start_battle_button.visible = can_start
			_start_battle_button.disabled = not can_start
			if _countdown_label != null:
				_countdown_label.visible = false
	if _reserved_seat_toggle != null:
		var toggle_run: RunState = _local_run if _lan_mode else Game.current_run
		_reserved_seat_toggle.visible = not _spectator_mode and toggle_run != null and toggle_run.relics.has("reserved_seat_tag")
		if _reserved_seat_toggle.visible:
			_reserved_seat_toggle.set_pressed_no_signal(_engine.is_relic_enabled(_local_side, "reserved_seat_tag"))
			_reserved_seat_toggle.disabled = _lan_mode and NetworkManager.is_waiting_for_reconnect()

	var preview_runtime_state: CardRuntimeState = _get_hovered_player_runtime_state(battle_state)
	var preview_card_def: CardDef = _get_hover_preview_card_def(preview_runtime_state)
	var preview_slot_cost: int = _get_hover_preview_slot_cost(preview_runtime_state, preview_card_def)
	var suppressed_shield_losses: Dictionary = _consume_suppressed_shield_decay_losses(battle_state)
	var local_unit: UnitState = battle_state.get_unit(_local_side)
	var opponent_unit: UnitState = battle_state.get_opponent(_local_side)
	if _lan_mode:
		_local_run.temporary_card_modifiers = local_unit.temporary_card_modifiers.duplicate(true)
		_opponent_run.temporary_card_modifiers = opponent_unit.temporary_card_modifiers.duplicate(true)
	if _run_info_banner != null:
		if _lan_mode:
			_run_info_banner.refresh_run(_local_run, local_unit.hp, local_unit.max_hp, "ONLINE" if NetworkManager.is_online_session() else "LAN")
		else:
			_run_info_banner.refresh(local_unit.hp, local_unit.max_hp)
	_enemy_panel.refresh_unit(opponent_unit, 0, int(suppressed_shield_losses.get(opponent_unit.unit_id, 0)))
	_player_panel.refresh_unit(local_unit, preview_slot_cost, int(suppressed_shield_losses.get(local_unit.unit_id, 0)))
	_enemy_cards_panel.refresh_cards(opponent_unit, _opponent_run if _lan_mode else null, "player" if _lan_mode else "enemy")
	_card_hand_panel.refresh_cards(local_unit, _local_run if _lan_mode else Game.current_run, "player")
	var preview_entry: TimelineEntry = _build_hover_preview_entry(battle_state, preview_runtime_state, preview_card_def)
	_timeline_panel.refresh_timeline(
		battle_state.timeline,
		battle_state.battle_time,
		_local_run if _lan_mode else Game.current_run,
		preview_entry,
		preview_card_def,
		_local_side,
		_opponent_run if _lan_mode else null,
		local_unit,
		opponent_unit
	)
	_log_panel.refresh_logs(battle_state.logs)
	var battle_info_text: String = ""
	if _lan_mode:
		var network_title: String = Localization.get_text("online.battle.title", "WEB BATTLE")
		battle_info_text = "\n".join([
			network_title,
			Localization.get_textf("battle.info.time", "Battle Time {value}s", {"value": "%.1f" % battle_state.battle_time}),
			Localization.get_textf("lan.battle.opponent", "Opponent: {value}", {"value": opponent_unit.display_name}),
		])
	else:
		var total_steps: int = max(1, Game.get_map_step_count())
		var display_step: int = min(total_steps, Game.get_current_step_index() + 1)
		battle_info_text = "\n".join([
			Localization.get_textf("battle.info.time", "Battle Time {value}s", {"value": "%.1f" % battle_state.battle_time}),
			Localization.get_textf("battle.info.map_step", "Map Step {current} / {total}", {
				"current": display_step,
				"total": total_steps,
			}),
			Localization.get_textf("battle.info.current_enemy", "Current Enemy: {value}", {"value": battle_state.enemy.display_name}),
		])
	_battle_info_label.text = "[center]%s[/center]" % battle_info_text
	_process_resolution_vfx(battle_state)


func _consume_suppressed_shield_decay_losses(battle_state: BattleState) -> Dictionary:
	var suppressed_by_unit: Dictionary = {}
	if battle_state == null:
		return suppressed_by_unit

	var battle_events: Array[Dictionary] = battle_state.battle_events
	var compact_lan_events: bool = _uses_compact_lan_events()
	var start_index: int = 0 if compact_lan_events else clampi(_processed_battle_event_count, 0, battle_events.size())
	for event_index in range(start_index, battle_events.size()):
		var event_data: Dictionary = Dictionary(battle_events[event_index])
		if compact_lan_events and int(event_data.get("_event_index", -1)) < _processed_battle_event_count:
			continue
		if String(event_data.get("event_type", "")) != "shield_decay":
			continue
		var target_id: String = String(event_data.get("target_id", ""))
		var shield_loss: int = max(0, -int(event_data.get("shield_delta", 0)))
		if target_id == "" or shield_loss <= 0:
			continue
		suppressed_by_unit[target_id] = int(suppressed_by_unit.get(target_id, 0)) + shield_loss
	_processed_battle_event_count = _lan_battle_event_total if compact_lan_events else battle_events.size()
	return suppressed_by_unit


func _process_resolution_vfx(battle_state: BattleState) -> void:
	if battle_state == null or _vfx_layer == null:
		return

	var battle_events: Array[Dictionary] = battle_state.battle_events
	var compact_lan_events: bool = _uses_compact_lan_events()
	var start_index: int = 0 if compact_lan_events else clampi(_processed_vfx_event_count, 0, battle_events.size())
	for event_index in range(start_index, battle_events.size()):
		var event_data: Dictionary = Dictionary(battle_events[event_index])
		if compact_lan_events and int(event_data.get("_event_index", -1)) < _processed_vfx_event_count:
			continue
		if String(event_data.get("event_type", "")) != "resolve_card":
			continue
		var actor_panel: UnitPanel = _resolve_unit_panel(String(event_data.get("actor_id", "")), battle_state)
		var target_panel: UnitPanel = _resolve_unit_panel(String(event_data.get("target_id", "")), battle_state)
		_vfx_layer.play_resolution(event_data, actor_panel, target_panel, _player_panel, _enemy_panel)
	_processed_vfx_event_count = _lan_battle_event_total if compact_lan_events else battle_events.size()


func _uses_compact_lan_events() -> bool:
	return _lan_mode and not NetworkManager.is_host()


func _resolve_unit_panel(unit_id: String, battle_state: BattleState) -> UnitPanel:
	if battle_state == null:
		return null
	var local_unit: UnitState = battle_state.get_unit(_local_side)
	var opponent_unit: UnitState = battle_state.get_opponent(_local_side)
	if unit_id == local_unit.unit_id or unit_id == _local_side:
		return _player_panel
	if unit_id == opponent_unit.unit_id or unit_id != "" and unit_id == ("enemy" if _local_side == "player" else "player"):
		return _enemy_panel
	return null


func _on_card_requested(runtime_id: String) -> void:
	if _spectator_mode:
		AudioManager.play_sfx("ui_error")
		return
	var requested: bool = false
	if _lan_mode and not NetworkManager.has_battle_countdown_finished():
		AudioManager.play_sfx("ui_error")
		return
	if _lan_mode and not NetworkManager.is_host():
		requested = NetworkManager.submit_card_command(runtime_id)
		if requested:
			var local_runtime: CardRuntimeState = _engine.battle_state.get_unit(_local_side).get_runtime_state(runtime_id)
			if local_runtime != null:
				local_runtime.begin_prepare()
			AudioManager.play_sfx("card_commit")
	else:
		requested = _engine.request_use_card(_local_side, runtime_id)
		if _lan_mode and requested:
			_publish_lan_snapshot(true)
	if not requested:
		AudioManager.play_sfx("ui_error")
	elif _hovered_player_runtime_id == runtime_id:
		_hovered_player_runtime_id = ""
	_refresh_ui(SlowModeController.get_time_scale(Input.is_key_pressed(KEY_SPACE)))


func _on_start_battle_pressed() -> void:
	if _spectator_mode:
		return
	var started: bool
	if _lan_mode:
		started = NetworkManager.set_local_battle_ready(not NetworkManager.is_local_battle_ready())
	else:
		started = _engine.start_battle()
	if not started:
		AudioManager.play_sfx("ui_error")
		return
	_refresh_ui(SlowModeController.get_time_scale(Input.is_key_pressed(KEY_SPACE)))


func _on_reserved_seat_toggled(enabled: bool) -> void:
	if _spectator_mode:
		return
	var accepted: bool = false
	if _lan_mode and not NetworkManager.is_host():
		accepted = NetworkManager.submit_relic_toggle("reserved_seat_tag", enabled)
		if accepted:
			_engine.set_relic_enabled(_local_side, "reserved_seat_tag", enabled)
	else:
		accepted = _engine.set_relic_enabled(_local_side, "reserved_seat_tag", enabled)
		if _lan_mode and accepted:
			_publish_lan_snapshot(true)
	if not accepted:
		AudioManager.play_sfx("ui_error")
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
	return battle_state.get_unit(_local_side).get_runtime_state(_hovered_player_runtime_id)


func _get_hover_preview_card_def(runtime_state: CardRuntimeState) -> CardDef:
	var run_state: RunState = _local_run if _lan_mode else Game.current_run
	if runtime_state == null or run_state == null:
		return null
	return CardUpgradeResolver.build_effective_card(runtime_state.card_id, run_state)


func _get_hover_preview_slot_cost(runtime_state: CardRuntimeState, card_def: CardDef) -> int:
	if runtime_state == null or card_def == null:
		return 0
	if not runtime_state.can_use():
		return 0
	if _engine.battle_state == null or not CardEffectResolver.can_pay_shield_cost(_engine.battle_state.get_unit(_local_side), card_def):
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
	var local_unit: UnitState = battle_state.get_unit(_local_side)
	if local_unit.active_slots_used + card_def.active_slot_cost > local_unit.active_slot_max:
		return null
	if not CardEffectResolver.can_pay_shield_cost(local_unit, card_def):
		return null

	var entry: TimelineEntry = TimelineEntry.new()
	entry.instance_id = TIMELINE_PREVIEW_INSTANCE_ID
	entry.owner_side = _local_side
	entry.runtime_id = "preview_%s" % runtime_state.runtime_id
	entry.card_id = runtime_state.card_id
	entry.card_name = card_def.name
	entry.created_at = battle_state.battle_time
	entry.scheduled_time = battle_state.battle_time + card_def.cast_time * local_unit.get_cast_time_multiplier()
	entry.sort_key = entry.scheduled_time - card_def.priority_modifier
	entry.priority_modifier = card_def.priority_modifier
	entry.actor_speed = local_unit.speed
	entry.slot_cost = card_def.active_slot_cost
	entry.interruptible = card_def.interruptible
	return entry


func _compute_timeline_horizon() -> float:
	if _engine.battle_state == null:
		return TimelinePanel.DEFAULT_TIMELINE_HORIZON
	var max_cast_time: float = TimelinePanel.DEFAULT_TIMELINE_HORIZON
	max_cast_time = maxf(max_cast_time, _get_unit_loadout_max_cast_time(
		_engine.battle_state.player,
		NetworkManager.get_match_run("player") if _lan_mode else Game.current_run
	))
	max_cast_time = maxf(max_cast_time, _get_unit_loadout_max_cast_time(
		_engine.battle_state.enemy,
		NetworkManager.get_match_run("enemy") if _lan_mode else null
	))
	return max_cast_time


func _get_unit_loadout_max_cast_time(unit: UnitState, run_state: RunState) -> float:
	var max_cast_time: float = 0.1
	for runtime_state in unit.card_runtime_states:
		var card_def: CardDef = null
		if run_state != null:
			card_def = CardUpgradeResolver.build_effective_card(runtime_state.card_id, run_state)
		else:
			card_def = Database.get_card(runtime_state.card_id)
		if card_def != null:
			max_cast_time = maxf(max_cast_time, card_def.cast_time)
	return max_cast_time


func _on_log_button_pressed() -> void:
	_log_popup.visible = not _log_popup.visible
	AudioManager.play_sfx("ui_toggle")


func _advance_after_battle() -> void:
	if _lan_mode:
		if NetworkManager.has_active_match():
			SceneRouter.go_to_battle()
		elif NetworkManager.is_lan_arena_session_active() and NetworkManager.get_lan_arena_phase() == "preparation" and not NetworkManager.is_local_spectator():
			SceneRouter.go_to_arena()
		else:
			_go_to_network_lobby()
		return
	if Game.current_run == null:
		SceneRouter.go_to_hub()
		return
	match Game.current_screen_hint:
		"result":
			SceneRouter.go_to_result()
		"facility":
			SceneRouter.go_to_facility()
		"map":
			SceneRouter.go_to_map()
		"arena":
			SceneRouter.go_to_arena()
		"reward":
			SceneRouter.go_to_reward()
		_:
			if Game.current_run.run_complete:
				SceneRouter.go_to_result()
			else:
				SceneRouter.go_to_reward()


func _go_to_network_lobby() -> void:
	SceneRouter.go_to_online_lobby()


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
	_force_battle_result(_local_side)


func _on_dev_force_defeat() -> void:
	_force_battle_result("enemy" if _local_side == "player" else "player")


func _on_dev_restore_hp() -> void:
	if _engine.battle_state == null:
		return
	var local_unit: UnitState = _engine.battle_state.get_unit(_local_side)
	local_unit.hp = local_unit.max_hp
	_refresh_ui(SlowModeController.get_time_scale(Input.is_key_pressed(KEY_SPACE)))


func _force_battle_result(winner: String) -> void:
	if _engine.battle_state == null or _handled_finish:
		return
	if _lan_mode:
		if not NetworkManager.is_host():
			AudioManager.play_sfx("ui_error")
			return
		_engine.battle_state.winner = winner
		_engine.battle_state.record_event({
			"time": _engine.battle_state.battle_time,
			"event_type": "developer_forced_result",
			"actor_id": "developer_mode",
			"card_id": "",
			"target_id": winner,
			"result": {"winner": winner},
			"hp_delta": 0,
			"shield_delta": 0,
			"timeline_before": [],
			"timeline_after": [],
		})
		_publish_lan_snapshot(true)
		NetworkManager.finish_lan_match(_engine.build_summary(false), NetworkManager.get_last_snapshot())
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
