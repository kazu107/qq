extends Node

signal language_changed(language_code: String)

const DEFAULT_LANGUAGE := "en"
const LANGUAGE_PATHS := {
	"ja": "res://data/localization/ja.json",
}
const LANGUAGE_LABELS := {
	"en": "English",
	"ja": "日本語",
}

var _current_language: String = DEFAULT_LANGUAGE
var _translations_by_language: Dictionary = {}


func _ready() -> void:
	_load_all_translations()


func normalize_language_code(language_code: String) -> String:
	if language_code == DEFAULT_LANGUAGE:
		return DEFAULT_LANGUAGE
	if LANGUAGE_PATHS.has(language_code):
		return language_code
	return DEFAULT_LANGUAGE


func get_language() -> String:
	return _current_language


func get_supported_languages() -> Array[Dictionary]:
	var languages: Array[Dictionary] = []
	languages.append({
		"code": DEFAULT_LANGUAGE,
		"label": String(LANGUAGE_LABELS.get(DEFAULT_LANGUAGE, DEFAULT_LANGUAGE)),
	})
	for language_code in LANGUAGE_PATHS.keys():
		languages.append({
			"code": String(language_code),
			"label": String(LANGUAGE_LABELS.get(language_code, language_code)),
		})
	return languages


func set_language(language_code: String, emit_signal: bool = true) -> bool:
	var normalized_code: String = normalize_language_code(language_code)
	var changed: bool = normalized_code != _current_language
	_current_language = normalized_code
	if changed and emit_signal:
		language_changed.emit(_current_language)
	return changed


func get_text(key: String, fallback: String = "") -> String:
	if _current_language != DEFAULT_LANGUAGE:
		var language_table: Dictionary = Dictionary(_translations_by_language.get(_current_language, {}))
		if language_table.has(key):
			return String(language_table.get(key, fallback))
	if fallback != "":
		return fallback
	return key


func get_textf(key: String, fallback: String, values: Dictionary) -> String:
	return format_text(get_text(key, fallback), values)


func format_text(text: String, values: Dictionary) -> String:
	var result: String = text
	for raw_key in values.keys():
		var key: String = String(raw_key)
		result = result.replace("{%s}" % key, str(values[raw_key]))
	return result


func get_rarity_name(rarity: String) -> String:
	return get_text("rarity.%s" % rarity, rarity.capitalize())


func get_target_name(target_id: String) -> String:
	match target_id:
		"enemy":
			return get_text("target.enemy", "Enemy")
		_:
			return get_text("target.self", "Self")


func get_owner_name(owner_side: String) -> String:
	match owner_side:
		"enemy":
			return get_text("owner.enemy", "Enemy")
		_:
			return get_text("owner.player", "Player")


func get_status_name(status_id: String) -> String:
	return get_text("status.%s" % status_id, status_id.capitalize())


func get_node_status_name(status_id: String) -> String:
	return get_text("map.status.%s" % status_id, status_id.capitalize())


func get_node_type_name(node_type: String) -> String:
	return get_text("map.type.%s" % node_type, node_type.capitalize())


func get_reward_name(reward_key: String) -> String:
	return get_text("reward.key.%s" % reward_key, reward_key.capitalize())


func get_winner_name(winner: String) -> String:
	return get_text("winner.%s" % winner, winner.capitalize())


func get_grade_label(tier: int) -> String:
	if tier <= 0:
		return get_text("card.grade.base", "Base")
	return "+%d" % tier


func get_tags_text(tags: Array[String]) -> String:
	if tags.is_empty():
		return get_text("card.tags.none", "None")
	var localized_tags: Array[String] = []
	for tag in tags:
		localized_tags.append(get_text("tag.%s" % tag, tag.capitalize()))
	return ", ".join(localized_tags)


func get_step_label(step_data: Dictionary) -> String:
	var label_key: String = String(step_data.get("label_key", ""))
	var fallback: String = String(step_data.get("label", ""))
	var values: Dictionary = Dictionary(step_data.get("label_args", {})).duplicate(true)
	if label_key == "":
		return fallback
	return get_textf(label_key, fallback, values)


func get_node_label(node_data: Dictionary) -> String:
	var label_key: String = String(node_data.get("label_key", ""))
	var fallback: String = String(node_data.get("label", ""))
	var values: Dictionary = Dictionary(node_data.get("label_args", {})).duplicate(true)
	if node_data.has("enemy_id") and not values.has("enemy_name"):
		var enemy_def: EnemyDef = Database.get_enemy(String(node_data.get("enemy_id", "")))
		if enemy_def != null:
			values["enemy_name"] = enemy_def.name
	if label_key == "":
		return fallback
	return get_textf(label_key, fallback, values)


func get_starter_name(starter_id: String) -> String:
	var starter_data: Dictionary = Database.get_starter(starter_id)
	if starter_data.is_empty():
		return starter_id
	return String(starter_data.get("name", starter_id))


func get_enemy_name(enemy_id: String, fallback: String = "") -> String:
	var enemy_def: EnemyDef = Database.get_enemy(enemy_id)
	if enemy_def != null:
		return enemy_def.name
	if fallback != "":
		return fallback
	return enemy_id


func get_relic_gained_text(relic_name: String) -> String:
	return get_textf("game.relic_gained", "Relic gained: {relic_name}", {
		"relic_name": relic_name,
	})


func _load_all_translations() -> void:
	_translations_by_language.clear()
	for raw_language_code in LANGUAGE_PATHS.keys():
		var language_code: String = String(raw_language_code)
		_translations_by_language[language_code] = _load_translation_file(String(LANGUAGE_PATHS[language_code]))


func _load_translation_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Localization parse error: %s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("Localization file must contain a JSON object: %s" % path)
		return {}
	return Dictionary(json.data)
