extends Control


func _ready() -> void:
	call_deferred("_build_and_capture")


func _build_and_capture() -> void:
	Database.load_all()
	if not Database.load_errors.is_empty():
		push_error("Battle layout review could not load the database")
		get_tree().quit(1)
		return
	Game.developer_open_battle("guardian", "balanced")
	var battle: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control
	add_child(battle)
	for _frame_index: int in range(10):
		await get_tree().process_frame
	var capture_path: String = OS.get_environment("QQ_BATTLE_LAYOUT_CAPTURE")
	if capture_path != "":
		var image: Image = get_viewport().get_texture().get_image()
		if image == null or image.save_png(capture_path) != OK:
			push_error("Battle layout review could not save the visual capture")
			get_tree().quit(1)
			return
		print("BATTLE_LAYOUT_CAPTURE_OK %s" % capture_path)
	get_tree().quit()
