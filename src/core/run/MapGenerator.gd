extends RefCounted
class_name MapGenerator

const AREA_ONE_POOL := ["scout", "brute", "raider", "medic_drone"]
const AREA_THREE_POOL := ["brute", "guardian", "chronoguard", "raider"]


func generate_run(seed: int) -> Dictionary:
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
	_unlock_step_nodes(steps, 0)
	return {
		"current_step": 0,
		"active_node_id": "",
		"steps": steps,
	}


func _build_step(step_index: int, area: int, label_key: String, label: String, nodes: Array) -> Dictionary:
	return {
		"id": "step_%d" % step_index,
		"area": area,
		"label_key": label_key,
		"label": label,
		"nodes": nodes,
	}


func _build_normal_battle_choices(rng: RandomNumberGenerator, pool: Array, area: int, count: int) -> Array:
	var picked_enemies: Array[String] = []
	var bag: Array = pool.duplicate()
	while picked_enemies.size() < count and not bag.is_empty():
		var pick_index: int = rng.randi_range(0, bag.size() - 1)
		picked_enemies.append(String(bag[pick_index]))
		bag.remove_at(pick_index)

	var nodes: Array = []
	for node_index in range(picked_enemies.size()):
		var enemy_id: String = picked_enemies[node_index]
		nodes.append(_build_battle_node(area, node_index, area, "normal_battle", enemy_id, "map.node.enemy_name", _enemy_label(enemy_id)))
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
