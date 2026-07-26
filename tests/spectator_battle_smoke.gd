extends Node


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	var first_profile: Dictionary = LanProtocol.build_profile("Alpha", "balanced")
	var second_profile: Dictionary = LanProtocol.build_profile("Beta", "tempo")
	var first_run: RunState = LanProtocol.profile_to_run(first_profile, 1101)
	var second_run: RunState = LanProtocol.profile_to_run(second_profile, 2202)
	NetworkManager._clear_session(false)
	NetworkManager._is_host = true
	NetworkManager._session_scope = NetworkManager.SESSION_SCOPE_ONLINE
	NetworkManager._local_participant_role = LanProtocol.ROLE_PLAYER
	NetworkManager._arena_session_active = true
	NetworkManager._arena_session_id = "spectator-arena"
	NetworkManager._arena_phase = "battle"
	NetworkManager._match_payload = {
		"protocol_version": LanProtocol.PROTOCOL_VERSION,
		"content_hash": LanProtocol.build_content_hash(),
		"match_id": "spectator-smoke",
		"player_run": first_run.to_dict(),
		"enemy_run": second_run.to_dict(),
		"player_name": "Alpha",
		"enemy_name": "Beta",
		"arena_session_id": "spectator-arena",
		"parallel_round": true,
		"peer_sides": {"1": "spectator", "2": "player", "3": "enemy"},
	}
	NetworkManager._match_active = true
	var packed_scene: PackedScene = load("res://scenes/battle/Battle.tscn") as PackedScene
	if packed_scene == null:
		_fail("Spectator battle scene could not be loaded")
		return
	var battle: Control = packed_scene.instantiate() as Control
	add_child(battle)
	await get_tree().process_frame
	var start_button: Button = battle.find_child("BattleStartButton", true, false) as Button
	var ready_count: Label = battle.find_child("BattleReadyCountLabel", true, false) as Label
	if start_button == null or start_button.visible:
		_fail("Spectator could access the battle start button")
		return
	if ready_count == null or ready_count.visible:
		_fail("Spectator battle displayed participant readiness controls")
		return
	if not NetworkManager.is_local_match_spectator() or NetworkManager.can_local_control_match():
		_fail("Spectator network role could issue battle commands")
		return
	NetworkManager._apply_match_finished({
		"match_id": "spectator-smoke",
		"winner": "player",
	})
	NetworkManager._apply_arena_round_results_snapshot({
		"arena_session_id": "spectator-arena",
		"round_index": 0,
		"results": [
			{"match_id": "spectator-smoke", "player_name": "Alpha", "enemy_name": "Beta", "status": "finished", "winner": "player", "player_hp": 30, "player_max_hp": 60, "enemy_hp": 0, "enemy_max_hp": 60},
			{"match_id": "other-match", "player_name": "Gamma", "enemy_name": "Delta", "status": "running"},
		],
		"all_complete": false,
		"standings": [],
		"public_details": [],
	})
	await get_tree().process_frame
	var result_overlay: ColorRect = battle.find_child("ArenaRoundResultsOverlay", true, false) as ColorRect
	var continue_button: Button = battle.find_child("ArenaRoundResultsContinue", true, false) as Button
	if result_overlay == null or not result_overlay.visible:
		_fail("Spectator did not enter the parallel round result window")
		return
	if continue_button == null or continue_button.visible:
		_fail("Continue button appeared before every parallel match finished")
		return
	NetworkManager._apply_arena_round_results_snapshot({
		"arena_session_id": "spectator-arena",
		"round_index": 0,
		"results": [
			{"match_id": "spectator-smoke", "player_name": "Alpha", "enemy_name": "Beta", "status": "finished", "winner": "player", "player_hp": 30, "player_max_hp": 60, "enemy_hp": 0, "enemy_max_hp": 60},
			{"match_id": "other-match", "player_name": "Gamma", "enemy_name": "Delta", "status": "finished", "winner": "enemy", "player_hp": 0, "player_max_hp": 60, "enemy_hp": 22, "enemy_max_hp": 60},
		],
		"all_complete": true,
		"standings": [],
		"public_details": [],
	})
	await get_tree().process_frame
	if not continue_button.visible:
		_fail("Continue button did not appear after every parallel match finished")
		return
	battle.queue_free()
	await get_tree().process_frame
	NetworkManager._clear_session(false)
	await _test_player_result_colors()
	print("Spectator battle smoke passed: read-only battle view")
	get_tree().quit()


func _test_player_result_colors() -> void:
	var first_profile: Dictionary = LanProtocol.build_profile("Alpha", "balanced")
	var second_profile: Dictionary = LanProtocol.build_profile("Beta", "tempo")
	var first_run: RunState = LanProtocol.profile_to_run(first_profile, 3301)
	var second_run: RunState = LanProtocol.profile_to_run(second_profile, 4402)
	NetworkManager._is_host = true
	NetworkManager._session_scope = NetworkManager.SESSION_SCOPE_ONLINE
	NetworkManager._local_participant_role = LanProtocol.ROLE_PLAYER
	NetworkManager._arena_session_active = true
	NetworkManager._arena_session_id = "result-color-arena"
	NetworkManager._arena_phase = "round_result"
	NetworkManager._match_payload = {
		"protocol_version": LanProtocol.PROTOCOL_VERSION,
		"content_hash": LanProtocol.build_content_hash(),
		"match_id": "result-color-match",
		"player_run": first_run.to_dict(),
		"enemy_run": second_run.to_dict(),
		"player_name": "Alpha",
		"enemy_name": "Beta",
		"arena_session_id": "result-color-arena",
		"parallel_round": true,
		"peer_sides": {"1": "player", "2": "enemy"},
	}
	NetworkManager._match_active = false
	NetworkManager._last_match_result = {
		"match_id": "result-color-match",
		"winner": "player",
	}
	NetworkManager._arena_round_results = [
		{
			"match_id": "result-color-match",
			"player_name": "Alpha",
			"enemy_name": "Beta",
			"status": "finished",
			"winner": "player",
			"player_hp": 28,
			"player_max_hp": 60,
			"enemy_hp": 0,
			"enemy_max_hp": 60,
		},
	]
	NetworkManager._arena_round_results_complete = true

	var battle: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control
	add_child(battle)
	await get_tree().process_frame
	var outcome: Label = battle.find_child("ArenaRoundResultsOutcome", true, false) as Label
	if (
		outcome == null
		or not outcome.visible
		or outcome.text != Localization.get_text("online.round_results.local_win", "VICTORY")
		or not outcome.get_theme_color("font_color").is_equal_approx(Color(0.30, 1.0, 0.62, 1.0))
	):
		_fail("Local victory was not displayed in green")
		return

	NetworkManager._last_match_result["winner"] = "enemy"
	battle.call("_refresh_round_results_overlay")
	if (
		outcome.text != Localization.get_text("online.round_results.local_loss", "DEFEAT")
		or not outcome.get_theme_color("font_color").is_equal_approx(Color(1.0, 0.36, 0.32, 1.0))
	):
		_fail("Local defeat was not displayed in red")
		return
	battle.queue_free()
	await get_tree().process_frame
	NetworkManager._clear_session(false)


func _fail(message: String) -> void:
	push_error(message)
	NetworkManager._clear_session(false)
	get_tree().quit(1)
