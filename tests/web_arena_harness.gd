extends Node

# Exported only by the Web Validation preset, never by the production preset.
var _bridge: JavaScriptObject
var _window: JavaScriptObject
var _elapsed: float = 0.0
var _ticks: int = 0
var _error: String = ""


func _ready() -> void:
	Database.load_all()
	Game.settings["developer_mode"] = true
	_bridge = JavaScriptBridge.create_callback(_command)
	_window = JavaScriptBridge.get_interface("window")
	_window.qqCommand = _bridge
	NetworkManager.network_error.connect(func(code: String, message: String) -> void: _error = code + ":" + message)


func _command(args: Array) -> void:
	var payload: Dictionary = JSON.parse_string(String(args[0]))
	var action: String = String(payload.get("action", ""))
	match action:
		"host":
			NetworkManager.host_online_lobby("P1", "balanced", String(payload["room"]), 0, false, 3, int(payload.get("players", 4)))
		"join":
			NetworkManager.join_online_lobby("", String(payload.get("name", "P2")), "balanced", String(payload["room"]), 0, bool(payload.get("spectator", false)))
		"lobby_ready":
			NetworkManager.set_local_ready(true)
		"prepare":
			NetworkManager.start_lan_arena_preparation()
		"ready":
			NetworkManager.set_local_arena_ready(true)
		"start":
			NetworkManager.set_local_battle_ready(true)
		"finish_pair":
			var keys: Array = NetworkManager._parallel_match_contexts.keys()
			var context: Dictionary = NetworkManager._parallel_match_contexts[keys[int(payload.get("index", 0))]]
			var engine: RealtimeBattleEngine = context["engine"]
			engine.battle_state.player.hp = 10
			engine.battle_state.enemy.hp = 10
			engine.battle_state.player.shield = 0
			engine.battle_state.enemy.shield = 0
			engine.debug_schedule_fatigue()
		"marker_hp":
			var index: int = 0
			for context: Dictionary in NetworkManager._parallel_match_contexts.values():
				var engine: RealtimeBattleEngine = context["engine"]
				engine.battle_state.player.hp = 30 + index * 10
				engine.battle_state.enemy.hp = 31 + index * 10
				index += 1
		"ack":
			NetworkManager.acknowledge_arena_round_results()
		"leave":
			NetworkManager.leave_session()
		"clear_error":
			_error = ""


func _process(delta: float) -> void:
	_ticks += 1
	_elapsed += delta
	if _elapsed < 0.1 or _window == null:
		return
	_elapsed = 0.0
	var run: RunState = NetworkManager.get_local_arena_run()
	var snapshot: Dictionary = NetworkManager.get_last_snapshot()
	var state: Dictionary = {"ticks": _ticks, "error": _error, "players": NetworkManager.get_lobby_players(),
		"phase": NetworkManager.get_lan_arena_phase(), "connected": NetworkManager.is_session_connected(),
		"matches": NetworkManager.get_match_payload(), "side": NetworkManager.get_local_side(),
		"battle_time": snapshot.get("battle_time", 0), "player_hp": Dictionary(snapshot.get("player", {})).get("hp", 0),
		"enemy_hp": Dictionary(snapshot.get("enemy", {})).get("hp", 0),
		"run": run.to_dict() if run != null else {}, "results": NetworkManager.get_arena_round_results_snapshot(),
		"diagnostics": NetworkManager.diagnostics.snapshot()}
	_window.qqState = JSON.stringify(state)
