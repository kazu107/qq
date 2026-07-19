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
	NetworkManager._match_payload = {
		"protocol_version": LanProtocol.PROTOCOL_VERSION,
		"content_hash": LanProtocol.build_content_hash(),
		"match_id": "spectator-smoke",
		"player_run": first_run.to_dict(),
		"enemy_run": second_run.to_dict(),
		"player_name": "Alpha",
		"enemy_name": "Beta",
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
	battle.queue_free()
	await get_tree().process_frame
	NetworkManager._clear_session(false)
	print("Spectator battle smoke passed: read-only battle view")
	get_tree().quit()


func _fail(message: String) -> void:
	push_error(message)
	NetworkManager._clear_session(false)
	get_tree().quit(1)
