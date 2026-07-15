extends Node

signal connection_state_changed(state: int, message: String)
signal lobby_changed(snapshot: Dictionary)
signal discovery_changed(hosts: Array[Dictionary])
signal network_error(code: String, message: String)
signal match_started(payload: Dictionary)
signal battle_snapshot_received(snapshot: Dictionary)
signal battle_command_received(peer_id: int, side: String, kind: String, runtime_id: String, sequence: int)
signal command_result_received(sequence: int, accepted: bool, snapshot: Dictionary)
signal match_finished(result: Dictionary)
signal session_ended(reason: String)
signal arena_preparation_started(snapshot: Dictionary)
signal arena_preparation_changed(snapshot: Dictionary)
signal arena_action_result_received(action: String, accepted: bool, result: Dictionary)
signal arena_session_finished(result: Dictionary)
signal battle_start_state_changed(state: Dictionary)
signal battle_countdown_finished()
signal online_host_status_changed(status: Dictionary)

enum ConnectionState {
	OFFLINE,
	DISCOVERING,
	HOSTING,
	CONNECTING,
	LOBBY,
	ARENA_PREPARATION,
	MATCH,
	RECONNECTING,
}

const DISCOVERY_BEACON_INTERVAL: float = 0.75
const DISCOVERY_ENTRY_LIFETIME_MSEC: int = 2600
const PING_INTERVAL: float = 1.0
const RECONNECT_RETRY_INTERVAL: float = 1.0
const BATTLE_COUNTDOWN_SECONDS: float = 3.0
const SESSION_SCOPE_LAN: String = "lan"
const SESSION_SCOPE_ONLINE: String = "online"
const ONLINE_UPNP_DESCRIPTION: String = "qq Online Arena"

var _state: int = ConnectionState.OFFLINE
var _peer: MultiplayerPeer
var _is_host: bool = false
var _host_port: int = LanProtocol.DEFAULT_PORT
var _last_address: String = "127.0.0.1"
var _local_profile: Dictionary = {}
var _profiles_by_peer: Dictionary = {}
var _peer_sides: Dictionary = {}
var _peer_pings: Dictionary = {}
var _public_lobby_snapshot: Dictionary = {}
var _match_payload: Dictionary = {}
var _match_active: bool = false
var _last_match_result: Dictionary = {}
var _last_snapshot: Dictionary = {}
var _snapshot_sequence: int = 0
var _last_received_snapshot_sequence: int = 0
var _local_command_sequence: int = 0
var _last_command_sequences: Dictionary = {}
var _command_rate_windows: Dictionary = {}
var _ping_elapsed: float = 0.0
var _ping_ms: int = 0
var _discovery_elapsed: float = 0.0
var _discovery_listener: PacketPeerUDP
var _discovery_sender: PacketPeerUDP
var _discovered_hosts: Dictionary = {}
var _waiting_for_reconnect: bool = false
var _reserved_remote_profile: Dictionary = {}
var _reconnect_deadline_msec: int = 0
var _next_reconnect_attempt_msec: int = 0
var _reconnecting: bool = false
var _closing_peer: bool = false
var _explicit_peer_leaves: Dictionary = {}
var _arena_coordinator: LanArenaCoordinator = LanArenaCoordinator.new()
var _arena_session_active: bool = false
var _arena_phase: String = ""
var _arena_session_id: String = ""
var _arena_runs_by_side: Dictionary = {}
var _local_arena_run: RunState
var _arena_ready_by_side: Dictionary = {"player": false, "enemy": false}
var _local_arena_action_sequence: int = 0
var _last_arena_action_sequences: Dictionary = {}
var _battle_ready_by_side: Dictionary = {"player": false, "enemy": false}
var _battle_countdown_active: bool = false
var _battle_countdown_deadline_msec: int = 0
var _battle_countdown_finished: bool = false
var _session_scope: String = SESSION_SCOPE_LAN
var _online_room_code: String = ""
var _online_room_proof: String = ""
var _online_host_status: Dictionary = {}
var _upnp_thread: Thread
var _upnp_instance: UPNP
var _upnp_operation: String = ""
var _upnp_port: int = 0
var _upnp_cancel_requested: bool = false


func _ready() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if _upnp_thread != null:
		var raw_result: Variant = _upnp_thread.wait_to_finish()
		if _upnp_operation == "open" and typeof(raw_result) == TYPE_DICTIONARY:
			var result: Dictionary = Dictionary(raw_result)
			if bool(result.get("mapped", false)):
				var opened_upnp: UPNP = result.get("upnp") as UPNP
				if opened_upnp != null:
					opened_upnp.delete_port_mapping(_upnp_port, "UDP")
		_upnp_thread = null
	if _upnp_instance != null and _upnp_port > 0:
		_upnp_instance.delete_port_mapping(_upnp_port, "UDP")
	_upnp_instance = null


func _process(delta: float) -> void:
	_process_discovery(delta)
	_process_ping(delta)
	_process_reconnect()
	_process_battle_countdown()
	_process_upnp_operation()


func configure_local_player(player_name: String, starter_id: String) -> Dictionary:
	var token: String = String(_local_profile.get("reconnect_token", ""))
	_local_profile = LanProtocol.build_profile(player_name, starter_id, false, token)
	return _local_profile.duplicate(true)


func host_lobby(player_name: String, starter_id: String, port: int = LanProtocol.DEFAULT_PORT) -> bool:
	_clear_session(false)
	_session_scope = SESSION_SCOPE_LAN
	_last_match_result.clear()
	configure_local_player(player_name, starter_id)
	_host_port = LanProtocol.sanitize_port(port)
	_last_address = "127.0.0.1"
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(_host_port, LanProtocol.MAX_PLAYERS - 1)
	if error != OK:
		_emit_error("host_failed", "Unable to host on UDP port %d (error %d)." % [_host_port, error])
		return false
	_peer = peer
	_is_host = true
	multiplayer.multiplayer_peer = _peer
	_profiles_by_peer[1] = _local_profile.duplicate(true)
	_peer_sides[1] = "player"
	_set_state(ConnectionState.HOSTING, "Hosting LAN lobby")
	_start_discovery_sender()
	_broadcast_lobby_state()
	return true


func host_online_lobby(
	player_name: String,
	starter_id: String,
	room_code: String,
	port: int = LanProtocol.DEFAULT_PORT,
	automatic_port_mapping: bool = true
) -> bool:
	_clear_session(false)
	_session_scope = SESSION_SCOPE_ONLINE
	_last_match_result.clear()
	configure_local_player(player_name, starter_id)
	_host_port = LanProtocol.sanitize_port(port)
	_last_address = "127.0.0.1"
	_online_room_code = LanProtocol.sanitize_online_room_code(room_code)
	if _online_room_code == "":
		_online_room_code = LanProtocol.generate_online_room_code()
	_online_room_proof = LanProtocol.build_online_room_proof(_online_room_code)
	if _use_online_enet_test_transport():
		var test_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var test_error: Error = test_peer.create_server(_host_port, LanProtocol.MAX_PLAYERS - 1)
		if test_error != OK:
			_emit_error("host_failed", "Unable to create the online test host (error %d)." % test_error)
			return false
		_peer = test_peer
	else:
		var eos_result: Dictionary = await EosService.create_room(_online_room_proof)
		if not bool(eos_result.get("ok", false)):
			_emit_error(
				String(eos_result.get("error", "eos_host_failed")),
				String(eos_result.get("message", "Unable to create the EOS Relay lobby."))
			)
			return false
		_peer = eos_result.get("peer") as MultiplayerPeer
		if _peer == null:
			_emit_error("eos_peer_missing", "EOS created a lobby without a multiplayer peer.")
			return false
	_is_host = true
	multiplayer.multiplayer_peer = _peer
	_profiles_by_peer[1] = _local_profile.duplicate(true)
	_peer_sides[1] = "player"
	_set_state(ConnectionState.HOSTING, "Hosting through EOS Relay")
	_set_online_host_status("relay", "", "", 0)
	_broadcast_lobby_state()
	return true


func join_lobby(
	address: String,
	player_name: String,
	starter_id: String,
	port: int = LanProtocol.DEFAULT_PORT
) -> bool:
	_clear_session(false)
	_session_scope = SESSION_SCOPE_LAN
	_last_match_result.clear()
	configure_local_player(player_name, starter_id)
	_last_address = address.strip_edges()
	if _last_address == "":
		_last_address = "127.0.0.1"
	_host_port = LanProtocol.sanitize_port(port)
	return _connect_client(false)


func join_online_lobby(
	address: String,
	player_name: String,
	starter_id: String,
	room_code: String,
	port: int = LanProtocol.DEFAULT_PORT
) -> bool:
	_clear_session(false)
	_session_scope = SESSION_SCOPE_ONLINE
	_last_match_result.clear()
	configure_local_player(player_name, starter_id)
	_last_address = address.strip_edges()
	if _last_address == "" and _use_online_enet_test_transport():
		_last_address = "127.0.0.1"
	_host_port = LanProtocol.sanitize_port(port)
	_online_room_code = LanProtocol.sanitize_online_room_code(room_code)
	_online_room_proof = LanProtocol.build_online_room_proof(_online_room_code)
	if _online_room_proof == "":
		_emit_error("invalid_room_code", "Enter the online room code.")
		return false
	if _use_online_enet_test_transport():
		return _connect_client(false)
	var eos_result: Dictionary = await EosService.join_room(_online_room_proof)
	if not bool(eos_result.get("ok", false)):
		_emit_error(
			String(eos_result.get("error", "eos_join_failed")),
			String(eos_result.get("message", "Unable to join the EOS Relay lobby."))
		)
		return false
	_peer = eos_result.get("peer") as MultiplayerPeer
	if _peer == null:
		_emit_error("eos_peer_missing", "EOS joined the lobby without a multiplayer peer.")
		return false
	_is_host = false
	multiplayer.multiplayer_peer = _peer
	_reconnecting = false
	_set_state(ConnectionState.CONNECTING, "Connecting through EOS Relay")
	return true


func leave_session(reason: String = "left") -> void:
	if _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		if _is_host:
			_receive_session_closed_rpc.rpc(reason)
		else:
			_client_leave_rpc.rpc_id(1, reason)
	_clear_session(true)
	session_ended.emit(reason)


func begin_discovery() -> void:
	if _discovery_listener != null:
		return
	var listener: PacketPeerUDP = PacketPeerUDP.new()
	var error: Error = listener.bind(LanProtocol.DISCOVERY_PORT, "*")
	if error != OK:
		return
	_discovery_listener = listener
	if _state == ConnectionState.OFFLINE:
		_set_state(ConnectionState.DISCOVERING, "Searching for LAN lobbies")


func end_discovery() -> void:
	if _discovery_listener != null:
		_discovery_listener.close()
	_discovery_listener = null
	_discovered_hosts.clear()
	if _state == ConnectionState.DISCOVERING:
		_set_state(ConnectionState.OFFLINE, "Offline")


func set_local_starter(starter_id: String) -> bool:
	if _local_profile.is_empty():
		return false
	_local_profile = LanProtocol.update_profile_starter(_local_profile, starter_id)
	_send_or_apply_local_profile()
	return true


func set_local_ready(ready: bool) -> bool:
	if _local_profile.is_empty() or _match_active or _arena_session_active:
		return false
	_local_profile["ready"] = ready
	_send_or_apply_local_profile()
	return true


func is_local_ready() -> bool:
	return bool(_local_profile.get("ready", false))


func can_start_match() -> bool:
	if not _is_host or _match_active or _arena_session_active or _profiles_by_peer.size() != LanProtocol.MAX_PLAYERS:
		return false
	for raw_profile in _profiles_by_peer.values():
		var profile: Dictionary = Dictionary(raw_profile)
		if not bool(profile.get("ready", false)):
			return false
	return true


func start_lan_match() -> bool:
	return start_lan_arena_preparation()


func start_lan_arena_preparation() -> bool:
	if not can_start_match():
		return false
	var guest_peer_id: int = _get_guest_peer_id()
	if guest_peer_id <= 1:
		return false
	var host_profile: Dictionary = Dictionary(_profiles_by_peer.get(1, {}))
	var guest_profile: Dictionary = Dictionary(_profiles_by_peer.get(guest_peer_id, {}))
	var base_seed: int = int(Time.get_ticks_msec() % 2147483646) + 1
	var player_run: RunState = _arena_coordinator.create_run(host_profile, base_seed)
	var enemy_run: RunState = _arena_coordinator.create_run(guest_profile, base_seed + 7919)
	if player_run == null or enemy_run == null:
		return false
	_arena_runs_by_side = {
		"player": player_run,
		"enemy": enemy_run,
	}
	_arena_session_id = "%d-%d" % [base_seed, Time.get_ticks_msec()]
	_arena_session_active = true
	_arena_phase = "preparation"
	_arena_ready_by_side = {"player": false, "enemy": false}
	_last_arena_action_sequences.clear()
	_match_payload.clear()
	_match_active = false
	_last_match_result.clear()
	_last_snapshot.clear()
	_snapshot_sequence = 0
	_last_received_snapshot_sequence = 0
	_local_command_sequence = 0
	_last_command_sequences.clear()
	_command_rate_windows.clear()
	_waiting_for_reconnect = false
	_reserved_remote_profile.clear()
	for raw_peer_id in _profiles_by_peer.keys():
		var peer_id: int = int(raw_peer_id)
		var profile: Dictionary = Dictionary(_profiles_by_peer.get(peer_id, {})).duplicate(true)
		profile["ready"] = false
		_profiles_by_peer[peer_id] = profile
	_local_profile = Dictionary(_profiles_by_peer.get(1, _local_profile)).duplicate(true)
	_set_state(ConnectionState.ARENA_PREPARATION, "%s arena preparation started" % _session_display_name())
	arena_preparation_started.emit(_build_arena_snapshot("player"))
	_send_arena_preparation_state()
	return true


func has_active_match() -> bool:
	return _match_active and not _match_payload.is_empty()


func is_lan_arena_session_active() -> bool:
	return _arena_session_active


func get_lan_arena_phase() -> String:
	return _arena_phase


func get_local_arena_run() -> RunState:
	if _is_host:
		return _arena_runs_by_side.get("player") as RunState
	return _local_arena_run


func get_local_arena_status() -> Dictionary:
	var run_state: RunState = get_local_arena_run()
	if run_state == null:
		return {}
	var local_side: String = get_local_side()
	var opponent_side: String = "enemy" if local_side == "player" else "player"
	var opponent_profile: Dictionary = _get_profile_for_side(opponent_side)
	return _arena_coordinator.build_status(
		run_state,
		String(opponent_profile.get("name", "Opponent")),
		String(opponent_profile.get("starter_id", "balanced")),
		bool(_arena_ready_by_side.get(local_side, false)),
		bool(_arena_ready_by_side.get(opponent_side, false))
	)


func get_local_arena_card_offers() -> Array[Dictionary]:
	var run_state: RunState = get_local_arena_run()
	if run_state == null:
		return []
	return _to_dictionary_array(run_state.arena_shop.get("cards", []))


func get_local_arena_relic_offers() -> Array[Dictionary]:
	var run_state: RunState = get_local_arena_run()
	if run_state == null:
		return []
	return _to_dictionary_array(run_state.arena_shop.get("relics", []))


func get_local_arena_pending_rewards() -> Array[Dictionary]:
	var run_state: RunState = get_local_arena_run()
	if run_state == null:
		return []
	return _arena_coordinator.get_pending_rewards(run_state)


func get_local_arena_loadout_entries() -> Array[Dictionary]:
	return _arena_coordinator.get_loadout_entries(get_local_arena_run())


func is_local_arena_ready() -> bool:
	return bool(_arena_ready_by_side.get(get_local_side(), false))


func submit_arena_action(action: String, payload: Dictionary = {}) -> bool:
	if not _arena_session_active or _arena_phase != "preparation" or _waiting_for_reconnect:
		return false
	var local_side: String = get_local_side()
	if _is_host:
		return _apply_arena_action_for_side(1, local_side, action, payload, 0)
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	_local_arena_action_sequence += 1
	_submit_arena_action_rpc.rpc_id(1, action, payload, _local_arena_action_sequence)
	return true


func set_local_arena_ready(ready: bool) -> bool:
	return submit_arena_action("set_ready", {"ready": ready})


func is_session_connected() -> bool:
	return _is_host or (
		_peer != null
		and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)


func is_host() -> bool:
	return _is_host


func is_waiting_for_reconnect() -> bool:
	return _waiting_for_reconnect or _reconnecting


func get_connection_state() -> int:
	return _state


func get_local_side() -> String:
	if _match_payload.is_empty():
		return "player" if _is_host else "enemy"
	var unique_id: int = multiplayer.get_unique_id()
	return String(Dictionary(_match_payload.get("peer_sides", {})).get(str(unique_id), "player" if _is_host else "enemy"))


func get_match_payload() -> Dictionary:
	return _match_payload.duplicate(true)


func get_match_run(side: String) -> RunState:
	if _match_payload.is_empty():
		return null
	var key: String = "player_run" if side == "player" else "enemy_run"
	return RunState.from_dict(Dictionary(_match_payload.get(key, {})))


func get_local_match_run() -> RunState:
	return get_match_run(get_local_side())


func get_opponent_match_run() -> RunState:
	return get_match_run("enemy" if get_local_side() == "player" else "player")


func get_local_profile() -> Dictionary:
	return _local_profile.duplicate(true)


func get_lobby_snapshot() -> Dictionary:
	return _public_lobby_snapshot.duplicate(true)


func get_lobby_players() -> Array[Dictionary]:
	var players: Array[Dictionary] = []
	for raw_player in Array(_public_lobby_snapshot.get("players", [])):
		players.append(Dictionary(raw_player).duplicate(true))
	return players


func get_discovered_hosts() -> Array[Dictionary]:
	var hosts: Array[Dictionary] = []
	for raw_entry in _discovered_hosts.values():
		hosts.append(Dictionary(raw_entry).duplicate(true))
	hosts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", ""))
	)
	return hosts


func get_last_match_result() -> Dictionary:
	return _last_match_result.duplicate(true)


func get_last_snapshot() -> Dictionary:
	return _last_snapshot.duplicate(true)


func get_connection_ping_ms() -> int:
	if not _is_host:
		return _ping_ms
	var guest_peer_id: int = _get_guest_peer_id()
	return maxi(0, int(_peer_pings.get(guest_peer_id, 0)))


func get_host_port() -> int:
	return _host_port


func get_session_scope() -> String:
	return _session_scope


func is_online_session() -> bool:
	return _session_scope == SESSION_SCOPE_ONLINE


func get_online_room_code() -> String:
	return _online_room_code


func get_online_host_status() -> Dictionary:
	return _online_host_status.duplicate(true)


func publish_battle_snapshot(snapshot: Dictionary, reliable: bool = false) -> bool:
	if not _is_host or not _match_active or snapshot.is_empty():
		return false
	_snapshot_sequence += 1
	var outgoing: Dictionary = snapshot.duplicate(true)
	outgoing["sequence"] = _snapshot_sequence
	outgoing["match_id"] = String(_match_payload.get("match_id", ""))
	outgoing["server_ticks_msec"] = Time.get_ticks_msec()
	_last_snapshot = outgoing.duplicate(true)
	if reliable:
		_receive_battle_snapshot_reliable_rpc.rpc(outgoing)
	else:
		_receive_battle_snapshot_rpc.rpc(outgoing)
	return true


func submit_card_command(runtime_id: String) -> bool:
	if not _battle_countdown_finished:
		return false
	return _submit_local_command("card", runtime_id)


func submit_relic_toggle(relic_id: String, enabled: bool) -> bool:
	if relic_id != "reserved_seat_tag":
		return false
	return _submit_local_command("relic_toggle_on" if enabled else "relic_toggle_off", relic_id)


func submit_start_command() -> bool:
	return set_local_battle_ready(true)


func set_local_battle_ready(ready: bool = true) -> bool:
	if not _match_active or _battle_countdown_active or _battle_countdown_finished:
		return false
	var local_side: String = get_local_side()
	if _is_host:
		return _set_battle_ready(local_side, ready)
	return _submit_local_command("battle_ready", "", {"ready": ready})


func is_local_battle_ready() -> bool:
	return bool(_battle_ready_by_side.get(get_local_side(), false))


func is_battle_countdown_active() -> bool:
	return _battle_countdown_active


func get_battle_countdown_remaining() -> float:
	if not _battle_countdown_active:
		return 0.0
	return maxf(0.0, float(_battle_countdown_deadline_msec - Time.get_ticks_msec()) / 1000.0)


func has_battle_countdown_finished() -> bool:
	return _battle_countdown_finished


func send_command_result(peer_id: int, sequence: int, accepted: bool, snapshot: Dictionary = {}) -> void:
	if not _is_host or peer_id <= 1:
		return
	_command_result_rpc.rpc_id(peer_id, sequence, accepted, snapshot)


func finish_lan_match(summary: Dictionary, final_snapshot: Dictionary = {}) -> bool:
	if not _is_host or not _match_active:
		return false
	var result: Dictionary = summary.duplicate(true)
	result["match_id"] = String(_match_payload.get("match_id", ""))
	result["winner"] = String(summary.get("winner", "draw"))
	result["player_name"] = String(_match_payload.get("player_name", "Host"))
	result["enemy_name"] = String(_match_payload.get("enemy_name", "Guest"))
	if not final_snapshot.is_empty():
		result["final_snapshot"] = final_snapshot.duplicate(true)
	var arena_finished: bool = false
	if _arena_session_active:
		var winner: String = String(result.get("winner", "draw"))
		var player_run: RunState = _arena_runs_by_side.get("player") as RunState
		var enemy_run: RunState = _arena_runs_by_side.get("enemy") as RunState
		var completed_round: int = player_run.arena_round if player_run != null else 0
		var player_snapshot: Dictionary = Dictionary(final_snapshot.get("player", {}))
		var enemy_snapshot: Dictionary = Dictionary(final_snapshot.get("enemy", {}))
		var player_hp: int = int(player_snapshot.get("hp", player_run.player_hp if player_run != null else 1))
		var enemy_hp: int = int(enemy_snapshot.get("hp", enemy_run.player_hp if enemy_run != null else 1))
		if player_snapshot.has("temporary_card_modifiers"):
			player_run.temporary_card_modifiers = Dictionary(player_snapshot.get("temporary_card_modifiers", {})).duplicate(true)
		if enemy_snapshot.has("temporary_card_modifiers"):
			enemy_run.temporary_card_modifiers = Dictionary(enemy_snapshot.get("temporary_card_modifiers", {})).duplicate(true)
		var player_progress: Dictionary = _arena_coordinator.apply_battle_result(player_run, winner == "player", player_hp, int(result.get("player_relic_bonus_gold", 0)))
		var enemy_progress: Dictionary = _arena_coordinator.apply_battle_result(enemy_run, winner == "enemy", enemy_hp, int(result.get("enemy_relic_bonus_gold", 0)))
		arena_finished = bool(player_progress.get("finished", false)) or bool(enemy_progress.get("finished", false))
		if not arena_finished and completed_round > 0 and completed_round % ArenaService.SPECIAL_REWARD_INTERVAL == 0:
			var shared_special_rewards: Array[Dictionary] = _arena_coordinator.assign_shared_special_rewards(
				player_run,
				enemy_run,
				completed_round,
				player_run.seed + completed_round * 6421
			)
			var special_reward_due: bool = not shared_special_rewards.is_empty()
			player_progress["special_reward_due"] = special_reward_due
			enemy_progress["special_reward_due"] = special_reward_due
		result["arena_session_id"] = _arena_session_id
		result["arena_continues"] = not arena_finished
		result["arena_finished"] = arena_finished
		result["player_progress"] = player_progress
		result["enemy_progress"] = enemy_progress
		result["player_arena_wins"] = player_run.arena_wins
		result["enemy_arena_wins"] = enemy_run.arena_wins
		result["player_arena_losses"] = player_run.arena_losses
		result["enemy_arena_losses"] = enemy_run.arena_losses
		_arena_phase = "finished" if arena_finished else "preparation"
		_arena_ready_by_side = {"player": false, "enemy": false}
	_receive_match_finished_rpc.rpc(result)
	_apply_match_finished(result)
	if _arena_session_active:
		if arena_finished:
			_finish_arena_session(String(result.get("winner", "draw")), String(result.get("reason", "arena_complete")))
		else:
			_send_arena_preparation_state()
		return true
	for raw_peer_id in _profiles_by_peer.keys():
		var peer_id: int = int(raw_peer_id)
		var profile: Dictionary = Dictionary(_profiles_by_peer.get(peer_id, {})).duplicate(true)
		profile["ready"] = false
		_profiles_by_peer[peer_id] = profile
	if _profiles_by_peer.has(1):
		_local_profile = Dictionary(_profiles_by_peer[1]).duplicate(true)
	_broadcast_lobby_state()
	return true


func developer_disconnect_peer() -> bool:
	if not _is_host:
		return false
	var guest_peer_id: int = _get_guest_peer_id()
	if guest_peer_id <= 1 or multiplayer.multiplayer_peer == null:
		return false
	multiplayer.multiplayer_peer.disconnect_peer(guest_peer_id)
	return true


func _connect_client(is_reconnect: bool) -> bool:
	_close_peer_only()
	var peer: MultiplayerPeer
	var error: Error = OK
	if _session_scope == SESSION_SCOPE_ONLINE and not _use_online_enet_test_transport():
		peer = EosService.create_reconnect_peer()
		if peer == null:
			error = ERR_CANT_CONNECT
	else:
		var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		error = enet_peer.create_client(_last_address, _host_port)
		peer = enet_peer
	if error != OK:
		if not is_reconnect:
			_emit_error("join_failed", "Unable to create the network client (error %d)." % error)
		return false
	_peer = peer
	_is_host = false
	multiplayer.multiplayer_peer = _peer
	_reconnecting = is_reconnect
	var connection_message: String = "Connecting through EOS Relay" if _session_scope == SESSION_SCOPE_ONLINE else "Connecting to %s:%d" % [_last_address, _host_port]
	_set_state(ConnectionState.RECONNECTING if is_reconnect else ConnectionState.CONNECTING, connection_message)
	return true


func _send_or_apply_local_profile() -> void:
	if _is_host:
		_profiles_by_peer[1] = _local_profile.duplicate(true)
		_broadcast_lobby_state()
		return
	if _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_submit_profile_rpc.rpc_id(1, _local_profile, _online_room_proof)


func _submit_local_command(kind: String, runtime_id: String, extra: Dictionary = {}) -> bool:
	if not _match_active or _is_host:
		return false
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	_local_command_sequence += 1
	var command: Dictionary = {
		"sequence": _local_command_sequence,
		"kind": kind,
		"runtime_id": runtime_id,
		"client_ticks_msec": Time.get_ticks_msec(),
	}
	command.merge(extra, true)
	_submit_battle_command_rpc.rpc_id(1, command)
	return true


func _on_peer_connected(_peer_id: int) -> void:
	if _is_host:
		var next_state: int = ConnectionState.HOSTING
		if _match_active:
			next_state = ConnectionState.MATCH
		elif _arena_session_active:
			next_state = ConnectionState.ARENA_PREPARATION
		_set_state(next_state, "Peer connected; validating content")


func _on_peer_disconnected(peer_id: int) -> void:
	if not _is_host:
		return
	var was_explicit: bool = bool(_explicit_peer_leaves.get(peer_id, false))
	_explicit_peer_leaves.erase(peer_id)
	var disconnected_profile: Dictionary = Dictionary(_profiles_by_peer.get(peer_id, {})).duplicate(true)
	_profiles_by_peer.erase(peer_id)
	_peer_sides.erase(peer_id)
	_peer_pings.erase(peer_id)
	if _arena_session_active and not was_explicit and not disconnected_profile.is_empty():
		_reserved_remote_profile = disconnected_profile
		_waiting_for_reconnect = true
		_reconnect_deadline_msec = Time.get_ticks_msec() + int(LanProtocol.RECONNECT_GRACE_SECONDS * 1000.0)
		_cancel_battle_countdown()
		var reconnect_state: int = ConnectionState.MATCH if _match_active else ConnectionState.ARENA_PREPARATION
		_set_state(reconnect_state, "Opponent disconnected; waiting for reconnection")
		return
	if _match_active:
		finish_lan_match({
			"winner": "player",
			"reason": "opponent_left",
			"battle_time": float(_last_snapshot.get("battle_time", 0.0)),
		}, _last_snapshot)
	elif _arena_session_active:
		_finish_arena_session("player", "opponent_left")
	else:
		_broadcast_lobby_state()


func _on_connected_to_server() -> void:
	if _is_host:
		return
	_submit_profile_rpc.rpc_id(1, _local_profile, _online_room_proof)


func _on_connection_failed() -> void:
	if _closing_peer:
		return
	if _reconnecting:
		_close_peer_only()
		_next_reconnect_attempt_msec = Time.get_ticks_msec() + int(RECONNECT_RETRY_INTERVAL * 1000.0)
		return
	_close_peer_only()
	_set_state(ConnectionState.OFFLINE, "Connection failed")
	_emit_error("connection_failed", "Could not connect to the host.")


func _on_server_disconnected() -> void:
	if _closing_peer:
		return
	if _match_active or _arena_session_active:
		_close_peer_only()
		_reconnecting = true
		_reconnect_deadline_msec = Time.get_ticks_msec() + int(LanProtocol.RECONNECT_GRACE_SECONDS * 1000.0)
		_next_reconnect_attempt_msec = Time.get_ticks_msec() + 250
		_set_state(ConnectionState.RECONNECTING, "Connection lost; reconnecting")
		return
	_close_peer_only()
	_set_state(ConnectionState.OFFLINE, "Host disconnected")
	session_ended.emit("host_disconnected")


@rpc("any_peer", "call_remote", "reliable", 0)
func _submit_profile_rpc(raw_profile: Dictionary, room_proof: String = "") -> void:
	if not _is_host:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 1:
		return
	if _session_scope == SESSION_SCOPE_ONLINE and room_proof != _online_room_proof:
		_reject_peer(sender_id, "invalid_room_code")
		return
	var validation: Dictionary = LanProtocol.validate_profile(raw_profile)
	if not bool(validation.get("valid", false)):
		_reject_peer(sender_id, String(validation.get("error", "invalid_profile")))
		return
	var profile: Dictionary = Dictionary(validation.get("profile", {})).duplicate(true)
	var rejoining: bool = _waiting_for_reconnect and (
		String(profile.get("reconnect_token", "")) == String(_reserved_remote_profile.get("reconnect_token", "reserved"))
	)
	if _waiting_for_reconnect and not rejoining:
		_reject_peer(sender_id, "seat_reserved")
		return
	if not _profiles_by_peer.has(sender_id) and _profiles_by_peer.size() >= LanProtocol.MAX_PLAYERS and not rejoining:
		_reject_peer(sender_id, "lobby_full")
		return
	_profiles_by_peer[sender_id] = profile
	_peer_sides[sender_id] = "enemy"
	if rejoining:
		_reserved_remote_profile.clear()
		_waiting_for_reconnect = false
		if _match_active:
			var sides: Dictionary = Dictionary(_match_payload.get("peer_sides", {})).duplicate(true)
			for raw_side_peer_id in sides.keys():
				if String(sides.get(raw_side_peer_id, "")) == "enemy":
					sides.erase(raw_side_peer_id)
			sides[str(sender_id)] = "enemy"
			_match_payload["peer_sides"] = sides
			_receive_match_started_rpc.rpc_id(sender_id, _match_payload)
			if not _last_snapshot.is_empty():
				_receive_battle_snapshot_reliable_rpc.rpc_id(sender_id, _last_snapshot)
			_broadcast_battle_start_state(sender_id)
			_set_state(ConnectionState.MATCH, "Opponent reconnected")
		else:
			_receive_arena_preparation_state_rpc.rpc_id(sender_id, _build_arena_snapshot("enemy"))
			_set_state(ConnectionState.ARENA_PREPARATION, "Opponent reconnected")
		return
	_set_state(ConnectionState.LOBBY, "%s lobby ready" % _session_display_name())
	_broadcast_lobby_state()


@rpc("authority", "call_remote", "reliable", 0)
func _receive_lobby_state_rpc(snapshot: Dictionary) -> void:
	_public_lobby_snapshot = snapshot.duplicate(true)
	var local_peer_id: int = multiplayer.get_unique_id()
	for raw_player in Array(snapshot.get("players", [])):
		var player_data: Dictionary = Dictionary(raw_player)
		if int(player_data.get("peer_id", -1)) != local_peer_id:
			continue
		_local_profile["ready"] = bool(player_data.get("ready", false))
		_local_profile["starter_id"] = String(player_data.get("starter_id", _local_profile.get("starter_id", "")))
		break
	if not _match_active and not _arena_session_active:
		_set_state(ConnectionState.LOBBY, "%s lobby ready" % _session_display_name())
	lobby_changed.emit(_public_lobby_snapshot.duplicate(true))


@rpc("authority", "call_remote", "reliable", 0)
func _receive_network_error_rpc(code: String, message: String) -> void:
	_emit_error(code, message)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_match_started_rpc(payload: Dictionary) -> void:
	_apply_match_started(payload)


@rpc("any_peer", "call_remote", "reliable", 0)
func _submit_arena_action_rpc(action: String, payload: Dictionary, sequence: int) -> void:
	if not _is_host or not _arena_session_active or _arena_phase != "preparation" or _waiting_for_reconnect:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var side: String = String(_peer_sides.get(sender_id, ""))
	var last_sequence: int = int(_last_arena_action_sequences.get(sender_id, 0))
	if side == "" or sequence <= last_sequence or not _consume_command_rate(sender_id):
		_arena_action_result_rpc.rpc_id(sender_id, action, false, {})
		return
	_last_arena_action_sequences[sender_id] = sequence
	_apply_arena_action_for_side(sender_id, side, action, payload, sequence)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_arena_preparation_state_rpc(snapshot: Dictionary) -> void:
	_apply_arena_preparation_state(snapshot)


@rpc("authority", "call_remote", "reliable", 0)
func _arena_action_result_rpc(action: String, accepted: bool, result: Dictionary) -> void:
	arena_action_result_received.emit(action, accepted, result.duplicate(true))


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_battle_snapshot_rpc(snapshot: Dictionary) -> void:
	_apply_battle_snapshot(snapshot)


@rpc("authority", "call_remote", "reliable", 2)
func _receive_battle_snapshot_reliable_rpc(snapshot: Dictionary) -> void:
	_apply_battle_snapshot(snapshot)


@rpc("any_peer", "call_remote", "reliable", 0)
func _submit_battle_command_rpc(command: Dictionary) -> void:
	if not _is_host or not _match_active or _waiting_for_reconnect:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var side: String = String(_peer_sides.get(sender_id, ""))
	var sequence: int = int(command.get("sequence", 0))
	var kind: String = String(command.get("kind", ""))
	var runtime_id: String = String(command.get("runtime_id", ""))
	var valid: bool = sequence > int(_last_command_sequences.get(sender_id, 0))
	valid = valid and (kind == "card" or kind == "battle_ready" or kind == "relic_toggle_on" or kind == "relic_toggle_off")
	if kind == "card":
		valid = valid and _battle_countdown_finished and LanProtocol.validate_runtime_id(side, runtime_id)
	elif kind == "relic_toggle_on" or kind == "relic_toggle_off":
		valid = valid and runtime_id == "reserved_seat_tag"
	valid = valid and _consume_command_rate(sender_id)
	if not valid:
		send_command_result(sender_id, sequence, false, _last_snapshot)
		return
	_last_command_sequences[sender_id] = sequence
	if kind == "battle_ready":
		var ready: bool = bool(command.get("ready", true))
		var accepted: bool = _set_battle_ready(side, ready)
		send_command_result(sender_id, sequence, accepted, _last_snapshot)
		return
	battle_command_received.emit(sender_id, side, kind, runtime_id, sequence)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_battle_start_state_rpc(state: Dictionary) -> void:
	_apply_battle_start_state(state)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_battle_countdown_finished_rpc(match_id: String) -> void:
	if match_id != String(_match_payload.get("match_id", "")):
		return
	_battle_countdown_active = false
	_battle_countdown_finished = true
	battle_start_state_changed.emit(_build_battle_start_state())
	battle_countdown_finished.emit()


@rpc("authority", "call_remote", "reliable", 0)
func _command_result_rpc(sequence: int, accepted: bool, snapshot: Dictionary) -> void:
	if not snapshot.is_empty():
		_apply_battle_snapshot(snapshot)
	command_result_received.emit(sequence, accepted, snapshot.duplicate(true))


@rpc("authority", "call_remote", "reliable", 0)
func _receive_match_finished_rpc(result: Dictionary) -> void:
	_apply_match_finished(result)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_arena_session_finished_rpc(result: Dictionary) -> void:
	_apply_arena_session_finished(result)


@rpc("any_peer", "call_remote", "reliable", 0)
func _client_leave_rpc(reason: String) -> void:
	if not _is_host:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_explicit_peer_leaves[sender_id] = true
	if _match_active:
		finish_lan_match({
			"winner": "player",
			"reason": reason,
			"battle_time": float(_last_snapshot.get("battle_time", 0.0)),
		}, _last_snapshot)
	elif _arena_session_active:
		_finish_arena_session("player", reason)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_session_closed_rpc(reason: String) -> void:
	_match_active = false
	_arena_session_active = false
	_arena_phase = ""
	_reconnecting = false
	_close_peer_only()
	_set_state(ConnectionState.OFFLINE, "Session closed")
	session_ended.emit(reason)


@rpc("any_peer", "call_remote", "unreliable", 3)
func _ping_rpc(sent_ticks_msec: int) -> void:
	if not _is_host:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_pong_rpc.rpc_id(sender_id, sent_ticks_msec)


@rpc("authority", "call_remote", "unreliable", 3)
func _pong_rpc(sent_ticks_msec: int) -> void:
	_ping_ms = maxi(0, Time.get_ticks_msec() - sent_ticks_msec)
	if _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_report_ping_rpc.rpc_id(1, _ping_ms)


@rpc("any_peer", "call_remote", "unreliable", 3)
func _report_ping_rpc(value: int) -> void:
	if not _is_host:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_peer_pings[sender_id] = clampi(value, 0, 9999)


func _apply_arena_action_for_side(
	peer_id: int,
	side: String,
	action: String,
	payload: Dictionary,
	_sequence: int
) -> bool:
	if not _is_host or not _arena_session_active or _arena_phase != "preparation":
		return false
	if side != "player" and side != "enemy":
		return false
	var run_state: RunState = _arena_runs_by_side.get(side) as RunState
	if run_state == null:
		return false
	var result: Dictionary = {
		"accepted": false,
		"action": action,
		"gold_delta": 0,
	}
	if action == "set_ready":
		var ready: bool = bool(payload.get("ready", true))
		var accepted: bool = not ready or (
			not _arena_coordinator.has_pending_reward(run_state)
			and _arena_coordinator.has_valid_loadout(run_state)
		)
		if accepted:
			_arena_ready_by_side[side] = ready
		result["accepted"] = accepted
		result["ready"] = ready if accepted else bool(_arena_ready_by_side.get(side, false))
	else:
		if bool(_arena_ready_by_side.get(side, false)):
			_send_arena_action_result(peer_id, action, false, result)
			return false
		result = _arena_coordinator.apply_action(
			run_state,
			action,
			payload,
			peer_id == 1 and Game.is_developer_mode_enabled()
		)

	var was_accepted: bool = bool(result.get("accepted", false))
	_send_arena_action_result(peer_id, action, was_accepted, result)
	_send_arena_preparation_state()
	if was_accepted and _are_both_arena_players_ready():
		_start_arena_match_from_preparation()
	return was_accepted


func _send_arena_action_result(peer_id: int, action: String, accepted: bool, result: Dictionary) -> void:
	if peer_id <= 1:
		arena_action_result_received.emit(action, accepted, result.duplicate(true))
	else:
		_arena_action_result_rpc.rpc_id(peer_id, action, accepted, result)


func _send_arena_preparation_state() -> void:
	if not _is_host or not _arena_session_active or _arena_phase != "preparation":
		return
	_apply_arena_preparation_state(_build_arena_snapshot("player"))
	var guest_peer_id: int = _get_guest_peer_id()
	if guest_peer_id > 1:
		_receive_arena_preparation_state_rpc.rpc_id(guest_peer_id, _build_arena_snapshot("enemy"))


func _build_arena_snapshot(side: String) -> Dictionary:
	var run_state: RunState = _arena_runs_by_side.get(side) as RunState
	if run_state == null:
		return {}
	var opponent_side: String = "enemy" if side == "player" else "player"
	var opponent_profile: Dictionary = _get_profile_for_side(opponent_side)
	return {
		"protocol_version": LanProtocol.PROTOCOL_VERSION,
		"content_hash": LanProtocol.build_content_hash(),
		"arena_session_id": _arena_session_id,
		"phase": _arena_phase,
		"local_side": side,
		"run": run_state.to_dict(),
		"ready_by_side": _arena_ready_by_side.duplicate(true),
		"status": _arena_coordinator.build_status(
			run_state,
			String(opponent_profile.get("name", "Opponent")),
			String(opponent_profile.get("starter_id", "balanced")),
			bool(_arena_ready_by_side.get(side, false)),
			bool(_arena_ready_by_side.get(opponent_side, false))
		),
	}


func _apply_arena_preparation_state(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	if int(snapshot.get("protocol_version", -1)) != LanProtocol.PROTOCOL_VERSION:
		_emit_error("protocol_mismatch", "Network protocol versions do not match.")
		return
	if String(snapshot.get("content_hash", "")) != LanProtocol.build_content_hash():
		_emit_error("content_mismatch", "Game data differs from the host.")
		return
	var incoming_session_id: String = String(snapshot.get("arena_session_id", ""))
	var is_new_session: bool = not _arena_session_active or incoming_session_id != _arena_session_id
	_arena_session_active = true
	_arena_session_id = incoming_session_id
	_arena_phase = String(snapshot.get("phase", "preparation"))
	_arena_ready_by_side = Dictionary(snapshot.get("ready_by_side", {})).duplicate(true)
	if not _is_host:
		_local_arena_run = RunState.from_dict(Dictionary(snapshot.get("run", {})))
	_reconnecting = false
	_waiting_for_reconnect = false
	_set_state(ConnectionState.ARENA_PREPARATION, "%s arena preparation" % _session_display_name())
	if is_new_session:
		arena_preparation_started.emit(snapshot.duplicate(true))
	arena_preparation_changed.emit(snapshot.duplicate(true))


func _are_both_arena_players_ready() -> bool:
	return (
		bool(_arena_ready_by_side.get("player", false))
		and bool(_arena_ready_by_side.get("enemy", false))
	)


func _start_arena_match_from_preparation() -> bool:
	if not _is_host or not _are_both_arena_players_ready() or _waiting_for_reconnect:
		return false
	var guest_peer_id: int = _get_guest_peer_id()
	var player_run: RunState = _arena_runs_by_side.get("player") as RunState
	var enemy_run: RunState = _arena_runs_by_side.get("enemy") as RunState
	if guest_peer_id <= 1 or not _arena_coordinator.has_valid_loadout(player_run) or not _arena_coordinator.has_valid_loadout(enemy_run):
		return false
	var seed: int = int(Time.get_ticks_msec() % 2147483646) + 1
	var host_profile: Dictionary = _get_profile_for_side("player")
	var guest_profile: Dictionary = _get_profile_for_side("enemy")
	_match_payload = {
		"protocol_version": LanProtocol.PROTOCOL_VERSION,
		"content_hash": LanProtocol.build_content_hash(),
		"arena_session_id": _arena_session_id,
		"arena_round": maxi(player_run.arena_round, enemy_run.arena_round),
		"match_id": "%s-r%d-%d" % [_arena_session_id, player_run.arena_round, Time.get_ticks_msec()],
		"seed": seed,
		"player_run": player_run.to_dict(),
		"enemy_run": enemy_run.to_dict(),
		"player_name": String(host_profile.get("name", "Host")),
		"enemy_name": String(guest_profile.get("name", "Guest")),
		"peer_sides": {
			"1": "player",
			str(guest_peer_id): "enemy",
		},
	}
	_arena_phase = "battle"
	_match_active = true
	_last_match_result.clear()
	_last_snapshot.clear()
	_snapshot_sequence = 0
	_last_received_snapshot_sequence = 0
	_local_command_sequence = 0
	_last_command_sequences.clear()
	_battle_ready_by_side = {"player": false, "enemy": false}
	_battle_countdown_active = false
	_battle_countdown_deadline_msec = 0
	_battle_countdown_finished = false
	_set_state(ConnectionState.MATCH, "%s arena battle ready" % _session_display_name())
	_receive_match_started_rpc.rpc(_match_payload)
	_apply_match_started(_match_payload)
	_broadcast_battle_start_state()
	return true


func _set_battle_ready(side: String, ready: bool) -> bool:
	if not _is_host or not _match_active or _waiting_for_reconnect:
		return false
	if _battle_countdown_active or _battle_countdown_finished:
		return false
	if side != "player" and side != "enemy":
		return false
	_battle_ready_by_side[side] = ready
	if bool(_battle_ready_by_side.get("player", false)) and bool(_battle_ready_by_side.get("enemy", false)):
		_battle_countdown_active = true
		_battle_countdown_deadline_msec = Time.get_ticks_msec() + int(BATTLE_COUNTDOWN_SECONDS * 1000.0)
	_broadcast_battle_start_state()
	return true


func _cancel_battle_countdown() -> void:
	if not _match_active or _battle_countdown_finished:
		return
	_battle_ready_by_side = {"player": false, "enemy": false}
	_battle_countdown_active = false
	_battle_countdown_deadline_msec = 0
	_battle_countdown_finished = false
	if _is_host:
		_broadcast_battle_start_state()


func _build_battle_start_state() -> Dictionary:
	return {
		"match_id": String(_match_payload.get("match_id", "")),
		"ready_by_side": _battle_ready_by_side.duplicate(true),
		"countdown_active": _battle_countdown_active,
		"countdown_remaining": get_battle_countdown_remaining(),
		"started": _battle_countdown_finished,
	}


func _broadcast_battle_start_state(target_peer_id: int = -1) -> void:
	if not _is_host or not _match_active:
		return
	var state: Dictionary = _build_battle_start_state()
	if target_peer_id > 1:
		_receive_battle_start_state_rpc.rpc_id(target_peer_id, state)
	else:
		_receive_battle_start_state_rpc.rpc(state)
	_apply_battle_start_state(state)


func _apply_battle_start_state(state: Dictionary) -> void:
	if String(state.get("match_id", "")) != String(_match_payload.get("match_id", "")):
		return
	_battle_ready_by_side = Dictionary(state.get("ready_by_side", {})).duplicate(true)
	_battle_countdown_active = bool(state.get("countdown_active", false))
	_battle_countdown_finished = bool(state.get("started", false))
	if _battle_countdown_active:
		var remaining: float = maxf(0.0, float(state.get("countdown_remaining", BATTLE_COUNTDOWN_SECONDS)))
		_battle_countdown_deadline_msec = Time.get_ticks_msec() + int(remaining * 1000.0)
	else:
		_battle_countdown_deadline_msec = 0
	battle_start_state_changed.emit(_build_battle_start_state())


func _process_battle_countdown() -> void:
	if not _is_host or not _match_active or not _battle_countdown_active:
		return
	if Time.get_ticks_msec() < _battle_countdown_deadline_msec:
		return
	_battle_countdown_active = false
	_battle_countdown_deadline_msec = 0
	_battle_countdown_finished = true
	_broadcast_battle_start_state()
	_receive_battle_countdown_finished_rpc.rpc(String(_match_payload.get("match_id", "")))
	battle_countdown_finished.emit()


func _apply_match_started(payload: Dictionary) -> void:
	if int(payload.get("protocol_version", -1)) != LanProtocol.PROTOCOL_VERSION:
		_emit_error("protocol_mismatch", "Network protocol versions do not match.")
		return
	if String(payload.get("content_hash", "")) != LanProtocol.build_content_hash():
		_emit_error("content_mismatch", "Game data differs from the host.")
		return
	var same_match: bool = String(payload.get("match_id", "")) == String(_match_payload.get("match_id", ""))
	_match_payload = payload.duplicate(true)
	_match_active = true
	if String(payload.get("arena_session_id", "")) != "":
		_arena_session_active = true
		_arena_session_id = String(payload.get("arena_session_id", _arena_session_id))
		_arena_phase = "battle"
	_reconnecting = false
	_waiting_for_reconnect = false
	_last_received_snapshot_sequence = 0
	if not same_match:
		_battle_ready_by_side = {"player": false, "enemy": false}
		_battle_countdown_active = false
		_battle_countdown_deadline_msec = 0
		_battle_countdown_finished = false
	_set_state(ConnectionState.MATCH, "%s match active" % _session_display_name())
	match_started.emit(_match_payload.duplicate(true))


func _apply_battle_snapshot(snapshot: Dictionary) -> void:
	if String(snapshot.get("match_id", "")) != String(_match_payload.get("match_id", "")):
		return
	var sequence: int = int(snapshot.get("sequence", 0))
	if sequence <= _last_received_snapshot_sequence:
		return
	_last_received_snapshot_sequence = sequence
	_last_snapshot = snapshot.duplicate(true)
	battle_snapshot_received.emit(_last_snapshot.duplicate(true))


func _apply_match_finished(result: Dictionary) -> void:
	var final_snapshot: Dictionary = Dictionary(result.get("final_snapshot", {}))
	if not final_snapshot.is_empty():
		_apply_battle_snapshot(final_snapshot)
	_match_active = false
	_reconnecting = false
	_waiting_for_reconnect = false
	_last_match_result = result.duplicate(true)
	_local_profile["ready"] = false
	_battle_ready_by_side = {"player": false, "enemy": false}
	_battle_countdown_active = false
	_battle_countdown_deadline_msec = 0
	_battle_countdown_finished = false
	var next_state: int = ConnectionState.OFFLINE
	if is_session_connected():
		next_state = ConnectionState.ARENA_PREPARATION if _arena_session_active else ConnectionState.LOBBY
	_set_state(next_state, "%s match finished" % _session_display_name())
	match_finished.emit(_last_match_result.duplicate(true))


func _finish_arena_session(winner: String, reason: String) -> void:
	if not _is_host or not _arena_session_active:
		return
	var result: Dictionary = {
		"arena_session_id": _arena_session_id,
		"winner": winner,
		"reason": reason,
		"player_run": (_arena_runs_by_side.get("player") as RunState).to_dict(),
		"enemy_run": (_arena_runs_by_side.get("enemy") as RunState).to_dict(),
	}
	_receive_arena_session_finished_rpc.rpc(result)
	_apply_arena_session_finished(result)
	_broadcast_lobby_state()


func _apply_arena_session_finished(result: Dictionary) -> void:
	_arena_session_active = false
	_arena_phase = "finished"
	_match_active = false
	_waiting_for_reconnect = false
	_reconnecting = false
	_battle_ready_by_side = {"player": false, "enemy": false}
	_battle_countdown_active = false
	_battle_countdown_deadline_msec = 0
	_battle_countdown_finished = false
	_local_profile["ready"] = false
	_set_state(ConnectionState.LOBBY if is_session_connected() else ConnectionState.OFFLINE, "%s arena finished" % _session_display_name())
	arena_session_finished.emit(result.duplicate(true))


func _broadcast_lobby_state() -> void:
	if not _is_host:
		return
	var players: Array[Dictionary] = []
	var peer_ids: Array[int] = []
	for raw_peer_id in _profiles_by_peer.keys():
		peer_ids.append(int(raw_peer_id))
	peer_ids.sort()
	for peer_id in peer_ids:
		var profile: Dictionary = Dictionary(_profiles_by_peer.get(peer_id, {}))
		players.append(LanProtocol.build_public_profile(
			profile,
			peer_id,
			String(_peer_sides.get(peer_id, "")),
			int(_peer_pings.get(peer_id, 0))
		))
	_public_lobby_snapshot = {
		"protocol_version": LanProtocol.PROTOCOL_VERSION,
		"content_hash": LanProtocol.build_content_hash(),
		"session_scope": _session_scope,
		"host_port": _host_port,
		"host_addresses": [] if _session_scope == SESSION_SCOPE_ONLINE else LanProtocol.get_lan_addresses(),
		"players": players,
		"can_start": can_start_match(),
		"match_active": _match_active,
		"arena_active": _arena_session_active,
	}
	_receive_lobby_state_rpc.rpc(_public_lobby_snapshot)
	lobby_changed.emit(_public_lobby_snapshot.duplicate(true))


func _reject_peer(peer_id: int, code: String) -> void:
	var message: String = _error_message_for_code(code)
	_receive_network_error_rpc.rpc_id(peer_id, code, message)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func _consume_command_rate(peer_id: int) -> bool:
	var now_msec: int = Time.get_ticks_msec()
	var window: Dictionary = Dictionary(_command_rate_windows.get(peer_id, {
		"started_msec": now_msec,
		"count": 0,
	}))
	if now_msec - int(window.get("started_msec", now_msec)) >= 1000:
		window["started_msec"] = now_msec
		window["count"] = 0
	var count: int = int(window.get("count", 0)) + 1
	window["count"] = count
	_command_rate_windows[peer_id] = window
	return count <= LanProtocol.MAX_COMMANDS_PER_SECOND


func _process_ping(delta: float) -> void:
	if _is_host or _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if _state != ConnectionState.LOBBY and _state != ConnectionState.ARENA_PREPARATION and _state != ConnectionState.MATCH:
		return
	_ping_elapsed += delta
	if _ping_elapsed < PING_INTERVAL:
		return
	_ping_elapsed = 0.0
	_ping_rpc.rpc_id(1, Time.get_ticks_msec())


func _process_reconnect() -> void:
	var now_msec: int = Time.get_ticks_msec()
	if _is_host and _waiting_for_reconnect and now_msec >= _reconnect_deadline_msec:
		_waiting_for_reconnect = false
		if _match_active:
			finish_lan_match({
				"winner": "player",
				"reason": "reconnect_timeout",
				"battle_time": float(_last_snapshot.get("battle_time", 0.0)),
			}, _last_snapshot)
			if _arena_session_active:
				_finish_arena_session("player", "reconnect_timeout")
		elif _arena_session_active:
			_finish_arena_session("player", "reconnect_timeout")
		return
	if not _reconnecting:
		return
	if now_msec >= _reconnect_deadline_msec:
		_match_active = false
		_arena_session_active = false
		_arena_phase = ""
		_reconnecting = false
		_close_peer_only()
		_set_state(ConnectionState.OFFLINE, "Reconnection timed out")
		session_ended.emit("reconnect_timeout")
		return
	if now_msec < _next_reconnect_attempt_msec:
		return
	if _peer != null and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_next_reconnect_attempt_msec = now_msec + int(RECONNECT_RETRY_INTERVAL * 1000.0)
	_connect_client(true)


func _process_discovery(delta: float) -> void:
	_discovery_elapsed += delta
	if _is_host and _discovery_sender != null and _discovery_elapsed >= DISCOVERY_BEACON_INTERVAL:
		_discovery_elapsed = 0.0
		var beacon: Dictionary = {
			"protocol_version": LanProtocol.PROTOCOL_VERSION,
			"content_hash": LanProtocol.build_content_hash(),
			"name": String(_local_profile.get("name", "LAN Host")),
			"port": _host_port,
			"players": _profiles_by_peer.size(),
			"max_players": LanProtocol.MAX_PLAYERS,
		}
		_discovery_sender.put_packet(JSON.stringify(beacon).to_utf8_buffer())
	if _discovery_listener != null:
		_poll_discovery_packets()
	_cleanup_discovery_entries()


func _poll_discovery_packets() -> void:
	var changed: bool = false
	while _discovery_listener.get_available_packet_count() > 0:
		var packet: PackedByteArray = _discovery_listener.get_packet()
		var source_ip: String = _discovery_listener.get_packet_ip()
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var beacon: Dictionary = Dictionary(parsed)
		if int(beacon.get("protocol_version", -1)) != LanProtocol.PROTOCOL_VERSION:
			continue
		if String(beacon.get("content_hash", "")) != LanProtocol.build_content_hash():
			continue
		var port: int = LanProtocol.sanitize_port(int(beacon.get("port", LanProtocol.DEFAULT_PORT)))
		var key: String = "%s:%d" % [source_ip, port]
		_discovered_hosts[key] = {
			"key": key,
			"address": source_ip,
			"port": port,
			"name": String(beacon.get("name", "LAN Host")),
			"players": int(beacon.get("players", 1)),
			"max_players": int(beacon.get("max_players", LanProtocol.MAX_PLAYERS)),
			"expires_msec": Time.get_ticks_msec() + DISCOVERY_ENTRY_LIFETIME_MSEC,
		}
		changed = true
	if changed:
		discovery_changed.emit(get_discovered_hosts())


func _cleanup_discovery_entries() -> void:
	var now_msec: int = Time.get_ticks_msec()
	var expired_keys: Array[String] = []
	for raw_key in _discovered_hosts.keys():
		var key: String = String(raw_key)
		var entry: Dictionary = Dictionary(_discovered_hosts.get(key, {}))
		if int(entry.get("expires_msec", 0)) <= now_msec:
			expired_keys.append(key)
	if expired_keys.is_empty():
		return
	for key in expired_keys:
		_discovered_hosts.erase(key)
	discovery_changed.emit(get_discovered_hosts())


func _start_discovery_sender() -> void:
	if _discovery_sender != null:
		return
	_discovery_sender = PacketPeerUDP.new()
	_discovery_sender.set_broadcast_enabled(true)
	_discovery_sender.set_dest_address("255.255.255.255", LanProtocol.DISCOVERY_PORT)


func _get_guest_peer_id() -> int:
	for raw_peer_id in _profiles_by_peer.keys():
		var peer_id: int = int(raw_peer_id)
		if peer_id != 1:
			return peer_id
	return -1


func _get_profile_for_side(side: String) -> Dictionary:
	if _is_host:
		for raw_peer_id in _peer_sides.keys():
			var peer_id: int = int(raw_peer_id)
			if String(_peer_sides.get(peer_id, "")) == side:
				return Dictionary(_profiles_by_peer.get(peer_id, {})).duplicate(true)
	for raw_player in Array(_public_lobby_snapshot.get("players", [])):
		var player_data: Dictionary = Dictionary(raw_player)
		if String(player_data.get("side", "")) == side:
			return player_data.duplicate(true)
	if side == get_local_side():
		return _local_profile.duplicate(true)
	return {}


func _to_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_item in Array(value):
		result.append(Dictionary(raw_item).duplicate(true))
	return result


func _clear_session(clear_profile: bool) -> void:
	if _session_scope == SESSION_SCOPE_ONLINE and not _use_online_enet_test_transport():
		EosService.leave_room_deferred()
	_close_peer_only()
	if _discovery_sender != null:
		_discovery_sender.close()
	_discovery_sender = null
	_is_host = false
	_profiles_by_peer.clear()
	_peer_sides.clear()
	_peer_pings.clear()
	_public_lobby_snapshot.clear()
	_match_payload.clear()
	_match_active = false
	_arena_session_active = false
	_arena_phase = ""
	_arena_session_id = ""
	_arena_runs_by_side.clear()
	_local_arena_run = null
	_arena_ready_by_side = {"player": false, "enemy": false}
	_local_arena_action_sequence = 0
	_last_arena_action_sequences.clear()
	_battle_ready_by_side = {"player": false, "enemy": false}
	_battle_countdown_active = false
	_battle_countdown_deadline_msec = 0
	_battle_countdown_finished = false
	_last_snapshot.clear()
	_snapshot_sequence = 0
	_last_received_snapshot_sequence = 0
	_local_command_sequence = 0
	_last_command_sequences.clear()
	_command_rate_windows.clear()
	_waiting_for_reconnect = false
	_reserved_remote_profile.clear()
	_reconnecting = false
	_explicit_peer_leaves.clear()
	_session_scope = SESSION_SCOPE_LAN
	_online_room_code = ""
	_online_room_proof = ""
	_online_host_status.clear()
	if clear_profile:
		_local_profile.clear()
	_set_state(ConnectionState.OFFLINE, "Offline")


func _close_peer_only() -> void:
	_closing_peer = true
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_closing_peer = false


func _set_state(next_state: int, message: String) -> void:
	_state = next_state
	connection_state_changed.emit(_state, message)


func _session_display_name() -> String:
	return "Online" if _session_scope == SESSION_SCOPE_ONLINE else "LAN"


func _use_online_enet_test_transport() -> bool:
	return OS.get_cmdline_user_args().has("--online-transport-test-enet")


func _emit_error(code: String, message: String) -> void:
	network_error.emit(code, message)


func _start_upnp_mapping(port: int) -> void:
	if _upnp_thread != null:
		_set_online_host_status("failed", "upnp_busy", "", port)
		return
	_upnp_cancel_requested = false
	_upnp_port = port
	_upnp_operation = "open"
	_upnp_thread = Thread.new()
	var start_error: Error = _upnp_thread.start(Callable(self, "_upnp_open_worker").bind(port))
	if start_error != OK:
		_upnp_thread = null
		_upnp_operation = ""
		_set_online_host_status("failed", "thread_start_failed", "", port)
		return
	_set_online_host_status("opening", "", "", port)


func _request_upnp_close() -> void:
	if _upnp_operation == "open" and _upnp_thread != null:
		_upnp_cancel_requested = true
		return
	if _upnp_thread != null or _upnp_instance == null or _upnp_port <= 0:
		return
	_upnp_operation = "close"
	_upnp_thread = Thread.new()
	var start_error: Error = _upnp_thread.start(
		Callable(self, "_upnp_close_worker").bind(_upnp_instance, _upnp_port)
	)
	if start_error != OK:
		_upnp_thread = null
		_upnp_operation = ""


func _process_upnp_operation() -> void:
	if _upnp_thread == null or _upnp_thread.is_alive():
		return
	var raw_result: Variant = _upnp_thread.wait_to_finish()
	var result: Dictionary = Dictionary(raw_result) if typeof(raw_result) == TYPE_DICTIONARY else {}
	var completed_operation: String = _upnp_operation
	_upnp_thread = null
	_upnp_operation = ""
	if completed_operation == "close":
		_upnp_instance = null
		_upnp_port = 0
		return
	_upnp_instance = result.get("upnp") as UPNP
	var mapped: bool = bool(result.get("mapped", false))
	if _upnp_cancel_requested or not _is_host or _session_scope != SESSION_SCOPE_ONLINE:
		_upnp_cancel_requested = false
		if mapped:
			_request_upnp_close()
		else:
			_upnp_instance = null
			_upnp_port = 0
		return
	if mapped:
		_set_online_host_status(
			"open",
			"",
			String(result.get("external_address", "")),
			_upnp_port
		)
	else:
		_set_online_host_status(
			"failed",
			String(result.get("error", "upnp_failed")),
			String(result.get("external_address", "")),
			_upnp_port
		)


func _set_online_host_status(state: String, error_code: String, external_address: String, port: int) -> void:
	_online_host_status = {
		"state": state,
		"error": error_code,
		"external_address": external_address,
		"port": port,
	}
	online_host_status_changed.emit(_online_host_status.duplicate(true))


func _upnp_open_worker(port: int) -> Dictionary:
	var upnp: UPNP = UPNP.new()
	var discover_result: int = upnp.discover(2500, 2, "InternetGatewayDevice")
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		return {"mapped": false, "error": "discover_%d" % discover_result, "upnp": upnp}
	var gateway: UPNPDevice = upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return {"mapped": false, "error": "no_gateway", "upnp": upnp}
	var external_address: String = gateway.query_external_address()
	var mapping_result: int = upnp.add_port_mapping(port, port, ONLINE_UPNP_DESCRIPTION, "UDP", 0)
	return {
		"mapped": mapping_result == UPNP.UPNP_RESULT_SUCCESS,
		"error": "" if mapping_result == UPNP.UPNP_RESULT_SUCCESS else "mapping_%d" % mapping_result,
		"external_address": external_address,
		"upnp": upnp,
	}


func _upnp_close_worker(upnp: UPNP, port: int) -> Dictionary:
	var close_result: int = upnp.delete_port_mapping(port, "UDP")
	return {"closed": close_result == UPNP.UPNP_RESULT_SUCCESS, "error": close_result}


func _error_message_for_code(code: String) -> String:
	match code:
		"protocol_mismatch":
			return "Network protocol versions do not match."
		"content_mismatch":
			return "Card or relic data differs from the host. Update both PCs to the same build."
		"invalid_starter", "invalid_card", "invalid_deck_size", "loadout_over_limit":
			return "The selected network loadout is invalid."
		"lobby_full":
			return "The network lobby is full."
		"seat_reserved":
			return "The open seat is reserved for a reconnecting player."
		"invalid_room_code":
			return "The online room code is incorrect."
		_:
			return "The %s host rejected the connection (%s)." % [_session_display_name(), code]
