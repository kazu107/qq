extends RefCounted
class_name RelicDef

var id: String = ""
var name: String = ""
var description: String = ""
var rarity: String = "common"
var tags: Array[String] = []
var effects: Array[Dictionary] = []
var mode_scope: Array[String] = ["run", "hazard", "arena", "infinite"]


static func from_dict(data: Dictionary) -> RelicDef:
	var relic_def := RelicDef.new()
	relic_def.id = String(data.get("id", ""))
	relic_def.name = String(data.get("name", relic_def.id))
	relic_def.description = String(data.get("description", ""))
	relic_def.rarity = String(data.get("rarity", "common"))
	if relic_def.rarity.is_empty():
		relic_def.rarity = "common"
	relic_def.tags = _to_string_array(data.get("tags", []))
	relic_def.effects = _to_dictionary_array(data.get("effects", []))
	relic_def.mode_scope = _to_string_array(data.get("mode_scope", ["run", "hazard", "arena", "infinite"]))
	if relic_def.mode_scope.is_empty():
		relic_def.mode_scope = ["run", "hazard", "arena", "infinite"]
	return relic_def


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"rarity": rarity,
		"tags": tags.duplicate(),
		"effects": effects.duplicate(true),
		"mode_scope": mode_scope.duplicate(),
	}


static func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value:
		result.append(String(item))
	return result


static func _to_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for item: Variant in value:
		if item is Dictionary:
			result.append(Dictionary(item).duplicate(true))
	return result
