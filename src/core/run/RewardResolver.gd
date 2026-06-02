extends RefCounted
class_name RewardResolver

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func build_reward_bundle(reward_key: String, reward_table: Dictionary, area: int, owned_cards: Array[String], allowed_card_ids: Array[String] = []) -> Dictionary:
	var resolved_area: int = max(1, area)
	var rarity_pool: Array[String] = _resolve_rarity_pool(reward_table, resolved_area)
	var option_count: int = int(reward_table.get("option_count", 3))
	var guarantee_new: bool = bool(reward_table.get("guarantee_new", true))
	var package: Dictionary = {
		"reward_key": reward_key,
		"area": resolved_area,
		"gold": int(reward_table.get("gold", 0)) + int(reward_table.get("gold_per_area", 0)) * max(0, resolved_area - 1),
		"heal": int(reward_table.get("heal", 0)) + int(reward_table.get("heal_per_area", 0)) * max(0, resolved_area - 1),
		"option_count": option_count,
		"rarity_pool": rarity_pool,
		"guarantee_new": guarantee_new,
	}
	package["options"] = roll_card_rewards(
		option_count,
		rarity_pool,
		owned_cards,
		allowed_card_ids,
		guarantee_new
	)
	return package


func roll_card_rewards(count: int, rarity_pool: Array, owned_cards: Array[String], allowed_card_ids: Array[String] = [], guarantee_new: bool = false) -> Array[String]:
	var weighted_pool: Array[String] = []
	for rarity in rarity_pool:
		for card_id in Database.get_card_ids_by_rarity(rarity):
			if not allowed_card_ids.is_empty() and not allowed_card_ids.has(card_id):
				continue
			weighted_pool.append(card_id)
	if weighted_pool.is_empty():
		if allowed_card_ids.is_empty():
			weighted_pool = Database.get_all_card_ids()
		else:
			weighted_pool = allowed_card_ids.duplicate()

	var options: Array[String] = []
	if guarantee_new and count > 0:
		var new_pool: Array[String] = []
		for candidate in weighted_pool:
			if not owned_cards.has(candidate) and not new_pool.has(candidate):
				new_pool.append(candidate)
		if not new_pool.is_empty():
			var guaranteed_id: String = new_pool[_rng.randi_range(0, new_pool.size() - 1)]
			options.append(guaranteed_id)
			_remove_all_from_pool(weighted_pool, guaranteed_id)

	while options.size() < count and not weighted_pool.is_empty():
		var candidate: String = _pick_reward_candidate(weighted_pool, owned_cards)
		if options.has(candidate):
			_remove_all_from_pool(weighted_pool, candidate)
			continue
		options.append(candidate)
		_remove_all_from_pool(weighted_pool, candidate)
	return options


func _pick_reward_candidate(weighted_pool: Array[String], owned_cards: Array[String]) -> String:
	var new_candidates: Array[String] = []
	var owned_candidates: Array[String] = []
	for candidate in weighted_pool:
		if owned_cards.has(candidate):
			owned_candidates.append(candidate)
		else:
			new_candidates.append(candidate)

	if not new_candidates.is_empty():
		return new_candidates[_rng.randi_range(0, new_candidates.size() - 1)]
	return owned_candidates[_rng.randi_range(0, owned_candidates.size() - 1)]


func _resolve_rarity_pool(reward_table: Dictionary, area: int) -> Array[String]:
	var rarity_pool_by_area: Dictionary = Dictionary(reward_table.get("rarity_pool_by_area", {}))
	var area_key: String = str(area)
	if rarity_pool_by_area.has(area_key):
		return _to_string_array(rarity_pool_by_area[area_key])
	return _to_string_array(reward_table.get("rarity_pool", []))


func _remove_all_from_pool(weighted_pool: Array[String], card_id: String) -> void:
	for index in range(weighted_pool.size() - 1, -1, -1):
		if String(weighted_pool[index]) == card_id:
			weighted_pool.remove_at(index)


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(String(item))
	return result
