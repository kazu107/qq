extends RefCounted
class_name LanArenaCoordinator

const TARGET_WINS: int = ArenaService.TARGET_WINS
const MAX_LOSSES: int = 3

var _arena_service: ArenaService = ArenaService.new()
var _relic_service: RelicService = RelicService.new()
var _shop_service: ShopService = ShopService.new()


func create_run(profile: Dictionary, seed: int) -> RunState:
	var run_state: RunState = LanProtocol.profile_to_run(profile, seed)
	if run_state == null:
		return null
	_arena_service.configure_run(run_state, Database.get_all_card_ids(), Database.get_all_relic_ids())
	run_state.arena_target_wins = TARGET_WINS
	run_state.arena_max_losses = MAX_LOSSES
	run_state.arena_next_enemy_id = ""
	return run_state


func apply_action(run_state: RunState, action: String, payload: Dictionary, developer_enabled: bool = false) -> Dictionary:
	var result: Dictionary = {
		"accepted": false,
		"action": action,
		"gold_delta": 0,
	}
	if run_state == null or run_state.run_complete:
		return result
	if not run_state.arena_pending_rewards.is_empty() and action != "choose_reward":
		return result

	var gold_before: int = run_state.gold
	match action:
		"buy_card":
			var bought_card_id: String = _arena_service.buy_card_offer(run_state, int(payload.get("index", -1)))
			if bought_card_id == "":
				return result
			_auto_equip_card_if_room(run_state, bought_card_id)
			result["card_id"] = bought_card_id
		"buy_relic":
			var bought_relic_id: String = _arena_service.buy_relic_offer(
				run_state,
				int(payload.get("index", -1)),
				_relic_service
			)
			if bought_relic_id == "":
				return result
			result["relic_id"] = bought_relic_id
		"toggle_card_hold":
			if not _arena_service.toggle_hold(run_state, "card", int(payload.get("index", -1))):
				return result
		"toggle_relic_hold":
			if not _arena_service.toggle_hold(run_state, "relic", int(payload.get("index", -1))):
				return result
		"reroll":
			if not _arena_service.reroll_shop(run_state, Database.get_all_card_ids(), Database.get_all_relic_ids()):
				return result
		"equip":
			if not equip_card(run_state, String(payload.get("card_id", ""))):
				return result
		"unequip":
			if not unequip_card(run_state, String(payload.get("card_id", ""))):
				return result
		"sell":
			var sold_card_id: String = String(payload.get("card_id", ""))
			if not sell_card(run_state, sold_card_id):
				return result
			result["card_id"] = sold_card_id
		"choose_reward":
			var reward_result: Dictionary = _arena_service.apply_pending_reward(
				run_state,
				String(payload.get("reward_id", "")),
				_relic_service
			)
			if not bool(reward_result.get("applied", false)):
				return result
			result.merge(reward_result, true)
		"dev_add_gold":
			if not developer_enabled:
				return result
			run_state.gold += maxi(0, int(payload.get("amount", 50)))
		"dev_restore_hp":
			if not developer_enabled:
				return result
			run_state.player_hp = run_state.max_hp
		"dev_grant_relic":
			if not developer_enabled:
				return result
			var relic_id: String = _relic_service.roll_random_relic(run_state.relics, Database.get_all_relic_ids())
			if relic_id == "" or not _relic_service.grant_relic(run_state, relic_id):
				return result
			result["relic_id"] = relic_id
		_:
			return result

	result["accepted"] = true
	result["gold_delta"] = run_state.gold - gold_before
	return result


func apply_battle_result(run_state: RunState, won: bool, hp_after: int) -> Dictionary:
	if run_state == null:
		return {
			"finished": false,
			"won": false,
			"reward_gold": 0,
			"reward_heal": 0,
		}
	run_state.player_hp = clampi(hp_after, 1, run_state.max_hp)
	return _arena_service.apply_battle_result(
		run_state,
		{"winner": "player" if won else "enemy"},
		Database.get_all_card_ids(),
		Database.get_all_relic_ids()
	)


func build_status(
	run_state: RunState,
	opponent_name: String,
	opponent_starter_id: String,
	local_ready: bool,
	opponent_ready: bool
) -> Dictionary:
	if run_state == null:
		return {}
	return {
		"round": run_state.arena_round,
		"wins": run_state.arena_wins,
		"losses": run_state.arena_losses,
		"target_wins": run_state.arena_target_wins,
		"max_losses": run_state.arena_max_losses,
		"next_enemy_id": opponent_starter_id,
		"next_enemy_name": opponent_name,
		"reroll_cost": ArenaService.REROLL_COST,
		"can_reroll": run_state.gold >= ArenaService.REROLL_COST,
		"local_ready": local_ready,
		"opponent_ready": opponent_ready,
	}


func get_loadout_entries(run_state: RunState) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if run_state == null:
		return entries
	var seen: Dictionary = {}
	var current_cost: int = RunState.get_total_loadout_cost(run_state.equipped_cards)
	for card_id in run_state.player_cards:
		if seen.has(card_id):
			continue
		seen[card_id] = true
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null:
			continue
		var owned_count: int = _count_occurrences(run_state.player_cards, card_id)
		var equipped_count: int = _count_occurrences(run_state.equipped_cards, card_id)
		entries.append({
			"card_id": card_id,
			"owned_count": owned_count,
			"equipped_count": equipped_count,
			"loadout_cost": card_def.loadout_cost,
			"can_equip": equipped_count < owned_count and current_cost + card_def.loadout_cost <= run_state.loadout_limit,
			"can_unequip": equipped_count > 0 and run_state.equipped_cards.size() > 1,
			"can_sell": can_sell_card(run_state, card_id),
			"sell_value": get_sell_value(card_id),
		})
	return entries


func equip_card(run_state: RunState, card_id: String) -> bool:
	if run_state == null:
		return false
	if _count_occurrences(run_state.equipped_cards, card_id) >= _count_occurrences(run_state.player_cards, card_id):
		return false
	var card_def: CardDef = Database.get_card(card_id)
	if card_def == null:
		return false
	if RunState.get_total_loadout_cost(run_state.equipped_cards) + card_def.loadout_cost > run_state.loadout_limit:
		return false
	run_state.equipped_cards.append(card_id)
	return true


func unequip_card(run_state: RunState, card_id: String) -> bool:
	if run_state == null or run_state.equipped_cards.size() <= 1:
		return false
	return _remove_occurrence(run_state.equipped_cards, card_id)


func can_sell_card(run_state: RunState, card_id: String) -> bool:
	if run_state == null or Database.get_card(card_id) == null:
		return false
	var owned_count: int = _count_occurrences(run_state.player_cards, card_id)
	if owned_count <= 0 or run_state.player_cards.size() <= 1:
		return false
	var equipped_count: int = _count_occurrences(run_state.equipped_cards, card_id)
	return not (equipped_count >= owned_count and run_state.equipped_cards.size() <= 1)


func sell_card(run_state: RunState, card_id: String) -> bool:
	if not can_sell_card(run_state, card_id):
		return false
	var owned_before: int = _count_occurrences(run_state.player_cards, card_id)
	if not _remove_occurrence(run_state.player_cards, card_id):
		return false
	if _count_occurrences(run_state.equipped_cards, card_id) >= owned_before:
		_remove_occurrence(run_state.equipped_cards, card_id)
	run_state.gold += get_sell_value(card_id)
	return true


func get_sell_value(card_id: String) -> int:
	if Database.get_card(card_id) == null:
		return 0
	return maxi(1, int(floor(float(_shop_service.get_price(card_id)) * 0.5)))


func has_valid_loadout(run_state: RunState) -> bool:
	return run_state != null and not run_state.equipped_cards.is_empty() and RunState.get_total_loadout_cost(run_state.equipped_cards) <= run_state.loadout_limit


func _auto_equip_card_if_room(run_state: RunState, card_id: String) -> void:
	if run_state == null:
		return
	var card_def: CardDef = Database.get_card(card_id)
	if card_def == null:
		return
	if RunState.get_total_loadout_cost(run_state.equipped_cards) + card_def.loadout_cost > run_state.loadout_limit:
		return
	run_state.equipped_cards.append(card_id)


func _count_occurrences(values: Array[String], target: String) -> int:
	var count: int = 0
	for value in values:
		if value == target:
			count += 1
	return count


func _remove_occurrence(values: Array[String], target: String) -> bool:
	for index in range(values.size() - 1, -1, -1):
		if values[index] != target:
			continue
		values.remove_at(index)
		return true
	return false
