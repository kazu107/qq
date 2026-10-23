extends Node


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	RankedSession.verifying = false
	var id: String = "11111111-1111-4111-8111-111111111111"
	var ticket: Dictionary = {"id": id, "user_id": "22222222-2222-4222-8222-222222222222", "seed": 1234, "starter_id": "balanced", "ruleset": RankedSession.RULESET}
	RankedSession.initialize(ticket)
	RankedSession.finish()
	assert(Dictionary(Game.settings.get("ranked_outbox", {})).has(id))
	Game.start_new_run("balanced", 777)
	assert(Dictionary(Game.settings.get("ranked_outbox", {})).has(id), "Starting an ordinary run must preserve pending submissions")
	var saved: SaveData = SaveData.from_dict(JSON.parse_string(JSON.stringify(Game.build_save_data("map").to_dict())))
	Game.apply_loaded_save(saved)
	assert(Dictionary(Game.settings.get("ranked_outbox", {})).has(id))
	Game.reset_settings_to_defaults()
	assert(Dictionary(Game.settings.get("ranked_outbox", {})).has(id), "Audio/display reset must not discard pending scores")
	print("RANKED_OUTBOX_SMOKE_OK retained across a new run, serialization, reload and settings reset")
	get_tree().quit()
