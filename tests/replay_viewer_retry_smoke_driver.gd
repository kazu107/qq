extends Node

var _failed: bool = false
var _engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
var _seed_value: int = 424242


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.set_replay_auto_export_enabled(true)
	call_deferred("_run")


func _run() -> void:
	Game.start_new_run("balanced", _seed_value)
	Game.current_run.player_hp = Game.current_run.max_hp
	Game.current_run.attack += 6
	Game.current_run.speed += 2
	_engine.setup(Game.current_run, "scout")

	await _resolve_battle()
	if _failed:
		return

	var replay_path: String = Game.get_last_replay_export_path()
	if replay_path == "" or not FileAccess.file_exists(replay_path):
		_fail("Replay viewer smoke failed: replay export path was missing")
		return

	if not Game.open_last_replay_view("result"):
		_fail("Replay viewer smoke failed: could not open last replay in viewer")
		return
	get_tree().change_scene_to_file("res://scenes/replay/ReplayViewer.tscn")
	var replay_scene: Node = await _wait_for_scene("ReplayViewer")
	if _failed or replay_scene == null:
		return

	var replay_events: VBoxContainer = replay_scene.find_child("ReplayEvents", true, false) as VBoxContainer
	var replay_title: Label = replay_scene.find_child("ReplayTitle", true, false) as Label
	var replay_retry_button: Button = replay_scene.find_child("ReplayRetrySeedButton", true, false) as Button
	if replay_events == null or replay_events.get_child_count() == 0:
		_fail("Replay viewer smoke failed: replay events were not rendered")
		return
	if replay_title == null or replay_title.text.find("Replay") == -1:
		_fail("Replay viewer smoke failed: replay title was not rendered")
		return
	if replay_retry_button == null or replay_retry_button.disabled:
		_fail("Replay viewer smoke failed: replay retry button should be enabled")
		return

	replay_retry_button.emit_signal("pressed")
	var map_scene: Node = await _wait_for_scene("Map")
	if _failed or map_scene == null:
		return
	if Game.current_run == null or Game.current_run.seed != _seed_value:
		_fail("Replay viewer smoke failed: replay retry did not preserve the original seed")
		return

	Game.current_run.run_complete = true
	Game.current_run.defeated = false
	Game.last_replay_export_path = replay_path
	Game.current_screen_hint = "result"
	SaveManager.save_game("result")
	get_tree().change_scene_to_file("res://scenes/result/RunResult.tscn")
	var result_scene: Node = await _wait_for_scene("RunResult")
	if _failed or result_scene == null:
		return

	var result_replay_button: Button = result_scene.find_child("ResultReplayViewerButton", true, false) as Button
	var result_retry_button: Button = result_scene.find_child("ResultRetrySameSeedButton", true, false) as Button
	if result_replay_button == null or result_replay_button.disabled:
		_fail("Replay viewer smoke failed: result replay button should be enabled")
		return
	if result_retry_button == null or result_retry_button.disabled:
		_fail("Replay viewer smoke failed: result same-seed retry button should be enabled")
		return

	result_replay_button.emit_signal("pressed")
	replay_scene = await _wait_for_scene("ReplayViewer")
	if _failed or replay_scene == null:
		return
	var back_button: Button = replay_scene.find_child("ReplayBackButton", true, false) as Button
	if back_button == null:
		_fail("Replay viewer smoke failed: replay back button was missing")
		return
	back_button.emit_signal("pressed")
	result_scene = await _wait_for_scene("RunResult")
	if _failed or result_scene == null:
		return

	result_retry_button = result_scene.find_child("ResultRetrySameSeedButton", true, false) as Button
	result_retry_button.emit_signal("pressed")
	map_scene = await _wait_for_scene("Map")
	if _failed or map_scene == null:
		return
	if Game.current_run == null or Game.current_run.seed != _seed_value:
		_fail("Replay viewer smoke failed: result retry did not restart the same seed")
		return

	print("Replay viewer smoke passed")
	get_tree().quit()


func _resolve_battle() -> void:
	var elapsed: float = 0.0
	while _engine.battle_state != null and _engine.battle_state.winner == "":
		var battle_state: BattleState = _engine.battle_state
		for runtime_state in battle_state.player.get_sorted_runtime_states():
			if not runtime_state.can_use():
				continue
			var card_def: CardDef = Database.get_card(runtime_state.card_id)
			if card_def == null:
				continue
			if battle_state.player.active_slots_used + card_def.active_slot_cost > battle_state.player.active_slot_max:
				continue
			_engine.request_use_card("player", runtime_state.runtime_id)
			break
		_engine.update(0.2)
		elapsed += 0.2
		if elapsed > 90.0:
			_fail("Replay viewer smoke failed: battle resolution timed out")
			return
		await get_tree().process_frame

	if _engine.battle_state == null:
		_fail("Replay viewer smoke failed: engine did not keep battle state")
		return
	Game.complete_battle(_engine.build_summary())


func _wait_for_scene(scene_name: String) -> Node:
	var timeout_frames: int = 180
	while timeout_frames > 0:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and String(scene.name) == scene_name:
			return scene
		timeout_frames -= 1
	_fail("Replay viewer smoke failed: scene %s did not open" % scene_name)
	return null


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
