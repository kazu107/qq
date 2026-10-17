extends Node


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.meta_progress["points"] = 123
	Game.set_master_volume(0.37)
	Game.start_new_run("balanced", 426)
	Game.current_screen_hint = "battle"
	Game.pending_enemy_id = "scout"
	SaveManager.save_game("battle")
	SaveManager.profiles_enabled = true
	var legacy: SaveData = SaveManager.load_save()
	assert(legacy.meta_progress["points"] == 123)
	assert(SafeSaveStore.has_any(SaveManager.SAVE_PATH), "The original single-file save must be retained")
	Game.apply_loaded_save(legacy)
	SaveManager.activate_profile("11111111-1111-4111-8111-111111111111", SaveData.new().to_dict())
	assert(Game.get_meta_points() == 0)
	assert(is_equal_approx(Game.get_master_volume(), 0.37))
	Game.meta_progress["points"] = 77
	Game.settings["developer_mode"] = true
	Game.settings["ranked_outbox"] = {"test": {"owner": "first"}}
	SaveManager.save_game("hub")
	var payload: Dictionary = SaveManager.cloud_payload()
	assert(payload["meta_progress"]["points"] == 77)
	assert(not payload["settings"].has("developer_mode") and not payload["settings"].has("master_volume") and not payload["settings"].has("ranked_outbox"))
	SaveManager.activate_profile("22222222-2222-4222-8222-222222222222", SaveData.new().to_dict())
	assert(Game.get_meta_points() == 0)
	Game.meta_progress["points"] = 99
	SaveManager.save_game("hub")
	SaveManager.activate_profile("11111111-1111-4111-8111-111111111111")
	assert(Game.get_meta_points() == 77)
	assert(Game.settings["ranked_outbox"].has("test"))
	SaveManager.activate_profile("guest")
	assert(Game.get_meta_points() == 123)
	assert(Game.has_suspended_run("normal"))
	assert(Game.suspended_runs["normal"]["screen_hint"] == "battle", "Keep the original checkpoint phase when changing profiles")
	assert(SaveManager.archive_profile("guest", "test"))
	var raw: Dictionary = SaveManager.read_profile("guest")
	raw["settings"].erase("_cloud_meta")
	SaveManager.activate_profile("33333333-3333-4333-8333-333333333333", raw)
	assert(Game.get_meta_points() == 123, "A modified legacy payload must get a new checksum, not silently become a fresh save")
	var ranking_sample: Dictionary = {"current_run": {"ranking": {"ticket": {"user_id": "owner"}}}, "suspended_runs": {"ranked": {"run": {"ranking": {"ticket": {"user_id": "foreign"}}}}}}
	CloudSession._prepare_guest_rankings(ranking_sample, "owner")
	assert(not ranking_sample["current_run"].is_empty() and ranking_sample["suspended_runs"].is_empty())
	SaveManager.profile_meta["guest_import_pending"] = true
	SaveManager.finish_guest_import()
	SaveManager.activate_profile("guest")
	assert(Game.get_meta_points() == 0 and Game.suspended_runs.is_empty())
	print("CLOUD_PROFILE_SMOKE_OK legacy migration, owner isolation, guest transfer, device preferences and battle checkpoints")
	get_tree().quit()
