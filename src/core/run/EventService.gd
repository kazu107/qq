extends RefCounted
class_name EventService

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _reward_resolver: RewardResolver = RewardResolver.new()


func _init() -> void:
	_rng.randomize()


func build_event_node(
	area: int,
	run_state: RunState,
	used_event_ids: Array[String],
	allowed_card_ids: Array[String],
	allowed_relic_ids: Array[String]
) -> Dictionary:
	var template: Dictionary = _pick_template(area, used_event_ids)
	if template.is_empty():
		return {}
	return _resolve_template(template, area, run_state, allowed_card_ids, allowed_relic_ids)


func build_specific_event_node(
	event_id: String,
	area: int,
	run_state: RunState,
	allowed_card_ids: Array[String],
	allowed_relic_ids: Array[String]
) -> Dictionary:
	var template: Dictionary = Database.get_event(event_id)
	if template.is_empty():
		return {}
	return _resolve_template(template, max(1, area), run_state, allowed_card_ids, allowed_relic_ids)


func get_event_title(event_id: String) -> String:
	var template: Dictionary = Database.get_event(event_id)
	return String(template.get("title", event_id))


func _pick_template(area: int, used_event_ids: Array[String]) -> Dictionary:
	var weighted_ids: Array[String] = []
	for event_id in Database.get_all_event_ids():
		if used_event_ids.has(event_id):
			continue
		var template: Dictionary = Database.get_event(event_id)
		if not _supports_area(template, area):
			continue
		var weight: int = max(1, int(template.get("weight", 1)))
		for _repeat_index in range(weight):
			weighted_ids.append(event_id)

	if weighted_ids.is_empty():
		for event_id in Database.get_all_event_ids():
			var template: Dictionary = Database.get_event(event_id)
			if not _supports_area(template, area):
				continue
			var weight: int = max(1, int(template.get("weight", 1)))
			for _repeat_index in range(weight):
				weighted_ids.append(event_id)

	if weighted_ids.is_empty():
		return {}

	var picked_id: String = weighted_ids[_rng.randi_range(0, weighted_ids.size() - 1)]
	return Database.get_event(picked_id)


func _resolve_template(
	template: Dictionary,
	area: int,
	run_state: RunState,
	allowed_card_ids: Array[String],
	allowed_relic_ids: Array[String]
) -> Dictionary:
	var base_context: Dictionary = {
		"area": area,
	}
	if run_state != null:
		base_context["gold"] = run_state.gold
		base_context["hp"] = run_state.player_hp

	var resolved_choices: Array[Dictionary] = []
	var raw_choices: Array = Array(template.get("choices", []))
	for raw_choice in raw_choices:
		var choice_data: Dictionary = Dictionary(raw_choice)
		var choice_context: Dictionary = base_context.duplicate(true)
		var values: Dictionary = Dictionary(choice_data.get("values", {}))
		for value_key in values.keys():
			choice_context[String(value_key)] = _resolve_scalar(values[value_key], area, choice_context)

		var resolution: Dictionary = _resolve_choice_effects(
			choice_data,
			area,
			run_state,
			allowed_card_ids,
			allowed_relic_ids,
			choice_context
		)
		var resolved_choice: Dictionary = {
			"id": String(choice_data.get("id", "")),
			"label": _format_text(String(choice_data.get("label", "")), choice_context),
			"description": _format_text(String(choice_data.get("description", "")), choice_context),
			"result": _format_text(String(choice_data.get("result", "")), choice_context),
			"effects": Array(resolution.get("effects", [])).duplicate(true),
			"enabled": bool(resolution.get("enabled", true)),
			"disabled_reason": String(resolution.get("disabled_reason", "")),
		}
		resolved_choices.append(resolved_choice)

	return {
		"event_id": String(template.get("id", "")),
		"event_title": _format_text(String(template.get("title", Localization.get_text("event.default_title", "Event"))), base_context),
		"event_description": _format_text(String(template.get("description", "")), base_context),
		"event_choices": resolved_choices,
	}


func _resolve_choice_effects(
	choice_data: Dictionary,
	area: int,
	run_state: RunState,
	allowed_card_ids: Array[String],
	allowed_relic_ids: Array[String],
	context: Dictionary
) -> Dictionary:
	var resolved_effects: Array[Dictionary] = []
	var enabled: bool = true
	var disabled_reason: String = ""
	var raw_effects: Array = Array(choice_data.get("effects", []))
	for raw_effect in raw_effects:
		var effect_data: Dictionary = Dictionary(raw_effect).duplicate(true)
		var effect_type: String = String(effect_data.get("type", ""))
		match effect_type:
			"grant_gold", "lose_gold", "heal", "lose_hp", "modify_attack", "modify_speed", "modify_max_hp", "modify_loadout_limit":
				effect_data["amount"] = _resolve_scalar(effect_data.get("amount", 0), area, context)
				if effect_type == "lose_gold" and run_state != null:
					var gold_cost: int = int(effect_data.get("amount", 0))
					if run_state.gold < gold_cost:
						enabled = false
						disabled_reason = Localization.get_text("event.disabled.not_enough_gold", "Not enough gold.")
			"grant_random_card":
				var rarity_pool: Array[String] = _resolve_string_array(effect_data.get("rarity_pool", []))
				var card_ids: Array[String] = _reward_resolver.roll_card_rewards(
					1,
					rarity_pool,
					_resolve_owned_cards(run_state),
					allowed_card_ids,
					bool(effect_data.get("guarantee_new", true))
				)
				var card_id: String = ""
				if not card_ids.is_empty():
					card_id = card_ids[0]
				effect_data["card_id"] = card_id
				if card_id == "":
					enabled = false
					disabled_reason = Localization.get_text("event.disabled.no_card", "No eligible card is available.")
				else:
					var card_def: CardDef = Database.get_card(card_id)
					context[String(effect_data.get("card_name_key", "card_name"))] = card_def.name if card_def != null else card_id
			"grant_random_relic":
				var excluded_ids: Array[String] = _resolve_owned_relics(run_state)
				var relic_id: String = RelicService.new().roll_random_relic(excluded_ids, allowed_relic_ids)
				effect_data["relic_id"] = relic_id
				if relic_id == "":
					enabled = false
					disabled_reason = Localization.get_text("event.disabled.no_relic", "No eligible relic is available.")
				else:
					var relic_def: RelicDef = Database.get_relic(relic_id)
					context[String(effect_data.get("relic_name_key", "relic_name"))] = relic_def.name if relic_def != null else relic_id
			"upgrade_random_card":
				var upgrade_target: Dictionary = _resolve_upgrade_target(run_state, String(effect_data.get("scope", "equipped")))
				effect_data["card_id"] = String(upgrade_target.get("card_id", ""))
				effect_data["next_tier"] = int(upgrade_target.get("next_tier", 0))
				if String(effect_data.get("card_id", "")) == "":
					enabled = false
					disabled_reason = Localization.get_text("event.disabled.no_upgrade", "No upgradable card is available.")
				else:
					context[String(effect_data.get("card_name_key", "card_name"))] = String(upgrade_target.get("card_name", ""))
					context[String(effect_data.get("grade_key", "next_grade"))] = String(upgrade_target.get("grade_label", ""))
			_:
				pass
		resolved_effects.append(effect_data)

	return {
		"effects": resolved_effects,
		"enabled": enabled,
		"disabled_reason": disabled_reason,
	}


func _resolve_upgrade_target(run_state: RunState, scope: String) -> Dictionary:
	if run_state == null:
		return {}

	var candidates: Array[String] = []
	match scope:
		"owned":
			candidates = _unique_card_ids(run_state.player_cards)
		_:
			candidates = _unique_card_ids(run_state.equipped_cards)

	var valid_candidates: Array[String] = []
	for card_id in candidates:
		if CardUpgradeResolver.get_tier(run_state, card_id) >= CardUpgradeResolver.MAX_TIER:
			continue
		valid_candidates.append(card_id)

	if valid_candidates.is_empty():
		return {}

	var picked_id: String = valid_candidates[_rng.randi_range(0, valid_candidates.size() - 1)]
	var next_tier: int = CardUpgradeResolver.get_tier(run_state, picked_id) + 1
	var card_def: CardDef = CardUpgradeResolver.build_effective_card(picked_id, run_state)
	return {
		"card_id": picked_id,
		"card_name": card_def.name if card_def != null else picked_id,
		"next_tier": next_tier,
		"grade_label": CardInfoFormatter.format_grade_label(next_tier),
	}


func _resolve_owned_cards(run_state: RunState) -> Array[String]:
	if run_state == null:
		return []
	return run_state.player_cards.duplicate()


func _resolve_owned_relics(run_state: RunState) -> Array[String]:
	if run_state == null:
		return []
	return run_state.relics.duplicate()


func _unique_card_ids(card_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	for card_id in card_ids:
		if seen.has(card_id):
			continue
		seen[card_id] = true
		result.append(card_id)
	return result


func _supports_area(template: Dictionary, area: int) -> bool:
	var areas: Array = Array(template.get("areas", []))
	if areas.is_empty():
		return true
	for raw_area in areas:
		if int(raw_area) == area:
			return true
	return false


func _resolve_scalar(value: Variant, area: int, context: Dictionary) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return value

	var value_data: Dictionary = Dictionary(value)
	if value_data.has("ref"):
		return context.get(String(value_data.get("ref", "")), 0)
	if value_data.has("by_area"):
		var by_area: Dictionary = Dictionary(value_data.get("by_area", {}))
		var area_key: String = str(area)
		if by_area.has(area_key):
			return by_area[area_key]
		if by_area.has("default"):
			return by_area["default"]

	var base_value: Variant = value_data.get("base", 0)
	var per_area_value: Variant = value_data.get("per_area", 0)
	var resolved: float = float(base_value) + float(per_area_value) * max(0, area - 1)
	var keep_float: bool = bool(value_data.get("as_float", false)) or typeof(base_value) == TYPE_FLOAT or typeof(per_area_value) == TYPE_FLOAT
	if keep_float:
		return resolved
	return int(round(resolved))


func _resolve_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(String(item))
	return result


func _format_text(text: String, context: Dictionary) -> String:
	var result: String = text
	for raw_key in context.keys():
		var key: String = String(raw_key)
		result = result.replace("{%s}" % key, str(context[key]))
	return result
