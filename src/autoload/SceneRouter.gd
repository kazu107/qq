extends Node

const TITLE_SCENE := "res://scenes/title/Title.tscn"
const HUB_SCENE := "res://scenes/hub/Hub.tscn"
const RUN_SETUP_SCENE := "res://scenes/run_setup/RunSetup.tscn"
const ARENA_SCENE := "res://scenes/arena/Arena.tscn"
const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const REWARD_SCENE := "res://scenes/reward/Reward.tscn"
const RESULT_SCENE := "res://scenes/result/RunResult.tscn"
const MAP_SCENE := "res://scenes/map/Map.tscn"
const FACILITY_SCENE := "res://scenes/facility/Facility.tscn"
const META_SCENE := "res://scenes/meta/MetaProgress.tscn"
const CARD_LIBRARY_SCENE := "res://scenes/library/CardLibrary.tscn"
const SETTINGS_SCENE := "res://scenes/settings/Settings.tscn"
const REPLAY_SCENE := "res://scenes/replay/ReplayViewer.tscn"
const TRANSITION_COVER_NAME := "SceneTransitionCover"
const GOLD_DELTA_POPUP_NAME := "GoldDeltaPopup"

var _transition_layer: CanvasLayer
var _transition_cover: ColorRect
var _gold_popup_layer: CanvasLayer
var _gold_popup_index: int = 0
var _scene_cache: Dictionary = {}


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
	]
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


func go_to_continue_target() -> void:
	match Game.current_screen_hint:
		"hub":
			go_to_hub()
		"run_setup":
			go_to_run_setup()
		"arena":
			go_to_arena()
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
			go_to_title()


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
	AudioManager.play_sfx("ui_page")
	_show_transition_cover()
	var current_scene: CanvasItem = get_tree().current_scene as CanvasItem
	if current_scene != null:
		current_scene.visible = false
	var packed_scene: PackedScene = _get_preloaded_scene(scene_path)
	if packed_scene != null:
		get_tree().change_scene_to_packed(packed_scene)
	else:
		get_tree().change_scene_to_file(scene_path)
	call_deferred("_release_transition_cover")


func _get_preloaded_scene(scene_path: String) -> PackedScene:
	var cached_scene: Variant = _scene_cache.get(scene_path, null)
	return cached_scene as PackedScene


func _show_transition_cover() -> void:
	_ensure_transition_cover()
	_transition_cover.visible = true


func _release_transition_cover() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _transition_cover != null:
		_transition_cover.visible = false


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
