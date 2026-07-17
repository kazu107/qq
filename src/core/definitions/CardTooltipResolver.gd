extends RefCounted
class_name CardTooltipResolver


static func build_context(card_id: String, run_state: RunState = null, unit: UnitState = null) -> Dictionary:
	var current_card: CardDef = _build_current_card(card_id, run_state, unit)
	var database_card: CardDef = Database.get_card(card_id)
	if current_card == null or database_card == null:
		return {"card": current_card, "comparison": null}

	var comparison_card: CardDef = CardDef.from_dict(database_card.to_dict())
	var baseline_attack: int = _get_baseline_attack(run_state, unit)
	var current_attack: int = baseline_attack
	if unit != null:
		current_attack = unit.get_attack_value()
		current_card.cast_time = maxf(0.0, current_card.cast_time * unit.get_cast_time_multiplier())

	_apply_attack_to_damage(current_card, current_attack)
	_apply_attack_to_damage(comparison_card, baseline_attack)
	return {
		"card": current_card,
		"comparison": comparison_card,
	}


static func _build_current_card(card_id: String, run_state: RunState, unit: UnitState) -> CardDef:
	var card_def: CardDef
	if run_state != null:
		card_def = CardUpgradeResolver.build_effective_card(card_id, run_state)
	elif unit != null and unit.temporary_card_modifiers.has(card_id):
		var modifier_totals: Dictionary = Dictionary(unit.temporary_card_modifiers.get(card_id, {}))
		var tier: int = clampi(int(modifier_totals.get("tier", 0)), 0, CardUpgradeResolver.MAX_TIER)
		card_def = CardUpgradeResolver.build_card_with_modifiers(card_id, modifier_totals, tier)
	else:
		var database_card: CardDef = Database.get_card(card_id)
		card_def = CardDef.from_dict(database_card.to_dict()) if database_card != null else null
	if card_def != null and unit != null:
		CardUpgradeResolver.apply_modifier_totals(
			card_def,
			Dictionary(unit.battle_card_modifiers.get(card_id, {}))
		)
	return card_def


static func _get_baseline_attack(run_state: RunState, unit: UnitState) -> int:
	if run_state != null:
		return maxi(0, run_state.attack)
	if unit == null:
		return 0
	var enemy_def: EnemyDef = Database.get_enemy(unit.unit_id)
	if enemy_def != null:
		return maxi(0, enemy_def.attack)
	return maxi(0, unit.attack)


static func _apply_attack_to_damage(card_def: CardDef, attack_value: int) -> void:
	if card_def == null or attack_value == 0:
		return
	var resolved_effects: Array[Dictionary] = []
	for raw_effect in card_def.effects:
		var effect: Dictionary = Dictionary(raw_effect).duplicate(true)
		if String(effect.get("type", "")) == "deal_damage":
			effect["amount"] = maxi(0, int(effect.get("amount", 0)) + attack_value)
		resolved_effects.append(effect)
	card_def.effects = resolved_effects
