extends RefCounted
class_name GameVersion

const DATA_PATH := "res://data/version_history.json"
const FALLBACK_VERSION := "QQ-0.0.0"
const FALLBACK_SCHEME := "QQ-MAJOR.MINOR.PATCH"

static var _cached_data: Dictionary = {}


static func get_current_version() -> String:
	_ensure_loaded()
	return String(_cached_data.get("current_version", FALLBACK_VERSION))


static func get_scheme() -> String:
	_ensure_loaded()
	return String(_cached_data.get("scheme", FALLBACK_SCHEME))


static func get_releases() -> Array[Dictionary]:
	_ensure_loaded()
	var releases: Array[Dictionary] = []
	var raw_releases: Variant = _cached_data.get("releases", [])
	if raw_releases is not Array:
		return releases
	for raw_release: Variant in raw_releases:
		if raw_release is Dictionary:
			releases.append(Dictionary(raw_release).duplicate(true))
	return releases


static func _ensure_loaded() -> void:
	if not _cached_data.is_empty():
		return
	_cached_data = {
		"scheme": FALLBACK_SCHEME,
		"current_version": FALLBACK_VERSION,
		"releases": [],
	}
	if not FileAccess.file_exists(DATA_PATH):
		push_error("Version history file was not found: %s" % DATA_PATH)
		return

	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Version history file could not be opened: %s" % DATA_PATH)
		return
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	if parse_error != OK:
		push_error("Version history parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return
	var parsed_data: Variant = json.data
	if parsed_data is not Dictionary:
		push_error("Version history root must be a JSON object")
		return
	_cached_data = Dictionary(parsed_data).duplicate(true)
