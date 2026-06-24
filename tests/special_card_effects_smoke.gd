extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	call_deferred("_run")


func _run() -> void:
	if not _test_large_shield_balance():
		return
	if not _test_delay_card_balance():
		return
	if not _test_shield_spend_cards():
		return
	if not _test_guardian_shield_cycle():
		return
	if not _test_empower_card():
		return
	if not _test_auto_queue_card():
		return
	if not _test_paradox_loop_depth():
		return
	if not _test_unlimited_auto_turret():
		return
	if not _test_hp_scaled_auto_queue():
		return
	if not _test_timeline_stop():
		return
	if not _test_timeline_reverse():
		return
	if not _test_special_card_descriptions():
		return
	print("Special card effects smoke passed")
	get_tree().quit()


func _test_large_shield_balance() -> bool:
	var expected_shield_by_card: Dictionary = {
		"barrier_deploy": [18, 20, 22, 23],
		"fortify": [34, 38, 40, 43],
		"bastion_drive": [11, 14, 16, 18],
		"entropy_armor": [13, 16, 19, 22],
		"grave_protocol": [18, 22, 26, 30],
	}
	for card_id: String in expected_shield_by_card:
		var expected_values: Array = Array(expected_shield_by_card[card_id])
		for tier in range(CardUpgradeResolver.MAX_TIER + 1):
			var tier_card: CardDef = CardUpgradeResolver.build_card_at_tier(card_id, tier)
			var actual_shield: int = int(_effect_amount(tier_card, "gain_shield"))
			if actual_shield != int(expected_values[tier]):
				_fail("Special card smoke failed: unexpected shield balance for %s tier %d" % [card_id, tier])
				return false
	if int(_effect_amount(Database.get_card("omega_ray"), "deal_damage")) != 22:
		_fail("Special card smoke failed: shield balance changed an unrelated damage card")
		return false
	return true


func _test_delay_card_balance() -> bool:
	var expected_delay_by_card: Dictionary = {
		"delay_step": [6.6, 7.9, 9.2, 10.6],
		"time_buy": [3.3, 4.3, 5.3, 6.3],
		"time_flow_control": [6.6, 7.9, 9.2, 10.6],
		"stasis_field": [5.3, 6.6, 7.9, 9.2],
		"null_cascade": [5.0, 5.9, 6.9, 7.9],
		"rift_volley": [3.3, 4.3, 5.3, 6.3],
	}
	for card_id: String in expected_delay_by_card:
		var expected_values: Array = Array(expected_delay_by_card[card_id])
		for tier in range(CardUpgradeResolver.MAX_TIER + 1):
			var tier_card: CardDef = CardUpgradeResolver.build_card_at_tier(card_id, tier)
			var actual_delay: float = _effect_amount(tier_card, "delay_enemy_active_card")
			if absf(actual_delay - float(expected_values[tier])) > 0.01:
				_fail("Special card smoke failed: unexpected delay balance for %s tier %d" % [card_id, tier])
				return false
	var expected_haste: Array[float] = [6.0, 7.2, 8.4, 9.6]
	for tier in range(CardUpgradeResolver.MAX_TIER + 1):
		var flow_card: CardDef = CardUpgradeResolver.build_card_at_tier("time_flow_control", tier)
		if absf(_effect_amount(flow_card, "haste_own_active_card") - expected_haste[tier]) > 0.01:
			_fail("Special card smoke failed: delay buff changed Time Flow Control haste at tier %d" % tier)
			return false
	return true


func _test_shield_spend_cards() -> bool:
	var ram_engine: RealtimeBattleEngine = _setup_engine(["aegis_ram"])
	ram_engine.battle_state.player.shield = 3
	if _request_card(ram_engine, "player", "aegis_ram"):
		_fail("Special card smoke failed: Aegis Ram should require 4 shield")
		return false
	if ram_engine.has_battle_started() or ram_engine.battle_state.player.shield != 3:
		_fail("Special card smoke failed: rejected shield cost should not start battle or spend shield")
		return false

	ram_engine.battle_state.player.shield = 10
	var enemy_hp_before: int = ram_engine.battle_state.enemy.hp
	if not _request_card(ram_engine, "player", "aegis_ram"):
		_fail("Special card smoke failed: Aegis Ram could not be requested with enough shield")
		return false
	if ram_engine.battle_state.player.shield != 6:
		_fail("Special card smoke failed: Aegis Ram did not immediately consume 4 shield")
		return false
	var ram_instance: ActiveCardInstance = _find_active_instance(ram_engine, "player", "aegis_ram", false)
	if ram_instance == null or ram_instance.shield_cost_paid != 4:
		_fail("Special card smoke failed: Aegis Ram did not record its paid shield cost")
		return false
	ram_engine.update(2.5)
	if ram_engine.battle_state.enemy.hp >= enemy_hp_before:
		_fail("Special card smoke failed: Aegis Ram did not deal damage after paying shield")
		return false
	var expected_consume_log: String = Localization.get_textf("battle.log.card_consume_shield", "{card_name} consumed {amount} shield", {
		"card_name": Database.get_card("aegis_ram").name,
		"amount": 4,
	})
	if not _has_log_fragment(ram_engine, expected_consume_log):
		_fail("Special card smoke failed: shield consumption was not written to the battle log")
		return false

	var expected_costs: Dictionary = {
		"aegis_ram": 4,
		"barrier_overdrive": 7,
		"bulwark_cannon": 12,
	}
	for card_id: String in expected_costs:
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null or CardEffectResolver.get_shield_cost(card_def) != int(expected_costs[card_id]):
			_fail("Special card smoke failed: invalid shield cost for %s" % card_id)
			return false
		if not ResourceLoader.exists("res://assets/icons/cards/%s.png" % card_id):
			_fail("Special card smoke failed: missing shield-spend card art for %s" % card_id)
			return false
		for tier in range(CardUpgradeResolver.MAX_TIER + 1):
			var tier_card: CardDef = CardUpgradeResolver.build_card_at_tier(card_id, tier)
			if tier_card == null or CardInfoFormatter.build_effect_summary(tier_card).find("consume_shield") >= 0:
				_fail("Special card smoke failed: shield-spend grade data was not formatted for %s tier %d" % [card_id, tier])
				return false

	var guardian: EnemyDef = Database.get_enemy("guardian")
	if guardian == null:
		_fail("Special card smoke failed: Guardian is missing")
		return false
	for card_id: String in expected_costs:
		if not guardian.cards.has(card_id):
			_fail("Special card smoke failed: Guardian does not carry %s" % card_id)
			return false
	return true


func _test_guardian_shield_cycle() -> bool:
	Game.start_new_run("balanced")
	Game.current_run.player_cards = ["guard"]
	Game.current_run.equipped_cards = ["guard"]
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.setup(Game.current_run, "guardian")
	engine.start_battle()
	var used_shield_spend: bool = false
	for _step in range(120):
		engine.update(0.1)
		for raw_event in engine.battle_state.battle_events:
			var event_data: Dictionary = Dictionary(raw_event)
			if String(event_data.get("actor_id", "")) != "guardian":
				continue
			var card_id: String = String(event_data.get("card_id", ""))
			if card_id in ["aegis_ram", "barrier_overdrive", "bulwark_cannon"]:
				used_shield_spend = true
				break
		if used_shield_spend:
			break
	if not used_shield_spend:
		_fail("Special card smoke failed: Guardian AI did not cycle shield into a shield-spend card")
		return false
	return true


func _test_empower_card() -> bool:
	var engine: RealtimeBattleEngine = _setup_engine(["self_tuning_edge"])
	if not _request_card(engine, "player", "self_tuning_edge"):
		_fail("Special card smoke failed: self_tuning_edge could not be requested")
		return false
	engine.update(3.7)

	var modifiers: Dictionary = Dictionary(Game.current_run.temporary_card_modifiers.get("self_tuning_edge", {}))
	if float(modifiers.get("damage", 0.0)) < 1.0:
		_fail("Special card smoke failed: self_tuning_edge did not empower its own damage")
		return false

	var upgraded_card: CardDef = CardUpgradeResolver.build_effective_card("self_tuning_edge", Game.current_run)
	if upgraded_card == null or _effect_amount(upgraded_card, "deal_damage") < 6.0:
		_fail("Special card smoke failed: temporary damage modifier was not applied to effective card data")
		return false

	var restored_run: RunState = RunState.from_dict(Game.current_run.to_dict())
	var restored_modifiers: Dictionary = Dictionary(restored_run.temporary_card_modifiers.get("self_tuning_edge", {}))
	if float(restored_modifiers.get("damage", 0.0)) < 1.0:
		_fail("Special card smoke failed: run-only card modifiers were not persisted in run state")
		return false
	return true


func _test_auto_queue_card() -> bool:
	var engine: RealtimeBattleEngine = _setup_engine(["recursive_protocol"])
	if not _request_card(engine, "player", "recursive_protocol"):
		_fail("Special card smoke failed: recursive_protocol could not be requested")
		return false
	engine.update(5.5)

	var auto_instance: ActiveCardInstance = _find_active_instance(engine, "player", "recursive_protocol", true)
	if auto_instance == null:
		_fail("Special card smoke failed: recursive_protocol did not auto-queue itself")
		return false
	if auto_instance.slot_cost != 0 or auto_instance.auto_depth != 1:
		_fail("Special card smoke failed: auto-queued card should be slotless and depth-limited")
		return false

	engine.update(6.2)
	if _count_active_auto_instances(engine, "player", "recursive_protocol") > 0:
		_fail("Special card smoke failed: recursive_protocol exceeded its auto-queue depth")
		return false
	return true


func _test_paradox_loop_depth() -> bool:
	var engine: RealtimeBattleEngine = _setup_engine(["paradox_loop"])
	if not _request_card(engine, "player", "paradox_loop"):
		_fail("Special card smoke failed: paradox_loop could not be requested")
		return false
	engine.update(6.1)
	engine.update(7.3)
	if _max_auto_depth(engine, "player", "paradox_loop") != 2:
		_fail("Special card smoke failed: paradox_loop should create a second-depth echo")
		return false
	engine.update(7.3)
	if _count_active_auto_instances(engine, "player", "paradox_loop") > 0:
		_fail("Special card smoke failed: paradox_loop exceeded its two-echo depth")
		return false
	return true


func _test_unlimited_auto_turret() -> bool:
	var engine: RealtimeBattleEngine = _setup_engine(["auto_turret"])
	if not _request_card(engine, "player", "auto_turret"):
		_fail("Special card smoke failed: auto_turret could not be requested")
		return false
	engine.update(3.1)
	engine.update(4.0)
	engine.update(4.0)

	var max_depth: int = _max_auto_depth(engine, "player", "auto_turret")
	if max_depth < 2:
		_fail("Special card smoke failed: auto_turret should keep auto-queueing itself without the normal depth cap")
		return false
	return true


func _test_hp_scaled_auto_queue() -> bool:
	var full_hp_engine: RealtimeBattleEngine = _setup_engine(["crisis_drone_swarm"])
	if not _request_card(full_hp_engine, "player", "crisis_drone_swarm"):
		_fail("Special card smoke failed: crisis_drone_swarm could not be requested at full HP")
		return false
	full_hp_engine.update(4.3)
	if _count_active_auto_instances(full_hp_engine, "player", "quick_guard") != 1:
		_fail("Special card smoke failed: crisis_drone_swarm should queue one guard at full HP")
		return false

	var low_hp_engine: RealtimeBattleEngine = _setup_engine(["crisis_drone_swarm"])
	low_hp_engine.battle_state.player.hp = int(round(float(low_hp_engine.battle_state.player.max_hp) * 0.25))
	if not _request_card(low_hp_engine, "player", "crisis_drone_swarm"):
		_fail("Special card smoke failed: crisis_drone_swarm could not be requested at low HP")
		return false
	low_hp_engine.update(4.3)
	if _count_active_auto_instances(low_hp_engine, "player", "quick_guard") != 4:
		_fail("Special card smoke failed: crisis_drone_swarm should scale queued guards with missing HP")
		return false
	return true


func _test_timeline_stop() -> bool:
	var engine: RealtimeBattleEngine = _setup_engine(["guard"])
	if not _request_card(engine, "enemy", "quick_slash"):
		_fail("Special card smoke failed: enemy card could not be manually queued for stop test")
		return false
	var instance: ActiveCardInstance = _find_active_instance(engine, "enemy", "quick_slash", false)
	if instance == null:
		_fail("Special card smoke failed: enemy active card missing for stop test")
		return false
	var initial_remaining: float = instance.get_remaining(engine.battle_state.battle_time)
	var affected_count: int = engine.apply_timeline_flow("player", {
		"target_side": "enemy",
		"mode": "stop",
		"duration": 1.0,
		"scope": "all",
	})
	if affected_count <= 0:
		_fail("Special card smoke failed: timeline stop did not target any active card")
		return false
	engine.update(0.75)
	instance = engine.battle_state.get_active_instance_by_id(instance.instance_id)
	if instance == null:
		_fail("Special card smoke failed: stopped card resolved too early")
		return false
	var stopped_remaining: float = instance.get_remaining(engine.battle_state.battle_time)
	if absf(stopped_remaining - initial_remaining) > 0.12:
		_fail("Special card smoke failed: timeline stop should keep remaining cast time stable")
		return false
	return true


func _test_timeline_reverse() -> bool:
	var engine: RealtimeBattleEngine = _setup_engine(["guard"])
	if not _request_card(engine, "enemy", "quick_slash"):
		_fail("Special card smoke failed: enemy card could not be manually queued for reverse test")
		return false
	var instance: ActiveCardInstance = _find_active_instance(engine, "enemy", "quick_slash", false)
	if instance == null:
		_fail("Special card smoke failed: enemy active card missing for reverse test")
		return false
	var initial_remaining: float = instance.get_remaining(engine.battle_state.battle_time)
	var affected_count: int = engine.apply_timeline_flow("player", {
		"target_side": "enemy",
		"mode": "reverse",
		"duration": 1.0,
		"speed": 1.0,
		"scope": "all",
	})
	if affected_count <= 0:
		_fail("Special card smoke failed: timeline reverse did not target any active card")
		return false
	engine.update(0.75)
	instance = engine.battle_state.get_active_instance_by_id(instance.instance_id)
	if instance == null:
		_fail("Special card smoke failed: reversed card resolved too early")
		return false
	var reversed_remaining: float = instance.get_remaining(engine.battle_state.battle_time)
	if reversed_remaining <= initial_remaining + 0.45:
		_fail("Special card smoke failed: timeline reverse should increase remaining cast time")
		return false
	return true


func _test_special_card_descriptions() -> bool:
	for card_id in [
		"self_tuning_edge", "sequence_loader", "chronostasis", "entropy_reversal",
		"auto_turret", "crisis_drone_swarm", "phase_lance", "mirror_aegis",
		"null_cascade", "paradox_loop", "rift_volley", "entropy_armor",
		"axiom_sever", "omega_ray", "grave_protocol", "zero_hour",
	]:
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null:
			_fail("Special card smoke failed: missing special card %s" % card_id)
			return false
		var summary: String = CardInfoFormatter.build_effect_summary(card_def)
		if summary == "" or summary.find("timeline_flow") >= 0 or summary.find("empower_card") >= 0 or summary.find("auto_queue_card") >= 0:
			_fail("Special card smoke failed: special card effect summary was not formatted for %s" % card_id)
			return false
	return true


func _setup_engine(card_ids: Array[String]) -> RealtimeBattleEngine:
	Game.start_new_run("balanced")
	var copied_cards: Array[String] = []
	for card_id in card_ids:
		copied_cards.append(card_id)
	var equipped_cards: Array[String] = []
	for card_id in copied_cards:
		equipped_cards.append(card_id)
	Game.current_run.player_cards = copied_cards
	Game.current_run.equipped_cards = equipped_cards
	Game.current_run.loadout_limit = 40
	Game.current_run.player_hp = Game.current_run.max_hp
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.setup(Game.current_run, "scout")
	return engine


func _request_card(engine: RealtimeBattleEngine, side: String, card_id: String) -> bool:
	var unit: UnitState = engine.battle_state.get_unit(side)
	for runtime_state in unit.card_runtime_states:
		if runtime_state.card_id == card_id:
			return engine.request_use_card(side, runtime_state.runtime_id)
	return false


func _find_active_instance(engine: RealtimeBattleEngine, side: String, card_id: String, require_auto: bool) -> ActiveCardInstance:
	for instance in engine.battle_state.active_instances:
		if instance.owner_side != side:
			continue
		if instance.card_id != card_id:
			continue
		if require_auto and not instance.is_auto_queued:
			continue
		return instance
	return null


func _count_active_auto_instances(engine: RealtimeBattleEngine, side: String, card_id: String) -> int:
	var count: int = 0
	for instance in engine.battle_state.active_instances:
		if instance.owner_side == side and instance.card_id == card_id and instance.is_auto_queued:
			count += 1
	return count


func _max_auto_depth(engine: RealtimeBattleEngine, side: String, card_id: String) -> int:
	var max_depth: int = 0
	for instance in engine.battle_state.active_instances:
		if instance.owner_side == side and instance.card_id == card_id and instance.is_auto_queued:
			max_depth = maxi(max_depth, instance.auto_depth)
	return max_depth


func _effect_amount(card_def: CardDef, effect_type: String) -> float:
	for raw_effect in card_def.effects:
		var effect_data: Dictionary = Dictionary(raw_effect)
		if String(effect_data.get("type", "")) == effect_type:
			return float(effect_data.get("amount", 0.0))
	return 0.0


func _has_log_fragment(engine: RealtimeBattleEngine, fragment: String) -> bool:
	for log_line: String in engine.battle_state.logs:
		if log_line.find(fragment) >= 0:
			return true
	return false


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
