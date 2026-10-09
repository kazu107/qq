extends Node

var _failures: Array[String] = []


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	_test_metrics()
	var simulation: BattleSimulation = BattleSimulation.new()
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	simulation.setup(run, "scout", 180.0, 0.1)
	while not simulation.finished:
		simulation.advance(100)
	var summary: Dictionary = simulation.result()
	var data: Dictionary = summary["analysis"]
	var samples: Array = data["hp_history"]
	_check(not samples.is_empty() and is_zero_approx(float(samples[0]["time"])), "HP history needs an initial sample")
	_check(int(samples.back()["enemy"]) == int(summary["enemy_hp"]), "HP history lost the terminal HP")
	_check(samples.size() <= BattleAnalysis.MAX_HP_SAMPLES, "HP history exceeded its bound")
	var enemy_row_found: bool = false
	for row: Dictionary in data["cards"]:
		_check(String(row["actor"]) in ["player", "enemy"], "PvE rows must use canonical sides")
		enemy_row_found = enemy_row_found or String(row["actor"]) == "enemy"
	_check(enemy_row_found, "PvE enemy card contributions missing")
	_check(BattleStateCodec.encode_match_summary(summary)["analysis"] == data, "Network summary lost full analytics")
	_check(ReplayData.from_dict(ReplayData.from_summary(summary).to_dict()).summary["analysis"] == data, "Replay lost analytics")
	var panel: BattleResultAnalysisPanel = BattleResultAnalysisPanel.new()
	add_child(panel)
	panel.show_result(summary, "enemy", false, true)
	_check(panel.visible and not panel._details_modal.visible, "Result should initially contain no statistics")
	_check(panel.find_child("BattleDetailsButton", true, false) != null, "Details action missing")
	panel.show_details()
	_check(panel._details_modal.visible and not panel._result_modal.visible, "Details should be a separate view")
	_check(panel._metrics.get_child_count() == 24, "Comparison table should have seven metrics and two players")
	for metric: String in ["damage", "heal", "shield", "absorbed"]:
		panel._select_metric(metric)
		_check(panel._card_rows.get_child_count() >= 2, "Metric graph missing player sections: " + metric)
	panel.close_details()
	_check(panel._result_modal.visible, "Back from details must restore result")
	panel.show_result({"winner": "draw", "analysis": {}}, "player", false, false)
	panel.show_details()
	_check(panel._hp_chart._samples.is_empty(), "Empty battles must not reuse old charts")
	panel.close_details()
	panel.queue_free()
	simulation.dispose()
	await get_tree().process_frame
	await _test_result_sequence("player")
	await _test_result_sequence("enemy")
	await _test_network_result_sequence()
	if _failures.is_empty():
		print("BATTLE_RESULT_DETAILS_OK: metrics, bounded HP history, enemy attribution, online/replay summaries, victory/defeat collapse ordering, detail navigation")
		get_tree().quit()
	else:
		for failure: String in _failures:
			push_error(failure)
		get_tree().quit(1)


func _test_metrics() -> void:
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	engine.setup_pvp(run, RunState.from_dict(run.to_dict()))
	engine.start_battle()
	engine.apply_status_from_card("player", "enemy", "bleed", 30.0)
	engine.battle_state.enemy.statuses["bleed"]["tick_accumulator"] = UnitState.BLEED_TICK_INTERVAL
	engine.update(0.1)
	var totals: Dictionary = engine.build_summary(false)["analysis"]["totals"]
	_check(int(totals["player"]["damage"]) == 1 and int(totals["enemy"]["damage_taken"]) == 1, "Status damage must count in totals without becoming a direct card contribution")
	engine.dispose()
	var attacker: UnitState = UnitState.new()
	attacker.hp = 20
	attacker.max_hp = 20
	var defender: UnitState = UnitState.new()
	defender.hp = 5
	defender.max_hp = 20
	defender.add_shield(8)
	DamageResolver.apply_damage(attacker, defender, 100)
	_check(int(attacker.combat_totals["damage"]) == 5 and int(attacker.combat_totals["absorbed"]) == 8, "Overkill/absorbed damage accounting incorrect")
	defender.heal(50)
	defender.heal(50)
	_check(int(defender.combat_totals["heal"]) == 20, "Overhealing inflated effective healing")
	defender.add_shield(4)
	defender.tick_shield_decay(1.0)
	_check(int(defender.combat_totals["shield"]) == 12 and int(defender.combat_totals["blocked"]) == 8, "Shield decay counted as blocking")
	var state: BattleState = BattleState.new()
	state.player = attacker
	state.enemy = defender
	var analysis: BattleAnalysis = BattleAnalysis.new()
	for index: int in range(5000):
		state.battle_time = float(index)
		analysis.capture_state(state, true)
	_check(analysis.hp_history.size() <= BattleAnalysis.MAX_HP_SAMPLES and float(analysis.hp_history[0]["time"]) == 0.0 and float(analysis.hp_history.back()["time"]) == 4999.0, "History compaction must preserve both endpoints")


func _test_result_sequence(winner: String) -> void:
	Game.start_new_run("balanced", 4242)
	Game.developer_open_battle("scout")
	var battle: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control
	add_child(battle)
	await get_tree().process_frame


	battle.set_process(false)
	var engine: RealtimeBattleEngine = battle.get("_engine")
	var stage: BattleStage3D = battle.get("_battle_stage")
	var panel: BattleResultAnalysisPanel = battle.get("_analysis_panel")
	stage.set_process(false)
	var player: BattleActor3D = stage.find_child("PlayerBattleActor3D", true, false) as BattleActor3D
	var enemy: BattleActor3D = stage.find_child("EnemyBattleActor3D", true, false) as BattleActor3D
	player.set_process(false)
	enemy.set_process(false)
	engine.battle_state.winner = winner
	engine.battle_state.get_opponent(winner).hp = 0
	battle.call("_queue_battle_result", engine.build_summary(), false, true)
	_check(not panel.visible, "Result opened before defeat animation started")
	for index: int in range(200):
		stage._process(0.02)
		player._process(0.02)
		enemy._process(0.02)
		if panel.visible:
			break
		if index == 10:
			_check(not panel.visible, "Result opened mid-collapse")
	_check(panel.visible and stage.has_battle_end_presentation_finished(), "Result did not open after collapse: " + winner)
	var loser: BattleActor3D = enemy if winner == "player" else player
	_check(loser.get_action_name() == "defeat" and loser.is_terminal_action_complete(), "Result must wait for actual loser animation completion")
	_check(String(Game.last_battle_summary.get("winner", "")) == winner, "Game result was not committed after presentation")
	battle.queue_free()
	await get_tree().process_frame


func _test_network_result_sequence() -> void:
	Game.start_new_run("balanced", 4242)
	Game.developer_open_battle("scout")
	var battle: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control
	add_child(battle)
	await get_tree().process_frame
	battle.set_process(false)
	battle.set("_lan_mode", true)
	battle.set("_local_run", Game.current_run)
	battle.set("_opponent_run", RunState.from_starter(Database.get_starter("balanced"), 4242))
	var stage: BattleStage3D = battle.get("_battle_stage")
	var panel: BattleResultAnalysisPanel = battle.get("_analysis_panel")
	stage.set_process(false)
	var player: BattleActor3D = stage.find_child("PlayerBattleActor3D", true, false) as BattleActor3D
	var enemy: BattleActor3D = stage.find_child("EnemyBattleActor3D", true, false) as BattleActor3D
	player.set_process(false)
	enemy.set_process(false)
	# A guest can receive a final summary without the final event in its compact window.
	battle.call("_on_lan_match_finished", {"winner": "player", "analysis": {"cards": [], "hp_history": []}})
	_check((battle.get("_engine") as RealtimeBattleEngine).battle_state.winner == "player", "Final summaries must freeze the client simulation even without a final event")
	battle.call("_show_round_results_overlay")
	_check(not panel.visible and not (battle.get("_round_results_overlay") as Control).visible, "Network updates bypassed the collapse gate")
	for index: int in range(200):
		stage._process(0.02)
		player._process(0.02)
		enemy._process(0.02)
	_check(panel.visible, "Guest did not present result when compact final event was missing")
	battle.call("_show_round_results_overlay")
	_check(not (battle.get("_round_results_overlay") as Control).visible, "Round waiting overlay covered the result/details")
	battle.queue_free()
	await get_tree().process_frame
