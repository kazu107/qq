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
	var tutorial_ids: Array[String] = []
	for tutorial: Dictionary in BattleTutorialCatalog.get_all():
		tutorial_ids.append(String(tutorial.get("id", "")))
	_check(tutorial_ids.size() == 10, "Tutorial catalog should expose ten lessons")
	_check(tutorial_ids == [
		"battle_basics",
		"slots_recast",
		"interrupts",
		"statuses",
		"shield_resource",
		"timeline_control",
		"recast_combo",
		"battle_growth",
		"auto_queue",
		"combat_exam",
	], "Tutorial catalog order changed")
	var catalog_scene: PackedScene = load("res://scenes/tutorial/BattleTutorial.tscn") as PackedScene
	_check(catalog_scene != null, "Tutorial catalog scene is missing")
	if catalog_scene != null:
		var catalog: Node = catalog_scene.instantiate()
		add_child(catalog)
		await get_tree().process_frame
		_check(int(catalog.call("get_tutorial_count")) == 10, "Tutorial catalog UI should expose ten lessons")
		_check(catalog.find_child("TutorialList", true, false) != null, "Tutorial list is missing")
		for tutorial_id: String in tutorial_ids:
			_check(catalog.find_child("TutorialStart_%s" % tutorial_id, true, false) != null, "Tutorial start button is missing: %s" % tutorial_id)
		catalog.queue_free()
		await get_tree().process_frame

	for tutorial_id: String in tutorial_ids:
		await _run_lesson(tutorial_id)

	Game.clear_battle_tutorial()
	if _failures.is_empty():
		print("BATTLE_TUTORIAL_SMOKE_OK 10 lessons, regular battle stage, guided pause, real timeline")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)


func _run_lesson(tutorial_id: String) -> void:
	_check(Game.begin_battle_tutorial(tutorial_id), "Could not begin tutorial: %s" % tutorial_id)
	var battle_scene: PackedScene = load("res://scenes/battle/Battle.tscn") as PackedScene
	_check(battle_scene != null, "Battle scene is missing")
	if battle_scene == null:
		return
	var battle: Node = battle_scene.instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bool(battle.call("is_tutorial_mode")), "Tutorial did not use the regular battle scene: %s" % tutorial_id)
	_check(battle.find_child("BattleStage3D", true, false) != null, "Tutorial is missing the 3D battle stage: %s" % tutorial_id)
	_check(battle.find_child("BattleTutorialOverlay", true, false) != null, "Tutorial guidance overlay is missing: %s" % tutorial_id)
	_check(bool(battle.call("is_tutorial_time_paused")), "Tutorial should start paused: %s" % tutorial_id)
	var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
	var completed: bool = false
	var shield_focus_checked: bool = false
	for _iteration: int in range(1000):
		var step: Dictionary = battle.call("get_tutorial_step_data")
		var mode: String = String(step.get("mode", ""))
		if tutorial_id == "battle_basics" and String(step.get("key", "")) == "basic_shield" and not shield_focus_checked:
			shield_focus_checked = true
			var shield_rect: Rect2 = battle.call("_get_tutorial_target_rect")
			_check(String(step.get("target", "")) == "player_shield", "Battle Basics should target only the shield value in lesson 5")
			_check(shield_rect.size.x >= 64.0 and shield_rect.size.x < 100.0 and shield_rect.size.y >= 30.0 and shield_rect.size.y < 50.0, "Battle Basics shield focus rectangle is invalid: %s" % [shield_rect])
		if mode == "complete":
			completed = true
			break
		var previous_step: int = int(battle.call("get_tutorial_step"))
		match mode:
			"continue":
				battle.call("debug_tutorial_continue")
			"queue_card":
				_try_queue_tutorial_card(battle, engine, String(step.get("card_id", "")))
			"free_battle":
				engine.battle_state.enemy.hp = 1
				_try_queue_tutorial_card(battle, engine, "quick_slash")
			_:
				battle.call("_process_tutorial_battle", 0.1)
		if int(battle.call("get_tutorial_step")) == previous_step and mode in ["continue", "queue_card"]:
			await get_tree().process_frame
		else:
			battle.call("_process_tutorial_battle", 0.1)
	_check(completed, "Tutorial did not reach completion: %s at step %d (%s)" % [tutorial_id, int(battle.call("get_tutorial_step")), str(battle.call("get_tutorial_step_data"))])
	if completed:
		_check(bool(battle.call("is_tutorial_time_paused")), "Completed tutorial should pause on its summary: %s" % tutorial_id)
	if tutorial_id == "battle_basics":
		_check(shield_focus_checked, "Battle Basics did not show the lesson 5 shield focus")
		_assert_basic_lesson_events(engine)
	battle.queue_free()
	await get_tree().process_frame
	Game.clear_battle_tutorial()


func _try_queue_tutorial_card(battle: Node, engine: RealtimeBattleEngine, card_id: String) -> bool:
	for runtime_state: CardRuntimeState in engine.battle_state.player.card_runtime_states:
		if runtime_state.card_id == card_id and runtime_state.can_use():
			battle.call("_on_card_requested", runtime_state.runtime_id)
			return true
	return false


func _assert_basic_lesson_events(engine: RealtimeBattleEngine) -> void:
	var shield_blocked: bool = false
	var delayed_enemy_card: bool = false
	var enemy_queued_near_delay: bool = false
	var fatigue_resolved: bool = false
	for event_data: Dictionary in engine.battle_state.battle_events:
		var event_type: String = String(event_data.get("event_type", ""))
		var card_id: String = String(event_data.get("card_id", ""))
		var result: Dictionary = Dictionary(event_data.get("result", {}))
		if event_type == "resolve_card" and card_id == "quick_slash" and bool(result.get("fully_blocked", false)):
			shield_blocked = true
		elif event_type == "resolve_card" and card_id == "delay_step":
			delayed_enemy_card = _timeline_card_shifted(event_data, "quick_slash", 1.0)
		elif event_type == "prepare_card" and card_id == "quick_slash":
			var event_time: float = float(event_data.get("time", 0.0))
			for raw_entry: Variant in Array(event_data.get("timeline_after", [])):
				var entry: Dictionary = Dictionary(raw_entry)
				if String(entry.get("owner_side", "")) == "player" and String(entry.get("card_id", "")) == "delay_step":
					var remaining: float = float(entry.get("scheduled_time", 0.0)) - event_time
					enemy_queued_near_delay = remaining >= 0.0 and remaining <= 1.1
		elif event_type == "fatigue_card":
			fatigue_resolved = true
	_check(shield_blocked, "Battle Basics did not fully block the enemy Quick Slash with shield")
	_check(enemy_queued_near_delay, "Battle Basics did not queue the enemy Quick Slash near 1 second remaining")
	_check(delayed_enemy_card, "Battle Basics did not move the enemy Quick Slash later on the timeline")
	_check(fatigue_resolved, "Battle Basics did not resolve the fatigue card")


func _timeline_card_shifted(event_data: Dictionary, card_id: String, minimum_shift: float) -> bool:
	var before_by_instance: Dictionary = {}
	for raw_entry: Variant in Array(event_data.get("timeline_before", [])):
		var entry: Dictionary = Dictionary(raw_entry)
		if String(entry.get("card_id", "")) == card_id:
			before_by_instance[int(entry.get("instance_id", -1))] = float(entry.get("scheduled_time", 0.0))
	for raw_entry: Variant in Array(event_data.get("timeline_after", [])):
		var entry: Dictionary = Dictionary(raw_entry)
		var instance_id: int = int(entry.get("instance_id", -1))
		if String(entry.get("card_id", "")) == card_id \
		and before_by_instance.has(instance_id) \
		and float(entry.get("scheduled_time", 0.0)) - float(before_by_instance[instance_id]) >= minimum_shift:
			return true
	return false
