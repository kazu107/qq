extends RefCounted
class_name ShopService

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func can_buy(run_state: RunState, price: int) -> bool:
	return run_state.gold >= price


func roll_inventory(count: int, rarity_pool: Array[String], owned_cards: Array[String], allowed_card_ids: Array[String] = []) -> Array[Dictionary]:
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

	var offers: Array[Dictionary] = []
	var seen: Dictionary = {}
	while offers.size() < count and not weighted_pool.is_empty():
		var candidate_index: int = _rng.randi_range(0, weighted_pool.size() - 1)
		var candidate_id: String = weighted_pool[candidate_index]
		weighted_pool.remove_at(candidate_index)
		if seen.has(candidate_id):
			continue
		if owned_cards.has(candidate_id) and weighted_pool.size() > count:
			continue
		seen[candidate_id] = true
		offers.append({
			"card_id": candidate_id,
			"price": get_price(candidate_id),
			"bought": false,
		})
	return offers


func get_price(card_id: String) -> int:
	var card_def: CardDef = Database.get_card(card_id)
	if card_def == null:
		return 20
	match card_def.rarity:
		"rare":
			return 32
		"epic":
			return 54
		_:
			return 18


func buy_card(run_state: RunState, card_id: String, price: int) -> bool:
	if not can_buy(run_state, price):
		return false
	run_state.gold -= price
	run_state.player_cards.append(card_id)
	return true
