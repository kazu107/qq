extends Node

var _three_way_branches: int = 0


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		push_error("Node map: " + message)
		get_tree().quit(1)
		assert(value, message)


func _validate(map: Dictionary) -> void:
	var steps: Array = map["steps"]
	var seen: Dictionary = {}
	var incoming: Dictionary = {}
	for index: int in steps.size():
		var next_ids: Array = []
		if index + 1 < steps.size():
			for node: Dictionary in steps[index + 1]["nodes"]: next_ids.append(String(node["id"]))
		for node: Dictionary in steps[index]["nodes"]:
			var id: String = String(node["id"])
			_check(not seen.has(id), "Duplicate node ID")
			seen[id] = true
			_check(float(node["map_x"]) > 0 and float(node["map_x"]) < 1, "Node escaped map")
			if index < steps.size() - 1: _check(not Array(node["next_ids"]).is_empty(), "Dead end before final boss")
			if next_ids.size() > 1: _check(Array(node["next_ids"]).size() >= 2, "Single-choice corridor before a non-boss row")
			if next_ids.size() > 2 and Array(steps[index]["nodes"]).size() > 1 and Array(node["next_ids"]).size() >= 3: _three_way_branches += 1
			_check(Array(node["next_ids"]).size() == _unique(node["next_ids"]).size(), "Duplicate route edge")
			for target: Variant in node["next_ids"]:
				_check(next_ids.has(String(target)), "Edge skips a step or points to missing node")
				incoming[String(target)] = true
			if index > 0: _check(incoming.has(id), "Unreachable generated node")
		if index % 7 == 6:
			_check(Array(steps[index]["nodes"]).size() == 1 and steps[index]["nodes"][0]["type"] == "boss", "Missing chapter boss")


func _run() -> void:
	var generator: MapGenerator = MapGenerator.new()
	for seed: int in 80:
		for tier: int in [1, 2, 3, 4]:
			var map: Dictionary = generator.generate_run(seed, tier)
			_check(map == generator.generate_run(seed, tier), "Map is not seeded/reproducible")
			_check(_node_count(map) == 26 * tier, "Expected 26 nodes per chapter")
			for index: int in Array(map["steps"]).size():
				_check(Array(map["steps"][index]["nodes"]).size() == MapGenerator.ROUTE_ROW_WIDTHS[index % 7], "Unexpected row width")
			_validate(map)
	_check(_three_way_branches > 0, "Seeded maps never generated three-way branches")
	var infinite: Dictionary = generator.generate_infinite_run(414)
	generator.append_infinite_cycle(infinite, 414)
	_check(Array(infinite["steps"]).size() == 56, "Infinite cycle did not append")
	_check(_node_count(infinite) == 208, "Infinite chapters did not receive expanded choices")
	_validate(infinite)
	var legacy: Dictionary = generator.generate_run(12)
	legacy.erase("graph_version")
	for index: int in Array(legacy["steps"]).size():
		if index % 7 not in [5, 6]: legacy["steps"][index]["nodes"] = Array(legacy["steps"][index]["nodes"]).slice(0, 2)
		for node: Dictionary in legacy["steps"][index]["nodes"]:
			node.erase("next_ids")
			node.erase("map_x")
	for index: int in 2: legacy["steps"][0]["nodes"][index]["status"] = "completed" if index == 1 else "skipped"
	legacy["current_step"] = 1
	for node: Dictionary in legacy["steps"][1]["nodes"]: node["status"] = "available"
	legacy["steps"][1]["nodes"][1]["shop_offers"] = [{"card_id": "guard", "price": 15, "bought": true}]
	var original_ids: Array = legacy["steps"][1]["nodes"].map(func(node: Dictionary) -> String: return node["id"])
	MapRouteGraph.migrate(legacy, 12)
	_check(legacy["graph_version"] == MapRouteGraph.VERSION and legacy["steps"][1]["nodes"][1]["shop_offers"][0]["bought"], "Migration lost offers")
	for id: String in original_ids: _check(MapRouteGraph.can_select(legacy, id), "Migration removed an offered choice")
	var migrated: Dictionary = legacy.duplicate(true)
	MapRouteGraph.migrate(legacy, 12)
	_check(legacy == migrated, "Migration is not idempotent")
	var restored: RunState = RunState.from_starter(Database.get_starter("balanced"), 12)
	restored.map_state = legacy
	_check(RunState.from_dict(restored.to_dict()).map_state == legacy, "Save round trip lost connections")
	Game.start_new_run("balanced", 4242)
	var first: Dictionary = Game.get_current_step_data()["nodes"][0]
	_check(Game.select_map_node(String(first["id"])) == "battle", "Available start rejected")
	_check(Game.select_map_node(String(Game.get_current_step_data()["nodes"][1]["id"])) == "", "Second selection accepted during active node")
	Game._complete_active_map_node_and_advance()
	var allowed: Array[String] = MapRouteGraph.allowed_ids(Game.current_run.map_state, 1)
	_check(allowed.size() >= 2, "First branch did not offer multiple connected destinations")
	for node: Dictionary in Game.get_current_step_data()["nodes"]:
		_check((node["status"] == "available") == allowed.has(String(node["id"])), "Unlock ignored connections")
		if not allowed.has(String(node["id"])):
			node["status"] = "available"
			_check(Game.select_map_node(String(node["id"])) == "", "Forged availability bypassed adjacency")
			node["status"] = "blocked"
	var wrong_step: String = String(Game.get_map_steps()[3]["nodes"][0]["id"])
	_check(Game.select_map_node(wrong_step) == "", "Future step was selectable")
	var fixture: Dictionary = {"graph_version": 1, "steps": [
		{"nodes": [{"id": "a", "type": "normal_battle", "status": "completed", "next_ids": ["b"]}]},
		{"nodes": [{"id": "b", "type": "normal_battle", "next_ids": ["d"]}, {"id": "c", "type": "heal", "next_ids": ["d"]}]},
		{"nodes": [{"id": "d", "type": "boss", "next_ids": []}]}]}
	_check(is_equal_approx(MapRouteGraph.minimum_route_weight(fixture, RunScoreResolver.new()._node_battle_weight), 3.5), "Score used an unreachable cheaper node")
	_test_saved_map_upgrade(generator)
	Game.current_screen_hint = "map"
	Game.settings["developer_mode"] = true
	var gold_before: int = Game.current_run.gold
	_check(Game.developer_advance_map_route() and Game.get_current_step_index() == 2, "Developer route advance failed")
	_check(Game.current_run.gold == gold_before and Game.current_run.battle_history.is_empty(), "Developer advance granted rewards")
	var screen: Control = load("res://scenes/map/Map.tscn").instantiate() as Control
	add_child(screen)
	await get_tree().process_frame
	_check(screen.find_child("DevMapAdvance", true, false) != null, "Developer panel did not expose route testing")
	_check(screen.find_child("RunBattleSummaryTotal", true, false) == null, "Hidden history was built eagerly")
	screen.call("_show_history")
	_check(screen.find_child("RunBattleSummaryEmpty", true, false) != null, "History did not build on demand")
	remove_child(screen)
	screen.call("_responsive_layout")
	screen.call("_scroll_to_current_step", 0)
	(screen.get("_route_canvas") as MapRouteCanvas).call("_layout")
	screen.queue_free()
	await get_tree().process_frame
	print("NODE_MAP_SMOKE_OK 320 seeded 26-node chapters, multi-choice edge lanes, 56-step infinite links, v1/legacy migration/offers/save, adjacency, double input, graph score and rewardless developer advance")
	get_tree().quit()


func _unique(values: Array) -> Dictionary:
	var ids: Dictionary = {}
	for id: Variant in values: ids[String(id)] = true
	return ids


func _node_count(map: Dictionary) -> int:
	var total: int = 0
	for step: Dictionary in map["steps"]: total += Array(step["nodes"]).size()
	return total


func _test_saved_map_upgrade(generator: MapGenerator) -> void:
	var saved: Dictionary = generator.generate_run(88)
	for index: int in 6:
		saved["steps"][index]["nodes"] = Array(saved["steps"][index]["nodes"]).slice(0, 2 if index == 0 else 3)
	saved["graph_version"] = 1
	saved["current_step"] = 1
	for node: Dictionary in saved["steps"][0]["nodes"]: node["status"] = "completed" if node == saved["steps"][0]["nodes"][1] else "skipped"
	for node: Dictionary in saved["steps"][1]["nodes"]: node["status"] = "available"
	saved["steps"][1]["nodes"][1]["shop_offers"] = [{"card_id": "guard", "price": 15, "bought": true}]
	var offered: Array = saved["steps"][1]["nodes"].map(func(node: Dictionary) -> String: return node["id"])
	var history: Dictionary = Dictionary(saved["steps"][0]["nodes"][1]).duplicate(true)
	generator.upgrade_pending_choices(saved, 88)
	MapRouteGraph.migrate(saved, 88)
	_check(saved["steps"][0]["nodes"].size() == 2, "Upgrade changed an already completed row")
	_check(saved["steps"][0]["nodes"][1]["id"] == history["id"] and saved["steps"][0]["nodes"][1]["status"] == "completed", "Upgrade lost route history")
	_check(saved["steps"][1]["nodes"].size() == 4 and saved["steps"][2]["nodes"].size() == 5, "Pending save rows were not expanded")
	_check(saved["steps"][1]["nodes"][1]["shop_offers"][0]["bought"], "Upgrade reset purchased offers")
	for id: String in offered: _check(MapRouteGraph.can_select(saved, id), "Upgrade removed an offered choice")
	_validate(saved)
	var once: Dictionary = saved.duplicate(true)
	generator.upgrade_pending_choices(saved, 88)
	MapRouteGraph.migrate(saved, 88)
	_check(saved == once, "Save upgrade was not idempotent")
	var active: Dictionary = once.duplicate(true)
	active["graph_version"] = 1
	active["active_node_id"] = active["steps"][1]["nodes"][0]["id"]
	active["steps"][1]["nodes"] = Array(active["steps"][1]["nodes"]).slice(0, 3)
	generator.upgrade_pending_choices(active, 88)
	_check(active["steps"][1]["nodes"].size() == 3, "Upgrade altered the active encounter row")
	var sources: Array = [{"id": "left"}, {"id": "right"}]
	var targets: Array = [{"id": "a"}, {"id": "b"}, {"id": "c"}, {"id": "d"}, {"id": "e"}]
	for index: int in 2: sources[index]["next_ids"] = MapRouteGraph._targets(index, 2, targets, true)
	MapRouteGraph._ensure_incoming(sources, targets)
	for target: Dictionary in targets: _check(sources.any(func(node: Dictionary) -> bool: return Array(node["next_ids"]).has(target["id"])), "Wide row has an unreachable node")
	var old_infinite: Dictionary = generator.generate_infinite_run(89)
	old_infinite["graph_version"] = 1
	for index: int in Array(old_infinite["steps"]).size():
		if index % 7 != 6:
			old_infinite["steps"][index]["nodes"] = Array(old_infinite["steps"][index]["nodes"]).slice(0, 2 if index % 7 == 0 else 3)
	generator.upgrade_pending_choices(old_infinite, 89)
	MapRouteGraph.migrate(old_infinite, 89)
	_validate(old_infinite)
	_check(_node_count(old_infinite) == 104, "Infinite save did not expand every pending chapter")
	for step: Dictionary in old_infinite["steps"]:
		for node: Dictionary in step["nodes"]:
			_check(node["cycle"] == step["cycle"] and node["infinite_power"] == step["infinite_power"], "New infinite node lost scaling metadata")
