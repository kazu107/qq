extends RefCounted
class_name BattleStateCodec

const NETWORK_EVENT_WINDOW: int = 12
const NETWORK_LOG_WINDOW: int = 16
const NETWORK_RESULT_UNIT_KEYS: Array[String] = [
	"player_before",
	"player_after",
	"enemy_before",
	"enemy_after",
]


static func encode(state: BattleState, battle_started: bool, compact_for_network: bool = false) -> Dictionary:
	if state == null:
		return {}
	var active_instances: Array[Dictionary] = []
	for instance in state.active_instances:
		active_instances.append(_encode_active_instance(instance))
	var timeline: Array[Dictionary] = []
	for entry in state.timeline:
		timeline.append(_encode_timeline_entry(entry))
	var encoded_logs: Array[String] = _encode_network_logs(state.logs) if compact_for_network else state.logs.duplicate()
	var encoded_events: Array[Dictionary] = (
		_encode_network_events(state.battle_events)
		if compact_for_network
		else state.battle_events.duplicate(true)
	)
	return {
		"version": LanProtocol.SNAPSHOT_VERSION,
		"compact_for_network": compact_for_network,
		"battle_event_total": state.battle_events.size(),
		"battle_started": battle_started,
		"battle_time": state.battle_time,
		"player": _encode_unit(state.player),
		"enemy": _encode_unit(state.enemy),
		"active_instances": active_instances,
		"timeline": timeline,
		"logs": encoded_logs,
		"battle_events": encoded_events,
		"winner": state.winner,
		"next_instance_id": state.next_instance_id,
		"relic_runtime_state": state.relic_runtime_state.duplicate(true),
	}


static func _encode_network_logs(logs: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var start_index: int = maxi(0, logs.size() - NETWORK_LOG_WINDOW)
	for index in range(start_index, logs.size()):
		result.append(logs[index])
	return result


static func _encode_network_events(events: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start_index: int = maxi(0, events.size() - NETWORK_EVENT_WINDOW)
	for index in range(start_index, events.size()):
		var event_data: Dictionary = events[index]
		result.append({
			"_event_index": index,
			"time": float(event_data.get("time", 0.0)),
			"event_type": String(event_data.get("event_type", "")),
			"actor_id": String(event_data.get("actor_id", "")),
			"card_id": String(event_data.get("card_id", "")),
			"target_id": String(event_data.get("target_id", "")),
			"result": _encode_network_result(Dictionary(event_data.get("result", {}))),
			"hp_delta": int(event_data.get("hp_delta", 0)),
			"shield_delta": int(event_data.get("shield_delta", 0)),
		})
	return result


static func _encode_network_result(result: Dictionary) -> Dictionary:
	var compact_result: Dictionary = {}
	for key: String in NETWORK_RESULT_UNIT_KEYS:
		var unit_data: Dictionary = Dictionary(result.get(key, {}))
		if unit_data.is_empty():
			continue
		compact_result[key] = {
			"hp": int(unit_data.get("hp", 0)),
			"shield": int(unit_data.get("shield", 0)),
		}
	return compact_result


static func decode(payload: Dictionary) -> BattleState:
	if int(payload.get("version", -1)) != LanProtocol.SNAPSHOT_VERSION:
		return null
	var state: BattleState = BattleState.new()
	state.battle_time = maxf(0.0, float(payload.get("battle_time", 0.0)))
	state.player = _decode_unit(Dictionary(payload.get("player", {})))
	state.enemy = _decode_unit(Dictionary(payload.get("enemy", {})))
	if state.player == null or state.enemy == null:
		return null
	for raw_instance in Array(payload.get("active_instances", [])):
		state.active_instances.append(_decode_active_instance(Dictionary(raw_instance)))
	for raw_entry in Array(payload.get("timeline", [])):
		state.timeline.append(_decode_timeline_entry(Dictionary(raw_entry)))
	state.logs = _to_string_array(payload.get("logs", []))
	state.battle_events = _to_dictionary_array(payload.get("battle_events", []))
	state.winner = String(payload.get("winner", ""))
	state.next_instance_id = maxi(1, int(payload.get("next_instance_id", 1)))
	state.relic_runtime_state = Dictionary(payload.get("relic_runtime_state", {})).duplicate(true)
	return state


static func _encode_unit(unit: UnitState) -> Dictionary:
	if unit == null:
		return {}
	var runtime_states: Array[Dictionary] = []
	for runtime_state in unit.card_runtime_states:
		runtime_states.append({
			"runtime_id": runtime_state.runtime_id,
			"card_id": runtime_state.card_id,
			"loadout_index": runtime_state.loadout_index,
			"state": int(runtime_state.state),
			"cooldown_remaining": runtime_state.cooldown_remaining,
		})
	return {
		"unit_id": unit.unit_id,
		"display_name": unit.display_name,
		"hp": unit.hp,
		"max_hp": unit.max_hp,
		"shield": unit.shield,
		"attack": unit.attack,
		"speed": unit.speed,
		"statuses": unit.statuses.duplicate(true),
		"active_slots_used": unit.active_slots_used,
		"active_slot_max": unit.active_slot_max,
		"runtime_states": runtime_states,
		"temporary_card_modifiers": unit.temporary_card_modifiers.duplicate(true),
		"battle_card_modifiers": unit.battle_card_modifiers.duplicate(true),
		"last_used_runtime_id": unit.last_used_runtime_id,
		"previous_used_runtime_id": unit.previous_used_runtime_id,
		"cast_time_modifier": unit.cast_time_modifier,
		"shield_decay_interval": unit.shield_decay_interval,
	}


static func _decode_unit(payload: Dictionary) -> UnitState:
	if payload.is_empty():
		return null
	var unit: UnitState = UnitState.new()
	unit.unit_id = String(payload.get("unit_id", ""))
	unit.display_name = String(payload.get("display_name", unit.unit_id))
	unit.hp = int(payload.get("hp", 1))
	unit.max_hp = maxi(1, int(payload.get("max_hp", 1)))
	unit.shield = maxi(0, int(payload.get("shield", 0)))
	unit.attack = int(payload.get("attack", 0))
	unit.speed = int(payload.get("speed", 0))
	unit.statuses = Dictionary(payload.get("statuses", {})).duplicate(true)
	unit.active_slots_used = maxi(0, int(payload.get("active_slots_used", 0)))
	unit.active_slot_max = maxi(1, int(payload.get("active_slot_max", 3)))
	var runtime_states: Array[CardRuntimeState] = []
	for raw_runtime in Array(payload.get("runtime_states", [])):
		var runtime_data: Dictionary = Dictionary(raw_runtime)
		var runtime_state: CardRuntimeState = CardRuntimeState.new()
		runtime_state.runtime_id = String(runtime_data.get("runtime_id", ""))
		runtime_state.card_id = String(runtime_data.get("card_id", ""))
		runtime_state.loadout_index = int(runtime_data.get("loadout_index", 0))
		runtime_state.state = clampi(
			int(runtime_data.get("state", CardRuntimeState.CardState.READY)),
			CardRuntimeState.CardState.READY,
			CardRuntimeState.CardState.INTERRUPTED
		)
		runtime_state.cooldown_remaining = maxf(0.0, float(runtime_data.get("cooldown_remaining", 0.0)))
		runtime_states.append(runtime_state)
	unit.set_runtime_states(runtime_states)
	unit.temporary_card_modifiers = Dictionary(payload.get("temporary_card_modifiers", {})).duplicate(true)
	unit.battle_card_modifiers = Dictionary(payload.get("battle_card_modifiers", {})).duplicate(true)
	unit.last_used_runtime_id = String(payload.get("last_used_runtime_id", ""))
	unit.previous_used_runtime_id = String(payload.get("previous_used_runtime_id", ""))
	unit.cast_time_modifier = maxf(0.05, float(payload.get("cast_time_modifier", 1.0)))
	unit.shield_decay_interval = maxf(0.1, float(payload.get("shield_decay_interval", 1.0)))
	return unit


static func _encode_active_instance(instance: ActiveCardInstance) -> Dictionary:
	return {
		"instance_id": instance.instance_id,
		"owner_side": instance.owner_side,
		"runtime_id": instance.runtime_id,
		"card_id": instance.card_id,
		"card_name": instance.card_name,
		"scheduled_time": instance.scheduled_time,
		"sort_key": instance.sort_key,
		"priority_modifier": instance.priority_modifier,
		"slot_cost": instance.slot_cost,
		"interruptible": instance.interruptible,
		"actor_speed": instance.actor_speed,
		"target_type": instance.target_type,
		"created_at": instance.created_at,
		"is_auto_queued": instance.is_auto_queued,
		"auto_depth": instance.auto_depth,
		"source_instance_id": instance.source_instance_id,
		"shield_cost_paid": instance.shield_cost_paid,
		"source_card_id": instance.source_card_id,
		"relic_effect_bonus": instance.relic_effect_bonus,
		"relic_recast_multiplier": instance.relic_recast_multiplier,
		"relic_recast_delta": instance.relic_recast_delta,
		"relic_delay_bank": instance.relic_delay_bank,
		"relic_delay_hits": instance.relic_delay_hits,
		"relic_flags": instance.relic_flags.duplicate(true),
		"continuous_shift_battle_time": instance.continuous_shift_battle_time,
		"continuous_shift_amount": instance.continuous_shift_amount,
	}


static func _decode_active_instance(payload: Dictionary) -> ActiveCardInstance:
	var instance: ActiveCardInstance = ActiveCardInstance.new()
	instance.instance_id = int(payload.get("instance_id", 0))
	instance.owner_side = String(payload.get("owner_side", ""))
	instance.runtime_id = String(payload.get("runtime_id", ""))
	instance.card_id = String(payload.get("card_id", ""))
	instance.card_name = String(payload.get("card_name", instance.card_id))
	instance.scheduled_time = float(payload.get("scheduled_time", 0.0))
	instance.sort_key = float(payload.get("sort_key", instance.scheduled_time))
	instance.priority_modifier = float(payload.get("priority_modifier", 0.0))
	instance.slot_cost = maxi(0, int(payload.get("slot_cost", 1)))
	instance.interruptible = bool(payload.get("interruptible", false))
	instance.actor_speed = int(payload.get("actor_speed", 0))
	instance.target_type = String(payload.get("target_type", "enemy"))
	instance.created_at = float(payload.get("created_at", 0.0))
	instance.is_auto_queued = bool(payload.get("is_auto_queued", false))
	instance.auto_depth = maxi(0, int(payload.get("auto_depth", 0)))
	instance.source_instance_id = int(payload.get("source_instance_id", 0))
	instance.shield_cost_paid = maxi(0, int(payload.get("shield_cost_paid", 0)))
	instance.source_card_id = String(payload.get("source_card_id", ""))
	instance.relic_effect_bonus = int(payload.get("relic_effect_bonus", 0))
	instance.relic_recast_multiplier = maxf(0.05, float(payload.get("relic_recast_multiplier", 1.0)))
	instance.relic_recast_delta = float(payload.get("relic_recast_delta", 0.0))
	instance.relic_delay_bank = maxf(0.0, float(payload.get("relic_delay_bank", 0.0)))
	instance.relic_delay_hits = maxi(0, int(payload.get("relic_delay_hits", 0)))
	instance.relic_flags = Dictionary(payload.get("relic_flags", {})).duplicate(true)
	instance.continuous_shift_battle_time = float(payload.get("continuous_shift_battle_time", -1.0))
	instance.continuous_shift_amount = float(payload.get("continuous_shift_amount", 0.0))
	return instance


static func _encode_timeline_entry(entry: TimelineEntry) -> Dictionary:
	return {
		"instance_id": entry.instance_id,
		"owner_side": entry.owner_side,
		"runtime_id": entry.runtime_id,
		"card_id": entry.card_id,
		"card_name": entry.card_name,
		"scheduled_time": entry.scheduled_time,
		"created_at": entry.created_at,
		"sort_key": entry.sort_key,
		"priority_modifier": entry.priority_modifier,
		"actor_speed": entry.actor_speed,
		"slot_cost": entry.slot_cost,
		"interruptible": entry.interruptible,
		"continuous_shift_battle_time": entry.continuous_shift_battle_time,
		"continuous_shift_amount": entry.continuous_shift_amount,
	}


static func _decode_timeline_entry(payload: Dictionary) -> TimelineEntry:
	var entry: TimelineEntry = TimelineEntry.new()
	entry.instance_id = int(payload.get("instance_id", 0))
	entry.owner_side = String(payload.get("owner_side", ""))
	entry.runtime_id = String(payload.get("runtime_id", ""))
	entry.card_id = String(payload.get("card_id", ""))
	entry.card_name = String(payload.get("card_name", entry.card_id))
	entry.scheduled_time = float(payload.get("scheduled_time", 0.0))
	entry.created_at = float(payload.get("created_at", 0.0))
	entry.sort_key = float(payload.get("sort_key", entry.scheduled_time))
	entry.priority_modifier = float(payload.get("priority_modifier", 0.0))
	entry.actor_speed = int(payload.get("actor_speed", 0))
	entry.slot_cost = maxi(0, int(payload.get("slot_cost", 1)))
	entry.interruptible = bool(payload.get("interruptible", false))
	entry.continuous_shift_battle_time = float(payload.get("continuous_shift_battle_time", -1.0))
	entry.continuous_shift_amount = float(payload.get("continuous_shift_amount", 0.0))
	return entry


static func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in Array(value):
		result.append(String(item))
	return result


static func _to_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in Array(value):
		result.append(Dictionary(item).duplicate(true))
	return result
