extends Node


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("Web bots smoke: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _fixture(count: int, spectator: bool = false) -> void:
	NetworkManager._clear_session(false)
	NetworkManager._is_host = true
	NetworkManager._session_scope = NetworkManager.SESSION_SCOPE_ONLINE
	NetworkManager._peer = OfflineMultiplayerPeer.new()
	NetworkManager.multiplayer.multiplayer_peer = NetworkManager._peer
	NetworkManager._state = NetworkManager.ConnectionState.HOSTING
	NetworkManager._online_max_players = count
	NetworkManager._online_target_wins = 3
	NetworkManager._online_special_reward_interval = 1
	var profile: Dictionary = NetworkManager.configure_local_player("Human", "balanced", LanProtocol.ROLE_SPECTATOR if spectator else LanProtocol.ROLE_PLAYER)
	profile["ready"] = not spectator
	NetworkManager._local_profile = profile
	NetworkManager._profiles_by_peer[1] = profile


func _run() -> void:
	_fixture(4)
	var bots: Array[Dictionary] = [
		{"id": 1000000001, "name": "BOT 1", "starterId": "tempo"},
		{"id": 1000000002, "name": "BOT 2", "starterId": "fortress"},
		{"id": 1000000003, "name": "BOT 3", "starterId": "balanced"},
	]
	NetworkManager._on_web_bots_updated(bots.slice(0, 2), true, "")
	_check(not NetworkManager.can_start_match(), "Odd/incomplete room started")
	NetworkManager._on_web_bots_updated(bots, true, "")
	_check(NetworkManager.can_start_match(), "Ready bots did not fill capacity")
	_check(NetworkManager.get_lobby_player_count() == 4, "Bots were omitted from player count")
	_check(NetworkManager._get_all_peer_ids() == [1], "Bots entered RPC recipient list")
	_check(bool(NetworkManager.get_lobby_players()[1].get("is_bot", false)), "Bot flag was not public")
	var forged: Dictionary = LanProtocol.build_profile("Guest", "balanced")
	forged["is_bot"] = true
	_check(not bool(Dictionary(LanProtocol.validate_profile(forged).get("profile", {})).get("is_bot", false)), "Remote client could forge a bot")
	var lobby: Control = load("res://scenes/online/OnlineLobby.tscn").instantiate() as Control
	add_child(lobby)
	await get_tree().process_frame
	_check(lobby.find_child("OnlineAddBotButton", true, false) != null, "Lobby has no bot add button")
	_check(lobby.find_child("OnlineRemoveBot_1000000001", true, false) != null, "Lobby has no bot remove button")
	lobby.queue_free()
	await get_tree().process_frame
	_check(NetworkManager.start_lan_arena_preparation(), "Arena preparation failed")
	for _tick: int in 3:
		NetworkManager._process_arena_bots(0.4)
	_check(NetworkManager.get_lan_arena_phase() == "preparation", "Bots skipped human preparation")
	_check(NetworkManager.get_arena_ready_count() == 3, "Bots did not finish preparation")
	for bot: Dictionary in bots:
		var run: RunState = NetworkManager._arena_runs_by_peer[int(bot["id"])]
		_check(run.gold >= 0 and run.gold <= run.arena_initial_gold, "Bot purchased with free/negative gold")
		_check(NetworkManager._arena_coordinator.has_valid_loadout(run), "Bot loadout invalid")
	_check(not NetworkManager.remove_online_bot(1000000001), "Bot removed during preparation")
	_check(not NetworkManager.add_online_bot(), "Bot added during preparation")
	_check(NetworkManager.set_local_arena_ready(true), "Human ready action failed")
	_check(NetworkManager._parallel_match_contexts.size() == 2, "Mixed room did not create parallel matches")
	var local: Dictionary = NetworkManager._get_local_parallel_match_context()
	_check(Array(local.get("bot_ais", [])).size() == 1, "Human match has wrong AI count")
	_check(not bool(local.get("countdown_active", true)), "Bot started battle before human")
	var engine: RealtimeBattleEngine = local["engine"]
	NetworkManager._process_parallel_matches(0.1)
	_check(is_zero_approx(engine.battle_state.battle_time), "Human battle advanced without start")
	_check(NetworkManager.set_local_battle_ready(true), "Human start failed")
	for context: Dictionary in NetworkManager._parallel_match_contexts.values():
		context["countdown_deadline_msec"] = 0
	NetworkManager._process_parallel_matches(0.1)
	_check(engine.has_battle_started(), "Countdown did not start engine")
	_check(engine.battle_state.get_active_instances_for_side("enemy").size() > 0, "Bot did not cast")
	for context: Dictionary in NetworkManager._parallel_match_contexts.values():
		for peer_id: int in Array(context["viewer_peer_ids"]):
			_check(not NetworkManager.is_bot_peer(peer_id), "Bot entered snapshot/replay audience")
		var match_engine: RealtimeBattleEngine = context["engine"]
		match_engine.battle_state.enemy.hp = 0
		match_engine.battle_state.winner = "player"
		NetworkManager._publish_parallel_context_snapshot(String(context["match_id"]), true)
		NetworkManager._finish_parallel_match(String(context["match_id"]))
	_check(NetworkManager._arena_round_results_complete, "Bot-only result did not reach barrier")
	NetworkManager._process_arena_bots(3.1)
	_check(NetworkManager.get_lan_arena_phase() == "round_result", "Bots skipped human results")
	_check(int(NetworkManager.get_arena_round_results_snapshot()["continue_ready_count"]) == 3, "Bots did not acknowledge results")
	_check(NetworkManager.acknowledge_arena_round_results(), "Human result acknowledgement failed")
	for _tick: int in 3:
		NetworkManager._process_arena_bots(0.4)
	for bot: Dictionary in bots:
		var run: RunState = NetworkManager._arena_runs_by_peer[int(bot["id"])]
		_check(not NetworkManager._arena_coordinator.has_pending_reward(run), "Bot stalled on ordinary/special rewards")
	_check(NetworkManager.get_arena_ready_count() == 3, "Bots did not prepare the next round")
	_fixture(8)
	var full_roster: Array[Dictionary] = []
	for index: int in 7:
		full_roster.append({"id": 1000000001 + index, "name": "BOT %d" % index, "starterId": Dictionary(Database.starters[index]).get("id", "balanced")})
	NetworkManager._on_web_bots_updated(full_roster, true, "")
	_check(NetworkManager.start_lan_arena_preparation(), "Eight-player preparation failed")
	for _tick: int in 7:
		NetworkManager._process_arena_bots(0.4)
	_check(NetworkManager.get_arena_ready_count() == 7, "All starter-deck bots did not prepare")
	_check(NetworkManager.set_local_arena_ready(true), "Eight-player readiness failed")
	_check(NetworkManager._parallel_match_contexts.size() == 4, "Eight-player room did not create four matches")
	_check(NetworkManager._get_all_peer_ids() == [1], "Eight-player room created bot transports")
	_fixture(2, true)
	NetworkManager._on_web_bots_updated(bots.slice(0, 2), true, "")
	_check(NetworkManager.can_start_match(), "Host spectator cannot start bot-only room")
	_check(NetworkManager.start_lan_arena_preparation(), "Bot-only room did not prepare")
	for _tick: int in 2:
		NetworkManager._process_arena_bots(0.4)
	_check(NetworkManager.is_local_match_spectator(), "Spectator became a combatant")
	_check(not NetworkManager._arena_runs_by_peer.has(1), "Spectator received bot run/stats")
	local = NetworkManager._get_local_parallel_match_context()
	_check(Array(local["bot_ais"]).size() == 2, "Bot-only match has wrong AI count")
	_check(bool(local["countdown_active"]), "Bot-only countdown was not automatic")
	local["countdown_deadline_msec"] = 0
	for _tick: int in 3600:
		NetworkManager._process_parallel_matches(0.1)
		if NetworkManager._arena_round_results_complete:
			break
	_check(NetworkManager._arena_round_results_complete, "Unforced bot-only battle failed to resolve")
	_check(not NetworkManager._arena_runs_by_peer.has(1), "Natural bot battle credited the spectator")
	NetworkManager._clear_session(false)
	print("WEB_BOTS_SMOKE_OK lobby, capacity, RPC isolation, purchases, AI, readiness, rewards, result barrier and spectator")
	get_tree().quit()
