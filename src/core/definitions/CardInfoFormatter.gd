extends RefCounted
class_name CardInfoFormatter


static func build_effect_lines(card_def: CardDef) -> Array[String]:
	var lines: Array[String] = []
	for raw_effect in card_def.effects:
		lines.append(_describe_effect(Dictionary(raw_effect), false))
	return lines


static func build_effect_summary(card_def: CardDef) -> String:
	var parts: Array[String] = []
	for raw_effect in card_def.effects:
		parts.append(_describe_effect(Dictionary(raw_effect), true))
	if parts.is_empty():
		return Localization.get_text("card.effect.none", "No effect data")
	return "; ".join(parts)


static func build_grade_lines(card_id: String) -> Array[String]:
	var lines: Array[String] = []
	for tier in range(CardUpgradeResolver.MAX_TIER + 1):
		var grade_card: CardDef = CardUpgradeResolver.build_card_at_tier(card_id, tier)
		if grade_card == null:
			continue
		lines.append(Localization.get_textf(
			"card.grade.line",
			"{grade} | Cast {cast_time}s | Recast {recast_time}s | {effect_summary}",
			{
				"grade": format_grade_label(tier),
				"cast_time": "%.1f" % grade_card.cast_time,
				"recast_time": "%.1f" % grade_card.recast_time,
				"effect_summary": build_effect_summary(grade_card),
			}
		))
	return lines


static func format_grade_label(tier: int) -> String:
	return Localization.get_grade_label(tier)


static func _describe_effect(effect: Dictionary, compact: bool) -> String:
	var effect_type: String = String(effect.get("type", ""))
	match effect_type:
		"deal_damage":
			var damage_text: String = Localization.get_textf("effect.deal_damage", "Deal {amount} damage", {
				"amount": int(effect.get("amount", 0)),
			})
			damage_text += _build_bonus_suffix(effect)
			return damage_text
		"gain_shield":
			return Localization.get_textf("effect.gain_shield", "Gain {amount} shield", {
				"amount": int(effect.get("amount", 0)),
			})
		"heal":
			return Localization.get_textf("effect.heal", "Heal {amount} HP", {
				"amount": int(effect.get("amount", 0)),
			})
		"apply_status":
			return Localization.get_textf("effect.apply_status", "Apply {status} for {duration}s to {target}", {
				"status": Localization.get_status_name(String(effect.get("status", ""))),
				"duration": "%.1f" % float(effect.get("duration", 0.0)),
				"target": _target_label(effect),
			})
		"remove_status":
			return Localization.get_textf("effect.remove_status", "Remove {status} from {target}", {
				"status": Localization.get_status_name(String(effect.get("status", ""))),
				"target": _target_label(effect),
			})
		"delay_enemy_active_card":
			return Localization.get_textf("effect.delay_enemy_active_card", "Delay {scope} by {amount}s", {
				"scope": _delay_scope_label(String(effect.get("scope", "single"))),
				"amount": "%.1f" % float(effect.get("amount", 0.0)),
			})
		"haste_own_active_card":
			return Localization.get_textf("effect.haste_own_active_card", "Haste {scope} by {amount}s", {
				"scope": _haste_scope_label(String(effect.get("scope", "single"))),
				"amount": "%.1f" % float(effect.get("amount", 0.0)),
			})
		"reduce_recast":
			return Localization.get_textf("effect.reduce_recast", "Reduce cooldown of {scope} by {amount}s", {
				"scope": _cooldown_scope_label(String(effect.get("scope", "highest_cooldown"))),
				"amount": "%.1f" % float(effect.get("amount", 0.0)),
			})
		"interrupt_card":
			return Localization.get_textf("effect.interrupt_card", "Interrupt {scope}", {
				"scope": _interrupt_scope_label(String(effect.get("scope", "single_interruptible"))),
			})
		"modify_attack":
			return Localization.get_textf("effect.modify_attack", "Modify attack of {target} by {amount}", {
				"target": _target_label(effect),
				"amount": _format_signed_value(int(effect.get("amount", 0))),
			})
		"modify_defense":
			return Localization.get_textf("effect.modify_defense", "Modify defense of {target} by {amount}", {
				"target": _target_label(effect),
				"amount": _format_signed_value(int(effect.get("amount", 0))),
			})
		"modify_speed":
			return Localization.get_textf("effect.modify_speed", "Modify speed of {target} by {amount}", {
				"target": _target_label(effect),
				"amount": _format_signed_value(int(effect.get("amount", 0))),
			})
		_:
			if compact:
				return effect_type
			return Localization.get_textf("effect.unknown", "Unknown effect: {effect_type}", {
				"effect_type": effect_type,
			})


static func _build_bonus_suffix(effect: Dictionary) -> String:
	var suffix_parts: Array[String] = []
	if effect.has("bonus_if_target_hp_below_ratio"):
		suffix_parts.append(Localization.get_textf(
			"effect.bonus.low_hp",
			"+{amount} if target HP <= {ratio}%",
			{
				"amount": int(effect.get("bonus_amount", 0)),
				"ratio": int(round(float(effect.get("bonus_if_target_hp_below_ratio", 0.0)) * 100.0)),
			}
		))
	if effect.has("bonus_if_target_has_status"):
		suffix_parts.append(Localization.get_textf(
			"effect.bonus.target_status",
			"+{amount} if target has {status}",
			{
				"amount": int(effect.get("bonus_amount", 0)),
				"status": Localization.get_status_name(String(effect.get("bonus_if_target_has_status", ""))),
			}
		))
	if suffix_parts.is_empty():
		return ""
	return " (%s)" % ", ".join(suffix_parts)


static func _target_label(effect: Dictionary) -> String:
	match String(effect.get("target", "self")):
		"enemy":
			return Localization.get_target_name("enemy")
		_:
			return Localization.get_target_name("self")


static func _delay_scope_label(scope: String) -> String:
	match scope:
		"all":
			return Localization.get_text("effect.scope.delay_all", "all enemy active cards")
		_:
			return Localization.get_text("effect.scope.delay_single", "1 enemy active card")


static func _haste_scope_label(scope: String) -> String:
	match scope:
		"all":
			return Localization.get_text("effect.scope.haste_all", "all own active cards")
		_:
			return Localization.get_text("effect.scope.haste_single", "1 own active card")


static func _cooldown_scope_label(scope: String) -> String:
	match scope:
		"all":
			return Localization.get_text("effect.scope.cooldown_all", "all own cards")
		"last_used":
			return Localization.get_text("effect.scope.cooldown_last_used", "the last used own card")
		_:
			return Localization.get_text("effect.scope.cooldown_highest", "the own highest-cooldown card")


static func _interrupt_scope_label(scope: String) -> String:
	match scope:
		"all_interruptible":
			return Localization.get_text("effect.scope.interrupt_all", "all enemy interruptible cards")
		_:
			return Localization.get_text("effect.scope.interrupt_single", "1 enemy interruptible card")


static func _format_signed_value(amount: int) -> String:
	if amount >= 0:
		return "+%d" % amount
	return "%d" % amount
