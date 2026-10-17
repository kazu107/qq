extends Node

signal profile_saved(profile: String)

const SAVE_PATH := "user://save.json"
const REPLAY_DIR := "user://replays"
const REQUEST_SAVE_DELAY_SECONDS := 0.12

var current_save := SaveData.new()
var last_recovery_source: String = ""
var _pending_scene_hint: String = ""
var _save_request_scheduled: bool = false
var _save_timer: Timer
var profiles_enabled: bool = false
var active_profile: String = "guest"
var profile_meta: Dictionary = {}
var device: Dictionary = {}
var _profiles_initialized: bool = false
const DEVICE_PATH := "user://profiles/device.json"
const DEVICE_KEYS := ["master_volume", "sfx_volume", "language", "resolution", "developer_mode", "developer_panel_collapsed", "replay_auto_export", "last_replay_export_path", "replay_view_path", "replay_view_return_hint", "lan_player_name", "lan_last_address", "lan_port", "online_player_name", "online_last_address", "online_room_code", "online_port", "online_automatic_upnp", "ranked_outbox"]
const RESUME_KEYS := ["screen_hint", "pending_enemy_id", "reward_options", "last_battle_summary", "last_reward_bundle", "last_run_starter_id", "last_run_seed", "last_run_infinite", "settings_return_hint"]


func _ready() -> void:
	_ensure_save_timer()


func has_save() -> bool:
	return SafeSaveStore.has_any(active_path())


func load_save() -> SaveData:
	if OS.has_feature("web") or profiles_enabled:
		_initialize_profiles()
	last_recovery_source = ""
	if not has_save():
		current_save = SaveData.new()
		return current_save

	var recovered: Dictionary = SafeSaveStore.read_best(active_path())
	if not bool(recovered.get("found", false)):
		push_error("No valid save file or backup could be read")
		current_save = SaveData.new()
		return current_save
	var source: String = String(recovered.get("source", ""))
	if source != active_path():
		last_recovery_source = source
		push_warning("Recovered save data from %s" % source)
	current_save = SaveData.from_dict(Dictionary(recovered.get("data", {})))
	if _profiles_initialized:
		profile_meta = Dictionary(current_save.settings.get("_cloud_meta", {})).duplicate(true)
		current_save.settings.erase("_cloud_meta")
		for key: String in DEVICE_KEYS:
			if device.has(key): current_save.settings[key] = device[key]
	return current_save


func save_game(scene_hint: String = "hub") -> bool:
	if RankedSession.verifying: return true
	if _save_timer != null:
		_save_timer.stop()
	_pending_scene_hint = ""
	_save_request_scheduled = false
	var save_data := Game.build_save_data(scene_hint)
	var stored: Dictionary = save_data.to_dict().duplicate(true)
	if _profiles_initialized:
		profile_meta["dirty"] = JSON.stringify(cloud_payload(save_data)).sha256_text() != String(profile_meta.get("synced_hash", ""))
		for key: String in DEVICE_KEYS:
			if Game.settings.has(key): device[key] = Game.settings[key]
			stored["settings"].erase(key)
		stored["settings"]["_cloud_meta"] = profile_meta.duplicate(true)
		_save_device()
	if not SafeSaveStore.write(active_path(), stored):
		push_error("Failed to safely write save file")
		return false
	current_save = save_data
	profile_saved.emit(active_profile)
	return true


func active_path() -> String:
	return profile_path(active_profile) if _profiles_initialized else SAVE_PATH


func profile_path(profile: String) -> String:
	assert(profile == "guest" or (profile.length() == 36 and profile.replace("-", "").is_valid_hex_number(false)))
	return "user://profiles/%s.json" % profile


func _initialize_profiles() -> void:
	if _profiles_initialized: return
	var record: Dictionary = SafeSaveStore.read_best(DEVICE_PATH)
	device = Dictionary(record.get("data", {}).get("settings", {})).duplicate(true)
	var legacy: Dictionary = Dictionary(SafeSaveStore.read_best(SAVE_PATH).get("data", {}))
	if not SafeSaveStore.has_any(profile_path("guest")) and not legacy.is_empty():
		SafeSaveStore.write(profile_path("guest"), legacy)
		for key: String in DEVICE_KEYS:
			if legacy.get("settings", {}).has(key) and not device.has(key): device[key] = legacy["settings"][key]
	active_profile = String(device.get("active_profile", "guest"))
	if active_profile != "guest" and (active_profile.length() != 36 or not active_profile.replace("-", "").is_valid_hex_number(false)): active_profile = "guest"
	_profiles_initialized = true
	_save_device()


func _save_device() -> void:
	device["active_profile"] = active_profile
	SafeSaveStore.write(DEVICE_PATH, {"current_run": {}, "meta_progress": {}, "settings": device})


func read_profile(profile: String) -> Dictionary:
	return Dictionary(SafeSaveStore.read_best(profile_path(profile)).get("data", {})).duplicate(true)


func activate_profile(profile: String, replacement: Dictionary = {}) -> bool:
	if not replacement.is_empty():
		var clean: Dictionary = replacement.duplicate(true)
		clean.erase(SafeSaveStore.CHECKSUM_KEY)
		if not SafeSaveStore.write(profile_path(profile), clean): return false
	active_profile = profile
	profile_meta = {}
	_save_device()
	var data: SaveData = load_save()
	# A fresh profile must inherit device preferences too.
	for key: String in DEVICE_KEYS:
		if device.has(key): data.settings[key] = device[key]
	Game.apply_loaded_save(data)
	Game.active_battle_tutorial_id = ""
	Game.stash_active_run_for_hub()
	return true


func cloud_payload(data: SaveData = null) -> Dictionary:
	var save: SaveData = current_save if data == null else data
	var result: Dictionary = save.to_dict().duplicate(true)
	result["schema_version"] = 1
	var resume: Dictionary = {}
	for key: String in RESUME_KEYS:
		if save.settings.has(key): resume[key] = save.settings[key]
	result["settings"] = resume
	return result


func archive_profile(profile: String, suffix: String = "conflict") -> bool:
	var source: Dictionary = read_profile(profile)
	if source.is_empty(): return true
	return SafeSaveStore.write("user://profiles/backups/%s-%s-%d.json" % [profile, suffix, Time.get_unix_time_from_system() * 1000000], source)


func finish_guest_import() -> void:
	if not bool(profile_meta.get("guest_import_pending", false)): return
	if not archive_profile("guest", "imported"): return
	if SafeSaveStore.write(profile_path("guest"), SaveData.new().to_dict()):
		profile_meta.erase("guest_import_pending")


func forget_cached_profile(profile: String) -> void:
	if profile == "guest" or profile == active_profile: return
	# Only exact, validated profile paths and their known recovery files are removed.
	for suffix: String in ["", ".tmp", ".previous", ".bak1", ".bak2", ".bak3"]:
		var path: String = profile_path(profile) + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)


func request_save(scene_hint: String = "hub") -> void:
	if RankedSession.verifying: return
	_pending_scene_hint = scene_hint
	_ensure_save_timer()
	_save_request_scheduled = true
	_save_timer.start()


func has_pending_save() -> bool:
	return _save_request_scheduled or _pending_scene_hint != ""


func flush_requested_save() -> bool:
	if _save_timer != null:
		_save_timer.stop()
	if _pending_scene_hint == "":
		_save_request_scheduled = false
		return true
	var scene_hint: String = _pending_scene_hint
	_pending_scene_hint = ""
	_save_request_scheduled = false
	return save_game(scene_hint)


func _ensure_save_timer() -> void:
	if _save_timer != null:
		return
	_save_timer = Timer.new()
	_save_timer.name = "DeferredSaveTimer"
	_save_timer.one_shot = true
	_save_timer.wait_time = REQUEST_SAVE_DELAY_SECONDS
	_save_timer.timeout.connect(flush_requested_save)
	add_child(_save_timer)


func export_replay(replay_data: ReplayData, battle_id: String = "") -> String:
	if replay_data == null:
		return ""

	var replay_dir: String = ProjectSettings.globalize_path(REPLAY_DIR)
	if DirAccess.make_dir_recursive_absolute(replay_dir) != OK and not DirAccess.dir_exists_absolute(replay_dir):
		push_error("Failed to create replay directory: %s" % replay_dir)
		return ""

	var safe_id: String = battle_id.strip_edges().replace(" ", "_")
	if safe_id == "":
		safe_id = "battle"
	var timestamp: String = Time.get_datetime_string_from_system(false).replace(":", "-")
	var file_name: String = "%s_%s.json" % [timestamp, safe_id]
	var file_path: String = "%s/%s" % [replay_dir, file_name]
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write replay file: %s" % file_path)
		return ""

	file.store_string(JSON.stringify(replay_data.to_dict(), "\t"))
	return file_path
