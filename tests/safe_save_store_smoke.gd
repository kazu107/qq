extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var path: String = "user://safe-save-smoke/%d/save.json" % Time.get_ticks_usec()
	for points: int in range(1, 6):
		if not _check(SafeSaveStore.write(path, _save_with_points(points)), "write failed at generation %d" % points):
			return
	if not _check(_points(SafeSaveStore.read_best(path)) == 5, "latest save was not loaded"):
		return
	for index: int in range(1, 4):
		if not _check(_points(SafeSaveStore.read_best("%s.bak%d" % [path, index])) == 5 - index, "backup generation %d is wrong" % index):
			return
	var tampered: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	tampered["meta_progress"]["points"] = 999
	_write_raw(path, JSON.stringify(tampered))
	if not _check(_points(SafeSaveStore.read_best(path)) == 4, "checksum mismatch did not recover the backup"):
		return

	_write_raw(path, "{broken")
	if not _check(_points(SafeSaveStore.read_best(path)) == 4, "corrupt primary did not recover from backup"):
		return
	_write_raw(path + ".tmp", JSON.stringify(_save_with_points(6)))
	if not _check(_points(SafeSaveStore.read_best(path)) == 6, "valid staged save was not recovered"):
		return
	_write_raw(path + ".tmp", "{truncated")
	if not _check(_points(SafeSaveStore.read_best(path)) == 4, "truncated staged save blocked backup recovery"):
		return
	if not _check(SafeSaveStore.write(path, _save_with_points(7)), "could not replace corrupt primary"):
		return
	if not _check(_points(SafeSaveStore.read_best(path)) == 7, "repaired primary was not loaded"):
		return
	if not _check(_points(SafeSaveStore.read_best(path + ".bak1")) == 4, "repair destroyed the valid backup"):
		return
	if not _check(SafeSaveStore.write(path, Dictionary(SafeSaveStore.read_best(path).get("data", {}))), "rewriting a checksummed save failed"):
		return
	if not _check(not SafeSaveStore.write(path, {"current_run": 1, "meta_progress": {}}), "invalid save shape was accepted"):
		return
	if not _check(_points(SafeSaveStore.read_best(path)) == 7, "invalid write changed the primary"):
		return
	if not _check(DirAccess.rename_absolute(path, path + ".previous") == OK, "could not simulate interrupted replacement"):
		return
	if not _check(_points(SafeSaveStore.read_best(path)) == 7, "interrupted replacement did not recover previous primary"):
		return
	_write_raw(path, JSON.stringify(_save_with_points(8)))
	if not _check(_points(SafeSaveStore.read_best(path)) == 8, "legacy save without checksum was rejected"):
		return
	print("SAFE_SAVE_STORE_SMOKE_OK rotation, corruption, staging and interruption")
	get_tree().quit(0)


func _save_with_points(points: int) -> Dictionary:
	var save: Dictionary = SaveData.new().to_dict()
	save["meta_progress"] = {"points": points}
	return save


func _points(result: Dictionary) -> int:
	if not bool(result.get("found", false)):
		return -1
	return int(Dictionary(result.get("data", {})).get("meta_progress", {}).get("points", -1))


func _write_raw(path: String, contents: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file = null


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("Safe save store smoke failed: %s" % message)
	get_tree().quit(1)
	return false
