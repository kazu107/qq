extends RefCounted
class_name RelicService

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func roll_random_relic(excluded_ids: Array[String], allowed_ids: Array[String] = []) -> String:
	var candidates: Array[String] = []
	for relic_id in Database.get_all_relic_ids():
		if not allowed_ids.is_empty() and not allowed_ids.has(relic_id):
			continue
		if excluded_ids.has(relic_id):
			continue
		candidates.append(relic_id)
	if candidates.is_empty():
		return ""
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func grant_relic(run_state: RunState, relic_id: String) -> bool:
	if run_state == null or relic_id == "" or run_state.relics.has(relic_id):
		return false

	run_state.relics.append(relic_id)
	match relic_id:
		"iron_plating":
			run_state.max_hp += 10
			run_state.player_hp = min(run_state.max_hp, run_state.player_hp + 10)
		"tempered_edge":
			run_state.attack += 1
		"kinetic_boots":
			run_state.speed += 1
		"auxiliary_core":
			run_state.loadout_limit += 2
		"titanium_rib":
			run_state.max_hp += 6
			run_state.player_hp = min(run_state.max_hp, run_state.player_hp + 6)
		"loadout_harness":
			run_state.loadout_limit += 3
		"war_cache":
			run_state.gold += 35
		"armor_garden":
			run_state.max_hp += 4
			run_state.player_hp = min(run_state.max_hp, run_state.player_hp + 4)
		"archive_compass":
			run_state.loadout_limit += 1
		"overtime_key":
			if run_state.arena_mode:
				run_state.arena_max_losses += 1
				run_state.arena_target_wins += 1
		"solar_pinion", "overcharge_confection_furnace", "polarization_converter", "balanced_three_phase_unit":
			_assign_engraved_card(run_state, relic_id)
	return true


static func get_effective_loadout_cost(run_state: RunState) -> int:
	if run_state == null:
		return 0
	return get_effective_loadout_cost_for_cards(run_state, run_state.equipped_cards)


static func get_effective_loadout_cost_for_cards(run_state: RunState, card_ids: Array[String]) -> int:
	if run_state == null:
		return 0
	var total: int = RunState.get_total_loadout_cost(card_ids)
	if not run_state.relics.has("unpolished_motherboard"):
		return total
	var base_count: int = 0
	for card_id: String in card_ids:
		if CardUpgradeResolver.get_tier(run_state, card_id) == 0:
			base_count += 1
	return maxi(0, total - mini(3, maxi(0, base_count - 1)))


static func get_allowed_loadout_overage(run_state: RunState) -> int:
	return 2 if run_state != null and run_state.relics.has("overload_seal") else 0


func apply_step_entry(run_state: RunState, step_number: int) -> String:
	if run_state == null or not run_state.relics.has("seven_step_validator") or not [7, 14, 21, 28].has(step_number):
		return ""
	var state: Dictionary = Dictionary(run_state.relic_state.get("seven_step_validator", {}))
	var claimed: Array = Array(state.get("claimed_steps", []))
	if claimed.has(step_number):
		return ""
	var best_id: String = ""
	var best_tier: int = CardUpgradeResolver.MAX_TIER + 1
	for card_id: String in run_state.equipped_cards:
		var tier: int = CardUpgradeResolver.get_tier(run_state, card_id)
		if tier < best_tier and tier < CardUpgradeResolver.MAX_TIER:
			best_id = card_id
			best_tier = tier
	if best_id == "":
		return ""
	run_state.card_upgrades[best_id] = best_tier + 1
	claimed.append(step_number)
	state["claimed_steps"] = claimed
	run_state.relic_state["seven_step_validator"] = state
	return best_id


func apply_infinite_cycle(run_state: RunState, cycle_number: int) -> String:
	if run_state == null or not run_state.relics.has("loop_wear_wheel") or cycle_number <= 1:
		return ""
	var state: Dictionary = Dictionary(run_state.relic_state.get("loop_wear_wheel", {}))
	var total: int = int(state.get("total_reduction", 0))
	if total >= 12:
		return ""
	var reductions: Dictionary = Dictionary(state.get("card_reductions", {}))
	var selected: String = ""
	var longest: float = -1.0
	for card_id: String in run_state.equipped_cards:
		var card: CardDef = Database.get_card(card_id)
		if card == null or int(reductions.get(card_id, 0)) >= 4:
			continue
		if card.recast_time > longest:
			longest = card.recast_time
			selected = card_id
	if selected == "":
		return ""
	reductions[selected] = int(reductions.get(selected, 0)) + 1
	state["card_reductions"] = reductions
	state["total_reduction"] = total + 1
	run_state.relic_state["loop_wear_wheel"] = state
	var modifiers: Dictionary = Dictionary(run_state.temporary_card_modifiers.get(selected, {}))
	modifiers["recast_time"] = float(modifiers.get("recast_time", 0.0)) - 1.0
	run_state.temporary_card_modifiers[selected] = modifiers
	return selected


func _assign_engraved_card(run_state: RunState, relic_id: String) -> void:
	var selected: String = ""
	var longest_cast: float = -1.0
	for card_id: String in run_state.equipped_cards:
		var card: CardDef = Database.get_card(card_id)
		if card == null:
			continue
		var eligible: bool = true
		if relic_id == "polarization_converter":
			var has_damage: bool = false
			var has_shield: bool = false
			for effect: Dictionary in card.effects:
				has_damage = has_damage or String(effect.get("type", "")) == "deal_damage"
				has_shield = has_shield or String(effect.get("type", "")) == "gain_shield"
			eligible = has_damage != has_shield
		elif relic_id == "balanced_three_phase_unit":
			eligible = card.active_slot_cost >= 2 or card.cast_time >= 6.0 or card.recast_time >= 30.0
		if eligible and card.cast_time > longest_cast:
			selected = card_id
			longest_cast = card.cast_time
	if selected == "" and not run_state.equipped_cards.is_empty():
		selected = run_state.equipped_cards[0]
	run_state.relic_state[relic_id] = {"card_id": selected}


func apply_battle_modifiers(unit: UnitState, run_state: RunState) -> void:
	if unit == null or run_state == null:
		return
	if run_state.relics.has("reactive_barrier"):
		unit.add_shield(6)
	if run_state.relics.has("chrono_shard"):
		unit.cast_time_modifier *= 0.9
	if run_state.relics.has("war_banner"):
		unit.attack += 2
	if run_state.relics.has("aegis_matrix"):
		unit.add_shield(8)
	if run_state.relics.has("surge_gimbal"):
		unit.speed += 1
	if run_state.relics.has("phase_capacitor"):
		unit.add_shield(12)
	if run_state.relics.has("paradox_prism"):
		unit.cast_time_modifier *= 0.92
		unit.speed += 1
	if run_state.relics.has("rift_compass"):
		unit.speed += 2
	if run_state.relics.has("omega_crown"):
		unit.attack += 3
	if run_state.relics.has("eternity_engine"):
		unit.cast_time_modifier *= 0.85
		unit.add_shield(10)
	if run_state.relics.has("signal_lens"):
		unit.attack += 1
		unit.cast_time_modifier *= 0.97
	if run_state.relics.has("pulse_injector"):
		unit.speed += 2
	if run_state.relics.has("barrier_seed"):
		unit.add_shield(5)
		unit.speed += 1
	if run_state.relics.has("stasis_clock"):
		unit.cast_time_modifier *= 0.94
	if run_state.relics.has("blood_pump"):
		unit.attack += 1
	if run_state.relics.has("emergency_foam"):
		unit.add_shield(16)
	if run_state.relics.has("overclock_key"):
		unit.attack += 2
		unit.speed += 1
	if run_state.relics.has("chrono_metronome"):
		unit.cast_time_modifier *= 0.88
	if run_state.relics.has("armor_garden"):
		unit.add_shield(4)
	if run_state.relics.has("bounty_drone"):
		unit.speed += 1
	if run_state.relics.has("prism_furnace"):
		unit.attack += 1
		unit.add_shield(8)
		unit.cast_time_modifier *= 0.96


func apply_victory_bonuses(run_state: RunState) -> Dictionary:
	var bonus: Dictionary = {
		"gold": 0,
		"heal": 0,
	}
	if run_state == null:
		return bonus
	if run_state.relics.has("salvage_magnet"):
		bonus["gold"] = int(bonus.get("gold", 0)) + 10
	if run_state.relics.has("repair_nanites"):
		bonus["heal"] = int(bonus.get("heal", 0)) + 5
	if run_state.relics.has("echo_coil"):
		bonus["gold"] = int(bonus.get("gold", 0)) + 15
	if run_state.relics.has("entropy_battery"):
		bonus["heal"] = int(bonus.get("heal", 0)) + 8
	if run_state.relics.has("blood_pump"):
		bonus["heal"] = int(bonus.get("heal", 0)) + 4
	if run_state.relics.has("scavenger_contract"):
		bonus["gold"] = int(bonus.get("gold", 0)) + 20
	if run_state.relics.has("armor_garden"):
		bonus["heal"] = int(bonus.get("heal", 0)) + 3
	if run_state.relics.has("bounty_drone"):
		bonus["gold"] = int(bonus.get("gold", 0)) + 12
	if run_state.relics.has("archive_compass"):
		bonus["gold"] = int(bonus.get("gold", 0)) + 8
		bonus["heal"] = int(bonus.get("heal", 0)) + 2
	run_state.gold += int(bonus.get("gold", 0))
	run_state.player_hp = min(run_state.max_hp, run_state.player_hp + int(bonus.get("heal", 0)))
	return bonus


func get_relic_names(relic_ids: Array[String]) -> Array[String]:
	var names: Array[String] = []
	for relic_id in relic_ids:
		var relic_def: RelicDef = Database.get_relic(relic_id)
		if relic_def == null:
			names.append(relic_id)
		else:
			names.append(relic_def.name)
	return names
