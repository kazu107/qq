extends Node

var _failures: Array[String] = []


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	Game.clear_battle_tutorial()
	var catalog_scene: PackedScene = load("res://scenes/tutorial/BattleTutorial.tscn") as PackedScene
	_check(catalog_scene != null, "Tutorial catalog scene is missing")
	if catalog_scene != null:
		var catalog: Node = catalog_scene.instantiate()
		add_child(catalog)
		await get_tree().process_frame
		_check(int(catalog.call("get_tutorial_count")) == 1, "Tutorial catalog should expose one lesson")
		_check(catalog.find_child("TutorialList", true, false) != null, "Tutorial list is missing")
		_check(catalog.find_child("TutorialStart_battle_basics", true, false) != null, "Battle Basics start button is missing")
		catalog.queue_free()
		await get_tree().process_frame

	_check(Game.begin_battle_tutorial("battle_basics"), "Could not begin Battle Basics tutorial")
	var battle_scene: PackedScene = load("res://scenes/battle/Battle.tscn") as PackedScene
	_check(battle_scene != null, "Battle scene is missing")
	if battle_scene != null:
		var battle: Node = battle_scene.instantiate()
		add_child(battle)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(bool(battle.call("is_tutorial_mode")), "Tutorial did not use the regular battle scene")
		_check(battle.find_child("BattleStage3D", true, false) != null, "Tutorial is missing the 3D battle stage")
		_check(battle.find_child("BattleTutorialOverlay", true, false) != null, "Tutorial guidance overlay is missing")
		_check(bool(battle.call("is_tutorial_time_paused")), "Tutorial should start paused")

		battle.call("debug_tutorial_continue")
		await get_tree().process_frame
		_check(int(battle.call("get_tutorial_step")) == 1, "Tutorial did not advance to attack card input")
		var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
		var quick_slash_runtime_id: String = ""
		for runtime_state: CardRuntimeState in engine.battle_state.player.card_runtime_states:
			if runtime_state.card_id == "quick_slash":
				quick_slash_runtime_id = runtime_state.runtime_id
				break
		_check(quick_slash_runtime_id != "", "Quick Slash runtime card is missing")
		if quick_slash_runtime_id != "":
			battle.call("_on_card_requested", quick_slash_runtime_id)
			await get_tree().process_frame
			_check(engine.battle_state.timeline.size() >= 1, "Tutorial card was not queued on the real timeline")
			_check(int(battle.call("get_tutorial_step")) == 2, "Tutorial did not pause on the timeline explanation")
			_check(bool(battle.call("is_tutorial_time_paused")), "Timeline explanation should pause battle time")
			_check(is_zero_approx(engine.battle_state.battle_time), "Battle time moved before the timeline explanation finished")
			battle.call("debug_tutorial_continue")
			await get_tree().process_frame
			_check(not bool(battle.call("is_tutorial_time_paused")), "Battle time did not resume after the timeline explanation")
			_check(engine.battle_state.battle_time > 0.0, "Real battle engine did not advance after tutorial resume")
			_advance_tutorial_until(battle, 4)
			_check(int(battle.call("get_tutorial_step")) == 4, "Attack resolution did not advance the guide")
			battle.call("debug_tutorial_continue")
			_queue_tutorial_card(battle, engine, "guard")
			_check(int(battle.call("get_tutorial_step")) == 6, "Guard was not queued through the guide")
			battle.call("debug_tutorial_continue")
			_advance_tutorial_until(battle, 8)
			_check(int(battle.call("get_tutorial_step")) == 8, "Guard resolution did not advance the guide")
			battle.call("debug_tutorial_continue")
			_queue_tutorial_card(battle, engine, "delay_step")
			_check(int(battle.call("get_tutorial_step")) == 10, "Delay Step was not queued through the guide")
			battle.call("debug_tutorial_continue")
			_advance_tutorial_until(battle, 12)
			_check(int(battle.call("get_tutorial_step")) == 12, "Delay Step resolution did not advance the guide")
			battle.call("debug_tutorial_continue")
			_advance_tutorial_until(battle, 14)
			_check(int(battle.call("get_tutorial_step")) == 14, "Fatigue did not complete the guide")
			_check(bool(battle.call("is_tutorial_time_paused")), "Completed tutorial should pause on its summary")
		battle.queue_free()
		await get_tree().process_frame

	Game.clear_battle_tutorial()
	if _failures.is_empty():
		print("BATTLE_TUTORIAL_SMOKE_OK catalog, regular battle stage, guided pause, real timeline")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)


func _queue_tutorial_card(battle: Node, engine: RealtimeBattleEngine, card_id: String) -> void:
	for runtime_state: CardRuntimeState in engine.battle_state.player.card_runtime_states:
		if runtime_state.card_id == card_id:
			battle.call("_on_card_requested", runtime_state.runtime_id)
			return
	_failures.append("Tutorial card runtime is missing: %s" % card_id)


func _advance_tutorial_until(battle: Node, target_step: int) -> void:
	for _tick: int in range(240):
		if int(battle.call("get_tutorial_step")) == target_step:
			return
		battle.call("_process_tutorial_battle", 0.1)
