extends Node


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized()
	call_deferred("_run")


func _run() -> void:
	for path: String in [SceneRouter.HUB_SCENE, SceneRouter.SETTINGS_SCENE]:
		var screen: Control = load(path).instantiate() as Control
		add_child(screen)
		UiTheme.call("_ensure_background", screen)
		var background: AtmosphereBackground = screen.get_node(UiTheme.BACKGROUND_NODE_NAME) as AtmosphereBackground
		assert(background != null and background.side_vignette_enabled == (path != SceneRouter.HUB_SCENE), "Incorrect side shading policy")
		assert(background.mouse_filter == Control.MOUSE_FILTER_IGNORE and background.z_index == -4096, "Background blocks the menu")
		assert(background.get("_authored_texture") != null, "Background art is missing")
		UiTheme.call("_ensure_background", screen)
		assert(screen.find_children(UiTheme.BACKGROUND_NODE_NAME, "Control", true, false).size() == 1, "Background duplicated")
		screen.queue_free(); await get_tree().process_frame
	print("HUB_BACKGROUND_SMOKE_OK Hub side bands disabled, other menus unchanged, art/input/cache retained")
	get_tree().quit()
