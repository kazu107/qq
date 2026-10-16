extends RefCounted
class_name InfiniteScoreResolver

const VERSION: int = 1
const STEP_POINTS: int = 1000
const BOSS_POINTS: int = 2000
const ELITE_POINTS: int = 300
const HAZARD_POINTS: int = 500
const EFFICIENCY_POINTS: int = 100
const CATEGORIES: Array[String] = ["progress", "boss", "challenge", "efficiency"]


func start_fresh(run: RunState) -> void:
	run.infinite_score = {"version": VERSION, "totals": {"progress": 0, "boss": 0, "challenge": 0, "efficiency": 0}, "awards": {}}


static func cycle_for_step(step_index: int) -> int:
	return maxi(1, floori(float(maxi(0, step_index)) / MapGenerator.INFINITE_STEP_SPAN) + 1)


static func multiplier(cycle: int) -> float:
	return 1.0 + 0.25 * float(maxi(1, cycle) - 1)


static func par_time(enemy_id: String, cycle: int) -> float:
	return float(RunScoreResolver.ENEMY_PAR_TIMES.get(enemy_id, 60.0)) * RealtimeBattleEngine.get_infinite_hp_multiplier(maxi(1, cycle))


func ensure_initialized(run: RunState) -> void:
	if int(run.infinite_score.get("version", 0)) == VERSION:
		return
	start_fresh(run)
	var expected: Array[Dictionary] = []
	var steps: Array = Array(run.map_state.get("steps", []))
	var completed: int = clampi(int(run.map_state.get("current_step", 0)), 0, steps.size())
	for index: int in steps.size():
		var node: Dictionary = MapRouteGraph.chosen_node(Dictionary(steps[index]))
		var cycle: int = cycle_for_step(index)
		if index < completed:
			_award(run, "step:%d" % index, "progress", STEP_POINTS, cycle)
			if node.get("type", "") == "boss":
				_award(run, "boss:" + String(node.get("id", "")), "boss", BOSS_POINTS, cycle)
			elif node.get("type", "") == "elite_battle":
				_award(run, "elite:" + String(node.get("id", "")), "challenge", ELITE_POINTS, cycle)
			_award_hazard(run, node, cycle)
		if node.is_empty() or index > completed:
			continue
		var type: String = String(node.get("type", ""))
		if type == "hazard":
			var queue: Array = Array(node.get("hazard_queue", []))
			var count: int = mini(queue.size(), int(node.get("hazard_cleared_waves", 0)) + (1 if index == completed else 0))
			for wave: int in count:
				expected.append(_battle_context(node, index, wave + 1, String(queue[wave])))
		elif type in ["normal_battle", "elite_battle", "boss"]:
			var enemies: Array[String] = EncounterSeries.queue(node)
			var count: int = enemies.size() if index < completed else mini(enemies.size(), EncounterSeries.cleared(node) + 1)
			for encounter: int in count:
				expected.append(_battle_context(node, index, encounter + 1 if enemies.size() > 1 else 0, enemies[encounter]))
	# Older histories lack node/wave IDs. Match only identifiable encounters in saved route order.
	var cursor: int = 0
	for battle: Dictionary in run.battle_history:
		var match_index: int = -1
		for index: int in range(cursor, expected.size()):
			var context: Dictionary = expected[index]
			if battle.has("node_id"):
				if String(battle["node_id"]) != String(context["node_id"]) or int(battle.get("wave", 0)) != int(context["wave"]):
					continue
			elif String(battle.get("enemy_id", "")) != String(context["enemy_id"]) or String(battle.get("node_type", "")) != String(context["node_type"]):
				continue
			match_index = index
			break
		if match_index < 0:
			continue
		var entry: Dictionary = battle.duplicate(true)
		entry.merge(expected[match_index], false)
		_record_battle(run, entry)
		cursor = match_index + 1
	run.infinite_score["migrated"] = true


func _battle_context(node: Dictionary, step_index: int, wave: int, enemy_id: String) -> Dictionary:
	return {"node_id": String(node.get("id", "")), "node_type": String(node.get("type", "")),
		"step_index": step_index, "cycle": cycle_for_step(step_index), "wave": wave, "enemy_id": enemy_id}


func record_battle(run: RunState, battle: Dictionary) -> void:
	ensure_initialized(run)
	_record_battle(run, battle)


func was_result_recorded(run: RunState, context: Dictionary) -> bool:
	ensure_initialized(run)
	return Dictionary(run.infinite_score["awards"]).has(_result_key(context))


func _result_key(context: Dictionary) -> String:
	return "result:%s:%d" % [String(context.get("node_id", "")), int(context.get("wave", 0))]


func _record_battle(run: RunState, battle: Dictionary) -> void:
	var node_id: String = String(battle.get("node_id", ""))
	var step_index: int = int(battle.get("step_index", -1))
	if node_id == "" or step_index < 0:
		return
	var seen: Dictionary = Dictionary(run.infinite_score["awards"])
	var result_key: String = _result_key(battle)
	if seen.has(result_key):
		return
	seen[result_key] = true
	run.infinite_score["awards"] = seen
	if String(battle.get("winner", "")) != "player" or bool(battle.get("forced_hazard_withdraw", false)):
		return
	var cycle: int = cycle_for_step(step_index)
	var type: String = String(battle.get("node_type", ""))
	if type == "boss":
		_award(run, "boss:" + node_id, "boss", BOSS_POINTS, cycle)
	elif type == "elite_battle":
		_award(run, "elite:" + node_id, "challenge", ELITE_POINTS, cycle)
	var time: float = float(battle.get("battle_time", 0.0))
	var ratio: float = 0.0
	if time > 0.0:
		ratio = clampf(2.0 - time / par_time(String(battle.get("enemy_id", "")), cycle), 0.0, 1.0)
	_award(run, "efficiency:%s:%d" % [node_id, int(battle.get("wave", 0))], "efficiency", roundi(EFFICIENCY_POINTS * ratio), cycle)


func record_step(run: RunState, node: Dictionary, step_index: int) -> void:
	ensure_initialized(run)
	var cycle: int = cycle_for_step(step_index)
	_award(run, "step:%d" % step_index, "progress", STEP_POINTS, cycle)
	_award_hazard(run, node, cycle)


func _award_hazard(run: RunState, node: Dictionary, cycle: int) -> void:
	var waves: int = Array(node.get("hazard_queue", [])).size()
	if node.get("type", "") == "hazard" and waves > 0 and int(node.get("hazard_cleared_waves", 0)) >= waves:
		_award(run, "hazard:" + String(node.get("id", "")), "challenge", HAZARD_POINTS, cycle)


func _award(run: RunState, key: String, category: String, base_points: int, cycle: int) -> void:
	var awards: Dictionary = Dictionary(run.infinite_score["awards"])
	if awards.has(key):
		return
	awards[key] = true
	var totals: Dictionary = Dictionary(run.infinite_score["totals"])
	totals[category] = int(totals.get(category, 0)) + maxi(0, roundi(float(base_points) * multiplier(cycle)))
	run.infinite_score["awards"] = awards
	run.infinite_score["totals"] = totals


func calculate(run: RunState) -> Dictionary:
	ensure_initialized(run)
	var totals: Dictionary = Dictionary(run.infinite_score["totals"])
	var total: int = 0
	for category: String in CATEGORIES:
		total += int(totals.get(category, 0))
	var completed: int = maxi(0, int(run.map_state.get("current_step", 0)))
	var result: Dictionary = {"score_mode": "infinite", "infinite_mode": true, "rank": "", "cleared": false,
		"total_score": total, "max_score": 0, "category_ids": CATEGORIES.duplicate(),
		"completed_steps": completed, "completed_cycles": floori(float(completed) / MapGenerator.INFINITE_STEP_SPAN),
		"reached_step": completed + 1, "reached_cycle": cycle_for_step(completed),
		"step_in_cycle": completed % MapGenerator.INFINITE_STEP_SPAN + 1,
		"score_preview": bool(run.infinite_score.get("preview", false)), "score_version": VERSION}
	for category: String in CATEGORIES:
		result[category] = int(totals.get(category, 0))
		# Shared visual scale represents contribution, not a score cap.
		result[category + "_max"] = maxi(1, total)
	return result


func build_preview_run(completed_steps: int = 35) -> RunState:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 424242)
	run.infinite_mode = true
	run.map_state = MapGenerator.new().generate_infinite_run(run.seed)
	while Array(run.map_state["steps"]).size() <= completed_steps:
		MapGenerator.new().append_infinite_cycle(run.map_state, run.seed)
	start_fresh(run)
	run.infinite_score["preview"] = true
	for index: int in completed_steps:
		var steps: Array = Array(run.map_state["steps"])
		var nodes: Array = Array(steps[index]["nodes"])
		var allowed: Array[String] = MapRouteGraph.allowed_ids(run.map_state, index)
		var chosen: int = 0
		var lowest: int = 999
		for option: int in nodes.size():
			if not allowed.has(String(nodes[option]["id"])):
				continue
			var priority: int = 0 if nodes[option]["type"] not in ["hazard", "elite_battle"] else 1
			if priority < lowest:
				lowest = priority
				chosen = option
		var node: Dictionary = nodes[chosen]
		var type: String = String(node["type"])
		if type == "hazard":
			node["hazard_queue"] = ["scout", "brute"]
			node["hazard_cleared_waves"] = 2
		if type in ["normal_battle", "boss", "elite_battle", "hazard"]:
			var enemies: Array = Array(node["hazard_queue"]) if type == "hazard" else [String(node["enemy_id"])]
			for wave: int in enemies.size():
				var battle: Dictionary = _battle_context(node, index, wave + 1 if type == "hazard" else 0, String(enemies[wave]))
				battle.merge({"winner": "player", "battle_time": par_time(String(enemies[wave]), cycle_for_step(index))})
				run.battle_history.append(battle)
				record_battle(run, battle)
		record_step(run, node, index)
		for option: int in nodes.size():
			nodes[option]["status"] = "completed" if option == chosen else "skipped"
		run.map_state["current_step"] = index + 1
	run.run_complete = true
	run.defeated = true
	run.player_hp = 0
	run.current_area = int(run.map_state["steps"][completed_steps].get("area", 1))
	run.encounters_cleared = run.battle_history.size()
	run.hp_damage_taken = run.max_hp
	return run
