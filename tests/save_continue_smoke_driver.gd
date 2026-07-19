extends Node

var _failed: bool = false
var _original_save_exists: bool = false
var _original_save_data: PackedByteArray = PackedByteArray()
var _original_save_restored: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	_capture_original_save()
	_delete_save()
	call_deferred("_run")


func _run() -> void:
	await _exercise_map_restore()
	if _failed:
		return

	await _exercise_facility_restore()
	if _failed:
		return

	await _exercise_reward_restore()
	if _failed:
		return

	await _exercise_suspended_run_slots()
	if _failed:
		return

	_restore_original_save()
	print("Save/continue smoke passed")
	get_tree().quit()


func _exercise_map_restore() -> void:
	Game.start_new_run("balanced")
	var card_id: String = Game.current_run.equipped_cards[Game.current_run.equipped_cards.size() - 1]
	if not Game.unequip_card(card_id):
		_fail("Save/continue smoke failed: could not mutate loadout before map save")
		return

	var equipped_count: int = Game.current_run.equipped_cards.size()
	var loadout_cost: int = Game.get_current_loadout_cost()
	_restore_from_disk()
	if _failed:
		return

	if Game.current_screen_hint != "map":
		_fail("Save/continue smoke failed: map save did not restore screen hint")
		return
	if Game.current_run == null or Game.current_run.equipped_cards.size() != equipped_count:
		_fail("Save/continue smoke failed: equipped cards were not restored on map save")
		return
	if Game.get_current_loadout_cost() != loadout_cost:
		_fail("Save/continue smoke failed: loadout cost was not restored on map save")
		return

	SceneRouter.go_to_continue_target()
	var map_scene: Node = await _wait_for_scene("Map")
	if _failed or map_scene == null:
		return

	var equipped_deck: CardHandPanel = map_scene.find_child("EquippedDeck", true, false) as CardHandPanel
	if equipped_deck == null or equipped_deck.get_child_count() != equipped_count:
		_fail("Save/continue smoke failed: continue did not reopen the map loadout view")
		return


func _exercise_facility_restore() -> void:
	Game.start_new_run("balanced")
	_prepare_first_facility("shop")
	if _failed:
		return

	var active_type: String = Game.get_active_facility_type()
	var offer_count: int = Game.get_shop_offers().size()
	_restore_from_disk()
	if _failed:
		return

	if Game.current_screen_hint != "facility" or Game.get_active_facility_type() != active_type:
		_fail("Save/continue smoke failed: facility save did not restore facility state")
		return
	if Game.get_shop_offers().size() != offer_count:
		_fail("Save/continue smoke failed: shop offers were not restored")
		return

	SceneRouter.go_to_continue_target()
	var facility_scene: Node = await _wait_for_scene("Facility")
	if _failed or facility_scene == null:
		return

	var options_box: VBoxContainer = facility_scene.find_child("FacilityOptions", true, false) as VBoxContainer
	if options_box == null or options_box.get_child_count() == 0:
		_fail("Save/continue smoke failed: continue did not reopen facility options")
		return


func _exercise_reward_restore() -> void:
	Game.start_new_run("balanced")
	var battle_node: Dictionary = _find_available_node("normal_battle")
	if battle_node.is_empty():
		_fail("Save/continue smoke failed: no opening battle node found")
		return
	if Game.select_map_node(String(battle_node.get("id", ""))) != "battle":
		_fail("Save/continue smoke failed: could not enter opening battle")
		return

	var enemy_id: String = Game.prepare_next_battle()
	if enemy_id == "":
		_fail("Save/continue smoke failed: opening battle did not resolve an enemy")
		return
	Game.complete_battle(_build_victory_summary(enemy_id))
	if Game.current_screen_hint != "reward" or Game.reward_options.is_empty():
		_fail("Save/continue smoke failed: opening battle did not create reward options")
		return

	var expected_rewards: Array[String] = Game.reward_options.duplicate()
	_restore_from_disk()
	if _failed:
		return

	if Game.current_screen_hint != "reward":
		_fail("Save/continue smoke failed: reward save did not restore screen hint")
		return
	if Game.reward_options != expected_rewards:
		_fail("Save/continue smoke failed: reward options were not restored")
		return

	SceneRouter.go_to_continue_target()
	var reward_scene: Node = await _wait_for_scene("Reward")
	if _failed or reward_scene == null:
		return

	var reward_cards: CardHandPanel = reward_scene.find_child("RewardCards", true, false) as CardHandPanel
	if reward_cards == null or reward_cards.get_child_count() != expected_rewards.size():
		_fail("Save/continue smoke failed: continue did not reopen reward cards")
		return


func _exercise_suspended_run_slots() -> void:
	Game.suspended_runs.clear()
	Game.start_new_run("balanced", 14001)
	Game.current_run.gold = 77
	Game.current_screen_hint = "map"
	Game.abandon_run_to_hub()
	if Game.current_run != null or not Game.has_suspended_run(Game.RUN_SETUP_MODE_NORMAL):
		_fail("Save/continue smoke failed: returning to hub did not suspend the normal run")
		return

	if not Game.start_arena_run("balanced", 24002):
		_fail("Save/continue smoke failed: arena run could not start for suspension coverage")
		return
	Game.current_run.gold = 88
	Game.current_screen_hint = "arena"
	Game.abandon_run_to_hub()
	if Game.current_run != null \
	or not Game.has_suspended_run(Game.RUN_SETUP_MODE_NORMAL) \
	or not Game.has_suspended_run(Game.RUN_SETUP_MODE_ARENA):
		_fail("Save/continue smoke failed: normal and arena suspension slots should coexist")
		return

	Game.current_run = null
	Game.suspended_runs = {}
	Game.settings = {}
	Game.meta_progress = {}
	Game.apply_loaded_save(SaveManager.load_save())
	if Game.current_run != null \
	or not Game.has_suspended_run(Game.RUN_SETUP_MODE_NORMAL) \
	or not Game.has_suspended_run(Game.RUN_SETUP_MODE_ARENA):
		_fail("Save/continue smoke failed: suspended run slots were not restored from disk")
		return

	var hub_scene: Control = load("res://scenes/hub/Hub.tscn").instantiate() as Control
	add_child(hub_scene)
	await get_tree().process_frame
	for button_name in ["RunStartButton", "ContinueNormalRunButton", "ArenaStartButton", "ContinueArenaRunButton"]:
		if hub_scene.find_child(button_name, true, false) == null:
			_fail("Save/continue smoke failed: hub did not render split start/continue button %s" % button_name)
			return
	hub_scene.queue_free()
	await get_tree().process_frame

	if Game.resume_suspended_run(Game.RUN_SETUP_MODE_NORMAL) != "map" \
	or Game.current_run == null \
	or Game.current_run.arena_mode \
	or Game.current_run.seed != 14001 \
	or Game.current_run.gold != 77:
		_fail("Save/continue smoke failed: normal run did not resume with its saved state")
		return
	if Game.has_suspended_run(Game.RUN_SETUP_MODE_NORMAL) or not Game.has_suspended_run(Game.RUN_SETUP_MODE_ARENA):
		_fail("Save/continue smoke failed: resuming normal should consume only the normal slot")
		return
	Game.abandon_run_to_hub()

	if Game.resume_suspended_run(Game.RUN_SETUP_MODE_ARENA) != "arena" \
	or Game.current_run == null \
	or not Game.current_run.arena_mode \
	or Game.current_run.seed != 24002 \
	or Game.current_run.gold != 88:
		_fail("Save/continue smoke failed: arena run did not resume with its saved state")
		return


func _prepare_first_facility(expected_type: String) -> void:
	var battle_node: Dictionary = _find_available_node("normal_battle")
	if battle_node.is_empty():
		_fail("Save/continue smoke failed: no opening battle node found for facility prep")
		return
	if Game.select_map_node(String(battle_node.get("id", ""))) != "battle":
		_fail("Save/continue smoke failed: could not enter opening battle for facility prep")
		return

	var enemy_id: String = Game.prepare_next_battle()
	if enemy_id == "":
		_fail("Save/continue smoke failed: opening battle prep did not resolve an enemy")
		return
	Game.complete_battle(_build_victory_summary(enemy_id))
	Game.skip_reward()

	var facility_node: Dictionary = _find_available_node(expected_type)
	if facility_node.is_empty():
		_fail("Save/continue smoke failed: no %s node found for facility save" % expected_type)
		return
	if Game.select_map_node(String(facility_node.get("id", ""))) != "facility":
		_fail("Save/continue smoke failed: selecting %s did not route to facility" % expected_type)


func _restore_from_disk() -> void:
	Game.current_run = null
	Game.meta_progress = {}
	Game.settings = {}
	Game.pending_enemy_id = ""
	Game.reward_options.clear()
	Game.last_battle_summary.clear()
	Game.current_screen_hint = "title"

	var save_data: SaveData = SaveManager.load_save()
	Game.apply_loaded_save(save_data)
	if Game.current_run == null:
		_fail("Save/continue smoke failed: current run was not restored from disk")


func _wait_for_scene(scene_name: String) -> Node:
	var timeout_frames: int = 120
	while timeout_frames > 0:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and String(scene.name) == scene_name:
			return scene
		timeout_frames -= 1
	_fail("Save/continue smoke failed: scene %s did not open" % scene_name)
	return null


func _build_victory_summary(enemy_id: String) -> Dictionary:
	var enemy_def: EnemyDef = Database.get_enemy(enemy_id)
	var enemy_name: String = enemy_id
	if enemy_def != null:
		enemy_name = enemy_def.name
	return {
		"winner": "player",
		"enemy_id": enemy_id,
		"enemy_name": enemy_name,
		"player_hp": max(1, Game.current_run.player_hp - 1),
	}


func _find_available_node(node_type: String) -> Dictionary:
	var current_step: Dictionary = Game.get_current_step_data()
	var nodes: Array = Array(current_step.get("nodes", []))
	for raw_node in nodes:
		var node_data: Dictionary = Dictionary(raw_node)
		if String(node_data.get("type", "")) == node_type and String(node_data.get("status", "")) == "available":
			return node_data
	return {}


func _delete_save() -> void:
	var absolute_path: String = ProjectSettings.globalize_path(SaveManager.SAVE_PATH)
	if FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(absolute_path)


func _capture_original_save() -> void:
	_original_save_exists = FileAccess.file_exists(SaveManager.SAVE_PATH)
	if not _original_save_exists:
		return
	var file: FileAccess = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.READ)
	if file != null:
		_original_save_data = file.get_buffer(file.get_length())


func _restore_original_save() -> void:
	if _original_save_restored:
		return
	_original_save_restored = true
	if not _original_save_exists:
		_delete_save()
		return
	var file: FileAccess = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_buffer(_original_save_data)


func _fail(message: String) -> void:
	_failed = true
	_restore_original_save()
	push_error(message)
	get_tree().quit(1)
