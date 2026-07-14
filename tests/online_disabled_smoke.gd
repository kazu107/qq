extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if Game.ONLINE_MULTIPLAYER_ENABLED:
		_fail("online feature flag is enabled")
		return
	if FileAccess.file_exists("res://addons/gd-eos/gd-eos.gdextension"):
		_fail("GD-EOS extension is still enabled")
		return
	if not FileAccess.file_exists("res://addons/gd-eos/gd-eos.gdextension.disabled"):
		_fail("disabled GD-EOS configuration is missing")
		return
	if EosService.get_state() != "disabled" or EosService.prepare():
		_fail("EOS service is not using the dependency-free disabled implementation")
		return

	var hub_scene: PackedScene = load("res://scenes/hub/Hub.tscn") as PackedScene
	var lan_scene: PackedScene = load("res://scenes/lan/LanLobby.tscn") as PackedScene
	if hub_scene == null or lan_scene == null:
		_fail("hub or LAN lobby scene could not be loaded")
		return
	var hub: Control = hub_scene.instantiate() as Control
	add_child(hub)
	await get_tree().process_frame
	var online_button: Button = hub.find_child("OnlineMultiplayerButton", true, false) as Button
	var lan_button: Button = hub.find_child("LanMultiplayerButton", true, false) as Button
	if online_button != null:
		_fail("online multiplayer button is still visible")
		return
	if lan_button == null or lan_button.disabled:
		_fail("LAN multiplayer button is not available")
		return

	hub.queue_free()
	print("ONLINE_DISABLED_SMOKE_OK EOS dependency absent; LAN entry available")
	get_tree().quit()


func _fail(reason: String) -> void:
	push_error("ONLINE_DISABLED_SMOKE_FAIL %s" % reason)
	get_tree().quit(1)
