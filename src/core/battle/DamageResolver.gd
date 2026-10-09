extends RefCounted
class_name DamageResolver


static func apply_damage(attacker: UnitState, defender: UnitState, base_amount: int) -> Dictionary:
	var raw: int = max(0, base_amount) + attacker.get_attack_value()
	var hp_before: int = defender.hp
	var result: Dictionary = apply_fixed_damage(defender, raw)
	attacker.combat_totals["damage"] = int(attacker.combat_totals["damage"]) + maxi(0, hp_before - defender.hp)
	attacker.combat_totals["absorbed"] = int(attacker.combat_totals["absorbed"]) + int(result["shield_absorb"])
	return result


static func apply_fixed_damage(defender: UnitState, raw: int) -> Dictionary:
	var mitigated: int = max(1, raw)
	mitigated += defender.get_incoming_damage_bonus()
	var shield_absorb: int = min(defender.shield, mitigated)
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
