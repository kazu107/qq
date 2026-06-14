extends RefCounted
class_name UnitState

const BLEED_TICK_INTERVAL := 6.0

var unit_id: String = ""
var display_name: String = ""
var hp: int = 1
var max_hp: int = 1
var shield: int = 0
var attack: int = 0
var defense: int = 0
var speed: int = 0
var statuses: Dictionary = {}
var active_slots_used: int = 0
var active_slot_max: int = 3
var card_runtime_states: Array[CardRuntimeState] = []
var temporary_card_modifiers: Dictionary = {}
var last_used_runtime_id: String = ""
var previous_used_runtime_id: String = ""
var cast_time_modifier: float = 1.0
var _shield_decay_accumulator: float = 0.0


func is_alive() -> bool:
	return hp > 0


func get_attack_value() -> int:
	var base_attack := attack
	if has_status("weak"):
		base_attack -= 2
	return max(0, base_attack)


func get_defense_value() -> int:
	return max(0, defense)


func get_cast_time_multiplier() -> float:
	var modifier: float = cast_time_modifier
	if has_status("slow"):
		modifier *= 1.1
	return modifier


func get_incoming_damage_bonus() -> int:
	if has_status("vulnerable"):
		return 3
	return 0


func add_shield(amount: int) -> void:
	shield += max(0, amount)


func tick_shield_decay(delta: float) -> int:
	if shield <= 0:
		_shield_decay_accumulator = 0.0
		return 0

	_shield_decay_accumulator += delta
	var decayed: int = 0
	while _shield_decay_accumulator >= 1.0 and shield > 0:
		_shield_decay_accumulator -= 1.0
		shield -= 1
		decayed += 1

	if shield <= 0:
		shield = 0
		_shield_decay_accumulator = 0.0
	return decayed


func heal(amount: int) -> void:
	hp = min(max_hp, hp + max(0, amount))


func add_status(status_id: String, duration: float) -> void:
	var data: Dictionary = Dictionary(statuses.get(status_id, {"duration": 0.0, "tick_accumulator": 0.0}))
	var current_duration: float = float(data.get("duration", 0.0))
	var current_max_duration: float = float(data.get("max_duration", current_duration))
	var next_duration: float = max(current_duration, duration)
	data["duration"] = next_duration
	data["max_duration"] = maxf(maxf(current_max_duration, next_duration), duration)
	statuses[status_id] = data


func remove_status(status_id: String) -> void:
	statuses.erase(status_id)


func has_status(status_id: String) -> bool:
	return statuses.has(status_id) and float(statuses[status_id].get("duration", 0.0)) > 0.0


func tick_statuses(delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var expired: Array[String] = []
	for status_id in statuses.keys():
		var data: Dictionary = Dictionary(statuses[status_id])
		var remaining: float = max(0.0, float(data.get("duration", 0.0)) - delta)
		data["duration"] = remaining
		if status_id == "bleed":
			var tick_accumulator: float = float(data.get("tick_accumulator", 0.0)) + delta
			while tick_accumulator >= BLEED_TICK_INTERVAL and remaining > 0.0:
				tick_accumulator -= BLEED_TICK_INTERVAL
				events.append({
					"type": "status_damage",
					"status": status_id,
					"amount": 1,
				})
			data["tick_accumulator"] = tick_accumulator
		statuses[status_id] = data
		if remaining <= 0.0:
			expired.append(String(status_id))
	for status_id in expired:
		statuses.erase(status_id)
	return events


func get_status_summary() -> String:
	if statuses.is_empty():
		return Localization.get_text("status.none", "None")
	var parts: Array[String] = []
	for status_id in statuses.keys():
		var remaining: float = snappedf(float(statuses[status_id].get("duration", 0.0)), 0.1)
		parts.append("%s %.1fs" % [Localization.get_status_name(String(status_id)), remaining])
	return ", ".join(parts)


func get_runtime_state(runtime_id: String) -> CardRuntimeState:
	for runtime_state in card_runtime_states:
		if runtime_state.runtime_id == runtime_id:
			return runtime_state
	return null


func set_runtime_states(states: Array[CardRuntimeState]) -> void:
	card_runtime_states = states


func get_sorted_runtime_states() -> Array[CardRuntimeState]:
	var states: Array[CardRuntimeState] = card_runtime_states.duplicate()
	states.sort_custom(func(a: CardRuntimeState, b: CardRuntimeState) -> bool:
		return a.loadout_index < b.loadout_index
	)
	return states
