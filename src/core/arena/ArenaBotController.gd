extends RefCounted
class_name ArenaBotController

const MAX_PURCHASES: int = 4


func prepare(coordinator: LanArenaCoordinator, run: RunState) -> Dictionary:
	var result: Dictionary = {"purchases": 0, "rewards": 0}
	if run == null or run.run_complete:
		return result
	# Ordinary and shared special rewards are separate queues.
	for _queue: int in 2:
		var rewards: Array[Dictionary] = coordinator.get_pending_rewards(run)
		if rewards.is_empty():
			break
		var best: Dictionary = rewards[0]
		for reward: Dictionary in rewards:
			if _reward_score(run, reward) > _reward_score(run, best):
				best = reward
		if bool(coordinator.apply_action(run, "choose_reward", {"reward_id": best.get("id", "")}).get("accepted", false)):
			result["rewards"] = int(result["rewards"]) + 1
	if coordinator.has_pending_reward(run):
		return result
	var shop: ArenaService = ArenaService.new()
	# Spend real gold only; no reroll loops, hidden bonuses or developer actions.
	for _purchase: int in MAX_PURCHASES:
		var action: String = ""
		var index: int = -1
		var score: float = -INF
		var cards: Array[Dictionary] = shop.get_card_offers(run)
		for item: int in cards.size():
			var offer: Dictionary = cards[item]
			var card_id: String = String(offer.get("card_id", ""))
			var card: CardDef = Database.get_card(card_id)
			if bool(offer.get("bought", false)) or int(offer.get("price", 0)) > run.gold or card == null:
				continue
			if card.loadout_cost > run.loadout_limit:
				continue
			var value: float = _card_score(card) / maxf(1.0, float(offer.get("price", 1)))
			if run.player_cards.has(card_id):
				value *= 0.5
			if value > score:
				score = value
				action = "buy_card"
				index = item
		var relics: Array[Dictionary] = shop.get_relic_offers(run)
		for item: int in relics.size():
			var offer: Dictionary = relics[item]
			var relic_id: String = String(offer.get("relic_id", ""))
			if bool(offer.get("bought", false)) or run.relics.has(relic_id) or int(offer.get("price", 0)) > run.gold:
				continue
			var value: float = 12.0 / maxf(1.0, float(offer.get("price", 1)))
			if value > score:
				score = value
				action = "buy_relic"
				index = item
		if action == "" or not bool(coordinator.apply_action(run, action, {"index": index}).get("accepted", false)):
			break
		result["purchases"] = int(result["purchases"]) + 1
	_rebuild_loadout(coordinator, run)
	return result


func _rebuild_loadout(coordinator: LanArenaCoordinator, run: RunState) -> void:
	var previous: Array[String] = run.equipped_cards.duplicate()
	var candidates: Array[String] = run.player_cards.duplicate()
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var first: CardDef = Database.get_card(a)
		var second: CardDef = Database.get_card(b)
		var difference: float = _card_score(first) - _card_score(second)
		return a < b if is_zero_approx(difference) else difference > 0.0
	)
	# Reserve one attack, then fill by value instead of making every deck all-out attack.
	for card_id: String in candidates:
		if _has_damage(Database.get_card(card_id)):
			candidates.erase(card_id)
			candidates.push_front(card_id)
			break
	run.equipped_cards.clear()
	for card_id: String in candidates:
		coordinator.equip_card(run, card_id)
	if not coordinator.has_valid_loadout(run):
		run.equipped_cards = previous


func _has_damage(card: CardDef) -> bool:
	if card == null:
		return false
	for effect: Dictionary in card.effects:
		if String(effect.get("type", "")) == "deal_damage":
			return true
	return false


func _card_score(card: CardDef) -> float:
	if card == null:
		return 0.0
	var score: float = 4.0
	for effect: Dictionary in card.effects:
		match String(effect.get("type", "")):
			"deal_damage": score += float(effect.get("amount", 0))
			"gain_shield", "heal": score += float(effect.get("amount", 0)) * 0.65
			"apply_status", "interrupt_card", "auto_queue_card", "empower_card", "repeat_next_card": score += 7.0
			"delay_enemy_active_card", "timeline_stop", "timeline_reverse": score += 5.0
	return maxf(1.0, score) / maxf(1.0, float(card.loadout_cost)) / (1.0 + card.cast_time * 0.08 + card.recast_time * 0.04)


func _reward_score(run: RunState, reward: Dictionary) -> float:
	match String(reward.get("kind", "")):
		"special_timing_discount": return 40.0
		"special_loadout_limit": return 35.0
		"special_legendary_card", "special_upgrade_two": return 30.0
		"special_max_hp": return 26.0
		"special_shop_discount": return 24.0
		"special_remove_loss": return 20.0 if run.arena_losses > 0 else 0.0
		"relic": return 25.0
		"upgrade": return 22.0
		"card": return _card_score(Database.get_card(String(reward.get("card_id", "")))) + 12.0
		"gold": return 15.0
	return 1.0
