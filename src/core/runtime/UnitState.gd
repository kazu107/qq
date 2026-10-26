extends RefCounted
class_name UnitState

const BLEED_TICK_INTERVAL := BleedRules.TICK_INTERVAL

var unit_id: String = ""
var display_name: String = ""
var hp: int = 1
var max_hp: int = 1
var shield: int = 0
var attack: int = 0
var next_attack_multiplier: float = 1.0
var repeat_charges: int = 0
var card_reservations: Array[Dictionary] = []
var speed: int = 0
var statuses: Dictionary = {}
var active_slots_used: int = 0
var active_slot_max: int = 3
var card_runtime_states: Array[CardRuntimeState] = []
var temporary_card_modifiers: Dictionary = {}
var battle_card_modifiers: Dictionary = {}
var last_used_runtime_id: String = ""
var previous_used_runtime_id: String = ""
var cast_time_modifier: float = 1.0
var shield_decay_interval: float = 1.0
var _shield_decay_accumulator: float = 0.0
var combat_totals: Dictionary = {"damage": 0, "absorbed": 0, "damage_taken": 0, "blocked": 0, "shield": 0, "heal": 0}


func is_alive() -> bool:
	return hp > 0


func get_attack_value() -> int:
	var base_attack := attack
	if has_status("weak"):
		base_attack -= 2
	return max(0, base_attack)


func charge_next_attack(multiplier: float) -> void:
	next_attack_multiplier *= maxf(1.0, multiplier)


func get_attack_charge_label() -> String:
	return "x%s" % String.num(next_attack_multiplier, 0)


func consume_next_attack_multiplier() -> float:
	var multiplier: float = next_attack_multiplier
	next_attack_multiplier = 1.0
	return multiplier


func get_display_statuses() -> Dictionary:
	var display: Dictionary = statuses.duplicate(true)
	if display.has("bleed"): display["bleed"] = BleedRules.normalize(display["bleed"])
	if display.has("regen"): display["regen"] = RegenerationRules.normalize(display["regen"])
	if next_attack_multiplier > 1.0:
		display["attack_charge"] = {"duration": 0.0, "charges": 1, "multiplier": next_attack_multiplier}
	if repeat_charges > 0:
		display["echo_ready"] = {"duration": 0.0, "charges": repeat_charges}
	ReservedCardRules.display_statuses(self, display)
	return display


func grant_repeat_charges(amount: int) -> int:
	var before: int = repeat_charges
	repeat_charges = clampi(repeat_charges + maxi(0, amount), 0, RepeatRules.MAX_CHARGES)
	return repeat_charges - before


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
	combat_totals["shield"] = int(combat_totals["shield"]) + maxi(0, amount)


func tick_shield_decay(delta: float) -> int:
	if shield <= 0:
		_shield_decay_accumulator = 0.0
		return 0

	_shield_decay_accumulator += delta
	var decayed: int = 0
	var interval: float = maxf(0.1, shield_decay_interval)
	while _shield_decay_accumulator >= interval and shield > 0:
		_shield_decay_accumulator -= interval
		shield -= 1
		decayed += 1

	if shield <= 0:
		shield = 0
		_shield_decay_accumulator = 0.0
	return decayed


func heal(amount: int) -> void:
	var before: int = hp
	hp = min(max_hp, hp + max(0, amount))
	combat_totals["heal"] = int(combat_totals["heal"]) + maxi(0, hp - before)


func add_status(status_id: String, duration: float, bleed_power: int = 1, source_side: String = "") -> void:
	if status_id == "regen":
		add_regeneration(duration, bleed_power, source_side, "")
		return
	if status_id == "bleed":
		var bleed: Dictionary = BleedRules.add(Dictionary(statuses.get(status_id, {})), duration, bleed_power, source_side)
		if float(bleed["duration"]) > 0: statuses[status_id] = bleed
		return
	var data: Dictionary = Dictionary(statuses.get(status_id, {"duration": 0.0, "tick_accumulator": 0.0}))
	var current_duration: float = float(data.get("duration", 0.0))
	var current_max_duration: float = float(data.get("max_duration", current_duration))
	var next_duration: float = max(current_duration, duration)
	data["duration"] = next_duration
	data["max_duration"] = maxf(maxf(current_max_duration, next_duration), duration)
	statuses[status_id] = data
	if source_side != "": statuses[status_id]["source_side"] = source_side


func adjust_status_duration(status_id: String, amount: float) -> void:
	if not statuses.has(status_id): return
	if status_id == "regen":
		statuses[status_id] = RegenerationRules.adjust_duration(statuses[status_id], amount)
		if float(statuses[status_id]["duration"]) <= 0: statuses.erase(status_id)
		return
	if status_id == "bleed":
		statuses[status_id] = BleedRules.adjust_duration(statuses[status_id], amount)
		if float(statuses[status_id]["duration"]) <= 0: statuses.erase(status_id)
	else: statuses[status_id]["duration"] = maxf(0, float(statuses[status_id].get("duration", 0)) + amount)


func remove_status(status_id: String) -> void:
	statuses.erase(status_id)


func has_status(status_id: String) -> bool:
	return statuses.has(status_id) and float(statuses[status_id].get("duration", 0.0)) > 0.0 and float(statuses[status_id].get("suspended", 0.0)) <= 0.0


func tick_statuses(delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var mixed_regen: bool = statuses.has("regen")
	var expired: Array[String] = []
	for status_id in statuses.keys():
		var data: Dictionary = Dictionary(statuses[status_id])
		if status_id == "regen":
			var tick: Dictionary = RegenerationRules.tick(data, delta)
			events.append_array(tick["events"])
			if float(tick["data"]["duration"]) <= 0: statuses.erase(status_id)
			else: statuses[status_id] = tick["data"]
			continue
		if status_id == "bleed":
			var bleed_tick: Dictionary = BleedRules.tick(data, delta)
			events.append_array(bleed_tick["events"])
			if float(bleed_tick["data"]["duration"]) <= 0: statuses.erase(status_id)
			else: statuses[status_id] = bleed_tick["data"]
			continue
		var suspended: float = float(data.get("suspended", 0.0))
		if suspended > 0.0:
			data["suspended"] = maxf(0.0, suspended - delta)
			statuses[status_id] = data
			continue
		var remaining: float = max(0.0, float(data.get("duration", 0.0)) - delta)
		data["duration"] = remaining
		statuses[status_id] = data
		if remaining <= 0.0:
			expired.append(String(status_id))
	for status_id in expired:
		statuses.erase(status_id)
		events.append({
			"type": "status_expired",
			"status": status_id,
		})
	if mixed_regen:
		events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var x: float = float(a.get("time_offset", delta)); var y: float = float(b.get("time_offset", delta))
			if not is_equal_approx(x, y): return x < y
			var order: Dictionary = {"status_damage": 0, "status_heal": 1, "status_expired": 2}
			return int(order.get(a.get("type"), 2)) < int(order.get(b.get("type"), 2)))
	return events


func add_regeneration(duration: float, power: int, source_side: String, card_id: String) -> void:
	var data: Dictionary = RegenerationRules.add(Dictionary(statuses.get("regen", {})), duration, power, source_side, card_id)
	if float(data["duration"]) > 0: statuses["regen"] = data


func get_status_summary() -> String:
	var display: Dictionary = get_display_statuses()
	if display.is_empty():
		return Localization.get_text("status.none", "None")
	var parts: Array[String] = []
	for status_id in display.keys():
		if String(status_id) in ["reservation_boost", "reservation_hex"]:
			parts.append(Localization.get_status_name(status_id) + " %d" % int(display[status_id]["charges"]))
			continue
		if String(status_id) == "echo_ready":
			parts.append(Localization.get_status_name("echo_ready") + " %d" % repeat_charges)
			continue
		if String(status_id) == "attack_charge":
			parts.append(Localization.get_status_name("attack_charge") + " " + get_attack_charge_label())
			continue
		var remaining: float = snappedf(float(display[status_id].get("duration", 0.0)), 0.1)
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
