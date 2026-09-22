extends Control


func _ready() -> void:
	call_deferred("_capture_review")


func _capture_review() -> void:
	Localization.set_language("ja", false)
	Database.load_all()
	var catalog: Control = load("res://scenes/tutorial/BattleTutorial.tscn").instantiate() as Control
	add_child(catalog)
	for _frame_index: int in range(4):
		await get_tree().process_frame
	if not _save_capture("QQ_TUTORIAL_CATALOG_CAPTURE"):
		get_tree().quit(1)
		return
	catalog.queue_free()
	await get_tree().process_frame

	Game.begin_battle_tutorial("battle_basics")
	var battle: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control
	add_child(battle)
	for _frame_index: int in range(8):
		await get_tree().process_frame
	if not _save_capture("QQ_TUTORIAL_BATTLE_CAPTURE"):
		get_tree().quit(1)
		return

	battle.call("debug_tutorial_continue")
	await get_tree().process_frame
	var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
	for runtime_state: CardRuntimeState in engine.battle_state.player.card_runtime_states:
		if runtime_state.card_id == "quick_slash":
			battle.call("_on_card_requested", runtime_state.runtime_id)
			break
	for _frame_index: int in range(3):
		await get_tree().process_frame
	if not _save_capture("QQ_TUTORIAL_TIMELINE_CAPTURE"):
		get_tree().quit(1)
		return
	Game.clear_battle_tutorial()
	get_tree().quit(0)


func _save_capture(environment_key: String) -> bool:
	var capture_path: String = OS.get_environment(environment_key)
	if capture_path == "":
		return true
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.save_png(capture_path) != OK:
		push_error("Tutorial review could not save %s" % capture_path)
		return false
	print("TUTORIAL_CAPTURE_OK %s" % capture_path)
	return true
