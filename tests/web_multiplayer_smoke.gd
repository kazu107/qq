extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
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
	var ready_count: Label = web_lobby.find_child("OnlineLobbyReadyCount", true, false) as Label
	if room_list == null or not room_list.visible:
		_fail("Compatible Web rooms are not exposed in the online lobby")
		return
	if (
		create_target == null
		or lobby_target == null
		or int(create_target.min_value) != NetworkManager.ONLINE_MIN_TARGET_WINS
		or int(create_target.max_value) != NetworkManager.ONLINE_MAX_TARGET_WINS
	):
		_fail("First-to-X room controls are missing or invalid")
		return
	if ready_count == null:
		_fail("Lobby readiness count is missing")
		return
	if (
		not network_source.contains('"target_wins": _online_target_wins')
		or not network_source.contains("player_run.arena_target_wins = _online_target_wins")
		or not network_source.contains("player_run.arena_max_losses = _online_target_wins + 1")
	):
		_fail("Online first-to-X rules are not synchronized into arena runs")
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
