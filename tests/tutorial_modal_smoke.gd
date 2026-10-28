extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.set_language("ja")
	Game.set_developer_mode_enabled(false)
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("Tutorial modal: " + message)
		get_tree().quit(1)
		assert(value, message)


func _settle() -> void:
	for frame: int in 6:
		await get_tree().process_frame


func _run() -> void:
	# Remain alive while exercising real scene changes into and out of a lesson.
	get_tree().current_scene = null
	reparent(SceneRouter)
	Game.start_new_run("balanced", 4242)
	SceneRouter.go_to_hub()
	await _settle()
	var hub: Control = get_tree().current_scene as Control
	var suspended: String = JSON.stringify(Game.suspended_runs)
	var meta: String = JSON.stringify(Game.meta_progress)
	var open_button: Button = hub.find_child("BattleTutorialButton", true, false) as Button
	open_button.grab_focus()
	open_button.pressed.emit()
	await _settle()
	var dialog: BattleTutorialDialog = SceneRouter.get_battle_tutorial_dialog()
	var content: Control = dialog.get("_content") as Control
	var content_id: int = content.get_instance_id()
	var scroll: ScrollContainer = content.find_child("TutorialScroll", true, false) as ScrollContainer
	var list: GridContainer = content.find_child("TutorialList", true, false) as GridContainer
	_check(dialog.visible and hub.visible and get_tree().current_scene == hub, "opening must keep the Hub scene")
	_check(Game.current_screen_hint == "hub", "opening must preserve the resume hint")
	_check(content.get("modal_mode") and int(content.call("get_tutorial_count")) == 14, "embedded catalog must show all fourteen lessons")
	_check(list.get_child_count() == 14, "lesson controls missing")
	_check(get_viewport().gui_get_focus_owner() == content.find_child("TutorialBackButton", true, false), "initial focus must be inside the window")
	hub.call("_open_settings")
	_check(hub.find_child("SettingsDialog", true, false) == null, "settings must not open behind the tutorial")
	hub.call("_on_open_meta_progress")
	_check(not SceneRouter.is_meta_progress_dialog_open(), "meta must not overlap the tutorial")
	hub.call("_open_version_history")
	_check(not (hub.get("_version_history_overlay") as Control).visible, "history must not overlap the tutorial")
	var first: Node = list.get_child(0)
	(content.find_child("TutorialBackButton", true, false) as Button).pressed.emit()
	await _settle()
	_check(not dialog.visible and get_tree().current_scene == hub, "close must keep the Hub")
	_check(get_viewport().gui_get_focus_owner() == open_button, "close must restore the invoking button focus")
	open_button.pressed.emit()
	await _settle()
	_check(dialog.get("_content") == content and list.get_child(0) == first, "reopen must reuse the catalog and rows")
	var original_size: Vector2 = dialog.size
	for dimensions: Vector2 in [Vector2(1600, 900), Vector2(900, 700), Vector2(420, 800)]:
		dialog.size = dimensions
		await _settle()
		var frame: Control = dialog.get("_frame") as Control
		_check(frame.position.x >= 0 and frame.position.y >= 0 and frame.get_rect().end.x <= dimensions.x + 1 and frame.get_rect().end.y <= dimensions.y + 1, "window must fit at " + str(dimensions))
		_check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page + 1, "no horizontal scrolling at " + str(dimensions))
		_check(list.columns == (2 if content.size.x >= 1240.0 else 1), "responsive lesson columns")
	dialog.size = original_size
	await _settle()
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	dialog.call("_unhandled_key_input", escape)
	_check(not dialog.visible, "Escape must close")
	open_button.pressed.emit()
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	dialog.call("_on_backdrop_input", click)
	_check(not dialog.visible, "backdrop must close")
	Game.set_language("en")
	await _settle()
	hub.call("_on_open_battle_tutorial")
	await _settle()
	dialog = SceneRouter.get_battle_tutorial_dialog()
	content = dialog.get("_content") as Control
	_check(content.get_instance_id() != content_id, "locale change must invalidate cached content")
	_check((content.find_child("TutorialBackButton", true, false) as Button).text == "Close", "reopened window must use the selected language")
	content_id = content.get_instance_id()
	(content.find_child("TutorialStart_battle_basics", true, false) as Button).pressed.emit()
	await _settle()
	var battle: Control = get_tree().current_scene as Control
	_check(battle.scene_file_path == SceneRouter.BATTLE_SCENE and bool(battle.call("is_tutorial_mode")), "lesson must use the regular battle screen")
	_check(not dialog.visible, "lesson launch must hide the catalog")
	battle.call("_exit_tutorial_to_list")
	await _settle()
	_check(get_tree().current_scene.scene_file_path == SceneRouter.HUB_SCENE and SceneRouter.is_battle_tutorial_dialog_open(), "exit lesson must return to the modal over Hub")
	_check((dialog.get("_content") as Control).get_instance_id() == content_id, "return from battle must reuse catalog")
	_check(not Game.is_battle_tutorial_active(), "return must clear tutorial state")
	_check(JSON.stringify(Game.suspended_runs) == suspended and JSON.stringify(Game.meta_progress) == meta, "lessons must not change saved runs or meta progress")
	dialog.close()
	SceneRouter.invalidate_profile_cache()
	await _settle()
	(get_tree().current_scene as Control).call("_on_open_battle_tutorial")
	await _settle()
	_check((SceneRouter.get_battle_tutorial_dialog().get("_content") as Control).get_instance_id() != content_id, "profile change must invalidate the window")
	SceneRouter.get_battle_tutorial_dialog().close()
	print("TUTORIAL_MODAL_SMOKE_OK checks=%d same-scene/cache/responsive/focus/close/Escape/backdrop/locale/lesson-return/save" % _checks)
	get_tree().quit()
