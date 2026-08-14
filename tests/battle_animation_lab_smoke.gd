extends Node

const LAB_SCENE: PackedScene = preload("res://scenes/debug/BattleAnimationLab.tscn")

var _previous_developer_mode: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	_previous_developer_mode = Game.is_developer_mode_enabled()
	Game.settings["developer_mode"] = true
	call_deferred("_run")


func _run() -> void:
	var lab: Control = LAB_SCENE.instantiate() as Control
	if lab == null:
		_fail("Battle animation lab smoke failed: scene could not be instantiated")
		return
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame

	var stage: BattleStage3D = lab.find_child("BattleAnimationLabStage", true, false) as BattleStage3D
	var player_option: OptionButton = lab.find_child("BattleAnimationLabPlayerModel", true, false) as OptionButton
	var enemy_option: OptionButton = lab.find_child("BattleAnimationLabEnemyModel", true, false) as OptionButton
	var action_option: OptionButton = lab.find_child("BattleAnimationLabAction", true, false) as OptionButton
	var camera_option: OptionButton = lab.find_child("BattleAnimationLabCamera", true, false) as OptionButton
	var speed_slider: HSlider = lab.find_child("BattleAnimationLabSpeed", true, false) as HSlider
	var play_button: Button = lab.find_child("BattleAnimationLabPlay", true, false) as Button
	var status_label: Label = lab.find_child("BattleAnimationLabStatus", true, false) as Label
	if stage == null \
	or player_option == null \
	or enemy_option == null \
	or action_option == null \
	or camera_option == null \
	or speed_slider == null \
	or play_button == null \
	or status_label == null:
		var missing_controls: Array[String] = []
		for expected_name: String in [
			"BattleAnimationLabStage",
			"BattleAnimationLabPlayerModel",
			"BattleAnimationLabEnemyModel",
			"BattleAnimationLabAction",
			"BattleAnimationLabCamera",
			"BattleAnimationLabSpeed",
			"BattleAnimationLabPlay",
			"BattleAnimationLabStatus",
		]:
			if lab.find_child(expected_name, true, false) == null:
				missing_controls.append(expected_name)
		_fail("Battle animation lab smoke failed: missing controls %s (developer mode %s)" % [
			missing_controls,
			Game.is_developer_mode_enabled(),
		])
		return

	var profile_count: int = Database.get_all_battle_visual_profiles().size()
	if player_option.item_count != profile_count \
	or enemy_option.item_count != profile_count \
	or action_option.item_count != 12 \
	or camera_option.item_count != 4:
		_fail("Battle animation lab smoke failed: model or action catalogs were incomplete")
		return
	if String(player_option.get_item_metadata(player_option.selected)) != "balanced" \
	or String(enemy_option.get_item_metadata(enemy_option.selected)) != "scout":
		_fail("Battle animation lab smoke failed: default preview models were not selected")
		return

	var player: BattleActor3D = stage.get_combat_actor("lab_player")
	var enemy: BattleActor3D = stage.get_combat_actor("lab_enemy")
	if player == null or enemy == null:
		_fail("Battle animation lab smoke failed: preview actors were not configured")
		return
	player._process(0.24)
	enemy._process(0.24)
	if player.get_action_name() != "ready" or enemy.get_action_name() != "ready":
		_fail("Battle animation lab smoke failed: both actors should start in the ready stance")
		return
	if _minimum_hand_forward_depth(player) < 0.18 or _minimum_hand_forward_depth(enemy) < 0.18:
		_fail("Battle animation lab smoke failed: preview hands were behind the chest")
		return

	var battle_camera_position: Vector3 = stage.get_camera_position()
	_select_by_metadata(camera_option, "side")
	camera_option.item_selected.emit(camera_option.selected)
	if stage.get_camera_position().distance_to(battle_camera_position) < 0.5:
		_fail("Battle animation lab smoke failed: camera presets did not move the camera")
		return

	_select_by_metadata(action_option, "block")
	play_button.pressed.emit()
	if player.get_action_name() != "block":
		_fail("Battle animation lab smoke failed: action playback did not target the selected actor")
		return

	speed_slider.value = 0.0
	speed_slider.value_changed.emit(speed_slider.value)
	if not is_equal_approx(player.get_animation_speed_scale(), 0.0) \
	or not is_equal_approx(enemy.get_animation_speed_scale(), 0.0):
		_fail("Battle animation lab smoke failed: playback speed was not applied to both actors")
		return

	var panel := DeveloperPanel.new()
	add_child(panel)
	panel.configure("Developer", [], "")
	if panel.find_child("DevBattleAnimationLab", true, false) == null:
		_fail("Battle animation lab smoke failed: developer panel did not expose the lab")
		return

	Game.settings["developer_mode"] = _previous_developer_mode
	print("BATTLE_ANIMATION_LAB_SMOKE_OK %d models, poses, cameras, and speed controls validated" % profile_count)
	get_tree().quit()


func _minimum_hand_forward_depth(actor: BattleActor3D) -> float:
	var chest_z: float = actor.get_bone_model_position("chest").z
	return minf(
		chest_z - actor.get_bone_model_position("left_hand").z,
		chest_z - actor.get_bone_model_position("right_hand").z
	)


func _select_by_metadata(option: OptionButton, target_id: String) -> void:
	for index in range(option.item_count):
		if String(option.get_item_metadata(index)) == target_id:
			option.select(index)
			return


func _fail(message: String) -> void:
	Game.settings["developer_mode"] = _previous_developer_mode
	push_error(message)
	get_tree().quit(1)
