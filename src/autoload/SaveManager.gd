extends Node

const SAVE_PATH := "user://save.json"
const REPLAY_DIR := "user://replays"
const REQUEST_SAVE_DELAY_SECONDS := 0.12

var current_save := SaveData.new()
var _pending_scene_hint: String = ""
var _save_request_scheduled: bool = false
var _save_timer: Timer


func _ready() -> void:
	_ensure_save_timer()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_save() -> SaveData:
	if not has_save():
		current_save = SaveData.new()
		return current_save

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open save file")
		current_save = SaveData.new()
		return current_save

	var json_text := file.get_as_text()
	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("Save parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		current_save = SaveData.new()
		return current_save

	current_save = SaveData.from_dict(Dictionary(json.data))
	return current_save


func save_game(scene_hint: String = "title") -> bool:
	if _save_timer != null:
		_save_timer.stop()
	_pending_scene_hint = ""
	_save_request_scheduled = false
	var save_data := Game.build_save_data(scene_hint)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write save file")
		return false

	file.store_string(JSON.stringify(save_data.to_dict(), "\t"))
	current_save = save_data
	return true


func request_save(scene_hint: String = "title") -> void:
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
