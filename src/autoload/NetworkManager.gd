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

enum ConnectionState {
	OFFLINE,
	DISCOVERING,
	HOSTING,
	CONNECTING,
	LOBBY,
	MATCH,
	RECONNECTING,
}

const DISCOVERY_BEACON_INTERVAL: float = 0.75
const DISCOVERY_ENTRY_LIFETIME_MSEC: int = 2600
const PING_INTERVAL: float = 1.0
const RECONNECT_RETRY_INTERVAL: float = 1.0

var _state: int = ConnectionState.OFFLINE
var _peer: ENetMultiplayerPeer
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


func _process(delta: float) -> void:
	_process_discovery(delta)
	_process_ping(delta)
	_process_reconnect()


func configure_local_player(player_name: String, starter_id: String) -> Dictionary:
	var token: String = String(_local_profile.get("reconnect_token", ""))
	_local_profile = LanProtocol.build_profile(player_name, starter_id, false, token)
	return _local_profile.duplicate(true)


func host_lobby(player_name: String, starter_id: String, port: int = LanProtocol.DEFAULT_PORT) -> bool:
	_clear_session(false)
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


func join_lobby(
	address: String,
	player_name: String,
	starter_id: String,
	port: int = LanProtocol.DEFAULT_PORT
) -> bool:
	_clear_session(false)
	_last_match_result.clear()
	configure_local_player(player_name, starter_id)
	_last_address = address.strip_edges()
	if _last_address == "":
		_last_address = "127.0.0.1"
	_host_port = LanProtocol.sanitize_port(port)
	return _connect_client(false)


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
	if _local_profile.is_empty() or _match_active:
		return false
	_local_profile["ready"] = ready
	_send_or_apply_local_profile()
	return true


func is_local_ready() -> bool:
	return bool(_local_profile.get("ready", false))


func can_start_match() -> bool:
	if not _is_host or _match_active or _profiles_by_peer.size() != LanProtocol.MAX_PLAYERS:
		return false
	for raw_profile in _profiles_by_peer.values():
		var profile: Dictionary = Dictionary(raw_profile)
		if not bool(profile.get("ready", false)):
			return false
	return true


func start_lan_match() -> bool:
	if not can_start_match():
		return false
	var guest_peer_id: int = _get_guest_peer_id()
	if guest_peer_id <= 1:
		return false
	var host_profile: Dictionary = Dictionary(_profiles_by_peer.get(1, {}))
	var guest_profile: Dictionary = Dictionary(_profiles_by_peer.get(guest_peer_id, {}))
	var seed: int = int(Time.get_ticks_msec() % 2147483646) + 1
	var payload: Dictionary = LanProtocol.build_match_payload(host_profile, guest_profile, seed, 1, guest_peer_id)
	if payload.is_empty():
		return false
	_match_payload = payload.duplicate(true)
	_match_active = true
	_last_match_result.clear()
	_last_snapshot.clear()
	_snapshot_sequence = 0
	_last_received_snapshot_sequence = 0
	_local_command_sequence = 0
	_last_command_sequences.clear()
	_command_rate_windows.clear()
	_waiting_for_reconnect = false
	_reserved_remote_profile.clear()
	_set_state(ConnectionState.MATCH, "LAN match started")
	_receive_match_started_rpc.rpc(_match_payload)
	_apply_match_started(_match_payload)
	return true


func has_active_match() -> bool:
	return _match_active and not _match_payload.is_empty()


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
		return "player"
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
	return _submit_local_command("card", runtime_id)


func submit_start_command() -> bool:
	return _submit_local_command("start", "")


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
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(_last_address, _host_port)
	if error != OK:
		if not is_reconnect:
			_emit_error("join_failed", "Unable to connect to %s:%d (error %d)." % [_last_address, _host_port, error])
		return false
	_peer = peer
	_is_host = false
	multiplayer.multiplayer_peer = _peer
	_reconnecting = is_reconnect
	_set_state(ConnectionState.RECONNECTING if is_reconnect else ConnectionState.CONNECTING, "Connecting to %s:%d" % [_last_address, _host_port])
	return true


func _send_or_apply_local_profile() -> void:
	if _is_host:
		_profiles_by_peer[1] = _local_profile.duplicate(true)
		_broadcast_lobby_state()
		return
	if _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_submit_profile_rpc.rpc_id(1, _local_profile)


func _submit_local_command(kind: String, runtime_id: String) -> bool:
	if not _match_active or _is_host:
		return false
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	_local_command_sequence += 1
	_submit_battle_command_rpc.rpc_id(1, {
		"sequence": _local_command_sequence,
		"kind": kind,
		"runtime_id": runtime_id,
		"client_ticks_msec": Time.get_ticks_msec(),
	})
	return true


func _on_peer_connected(_peer_id: int) -> void:
	if _is_host:
		_set_state(ConnectionState.HOSTING if not _match_active else ConnectionState.MATCH, "Peer connected; validating content")


func _on_peer_disconnected(peer_id: int) -> void:
	if not _is_host:
		return
	var was_explicit: bool = bool(_explicit_peer_leaves.get(peer_id, false))
	_explicit_peer_leaves.erase(peer_id)
	var disconnected_profile: Dictionary = Dictionary(_profiles_by_peer.get(peer_id, {})).duplicate(true)
	_profiles_by_peer.erase(peer_id)
	_peer_sides.erase(peer_id)
	_peer_pings.erase(peer_id)
	if _match_active and not was_explicit and not disconnected_profile.is_empty():
		_reserved_remote_profile = disconnected_profile
		_waiting_for_reconnect = true
		_reconnect_deadline_msec = Time.get_ticks_msec() + int(LanProtocol.RECONNECT_GRACE_SECONDS * 1000.0)
		_set_state(ConnectionState.MATCH, "Opponent disconnected; waiting for reconnection")
		return
	if _match_active:
		finish_lan_match({
			"winner": "player",
			"reason": "opponent_left",
			"battle_time": float(_last_snapshot.get("battle_time", 0.0)),
		}, _last_snapshot)
	else:
		_broadcast_lobby_state()


func _on_connected_to_server() -> void:
	if _is_host:
		return
	_submit_profile_rpc.rpc_id(1, _local_profile)


func _on_connection_failed() -> void:
	if _closing_peer:
		return
	if _reconnecting:
		_close_peer_only()
		_next_reconnect_attempt_msec = Time.get_ticks_msec() + int(RECONNECT_RETRY_INTERVAL * 1000.0)
		return
	_close_peer_only()
	_set_state(ConnectionState.OFFLINE, "Connection failed")
	_emit_error("connection_failed", "Could not connect to the LAN host.")


func _on_server_disconnected() -> void:
	if _closing_peer:
		return
	if _match_active:
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
func _submit_profile_rpc(raw_profile: Dictionary) -> void:
	if not _is_host:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 1:
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
		var sides: Dictionary = Dictionary(_match_payload.get("peer_sides", {})).duplicate(true)
		for raw_side_peer_id in sides.keys():
			if String(sides.get(raw_side_peer_id, "")) == "enemy":
				sides.erase(raw_side_peer_id)
		sides[str(sender_id)] = "enemy"
		_match_payload["peer_sides"] = sides
		_receive_match_started_rpc.rpc_id(sender_id, _match_payload)
		if not _last_snapshot.is_empty():
			_receive_battle_snapshot_reliable_rpc.rpc_id(sender_id, _last_snapshot)
		_set_state(ConnectionState.MATCH, "Opponent reconnected")
		return
	_set_state(ConnectionState.LOBBY, "LAN lobby ready")
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
	if not _match_active:
		_set_state(ConnectionState.LOBBY, "LAN lobby ready")
	lobby_changed.emit(_public_lobby_snapshot.duplicate(true))


@rpc("authority", "call_remote", "reliable", 0)
func _receive_network_error_rpc(code: String, message: String) -> void:
	_emit_error(code, message)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_match_started_rpc(payload: Dictionary) -> void:
	_apply_match_started(payload)


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
	valid = valid and (kind == "card" or kind == "start")
	if kind == "card":
		valid = valid and LanProtocol.validate_runtime_id(side, runtime_id)
	valid = valid and _consume_command_rate(sender_id)
	if not valid:
		send_command_result(sender_id, sequence, false, _last_snapshot)
		return
	_last_command_sequences[sender_id] = sequence
	battle_command_received.emit(sender_id, side, kind, runtime_id, sequence)


@rpc("authority", "call_remote", "reliable", 0)
func _command_result_rpc(sequence: int, accepted: bool, snapshot: Dictionary) -> void:
	if not snapshot.is_empty():
		_apply_battle_snapshot(snapshot)
	command_result_received.emit(sequence, accepted, snapshot.duplicate(true))


@rpc("authority", "call_remote", "reliable", 0)
func _receive_match_finished_rpc(result: Dictionary) -> void:
	_apply_match_finished(result)


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
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_session_closed_rpc(reason: String) -> void:
	_match_active = false
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


func _apply_match_started(payload: Dictionary) -> void:
	if int(payload.get("protocol_version", -1)) != LanProtocol.PROTOCOL_VERSION:
		_emit_error("protocol_mismatch", "LAN protocol versions do not match.")
		return
	if String(payload.get("content_hash", "")) != LanProtocol.build_content_hash():
		_emit_error("content_mismatch", "Game data differs from the host.")
		return
	_match_payload = payload.duplicate(true)
	_match_active = true
	_reconnecting = false
	_waiting_for_reconnect = false
	_last_received_snapshot_sequence = 0
	_set_state(ConnectionState.MATCH, "LAN match active")
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
	_set_state(ConnectionState.LOBBY if is_session_connected() else ConnectionState.OFFLINE, "LAN match finished")
	match_finished.emit(_last_match_result.duplicate(true))


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
		"host_port": _host_port,
		"host_addresses": LanProtocol.get_lan_addresses(),
		"players": players,
		"can_start": can_start_match(),
		"match_active": _match_active,
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
	if _state != ConnectionState.LOBBY and _state != ConnectionState.MATCH:
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
		finish_lan_match({
			"winner": "player",
			"reason": "reconnect_timeout",
			"battle_time": float(_last_snapshot.get("battle_time", 0.0)),
		}, _last_snapshot)
		return
	if not _reconnecting:
		return
	if now_msec >= _reconnect_deadline_msec:
		_match_active = false
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


func _clear_session(clear_profile: bool) -> void:
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


func _emit_error(code: String, message: String) -> void:
	network_error.emit(code, message)


func _error_message_for_code(code: String) -> String:
	match code:
		"protocol_mismatch":
			return "LAN protocol versions do not match."
		"content_mismatch":
			return "Card or relic data differs from the host. Update both PCs to the same build."
		"invalid_starter", "invalid_card", "invalid_deck_size", "loadout_over_limit":
			return "The selected LAN loadout is invalid."
		"lobby_full":
			return "The LAN lobby is full."
		"seat_reserved":
			return "The open seat is reserved for a reconnecting player."
		_:
			return "The LAN host rejected the connection (%s)." % code
