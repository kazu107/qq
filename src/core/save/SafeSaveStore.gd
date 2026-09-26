extends RefCounted
class_name SafeSaveStore

const BACKUP_COUNT: int = 3
const CHECKSUM_KEY := "_save_sha256"


static func has_any(path: String) -> bool:
	for candidate: String in _recovery_paths(path):
		if FileAccess.file_exists(candidate):
			return true
	return false


static func read_best(path: String) -> Dictionary:
	for candidate: String in _recovery_paths(path):
		var data: Dictionary = _read_valid(candidate)
		if not data.is_empty():
			return {"found": true, "source": candidate, "data": data}
	return {"found": false, "source": "", "data": {}}


static func write(path: String, data: Dictionary) -> bool:
	if not _is_valid_save(data):
		return false
	var stored_data: Dictionary = JSON.parse_string(JSON.stringify(data))
	stored_data.erase(CHECKSUM_KEY)
	stored_data[CHECKSUM_KEY] = JSON.stringify(stored_data).sha256_text()
	var directory: String = path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK and not DirAccess.dir_exists_absolute(directory):
		return false
	var staged: String = path + ".tmp"
	if not _write_text(staged, JSON.stringify(stored_data, "\t")) or _read_valid(staged).is_empty():
		return false

	var primary_valid: bool = not _read_valid(path).is_empty()
	if primary_valid:
		for backup_index: int in range(BACKUP_COUNT, 1, -1):
			var previous: String = _backup_path(path, backup_index - 1)
			if not _read_valid(previous).is_empty() and not _copy_verified(previous, _backup_path(path, backup_index)):
				return false
		if not _copy_verified(path, _backup_path(path, 1)):
			return false

	var previous_primary: String = path + ".previous"
	if FileAccess.file_exists(previous_primary) and DirAccess.remove_absolute(previous_primary) != OK:
		return false
	var moved_primary: bool = FileAccess.file_exists(path)
	if moved_primary and DirAccess.rename_absolute(path, previous_primary) != OK:
		return false
	if DirAccess.rename_absolute(staged, path) != OK:
		if moved_primary:
			DirAccess.rename_absolute(previous_primary, path)
		return false
	if moved_primary:
		DirAccess.remove_absolute(previous_primary)
	return true


static func _copy_verified(source: String, destination: String) -> bool:
	var staged: String = destination + ".tmp"
	var source_file: FileAccess = FileAccess.open(source, FileAccess.READ)
	if source_file == null:
		return false
	var contents: PackedByteArray = source_file.get_buffer(source_file.get_length())
	source_file = null
	var staged_file: FileAccess = FileAccess.open(staged, FileAccess.WRITE)
	if staged_file == null:
		return false
	staged_file.store_buffer(contents)
	staged_file.flush()
	staged_file = null
	if _read_valid(staged).is_empty():
		return false
	if FileAccess.file_exists(destination) and DirAccess.remove_absolute(destination) != OK:
		return false
	return DirAccess.rename_absolute(staged, destination) == OK


static func _write_text(path: String, contents: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	file.flush()
	var error: Error = file.get_error()
	file = null
	return error == OK


static func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var parsed: Variant = json.data
	if parsed is Dictionary and _is_valid_save(parsed):
		return parsed
	return {}


static func _is_valid_save(data: Dictionary) -> bool:
	if not data.has("current_run") or not data.has("meta_progress"):
		return false
	for key: String in ["current_run", "suspended_runs", "meta_progress", "settings"]:
		if data.has(key) and not data[key] is Dictionary:
			return false
	if data.has(CHECKSUM_KEY):
		var checksum: String = String(data[CHECKSUM_KEY])
		if checksum.length() != 64:
			return false
		var payload: Dictionary = data.duplicate(true)
		payload.erase(CHECKSUM_KEY)
		if JSON.stringify(payload).sha256_text() != checksum:
			return false
	return true


static func _backup_path(path: String, index: int) -> String:
	return "%s.bak%d" % [path, index]


static func _recovery_paths(path: String) -> Array[String]:
	var paths: Array[String] = [path, path + ".tmp", path + ".previous"]
	for backup_index: int in range(1, BACKUP_COUNT + 1):
		paths.append(_backup_path(path, backup_index))
	return paths
