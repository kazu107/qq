extends Node

var _checks: int = 0
var _generator: MapGenerator = MapGenerator.new()


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.settings["developer_mode"] = true
	Game.settings["replay_auto_export"] = false
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		push_error("Encounter growth: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _run() -> void:
	_test_boundaries()
	_test_generated_maps()
	_test_migration()
	_test_chain(false, 14, "normal_battle", 2)
	_test_chain(true, 28, "normal_battle", 3)
	_test_chain(true, 30, "hazard", 4)
	_test_chain(true, 37, "hazard", 5)
	_test_chain(true, 44, "hazard", 6)
	_test_developer_preview()
	print("ENCOUNTER_GROWTH_SMOKE_OK checks=%d" % _checks)
	get_tree().quit()


func _test_boundaries() -> void:
	for step: int in [1, 14, 15, 28, 29, 35, 36, 42, 43, 49, 50, 56, 57, 70, 71, 1001]:
		_check(EncounterSeries.normal_battle_count(step - 1) == 1 + floori(float(step - 1) / 14.0), "normal count boundary at step %d" % step)
		var expected: int = 3 if step <= 28 else 4 + floori(float(step - 29) / 7.0)
		_check(EncounterSeries.build_hazard_queue(13, step - 1, true).size() == expected, "infinite hazard boundary at step %d" % step)
	_check(EncounterSeries.normal_battle_count(-10) == 1, "negative step must not remove the first enemy")
	_check(EncounterSeries.build_hazard_queue(2, 2, true) == ["raider", "guardian"], "first-cycle two-wave hazard changed")
	_check(EncounterSeries.build_hazard_queue(3, 4, false) == ["chronoguard", "disruptor", "brute"], "normal three-wave hazard changed")
	_check(EncounterSeries.build_hazard_queue(12, 999, false).size() == 3, "normal-mode hazards must not grow")


func _test_generated_maps() -> void:
	for seed_value: int in range(1, 25):
		var normal: Dictionary = _generator.generate_run(seed_value, 4)
		_check(JSON.stringify(normal) == JSON.stringify(_generator.generate_run(seed_value, 4)), "normal generation must remain deterministic")
		_check_map(normal, false)
		var infinite: Dictionary = _generator.generate_infinite_run(seed_value)
		for cycle: int in 3: _generator.append_infinite_cycle(infinite, seed_value)
		_check_map(infinite, true)
		var twin: Dictionary = _generator.generate_infinite_run(seed_value)
		for cycle: int in 3: _generator.append_infinite_cycle(twin, seed_value)
		_check(JSON.stringify(infinite) == JSON.stringify(twin), "infinite queues must remain deterministic across cycle appends")


func _check_map(map_state: Dictionary, infinite: bool) -> void:
	var steps: Array = map_state["steps"]
	for index: int in steps.size():
		for node: Dictionary in steps[index]["nodes"]:
			var enemies: Array[String] = EncounterSeries.queue(node)
			match String(node["type"]):
				"normal_battle":
					_check(enemies.size() == EncounterSeries.normal_battle_count(index), "generated normal queue has local rather than global step count")
					_check(enemies[0] == node["enemy_id"], "selected map enemy must remain the first opponent")
				"hazard":
					_check(enemies == EncounterSeries.build_hazard_queue(int(node["area"]), index, infinite), "generated hazard queue mismatch")
				"elite_battle", "boss":
					_check(enemies.size() == 1, "elite or boss was incorrectly converted to a growing chain")
			for enemy_id: String in enemies:
				_check(Database.get_enemy(enemy_id) != null, "unknown enemy in generated queue")
				if node["type"] == "normal_battle": _check(not enemy_id.begins_with("boss_"), "normal chain must not contain bosses")
			if not enemies.is_empty():
				var weight: float = RunScoreResolver.new()._get_battle_weight(String(node["type"])) * enemies.size()
				_check(is_equal_approx(RunScoreResolver.new()._node_battle_weight(node), weight), "unplayed encounters missing from efficiency denominator")


func _test_migration() -> void:
	var map_state: Dictionary = _generator.generate_infinite_run(42)
	_generator.append_infinite_cycle(map_state, 42)
	map_state.erase("encounter_growth_version")
	for step: Dictionary in map_state["steps"]:
		for node: Dictionary in step["nodes"]:
			node.erase("encounter_queue")
			node.erase("hazard_queue")
	var steps: Array = map_state["steps"]
	var completed: Dictionary = steps[14]["nodes"][0]
	completed["status"] = "completed"
	var active: Dictionary = steps[28]["nodes"][0]
	active["status"] = "selected"
	active["encounters_cleared"] = 0
	map_state["current_step"] = 28
	map_state["active_node_id"] = active["id"]
	var custom: Dictionary = steps[30]["nodes"][1]
	custom["type"] = "hazard"
	custom["hazard_queue"] = ["scout", "guardian"]
	custom["hazard_cleared_waves"] = 1
	custom["hazard_wave_gold"] = 99
	_generator.upgrade_encounter_growth(map_state, true)
	_check(not completed.has("encounter_queue") and not active.has("encounter_queue"), "migration rewrote a completed or active legacy battle")
	_check(custom["hazard_queue"] == ["scout", "guardian"] and custom["hazard_cleared_waves"] == 1 and custom["hazard_wave_gold"] == 99, "migration lost authored queues/progress/rewards")
	_check(EncounterSeries.queue(steps[28]["nodes"][1]).size() == 3, "unstarted legacy normal node was not upgraded")
	_check(EncounterSeries.queue(steps[37]["nodes"][1]).size() == 5, "unstarted legacy hazard was not upgraded")
	var snapshot: String = JSON.stringify(map_state)
	_generator.upgrade_encounter_growth(map_state, true)
	_check(JSON.stringify(map_state) == snapshot, "migration repeated or grew queues twice")


func _prepare_step(index: int, infinite: bool) -> void:
	Game.start_new_run("balanced", 4242)
	Game.current_run.infinite_mode = infinite
	Game.current_run.map_state = _generator.generate_infinite_run(4242) if infinite else _generator.generate_run(4242, 4)
	while Array(Game.current_run.map_state["steps"]).size() <= index:
		_generator.append_infinite_cycle(Game.current_run.map_state, 4242)
	Game.current_run.map_state["current_step"] = index
	var steps: Array = Game.current_run.map_state["steps"]
	var previous: Dictionary = steps[index - 1]["nodes"][0]
	previous["status"] = "completed"
	previous["next_ids"] = steps[index]["nodes"].map(func(node: Dictionary) -> String: return String(node["id"]))
	MapRouteGraph.unlock(Game.current_run.map_state, index)
	if infinite: InfiniteScoreResolver.new().start_fresh(Game.current_run)


func _test_chain(infinite: bool, index: int, type: String, total: int) -> void:
	_prepare_step(index, infinite)
	var chosen: Dictionary = {}
	for node: Dictionary in Game.get_current_step_data()["nodes"]:
		if node["type"] == type:
			chosen = node
			break
	_check(not chosen.is_empty(), "test chain node missing")
	var data: Dictionary = Game.get_encounter_preview(chosen["id"])
	_check(data["total"] == total and data["index"] == 1, "pre-entry intel does not show the full generated count")
	_check(Game.select_map_node(chosen["id"]) == ("facility" if type == "hazard" else "battle"), "wrong entry flow")
	if type == "hazard":
		_check(Game.get_hazard_status()["wave_gold"] > 0 and Game.get_hazard_status()["wave_heal"] == 2, "precomputed queues omitted hazard reward metadata")
	var snapshot: Array[String] = EncounterSeries.queue(Game.get_active_map_node())
	for wave: int in total:
		data = Game.get_encounter_preview()
		_check(data["index"] == wave + 1 and data["total"] == total and data["enemy_id"] == snapshot[wave], "incorrect next enemy/counter")
		if type == "hazard" or wave > 0: _check(Game.start_active_encounter(), "next encounter cannot start")
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
		engine.record_visuals = false
		engine.set_audio_enabled(false)
		engine.setup(Game.current_run, String(data["enemy_id"]))
		engine.battle_state.winner = "player"
		engine.battle_state.battle_time = 20.0
		var summary: Dictionary = engine.build_summary()
		engine.dispose()
		Game.complete_battle(summary)
		_check(Game.current_screen_hint == "reward" and not Game.reward_options.is_empty(), "every encounter must grant rewards")
		_check(EncounterSeries.cleared(Game.get_active_map_node()) == wave + 1, "cleared counter did not advance once")
		Game.skip_reward()
		if wave < total - 1:
			_check(Game.get_current_step_index() == index, "step advanced before the final enemy")
			_check(Game.current_screen_hint == ("facility" if type == "hazard" else "map"), "interim reward did not return to next enemy preview flow")
			Game.current_run = RunState.from_dict(JSON.parse_string(JSON.stringify(Game.current_run.to_dict())))
			_check(EncounterSeries.queue(Game.get_active_map_node()) == snapshot, "save/load rewrote the queue")
		else:
			_check(Game.get_current_step_index() == index + 1 and Game.current_screen_hint == "map", "final enemy must advance exactly one step")
	_check(Game.current_run.battle_history.size() == total, "chained encounters missing from battle history")
	if infinite:
		var multiplier: float = InfiniteScoreResolver.multiplier(InfiniteScoreResolver.cycle_for_step(index))
		var expected: int = roundi((1000 + 100 * total + (500 if type == "hazard" else 0)) * multiplier)
		_check(InfiniteScoreResolver.new().calculate(Game.current_run)["total_score"] == expected, "per-wave efficiency/full-clear/step scores missing or duplicated")


func _test_developer_preview() -> void:
	_prepare_step(49, true)
	var id: String = Game.developer_prepare_encounter_chain(true)
	_check(Game.get_encounter_preview(id)["total"] == 7, "developer hazard preview did not follow current step growth")
	Game.settings["developer_mode"] = false
	_check(Game.developer_prepare_encounter_chain() == "", "non-developers can generate debug chains")
