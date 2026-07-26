extends RefCounted
class_name RunState

var starter_id: String = ""
var seed: int = 0
var current_area: int = 1
var player_hp: int = 1
var max_hp: int = 1
var attack: int = 0
var speed: int = 0
var map_state: Dictionary = {}
var player_cards: Array[String] = []
var equipped_cards: Array[String] = []
var loadout_limit: int = 10
var card_upgrades: Dictionary = {}
var temporary_card_modifiers: Dictionary = {}
var relics: Array[String] = []
var relic_state: Dictionary = {}
var gold: int = 0
var encounters_cleared: int = 0
var battle_history: Array[Dictionary] = []
var hp_damage_taken: int = 0
var run_complete: bool = false
var defeated: bool = false
var infinite_mode: bool = false
var arena_mode: bool = false
var arena_round: int = 1
var arena_wins: int = 0
var arena_losses: int = 0
var arena_target_wins: int = 12
var arena_max_losses: int = 3
var arena_next_enemy_id: String = ""
var arena_shop: Dictionary = {}
var arena_pending_rewards: Array[Dictionary] = []
var arena_pending_special_rewards: Array[Dictionary] = []
var arena_shop_discount_stacks: int = 0
var arena_timing_discount_stacks: int = 0
var arena_initial_gold: int = 70
var arena_match_gold: int = 50
var arena_initial_max_hp: int = 0
var arena_special_reward_interval: int = 3
var arena_shop_price_percent: int = 100
var arena_reroll_cost: int = 8
var arena_shop_offer_count: int = 5


static func from_starter(starter_data: Dictionary, seed_override: int = 0) -> RunState:
	var run_state := RunState.new()
	run_state.starter_id = String(starter_data.get("id", ""))
	if seed_override > 0:
		run_state.seed = seed_override
	else:
		run_state.seed = Time.get_unix_time_from_system()
	run_state.current_area = 1
	run_state.max_hp = int(starter_data.get("max_hp", 1))
	run_state.player_hp = run_state.max_hp
	run_state.attack = int(starter_data.get("attack", 0))
	run_state.speed = int(starter_data.get("speed", 0))
	run_state.map_state = {}
	run_state.player_cards = _to_string_array(starter_data.get("cards", []))
	run_state.loadout_limit = max(10, get_total_loadout_cost(run_state.player_cards))
	run_state.equipped_cards = build_default_equipped_cards(run_state.player_cards, run_state.loadout_limit)
	run_state.card_upgrades = {}
	run_state.temporary_card_modifiers = {}
	run_state.relics = []
	run_state.relic_state = {}
	run_state.gold = 0
	run_state.battle_history = []
	run_state.hp_damage_taken = 0
	run_state.infinite_mode = false
	run_state.arena_mode = false
	run_state.arena_round = 1
	run_state.arena_wins = 0
	run_state.arena_losses = 0
	run_state.arena_target_wins = 12
	run_state.arena_max_losses = 3
	run_state.arena_next_enemy_id = ""
	run_state.arena_shop = {}
	run_state.arena_pending_rewards = []
	run_state.arena_pending_special_rewards = []
	run_state.arena_shop_discount_stacks = 0
	run_state.arena_timing_discount_stacks = 0
	run_state.arena_initial_gold = 70
	run_state.arena_match_gold = 50
	run_state.arena_initial_max_hp = run_state.max_hp
	run_state.arena_special_reward_interval = 3
	run_state.arena_shop_price_percent = 100
	run_state.arena_reroll_cost = 8
	run_state.arena_shop_offer_count = 5
	return run_state


static func from_dict(data: Dictionary) -> RunState:
	var run_state := RunState.new()
	run_state.starter_id = String(data.get("starter_id", ""))
	run_state.seed = int(data.get("seed", 0))
	run_state.current_area = int(data.get("current_area", 1))
	run_state.player_hp = int(data.get("player_hp", 1))
	run_state.max_hp = int(data.get("max_hp", 1))
	run_state.attack = int(data.get("attack", 0))
	run_state.speed = int(data.get("speed", 0))
	run_state.map_state = Dictionary(data.get("map_state", {}))
	run_state.player_cards = _to_string_array(data.get("player_cards", []))
	run_state.loadout_limit = int(data.get("loadout_limit", 10))
	run_state.equipped_cards = _to_string_array(data.get("equipped_cards", []))
	if run_state.equipped_cards.is_empty():
		run_state.equipped_cards = build_default_equipped_cards(run_state.player_cards, run_state.loadout_limit)
	run_state.card_upgrades = Dictionary(data.get("card_upgrades", {}))
	run_state.temporary_card_modifiers = Dictionary(data.get("temporary_card_modifiers", {}))
	run_state.relics = _to_string_array(data.get("relics", []))
	run_state.relic_state = Dictionary(data.get("relic_state", {})).duplicate(true)
	run_state.gold = int(data.get("gold", 0))
	run_state.encounters_cleared = int(data.get("encounters_cleared", 0))
	run_state.battle_history = _to_dictionary_array(data.get("battle_history", []))
	run_state.hp_damage_taken = int(data.get("hp_damage_taken", 0))
	run_state.run_complete = bool(data.get("run_complete", false))
	run_state.defeated = bool(data.get("defeated", false))
	run_state.infinite_mode = bool(data.get("infinite_mode", false))
	run_state.arena_mode = bool(data.get("arena_mode", false))
	run_state.arena_round = int(data.get("arena_round", 1))
	run_state.arena_wins = int(data.get("arena_wins", 0))
	run_state.arena_losses = int(data.get("arena_losses", 0))
	run_state.arena_target_wins = int(data.get("arena_target_wins", 12))
	run_state.arena_max_losses = int(data.get("arena_max_losses", 3))
	run_state.arena_next_enemy_id = String(data.get("arena_next_enemy_id", ""))
	run_state.arena_shop = Dictionary(data.get("arena_shop", {}))
	run_state.arena_pending_rewards = _to_dictionary_array(data.get("arena_pending_rewards", []))
	run_state.arena_pending_special_rewards = _to_dictionary_array(data.get("arena_pending_special_rewards", []))
	run_state.arena_shop_discount_stacks = maxi(0, int(data.get("arena_shop_discount_stacks", 0)))
	run_state.arena_timing_discount_stacks = maxi(0, int(data.get("arena_timing_discount_stacks", 0)))
	run_state.arena_initial_gold = maxi(0, int(data.get("arena_initial_gold", 70)))
	run_state.arena_match_gold = maxi(0, int(data.get("arena_match_gold", 50)))
	run_state.arena_initial_max_hp = maxi(1, int(data.get("arena_initial_max_hp", run_state.max_hp)))
	run_state.arena_special_reward_interval = maxi(1, int(data.get("arena_special_reward_interval", 3)))
	run_state.arena_shop_price_percent = maxi(1, int(data.get("arena_shop_price_percent", 100)))
	run_state.arena_reroll_cost = maxi(0, int(data.get("arena_reroll_cost", 8)))
	run_state.arena_shop_offer_count = maxi(2, int(data.get("arena_shop_offer_count", 5)))
	return run_state


func to_dict() -> Dictionary:
	return {
		"starter_id": starter_id,
		"seed": seed,
		"current_area": current_area,
		"player_hp": player_hp,
		"max_hp": max_hp,
		"attack": attack,
		"speed": speed,
		"map_state": map_state,
		"player_cards": player_cards,
		"equipped_cards": equipped_cards,
		"loadout_limit": loadout_limit,
		"card_upgrades": card_upgrades,
		"temporary_card_modifiers": temporary_card_modifiers,
		"relics": relics,
		"relic_state": relic_state.duplicate(true),
		"gold": gold,
		"encounters_cleared": encounters_cleared,
		"battle_history": battle_history,
		"hp_damage_taken": hp_damage_taken,
		"run_complete": run_complete,
		"defeated": defeated,
		"infinite_mode": infinite_mode,
		"arena_mode": arena_mode,
		"arena_round": arena_round,
		"arena_wins": arena_wins,
		"arena_losses": arena_losses,
		"arena_target_wins": arena_target_wins,
		"arena_max_losses": arena_max_losses,
		"arena_next_enemy_id": arena_next_enemy_id,
		"arena_shop": arena_shop,
		"arena_pending_rewards": arena_pending_rewards,
		"arena_pending_special_rewards": arena_pending_special_rewards,
		"arena_shop_discount_stacks": arena_shop_discount_stacks,
		"arena_timing_discount_stacks": arena_timing_discount_stacks,
		"arena_initial_gold": arena_initial_gold,
		"arena_match_gold": arena_match_gold,
		"arena_initial_max_hp": arena_initial_max_hp,
		"arena_special_reward_interval": arena_special_reward_interval,
		"arena_shop_price_percent": arena_shop_price_percent,
		"arena_reroll_cost": arena_reroll_cost,
		"arena_shop_offer_count": arena_shop_offer_count,
	}


static func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(String(item))
	return result


static func _to_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in Array(value):
		result.append(Dictionary(item).duplicate(true))
	return result


static func get_total_loadout_cost(card_ids: Array[String]) -> int:
	var total_cost: int = 0
	for card_id in card_ids:
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null:
			continue
		total_cost += card_def.loadout_cost
	return total_cost


static func build_default_equipped_cards(card_ids: Array[String], limit: int) -> Array[String]:
	var equipped: Array[String] = []
	var current_cost: int = 0
	for card_id in card_ids:
		var card_def: CardDef = Database.get_card(card_id)
		var card_cost: int = 0
		if card_def != null:
			card_cost = card_def.loadout_cost
		var next_cost: int = current_cost + card_cost
		if not equipped.is_empty() and next_cost > limit:
			continue
		equipped.append(card_id)
		current_cost = next_cost
	return equipped
