extends RefCounted
class_name MetaProgressService

const DEFAULT_UNLOCKED_STARTERS := ["balanced"]
const DEFAULT_UNLOCKED_RELICS := ["iron_plating", "reactive_barrier"]
const DEFAULT_ACHIEVEMENT_STATS := {
	"runs_started": 0,
	"victories": 0,
	"boss_wins": 0,
}
const DEFAULT_PERMANENT_BONUSES := {
	"max_hp": 0,
	"attack": 0,
	"speed": 0,
	"loadout_limit": 0,
}
const STARTER_UNLOCK_COSTS := {
	"tempo": 2,
	"fortress": 2,
}


func ensure_defaults(meta_progress: Dictionary) -> void:
	if not meta_progress.has("points"):
		meta_progress["points"] = 0
	if not meta_progress.has("best_clear"):
		meta_progress["best_clear"] = 0

	var starters: Array[String] = _to_string_array(meta_progress.get("unlocked_starters", []))
	if starters.is_empty():
		meta_progress["unlocked_starters"] = DEFAULT_UNLOCKED_STARTERS.duplicate()

	var cards: Array[String] = _to_string_array(meta_progress.get("unlocked_cards", []))
	if cards.is_empty():
		meta_progress["unlocked_cards"] = get_default_unlocked_card_ids()

	var relics: Array[String] = _to_string_array(meta_progress.get("unlocked_relics", []))
	if relics.is_empty():
		meta_progress["unlocked_relics"] = DEFAULT_UNLOCKED_RELICS.duplicate()

	meta_progress["claimed_achievements"] = _to_string_array(meta_progress.get("claimed_achievements", []))
	meta_progress["achievement_stats"] = _normalized_int_dictionary(
		meta_progress.get("achievement_stats", {}),
		DEFAULT_ACHIEVEMENT_STATS
	)
	meta_progress["permanent_bonuses"] = _normalized_int_dictionary(
		meta_progress.get("permanent_bonuses", {}),
		DEFAULT_PERMANENT_BONUSES
	)


func get_default_unlocked_card_ids() -> Array[String]:
	var unlocked_ids: Array[String] = []
	for card_id in Database.get_all_card_ids():
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null:
			continue
		if card_def.rarity == "common":
			unlocked_ids.append(card_id)
	return unlocked_ids


func get_default_unlocked_relic_ids() -> Array[String]:
	return DEFAULT_UNLOCKED_RELICS.duplicate()


func get_unlocked_starters(meta_progress: Dictionary) -> Array[String]:
	ensure_defaults(meta_progress)
	return _to_string_array(meta_progress.get("unlocked_starters", []))


func get_unlocked_cards(meta_progress: Dictionary) -> Array[String]:
	ensure_defaults(meta_progress)
	return _to_string_array(meta_progress.get("unlocked_cards", []))


func get_unlocked_relics(meta_progress: Dictionary) -> Array[String]:
	ensure_defaults(meta_progress)
	return _to_string_array(meta_progress.get("unlocked_relics", []))


func get_claimed_achievement_ids(meta_progress: Dictionary) -> Array[String]:
	ensure_defaults(meta_progress)
	return _to_string_array(meta_progress.get("claimed_achievements", []))


func get_achievement_stats(meta_progress: Dictionary) -> Dictionary:
	ensure_defaults(meta_progress)
	return Dictionary(meta_progress.get("achievement_stats", {})).duplicate(true)


func get_permanent_bonuses(meta_progress: Dictionary) -> Dictionary:
	ensure_defaults(meta_progress)
	return Dictionary(meta_progress.get("permanent_bonuses", {})).duplicate(true)


func is_starter_unlocked(meta_progress: Dictionary, starter_id: String) -> bool:
	return get_unlocked_starters(meta_progress).has(starter_id)


func is_card_unlocked(meta_progress: Dictionary, card_id: String) -> bool:
	return get_unlocked_cards(meta_progress).has(card_id)


func is_relic_unlocked(meta_progress: Dictionary, relic_id: String) -> bool:
	return get_unlocked_relics(meta_progress).has(relic_id)


func get_starter_unlock_cost(starter_id: String) -> int:
	return int(STARTER_UNLOCK_COSTS.get(starter_id, 0))


func get_card_unlock_cost(card_id: String) -> int:
	var card_def: CardDef = Database.get_card(card_id)
	if card_def == null:
		return 1
	match card_def.rarity:
		"epic":
			return 2
		"rare":
			return 1
		_:
			return 0


func get_relic_unlock_cost(relic_id: String) -> int:
	if DEFAULT_UNLOCKED_RELICS.has(relic_id):
		return 0
	return 1


func unlock_starter(meta_progress: Dictionary, starter_id: String) -> bool:
	if starter_id == "" or is_starter_unlocked(meta_progress, starter_id):
		return false
	var cost: int = get_starter_unlock_cost(starter_id)
	if int(meta_progress.get("points", 0)) < cost:
		return false
	meta_progress["points"] = int(meta_progress.get("points", 0)) - cost
	var unlocked: Array[String] = get_unlocked_starters(meta_progress)
	unlocked.append(starter_id)
	meta_progress["unlocked_starters"] = unlocked
	return true


func unlock_card(meta_progress: Dictionary, card_id: String) -> bool:
	if card_id == "" or is_card_unlocked(meta_progress, card_id):
		return false
	var cost: int = get_card_unlock_cost(card_id)
	if int(meta_progress.get("points", 0)) < cost:
		return false
	meta_progress["points"] = int(meta_progress.get("points", 0)) - cost
	var unlocked: Array[String] = get_unlocked_cards(meta_progress)
	unlocked.append(card_id)
	meta_progress["unlocked_cards"] = unlocked
	return true


func unlock_relic(meta_progress: Dictionary, relic_id: String) -> bool:
	if relic_id == "" or is_relic_unlocked(meta_progress, relic_id):
		return false
	var cost: int = get_relic_unlock_cost(relic_id)
	if int(meta_progress.get("points", 0)) < cost:
		return false
	meta_progress["points"] = int(meta_progress.get("points", 0)) - cost
	var unlocked: Array[String] = get_unlocked_relics(meta_progress)
	unlocked.append(relic_id)
	meta_progress["unlocked_relics"] = unlocked
	return true


func unlock_all(meta_progress: Dictionary) -> void:
	ensure_defaults(meta_progress)
	var all_starters: Array[String] = []
	for starter in Database.starters:
		all_starters.append(String(starter.get("id", "")))
	meta_progress["unlocked_starters"] = all_starters
	meta_progress["unlocked_cards"] = Database.get_all_card_ids()
	meta_progress["unlocked_relics"] = Database.get_all_relic_ids()


func reset(meta_progress: Dictionary, template: Dictionary) -> Dictionary:
	var reset_data: Dictionary = template.duplicate(true)
	ensure_defaults(reset_data)
	return reset_data


func build_starter_entries(meta_progress: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for starter in Database.starters:
		var starter_id: String = String(starter.get("id", ""))
		entries.append({
			"id": starter_id,
			"name": String(starter.get("name", starter_id)),
			"description": String(starter.get("description", "")),
			"cost": get_starter_unlock_cost(starter_id),
			"unlocked": is_starter_unlocked(meta_progress, starter_id),
			"type": "starter",
		})
	return entries


func build_card_entries(meta_progress: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for card_id in Database.get_all_card_ids():
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null:
			continue
		entries.append({
			"id": card_id,
			"name": card_def.name,
			"description": card_def.description,
			"cost": get_card_unlock_cost(card_id),
			"unlocked": is_card_unlocked(meta_progress, card_id),
			"type": "card",
			"rarity": card_def.rarity,
		})
	return entries


func build_relic_entries(meta_progress: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for relic_id in Database.get_all_relic_ids():
		var relic_def: RelicDef = Database.get_relic(relic_id)
		if relic_def == null:
			continue
		entries.append({
			"id": relic_id,
			"name": relic_def.name,
			"description": relic_def.description,
			"cost": get_relic_unlock_cost(relic_id),
			"unlocked": is_relic_unlocked(meta_progress, relic_id),
			"type": "relic",
		})
	return entries


func increment_achievement_stat(meta_progress: Dictionary, stat_id: String, amount: int = 1) -> int:
	ensure_defaults(meta_progress)
	var stats: Dictionary = Dictionary(meta_progress.get("achievement_stats", {})).duplicate(true)
	var next_value: int = int(stats.get(stat_id, 0)) + amount
	stats[stat_id] = next_value
	meta_progress["achievement_stats"] = stats
	return next_value


func is_achievement_claimed(meta_progress: Dictionary, achievement_id: String) -> bool:
	return get_claimed_achievement_ids(meta_progress).has(achievement_id)


func is_achievement_claimable(meta_progress: Dictionary, achievement_id: String) -> bool:
	if is_achievement_claimed(meta_progress, achievement_id):
		return false
	var achievement_data: Dictionary = Database.get_achievement(achievement_id)
	if achievement_data.is_empty():
		return false
	var condition: Dictionary = Dictionary(achievement_data.get("condition", {}))
	var stat_id: String = String(condition.get("stat", ""))
	var target_value: int = int(condition.get("value", 1))
	return _get_condition_value(meta_progress, stat_id) >= target_value


func build_achievement_entries(meta_progress: Dictionary) -> Array[Dictionary]:
	ensure_defaults(meta_progress)
	var entries: Array[Dictionary] = []
	var claimed_ids: Array[String] = get_claimed_achievement_ids(meta_progress)
	for achievement_id in Database.get_all_achievement_ids():
		var achievement_data: Dictionary = Database.get_achievement(achievement_id)
		if achievement_data.is_empty():
			continue
		var condition: Dictionary = Dictionary(achievement_data.get("condition", {}))
		var stat_id: String = String(condition.get("stat", ""))
		var target_value: int = int(condition.get("value", 1))
		var current_value: int = _get_condition_value(meta_progress, stat_id)
		var claimed: bool = claimed_ids.has(achievement_id)
		var rewards: Array = Array(achievement_data.get("rewards", []))
		entries.append({
			"id": achievement_id,
			"name": String(achievement_data.get("name", achievement_id)),
			"description": String(achievement_data.get("description", "")),
			"stat": stat_id,
			"current": current_value,
			"target": target_value,
			"claimed": claimed,
			"claimable": not claimed and current_value >= target_value,
			"reward_text": _build_reward_text(rewards),
		})
	return entries


func claim_achievement(meta_progress: Dictionary, achievement_id: String) -> bool:
	if not is_achievement_claimable(meta_progress, achievement_id):
		return false

	var claimed_ids: Array[String] = get_claimed_achievement_ids(meta_progress)
	claimed_ids.append(achievement_id)
	meta_progress["claimed_achievements"] = claimed_ids

	var achievement_data: Dictionary = Database.get_achievement(achievement_id)
	var rewards: Array = Array(achievement_data.get("rewards", []))
	for raw_reward in rewards:
		_apply_achievement_reward(meta_progress, Dictionary(raw_reward))
	return true


func _get_condition_value(meta_progress: Dictionary, stat_id: String) -> int:
	ensure_defaults(meta_progress)
	match stat_id:
		"best_clear":
			return int(meta_progress.get("best_clear", 0))
		"unlocked_cards":
			return get_unlocked_cards(meta_progress).size()
		"unlocked_relics":
			return get_unlocked_relics(meta_progress).size()
		"unlocked_starters":
			return get_unlocked_starters(meta_progress).size()
		_:
			var stats: Dictionary = Dictionary(meta_progress.get("achievement_stats", {}))
			return int(stats.get(stat_id, 0))


func _apply_achievement_reward(meta_progress: Dictionary, reward_data: Dictionary) -> void:
	var reward_type: String = String(reward_data.get("type", ""))
	match reward_type:
		"permanent_bonus":
			var stat_id: String = String(reward_data.get("stat", ""))
			if stat_id == "":
				return
			var amount: int = int(reward_data.get("amount", 0))
			var bonuses: Dictionary = get_permanent_bonuses(meta_progress)
			bonuses[stat_id] = int(bonuses.get(stat_id, 0)) + amount
			meta_progress["permanent_bonuses"] = bonuses
		"meta_points":
			meta_progress["points"] = int(meta_progress.get("points", 0)) + int(reward_data.get("amount", 0))


func _build_reward_text(rewards: Array) -> String:
	var parts: Array[String] = []
	for raw_reward in rewards:
		var text: String = _reward_text(Dictionary(raw_reward))
		if text != "":
			parts.append(text)
	return ", ".join(parts)


func _reward_text(reward_data: Dictionary) -> String:
	var amount: int = int(reward_data.get("amount", 0))
	match String(reward_data.get("type", "")):
		"permanent_bonus":
			match String(reward_data.get("stat", "")):
				"max_hp":
					return Localization.get_textf("achievement.reward.max_hp", "Permanent HP +{amount}", {"amount": amount})
				"attack":
					return Localization.get_textf("achievement.reward.attack", "Permanent Attack +{amount}", {"amount": amount})
				"speed":
					return Localization.get_textf("achievement.reward.speed", "Permanent Speed +{amount}", {"amount": amount})
				"loadout_limit":
					return Localization.get_textf("achievement.reward.loadout_limit", "Permanent Loadout +{amount}", {"amount": amount})
		"meta_points":
			return Localization.get_textf("achievement.reward.meta_points", "Meta Points +{amount}", {"amount": amount})
	return ""


func _normalized_int_dictionary(value: Variant, defaults: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) == TYPE_DICTIONARY:
		result = Dictionary(value).duplicate(true)
	for raw_key in defaults.keys():
		var key: String = String(raw_key)
		result[key] = int(result.get(key, int(defaults.get(key, 0))))
	return result


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(String(item))
	return result
