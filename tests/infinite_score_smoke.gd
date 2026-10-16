extends Node

var _checks: int = 0
var _resolver: InfiniteScoreResolver = InfiniteScoreResolver.new()


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		push_error("Infinite score: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _new_run() -> RunState:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.infinite_mode = true
	run.map_state = MapGenerator.new().generate_infinite_run(run.seed)
	_resolver.start_fresh(run)
	return run


func _battle(node_id: String, step: int, type: String = "normal_battle", wave: int = 0, time_ratio: float = 1.0) -> Dictionary:
	return {"node_id": node_id, "step_index": step, "node_type": type, "wave": wave,
		"enemy_id": "scout", "winner": "player", "battle_time": InfiniteScoreResolver.par_time("scout", InfiniteScoreResolver.cycle_for_step(step)) * time_ratio}


func _score(run: RunState) -> int:
	return int(_resolver.calculate(run)["total_score"])


func _run() -> void:
	var run: RunState = _new_run()
	for index: int in 56:
		if index == 28:
			var previous: int = _score(run)
			MapGenerator.new().append_infinite_cycle(run.map_state, run.seed)
			_check(_score(run) == previous, "adding a cycle changed frozen points")
		var type: String = "boss" if index % 7 == 6 else "event"
		var node: Dictionary = {"id": "node_%d" % index, "type": type}
		if type == "boss":
			_resolver.record_battle(run, _battle(node["id"], index, type, 0, 2.0))
		_resolver.record_step(run, node, index)
		run.map_state["current_step"] = index + 1
		if index == 27:
			_check(_score(run) == 36000, "first cycle base points should be 36000")
	_check(_score(run) == 81000, "two cycle base points should be 81000")
	_check(String(_resolver.calculate(run)["rank"]) == "" and int(_resolver.calculate(run)["max_score"]) == 0, "infinite score must not have rank or a score cap")
	var before: int = _score(run)
	_resolver.record_step(run, {"id": "different_branch", "type": "event"}, 55)
	_check(_score(run) == before, "another branch at the same step was counted twice")
	_resolver.record_battle(run, _battle("elite", 29, "elite_battle"))
	_check(_score(run) == before + 375 + 125, "cycle two elite and efficiency awards are incorrect")
	before = _score(run)
	var wave: Dictionary = _battle("hazard", 30, "hazard", 1)
	wave["battle_id"] = "same-battle"
	_resolver.record_battle(run, wave)
	_resolver.record_battle(run, wave)
	_check(_score(run) == before + 125, "duplicate wave was counted twice")
	wave["wave"] = 2
	_resolver.record_battle(run, wave)
	_check(_score(run) == before + 250, "distinct second wave with an identical legacy battle ID was not counted")
	_resolver.record_step(run, {"id": "hazard", "type": "hazard", "hazard_queue": ["scout", "scout"], "hazard_cleared_waves": 1}, 30)
	before = _score(run)
	_resolver.record_step(run, {"id": "hazard", "type": "hazard", "hazard_queue": ["scout", "scout"], "hazard_cleared_waves": 2}, 30)
	_check(_score(run) == before + 625, "full hazard bonus is missing")
	before = _score(run)
	_resolver.record_step(run, {"id": "hazard", "type": "hazard", "hazard_queue": ["scout", "scout"], "hazard_cleared_waves": 2}, 30)
	var lost: Dictionary = _battle("lost", 31)
	lost["winner"] = "enemy"
	_resolver.record_battle(run, lost)
	var forced: Dictionary = _battle("forced", 31)
	forced["forced_hazard_withdraw"] = true
	_resolver.record_battle(run, forced)
	_check(_score(run) == before, "duplicate hazard, defeat or forced withdrawal changed score")
	var zero: Dictionary = _battle("zero", 31)
	zero["battle_time"] = 0.0
	_resolver.record_battle(run, zero)
	_check(_score(run) == before, "zero-time battle earned an efficiency bonus")
	run.player_hp = 0
	run.gold = 9999999
	run.hp_damage_taken = 9999999
	run.run_complete = true
	run.defeated = true
	_check(_score(run) == before, "HP, gold or defeat changed earned points")
	var restored: RunState = RunState.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
	_check(_score(restored) == before, "JSON save/load lost ledger totals")
	_resolver.record_battle(restored, _battle("elite", 29, "elite_battle"))
	_check(_score(restored) == before, "save/load lost duplicate protection")
	for index: int in 1000:
		_resolver.record_step(restored, {"id": "long_%d" % index, "type": "event"}, index + 56)
	_check(_score(restored) > 1000000, "score did not grow beyond ordinary rank limits")
	_test_migration()
	await _test_game_and_ui()
	print("INFINITE_SCORE_SMOKE_OK %d checks: cumulative points, cycles, deduplication, migration, saves, high scores, UI" % _checks)
	get_tree().quit(0)


func _test_migration() -> void:
	var run: RunState = _new_run()
	var first: Dictionary = run.map_state["steps"][0]["nodes"][0]
	first["status"] = "completed"
	run.map_state["current_step"] = 1
	run.battle_history = [{"enemy_id": first["enemy_id"], "node_type": first["type"], "winner": "player", "battle_time": 1.0}]
	run.infinite_score.clear()
	_check(_score(run) == 1100, "legacy completed step and identifiable battle were not restored")
	run.battle_history[0]["battle_time"] = 9999.0
	_check(_score(run) == 1100, "legacy score was recalculated after initialization")
	var unknown: RunState = _new_run()
	unknown.map_state["current_step"] = 1
	unknown.battle_history = [{"enemy_id": "unknown", "winner": "player", "battle_time": 1.0}]
	unknown.infinite_score.clear()
	_check(_score(unknown) == 1000, "unidentifiable history invented an efficiency bonus")


func _test_game_and_ui() -> void:
	Game.meta_progress = Database.meta_progress_template.duplicate(true)
	Game.ensure_meta_initialized()
	Game.meta_progress["infinite_mode_unlocked"] = true
	_check(Game.start_infinite_run("balanced", 12345), "infinite run could not start")
	var first: Dictionary = Game.get_current_step_data()["nodes"][0]
	_check(Game.select_map_node(first["id"]) == "battle", "opening battle was not selected")
	Game.complete_battle({"battle_id": "game-first", "winner": "player", "enemy_id": first["enemy_id"], "player_hp": 50, "battle_time": 1.0})
	_check(_score(Game.current_run) == 100, "victory did not immediately award efficiency")
	Game.choose_reward("")
	_check(_score(Game.current_run) == 1100, "reward continuation did not award the completed step")
	_check(Game.stash_active_run_for_hub(), "infinite run could not suspend")
	Game.apply_loaded_save(SaveData.from_dict(JSON.parse_string(JSON.stringify(Game.build_save_data("hub").to_dict()))))
	_check(Game.resume_suspended_run(Game.RUN_SETUP_MODE_NORMAL) == "map" and _score(Game.current_run) == 1100, "suspend/resume changed score")
	Game.current_run.run_complete = true
	Game.current_run.defeated = true
	Game.current_run.player_hp = 0
	var summary: Dictionary = Game.get_run_summary()
	_check(int(summary["high_score"]) == 1100 and bool(summary["is_new_record"]), "first record was not stored")
	SaveManager.flush_requested_save()
	Game.apply_loaded_save(SaveManager.load_save())
	_check(int(Game.get_run_summary()["high_score"]) == 1100, "record was not persistent")
	SaveManager.flush_requested_save()
	Game.get_run_summary()
	_check(not SaveManager.has_pending_save(), "reopening result repeatedly requested a save")
	Game.current_run = _new_run()
	_resolver.record_step(Game.current_run, {"id": "lower", "type": "event"}, 0)
	Game.current_run.map_state["current_step"] = 1
	Game.current_run.run_complete = true
	Game.current_run.defeated = true
	var lower: Dictionary = Game.get_run_summary()
	_check(int(lower["high_score"]) == 1100 and not bool(lower["is_new_record"]), "a lower score replaced the record")
	_test_hazard_flow()
	var saved: Dictionary = Game.meta_progress["infinite_record"].duplicate(true)
	Game.settings["developer_mode"] = true
	Game.start_new_run("balanced", 334455)
	Game.developer_open_infinite_result()
	_check(Game.has_suspended_run(Game.RUN_SETUP_MODE_NORMAL) and int(Game.suspended_runs[Game.RUN_SETUP_MODE_NORMAL]["run"]["seed"]) == 334455, "preview replaced an active run instead of suspending it")
	_check(Game.get_run_summary()["score_preview"] and Game.meta_progress["infinite_record"] == saved, "developer preview changed real records")
	_check(int(Game.get_run_summary()["total_score"]) > 10000, "preview did not demonstrate uncapped scoring")
	Localization.set_language("ja", false)
	var scene: Control = load("res://scenes/result/RunResult.tscn").instantiate() as Control
	add_child(scene)
	await get_tree().process_frame
	scene.call("_finish_score_animation")
	var total: Label = scene.find_child("ResultTotalScore", true, false) as Label
	var reach: Label = scene.find_child("ResultRankLabel", true, false) as Label
	_check(not total.text.contains("/") and not ["S", "A", "B", "C", "D", "E"].has(reach.text), "infinite result still displays a cap or ordinary rank")
	_check(reach.text.contains("2") and reach.text.contains("8"), "result reached record is incorrect")
	_check(scene.find_child("ResultScoreBar_boss", true, false) != null and scene.find_child("ResultScoreBar_survival", true, false) == null, "infinite result categories are incorrect")
	_check(scene.find_child("ResultInfiniteRecord", true, false) != null, "result high score is missing")
	_check(scene.find_child("DevInfiniteScorePreview", true, false) != null, "developer preview action is missing")
	var seed: int = Game.current_run.seed
	_check(Game.retry_last_seed_run() and Game.current_run.infinite_mode and Game.current_run.seed == seed and _score(Game.current_run) == 0, "retry did not start a fresh infinite run")
	var achievement_stats: Dictionary = Game.meta_progress["achievement_stats"].duplicate(true)
	Game.current_run.run_complete = true
	Game.current_run.defeated = false
	Game._record_completed_run_rank()
	_check(Game.meta_progress["achievement_stats"] == achievement_stats, "infinite score changed normal rank achievements")
	Game.start_new_run("balanced", 123)
	_check(int(RunScoreResolver.new().calculate(Game.current_run)["max_score"]) == 10000, "normal run score cap changed")


func _test_hazard_flow() -> void:
	Game.current_run = _new_run()
	var run: RunState = Game.current_run
	var node: Dictionary = run.map_state["steps"][2]["nodes"][1]
	node["type"] = "hazard"
	node["status"] = "selected"
	node["hazard_queue"] = ["scout", "brute"]
	node["hazard_cleared_waves"] = 0
	run.map_state["current_step"] = 2
	run.map_state["active_node_id"] = node["id"]
	_resolver.record_step(run, {"id": "earlier0", "type": "event"}, 0)
	_resolver.record_step(run, {"id": "earlier1", "type": "event"}, 1)
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.set_audio_enabled(false)
	engine.setup(run, "scout")
	engine.battle_state.winner = "player"
	engine.battle_state.battle_time = 1.0
	var first_summary: Dictionary = engine.build_summary(false)
	engine.dispose()
	Game.complete_battle(first_summary)
	Game.complete_battle(first_summary)
	Game.choose_reward("")
	_check(_score(run) == 2100 and Game.current_screen_hint == "facility", "partial hazard did not retain only earned wave points")
	_check(int(Game.get_active_map_node()["hazard_cleared_waves"]) == 1, "duplicate callback advanced the hazard counter")
	Game.complete_battle({"battle_id": "hazard2", "winner": "player", "enemy_id": "brute", "player_hp": 50, "battle_time": 1.0})
	Game.choose_reward("")
	_check(_score(run) == 3700 and int(run.map_state["current_step"]) == 3, "full hazard did not award two waves, one step and one completion bonus")
