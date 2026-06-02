extends RefCounted
class_name SaveData

var current_run: Dictionary = {}
var meta_progress: Dictionary = {}
var settings: Dictionary = {}


static func from_dict(data: Dictionary) -> SaveData:
	var save_data := SaveData.new()
	save_data.current_run = Dictionary(data.get("current_run", {}))
	save_data.meta_progress = Dictionary(data.get("meta_progress", {}))
	save_data.settings = Dictionary(data.get("settings", {}))
	return save_data


func to_dict() -> Dictionary:
	return {
		"current_run": current_run,
		"meta_progress": meta_progress,
		"settings": settings,
	}
