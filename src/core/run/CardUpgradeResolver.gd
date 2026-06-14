extends RefCounted
class_name CardUpgradeResolver

const MAX_TIER := 3


static func get_tier(run_state: RunState, card_id: String) -> int:
	if run_state == null:
		return 0
	return clampi(int(run_state.card_upgrades.get(card_id, 0)), 0, MAX_TIER)


static func build_effective_card(card_id: String, run_state: RunState) -> CardDef:
	var card_def: CardDef = build_card_at_tier(card_id, get_tier(run_state, card_id))
	if card_def == null or run_state == null:
		return card_def
	var modifier_totals: Dictionary = Dictionary(run_state.temporary_card_modifiers.get(card_id, {}))
	apply_modifier_totals(card_def, modifier_totals)
	return card_def


static func build_card_with_modifiers(card_id: String, modifier_totals: Dictionary, tier: int = 0) -> CardDef:
	var card_def: CardDef = build_card_at_tier(card_id, tier)
	if card_def == null:
		return null
	apply_modifier_totals(card_def, modifier_totals)
	return card_def


static func build_card_at_tier(card_id: String, tier: int) -> CardDef:
	var base_card: CardDef = Database.get_card(card_id)
	if base_card == null:
		return null

	var safe_tier: int = clampi(tier, 0, MAX_TIER)
	var upgraded_card: CardDef = CardDef.from_dict(base_card.to_dict())
	if safe_tier <= 0:
		return upgraded_card

	upgraded_card.name = "%s +%d" % [base_card.name, safe_tier]
	_apply_upgrades(upgraded_card, safe_tier)
	return upgraded_card


static func _apply_upgrades(card_def: CardDef, tier: int) -> void:
	var damage_bonus: int = int(_get_profile_value(card_def.upgrade_profile, "damage", tier))
	var shield_bonus: int = int(_get_profile_value(card_def.upgrade_profile, "shield", tier))
	var heal_bonus: int = int(_get_profile_value(card_def.upgrade_profile, "heal", tier))
	var duration_bonus: float = float(_get_profile_value(card_def.upgrade_profile, "duration", tier))
	var delay_bonus: float = float(_get_profile_value(card_def.upgrade_profile, "delay", tier))
	var haste_bonus: float = float(_get_profile_value(card_def.upgrade_profile, "haste", tier))
	var cooldown_bonus: float = float(_get_profile_value(card_def.upgrade_profile, "cooldown", tier))
	var recast_reduction: float = float(_get_profile_value(card_def.upgrade_profile, "recast_reduction", tier))
	var recast_time_delta: float = float(_get_profile_value(card_def.upgrade_profile, "recast_time", tier))
	var cast_time_delta: float = float(_get_profile_value(card_def.upgrade_profile, "cast_time", tier))
	var timing_bonus: float = float(_get_profile_value(card_def.upgrade_profile, "timing", tier))
	var attack_mod_bonus: int = int(_get_profile_value(card_def.upgrade_profile, "attack_mod", tier))
	var defense_mod_bonus: int = int(_get_profile_value(card_def.upgrade_profile, "defense_mod", tier))
	var speed_mod_bonus: int = int(_get_profile_value(card_def.upgrade_profile, "speed_mod", tier))
	var empower_bonus: float = float(_get_profile_value(card_def.upgrade_profile, "empower", tier))

	if recast_reduction > 0.0:
		card_def.recast_time = max(0.0, card_def.recast_time - recast_reduction)
	if not is_zero_approx(recast_time_delta):
		card_def.recast_time = max(0.0, card_def.recast_time + recast_time_delta)
	if not is_zero_approx(cast_time_delta):
		card_def.cast_time = max(0.0, card_def.cast_time + cast_time_delta)

	var upgraded_effects: Array[Dictionary] = []
	for raw_effect in card_def.effects:
		var effect_data: Dictionary = Dictionary(raw_effect)
		var effect_type: String = String(effect_data.get("type", ""))
		match effect_type:
			"deal_damage":
				if damage_bonus != 0:
					effect_data["amount"] = int(effect_data.get("amount", 0)) + damage_bonus
			"gain_shield":
				if shield_bonus != 0:
					effect_data["amount"] = int(effect_data.get("amount", 0)) + shield_bonus
			"heal":
				if heal_bonus != 0:
					effect_data["amount"] = int(effect_data.get("amount", 0)) + heal_bonus
			"apply_status":
				if not is_zero_approx(duration_bonus):
					effect_data["duration"] = float(effect_data.get("duration", 0.0)) + duration_bonus
			"delay_enemy_active_card":
				var total_delay_bonus: float = delay_bonus + timing_bonus
				if not is_zero_approx(total_delay_bonus):
					effect_data["amount"] = float(effect_data.get("amount", 0.0)) + total_delay_bonus
			"haste_own_active_card":
				var total_haste_bonus: float = haste_bonus + timing_bonus
				if not is_zero_approx(total_haste_bonus):
					effect_data["amount"] = float(effect_data.get("amount", 0.0)) + total_haste_bonus
			"reduce_recast":
				if not is_zero_approx(cooldown_bonus):
					effect_data["amount"] = float(effect_data.get("amount", 0.0)) + cooldown_bonus
			"modify_attack":
				if attack_mod_bonus != 0:
					effect_data["amount"] = int(effect_data.get("amount", 0)) + attack_mod_bonus
			"modify_defense":
				if defense_mod_bonus != 0:
					effect_data["amount"] = int(effect_data.get("amount", 0)) + defense_mod_bonus
			"modify_speed":
				if speed_mod_bonus != 0:
					effect_data["amount"] = int(effect_data.get("amount", 0)) + speed_mod_bonus
			"empower_card":
				if not is_zero_approx(empower_bonus):
					effect_data["amount"] = float(effect_data.get("amount", 0.0)) + empower_bonus
			"timeline_flow":
				if not is_zero_approx(duration_bonus):
					effect_data["duration"] = maxf(0.0, float(effect_data.get("duration", 0.0)) + duration_bonus)
		upgraded_effects.append(effect_data)
	card_def.effects = upgraded_effects


static func apply_modifier_totals(card_def: CardDef, modifier_totals: Dictionary) -> void:
	if card_def == null or modifier_totals.is_empty():
		return

	if modifier_totals.has("recast_time"):
		card_def.recast_time = maxf(0.0, card_def.recast_time + float(modifier_totals.get("recast_time", 0.0)))
	if modifier_totals.has("cast_time"):
		card_def.cast_time = maxf(0.0, card_def.cast_time + float(modifier_totals.get("cast_time", 0.0)))
	if modifier_totals.has("priority"):
		card_def.priority_modifier += float(modifier_totals.get("priority", 0.0))

	var damage_bonus: int = int(round(float(modifier_totals.get("damage", 0.0))))
	var shield_bonus: int = int(round(float(modifier_totals.get("shield", 0.0))))
	var heal_bonus: int = int(round(float(modifier_totals.get("heal", 0.0))))
	var duration_bonus: float = float(modifier_totals.get("duration", 0.0))
	var delay_bonus: float = float(modifier_totals.get("delay", 0.0))
	var haste_bonus: float = float(modifier_totals.get("haste", 0.0))
	var cooldown_bonus: float = float(modifier_totals.get("cooldown", 0.0))
	var attack_mod_bonus: int = int(round(float(modifier_totals.get("attack_mod", 0.0))))
	var defense_mod_bonus: int = int(round(float(modifier_totals.get("defense_mod", 0.0))))
	var speed_mod_bonus: int = int(round(float(modifier_totals.get("speed_mod", 0.0))))
	var empower_bonus: float = float(modifier_totals.get("empower", 0.0))
	var timeline_duration_bonus: float = float(modifier_totals.get("timeline_duration", 0.0))

	var modified_effects: Array[Dictionary] = []
	for raw_effect in card_def.effects:
		var effect_data: Dictionary = Dictionary(raw_effect)
		var effect_type: String = String(effect_data.get("type", ""))
		match effect_type:
			"deal_damage":
				_add_int_delta(effect_data, "amount", damage_bonus, 0)
			"gain_shield":
				_add_int_delta(effect_data, "amount", shield_bonus, 0)
			"heal":
				_add_int_delta(effect_data, "amount", heal_bonus, 0)
			"apply_status":
				_add_float_delta(effect_data, "duration", duration_bonus, 0.0)
			"delay_enemy_active_card":
				_add_float_delta(effect_data, "amount", delay_bonus, 0.0)
			"haste_own_active_card":
				_add_float_delta(effect_data, "amount", haste_bonus, 0.0)
			"reduce_recast":
				_add_float_delta(effect_data, "amount", cooldown_bonus, 0.0)
			"modify_attack":
				_add_int_delta(effect_data, "amount", attack_mod_bonus, -999)
			"modify_defense":
				_add_int_delta(effect_data, "amount", defense_mod_bonus, -999)
			"modify_speed":
				_add_int_delta(effect_data, "amount", speed_mod_bonus, -999)
			"empower_card":
				_add_float_delta(effect_data, "amount", empower_bonus, -999.0)
			"timeline_flow":
				_add_float_delta(effect_data, "duration", timeline_duration_bonus, 0.0)
		modified_effects.append(effect_data)
	card_def.effects = modified_effects


static func _add_int_delta(effect_data: Dictionary, key: String, delta: int, minimum_value: int) -> void:
	if delta == 0:
		return
	var current_value: int = int(effect_data.get(key, 0))
	effect_data[key] = maxi(minimum_value, current_value + delta)


static func _add_float_delta(effect_data: Dictionary, key: String, delta: float, minimum_value: float) -> void:
	if is_zero_approx(delta):
		return
	var current_value: float = float(effect_data.get(key, 0.0))
	effect_data[key] = maxf(minimum_value, current_value + delta)


static func _get_profile_value(profile: Dictionary, key: String, tier: int) -> Variant:
	if not profile.has(key):
		return 0
	var values: Array = Array(profile.get(key, []))
	if values.is_empty():
		return 0
	var safe_index: int = clampi(tier, 0, values.size() - 1)
	return values[safe_index]
