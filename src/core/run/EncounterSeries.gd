extends RefCounted
class_name EncounterSeries


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
