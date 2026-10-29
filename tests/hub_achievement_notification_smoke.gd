extends Node

var _checks: int = 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		push_error(message)
		get_tree().quit(1)
		assert(condition, message)


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _settle() -> void:
	for frame: int in 4: await get_tree().process_frame


func _compare_counter() -> void:
	var expected: int = 0
	for entry: Dictionary in Game.get_meta_achievement_entries():
		if entry["claimable"]: expected += 1
	_check(Game.get_claimable_achievement_count() == expected, "Lightweight count diverged from the real claim buttons")


func _clean_fixture() -> void:
	Game.meta_progress = Database.meta_progress_template.duplicate(true)
	Game.ensure_meta_initialized()
	# Initial content unlocks can already satisfy collection achievements.
	# Mark those rows complete only in this isolated test fixture.
	for entry: Dictionary in Game.get_meta_achievement_entries():
		if entry["claimable"]:
			Game.meta_progress["achievement_claim_counts"][entry["id"]] = entry["tier_count"]


func _run() -> void:
	Game.set_language("ja")
	Game.settings["developer_mode"] = false
	_clean_fixture()
	_compare_counter()
	var hub: Control = load("res://scenes/hub/Hub.tscn").instantiate() as Control
	add_child(hub)
	await _settle()
	var button: Button = hub.find_child("HubMetaProgressButton", true, false) as Button
	var badge: Control = button.get_node("HubAchievementNotification") as Control
	_check(not badge.visible, "A profile without pending rewards should not show a notification")
	_check(not hub.is_processing(), "Notification must not poll every frame")
	var button_size: Vector2 = button.size
	var meta: String = JSON.stringify(Game.meta_progress)
	hub.call("_refresh_achievement_notification")
	_check(JSON.stringify(Game.meta_progress) == meta, "Notification changed existing progress")
	Game.developer_add_achievement_stat("gold_spent", 25)
	SaveManager.flush_requested_save()
	await _settle()
	_check(badge.visible and badge.get_meta("claimable_count") == 1, "Achievement unlock did not show the badge after saving")
	_check(badge.size == Vector2(22,22) and badge.get_rect().end.x <= button.size.x and badge.position.x > button.size.x*.8 and badge.position.y < 0, "Badge is not a compact square at the top-right")
	_check(badge.mouse_filter == Control.MOUSE_FILTER_IGNORE and button.size == button_size, "Badge changed input/layout")
	_check(button.tooltip_text.contains("1"), "Claimable count is missing from the hint")
	button.pressed.emit()
	await _settle()
	var dialog: MetaProgressDialog = SceneRouter.get_meta_progress_dialog()
	_check(dialog.visible and badge.visible, "Opening the list should not dismiss unclaimed rewards")
	dialog.close()
	await _settle()
	_check(badge.visible, "Closing without claiming incorrectly cleared the notification")
	_check(Game.claim_meta_achievement("big_spender"), "Fixture achievement could not be claimed")
	_check(not badge.visible, "The last claim did not immediately clear the badge")
	Game.developer_add_achievement_stat("victories", 3)
	SaveManager.flush_requested_save()
	_check(badge.visible, "Tiered achievement was not detected")
	_check(Game.claim_meta_achievement("victory_milestones"), "First tier claim failed")
	_check(badge.visible, "The next already-achieved tier should keep the badge visible")
	_check(Game.claim_meta_achievement("victory_milestones"), "Second tier claim failed")
	_compare_counter()
	# Query all conditions and legacy/completed tier representations without granting rewards.
	for id: String in Database.get_all_achievement_ids():
		var definition: Dictionary = Database.get_achievement(id)
		var tiers: Array = definition.get("tiers", [])
		if not tiers.is_empty():
			for tier: Dictionary in tiers:
				var condition: Dictionary = tier.get("condition", definition.get("condition", {}))
				Game.meta_progress["achievement_stats"][condition.get("stat", "")] = 999999999
		Game.meta_progress["achievement_claim_counts"][id] = 0
		_compare_counter()
		Game.meta_progress["achievement_claim_counts"][id] = tiers.size()
		_compare_counter()
	_clean_fixture()
	CloudSession.changed.emit()
	_check(not badge.visible, "Cloud/profile replacement retained another profile's badge")
	Game.meta_progress["achievement_stats"]["gold_spent"] = 25
	CloudSession.changed.emit()
	_check(badge.visible, "Cloud/profile replacement did not show claimable rewards")
	hub.call("_rebuild_menu", "HubMetaProgressButton")
	await _settle()
	badge = hub.find_child("HubAchievementNotification", true, false) as Control
	_check(badge.visible, "Menu rebuild lost the notification")
	Game.developer_reset_meta_progress()
	SaveManager.flush_requested_save()
	_check(badge.visible == (Game.get_claimable_achievement_count() > 0), "Developer reset retained an old badge instead of recalculating defaults")
	hub.queue_free()
	print("HUB_ACHIEVEMENT_NOTIFICATION_SMOKE_OK checks=%d claimability/tiers/reset/cloud/layout/no-polling" % _checks)
	get_tree().quit()
