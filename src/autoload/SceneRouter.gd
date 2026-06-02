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
	get_tree().change_scene_to_file(scene_path)
