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
		unit.defense += 2
	if run_state.relics.has("surge_gimbal"):
		unit.speed += 1


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
