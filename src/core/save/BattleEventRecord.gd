extends RefCounted
class_name BattleEventRecord

var time: float = 0.0
var event_type: String = ""
var actor_id: String = ""
var card_id: String = ""
var target_id: String = ""
var result: Dictionary = {}
var hp_delta: int = 0
var shield_delta: int = 0
var timeline_before: Array[Dictionary] = []
var timeline_after: Array[Dictionary] = []


static func from_dict(data: Dictionary) -> BattleEventRecord:
	var record: BattleEventRecord = BattleEventRecord.new()
	record.time = float(data.get("time", 0.0))
	record.event_type = String(data.get("event_type", ""))
	record.actor_id = String(data.get("actor_id", ""))
	record.card_id = String(data.get("card_id", ""))
	record.target_id = String(data.get("target_id", ""))
	record.result = Dictionary(data.get("result", {}))
	record.hp_delta = int(data.get("hp_delta", 0))
	record.shield_delta = int(data.get("shield_delta", 0))
	record.timeline_before = _to_dictionary_array(data.get("timeline_before", []))
	record.timeline_after = _to_dictionary_array(data.get("timeline_after", []))
	return record


func to_dict() -> Dictionary:
	return {
		"time": time,
		"event_type": event_type,
		"actor_id": actor_id,
		"card_id": card_id,
		"target_id": target_id,
		"result": result,
		"hp_delta": hp_delta,
		"shield_delta": shield_delta,
		"timeline_before": timeline_before,
		"timeline_after": timeline_after,
	}


static func _to_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in value:
		result.append(Dictionary(item))
	return result
