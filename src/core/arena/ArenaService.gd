extends RefCounted
class_name ArenaService

const INITIAL_GOLD: int = 70
const TARGET_WINS: int = 12
const MAX_LOSSES: int = 3
const CARD_OFFER_COUNT: int = 3
const RELIC_OFFER_COUNT: int = 2
const REROLL_COST: int = 8

var _shop_service: ShopService = ShopService.new()
var _forge_service: ForgeService = ForgeService.new()


func configure_run(run_state: RunState, allowed_card_ids: Array[String], allowed_relic_ids: Array[String]) -> void:
	if run_state == null:
		return
	run_state.arena_mode = true
	run_state.infinite_mode = false
	run_state.current_area = 1
	run_state.gold += INITIAL_GOLD
	run_state.arena_round = 1
	run_state.arena_wins = 0
	run_state.arena_losses = 0
	run_state.arena_target_wins = TARGET_WINS
	run_state.arena_max_losses = MAX_LOSSES
	run_state.arena_next_enemy_id = _pick_enemy_for_round(run_state)
	run_state.arena_shop = {}
	run_state.arena_pending_rewards = []
	run_state.map_state = {
		"arena": true,
		"current_step": 0,
		"active_node_id": "",
		"steps": [],
	}
	refresh_shop(run_state, allowed_card_ids, allowed_relic_ids, false)


func build_status(run_state: RunState) -> Dictionary:
	if run_state == null:
		return {}
	var next_enemy_id: String = resolve_next_enemy_id(run_state)
	var enemy_def: EnemyDef = Database.get_enemy(next_enemy_id)
	var enemy_name: String = next_enemy_id
	if enemy_def != null:
		enemy_name = enemy_def.name
	return {
		"round": run_state.arena_round,
		"wins": run_state.arena_wins,
		"losses": run_state.arena_losses,
		"target_wins": run_state.arena_target_wins,
		"max_losses": run_state.arena_max_losses,
		"next_enemy_id": next_enemy_id,
		"next_enemy_name": enemy_name,
		"reroll_cost": REROLL_COST,
		"can_reroll": run_state.gold >= REROLL_COST,
	}


func resolve_next_enemy_id(run_state: RunState) -> String:
	if run_state == null:
		return ""
	if run_state.arena_next_enemy_id == "":
		run_state.arena_next_enemy_id = _pick_enemy_for_round(run_state)
	return run_state.arena_next_enemy_id


func get_card_offers(run_state: RunState) -> Array[Dictionary]:
	if run_state == null:
		return []
	return _to_dictionary_array(run_state.arena_shop.get("cards", []))


func get_relic_offers(run_state: RunState) -> Array[Dictionary]:
	if run_state == null:
		return []
	return _to_dictionary_array(run_state.arena_shop.get("relics", []))


func get_pending_rewards(run_state: RunState) -> Array[Dictionary]:
	if run_state == null:
		return []
	return _to_dictionary_array(run_state.arena_pending_rewards)


func can_reroll(run_state: RunState) -> bool:
	return run_state != null and run_state.gold >= REROLL_COST


func reroll_shop(run_state: RunState, allowed_card_ids: Array[String], allowed_relic_ids: Array[String]) -> bool:
	if not can_reroll(run_state):
		return false
	run_state.gold = max(0, run_state.gold - REROLL_COST)
	refresh_shop(run_state, allowed_card_ids, allowed_relic_ids, true)
	return true


func refresh_shop(run_state: RunState, allowed_card_ids: Array[String], allowed_relic_ids: Array[String], keep_held: bool) -> void:
	if run_state == null:
		return
	var refresh_count: int = int(run_state.arena_shop.get("refresh_count", 0)) + 1
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(run_state.seed + run_state.arena_round * 1009 + refresh_count * 7919 + run_state.arena_wins * 313)

	var card_offers: Array[Dictionary] = []
	var relic_offers: Array[Dictionary] = []
	if keep_held:
		card_offers = _collect_held_offers(run_state, "cards")
		relic_offers = _collect_held_offers(run_state, "relics")
	_fill_card_offers(run_state, card_offers, CARD_OFFER_COUNT, allowed_card_ids, rng, refresh_count)
	_fill_relic_offers(run_state, relic_offers, RELIC_OFFER_COUNT, allowed_relic_ids, rng, refresh_count)
	run_state.arena_shop = {
		"refresh_count": refresh_count,
		"cards": card_offers,
		"relics": relic_offers,
	}


func buy_card_offer(run_state: RunState, offer_index: int) -> String:
	if run_state == null:
		return ""
	var offers: Array[Dictionary] = get_card_offers(run_state)
	if offer_index < 0 or offer_index >= offers.size():
		return ""
	var offer_data: Dictionary = offers[offer_index]
	if bool(offer_data.get("bought", false)):
		return ""
	var card_id: String = String(offer_data.get("card_id", ""))
	var price: int = int(offer_data.get("price", 0))
	if not _shop_service.buy_card(run_state, card_id, price):
		return ""
	offer_data["bought"] = true
	offer_data["held"] = false
	offers[offer_index] = offer_data
	_set_offer_array(run_state, "cards", offers)
	return card_id


func buy_relic_offer(run_state: RunState, offer_index: int, relic_service: RelicService) -> String:
	if run_state == null or relic_service == null:
		return ""
	var offers: Array[Dictionary] = get_relic_offers(run_state)
	if offer_index < 0 or offer_index >= offers.size():
		return ""
	var offer_data: Dictionary = offers[offer_index]
	if bool(offer_data.get("bought", false)):
		return ""
	var relic_id: String = String(offer_data.get("relic_id", ""))
	if relic_id == "" or run_state.relics.has(relic_id):
		return ""
	var price: int = int(offer_data.get("price", 0))
	if run_state.gold < price:
		return ""
	if not relic_service.grant_relic(run_state, relic_id):
		return ""
	run_state.gold = max(0, run_state.gold - price)
	offer_data["bought"] = true
	offer_data["held"] = false
	offers[offer_index] = offer_data
	_set_offer_array(run_state, "relics", offers)
	return relic_id


func toggle_hold(run_state: RunState, offer_kind: String, offer_index: int) -> bool:
	if run_state == null:
		return false
	var array_key: String = "cards" if offer_kind == "card" else "relics"
	var offers: Array[Dictionary] = _to_dictionary_array(run_state.arena_shop.get(array_key, []))
	if offer_index < 0 or offer_index >= offers.size():
		return false
	var offer_data: Dictionary = offers[offer_index]
	if bool(offer_data.get("bought", false)):
		return false
	offer_data["held"] = not bool(offer_data.get("held", false))
	offers[offer_index] = offer_data
	_set_offer_array(run_state, array_key, offers)
	return true


func start_next_match(run_state: RunState) -> String:
	if run_state == null or run_state.run_complete:
		return ""
	return resolve_next_enemy_id(run_state)


func apply_battle_result(run_state: RunState, summary: Dictionary, allowed_card_ids: Array[String], allowed_relic_ids: Array[String]) -> Dictionary:
	var result: Dictionary = {
		"finished": false,
		"won": false,
		"reward_gold": 0,
		"reward_heal": 0,
		"next_enemy_id": "",
	}
	if run_state == null:
		return result

	var winner: String = String(summary.get("winner", ""))
	if winner == "player":
		run_state.arena_wins += 1
		run_state.encounters_cleared += 1
		run_state.current_area = 1 + int(floor(float(run_state.arena_wins) / 3.0))
		var reward_gold: int = 24 + run_state.current_area * 5 + run_state.arena_wins * 2
		reward_gold += maxi(0, int(summary.get("relic_bonus_gold", 0)))
		var reward_heal: int = 5 + run_state.current_area
		run_state.gold += reward_gold
		run_state.player_hp = min(run_state.max_hp, run_state.player_hp + reward_heal)
		result["won"] = true
		result["reward_gold"] = reward_gold
		result["reward_heal"] = reward_heal
		run_state.arena_pending_rewards = build_victory_rewards(run_state, allowed_card_ids, allowed_relic_ids)
	else:
		run_state.arena_losses += 1
		run_state.relic_state["arena_lost_last_battle"] = true
		run_state.player_hp = max(1, int(ceil(float(run_state.max_hp) * 0.42)))
		run_state.arena_pending_rewards = []
	if winner == "player":
		run_state.relic_state["arena_lost_last_battle"] = false

	if run_state.arena_wins >= run_state.arena_target_wins:
		run_state.run_complete = true
		run_state.defeated = false
		result["finished"] = true
		return result

	if run_state.arena_losses >= run_state.arena_max_losses:
		run_state.run_complete = true
		run_state.defeated = true
		result["finished"] = true
		return result

	run_state.arena_round += 1
	run_state.arena_next_enemy_id = _pick_enemy_for_round(run_state)
	result["next_enemy_id"] = run_state.arena_next_enemy_id
	refresh_shop(run_state, allowed_card_ids, allowed_relic_ids, true)
	return result


func build_victory_rewards(run_state: RunState, allowed_card_ids: Array[String], allowed_relic_ids: Array[String]) -> Array[Dictionary]:
	var rewards: Array[Dictionary] = []
	if run_state == null:
		return rewards
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(run_state.seed + run_state.arena_round * 1543 + run_state.arena_wins * 3571)

	var card_id: String = _pick_reward_card(run_state, allowed_card_ids, rng)
	if card_id != "":
		var card_def: CardDef = Database.get_card(card_id)
		if card_def != null:
			rewards.append({
				"id": "arena_reward_card_%s" % card_id,
				"kind": "card",
				"card_id": card_id,
				"label": card_def.name,
				"description": CardInfoFormatter.build_effect_summary(card_def),
			})

	var gold_amount: int = 22 + run_state.current_area * 6 + run_state.arena_wins * 3
	rewards.append({
		"id": "arena_reward_gold",
		"kind": "gold",
		"amount": gold_amount,
		"label": Localization.get_textf("arena.reward.gold.label", "{amount} Gold", {"amount": gold_amount}),
		"description": Localization.get_text("arena.reward.gold.description", "Gain gold for future arena preparation."),
	})

	var relic_id: String = _pick_reward_relic(run_state, allowed_relic_ids, rng)
	if relic_id != "":
		var relic_def: RelicDef = Database.get_relic(relic_id)
		if relic_def != null:
			rewards.append({
				"id": "arena_reward_relic_%s" % relic_id,
				"kind": "relic",
				"relic_id": relic_id,
				"label": relic_def.name,
				"description": relic_def.description,
			})

	var upgrade_card_id: String = _pick_upgrade_card(run_state, rng)
	if upgrade_card_id != "":
		var current_tier: int = CardUpgradeResolver.get_tier(run_state, upgrade_card_id)
		var next_tier: int = mini(CardUpgradeResolver.MAX_TIER, current_tier + 1)
		var upgraded_card_def: CardDef = CardUpgradeResolver.build_card_at_tier(upgrade_card_id, next_tier)
		if upgraded_card_def != null:
			rewards.append({
				"id": "arena_reward_upgrade_%s" % upgrade_card_id,
				"kind": "upgrade",
				"card_id": upgrade_card_id,
				"next_tier": next_tier,
				"label": Localization.get_textf("arena.reward.upgrade.label", "Upgrade {card_name}", {"card_name": upgraded_card_def.name}),
				"description": CardInfoFormatter.build_effect_summary(upgraded_card_def),
			})
	return rewards


func apply_pending_reward(run_state: RunState, reward_id: String, relic_service: RelicService) -> Dictionary:
	var result: Dictionary = {
		"applied": false,
	}
	if run_state == null or reward_id == "":
		return result
	var rewards: Array[Dictionary] = get_pending_rewards(run_state)
	var selected_reward: Dictionary = {}
	for reward_data in rewards:
		if String(reward_data.get("id", "")) == reward_id:
			selected_reward = reward_data
			break
	if selected_reward.is_empty():
		return result

	var reward_kind: String = String(selected_reward.get("kind", ""))
	match reward_kind:
		"card":
			var card_id: String = String(selected_reward.get("card_id", ""))
			if Database.get_card(card_id) == null:
				return result
			run_state.player_cards.append(card_id)
			result["selected_reward_card_id"] = card_id
		"gold":
			var amount: int = int(selected_reward.get("amount", 0))
			if amount <= 0:
				return result
			run_state.gold += amount
			result["reward_gold"] = amount
		"relic":
			var relic_id: String = String(selected_reward.get("relic_id", ""))
			if relic_service == null or not relic_service.grant_relic(run_state, relic_id):
				return result
			result["bonus_relic_id"] = relic_id
		"upgrade":
			var upgrade_card_id: String = String(selected_reward.get("card_id", ""))
			if not run_state.player_cards.has(upgrade_card_id):
				return result
			var before_tier: int = CardUpgradeResolver.get_tier(run_state, upgrade_card_id)
			if before_tier >= CardUpgradeResolver.MAX_TIER:
				return result
			var next_tier: int = _forge_service.upgrade_card(run_state, upgrade_card_id)
			result["upgraded_card_id"] = upgrade_card_id
			result["upgraded_card_tier"] = next_tier
		_:
			return result

	run_state.arena_pending_rewards = []
	result["applied"] = true
	result["kind"] = reward_kind
	return result


func build_history_node(run_state: RunState) -> Dictionary:
	if run_state == null:
		return {"type": "arena", "area": 1}
	return {
		"type": "arena",
		"area": run_state.current_area,
	}


func _collect_held_offers(run_state: RunState, array_key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for offer_data in _to_dictionary_array(run_state.arena_shop.get(array_key, [])):
		if bool(offer_data.get("bought", false)):
			continue
		if not bool(offer_data.get("held", false)):
			continue
		if run_state.relics.has("carryover_price_tag"):
			var previous_rounds: int = mini(4, int(offer_data.get("held_rounds", 0)))
			var held_rounds: int = mini(4, previous_rounds + 1)
			offer_data["held_rounds"] = held_rounds
			if held_rounds > previous_rounds:
				offer_data["price"] = maxi(0, int(offer_data.get("price", 0)) - 4)
		result.append(offer_data)
	return result


func _fill_card_offers(run_state: RunState, offers: Array[Dictionary], target_count: int, allowed_card_ids: Array[String], rng: RandomNumberGenerator, refresh_count: int) -> void:
	var weighted_pool: Array[String] = _build_card_pool(allowed_card_ids, _get_card_rarity_pool(run_state.arena_wins))
	var seen: Dictionary = {}
	for offer_data in offers:
		seen[String(offer_data.get("card_id", ""))] = true

	while offers.size() < target_count and not weighted_pool.is_empty():
		var pick_index: int = rng.randi_range(0, weighted_pool.size() - 1)
		var card_id: String = weighted_pool[pick_index]
		weighted_pool.remove_at(pick_index)
		if seen.has(card_id):
			continue
		if Database.get_card(card_id) == null:
			continue
		seen[card_id] = true
		offers.append({
			"id": _make_offer_id("card", card_id, run_state, refresh_count, offers.size()),
			"kind": "card",
			"card_id": card_id,
			"price": _get_card_price(card_id, run_state.arena_wins),
			"held": false,
			"bought": false,
		})


func _fill_relic_offers(run_state: RunState, offers: Array[Dictionary], target_count: int, allowed_relic_ids: Array[String], rng: RandomNumberGenerator, refresh_count: int) -> void:
	var pool: Array[String] = _build_relic_pool(run_state, allowed_relic_ids)
	var seen: Dictionary = {}
	for offer_data in offers:
		seen[String(offer_data.get("relic_id", ""))] = true

	while offers.size() < target_count and not pool.is_empty():
		var pick_index: int = rng.randi_range(0, pool.size() - 1)
		var relic_id: String = pool[pick_index]
		pool.remove_at(pick_index)
		if seen.has(relic_id):
			continue
		if Database.get_relic(relic_id) == null:
			continue
		seen[relic_id] = true
		offers.append({
			"id": _make_offer_id("relic", relic_id, run_state, refresh_count, offers.size()),
			"kind": "relic",
			"relic_id": relic_id,
			"price": _get_relic_price(relic_id, run_state.arena_wins),
			"held": false,
			"bought": false,
		})


func _build_card_pool(allowed_card_ids: Array[String], rarity_pool: Array[String]) -> Array[String]:
	var pool: Array[String] = []
	for rarity in rarity_pool:
		var ids: Array[String] = Database.get_card_ids_by_rarity(rarity)
		for card_id in ids:
			if not allowed_card_ids.is_empty() and not allowed_card_ids.has(card_id):
				continue
			pool.append(card_id)
	if pool.is_empty():
		pool = Database.get_all_card_ids() if allowed_card_ids.is_empty() else allowed_card_ids.duplicate()
	return pool


func _pick_reward_card(run_state: RunState, allowed_card_ids: Array[String], rng: RandomNumberGenerator) -> String:
	var pool: Array[String] = _build_card_pool(allowed_card_ids, _get_card_rarity_pool(run_state.arena_wins))
	var preferred_pool: Array[String] = []
	for card_id in pool:
		if not run_state.player_cards.has(card_id) and not preferred_pool.has(card_id):
			preferred_pool.append(card_id)
	if preferred_pool.is_empty():
		preferred_pool = _unique_strings(pool)
	if preferred_pool.is_empty():
		return ""
	return preferred_pool[rng.randi_range(0, preferred_pool.size() - 1)]


func _pick_reward_relic(run_state: RunState, allowed_relic_ids: Array[String], rng: RandomNumberGenerator) -> String:
	var pool: Array[String] = _build_relic_pool(run_state, allowed_relic_ids)
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]


func _pick_upgrade_card(run_state: RunState, rng: RandomNumberGenerator) -> String:
	var candidates: Array[String] = []
	var seen: Dictionary = {}
	for card_id in run_state.player_cards:
		if seen.has(card_id):
			continue
		seen[card_id] = true
		if CardUpgradeResolver.get_tier(run_state, card_id) >= CardUpgradeResolver.MAX_TIER:
			continue
		if Database.get_card(card_id) == null:
			continue
		candidates.append(card_id)
	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _unique_strings(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		if result.has(value):
			continue
		result.append(value)
	return result


func _build_relic_pool(run_state: RunState, allowed_relic_ids: Array[String]) -> Array[String]:
	var pool: Array[String] = []
	for relic_id in Database.get_all_relic_ids():
		if not allowed_relic_ids.is_empty() and not allowed_relic_ids.has(relic_id):
			continue
		if run_state.relics.has(relic_id):
			continue
		pool.append(relic_id)
	if pool.is_empty() and not allowed_relic_ids.is_empty():
		for relic_id in allowed_relic_ids:
			if not run_state.relics.has(relic_id):
				pool.append(relic_id)
	return pool


func _get_card_rarity_pool(wins: int) -> Array[String]:
	if wins < 3:
		return ["common", "common", "common", "rare"]
	if wins < 7:
		return ["common", "rare", "rare", "epic", "epic", "legendary"]
	return ["rare", "rare", "epic", "epic", "epic", "legendary"]


func _get_card_price(card_id: String, wins: int) -> int:
	return _shop_service.get_price(card_id) + wins * 2


func _get_relic_price(relic_id: String, wins: int) -> int:
	var price: int = 42 + wins * 3
	if [
		"omega_crown", "eternity_engine", "paradox_prism",
		"overclock_key", "chrono_metronome", "prism_furnace", "emergency_foam",
	].has(relic_id):
		price += 18
	elif [
		"reactive_barrier", "aegis_matrix", "phase_capacitor", "entropy_battery",
		"signal_lens", "pulse_injector", "rift_compass", "barrier_seed", "stasis_clock",
		"scavenger_contract", "blood_pump", "armor_garden", "bounty_drone",
	].has(relic_id):
		price += 10
	return price


func _pick_enemy_for_round(run_state: RunState) -> String:
	var round_number: int = max(1, run_state.arena_round)
	if round_number % 4 == 0:
		return _pick_boss(round_number)

	var pool: Array[String] = []
	if run_state.arena_wins < 3:
		pool = ["scout", "raider", "brute", "medic_drone"]
	elif run_state.arena_wins < 6:
		pool = ["guardian", "chronoguard", "disruptor", "phase_stalker"]
	elif run_state.arena_wins < 9:
		pool = ["void_bastion", "echo_revenant", "rift_predator"]
	else:
		pool = ["entropy_colossus", "omega_seraph", "grave_architect"]

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(run_state.seed + round_number * 431 + run_state.arena_wins * 977 + run_state.arena_losses * 619)
	return pool[rng.randi_range(0, pool.size() - 1)]


func _pick_boss(round_number: int) -> String:
	if round_number <= 4:
		return "boss_timekeeper"
	if round_number <= 8:
		return "boss_paradox_core"
	return "boss_axiom_breaker"


func _make_offer_id(kind: String, item_id: String, run_state: RunState, refresh_count: int, offer_index: int) -> String:
	return "arena_%s_%s_r%d_s%d_%d" % [kind, item_id, run_state.arena_round, refresh_count, offer_index]


func _set_offer_array(run_state: RunState, array_key: String, offers: Array[Dictionary]) -> void:
	var shop_data: Dictionary = run_state.arena_shop.duplicate(true)
	shop_data[array_key] = offers
	run_state.arena_shop = shop_data


func _to_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in Array(value):
		result.append(Dictionary(item).duplicate(true))
	return result
