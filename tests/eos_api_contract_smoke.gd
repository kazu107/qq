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
	"EOSConnect": ["login", "create_user"],
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
