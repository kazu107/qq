extends Node

const DEFAULT_SOAK_SECONDS: float = 35.0
const TIMEOUT_PADDING_SECONDS: float = 15.0
const EVENT_BATCH_INTERVAL: float = 0.1
const EVENTS_PER_BATCH: int = 1
const MAX_SNAPSHOT_BYTES: int = 32768
const MAX_RECEIVE_GAP_MSEC: int = 1500

var _role: String = ""
var _port: int = LanProtocol.DEFAULT_PORT + 180
var _soak_seconds: float = DEFAULT_SOAK_SECONDS
var _elapsed: float = 0.0
var _arena_started: bool = false
var _arena_ready: bool = false
var _battle_screen: Control
var _soak_active: bool = false
var _soak_start_msec: int = 0
var _generated_soak_events: int = 0
var _heavy_unit: Dictionary = {}
var _heavy_timeline: Array[Dictionary] = []
var _snapshot_count: int = 0
var _last_snapshot_received_msec: int = 0
var _max_receive_gap_msec: int = 0
var _max_snapshot_bytes: int = 0
var _last_remote_battle_time: float = 0.0
var _last_event_total: int = 0
var _finishing: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	_parse_arguments()
	_heavy_unit = _build_heavy_unit_snapshot()
	_heavy_timeline = _build_heavy_timeline()
	NetworkManager.lobby_changed.connect(_on_lobby_changed)
	NetworkManager.arena_preparation_started.connect(_on_arena_preparation_started)
	NetworkManager.match_started.connect(_on_match_started)
	NetworkManager.battle_countdown_finished.connect(_on_battle_countdown_finished)
	NetworkManager.battle_snapshot_received.connect(_on_battle_snapshot_received)
	NetworkManager.network_error.connect(_on_network_error)
	NetworkManager.session_ended.connect(_on_session_ended)
	call_deferred("_start_role")


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _soak_seconds + TIMEOUT_PADDING_SECONDS and not _finishing:
		_fail("timeout")
		return
	if not _soak_active or _finishing:
		return
	var soak_elapsed: float = float(Time.get_ticks_msec() - _soak_start_msec) / 1000.0
	if _role == "host":
		var expected_event_count: int = int(floor(_soak_seconds / EVENT_BATCH_INTERVAL)) * EVENTS_PER_BATCH
		var elapsed_event_count: int = int(floor(minf(soak_elapsed, _soak_seconds) / EVENT_BATCH_INTERVAL)) * EVENTS_PER_BATCH
		var target_event_count: int = mini(expected_event_count, elapsed_event_count)
		while _generated_soak_events < target_event_count:
			_append_host_event_batch()
		if soak_elapsed >= _soak_seconds + 1.0 and _generated_soak_events >= expected_event_count:
			_finish_host()
	elif soak_elapsed >= _soak_seconds:
		_finish_client()


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lan-soak-role="):
			_role = argument.trim_prefix("--lan-soak-role=")
		elif argument.begins_with("--lan-soak-port="):
			_port = int(argument.trim_prefix("--lan-soak-port="))
		elif argument.begins_with("--lan-soak-seconds="):
			_soak_seconds = maxf(5.0, float(argument.trim_prefix("--lan-soak-seconds=")))


func _start_role() -> void:
	if _role == "host":
		if not NetworkManager.host_lobby("Soak Host", "balanced", _port):
			_fail("host_failed")
	elif _role == "client":
		await get_tree().create_timer(0.35).timeout
		if not NetworkManager.join_lobby("127.0.0.1", "Soak Client", "tempo", _port):
			_fail("join_failed")
	else:
		_fail("missing_role")


func _on_lobby_changed(_snapshot: Dictionary) -> void:
	if NetworkManager.is_lan_arena_session_active():
		return
	if not NetworkManager.is_local_ready():
		NetworkManager.set_local_ready(true)
		return
	if _role == "host" and NetworkManager.can_start_match() and not _arena_started:
		_arena_started = true
		call_deferred("_start_arena")


func _start_arena() -> void:
	if not NetworkManager.start_lan_arena_preparation():
		_fail("arena_start_failed")


func _on_arena_preparation_started(_snapshot: Dictionary) -> void:
	if _arena_ready:
		return
	_arena_ready = true
	if not NetworkManager.set_local_arena_ready(true):
		_fail("arena_ready_failed")


func _on_match_started(_payload: Dictionary) -> void:
	if _battle_screen == null:
		var battle_scene: PackedScene = load("res://scenes/battle/Battle.tscn") as PackedScene
		if battle_scene == null:
			_fail("battle_scene_missing")
			return
		_battle_screen = battle_scene.instantiate() as Control
		add_child(_battle_screen)
	await get_tree().process_frame
	if not NetworkManager.set_local_battle_ready(true):
		_fail("battle_ready_failed")


func _on_battle_countdown_finished() -> void:
	if _soak_active:
		return
	_soak_active = true
	_soak_start_msec = Time.get_ticks_msec()
	_last_snapshot_received_msec = _soak_start_msec


func _on_battle_snapshot_received(snapshot: Dictionary) -> void:
	if _role != "client" or not _soak_active:
		return
	var now_msec: int = Time.get_ticks_msec()
	if _snapshot_count > 0:
		_max_receive_gap_msec = maxi(_max_receive_gap_msec, now_msec - _last_snapshot_received_msec)
	_last_snapshot_received_msec = now_msec
	_snapshot_count += 1
	_max_snapshot_bytes = maxi(_max_snapshot_bytes, var_to_bytes(snapshot).size())
	_last_remote_battle_time = float(snapshot.get("battle_time", 0.0))
	_last_event_total = int(snapshot.get("battle_event_total", 0))
	if Array(snapshot.get("battle_events", [])).size() > BattleStateCodec.NETWORK_EVENT_WINDOW:
		_fail("event_window_exceeded")


func _append_host_event_batch() -> void:
	if _battle_screen == null:
		return
	var engine: RealtimeBattleEngine = _battle_screen.get("_engine") as RealtimeBattleEngine
	if engine == null or engine.battle_state == null:
		return
	for _event_offset in range(EVENTS_PER_BATCH):
		var event_index: int = engine.battle_state.battle_events.size()
		engine.battle_state.record_event({
			"time": engine.battle_state.battle_time,
			"event_type": "network_soak",
			"actor_id": "player",
			"card_id": "quick_slash",
			"target_id": "enemy",
			"result": {
				"player_before": _heavy_unit,
				"player_after": _heavy_unit,
				"enemy_before": _heavy_unit,
				"enemy_after": _heavy_unit,
				"event_index": event_index,
			},
			"hp_delta": 0,
			"shield_delta": 0,
			"timeline_before": _heavy_timeline,
			"timeline_after": _heavy_timeline,
		})
		_generated_soak_events += 1
	engine.battle_state.add_log("network soak events=%d" % engine.battle_state.battle_events.size())


func _finish_client() -> void:
	if _finishing:
		return
	var minimum_snapshots: int = maxi(1, int(floor(_soak_seconds * 6.0)))
	var minimum_events: int = maxi(1, int(floor(_soak_seconds / EVENT_BATCH_INTERVAL)) * EVENTS_PER_BATCH - 24)
	if _snapshot_count < minimum_snapshots:
		_fail("too_few_snapshots_%d" % _snapshot_count)
		return
	if _max_receive_gap_msec > MAX_RECEIVE_GAP_MSEC:
		_fail("receive_gap_%dms" % _max_receive_gap_msec)
		return
	if _max_snapshot_bytes > MAX_SNAPSHOT_BYTES:
		_fail("snapshot_too_large_%d" % _max_snapshot_bytes)
		return
	if _last_remote_battle_time < _soak_seconds - 2.0:
		_fail("battle_time_lag_%.2f" % _last_remote_battle_time)
		return
	if _last_event_total < minimum_events:
		_fail("event_total_lag_%d" % _last_event_total)
		return
	_finishing = true
	print("LAN_NETWORK_SOAK_OK client snapshots=%d max_gap=%dms max_bytes=%d battle_time=%.2f events=%d" % [
		_snapshot_count,
		_max_receive_gap_msec,
		_max_snapshot_bytes,
		_last_remote_battle_time,
		_last_event_total,
	])
	NetworkManager.leave_session("network_soak_client_complete")
	get_tree().quit()


func _finish_host() -> void:
	if _finishing:
		return
	var engine: RealtimeBattleEngine = _battle_screen.get("_engine") as RealtimeBattleEngine
	if engine == null or engine.battle_state == null:
		_fail("host_engine_missing")
		return
	var latest_snapshot: Dictionary = NetworkManager.get_last_snapshot()
	var snapshot_bytes: int = var_to_bytes(latest_snapshot).size()
	var expected_events: int = maxi(1, int(floor(_soak_seconds / EVENT_BATCH_INTERVAL)) * EVENTS_PER_BATCH)
	if engine.battle_state.battle_events.size() < expected_events:
		_fail("host_event_total_lag_%d" % engine.battle_state.battle_events.size())
		return
	if snapshot_bytes > MAX_SNAPSHOT_BYTES:
		_fail("host_snapshot_too_large_%d" % snapshot_bytes)
		return
	_finishing = true
	print("LAN_NETWORK_SOAK_OK host events=%d snapshot_bytes=%d battle_time=%.2f" % [
		engine.battle_state.battle_events.size(),
		snapshot_bytes,
		engine.battle_state.battle_time,
	])
	NetworkManager.leave_session("network_soak_complete")
	get_tree().quit()


func _build_heavy_unit_snapshot() -> Dictionary:
	var runtime_states: Array[Dictionary] = []
	for runtime_index in range(16):
		runtime_states.append({
			"runtime_id": "player_%d" % runtime_index,
			"card_id": "quick_slash",
			"loadout_index": runtime_index,
			"state": CardRuntimeState.CardState.READY,
			"cooldown_remaining": float(runtime_index) * 0.1,
		})
	return {
		"hp": 50,
		"max_hp": 60,
		"shield": 12,
		"attack": 4,
		"speed": 7,
		"statuses": {"bleed": {"remaining": 8.0, "stacks": 3}},
		"runtime_states": runtime_states,
		"temporary_card_modifiers": {
			"quick_slash": {"damage": 12.0, "cast_time": -0.6, "recast_time": -1.2},
		},
	}


func _build_heavy_timeline() -> Array[Dictionary]:
	var timeline: Array[Dictionary] = []
	for timeline_index in range(12):
		timeline.append({
			"instance_id": timeline_index,
			"owner_side": "player" if timeline_index % 2 == 0 else "enemy",
			"runtime_id": "runtime_%d" % timeline_index,
			"card_id": "quick_slash",
			"scheduled_time": float(timeline_index) * 0.75,
		})
	return timeline


func _on_network_error(code: String, _message: String) -> void:
	if not _finishing:
		_fail(code)


func _on_session_ended(reason: String) -> void:
	if not _finishing:
		_fail("session_ended_%s" % reason)


func _fail(reason: String) -> void:
	if _finishing:
		return
	_finishing = true
	push_error("LAN_NETWORK_SOAK_FAIL %s %s" % [_role, reason])
	NetworkManager.leave_session("network_soak_failed")
	get_tree().quit(1)
