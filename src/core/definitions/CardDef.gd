extends RefCounted
class_name CardDef

var id: String = ""
var name: String = ""
var description: String = ""
var rarity: String = "common"
var tags: Array[String] = []
var loadout_cost: int = 0
var recast_time: float = 0.0
var cast_time: float = 0.0
var active_slot_cost: int = 1
var priority_modifier: float = 0.0
var interruptible: bool = false
var target_type: String = "enemy"
var effects: Array[Dictionary] = []
var upgrade_profile: Dictionary = {}


static func from_dict(data: Dictionary) -> CardDef:
	var card_def := CardDef.new()
	card_def.id = String(data.get("id", ""))
	card_def.name = String(data.get("name", card_def.id))
	card_def.description = String(data.get("description", ""))
	card_def.rarity = String(data.get("rarity", "common"))
	card_def.tags = _to_string_array(data.get("tags", []))
	card_def.loadout_cost = int(data.get("loadout_cost", 0))
	card_def.recast_time = float(data.get("recast_time", 0.0))
	card_def.cast_time = float(data.get("cast_time", 0.0))
	card_def.active_slot_cost = int(data.get("active_slot_cost", 1))
	card_def.priority_modifier = float(data.get("priority_modifier", 0.0))
	card_def.interruptible = bool(data.get("interruptible", false))
	card_def.target_type = String(data.get("target_type", "enemy"))
	card_def.effects = _to_dictionary_array(data.get("effects", []))
	card_def.upgrade_profile = Dictionary(data.get("upgrade_profile", {}))
	return card_def


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"rarity": rarity,
		"tags": tags.duplicate(),
		"loadout_cost": loadout_cost,
		"recast_time": recast_time,
		"cast_time": cast_time,
		"active_slot_cost": active_slot_cost,
		"priority_modifier": priority_modifier,
		"interruptible": interruptible,
		"target_type": target_type,
		"effects": effects.duplicate(true),
		"upgrade_profile": upgrade_profile.duplicate(true),
	}


static func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(String(item))
	return result


static func _to_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in value:
		result.append(Dictionary(item).duplicate(true))
	return result
