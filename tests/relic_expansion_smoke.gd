extends Node

const EXPECTED_TOTAL: int = 86
const NEW_IDS: Array[String] = [
	"triplet_relay", "borrowed_second_hand", "terminal_echo_ring", "four_name_quartet",
	"dead_heat_needle", "silent_three_second_timer", "delay_return_gear", "zero_hour_clapper",
	"terminal_bell", "paradox_mortgage", "overtake_signal", "reversal_turbine",
	"full_slot_bell", "vacancy_interest_meter", "fourth_reserve_rack", "single_seat_duel_sheath",
	"reserved_seat_tag", "echo_rectifier", "waste_heat_printer", "isolation_chamber",
	"resin_memory_block", "full_absorption_gauge", "evaporation_recovery_valve",
	"residual_pressure_detonator", "rupture_insurance_film", "compression_caliper",
	"twilight_pacemaker", "bleed_pulsator", "slow_charge_accumulator", "four_symptom_seal",
	"quarantine_buffer", "symptom_transfer_paper", "critical_pathology_meter", "grade_staircase",
	"unpolished_motherboard", "overload_seal", "empty_rack_bus", "full_load_latch",
	"weight_ticket_punch", "grade_differential_wheel", "solar_pinion",
	"overcharge_confection_furnace", "polarization_converter", "balanced_three_phase_unit",
	"memorial_fund_coil", "seven_step_validator", "depth_pressure_gauge",
	"emergency_recovery_line", "carryover_price_tag", "defeat_wiring", "overtime_key",
	"loop_wear_wheel",
]


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	if not _test_catalog_and_art():
		return
	if not _test_persistent_state_and_acquisition():
		return
	if not _test_battle_profiles_and_codec():
		return
	if not _test_mode_effects():
		return
	if not _test_review_boundaries():
		return
	print("Relic expansion smoke passed: %d relics / %d new effects" % [EXPECTED_TOTAL, NEW_IDS.size()])
	get_tree().quit()


func _test_catalog_and_art() -> bool:
	var ids: Array[String] = Database.get_all_relic_ids()
	if ids.size() != EXPECTED_TOTAL:
		return _fail("expected %d relics, got %d" % [EXPECTED_TOTAL, ids.size()])
	for relic_id: String in ids:
		var relic: RelicDef = Database.get_relic(relic_id)
		if relic == null or relic.name.is_empty() or relic.description.is_empty():
			return _fail("missing relic definition: %s" % relic_id)
		if not ResourceLoader.exists("res://assets/icons/relics/%s.png" % relic_id, "Texture2D"):
			return _fail("missing imported relic art: %s" % relic_id)
	for relic_id: String in NEW_IDS:
		var relic: RelicDef = Database.get_relic(relic_id)
		if relic == null or relic.effects.is_empty() or relic.tags.is_empty() or relic.mode_scope.is_empty():
			return _fail("new relic lacks runtime metadata: %s" % relic_id)
	return true


func _test_persistent_state_and_acquisition() -> bool:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 90210)
	run.relic_state = {"sample": {"charges": 3}}
	var restored: RunState = RunState.from_dict(run.to_dict())
	if int(Dictionary(restored.relic_state.get("sample", {})).get("charges", 0)) != 3:
		return _fail("RunState did not preserve relic_state")
	var service: RelicService = RelicService.new()
	run.arena_mode = true
	var target_before: int = run.arena_target_wins
	var losses_before: int = run.arena_max_losses
	if not service.grant_relic(run, "overtime_key") or run.arena_target_wins != target_before + 1 or run.arena_max_losses != losses_before + 1:
		return _fail("Overtime Key acquisition effect failed")
	if not service.grant_relic(run, "solar_pinion") or String(Dictionary(run.relic_state.get("solar_pinion", {})).get("card_id", "")).is_empty():
		return _fail("engraving relic did not select a card")
	return true


func _test_battle_profiles_and_codec() -> bool:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 123)
	run.relics = ["fourth_reserve_rack", "compression_caliper", "vacancy_interest_meter"]
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.setup(run, "scout")
	if engine.battle_state.player.active_slot_max != 4:
		return _fail("Fourth Reserve Rack did not add an active slot")
	engine.start_battle()
	engine.battle_state.player.shield = 12
	engine.update(0.1)
	if not is_equal_approx(engine.battle_state.player.shield_decay_interval, 2.0):
		return _fail("Compression Caliper did not slow shield decay")
	engine.battle_state.relic_runtime_state["player"]["charges"] = 2
	var payload: Dictionary = BattleStateCodec.encode(engine.battle_state, true)
	var decoded: BattleState = BattleStateCodec.decode(payload)
	if decoded == null or int(Dictionary(decoded.relic_runtime_state.get("player", {})).get("charges", 0)) != 2:
		return _fail("battle relic runtime state did not survive codec roundtrip")

	var hazard_run: RunState = RunState.from_starter(Database.get_starter("balanced"), 456)
	hazard_run.relics = ["emergency_recovery_line"]
	hazard_run.map_state = {
		"active_node_id": "hazard_test",
		"steps": [{"nodes": [{
			"id": "hazard_test",
			"type": "hazard",
			"hazard_cleared_waves": 1,
		}]}],
	}
	var hazard_engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	hazard_engine.setup(hazard_run, "scout")
	hazard_engine.battle_state.player.hp = 0
	if not hazard_engine.prevent_lethal("player"):
		return _fail("Emergency Recovery Line did not prevent lethal hazard damage")
	var hazard_summary: Dictionary = hazard_engine.build_summary()
	if hazard_engine.battle_state.player.hp != 1 or hazard_engine.battle_state.winner != "hazard_withdraw" or not bool(hazard_summary.get("forced_hazard_withdraw", false)):
		return _fail("Emergency Recovery Line did not force hazard withdrawal")
	return true


func _test_mode_effects() -> bool:
	var service: RelicService = RelicService.new()
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 77)
	run.relics = ["seven_step_validator", "loop_wear_wheel", "carryover_price_tag"]
	var upgraded: String = service.apply_step_entry(run, 7)
	if upgraded.is_empty() or CardUpgradeResolver.get_tier(run, upgraded) != 1:
		return _fail("Seven-Step Validator did not upgrade a card")
	var worn: String = service.apply_infinite_cycle(run, 2)
	if worn.is_empty() or float(Dictionary(run.temporary_card_modifiers.get(worn, {})).get("recast_time", 0.0)) != -1.0:
		return _fail("Loop Wear Wheel did not persist recast reduction")
	run.arena_shop = {"cards": [{"card_id": "quick_slash", "price": 20, "held": true, "bought": false}], "relics": []}
	var arena: ArenaService = ArenaService.new()
	var held: Array[Dictionary] = arena._collect_held_offers(run, "cards")
	if held.is_empty() or int(held[0].get("price", 0)) != 16:
		return _fail("Carryover Price Tag did not discount a held item")
	return true


func _test_review_boundaries() -> bool:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 818)
	run.relics = ["vacancy_interest_meter", "resin_memory_block", "reserved_seat_tag"]
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.setup(run, "scout")
	engine.start_battle()
	engine.update(20.0)
	var player_relic_state: Dictionary = Dictionary(engine.battle_state.relic_runtime_state.get("player", {}))
	if int(player_relic_state.get("empty_slot_charges", 0)) != 3 or float(player_relic_state.get("empty_slot_seconds", 0.0)) >= 3.0:
		return _fail("Vacancy Interest Meter accumulated hidden time at max charges")
	if not engine.set_relic_enabled("player", "reserved_seat_tag", false) or engine.is_relic_enabled("player", "reserved_seat_tag"):
		return _fail("Reserved Seat Tag toggle did not update battle state")

	var auto_instance: ActiveCardInstance = ActiveCardInstance.new()
	auto_instance.owner_side = "player"
	auto_instance.card_id = "quick_slash"
	auto_instance.source_card_id = "quick_slash"
	auto_instance.is_auto_queued = true
	var source_card: CardDef = Database.get_card("quick_slash")
	for _index: int in 6:
		engine._relic_controller.after_resolve("player", auto_instance, source_card, {})
	var battle_modifiers: Dictionary = Dictionary(engine.battle_state.player.battle_card_modifiers.get("quick_slash", {}))
	if int(battle_modifiers.get("damage", 0)) != 5 or run.temporary_card_modifiers.has("quick_slash"):
		return _fail("Resin Memory Block was not capped or leaked outside battle state")
	var synced_state: BattleState = BattleStateCodec.decode(BattleStateCodec.encode(engine.battle_state, true))
	var synced_modifiers: Dictionary = Dictionary(synced_state.player.battle_card_modifiers.get("quick_slash", {}))
	var synced_relic_state: Dictionary = Dictionary(synced_state.relic_runtime_state.get("player", {}))
	if int(synced_modifiers.get("damage", 0)) != 5 or bool(synced_relic_state.get("enabled_reserved_seat_tag", true)):
		return _fail("battle-only modifier or relic toggle did not survive snapshot codec")

	auto_instance.instance_id = engine.battle_state.next_instance_id
	engine.battle_state.next_instance_id += 1
	auto_instance.runtime_id = "__auto_player_test"
	auto_instance.interruptible = true
	auto_instance.scheduled_time = engine.battle_state.battle_time + 5.0
	engine.battle_state.active_instances.append(auto_instance)
	if not engine.interrupt_instance(auto_instance) or engine.battle_state.get_active_instance_by_id(auto_instance.instance_id) != null:
		return _fail("auto-queued instance could not be interrupted")

	var arena_run: RunState = RunState.from_starter(Database.get_starter("balanced"), 919)
	arena_run.arena_mode = true
	arena_run.loadout_limit = 20
	arena_run.relics = ["fourth_reserve_rack", "empty_rack_bus", "defeat_wiring"]
	arena_run.relic_state["arena_lost_last_battle"] = true
	var arena_engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	arena_engine.setup(arena_run, "scout")
	var slots_before: int = arena_engine.battle_state.player.active_slot_max
	arena_engine.start_battle()
	arena_engine.update(16.0)
	if arena_engine.battle_state.player.active_slot_max != slots_before:
		return _fail("Defeat Wiring removed permanent relic slots")
	return true


func _fail(message: String) -> bool:
	push_error("Relic expansion smoke failed: %s" % message)
	get_tree().quit(1)
	return false
