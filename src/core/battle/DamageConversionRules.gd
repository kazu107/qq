extends RefCounted
class_name DamageConversionRules

const MAX_DURATION: float = 8.0
const MIN_LOCKOUT: float = 4.0
const CARD_IDS: Array[String] = ["life_conversion", "barrier_conversion"]


static func arm(unit: UnitState, mode: String, duration: float, ratio: float, lockout: float, card_id: String) -> bool:
	if unit == null or not unit.is_alive() or mode not in ["heal", "shield"] or unit.has_status("conversion_lockout") or duration <= 0: return false
	var current: Dictionary = Dictionary(unit.statuses.get("damage_conversion", {}))
	var remaining: float = minf(MAX_DURATION, duration)
	var fraction: float = 0
	if unit.has_status("damage_conversion"):
		remaining = minf(remaining, float(current["duration"]))
		if current.get("mode") == mode:
			ratio = maxf(ratio, float(current.get("ratio", 0)))
			fraction = float(current.get("fraction", 0))
	unit.statuses["damage_conversion"] = {"duration": remaining, "max_duration": remaining, "mode": mode, "ratio": clampf(ratio, 0, 1), "lockout_duration": clampf(lockout, MIN_LOCKOUT, 12), "fraction": fraction, "card_id": card_id}
	return true


static func end(unit: UnitState, overshoot: float = 0) -> void:
	var current: Dictionary = Dictionary(unit.statuses.get("damage_conversion", {}))
	unit.statuses.erase("damage_conversion")
	var remaining: float = maxf(0, float(current.get("lockout_duration", MIN_LOCKOUT)) - overshoot)
	if remaining > 0: unit.statuses["conversion_lockout"] = {"duration": remaining, "max_duration": remaining}


static func clear(unit: UnitState) -> void:
	unit.statuses.erase("damage_conversion"); unit.statuses.erase("conversion_lockout")


static func absorb(unit: UnitState, amount: int) -> Dictionary:
	if not unit.is_alive() or amount <= 0 or not unit.has_status("damage_conversion"): return {}
	var state: Dictionary = unit.statuses["damage_conversion"]
	var accumulated: float = amount * clampf(float(state.get("ratio", 0)), 0, 1) + float(state.get("fraction", 0))
	var converted: int = floori(accumulated + 0.0000001)
	state["fraction"] = maxf(0, accumulated - converted)
	var healed: int = 0
	var shield: int = 0
	if state.get("mode") == "heal":
		var before: int = unit.hp; unit.heal(converted); healed = unit.hp - before
	else:
		unit.add_shield(converted); shield = converted
	unit.combat_totals["prevented"] = int(unit.combat_totals.get("prevented", 0)) + amount
	var id: String = state.get("card_id", "")
	var credit: Dictionary = unit.conversion_credits.get(id, {"heal": 0, "shield": 0, "prevented": 0})
	credit["heal"] += healed; credit["shield"] += shield; credit["prevented"] += amount
	unit.conversion_credits[id] = credit
	return {"damage_prevented": amount, "converted_heal": healed, "converted_shield": shield}
