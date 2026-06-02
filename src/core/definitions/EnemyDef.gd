extends RefCounted
class_name EnemyDef

var id: String = ""
var name: String = ""
var max_hp: int = 1
var attack: int = 0
var defense: int = 0
var speed: int = 0
var cards: Array[String] = []
var role: String = ""
var passive: Dictionary = {}


static func from_dict(data: Dictionary) -> EnemyDef:
	var enemy_def := EnemyDef.new()
	enemy_def.id = String(data.get("id", ""))
	enemy_def.name = String(data.get("name", enemy_def.id))
	enemy_def.max_hp = int(data.get("max_hp", 1))
	enemy_def.attack = int(data.get("attack", 0))
	enemy_def.defense = int(data.get("defense", 0))
	enemy_def.speed = int(data.get("speed", 0))
	enemy_def.cards = _to_string_array(data.get("cards", []))
	enemy_def.role = String(data.get("role", ""))
	enemy_def.passive = Dictionary(data.get("passive", {}))
	return enemy_def


static func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(String(item))
	return result
