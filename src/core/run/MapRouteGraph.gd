extends RefCounted
class_name MapRouteGraph

const VERSION: int = 1
const CHAPTER_STEPS: int = 7


static func decorate(steps: Array, seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed ^ 0x51756575
	var mirrored: bool = false
	for step_index: int in steps.size():
		if step_index % CHAPTER_STEPS == 0:
			mirrored = rng.randf() < 0.5
		var nodes: Array = steps[step_index].get("nodes", [])
		var next: Array = steps[step_index + 1].get("nodes", []) if step_index + 1 < steps.size() else []
		var rightward: bool = rng.randf() < 0.5
		for index: int in nodes.size():
			var node: Dictionary = nodes[index]
			var lane: float = 0.5 if nodes.size() == 1 else lerpf(0.16, 0.84, float(index) / float(nodes.size() - 1))
			node["map_x"] = (1.0 - lane if mirrored else lane) + rng.randf_range(-0.025, 0.025)
			node["next_ids"] = _targets(index, nodes.size(), next, rightward)
			nodes[index] = node
		steps[step_index]["nodes"] = nodes


static func _targets(index: int, count: int, next: Array, rightward: bool) -> Array[String]:
	var targets: Array[String] = []
	if next.is_empty():
		return targets
	var indices: Array[int] = []
	if count == 1:
		for target: int in next.size(): indices.append(target)
	elif next.size() == 1:
		indices.append(0)
	elif count < next.size():
		indices = [index, index + 1]
	elif count > next.size():
		indices = [0] if index == 0 else ([next.size() - 1] if index == count - 1 else [0, 1])
	else:
		indices.append(index)
		var neighbor: int = index + (1 if rightward else -1)
		if neighbor >= 0 and neighbor < next.size(): indices.append(neighbor)
	for target: int in indices:
		if target < next.size(): targets.append(String(next[target]["id"]))
	return targets


static func migrate(map: Dictionary, seed: int) -> void:
	if int(map.get("graph_version", 0)) >= VERSION or bool(map.get("arena", false)):
		return
	var steps: Array = map.get("steps", [])
	decorate(steps, seed)
	var current: int = int(map.get("current_step", 0))
	# Preserve every historical choice and the options already offered by an older save.
	for index: int in mini(current + 1, steps.size()):
		if index == 0: continue
		var previous: Dictionary = chosen_node(steps[index - 1])
		if previous.is_empty(): continue
		var preserved: Array[String] = []
		for node: Dictionary in steps[index].get("nodes", []):
			if String(node.get("status", "")) in ["available", "selected", "completed"]:
				preserved.append(String(node["id"]))
		for id: String in preserved:
			if not Array(previous["next_ids"]).has(id): previous["next_ids"].append(id)
	map["steps"] = steps
	map["graph_version"] = VERSION


static func chosen_node(step: Dictionary) -> Dictionary:
	for node: Dictionary in step.get("nodes", []):
		if String(node.get("status", "")) in ["selected", "completed"]:
			return node
	return {}


static func allowed_ids(map: Dictionary, step_index: int) -> Array[String]:
	var steps: Array = map.get("steps", [])
	var ids: Array[String] = []
	if step_index < 0 or step_index >= steps.size(): return ids
	if step_index == 0:
		for node: Dictionary in steps[0].get("nodes", []): ids.append(String(node["id"]))
		return ids
	var previous: Dictionary = chosen_node(steps[step_index - 1])
	for id: Variant in previous.get("next_ids", []): ids.append(String(id))
	return ids


static func can_select(map: Dictionary, node_id: String) -> bool:
	if String(map.get("active_node_id", "")) != "": return false
	var current: int = int(map.get("current_step", 0))
	if not allowed_ids(map, current).has(node_id): return false
	var steps: Array = map.get("steps", [])
	if current < 0 or current >= steps.size(): return false
	for node: Dictionary in steps[current].get("nodes", []):
		if String(node["id"]) == node_id: return String(node.get("status", "")) == "available"
	return false


static func unlock(map: Dictionary, step_index: int) -> void:
	var steps: Array = map.get("steps", [])
	if step_index < 0 or step_index >= steps.size(): return
	var allowed: Array[String] = allowed_ids(map, step_index)
	for node: Dictionary in steps[step_index].get("nodes", []):
		if String(node.get("status", "")) in ["locked", "blocked", "available"]:
			node["status"] = "available" if allowed.has(String(node["id"])) else "blocked"
	map["steps"] = steps


static func minimum_route_weight(map: Dictionary, weight: Callable) -> float:
	var steps: Array = map.get("steps", [])
	var costs: Dictionary = {}
	for index: int in range(steps.size() - 1, -1, -1):
		var chosen: Dictionary = chosen_node(steps[index])
		var row_costs: Dictionary = {}
		for node: Dictionary in steps[index].get("nodes", []):
			if not chosen.is_empty() and node["id"] != chosen["id"]: continue
			var tail: float = 0.0 if index == steps.size() - 1 else INF
			for id: Variant in node.get("next_ids", []): tail = minf(tail, float(costs.get(String(id), INF)))
			row_costs[String(node["id"])] = float(weight.call(node)) + tail
		costs = row_costs
	var result: float = INF
	for cost: Variant in costs.values(): result = minf(result, float(cost))
	return result
