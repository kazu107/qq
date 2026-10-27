extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized()
	Game.set_language("ja"); Game.set_developer_mode_enabled(false)
	Game.start_new_run("balanced", 4242)
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value: push_error("Settings modal: " + message); get_tree().quit(1); assert(value, message)


func _run() -> void:
	var original_scene: Node = get_tree().current_scene
	var hub: Control = load("res://scenes/hub/Hub.tscn").instantiate() as Control
	hub.theme = UiTheme.get_game_theme(); add_child(hub)
	await get_tree().process_frame
	var suspended: String = JSON.stringify(Game.suspended_runs)
	var menu: Node = hub.find_child("HubModeSelection", true, false)
	var scroll: ScrollContainer = hub.find_child("HubContentScroll", true, false) as ScrollContainer
	scroll.scroll_vertical = 20
	var original_scroll: int = scroll.scroll_vertical
	var gear: Button = hub.find_child("OpenSettingsButton", true, false) as Button
	gear.grab_focus(); gear.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var dialog: SettingsDialog = hub.find_child("SettingsDialog", true, false) as SettingsDialog
	_check(dialog != null and dialog.visible, "modal did not open")
	_check(get_tree().current_scene == original_scene and hub.visible, "opening settings replaced the current scene")
	_check(Game.current_screen_hint == "hub", "modal changed the resume hint")
	_check(hub.find_children("SettingsDialog", "Control", true, false).size() == 1, "duplicate modal")
	_check(hub.find_child("HubModeSelection", true, false) == menu, "menu was rebuilt on open")
	dialog.size = Vector2(640, 700)
	await get_tree().process_frame; await get_tree().process_frame
	_check((dialog.get("_content").get("_columns") as GridContainer).columns == 1, "narrow dialog did not stack sections")
	_check((dialog.get("_content").get("_footer") as BoxContainer).vertical, "narrow footer was not stacked")
	var body_scroll: ScrollContainer = dialog.find_child("SettingsContentScroll", true, false) as ScrollContainer
	_check(body_scroll.get_h_scroll_bar().max_value <= body_scroll.get_h_scroll_bar().page + 1, "narrow content overflows horizontally")
	dialog.size = hub.size
	await get_tree().process_frame; await get_tree().process_frame
	var volume: HSlider = dialog.find_child("MasterVolumeSlider", true, false) as HSlider
	var sfx: HSlider = dialog.find_child("SfxVolumeSlider", true, false) as HSlider
	volume.value = .35; sfx.value = .45
	(dialog.find_child("ReplayAutoExportToggle", true, false) as CheckButton).button_pressed = false
	var saved: SaveData = SaveManager.load_save()
	_check(is_equal_approx(float(saved.settings["master_volume"]), .35) and is_equal_approx(float(saved.settings["sfx_volume"]), .45), "volume changes were not saved")
	_check(not bool(saved.settings["replay_auto_export"]), "toggle was not saved")
	_check(JSON.stringify(Game.suspended_runs) == suspended, "settings modified the suspended run")
	var close: Button = dialog.find_child("SettingsCloseButton", true, false) as Button
	_check(get_viewport().gui_get_focus_owner() == close, "initial modal focus")
	gear.grab_focus(); await get_tree().process_frame
	_check(dialog.is_ancestor_of(get_viewport().gui_get_focus_owner()), "focus escaped behind modal")
	close.pressed.emit(); await get_tree().process_frame
	_check(not dialog.visible and get_tree().current_scene == original_scene, "close replaced the scene")
	_check(menu == hub.find_child("HubModeSelection", true, false) and scroll.scroll_vertical == original_scroll, "close reset menu/scroll")
	_check(get_viewport().gui_get_focus_owner() == gear, "close did not restore focus")
	gear.pressed.emit(); await get_tree().process_frame
	_check(hub.find_child("SettingsDialog", true, false) == dialog and dialog.visible, "dialog was not reused")
	var language: OptionButton = dialog.find_child("LanguageOptionButton", true, false) as OptionButton
	language.item_selected.emit(0)
	await get_tree().process_frame; await get_tree().process_frame
	_check(Game.get_language() == "en" and dialog.visible, "language change closed modal")
	_check((dialog.find_child("SettingsBackButton", true, false) as Button).text == "Close", "modal did not localize")
	(dialog.find_child("SettingsBackButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame; await get_tree().process_frame
	_check(get_tree().current_scene == original_scene, "language change replaced scene")
	_check((hub.find_child("RunStartButton", true, false) as Button).text == "New Game", "hub language was not refreshed")
	_check(hub.find_children("OpenSettingsButton", "Button", true, false).size() == 1, "localized rebuild duplicated controls")
	_check(JSON.stringify(Game.suspended_runs) == suspended, "localized menu lost suspended run")
	hub.call("_open_settings"); await get_tree().process_frame
	(dialog.find_child("DeveloperModeToggle", true, false) as CheckButton).button_pressed = true
	dialog.close(); await get_tree().process_frame; await get_tree().process_frame
	_check(hub.find_child("DebugBattleLab", true, false) != null, "developer tools not reflected in hub")
	hub.call("_open_settings"); await get_tree().process_frame
	(dialog.find_child("DeveloperModeToggle", true, false) as CheckButton).button_pressed = false
	dialog.close(); await get_tree().process_frame; await get_tree().process_frame
	_check(hub.find_child("DebugBattleLab", true, false) == null, "disabled developer tools remain")
	_check(AccountSession.changed.get_connections().filter(func(connection: Dictionary) -> bool: return connection["callable"] == Callable(dialog.get("_content"), "_refresh_developer_access")).size() == 1, "language rebuild duplicated account signal")
	hub.call("_open_settings"); await get_tree().process_frame
	var escape: InputEventKey = InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	dialog.call("_unhandled_key_input", escape); await get_tree().process_frame
	_check(not dialog.visible, "Escape did not close modal")
	hub.call("_open_settings"); await get_tree().process_frame
	var click: InputEventMouseButton = InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	dialog.call("_on_backdrop_input", click); await get_tree().process_frame
	_check(not dialog.visible, "backdrop did not close modal")
	_check(JSON.stringify(Game.suspended_runs) == suspended and Game.current_screen_hint == "hub", "closing changed resume data")
	hub.queue_free(); await get_tree().process_frame
	print("SETTINGS_MODAL_SMOKE_OK checks=%d no-transition/cache/focus/close/Escape/backdrop/volume/persistence/language/developer/resume" % _checks)
	get_tree().quit()
