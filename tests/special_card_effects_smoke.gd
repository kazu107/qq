extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	call_deferred("_run")


func _run() -> void:
	if not _test_empower_card():
		return
	if not _test_auto_queue_card():
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
	for card_id in ["self_tuning_edge", "sequence_loader", "chronostasis", "entropy_reversal", "auto_turret", "crisis_drone_swarm"]:
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


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
