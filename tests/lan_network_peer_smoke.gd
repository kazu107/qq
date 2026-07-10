extends Node

const TIMEOUT_SECONDS: float = 15.0

var _role: String = ""
var _port: int = LanProtocol.DEFAULT_PORT + 80
var _elapsed: float = 0.0
var _match_start_requested: bool = false
var _commands_received: int = 0
var _results_received: int = 0
var _finishing: bool = false
var _battle_screen: Control
var _match_started_count: int = 0
var _disconnect_scheduled: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	_parse_arguments()
	NetworkManager.lobby_changed.connect(_on_lobby_changed)
	NetworkManager.match_started.connect(_on_match_started)
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
	if not NetworkManager.is_local_ready():
		NetworkManager.set_local_ready(true)
		return
	if _role == "host" and NetworkManager.can_start_match() and not _match_start_requested:
		_match_start_requested = true
		call_deferred("_start_match")


func _start_match() -> void:
	if not NetworkManager.start_lan_match():
		_fail("match_start_failed")


func _on_match_started(_payload: Dictionary) -> void:
	_match_started_count += 1
	if _battle_screen == null:
		var packed_battle: PackedScene = load("res://scenes/battle/Battle.tscn") as PackedScene
		if packed_battle == null:
			_fail("battle_scene_missing")
			return
		_battle_screen = packed_battle.instantiate() as Control
		add_child(_battle_screen)
	if _role != "client":
		return
	await get_tree().process_frame
	if _match_started_count == 1:
		if not NetworkManager.submit_start_command():
			_fail("start_command_failed")
	elif _match_started_count == 2:
		if not NetworkManager.submit_card_command("enemy_0"):
			_fail("card_command_after_reconnect_failed")


func _on_battle_command_received(_peer_id: int, _side: String, _kind: String, _runtime_id: String, _sequence: int) -> void:
	if _role != "host":
		return
	_commands_received += 1
	if _commands_received == 1 and not _disconnect_scheduled:
		_disconnect_scheduled = true
		call_deferred("_drop_remote_after_ack")
	if _commands_received >= 2 and not _finishing:
		_finishing = true
		await get_tree().create_timer(0.55).timeout
		var snapshot: Dictionary = NetworkManager.get_last_snapshot()
		var restored: BattleState = BattleStateCodec.decode(snapshot)
		if restored == null or not bool(snapshot.get("battle_started", false)):
			push_error("LAN_NETWORK_SMOKE_FAIL host battle_screen_sync")
			get_tree().quit(1)
			return
		print("LAN_NETWORK_SMOKE_OK host commands=%d battle_time=%.2f" % [_commands_received, restored.battle_time])
		await get_tree().create_timer(0.45).timeout
		NetworkManager.leave_session("peer_smoke_complete")
		get_tree().quit()


func _drop_remote_after_ack() -> void:
	await get_tree().create_timer(0.35).timeout
	if not NetworkManager.developer_disconnect_peer():
		_fail("developer_disconnect_failed")


func _on_command_result_received(_sequence: int, accepted: bool, _snapshot: Dictionary) -> void:
	if _role != "client" or not accepted:
		return
	_results_received += 1
	if _results_received >= 2 and not _finishing:
		_finishing = true
		await get_tree().create_timer(0.25).timeout
		var snapshot: Dictionary = NetworkManager.get_last_snapshot()
		var restored: BattleState = BattleStateCodec.decode(snapshot)
		if restored == null or not bool(snapshot.get("battle_started", false)):
			push_error("LAN_NETWORK_SMOKE_FAIL client battle_screen_sync")
			get_tree().quit(1)
			return
		print("LAN_NETWORK_SMOKE_OK client results=%d battle_time=%.2f" % [_results_received, restored.battle_time])
		await get_tree().create_timer(0.45).timeout
		NetworkManager.leave_session("peer_smoke_complete")
		get_tree().quit()


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
