extends SceneTree

const REQUIRED_CLASSES: Array[String] = [
	"EOSInitializeOptions",
	"EOSPlatform_Options",
	"EOSAuth_Credentials",
	"EOSConnect_Credentials",
	"EOSLobby_CreateLobbyOptions",
	"EOSLobby_AttributeData",
	"EOSLobby_JoinLobbyOptions",
	"EOSLobbySearch",
	"EOSLobbyDetails",
	"EOSLobbyModification",
	"EOSMultiplayerPeer",
]

const REQUIRED_METHODS: Dictionary = {
	"EOSPlatform": ["platform_create", "tick"],
	"EOSAuth": ["login", "copy_id_token"],
	"EOSConnect": ["login", "create_user", "create_device_id"],
	"EOSLobby": ["create_lobby", "create_lobby_search", "join_lobby", "update_lobby_modification"],
	"EOSLobbySearch": ["set_parameter", "find", "copy_search_result_by_index"],
	"EOSLobbyDetails": ["copy_attribute_by_key", "get_lobby_owner"],
	"EOSMultiplayerPeer": ["create_server", "create_client", "get_local_user_id"],
	"EOSP2P": ["set_relay_control", "get_relay_control"],
}


func _initialize() -> void:
	for eos_class_name in REQUIRED_CLASSES:
		if not ClassDB.class_exists(eos_class_name):
			_fail("Missing GD-EOS class: %s" % eos_class_name)
			return
	for raw_owner in REQUIRED_METHODS.keys():
		var owner: String = String(raw_owner)
		for raw_method in Array(REQUIRED_METHODS.get(raw_owner, [])):
			var method_name: String = String(raw_method)
			if not ClassDB.class_has_method(owner, method_name, true):
				_fail("Missing GD-EOS method: %s.%s" % [owner, method_name])
				return
	if EOSP2P.RC_ForceRelays == EOSP2P.RC_NoRelays:
		_fail("GD-EOS relay control enum is invalid")
		return
	if EOSLobby.LPL_PUBLICADVERTISED == EOSLobby.LPL_INVITEONLY:
		_fail("GD-EOS lobby permission enum is invalid")
		return
	if EOS.ECT_DEVICEID_ACCESS_TOKEN == EOS.ECT_EPIC_ID_TOKEN:
		_fail("EOS Device ID credential enum is invalid")
		return
	var eos_service_source: String = FileAccess.get_file_as_string("res://src/autoload/EosService.gd")
	if eos_service_source.contains("LCT_AccountPortal"):
		_fail("EOS Account Portal login must not be used by the normal online flow")
		return
	var eos_service_script: Script = load("res://src/autoload/EosService.gd") as Script
	var eos_service: Node = eos_service_script.new() as Node
	var device_model: String = String(eos_service.call("_build_device_model"))
	var device_display_name: String = String(eos_service.call("_build_device_display_name"))
	if device_model.is_empty() or device_model.length() > 64:
		_fail("EOS Device ID model is invalid")
		return
	if device_display_name.is_empty() or device_display_name.length() > EOSConnect.CONNECT_USERLOGININFO_DISPLAYNAME_MAX_LENGTH:
		_fail("EOS Device ID display name is invalid")
		return
	var socket_id: String = String(eos_service.call("_build_socket_id", "lobby-id:with_symbols"))
	var socket_id_is_valid: bool = bool(eos_service.call("_is_valid_socket_id", socket_id))
	var underscore_is_rejected: bool = not bool(eos_service.call("_is_valid_socket_id", "qq_invalid"))
	var overlength_is_rejected: bool = not bool(eos_service.call("_is_valid_socket_id", "q".repeat(33)))
	eos_service.free()
	if not socket_id_is_valid or not underscore_is_rejected or not overlength_is_rejected or socket_id.length() != 32:
		_fail("Generated EOS socket ID is incompatible with GD-EOS")
		return

	var config: ConfigFile = ConfigFile.new()
	if config.load("res://config/eos_product.cfg") != OK:
		_fail("EOS product configuration could not be loaded")
		return
	for key in ["product_id", "sandbox_id", "deployment_id", "client_id"]:
		if String(config.get_value("eos", key, "")).strip_edges() == "":
			_fail("EOS product configuration is missing: %s" % key)
			return

	print("EOS_API_CONTRACT_OK classes=%d relay=ForceRelays" % REQUIRED_CLASSES.size())
	quit()


func _fail(message: String) -> void:
	push_error("EOS API contract smoke failed: %s" % message)
	quit(1)
