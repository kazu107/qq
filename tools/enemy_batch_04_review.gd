extends Control

const IDS: Array[String] = [
	"brute", "disruptor", "raider", "medic_drone", "chronoguard", "phase_stalker",
	"void_bastion", "echo_revenant", "rift_predator", "entropy_colossus", "omega_seraph", "grave_architect", "scout",
]


func _ready() -> void:
	get_window().size = Vector2i(1600, 1020)
	get_window().content_scale_size = Vector2i(1600, 1020)
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/blender/characters/qq_enemies_04.manifest.json")) as Dictionary
	var output: String = OS.get_environment("QQ_ENEMY_04_REVIEW_DIR")
	if output.is_empty():
		output = "res://art_src/blender/previews"
	var title := Label.new()
	title.text = "ENEMY COLLECTION / 04 / GODOT IMPORT"
	title.position = Vector2(24, 14)
	title.add_theme_font_size_override("font_size", 27)
	add_child(title)
	for page: int in range(2):
		var page_root := Control.new()
		add_child(page_root)
		var previews: Array[StarterModelPreview] = []
		for slot: int in range(8):
			var index: int = page * 8 + slot
			if index >= IDS.size():
				break
			var visual_id: String = IDS[index]
			var origin := Vector2(24 + (slot % 4) * 394, 62 + (slot / 4) * 474)
			var model := StarterModelPreview.new()
			model.position = origin
			model.size = Vector2(368, 365)
			model.custom_minimum_size = model.size
			page_root.add_child(model)
			model.show_starter(visual_id)
			var profile: Dictionary = Database.get_battle_visual_profile(visual_id).duplicate(true)
			profile["model_scene"] = "res://assets/models/battle/%s.glb" % visual_id
			model.get_preview_actor().configure_visual(visual_id, profile)
			var camera: Camera3D = model.find_child("StarterPreviewCamera", true, false) as Camera3D
			camera.fov = 46.0
			model.get_preview_actor().start_timeline_stance()
			previews.append(model)
			var portrait := TextureRect.new()
			portrait.texture = load("res://assets/portraits/%s.png" % visual_id) as Texture2D
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.position = origin + Vector2(0, 373)
			portrait.size = Vector2(82, 82)
			page_root.add_child(portrait)
			var label := Label.new()
			label.text = "%s\n18 bones / 5 sockets" % visual_id
			label.position = origin + Vector2(96, 381)
			label.add_theme_font_size_override("font_size", 17)
			page_root.add_child(label)
		await get_tree().create_timer(1.0).timeout
		for preview: StarterModelPreview in previews:
			if not preview.get_preview_actor().is_using_authored_model():
				push_error("Enemy review fallback: " + preview.get_selected_starter_id())
				get_tree().quit(1)
				return
		RenderingServer.force_draw(false, 0.0)
		var capture: Image = get_viewport().get_texture().get_image()
		var target: String = output.path_join("enemy_batch_04_game_ui_%d.png" % (page + 1))
		if capture == null or capture.save_png(target) != OK:
			push_error("Could not capture enemy art review")
			get_tree().quit(1)
			return
		print("ENEMY_04_GAME_UI_CAPTURE_OK ", target)
		page_root.free()
		await get_tree().process_frame
	print("ENEMY_04_GAME_UI_REVIEW_OK %d manifest entries" % manifest.get("assets", []).size())
	get_tree().quit()
