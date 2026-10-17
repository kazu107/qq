extends Node


func _ready() -> void:
	RankedSession.verifying = true
	Database.load_all()
	Game.settings["replay_auto_export"] = false
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1:
		get_tree().quit(2)
		return
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if source is not Dictionary or String(source.get("ticket", {}).get("ruleset", "")) != RankedSession.RULESET:
		print("QQ_RANKED_RESULT ", JSON.stringify({"error": "ruleset_mismatch"}))
		get_tree().quit(2)
		return
	var result: Dictionary = RankedSession.replay(Dictionary(source["ticket"]), Array(source.get("commands", [])))
	print("QQ_RANKED_RESULT ", JSON.stringify(result))
	get_tree().quit(0)
