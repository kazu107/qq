extends Node

const SAVE_PATH := "user://save.json"
const REPLAY_DIR := "user://replays"
const REQUEST_SAVE_DELAY_SECONDS := 0.12

var current_save := SaveData.new()
var last_recovery_source: String = ""
var _pending_scene_hint: String = ""
var _save_request_scheduled: bool = false
var _save_timer: Timer


func _ready() -> void:
	_ensure_save_timer()


func has_save() -> bool:
	return SafeSaveStore.has_any(SAVE_PATH)


func load_save() -> SaveData:
	last_recovery_source = ""
	if not has_save():
		current_save = SaveData.new()
		return current_save

	var recovered: Dictionary = SafeSaveStore.read_best(SAVE_PATH)
	if not bool(recovered.get("found", false)):
		push_error("No valid save file or backup could be read")
		current_save = SaveData.new()
		return current_save
	var source: String = String(recovered.get("source", ""))
	if source != SAVE_PATH:
		last_recovery_source = source
		push_warning("Recovered save data from %s" % source)
	current_save = SaveData.from_dict(Dictionary(recovered.get("data", {})))
	return current_save


func save_game(scene_hint: String = "hub") -> bool:
	if _save_timer != null:
		_save_timer.stop()
	_pending_scene_hint = ""
	_save_request_scheduled = false
	var save_data := Game.build_save_data(scene_hint)
	if not SafeSaveStore.write(SAVE_PATH, save_data.to_dict()):
		push_error("Failed to safely write save file")
		return false
	current_save = save_data
	return true


func request_save(scene_hint: String = "hub") -> void:
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
