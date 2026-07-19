extends Node


func _ready() -> void:
	Database.load_all()
	_test_even_capacity()
	_test_round_pairings()
	_test_spectator_roles()
	_test_standings()
	print("Arena tournament smoke passed: even capacities, pairings, spectators, and standings")
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


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	get_tree().quit(1)
