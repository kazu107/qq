extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	call_deferred("_run")


func _run() -> void:
	var sanitized_code: String = LanProtocol.sanitize_online_room_code(" ab-12!z ")
	if sanitized_code != "AB12Z":
		_fail("Online smoke failed: room code sanitization was invalid")
		return
	var proof: String = LanProtocol.build_online_room_proof(sanitized_code)
	if proof.length() != 64 or proof == LanProtocol.build_online_room_proof("OTHER"):
		_fail("Online smoke failed: room proof was invalid")
		return
	if LanProtocol.generate_online_room_code().length() != LanProtocol.ONLINE_ROOM_CODE_LENGTH:
		_fail("Online smoke failed: generated room code length was invalid")
		return

	var packed_scene: PackedScene = load("res://scenes/online/OnlineLobby.tscn") as PackedScene
	if packed_scene == null:
		_fail("Online smoke failed: online lobby scene could not be loaded")
		return
	var lobby: Control = packed_scene.instantiate() as Control
	add_child(lobby)
	await get_tree().process_frame
	var room_code_edit: LineEdit = lobby.find_child("OnlineRoomCodeEdit", true, false) as LineEdit
	var upnp_check: CheckButton = lobby.find_child("OnlineAutomaticUpnpCheck", true, false) as CheckButton
	var discovered_list: ItemList = lobby.find_child("LanDiscoveredList", true, false) as ItemList
	var create_target_wins_spin: SpinBox = lobby.find_child("OnlineTargetWinsSpin", true, false) as SpinBox
	var lobby_target_wins_spin: SpinBox = lobby.find_child("OnlineLobbyTargetWinsSpin", true, false) as SpinBox
	var max_players_spin: SpinBox = lobby.find_child("OnlineLobbyMaxPlayersSpin", true, false) as SpinBox
	var spectator_check: CheckButton = lobby.find_child("OnlineJoinAsSpectatorCheck", true, false) as CheckButton
	var participant_role_option: OptionButton = lobby.find_child("OnlineParticipantRoleOption", true, false) as OptionButton
	var expected_rule_controls: Dictionary = {
		"OnlineInitialGoldSpin": ArenaService.INITIAL_GOLD,
		"OnlineInitialMaxHpSpin": ArenaService.INITIAL_MAX_HP,
		"OnlineSpecialRewardIntervalSpin": ArenaService.SPECIAL_REWARD_INTERVAL,
		"OnlineShopPricePercentSpin": 100,
		"OnlineRerollCostSpin": ArenaService.REROLL_COST,
		"OnlineShopOfferCountSpin": ArenaService.SHOP_OFFER_COUNT,
	}
	if room_code_edit == null or not room_code_edit.visible or upnp_check == null or upnp_check.visible:
		_fail("Online smoke failed: online connection controls were missing")
		return
	if discovered_list == null or not discovered_list.visible:
		_fail("Online smoke failed: Web room directory was not visible")
		return
	if create_target_wins_spin != null:
		_fail("Online smoke failed: first-to-X was editable before room creation")
		return
	if lobby_target_wins_spin == null or int(lobby_target_wins_spin.value) != ArenaService.TARGET_WINS:
		_fail("Online smoke failed: lobby first-to-X room rule control was missing")
		return
	if max_players_spin == null or int(max_players_spin.value) != LanProtocol.DEFAULT_PLAYERS or spectator_check == null or participant_role_option == null or participant_role_option.item_count != 2:
		_fail("Online smoke failed: multiplayer capacity or spectator controls were missing")
		return
	for control_name in expected_rule_controls.keys():
		var rule_control: SpinBox = lobby.find_child(String(control_name), true, false) as SpinBox
		if rule_control == null or int(rule_control.value) != int(expected_rule_controls.get(control_name, -1)):
			_fail("Online smoke failed: lobby rule control was missing or invalid: %s" % control_name)
			return
	lobby.queue_free()
	await get_tree().process_frame

	if not Game.WEB_MULTIPLAYER_ENABLED:
		_fail("Online smoke failed: Web multiplayer was disabled")
		return
	if WebRtcSignalingClient.resolve_signaling_url().strip_edges() == "":
		_fail("Online smoke failed: WebRTC signaling URL was unavailable")
		return

	print("Online multiplayer smoke passed: proof=%s transport=WebRTC" % proof.left(10))
	get_tree().quit()


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	if NetworkManager.is_session_connected():
		NetworkManager.leave_session("online_smoke_failed")
	get_tree().quit(1)
