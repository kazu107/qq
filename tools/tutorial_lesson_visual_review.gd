extends Control


func _ready() -> void:
	call_deferred("_capture_review")


func _capture_review() -> void:
	Localization.set_language("ja", false)
	Database.load_all()
	var tutorial_id: String = OS.get_environment("QQ_TUTORIAL_REVIEW_ID")
	var target_key: String = OS.get_environment("QQ_TUTORIAL_REVIEW_STEP")
	var capture_path: String = OS.get_environment("QQ_TUTORIAL_REVIEW_CAPTURE")
	if tutorial_id == "" or target_key == "" or capture_path == "":
		push_error("Tutorial lesson review requires tutorial id, step key and capture path")
		get_tree().quit(1)
		return
	if not Game.begin_battle_tutorial(tutorial_id):
		push_error("Tutorial lesson review could not start %s" % tutorial_id)
		get_tree().quit(1)
		return
	var battle: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control
	add_child(battle)
	for _frame_index: int in range(6):
		await get_tree().process_frame
	if not await _advance_to_step(battle, target_key):
		push_error("Tutorial lesson review could not reach %s in %s" % [target_key, tutorial_id])
		get_tree().quit(1)
		return
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.save_png(capture_path) != OK:
		push_error("Tutorial lesson review could not save %s" % capture_path)
		get_tree().quit(1)
		return
	print("TUTORIAL_LESSON_CAPTURE_OK %s %s %s" % [tutorial_id, target_key, capture_path])
	Game.clear_battle_tutorial()
	get_tree().quit(0)


func _advance_to_step(battle: Node, target_key: String) -> bool:
	var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
	for _iteration: int in range(1200):
		var step: Dictionary = battle.call("get_tutorial_step_data")
		if String(step.get("key", "")) == target_key:
			for _frame_index: int in range(3):
				await get_tree().process_frame
			return true
		match String(step.get("mode", "")):
			"continue":
				battle.call("debug_tutorial_continue")
			"queue_card":
				_queue_ready_card(battle, engine, String(step.get("card_id", "")))
			"free_battle", "complete":
				return false
			_:
				battle.call("_process_tutorial_battle", 0.1)
		await get_tree().process_frame
	return false


func _queue_ready_card(battle: Node, engine: RealtimeBattleEngine, card_id: String) -> bool:
	for runtime_state: CardRuntimeState in engine.battle_state.player.card_runtime_states:
		if runtime_state.card_id == card_id and runtime_state.can_use():
			battle.call("_on_card_requested", runtime_state.runtime_id)
			return true
	return false
