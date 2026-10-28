extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized()
	Game.set_language("ja"); Game.set_developer_mode_enabled(false)
	Game.meta_progress = Database.meta_progress_template.duplicate(true); Game.ensure_meta_initialized()
	Game.meta_progress["points"] = 100
	Game.meta_progress["achievement_stats"]["gold_spent"] = 100
	Game.start_new_run("balanced", 4242)
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value: push_error("Meta modal: " + message); get_tree().quit(1); assert(value, message)


func _run() -> void:
	SceneRouter.get("_scene_cache")[SceneRouter.META_SCENE] = load(SceneRouter.META_SCENE)
	await SceneRouter.warm_ui_scene_cache_async()
	var cached: Control = SceneRouter.get("_ui_scene_cache")[SceneRouter.META_SCENE]
	var hub: Control = load("res://scenes/hub/Hub.tscn").instantiate() as Control
	hub.theme = UiTheme.get_game_theme(); add_child(hub)
	await get_tree().process_frame
	var original_scene: Node = get_tree().current_scene
	var suspended: String = JSON.stringify(Game.suspended_runs)
	(hub.find_child("HubMetaProgressButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame; await get_tree().process_frame
	var dialog: MetaProgressDialog = SceneRouter.get_meta_progress_dialog()
	var content: Control = dialog.get("_content") as Control
	_check(dialog.visible and hub.visible, "modal did not open over hub")
	_check(get_tree().current_scene == original_scene and Game.current_screen_hint == "hub", "opening replaced the scene or resume hint")
	_check(content == cached and bool(content.call("is_content_ready")), "startup cache was not reused")
	hub.call("_open_settings")
	_check(hub.find_child("SettingsDialog", true, false) == null, "settings opened behind the meta modal")
	_check((content.find_child("MetaAchievementBox", true, false) as GridContainer).get_child_count() == 30, "achievement list incomplete")
	_check(content.find_children("*", "SubViewport", true, false).is_empty(), "unlock icons must not create live 3D viewports")
	for entry: Dictionary in Game.get_meta_starter_entries():
		var id: String = String(entry["id"])
		var icon: TextureRect = content.find_child("StarterIcon_" + id, true, false) as TextureRect
		var icon_frame: PanelContainer = content.find_child("StarterIconFrame_" + id, true, false) as PanelContainer
		_check(icon != null and icon.texture != null and icon.texture.resource_path == "res://assets/portraits/%s.png" % id, "starter model portrait missing: " + id)
		_check(icon.texture == UnitPanel.get_portrait_texture(id), "starter portrait must reuse the shared cache: " + id)
		_check(icon_frame.size.is_equal_approx(Vector2(96, 96)) and icon.expand_mode == TextureRect.EXPAND_IGNORE_SIZE, "starter icon must remain square and ignore source image dimensions: " + id)
	var first: Node = (content.find_child("MetaAchievementBox", true, false) as GridContainer).get_child(0)
	var widgets: Dictionary = content.get("_achievement_widgets")
	var claim: Button = widgets["big_spender"]["button"] as Button
	_check(not claim.disabled, "claimable reward is disabled")
	var before_points: int = Game.get_meta_points()
	claim.pressed.emit(); await get_tree().process_frame
	_check(int(Game.meta_progress["achievement_claim_counts"].get("big_spender", 0)) == 1 and Game.get_meta_points() > before_points, "claim did not grant reward")
	var buy: Button = content.find_child("BuyMetaStatUpgrade_max_hp", true, false) as Button
	_check(not buy.disabled, "stat upgrade is disabled")
	buy.pressed.emit(); await get_tree().process_frame
	_check(int(Game.meta_progress["permanent_upgrade_levels"].get("max_hp", 0)) == 1, "stat upgrade did not persist")
	var tempo_icon: TextureRect = content.find_child("StarterIcon_tempo", true, false) as TextureRect
	var tempo_frame: PanelContainer = content.find_child("StarterIconFrame_tempo", true, false) as PanelContainer
	var tempo_texture: Texture2D = tempo_icon.texture
	var starter_points: int = Game.get_meta_points()
	(content.find_child("UnlockStarter_tempo", true, false) as Button).pressed.emit()
	_check(Array(Game.meta_progress["unlocked_starters"]).has("tempo") and Game.get_meta_points() == starter_points - 2, "portrait row must preserve starter purchasing")
	_check((tempo_frame.get_theme_stylebox("panel") as StyleBoxFlat).border_color == UiTheme.ACCENT_GOLD, "unlock must update the icon border")
	var unlocked_style: StyleBox = tempo_frame.get_theme_stylebox("panel")
	content.call("_refresh_ui")
	_check(tempo_frame.get_theme_stylebox("panel") == unlocked_style and tempo_icon.texture == tempo_texture, "refresh must preserve unchanged icon controls, styles and textures")
	_check(JSON.stringify(Game.suspended_runs) == suspended, "meta rewards changed suspended run")
	SaveManager.flush_requested_save()
	var saved: SaveData = SaveManager.load_save()
	_check(int(saved.meta_progress["achievement_claim_counts"].get("big_spender", 0)) == 1, "claim was not saved")
	_check(Array(saved.meta_progress["unlocked_starters"]).has("tempo"), "starter unlock was not saved")
	(content.find_child("MetaCloseButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame; await get_tree().process_frame
	_check(not dialog.visible and get_tree().current_scene == original_scene, "closing replaced scene")
	_check((hub.find_child("HubMetaPoints", true, false) as Label).text == str(Game.get_meta_points()), "hub points are stale")
	hub.call("_on_open_meta_progress"); await get_tree().process_frame
	_check(SceneRouter.get_meta_progress_dialog() == dialog and dialog.get("_content") == content, "window content was rebuilt on reopen")
	_check((content.find_child("MetaAchievementBox", true, false) as GridContainer).get_child(0) == first, "cached rows were rebuilt")
	var old_size: Vector2 = dialog.size
	dialog.size = Vector2(700, 800); await get_tree().process_frame; await get_tree().process_frame
	_check((content.get("_layout_root") as BoxContainer).vertical, "narrow layout was not stacked")
	var scroll: ScrollContainer = content.find_child("MetaWindowScroll", true, false) as ScrollContainer
	_check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page + 1, "horizontal overflow")
	dialog.size = old_size; await get_tree().process_frame
	var escape: InputEventKey = InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	dialog.call("_unhandled_key_input", escape); await get_tree().process_frame
	_check(not dialog.visible, "Escape did not close")
	hub.call("_on_open_meta_progress"); await get_tree().process_frame
	var click: InputEventMouseButton = InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	dialog.call("_on_backdrop_input", click); await get_tree().process_frame
	_check(not dialog.visible, "backdrop did not close")
	Game.set_language("en"); await get_tree().process_frame
	hub.call("_on_open_meta_progress"); await get_tree().process_frame
	var localized: Control = SceneRouter.get_meta_progress_dialog().get("_content") as Control
	while not bool(localized.call("is_content_ready")): await get_tree().process_frame
	_check(localized != content and (localized.find_child("MetaBackButton", true, false) as Button).text == "Close", "locale invalidation failed")
	_check(JSON.stringify(Game.suspended_runs) == suspended and Game.current_screen_hint == "hub", "resume data changed")
	SceneRouter.get_meta_progress_dialog().close()
	SceneRouter.invalidate_profile_cache()
	await get_tree().process_frame
	Game.meta_progress = Database.meta_progress_template.duplicate(true); Game.ensure_meta_initialized()
	hub.call("_on_open_meta_progress"); await get_tree().process_frame
	var fresh: Control = SceneRouter.get_meta_progress_dialog().get("_content") as Control
	while not bool(fresh.call("is_content_ready")): await get_tree().process_frame
	_check(fresh != localized and Game.get_meta_points() == 0, "profile change reused old progression")
	_check((fresh.get("_achievement_widgets")["big_spender"]["button"] as Button).disabled, "old claimable state leaked into a new profile")
	_check((fresh.find_child("StarterIconFrame_tempo", true, false).get_theme_stylebox("panel") as StyleBoxFlat).border_color == UiTheme.PANEL_STROKE, "old portrait unlock styling leaked into a new profile")
	SceneRouter.get_meta_progress_dialog().close()
	hub.queue_free(); await get_tree().process_frame
	print("META_MODAL_SMOKE_OK checks=%d startup-cache/claim/stat-upgrade/save/hub-refresh/reopen/resize/Escape/backdrop/locale/resume" % _checks)
	get_tree().quit()
