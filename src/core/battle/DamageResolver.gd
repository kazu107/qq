extends RefCounted
class_name DamageResolver


static func apply_damage(attacker: UnitState, defender: UnitState, base_amount: int, multiplier: float = 1.0) -> Dictionary:
	var raw: int = roundi(float(max(0, base_amount) + attacker.get_attack_value()) * multiplier)
	var hp_before: int = defender.hp
	var result: Dictionary = apply_fixed_damage(defender, raw)
	attacker.combat_totals["damage"] = int(attacker.combat_totals["damage"]) + maxi(0, hp_before - defender.hp)
	attacker.achievement_max_hit = maxi(attacker.achievement_max_hit, maxi(0, hp_before - defender.hp))
	attacker.combat_totals["absorbed"] = int(attacker.combat_totals["absorbed"]) + int(result["shield_absorb"])
	return result


static func apply_fixed_damage(defender: UnitState, raw: int, bypass_shield: bool = false, incoming_bonus: bool = true, allow_conversion: bool = true) -> Dictionary:
	var mitigated: int = max(1, raw)
	if incoming_bonus: mitigated += defender.get_incoming_damage_bonus()
	var converted: Dictionary = DamageConversionRules.absorb(defender, mitigated) if allow_conversion else {}
	if not converted.is_empty():
		converted.merge({"raw": raw, "mitigated": mitigated, "shield_absorb": 0, "hp_damage": 0, "total_damage": 0})
		return converted
	var shield_absorb: int = 0 if bypass_shield else min(defender.shield, mitigated)
	defender.shield -= shield_absorb
	var hp_damage: int = max(0, mitigated - shield_absorb)
	var hp_before: int = defender.hp
	defender.hp = max(0, defender.hp - hp_damage)
	defender.combat_totals["damage_taken"] = int(defender.combat_totals["damage_taken"]) + maxi(0, hp_before - defender.hp)
	defender.combat_totals["blocked"] = int(defender.combat_totals["blocked"]) + shield_absorb
	return {
		"raw": raw,
		"mitigated": mitigated,
		"shield_absorb": shield_absorb,
		"hp_damage": hp_damage,
		"total_damage": hp_damage + shield_absorb,
	}


static func gain_shield(target: UnitState, amount: int) -> int:
	var shield_amount: int = max(0, amount)
	target.add_shield(shield_amount)
	return shield_amount


static func heal(target: UnitState, amount: int) -> int:
	var before: int = target.hp
	target.heal(amount)
	return target.hp - before
