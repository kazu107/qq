extends Node

var _failed: bool = false
var _arena_service: ArenaService = ArenaService.new()
var _relic_service: RelicService = RelicService.new()


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	_test_three_battle_trigger_and_reward_order()
	_test_custom_arena_rules()
	_test_special_reward_effects()
	_test_all_reward_kinds_can_be_rolled()
	_test_lan_shared_choices()
	_test_run_state_round_trip()
	_test_special_reward_ui()
	_test_card_tooltip_always_has_loadout_cost()
	if _failed:
		return
	print("Arena special reward smoke passed")
	get_tree().quit()


func _test_custom_arena_rules() -> void:
	var run_state: RunState = RunState.from_starter(Database.get_starter("balanced"), 901)
	_arena_service.configure_run(
		run_state,
		Database.get_all_card_ids(),
		Database.get_all_relic_ids(),
		{
			"initial_gold": 123,
			"match_gold": 91,
			"initial_max_hp": 88,
			"special_reward_interval": 2,
			"shop_price_percent": 150,
			"reroll_cost": 13,
			"shop_offer_count": 7,
		}
	)
	_expect(run_state.gold == 123, "Custom starting gold was not applied")
	_expect(run_state.arena_match_gold == 91, "Custom base match gold was not applied")
	_expect(run_state.max_hp == 88 and run_state.player_hp == 88, "Custom starting max HP was not applied")
	_expect(
		_arena_service.get_card_offers(run_state).size() + _arena_service.get_relic_offers(run_state).size() == 7,
		"Custom total shop item count was not applied"
	)
	var first_offer: Dictionary = _arena_service.get_card_offers(run_state)[0]
	var first_card_id: String = String(first_offer.get("card_id", ""))
	var expected_price: int = maxi(1, int(round(float(ShopService.new().get_price(first_card_id)) * 1.5)))
	_expect(int(first_offer.get("price", 0)) == expected_price, "Custom shop price multiplier was not applied")
	var gold_before_reroll: int = run_state.gold
	_expect(
		_arena_service.reroll_shop(run_state, Database.get_all_card_ids(), Database.get_all_relic_ids()),
		"Custom-price shop could not be rerolled"
	)
	_expect(run_state.gold == gold_before_reroll - 13, "Custom reroll cost was not applied")
	_expect(int(_arena_service.build_status(run_state).get("reroll_cost", -1)) == 13, "Custom reroll cost was not exposed to the UI")
	var reward_run: RunState = RunState.from_starter(Database.get_starter("balanced"), 904)
	_arena_service.configure_run(
		reward_run,
		Database.get_all_card_ids(),
		Database.get_all_relic_ids(),
		{"match_gold": 91}
	)
	var reward_result: Dictionary = _arena_service.apply_battle_result(
		reward_run,
		{"winner": "enemy"},
		Database.get_all_card_ids(),
		Database.get_all_relic_ids()
	)
	_expect(
		int(reward_result.get("reward_gold", 0))
		== 91 + ArenaService.MATCH_GOLD_PER_TIER + ArenaService.MATCH_GOLD_PER_ROUND,
		"Custom base match gold was not used by the reward calculation"
	)

	var early_run: RunState = RunState.from_starter(Database.get_starter("balanced"), 902)
	_arena_service.configure_run(early_run, Database.get_all_card_ids(), Database.get_all_relic_ids(), {"special_reward_interval": 2})
	early_run.arena_round = 1
	var early_result: Dictionary = _arena_service.apply_battle_result(
		early_run,
		{"winner": "enemy"},
		Database.get_all_card_ids(),
		Database.get_all_relic_ids()
	)
	_expect(not bool(early_result.get("special_reward_due", false)), "Custom special reward appeared too early")
	var due_run: RunState = RunState.from_starter(Database.get_starter("balanced"), 903)
	_arena_service.configure_run(due_run, Database.get_all_card_ids(), Database.get_all_relic_ids(), {"special_reward_interval": 2})
	due_run.arena_round = 2
	var due_result: Dictionary = _arena_service.apply_battle_result(
		due_run,
		{"winner": "enemy"},
		Database.get_all_card_ids(),
		Database.get_all_relic_ids()
	)
	_expect(bool(due_result.get("special_reward_due", false)), "Custom special reward interval was not applied")


func _test_three_battle_trigger_and_reward_order() -> void:
	var losing_run: RunState = _new_run(1001)
	losing_run.arena_round = 3
	var loss_result: Dictionary = _arena_service.apply_battle_result(
		losing_run,
		{"winner": "enemy"},
		Database.get_all_card_ids(),
		Database.get_all_relic_ids()
	)
	_expect(bool(loss_result.get("special_reward_due", false)), "Third battle loss did not create a special reward")
	_expect(losing_run.arena_pending_special_rewards.size() == 3, "Third battle special reward did not contain 3 choices")
	_expect(_arena_service.get_pending_rewards(losing_run) == losing_run.arena_pending_special_rewards, "Loss special reward was not exposed as pending")

	var winning_run: RunState = _new_run(1002)
	winning_run.arena_round = 3
	_arena_service.apply_battle_result(
		winning_run,
		{"winner": "player"},
		Database.get_all_card_ids(),
		Database.get_all_relic_ids()
	)
	_expect(not winning_run.arena_pending_rewards.is_empty(), "Winning battle did not create its normal reward")
	_expect(winning_run.arena_pending_special_rewards.size() == 3, "Winning third battle did not also create a special reward")
	var first_pending_id: String = String(_arena_service.get_pending_rewards(winning_run)[0].get("id", ""))
	_expect(not bool(_arena_service.get_pending_rewards(winning_run)[0].get("special", false)), "Special reward appeared before the normal victory reward")
	var normal_result: Dictionary = _arena_service.apply_pending_reward(winning_run, first_pending_id, _relic_service)
	_expect(bool(normal_result.get("applied", false)), "Normal reward could not be selected before the special reward")
	_expect(bool(_arena_service.get_pending_rewards(winning_run)[0].get("special", false)), "Special reward did not follow the normal reward")


func _test_special_reward_effects() -> void:
	var loadout_run: RunState = _new_run(2001)
	var limit_before: int = loadout_run.loadout_limit
	var loadout_result: Dictionary = _apply_special(loadout_run, {
		"id": "test_loadout",
		"kind": "special_loadout_limit",
		"special": true,
	})
	_expect(bool(loadout_result.get("applied", false)) and loadout_run.loadout_limit == limit_before + 1, "Loadout limit reward was not applied")

	var hp_run: RunState = _new_run(2002)
	var max_hp_before: int = hp_run.max_hp
	var hp_before: int = hp_run.player_hp
	_apply_special(hp_run, {
		"id": "test_hp",
		"kind": "special_max_hp",
		"special": true,
		"amount": 14,
	})
	_expect(hp_run.max_hp == max_hp_before + 14 and hp_run.player_hp == hp_before + 14, "Max HP reward did not increase both maximum and current HP")

	var shop_run: RunState = _new_run(2003)
	var price_before: int = int(_arena_service.get_card_offers(shop_run)[0].get("price", 0))
	_apply_special(shop_run, {
		"id": "test_shop_1",
		"kind": "special_shop_discount",
		"special": true,
	})
	var first_discount_price: int = int(_arena_service.get_card_offers(shop_run)[0].get("price", 0))
	_apply_special(shop_run, {
		"id": "test_shop_2",
		"kind": "special_shop_discount",
		"special": true,
	})
	var second_discount_price: int = int(_arena_service.get_card_offers(shop_run)[0].get("price", 0))
	_expect(shop_run.arena_shop_discount_stacks == 2, "Shop discount reward did not stack")
	_expect(first_discount_price < price_before and second_discount_price < first_discount_price, "Stacked shop discounts did not lower current offer prices")
	shop_run.gold = 999
	_arena_service.reroll_shop(shop_run, Database.get_all_card_ids(), Database.get_all_relic_ids())
	var shop_service: ShopService = ShopService.new()
	for offer_data in _arena_service.get_card_offers(shop_run):
		var offer_card_id: String = String(offer_data.get("card_id", ""))
		var expected_price: int = maxi(1, int(round(float(shop_service.get_price(offer_card_id)) * 0.81)))
		_expect(int(offer_data.get("price", 0)) == expected_price, "Stacked discount was not applied to newly rolled shop offers")

	var timing_run: RunState = _new_run(2004)
	var timing_card_id: String = timing_run.player_cards[0]
	var base_card: CardDef = Database.get_card(timing_card_id)
	_apply_special(timing_run, {
		"id": "test_timing_1",
		"kind": "special_timing_discount",
		"special": true,
	})
	_apply_special(timing_run, {
		"id": "test_timing_2",
		"kind": "special_timing_discount",
		"special": true,
	})
	var effective_card: CardDef = CardUpgradeResolver.build_effective_card(timing_card_id, timing_run)
	_expect(is_equal_approx(effective_card.cast_time, base_card.cast_time * 0.81), "Stacked cast reduction was not multiplicative")
	_expect(is_equal_approx(effective_card.recast_time, base_card.recast_time * 0.81), "Stacked recast reduction was not multiplicative")

	var loss_run: RunState = _new_run(2005)
	loss_run.arena_losses = 2
	_apply_special(loss_run, {
		"id": "test_loss",
		"kind": "special_remove_loss",
		"special": true,
	})
	_expect(loss_run.arena_losses == 1, "Loss removal reward did not reduce losses")

	var upgrade_run: RunState = _new_run(2006)
	var upgrade_result: Dictionary = _apply_special(upgrade_run, {
		"id": "test_upgrade",
		"kind": "special_upgrade_two",
		"special": true,
		"apply_seed": 500,
	})
	var upgraded_ids: Array[String] = _to_string_array(upgrade_result.get("upgraded_card_ids", []))
	_expect(upgraded_ids.size() == mini(2, _unique_strings(upgrade_run.player_cards).size()), "Random upgrade reward did not upgrade 2 distinct cards")
	for card_id in upgraded_ids:
		_expect(CardUpgradeResolver.get_tier(upgrade_run, card_id) == 1, "Random upgrade reward applied an incorrect Grade")

	var legendary_ids: Array[String] = Database.get_card_ids_by_rarity("legendary")
	_expect(not legendary_ids.is_empty(), "Legendary reward test has no Legendary cards")
	if not legendary_ids.is_empty():
		var legendary_run: RunState = _new_run(2007)
		var legendary_id: String = legendary_ids[0]
		var owned_before: int = _count_occurrences(legendary_run.player_cards, legendary_id)
		_apply_special(legendary_run, {
			"id": "test_legendary",
			"kind": "special_legendary_card",
			"special": true,
			"card_id": legendary_id,
		})
		_expect(_count_occurrences(legendary_run.player_cards, legendary_id) == owned_before + 1, "Legendary reward did not grant a card")


func _test_all_reward_kinds_can_be_rolled() -> void:
	var expected_kinds: Array[String] = [
		"special_loadout_limit",
		"special_max_hp",
		"special_shop_discount",
		"special_timing_discount",
		"special_remove_loss",
		"special_upgrade_two",
		"special_legendary_card",
	]
	var seen: Dictionary = {}
	var run_state: RunState = _new_run(3001)
	var early_hp_amount: int = 0
	var late_hp_amount: int = 0
	for seed_value in range(1, 80):
		var rewards: Array[Dictionary] = _arena_service.build_special_rewards(run_state, 3, seed_value)
		var late_rewards: Array[Dictionary] = _arena_service.build_special_rewards(run_state, 12, seed_value)
		_expect(rewards.size() == 3, "Special reward roll did not return exactly 3 choices")
		var ids: Dictionary = {}
		for reward_data in rewards:
			var reward_id: String = String(reward_data.get("id", ""))
			ids[reward_id] = true
			var reward_kind: String = String(reward_data.get("kind", ""))
			seen[reward_kind] = true
			if reward_kind == "special_max_hp":
				early_hp_amount = int(reward_data.get("amount", 0))
		for late_reward_data in late_rewards:
			if String(late_reward_data.get("kind", "")) == "special_max_hp":
				late_hp_amount = int(late_reward_data.get("amount", 0))
		_expect(ids.size() == rewards.size(), "Special reward roll contained duplicate choices")
	for expected_kind in expected_kinds:
		_expect(seen.has(expected_kind), "Special reward kind was never rollable: %s" % expected_kind)
	_expect(early_hp_amount > 0 and late_hp_amount > early_hp_amount, "Max HP reward did not scale up in later rounds")


func _test_lan_shared_choices() -> void:
	var coordinator: LanArenaCoordinator = LanArenaCoordinator.new()
	var player_run: RunState = _new_run(4001)
	var enemy_run: RunState = _new_run(4999)
	var shared_rewards: Array[Dictionary] = coordinator.assign_shared_special_rewards(player_run, enemy_run, 3, 7777)
	_expect(shared_rewards.size() == 3, "LAN shared special reward did not contain 3 choices")
	_expect(player_run.arena_pending_special_rewards == enemy_run.arena_pending_special_rewards, "LAN players received different special reward choices")


func _test_run_state_round_trip() -> void:
	var run_state: RunState = _new_run(5001)
	run_state.arena_shop_discount_stacks = 2
	run_state.arena_timing_discount_stacks = 3
	run_state.arena_pending_special_rewards = [{"id": "round_trip", "kind": "special_loadout_limit", "special": true}]
	run_state.arena_initial_gold = 123
	run_state.arena_match_gold = 91
	run_state.arena_initial_max_hp = 88
	run_state.arena_special_reward_interval = 2
	run_state.arena_shop_price_percent = 150
	run_state.arena_reroll_cost = 13
	run_state.arena_shop_offer_count = 7
	var restored: RunState = RunState.from_dict(run_state.to_dict())
	_expect(restored.arena_shop_discount_stacks == 2, "Shop discount stacks were not saved")
	_expect(restored.arena_timing_discount_stacks == 3, "Timing discount stacks were not saved")
	_expect(restored.arena_pending_special_rewards == run_state.arena_pending_special_rewards, "Pending special rewards were not saved")
	_expect(restored.arena_initial_gold == 123 and restored.arena_initial_max_hp == 88, "Custom starting resources were not saved")
	_expect(restored.arena_match_gold == 91, "Custom base match gold was not saved")
	_expect(restored.arena_special_reward_interval == 2, "Custom special reward interval was not saved")
	_expect(restored.arena_shop_price_percent == 150, "Custom shop multiplier was not saved")
	_expect(restored.arena_reroll_cost == 13 and restored.arena_shop_offer_count == 7, "Custom shop rules were not saved")


func _test_special_reward_ui() -> void:
	var run_state: RunState = _new_run(6001)
	run_state.arena_pending_special_rewards = _arena_service.build_special_rewards(run_state, 3, 8800)
	Game.current_run = run_state
	Game.current_screen_hint = "arena"
	var arena_scene: Control = load("res://scenes/arena/Arena.tscn").instantiate() as Control
	add_child(arena_scene)
	var title_label: Label = arena_scene.find_child("ArenaRewardTitle", true, false) as Label
	var option_box: HBoxContainer = arena_scene.find_child("ArenaRewardOptions", true, false) as HBoxContainer
	_expect(title_label != null and title_label.text == Localization.get_text("arena.special.title", "Special Reward"), "Special reward modal did not use its dedicated title")
	_expect(option_box != null and option_box.get_child_count() == 3, "Special reward modal did not render 3 choices")
	arena_scene.queue_free()
	Game.current_run = null


func _test_card_tooltip_always_has_loadout_cost() -> void:
	var card_id: String = Database.get_all_card_ids()[0]
	var card_def: CardDef = Database.get_card(card_id)
	var preview: CardButton = CardButton.new()
	add_child(preview)
	preview.bind_preview(card_def, card_id)
	var expected_text: String = Localization.get_textf("card.tooltip.loadout_cost", "Loadout Cost: {cost}", {
		"cost": card_def.loadout_cost,
	})
	_expect(preview.tooltip_text.find(expected_text) != -1, "Card tooltip did not always include loadout cost")
	preview.queue_free()


func _new_run(seed_value: int) -> RunState:
	var run_state: RunState = RunState.from_starter(Database.get_starter("balanced"), seed_value)
	_arena_service.configure_run(run_state, Database.get_all_card_ids(), Database.get_all_relic_ids())
	return run_state


func _apply_special(run_state: RunState, reward_data: Dictionary) -> Dictionary:
	_arena_service.assign_special_rewards(run_state, [reward_data])
	return _arena_service.apply_pending_reward(run_state, String(reward_data.get("id", "")), _relic_service)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Arena special reward smoke failed: %s" % message)
	get_tree().quit(1)


func _count_occurrences(values: Array[String], target: String) -> int:
	var count: int = 0
	for value in values:
		if value == target:
			count += 1
	return count


func _unique_strings(values: Array[String]) -> Array[String]:
	var unique_values: Array[String] = []
	for value in values:
		if not unique_values.has(value):
			unique_values.append(value)
	return unique_values


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in Array(value):
		result.append(String(item))
	return result
