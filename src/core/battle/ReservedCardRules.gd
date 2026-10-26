extends RefCounted
class_name ReservedCardRules

const MAX_PENDING := 8
const MAX_PER_KIND := 3
const COMMIT_KINDS := ["swift_commit", "heavy_commit"]
const NAMES: Dictionary = {
	"focus": "Focused Command", "shield": "Barrier Booster", "siphon": "Siphon Load",
	"reload": "Reload Reservation", "status": "Status Booster", "chain": "Chain Command",
	"growth": "Growth Mark", "tempo": "Tempo Theft", "weaken": "Weakening Tag",
	"shield_jam": "Shield Interference", "heal_jam": "Healing Corruption", "recast_jam": "Recast Jammer",
	"recoil": "Recoil Tag", "time_mine": "Time Mine", "wear": "Card Wear", "mirror": "Mirror Intercept",
	"swift_commit": "Express Cast", "heavy_commit": "Slot Jammer",
}
const TEXT: Dictionary = {
	"focus": "Next attack: damage +{amount}.", "shield": "Next shield card: shield x{amount}.",
	"siphon": "Next attack: heal {percent}% of actual HP damage.", "reload": "Next card: recast x{amount}.",
	"status": "Next status card: duration +{amount}s, bleed power +{secondary}.",
	"chain": "After the next card: automatically queue one Guard.",
	"growth": "After the next attack/shield card: its damage and shield +{amount} for this battle.",
	"tempo": "After the next card: delay all opposing cards by {amount}s.",
	"weaken": "Next attack: damage x{amount}.", "shield_jam": "Next shield card: shield x{amount}.",
	"heal_jam": "Next heal card: healing x{amount}; the opponent heals {secondary} HP.",
	"recast_jam": "Next card: recast +{amount}s.", "recoil": "After the next card: take {amount} fixed damage (shield applies).",
	"time_mine": "After the next card: delay its owner's other cards by {amount}s.",
	"wear": "After the next card: its recast +{amount}s for this battle.",
	"mirror": "Copy {percent}% of the next card's actual shield/healing to the opponent.",
	"swift_commit": "Next manual registration: cast x{amount}.",
	"heavy_commit": "Next manual registration: slots +{amount} (up to the unit's slot capacity).",
}


static func kind_name(kind: String) -> String:
	return Localization.get_text("reservation.name." + kind, NAMES.get(kind, kind))


static func describe(effect: Dictionary) -> String:
	var kind: String = effect.get("reservation", "")
	var amount: float = float(effect.get("amount", 1))
	return Localization.get_text("reservation.effect." + kind, TEXT.get(kind, kind)).format({"amount": String.num(amount, 2), "percent": String.num(amount * 100, 0), "secondary": String.num(float(effect.get("secondary", 0)), 2)})


static func grant(unit: UnitState, effect: Dictionary, source_side: String) -> bool:
	var kind: String = effect.get("reservation", "")
	if unit == null or not NAMES.has(kind) or unit.card_reservations.size() >= MAX_PENDING: return false
	var count: int = 0
	for entry: Dictionary in unit.card_reservations:
		if entry.get("reservation") == kind: count += 1
	if count >= MAX_PER_KIND: return false
	var entry: Dictionary = {"reservation": kind, "amount": float(effect.get("amount", 1)), "secondary": float(effect.get("secondary", 0)), "source_side": source_side, "hostile": effect.get("target", "self") == "enemy"}
	unit.card_reservations.append(entry)
	return true


static func matches(entry: Dictionary, card: CardDef, trigger: String = "resolve") -> bool:
	if card == null or RepeatRules.is_setup_card(card): return false
	var kind: String = entry.get("reservation", "")
	if COMMIT_KINDS.has(kind) != (trigger == "commit"): return false
	var types: Array[String] = []
	for effect: Dictionary in card.effects: types.append(String(effect.get("type", "")))
	match kind:
		"focus", "siphon", "weaken": return types.has("deal_damage")
		"shield", "shield_jam": return types.has("gain_shield")
		"heal_jam": return types.has("heal")
		"status": return types.has("apply_status")
		"mirror": return types.has("gain_shield") or types.has("heal")
		"growth": return types.has("deal_damage") or types.has("gain_shield")
	return NAMES.has(kind)


static func select(pending: Array[Dictionary], card: CardDef, trigger: String = "resolve", consume: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var used: Array[String] = []
	for entry: Dictionary in pending:
		var kind: String = entry.get("reservation", "")
		if not used.has(kind) and matches(entry, card, trigger):
			result.append(entry); used.append(kind)
	if consume:
		for entry: Dictionary in result: pending.erase(entry)
	return result


static func commit_profile(profile: Dictionary, entries: Array[Dictionary], max_slots: int = 3) -> void:
	for entry: Dictionary in entries:
		match entry["reservation"]:
			"swift_commit": profile["cast_time"] = float(profile["cast_time"]) * clampf(float(entry["amount"]), 0.1, 1)
			"heavy_commit": profile["slot_cost"] = mini(max_slots, int(profile["slot_cost"]) + clampi(int(entry["amount"]), 1, 2))


static func recast_duration(duration: float, entries: Array[Dictionary]) -> float:
	var added: float = 0
	var multiplier: float = 1
	for entry: Dictionary in entries:
		match entry["reservation"]:
			"reload": multiplier *= clampf(float(entry["amount"]), 0.1, 1)
			"recast_jam", "wear": added += float(entry["amount"])
	return duration * multiplier + added


static func effect_value(entries: Array[Dictionary], effect_type: String, amount: float) -> float:
	for entry: Dictionary in entries:
		match entry["reservation"]:
			"focus":
				if effect_type == "deal_damage": amount += float(entry["amount"])
			"shield", "shield_jam":
				if effect_type == "gain_shield": amount *= float(entry["amount"])
			"heal_jam":
				if effect_type == "heal": amount *= float(entry["amount"])
	return amount


static func attack_scale(entries: Array[Dictionary]) -> float:
	for entry: Dictionary in entries:
		if entry["reservation"] == "weaken": return clampf(float(entry["amount"]), 0.1, 1)
	return 1


static func status_bonus(entries: Array[Dictionary], bleed: bool = false) -> float:
	for entry: Dictionary in entries:
		if entry["reservation"] == "status": return float(entry["secondary"] if bleed else entry["amount"])
	return 0


static func after_effects(engine: RealtimeBattleEngine, instance: ActiveCardInstance) -> void:
	var side: String = instance.owner_side
	var other: String = "enemy" if side == "player" else "player"
	var unit: UnitState = engine.battle_state.get_unit(side)
	var opponent: UnitState = engine.battle_state.get_unit(other)
	# Totals are frozen before post-triggers, so copied heals cannot feed each other.
	var damage: int = int(engine.resolution_metrics.get("damage", 0))
	var shield: int = int(engine.resolution_metrics.get("shield", 0))
	var heal: int = int(engine.resolution_metrics.get("heal", 0))
	for entry: Dictionary in instance.card_reservations:
		var amount: float = float(entry["amount"])
		match entry["reservation"]:
			"siphon":
				if unit.is_alive(): engine.resolution_metrics["heal"] += DamageResolver.heal(unit, floori(damage * amount))
			"heal_jam":
				if opponent.is_alive(): engine.analysis.record_reservation_proc(other, "heal_jam", {"heal": DamageResolver.heal(opponent, int(entry["secondary"]))})
			"mirror":
				if opponent.is_alive():
					var copied_shield: int = DamageResolver.gain_shield(opponent, floori(shield * amount))
					var copied_heal: int = DamageResolver.heal(opponent, floori(heal * amount))
					engine.analysis.record_reservation_proc(other, "mirror", {"shield": copied_shield, "heal": copied_heal})
			"recoil":
				var before: int = unit.hp
				var result: Dictionary = DamageResolver.apply_fixed_damage(unit, roundi(amount))
				opponent.combat_totals["damage"] += maxi(0, before - unit.hp)
				opponent.combat_totals["absorbed"] += int(result["shield_absorb"])
				engine.analysis.record_reservation_proc(other, "recoil", {"damage": maxi(0, before - unit.hp), "absorbed": int(result["shield_absorb"])})
				engine.prevent_lethal(side)
			"growth":
				engine.add_battle_card_modifier(side, instance.card_id, "damage", amount)
				engine.add_battle_card_modifier(side, instance.card_id, "shield", amount)
			"wear": engine.add_battle_card_modifier(side, instance.card_id, "recast_time", amount)
			"tempo": engine.delay_active_cards(other, amount, "all", side)
			"time_mine": engine.delay_active_cards(side, amount, "all", other)
			"chain":
				if unit.is_alive() and opponent.is_alive(): engine.auto_queue_card(side, instance, {"card_id": "guard", "delay": 0.3, "max_depth": 1})


static func preview_card(card: CardDef, entries: Array[Dictionary], attack_multiplier: float = 1.0) -> CardDef:
	if entries.is_empty(): return card
	var result: CardDef = CardDef.from_dict(card.to_dict())
	result.recast_time = maxf(4, recast_duration(result.recast_time, entries))
	for effect: Dictionary in result.effects:
		var type: String = effect.get("type", "")
		if type in ["deal_damage", "gain_shield", "heal"]:
			var scaled_entries: Array[Dictionary] = entries.duplicate(true)
			for entry: Dictionary in scaled_entries:
				if entry["reservation"] == "focus": entry["amount"] = float(entry["amount"]) * attack_multiplier
			effect["amount"] = roundi(effect_value(scaled_entries, type, float(effect.get("amount", 0))) * (attack_scale(entries) if type == "deal_damage" else 1.0))
		if type == "apply_status":
			effect["duration"] = float(effect.get("duration", 0)) + status_bonus(entries)
			if effect.get("status") == "bleed": effect["bleed_power"] = int(effect.get("bleed_power", 1)) + int(status_bonus(entries, true))
	return result


static func display_statuses(unit: UnitState, display: Dictionary) -> void:
	for hostile: bool in [false, true]:
		var entries: Array[Dictionary] = []
		for entry: Dictionary in unit.card_reservations:
			if bool(entry.get("hostile", false)) == hostile: entries.append(entry)
		if not entries.is_empty(): display["reservation_hex" if hostile else "reservation_boost"] = {"charges": entries.size(), "duration": 0.0, "reservations": entries}
