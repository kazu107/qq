extends RefCounted
class_name RelicBattleController

const NEGATIVE_STATUSES: Array[String] = ["bleed", "weak", "slow", "vulnerable"]
const THRESHOLDS: Array[float] = [10.0, 20.0, 30.0]

var _engine: RealtimeBattleEngine
var _state: BattleState
var _runs: Dictionary = {}


func setup(engine: RealtimeBattleEngine, state: BattleState, player_run: RunState, enemy_run: RunState) -> void:
	_engine = engine
	_state = state
	_runs = {"player": player_run, "enemy": enemy_run}
	if _state.relic_runtime_state.is_empty():
		_state.relic_runtime_state = {"player": {}, "enemy": {}}
	for side: String in ["player", "enemy"]:
		if not _state.relic_runtime_state.has(side):
			_state.relic_runtime_state[side] = {}


func detach() -> void:
	_engine = null
	_state = null
	_runs.clear()


func apply_unit_setup(side: String, unit: UnitState) -> void:
	var run: RunState = _run(side)
	if unit == null or run == null:
		return
	if has_relic(side, "fourth_reserve_rack"):
		unit.active_slot_max += 1
	if has_relic(side, "empty_rack_bus"):
		var unused: int = maxi(0, run.loadout_limit - RelicService.get_effective_loadout_cost(run))
		unit.active_slot_max += mini(2, unused / 3)
	if has_relic(side, "overload_seal"):
		var overage: int = maxi(0, RelicService.get_effective_loadout_cost(run) - run.loadout_limit)
		if overage > 0:
			unit.add_status("vulnerable", float(mini(2, overage)) * 12.0)
	if has_relic(side, "defeat_wiring") and run.arena_mode and bool(run.relic_state.get("arena_lost_last_battle", false)):
		var base_slots: int = unit.active_slot_max
		unit.active_slot_max = maxi(base_slots, 4)
		if unit.active_slot_max > base_slots:
			_set_value(side, "defeat_wiring_base_slots", base_slots)
			_set_value(side, "defeat_wiring_until", 15.0)
	if has_relic(side, "depth_pressure_gauge"):
		var wave: int = _hazard_wave(run)
		if wave >= 2:
			unit.active_slot_max += wave - 1
			unit.cast_time_modifier *= 1.0 + float(wave - 1) * 0.05
	_update_compression_caliper(side)


func update(delta: float) -> void:
	if _state == null:
		return
	for side: String in ["player", "enemy"]:
		var unit: UnitState = _state.get_unit(side)
		if unit == null:
			continue
		_update_compression_caliper(side)
		if has_relic(side, "fourth_reserve_rack") and unit.active_slots_used >= 4:
			for instance: ActiveCardInstance in _state.get_active_instances_for_side(side):
				instance.shift_schedule(delta * 0.25, _state.battle_time, true)
		if has_relic(side, "vacancy_interest_meter"):
			var empty_slots: int = maxi(0, unit.active_slot_max - unit.active_slots_used)
			var accumulator: float = _number(side, "empty_slot_seconds") + delta * float(empty_slots)
			var charges: int = _integer(side, "empty_slot_charges")
			while accumulator >= 3.0 and charges < 3:
				accumulator -= 3.0
				charges += 1
			if charges >= 3:
				accumulator = minf(accumulator, 2.999)
			_set_value(side, "empty_slot_seconds", accumulator)
			_set_value(side, "empty_slot_charges", charges)
		if has_relic(side, "silent_three_second_timer"):
			if _state.get_active_instances_for_side(side).is_empty():
				_set_value(side, "empty_timeline_seconds", _number(side, "empty_timeline_seconds") + delta)
			else:
				_set_value(side, "empty_timeline_seconds", 0.0)
		for threshold: float in THRESHOLDS:
			var key: String = "zero_hour_%d" % int(threshold)
			if has_relic(side, "zero_hour_clapper") and _state.battle_time >= threshold and not _flag(side, key):
				_set_value(side, key, true)
				_engine.haste_active_cards(side, 1.0, "single")
				_play_relic_proc(side, "zero_hour_clapper")
		if has_relic(side, "defeat_wiring") and _state.battle_time >= _number(side, "defeat_wiring_until") and _number(side, "defeat_wiring_until") > 0.0:
			unit.active_slot_max = maxi(3, _integer(side, "defeat_wiring_base_slots"))
			_set_value(side, "defeat_wiring_until", 0.0)


func get_cooldown_delta(side: String, delta: float) -> float:
	if has_relic(side, "fourth_reserve_rack") and _state.get_unit(side).active_slots_used >= 4:
		return delta * 0.8
	return delta


func prevent_lethal(side: String) -> bool:
	var run: RunState = _run(side)
	var unit: UnitState = _state.get_unit(side)
	if run == null or unit == null or unit.hp > 0 or not has_relic(side, "emergency_recovery_line") or _hazard_wave(run) < 2:
		return false
	var relic_data: Dictionary = Dictionary(run.relic_state.get("emergency_recovery_line", {}))
	if bool(relic_data.get("used", false)):
		return false
	unit.hp = 1
	relic_data["used"] = true
	run.relic_state["emergency_recovery_line"] = relic_data
	_mark_current_hazard_reward_lost(run)
	_state.winner = "hazard_withdraw"
	_set_value(side, "forced_hazard_withdraw", true)
	_play_relic_proc(side, "emergency_recovery_line")
	return true


func build_commit_profile(side: String, card_def: CardDef) -> Dictionary:
	var unit: UnitState = _state.get_unit(side)
	var run: RunState = _run(side)
	var profile: Dictionary = {
		"cast_time": card_def.cast_time * unit.get_cast_time_multiplier(),
		"slot_cost": card_def.active_slot_cost,
		"shield_cost": CardEffectResolver.get_shield_cost(card_def),
		"effect_bonus": 0,
		"recast_multiplier": 1.0,
		"recast_delta": 0.0,
		"flags": {},
	}
	if run == null:
		return profile
	var flags: Dictionary = profile["flags"]
	if has_relic(side, "vacancy_interest_meter"):
		var charges: int = _integer(side, "empty_slot_charges")
		if charges > 0:
			profile["cast_time"] = maxf(0.45, float(profile["cast_time"]) - float(charges) * 0.8)
			flags["spent_empty_slot_charges"] = charges
	if has_relic(side, "silent_three_second_timer") and _number(side, "empty_timeline_seconds") >= 3.0:
		profile["cast_time"] = maxf(0.45, float(profile["cast_time"]) * 0.7)
		profile["recast_multiplier"] = 1.25
		flags["silent_clock"] = true
	if has_relic(side, "single_seat_duel_sheath") and unit.active_slots_used == 0 and card_def.active_slot_cost >= 2:
		profile["cast_time"] = maxf(1.0, float(profile["cast_time"]) * 0.85)
		flags["single_seat"] = true
	if has_relic(side, "reserved_seat_tag") and is_relic_enabled(side, "reserved_seat_tag") and unit.active_slot_max - unit.active_slots_used == 1 and _enemy_has_interruptible(side) and card_def.tags.has("interrupt"):
		profile["cast_time"] = maxf(0.45, float(profile["cast_time"]) * 0.8)
	if has_relic(side, "full_load_latch") and not _flag(side, "full_load_used") and RelicService.get_effective_loadout_cost(run) == run.loadout_limit and card_def.active_slot_cost >= 2:
		profile["slot_cost"] = maxi(1, card_def.active_slot_cost - 1)
		flags["full_load_latch"] = true
	if has_relic(side, "twilight_pacemaker"):
		var hp_ratio: float = float(unit.hp) / maxf(1.0, float(unit.max_hp))
		if hp_ratio <= 0.43 and (card_def.tags.has("attack") or card_def.tags.has("control")):
			profile["cast_time"] = maxf(0.45, float(profile["cast_time"]) * 0.91)
		elif hp_ratio >= 0.49 and (card_def.tags.has("shield") or card_def.tags.has("heal")):
			profile["effect_bonus"] = int(profile["effect_bonus"]) + maxi(1, _primary_effect_amount(card_def) * 8 / 100)
	if has_relic(side, "slow_charge_accumulator") and unit.has_status("slow"):
		var added_cast: float = card_def.cast_time * unit.cast_time_modifier * 0.1
		profile["effect_bonus"] = int(profile["effect_bonus"]) + mini(3, floori(added_cast / 0.5))
	if has_relic(side, "compression_caliper") and unit.shield >= 12 and int(profile["shield_cost"]) > 0:
		profile["shield_cost"] = int(profile["shield_cost"]) + 2
	if has_relic(side, "evaporation_recovery_valve") and int(profile["shield_cost"]) > 0:
		var tokens: int = _integer(side, "shield_discount_tokens")
		var used: int = mini(tokens, int(profile["shield_cost"]))
		profile["shield_cost"] = maxi(0, int(profile["shield_cost"]) - used)
		flags["shield_discount_used"] = used
	if has_relic(side, "unpolished_motherboard") and CardUpgradeResolver.get_tier(run, card_def.id) == 0 and _is_discounted_base_card(run, card_def.id):
		profile["cast_time"] = float(profile["cast_time"]) * 1.12
	_apply_engraving_profile(side, card_def, profile)
	return profile


func can_commit(side: String, card_def: CardDef, profile: Dictionary) -> bool:
	var unit: UnitState = _state.get_unit(side)
	if unit == null:
		return false
	if _flag(side, "single_seat_locked"):
		return false
	if has_relic(side, "reserved_seat_tag") and is_relic_enabled(side, "reserved_seat_tag") and unit.active_slot_max - unit.active_slots_used == 1 and _enemy_has_interruptible(side) and not card_def.tags.has("interrupt"):
		return false
	return unit.active_slots_used + int(profile.get("slot_cost", card_def.active_slot_cost)) <= unit.active_slot_max and unit.shield >= int(profile.get("shield_cost", 0))


func after_commit(side: String, instance: ActiveCardInstance, card_def: CardDef, profile: Dictionary, shield_before: int) -> void:
	var flags: Dictionary = Dictionary(profile.get("flags", {}))
	instance.relic_effect_bonus = int(profile.get("effect_bonus", 0))
	instance.relic_recast_multiplier = float(profile.get("recast_multiplier", 1.0))
	instance.relic_recast_delta = float(profile.get("recast_delta", 0.0))
	instance.relic_flags = flags.duplicate(true)
	if flags.has("spent_empty_slot_charges"):
		_set_value(side, "empty_slot_charges", 0)
		_play_relic_proc(side, "vacancy_interest_meter")
	if flags.has("shield_discount_used"):
		_set_value(side, "shield_discount_tokens", maxi(0, _integer(side, "shield_discount_tokens") - int(flags["shield_discount_used"])))
		if int(flags["shield_discount_used"]) > 0:
			_play_relic_proc(side, "evaporation_recovery_valve")
	if flags.has("silent_clock"):
		_set_value(side, "empty_timeline_seconds", 0.0)
		_play_relic_proc(side, "silent_three_second_timer")
	if flags.has("single_seat"):
		_set_value(side, "single_seat_locked", true)
		_play_relic_proc(side, "single_seat_duel_sheath")
	if flags.has("full_load_latch"):
		_set_value(side, "full_load_used", true)
		_play_relic_proc(side, "full_load_latch")
	if has_relic(side, "dead_heat_needle"):
		var enemy_front: ActiveCardInstance = _front_instance(_opponent(side))
		if enemy_front != null:
			var difference: float = instance.scheduled_time - enemy_front.scheduled_time
			if difference >= 0.0 and difference <= 0.2 and _cooldown_ready(side, "dead_heat_needle", 5.0):
				instance.scheduled_time = enemy_front.scheduled_time
				instance.priority_modifier += 0.01
				instance.sort_key = instance.scheduled_time - instance.priority_modifier
	if has_relic(side, "residual_pressure_detonator") and shield_before > 0 and _state.get_unit(side).shield == 0 and _cooldown_ready(side, "residual_pressure_detonator", 6.0):
		var haste: float = minf(3.0, card_def.cast_time * 0.2)
		instance.shift_schedule(-haste, _state.battle_time)
	if instance.shield_cost_paid > 0 and has_relic(side, "memorial_fund_coil"):
		_set_value(side, "memorial_shield_spent", mini(24, _integer(side, "memorial_shield_spent") + instance.shield_cost_paid))


func was_forced_hazard_withdraw(side: String) -> bool:
	return _flag(side, "forced_hazard_withdraw")


func prepare_resolution_card(side: String, instance: ActiveCardInstance, card_def: CardDef) -> CardDef:
	var result: CardDef = CardDef.from_dict(card_def.to_dict())
	if instance.relic_effect_bonus != 0:
		_add_primary_effect(result, instance.relic_effect_bonus)
	if _integer(side, "next_attack_bonus") > 0 and card_def.tags.has("attack"):
		_add_primary_effect(result, _integer(side, "next_attack_bonus"))
		instance.relic_flags["consumed_next_attack_bonus"] = true
	if has_relic(side, "reversal_turbine"):
		_add_primary_effect(result, mini(4, floori(float(instance.relic_flags.get("reverse_seconds", 0.0)))))
	if bool(instance.relic_flags.get("overcharge_first", false)):
		_scale_numeric_effects(result, 1.4)
	if has_relic(side, "polarization_converter") and _relic_card(side, "polarization_converter") == card_def.id:
		_convert_attack_shield(result)
	if has_relic(side, "balanced_three_phase_unit") and _relic_card(side, "balanced_three_phase_unit") == card_def.id:
		_cap_primary_effects(result, 8)
	return result


func after_resolve(side: String, instance: ActiveCardInstance, card_def: CardDef, result: Dictionary) -> void:
	var unit: UnitState = _state.get_unit(side)
	if bool(instance.relic_flags.get("single_seat", false)):
		_set_value(side, "single_seat_locked", false)
	if not instance.is_auto_queued:
		_set_value(side, "manual_resolves", _integer(side, "manual_resolves") + 1)
		_handle_manual_sequences(side, instance, card_def)
	if has_relic(side, "full_slot_bell") and int(result.get("slots_before", 0)) >= 3 and unit.active_slots_used < 3 and _cooldown_ready(side, "full_slot_bell", 4.0):
		unit.add_shield(4)
	if has_relic(side, "terminal_echo_ring") and not instance.is_auto_queued and _state.get_active_instances_for_side(side).is_empty() and _cooldown_ready(side, "terminal_echo_ring", 4.0):
		_engine.reduce_cooldowns(side, 2.0, "last_used", instance.runtime_id)
	if instance.is_auto_queued:
		_handle_auto_resolution(side, instance)
	var defender_side: String = _opponent(side)
	if has_relic(defender_side, "full_absorption_gauge") and bool(result.get("fully_blocked", false)) and _integer(defender_side, "full_absorption_count") < 5 and _cooldown_ready(defender_side, "full_absorption_gauge", 4.0):
		_engine.reduce_cooldowns(defender_side, 1.5, "highest_cooldown")
		_set_value(defender_side, "full_absorption_count", _integer(defender_side, "full_absorption_count") + 1)
	if has_relic(side, "weight_ticket_punch") and card_def.loadout_cost == 5 and _integer(side, "heavyweight_count") < 3:
		_reduce_cooldowns_by_cost(side, 2.5, 1, 2)
		_set_value(side, "heavyweight_count", _integer(side, "heavyweight_count") + 1)
		_play_relic_proc(side, "weight_ticket_punch")
	if bool(instance.relic_flags.get("consumed_next_attack_bonus", false)):
		_set_value(side, "next_attack_bonus", 0)
	if has_relic(side, "overtake_signal") and bool(instance.relic_flags.get("overtook_enemy", false)) and _cooldown_ready(side, "overtake_signal", 5.0):
		unit.add_shield(3)
		_set_value(side, "next_attack_bonus", 2)
	for engraving_id: String in ["solar_pinion", "overcharge_confection_furnace", "polarization_converter", "balanced_three_phase_unit"]:
		if _relic_card(side, engraving_id) == card_def.id:
			_set_value(side, "engraved_used_%s" % engraving_id, true)


func after_interrupt(side: String, instance: ActiveCardInstance, card_def: CardDef, runtime_state: CardRuntimeState, slots_before: int) -> void:
	if bool(instance.relic_flags.get("single_seat", false)):
		_set_value(side, "single_seat_locked", false)
	if has_relic(side, "full_slot_bell") and slots_before >= 3 and _state.get_unit(side).active_slots_used < 3 and _cooldown_ready(side, "full_slot_bell", 4.0):
		_state.get_unit(side).add_shield(2)
	if runtime_state != null and has_relic(side, "rupture_insurance_film") and instance.shield_cost_paid > 0 and not _flag(side, "rupture_insurance_used"):
		_state.get_unit(side).add_shield(ceili(float(instance.shield_cost_paid) * 0.5))
		runtime_state.begin_cooldown(maxf(4.0, card_def.recast_time * 0.7))
		_set_value(side, "rupture_insurance_used", true)
		_play_relic_proc(side, "rupture_insurance_film")


func on_shield_decay(side: String, amount: int) -> void:
	if has_relic(side, "evaporation_recovery_valve"):
		var total: int = _integer(side, "natural_shield_decay") + amount
		var tokens: int = _integer(side, "shield_discount_tokens")
		var tokens_before: int = tokens
		while total >= 3 and tokens < 3:
			total -= 3
			tokens += 1
		_set_value(side, "natural_shield_decay", total)
		_set_value(side, "shield_discount_tokens", tokens)
		if tokens > tokens_before:
			_play_relic_proc(side, "evaporation_recovery_valve")


func on_status_event(side: String, event_data: Dictionary) -> void:
	var event_type: String = String(event_data.get("type", ""))
	var status_id: String = String(event_data.get("status", ""))
	if event_type == "status_damage" and status_id == "bleed" and has_relic(side, "bleed_pulsator") and _integer(side, "bleeding_pulses") < 6:
		if _engine.haste_active_cards(side, 0.8, "single") == 0:
			_engine.reduce_cooldowns(side, 0.8, "highest_cooldown")
		_set_value(side, "bleeding_pulses", _integer(side, "bleeding_pulses") + 1)
		_play_relic_proc(side, "bleed_pulsator")
	elif event_type == "status_expired" and NEGATIVE_STATUSES.has(status_id) and has_relic(_opponent(side), "critical_pathology_meter") and _cooldown_ready(_opponent(side), "critical_pathology_meter", 4.0):
		if status_id == "bleed":
			_state.get_unit(side).hp = maxi(0, _state.get_unit(side).hp - 1)
			_engine.prevent_lethal(side)
		else:
			_engine.delay_active_cards(side, 1.2, "single", _opponent(side))


func apply_status(source_side: String, target_side: String, status_id: String, duration: float) -> bool:
	if NEGATIVE_STATUSES.has(status_id) and has_relic(target_side, "quarantine_buffer") and not _flag(target_side, "quarantine_used"):
		_set_value(target_side, "quarantine_used", true)
		var unit: UnitState = _state.get_unit(target_side)
		unit.statuses[status_id] = {"duration": duration, "max_duration": duration, "tick_accumulator": 0.0, "suspended": 6.0}
		_play_relic_proc(target_side, "quarantine_buffer")
		return true
	_state.get_unit(target_side).add_status(status_id, duration)
	if has_relic(source_side, "four_symptom_seal") and not _flag(source_side, "four_symptom_used") and _has_four_symptoms(_state.get_unit(target_side)):
		_engine.apply_timeline_flow(source_side, {"target_side": "enemy", "mode": "stop", "duration": 2.0})
		for key: String in NEGATIVE_STATUSES:
			var data: Dictionary = Dictionary(_state.get_unit(target_side).statuses.get(key, {}))
			data["duration"] = maxf(0.0, float(data.get("duration", 0.0)) - 6.0)
			_state.get_unit(target_side).statuses[key] = data
		_set_value(source_side, "four_symptom_used", true)
		_play_relic_proc(source_side, "four_symptom_seal")
	return true


func remove_status(source_side: String, target_side: String, status_id: String) -> void:
	var unit: UnitState = _state.get_unit(target_side)
	var data: Dictionary = Dictionary(unit.statuses.get(status_id, {}))
	var remaining: float = float(data.get("duration", 0.0))
	unit.remove_status(status_id)
	if source_side == target_side and NEGATIVE_STATUSES.has(status_id) and remaining > 0.0 and has_relic(source_side, "symptom_transfer_paper") and _integer(source_side, "symptom_transfers") < 2:
		_state.get_opponent(source_side).add_status(status_id, remaining * 0.4)
		_set_value(source_side, "symptom_transfers", _integer(source_side, "symptom_transfers") + 1)
		_play_relic_proc(source_side, "symptom_transfer_paper")


func modify_timeline_flow(side: String, effect: Dictionary) -> Dictionary:
	var result: Dictionary = effect.duplicate(true)
	if has_relic(side, "paradox_mortgage"):
		var original: float = float(result.get("duration", 0.0))
		var extension: float = minf(2.0, original * 0.3)
		result["duration"] = original + extension
		_set_value(side, "paradox_recast_debt", _number(side, "paradox_recast_debt") + 6.0)
		_play_relic_proc(side, "paradox_mortgage")
	return result


func before_auto_queue(side: String) -> bool:
	if has_relic(side, "waste_heat_printer") and _integer(side, "auto_heat") >= 3:
		_set_value(side, "auto_heat", 0)
		_engine.reduce_cooldowns(side, 6.0, "highest_cooldown")
		_play_relic_proc(side, "waste_heat_printer")
		return false
	if has_relic(side, "isolation_chamber") and _flag(side, "isolation_occupied"):
		return false
	return true


func configure_auto_instance(side: String, source: ActiveCardInstance, instance: ActiveCardInstance) -> void:
	instance.source_card_id = source.source_card_id if source.source_card_id != "" else source.card_id
	if has_relic(side, "isolation_chamber"):
		instance.scheduled_time = _state.battle_time + maxf(0.0, instance.scheduled_time - _state.battle_time) * 0.8
		instance.slot_cost = 0
		instance.relic_flags["isolation"] = true
		_set_value(side, "isolation_occupied", true)
		_play_relic_proc(side, "isolation_chamber")


func on_timeline_shift(target_side: String, source_side: String, instance: ActiveCardInstance, actual_delta: float) -> void:
	if actual_delta > 0.0:
		instance.relic_delay_hits += 1
		if has_relic(target_side, "delay_return_gear"):
			instance.relic_delay_bank = minf(4.0, instance.relic_delay_bank + actual_delta * 0.5)
			_play_relic_proc(target_side, "delay_return_gear")
		if source_side != "" and source_side != target_side and has_relic(source_side, "borrowed_second_hand") and _cooldown_ready(source_side, "borrowed_second_hand", 6.0):
			_engine.haste_active_cards(source_side, minf(2.0, actual_delta * 0.35), "single")
		if source_side != "" and source_side != target_side and has_relic(source_side, "terminal_bell") and instance.relic_delay_hits >= 3:
			if _state.battle_time + 0.0001 >= _number(source_side, "cd_terminal_bell"):
				var triggered: bool = false
				if instance.interruptible:
					triggered = _engine.interrupt_instance(instance)
				else:
					instance.shift_schedule(3.0, _state.battle_time)
					triggered = true
				if triggered:
					instance.relic_delay_hits = 0
					_set_value(source_side, "cd_terminal_bell", _state.battle_time + 12.0)
	elif actual_delta < 0.0 and has_relic(target_side, "overtake_signal"):
		var enemy_front: ActiveCardInstance = _front_instance(_opponent(target_side))
		var before_shift: float = instance.scheduled_time - actual_delta
		if enemy_front != null and before_shift > enemy_front.scheduled_time and instance.scheduled_time <= enemy_front.scheduled_time:
			instance.relic_flags["overtook_enemy"] = true


func on_reverse_shift(side: String, instance: ActiveCardInstance, seconds: float) -> void:
	if has_relic(side, "reversal_turbine") and not instance.is_auto_queued:
		instance.relic_flags["reverse_seconds"] = minf(4.0, float(instance.relic_flags.get("reverse_seconds", 0.0)) + seconds)


func victory_gold_bonus(side: String) -> int:
	if not has_relic(side, "memorial_fund_coil"):
		return 0
	return mini(12, _integer(side, "memorial_shield_spent") / 2)


func has_relic(side: String, relic_id: String) -> bool:
	var run: RunState = _run(side)
	return run != null and run.relics.has(relic_id)


func is_relic_enabled(side: String, relic_id: String) -> bool:
	return bool(_value(side, "enabled_%s" % relic_id, true))


func set_relic_enabled(side: String, relic_id: String, enabled: bool) -> bool:
	if not has_relic(side, relic_id):
		return false
	_set_value(side, "enabled_%s" % relic_id, enabled)
	return true


func _handle_manual_sequences(side: String, instance: ActiveCardInstance, card_def: CardDef) -> void:
	var manual_count: int = _integer(side, "manual_resolves")
	if has_relic(side, "triplet_relay") and manual_count % 3 == 0 and _integer(side, "triple_meter_count") < 4:
		_engine.reduce_cooldowns(side, 4.0, "highest_cooldown", instance.runtime_id)
		_set_value(side, "triple_meter_count", _integer(side, "triple_meter_count") + 1)
		_play_relic_proc(side, "triplet_relay")
	if has_relic(side, "four_name_quartet"):
		var ids: Array = Array(_value(side, "distinct_manual_ids", []))
		if ids.has(card_def.id):
			ids = [card_def.id]
		else:
			ids.append(card_def.id)
		if ids.size() >= 4 and _integer(side, "four_name_count") < 3:
			_engine.reduce_cooldowns(side, 2.5, "all")
			_set_value(side, "four_name_count", _integer(side, "four_name_count") + 1)
			ids.clear()
			_play_relic_proc(side, "four_name_quartet")
		_set_value(side, "distinct_manual_ids", ids)
	if has_relic(side, "grade_staircase") and not _flag(side, "grade_staircase_used"):
		var expected: int = _integer(side, "grade_staircase_next")
		var grade: int = CardUpgradeResolver.get_tier(_run(side), card_def.id)
		if grade == expected:
			expected += 1
			if expected >= 4:
				_state.get_unit(side).add_shield(10)
				_engine.reduce_cooldowns(side, 3.0, "all")
				_set_value(side, "grade_staircase_used", true)
				expected = 0
				_play_relic_proc(side, "grade_staircase")
		else:
			expected = 1 if grade == 0 else 0
		_set_value(side, "grade_staircase_next", expected)
	if has_relic(side, "grade_differential_wheel"):
		var previous_grade: int = _integer(side, "previous_grade")
		var previous_time: float = _number(side, "previous_grade_time")
		var current_grade: int = CardUpgradeResolver.get_tier(_run(side), card_def.id)
		if previous_time > 0.0 and _state.battle_time - previous_time <= 8.0 and previous_grade > current_grade:
			var reduction: float = minf(4.5, float(previous_grade - current_grade) * 1.5)
			var runtime_state: CardRuntimeState = _state.get_unit(side).get_runtime_state(instance.runtime_id)
			if runtime_state != null:
				runtime_state.set_cooldown_remaining(runtime_state.cooldown_remaining - reduction)
				_play_relic_proc(side, "grade_differential_wheel")
		_set_value(side, "previous_grade", current_grade)
		_set_value(side, "previous_grade_time", _state.battle_time)


func _handle_auto_resolution(side: String, instance: ActiveCardInstance) -> void:
	if has_relic(side, "echo_rectifier") and instance.source_card_id != "":
		var counts: Dictionary = Dictionary(_value(side, "echo_source_counts", {}))
		var count: int = int(counts.get(instance.source_card_id, 0))
		if count < 3:
			_reduce_card_cooldown(side, instance.source_card_id, 1.5)
			counts[instance.source_card_id] = count + 1
			_set_value(side, "echo_source_counts", counts)
			_play_relic_proc(side, "echo_rectifier")
	if has_relic(side, "waste_heat_printer"):
		_set_value(side, "auto_heat", _integer(side, "auto_heat") + 1)
	if has_relic(side, "resin_memory_block") and instance.source_card_id != "":
		var counts: Dictionary = Dictionary(_value(side, "resin_counts", {}))
		var previous_count: int = int(counts.get(instance.source_card_id, 0))
		if previous_count < 5:
			counts[instance.source_card_id] = previous_count + 1
			_set_value(side, "resin_counts", counts)
			var source_card: CardDef = Database.get_card(instance.source_card_id)
			var modifier_stat: String = _primary_modifier_stat(source_card)
			if modifier_stat != "":
				_engine.add_battle_card_modifier(side, instance.source_card_id, modifier_stat, 1.0)
				_play_relic_proc(side, "resin_memory_block")
	if bool(instance.relic_flags.get("isolation", false)):
		_set_value(side, "isolation_occupied", false)


func _apply_engraving_profile(side: String, card_def: CardDef, profile: Dictionary) -> void:
	if has_relic(side, "solar_pinion") and _relic_card(side, "solar_pinion") == card_def.id:
		profile["cast_time"] = maxf(0.6, float(profile["cast_time"]) - 1.0)
		profile["recast_multiplier"] = float(profile["recast_multiplier"]) * 1.15
	if has_relic(side, "overcharge_confection_furnace") and _relic_card(side, "overcharge_confection_furnace") == card_def.id and not _flag(side, "engraved_used_overcharge_confection_furnace"):
		Dictionary(profile["flags"])["overcharge_first"] = true
		profile["recast_delta"] = maxf(float(profile["recast_delta"]), 60.0 - card_def.recast_time)
	if has_relic(side, "polarization_converter") and _relic_card(side, "polarization_converter") == card_def.id:
		profile["cast_time"] = float(profile["cast_time"]) + 0.6
	if has_relic(side, "balanced_three_phase_unit") and _relic_card(side, "balanced_three_phase_unit") == card_def.id:
		profile["slot_cost"] = 1
		profile["cast_time"] = 4.0
		profile["recast_delta"] = 30.0 - card_def.recast_time


func _update_compression_caliper(side: String) -> void:
	var unit: UnitState = _state.get_unit(side)
	unit.shield_decay_interval = 2.0 if has_relic(side, "compression_caliper") and unit.shield >= 12 else 1.0


func _cooldown_ready(side: String, key: String, duration: float) -> bool:
	var ready_at: float = _number(side, "cd_%s" % key)
	if _state.battle_time + 0.0001 < ready_at:
		return false
	_set_value(side, "cd_%s" % key, _state.battle_time + duration)
	_play_relic_proc(side, key)
	return true


func _play_relic_proc(side: String, relic_id: String) -> void:
	AudioManager.play_relic_proc(relic_id, 1.0 if side == "player" else 0.9)


func _reduce_card_cooldown(side: String, card_id: String, amount: float) -> void:
	for runtime_state: CardRuntimeState in _state.get_unit(side).card_runtime_states:
		if runtime_state.card_id == card_id and runtime_state.state == CardRuntimeState.CardState.COOLDOWN:
			runtime_state.set_cooldown_remaining(runtime_state.cooldown_remaining - amount)


func _reduce_cooldowns_by_cost(side: String, amount: float, min_cost: int, max_cost: int) -> void:
	for runtime_state: CardRuntimeState in _state.get_unit(side).card_runtime_states:
		var card: CardDef = Database.get_card(runtime_state.card_id)
		if card != null and card.loadout_cost >= min_cost and card.loadout_cost <= max_cost and runtime_state.state == CardRuntimeState.CardState.COOLDOWN:
			runtime_state.set_cooldown_remaining(runtime_state.cooldown_remaining - amount)


func _enemy_has_interruptible(side: String) -> bool:
	for instance: ActiveCardInstance in _state.get_active_instances_for_side(_opponent(side)):
		if instance.interruptible:
			return true
	return false


func _front_instance(side: String) -> ActiveCardInstance:
	var instances: Array[ActiveCardInstance] = _state.get_active_instances_for_side(side)
	if instances.is_empty():
		return null
	instances.sort_custom(func(a: ActiveCardInstance, b: ActiveCardInstance) -> bool: return a.scheduled_time < b.scheduled_time)
	return instances[0]


func _has_four_symptoms(unit: UnitState) -> bool:
	for status_id: String in NEGATIVE_STATUSES:
		if not unit.has_status(status_id):
			return false
	return true


func _primary_effect_amount(card_def: CardDef) -> int:
	for raw_effect: Dictionary in card_def.effects:
		var effect: Dictionary = Dictionary(raw_effect)
		if ["deal_damage", "gain_shield", "heal"].has(String(effect.get("type", ""))):
			return int(effect.get("amount", 0))
	return 0


func _primary_modifier_stat(card_def: CardDef) -> String:
	if card_def == null:
		return ""
	for raw_effect: Dictionary in card_def.effects:
		match String(raw_effect.get("type", "")):
			"deal_damage":
				return "damage"
			"gain_shield":
				return "shield"
			"heal":
				return "heal"
	return ""


func _add_primary_effect(card_def: CardDef, bonus: int) -> void:
	if bonus == 0:
		return
	var changed: bool = false
	for index: int in card_def.effects.size():
		var effect: Dictionary = Dictionary(card_def.effects[index])
		if not changed and ["deal_damage", "gain_shield", "heal"].has(String(effect.get("type", ""))):
			effect["amount"] = maxi(0, int(effect.get("amount", 0)) + bonus)
			card_def.effects[index] = effect
			changed = true


func _scale_numeric_effects(card_def: CardDef, multiplier: float) -> void:
	for index: int in card_def.effects.size():
		var effect: Dictionary = Dictionary(card_def.effects[index])
		if ["deal_damage", "gain_shield", "heal"].has(String(effect.get("type", ""))):
			effect["amount"] = maxi(0, roundi(float(effect.get("amount", 0)) * multiplier))
		card_def.effects[index] = effect


func _convert_attack_shield(card_def: CardDef) -> void:
	for index: int in card_def.effects.size():
		var effect: Dictionary = Dictionary(card_def.effects[index])
		var effect_type: String = String(effect.get("type", ""))
		if effect_type == "gain_shield":
			effect["type"] = "deal_damage"
			effect["target"] = "enemy"
			effect["amount"] = floori(float(effect.get("amount", 0)) * 0.65)
		elif effect_type == "deal_damage":
			effect["type"] = "gain_shield"
			effect["target"] = "self"
			effect["amount"] = floori(float(effect.get("amount", 0)) * 0.8)
		card_def.effects[index] = effect


func _cap_primary_effects(card_def: CardDef, cap: int) -> void:
	for index: int in card_def.effects.size():
		var effect: Dictionary = Dictionary(card_def.effects[index])
		if ["deal_damage", "gain_shield", "heal"].has(String(effect.get("type", ""))):
			effect["amount"] = mini(cap, int(effect.get("amount", 0)))
		card_def.effects[index] = effect


func _relic_card(side: String, relic_id: String) -> String:
	var run: RunState = _run(side)
	if run == null:
		return ""
	var relic_data: Dictionary = Dictionary(run.relic_state.get(relic_id, {}))
	return String(relic_data.get("card_id", ""))


func _hazard_wave(run: RunState) -> int:
	if run == null:
		return 0
	var active_id: String = String(run.map_state.get("active_node_id", ""))
	for raw_step: Variant in Array(run.map_state.get("steps", [])):
		for raw_node: Variant in Array(Dictionary(raw_step).get("nodes", [])):
			var node: Dictionary = Dictionary(raw_node)
			if String(node.get("id", "")) == active_id and String(node.get("type", "")) == "hazard":
				return int(node.get("hazard_cleared_waves", 0)) + 1
	return 0


func _is_discounted_base_card(run: RunState, card_id: String) -> bool:
	var base_seen: int = 0
	for equipped_id: String in run.equipped_cards:
		if CardUpgradeResolver.get_tier(run, equipped_id) != 0:
			continue
		base_seen += 1
		if equipped_id == card_id and base_seen >= 2 and base_seen <= 4:
			return true
	return false


func _mark_current_hazard_reward_lost(run: RunState) -> void:
	var active_id: String = String(run.map_state.get("active_node_id", ""))
	var steps: Array = Array(run.map_state.get("steps", []))
	for step_index: int in steps.size():
		var step: Dictionary = Dictionary(steps[step_index])
		var nodes: Array = Array(step.get("nodes", []))
		for node_index: int in nodes.size():
			var node: Dictionary = Dictionary(nodes[node_index])
			if String(node.get("id", "")) != active_id:
				continue
			node["hazard_current_reward_lost"] = true
			nodes[node_index] = node
			step["nodes"] = nodes
			steps[step_index] = step
			run.map_state["steps"] = steps
			return


func _run(side: String) -> RunState:
	return _runs.get(side) as RunState


func _side_state(side: String) -> Dictionary:
	var root: Dictionary = _state.relic_runtime_state
	var result: Dictionary = Dictionary(root.get(side, {}))
	root[side] = result
	_state.relic_runtime_state = root
	return result


func _value(side: String, key: String, default_value: Variant = null) -> Variant:
	return _side_state(side).get(key, default_value)


func _number(side: String, key: String) -> float:
	return float(_value(side, key, 0.0))


func _integer(side: String, key: String) -> int:
	return int(_value(side, key, 0))


func _flag(side: String, key: String) -> bool:
	return bool(_value(side, key, false))


func _set_value(side: String, key: String, value: Variant) -> void:
	var root: Dictionary = _state.relic_runtime_state
	var side_data: Dictionary = Dictionary(root.get(side, {}))
	side_data[key] = value
	root[side] = side_data
	_state.relic_runtime_state = root


func _opponent(side: String) -> String:
	return "enemy" if side == "player" else "player"
