extends RefCounted
class_name MapGenerator

const AREA_ONE_POOL := ["scout", "brute", "raider", "medic_drone"]
const AREA_THREE_POOL := ["brute", "guardian", "chronoguard", "raider"]
const AREA_FOUR_POOL := ["phase_stalker", "echo_revenant"]
const AREA_SIX_POOL := ["phase_stalker", "void_bastion", "echo_revenant"]
const AREA_SEVEN_POOL := ["rift_predator", "entropy_colossus"]
const AREA_NINE_POOL := ["rift_predator", "entropy_colossus"]
const AREA_TEN_POOL := ["omega_seraph", "grave_architect"]
const AREA_TWELVE_POOL := ["omega_seraph", "grave_architect"]
const MAX_IMPLEMENTED_STEP_TIER: int = 4


func generate_run(seed: int, unlocked_step_tier: int = 1) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed

	var steps: Array = [
		_build_step(0, 1, "map.step.area1_encounter", "Area 1 Encounter", _build_normal_battle_choices(rng, AREA_ONE_POOL, 1, 2)),
		_build_step(1, 1, "map.step.area1_recovery", "Area 1 Recovery", [
			_build_non_battle_node(1, 0, 1, "heal", "map.node.repair_bay", "Repair Bay"),
			_build_non_battle_node(1, 1, 1, "shop", "map.node.field_shop", "Field Shop"),
		]),
		_build_step(2, 2, "map.step.area2_challenge", "Area 2 Challenge", [
			_build_battle_node(2, 0, 2, "elite_battle", "guardian", "map.node.elite_enemy", "Elite Guardian"),
			_build_non_battle_node(2, 1, 2, "hazard", "map.node.hazard_zone", "Hazard Zone"),
		]),
		_build_step(3, 2, "map.step.area2_support", "Area 2 Support", [
			_build_non_battle_node(3, 0, 2, "forge", "map.node.forge", "Forge"),
			_build_non_battle_node(3, 1, 2, "event", "map.node.unknown_signal", "Unknown Signal"),
		]),
		_build_step(4, 3, "map.step.area3_clash", "Area 3 Clash", [
			_build_battle_node(4, 0, 3, "normal_battle", _pick_enemy(rng, AREA_THREE_POOL), "map.node.enemy_name", "Frontline Battle"),
			_build_battle_node(4, 1, 3, "elite_battle", "chronoguard", "map.node.elite_enemy", "Elite Chronoguard"),
		]),
		_build_step(5, 3, "map.step.area3_recovery", "Area 3 Recovery", [
			_build_non_battle_node(5, 0, 3, "heal", "map.node.emergency_medbay", "Emergency Medbay"),
			_build_non_battle_node(5, 1, 3, "shop", "map.node.final_shop", "Final Shop"),
			_build_non_battle_node(5, 2, 3, "event", "map.node.archive_echo", "Archive Echo"),
		]),
		_build_step(6, 3, "map.step.final_boss", "Final Boss", [
			_build_battle_node(6, 0, 3, "boss", "boss_timekeeper", "map.node.boss_enemy", "Timekeeper"),
		]),
	]
	if unlocked_step_tier >= 2:
		_mark_step_as_gate(steps, 6, "map.step.timekeeper_gate", "Timekeeper Gate")
		steps.append_array(_build_tier_two_steps(rng))
	if unlocked_step_tier >= 3:
		_mark_step_as_gate(steps, 13, "map.step.paradox_gate", "Paradox Gate")
		steps.append_array(_build_tier_three_steps(rng))
	if unlocked_step_tier >= 4:
		_mark_step_as_gate(steps, 20, "map.step.axiom_gate", "Axiom Gate")
		steps.append_array(_build_tier_four_steps(rng))
	_unlock_step_nodes(steps, 0)
	return {
		"current_step": 0,
		"active_node_id": "",
		"steps": steps,
	}


func _build_tier_two_steps(rng: RandomNumberGenerator) -> Array:
	return [
		_build_step(7, 4, "map.step.area4_breach", "Area 4 Phase Breach", _build_normal_battle_choices(rng, AREA_FOUR_POOL, 4, 2, 7)),
		_build_step(8, 4, "map.step.area4_support", "Area 4 Recovery", [
			_build_non_battle_node(8, 0, 4, "shop", "map.node.phase_exchange", "Phase Exchange"),
			_build_non_battle_node(8, 1, 4, "event", "map.node.echo_signal", "Echo Signal"),
		]),
		_build_step(9, 5, "map.step.area5_trial", "Area 5 Void Trial", [
			_build_battle_node(9, 0, 5, "elite_battle", "void_bastion", "map.node.elite_enemy", "Elite Void Bastion"),
			_build_non_battle_node(9, 1, 5, "hazard", "map.node.paradox_storm", "Paradox Storm"),
		]),
		_build_step(10, 5, "map.step.area5_support", "Area 5 Refit", [
			_build_non_battle_node(10, 0, 5, "forge", "map.node.void_forge", "Void Forge"),
			_build_non_battle_node(10, 1, 5, "heal", "map.node.phase_shelter", "Phase Shelter"),
		]),
		_build_step(11, 6, "map.step.area6_clash", "Area 6 Paradox Front", [
			_build_battle_node(11, 0, 6, "normal_battle", _pick_enemy(rng, AREA_SIX_POOL), "map.node.enemy_name", "Paradox Front"),
			_build_battle_node(11, 1, 6, "elite_battle", "echo_revenant", "map.node.elite_enemy", "Elite Echo Revenant"),
		]),
		_build_step(12, 6, "map.step.area6_recovery", "Area 6 Final Calibration", [
			_build_non_battle_node(12, 0, 6, "shop", "map.node.paradox_market", "Paradox Market"),
			_build_non_battle_node(12, 1, 6, "event", "map.node.core_memory", "Core Memory"),
			_build_non_battle_node(12, 2, 6, "heal", "map.node.last_anchor", "Last Anchor"),
		]),
		_build_step(13, 6, "map.step.paradox_core", "Paradox Core", [
			_build_battle_node(13, 0, 6, "boss", "boss_paradox_core", "map.node.boss_enemy", "Paradox Core"),
		]),
	]


func _build_tier_three_steps(rng: RandomNumberGenerator) -> Array:
	return [
		_build_step(14, 7, "map.step.area7_rift", "Area 7 Rift Pursuit", _build_normal_battle_choices(rng, AREA_SEVEN_POOL, 7, 2, 14)),
		_build_step(15, 7, "map.step.area7_support", "Area 7 Rift Anchorage", [
			_build_non_battle_node(15, 0, 7, "shop", "map.node.rift_exchange", "Rift Exchange"),
			_build_non_battle_node(15, 1, 7, "event", "map.node.fractured_beacon", "Fractured Beacon"),
		]),
		_build_step(16, 8, "map.step.area8_trial", "Area 8 Entropy Trial", [
			_build_battle_node(16, 0, 8, "elite_battle", "entropy_colossus", "map.node.elite_enemy", "Elite Entropy Colossus"),
			_build_non_battle_node(16, 1, 8, "hazard", "map.node.entropy_surge", "Entropy Surge"),
		]),
		_build_step(17, 8, "map.step.area8_support", "Area 8 Axiom Refit", [
			_build_non_battle_node(17, 0, 8, "forge", "map.node.axiom_forge", "Axiom Forge"),
			_build_non_battle_node(17, 1, 8, "heal", "map.node.rift_shelter", "Rift Shelter"),
		]),
		_build_step(18, 9, "map.step.area9_clash", "Area 9 Broken Axiom", [
			_build_battle_node(18, 0, 9, "normal_battle", _pick_enemy(rng, AREA_NINE_POOL), "map.node.enemy_name", "Broken Axiom"),
			_build_battle_node(18, 1, 9, "elite_battle", "rift_predator", "map.node.elite_enemy", "Elite Rift Predator"),
		]),
		_build_step(19, 9, "map.step.area9_recovery", "Area 9 Final Proof", [
			_build_non_battle_node(19, 0, 9, "shop", "map.node.axiom_market", "Axiom Market"),
			_build_non_battle_node(19, 1, 9, "event", "map.node.proof_archive", "Proof Archive"),
			_build_non_battle_node(19, 2, 9, "heal", "map.node.last_theorem", "Last Theorem"),
		]),
		_build_step(20, 9, "map.step.axiom_breaker", "Axiom Breaker", [
			_build_battle_node(20, 0, 9, "boss", "boss_axiom_breaker", "map.node.boss_enemy", "Axiom Breaker"),
		]),
	]


func _build_tier_four_steps(rng: RandomNumberGenerator) -> Array:
	return [
		_build_step(21, 10, "map.step.area10_omega", "Area 10 Omega Descent", _build_normal_battle_choices(rng, AREA_TEN_POOL, 10, 2, 21)),
		_build_step(22, 10, "map.step.area10_support", "Area 10 Omega Anchorage", [
			_build_non_battle_node(22, 0, 10, "shop", "map.node.omega_exchange", "Omega Exchange"),
			_build_non_battle_node(22, 1, 10, "event", "map.node.seraph_signal", "Seraph Signal"),
		]),
		_build_step(23, 11, "map.step.area11_trial", "Area 11 Grave Trial", [
			_build_battle_node(23, 0, 11, "elite_battle", "grave_architect", "map.node.elite_enemy", "Elite Grave Architect"),
			_build_non_battle_node(23, 1, 11, "hazard", "map.node.zero_storm", "Zero Storm"),
		]),
		_build_step(24, 11, "map.step.area11_support", "Area 11 Eternity Refit", [
			_build_non_battle_node(24, 0, 11, "forge", "map.node.eternity_forge", "Eternity Forge"),
			_build_non_battle_node(24, 1, 11, "heal", "map.node.omega_shelter", "Omega Shelter"),
		]),
		_build_step(25, 12, "map.step.area12_clash", "Area 12 End of Time", [
			_build_battle_node(25, 0, 12, "normal_battle", _pick_enemy(rng, AREA_TWELVE_POOL), "map.node.enemy_name", "End of Time"),
			_build_battle_node(25, 1, 12, "elite_battle", "omega_seraph", "map.node.elite_enemy", "Elite Omega Seraph"),
		]),
		_build_step(26, 12, "map.step.area12_recovery", "Area 12 Final Continuum", [
			_build_non_battle_node(26, 0, 12, "shop", "map.node.eternity_market", "Eternity Market"),
			_build_non_battle_node(26, 1, 12, "event", "map.node.zero_archive", "Zero Archive"),
			_build_non_battle_node(26, 2, 12, "heal", "map.node.last_continuum", "Last Continuum"),
		]),
		_build_step(27, 12, "map.step.eternity_zero", "Eternity Zero", [
			_build_battle_node(27, 0, 12, "boss", "boss_eternity_zero", "map.node.boss_enemy", "Eternity Zero"),
		]),
	]


func _mark_step_as_gate(steps: Array, step_index: int, label_key: String, label: String) -> void:
	if step_index < 0 or step_index >= steps.size():
		return
	var gate_step: Dictionary = Dictionary(steps[step_index])
	gate_step["label_key"] = label_key
	gate_step["label"] = label
	steps[step_index] = gate_step


func _build_step(step_index: int, area: int, label_key: String, label: String, nodes: Array) -> Dictionary:
	return {
		"id": "step_%d" % step_index,
		"area": area,
		"label_key": label_key,
		"label": label,
		"nodes": nodes,
	}


func _build_normal_battle_choices(rng: RandomNumberGenerator, pool: Array, area: int, count: int, seed_offset: int = -1) -> Array:
	var picked_enemies: Array[String] = []
	var bag: Array = pool.duplicate()
	while picked_enemies.size() < count and not bag.is_empty():
		var pick_index: int = rng.randi_range(0, bag.size() - 1)
		picked_enemies.append(String(bag[pick_index]))
		bag.remove_at(pick_index)

	var nodes: Array = []
	var resolved_seed_offset: int = area if seed_offset < 0 else seed_offset
	for node_index in range(picked_enemies.size()):
		var enemy_id: String = picked_enemies[node_index]
		nodes.append(_build_battle_node(resolved_seed_offset, node_index, area, "normal_battle", enemy_id, "map.node.enemy_name", _enemy_label(enemy_id)))
	return nodes


func _build_non_battle_node(seed_offset: int, node_index: int, area: int, node_type: String, label_key: String, label: String) -> Dictionary:
	return {
		"id": "%s_%d_%d" % [node_type, seed_offset, node_index],
		"type": node_type,
		"label_key": label_key,
		"label": label,
		"area": area,
		"status": "locked",
	}


func _build_battle_node(seed_offset: int, node_index: int, area: int, node_type: String, enemy_id: String, label_key: String, label: String) -> Dictionary:
	return {
		"id": "battle_%d_%d" % [seed_offset, node_index],
		"type": node_type,
		"label_key": label_key,
		"label": label,
		"label_args": {
			"enemy_id": enemy_id,
		},
		"enemy_id": enemy_id,
		"area": area,
		"status": "locked",
	}


func _pick_enemy(rng: RandomNumberGenerator, pool: Array) -> String:
	if pool.is_empty():
		return "scout"
	return String(pool[rng.randi_range(0, pool.size() - 1)])


func _enemy_label(enemy_id: String) -> String:
	var enemy_def: EnemyDef = Database.get_enemy(enemy_id)
	if enemy_def == null:
		return enemy_id.capitalize()
	return enemy_def.name


func _unlock_step_nodes(steps: Array, step_index: int) -> void:
	if step_index < 0 or step_index >= steps.size():
		return
	var step_data: Dictionary = Dictionary(steps[step_index])
	var nodes: Array = Array(step_data.get("nodes", []))
	for node_index in range(nodes.size()):
		var node_data: Dictionary = Dictionary(nodes[node_index])
		node_data["status"] = "available"
		nodes[node_index] = node_data
	step_data["nodes"] = nodes
	steps[step_index] = step_data
