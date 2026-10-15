extends Node


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		push_error("Event progression: " + message)
		get_tree().quit(1)
		assert(value, message)


func _run() -> void:
	Game.start_new_run("balanced", 4242)
	var service: EventService = EventService.new()
	var used: Array[String] = Database.get_all_event_ids()
	var cards: Array[String] = Game.get_unlocked_card_ids()
	var relics: Array[String] = Game.get_unlocked_relic_ids()
	var none: Array[String] = []
	for area: int in range(1, 61):
		for exhausted: bool in [false, true]:
			var data: Dictionary = service.build_event_node(area, Game.current_run, used if exhausted else none, cards, relics)
			_check(not String(data.get("event_id", "")).is_empty(), "No event at area %d" % area)
			_check(Array(data.get("event_choices", [])).size() == 3, "Empty choices at area %d" % area)
	var scaled: Dictionary = service.build_specific_event_node("salvage_cache", 6, Game.current_run, cards, relics)
	var gold: Dictionary = Array(scaled["event_choices"]).filter(func(choice: Dictionary) -> bool: return choice["id"] == "take_gold")[0]
	_check(gold["effects"][0]["amount"] == 54, "Fallback changed actual-area reward scaling")
	_check(service._resolve_scalar({"by_area": {"1": 10, "2": 20, "3": 30}}, 4, {}) == 10, "Later-area table resolved to zero")
	_check(service._resolve_scalar({"by_area": {"1": 10, "3": 30}}, 6, {}) == 30, "Later chapter did not use its third-area value")
	_check(service._resolve_scalar({"by_area": {"1": 10, "4": 99}}, 4, {}) == 99, "Explicit later-area value was ignored")
	_check(service._resolve_scalar({"by_area": {"1": 10, "default": 40}}, 4, {}) == 40, "Explicit default value was ignored")
	Database.events["future_area_test"] = {"id": "future_area_test", "areas": [4], "choices": [{"id": "next", "label": "Next", "effects": []}]}
	Database.event_order.append("future_area_test")
	_check(service._pick_template(4, [])["id"] == "future_area_test", "Absolute-area authored content did not take priority")
	Database.event_order.erase("future_area_test")
	Database.events.erase("future_area_test")

	_open_later_event()
	var event_data: Dictionary = Game.get_active_event_data().duplicate(true)
	_check(Game.get_active_map_node()["area"] == 4 and event_data["choices"].size() == 3, "Second-chapter event was not prepared")
	await _check_event_ui(3)
	_check(Game.get_active_event_data() == event_data, "Opening the UI rerolled valid choices")
	var save: SaveData = SaveData.from_dict(Game.build_save_data("facility").to_dict())
	Game.apply_loaded_save(save)
	_check(Game.get_active_event_data() == event_data, "Save round trip rerolled valid choices")

	for saved_id: String in ["", "salvage_cache", "missing_event_id"]:
		var location: Dictionary = Game._get_active_node_location()
		var node: Dictionary = Game.get_active_map_node().duplicate(true)
		node["event_id"] = saved_id
		node["event_choices"] = []
		Game._set_node(int(location["step_index"]), int(location["node_index"]), node)
		var resources: Array = _resources()
		Game.apply_loaded_save(SaveData.from_dict(Game.build_save_data("facility").to_dict()))
		var repaired: Dictionary = Game.get_active_event_data().duplicate(true)
		_check(repaired["choices"].size() == 3, "Saved empty event was not repaired: " + saved_id)
		if saved_id == "salvage_cache": _check(repaired["id"] == saved_id, "Repair replaced a known event identity")
		_check(_resources() == resources, "Repair granted rewards before choosing")
		_check(Game.get_active_event_data() == repaired, "Repair rerolled on a second read")
		_check(SaveManager.has_pending_save() and SaveManager.flush_requested_save(), "Repaired event was not persisted")
		Game.apply_loaded_save(SaveManager.load_save())
		# JSON reads numbers as floats; canonicalize both snapshots without changing game data.
		_check(JSON.parse_string(JSON.stringify(Game.get_active_event_data())) == JSON.parse_string(JSON.stringify(repaired)), "Persisted repair was lost on continue")
		await _check_event_ui(3)
	var reward_location: Dictionary = Game._get_active_node_location()
	var safe_node: Dictionary = Game.get_active_map_node().duplicate(true)
	safe_node.merge(service.build_specific_event_node("salvage_cache", 4, Game.current_run, cards, relics), true)
	Game._set_node(reward_location["step_index"], reward_location["node_index"], safe_node)
	var before_step: int = Game.get_current_step_index()
	var before_gold: int = Game.current_run.gold
	var reward: Dictionary = Array(Game.get_active_event_data()["choices"]).filter(func(choice: Dictionary) -> bool: return choice["id"] == "take_gold")[0]
	_check(not reward.is_empty(), "Event had no usable choice")
	_check(Game.resolve_event_choice(reward["id"]) != "" and Game.get_current_step_index() == before_step + 1, "Choosing an event did not advance exactly once")
	var applied_gold: int = Game.current_run.gold
	_check(Game.resolve_event_choice(reward["id"]) == "" and Game.current_run.gold == applied_gold, "Repeated choice granted a second reward")
	_check(Game.current_run.gold == before_gold + 42, "Selected event did not grant its actual-area reward")

	_open_later_event()
	var templates: Dictionary = Database.events.duplicate(true)
	Database.events.clear()
	var location: Dictionary = Game._get_active_node_location()
	var empty: Dictionary = Game.get_active_map_node().duplicate(true)
	empty["event_id"] = ""
	empty["event_choices"] = []
	Game._set_node(location["step_index"], location["node_index"], empty)
	await _check_event_ui(1, true)
	var unchanged: Array = _resources()
	var empty_step: int = Game.get_current_step_index()
	Game.leave_facility()
	_check(_resources() == unchanged and Game.get_current_step_index() == empty_step + 1, "Empty-event exit altered resources or failed to advance")
	Database.events = templates
	print("EVENT_PROGRESSION_SMOKE_OK areas 1-60, exhausted pools, authored priority, actual-area scaling, chapter-2 UI, empty-save repair/persistence, no rerolls/double rewards, safe empty-content exit")
	get_tree().quit()


func _open_later_event() -> void:
	Game.start_new_run("balanced", 4242)
	Game.current_run.map_state = MapGenerator.new().generate_run(4242, 4)
	Game.settings["developer_mode"] = true
	for index: int in 8: _check(Game.developer_advance_map_route(), "Could not reach chapter 2")
	for node: Dictionary in Game.get_current_step_data()["nodes"]:
		if node["type"] == "event" and node["status"] == "available":
			_check(Game.select_map_node(node["id"]) == "facility", "Chapter-2 event selection failed")
			return
	_check(false, "No connected chapter-2 event")


func _check_event_ui(count: int, fallback: bool = false) -> void:
	var screen: Control = load("res://scenes/facility/Facility.tscn").instantiate() as Control
	add_child(screen)
	await get_tree().process_frame
	var list: VBoxContainer = screen.find_child("EventChoiceList", true, false) as VBoxContainer
	_check(list != null and list.get_child_count() == count, "Incorrect displayed event choice count")
	if fallback:
		var leave: Button = screen.find_child("EventChoiceButton_leave_empty_event", true, false) as Button
		_check(leave != null and not leave.disabled and leave.is_visible_in_tree(), "Empty content stranded the player")
		_check(leave.find_children("ChoiceDescription_leave_empty_event", "Label", true, false).size() == 1, "Empty-event description was duplicated")
	remove_child(screen)
	screen.queue_free()
	await get_tree().process_frame


func _resources() -> Array:
	return [Game.current_run.gold, Game.current_run.player_hp, Game.current_run.attack, Game.current_run.speed,
		Game.current_run.player_cards.duplicate(), Game.current_run.relics.duplicate()]
