extends RefCounted
class_name CardInfoFormatter

const BUFF_COLOR := "#72d36f"
const NERF_COLOR := "#ff6868"


static func build_effect_lines(card_def: CardDef, comparison_card_def: CardDef = null, rich: bool = false) -> Array[String]:
	var lines: Array[String] = []
	for effect_index in range(card_def.effects.size()):
		var effect: Dictionary = Dictionary(card_def.effects[effect_index])
		var comparison_effect: Dictionary = _get_comparison_effect(comparison_card_def, effect_index, effect)
		lines.append(_describe_effect(effect, false, comparison_effect, rich))
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


static func _describe_effect(effect: Dictionary, compact: bool, comparison_effect: Dictionary = {}, rich: bool = false) -> String:
	var effect_type: String = String(effect.get("type", ""))
	match effect_type:
		"deal_damage":
			var damage_text: String = Localization.get_textf("effect.deal_damage", "Deal {amount} damage", {
				"amount": _format_compared_int(effect, comparison_effect, "amount", true, rich),
			})
			damage_text += _build_bonus_suffix(effect)
			return damage_text
		"gain_shield":
			return Localization.get_textf("effect.gain_shield", "Gain {amount} shield", {
				"amount": _format_compared_int(effect, comparison_effect, "amount", true, rich),
			})
		"heal":
			return Localization.get_textf("effect.heal", "Heal {amount} HP", {
				"amount": _format_compared_int(effect, comparison_effect, "amount", true, rich),
			})
		"apply_status":
			return Localization.get_textf("effect.apply_status", "Apply {status} for {duration}s to {target}", {
				"status": Localization.get_status_name(String(effect.get("status", ""))),
				"duration": _format_compared_float(effect, comparison_effect, "duration", 1, true, rich),
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
				"amount": _format_compared_float(effect, comparison_effect, "amount", 1, true, rich),
			})
		"haste_own_active_card":
			return Localization.get_textf("effect.haste_own_active_card", "Haste {scope} by {amount}s", {
				"scope": _haste_scope_label(String(effect.get("scope", "single"))),
				"amount": _format_compared_float(effect, comparison_effect, "amount", 1, true, rich),
			})
		"reduce_recast":
			return Localization.get_textf("effect.reduce_recast", "Reduce cooldown of {scope} by {amount}s", {
				"scope": _cooldown_scope_label(String(effect.get("scope", "highest_cooldown"))),
				"amount": _format_compared_float(effect, comparison_effect, "amount", 1, true, rich),
			})
		"interrupt_card":
			return Localization.get_textf("effect.interrupt_card", "Interrupt {scope}", {
				"scope": _interrupt_scope_label(String(effect.get("scope", "single_interruptible"))),
			})
		"modify_attack":
			return Localization.get_textf("effect.modify_attack", "Modify attack of {target} by {amount}", {
				"target": _target_label(effect),
				"amount": _format_compared_signed_int(effect, comparison_effect, "amount", true, rich),
			})
		"modify_defense":
			return Localization.get_textf("effect.modify_defense", "Modify defense of {target} by {amount}", {
				"target": _target_label(effect),
				"amount": _format_compared_signed_int(effect, comparison_effect, "amount", true, rich),
			})
		"modify_speed":
			return Localization.get_textf("effect.modify_speed", "Modify speed of {target} by {amount}", {
				"target": _target_label(effect),
				"amount": _format_compared_signed_int(effect, comparison_effect, "amount", true, rich),
			})
		"empower_card":
			var empower_stat: String = String(effect.get("stat", "damage"))
			return Localization.get_textf("effect.empower_card", "Empower {scope}: {stat} {amount} for this run", {
				"scope": _empower_scope_label(effect),
				"stat": _modifier_stat_label(empower_stat),
				"amount": _format_compared_signed_float(effect, comparison_effect, "amount", 1, _is_higher_beneficial_for_modifier_stat(empower_stat), rich),
			})
		"auto_queue_card":
			var auto_queue_text: String = Localization.get_textf("effect.auto_queue_card", "Auto-queue {count} {card} after {delay}s", {
				"count": _format_compared_int(effect, comparison_effect, "count", true, rich, 1),
				"card": _auto_queue_card_label(effect),
				"delay": _format_compared_float(effect, comparison_effect, "delay", 1, false, rich),
			})
			var auto_queue_suffix: String = _build_auto_queue_suffix(effect)
			if auto_queue_suffix != "":
				auto_queue_text += " (%s)" % auto_queue_suffix
			return auto_queue_text
		"timeline_flow":
			return Localization.get_textf("effect.timeline_flow", "{mode} {target} timeline for {duration}s", {
				"mode": _timeline_mode_label(String(effect.get("mode", "stop"))),
				"target": _timeline_target_label(String(effect.get("target_side", "enemy"))),
				"duration": _format_compared_float(effect, comparison_effect, "duration", 1, true, rich),
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


static func _get_comparison_effect(comparison_card_def: CardDef, effect_index: int, effect: Dictionary) -> Dictionary:
	if comparison_card_def == null:
		return {}
	if effect_index < 0 or effect_index >= comparison_card_def.effects.size():
		return {}
	var candidate: Dictionary = Dictionary(comparison_card_def.effects[effect_index])
	if String(candidate.get("type", "")) != String(effect.get("type", "")):
		return {}
	return candidate


static func _format_compared_int(effect: Dictionary, comparison_effect: Dictionary, key: String, higher_is_beneficial: bool, rich: bool, default_value: int = 0) -> String:
	var current_value: int = int(effect.get(key, default_value))
	if not comparison_effect.has(key):
		return "%d" % current_value
	var base_value: int = int(comparison_effect.get(key, default_value))
	return _format_compared_number(float(current_value), float(base_value), 0, higher_is_beneficial, rich, false)


static func _format_compared_signed_int(effect: Dictionary, comparison_effect: Dictionary, key: String, higher_is_beneficial: bool, rich: bool, default_value: int = 0) -> String:
	var current_value: int = int(effect.get(key, default_value))
	if not comparison_effect.has(key):
		return _format_signed_value(current_value)
	var base_value: int = int(comparison_effect.get(key, default_value))
	return _format_compared_number(float(current_value), float(base_value), 0, higher_is_beneficial, rich, true)


static func _format_compared_float(effect: Dictionary, comparison_effect: Dictionary, key: String, decimals: int, higher_is_beneficial: bool, rich: bool, default_value: float = 0.0) -> String:
	var current_value: float = float(effect.get(key, default_value))
	if not comparison_effect.has(key):
		return _format_float_value(current_value, decimals, false)
	var base_value: float = float(comparison_effect.get(key, default_value))
	return _format_compared_number(current_value, base_value, decimals, higher_is_beneficial, rich, false)


static func _format_compared_signed_float(effect: Dictionary, comparison_effect: Dictionary, key: String, decimals: int, higher_is_beneficial: bool, rich: bool, default_value: float = 0.0) -> String:
	var current_value: float = float(effect.get(key, default_value))
	if not comparison_effect.has(key):
		return _format_float_value(current_value, decimals, true)
	var base_value: float = float(comparison_effect.get(key, default_value))
	return _format_compared_number(current_value, base_value, decimals, higher_is_beneficial, rich, true)


static func _format_compared_number(current_value: float, base_value: float, decimals: int, higher_is_beneficial: bool, rich: bool, force_sign_current: bool) -> String:
	var current_text: String = _format_float_value(current_value, decimals, force_sign_current)
	var delta: float = current_value - base_value
	if absf(delta) < 0.001:
		return current_text

	var delta_text: String = _format_float_value(delta, decimals, true)
	var compared_text: String = "%s (%s)" % [current_text, delta_text]
	if not rich:
		return compared_text

	var is_beneficial: bool = delta > 0.0 if higher_is_beneficial else delta < 0.0
	var color: String = BUFF_COLOR if is_beneficial else NERF_COLOR
	return "[color=%s]%s[/color]" % [color, compared_text]


static func _format_float_value(value: float, decimals: int, force_sign: bool) -> String:
	if decimals <= 0:
		var int_value: int = int(roundf(value))
		if force_sign:
			return _format_signed_value(int_value)
		return "%d" % int_value
	var pattern: String = "%." + str(decimals) + "f"
	var value_text: String = pattern % value
	if force_sign and value >= 0.0:
		return "+%s" % value_text
	return value_text


static func _is_higher_beneficial_for_modifier_stat(stat: String) -> bool:
	match stat:
		"cast_time", "recast_time":
			return false
		_:
			return true


static func _build_auto_queue_suffix(effect: Dictionary) -> String:
	var suffix_parts: Array[String] = []
	var unlimited_depth: bool = bool(effect.get("unlimited", false)) or int(effect.get("max_depth", 1)) < 0
	if unlimited_depth:
		suffix_parts.append(Localization.get_text("effect.auto_queue_depth.unlimited", "unlimited chain"))
	var missing_hp_ratio_per_extra: float = float(effect.get("missing_hp_ratio_per_extra", 0.0))
	if missing_hp_ratio_per_extra > 0.0:
		var max_count_text: String = "--"
		var max_count: int = int(effect.get("max_count", 0))
		if max_count > 0:
			max_count_text = "%d" % max_count
		suffix_parts.append(Localization.get_textf(
			"effect.auto_queue_scaling.missing_hp",
			"+1 per {ratio}% missing HP, max {max}",
			{
				"ratio": int(round(missing_hp_ratio_per_extra * 100.0)),
				"max": max_count_text,
			}
		))
	if suffix_parts.is_empty():
		return ""
	return ", ".join(suffix_parts)


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


static func _empower_scope_label(effect: Dictionary) -> String:
	match String(effect.get("scope", "self")):
		"all_own":
			return Localization.get_text("effect.scope.empower_all_own", "all own cards")
		"other_own":
			return Localization.get_text("effect.scope.empower_other_own", "other own cards")
		"card_id":
			return _card_name_or_id(String(effect.get("card_id", "")))
		_:
			return Localization.get_text("effect.scope.empower_self", "this card")


static func _auto_queue_card_label(effect: Dictionary) -> String:
	var card_id: String = String(effect.get("card_id", "self"))
	if card_id == "" or card_id == "self":
		return Localization.get_text("effect.card.self", "this card")
	return _card_name_or_id(card_id)


static func _card_name_or_id(card_id: String) -> String:
	var card_def: CardDef = Database.get_card(card_id)
	if card_def != null:
		return card_def.name
	return card_id


static func _timeline_mode_label(mode: String) -> String:
	match mode:
		"reverse":
			return Localization.get_text("effect.timeline_mode.reverse", "Reverse")
		_:
			return Localization.get_text("effect.timeline_mode.stop", "Stop")


static func _timeline_target_label(target_side: String) -> String:
	match target_side:
		"self", "own":
			return Localization.get_text("effect.timeline_target.self", "own")
		"all":
			return Localization.get_text("effect.timeline_target.all", "all")
		"player":
			return Localization.get_text("effect.timeline_target.player", "player")
		_:
			return Localization.get_text("effect.timeline_target.enemy", "enemy")


static func _modifier_stat_label(stat: String) -> String:
	match stat:
		"damage":
			return Localization.get_text("effect.stat.damage", "damage")
		"shield":
			return Localization.get_text("effect.stat.shield", "shield")
		"heal":
			return Localization.get_text("effect.stat.heal", "heal")
		"cast_time":
			return Localization.get_text("effect.stat.cast_time", "cast time")
		"recast_time":
			return Localization.get_text("effect.stat.recast_time", "recast")
		"duration":
			return Localization.get_text("effect.stat.duration", "duration")
		"delay":
			return Localization.get_text("effect.stat.delay", "delay")
		"haste":
			return Localization.get_text("effect.stat.haste", "haste")
		"cooldown":
			return Localization.get_text("effect.stat.cooldown", "cooldown")
		"attack_mod":
			return Localization.get_text("effect.stat.attack_mod", "attack modifier")
		"defense_mod":
			return Localization.get_text("effect.stat.defense_mod", "defense modifier")
		"speed_mod":
			return Localization.get_text("effect.stat.speed_mod", "speed modifier")
		"timeline_duration":
			return Localization.get_text("effect.stat.timeline_duration", "timeline duration")
		_:
			return stat


static func _format_signed_value(amount: int) -> String:
	if amount >= 0:
		return "+%d" % amount
	return "%d" % amount


static func _format_signed_float(amount: float) -> String:
	if absf(amount - roundf(amount)) < 0.01:
		return _format_signed_value(int(roundf(amount)))
	if amount >= 0.0:
		return "+%.1f" % amount
	return "%.1f" % amount
