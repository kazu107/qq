extends RefCounted
class_name ReplayData

const FORMAT_VERSION := 1

var format_version: int = FORMAT_VERSION
var exported_at: String = ""
var battle_id: String = ""
var summary: Dictionary = {}
var battle_events: Array[Dictionary] = []


static func from_summary(summary_data: Dictionary) -> ReplayData:
	var replay_data: ReplayData = ReplayData.new()
	replay_data.exported_at = Time.get_datetime_string_from_system(true)
	replay_data.battle_id = String(summary_data.get("battle_id", ""))
	replay_data.summary = Dictionary(summary_data.duplicate(true))
	replay_data.battle_events = _to_dictionary_array(summary_data.get("battle_events", []))
	return replay_data


func to_dict() -> Dictionary:
	return {
		"format_version": format_version,
		"exported_at": exported_at,
		"battle_id": battle_id,
		"summary": summary,
		"battle_events": battle_events,
	}


static func _to_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in value:
		result.append(Dictionary(item))
	return result
