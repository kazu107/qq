extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	SceneRouter.warm_scene_cache()
	var hint_before: String = Game.current_screen_hint
	var warmed: int = await SceneRouter.warm_ui_scene_cache_async()
	var expected_count: int = 1 if Game.is_web_build() else 2
	if not _check(warmed == expected_count, "startup did not prebuild the expected screens"):
		return
	if not _check(Game.current_screen_hint == hint_before, "prebuild changed the active screen hint"):
		return

	var meta_id: int = (SceneRouter.get("_ui_scene_cache") as Dictionary)[SceneRouter.META_SCENE].get_instance_id()
	SceneRouter.go_to_meta_progress()
	await _next_screen()
	if not _check(get_tree().current_scene.get_instance_id() == meta_id, "meta screen was rebuilt on first entry"):
		return
	if not _check(_only_current_scene_is_attached(), "previous screen remained attached behind meta"):
		return
	SceneRouter.go_to_card_library()
	await _next_screen()
	var library_id: int = get_tree().current_scene.get_instance_id()
	if not _check(_only_current_scene_is_attached(), "previous screen remained attached behind library"):
		return
	if not _check(SceneRouter.get_cached_ui_scene_count() >= 1, "meta screen was not cached on exit"):
		return
	SceneRouter.go_to_hub()
	await _next_screen()
	if not _check(SceneRouter.get_cached_ui_scene_count() == 2, "both visited screens were not cached"):
		return
	var previous_points: int = Game.get_meta_points()
	Game.meta_progress["points"] = 12345
	var revisit_start_us: int = Time.get_ticks_usec()
	SceneRouter.go_to_meta_progress()
	var revisit_meta_ms: float = (Time.get_ticks_usec() - revisit_start_us) / 1000.0
	await _next_screen()
	if not _check(get_tree().current_scene.get_instance_id() == meta_id, "meta screen was rebuilt on revisit"):
		return
	var summary_label: RichTextLabel = get_tree().current_scene.get("_summary_label") as RichTextLabel
	if not _check(summary_label != null and summary_label.text.contains("12345"), "reused meta screen did not refresh values"):
		return
	Game.meta_progress["points"] = previous_points
	revisit_start_us = Time.get_ticks_usec()
	SceneRouter.go_to_card_library()
	var revisit_library_ms: float = (Time.get_ticks_usec() - revisit_start_us) / 1000.0
	await _next_screen()
	if not _check(get_tree().current_scene.get_instance_id() == library_id, "library screen was rebuilt on revisit"):
		return
	SceneRouter.go_to_hub()
	await _next_screen()
	var alternate_language: String = "en" if Localization.get_language() != "en" else "ja"
	Localization.set_language(alternate_language)
	await get_tree().process_frame
	if not _check(SceneRouter.get_cached_ui_scene_count() == 0, "language change retained stale UI"):
		return
	if not _check(_only_current_scene_is_attached(), "language change left stale screens in the tree"):
		return
	print("UI_SCENE_CACHE_SMOKE_OK %s" % JSON.stringify({
		"revisit_meta_ms": revisit_meta_ms,
		"revisit_library_ms": revisit_library_ms,
		"reused_and_invalidated": true,
	}))
	get_tree().quit(0)


func _next_screen() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _only_current_scene_is_attached() -> bool:
	var cached_screens: Dictionary = SceneRouter.get("_ui_scene_cache") as Dictionary
	for child: Node in get_tree().root.get_children():
		if child == get_tree().current_scene:
			continue
		if cached_screens.values().has(child):
			if child is CanvasItem and (child as CanvasItem).visible:
				return false
			continue
		if child.scene_file_path.begins_with("res://scenes/"):
			return false
	return true


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("UI scene cache smoke failed: %s" % message)
	get_tree().quit(1)
	return false
