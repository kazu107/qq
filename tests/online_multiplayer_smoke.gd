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
	if room_code_edit == null or not room_code_edit.visible or upnp_check == null or upnp_check.visible:
		_fail("Online smoke failed: online connection controls were missing")
		return
	if discovered_list == null or discovered_list.visible:
		_fail("Online smoke failed: LAN discovery was visible online")
		return
	lobby.queue_free()
	await get_tree().process_frame

	if not ClassDB.class_exists("EOSMultiplayerPeer") or not ClassDB.class_has_method("EOSP2P", "set_relay_control", true):
		_fail("Online smoke failed: EOS Relay transport was unavailable")
		return

	print("Online multiplayer smoke passed: proof=%s transport=EOS" % proof.left(10))
	get_tree().quit()


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	if NetworkManager.is_session_connected():
		NetworkManager.leave_session("online_smoke_failed")
	get_tree().quit(1)
