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
	var lesson_observations: Dictionary = {}
	for _iteration: int in range(1000):
		var step: Dictionary = battle.call("get_tutorial_step_data")
		var mode: String = String(step.get("mode", ""))
		_capture_lesson_observations(step, battle, engine, lesson_observations)
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
				_try_queue_exam_card(battle, engine)
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
	else:
		_assert_lesson_outcome(tutorial_id, engine, lesson_observations)
	battle.queue_free()
	await get_tree().process_frame
	Game.clear_battle_tutorial()


func _try_queue_tutorial_card(battle: Node, engine: RealtimeBattleEngine, card_id: String) -> bool:
	for runtime_state: CardRuntimeState in engine.battle_state.player.card_runtime_states:
		if runtime_state.card_id == card_id and runtime_state.can_use():
			battle.call("_on_card_requested", runtime_state.runtime_id)
			return true
	return false


func _try_queue_exam_card(battle: Node, engine: RealtimeBattleEngine) -> bool:
	var player: UnitState = engine.battle_state.player
	if player.active_slots_used >= player.active_slot_max:
		return false
	if _enemy_has_interruptible_card(engine) and _try_queue_tutorial_card(battle, engine, "interrupt_shot"):
		return true
	if player.shield < 4 and _try_queue_tutorial_card(battle, engine, "guard"):
		return true
	if (player.hp <= player.max_hp - 6 or not player.statuses.is_empty()) and _try_queue_tutorial_card(battle, engine, "field_medic"):
		return true
	if _try_queue_tutorial_card(battle, engine, "quick_slash"):
		return true
	if not engine.battle_state.get_active_instances_for_side("enemy").is_empty() and _try_queue_tutorial_card(battle, engine, "delay_step"):
		return true
	return false


func _enemy_has_interruptible_card(engine: RealtimeBattleEngine) -> bool:
	for instance: ActiveCardInstance in engine.battle_state.active_instances:
		if instance.owner_side == "enemy" and instance.interruptible:
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


func _capture_lesson_observations(
	step: Dictionary,
	battle: Node,
	engine: RealtimeBattleEngine,
	observations: Dictionary
) -> void:
	var key: String = String(step.get("key", ""))
	if not observations.has(key):
		observations[key] = true
	match key:
		"slots_full":
			observations["slots_used"] = engine.battle_state.player.active_slots_used
			observations["slots_target"] = String(step.get("target", ""))
			observations["slots_rect"] = battle.call("_get_tutorial_target_rect")
		"status_intro":
			observations["status_target"] = String(step.get("target", ""))
			observations["status_rect"] = battle.call("_get_tutorial_target_rect")
			observations["statuses_seen"] = engine.battle_state.player.has_status("bleed") and engine.battle_state.player.has_status("weak")
		"shield_resource_value":
			observations["shield_target"] = String(step.get("target", ""))
			observations["shield_rect"] = battle.call("_get_tutorial_target_rect")
			observations["shield_before_spend"] = engine.battle_state.player.shield
		"timeline_control_observe_stop":
			if not observations.has("stop_start"):
				observations["stop_start"] = _active_remaining(engine, "enemy", "heavy_swing")
		"timeline_control_reverse":
			if not observations.has("stop_end"):
				observations["stop_end"] = _active_remaining(engine, "enemy", "heavy_swing")
		"timeline_control_observe_reverse":
			if not observations.has("reverse_start"):
				observations["reverse_start"] = _active_remaining(engine, "enemy", "heavy_swing")
		"timeline_control_heavy":
			if not observations.has("reverse_end"):
				observations["reverse_end"] = _active_remaining(engine, "enemy", "heavy_swing")
		"growth_compare":
			observations["growth_after_first"] = float(Dictionary(engine.battle_state.player.temporary_card_modifiers.get("self_tuning_edge", {})).get("damage", 0.0))
		"auto_queue_explain":
			observations["generated_slash"] = _has_auto_instance(engine, "quick_slash")
		"auto_queue_complete":
			observations["generated_turret"] = _has_auto_instance(engine, "auto_turret")
			observations["auto_complete_target"] = String(step.get("target", ""))
		"exam_battle":
			observations["exam_target"] = String(step.get("target", ""))


func _assert_lesson_outcome(tutorial_id: String, engine: RealtimeBattleEngine, observations: Dictionary) -> void:
	match tutorial_id:
		"slots_recast":
			_check(int(observations.get("slots_used", -1)) == 3, "Slots lesson did not fill all three active slots")
			_check(String(observations.get("slots_target", "")) == "player_slots", "Slots lesson did not focus the battery cells")
			var slots_rect: Rect2 = observations.get("slots_rect", Rect2()) as Rect2
			_check(slots_rect.size.x >= 90.0 and slots_rect.size.x < 150.0, "Slots focus rectangle is too broad: %s" % [slots_rect])
			_check(_has_event(engine, "resolve_card", "guard"), "Slots lesson did not resolve Guard")
			_check(_has_event(engine, "resolve_card", "quick_slash"), "Slots lesson did not resolve Quick Slash")
			_check(_card_ready(engine, "quick_slash"), "Slots lesson completed before Quick Slash became Ready")
		"interrupts":
			_check(_has_event(engine, "interrupt_card", "heavy_swing"), "Interrupt lesson did not cancel enemy Heavy Swing")
		"statuses":
			_check(bool(observations.get("statuses_seen", false)), "Status lesson did not apply Bleed and Weak")
			_check(String(observations.get("status_target", "")) == "player_status_row", "Status lesson did not focus the status row")
			var status_rect: Rect2 = observations.get("status_rect", Rect2()) as Rect2
			_check(status_rect.size.y < 60.0, "Status focus rectangle is too broad: %s" % [status_rect])
			_check(_has_event(engine, "status_damage", ""), "Status lesson did not demonstrate bleed damage")
			_check(_has_event(engine, "resolve_card", "field_medic"), "Status lesson did not resolve Field Medic")
			_check(not engine.battle_state.player.has_status("bleed") and not engine.battle_state.player.has_status("weak"), "Field Medic did not cleanse the tutorial statuses")
		"shield_resource":
			_check(String(observations.get("shield_target", "")) == "player_shield", "Shield lesson did not focus the shield value")
			_check(int(observations.get("shield_before_spend", 0)) >= 4, "Shield lesson did not build enough shield for Aegis Ram")
			_check(_event_result_int(engine, "prepare_card", "aegis_ram", "shield_cost") == 4, "Aegis Ram did not pay four shield when committed")
			_check(_has_event(engine, "resolve_card", "aegis_ram"), "Shield lesson did not resolve Aegis Ram")
		"timeline_control":
			var stop_start: float = float(observations.get("stop_start", -100.0))
			var stop_end: float = float(observations.get("stop_end", 100.0))
			var reverse_start: float = float(observations.get("reverse_start", -100.0))
			var reverse_end: float = float(observations.get("reverse_end", -100.0))
			_check(absf(stop_end - stop_start) <= 0.25, "Chronostasis did not hold enemy cast position: %.2f -> %.2f" % [stop_start, stop_end])
			_check(reverse_end - reverse_start >= 0.8, "Entropy Reversal did not move the enemy card backward: %.2f -> %.2f" % [reverse_start, reverse_end])
			_check(_event_shifted_earlier(engine, "haste_focus", "heavy_swing", 3.0), "Haste Focus did not pull Heavy Swing toward zero")
		"recast_combo":
			_check(_count_event(engine, "prepare_card", "quick_slash") == 2, "Recast lesson did not commit Quick Slash twice")
			_check(_has_event(engine, "resolve_card", "reload"), "Recast lesson did not resolve Reload")
		"battle_growth":
			_check(float(observations.get("growth_after_first", 0.0)) >= 1.0, "Growth lesson did not apply the first damage increase")
			var modifiers: Dictionary = Dictionary(engine.battle_state.player.temporary_card_modifiers.get("self_tuning_edge", {}))
			_check(float(modifiers.get("damage", 0.0)) >= 2.0, "Growth lesson did not retain both in-battle upgrades")
			_check(_resolve_metric_increased(engine, "self_tuning_edge", "damage"), "The second Self Tuning Edge did not deal increased damage")
		"auto_queue":
			_check(bool(observations.get("generated_slash", false)), "Sequence Loader did not leave an automatic Quick Slash on the timeline")
			_check(bool(observations.get("generated_turret", false)), "Auto Turret did not create a recursive copy")
			_check(String(observations.get("auto_complete_target", "")) == "timeline", "Automatic queue completion did not focus the generated timeline card")
		"combat_exam":
			_check(String(observations.get("exam_target", "")) == "timeline", "Combat exam did not focus the timeline during free battle")
			_check(engine.battle_state.winner == "player", "Combat exam did not finish with a player victory")


func _active_remaining(engine: RealtimeBattleEngine, side: String, card_id: String) -> float:
	for instance: ActiveCardInstance in engine.battle_state.active_instances:
		if instance.owner_side == side and instance.card_id == card_id:
			return instance.get_remaining(engine.battle_state.battle_time)
	return -1.0


func _has_auto_instance(engine: RealtimeBattleEngine, card_id: String) -> bool:
	for instance: ActiveCardInstance in engine.battle_state.active_instances:
		if instance.owner_side == "player" and instance.card_id == card_id and instance.is_auto_queued:
			return true
	return false


func _card_ready(engine: RealtimeBattleEngine, card_id: String) -> bool:
	for runtime_state: CardRuntimeState in engine.battle_state.player.card_runtime_states:
		if runtime_state.card_id == card_id and runtime_state.can_use():
			return true
	return false


func _has_event(engine: RealtimeBattleEngine, event_type: String, card_id: String) -> bool:
	return _count_event(engine, event_type, card_id) > 0


func _count_event(engine: RealtimeBattleEngine, event_type: String, card_id: String) -> int:
	var count: int = 0
	for event_data: Dictionary in engine.battle_state.battle_events:
		if String(event_data.get("event_type", "")) != event_type:
			continue
		if card_id == "" or String(event_data.get("card_id", "")) == card_id:
			count += 1
	return count


func _event_result_int(engine: RealtimeBattleEngine, event_type: String, card_id: String, field: String) -> int:
	for event_data: Dictionary in engine.battle_state.battle_events:
		if String(event_data.get("event_type", "")) == event_type and String(event_data.get("card_id", "")) == card_id:
			return int(Dictionary(event_data.get("result", {})).get(field, 0))
	return 0


func _event_shifted_earlier(engine: RealtimeBattleEngine, source_card_id: String, shifted_card_id: String, minimum_shift: float) -> bool:
	for event_data: Dictionary in engine.battle_state.battle_events:
		if String(event_data.get("event_type", "")) != "resolve_card" or String(event_data.get("card_id", "")) != source_card_id:
			continue
		var before_by_instance: Dictionary = {}
		for raw_entry: Variant in Array(event_data.get("timeline_before", [])):
			var entry: Dictionary = Dictionary(raw_entry)
			if String(entry.get("card_id", "")) == shifted_card_id:
				before_by_instance[int(entry.get("instance_id", -1))] = float(entry.get("scheduled_time", 0.0))
		for raw_entry: Variant in Array(event_data.get("timeline_after", [])):
			var entry: Dictionary = Dictionary(raw_entry)
			var instance_id: int = int(entry.get("instance_id", -1))
			if String(entry.get("card_id", "")) == shifted_card_id and before_by_instance.has(instance_id):
				if float(before_by_instance[instance_id]) - float(entry.get("scheduled_time", 0.0)) >= minimum_shift:
					return true
	return false


func _resolve_metric_increased(engine: RealtimeBattleEngine, card_id: String, metric: String) -> bool:
	var values: Array[int] = []
	for event_data: Dictionary in engine.battle_state.battle_events:
		if String(event_data.get("event_type", "")) != "resolve_card" or String(event_data.get("card_id", "")) != card_id:
			continue
		var result: Dictionary = Dictionary(event_data.get("result", {}))
		values.append(int(Dictionary(result.get("metrics", {})).get(metric, 0)))
	return values.size() >= 2 and values[1] > values[0]


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
