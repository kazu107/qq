extends Control

var _save_existed: bool
var _saved_bytes: PackedByteArray


func _ready() -> void:
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	if _save_existed:
		_saved_bytes = FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH)
	Game.ensure_meta_initialized()
	Game.settings["developer_mode"] = true
	Localization.set_language("ja", false)
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	get_window().size = Vector2i(1280, 900)
	var simulation: BattleSimulation = BattleSimulation.new()
	var run: RunState = RunState.from_starter(Database.get_starter("fortress"), 123)
	simulation.setup(run, "guardian", 150.0)
	while not simulation.finished:
		simulation.advance(200)
	var summary: Dictionary = simulation.result()
	var replay_path: String = SaveManager.export_replay(ReplayData.from_summary(summary), "quality_review")
	Game.settings["replay_view_path"] = replay_path
	Game.settings["replay_view_return_hint"] = "hub"
	var replay: Control = load("res://scenes/replay/ReplayViewer.tscn").instantiate() as Control
	add_child(replay)
	var player: ReplayVisualPlayer = replay._visual_player
	player.seek(7.0)
	await _capture("quality_replay.png")
	(replay.find_child("ReplayTabs", true, false) as TabContainer).current_tab = 1
	await _capture("quality_analysis.png")
	replay.queue_free()
	await get_tree().process_frame
	var lab: Control = load("res://scenes/debug/AutomatedBattleLab.tscn").instantiate() as Control
	add_child(lab)
	lab._count.value = 3
	lab._begin()
	while lab._running:
		await get_tree().process_frame
	await _capture("quality_lab.png")
	lab.queue_free()
	simulation.dispose()
	DirAccess.remove_absolute(replay_path)
	if _save_existed:
		FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE).store_buffer(_saved_bytes)
	else:
		DirAccess.remove_absolute(SaveManager.SAVE_PATH)
	print("QUALITY_REVIEW_OK")
	get_tree().quit()


func _capture(filename: String) -> void:
	for _frame in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/.local/" + filename)
