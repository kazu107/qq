extends RefCounted
class_name CardFaceSummaryResolver

const DELTA_EPSILON: float = 0.001


static func build_summaries(card_def: CardDef, comparison_card_def: CardDef = null) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	if card_def == null:
		return summaries

	var cleanse_count: int = 0
	var cleanse_first_index: int = -1
	for effect_index in range(card_def.effects.size()):
		var effect: Dictionary = Dictionary(card_def.effects[effect_index])
		var effect_type: String = String(effect.get("type", ""))
		if effect_type == "remove_status":
			cleanse_count += 1
			if cleanse_first_index < 0:
				cleanse_first_index = effect_index
			continue

		var comparison_effect: Dictionary = _get_comparison_effect(comparison_card_def, effect_index, effect_type)
		var summary: Dictionary = _build_summary(effect, comparison_effect, effect_index)
		if not summary.is_empty():
			summaries.append(summary)

	if cleanse_count > 0:
		summaries.append({
			"icon_id": "cleanse",
			"value_text": "x%d" % cleanse_count,
			"delta_text": "",
			"delta_state": "neutral",
			"priority": 96,
			"source_index": cleanse_first_index,
			"effect_type": "remove_status",
		})

	summaries.sort_custom(_compare_summaries)
	return summaries


static func _build_summary(effect: Dictionary, comparison_effect: Dictionary, source_index: int) -> Dictionary:
	var effect_type: String = String(effect.get("type", ""))
	match effect_type:
		"consume_shield":
			return _numeric_summary(effect, comparison_effect, "amount", "shield_spend", "", 0, -1.0, true, 130, source_index)
		"deal_damage":
			return _numeric_summary(effect, comparison_effect, "amount", "attack", "", 0, 1.0, true, 120, source_index)
		"gain_shield":
			return _numeric_summary(effect, comparison_effect, "amount", "shield", "", 0, 1.0, true, 116, source_index)
		"heal":
			return _numeric_summary(effect, comparison_effect, "amount", "hp", "", 0, 1.0, true, 112, source_index)
		"apply_status":
			var status_id: String = String(effect.get("status", ""))
			return _numeric_summary(effect, comparison_effect, "duration", "status:%s" % status_id, "s", 1, 1.0, true, 110, source_index)
		"delay_enemy_active_card":
			return _numeric_summary(effect, comparison_effect, "amount", "delay", "s", 1, 1.0, true, 108, source_index)
		"haste_own_active_card":
			return _numeric_summary(effect, comparison_effect, "amount", "haste", "s", 1, -1.0, false, 106, source_index)
		"reduce_recast":
			return _numeric_summary(effect, comparison_effect, "amount", "recast", "s", 1, -1.0, false, 104, source_index)
		"interrupt_card":
			var interrupt_value: String = "ALL" if String(effect.get("scope", "")) == "all_interruptible" else "1"
			return _plain_summary("interrupt", interrupt_value, 114, source_index, effect_type)
		"modify_attack":
			var attack_target: String = String(effect.get("target", "self"))
			return _numeric_summary(effect, comparison_effect, "amount", "attack", "", 0, 1.0, attack_target != "enemy", 102, source_index, true)
		"modify_speed":
			var speed_target: String = String(effect.get("target", "self"))
			return _numeric_summary(effect, comparison_effect, "amount", "speed", "", 0, 1.0, speed_target != "enemy", 100, source_index, true)
		"empower_card":
			var stat_id: String = String(effect.get("stat", "damage"))
			var empower_icon: String = _get_modifier_icon(stat_id)
			var suffix: String = "s" if stat_id in ["cast_time", "recast_time", "duration", "delay", "haste", "cooldown"] else ""
			var higher_is_beneficial: bool = stat_id not in ["cast_time", "recast_time"]
			return _numeric_summary(effect, comparison_effect, "amount", empower_icon, suffix, 1, 1.0, higher_is_beneficial, 98, source_index, true)
		"auto_queue_card":
			return _numeric_summary(effect, comparison_effect, "count", "auto_queue", "", 0, 1.0, true, 118, source_index, false, "x")
		"timeline_flow":
			var mode: String = String(effect.get("mode", "stop"))
			var icon_id: String = "timeline_reverse" if mode == "reverse" else "timeline_stop"
			var target_side: String = String(effect.get("target_side", "enemy"))
			var duration_is_beneficial: bool = target_side not in ["self", "own", "player"]
			return _numeric_summary(effect, comparison_effect, "duration", icon_id, "s", 1, 1.0, duration_is_beneficial, 125, source_index)
		_:
			return _plain_summary("effect", "", 20, source_index, effect_type)


static func _numeric_summary(
	effect: Dictionary,
	comparison_effect: Dictionary,
	value_key: String,
	icon_id: String,
	suffix: String,
	decimals: int,
	display_multiplier: float,
	higher_is_beneficial: bool,
	priority: int,
	source_index: int,
	force_sign: bool = false,
	prefix: String = ""
) -> Dictionary:
	var current_value: float = float(effect.get(value_key, 0.0)) * display_multiplier
	var value_text: String = "%s%s%s" % [prefix, _format_number(current_value, decimals, force_sign), suffix]
	var delta_text: String = ""
	var delta_state: String = "neutral"
	if comparison_effect.has(value_key):
		var base_value: float = float(comparison_effect.get(value_key, 0.0)) * display_multiplier
		var delta: float = current_value - base_value
		if absf(delta) >= DELTA_EPSILON:
			delta_text = _format_number(delta, decimals, true)
			var beneficial: bool = delta > 0.0 if higher_is_beneficial else delta < 0.0
			delta_state = "buff" if beneficial else "nerf"

	return {
		"icon_id": icon_id,
		"value_text": value_text,
		"delta_text": delta_text,
		"delta_state": delta_state,
		"priority": priority,
		"source_index": source_index,
		"effect_type": String(effect.get("type", "")),
	}


static func _plain_summary(icon_id: String, value_text: String, priority: int, source_index: int, effect_type: String) -> Dictionary:
	return {
		"icon_id": icon_id,
		"value_text": value_text,
		"delta_text": "",
		"delta_state": "neutral",
		"priority": priority,
		"source_index": source_index,
		"effect_type": effect_type,
	}


static func _get_comparison_effect(comparison_card_def: CardDef, effect_index: int, effect_type: String) -> Dictionary:
	if comparison_card_def == null or effect_index < 0 or effect_index >= comparison_card_def.effects.size():
		return {}
	var candidate: Dictionary = Dictionary(comparison_card_def.effects[effect_index])
	if String(candidate.get("type", "")) != effect_type:
		return {}
	return candidate


static func _get_modifier_icon(stat_id: String) -> String:
	match stat_id:
		"damage", "attack_mod":
			return "attack"
		"shield":
			return "shield"
		"heal":
			return "hp"
		"cast_time", "haste":
			return "haste"
		"recast_time", "cooldown":
			return "recast"
		"delay":
			return "delay"
		"speed_mod":
			return "speed"
		"duration":
			return "status"
		_:
			return "empower"


static func _format_number(value: float, decimals: int, force_sign: bool) -> String:
	var value_text: String
	if decimals <= 0 or is_equal_approx(value, roundf(value)):
		value_text = "%d" % int(roundf(value))
	else:
		var pattern: String = "%." + str(decimals) + "f"
		value_text = pattern % value
	if force_sign and value > 0.0:
		return "+%s" % value_text
	return value_text


static func _compare_summaries(left: Dictionary, right: Dictionary) -> bool:
	var left_priority: int = int(left.get("priority", 0))
	var right_priority: int = int(right.get("priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	return int(left.get("source_index", 0)) < int(right.get("source_index", 0))
