extends RefCounted
class_name WebRtcSignalingClient

signal transport_ready(peer: WebRTCMultiplayerPeer, is_host: bool, room_code: String)
signal status_changed(message: String)
signal failed(code: String, message: String)
signal room_list_changed(rooms: Array[Dictionary])

const DEFAULT_LOCAL_SIGNALING_URL: String = "ws://127.0.0.1:8060/signal"
const MAX_SIGNAL_PACKET_BYTES: int = 65536
var _socket: WebSocketPeer
var _rtc_peer: WebRTCMultiplayerPeer
var _connections: Dictionary = {}
var _pending_candidates: Dictionary = {}
var _ice_servers: Array[Dictionary] = []
var _role: String = ""
var _room_code: String = ""
var _signaling_url: String = ""
var _join_sent: bool = false
var _transport_announced: bool = false
var _closing: bool = false
var _last_socket_state: int = WebSocketPeer.STATE_CLOSED
var _host_name: String = ""
var _target_wins: int = ArenaService.TARGET_WINS
var _max_players: int = LanProtocol.DEFAULT_PLAYERS
var _spectator_join: bool = false


func start_host(
	room_code: String,
	protocol_version: int,
	content_hash: String,
	host_name: String = "",
	target_wins: int = ArenaService.TARGET_WINS,
	max_players: int = LanProtocol.DEFAULT_PLAYERS
) -> Error:
	var start_error: Error = _start("host", room_code, protocol_version, content_hash)
	if start_error == OK:
		_host_name = host_name.strip_edges()
		_target_wins = target_wins
		_max_players = LanProtocol.sanitize_player_capacity(max_players)
	return start_error


func start_join(room_code: String, protocol_version: int, content_hash: String, spectator: bool = false) -> Error:
	var start_error: Error = _start("join", room_code, protocol_version, content_hash)
	if start_error == OK:
		_spectator_join = spectator
	return start_error


func start_directory(protocol_version: int, content_hash: String) -> Error:
	return _start("directory", "", protocol_version, content_hash)


func update_room(target_wins: int, max_players: int = LanProtocol.DEFAULT_PLAYERS) -> void:
	if _role != "host":
		return
	_target_wins = target_wins
	_max_players = LanProtocol.sanitize_player_capacity(max_players)
	_send({
		"type": "update_room",
		"targetWins": target_wins,
		"maxPlayers": _max_players,
	})


func poll() -> void:
	if _socket == null:
		return
	_socket.poll()
	var socket_state: int = _socket.get_ready_state()
	if socket_state != _last_socket_state:
		_last_socket_state = socket_state
		if socket_state == WebSocketPeer.STATE_OPEN:
			_send_join_request()
		elif socket_state == WebSocketPeer.STATE_CLOSED and not _closing:
			_handle_unexpected_close()
	if socket_state != WebSocketPeer.STATE_OPEN:
		return
	while _socket.get_available_packet_count() > 0:
		var packet: PackedByteArray = _socket.get_packet()
		if packet.size() > MAX_SIGNAL_PACKET_BYTES:
			_fail("signal_packet_too_large", "The signaling server sent an invalid packet.")
			return
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			_fail("invalid_signal", "The signaling server sent invalid data.")
			return
		_handle_message(Dictionary(parsed))
		if _socket == null:
			return


func close() -> void:
	_closing = true
	if _socket != null:
		_socket.close(1000, "client_closed")
	_socket = null
	if _rtc_peer != null:
		_rtc_peer.close()
	_rtc_peer = null
	_connections.clear()
	_pending_candidates.clear()
	_ice_servers.clear()
	_role = ""
	_room_code = ""
	_signaling_url = ""
	_join_sent = false
	_transport_announced = false
	_host_name = ""
	_target_wins = ArenaService.TARGET_WINS
	_max_players = LanProtocol.DEFAULT_PLAYERS
	_spectator_join = false
	_last_socket_state = WebSocketPeer.STATE_CLOSED
	_closing = false


func get_room_code() -> String:
	return _room_code


func get_signaling_url() -> String:
	return _signaling_url


static func resolve_signaling_url() -> String:
	if not OS.has_feature("web"):
		return DEFAULT_LOCAL_SIGNALING_URL
	var protocol_value: Variant = JavaScriptBridge.eval("window.location.protocol", true)
	var host_value: Variant = JavaScriptBridge.eval("window.location.host", true)
	var page_protocol: String = String(protocol_value)
	var page_host: String = String(host_value)
	if page_host == "":
		return DEFAULT_LOCAL_SIGNALING_URL
	return "%s://%s/signal" % ["wss" if page_protocol == "https:" else "ws", page_host]


func _start(role: String, room_code: String, protocol_version: int, content_hash: String) -> Error:
	close()
	if not OS.has_feature("web"):
		_fail("web_only", "Web multiplayer is available in the browser edition.")
		return ERR_UNAVAILABLE
	_role = role
	_room_code = LanProtocol.sanitize_online_room_code(room_code)
	if _role != "directory" and _room_code == "":
		_fail("invalid_room_code", "Enter a valid room code.")
		return ERR_INVALID_PARAMETER
	_signaling_url = resolve_signaling_url()
	_socket = WebSocketPeer.new()
	_socket.set_outbound_buffer_size(MAX_SIGNAL_PACKET_BYTES * 2)
	_socket.set_inbound_buffer_size(MAX_SIGNAL_PACKET_BYTES * 2)
	var connect_error: Error = _socket.connect_to_url(_signaling_url)
	if connect_error != OK:
		_socket = null
		_fail("signal_connect_failed", "Could not connect to the Web multiplayer server.")
		return connect_error
	_socket.set_meta("protocol_version", protocol_version)
	_socket.set_meta("content_hash", content_hash)
	_last_socket_state = WebSocketPeer.STATE_CONNECTING
	status_changed.emit("Connecting to the Web multiplayer server...")
	return OK


func _send_join_request() -> void:
	if _join_sent or _socket == null:
		return
	_join_sent = true
	var request: Dictionary = {
		"type": "list_rooms" if _role == "directory" else _role,
		"protocolVersion": int(_socket.get_meta("protocol_version", -1)),
		"contentHash": String(_socket.get_meta("content_hash", "")),
	}
	if _role != "directory":
		request["room"] = _room_code
	if _role == "host":
		request["name"] = _host_name
		request["targetWins"] = _target_wins
		request["maxPlayers"] = _max_players
	elif _role == "join":
		request["spectator"] = _spectator_join
	_send(request)
	if _role != "directory":
		status_changed.emit("Creating room..." if _role == "host" else "Joining room...")


func _handle_message(message: Dictionary) -> void:
	var message_type: String = String(message.get("type", ""))
	match message_type:
		"room_list":
			room_list_changed.emit(_dictionary_array(message.get("rooms", [])))
		"assigned":
			_handle_assigned(message)
		"peer_joined":
			_create_connection(int(message.get("id", 0)))
		"peer_left":
			_remove_connection(int(message.get("id", 0)))
		"offer", "answer":
			_handle_session_description(message_type, message)
		"candidate":
			_handle_candidate(message)
		"error":
			_fail(
				String(message.get("code", "signal_error")),
				String(message.get("message", "Web multiplayer signaling failed."))
			)
		"pong":
			pass
		_:
			_fail("unknown_signal", "The signaling server sent an unknown message.")


func _handle_assigned(message: Dictionary) -> void:
	if _rtc_peer != null:
		return
	var local_id: int = int(message.get("id", 0))
	var assigned_role: String = String(message.get("role", ""))
	if local_id < 1 or (assigned_role != "host" and assigned_role != "guest"):
		_fail("invalid_assignment", "The multiplayer server returned an invalid assignment.")
		return
	_ice_servers = _dictionary_array(message.get("iceServers", []))
	_rtc_peer = WebRTCMultiplayerPeer.new()
	var create_error: Error = OK
	if assigned_role == "host":
		create_error = _rtc_peer.create_server()
	else:
		create_error = _rtc_peer.create_client(local_id)
	if create_error != OK:
		_fail("webrtc_create_failed", "Could not initialize the WebRTC multiplayer peer.")
		return
	_transport_announced = true
	transport_ready.emit(_rtc_peer, assigned_role == "host", _room_code)
	status_changed.emit("Room %s is ready." % _room_code if assigned_role == "host" else "Negotiating a peer connection...")
	for raw_peer_id in Array(message.get("peers", [])):
		_create_connection(int(raw_peer_id))


func _create_connection(peer_id: int) -> void:
	if _rtc_peer == null or peer_id <= 0 or _connections.has(peer_id):
		return
	var connection: WebRTCPeerConnection = WebRTCPeerConnection.new()
	var initialize_error: Error = connection.initialize({"iceServers": _ice_servers})
	if initialize_error != OK:
		_fail("webrtc_initialize_failed", "Could not initialize the browser peer connection.")
		return
	connection.session_description_created.connect(_on_session_description_created.bind(peer_id))
	connection.ice_candidate_created.connect(_on_ice_candidate_created.bind(peer_id))
	_connections[peer_id] = connection
	var add_error: Error = _rtc_peer.add_peer(connection, peer_id)
	if add_error != OK:
		_connections.erase(peer_id)
		_fail("webrtc_add_peer_failed", "Could not add the opponent to the WebRTC session.")
		return
	_flush_pending_candidates(peer_id, connection)
	if peer_id < _rtc_peer.get_unique_id():
		var offer_error: Error = connection.create_offer()
		if offer_error != OK:
			_fail("webrtc_offer_failed", "Could not create a WebRTC offer.")


func _remove_connection(peer_id: int) -> void:
	_connections.erase(peer_id)
	_pending_candidates.erase(peer_id)
	if _rtc_peer != null and peer_id > 0:
		_rtc_peer.remove_peer(peer_id)


func _handle_session_description(description_type: String, message: Dictionary) -> void:
	var peer_id: int = int(message.get("from", 0))
	if not _connections.has(peer_id):
		_create_connection(peer_id)
	var connection: WebRTCPeerConnection = _connections.get(peer_id) as WebRTCPeerConnection
	if connection == null:
		return
	var sdp: String = String(message.get("sdp", ""))
	if sdp == "":
		_fail("invalid_sdp", "The signaling server sent an empty session description.")
		return
	var remote_error: Error = connection.set_remote_description(description_type, sdp)
	if remote_error != OK:
		_fail("webrtc_remote_description_failed", "Could not apply the opponent connection description.")


func _handle_candidate(message: Dictionary) -> void:
	var peer_id: int = int(message.get("from", 0))
	var candidate: Dictionary = {
		"mid": String(message.get("mid", "")),
		"index": int(message.get("index", 0)),
		"candidate": String(message.get("candidate", "")),
	}
	var connection: WebRTCPeerConnection = _connections.get(peer_id) as WebRTCPeerConnection
	if connection == null:
		var queued: Array = Array(_pending_candidates.get(peer_id, []))
		queued.append(candidate)
		_pending_candidates[peer_id] = queued
		return
	_add_candidate(connection, candidate)


func _flush_pending_candidates(peer_id: int, connection: WebRTCPeerConnection) -> void:
	for raw_candidate in Array(_pending_candidates.get(peer_id, [])):
		_add_candidate(connection, Dictionary(raw_candidate))
	_pending_candidates.erase(peer_id)


func _add_candidate(connection: WebRTCPeerConnection, candidate: Dictionary) -> void:
	var candidate_text: String = String(candidate.get("candidate", ""))
	if candidate_text == "":
		return
	connection.add_ice_candidate(
		String(candidate.get("mid", "")),
		int(candidate.get("index", 0)),
		candidate_text
	)


func _on_session_description_created(description_type: String, sdp: String, peer_id: int) -> void:
	var connection: WebRTCPeerConnection = _connections.get(peer_id) as WebRTCPeerConnection
	if connection == null:
		return
	var local_error: Error = connection.set_local_description(description_type, sdp)
	if local_error != OK:
		_fail("webrtc_local_description_failed", "Could not apply the local connection description.")
		return
	_send({
		"type": description_type,
		"to": peer_id,
		"sdp": sdp,
	})


func _on_ice_candidate_created(mid: String, index: int, candidate: String, peer_id: int) -> void:
	_send({
		"type": "candidate",
		"to": peer_id,
		"mid": mid,
		"index": index,
		"candidate": candidate,
	})


func _send(payload: Dictionary) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(payload))


func _handle_unexpected_close() -> void:
	if _role == "directory":
		room_list_changed.emit([])
		return
	if _transport_announced:
		status_changed.emit("The signaling channel closed; the current peer connection remains active.")
		return
	_fail("signal_disconnected", "The Web multiplayer server disconnected before the room was ready.")


func _fail(code: String, message: String) -> void:
	failed.emit(code, message)


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_entry in Array(value):
		if typeof(raw_entry) == TYPE_DICTIONARY:
			result.append(Dictionary(raw_entry).duplicate(true))
	return result
