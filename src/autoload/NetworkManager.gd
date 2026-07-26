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
signal online_rooms_changed(rooms: Array[Dictionary])
signal arena_round_results_changed(snapshot: Dictionary)

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
const ONLINE_MIN_TARGET_WINS: int = 1
const ONLINE_MAX_TARGET_WINS: int = 20
const ONLINE_MIN_INITIAL_GOLD: int = 0
const ONLINE_MAX_INITIAL_GOLD: int = 500
const ONLINE_MIN_INITIAL_MAX_HP: int = 20
const ONLINE_MAX_INITIAL_MAX_HP: int = 200
const ONLINE_MIN_SPECIAL_REWARD_INTERVAL: int = 1
const ONLINE_MAX_SPECIAL_REWARD_INTERVAL: int = 10
const ONLINE_MIN_SHOP_PRICE_PERCENT: int = 50
const ONLINE_MAX_SHOP_PRICE_PERCENT: int = 200
const ONLINE_MIN_REROLL_COST: int = 0
const ONLINE_MAX_REROLL_COST: int = 100
const ONLINE_MIN_SHOP_OFFER_COUNT: int = 2
const ONLINE_MAX_SHOP_OFFER_COUNT: int = 10

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
var _arena_runs_by_peer: Dictionary = {}
var _local_arena_run: RunState
var _arena_ready_by_side: Dictionary = {"player": false, "enemy": false}
var _arena_ready_by_peer: Dictionary = {}
var _arena_player_peer_ids: Array[int] = []
var _arena_pairings: Array[Dictionary] = []
var _arena_pair_index: int = 0
var _arena_round_index: int = 0
var _active_match_peer_ids: Array[int] = []
var _arena_standings: Array[Dictionary] = []
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
var _web_signaling: WebRtcSignalingClient = WebRtcSignalingClient.new()
var _web_directory: WebRtcSignalingClient = WebRtcSignalingClient.new()
var _online_rooms: Array[Dictionary] = []
var _online_target_wins: int = ArenaService.TARGET_WINS
var _online_initial_gold: int = ArenaService.INITIAL_GOLD
var _online_initial_max_hp: int = ArenaService.INITIAL_MAX_HP
var _online_special_reward_interval: int = ArenaService.SPECIAL_REWARD_INTERVAL
var _online_shop_price_percent: int = 100
var _online_reroll_cost: int = ArenaService.REROLL_COST
var _online_shop_offer_count: int = ArenaService.SHOP_OFFER_COUNT
var _online_max_players: int = LanProtocol.DEFAULT_PLAYERS
var _local_participant_role: String = LanProtocol.ROLE_PLAYER
var _pending_participant_role: String = ""
var _web_failure_pending: bool = false
var _parallel_match_contexts: Dictionary = {}
var _match_id_by_peer: Dictionary = {}
var _spectator_match_id: String = ""
var _arena_round_results: Array[Dictionary] = []
var _arena_round_results_complete: bool = false
var _arena_round_continue_by_peer: Dictionary = {}
var _arena_public_details: Array[Dictionary] = []
var _arena_details_auto_open_pending: bool = false


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
	if not _web_signaling.transport_ready.is_connected(_on_web_transport_ready):
		_web_signaling.transport_ready.connect(_on_web_transport_ready)
	if not _web_signaling.status_changed.is_connected(_on_web_signaling_status_changed):
		_web_signaling.status_changed.connect(_on_web_signaling_status_changed)
	if not _web_signaling.failed.is_connected(_on_web_signaling_failed):
		_web_signaling.failed.connect(_on_web_signaling_failed)
	if not _web_signaling.participant_role_update_result.is_connected(_on_web_participant_role_update_result):
		_web_signaling.participant_role_update_result.connect(_on_web_participant_role_update_result)
	if not _web_directory.room_list_changed.is_connected(_on_online_room_list_changed):
		_web_directory.room_list_changed.connect(_on_online_room_list_changed)
	if not _web_directory.failed.is_connected(_on_online_directory_failed):
		_web_directory.failed.connect(_on_online_directory_failed)


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
	_web_signaling.poll()
	_web_directory.poll()
	_process_discovery(delta)
	_process_ping(delta)
	_process_reconnect()
	if _parallel_match_contexts.is_empty():
		_process_battle_countdown()
	else:
		_process_parallel_matches(delta)
	_process_upnp_operation()


func configure_local_player(
	player_name: String,
	starter_id: String,
	participant_role: String = LanProtocol.ROLE_PLAYER
) -> Dictionary:
	var token: String = String(_local_profile.get("reconnect_token", ""))
	_local_participant_role = LanProtocol.sanitize_participant_role(participant_role)
	_local_profile = LanProtocol.build_profile(player_name, starter_id, false, token, _local_participant_role)
	return _local_profile.duplicate(true)


func host_lobby(player_name: String, starter_id: String, port: int = LanProtocol.DEFAULT_PORT) -> bool:
	_clear_session(false)
	_session_scope = SESSION_SCOPE_LAN
	_last_match_result.clear()
	configure_local_player(player_name, starter_id)
	_host_port = LanProtocol.sanitize_port(port)
	_last_address = "127.0.0.1"
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(_host_port, LanProtocol.DEFAULT_PLAYERS - 1)
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
	_port: int = LanProtocol.DEFAULT_PORT,
	_automatic_port_mapping: bool = true,
	target_wins: int = ArenaService.TARGET_WINS,
	max_players: int = LanProtocol.DEFAULT_PLAYERS
) -> bool:
	stop_online_room_directory()
	_clear_session(false)
	_session_scope = SESSION_SCOPE_ONLINE
	_online_target_wins = clampi(target_wins, ONLINE_MIN_TARGET_WINS, ONLINE_MAX_TARGET_WINS)
	_online_max_players = LanProtocol.sanitize_player_capacity(max_players)
	_last_match_result.clear()
	configure_local_player(player_name, starter_id)
	_online_room_code = LanProtocol.sanitize_online_room_code(room_code)
	if _online_room_code == "":
		_online_room_code = LanProtocol.generate_online_room_code()
	_online_room_proof = LanProtocol.build_online_room_proof(_online_room_code)
	var start_error: Error = _web_signaling.start_host(
		_online_room_code,
		LanProtocol.PROTOCOL_VERSION,
		LanProtocol.build_content_hash(),
		String(_local_profile.get("name", player_name)),
		_online_target_wins,
		_online_max_players
	)
	if start_error != OK:
		_set_state(ConnectionState.OFFLINE, "Web multiplayer is unavailable")
		return false
	_set_state(ConnectionState.CONNECTING, "Connecting to the Web multiplayer server")
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
	_address: String,
	player_name: String,
	starter_id: String,
	room_code: String,
	_port: int = LanProtocol.DEFAULT_PORT,
	spectator: bool = false
) -> bool:
	stop_online_room_directory()
	_clear_session(false)
	_session_scope = SESSION_SCOPE_ONLINE
	_last_match_result.clear()
	configure_local_player(
		player_name,
		starter_id,
		LanProtocol.ROLE_SPECTATOR if spectator else LanProtocol.ROLE_PLAYER
	)
	_online_room_code = LanProtocol.sanitize_online_room_code(room_code)
	_online_room_proof = LanProtocol.build_online_room_proof(_online_room_code)
	if _online_room_proof == "":
		_emit_error("invalid_room_code", "Enter the online room code.")
		return false
	var start_error: Error = _web_signaling.start_join(
		_online_room_code,
		LanProtocol.PROTOCOL_VERSION,
		LanProtocol.build_content_hash(),
		spectator
	)
	if start_error != OK:
		_set_state(ConnectionState.OFFLINE, "Web multiplayer is unavailable")
		return false
	_set_state(ConnectionState.CONNECTING, "Connecting to the Web multiplayer room")
	return true


func start_online_room_directory() -> bool:
	if not OS.has_feature("web") or is_session_connected():
		return false
	if _web_directory.start_directory(LanProtocol.PROTOCOL_VERSION, LanProtocol.build_content_hash()) != OK:
		return false
	return true


func stop_online_room_directory() -> void:
	_web_directory.close()


func get_online_rooms() -> Array[Dictionary]:
	return _to_dictionary_array(_online_rooms)


func get_online_target_wins() -> int:
	return _online_target_wins


func set_online_target_wins(value: int) -> bool:
	if not _is_host or _session_scope != SESSION_SCOPE_ONLINE or _match_active or _arena_session_active:
		return false
	var target_wins: int = clampi(value, ONLINE_MIN_TARGET_WINS, ONLINE_MAX_TARGET_WINS)
	if target_wins == _online_target_wins:
		return true
	_online_target_wins = target_wins
	_web_signaling.update_room(target_wins, _online_max_players)
	_broadcast_lobby_state()
	return true


func get_online_max_players() -> int:
	return _online_max_players


func set_online_max_players(value: int) -> bool:
	if not _is_host or _session_scope != SESSION_SCOPE_ONLINE or _match_active or _arena_session_active:
		return false
	var capacity: int = LanProtocol.sanitize_player_capacity(value)
	if _get_player_peer_ids().size() > capacity:
		return false
	if capacity == _online_max_players:
		return true
	_online_max_players = capacity
	_web_signaling.update_room(_online_target_wins, _online_max_players)
	_broadcast_lobby_state()
	return true


func get_player_capacity() -> int:
	return _online_max_players if _session_scope == SESSION_SCOPE_ONLINE else LanProtocol.DEFAULT_PLAYERS


func get_lobby_player_count() -> int:
	return _get_player_peer_ids().size()


func get_lobby_spectator_count() -> int:
	return _get_spectator_peer_ids().size()


func is_local_spectator() -> bool:
	return _local_participant_role == LanProtocol.ROLE_SPECTATOR


func is_participant_role_change_pending() -> bool:
	return _pending_participant_role != ""


func set_local_participant_role(role: String) -> bool:
	var resolved_role: String = LanProtocol.sanitize_participant_role(role)
	if _session_scope != SESSION_SCOPE_ONLINE or not is_session_connected():
		return false
	if _arena_session_active or _match_active or _pending_participant_role != "" or _local_profile.is_empty():
		return false
	if resolved_role == _local_participant_role:
		return true
	_pending_participant_role = resolved_role
	if not _web_signaling.update_participant_role(resolved_role):
		_pending_participant_role = ""
		return false
	return true


func is_local_match_spectator() -> bool:
	return get_local_side() == "spectator"


func get_arena_player_count() -> int:
	return _arena_player_peer_ids.size()


func get_arena_standings() -> Array[Dictionary]:
	return _to_dictionary_array(_arena_standings)


func get_arena_participant_statuses() -> Array[Dictionary]:
	var participants: Array[Dictionary] = []
	for standing in _arena_standings:
		var entry: Dictionary = standing.duplicate(true)
		var peer_id: int = int(entry.get("peer_id", -1))
		var run_state: RunState = _arena_runs_by_peer.get(peer_id) as RunState
		entry["ready"] = bool(_arena_ready_by_peer.get(str(peer_id), false))
		entry["target_wins"] = run_state.arena_target_wins if run_state != null else _online_target_wins
		participants.append(entry)
	return participants


func get_arena_pairings() -> Array[Dictionary]:
	return _to_dictionary_array(_arena_pairings)


func is_parallel_arena_round() -> bool:
	return _arena_session_active and (
		not _parallel_match_contexts.is_empty()
		or bool(_match_payload.get("parallel_round", false))
	)


func is_local_waiting_for_round_results() -> bool:
	return (
		_arena_session_active
		and bool(_match_payload.get("parallel_round", false))
		and not _match_active
		and not is_local_spectator()
		and (_arena_phase == "battle" or _arena_phase == "round_result")
	)


func get_arena_round_results_snapshot() -> Dictionary:
	return _build_arena_round_results_snapshot()


func get_arena_public_details() -> Array[Dictionary]:
	return _to_dictionary_array(_arena_public_details)


func request_arena_details_auto_open() -> void:
	_arena_details_auto_open_pending = true


func consume_arena_details_auto_open_request() -> bool:
	if not _arena_details_auto_open_pending:
		return false
	_arena_details_auto_open_pending = false
	return true


func get_online_arena_rules() -> Dictionary:
	return _build_online_arena_rules()


func set_online_arena_rules(rules: Dictionary) -> bool:
	if not _is_host or _session_scope != SESSION_SCOPE_ONLINE or _match_active or _arena_session_active:
		return false
	var sanitized_rules: Dictionary = {
		"initial_gold": clampi(int(rules.get("initial_gold", _online_initial_gold)), ONLINE_MIN_INITIAL_GOLD, ONLINE_MAX_INITIAL_GOLD),
		"initial_max_hp": clampi(int(rules.get("initial_max_hp", _online_initial_max_hp)), ONLINE_MIN_INITIAL_MAX_HP, ONLINE_MAX_INITIAL_MAX_HP),
		"special_reward_interval": clampi(int(rules.get("special_reward_interval", _online_special_reward_interval)), ONLINE_MIN_SPECIAL_REWARD_INTERVAL, ONLINE_MAX_SPECIAL_REWARD_INTERVAL),
		"shop_price_percent": clampi(int(rules.get("shop_price_percent", _online_shop_price_percent)), ONLINE_MIN_SHOP_PRICE_PERCENT, ONLINE_MAX_SHOP_PRICE_PERCENT),
		"reroll_cost": clampi(int(rules.get("reroll_cost", _online_reroll_cost)), ONLINE_MIN_REROLL_COST, ONLINE_MAX_REROLL_COST),
		"shop_offer_count": clampi(int(rules.get("shop_offer_count", _online_shop_offer_count)), ONLINE_MIN_SHOP_OFFER_COUNT, ONLINE_MAX_SHOP_OFFER_COUNT),
	}
	if sanitized_rules == _build_online_arena_rules():
		return true
	_apply_online_arena_rules(sanitized_rules)
	_broadcast_lobby_state()
	return true


func _build_online_arena_rules() -> Dictionary:
	return {
		"initial_gold": _online_initial_gold,
		"initial_max_hp": _online_initial_max_hp,
		"special_reward_interval": _online_special_reward_interval,
		"shop_price_percent": _online_shop_price_percent,
		"reroll_cost": _online_reroll_cost,
		"shop_offer_count": _online_shop_offer_count,
	}


func _apply_online_arena_rules(rules: Dictionary) -> void:
	_online_initial_gold = clampi(
		int(rules.get("initial_gold", _online_initial_gold)),
		ONLINE_MIN_INITIAL_GOLD,
		ONLINE_MAX_INITIAL_GOLD
	)
	_online_initial_max_hp = clampi(
		int(rules.get("initial_max_hp", _online_initial_max_hp)),
		ONLINE_MIN_INITIAL_MAX_HP,
		ONLINE_MAX_INITIAL_MAX_HP
	)
	_online_special_reward_interval = clampi(
		int(rules.get("special_reward_interval", _online_special_reward_interval)),
		ONLINE_MIN_SPECIAL_REWARD_INTERVAL,
		ONLINE_MAX_SPECIAL_REWARD_INTERVAL
	)
	_online_shop_price_percent = clampi(
		int(rules.get("shop_price_percent", _online_shop_price_percent)),
		ONLINE_MIN_SHOP_PRICE_PERCENT,
		ONLINE_MAX_SHOP_PRICE_PERCENT
	)
	_online_reroll_cost = clampi(
		int(rules.get("reroll_cost", _online_reroll_cost)),
		ONLINE_MIN_REROLL_COST,
		ONLINE_MAX_REROLL_COST
	)
	_online_shop_offer_count = clampi(
		int(rules.get("shop_offer_count", _online_shop_offer_count)),
		ONLINE_MIN_SHOP_OFFER_COUNT,
		ONLINE_MAX_SHOP_OFFER_COUNT
	)


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
	if _local_profile.is_empty() or _match_active or _arena_session_active or is_local_spectator():
		return false
	_local_profile["ready"] = ready
	_send_or_apply_local_profile()
	return true


func is_local_ready() -> bool:
	return bool(_local_profile.get("ready", false))


func get_lobby_ready_count() -> int:
	var ready_count: int = 0
	for raw_player in Array(_public_lobby_snapshot.get("players", [])):
		if bool(Dictionary(raw_player).get("ready", false)):
			ready_count += 1
	return ready_count


func get_arena_ready_count() -> int:
	var ready_count: int = 0
	for peer_id in _arena_player_peer_ids:
		if bool(_arena_ready_by_peer.get(str(peer_id), false)):
			ready_count += 1
	return ready_count


func get_battle_ready_count() -> int:
	if is_parallel_arena_round():
		var context: Dictionary = _get_local_parallel_match_context()
		if not context.is_empty():
			var ready_by_side: Dictionary = Dictionary(context.get("ready_by_side", {}))
			return int(bool(ready_by_side.get("player", false))) + int(bool(ready_by_side.get("enemy", false)))
	return int(bool(_battle_ready_by_side.get("player", false))) + int(bool(_battle_ready_by_side.get("enemy", false)))


func can_start_match() -> bool:
	if not _is_host or _match_active or _arena_session_active:
		return false
	var player_peer_ids: Array[int] = _get_player_peer_ids()
	var capacity: int = get_player_capacity()
	if player_peer_ids.size() != capacity or capacity % 2 != 0:
		return false
	for peer_id in player_peer_ids:
		var profile: Dictionary = Dictionary(_profiles_by_peer.get(peer_id, {}))
		if not bool(profile.get("ready", false)):
			return false
	return true


func start_lan_match() -> bool:
	return start_lan_arena_preparation()


func start_lan_arena_preparation() -> bool:
	if not can_start_match():
		return false
	var base_seed: int = int(Time.get_ticks_msec() % 2147483646) + 1
	var arena_rules: Dictionary = {}
	if _session_scope == SESSION_SCOPE_ONLINE:
		arena_rules = _build_online_arena_rules()
		arena_rules["target_wins"] = _online_target_wins
		arena_rules["max_losses"] = _online_target_wins * LanProtocol.MAX_PLAYERS + 1
	_arena_player_peer_ids = _get_player_peer_ids()
	_arena_runs_by_peer.clear()
	for player_index in range(_arena_player_peer_ids.size()):
		var peer_id: int = _arena_player_peer_ids[player_index]
		var profile: Dictionary = Dictionary(_profiles_by_peer.get(peer_id, {}))
		var run_state: RunState = _arena_coordinator.create_run(profile, base_seed + player_index * 7919, arena_rules)
		if run_state == null:
			_arena_runs_by_peer.clear()
			return false
		_arena_runs_by_peer[peer_id] = run_state
	_arena_runs_by_side.clear()
	_arena_session_id = "%d-%d" % [base_seed, Time.get_ticks_msec()]
	_arena_session_active = true
	_arena_phase = "preparation"
	_arena_ready_by_side = {"player": false, "enemy": false}
	_arena_ready_by_peer.clear()
	for peer_id in _arena_player_peer_ids:
		_arena_ready_by_peer[str(peer_id)] = false
	_arena_round_index = 0
	_arena_pair_index = 0
	_arena_pairings = ArenaTournamentCoordinator.build_round_pairings(_arena_player_peer_ids, _arena_round_index)
	_active_match_peer_ids.clear()
	_arena_standings = ArenaTournamentCoordinator.build_standings(_arena_player_peer_ids, _profiles_by_peer, _arena_runs_by_peer)
	_dispose_parallel_match_contexts()
	_match_id_by_peer.clear()
	_spectator_match_id = ""
	_arena_round_results.clear()
	_arena_round_results_complete = false
	_arena_round_continue_by_peer.clear()
	_arena_public_details = _build_arena_public_details()
	_arena_details_auto_open_pending = false
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
	arena_preparation_started.emit(_build_arena_snapshot(1))
	_send_arena_preparation_state()
	_broadcast_lobby_state()
	return true


func has_active_match() -> bool:
	return _match_active and not _match_payload.is_empty()


func is_lan_arena_session_active() -> bool:
	return _arena_session_active


func get_lan_arena_phase() -> String:
	return _arena_phase


func get_local_arena_run() -> RunState:
	if _is_host:
		return _arena_runs_by_peer.get(1) as RunState
	return _local_arena_run


func get_local_arena_status() -> Dictionary:
	var run_state: RunState = get_local_arena_run()
	if run_state == null:
		return {}
	var local_peer_id: int = multiplayer.get_unique_id()
	var opponent_peer_id: int = ArenaTournamentCoordinator.find_opponent_peer_id(_arena_pairings, local_peer_id)
	var opponent_profile: Dictionary = _get_profile_for_peer(opponent_peer_id)
	return _arena_coordinator.build_status(
		run_state,
		String(opponent_profile.get("name", "Opponent")),
		String(opponent_profile.get("starter_id", "balanced")),
		bool(_arena_ready_by_peer.get(str(local_peer_id), false)),
		bool(_arena_ready_by_peer.get(str(opponent_peer_id), false))
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
	return bool(_arena_ready_by_peer.get(str(multiplayer.get_unique_id()), false))


func submit_arena_action(action: String, payload: Dictionary = {}) -> bool:
	if not _arena_session_active or _arena_phase != "preparation" or _waiting_for_reconnect or is_local_spectator():
		return false
	if _is_host:
		return _apply_arena_action_for_peer(1, action, payload, 0)
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


func can_local_control_match() -> bool:
	var side: String = get_local_side()
	return side == "player" or side == "enemy"


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
	var remote_peer_id: int = -1
	for peer_id in _active_match_peer_ids:
		if peer_id != 1:
			remote_peer_id = peer_id
			break
	if remote_peer_id <= 1:
		remote_peer_id = _get_guest_peer_id()
	return maxi(0, int(_peer_pings.get(remote_peer_id, 0)))


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
	if not _match_active or _battle_countdown_active or _battle_countdown_finished or not can_local_control_match():
		return false
	var local_side: String = get_local_side()
	if _is_host:
		if is_parallel_arena_round():
			return _set_parallel_battle_ready(String(_match_payload.get("match_id", "")), local_side, ready)
		return _set_battle_ready(local_side, ready)
	return _submit_local_command("battle_ready", "", {"ready": ready})


func is_local_battle_ready() -> bool:
	if is_parallel_arena_round():
		var context: Dictionary = _get_local_parallel_match_context()
		if not context.is_empty():
			var ready_by_side: Dictionary = Dictionary(context.get("ready_by_side", {}))
			return bool(ready_by_side.get(get_local_side(), false))
	return bool(_battle_ready_by_side.get(get_local_side(), false))


func is_battle_countdown_active() -> bool:
	return _battle_countdown_active


func get_battle_countdown_remaining() -> float:
	if not _battle_countdown_active:
		return 0.0
	return maxf(0.0, float(_battle_countdown_deadline_msec - Time.get_ticks_msec()) / 1000.0)


func has_battle_countdown_finished() -> bool:
	return _battle_countdown_finished


func acknowledge_arena_round_results() -> bool:
	if not _arena_session_active or not _arena_round_results_complete or is_local_spectator():
		return false
	var local_peer_id: int = multiplayer.get_unique_id()
	if _is_host:
		return _acknowledge_round_results_for_peer(local_peer_id)
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	_acknowledge_round_results_rpc.rpc_id(1)
	return true


func developer_force_local_match(winner_side: String) -> bool:
	if not _is_host or not is_parallel_arena_round():
		return false
	var match_id: String = String(_match_payload.get("match_id", ""))
	var context: Dictionary = Dictionary(_parallel_match_contexts.get(match_id, {}))
	var engine: RealtimeBattleEngine = context.get("engine") as RealtimeBattleEngine
	if engine == null or engine.battle_state == null or bool(context.get("finished", false)):
		return false
	if winner_side != "player" and winner_side != "enemy":
		return false
	engine.battle_state.winner = winner_side
	_publish_parallel_context_snapshot(match_id, true)
	_finish_parallel_match(match_id)
	return true


func send_command_result(peer_id: int, sequence: int, accepted: bool, snapshot: Dictionary = {}) -> void:
	if not _is_host or peer_id <= 1:
		return
	_command_result_rpc.rpc_id(peer_id, sequence, accepted, snapshot)


func finish_lan_match(summary: Dictionary, final_snapshot: Dictionary = {}) -> bool:
	if not _is_host or not _match_active:
		return false
	var result: Dictionary = BattleStateCodec.encode_match_summary(summary)
	result["match_id"] = String(_match_payload.get("match_id", ""))
	result["winner"] = String(summary.get("winner", "draw"))
	result["player_name"] = String(_match_payload.get("player_name", "Player"))
	result["enemy_name"] = String(_match_payload.get("enemy_name", "Opponent"))
	if not final_snapshot.is_empty():
		result["final_snapshot"] = final_snapshot.duplicate(true)
	if _arena_session_active:
		var winner: String = String(result.get("winner", "draw"))
		var player_peer_id: int = int(_match_payload.get("player_peer_id", -1))
		var enemy_peer_id: int = int(_match_payload.get("enemy_peer_id", -1))
		var player_run: RunState = _arena_runs_by_peer.get(player_peer_id) as RunState
		var enemy_run: RunState = _arena_runs_by_peer.get(enemy_peer_id) as RunState
		if player_run == null or enemy_run == null:
			return false
		var player_snapshot: Dictionary = Dictionary(final_snapshot.get("player", {}))
		var enemy_snapshot: Dictionary = Dictionary(final_snapshot.get("enemy", {}))
		var player_hp: int = int(player_snapshot.get("hp", player_run.player_hp))
		var enemy_hp: int = int(enemy_snapshot.get("hp", enemy_run.player_hp))
		if player_snapshot.has("temporary_card_modifiers"):
			player_run.temporary_card_modifiers = Dictionary(player_snapshot.get("temporary_card_modifiers", {})).duplicate(true)
		if enemy_snapshot.has("temporary_card_modifiers"):
			enemy_run.temporary_card_modifiers = Dictionary(enemy_snapshot.get("temporary_card_modifiers", {})).duplicate(true)
		var player_progress: Dictionary = _arena_coordinator.apply_battle_result(player_run, winner == "player", player_hp, int(result.get("player_relic_bonus_gold", 0)))
		var enemy_progress: Dictionary = _arena_coordinator.apply_battle_result(enemy_run, winner == "enemy", enemy_hp, int(result.get("enemy_relic_bonus_gold", 0)))
		_arena_standings = ArenaTournamentCoordinator.build_standings(_arena_player_peer_ids, _profiles_by_peer, _arena_runs_by_peer)
		var winner_peer_id: int = player_peer_id if winner == "player" else enemy_peer_id if winner == "enemy" else -1
		var next_pair_index: int = _arena_pair_index + 1
		var round_complete: bool = next_pair_index >= _arena_pairings.size()
		result["arena_session_id"] = _arena_session_id
		result["arena_continues"] = true
		result["arena_finished"] = false
		result["round_complete"] = round_complete
		result["round_index"] = _arena_round_index
		result["pair_index"] = _arena_pair_index
		result["winner_peer_id"] = winner_peer_id
		result["player_progress"] = player_progress
		result["enemy_progress"] = enemy_progress
		result["player_arena_wins"] = player_run.arena_wins
		result["enemy_arena_wins"] = enemy_run.arena_wins
		result["player_arena_losses"] = player_run.arena_losses
		result["enemy_arena_losses"] = enemy_run.arena_losses
		result["standings"] = _arena_standings.duplicate(true)
		_arena_ready_by_side = {"player": false, "enemy": false}
		_arena_phase = "round_result" if round_complete else "between_matches"
		_receive_match_finished_rpc.rpc(result)
		_apply_match_finished(result)
		if not round_complete:
			_arena_pair_index = next_pair_index
			call_deferred("_start_current_pairing_match")
			return true

		var tournament_winner_peer_id: int = _find_tournament_winner_peer_id()
		if tournament_winner_peer_id > 0:
			_finish_arena_session("winner", "target_wins", tournament_winner_peer_id)
			return true
		_prepare_next_tournament_round()
		return true

	_receive_match_finished_rpc.rpc(result)
	_apply_match_finished(result)
	for raw_peer_id in _profiles_by_peer.keys():
		var peer_id: int = int(raw_peer_id)
		var profile: Dictionary = Dictionary(_profiles_by_peer.get(peer_id, {})).duplicate(true)
		profile["ready"] = false
		_profiles_by_peer[peer_id] = profile
	if _profiles_by_peer.has(1):
		_local_profile = Dictionary(_profiles_by_peer[1]).duplicate(true)
	_broadcast_lobby_state()
	return true


func _find_tournament_winner_peer_id() -> int:
	for standing in _arena_standings:
		var peer_id: int = int(standing.get("peer_id", -1))
		var run_state: RunState = _arena_runs_by_peer.get(peer_id) as RunState
		if run_state != null and run_state.arena_wins >= run_state.arena_target_wins:
			return peer_id
	return -1


func _prepare_next_tournament_round() -> void:
	var completed_round: int = _arena_round_index + 1
	var runs: Array[RunState] = []
	for peer_id in _arena_player_peer_ids:
		var run_state: RunState = _arena_runs_by_peer.get(peer_id) as RunState
		if run_state != null:
			runs.append(run_state)
	if not runs.is_empty():
		var interval: int = maxi(1, runs[0].arena_special_reward_interval)
		if completed_round % interval == 0:
			_arena_coordinator.assign_shared_special_rewards_to_runs(
				runs,
				completed_round,
				runs[0].seed + completed_round * 6421
			)
	_arena_round_index += 1
	_arena_pair_index = 0
	_arena_pairings = ArenaTournamentCoordinator.build_round_pairings(_arena_player_peer_ids, _arena_round_index)
	_active_match_peer_ids.clear()
	_arena_runs_by_side.clear()
	_dispose_parallel_match_contexts()
	_match_id_by_peer.clear()
	_spectator_match_id = ""
	_arena_round_results.clear()
	_arena_round_results_complete = false
	_arena_round_continue_by_peer.clear()
	_match_active = false
	_match_payload.clear()
	_last_snapshot.clear()
	_arena_ready_by_peer.clear()
	for peer_id in _arena_player_peer_ids:
		_arena_ready_by_peer[str(peer_id)] = false
	_arena_phase = "preparation"
	_arena_public_details = _build_arena_public_details()
	_send_arena_preparation_state()
	_broadcast_lobby_state()


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
	var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = enet_peer.create_client(_last_address, _host_port)
	if error != OK:
		if not is_reconnect:
			_emit_error("join_failed", "Unable to create the network client (error %d)." % error)
		return false
	_peer = enet_peer
	_is_host = false
	multiplayer.multiplayer_peer = _peer
	_reconnecting = is_reconnect
	var connection_message: String = "Connecting to %s:%d" % [_last_address, _host_port]
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
	if not _match_active or not can_local_control_match():
		return false
	_local_command_sequence += 1
	var command: Dictionary = {
		"sequence": _local_command_sequence,
		"kind": kind,
		"runtime_id": runtime_id,
		"client_ticks_msec": Time.get_ticks_msec(),
	}
	command.merge(extra, true)
	if _is_host:
		if not is_parallel_arena_round():
			return false
		return _apply_parallel_battle_command(1, command)
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	_submit_battle_command_rpc.rpc_id(1, command)
	return true


func _on_peer_connected(_peer_id: int) -> void:
	if _is_host:
		var next_state: int = ConnectionState.HOSTING
		if _match_active or _has_unfinished_parallel_matches():
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
	var disconnected_role: String = String(disconnected_profile.get("role", LanProtocol.ROLE_PLAYER))
	_profiles_by_peer.erase(peer_id)
	_peer_sides.erase(peer_id)
	_peer_pings.erase(peer_id)
	if disconnected_role == LanProtocol.ROLE_SPECTATOR:
		_broadcast_lobby_state()
		return
	if _session_scope == SESSION_SCOPE_ONLINE and _arena_session_active:
		var winner_peer_id: int = -1
		if _active_match_peer_ids.size() == 2:
			winner_peer_id = _active_match_peer_ids[1] if _active_match_peer_ids[0] == peer_id else _active_match_peer_ids[0]
		_finish_arena_session("disconnect", "player_left", winner_peer_id)
		return
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


func _on_web_transport_ready(peer: WebRTCMultiplayerPeer, host_role: bool, room_code: String) -> void:
	if _session_scope != SESSION_SCOPE_ONLINE or room_code != _online_room_code:
		peer.close()
		return
	_peer = peer
	_is_host = host_role
	_reconnecting = false
	multiplayer.multiplayer_peer = _peer
	if _is_host:
		_profiles_by_peer[1] = _local_profile.duplicate(true)
		_peer_sides[1] = "player"
		_set_state(ConnectionState.HOSTING, "Web room %s is ready" % _online_room_code)
		_set_online_host_status("relay", "", "", 0)
		_broadcast_lobby_state()
	else:
		_set_state(ConnectionState.CONNECTING, "Negotiating the WebRTC peer connection")


func _on_web_signaling_status_changed(message: String) -> void:
	if _session_scope != SESSION_SCOPE_ONLINE or message == "":
		return
	connection_state_changed.emit(_state, message)


func _on_web_participant_role_update_result(role: String, accepted: bool, code: String, message: String) -> void:
	_pending_participant_role = ""
	if not accepted:
		_emit_error(code if code != "" else "role_change_rejected", message if message != "" else "Could not change participant role.")
		return
	_local_participant_role = LanProtocol.sanitize_participant_role(role)
	_local_profile["role"] = _local_participant_role
	_local_profile["ready"] = false
	_send_or_apply_local_profile()


func _on_web_signaling_failed(code: String, message: String) -> void:
	if _session_scope != SESSION_SCOPE_ONLINE or _web_failure_pending:
		return
	_web_failure_pending = true
	call_deferred("_finalize_web_signaling_failure", code, message)


func _on_online_room_list_changed(rooms: Array[Dictionary]) -> void:
	_online_rooms = _to_dictionary_array(rooms)
	online_rooms_changed.emit(get_online_rooms())


func _on_online_directory_failed(_code: String, _message: String) -> void:
	_online_rooms.clear()
	online_rooms_changed.emit([])


func _finalize_web_signaling_failure(code: String, message: String) -> void:
	if not _web_failure_pending:
		return
	_web_failure_pending = false
	if _session_scope != SESSION_SCOPE_ONLINE:
		return
	_web_signaling.close()
	_close_peer_only()
	_is_host = false
	_set_state(ConnectionState.OFFLINE, message)
	_emit_error(code, message)


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
	if _session_scope == SESSION_SCOPE_ONLINE:
		_close_peer_only()
		_match_active = false
		_arena_session_active = false
		_arena_phase = ""
		_set_state(ConnectionState.OFFLINE, "Web opponent disconnected")
		session_ended.emit("host_disconnected")
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
	if not _profiles_by_peer.has(sender_id) and not rejoining:
		var participant_role: String = String(profile.get("role", LanProtocol.ROLE_PLAYER))
		if participant_role == LanProtocol.ROLE_SPECTATOR:
			if _get_spectator_peer_ids().size() >= LanProtocol.MAX_SPECTATORS:
				_reject_peer(sender_id, "spectator_full")
				return
		elif _get_player_peer_ids().size() >= get_player_capacity():
			_reject_peer(sender_id, "lobby_full")
			return
	_profiles_by_peer[sender_id] = profile
	_peer_sides[sender_id] = "spectator" if String(profile.get("role", LanProtocol.ROLE_PLAYER)) == LanProtocol.ROLE_SPECTATOR else "waiting"
	if _arena_session_active and String(profile.get("role", LanProtocol.ROLE_PLAYER)) == LanProtocol.ROLE_SPECTATOR:
		_broadcast_lobby_state()
		if _match_active:
			if not _parallel_match_contexts.is_empty() and _spectator_match_id != "":
				var context: Dictionary = Dictionary(_parallel_match_contexts.get(_spectator_match_id, {}))
				var viewer_peer_ids: Array[int] = _to_int_array(context.get("viewer_peer_ids", []))
				if not viewer_peer_ids.has(sender_id):
					viewer_peer_ids.append(sender_id)
				context["viewer_peer_ids"] = viewer_peer_ids
				_parallel_match_contexts[_spectator_match_id] = context
				_match_id_by_peer[sender_id] = _spectator_match_id
				_receive_match_started_rpc.rpc_id(sender_id, Dictionary(context.get("payload", {})))
				var context_snapshot: Dictionary = Dictionary(context.get("last_snapshot", {}))
				if not context_snapshot.is_empty():
					_receive_battle_snapshot_reliable_rpc.rpc_id(sender_id, context_snapshot)
				var start_state: Dictionary = _build_parallel_battle_start_state(context)
				_receive_battle_start_state_rpc.rpc_id(sender_id, start_state)
			else:
				var sides: Dictionary = Dictionary(_match_payload.get("peer_sides", {})).duplicate(true)
				sides[str(sender_id)] = "spectator"
				_match_payload["peer_sides"] = sides
				_receive_match_started_rpc.rpc_id(sender_id, _match_payload)
				if not _last_snapshot.is_empty():
					_receive_battle_snapshot_reliable_rpc.rpc_id(sender_id, _last_snapshot)
				_broadcast_battle_start_state(sender_id)
		else:
			_receive_arena_preparation_state_rpc.rpc_id(sender_id, _build_arena_snapshot(sender_id))
		return
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
			_receive_arena_preparation_state_rpc.rpc_id(sender_id, _build_arena_snapshot(sender_id))
			_set_state(ConnectionState.ARENA_PREPARATION, "Opponent reconnected")
		return
	_set_state(ConnectionState.LOBBY, "%s lobby ready" % _session_display_name())
	_broadcast_lobby_state()


@rpc("authority", "call_remote", "reliable", 0)
func _receive_lobby_state_rpc(snapshot: Dictionary) -> void:
	_public_lobby_snapshot = snapshot.duplicate(true)
	if String(snapshot.get("session_scope", "")) == SESSION_SCOPE_ONLINE:
		_online_target_wins = clampi(
			int(snapshot.get("target_wins", ArenaService.TARGET_WINS)),
			ONLINE_MIN_TARGET_WINS,
			ONLINE_MAX_TARGET_WINS
		)
		_online_max_players = LanProtocol.sanitize_player_capacity(int(snapshot.get("max_players", LanProtocol.DEFAULT_PLAYERS)))
		_apply_online_arena_rules(Dictionary(snapshot.get("arena_rules", {})))
	_arena_round_results = _to_dictionary_array(snapshot.get("arena_round_results", _arena_round_results))
	_arena_round_results_complete = bool(snapshot.get("arena_round_results_complete", _arena_round_results_complete))
	_arena_public_details = _to_dictionary_array(snapshot.get("arena_public_details", _arena_public_details))
	var local_peer_id: int = multiplayer.get_unique_id()
	for raw_player in Array(snapshot.get("players", [])):
		var player_data: Dictionary = Dictionary(raw_player)
		if int(player_data.get("peer_id", -1)) != local_peer_id:
			continue
		_local_profile["ready"] = bool(player_data.get("ready", false))
		_local_profile["starter_id"] = String(player_data.get("starter_id", _local_profile.get("starter_id", "")))
		_local_participant_role = LanProtocol.sanitize_participant_role(String(player_data.get("role", _local_participant_role)))
		_local_profile["role"] = _local_participant_role
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
	var last_sequence: int = int(_last_arena_action_sequences.get(sender_id, 0))
	if not _arena_runs_by_peer.has(sender_id) or sequence <= last_sequence or not _consume_command_rate(sender_id):
		_arena_action_result_rpc.rpc_id(sender_id, action, false, {})
		return
	_last_arena_action_sequences[sender_id] = sequence
	_apply_arena_action_for_peer(sender_id, action, payload, sequence)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_arena_preparation_state_rpc(snapshot: Dictionary) -> void:
	_apply_arena_preparation_state(snapshot)


@rpc("authority", "call_remote", "reliable", 0)
func _arena_action_result_rpc(action: String, accepted: bool, result: Dictionary) -> void:
	arena_action_result_received.emit(action, accepted, result.duplicate(true))


@rpc("authority", "call_remote", "unreliable_ordered", 0)
func _receive_battle_snapshot_rpc(snapshot: Dictionary) -> void:
	_apply_battle_snapshot(snapshot)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_battle_snapshot_reliable_rpc(snapshot: Dictionary) -> void:
	_apply_battle_snapshot(snapshot)


@rpc("any_peer", "call_remote", "reliable", 0)
func _submit_battle_command_rpc(command: Dictionary) -> void:
	if not _is_host or _waiting_for_reconnect:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if not _parallel_match_contexts.is_empty():
		_apply_parallel_battle_command(sender_id, command)
		return
	if not _match_active:
		return
	var side: String = String(Dictionary(_match_payload.get("peer_sides", {})).get(str(sender_id), "spectator"))
	var sequence: int = int(command.get("sequence", 0))
	var kind: String = String(command.get("kind", ""))
	var runtime_id: String = String(command.get("runtime_id", ""))
	var valid: bool = (side == "player" or side == "enemy") and sequence > int(_last_command_sequences.get(sender_id, 0))
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
func _receive_arena_round_results_rpc(snapshot: Dictionary) -> void:
	_apply_arena_round_results_snapshot(snapshot)


@rpc("any_peer", "call_remote", "reliable", 0)
func _acknowledge_round_results_rpc() -> void:
	if not _is_host:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_acknowledge_round_results_for_peer(sender_id)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_arena_session_finished_rpc(result: Dictionary) -> void:
	_apply_arena_session_finished(result)


@rpc("any_peer", "call_remote", "reliable", 0)
func _client_leave_rpc(reason: String) -> void:
	if not _is_host:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_explicit_peer_leaves[sender_id] = true
	var sender_profile: Dictionary = Dictionary(_profiles_by_peer.get(sender_id, {}))
	if String(sender_profile.get("role", LanProtocol.ROLE_PLAYER)) == LanProtocol.ROLE_SPECTATOR:
		_profiles_by_peer.erase(sender_id)
		_peer_sides.erase(sender_id)
		_peer_pings.erase(sender_id)
		_broadcast_lobby_state()
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	if _match_active:
		if _session_scope == SESSION_SCOPE_ONLINE and _arena_session_active:
			var survivor_peer_id: int = -1
			if _active_match_peer_ids.size() == 2:
				survivor_peer_id = _active_match_peer_ids[1] if _active_match_peer_ids[0] == sender_id else _active_match_peer_ids[0]
			_finish_arena_session("disconnect", reason, survivor_peer_id)
		else:
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


@rpc("any_peer", "call_remote", "unreliable", 0)
func _ping_rpc(sent_ticks_msec: int) -> void:
	if not _is_host:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_pong_rpc.rpc_id(sender_id, sent_ticks_msec)


@rpc("authority", "call_remote", "unreliable", 0)
func _pong_rpc(sent_ticks_msec: int) -> void:
	_ping_ms = maxi(0, Time.get_ticks_msec() - sent_ticks_msec)
	if _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_report_ping_rpc.rpc_id(1, _ping_ms)


@rpc("any_peer", "call_remote", "unreliable", 0)
func _report_ping_rpc(value: int) -> void:
	if not _is_host:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_peer_pings[sender_id] = clampi(value, 0, 9999)


func _apply_arena_action_for_peer(
	peer_id: int,
	action: String,
	payload: Dictionary,
	_sequence: int
) -> bool:
	if not _is_host or not _arena_session_active or _arena_phase != "preparation":
		return false
	var run_state: RunState = _arena_runs_by_peer.get(peer_id) as RunState
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
			_arena_ready_by_peer[str(peer_id)] = ready
		result["accepted"] = accepted
		result["ready"] = ready if accepted else bool(_arena_ready_by_peer.get(str(peer_id), false))
	else:
		if bool(_arena_ready_by_peer.get(str(peer_id), false)):
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
	if was_accepted:
		_arena_public_details = _build_arena_public_details()
	_send_arena_preparation_state()
	if was_accepted and _are_all_arena_players_ready():
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
	_apply_arena_preparation_state(_build_arena_snapshot(1))
	for peer_id in _get_all_peer_ids():
		if peer_id > 1:
			_receive_arena_preparation_state_rpc.rpc_id(peer_id, _build_arena_snapshot(peer_id))


func _build_arena_snapshot(peer_id: int) -> Dictionary:
	var run_state: RunState = _arena_runs_by_peer.get(peer_id) as RunState
	var profile: Dictionary = _get_profile_for_peer(peer_id)
	var spectator: bool = String(profile.get("role", LanProtocol.ROLE_PLAYER)) == LanProtocol.ROLE_SPECTATOR
	var opponent_peer_id: int = ArenaTournamentCoordinator.find_opponent_peer_id(_arena_pairings, peer_id)
	var opponent_profile: Dictionary = _get_profile_for_peer(opponent_peer_id)
	var status: Dictionary = {}
	if run_state != null:
		status = _arena_coordinator.build_status(
			run_state,
			String(opponent_profile.get("name", "Opponent")),
			String(opponent_profile.get("starter_id", "balanced")),
			bool(_arena_ready_by_peer.get(str(peer_id), false)),
			bool(_arena_ready_by_peer.get(str(opponent_peer_id), false))
		)
	return {
		"protocol_version": LanProtocol.PROTOCOL_VERSION,
		"content_hash": LanProtocol.build_content_hash(),
		"arena_session_id": _arena_session_id,
		"phase": _arena_phase,
		"local_peer_id": peer_id,
		"spectator": spectator,
		"run": run_state.to_dict() if run_state != null else {},
		"ready_by_side": _arena_ready_by_side.duplicate(true),
		"ready_by_peer": _arena_ready_by_peer.duplicate(true),
		"player_peer_ids": _arena_player_peer_ids.duplicate(),
		"pairings": _arena_pairings.duplicate(true),
		"pair_index": _arena_pair_index,
		"round_index": _arena_round_index,
		"standings": _arena_standings.duplicate(true),
		"round_results": _arena_round_results.duplicate(true),
		"round_results_complete": _arena_round_results_complete,
		"public_details": _arena_public_details.duplicate(true),
		"status": status,
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
	_arena_ready_by_peer = Dictionary(snapshot.get("ready_by_peer", {})).duplicate(true)
	_arena_player_peer_ids = _to_int_array(snapshot.get("player_peer_ids", []))
	_arena_pairings = _to_dictionary_array(snapshot.get("pairings", []))
	_arena_pair_index = int(snapshot.get("pair_index", 0))
	_arena_round_index = int(snapshot.get("round_index", 0))
	_arena_standings = _to_dictionary_array(snapshot.get("standings", []))
	_arena_round_results = _to_dictionary_array(snapshot.get("round_results", []))
	_arena_round_results_complete = bool(snapshot.get("round_results_complete", false))
	_arena_public_details = _to_dictionary_array(snapshot.get("public_details", []))
	_local_participant_role = LanProtocol.ROLE_SPECTATOR if bool(snapshot.get("spectator", false)) else LanProtocol.ROLE_PLAYER
	if not _is_host:
		var run_data: Dictionary = Dictionary(snapshot.get("run", {}))
		_local_arena_run = null if run_data.is_empty() else RunState.from_dict(run_data)
	_reconnecting = false
	_waiting_for_reconnect = false
	_set_state(ConnectionState.ARENA_PREPARATION, "%s arena preparation" % _session_display_name())
	if is_new_session:
		arena_preparation_started.emit(snapshot.duplicate(true))
	arena_preparation_changed.emit(snapshot.duplicate(true))


func _are_all_arena_players_ready() -> bool:
	if _arena_player_peer_ids.is_empty() or _arena_player_peer_ids.size() % 2 != 0:
		return false
	for peer_id in _arena_player_peer_ids:
		if not bool(_arena_ready_by_peer.get(str(peer_id), false)):
			return false
	return true


func _start_arena_match_from_preparation() -> bool:
	if not _is_host or not _are_all_arena_players_ready() or _waiting_for_reconnect:
		return false
	_arena_pair_index = 0
	return _start_parallel_round_matches()


func _start_parallel_round_matches() -> bool:
	if not _is_host or not _arena_session_active or _arena_pairings.is_empty():
		return false
	_dispose_parallel_match_contexts()
	_match_id_by_peer.clear()
	_spectator_match_id = ""
	_arena_round_results.clear()
	_arena_round_results_complete = false
	_arena_round_continue_by_peer.clear()
	_last_command_sequences.clear()
	_command_rate_windows.clear()
	var all_peer_ids: Array[int] = _get_all_peer_ids()
	var spectator_peer_ids: Array[int] = _get_spectator_peer_ids()
	for pair_index in range(_arena_pairings.size()):
		var pairing: Dictionary = _arena_pairings[pair_index]
		var player_peer_id: int = int(pairing.get("player_peer_id", -1))
		var enemy_peer_id: int = int(pairing.get("enemy_peer_id", -1))
		var player_run: RunState = _arena_runs_by_peer.get(player_peer_id) as RunState
		var enemy_run: RunState = _arena_runs_by_peer.get(enemy_peer_id) as RunState
		if player_run == null or enemy_run == null:
			_dispose_parallel_match_contexts()
			_match_id_by_peer.clear()
			return false
		if not _arena_coordinator.has_valid_loadout(player_run) or not _arena_coordinator.has_valid_loadout(enemy_run):
			_dispose_parallel_match_contexts()
			_match_id_by_peer.clear()
			return false
		var match_id: String = "%s-r%d-p%d-%d" % [
			_arena_session_id,
			_arena_round_index + 1,
			pair_index + 1,
			Time.get_ticks_msec() + pair_index,
		]
		var player_profile: Dictionary = _get_profile_for_peer(player_peer_id)
		var enemy_profile: Dictionary = _get_profile_for_peer(enemy_peer_id)
		var peer_sides: Dictionary = ArenaTournamentCoordinator.build_peer_sides(
			all_peer_ids,
			player_peer_id,
			enemy_peer_id
		)
		var payload: Dictionary = {
			"protocol_version": LanProtocol.PROTOCOL_VERSION,
			"content_hash": LanProtocol.build_content_hash(),
			"arena_session_id": _arena_session_id,
			"arena_round": _arena_round_index + 1,
			"pair_index": pair_index,
			"pair_count": _arena_pairings.size(),
			"parallel_round": true,
			"match_id": match_id,
			"seed": int(Time.get_ticks_msec() % 2147483646) + pair_index * 7919 + 1,
			"player_run": player_run.to_dict(),
			"enemy_run": enemy_run.to_dict(),
			"player_name": String(player_profile.get("name", "Player")),
			"enemy_name": String(enemy_profile.get("name", "Opponent")),
			"player_peer_id": player_peer_id,
			"enemy_peer_id": enemy_peer_id,
			"peer_sides": peer_sides,
			"standings": _arena_standings.duplicate(true),
		}
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
		engine.set_audio_enabled(false)
		engine.setup_pvp(
			player_run,
			enemy_run,
			String(payload.get("player_name", "Player")),
			String(payload.get("enemy_name", "Opponent"))
		)
		var viewer_peer_ids: Array[int] = [player_peer_id, enemy_peer_id]
		if pair_index == 0:
			_spectator_match_id = match_id
			for spectator_peer_id in spectator_peer_ids:
				viewer_peer_ids.append(spectator_peer_id)
				_match_id_by_peer[spectator_peer_id] = match_id
		var context: Dictionary = {
			"match_id": match_id,
			"pair_index": pair_index,
			"player_peer_id": player_peer_id,
			"enemy_peer_id": enemy_peer_id,
			"payload": payload,
			"engine": engine,
			"viewer_peer_ids": viewer_peer_ids,
			"ready_by_side": {"player": false, "enemy": false},
			"countdown_active": false,
			"countdown_deadline_msec": 0,
			"countdown_finished": false,
			"snapshot_sequence": 0,
			"snapshot_elapsed": 0.0,
			"last_snapshot": {},
			"finished": false,
			"result": {},
		}
		_parallel_match_contexts[match_id] = context
		_match_id_by_peer[player_peer_id] = match_id
		_match_id_by_peer[enemy_peer_id] = match_id
		_arena_round_results.append({
			"match_id": match_id,
			"pair_index": pair_index,
			"player_peer_id": player_peer_id,
			"enemy_peer_id": enemy_peer_id,
			"player_name": String(payload.get("player_name", "Player")),
			"enemy_name": String(payload.get("enemy_name", "Opponent")),
			"status": "running",
			"winner": "",
			"player_hp": player_run.player_hp,
			"enemy_hp": enemy_run.player_hp,
		})
	_arena_phase = "battle"
	_match_active = true
	_arena_public_details = _build_arena_public_details()
	for peer_id in all_peer_ids:
		var peer_match_id: String = String(_match_id_by_peer.get(peer_id, ""))
		if peer_match_id == "":
			continue
		var peer_context: Dictionary = Dictionary(_parallel_match_contexts.get(peer_match_id, {}))
		var peer_payload: Dictionary = Dictionary(peer_context.get("payload", {}))
		if peer_id == 1:
			_apply_match_started(peer_payload)
		else:
			_receive_match_started_rpc.rpc_id(peer_id, peer_payload)
	var local_context: Dictionary = _get_local_parallel_match_context()
	_apply_local_parallel_context_legacy_state(local_context)
	_set_state(ConnectionState.MATCH, "%s arena battles active" % _session_display_name())
	for raw_match_id in _parallel_match_contexts.keys():
		var context_match_id: String = String(raw_match_id)
		_publish_parallel_context_snapshot(context_match_id, true)
		_broadcast_parallel_battle_start_state(context_match_id)
	_broadcast_arena_round_results()
	_broadcast_lobby_state()
	return true


func _get_local_parallel_match_context() -> Dictionary:
	var local_peer_id: int = multiplayer.get_unique_id()
	var match_id: String = String(_match_id_by_peer.get(local_peer_id, ""))
	if match_id == "" and not _match_payload.is_empty():
		match_id = String(_match_payload.get("match_id", ""))
	return Dictionary(_parallel_match_contexts.get(match_id, {}))


func _apply_local_parallel_context_legacy_state(context: Dictionary) -> void:
	if context.is_empty():
		return
	var payload: Dictionary = Dictionary(context.get("payload", {}))
	var player_peer_id: int = int(payload.get("player_peer_id", -1))
	var enemy_peer_id: int = int(payload.get("enemy_peer_id", -1))
	_active_match_peer_ids = [player_peer_id, enemy_peer_id]
	_arena_runs_by_side = {
		"player": _arena_runs_by_peer.get(player_peer_id),
		"enemy": _arena_runs_by_peer.get(enemy_peer_id),
	}
	_battle_ready_by_side = Dictionary(context.get("ready_by_side", {})).duplicate(true)
	_battle_countdown_active = bool(context.get("countdown_active", false))
	_battle_countdown_deadline_msec = int(context.get("countdown_deadline_msec", 0))
	_battle_countdown_finished = bool(context.get("countdown_finished", false))
	_last_snapshot = Dictionary(context.get("last_snapshot", {})).duplicate(true)


func _process_parallel_matches(delta: float) -> void:
	if not _is_host or _parallel_match_contexts.is_empty():
		return
	var now_msec: int = Time.get_ticks_msec()
	var match_ids: Array[String] = []
	for raw_match_id in _parallel_match_contexts.keys():
		match_ids.append(String(raw_match_id))
	for match_id in match_ids:
		var context: Dictionary = Dictionary(_parallel_match_contexts.get(match_id, {}))
		if context.is_empty() or bool(context.get("finished", false)):
			continue
		var engine: RealtimeBattleEngine = context.get("engine") as RealtimeBattleEngine
		if engine == null or engine.battle_state == null:
			continue
		if bool(context.get("countdown_active", false)) and now_msec >= int(context.get("countdown_deadline_msec", 0)):
			context["countdown_active"] = false
			context["countdown_deadline_msec"] = 0
			context["countdown_finished"] = true
			_parallel_match_contexts[match_id] = context
			engine.start_battle()
			_broadcast_parallel_battle_start_state(match_id)
			_emit_parallel_countdown_finished(match_id)
			_publish_parallel_context_snapshot(match_id, true)
		if bool(context.get("countdown_finished", false)) and engine.battle_state.winner == "":
			engine.update(delta)
		var snapshot_elapsed: float = float(context.get("snapshot_elapsed", 0.0)) + delta
		if snapshot_elapsed >= 1.0 / 12.0:
			snapshot_elapsed = fmod(snapshot_elapsed, 1.0 / 12.0)
			context["snapshot_elapsed"] = snapshot_elapsed
			_parallel_match_contexts[match_id] = context
			_publish_parallel_context_snapshot(match_id, false)
		else:
			context["snapshot_elapsed"] = snapshot_elapsed
			_parallel_match_contexts[match_id] = context
		if engine.battle_state.winner != "":
			_publish_parallel_context_snapshot(match_id, true)
			_finish_parallel_match(match_id)


func _publish_parallel_context_snapshot(match_id: String, reliable: bool) -> bool:
	var context: Dictionary = Dictionary(_parallel_match_contexts.get(match_id, {}))
	var engine: RealtimeBattleEngine = context.get("engine") as RealtimeBattleEngine
	if engine == null or engine.battle_state == null:
		return false
	var sequence: int = int(context.get("snapshot_sequence", 0)) + 1
	var outgoing: Dictionary = BattleStateCodec.encode(
		engine.battle_state,
		engine.has_battle_started(),
		true
	)
	outgoing["sequence"] = sequence
	outgoing["match_id"] = match_id
	outgoing["server_ticks_msec"] = Time.get_ticks_msec()
	context["snapshot_sequence"] = sequence
	context["last_snapshot"] = outgoing.duplicate(true)
	_parallel_match_contexts[match_id] = context
	var viewer_peer_ids: Array[int] = _to_int_array(context.get("viewer_peer_ids", []))
	for peer_id in viewer_peer_ids:
		if peer_id == 1:
			if String(_match_payload.get("match_id", "")) == match_id:
				_apply_battle_snapshot(outgoing)
		elif reliable:
			_receive_battle_snapshot_reliable_rpc.rpc_id(peer_id, outgoing)
		else:
			_receive_battle_snapshot_rpc.rpc_id(peer_id, outgoing)
	return true


func _set_parallel_battle_ready(match_id: String, side: String, ready: bool) -> bool:
	var context: Dictionary = Dictionary(_parallel_match_contexts.get(match_id, {}))
	if context.is_empty() or bool(context.get("finished", false)):
		return false
	if bool(context.get("countdown_active", false)) or bool(context.get("countdown_finished", false)):
		return false
	if side != "player" and side != "enemy":
		return false
	var ready_by_side: Dictionary = Dictionary(context.get("ready_by_side", {})).duplicate(true)
	ready_by_side[side] = ready
	context["ready_by_side"] = ready_by_side
	if bool(ready_by_side.get("player", false)) and bool(ready_by_side.get("enemy", false)):
		context["countdown_active"] = true
		context["countdown_deadline_msec"] = Time.get_ticks_msec() + int(BATTLE_COUNTDOWN_SECONDS * 1000.0)
	_parallel_match_contexts[match_id] = context
	_broadcast_parallel_battle_start_state(match_id)
	return true


func _build_parallel_battle_start_state(context: Dictionary) -> Dictionary:
	var remaining: float = 0.0
	if bool(context.get("countdown_active", false)):
		remaining = maxf(
			0.0,
			float(int(context.get("countdown_deadline_msec", 0)) - Time.get_ticks_msec()) / 1000.0
		)
	return {
		"match_id": String(context.get("match_id", "")),
		"ready_by_side": Dictionary(context.get("ready_by_side", {})).duplicate(true),
		"countdown_active": bool(context.get("countdown_active", false)),
		"countdown_remaining": remaining,
		"started": bool(context.get("countdown_finished", false)),
	}


func _broadcast_parallel_battle_start_state(match_id: String) -> void:
	var context: Dictionary = Dictionary(_parallel_match_contexts.get(match_id, {}))
	if context.is_empty():
		return
	var state: Dictionary = _build_parallel_battle_start_state(context)
	var viewer_peer_ids: Array[int] = _to_int_array(context.get("viewer_peer_ids", []))
	for peer_id in viewer_peer_ids:
		if peer_id == 1:
			if String(_match_payload.get("match_id", "")) == match_id:
				_apply_battle_start_state(state)
		else:
			_receive_battle_start_state_rpc.rpc_id(peer_id, state)


func _emit_parallel_countdown_finished(match_id: String) -> void:
	var context: Dictionary = Dictionary(_parallel_match_contexts.get(match_id, {}))
	var viewer_peer_ids: Array[int] = _to_int_array(context.get("viewer_peer_ids", []))
	for peer_id in viewer_peer_ids:
		if peer_id == 1:
			if String(_match_payload.get("match_id", "")) == match_id:
				battle_countdown_finished.emit()
		else:
			_receive_battle_countdown_finished_rpc.rpc_id(peer_id, match_id)


func _apply_parallel_battle_command(peer_id: int, command: Dictionary) -> bool:
	var match_id: String = String(_match_id_by_peer.get(peer_id, ""))
	var context: Dictionary = Dictionary(_parallel_match_contexts.get(match_id, {}))
	if context.is_empty() or bool(context.get("finished", false)):
		return false
	var player_peer_id: int = int(context.get("player_peer_id", -1))
	var enemy_peer_id: int = int(context.get("enemy_peer_id", -1))
	var side: String = "player" if peer_id == player_peer_id else "enemy" if peer_id == enemy_peer_id else "spectator"
	var sequence: int = int(command.get("sequence", 0))
	var kind: String = String(command.get("kind", ""))
	var runtime_id: String = String(command.get("runtime_id", ""))
	var valid: bool = (side == "player" or side == "enemy")
	valid = valid and sequence > int(_last_command_sequences.get(peer_id, 0))
	valid = valid and (kind == "card" or kind == "battle_ready" or kind == "relic_toggle_on" or kind == "relic_toggle_off")
	if kind == "card":
		valid = valid and bool(context.get("countdown_finished", false))
		valid = valid and LanProtocol.validate_runtime_id(side, runtime_id)
	elif kind == "relic_toggle_on" or kind == "relic_toggle_off":
		valid = valid and runtime_id == "reserved_seat_tag"
	valid = valid and _consume_command_rate(peer_id)
	var last_snapshot: Dictionary = Dictionary(context.get("last_snapshot", {}))
	if not valid:
		if peer_id > 1:
			send_command_result(peer_id, sequence, false, last_snapshot)
		return false
	_last_command_sequences[peer_id] = sequence
	if kind == "battle_ready":
		var ready: bool = bool(command.get("ready", true))
		var ready_accepted: bool = _set_parallel_battle_ready(match_id, side, ready)
		if peer_id > 1:
			send_command_result(peer_id, sequence, ready_accepted, last_snapshot)
		return ready_accepted
	var engine: RealtimeBattleEngine = context.get("engine") as RealtimeBattleEngine
	if engine == null:
		return false
	var accepted: bool = false
	if kind == "card":
		accepted = engine.request_use_card(side, runtime_id)
	elif kind == "relic_toggle_on" or kind == "relic_toggle_off":
		accepted = engine.set_relic_enabled(side, runtime_id, kind == "relic_toggle_on")
	_publish_parallel_context_snapshot(match_id, true)
	context = Dictionary(_parallel_match_contexts.get(match_id, {}))
	last_snapshot = Dictionary(context.get("last_snapshot", {}))
	if peer_id > 1:
		send_command_result(peer_id, sequence, accepted, last_snapshot)
	return accepted


func _finish_parallel_match(match_id: String) -> bool:
	var context: Dictionary = Dictionary(_parallel_match_contexts.get(match_id, {}))
	var engine: RealtimeBattleEngine = context.get("engine") as RealtimeBattleEngine
	if context.is_empty() or engine == null or engine.battle_state == null or bool(context.get("finished", false)):
		return false
	var summary: Dictionary = engine.build_summary(false)
	var result: Dictionary = BattleStateCodec.encode_match_summary(summary)
	var player_peer_id: int = int(context.get("player_peer_id", -1))
	var enemy_peer_id: int = int(context.get("enemy_peer_id", -1))
	var payload: Dictionary = Dictionary(context.get("payload", {}))
	var final_snapshot: Dictionary = Dictionary(context.get("last_snapshot", {})).duplicate(true)
	var winner: String = String(summary.get("winner", "draw"))
	result["match_id"] = match_id
	result["winner"] = winner
	result["player_name"] = String(payload.get("player_name", "Player"))
	result["enemy_name"] = String(payload.get("enemy_name", "Opponent"))
	result["player_peer_id"] = player_peer_id
	result["enemy_peer_id"] = enemy_peer_id
	result["final_snapshot"] = final_snapshot
	result["arena_session_id"] = _arena_session_id
	result["round_index"] = _arena_round_index
	result["pair_index"] = int(context.get("pair_index", 0))
	var player_run: RunState = _arena_runs_by_peer.get(player_peer_id) as RunState
	var enemy_run: RunState = _arena_runs_by_peer.get(enemy_peer_id) as RunState
	if player_run == null or enemy_run == null:
		return false
	var player_state: UnitState = engine.battle_state.player
	var enemy_state: UnitState = engine.battle_state.enemy
	player_run.temporary_card_modifiers = player_state.temporary_card_modifiers.duplicate(true)
	enemy_run.temporary_card_modifiers = enemy_state.temporary_card_modifiers.duplicate(true)
	var player_progress: Dictionary = _arena_coordinator.apply_battle_result(
		player_run,
		winner == "player",
		player_state.hp,
		int(result.get("player_relic_bonus_gold", 0))
	)
	var enemy_progress: Dictionary = _arena_coordinator.apply_battle_result(
		enemy_run,
		winner == "enemy",
		enemy_state.hp,
		int(result.get("enemy_relic_bonus_gold", 0))
	)
	result["player_progress"] = player_progress
	result["enemy_progress"] = enemy_progress
	result["winner_peer_id"] = player_peer_id if winner == "player" else enemy_peer_id if winner == "enemy" else -1
	result["player_arena_wins"] = player_run.arena_wins
	result["enemy_arena_wins"] = enemy_run.arena_wins
	result["player_arena_losses"] = player_run.arena_losses
	result["enemy_arena_losses"] = enemy_run.arena_losses
	context["finished"] = true
	context["result"] = result.duplicate(true)
	_parallel_match_contexts[match_id] = context
	_arena_standings = ArenaTournamentCoordinator.build_standings(
		_arena_player_peer_ids,
		_profiles_by_peer,
		_arena_runs_by_peer
	)
	for result_index in range(_arena_round_results.size()):
		var round_result: Dictionary = _arena_round_results[result_index]
		if String(round_result.get("match_id", "")) != match_id:
			continue
		round_result["status"] = "finished"
		round_result["winner"] = winner
		round_result["winner_peer_id"] = int(result.get("winner_peer_id", -1))
		round_result["player_hp"] = player_state.hp
		round_result["player_max_hp"] = player_state.max_hp
		round_result["enemy_hp"] = enemy_state.hp
		round_result["enemy_max_hp"] = enemy_state.max_hp
		round_result["battle_time"] = float(summary.get("battle_time", 0.0))
		_arena_round_results[result_index] = round_result
		break
	result["standings"] = _arena_standings.duplicate(true)
	var viewer_peer_ids: Array[int] = _to_int_array(context.get("viewer_peer_ids", []))
	for peer_id in viewer_peer_ids:
		if peer_id == 1:
			if String(_match_payload.get("match_id", "")) == match_id:
				_apply_match_finished(result)
		else:
			_receive_match_finished_rpc.rpc_id(peer_id, result)
	_arena_round_results_complete = _are_all_parallel_matches_finished()
	if _arena_round_results_complete:
		_arena_phase = "round_result"
		_match_active = false
	_arena_public_details = _build_arena_public_details()
	_broadcast_arena_round_results()
	_broadcast_lobby_state()
	return true


func _are_all_parallel_matches_finished() -> bool:
	if _parallel_match_contexts.is_empty():
		return false
	for raw_context in _parallel_match_contexts.values():
		var context: Dictionary = Dictionary(raw_context)
		if not bool(context.get("finished", false)):
			return false
	return true


func _has_unfinished_parallel_matches() -> bool:
	for raw_context in _parallel_match_contexts.values():
		var context: Dictionary = Dictionary(raw_context)
		if not bool(context.get("finished", false)):
			return true
	return false


func _dispose_parallel_match_contexts() -> void:
	for raw_context in _parallel_match_contexts.values():
		var context: Dictionary = Dictionary(raw_context)
		var engine: RealtimeBattleEngine = context.get("engine") as RealtimeBattleEngine
		if engine != null:
			engine.dispose()
	_parallel_match_contexts.clear()


func _build_arena_round_results_snapshot() -> Dictionary:
	var completed_count: int = 0
	for result in _arena_round_results:
		if String(result.get("status", "")) == "finished":
			completed_count += 1
	var continue_ready_count: int = 0
	for peer_id in _arena_player_peer_ids:
		if bool(_arena_round_continue_by_peer.get(str(peer_id), false)):
			continue_ready_count += 1
	return {
		"arena_session_id": _arena_session_id,
		"round_index": _arena_round_index,
		"phase": _arena_phase,
		"results": _arena_round_results.duplicate(true),
		"completed_count": completed_count,
		"total_count": _arena_round_results.size(),
		"all_complete": _arena_round_results_complete,
		"continue_ready_count": continue_ready_count,
		"continue_total": _arena_player_peer_ids.size(),
		"continue_by_peer": _arena_round_continue_by_peer.duplicate(true),
		"standings": _arena_standings.duplicate(true),
		"public_details": _arena_public_details.duplicate(true),
	}


func _broadcast_arena_round_results() -> void:
	if not _is_host or not _arena_session_active:
		return
	var snapshot: Dictionary = _build_arena_round_results_snapshot()
	_receive_arena_round_results_rpc.rpc(snapshot)
	_apply_arena_round_results_snapshot(snapshot)


func _apply_arena_round_results_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var incoming_session_id: String = String(snapshot.get("arena_session_id", ""))
	if _arena_session_id != "" and incoming_session_id != _arena_session_id:
		return
	_arena_session_id = incoming_session_id
	_arena_round_index = int(snapshot.get("round_index", _arena_round_index))
	_arena_phase = String(snapshot.get("phase", _arena_phase))
	_arena_round_results = _to_dictionary_array(snapshot.get("results", []))
	_arena_round_results_complete = bool(snapshot.get("all_complete", false))
	_arena_round_continue_by_peer = Dictionary(snapshot.get("continue_by_peer", {})).duplicate(true)
	_arena_standings = _to_dictionary_array(snapshot.get("standings", _arena_standings))
	_arena_public_details = _to_dictionary_array(snapshot.get("public_details", _arena_public_details))
	arena_round_results_changed.emit(snapshot.duplicate(true))


func _acknowledge_round_results_for_peer(peer_id: int) -> bool:
	if not _is_host or not _arena_round_results_complete or not _arena_player_peer_ids.has(peer_id):
		return false
	_arena_round_continue_by_peer[str(peer_id)] = true
	_broadcast_arena_round_results()
	for player_peer_id in _arena_player_peer_ids:
		if not bool(_arena_round_continue_by_peer.get(str(player_peer_id), false)):
			return true
	var tournament_winner_peer_id: int = _find_tournament_winner_peer_id()
	if tournament_winner_peer_id > 0:
		_finish_arena_session("winner", "target_wins", tournament_winner_peer_id)
	else:
		_prepare_next_tournament_round()
	return true


func _build_arena_public_details() -> Array[Dictionary]:
	var details: Array[Dictionary] = []
	for peer_id in _arena_player_peer_ids:
		var run_state: RunState = _arena_runs_by_peer.get(peer_id) as RunState
		if run_state == null:
			continue
		var profile: Dictionary = _get_profile_for_peer(peer_id)
		var owned_counts: Dictionary = {}
		for card_id in run_state.player_cards:
			owned_counts[card_id] = int(owned_counts.get(card_id, 0)) + 1
		var owned_cards: Array[String] = []
		for raw_card_id in owned_counts.keys():
			var card_id: String = String(raw_card_id)
			var card_def: CardDef = Database.get_card(card_id)
			var card_name: String = card_def.name if card_def != null else card_id
			owned_cards.append("%s x%d" % [card_name, int(owned_counts.get(card_id, 0))])
		owned_cards.sort()
		var equipped_cards: Array[String] = []
		for equipped_card_id in run_state.equipped_cards:
			var equipped_def: CardDef = Database.get_card(equipped_card_id)
			equipped_cards.append(equipped_def.name if equipped_def != null else equipped_card_id)
		var relic_names: Array[String] = []
		for relic_id in run_state.relics:
			var relic_def: RelicDef = Database.get_relic(relic_id)
			relic_names.append(relic_def.name if relic_def != null else relic_id)
		details.append({
			"peer_id": peer_id,
			"name": String(profile.get("name", "Player")),
			"hp": run_state.player_hp,
			"max_hp": run_state.max_hp,
			"gold": run_state.gold,
			"wins": run_state.arena_wins,
			"losses": run_state.arena_losses,
			"owned_cards": owned_cards,
			"equipped_cards": equipped_cards,
			"relics": relic_names,
		})
	return details


func _start_current_pairing_match() -> bool:
	if not _is_host or not _arena_session_active or _arena_pair_index < 0 or _arena_pair_index >= _arena_pairings.size():
		return false
	var pairing: Dictionary = _arena_pairings[_arena_pair_index]
	var player_peer_id: int = int(pairing.get("player_peer_id", -1))
	var enemy_peer_id: int = int(pairing.get("enemy_peer_id", -1))
	var player_run: RunState = _arena_runs_by_peer.get(player_peer_id) as RunState
	var enemy_run: RunState = _arena_runs_by_peer.get(enemy_peer_id) as RunState
	if player_run == null or enemy_run == null:
		return false
	if not _arena_coordinator.has_valid_loadout(player_run) or not _arena_coordinator.has_valid_loadout(enemy_run):
		return false
	var seed: int = int(Time.get_ticks_msec() % 2147483646) + 1
	var player_profile: Dictionary = _get_profile_for_peer(player_peer_id)
	var enemy_profile: Dictionary = _get_profile_for_peer(enemy_peer_id)
	var all_peer_ids: Array[int] = _get_all_peer_ids()
	var peer_sides: Dictionary = ArenaTournamentCoordinator.build_peer_sides(all_peer_ids, player_peer_id, enemy_peer_id)
	_peer_sides.clear()
	for peer_id in all_peer_ids:
		_peer_sides[peer_id] = String(peer_sides.get(str(peer_id), "spectator"))
	_active_match_peer_ids = [player_peer_id, enemy_peer_id]
	_arena_runs_by_side = {"player": player_run, "enemy": enemy_run}
	_match_payload = {
		"protocol_version": LanProtocol.PROTOCOL_VERSION,
		"content_hash": LanProtocol.build_content_hash(),
		"arena_session_id": _arena_session_id,
		"arena_round": _arena_round_index + 1,
		"pair_index": _arena_pair_index,
		"pair_count": _arena_pairings.size(),
		"match_id": "%s-r%d-p%d-%d" % [_arena_session_id, _arena_round_index + 1, _arena_pair_index + 1, Time.get_ticks_msec()],
		"seed": seed,
		"player_run": player_run.to_dict(),
		"enemy_run": enemy_run.to_dict(),
		"player_name": String(player_profile.get("name", "Player")),
		"enemy_name": String(enemy_profile.get("name", "Opponent")),
		"player_peer_id": player_peer_id,
		"enemy_peer_id": enemy_peer_id,
		"peer_sides": peer_sides,
		"standings": _arena_standings.duplicate(true),
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
		if _arena_session_active and bool(_match_payload.get("parallel_round", false)):
			next_state = ConnectionState.MATCH
		else:
			next_state = ConnectionState.ARENA_PREPARATION if _arena_session_active else ConnectionState.LOBBY
	_set_state(next_state, "%s match finished" % _session_display_name())
	match_finished.emit(_last_match_result.duplicate(true))


func _finish_arena_session(winner: String, reason: String, winner_peer_id: int = -1) -> void:
	if not _is_host or not _arena_session_active:
		return
	if winner_peer_id <= 0 and _active_match_peer_ids.size() == 2:
		if winner == "player":
			winner_peer_id = _active_match_peer_ids[0]
		elif winner == "enemy":
			winner_peer_id = _active_match_peer_ids[1]
	var runs_by_peer: Dictionary = {}
	for peer_id in _arena_player_peer_ids:
		var run_state: RunState = _arena_runs_by_peer.get(peer_id) as RunState
		if run_state != null:
			runs_by_peer[str(peer_id)] = run_state.to_dict()
	var result: Dictionary = {
		"arena_session_id": _arena_session_id,
		"winner": winner,
		"winner_peer_id": winner_peer_id,
		"reason": reason,
		"runs_by_peer": runs_by_peer,
		"standings": _arena_standings.duplicate(true),
	}
	var player_run: RunState = _arena_runs_by_side.get("player") as RunState
	var enemy_run: RunState = _arena_runs_by_side.get("enemy") as RunState
	if player_run != null:
		result["player_run"] = player_run.to_dict()
	if enemy_run != null:
		result["enemy_run"] = enemy_run.to_dict()
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
	_dispose_parallel_match_contexts()
	_match_id_by_peer.clear()
	_spectator_match_id = ""
	_arena_round_continue_by_peer.clear()
	_local_profile["ready"] = false
	_arena_standings = _to_dictionary_array(result.get("standings", _arena_standings))
	request_arena_details_auto_open()
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
		"max_players": get_player_capacity(),
		"player_count": _get_player_peer_ids().size(),
		"spectator_count": _get_spectator_peer_ids().size(),
		"max_spectators": LanProtocol.MAX_SPECTATORS,
		"can_start": can_start_match(),
		"match_active": _match_active or _has_unfinished_parallel_matches(),
		"arena_active": _arena_session_active,
		"target_wins": _online_target_wins,
		"arena_rules": _build_online_arena_rules(),
		"arena_phase": _arena_phase,
		"arena_round_index": _arena_round_index,
		"arena_pair_index": _arena_pair_index,
		"arena_pairings": _arena_pairings.duplicate(true),
		"arena_standings": _arena_standings.duplicate(true),
		"arena_round_results": _arena_round_results.duplicate(true),
		"arena_round_results_complete": _arena_round_results_complete,
		"arena_public_details": _arena_public_details.duplicate(true),
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
	if _session_scope == SESSION_SCOPE_ONLINE:
		return
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
			"max_players": get_player_capacity(),
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
			"max_players": int(beacon.get("max_players", LanProtocol.DEFAULT_PLAYERS)),
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


func _get_all_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for raw_peer_id in _profiles_by_peer.keys():
		peer_ids.append(int(raw_peer_id))
	peer_ids.sort()
	return peer_ids


func _get_player_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for peer_id in _get_all_peer_ids():
		var profile: Dictionary = Dictionary(_profiles_by_peer.get(peer_id, {}))
		if String(profile.get("role", LanProtocol.ROLE_PLAYER)) == LanProtocol.ROLE_PLAYER:
			peer_ids.append(peer_id)
	return peer_ids


func _get_spectator_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for peer_id in _get_all_peer_ids():
		var profile: Dictionary = Dictionary(_profiles_by_peer.get(peer_id, {}))
		if String(profile.get("role", LanProtocol.ROLE_PLAYER)) == LanProtocol.ROLE_SPECTATOR:
			peer_ids.append(peer_id)
	return peer_ids


func _get_profile_for_peer(peer_id: int) -> Dictionary:
	if _is_host and _profiles_by_peer.has(peer_id):
		return Dictionary(_profiles_by_peer.get(peer_id, {})).duplicate(true)
	for raw_player in Array(_public_lobby_snapshot.get("players", [])):
		var player_data: Dictionary = Dictionary(raw_player)
		if int(player_data.get("peer_id", -1)) == peer_id:
			return player_data.duplicate(true)
	if peer_id == multiplayer.get_unique_id():
		return _local_profile.duplicate(true)
	return {}


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


func _to_int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	for raw_item in Array(value):
		result.append(int(raw_item))
	return result


func _clear_session(clear_profile: bool) -> void:
	_web_failure_pending = false
	_web_signaling.close()
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
	_arena_runs_by_peer.clear()
	_local_arena_run = null
	_arena_ready_by_side = {"player": false, "enemy": false}
	_arena_ready_by_peer.clear()
	_arena_player_peer_ids.clear()
	_arena_pairings.clear()
	_arena_pair_index = 0
	_arena_round_index = 0
	_active_match_peer_ids.clear()
	_arena_standings.clear()
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
	_online_target_wins = ArenaService.TARGET_WINS
	_online_initial_gold = ArenaService.INITIAL_GOLD
	_online_initial_max_hp = ArenaService.INITIAL_MAX_HP
	_online_special_reward_interval = ArenaService.SPECIAL_REWARD_INTERVAL
	_online_shop_price_percent = 100
	_online_reroll_cost = ArenaService.REROLL_COST
	_online_shop_offer_count = ArenaService.SHOP_OFFER_COUNT
	_online_max_players = LanProtocol.DEFAULT_PLAYERS
	_local_participant_role = LanProtocol.ROLE_PLAYER
	_pending_participant_role = ""
	_dispose_parallel_match_contexts()
	_match_id_by_peer.clear()
	_spectator_match_id = ""
	_arena_round_results.clear()
	_arena_round_results_complete = false
	_arena_round_continue_by_peer.clear()
	_arena_public_details.clear()
	_arena_details_auto_open_pending = false
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
	return "Web" if _session_scope == SESSION_SCOPE_ONLINE else "LAN"


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
		"spectator_full":
			return "The spectator seats are full."
		"seat_reserved":
			return "The open seat is reserved for a reconnecting player."
		"invalid_room_code":
			return "The online room code is incorrect."
		_:
			return "The %s host rejected the connection (%s)." % [_session_display_name(), code]
