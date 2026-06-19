extends RefCounted
class_name DamageResolver


static func apply_damage(attacker: UnitState, defender: UnitState, base_amount: int) -> Dictionary:
	var raw: int = max(0, base_amount) + attacker.get_attack_value()
	var mitigated: int = max(1, raw)
	mitigated += defender.get_incoming_damage_bonus()
	var shield_absorb: int = min(defender.shield, mitigated)
	defender.shield -= shield_absorb
	var hp_damage: int = max(0, mitigated - shield_absorb)
	defender.hp = max(0, defender.hp - hp_damage)
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
