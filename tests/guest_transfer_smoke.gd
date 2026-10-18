extends Node

const OWNER := "11111111-1111-4111-8111-111111111111"
const OTHER := "22222222-2222-4222-8222-222222222222"


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.meta_progress["points"] = 123
	Game.start_new_run("balanced", 426)
	SaveManager.save_game("map")
	SaveManager.profiles_enabled = true
	Game.apply_loaded_save(SaveManager.load_save())
	SaveManager.save_game("map")
	var original: Dictionary = SaveManager.read_profile("guest")
	var identity: Dictionary = SaveManager.guest_identity()
	assert(String(identity["secret"]).length() == 43)
	assert(String(identity["origin_id"]).length() == 36)
	var restored_copy: Dictionary = original.duplicate(true)
	var receipt: Dictionary = {"id": "33333333-3333-4333-8333-333333333333", "origin_id": identity["origin_id"], "owner_id": OWNER, "revision": 1}
	var activated: bool = SaveManager.activate_profile(OWNER, SaveManager.cloud_payload(SaveData.from_dict(original)))
	assert(activated)
	var complete: bool = SaveManager.finish_guest_import(receipt, original)
	assert(complete)
	assert(not SafeSaveStore.has_any(SaveManager.SAVE_PATH), "Legacy recovery files must not be an alternate import source")
	var fresh: Dictionary = SaveManager.read_profile("guest")
	assert(fresh.get("meta_progress", {}).get("points", 0) == 0)
	assert(fresh["settings"]["_cloud_meta"]["guest_identity"]["origin_id"] != identity["origin_id"])
	assert(not FileAccess.file_exists(SaveManager.profile_path("guest") + ".bak1"))
	var backups: Array[String] = SaveManager.local_backups(OWNER)
	assert(not backups.is_empty())
	var bound: Dictionary = SaveManager.read_local_backup(OWNER, backups[0])
	assert(bound["settings"]["_cloud_meta"]["owner_id"] == OWNER)
	assert(not bound["settings"]["_cloud_meta"].has("guest_identity"), "Consumed guest credentials must not be reusable from an account backup")
	var foreign: bool = SaveManager.activate_profile(OTHER, bound)
	assert(not foreign and SaveManager.active_profile == OWNER)
	var as_guest: bool = SaveManager.activate_profile("guest", bound)
	assert(not as_guest)
	var own: bool = SaveManager.activate_profile(OWNER, bound)
	assert(own and Game.get_meta_points() == 123)
	var independent: Dictionary = original.duplicate(true)
	independent["settings"]["_cloud_meta"] = fresh["settings"]["_cloud_meta"].duplicate(true)
	independent.erase(SafeSaveStore.CHECKSUM_KEY)
	var independent_written: bool = SafeSaveStore.write(SaveManager.profile_path("guest"), independent)
	assert(independent_written)
	SaveManager._prepare_guest_file()
	assert(SaveManager.read_profile("guest").get("meta_progress", {}).get("points", 0) == 123, "Independent guest identities must not be rejected merely for equal progress values")
	# Restore a pre-issuance source; the durable origin tombstone must still retire it.
	var restored: bool = SafeSaveStore.write(SaveManager.profile_path("guest"), restored_copy)
	assert(restored)
	SaveManager._prepare_guest_file()
	assert(SaveManager.read_profile("guest").get("meta_progress", {}).get("points", 0) == 0)
	var staged: bool = SafeSaveStore.write(SaveManager.SAVE_PATH, original)
	assert(staged)
	DirAccess.remove_absolute(SaveManager.profile_path("guest"))
	SaveManager._profiles_initialized = false
	SaveManager.load_save()
	assert(SaveManager.read_profile("guest").get("meta_progress", {}).get("points", 0) == 0, "A deleted guest file must not reimport the old single-file save")
	print("GUEST_TRANSFER_SMOKE_OK owner-bound recovery, durable consumption, legacy quarantine and fresh guest identity")
	get_tree().quit()
