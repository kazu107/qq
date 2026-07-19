extends RefCounted
class_name ArenaTournamentCoordinator


static func build_round_pairings(peer_ids: Array[int], round_index: int) -> Array[Dictionary]:
	var ordered: Array[int] = peer_ids.duplicate()
	ordered.sort()
	if ordered.size() < 2 or ordered.size() % 2 != 0:
		return []

	var fixed_peer: int = ordered[0]
	var rotating: Array[int] = ordered.slice(1)
	if rotating.size() > 1:
		var shift: int = posmod(round_index, rotating.size())
		for _step in range(shift):
			rotating.push_front(rotating.pop_back())
	ordered = [fixed_peer]
	ordered.append_array(rotating)

	var pairings: Array[Dictionary] = []
	for pair_index in range(ordered.size() / 2):
		pairings.append({
			"pair_index": pair_index,
			"player_peer_id": ordered[pair_index],
			"enemy_peer_id": ordered[ordered.size() - pair_index - 1],
		})
	return pairings


static func build_peer_sides(all_peer_ids: Array[int], player_peer_id: int, enemy_peer_id: int) -> Dictionary:
	var peer_sides: Dictionary = {}
	for peer_id in all_peer_ids:
		var side: String = "spectator"
		if peer_id == player_peer_id:
			side = "player"
		elif peer_id == enemy_peer_id:
			side = "enemy"
		peer_sides[str(peer_id)] = side
	return peer_sides


static func find_opponent_peer_id(pairings: Array[Dictionary], peer_id: int) -> int:
	for pairing in pairings:
		var player_peer_id: int = int(pairing.get("player_peer_id", -1))
		var enemy_peer_id: int = int(pairing.get("enemy_peer_id", -1))
		if player_peer_id == peer_id:
			return enemy_peer_id
		if enemy_peer_id == peer_id:
			return player_peer_id
	return -1


static func build_standings(
	peer_ids: Array[int],
	profiles_by_peer: Dictionary,
	runs_by_peer: Dictionary
) -> Array[Dictionary]:
	var standings: Array[Dictionary] = []
	for peer_id in peer_ids:
		var profile: Dictionary = Dictionary(profiles_by_peer.get(peer_id, {}))
		var run_state: RunState = runs_by_peer.get(peer_id) as RunState
		standings.append({
			"peer_id": peer_id,
			"name": String(profile.get("name", "Player")),
			"starter_id": String(profile.get("starter_id", "balanced")),
			"wins": run_state.arena_wins if run_state != null else 0,
			"losses": run_state.arena_losses if run_state != null else 0,
		})
	standings.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_wins: int = int(left.get("wins", 0))
		var right_wins: int = int(right.get("wins", 0))
		if left_wins != right_wins:
			return left_wins > right_wins
		var left_losses: int = int(left.get("losses", 0))
		var right_losses: int = int(right.get("losses", 0))
		if left_losses != right_losses:
			return left_losses < right_losses
		return int(left.get("peer_id", 0)) < int(right.get("peer_id", 0))
	)
	for index in range(standings.size()):
		standings[index]["rank"] = index + 1
	return standings
