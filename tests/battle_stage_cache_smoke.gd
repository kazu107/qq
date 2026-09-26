extends Node

func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	await SceneRouter.warm_battle_stage_cache_async()
	if not _check(SceneRouter.has_cached_battle_stage(), "startup did not build the battle stage"):
		return
	var cached_stage: BattleStage3D = SceneRouter.get("_battle_stage_cache") as BattleStage3D
	var stage_id: int = cached_stage.get_instance_id()
	if not _check(cached_stage.process_mode == Node.PROCESS_MODE_DISABLED, "cached stage is still processing"):
		return
	if not _check(cached_stage.get_combat_actor("player").get_visual_profile_id() == "balanced", "first player model was not prepared"):
		return
	if not _check(cached_stage.get_combat_actor("enemy").get_visual_profile_id() == "scout", "first enemy model was not prepared"):
		return
	Game.current_run = RunState.from_starter(Database.get_starter("balanced"), 42)
	Game.pending_enemy_id = "scout"
	var selected_cards: Array = SceneRouter.call("_current_battle_card_ids")
	for card_id: String in Game.current_run.equipped_cards:
		if not _check(selected_cards.has(card_id), "current deck art was omitted from preloading"):
			return
	for card_id: String in Database.get_enemy("scout").cards:
		if not _check(selected_cards.has(card_id), "current enemy art was omitted from preloading"):
			return
	Game.current_run = null
	Game.pending_enemy_id = ""

	for tutorial_id: String in ["battle_basics", "slots_recast"]:
		if not _check(Game.begin_battle_tutorial(tutorial_id), "tutorial setup failed"):
			return
		if not _check(not Array(SceneRouter.call("_current_battle_card_ids")).is_empty(), "tutorial art was omitted from preloading"):
			return
		var battle: Node = load("res://scenes/battle/Battle.tscn").instantiate()
		add_child(battle)
		await get_tree().process_frame
		var active_stage: BattleStage3D = battle.get("_battle_stage") as BattleStage3D
		if not _check(active_stage != null and active_stage.get_instance_id() == stage_id, "battle rebuilt its 3D stage"):
			return
		if not _check(active_stage.get_combat_actor("player") != null, "reused stage lost its combatants"):
			return
		var stage_viewport: SubViewport = active_stage.get_node("BattleStageViewport") as SubViewport
		if not _check(stage_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "reused stage did not resume rendering"):
			return
		SceneRouter.call("_store_battle_stage", battle.call("detach_battle_stage_for_cache"))
		battle.queue_free()
		await get_tree().process_frame
		Game.clear_battle_tutorial()
		if not _check(SceneRouter.has_cached_battle_stage(), "scene exit did not retain the stage"):
			return
		if not _check(stage_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "cached stage kept rendering offscreen"):
			return

	print("BATTLE_STAGE_CACHE_SMOKE_OK reused 3D stage across two battles")
	get_tree().quit(0)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("Battle stage cache smoke failed: %s" % message)
	get_tree().quit(1)
	return false
