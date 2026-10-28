extends RefCounted
class_name EncounterSeries


static func normal_battle_count(step_index: int) -> int:
	return 1 + floori(float(maxi(0, step_index)) / 14.0)


static func build_hazard_queue(area: int, step_index: int = 0, infinite: bool = false) -> Array[String]:
	var local_area: int = 1 + (maxi(1, area) - 1) % 12 if infinite else area
	var pattern: Array[String]
	if local_area <= 2:
		pattern = ["raider", "guardian"]
	elif local_area <= 3:
		pattern = ["chronoguard", "disruptor", "brute"]
	elif local_area <= 6:
		pattern = ["phase_stalker", "echo_revenant", "void_bastion"]
	elif local_area <= 9:
		pattern = ["rift_predator", "entropy_colossus", "rift_predator"]
	else:
		pattern = ["omega_seraph", "grave_architect", "omega_seraph"]
	var count: int = pattern.size()
	if infinite and step_index >= 28:
		count = 4 + floori(float(step_index - 28) / 7.0)
	var enemies: Array[String] = []
	for index: int in count:
		var id: String = pattern[index % pattern.size()]
		enemies.append(InfiniteEnemyCatalog.resolve(id, 1 + floori(float(step_index) / 28.0)) if infinite else id)
	return enemies


static func queue(node: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var key: String = "hazard_queue" if node.get("type", "") == "hazard" else "encounter_queue"
	for id: Variant in node.get(key, []):
		result.append(String(id))
	if result.is_empty() and node.get("type", "") in ["normal_battle", "elite_battle", "boss"]:
		var enemy_id: String = String(node.get("enemy_id", ""))
		if enemy_id != "": result.append(enemy_id)
	return result


static func cleared_key(node: Dictionary) -> String:
	return "hazard_cleared_waves" if node.get("type", "") == "hazard" else "encounters_cleared"


static func cleared(node: Dictionary) -> int:
	return clampi(int(node.get(cleared_key(node), 0)), 0, queue(node).size())


static func next_enemy(node: Dictionary) -> String:
	var enemies: Array[String] = queue(node)
	var index: int = cleared(node)
	return enemies[index] if index < enemies.size() else ""


static func has_next(node: Dictionary) -> bool:
	return next_enemy(node) != ""


static func score_wave(node: Dictionary) -> int:
	# Keep legacy single-fight score keys stable while giving each chained fight its own key.
	return cleared(node) + 1 if node.get("type", "") == "hazard" or queue(node).size() > 1 else 0
