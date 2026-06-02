extends RefCounted
class_name TimelineResolver


func rebuild_timeline(battle_state: BattleState) -> void:
	var entries: Array[TimelineEntry] = []
	for instance in battle_state.active_instances:
		entries.append(TimelineEntry.from_instance(instance))
	entries.sort_custom(_compare_entries)
	battle_state.timeline = entries


func _compare_entries(a: TimelineEntry, b: TimelineEntry) -> bool:
	if not is_equal_approx(a.scheduled_time, b.scheduled_time):
		return a.scheduled_time < b.scheduled_time
	if not is_equal_approx(a.priority_modifier, b.priority_modifier):
		return a.priority_modifier > b.priority_modifier
	if a.actor_speed != b.actor_speed:
		return a.actor_speed > b.actor_speed
	return a.instance_id < b.instance_id
