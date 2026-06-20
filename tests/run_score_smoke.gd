extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	call_deferred("_run")


func _run() -> void:
	_test_score_calculation()
	if _failed:
		return
	_test_backward_compatible_run_state()
	if _failed:
		return
	_test_battle_stat_aggregation()
	if _failed:
		return
	await _test_result_ui()
	if _failed:
		return
	print("Run score smoke passed: score calculation, persistence, aggregation, and animated result UI")
	get_tree().quit(0)


func _test_score_calculation() -> void:
	var run_state: RunState = _build_run_state()
	run_state.run_complete = true
	run_state.defeated = false
	run_state.player_hp = run_state.max_hp / 2
	run_state.map_state["current_step"] = 7
	_mark_challenge_route(run_state)
	run_state.battle_history = [
		{"enemy_id": "scout", "node_type": "normal_battle", "battle_time": 32.0, "winner": "player"},
		{"enemy_id": "guardian", "node_type": "hazard", "battle_time": 97.0, "winner": "player"},
		{"enemy_id": "chronoguard", "node_type": "elite_battle", "battle_time": 57.0, "winner": "player"},
		{"enemy_id": "boss_timekeeper", "node_type": "boss", "battle_time": 80.0, "winner": "player"},
	]

	var score: Dictionary = RunScoreResolver.new().calculate(run_state)
	if int(score.get("progress", -1)) != 6000:
		_fail("Run score smoke failed: clear progress score should be 6000")
		return
	if int(score.get("survival", -1)) != 750:
		_fail("Run score smoke failed: half HP survival score should be 750")
		return
	if int(score.get("efficiency", -1)) != 1500:
		_fail("Run score smoke failed: par-time battles should receive full efficiency score")
		return
	if int(score.get("challenge", -1)) != 1000:
		_fail("Run score smoke failed: completed hazard and area 3 elite should receive full challenge score")
		return
	if int(score.get("total_score", -1)) != 9250 or String(score.get("rank", "")) != "S":
		_fail("Run score smoke failed: expected a 9250 S-rank clear")
		return

	run_state.run_complete = true
	run_state.defeated = true
	run_state.player_hp = 0
	run_state.map_state["current_step"] = 6
	score = RunScoreResolver.new().calculate(run_state)
	if String(score.get("rank", "")) != "C":
		_fail("Run score smoke failed: a defeated run should not rank above C")


func _test_backward_compatible_run_state() -> void:
	var restored: RunState = RunState.from_dict({
		"starter_id": "balanced",
		"player_hp": 10,
		"max_hp": 10,
	})
	if not restored.battle_history.is_empty() or restored.hp_damage_taken != 0:
		_fail("Run score smoke failed: old saves should default new run statistics safely")


func _test_battle_stat_aggregation() -> void:
	Game.start_new_run("balanced", 12345)
	var current_step: Dictionary = Game.get_current_step_data()
	var nodes: Array = Array(current_step.get("nodes", []))
	if nodes.is_empty():
		_fail("Run score smoke failed: generated map had no first-step battle")
		return
	var node_data: Dictionary = Dictionary(nodes[0])
	Game.select_map_node(String(node_data.get("id", "")))
	Game.complete_battle({
		"winner": "enemy",
		"enemy_id": String(node_data.get("enemy_id", "scout")),
		"enemy_name": "Score Test Enemy",
		"player_hp": 0,
		"battle_time": 47.5,
		"battle_events": [
			{"target_id": "player", "hp_delta": -7},
			{"target_id": "enemy", "hp_delta": -11},
		],
	})
	if Game.current_run.battle_history.size() != 1:
		_fail("Run score smoke failed: battle completion did not append run history")
		return
	if not is_equal_approx(float(Game.current_run.battle_history[0].get("battle_time", 0.0)), 47.5):
		_fail("Run score smoke failed: battle time was not preserved")
		return
	if Game.current_run.hp_damage_taken != 7:
		_fail("Run score smoke failed: player HP damage aggregation was incorrect")


func _test_result_ui() -> void:
	Game.developer_open_result("balanced")
	var result_scene: Control = load("res://scenes/result/RunResult.tscn").instantiate() as Control
	add_child(result_scene)
	await get_tree().process_frame
	result_scene.call("_finish_score_animation")
	await get_tree().process_frame

	var summary: Dictionary = Game.get_run_summary()
	var total_label: Label = result_scene.find_child("ResultTotalScore", true, false) as Label
	var rank_label: Label = result_scene.find_child("ResultRankLabel", true, false) as Label
	if total_label == null or total_label.text.replace(",", "").find("%s" % int(summary.get("total_score", -1))) == -1:
		_fail("Run score smoke failed: result UI did not render the final total score")
		return
	if rank_label == null or rank_label.text != String(summary.get("rank", "")):
		_fail("Run score smoke failed: result UI did not reveal the calculated rank")
		return
	for category_id: String in ["progress", "survival", "efficiency", "challenge"]:
		var bar: ProgressBar = result_scene.find_child("ResultScoreBar_%s" % category_id, true, false) as ProgressBar
		if bar == null or not is_equal_approx(bar.value, float(summary.get(category_id, -1))):
			_fail("Run score smoke failed: %s score bar did not reach its final value" % category_id)
			return
	result_scene.queue_free()


func _build_run_state() -> RunState:
	var run_state: RunState = RunState.from_starter(Database.get_starter("balanced"), 777)
	run_state.map_state = MapGenerator.new().generate_run(run_state.seed)
	return run_state


func _mark_challenge_route(run_state: RunState) -> void:
	var steps: Array = Array(run_state.map_state.get("steps", []))
	var hazard_step: Dictionary = Dictionary(steps[2])
	var hazard_nodes: Array = Array(hazard_step.get("nodes", []))
	var hazard_node: Dictionary = Dictionary(hazard_nodes[1])
	hazard_node["status"] = "completed"
	hazard_node["hazard_queue"] = ["scout", "brute", "guardian"]
	hazard_node["hazard_cleared_waves"] = 3
	hazard_nodes[1] = hazard_node
	hazard_step["nodes"] = hazard_nodes
	steps[2] = hazard_step

	var clash_step: Dictionary = Dictionary(steps[4])
	var clash_nodes: Array = Array(clash_step.get("nodes", []))
	var elite_node: Dictionary = Dictionary(clash_nodes[1])
	elite_node["status"] = "completed"
	clash_nodes[1] = elite_node
	clash_step["nodes"] = clash_nodes
	steps[4] = clash_step
	run_state.map_state["steps"] = steps


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
