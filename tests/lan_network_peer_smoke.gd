extends Node

const TIMEOUT_SECONDS: float = 30.0

var _role: String = ""
var _port: int = LanProtocol.DEFAULT_PORT + 80
var _elapsed: float = 0.0
var _arena_start_requested: bool = false
var _arena_ready_requested: bool = false
var _commands_received: int = 0
var _card_commands_sent: int = 0
var _card_results_received: int = 0
var _finishing: bool = false
var _round_finishing: bool = false
var _battle_screen: Control
var _match_started_count: int = 0
var _disconnect_scheduled: bool = false
var _countdown_seen: bool = false
var _countdown_started_msec: int = 0


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	_parse_arguments()
	NetworkManager.lobby_changed.connect(_on_lobby_changed)
	NetworkManager.arena_preparation_started.connect(_on_arena_preparation_started)
	NetworkManager.arena_preparation_changed.connect(_on_arena_preparation_changed)
	NetworkManager.match_started.connect(_on_match_started)
	NetworkManager.battle_start_state_changed.connect(_on_battle_start_state_changed)
	NetworkManager.battle_countdown_finished.connect(_on_battle_countdown_finished)
	NetworkManager.battle_command_received.connect(_on_battle_command_received)
	NetworkManager.command_result_received.connect(_on_command_result_received)
	NetworkManager.network_error.connect(_on_network_error)
	call_deferred("_start_role")


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= TIMEOUT_SECONDS and not _finishing:
		_fail("timeout")


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lan-smoke-role="):
			_role = argument.trim_prefix("--lan-smoke-role=")
		elif argument.begins_with("--lan-smoke-port="):
			_port = int(argument.trim_prefix("--lan-smoke-port="))


func _start_role() -> void:
	if _role == "host":
		if not NetworkManager.host_lobby("Peer Host", "balanced", _port):
			_fail("host_failed")
	elif _role == "client":
		await get_tree().create_timer(0.35).timeout
		if not NetworkManager.join_lobby("127.0.0.1", "Peer Client", "tempo", _port):
			_fail("join_failed")
	else:
		_fail("missing_role")


func _on_lobby_changed(_snapshot: Dictionary) -> void:
	if NetworkManager.is_lan_arena_session_active():
		return
	if not NetworkManager.is_local_ready():
		NetworkManager.set_local_ready(true)
		return
	if _role == "host" and NetworkManager.can_start_match() and not _arena_start_requested:
		_arena_start_requested = true
		call_deferred("_start_arena")


func _start_arena() -> void:
	if not NetworkManager.start_lan_arena_preparation():
		_fail("arena_start_failed")


func _on_arena_preparation_started(snapshot: Dictionary) -> void:
	if _arena_ready_requested:
		return
	var run_state: RunState = NetworkManager.get_local_arena_run()
	if run_state == null or not run_state.arena_mode or run_state.gold <= 0:
		_fail("arena_run_missing")
		return
	if Array(run_state.arena_shop.get("cards", [])).is_empty():
		_fail("arena_shop_missing")
		return
	if String(snapshot.get("phase", "")) != "preparation":
		_fail("arena_phase_invalid")
		return
	_arena_ready_requested = true
	call_deferred("_finish_arena_preparation")


func _finish_arena_preparation() -> void:
	NetworkManager.submit_arena_action("toggle_card_hold", {"index": 0})
	if not NetworkManager.set_local_arena_ready(true):
		_fail("arena_ready_failed")


func _on_arena_preparation_changed(_snapshot: Dictionary) -> void:
	call_deferred("_finish_client_round_if_ready")


func _finish_client_round_if_ready() -> void:
	if _role != "client" or _finishing or _match_started_count < 2:
		return
	if NetworkManager.get_lan_arena_phase() != "preparation":
		return
	var run_state: RunState = NetworkManager.get_local_arena_run()
	if run_state == null or run_state.arena_losses != 1:
		_fail("client_round_progress_invalid")
		return
	_finishing = true
	print("LAN_NETWORK_SMOKE_OK client arena_round=%d losses=%d countdown=%s" % [
		run_state.arena_round,
		run_state.arena_losses,
		str(_countdown_seen),
	])
	NetworkManager.leave_session("peer_smoke_client_complete")
	get_tree().quit()


func _on_match_started(_payload: Dictionary) -> void:
	_match_started_count += 1
	if not NetworkManager.is_lan_arena_session_active() or NetworkManager.get_lan_arena_phase() != "battle":
		_fail("match_not_in_arena")
		return
	if _battle_screen == null:
		var packed_battle: PackedScene = load("res://scenes/battle/Battle.tscn") as PackedScene
		if packed_battle == null:
			_fail("battle_scene_missing")
			return
		_battle_screen = packed_battle.instantiate() as Control
		add_child(_battle_screen)
	await get_tree().process_frame
	if _match_started_count == 1:
		if NetworkManager.submit_card_command("enemy_0" if _role == "client" else "player_0"):
			_fail("card_accepted_before_countdown")
			return
		if not NetworkManager.set_local_battle_ready(true):
			_fail("battle_ready_failed")
	elif _role == "client" and _match_started_count == 2:
		if not NetworkManager.has_battle_countdown_finished():
			_fail("battle_start_not_restored")
			return
		_send_card("enemy_1", "card_command_after_reconnect_failed")


func _on_battle_start_state_changed(state: Dictionary) -> void:
	if not bool(state.get("countdown_active", false)) or _countdown_seen:
		return
	_countdown_seen = true
	_countdown_started_msec = Time.get_ticks_msec()


func _on_battle_countdown_finished() -> void:
	if not _countdown_seen:
		_fail("countdown_not_announced")
		return
	var elapsed_seconds: float = float(Time.get_ticks_msec() - _countdown_started_msec) / 1000.0
	if elapsed_seconds < 2.5:
		_fail("countdown_too_short")
		return
	if _role == "client" and _match_started_count == 1 and _card_commands_sent == 0:
		call_deferred("_send_first_card")


func _send_first_card() -> void:
	await get_tree().process_frame
	_send_card("enemy_0", "first_card_command_failed")


func _send_card(runtime_id: String, failure_reason: String) -> void:
	if not NetworkManager.submit_card_command(runtime_id):
		_fail(failure_reason)
		return
	_card_commands_sent += 1


func _on_battle_command_received(_peer_id: int, _side: String, kind: String, _runtime_id: String, _sequence: int) -> void:
	if _role != "host" or kind != "card":
		return
	_commands_received += 1
	if _commands_received == 1 and not _disconnect_scheduled:
		_disconnect_scheduled = true
		call_deferred("_drop_remote_after_ack")
	if _commands_received >= 2 and not _round_finishing:
		_round_finishing = true
		call_deferred("_finish_round_and_exit")


func _drop_remote_after_ack() -> void:
	await get_tree().create_timer(0.35).timeout
	if not NetworkManager.developer_disconnect_peer():
		_fail("developer_disconnect_failed")


func _finish_round_and_exit() -> void:
	await get_tree().create_timer(0.55).timeout
	var snapshot: Dictionary = NetworkManager.get_last_snapshot()
	var restored: BattleState = BattleStateCodec.decode(snapshot)
	if restored == null or not bool(snapshot.get("battle_started", false)):
		_fail("host_battle_screen_sync")
		return
	var reconnect_runtime: CardRuntimeState = restored.enemy.get_runtime_state("enemy_1")
	var reconnect_card_prepared: bool = false
	if reconnect_runtime != null:
		for event_value: Variant in restored.battle_events:
			var event_data: Dictionary = Dictionary(event_value)
			if String(event_data.get("event_type", "")) != "prepare_card":
				continue
			if String(event_data.get("actor_id", "")) == "enemy" and String(event_data.get("card_id", "")) == reconnect_runtime.card_id:
				reconnect_card_prepared = true
				break
	if not reconnect_card_prepared:
		_fail("reconnect_card_not_applied")
		return
	if not NetworkManager.finish_lan_match({
		"winner": "player",
		"reason": "peer_smoke_round",
		"battle_time": restored.battle_time,
	}, snapshot):
		_fail("arena_round_finish_failed")
		return
	var run_state: RunState = NetworkManager.get_local_arena_run()
	if run_state == null or run_state.arena_wins != 1 or run_state.arena_pending_rewards.is_empty():
		_fail("host_round_progress_invalid")
		return
	_finishing = true
	print("LAN_NETWORK_SMOKE_OK host commands=%d arena_round=%d wins=%d battle_time=%.2f" % [
		_commands_received,
		run_state.arena_round,
		run_state.arena_wins,
		restored.battle_time,
	])
	await get_tree().create_timer(2.0).timeout
	NetworkManager.leave_session("peer_smoke_complete")
	get_tree().quit()


func _on_command_result_received(_sequence: int, accepted: bool, _snapshot: Dictionary) -> void:
	if _role != "client" or _card_commands_sent <= _card_results_received:
		return
	if not accepted:
		_fail("card_command_rejected")
		return
	_card_results_received += 1
	call_deferred("_finish_client_round_if_ready")


func _on_network_error(code: String, _message: String) -> void:
	if not _finishing:
		_fail(code)


func _fail(reason: String) -> void:
	if _finishing:
		return
	_finishing = true
	push_error("LAN_NETWORK_SMOKE_FAIL %s %s" % [_role, reason])
	NetworkManager.leave_session("peer_smoke_failed")
	get_tree().quit(1)
