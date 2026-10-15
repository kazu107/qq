extends RefCounted
class_name ContentPoolService

const VERSION: int = 1


static func valid_ids(values: Variant, kind: String) -> Array[String]:
	var result: Array[String] = []
	if not values is Array:
		return result
	for value: Variant in values:
		var id: String = String(value)
		var valid: bool = Database.is_collectible_card(id) if kind == "cards" else Database.get_relic(id) != null
		if valid and not result.has(id):
			result.append(id)
	return result


static func build_snapshot(meta_progress: Dictionary, arena: bool = false) -> Dictionary:
	var cards: Array[String] = Database.get_all_card_ids() if arena else valid_ids(meta_progress.get("unlocked_cards", []), "cards")
	var relics: Array[String] = Database.get_all_relic_ids() if arena else valid_ids(meta_progress.get("unlocked_relics", []), "relics")
	var sealed_cards: Array[String] = []
	var sealed_relics: Array[String] = []
	if not arena:
		sealed_cards = valid_ids(meta_progress.get("sealed_cards", []), "cards")
		sealed_relics = valid_ids(meta_progress.get("sealed_relics", []), "relics")
	return {
		"version": VERSION,
		"mode": "arena" if arena else "progression",
		"cards": _without(cards, sealed_cards),
		"relics": _without(relics, sealed_relics),
		"sealed_cards": sealed_cards.duplicate(),
		"sealed_relics": sealed_relics.duplicate(),
	}


static func weighted_cards(rarity_pool: Array, allowed_ids: Variant = null) -> Array[String]:
	# null means unrestricted; an explicit empty array must remain empty.
	var allowed: Array[String] = Database.get_all_card_ids() if allowed_ids == null else valid_ids(allowed_ids, "cards")
	var result: Array[String] = []
	for rarity: Variant in rarity_pool:
		for card_id: String in Database.get_card_ids_by_rarity(String(rarity)):
			if allowed.has(card_id):
				result.append(card_id)
	if result.is_empty():
		result = allowed.duplicate()
	return result


static func available_relics(excluded_ids: Array[String], allowed_ids: Variant = null) -> Array[String]:
	var allowed: Array[String] = Database.get_all_relic_ids() if allowed_ids == null else valid_ids(allowed_ids, "relics")
	return _without(allowed, excluded_ids)


static func _without(ids: Array[String], excluded: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for id: String in ids:
		if not excluded.has(id):
			result.append(id)
	return result
