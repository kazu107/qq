extends RefCounted
class_name ShopService

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func can_buy(run_state: RunState, price: int) -> bool:
	return run_state.gold >= price


func roll_inventory(count: int, rarity_pool: Array[String], owned_cards: Array[String], allowed_card_ids: Variant = null) -> Array[Dictionary]:
	var weighted_pool: Array[String] = ContentPoolService.weighted_cards(rarity_pool, allowed_card_ids)

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
		"legendary":
			return 82
		_:
			return 18


func buy_card(run_state: RunState, card_id: String, price: int) -> bool:
	if not can_buy(run_state, price):
		return false
	run_state.gold -= price
	run_state.player_cards.append(card_id)
	return true
