extends RefCounted
class_name BattleRecording

const MAX_FRAMES: int = 3000
var frames: Array[Dictionary] = []
var interval: float = 0.25
var _last_time: float = -1.0


func capture(state: BattleState, force: bool = false) -> void:
	if state == null or (not force and state.battle_time - _last_time < interval):
		return
	var timeline: Array[Dictionary] = []
	for entry in state.timeline:
		timeline.append(BattleStateCodec._encode_timeline_entry(entry))
	var frame: Dictionary = {"time": state.battle_time, "timeline": timeline,
		"player": _unit_frame(state.player, is_zero_approx(state.battle_time)), "enemy": _unit_frame(state.enemy, is_zero_approx(state.battle_time))}
	if not frames.is_empty() and is_equal_approx(float(frames.back()["time"]), state.battle_time):
		frames[-1] = frame
	else:
		frames.append(frame)
	_last_time = state.battle_time
	if frames.size() >= MAX_FRAMES:
		var reduced: Array[Dictionary] = []
		for index in range(0, frames.size(), 2):
			reduced.append(frames[index])
		reduced.append(frames.back())
		frames = reduced
		interval *= 2.0


func _unit_frame(unit: UnitState, initial: bool = false) -> Dictionary:
	if frames.is_empty() or initial:
		return BattleStateCodec._encode_unit(unit)
	return {"unit_id": unit.unit_id, "display_name": unit.display_name, "hp": unit.hp, "max_hp": unit.max_hp,
		"shield": unit.shield, "attack": unit.attack, "speed": unit.speed, "statuses": unit.statuses.duplicate(true),
		"active_slots_used": unit.active_slots_used, "active_slot_max": unit.active_slot_max,
		"temporary_card_modifiers": unit.temporary_card_modifiers.duplicate(true), "battle_card_modifiers": unit.battle_card_modifiers.duplicate(true),
		"cast_time_modifier": unit.cast_time_modifier}


static func frame_at(frames_data: Array, time: float) -> Dictionary:
	if frames_data.is_empty():
		return {}
	var low: int = 0
	var high: int = frames_data.size() - 1
	while low < high:
		var mid: int = (low + high + 1) / 2
		if float(frames_data[mid].get("time", 0.0)) <= time:
			low = mid
		else:
			high = mid - 1
	return Dictionary(frames_data[low])
