extends Node

const SAVE_PATH := "user://save.json"
const REPLAY_DIR := "user://replays"

var current_save := SaveData.new()


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
	var save_data := Game.build_save_data(scene_hint)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write save file")
		return false

	file.store_string(JSON.stringify(save_data.to_dict(), "\t"))
	current_save = save_data
	return true


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
