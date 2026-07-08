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
	return true


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
