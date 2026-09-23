extends Node

const WARMUP: GDScript = preload("res://src/core/services/StartupWarmupService.gd")
const SCENES: Array[Dictionary] = [
	{"id": "Hub", "path": "res://scenes/hub/Hub.tscn"},
	{"id": "RunSetup", "path": "res://scenes/run_setup/RunSetup.tscn"},
	{"id": "Map", "path": "res://scenes/map/Map.tscn"},
	{"id": "MetaProgress", "path": "res://scenes/meta/MetaProgress.tscn"},
	{"id": "CardLibrary", "path": "res://scenes/library/CardLibrary.tscn"},
	{"id": "Settings", "path": "res://scenes/settings/Settings.tscn"},
	{"id": "Arena", "path": "res://scenes/arena/Arena.tscn"},
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment("QQ_PROFILE_ISOLATED") != "1":
		push_error("SceneLoadProfile requires QQ_PROFILE_ISOLATED=1 and an isolated APPDATA directory.")
		get_tree().quit(1)
		return
	Database.load_all()
	Game.ensure_meta_initialized()
	await WARMUP.warm_all_async()
	for entry: Dictionary in SCENES:
		if String(entry["id"]) == "Map":
			Game.start_new_run("balanced", 4747)
		if String(entry["id"]) == "Arena":
			Game.start_arena_run("balanced", 4747)
		var scene: PackedScene = load(String(entry["path"])) as PackedScene
		var screen: Node = scene.instantiate()
		var start_us: int = Time.get_ticks_usec()
		add_child(screen)
		var added_us: int = Time.get_ticks_usec()
		await get_tree().process_frame
		var first_frame_us: int = Time.get_ticks_usec()
		var content_ready_us: int = first_frame_us
		if screen.has_method("is_content_ready"):
			for _frame_index: int in range(120):
				if bool(screen.call("is_content_ready")):
					break
				await get_tree().process_frame
			content_ready_us = Time.get_ticks_usec()
		print("SCENE_LOAD_PROFILE %s" % JSON.stringify({
			"screen": entry["id"],
			"add_ms": (added_us - start_us) / 1000.0,
			"first_frame_ms": (first_frame_us - added_us) / 1000.0,
			"content_ms": (content_ready_us - added_us) / 1000.0,
		}))
		screen.queue_free()
		await get_tree().process_frame
	get_tree().quit()
