extends Node

const CARDS_PATH := "res://data/cards.json"
const ENEMIES_PATH := "res://data/enemies.json"
const STARTERS_PATH := "res://data/starters.json"
const REWARDS_PATH := "res://data/rewards.json"
const META_PROGRESS_PATH := "res://data/meta_progress.json"
const RELICS_PATH := "res://data/relics.json"
const EVENTS_PATH := "res://data/events.json"
const ACHIEVEMENTS_PATH := "res://data/achievements.json"

var cards: Dictionary = {}
var enemies: Dictionary = {}
var starters: Array[Dictionary] = []
var rewards: Dictionary = {}
var meta_progress_template: Dictionary = {}
var relics: Dictionary = {}
var events: Dictionary = {}
var event_order: Array[String] = []
var achievements: Dictionary = {}
var achievement_order: Array[String] = []
var load_errors: Array[String] = []


func load_all() -> void:
	cards.clear()
	enemies.clear()
	starters.clear()
	rewards.clear()
	meta_progress_template.clear()
	relics.clear()
	events.clear()
	event_order.clear()
	achievements.clear()
	achievement_order.clear()
	load_errors.clear()

	_load_cards()
	_load_enemies()
	starters = _load_json_dictionary_array(STARTERS_PATH)
	rewards = _load_json_dictionary(REWARDS_PATH)
	meta_progress_template = _load_json_dictionary(META_PROGRESS_PATH)
	_load_relics()
	_load_events()
	_load_achievements()
	_apply_localization()

	if load_errors.is_empty():
		print("Database loaded: %d cards / %d enemies / %d starters / %d relics / %d events / %d achievements" % [
			cards.size(),
			enemies.size(),
			starters.size(),
			relics.size(),
			event_order.size(),
			achievement_order.size(),
		])
	else:
		for error_text in load_errors:
			push_error(error_text)


func get_card(card_id: String) -> CardDef:
	return cards.get(card_id) as CardDef


func get_enemy(enemy_id: String) -> EnemyDef:
	return enemies.get(enemy_id) as EnemyDef


func get_starter(starter_id: String) -> Dictionary:
	for starter in starters:
		if String(starter.get("id", "")) == starter_id:
			return starter
	return {}


func get_card_ids_by_rarity(rarity: String) -> Array[String]:
	var ids: Array[String] = []
	for card_id in cards.keys():
		var card_def: CardDef = cards[card_id] as CardDef
		if card_def != null and card_def.rarity == rarity:
			ids.append(card_def.id)
	return ids


func get_all_card_ids() -> Array[String]:
	var ids: Array[String] = []
	for card_id in cards.keys():
		ids.append(String(card_id))
	return ids


func get_relic(relic_id: String) -> RelicDef:
	return relics.get(relic_id) as RelicDef


func get_all_relic_ids() -> Array[String]:
	var ids: Array[String] = []
	for relic_id in relics.keys():
		ids.append(String(relic_id))
	return ids


func get_event(event_id: String) -> Dictionary:
	if not events.has(event_id):
		return {}
	return Dictionary(events[event_id]).duplicate(true)


func get_all_event_ids() -> Array[String]:
	return event_order.duplicate()


func get_achievement(achievement_id: String) -> Dictionary:
	if not achievements.has(achievement_id):
		return {}
	return Dictionary(achievements[achievement_id]).duplicate(true)


func get_all_achievement_ids() -> Array[String]:
	return achievement_order.duplicate()


func _load_cards() -> void:
	for raw_card in _load_json_array(CARDS_PATH):
		var card_data: Dictionary = Dictionary(raw_card)
		if not _has_required_keys(card_data, CARDS_PATH, ["id", "name", "recast_time", "cast_time", "active_slot_cost", "effects"]):
			continue
		var card_def: CardDef = CardDef.from_dict(card_data)
		cards[card_def.id] = card_def


func _load_enemies() -> void:
	for raw_enemy in _load_json_array(ENEMIES_PATH):
		var enemy_data: Dictionary = Dictionary(raw_enemy)
		if not _has_required_keys(enemy_data, ENEMIES_PATH, ["id", "name", "max_hp", "attack", "speed", "cards"]):
			continue
		var enemy_def: EnemyDef = EnemyDef.from_dict(enemy_data)
		enemies[enemy_def.id] = enemy_def


func _load_relics() -> void:
	for raw_relic in _load_json_array(RELICS_PATH):
		var relic_data: Dictionary = Dictionary(raw_relic)
		if not _has_required_keys(relic_data, RELICS_PATH, ["id", "name", "description"]):
			continue
		var relic_def: RelicDef = RelicDef.from_dict(relic_data)
		relics[relic_def.id] = relic_def


func _load_events() -> void:
	for raw_event in _load_json_array(EVENTS_PATH):
		var event_data: Dictionary = Dictionary(raw_event)
		if not _has_required_keys(event_data, EVENTS_PATH, ["id", "title", "description", "choices"]):
			continue
		var event_id: String = String(event_data.get("id", ""))
		if event_id == "":
			_record_error("%s contains an event with an empty id" % EVENTS_PATH)
			continue
		events[event_id] = event_data.duplicate(true)
		event_order.append(event_id)


func _load_achievements() -> void:
	for raw_achievement in _load_json_array(ACHIEVEMENTS_PATH):
		var achievement_data: Dictionary = Dictionary(raw_achievement)
		if not _has_required_keys(achievement_data, ACHIEVEMENTS_PATH, ["id", "name", "description", "condition", "rewards"]):
			continue
		var achievement_id: String = String(achievement_data.get("id", ""))
		if achievement_id == "":
			_record_error("%s contains an achievement with an empty id" % ACHIEVEMENTS_PATH)
			continue
		achievements[achievement_id] = achievement_data.duplicate(true)
		achievement_order.append(achievement_id)


func _apply_localization() -> void:
	for raw_card_id in cards.keys():
		var card_id: String = String(raw_card_id)
		var card_def: CardDef = cards[card_id] as CardDef
		if card_def == null:
			continue
		card_def.name = Localization.get_text("card.%s.name" % card_id, card_def.name)
		card_def.description = Localization.get_text("card.%s.description" % card_id, card_def.description)

	for raw_enemy_id in enemies.keys():
		var enemy_id: String = String(raw_enemy_id)
		var enemy_def: EnemyDef = enemies[enemy_id] as EnemyDef
		if enemy_def == null:
			continue
		enemy_def.name = Localization.get_text("enemy.%s.name" % enemy_id, enemy_def.name)

	for starter_index in range(starters.size()):
		var starter_data: Dictionary = starters[starter_index].duplicate(true)
		var starter_id: String = String(starter_data.get("id", ""))
		if starter_id == "":
			continue
		starter_data["name"] = Localization.get_text("starter.%s.name" % starter_id, String(starter_data.get("name", starter_id)))
		starter_data["description"] = Localization.get_text("starter.%s.description" % starter_id, String(starter_data.get("description", "")))
		starters[starter_index] = starter_data

	for raw_relic_id in relics.keys():
		var relic_id: String = String(raw_relic_id)
		var relic_def: RelicDef = relics[relic_id] as RelicDef
		if relic_def == null:
			continue
		relic_def.name = Localization.get_text("relic.%s.name" % relic_id, relic_def.name)
		relic_def.description = Localization.get_text("relic.%s.description" % relic_id, relic_def.description)

	for event_index in range(event_order.size()):
		var event_id: String = event_order[event_index]
		var event_data: Dictionary = Dictionary(events.get(event_id, {})).duplicate(true)
		if event_data.is_empty():
			continue
		event_data["title"] = Localization.get_text("event.%s.title" % event_id, String(event_data.get("title", event_id)))
		event_data["description"] = Localization.get_text("event.%s.description" % event_id, String(event_data.get("description", "")))
		var choices: Array = Array(event_data.get("choices", []))
		for choice_index in range(choices.size()):
			var choice_data: Dictionary = Dictionary(choices[choice_index]).duplicate(true)
			var choice_id: String = String(choice_data.get("id", ""))
			if choice_id == "":
				continue
			choice_data["label"] = Localization.get_text(
				"event.%s.choice.%s.label" % [event_id, choice_id],
				String(choice_data.get("label", choice_id))
			)
			choice_data["description"] = Localization.get_text(
				"event.%s.choice.%s.description" % [event_id, choice_id],
				String(choice_data.get("description", ""))
			)
			choice_data["result"] = Localization.get_text(
				"event.%s.choice.%s.result" % [event_id, choice_id],
				String(choice_data.get("result", ""))
			)
			choices[choice_index] = choice_data
		event_data["choices"] = choices
		events[event_id] = event_data

	for achievement_index in range(achievement_order.size()):
		var achievement_id: String = achievement_order[achievement_index]
		var achievement_data: Dictionary = Dictionary(achievements.get(achievement_id, {})).duplicate(true)
		if achievement_data.is_empty():
			continue
		achievement_data["name"] = Localization.get_text("achievement.%s.name" % achievement_id, String(achievement_data.get("name", achievement_id)))
		achievement_data["description"] = Localization.get_text("achievement.%s.description" % achievement_id, String(achievement_data.get("description", "")))
		achievements[achievement_id] = achievement_data


func _load_json_array(path: String) -> Array:
	var data: Variant = _parse_json_file(path)
	if data == null:
		return []
	if typeof(data) != TYPE_ARRAY:
		_record_error("%s must contain a JSON array" % path)
		return []
	return data as Array


func _load_json_dictionary(path: String) -> Dictionary:
	var data: Variant = _parse_json_file(path)
	if data == null:
		return {}
	if typeof(data) != TYPE_DICTIONARY:
		_record_error("%s must contain a JSON object" % path)
		return {}
	return data as Dictionary


func _load_json_dictionary_array(path: String) -> Array[Dictionary]:
	var raw_array: Array = _load_json_array(path)
	var result: Array[Dictionary] = []
	for item in raw_array:
		result.append(Dictionary(item))
	return result


func _parse_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_record_error("Missing data file: %s" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Failed to open data file: %s" % path)
		return null

	var json_text := file.get_as_text()
	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		_record_error("%s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _has_required_keys(data: Dictionary, source_path: String, required_keys: Array[String]) -> bool:
	for key in required_keys:
		if not data.has(key):
			_record_error("%s missing key '%s'" % [source_path, key])
			return false
	return true


func _record_error(error_text: String) -> void:
	load_errors.append(error_text)
