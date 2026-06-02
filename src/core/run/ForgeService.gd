extends RefCounted
class_name ForgeService

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func roll_candidates(run_state: RunState, count: int) -> Array[String]:
	var unique_cards: Array[String] = get_upgradable_cards(run_state)
	if unique_cards.is_empty():
		return []
	unique_cards.shuffle()
	return unique_cards.slice(0, min(count, unique_cards.size()))


func get_upgradable_cards(run_state: RunState) -> Array[String]:
	var candidates: Array[String] = []
	var seen: Dictionary = {}
	for card_id in run_state.player_cards:
		if seen.has(card_id):
			continue
		seen[card_id] = true
		if int(run_state.card_upgrades.get(card_id, 0)) >= 3:
			continue
		candidates.append(card_id)
	return candidates


func upgrade_card(run_state: RunState, card_id: String) -> int:
	var current_tier := int(run_state.card_upgrades.get(card_id, 0))
	if current_tier >= 3:
		return current_tier
	current_tier += 1
	run_state.card_upgrades[card_id] = current_tier
	return current_tier
