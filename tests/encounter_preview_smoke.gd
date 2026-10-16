extends Node

var _checks: int = 0
var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.settings["developer_mode"] = true
	Game.settings["replay_auto_export"] = false
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error("Encounter preview smoke failed: " + message)


func _win(enemy_id: String) -> void:
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.setup(Game.current_run, enemy_id)
	engine.battle_state.winner = "player"
	engine.battle_state.battle_time = 30.0
	var summary: Dictionary = engine.build_summary()
	engine.dispose()
	Game.complete_battle(summary)


func _run() -> void:
	Game.start_new_run("balanced", 4242)
	var first: Dictionary = Game.get_current_step_data()["nodes"][0]
	var original: String = JSON.stringify(Game.current_run.to_dict())
	var single: Dictionary = Game.get_encounter_preview(String(first["id"]))
	_check(not single.is_empty() and single["index"] == 1 and single["total"] == 1, "single enemy defaults to 1/1")
	_check(JSON.stringify(Game.current_run.to_dict()) == original and Game.pending_enemy_id == "", "opening intel must not select node or consume progress")
	_check(Game.get_encounter_preview("missing").is_empty(), "invalid nodes cannot be previewed")
	var locked: Dictionary = Game.get_map_steps()[1]["nodes"][0]
	_check(Game.get_encounter_preview(String(locked["id"])).is_empty(), "locked nodes cannot be previewed")
	var map: Control = load("res://scenes/map/Map.tscn").instantiate() as Control
	add_child(map)
	map.call("_on_node_selected", String(first["id"]))
	await get_tree().process_frame
	await get_tree().process_frame
	var dialog: EnemyEncounterDialog = map.get("_enemy_dialog") as EnemyEncounterDialog
	for _frame: int in 12: await get_tree().process_frame
	_check(dialog._frame.get_global_rect().position.y >= 0 and dialog._frame.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "intel fits after flow containers settle")
	_check(dialog != null and dialog.visible, "map node opens frontmost intel")
	_check(dialog._model.is_preview_ready() and dialog._model._preview_side == "enemy", "animated enemy model is ready")
	_check(dialog._model.get_selected_starter_id() == single["enemy_id"], "correct enemy model selected")
	_check(dialog._card_buttons.filter(func(card: CardButton) -> bool: return card.visible).size() == (single["unit"] as UnitState).card_runtime_states.size(), "all enemy cards shown")
	_check(dialog._card_buttons[0].tooltip_text != "", "enemy cards retain detailed tooltips")
	dialog.close()
	_check(not dialog.visible and Game.get_active_map_node().is_empty(), "cancel leaves map unchanged")
	_check(dialog._model.get_preview_viewport().render_target_update_mode == SubViewport.UPDATE_DISABLED, "closed preview stops rendering")
	map.queue_free()
	await get_tree().process_frame
	Game.select_map_node(String(first["id"]))
	_win(String(single["enemy_id"]))
	Game.skip_reward()
	_check(Game.get_current_step_index() == 1 and Game.current_screen_hint == "map", "single battle still advances exactly one step")

	Game.start_new_run("balanced", 4242)
	var chain_id: String = Game.developer_prepare_encounter_chain()
	_check(chain_id != "", "developer two-enemy fixture available")
	_check(Game.get_encounter_preview(chain_id)["total"] == 2, "configured normal chain reports two enemies")
	Game.select_map_node(chain_id)
	_win("scout")
	_check(Game.current_screen_hint == "reward", "normal chain retains per-battle rewards")
	Game.choose_reward("")
	_check(Game.get_current_step_index() == 0 and Game.current_screen_hint == "map", "interim reward must not complete the node")
	var next: Dictionary = Game.get_encounter_preview()
	_check(next["index"] == 2 and next["total"] == 2 and next["enemy_id"] == "guardian", "next enemy advances to 2/2")
	_check(Game.stash_active_run_for_hub(), "can suspend between encounters")
	_check(Game.resume_suspended_run(Game.RUN_SETUP_MODE_NORMAL) == "map", "resume returns to the map intel flow")
	_check(Game.get_encounter_preview()["index"] == 2, "save roundtrip preserves encounter counter")
	map = load("res://scenes/map/Map.tscn").instantiate() as Control
	add_child(map)
	await get_tree().process_frame
	await get_tree().process_frame
	dialog = map.get("_enemy_dialog") as EnemyEncounterDialog
	_check(dialog != null and dialog.visible and dialog.preview_data["index"] == 2, "next/resumed normal chain automatically opens intel")
	dialog.close()
	(map.get("_encounter_button") as Button).pressed.emit()
	_check(dialog.visible, "intel can be reopened after closing")
	map.queue_free()
	await get_tree().process_frame
	_check(Game.start_active_encounter() and Game.pending_enemy_id == "guardian", "confirm uses next enemy rather than first enemy")
	_check(not Game.start_active_encounter(), "double confirm cannot start twice")
	_win("guardian")
	Game.skip_reward()
	_check(Game.get_current_step_index() == 1 and Game.get_encounter_preview().is_empty(), "final normal chain advances once and closes intel")
	_check(Game.current_run.battle_history.size() == 2, "normal chain records both battles")
	_check(is_equal_approx(RunScoreResolver.new()._node_battle_weight({"type": "normal_battle", "encounter_queue": ["scout", "guardian"]}), 2.0), "score denominator includes both encounters")

	Game.start_new_run("balanced", 4242)
	var hazard_id: String = Game.developer_prepare_encounter_chain(true)
	Game.select_map_node(hazard_id)
	for index: int in 3:
		var data: Dictionary = Game.get_encounter_preview()
		_check(data["index"] == index + 1 and data["total"] == 3, "hazard counter matches wave")
		var facility: Control = load("res://scenes/facility/Facility.tscn").instantiate() as Control
		add_child(facility)
		await get_tree().process_frame
		await get_tree().process_frame
		dialog = facility.get("_enemy_dialog") as EnemyEncounterDialog
		_check(dialog != null and dialog.visible and dialog.preview_data["index"] == index + 1, "hazard opens next enemy before every battle")
		facility.queue_free()
		await get_tree().process_frame
		_check(Game.start_active_encounter(), "hazard confirm starts wave")
		_win(String(data["enemy_id"]))
		_check(Game.current_screen_hint == "reward", "every hazard wave opens rewards")
		Game.skip_reward()
		_check(Game.get_current_step_index() == (1 if index == 2 else 0), "hazard step only advances after last wave")
	_check(Game.current_screen_hint == "map", "completed hazard returns to map")

	Game.start_new_run("balanced", 4242)
	Game.current_run.infinite_mode = true
	InfiniteScoreResolver.new().start_fresh(Game.current_run)
	chain_id = Game.developer_prepare_encounter_chain()
	Game.select_map_node(chain_id)
	for index: int in 2:
		var data: Dictionary = Game.get_encounter_preview()
		var unit: UnitState = data["unit"] as UnitState
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
		engine.setup(Game.current_run, String(data["enemy_id"]))
		_check(unit.hp == engine.battle_state.enemy.hp and unit.attack == engine.battle_state.enemy.attack and unit.speed == engine.battle_state.enemy.speed, "preview and battle share infinite stat scaling")
		_check(unit.temporary_card_modifiers == engine.battle_state.enemy.temporary_card_modifiers, "preview and battle share card grades and overflow bonuses")
		engine.battle_state.winner = "player"
		engine.battle_state.battle_time = 20.0
		var summary: Dictionary = engine.build_summary()
		engine.dispose()
		Game.complete_battle(summary)
		var score: int = int(InfiniteScoreResolver.new().calculate(Game.current_run)["total_score"])
		Game.complete_battle(summary)
		_check(int(InfiniteScoreResolver.new().calculate(Game.current_run)["total_score"]) == score and EncounterSeries.cleared(Game.get_active_map_node()) == index + 1, "infinite results are unique per chained encounter")
		Game.skip_reward()
		if index == 0: Game.start_active_encounter()
	_check(Game.current_run.battle_history.size() == 2 and Game.get_current_step_index() == 1, "infinite chain does not drop its second result")

	Game.start_new_run("balanced", 4242)
	first = Game.get_current_step_data()["nodes"][0]
	Game.select_map_node(String(first["id"]))
	_win(String(first["enemy_id"]))
	var location: Dictionary = Game._get_active_node_location()
	var legacy: Dictionary = Game.get_active_map_node()
	legacy.erase("encounters_cleared")
	Game._set_node(int(location["step_index"]), int(location["node_index"]), legacy)
	Game.skip_reward()
	_check(Game.get_current_step_index() == 1, "old reward saves without encounter counters must not repeat battles")

	Game.start_new_run("balanced", 4242)
	hazard_id = Game.developer_prepare_encounter_chain(true)
	Game.select_map_node(hazard_id)
	Game.continue_hazard()
	_win("scout")
	Game.skip_reward()
	Game.withdraw_hazard()
	_check(Game.get_current_step_index() == 1 and Game.get_encounter_preview().is_empty(), "withdrawal ends hazard without another preview")

	Game.start_new_run("balanced", 4242)
	chain_id = Game.developer_prepare_encounter_chain()
	Game.select_map_node(chain_id)
	Game.complete_battle({"enemy_id": "scout", "winner": "enemy", "player_hp": 0, "battle_time": 5.0})
	_check(Game.current_screen_hint == "result" and Game.get_encounter_preview().is_empty(), "defeat never offers next enemy")
	_check(not Game.start_active_encounter(), "cannot enter encounters after defeat")
	Game.start_new_run("balanced", 4242)
	Game.settings["developer_mode"] = false
	_check(Game.developer_prepare_encounter_chain() == "", "fixtures require developer mode")
	if _failed: get_tree().quit(1)
	else:
		print("ENCOUNTER_PREVIEW_SMOKE_OK checks=%d" % _checks)
		get_tree().quit()
