extends Node


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("Relic names: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _all_kanji(text: String) -> bool:
	if text.length() < 4:
		return false
	for index: int in text.length():
		var code: int = text.unicode_at(index)
		if not ((code >= 0x3400 and code <= 0x9fff) or code in [0x3005, 0x3007]):
			return false
	return true


func _run() -> void:
	Localization.set_language("ja")
	Database.load_all()
	var baseline: Array = JSON.parse_string(FileAccess.get_file_as_string(Database.RELICS_PATH))
	_check(Database.get_all_relic_ids().size() == baseline.size(), "Relic IDs changed")
	var names: Dictionary = {}
	for definition: Dictionary in baseline:
		var id: String = String(definition["id"])
		var relic: RelicDef = Database.get_relic(id)
		_check(relic != null and not relic.name.is_empty(), "Missing localized relic " + id)
		_check(not _all_kanji(relic.name), "Long all-kanji name remains: " + id + " / " + relic.name)
		_check(not names.has(relic.name), "Ambiguous duplicate name: " + relic.name)
		names[relic.name] = id
		_check(relic.name == Localization.get_text("relic.%s.name" % id), "Japanese name did not propagate to Database")
		var icon: RelicIcon = RelicIcon.new()
		icon.bind(relic)
		_check(icon.relic_id == id and icon.tooltip_text.contains(relic.name), "Icon tooltip retained a stale name: " + id)
		icon.free()
	for id: String in ["borrowed_second_hand", "reactive_barrier", "balanced_three_phase_unit"]:
		print("RELIC_NAME ", id, " -> ", Database.get_relic(id).name)
	Localization.set_language("en")
	Database.load_all()
	for definition: Dictionary in baseline:
		var relic: RelicDef = Database.get_relic(String(definition["id"]))
		_check(relic.name == String(definition["name"]) and relic.description == String(definition["description"]), "English definition changed")
	print("RELIC_NAMES_SMOKE_OK ", baseline.size(), " unique/readable Japanese names, stable IDs, live icon tooltips, English unchanged")
	get_tree().quit()
