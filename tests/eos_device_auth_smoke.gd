extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not await EosService.ensure_authenticated():
		_fail("authentication_failed: %s" % EosService.get_status_message())
		return
	if not EosService.is_authenticated():
		_fail("product_user_missing")
		return

	var room_code: String = "DEVICE%d" % Time.get_ticks_msec()
	var room_result: Dictionary = await EosService.create_room(LanProtocol.build_online_room_proof(room_code))
	if not bool(room_result.get("ok", false)):
		_fail("lobby_create_failed: %s" % String(room_result.get("message", "")))
		return
	var peer: MultiplayerPeer = room_result.get("peer") as MultiplayerPeer
	if peer == null:
		_fail("relay_peer_missing")
		return
	multiplayer.multiplayer_peer = peer
	await get_tree().create_timer(0.5).timeout
	peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	await EosService.leave_room()
	print("EOS_DEVICE_AUTH_SMOKE_OK anonymous lobby lifecycle completed")
	get_tree().quit()


func _fail(reason: String) -> void:
	push_error("EOS_DEVICE_AUTH_SMOKE_FAIL %s" % reason)
	get_tree().quit(1)
