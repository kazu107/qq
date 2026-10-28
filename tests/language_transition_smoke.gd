extends Node

var _checks: int = 0
var _warm_finished: bool = false


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized(); Game.set_developer_mode_enabled(false)
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value: push_error("Language transition: " + message); get_tree().quit(1); assert(value, message)


func _settle() -> void:
	for frame: int in 6: await get_tree().process_frame
	var screen: Node = get_tree().current_scene
	for frame: int in 120:
		if not screen.has_method("is_content_ready") or screen.call("is_content_ready"): break
		await get_tree().process_frame


func _captions(node: Node) -> Array[String]:
	var output: Array[String] = []
	if node is Label: output.append((node as Label).text)
	for child: Node in node.get_children(): output.append_array(_captions(child))
	return output


func _warm() -> void:
	await SceneRouter.warm_ui_scene_cache_async()
	_warm_finished = true


func _run() -> void:
	Game.set_language("ja"); SceneRouter.warm_scene_cache()
	await SceneRouter.warm_ui_scene_cache_async()
	SceneRouter.go_to_card_library(); await _settle()
	var old: int = get_tree().current_scene.get_instance_id()
	Game.set_language("en")
	SceneRouter.go_to_hub(); await _settle()
	_check(not SceneRouter.get("_ui_scene_cache").has(SceneRouter.CARD_LIBRARY_SCENE), "old active screen was recached after invalidation")
	SceneRouter.go_to_card_library(); await _settle()
	_check(get_tree().current_scene.get_instance_id() != old, "stale library reused")
	_check(_captions(get_tree().current_scene).has("Card & Relic Library"), "English heading not rebuilt")
	for language: String in ["ja", "en", "ja"]:
		SceneRouter.go_to_hub(); await _settle()
		Game.set_language(language)
		SceneRouter.go_to_card_library(); await _settle()
		_check(SceneRouter.call("_screen_is_current", get_tree().current_scene), "wrong cache epoch on first entry")
		_check(_captions(get_tree().current_scene).has(Localization.get_text("library.title", "Card & Relic Library")), "heading language mismatch")
		SceneRouter.go_to_hub(); await _settle()
		var dialog: MetaProgressDialog = SceneRouter.get_meta_progress_dialog(); dialog.open()
		var content: Control = dialog.get("_content") as Control
		while not bool(content.call("is_content_ready")): await get_tree().process_frame
		_check(SceneRouter.call("_screen_is_current", content), "modal reused old language")
		_check(_captions(content).has(Localization.get_text("meta.title", "Meta Progress")), "modal heading mismatch")
		dialog.close()
	SceneRouter.invalidate_profile_cache(); Game.set_language("ja")
	_warm.call_deferred(); await get_tree().process_frame
	_check(not _warm_finished, "warmup race was not exercised")
	Game.set_language("en")
	for frame: int in 120:
		if _warm_finished: break
		await get_tree().process_frame
	_check(_warm_finished, "cancelled warmup did not finish")
	for screen: Control in SceneRouter.get("_ui_scene_cache").values():
		_check(SceneRouter.call("_screen_is_current", screen), "old language reinserted by delayed warmup")
	SceneRouter.go_to_hub(); await _settle()
	var revision: int = SceneRouter.get("_transition_revision")
	SceneRouter.call_deferred("_release_transition_cover", SceneRouter.HUB_SCENE, 0, revision)
	SceneRouter.set("_transition_revision", revision + 1); SceneRouter.call("_show_transition_cover")
	for frame: int in 4: await get_tree().process_frame
	_check((SceneRouter.get("_transition_cover") as Control).visible, "old transition removed a newer cover")
	SceneRouter.call_deferred("_release_transition_cover", SceneRouter.HUB_SCENE, 0, revision + 1)
	for frame: int in 5: await get_tree().process_frame
	_check(not (SceneRouter.get("_transition_cover") as Control).visible, "current transition stayed covered")
	var sign: BattleInfoSign3D = BattleInfoSign3D.new(); add_child(sign)
	Game.set_language("ja"); sign.refresh_content("", "", "", false, "", false, "", false)
	_check((sign.get("_title_label") as Label3D).text == Localization.get_text("battle.section.battle", "Battle"), "cached 3D sign retained old language")
	sign.queue_free()
	print("LANGUAGE_TRANSITION_SMOKE_OK checks=%d active-cache/reentry/modal/warmup-race/transition-order" % _checks)
	get_tree().quit()
