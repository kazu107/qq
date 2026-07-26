extends RefCounted
class_name ArenaService

const INITIAL_GOLD: int = 70
const INITIAL_MAX_HP: int = 60
const TARGET_WINS: int = 12
const MAX_LOSSES: int = 3
const CARD_OFFER_COUNT: int = 3
const RELIC_OFFER_COUNT: int = 2
const SHOP_OFFER_COUNT: int = CARD_OFFER_COUNT + RELIC_OFFER_COUNT
const REROLL_COST: int = 8
const SPECIAL_REWARD_INTERVAL: int = 3
const SPECIAL_REWARD_OPTION_COUNT: int = 3
const STACKING_DISCOUNT_MULTIPLIER: float = 0.9
const MATCH_GOLD_BASE: int = 50
const MATCH_GOLD_PER_TIER: int = 5
const MATCH_GOLD_PER_ROUND: int = 2

var _shop_service: ShopService = ShopService.new()
var _forge_service: ForgeService = ForgeService.new()


func configure_run(
	run_state: RunState,
	allowed_card_ids: Array[String],
	allowed_relic_ids: Array[String],
	rules: Dictionary = {}
) -> void:
	if run_state == null:
		return
	run_state.arena_initial_gold = maxi(0, int(rules.get("initial_gold", INITIAL_GOLD)))
	run_state.arena_match_gold = maxi(0, int(rules.get("match_gold", MATCH_GOLD_BASE)))
	run_state.arena_initial_max_hp = maxi(1, int(rules.get("initial_max_hp", run_state.max_hp)))
	run_state.arena_special_reward_interval = maxi(1, int(rules.get("special_reward_interval", SPECIAL_REWARD_INTERVAL)))
	run_state.arena_shop_price_percent = clampi(int(rules.get("shop_price_percent", 100)), 1, 500)
	run_state.arena_reroll_cost = maxi(0, int(rules.get("reroll_cost", REROLL_COST)))
	run_state.arena_shop_offer_count = clampi(int(rules.get("shop_offer_count", SHOP_OFFER_COUNT)), 2, 12)
	run_state.arena_mode = true
	run_state.infinite_mode = false
	run_state.current_area = 1
	run_state.max_hp = run_state.arena_initial_max_hp
	run_state.player_hp = run_state.max_hp
	run_state.gold = run_state.arena_initial_gold
	run_state.arena_round = 1
	run_state.arena_wins = 0
	run_state.arena_losses = 0
	run_state.arena_target_wins = maxi(1, int(rules.get("target_wins", TARGET_WINS)))
	run_state.arena_max_losses = maxi(1, int(rules.get("max_losses", MAX_LOSSES)))
	run_state.arena_next_enemy_id = _pick_enemy_for_round(run_state)
	run_state.arena_shop = {}
	run_state.arena_pending_rewards = []
	run_state.arena_pending_special_rewards = []
	run_state.arena_shop_discount_stacks = 0
	run_state.arena_timing_discount_stacks = 0
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
		"reroll_cost": run_state.arena_reroll_cost,
		"can_reroll": run_state.gold >= run_state.arena_reroll_cost,
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
	if not run_state.arena_pending_rewards.is_empty():
		return _to_dictionary_array(run_state.arena_pending_rewards)
	return _to_dictionary_array(run_state.arena_pending_special_rewards)


func has_pending_reward(run_state: RunState) -> bool:
	return run_state != null and (
		not run_state.arena_pending_rewards.is_empty()
		or not run_state.arena_pending_special_rewards.is_empty()
	)


func can_reroll(run_state: RunState) -> bool:
	return run_state != null and run_state.gold >= run_state.arena_reroll_cost


func reroll_shop(run_state: RunState, allowed_card_ids: Array[String], allowed_relic_ids: Array[String]) -> bool:
	if not can_reroll(run_state):
		return false
	run_state.gold = max(0, run_state.gold - run_state.arena_reroll_cost)
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
	var relic_offer_count: int = maxi(1, floori(float(run_state.arena_shop_offer_count) * 0.4))
	var card_offer_count: int = maxi(1, run_state.arena_shop_offer_count - relic_offer_count)
	_fill_card_offers(run_state, card_offers, card_offer_count, allowed_card_ids, rng, refresh_count)
	_fill_relic_offers(run_state, relic_offers, relic_offer_count, allowed_relic_ids, rng, refresh_count)
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


func apply_battle_result(
	run_state: RunState,
	summary: Dictionary,
	allowed_card_ids: Array[String],
	allowed_relic_ids: Array[String],
	generate_special_reward: bool = true
) -> Dictionary:
	var result: Dictionary = {
		"finished": false,
		"won": false,
		"reward_gold": 0,
		"reward_heal": 0,
		"next_enemy_id": "",
		"special_reward_due": false,
	}
	if run_state == null:
		return result

	var winner: String = String(summary.get("winner", ""))
	var reward_round: int = maxi(1, run_state.arena_round)
	var reward_tier: int = 1 + int(floor(float(reward_round) / 3.0))
	var reward_gold: int = (
		run_state.arena_match_gold
		+ reward_tier * MATCH_GOLD_PER_TIER
		+ reward_round * MATCH_GOLD_PER_ROUND
		+ maxi(0, int(summary.get("relic_bonus_gold", 0)))
	)
	run_state.gold += reward_gold
	result["reward_gold"] = reward_gold
	if winner == "player":
		run_state.arena_wins += 1
		run_state.encounters_cleared += 1
		run_state.current_area = 1 + int(floor(float(run_state.arena_wins) / 3.0))
		var reward_heal: int = 5 + run_state.current_area
		run_state.player_hp = min(run_state.max_hp, run_state.player_hp + reward_heal)
		result["won"] = true
		result["reward_heal"] = reward_heal
		run_state.arena_pending_rewards = build_victory_rewards(run_state, allowed_card_ids, allowed_relic_ids)
	else:
		run_state.arena_losses += 1
		run_state.relic_state["arena_lost_last_battle"] = true
		run_state.player_hp = run_state.max_hp
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

	if generate_special_reward and run_state.arena_round % run_state.arena_special_reward_interval == 0:
		run_state.arena_pending_special_rewards = build_special_rewards(run_state, run_state.arena_round)
		result["special_reward_due"] = not run_state.arena_pending_special_rewards.is_empty()

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


func build_special_rewards(run_state: RunState, completed_round: int, seed_override: int = 0) -> Array[Dictionary]:
	var rewards: Array[Dictionary] = []
	if run_state == null or completed_round <= 0:
		return rewards

	var reward_stage: int = maxi(1, int(completed_round / run_state.arena_special_reward_interval))
	var max_hp_amount: int = 6 + reward_stage * 2
	var seed_value: int = seed_override
	if seed_value == 0:
		seed_value = int(run_state.seed + completed_round * 6421 + reward_stage * 1879)
	var legendary_card_id: String = _pick_legendary_card(seed_value + 97)
	var candidates: Array[Dictionary] = [
		{
			"id": "arena_special_loadout_r%d" % completed_round,
			"kind": "special_loadout_limit",
			"special": true,
			"visual_icon": "card_equipped",
			"label": Localization.get_text("arena.special.loadout.label", "Loadout Limit +1"),
			"description": Localization.get_text("arena.special.loadout.description", "Permanently increase loadout capacity by 1 for this Arena run."),
		},
		{
			"id": "arena_special_max_hp_r%d" % completed_round,
			"kind": "special_max_hp",
			"special": true,
			"visual_icon": "hp",
			"amount": max_hp_amount,
			"label": Localization.get_textf("arena.special.max_hp.label", "Max HP +{amount}", {"amount": max_hp_amount}),
			"description": Localization.get_text("arena.special.max_hp.description", "Increase maximum and current HP. Later rewards grant more HP."),
		},
		{
			"id": "arena_special_shop_discount_r%d" % completed_round,
			"kind": "special_shop_discount",
			"special": true,
			"visual_icon": "gold",
			"label": Localization.get_text("arena.special.shop_discount.label", "Shop Prices -10%"),
			"description": Localization.get_text("arena.special.shop_discount.description", "Permanently reduce Arena shop item prices by 10%. Stacks multiplicatively."),
		},
		{
			"id": "arena_special_timing_discount_r%d" % completed_round,
			"kind": "special_timing_discount",
			"special": true,
			"visual_icon": "speed",
			"label": Localization.get_text("arena.special.timing_discount.label", "All Card Times -10%"),
			"description": Localization.get_text("arena.special.timing_discount.description", "Permanently shorten cast and recast times of every card by 10%. Stacks multiplicatively."),
		},
		{
			"id": "arena_special_remove_loss_r%d" % completed_round,
			"kind": "special_remove_loss",
			"special": true,
			"visual_icon": "shield",
			"label": Localization.get_text("arena.special.remove_loss.label", "Remove 1 Loss"),
			"description": Localization.get_text("arena.special.remove_loss.description", "Reduce the current Arena loss count by 1, to a minimum of 0."),
		},
		{
			"id": "arena_special_upgrade_two_r%d" % completed_round,
			"kind": "special_upgrade_two",
			"special": true,
			"visual_icon": "card_owned",
			"apply_seed": seed_value + 211,
			"label": Localization.get_text("arena.special.upgrade_two.label", "Upgrade 2 Random Cards"),
			"description": Localization.get_text("arena.special.upgrade_two.description", "Increase the Grade of up to 2 random owned cards by 1."),
		},
	]
	if legendary_card_id != "":
		var legendary_def: CardDef = Database.get_card(legendary_card_id)
		if legendary_def != null:
			candidates.append({
				"id": "arena_special_legendary_r%d" % completed_round,
				"kind": "special_legendary_card",
				"special": true,
				"card_id": legendary_card_id,
				"label": legendary_def.name,
				"description": Localization.get_text("arena.special.legendary.description", "Gain this Legendary card."),
			})

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	while rewards.size() < SPECIAL_REWARD_OPTION_COUNT and not candidates.is_empty():
		var pick_index: int = rng.randi_range(0, candidates.size() - 1)
		rewards.append(candidates[pick_index].duplicate(true))
		candidates.remove_at(pick_index)
	return rewards


func apply_pending_reward(run_state: RunState, reward_id: String, relic_service: RelicService) -> Dictionary:
	var result: Dictionary = {
		"applied": false,
	}
	if run_state == null or reward_id == "":
		return result
	var is_special_reward: bool = run_state.arena_pending_rewards.is_empty()
	var rewards: Array[Dictionary] = _to_dictionary_array(
		run_state.arena_pending_special_rewards if is_special_reward else run_state.arena_pending_rewards
	)
	var selected_reward: Dictionary = {}
	for reward_data in rewards:
		if String(reward_data.get("id", "")) == reward_id:
			selected_reward = reward_data
			break
	if selected_reward.is_empty():
		return result

	var reward_kind: String = String(selected_reward.get("kind", ""))
	if is_special_reward:
		if not _apply_special_reward(run_state, selected_reward, result):
			return result
		run_state.arena_pending_special_rewards = []
		result["applied"] = true
		result["kind"] = reward_kind
		result["special"] = true
		return result

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


func assign_special_rewards(run_state: RunState, rewards: Array[Dictionary]) -> void:
	if run_state == null:
		return
	run_state.arena_pending_special_rewards = _to_dictionary_array(rewards)


func _apply_special_reward(run_state: RunState, reward_data: Dictionary, result: Dictionary) -> bool:
	var reward_kind: String = String(reward_data.get("kind", ""))
	match reward_kind:
		"special_loadout_limit":
			run_state.loadout_limit += 1
			result["loadout_limit_delta"] = 1
		"special_max_hp":
			var hp_amount: int = maxi(1, int(reward_data.get("amount", 1)))
			run_state.max_hp += hp_amount
			run_state.player_hp += hp_amount
			result["max_hp_delta"] = hp_amount
		"special_shop_discount":
			run_state.arena_shop_discount_stacks += 1
			_discount_current_shop(run_state)
			result["shop_discount_stacks"] = run_state.arena_shop_discount_stacks
		"special_timing_discount":
			run_state.arena_timing_discount_stacks += 1
			result["timing_discount_stacks"] = run_state.arena_timing_discount_stacks
		"special_remove_loss":
			var losses_before: int = run_state.arena_losses
			run_state.arena_losses = maxi(0, run_state.arena_losses - 1)
			result["losses_removed"] = losses_before - run_state.arena_losses
		"special_upgrade_two":
			var upgraded_ids: Array[String] = _upgrade_random_cards(
				run_state,
				2,
				int(reward_data.get("apply_seed", run_state.seed)) + run_state.seed
			)
			result["upgraded_card_ids"] = upgraded_ids
		"special_legendary_card":
			var card_id: String = String(reward_data.get("card_id", ""))
			var card_def: CardDef = Database.get_card(card_id)
			if card_def == null or card_def.rarity != "legendary":
				return false
			run_state.player_cards.append(card_id)
			result["selected_reward_card_id"] = card_id
		_:
			return false
	return true


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
			"price": _get_card_price(card_id, run_state),
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
			"price": _get_relic_price(relic_id, run_state),
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
	var candidates: Array[String] = _get_upgrade_candidates(run_state)
	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _get_upgrade_candidates(run_state: RunState) -> Array[String]:
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
	return candidates


func _upgrade_random_cards(run_state: RunState, count: int, seed_value: int) -> Array[String]:
	var upgraded_ids: Array[String] = []
	var candidates: Array[String] = _get_upgrade_candidates(run_state)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	while upgraded_ids.size() < count and not candidates.is_empty():
		var pick_index: int = rng.randi_range(0, candidates.size() - 1)
		var card_id: String = candidates[pick_index]
		candidates.remove_at(pick_index)
		var tier_before: int = CardUpgradeResolver.get_tier(run_state, card_id)
		var tier_after: int = _forge_service.upgrade_card(run_state, card_id)
		if tier_after > tier_before:
			upgraded_ids.append(card_id)
	return upgraded_ids


func _pick_legendary_card(seed_value: int) -> String:
	var legendary_ids: Array[String] = Database.get_card_ids_by_rarity("legendary")
	if legendary_ids.is_empty():
		return ""
	legendary_ids.sort()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return legendary_ids[rng.randi_range(0, legendary_ids.size() - 1)]


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


func _get_card_price(card_id: String, run_state: RunState) -> int:
	var base_price: int = _shop_service.get_price(card_id) + run_state.arena_wins * 2
	var configured_price: int = _apply_shop_price_percent(base_price, run_state.arena_shop_price_percent)
	return _apply_shop_discount(configured_price, run_state.arena_shop_discount_stacks)


func _get_relic_price(relic_id: String, run_state: RunState) -> int:
	var price: int = 42 + run_state.arena_wins * 3
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
	var configured_price: int = _apply_shop_price_percent(price, run_state.arena_shop_price_percent)
	return _apply_shop_discount(configured_price, run_state.arena_shop_discount_stacks)


func _apply_shop_price_percent(price: int, price_percent: int) -> int:
	return maxi(1, int(round(float(price) * float(price_percent) / 100.0)))


func _apply_shop_discount(price: int, discount_stacks: int) -> int:
	var multiplier: float = pow(STACKING_DISCOUNT_MULTIPLIER, maxi(0, discount_stacks))
	return maxi(1, int(round(float(price) * multiplier)))


func _discount_current_shop(run_state: RunState) -> void:
	var shop_data: Dictionary = run_state.arena_shop.duplicate(true)
	for array_key in ["cards", "relics"]:
		var offers: Array[Dictionary] = _to_dictionary_array(shop_data.get(array_key, []))
		for offer_index in range(offers.size()):
			var offer_data: Dictionary = offers[offer_index]
			if not bool(offer_data.get("bought", false)):
				offer_data["price"] = _apply_shop_discount(int(offer_data.get("price", 1)), 1)
			offers[offer_index] = offer_data
		shop_data[array_key] = offers
	run_state.arena_shop = shop_data


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
