extends Node

signal state_changed(state: String, message: String)

const DISABLED_MESSAGE: String = "Online multiplayer is temporarily disabled. LAN multiplayer remains available."


func _ready() -> void:
	state_changed.emit("disabled", DISABLED_MESSAGE)


func prepare() -> bool:
	return false


func ensure_authenticated() -> bool:
	return false


func is_authenticated() -> bool:
	return false


func create_room(_room_proof: String) -> Dictionary:
	return _disabled_result()


func join_room(_room_proof: String) -> Dictionary:
	return _disabled_result()


func create_reconnect_peer() -> MultiplayerPeer:
	return null


func leave_room() -> void:
	pass


func leave_room_deferred() -> void:
	pass


func get_state() -> String:
	return "disabled"


func get_status_message() -> String:
	return DISABLED_MESSAGE


func _disabled_result() -> Dictionary:
	return {
		"ok": false,
		"error": "online_disabled",
		"message": DISABLED_MESSAGE,
	}
