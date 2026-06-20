extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.set_developer_mode_enabled(false)
	call_deferred("_run")


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/title/Title.tscn")
	var title_scene: Node = await _wait_for_scene("Title")
	if _failed or title_scene == null:
		return

	var developer_toggle: Button = title_scene.find_child("DeveloperModeButton", true, false) as Button
	if developer_toggle == null:
		_fail("Developer mode smoke failed: title scene did not render the developer toggle")
		return
	developer_toggle.emit_signal("pressed")
	await get_tree().process_frame
	if not Game.is_developer_mode_enabled():
		_fail("Developer mode smoke failed: title toggle did not enable developer mode")
		return

	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
	var hub_scene: Node = await _wait_for_scene("Hub")
	if _failed or hub_scene == null:
		return
	var enemy_option: OptionButton = hub_scene.find_child("DebugEnemyOption", true, false) as OptionButton
	var first_card_option: OptionButton = hub_scene.find_child("DebugCardSlot0", true, false) as OptionButton
	var first_grade_option: OptionButton = hub_scene.find_child("DebugCardGradeSlot0", true, false) as OptionButton
	var custom_battle_button: Button = hub_scene.find_child("DevCustomBattleStart", true, false) as Button
	if enemy_option == null or first_card_option == null or first_grade_option == null or custom_battle_button == null:
		_fail("Developer mode smoke failed: custom battle lab controls were missing")
		return
	if not _select_option_by_metadata(enemy_option, "brute") \
	or not _select_option_by_metadata(first_card_option, "meteor_crash") \
	or not _select_option_by_metadata(first_grade_option, "3"):
		_fail("Developer mode smoke failed: custom battle lab could not select requested options")
		return
	custom_battle_button.emit_signal("pressed")
	var custom_battle_scene: Node = await _wait_for_scene("Battle")
	if _failed or custom_battle_scene == null:
		return
	var custom_engine: RealtimeBattleEngine = custom_battle_scene.get("_engine") as RealtimeBattleEngine
	if custom_engine == null or custom_engine.battle_state == null or custom_engine.battle_state.enemy.unit_id != "brute":
		_fail("Developer mode smoke failed: custom battle lab did not open the requested enemy")
		return
	if Game.current_run == null or not Game.current_run.equipped_cards.has("meteor_crash"):
		_fail("Developer mode smoke failed: custom battle lab did not apply the requested loadout")
		return
	if CardUpgradeResolver.get_tier(Game.current_run, "meteor_crash") != 3:
		_fail("Developer mode smoke failed: custom battle lab did not apply the requested card grade")
		return

	Game.developer_start_run("balanced")
	get_tree().change_scene_to_file("res://scenes/map/Map.tscn")
	var map_scene: Node = await _wait_for_scene("Map")
	if _failed or map_scene == null:
		return

	var map_panel: DeveloperPanel = map_scene.find_child("DeveloperPanel", true, false) as DeveloperPanel
	if map_panel == null:
		_fail("Developer mode smoke failed: map scene did not render the developer panel")
		return
	if map_panel.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("Developer mode smoke failed: developer panel background should not block covered UI")
		return
	var panel_toggle: Button = map_panel.find_child("DeveloperPanelToggle", true, false) as Button
	var panel_content: Control = map_panel.find_child("DeveloperPanelContent", true, false) as Control
	if panel_toggle == null or panel_content == null:
		_fail("Developer mode smoke failed: developer panel collapse controls were missing")
		return
	panel_toggle.emit_signal("pressed")
	await get_tree().process_frame
	if not map_panel.is_collapsed() or panel_content.visible:
		_fail("Developer mode smoke failed: developer panel did not collapse")
		return
	panel_toggle.emit_signal("pressed")
	await get_tree().process_frame
	if map_panel.is_collapsed() or not panel_content.visible:
		_fail("Developer mode smoke failed: developer panel did not expand")
		return

	var gold_before: int = Game.current_run.gold
	var add_gold_button: Button = map_panel.find_child("DevAddGold", true, false) as Button
	if add_gold_button == null:
		_fail("Developer mode smoke failed: map developer gold action was missing")
		return
	if add_gold_button.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("Developer mode smoke failed: developer buttons should remain clickable")
		return
	add_gold_button.emit_signal("pressed")
	await get_tree().process_frame
	if Game.current_run.gold != gold_before + 50:
		_fail("Developer mode smoke failed: map developer gold action did not apply")
		return

	var relics_before: int = Game.current_run.relics.size()
	var grant_relic_button: Button = map_panel.find_child("DevGrantRelic", true, false) as Button
	if grant_relic_button == null:
		_fail("Developer mode smoke failed: map developer relic action was missing")
		return
	grant_relic_button.emit_signal("pressed")
	await get_tree().process_frame
	if Game.current_run.relics.size() <= relics_before:
		_fail("Developer mode smoke failed: map developer relic action did not apply")
		return

	var debug_event_button: Button = map_panel.find_child("DevEvent_salvage_cache", true, false) as Button
	if debug_event_button == null:
		_fail("Developer mode smoke failed: event-specific debug action was missing")
		return
	debug_event_button.emit_signal("pressed")

	var facility_scene: Node = await _wait_for_scene("Facility")
	if _failed or facility_scene == null:
		return
	if String(Game.get_active_event_data().get("id", "")) != "salvage_cache":
		_fail("Developer mode smoke failed: event-specific debug action did not open the requested event")
		return

	var event_choices: Array = Array(Game.get_active_event_data().get("choices", []))
	for raw_choice in event_choices:
		var choice_data: Dictionary = Dictionary(raw_choice)
		if not bool(choice_data.get("enabled", true)):
			continue
		Game.resolve_event_choice(String(choice_data.get("id", "")))
		break
	get_tree().change_scene_to_file("res://scenes/map/Map.tscn")
	map_scene = await _wait_for_scene("Map")
	if _failed or map_scene == null:
		return

	Game.developer_open_battle("scout")
	get_tree().change_scene_to_file("res://scenes/battle/Battle.tscn")
	var battle_scene: Node = await _wait_for_scene("Battle")
	if _failed or battle_scene == null:
		return

	var battle_panel: DeveloperPanel = battle_scene.find_child("DeveloperPanel", true, false) as DeveloperPanel
	if battle_panel == null:
		_fail("Developer mode smoke failed: battle scene did not render the developer panel")
		return

	var win_button: Button = battle_panel.find_child("DevWinBattle", true, false) as Button
	if win_button == null:
		_fail("Developer mode smoke failed: battle force victory action was missing")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(win_button) or win_button.get_parent() == null:
		_fail("Developer mode smoke failed: battle developer buttons should remain usable across frames")
		return
	win_button.emit_signal("pressed")

	var reward_scene: Node = await _wait_for_scene("Reward")
	if _failed or reward_scene == null:
		return
	if Game.current_screen_hint != "reward":
		_fail("Developer mode smoke failed: force victory did not route to reward")
		return

	var reward_panel: DeveloperPanel = reward_scene.find_child("DeveloperPanel", true, false) as DeveloperPanel
	if reward_panel == null:
		_fail("Developer mode smoke failed: reward scene did not render the developer panel")
		return

	print("Developer mode smoke passed")
	get_tree().quit()


func _wait_for_scene(scene_name: String) -> Node:
	var timeout_frames: int = 180
	while timeout_frames > 0:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and String(scene.name) == scene_name:
			return scene
		timeout_frames -= 1
	_fail("Developer mode smoke failed: scene %s did not open" % scene_name)
	return null


func _select_option_by_metadata(option: OptionButton, target_id: String) -> bool:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == target_id:
			option.select(index)
			return true
	return false


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
