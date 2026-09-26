extends Node

const TITLE_SCENE := "res://scenes/title/Title.tscn"
const HUB_SCENE := "res://scenes/hub/Hub.tscn"
const RUN_SETUP_SCENE := "res://scenes/run_setup/RunSetup.tscn"
const ARENA_SCENE := "res://scenes/arena/Arena.tscn"
const ONLINE_LOBBY_SCENE := "res://scenes/online/OnlineLobby.tscn"
const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const REWARD_SCENE := "res://scenes/reward/Reward.tscn"
const RESULT_SCENE := "res://scenes/result/RunResult.tscn"
const MAP_SCENE := "res://scenes/map/Map.tscn"
const FACILITY_SCENE := "res://scenes/facility/Facility.tscn"
const META_SCENE := "res://scenes/meta/MetaProgress.tscn"
const CARD_LIBRARY_SCENE := "res://scenes/library/CardLibrary.tscn"
const SETTINGS_SCENE := "res://scenes/settings/Settings.tscn"
const REPLAY_SCENE := "res://scenes/replay/ReplayViewer.tscn"
const SFX_LAB_SCENE := "res://scenes/debug/SfxLab.tscn"
const BATTLE_ANIMATION_LAB_SCENE := "res://scenes/debug/BattleAnimationLab.tscn"
const AUTOMATED_BATTLE_LAB_SCENE := "res://scenes/debug/AutomatedBattleLab.tscn"
const BATTLE_TUTORIAL_SCENE := "res://scenes/tutorial/BattleTutorial.tscn"
const TRANSITION_COVER_NAME := "SceneTransitionCover"
const GOLD_DELTA_POPUP_NAME := "GoldDeltaPopup"

var _transition_layer: CanvasLayer
var _transition_cover: ColorRect
var _gold_popup_layer: CanvasLayer
var _gold_popup_index: int = 0
var _scene_cache: Dictionary = {}
var _ui_scene_cache: Dictionary = {}
var _warming_ui_scene: bool = false
var _battle_stage_cache: BattleStage3D
var _pending_battle_card_ids: Array[String] = []
var _debug_return_scene_path: String = HUB_SCENE


func _ready() -> void:
	set_process(false)
	Localization.language_changed.connect(_on_language_changed)


func is_warming_ui_scene() -> bool:
	return _warming_ui_scene


func warm_ui_scene_cache_async(progress_callback: Callable = Callable()) -> int:
	var scene_paths: Array[String] = [META_SCENE]
	if not Game.is_web_build():
		scene_paths.append(CARD_LIBRARY_SCENE)
	var warmed: int = 0
	for scene_index: int in range(scene_paths.size()):
		var scene_path: String = scene_paths[scene_index]
		if progress_callback.is_valid():
			progress_callback.call(
				Localization.get_text("boot.caching_ui_screens", "Preparing menus..."),
				0.975 + 0.01 * float(scene_index) / float(scene_paths.size())
			)
		if _ui_scene_cache.has(scene_path):
			continue
		var packed_scene: PackedScene = _get_preloaded_scene(scene_path)
		if packed_scene == null:
			continue
		var screen: Control = packed_scene.instantiate() as Control
		if screen == null:
			continue
		screen.visible = false
		_warming_ui_scene = true
		get_tree().root.add_child(screen)
		_warming_ui_scene = false
		var wait_frames: int = 0
		while is_instance_valid(screen) and not bool(screen.call("is_content_ready")) and wait_frames < 300:
			await get_tree().process_frame
			wait_frames += 1
		if is_instance_valid(screen) and bool(screen.call("is_content_ready")):
			_ui_scene_cache[scene_path] = screen
			warmed += 1
		elif is_instance_valid(screen):
			screen.queue_free()
	if progress_callback.is_valid():
		progress_callback.call(Localization.get_text("boot.caching_ui_screens", "Preparing menus..."), 0.985)
	return warmed


func get_cached_ui_scene_count() -> int:
	return _ui_scene_cache.size()


func _process(_delta: float) -> void:
	if _pending_battle_card_ids.is_empty():
		set_process(false)
		return
	CardButton.warm_texture_cache([_pending_battle_card_ids.pop_front()])


func warm_battle_stage_cache_async() -> bool:
	if _battle_stage_cache != null and is_instance_valid(_battle_stage_cache):
		return true
	var stage: BattleStage3D = BattleStage3D.new()
	stage.name = "CachedBattleStage3D"
	stage.position = Vector2(-2048.0, -2048.0)
	stage.size = Vector2(BattleStage3D.DEFAULT_VIEWPORT_SIZE)
	add_child(stage)
	_battle_stage_cache = stage
	await get_tree().process_frame
	await get_tree().process_frame
	stage.suspend_for_cache()
	return true


func has_cached_battle_stage() -> bool:
	return _battle_stage_cache != null and is_instance_valid(_battle_stage_cache)


func take_cached_battle_stage() -> BattleStage3D:
	if not has_cached_battle_stage():
		return BattleStage3D.new()
	var stage: BattleStage3D = _battle_stage_cache
	_battle_stage_cache = null
	remove_child(stage)
	return stage


func warm_current_battle_cards_async() -> int:
	if not Game.is_web_build():
		return 0
	var card_ids: Array[String] = _current_battle_card_ids()
	var warmed: int = 0
	for card_id: String in card_ids:
		warmed += CardButton.warm_texture_cache([card_id])
		await get_tree().process_frame
	return warmed


func schedule_current_battle_cards() -> void:
	if not Game.is_web_build():
		return
	for card_id: String in _current_battle_card_ids():
		if not _pending_battle_card_ids.has(card_id):
			_pending_battle_card_ids.append(card_id)
	if not _pending_battle_card_ids.is_empty():
		set_process(true)


func _current_battle_card_ids() -> Array[String]:
	var card_ids: Array[String] = []
	if Game.is_battle_tutorial_active():
		var tutorial: Dictionary = BattleTutorialCatalog.get_tutorial(Game.active_battle_tutorial_id)
		for raw_card_id: Variant in Array(tutorial.get("cards", [])):
			var card_id: String = String(raw_card_id)
			if not card_ids.has(card_id):
				card_ids.append(card_id)
		var tutorial_enemy: EnemyDef = Database.get_enemy(String(tutorial.get("enemy_id", "")))
		if tutorial_enemy != null:
			for card_id: String in tutorial_enemy.cards:
				if not card_ids.has(card_id):
					card_ids.append(card_id)
	if Game.current_run != null:
		for card_id: String in Game.current_run.equipped_cards:
			if not card_ids.has(card_id):
				card_ids.append(card_id)
		var enemy_id: String = Game.pending_enemy_id
		if enemy_id == "":
			enemy_id = String(Game.get_active_map_node().get("enemy_id", ""))
		var enemy: EnemyDef = Database.get_enemy(enemy_id)
		if enemy != null:
			for card_id: String in enemy.cards:
				if not card_ids.has(card_id):
					card_ids.append(card_id)
	if NetworkManager.has_active_match():
		for side: String in ["player", "enemy"]:
			var match_run: RunState = NetworkManager.get_match_run(side)
			if match_run == null:
				continue
			for card_id: String in match_run.equipped_cards:
				if not card_ids.has(card_id):
					card_ids.append(card_id)
	return card_ids


func warm_scene_cache() -> void:
	var scene_paths: Array[String] = [
		TITLE_SCENE,
		HUB_SCENE,
		RUN_SETUP_SCENE,
		ARENA_SCENE,
		BATTLE_SCENE,
		REWARD_SCENE,
		RESULT_SCENE,
		MAP_SCENE,
		FACILITY_SCENE,
		META_SCENE,
		CARD_LIBRARY_SCENE,
		SETTINGS_SCENE,
		REPLAY_SCENE,
		SFX_LAB_SCENE,
		BATTLE_ANIMATION_LAB_SCENE,
		AUTOMATED_BATTLE_LAB_SCENE,
		BATTLE_TUTORIAL_SCENE,
	]
	if Game.WEB_MULTIPLAYER_ENABLED:
		scene_paths.append(ONLINE_LOBBY_SCENE)
	for scene_path in scene_paths:
		if _scene_cache.has(scene_path):
			continue
		var resource: Resource = ResourceLoader.load(scene_path)
		var packed_scene: PackedScene = resource as PackedScene
		if packed_scene != null:
			_scene_cache[scene_path] = packed_scene


func get_cached_scene_count() -> int:
	return _scene_cache.size()

func go_to_title() -> void:
	_change_scene(TITLE_SCENE)


func go_to_hub() -> void:
	_change_scene(HUB_SCENE)


func go_to_run_setup(mode: String = Game.RUN_SETUP_MODE_NORMAL) -> void:
	Game.prepare_run_setup(mode)
	_change_scene(RUN_SETUP_SCENE)


func go_to_arena() -> void:
	_change_scene(ARENA_SCENE)


func go_to_online_lobby() -> void:
	if not Game.WEB_MULTIPLAYER_ENABLED:
		Game.current_screen_hint = "hub"
		go_to_hub()
		return
	_change_scene(ONLINE_LOBBY_SCENE)


func go_to_battle() -> void:
	_change_scene(BATTLE_SCENE)


func go_to_reward() -> void:
	_change_scene(REWARD_SCENE)


func go_to_result() -> void:
	_change_scene(RESULT_SCENE)


func go_to_map() -> void:
	_change_scene(MAP_SCENE)


func go_to_facility() -> void:
	_change_scene(FACILITY_SCENE)


func go_to_meta_progress() -> void:
	_change_scene(META_SCENE)


func go_to_card_library() -> void:
	_change_scene(CARD_LIBRARY_SCENE)


func go_to_settings() -> void:
	_change_scene(SETTINGS_SCENE)


func go_to_replay_viewer() -> void:
	_change_scene(REPLAY_SCENE)


func go_to_battle_tutorial() -> void:
	if NetworkManager.is_session_connected():
		return
	Game.clear_battle_tutorial()
	_change_scene(BATTLE_TUTORIAL_SCENE)


func start_battle_tutorial(tutorial_id: String) -> void:
	if not Game.begin_battle_tutorial(tutorial_id):
		AudioManager.play_sfx("ui_error")
		return
	_change_scene(BATTLE_SCENE)


func go_to_sfx_lab() -> void:
	if not Game.is_developer_mode_enabled():
		go_to_hub()
		return
	_remember_debug_return_scene()
	_change_scene(SFX_LAB_SCENE)


func go_to_automated_battle_lab() -> void:
	if not Game.is_developer_mode_enabled() or NetworkManager.is_session_connected():
		return
	_remember_debug_return_scene()
	_change_scene(AUTOMATED_BATTLE_LAB_SCENE)


func return_from_sfx_lab() -> void:
	return_from_debug_lab()


func go_to_battle_animation_lab() -> void:
	if not Game.is_developer_mode_enabled():
		go_to_hub()
		return
	_remember_debug_return_scene()
	_change_scene(BATTLE_ANIMATION_LAB_SCENE)


func return_from_debug_lab() -> void:
	var return_path: String = _debug_return_scene_path
	if return_path == "" or return_path == SFX_LAB_SCENE or return_path == BATTLE_ANIMATION_LAB_SCENE:
		return_path = HUB_SCENE
	_change_scene(return_path)


func _remember_debug_return_scene() -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null or current_scene.scene_file_path == "":
		return
	if current_scene.scene_file_path == SFX_LAB_SCENE or current_scene.scene_file_path == BATTLE_ANIMATION_LAB_SCENE:
		return
	_debug_return_scene_path = current_scene.scene_file_path


func go_to_continue_target() -> void:
	match Game.current_screen_hint:
		"hub":
			go_to_hub()
		"run_setup":
			go_to_run_setup()
		"arena":
			go_to_arena()
		"online":
			go_to_online_lobby()
		"battle":
			go_to_battle()
		"reward":
			go_to_reward()
		"result":
			go_to_result()
		"map":
			go_to_map()
		"facility":
			go_to_facility()
		"meta":
			go_to_meta_progress()
		"library":
			go_to_card_library()
		"settings":
			go_to_settings()
		"replay":
			go_to_replay_viewer()
		_:
			go_to_hub()


func continue_suspended_run(mode: String) -> void:
	if Game.resume_suspended_run(mode) == "":
		AudioManager.play_sfx("ui_error")
		return
	AudioManager.play_sfx("run_resume")
	go_to_continue_target()


func show_gold_delta(amount: int) -> void:
	if amount == 0:
		return
	_ensure_gold_popup_layer()
	_gold_popup_index += 1
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var popup: PanelContainer = PanelContainer.new()
	popup.name = "%s_%d" % [GOLD_DELTA_POPUP_NAME, _gold_popup_index]
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.custom_minimum_size = Vector2(132.0, 44.0)
	popup.position = Vector2(maxf(18.0, viewport_size.x * 0.5 - 66.0), 74.0 + float((_gold_popup_index % 3) * 18))
	popup.add_theme_stylebox_override("panel", _make_gold_popup_style(amount > 0))
	_gold_popup_layer.add_child(popup)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 7)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var icon: TextureRect = TextureRect.new()
	icon.name = "GoldDeltaIcon"
	icon.custom_minimum_size = Vector2(28.0, 28.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = StatIconFactory.get_icon("gold")
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var label: Label = Label.new()
	label.name = "GoldDeltaValue"
	label.text = "%+d" % amount
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.30, 1.0) if amount > 0 else Color(1.0, 0.42, 0.28, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	var start_position: Vector2 = popup.position
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position", start_position + Vector2(0.0, -42.0), 1.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "scale", Vector2(1.08, 1.08), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "scale", Vector2.ONE, 0.24).set_delay(0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.32).set_delay(0.92).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.finished.connect(popup.queue_free)


func _change_scene(scene_path: String) -> void:
	var transition_started_us: int = Time.get_ticks_usec()
	AudioManager.play_sfx("ui_page")
	_show_transition_cover()
	var current_scene: CanvasItem = get_tree().current_scene as CanvasItem
	if current_scene != null:
		current_scene.visible = false
		if current_scene.has_method("detach_battle_stage_for_cache"):
			var stage: BattleStage3D = current_scene.call("detach_battle_stage_for_cache") as BattleStage3D
			if stage != null:
				_store_battle_stage(stage)
	if scene_path == BATTLE_SCENE:
		_pending_battle_card_ids.clear()
		set_process(false)
		if Game.is_web_build():
			CardButton.warm_texture_cache(_current_battle_card_ids())
	else:
		schedule_current_battle_cards()
	_cache_current_ui_scene(current_scene)
	if _ui_scene_cache.has(scene_path):
		if current_scene != null and current_scene.get_parent() == get_tree().root \
		and _ui_scene_cache.get(current_scene.scene_file_path) != current_scene:
			get_tree().current_scene = null
			get_tree().root.remove_child(current_scene)
			current_scene.queue_free()
		var screen: Control = _ui_scene_cache[scene_path] as Control
		_ui_scene_cache.erase(scene_path)
		get_tree().current_scene = screen
		screen.visible = true
		screen.call("on_reenter")
		call_deferred("_release_transition_cover", scene_path, transition_started_us)
		return
	var packed_scene: PackedScene = _get_preloaded_scene(scene_path)
	if packed_scene != null:
		get_tree().change_scene_to_packed(packed_scene)
	else:
		get_tree().change_scene_to_file(scene_path)
	call_deferred("_release_transition_cover", scene_path, transition_started_us)


func _cache_current_ui_scene(current_scene: CanvasItem) -> void:
	if current_scene == null:
		return
	var scene_path: String = current_scene.scene_file_path
	if scene_path != META_SCENE and scene_path != CARD_LIBRARY_SCENE:
		return
	if not current_scene.has_method("is_content_ready") or not bool(current_scene.call("is_content_ready")):
		return
	if _ui_scene_cache.has(scene_path):
		return
	get_tree().current_scene = null
	_ui_scene_cache[scene_path] = current_scene


func _on_language_changed(_language_code: String) -> void:
	for cached_screen: Control in _ui_scene_cache.values():
		if is_instance_valid(cached_screen):
			cached_screen.queue_free()
	_ui_scene_cache.clear()


func _store_battle_stage(stage: BattleStage3D) -> void:
	if has_cached_battle_stage():
		stage.queue_free()
		return
	stage.suspend_for_cache()
	stage.position = Vector2(-2048.0, -2048.0)
	stage.size = Vector2(BattleStage3D.DEFAULT_VIEWPORT_SIZE)
	add_child(stage)
	_battle_stage_cache = stage


func _get_preloaded_scene(scene_path: String) -> PackedScene:
	var cached_scene: Variant = _scene_cache.get(scene_path, null)
	return cached_scene as PackedScene


func _show_transition_cover() -> void:
	_ensure_transition_cover()
	_transition_cover.visible = true


func _release_transition_cover(scene_path: String = "", started_us: int = 0) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _transition_cover != null:
		_transition_cover.visible = false
	if started_us > 0:
		WebLoadMetrics.record("scene_transition", (Time.get_ticks_usec() - started_us) / 1000.0, {
			"screen": scene_path.get_file().get_basename(),
		})


func _ensure_transition_cover() -> void:
	if _transition_cover != null:
		return
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "SceneTransitionLayer"
	_transition_layer.layer = 4096
	add_child(_transition_layer)

	_transition_cover = ColorRect.new()
	_transition_cover.name = TRANSITION_COVER_NAME
	_transition_cover.color = Color(0.006, 0.010, 0.016, 0.98)
	_transition_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_transition_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_cover.visible = false
	_transition_layer.add_child(_transition_cover)


func _ensure_gold_popup_layer() -> void:
	if _gold_popup_layer != null:
		return
	_gold_popup_layer = CanvasLayer.new()
	_gold_popup_layer.name = "GoldDeltaPopupLayer"
	_gold_popup_layer.layer = 4095
	add_child(_gold_popup_layer)


func _make_gold_popup_style(positive: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.035, 0.012, 0.92) if positive else Color(0.06, 0.018, 0.014, 0.92)
	style.border_color = Color(1.0, 0.78, 0.26, 0.92) if positive else Color(1.0, 0.36, 0.26, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 4.0)
	return style
