extends Node

signal state_changed(state: String, message: String)

const PRODUCT_CONFIG_PATH: String = "res://config/eos_product.cfg"
const LOCAL_CREDENTIALS_PATH: String = "res://config/eos_credentials.local.cfg"
const LOBBY_BUCKET_ID: String = "qq-arena-p2p-v1"
const ATTR_ROOM_PROOF: String = "QQ_ROOM_PROOF"
const ATTR_SOCKET_ID: String = "QQ_SOCKET_ID"
const ATTR_PROTOCOL: String = "QQ_PROTOCOL"
const ATTR_CONTENT_HASH: String = "QQ_CONTENT_HASH"
const ATTR_STATUS: String = "QQ_STATUS"
const LOBBY_STATUS_OPEN: String = "OPEN"
const SOCKET_ID_LENGTH: int = 32
const SOCKET_ID_PREFIX: String = "qq"
const SOCKET_ID_CHARACTERS: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const LOBBY_SEARCH_ATTEMPTS: int = 8
const LOBBY_SEARCH_RETRY_SECONDS: float = 0.75

var _config: Dictionary = {}
var _state: String = "offline"
var _message: String = "EOS is not initialized."
var _initialized: bool = false
var _authenticating: bool = false
var _epic_account_id: EOSEpicAccountId
var _product_user_id: EOSProductUserId
var _lobby_id: String = ""
var _socket_id: String = ""
var _remote_owner_id: EOSProductUserId


func _ready() -> void:
	call_deferred("_prepare_for_boot_scene")


func _prepare_for_boot_scene() -> void:
	for _attempt in range(5):
		var current_scene: Node = get_tree().current_scene
		if current_scene != null:
			if current_scene.scene_file_path == "res://scenes/boot/Boot.tscn":
				prepare()
			return
		await get_tree().process_frame


func prepare() -> bool:
	if _initialized:
		return true
	_load_configuration()
	if not _has_complete_configuration():
		_set_state("configuration_required", "EOS Client Secret is not configured on this PC.")
		return false

	_set_state("initializing", "Initializing Epic Online Services...")
	var initialize_options: EOSInitializeOptions = EOSInitializeOptions.new()
	initialize_options.product_name = String(_config.get("product_name", "qq"))
	initialize_options.product_version = String(_config.get("product_version", "0.1.0"))
	var initialize_result: EOS.Result = EOS.initialize(initialize_options)
	if initialize_result != EOS.Success and initialize_result != EOS.AlreadyConfigured:
		_set_failure("EOS initialization failed: %s" % EOS.result_to_string(initialize_result))
		return false

	EOS.set_logging_callback(_on_eos_log_message)
	EOS.set_log_level(EOS.LC_ALL_CATEGORIES, EOS.LOG_Warning)

	var platform_options: EOSPlatform_Options = EOSPlatform_Options.new()
	platform_options.product_id = String(_config.get("product_id", ""))
	platform_options.sandbox_id = String(_config.get("sandbox_id", ""))
	platform_options.deployment_id = String(_config.get("deployment_id", ""))
	platform_options.client_credentials = EOSPlatform_ClientCredentials.new()
	platform_options.client_credentials.client_id = String(_config.get("client_id", ""))
	platform_options.client_credentials.client_secret = String(_config.get("client_secret", ""))
	platform_options.encryption_key = String(_config.get("encryption_key", ""))
	platform_options.flags = EOSPlatform.PF_DISABLE_OVERLAY
	platform_options.tick_budget_in_milliseconds = 2
	EOSPlatform.platform_create(platform_options)

	var relay_result: EOS.Result = EOSP2P.set_relay_control(EOSP2P.RC_ForceRelays)
	if relay_result != EOS.Success:
		_set_failure("EOS Relay could not be enabled: %s" % EOS.result_to_string(relay_result))
		return false

	_initialized = true
	_set_state("ready", "EOS Relay is ready.")
	return true


func ensure_authenticated() -> bool:
	if is_authenticated():
		return true
	while _authenticating:
		await get_tree().process_frame
		if is_authenticated():
			return true
	if not prepare():
		return false

	_authenticating = true
	var connect_credentials: EOSConnect_Credentials = EOSConnect_Credentials.new()
	var login_info: EOSConnect_UserLoginInfo = EOSConnect_UserLoginInfo.new()
	var developer_login: Dictionary = _get_developer_login()
	if not developer_login.is_empty():
		_set_state("authenticating", "Signing in through EOS DevAuthTool...")
		var auth_credentials: EOSAuth_Credentials = EOSAuth_Credentials.new()
		auth_credentials.external_type = EOS.ECT_EPIC
		auth_credentials.type = EOSAuth.LCT_Developer
		auth_credentials.id = String(developer_login.get("url", "localhost:8081"))
		auth_credentials.token = String(developer_login.get("token", ""))
		var auth_result: EOSAuth_LoginCallbackInfo = await EOSAuth.login(
			auth_credentials,
			EOSAuth.AS_BasicProfile,
			0
		)
		if auth_result.result_code != EOS.Success:
			_authenticating = false
			_set_failure("EOS developer sign-in failed: %s" % EOS.result_to_string(auth_result.result_code))
			return false
		_epic_account_id = auth_result.local_user_id

		var id_token: EOSAuth_IdToken = EOSAuth.copy_id_token(_epic_account_id)
		if not is_instance_valid(id_token):
			_authenticating = false
			_set_failure("EOS could not create an Epic ID token for DevAuthTool.")
			return false
		connect_credentials.type = EOS.ECT_EPIC_ID_TOKEN
		connect_credentials.token = id_token.json_web_token
	else:
		_set_state("authenticating", "Preparing an anonymous EOS device session...")
		var device_id_result: EOS.Result = await EOSConnect.create_device_id(_build_device_model())
		if device_id_result != EOS.Success and device_id_result != EOS.DuplicateNotAllowed:
			_authenticating = false
			_set_failure("EOS Device ID creation failed: %s" % EOS.result_to_string(device_id_result))
			return false
		connect_credentials.type = EOS.ECT_DEVICEID_ACCESS_TOKEN
		login_info.display_name = _build_device_display_name()

	var connect_result: EOSConnect_LoginCallbackInfo = await EOSConnect.login(connect_credentials, login_info)
	if connect_result.result_code == EOS.InvalidUser:
		var create_result: EOSConnect_CreateUserCallbackInfo = await EOSConnect.create_user(connect_result.continuance_token)
		if create_result.result_code != EOS.Success:
			_authenticating = false
			_set_failure("EOS product user creation failed: %s" % EOS.result_to_string(create_result.result_code))
			return false
		_product_user_id = create_result.local_user_id
	elif connect_result.result_code == EOS.Success:
		_product_user_id = connect_result.local_user_id
	else:
		_authenticating = false
		_set_failure("EOS Connect sign-in failed: %s" % EOS.result_to_string(connect_result.result_code))
		return false

	_authenticating = false
	_set_state("authenticated", "EOS connection is ready. Relay matchmaking is available.")
	return true


func create_room(room_proof: String) -> Dictionary:
	var authenticated: bool = await ensure_authenticated()
	if not authenticated:
		return _failure_result("authentication_failed")
	await leave_room()

	_set_state("creating_lobby", "Creating an EOS Relay lobby...")
	var options: EOSLobby_CreateLobbyOptions = EOSLobby_CreateLobbyOptions.new()
	options.max_lobby_members = LanProtocol.MAX_PLAYERS
	options.permission_level = EOSLobby.LPL_PUBLICADVERTISED
	options.presence_enabled = false
	options.allow_invites = false
	options.bucket_id = LOBBY_BUCKET_ID
	options.disable_host_migration = true
	options.enable_rtc_room = false
	var create_result: EOSLobby_CreateLobbyCallbackInfo = await EOSLobby.create_lobby(options)
	if create_result.result_code != EOS.Success:
		return _lobby_failure("lobby_create_failed", create_result.result_code)

	_lobby_id = create_result.lobby_id
	_socket_id = _build_socket_id(_lobby_id)
	var attributes: Dictionary = {
		ATTR_ROOM_PROOF: room_proof,
		ATTR_SOCKET_ID: _socket_id,
		ATTR_PROTOCOL: str(LanProtocol.PROTOCOL_VERSION),
		ATTR_CONTENT_HASH: LanProtocol.build_content_hash(),
		ATTR_STATUS: LOBBY_STATUS_OPEN,
	}
	var update_error: String = await _set_lobby_attributes(attributes)
	if update_error != "":
		await EOSLobby.destroy_lobby(_lobby_id)
		_clear_room_state()
		_set_failure(update_error)
		return _failure_result("lobby_update_failed")
	print("EOS lobby created and advertised; opening the Relay socket.")

	var peer: EOSMultiplayerPeer = EOSMultiplayerPeer.new()
	peer.set_auto_accept_connection_requests(true)
	peer.set_allow_delayed_delivery(true)
	var peer_error: Error = peer.create_server(_socket_id)
	if peer_error != OK:
		await EOSLobby.destroy_lobby(_lobby_id)
		_clear_room_state()
		_set_failure("EOS Relay server creation failed: %s (error %d)." % [error_string(peer_error), peer_error])
		return _failure_result("peer_create_failed")

	print("EOS Relay host socket is ready.")
	_set_state("lobby", "EOS Relay lobby created.")
	return {
		"ok": true,
		"peer": peer,
		"lobby_id": _lobby_id,
		"socket_id": _socket_id,
	}


func join_room(room_proof: String) -> Dictionary:
	var authenticated: bool = await ensure_authenticated()
	if not authenticated:
		return _failure_result("authentication_failed")
	await leave_room()

	var search_result: Dictionary = await _find_compatible_lobby(room_proof)
	if not bool(search_result.get("ok", false)):
		_set_failure(String(search_result.get("message", "EOS lobby search failed.")))
		return _failure_result(String(search_result.get("error", "lobby_search_failed")))
	var selected_details: EOSLobbyDetails = search_result.get("details") as EOSLobbyDetails
	if not is_instance_valid(selected_details):
		_set_failure("EOS returned an invalid lobby search result.")
		return _failure_result("room_not_found")

	var socket_id: String = String(_get_lobby_attribute(selected_details, ATTR_SOCKET_ID))
	var owner_id: EOSProductUserId = selected_details.get_lobby_owner()
	if socket_id == "" or not is_instance_valid(owner_id):
		_set_failure("The EOS lobby did not provide valid host connection details.")
		return _failure_result("invalid_lobby")
	if owner_id == _product_user_id:
		_set_failure("Host and client are using the same EOS identity. Use different PCs or Windows profiles, or separate DevAuthTool credentials for a same-PC test.")
		return _failure_result("same_eos_identity")

	var join_options: EOSLobby_JoinLobbyOptions = EOSLobby_JoinLobbyOptions.new()
	join_options.lobby_details = selected_details
	join_options.presence_enabled = false
	var join_result: EOSLobby_JoinLobbyCallbackInfo = await EOSLobby.join_lobby(join_options)
	if join_result.result_code != EOS.Success:
		return _lobby_failure("lobby_join_failed", join_result.result_code)

	_lobby_id = join_result.lobby_id
	_socket_id = socket_id
	_remote_owner_id = owner_id
	var peer: EOSMultiplayerPeer = create_reconnect_peer()
	if peer == null:
		await EOSLobby.leave_lobby(_lobby_id)
		_clear_room_state()
		return _failure_result("peer_create_failed")

	print("EOS Relay lobby joined; client socket is ready.")
	_set_state("lobby", "Connected through EOS Relay.")
	return {
		"ok": true,
		"peer": peer,
		"lobby_id": _lobby_id,
		"socket_id": _socket_id,
	}


func create_reconnect_peer() -> EOSMultiplayerPeer:
	if _socket_id == "" or not is_instance_valid(_remote_owner_id):
		_set_failure("EOS reconnect details are unavailable.")
		return null
	var peer: EOSMultiplayerPeer = EOSMultiplayerPeer.new()
	peer.set_allow_delayed_delivery(true)
	var peer_error: Error = peer.create_client(_socket_id, _remote_owner_id)
	if peer_error != OK:
		_set_failure("EOS Relay client creation failed: %s (error %d)." % [error_string(peer_error), peer_error])
		return null
	return peer


func leave_room() -> void:
	if _lobby_id == "" or not is_authenticated():
		_clear_room_state()
		return
	var departing_lobby_id: String = _lobby_id
	var details: EOSLobbyDetails = EOSLobby.copy_lobby_details(departing_lobby_id)
	if is_instance_valid(details) and details.get_lobby_owner() == _product_user_id:
		await EOSLobby.destroy_lobby(departing_lobby_id)
	else:
		await EOSLobby.leave_lobby(departing_lobby_id)
	_clear_room_state()
	_set_state("authenticated", "EOS connection is ready. Relay matchmaking is available.")


func leave_room_deferred() -> void:
	leave_room()


func is_initialized() -> bool:
	return _initialized


func is_authenticated() -> bool:
	return is_instance_valid(_product_user_id)


func is_configured() -> bool:
	if _config.is_empty():
		_load_configuration()
	return _has_complete_configuration()


func get_state() -> String:
	return _state


func get_status_message() -> String:
	return _message


func get_lobby_id() -> String:
	return _lobby_id


func _set_lobby_attributes(attributes: Dictionary) -> String:
	var modification: EOSLobbyModification = EOSLobby.update_lobby_modification(_lobby_id)
	if not is_instance_valid(modification):
		return "EOS lobby modification could not be created."
	for raw_key in attributes.keys():
		var key: String = String(raw_key)
		var attribute: EOSLobby_AttributeData = EOSLobby_AttributeData.new()
		attribute.key = key
		attribute.value = attributes.get(raw_key)
		var add_result: EOS.Result = modification.add_attribute(attribute, EOSLobby.LAT_PUBLIC)
		if add_result != EOS.Success:
			return "EOS lobby attribute '%s' failed: %s" % [key, EOS.result_to_string(add_result)]
	var update_result: EOSLobby_UpdateLobbyCallbackInfo = await EOSLobby.update_lobby(modification)
	if update_result.result_code != EOS.Success:
		return "EOS lobby update failed: %s" % EOS.result_to_string(update_result.result_code)
	return ""


func _get_lobby_attribute(details: EOSLobbyDetails, key: String) -> Variant:
	var attribute: EOSLobby_Attribute = details.copy_attribute_by_key(key)
	if not is_instance_valid(attribute) or not is_instance_valid(attribute.data):
		return null
	return attribute.data.value


func _find_compatible_lobby(room_proof: String) -> Dictionary:
	var last_find_result: EOS.Result = EOS.NotFound
	var compatible_candidate_seen: bool = false
	for attempt in range(LOBBY_SEARCH_ATTEMPTS):
		_set_state("searching_lobby", "Searching for the EOS Relay lobby... (%d/%d)" % [attempt + 1, LOBBY_SEARCH_ATTEMPTS])
		var search: EOSLobbySearch = EOSLobby.create_lobby_search(10)
		if not is_instance_valid(search):
			return {
				"ok": false,
				"error": "search_create_failed",
				"message": "EOS lobby search could not be created.",
			}
		var room_parameter: EOSLobby_AttributeData = EOSLobby_AttributeData.new()
		room_parameter.key = ATTR_ROOM_PROOF
		room_parameter.value = room_proof
		var parameter_result: EOS.Result = search.set_parameter(room_parameter, EOS.CO_EQUAL)
		if parameter_result != EOS.Success:
			return {
				"ok": false,
				"error": "search_parameter_failed",
				"message": "EOS lobby search parameter failed: %s" % EOS.result_to_string(parameter_result),
			}

		last_find_result = await search.find()
		var search_result_count: int = search.get_search_result_count() if last_find_result == EOS.Success else 0
		print("EOS lobby search attempt %d/%d: result=%s candidates=%d" % [
			attempt + 1,
			LOBBY_SEARCH_ATTEMPTS,
			EOS.result_to_string(last_find_result),
			search_result_count,
		])
		if last_find_result == EOS.Success:
			for index in range(search_result_count):
				var details: EOSLobbyDetails = search.copy_search_result_by_index(index)
				if not is_instance_valid(details):
					continue
				if String(_get_lobby_attribute(details, ATTR_ROOM_PROOF)) != room_proof:
					continue
				compatible_candidate_seen = true
				if String(_get_lobby_attribute(details, ATTR_STATUS)) != LOBBY_STATUS_OPEN:
					continue
				if String(_get_lobby_attribute(details, ATTR_PROTOCOL)) != str(LanProtocol.PROTOCOL_VERSION):
					continue
				if String(_get_lobby_attribute(details, ATTR_CONTENT_HASH)) != LanProtocol.build_content_hash():
					continue
				return {"ok": true, "details": details}

		if attempt + 1 < LOBBY_SEARCH_ATTEMPTS:
			await get_tree().create_timer(LOBBY_SEARCH_RETRY_SECONDS).timeout

	var message: String
	if last_find_result != EOS.Success:
		message = "EOS lobby search failed after retries: %s" % EOS.result_to_string(last_find_result)
	elif compatible_candidate_seen:
		message = "A lobby was found, but its game version or data does not match this client."
	else:
		message = "No active EOS lobby was found. Keep the host lobby open, wait a few seconds, and confirm both players use different EOS device identities."
	return {
		"ok": false,
		"error": "room_not_found",
		"message": message,
	}


func _load_configuration() -> void:
	_config.clear()
	_merge_config_file(PRODUCT_CONFIG_PATH)
	_merge_config_file(LOCAL_CREDENTIALS_PATH)
	var environment_secret: String = OS.get_environment("QQ_EOS_CLIENT_SECRET")
	if environment_secret != "":
		_config["client_secret"] = environment_secret


func _merge_config_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var config_file: ConfigFile = ConfigFile.new()
	if config_file.load(path) != OK:
		return
	if not config_file.has_section("eos"):
		return
	for raw_key in config_file.get_section_keys("eos"):
		var key: String = String(raw_key)
		_config[key] = config_file.get_value("eos", key, "")


func _has_complete_configuration() -> bool:
	for key in ["product_id", "sandbox_id", "deployment_id", "client_id", "client_secret", "encryption_key"]:
		if String(_config.get(key, "")).strip_edges() == "":
			return false
	return String(_config.get("encryption_key", "")).length() == 64


func _get_developer_login() -> Dictionary:
	var url: String = OS.get_environment("QQ_EOS_DEV_AUTH_URL")
	var token: String = OS.get_environment("QQ_EOS_DEV_AUTH_TOKEN")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--eos-dev-auth-url="):
			url = argument.trim_prefix("--eos-dev-auth-url=")
		elif argument.begins_with("--eos-dev-auth-token="):
			token = argument.trim_prefix("--eos-dev-auth-token=")
	if token == "":
		return {}
	if url == "":
		url = "localhost:8081"
	return {"url": url, "token": token}


func _build_device_model() -> String:
	return ("%s:%s" % [OS.get_name(), OS.get_model_name()]).left(64)


func _build_device_display_name() -> String:
	var device_seed: String = OS.get_unique_id()
	if device_seed.is_empty():
		device_seed = "%s:%s" % [OS.get_name(), OS.get_model_name()]
	return ("qq-" + device_seed.sha256_text()).left(EOSConnect.CONNECT_USERLOGININFO_DISPLAYNAME_MAX_LENGTH)


func _build_socket_id(lobby_id: String) -> String:
	var socket_id: String = (SOCKET_ID_PREFIX + lobby_id.sha256_text()).left(SOCKET_ID_LENGTH)
	assert(_is_valid_socket_id(socket_id), "Generated EOS socket ID is invalid.")
	return socket_id


func _is_valid_socket_id(socket_id: String) -> bool:
	if socket_id.is_empty() or socket_id.length() > SOCKET_ID_LENGTH:
		return false
	for index in range(socket_id.length()):
		if SOCKET_ID_CHARACTERS.find(socket_id.substr(index, 1)) < 0:
			return false
	return true


func _lobby_failure(code: String, result_code: EOS.Result) -> Dictionary:
	_set_failure("EOS lobby operation failed: %s" % EOS.result_to_string(result_code))
	return _failure_result(code)


func _failure_result(code: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"message": _message,
	}


func _clear_room_state() -> void:
	_lobby_id = ""
	_socket_id = ""
	_remote_owner_id = null


func _set_failure(message: String) -> void:
	_set_state("failed", message)


func _set_state(state: String, message: String) -> void:
	_state = state
	_message = message
	state_changed.emit(_state, _message)


static func _on_eos_log_message(category: String, message: String, level: EOS.LogLevel) -> void:
	if level == EOS.LOG_Error or level == EOS.LOG_Fatal:
		printerr("EOS [%s] %s" % [category, message])
	elif level == EOS.LOG_Warning:
		print("EOS WARNING [%s] %s" % [category, message])
	elif OS.is_debug_build():
		print("EOS [%s] %s" % [category, message])
