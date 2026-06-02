extends RefCounted
class_name MetaProgressService

const DEFAULT_UNLOCKED_STARTERS := ["balanced"]
const DEFAULT_UNLOCKED_RELICS := ["iron_plating", "reactive_barrier"]
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


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(String(item))
	return result
