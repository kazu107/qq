extends RefCounted
class_name BattleState

var battle_time: float = 0.0
var player: UnitState
var enemy: UnitState
var active_instances: Array[ActiveCardInstance] = []
var timeline: Array[TimelineEntry] = []
var logs: Array[String] = []
var battle_events: Array[Dictionary] = []
var winner: String = ""
var next_instance_id: int = 1


func add_log(text: String) -> void:
	logs.append("[%.1f] %s" % [battle_time, text])
	while logs.size() > 24:
		logs.remove_at(0)


func record_event(event_data: Dictionary) -> void:
	battle_events.append(event_data.duplicate(true))


func get_unit(side: String) -> UnitState:
	if side == "player":
		return player
	return enemy


func get_opponent(side: String) -> UnitState:
	if side == "player":
		return enemy
	return player


func get_active_instances_for_side(side: String, exclude_instance_id: int = -1) -> Array[ActiveCardInstance]:
	var result: Array[ActiveCardInstance] = []
	for instance in active_instances:
		if instance.owner_side != side:
			continue
		if exclude_instance_id >= 0 and instance.instance_id == exclude_instance_id:
			continue
		result.append(instance)
	return result


func get_active_instance_by_id(instance_id: int) -> ActiveCardInstance:
	for instance in active_instances:
		if instance.instance_id == instance_id:
			return instance
	return null


func remove_active_instance(instance_id: int) -> ActiveCardInstance:
	for index in range(active_instances.size()):
		var instance := active_instances[index]
		if instance.instance_id == instance_id:
			active_instances.remove_at(index)
			return instance
	return null
