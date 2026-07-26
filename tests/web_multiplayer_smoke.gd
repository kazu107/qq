extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	NetworkManager._arena_details_auto_open_pending = false
	if not Game.WEB_MULTIPLAYER_ENABLED:
		_fail("Web multiplayer feature flag is disabled")
		return
	if Game.supports_lan_multiplayer():
		_fail("LAN multiplayer is still enabled")
		return
	var project_text: String = FileAccess.get_file_as_string("res://project.godot")
	if project_text.find("EosService=") >= 0:
		_fail("EOS autoload is still enabled")
		return
	if not FileAccess.file_exists("res://server/server.js") or not FileAccess.file_exists("res://package.json"):
		_fail("Heroku signaling server files are missing")
		return
	if WebRtcSignalingClient.resolve_signaling_url() != WebRtcSignalingClient.DEFAULT_LOCAL_SIGNALING_URL:
		_fail("Native signaling URL fallback is invalid")
		return
	if LanProtocol.sanitize_online_room_code("ABC123EXTRA") != "ABC123":
		_fail("Web room codes are not constrained to six characters")
		return
	var network_source: String = FileAccess.get_file_as_string("res://src/autoload/NetworkManager.gd")
	if network_source.contains("unreliable_ordered\", 1") or network_source.contains("unreliable\", 3"):
		_fail("WebRTC RPCs must use the default transfer channels")
		return
	var server_source: String = FileAccess.get_file_as_string("res://server/server.js")
	if (
		not server_source.contains('peers: [1], iceServers')
		or not server_source.contains('send(room.peers.get(1), { type: "peer_joined"')
	):
		_fail("WebRTC guests must connect only to the relay host")
		return

	var hub_scene: PackedScene = load("res://scenes/hub/Hub.tscn") as PackedScene
	var web_lobby_scene: PackedScene = load("res://scenes/online/OnlineLobby.tscn") as PackedScene
	if hub_scene == null or web_lobby_scene == null:
		_fail("Hub or Web multiplayer lobby scene could not be loaded")
		return
	var hub: Control = hub_scene.instantiate() as Control
	add_child(hub)
	await get_tree().process_frame
	var web_button: Button = hub.find_child("WebMultiplayerButton", true, false) as Button
	var lan_button: Button = hub.find_child("LanMultiplayerButton", true, false) as Button
	if web_button == null or web_button.disabled:
		_fail("Web multiplayer button is not available")
		return
	if lan_button != null:
		_fail("LAN multiplayer button is still visible")
		return
	var web_lobby: Control = web_lobby_scene.instantiate() as Control
	add_child(web_lobby)
	await get_tree().process_frame
	var room_code_edit: LineEdit = web_lobby.find_child("OnlineRoomCodeEdit", true, false) as LineEdit
	if room_code_edit == null or room_code_edit.max_length != LanProtocol.ONLINE_ROOM_CODE_LENGTH:
		_fail("Web room code input length is inconsistent with the signaling server")
		return
	var room_list: ItemList = web_lobby.find_child("LanDiscoveredList", true, false) as ItemList
	var create_target: SpinBox = web_lobby.find_child("OnlineTargetWinsSpin", true, false) as SpinBox
	var lobby_target: SpinBox = web_lobby.find_child("OnlineLobbyTargetWinsSpin", true, false) as SpinBox
	var max_players: SpinBox = web_lobby.find_child("OnlineLobbyMaxPlayersSpin", true, false) as SpinBox
	var match_gold: SpinBox = web_lobby.find_child("OnlineMatchGoldSpin", true, false) as SpinBox
	var spectator_check: CheckButton = web_lobby.find_child("OnlineJoinAsSpectatorCheck", true, false) as CheckButton
	var participant_role_option: OptionButton = web_lobby.find_child("OnlineParticipantRoleOption", true, false) as OptionButton
	var rules_grid: GridContainer = web_lobby.find_child("OnlineLobbyRulesGrid", true, false) as GridContainer
	var ready_count: Label = web_lobby.find_child("OnlineLobbyReadyCount", true, false) as Label
	var lobby_scroll: ScrollContainer = web_lobby.find_child("OnlineLobbyContentScroll", true, false) as ScrollContainer
	var ready_button: Button = web_lobby.find_child("LanReadyButton", true, false) as Button
	var start_button: Button = web_lobby.find_child("LanStartMatchButton", true, false) as Button
	var leave_button: Button = web_lobby.find_child("LanLeaveButton", true, false) as Button
	var details_button: Button = web_lobby.find_child("OnlineMatchDetailsButton", true, false) as Button
	var details_overlay: ColorRect = web_lobby.find_child("OnlineMatchDetailsOverlay", true, false) as ColorRect
	var details_content: RichTextLabel = web_lobby.find_child("OnlineMatchDetailsContent", true, false) as RichTextLabel
	if room_list == null or not room_list.visible:
		_fail("Compatible Web rooms are not exposed in the online lobby")
		return
	if (
		create_target != null
		or lobby_target == null
		or rules_grid == null
		or rules_grid.get_child_count() != 9
		or max_players == null
		or int(max_players.step) != 2
		or match_gold == null
		or int(match_gold.value) != ArenaService.MATCH_GOLD_BASE
		or int(match_gold.min_value) != NetworkManager.ONLINE_MIN_MATCH_GOLD
		or int(match_gold.max_value) != NetworkManager.ONLINE_MAX_MATCH_GOLD
		or spectator_check == null
		or participant_role_option == null
		or participant_role_option.item_count != 2
		or int(lobby_target.min_value) != NetworkManager.ONLINE_MIN_TARGET_WINS
		or int(lobby_target.max_value) != NetworkManager.ONLINE_MAX_TARGET_WINS
	):
		_fail("First-to-X must only be configurable inside the created lobby")
		return
	if ready_count == null:
		_fail("Lobby readiness count is missing")
		return
	if (
		lobby_scroll == null
		or ready_button == null
		or start_button == null
		or leave_button == null
		or lobby_scroll.is_ancestor_of(ready_button)
		or lobby_scroll.is_ancestor_of(start_button)
		or lobby_scroll.is_ancestor_of(leave_button)
	):
		_fail("Lobby action buttons are still inside the scrolling content")
		return
	if details_button == null or details_overlay == null or details_content == null or details_overlay.visible:
		_fail("Foreground match details modal is not configured")
		return
	NetworkManager._public_lobby_snapshot = {
		"arena_standings": [{"rank": 1, "name": "Alpha", "wins": 1, "losses": 0}],
		"arena_round_results": [{
			"status": "finished",
			"player_name": "Alpha",
			"enemy_name": "Beta",
			"winner": "player",
		}],
		"arena_public_details": [{
			"name": "Alpha",
			"hp": 60,
			"max_hp": 60,
			"gold": 100,
			"wins": 1,
			"losses": 0,
		}],
	}
	NetworkManager.request_arena_details_auto_open()
	web_lobby.call("_on_arena_session_finished", {})
	await get_tree().process_frame
	if not details_overlay.visible or NetworkManager.consume_arena_details_auto_open_request():
		_fail("Match details modal did not open automatically after returning to the lobby")
		return
	if (
		not details_content.text.contains("Alpha")
		or details_content.text.contains(Localization.get_text("online.details.results", "LATEST ROUND"))
	):
		_fail("Match details modal still shows the latest round section")
		return
	if (
		not network_source.contains('"target_wins": _online_target_wins')
		or not network_source.contains('"arena_rules": _build_online_arena_rules()')
		or not network_source.contains('"match_gold": _online_match_gold')
		or not network_source.contains('arena_rules["target_wins"] = _online_target_wins')
		or not network_source.contains("_arena_coordinator.create_run(profile, base_seed + player_index * 7919, arena_rules)")
		or not network_source.contains("ArenaTournamentCoordinator.build_round_pairings")
	):
		_fail("Online lobby rules are not synchronized into arena runs")
		return
	var boot_source: String = FileAccess.get_file_as_string("res://src/ui/screens/BootScreen.gd")
	if not boot_source.contains("SceneRouter.go_to_hub()") or boot_source.contains("SceneRouter.go_to_title()"):
		_fail("Boot flow does not start directly at the Hub")
		return

	hub.queue_free()
	web_lobby.queue_free()
	print("WEB_MULTIPLAYER_SMOKE_OK WebRTC entry and Heroku server configured")
	get_tree().quit()


func _fail(reason: String) -> void:
	push_error("WEB_MULTIPLAYER_SMOKE_FAIL %s" % reason)
	get_tree().quit(1)
