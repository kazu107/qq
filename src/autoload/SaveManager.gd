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
		if not _owner_allows(profile_meta, active_profile):
			push_warning("A profile from another owner was not loaded")
			current_save = SaveData.new()
		current_save.settings.erase("_cloud_meta")
		for key: String in DEVICE_KEYS:
			if device.has(key): current_save.settings[key] = device[key]
	return current_save


func save_game(scene_hint: String = "hub") -> bool:
	if RankedSession.verifying: return true
	if _profiles_initialized and not _owner_allows(profile_meta, active_profile): return false
	if _save_timer != null:
		_save_timer.stop()
	_pending_scene_hint = ""
	_save_request_scheduled = false
	var save_data := Game.build_save_data(scene_hint)
	var stored: Dictionary = save_data.to_dict().duplicate(true)
	if _profiles_initialized:
		profile_meta["owner_id"] = active_profile
		if active_profile == "guest": _ensure_guest_identity(profile_meta)
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


func is_profile_writable() -> bool:
	return not _profiles_initialized or _owner_allows(profile_meta, active_profile)


func profile_path(profile: String) -> String:
	assert(profile == "guest" or (profile.length() == 36 and profile.replace("-", "").is_valid_hex_number(false)))
	return "user://profiles/%s.json" % profile


func _initialize_profiles() -> void:
	if _profiles_initialized: return
	var record: Dictionary = SafeSaveStore.read_best(DEVICE_PATH)
	device = Dictionary(record.get("data", {}).get("settings", {})).duplicate(true)
	var legacy: Dictionary = Dictionary(SafeSaveStore.read_best(SAVE_PATH).get("data", {}))
	if not bool(device.get("legacy_guest_import_disabled", false)) and not SafeSaveStore.has_any(profile_path("guest")) and not legacy.is_empty():
		SafeSaveStore.write(profile_path("guest"), legacy)
		for key: String in DEVICE_KEYS:
			if legacy.get("settings", {}).has(key) and not device.has(key): device[key] = legacy["settings"][key]
	active_profile = String(device.get("active_profile", "guest"))
	if active_profile != "guest" and (active_profile.length() != 36 or not active_profile.replace("-", "").is_valid_hex_number(false)): active_profile = "guest"
	_profiles_initialized = true
	device["legacy_guest_import_disabled"] = true
	_prepare_guest_file()
	_save_device()


func _save_device() -> bool:
	device["active_profile"] = active_profile
	return SafeSaveStore.write(DEVICE_PATH, {"current_run": {}, "meta_progress": {}, "settings": device})


func read_profile(profile: String) -> Dictionary:
	var data: Dictionary = Dictionary(SafeSaveStore.read_best(profile_path(profile)).get("data", {})).duplicate(true)
	return data if _owner_allows(Dictionary(data.get("settings", {}).get("_cloud_meta", {})), profile) else {}


func activate_profile(profile: String, replacement: Dictionary = {}) -> bool:
	if not replacement.is_empty():
		if not _owner_allows(Dictionary(replacement.get("settings", {}).get("_cloud_meta", {})), profile): return false
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
	_strip_cloud_visuals(result)
	return result


func _strip_cloud_visuals(value: Variant) -> void:
	if value is Dictionary:
		value.erase("visual_replay")
		for child: Variant in value.values():
			if child is Dictionary or child is Array: _strip_cloud_visuals(child)
	elif value is Array:
		for child: Variant in value:
			if child is Dictionary or child is Array: _strip_cloud_visuals(child)


func archive_profile(profile: String, suffix: String = "conflict") -> bool:
	var source: Dictionary = read_profile(profile)
	if source.is_empty(): return true
	var written: bool = SafeSaveStore.write("user://profiles/backups/%s-%s-%d.json" % [profile, suffix, Time.get_unix_time_from_system() * 1000000], source)
	if written:
		var backups: Array[String] = local_backups(profile)
		for index: int in range(10, backups.size()): DirAccess.remove_absolute("user://profiles/backups/" + backups[index])
	return written


func local_backups(profile: String) -> Array[String]:
	var result: Array[String] = []
	var folder: DirAccess = DirAccess.open("user://profiles/backups")
	if folder == null: return result
	for filename: String in folder.get_files():
		if filename.begins_with(profile + "-") and filename.ends_with(".json"): result.append(filename)
	result.sort_custom(func(a: String, b: String) -> bool: return a.get_basename().split("-")[-1].to_int() > b.get_basename().split("-")[-1].to_int())
	return result


func read_local_backup(profile: String, filename: String) -> Dictionary:
	if not local_backups(profile).has(filename): return {}
	var data: Dictionary = Dictionary(SafeSaveStore.read_best("user://profiles/backups/" + filename).get("data", {}))
	return data if _owner_allows(Dictionary(data.get("settings", {}).get("_cloud_meta", {})), profile) else {}


func finish_guest_import(receipt: Dictionary = {}, source: Dictionary = {}) -> bool:
	# Compatibility cleanup for an acknowledged transfer made by QQ-0.47.
	if receipt.is_empty():
		if not bool(profile_meta.get("guest_import_pending", false)): return true
		receipt = {"id": _uuid(), "owner_id": active_profile, "legacy": true}
	var owner: String = String(receipt.get("owner_id", ""))
	if owner.length() != 36 or not owner.replace("-", "").is_valid_hex_number(false): return false
	var receipt_id: String = String(receipt.get("id", ""))
	if receipt_id.length() != 36 or not receipt_id.replace("-", "").is_valid_hex_number(false): return false
	var raw: Dictionary = Dictionary(SafeSaveStore.read_best(profile_path("guest")).get("data", {}))
	var original: Dictionary = source.duplicate(true) if not source.is_empty() else raw.duplicate(true)
	var identity: Dictionary = Dictionary(original.get("settings", {}).get("_cloud_meta", {}).get("guest_identity", {}))
	var origin: String = String(receipt.get("origin_id", identity.get("origin_id", receipt["id"])))
	if source.is_empty() and not bool(receipt.get("legacy", false)) and identity.get("origin_id", "") != origin and original.get("settings", {}).get("_cloud_meta", {}).get("owner_id", "") != owner: original = {}
	var records: Dictionary = Dictionary(device.get("guest_receipts", {}))
	records[origin] = receipt.duplicate(true)
	device["guest_receipts"] = records
	if _meaningful_guest(original):
		var fingerprints: Dictionary = Dictionary(device.get("consumed_guest_fingerprints", {}))
		fingerprints[_guest_fingerprint(original)] = receipt.duplicate(true)
		device["consumed_guest_fingerprints"] = fingerprints
	if not _save_device(): return false
	if not original.is_empty():
		var bound: Dictionary = original.duplicate(true)
		bound.erase(SafeSaveStore.CHECKSUM_KEY)
		bound["settings"] = Dictionary(bound.get("settings", {}))
		bound["settings"]["_cloud_meta"] = {"owner_id": owner, "guest_receipt": receipt.duplicate(true)}
		if not SafeSaveStore.write("user://profiles/backups/%s-guest-%s-%d.json" % [owner, receipt["id"], Time.get_unix_time_from_system() * 1000000], bound): return false
		var owned_backups: Array[String] = local_backups(owner)
		for index: int in range(10, owned_backups.size()): DirAccess.remove_absolute("user://profiles/backups/" + owned_backups[index])
	var current_identity: Dictionary = Dictionary(raw.get("settings", {}).get("_cloud_meta", {}).get("guest_identity", {}))
	var raw_owner: String = String(raw.get("settings", {}).get("_cloud_meta", {}).get("owner_id", ""))
	if bool(receipt.get("legacy", false)) or current_identity.get("origin_id", "") == origin or raw_owner not in ["", "guest"]:
		if not _write_fresh_guest(): return false
	if not _quarantine_legacy_files(): return false
	# Recovery copies with a consumed identity must not turn back into playable guests.
	for filename: String in local_backups("guest"):
		var path: String = "user://profiles/backups/" + filename
		var backup: Dictionary = Dictionary(SafeSaveStore.read_best(path).get("data", {}))
		if backup.is_empty(): continue
		var meta: Dictionary = Dictionary(backup.get("settings", {}).get("_cloud_meta", {}))
		backup["settings"] = Dictionary(backup.get("settings", {}))
		if meta.get("guest_identity", {}).get("origin_id", "") == origin:
			backup["settings"]["_cloud_meta"] = {"owner_id": owner, "guest_receipt": receipt.duplicate(true)}
		else:
			if meta.get("guest_identity", {}).get("origin_id", "") != "" or meta.get("owner_id", "") not in ["", "guest"]: continue
			meta["guest_import_blocked"] = true
			backup["settings"]["_cloud_meta"] = meta
		backup.erase(SafeSaveStore.CHECKSUM_KEY)
		if not SafeSaveStore.write(path, backup): return false
	profile_meta.erase("guest_import_pending")
	profile_meta.erase("guest_cleanup_receipt")
	return true


func guest_identity() -> Dictionary:
	var raw: Dictionary = read_profile("guest")
	return Dictionary(raw.get("settings", {}).get("_cloud_meta", {}).get("guest_identity", {})).duplicate(true)


func consumed_guest_receipt() -> Dictionary:
	var raw: Dictionary = Dictionary(SafeSaveStore.read_best(profile_path("guest")).get("data", {}))
	var meta: Dictionary = Dictionary(raw.get("settings", {}).get("_cloud_meta", {}))
	return Dictionary(device.get("guest_receipts", {})).get(String(meta.get("guest_identity", {}).get("origin_id", "")), {}).duplicate(true)


func store_guest_identity(identity: Dictionary) -> bool:
	var raw: Dictionary = read_profile("guest")
	if raw.is_empty(): return false
	var meta: Dictionary = Dictionary(raw.get("settings", {}).get("_cloud_meta", {}))
	if meta.get("guest_identity", {}).get("origin_id", "") != identity.get("origin_id", ""): return false
	meta["guest_identity"] = identity.duplicate(true)
	raw["settings"]["_cloud_meta"] = meta
	raw.erase(SafeSaveStore.CHECKSUM_KEY)
	if not SafeSaveStore.write(profile_path("guest"), raw): return false
	if active_profile == "guest": profile_meta = meta
	return true


func _ensure_guest_identity(meta: Dictionary) -> void:
	if not meta.has("guest_identity"):
		meta["guest_identity"] = {"origin_id": _uuid(), "secret": Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32)).replace("+", "-").replace("/", "_").trim_suffix("=")}


func _owner_allows(meta: Dictionary, profile: String) -> bool:
	var owner: String = String(meta.get("owner_id", ""))
	var consumed: Dictionary = Dictionary(device.get("guest_receipts", {})).get(String(meta.get("guest_identity", {}).get("origin_id", "")), {})
	if not consumed.is_empty() and consumed.get("owner_id", "") != profile: return false
	if bool(meta.get("guest_import_blocked", false)) and owner != profile: return false
	if profile == "guest":
		return owner in ["", "guest"] and not bool(meta.get("guest_import_blocked", false)) and not Dictionary(device.get("guest_receipts", {})).has(String(meta.get("guest_identity", {}).get("origin_id", "")))
	return owner in ["", "guest", profile]


func _prepare_guest_file() -> void:
	var raw: Dictionary = Dictionary(SafeSaveStore.read_best(profile_path("guest")).get("data", {}))
	var meta: Dictionary = Dictionary(raw.get("settings", {}).get("_cloud_meta", {}))
	var consumed: Dictionary = Dictionary(device.get("guest_receipts", {})).get(String(meta.get("guest_identity", {}).get("origin_id", "")), {})
	if consumed.is_empty() and meta.get("guest_receipt") is Dictionary: consumed = Dictionary(meta["guest_receipt"]).duplicate(true)
	if consumed.is_empty() and not meta.has("guest_identity") and _meaningful_guest(raw):
		consumed = Dictionary(device.get("consumed_guest_fingerprints", {})).get(_guest_fingerprint(raw), {}).duplicate(true)
		if not consumed.is_empty(): consumed["legacy"] = true
	if not consumed.is_empty():
		finish_guest_import(consumed, raw)
		return
	if not _owner_allows(meta, "guest"):
		# Keep unassignable old recovery data for manual recovery, not as an importable guest.
		if not raw.is_empty() and not SafeSaveStore.write("user://profiles/quarantine/guest-%d.json" % (Time.get_unix_time_from_system() * 1000000), raw): return
		_write_fresh_guest()
		return
	if raw.is_empty(): raw = SaveData.new().to_dict()
	raw["settings"] = Dictionary(raw.get("settings", {}))
	meta["owner_id"] = "guest"
	_ensure_guest_identity(meta)
	raw["settings"]["_cloud_meta"] = meta
	raw.erase(SafeSaveStore.CHECKSUM_KEY)
	SafeSaveStore.write(profile_path("guest"), raw)


func _write_fresh_guest() -> bool:
	var fresh: Dictionary = SaveData.new().to_dict()
	var meta: Dictionary = {"owner_id": "guest"}
	_ensure_guest_identity(meta)
	fresh["settings"]["_cloud_meta"] = meta
	if not SafeSaveStore.write(profile_path("guest"), fresh): return false
	for suffix: String in [".tmp", ".previous", ".bak1", ".bak2", ".bak3"]:
		var path: String = profile_path("guest") + suffix
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK: return false
	return true


func _quarantine_legacy_files() -> bool:
	device["legacy_guest_import_disabled"] = true
	if not _save_device(): return false
	for suffix: String in ["", ".tmp", ".previous", ".bak1", ".bak2", ".bak3"]:
		var path: String = SAVE_PATH + suffix
		if not FileAccess.file_exists(path): continue
		var data: Dictionary = Dictionary(SafeSaveStore.read_best(path).get("data", {}))
		if not data.is_empty():
			data.erase(SafeSaveStore.CHECKSUM_KEY)
			data["settings"] = Dictionary(data.get("settings", {}))
			var meta: Dictionary = Dictionary(data.get("settings", {}).get("_cloud_meta", {}))
			meta["guest_import_blocked"] = true
			data["settings"]["_cloud_meta"] = meta
			if not SafeSaveStore.write("user://profiles/quarantine/legacy%s-%d.json" % [suffix.replace(".", "-"), Time.get_unix_time_from_system() * 1000000], data): return false
		if DirAccess.remove_absolute(path) != OK: return false
	return true


func _guest_fingerprint(data: Dictionary) -> String:
	return JSON.stringify(cloud_payload(SaveData.from_dict(data))).sha256_text()


func _meaningful_guest(data: Dictionary) -> bool:
	if not Dictionary(data.get("current_run", {})).is_empty() or not Dictionary(data.get("suspended_runs", {})).is_empty(): return true
	var meta: Dictionary = Dictionary(data.get("meta_progress", {}))
	var defaults: Dictionary = Database.meta_progress_template.duplicate(true)
	MetaProgressService.new().ensure_defaults(defaults)
	return not meta.is_empty() and meta != defaults


func _uuid() -> String:
	var hex: String = Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


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
