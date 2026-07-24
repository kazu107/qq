extends Node


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	_test_even_capacity()
	_test_round_pairings()
	_test_spectator_roles()
	_test_standings()
	_test_parallel_round_isolation()
	_test_participant_statuses()
	await _test_preparation_roster_ui()
	print("Arena tournament smoke passed: parallel pairings, spectator isolation, standings, and UI")
	get_tree().quit()


func _test_even_capacity() -> void:
	_expect(LanProtocol.sanitize_player_capacity(1) == 2, "Capacity below minimum was not clamped")
	_expect(LanProtocol.sanitize_player_capacity(5) == 4, "Odd capacity was not converted to an even value")
	_expect(LanProtocol.sanitize_player_capacity(9) == 8, "Capacity above maximum was not clamped")


func _test_round_pairings() -> void:
	var peer_ids: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
	var host_opponents: Dictionary = {}
	for round_index in range(peer_ids.size() - 1):
		var pairings: Array[Dictionary] = ArenaTournamentCoordinator.build_round_pairings(peer_ids, round_index)
		_expect(pairings.size() == 4, "Eight players did not create four pairings")
		var seen: Dictionary = {}
		for pairing in pairings:
			var player_peer_id: int = int(pairing.get("player_peer_id", -1))
			var enemy_peer_id: int = int(pairing.get("enemy_peer_id", -1))
			_expect(player_peer_id != enemy_peer_id, "A player was paired against itself")
			_expect(not seen.has(player_peer_id) and not seen.has(enemy_peer_id), "A player appeared twice in one round")
			seen[player_peer_id] = true
			seen[enemy_peer_id] = true
		var opponent_peer_id: int = ArenaTournamentCoordinator.find_opponent_peer_id(pairings, 1)
		host_opponents[opponent_peer_id] = true
	_expect(host_opponents.size() == peer_ids.size() - 1, "Round-robin rotation repeated a host opponent")
	_expect(ArenaTournamentCoordinator.build_round_pairings([1, 2, 3], 0).is_empty(), "Odd player count created invalid pairings")


func _test_spectator_roles() -> void:
	var spectator_profile: Dictionary = LanProtocol.build_profile("Watcher", "balanced", true, "spectator-token", LanProtocol.ROLE_SPECTATOR)
	var validation: Dictionary = LanProtocol.validate_profile(spectator_profile)
	_expect(bool(validation.get("valid", false)), "Spectator profile was rejected")
	var profile: Dictionary = Dictionary(validation.get("profile", {}))
	_expect(String(profile.get("role", "")) == LanProtocol.ROLE_SPECTATOR, "Spectator role was lost")
	_expect(not bool(profile.get("ready", true)), "Spectator was counted as ready")
	var sides: Dictionary = ArenaTournamentCoordinator.build_peer_sides([1, 2, 3, 4, 5], 2, 4)
	_expect(String(sides.get("2", "")) == "player", "First combatant side was invalid")
	_expect(String(sides.get("4", "")) == "enemy", "Second combatant side was invalid")
	_expect(String(sides.get("1", "")) == "spectator" and String(sides.get("5", "")) == "spectator", "Inactive peers were not spectators")


func _test_standings() -> void:
	var profiles: Dictionary = {}
	var runs: Dictionary = {}
	for peer_id in [1, 2, 3, 4]:
		profiles[peer_id] = LanProtocol.build_profile("P%d" % peer_id, "balanced")
		var run_state: RunState = LanProtocol.profile_to_run(profiles[peer_id], peer_id)
		run_state.arena_wins = peer_id % 3
		run_state.arena_losses = 4 - peer_id
		runs[peer_id] = run_state
	var standings: Array[Dictionary] = ArenaTournamentCoordinator.build_standings([1, 2, 3, 4], profiles, runs)
	_expect(standings.size() == 4, "Standings omitted players")
	_expect(int(standings[0].get("wins", 0)) >= int(standings[1].get("wins", 0)), "Standings were not sorted by wins")
	for index in range(standings.size()):
		_expect(int(standings[index].get("rank", 0)) == index + 1, "Standing rank was invalid")


func _test_parallel_round_isolation() -> void:
	NetworkManager._clear_session(false)
	var profiles: Dictionary = {}
	var runs: Dictionary = {}
	var coordinator: LanArenaCoordinator = LanArenaCoordinator.new()
	for peer_id in [1, 2, 3, 4]:
		var profile: Dictionary = LanProtocol.build_profile("P%d" % peer_id, "balanced")
		profiles[peer_id] = profile
		var run_state: RunState = coordinator.create_run(profile, 500 + peer_id)
		run_state.max_hp = 50 + peer_id * 10
		run_state.player_hp = run_state.max_hp
		runs[peer_id] = run_state
	profiles[5] = LanProtocol.build_profile(
		"Watcher",
		"balanced",
		false,
		"watcher-token",
		LanProtocol.ROLE_SPECTATOR
	)
	var first_engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	var second_engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	first_engine.set_audio_enabled(false)
	second_engine.set_audio_enabled(false)
	first_engine.setup_pvp(runs[1] as RunState, runs[4] as RunState, "P1", "P4")
	second_engine.setup_pvp(runs[2] as RunState, runs[3] as RunState, "P2", "P3")
	first_engine.start_battle()
	second_engine.start_battle()
	NetworkManager._is_host = true
	NetworkManager._arena_session_active = true
	NetworkManager._arena_session_id = "parallel-test"
	NetworkManager._arena_phase = "battle"
	NetworkManager._profiles_by_peer = profiles
	NetworkManager._arena_runs_by_peer = runs
	NetworkManager._arena_player_peer_ids = [1, 2, 3, 4]
	NetworkManager._arena_pairings = [
		{"player_peer_id": 1, "enemy_peer_id": 4},
		{"player_peer_id": 2, "enemy_peer_id": 3},
	]
	NetworkManager._arena_standings = ArenaTournamentCoordinator.build_standings(
		NetworkManager._arena_player_peer_ids,
		profiles,
		runs
	)
	NetworkManager._arena_round_results = [
		{"match_id": "m1", "pair_index": 0, "player_peer_id": 1, "enemy_peer_id": 4, "player_name": "P1", "enemy_name": "P4", "status": "running"},
		{"match_id": "m2", "pair_index": 1, "player_peer_id": 2, "enemy_peer_id": 3, "player_name": "P2", "enemy_name": "P3", "status": "running"},
	]
	NetworkManager._parallel_match_contexts = {
		"m1": _make_parallel_context("m1", 0, 1, 4, first_engine),
		"m2": _make_parallel_context("m2", 1, 2, 3, second_engine),
	}
	NetworkManager._process_parallel_matches(0.25)
	_expect(is_equal_approx(first_engine.battle_state.battle_time, 0.25), "First parallel battle did not advance")
	_expect(is_equal_approx(second_engine.battle_state.battle_time, 0.25), "Second parallel battle did not advance")

	var untouched_two_hp: int = (runs[2] as RunState).player_hp
	var untouched_three_hp: int = (runs[3] as RunState).player_hp
	first_engine.battle_state.player.hp = 37
	first_engine.battle_state.enemy.hp = 0
	first_engine.battle_state.winner = "player"
	NetworkManager._publish_parallel_context_snapshot("m1", true)
	_expect(NetworkManager._finish_parallel_match("m1"), "First parallel result was rejected")
	_expect((runs[1] as RunState).arena_wins == 1, "First match winner did not receive a win")
	_expect((runs[4] as RunState).arena_losses == 1, "First match loser did not receive a loss")
	_expect((runs[2] as RunState).arena_wins == 0 and (runs[2] as RunState).arena_losses == 0, "Other pairing received the first result")
	_expect((runs[3] as RunState).arena_wins == 0 and (runs[3] as RunState).arena_losses == 0, "Other pairing received the first result")
	_expect((runs[2] as RunState).player_hp == untouched_two_hp and (runs[3] as RunState).player_hp == untouched_three_hp, "Other pairing HP was overwritten")
	_expect(not NetworkManager._arena_runs_by_peer.has(5), "Spectator received an arena RunState")
	_expect(not NetworkManager._arena_round_results_complete, "Round completed before every pairing finished")

	second_engine.battle_state.player.hp = 0
	second_engine.battle_state.enemy.hp = 31
	second_engine.battle_state.winner = "enemy"
	NetworkManager._publish_parallel_context_snapshot("m2", true)
	_expect(NetworkManager._finish_parallel_match("m2"), "Second parallel result was rejected")
	_expect((runs[2] as RunState).arena_losses == 1, "Second match loser did not receive a loss")
	_expect((runs[3] as RunState).arena_wins == 1, "Second match winner did not receive a win")
	_expect(NetworkManager._arena_round_results_complete, "Round did not complete after every pairing finished")
	_expect(not NetworkManager._acknowledge_round_results_for_peer(5), "Spectator was allowed to advance player results")
	_expect(NetworkManager._acknowledge_round_results_for_peer(1), "Player result acknowledgement failed")
	var result_snapshot: Dictionary = NetworkManager.get_arena_round_results_snapshot()
	_expect(int(result_snapshot.get("continue_ready_count", 0)) == 1, "Player acknowledgement count was invalid")
	NetworkManager._clear_session(false)


func _make_parallel_context(
	match_id: String,
	pair_index: int,
	player_peer_id: int,
	enemy_peer_id: int,
	engine: RealtimeBattleEngine
) -> Dictionary:
	return {
		"match_id": match_id,
		"pair_index": pair_index,
		"player_peer_id": player_peer_id,
		"enemy_peer_id": enemy_peer_id,
		"payload": {
			"match_id": match_id,
			"player_name": "P%d" % player_peer_id,
			"enemy_name": "P%d" % enemy_peer_id,
		},
		"engine": engine,
		"viewer_peer_ids": [],
		"ready_by_side": {"player": true, "enemy": true},
		"countdown_active": false,
		"countdown_deadline_msec": 0,
		"countdown_finished": true,
		"snapshot_sequence": 0,
		"snapshot_elapsed": 0.0,
		"last_snapshot": {},
		"finished": false,
		"result": {},
	}


func _test_participant_statuses() -> void:
	NetworkManager._arena_standings = [
		{"peer_id": 1, "name": "Alpha", "wins": 2, "losses": 0},
		{"peer_id": 2, "name": "Beta", "wins": 1, "losses": 1},
	]
	NetworkManager._arena_ready_by_peer = {"1": false, "2": true}
	var participants: Array[Dictionary] = NetworkManager.get_arena_participant_statuses()
	_expect(participants.size() == 2, "Preparation participants were omitted")
	_expect(not bool(participants[0].get("ready", true)), "Preparing participant state was invalid")
	_expect(bool(participants[1].get("ready", false)), "Ready participant state was invalid")
	NetworkManager._arena_standings.clear()
	NetworkManager._arena_ready_by_peer.clear()


func _test_preparation_roster_ui() -> void:
	NetworkManager._clear_session(false)
	var profiles: Dictionary = {
		1: LanProtocol.build_profile("Alpha", "balanced"),
		2: LanProtocol.build_profile("Beta", "balanced"),
	}
	var coordinator: LanArenaCoordinator = LanArenaCoordinator.new()
	var runs: Dictionary = {
		1: coordinator.create_run(Dictionary(profiles[1]), 101),
		2: coordinator.create_run(Dictionary(profiles[2]), 202),
	}
	(runs[1] as RunState).arena_wins = 2
	(runs[2] as RunState).arena_wins = 1
	(runs[2] as RunState).arena_losses = 1
	NetworkManager._is_host = true
	NetworkManager._session_scope = NetworkManager.SESSION_SCOPE_ONLINE
	NetworkManager._arena_session_active = true
	NetworkManager._arena_phase = "preparation"
	NetworkManager._profiles_by_peer = profiles
	NetworkManager._arena_runs_by_peer = runs
	NetworkManager._arena_player_peer_ids = [1, 2]
	NetworkManager._arena_pairings = ArenaTournamentCoordinator.build_round_pairings([1, 2], 0)
	NetworkManager._arena_standings = ArenaTournamentCoordinator.build_standings([1, 2], profiles, runs)
	NetworkManager._arena_ready_by_peer = {"1": false, "2": true}

	var arena: Control = load("res://scenes/arena/Arena.tscn").instantiate() as Control
	add_child(arena)
	await get_tree().process_frame
	var status_label: Label = arena.find_child("ArenaStatusLabel", true, false) as Label
	var loadout_body: VBoxContainer = arena.find_child("ArenaLoadoutPanelBody", true, false) as VBoxContainer
	var participants_body: VBoxContainer = arena.find_child("ArenaParticipantsPanelBody", true, false) as VBoxContainer
	var participants_list: VBoxContainer = arena.find_child("ArenaParticipantsList", true, false) as VBoxContainer
	var preparing_label: Label = arena.find_child("ArenaParticipantReady_1", true, false) as Label
	var ready_label: Label = arena.find_child("ArenaParticipantReady_2", true, false) as Label
	_expect(status_label != null and not status_label.visible, "Legacy preparation score and readiness text remained visible")
	_expect(participants_list != null and participants_list.get_child_count() == 2, "Preparation roster did not show every player")
	_expect(loadout_body != null and participants_body != null and participants_body.get_parent().get_parent().get_index() > loadout_body.get_parent().get_parent().get_index(), "Preparation roster was not placed to the right of the loadout")
	_expect(preparing_label != null and preparing_label.get_theme_color("font_color").is_equal_approx(Color(1.0, 0.78, 0.28, 1.0)), "Preparing state was not yellow")
	_expect(ready_label != null and ready_label.get_theme_color("font_color").is_equal_approx(Color(0.30, 1.0, 0.62, 1.0)), "Ready state was not green")
	arena.queue_free()
	await get_tree().process_frame
	NetworkManager._clear_session(false)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	get_tree().quit(1)
