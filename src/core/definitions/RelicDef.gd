extends RefCounted
class_name RelicDef

var id: String = ""
var name: String = ""
var description: String = ""


static func from_dict(data: Dictionary) -> RelicDef:
	var relic_def := RelicDef.new()
	relic_def.id = String(data.get("id", ""))
	relic_def.name = String(data.get("name", relic_def.id))
	relic_def.description = String(data.get("description", ""))
	return relic_def
