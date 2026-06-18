extends Node

const TITLE_SCENE := "res://scenes/title/Title.tscn"
const HUB_SCENE := "res://scenes/hub/Hub.tscn"
const RUN_SETUP_SCENE := "res://scenes/run_setup/RunSetup.tscn"
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

var _transition_layer: CanvasLayer
var _transition_cover: ColorRect

func go_to_title() -> void:
	_change_scene(TITLE_SCENE)


func go_to_hub() -> void:
	_change_scene(HUB_SCENE)


func go_to_run_setup() -> void:
	_change_scene(RUN_SETUP_SCENE)


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


func _change_scene(scene_path: String) -> void:
	AudioManager.play_sfx("ui_page")
	_show_transition_cover()
	var current_scene: CanvasItem = get_tree().current_scene as CanvasItem
	if current_scene != null:
		current_scene.visible = false
	get_tree().change_scene_to_file(scene_path)
	call_deferred("_release_transition_cover")


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
