extends Node

signal changed

var initialized: bool = false
var account_id: String = ""
var state: String = "guest"
var remote: Dictionary = {}
var history: Array = []
var _bridge: JavaScriptObject
var _listener: JavaScriptObject
var _writer: String = ""
var _target: String = ""
var _epoch: int = 0
var _busy: bool = false
var _loading: bool = false
var _elapsed: float = 0.0
var _dirty_elapsed: float = 0.0
var _last_save: float = 0.0
var _last_error: String = ""
var _identity_known: bool = false
var _action_pending: bool = false

class Reply extends RefCounted:
	signal completed(data: Dictionary)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		_bridge = JavaScriptBridge.get_interface("qqCloud")
		if _bridge != null:
			_writer = String(_bridge.writerId())
			_listener = JavaScriptBridge.create_callback(_on_action)
			_bridge.subscribe(_listener)
	AccountSession.changed.connect(_on_account)
	SaveManager.profile_saved.connect(_on_saved)


func begin() -> void:
	if _bridge == null or initialized: return
	if OS.has_feature("qq_layout_review") and not bool(_bridge.enableQA()): return
	initialized = true
	for _i: int in 80:
		if AccountSession.snapshot.get("reason", "") != "loading": break
		await get_tree().create_timer(0.1, true).timeout
	_on_account()


func _on_account() -> void:
	if not initialized: return
	var snapshot: Dictionary = AccountSession.snapshot
	if snapshot.get("reason", "") in ["loading", "unavailable", "temporarily_unavailable"]:
		if state in ["ready", "guest", "offline"]: state = "offline" if SaveManager.active_profile != "guest" else "guest"
		publish()
		return
	var owner: String = String(snapshot.get("user", {}).get("id", "")) if snapshot.get("user") is Dictionary and not bool(snapshot.get("needsUsername", false)) else ""
	if _identity_known and owner == _target: return
	_identity_known = true
	_target = owner
	_epoch += 1
	_transition(_epoch, owner)


func _transition(epoch: int, owner: String) -> void:
	_loading = true
	_busy = false
	if owner == "":
		if not _switch_local("guest"):
			_loading = false
			return
		account_id = ""
		state = "guest"
		remote = {}
		_loading = false
		publish()
		return
	account_id = owner
	history = []
	state = "loading"
	publish()
	var response: Dictionary = await request("GET", "/api/cloud/save", {}, owner)
	if epoch != _epoch: return
	_loading = false
	if response.has("error"):
		_last_error = String(response["error"])
		state = "load_error"
		publish()
		return
	remote = response
	var cached: Dictionary = SaveManager.read_profile(owner)
	var metadata: Dictionary = Dictionary(cached.get("settings", {}).get("_cloud_meta", {}))
	if SaveManager.active_profile == owner:
		SaveManager.flush_requested_save()
		metadata = SaveManager.profile_meta
	if metadata.get("pending_request", "") != "" and metadata.get("pending_request", "") == response.get("request_id", ""):
		metadata["revision"] = int(remote["revision"])
		metadata["synced_hash"] = String(metadata.get("pending_hash", ""))
		metadata["dirty"] = JSON.stringify(SaveManager.cloud_payload()).sha256_text() != String(metadata["synced_hash"]) if SaveManager.active_profile == owner else true
	if response.get("payload") == null:
		state = "import_choice"
	elif cached.is_empty() and _has_guest_progress():
		state = "guest_choice"
	elif bool(metadata.get("dirty", false)) and int(metadata.get("revision", 0)) != int(remote["revision"]):
		state = "conflict"
	else:
		await _claim_and_load(false, not bool(metadata.get("dirty", false)), epoch)
		return
	publish()


func request(method: String, path: String, body: Dictionary = {}, owner: String = "") -> Dictionary:
	if _bridge == null: return {"error": "web_only"}
	var reply: Reply = Reply.new()
	var callback: JavaScriptObject = JavaScriptBridge.create_callback(func(arguments: Array) -> void:
		var parsed: Variant = JSON.parse_string(String(arguments[0]))
		reply.completed.emit(Dictionary(parsed) if parsed is Dictionary else {"error": "network_error"})
	)
	_bridge.request(method, path, JSON.stringify(body), account_id if owner == "" else owner, callback)
	return await reply.completed


func _claim_and_load(takeover: bool, use_remote: bool, epoch: int) -> void:
	SaveManager.flush_requested_save()
	state = "loading"
	publish()
	var response: Dictionary = await request("POST", "/api/cloud/claim", {"writer_id": _writer, "device_label": "Web / " + OS.get_name(), "takeover": takeover})
	if epoch != _epoch: return
	if response.has("error"):
		_last_error = String(response["error"])
		state = "device_busy" if response["error"] == "device_busy" else "load_error"
		publish()
		return
	# A claim may race a save from the previous writer. Never silently adopt a new base.
	if not use_remote and int(response["revision"]) != int(remote.get("revision", 0)):
		remote = response
		state = "conflict"
		publish()
		return
	remote = response
	if use_remote:
		if not SaveManager.archive_profile(account_id):
			state = "local_save_error"
			publish()
			return
		if not _switch_local(account_id, Dictionary(remote["payload"])): return
		SaveManager.profile_meta = {"revision": int(remote["revision"])}
		var incoming: Dictionary = SaveManager.cloud_payload(SaveData.from_dict(Dictionary(remote["payload"])))
		var local: Dictionary = SaveManager.cloud_payload(Game.build_save_data("hub"))
		SaveManager.profile_meta["synced_hash"] = JSON.stringify(local if local == incoming else incoming).sha256_text()
	else:
		if not _switch_local(account_id): return
		SaveManager.profile_meta["revision"] = int(remote["revision"])
	state = "ready"
	SaveManager.save_game("hub")
	_refresh_hub()
	publish()
	if bool(SaveManager.profile_meta.get("dirty", false)): sync_now()


func _switch_local(profile: String, replacement: Dictionary = {}) -> bool:
	if SaveManager.active_profile == profile and replacement.is_empty(): return true
	SaveManager.flush_requested_save()
	var previous: SaveData = Game.build_save_data(Game.current_screen_hint)
	if not SaveManager.save_game(Game.current_screen_hint):
		state = "local_save_error"
		publish()
		return false
	Game.stash_active_run_for_hub()
	if not SaveManager.save_game("hub"):
		Game.apply_loaded_save(previous)
		state = "local_save_error"
		publish()
		return false
	if RankedSession.engine != null:
		RankedSession.engine.dispose()
		RankedSession.engine = null
	if NetworkManager.is_session_connected(): NetworkManager.leave_session("account_changed")
	SceneRouter.invalidate_profile_cache()
	if not SaveManager.activate_profile(profile, replacement):
		state = "local_save_error"
		publish()
		return false
	_refresh_hub()
	return true


func _refresh_hub() -> void:
	var scene: Node = get_tree().current_scene
	if scene != null and scene.scene_file_path != "res://scenes/boot/Boot.tscn": SceneRouter.call_deferred("go_to_hub")


func _on_saved(profile: String) -> void:
	if not initialized or _loading or profile != account_id: return
	_last_save = Time.get_ticks_msec() / 1000.0
	_dirty_elapsed = 0.0
	publish()


func _process(delta: float) -> void:
	if not initialized or _bridge == null or _busy or _loading or _action_pending: return
	_elapsed += delta
	_dirty_elapsed += delta
	if state in ["ready", "offline"] and SaveManager.active_profile == account_id and account_id != "":
		if bool(SaveManager.profile_meta.get("dirty", false)) and (_dirty_elapsed > 2.0 or _elapsed > 15.0):
			sync_now()
		elif _elapsed > 15.0:
			_heartbeat()


func _heartbeat() -> void:
	_busy = true
	_elapsed = 0.0
	var epoch: int = _epoch
	var response: Dictionary = await request("POST", "/api/cloud/lease", {"writer_id": _writer})
	if epoch != _epoch: return
	_busy = false
	if response.has("error"):
		_last_error = String(response["error"])
		state = "device_busy" if response["error"] == "lease_lost" else "offline"
		if response["error"] in ["login_required", "account_changed"]: AccountSession.refresh()
	else: state = "ready"
	publish()


func sync_now() -> bool:
	if _busy or _loading or account_id == "" or SaveManager.active_profile != account_id: return false
	_busy = true
	_elapsed = 0.0
	_dirty_elapsed = 0.0
	SaveManager.flush_requested_save()
	var payload: Dictionary = SaveManager.cloud_payload(Game.build_save_data(Game.current_screen_hint))
	var hash: String = JSON.stringify(payload).sha256_text()
	if hash == String(SaveManager.profile_meta.get("synced_hash", "")):
		_busy = false
		return true
	var epoch: int = _epoch
	if SaveManager.profile_meta.get("pending_hash", "") != hash or String(SaveManager.profile_meta.get("pending_request", "")) == "":
		SaveManager.profile_meta["pending_request"] = _uuid()
		SaveManager.profile_meta["pending_hash"] = hash
	SaveManager.save_game(Game.current_screen_hint)
	var response: Dictionary = await request("PUT", "/api/cloud/save", {"writer_id": _writer, "base_revision": int(SaveManager.profile_meta.get("revision", 0)), "request_id": SaveManager.profile_meta["pending_request"], "payload": payload})
	if epoch != _epoch: return false
	_busy = false
	if response.has("error"):
		_last_error = String(response["error"])
		state = "conflict" if response["error"] == "revision_conflict" else "device_busy" if response["error"] == "lease_lost" else "offline"
		if state == "conflict":
			var current: Dictionary = await request("GET", "/api/cloud/save")
			if epoch != _epoch: return false
			if not current.has("error"): remote = current
		if response["error"] in ["login_required", "account_changed"]: AccountSession.refresh()
		publish()
		return false
	remote.merge(response, true)
	SaveManager.profile_meta["revision"] = int(response["revision"])
	SaveManager.profile_meta["synced_hash"] = hash
	SaveManager.profile_meta.erase("pending_request")
	SaveManager.profile_meta.erase("pending_hash")
	SaveManager.finish_guest_import()
	state = "ready"
	SaveManager.save_game(Game.current_screen_hint)
	publish()
	return true


func _uuid() -> String:
	var hex: String = Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


func _has_guest_progress() -> bool:
	var data: Dictionary = SaveManager.read_profile("guest")
	var defaults: Dictionary = Database.meta_progress_template.duplicate(true)
	MetaProgressService.new().ensure_defaults(defaults)
	var meta: Dictionary = Dictionary(data.get("meta_progress", {}))
	return not Dictionary(data.get("current_run", {})).is_empty() or not Dictionary(data.get("suspended_runs", {})).is_empty() or (not meta.is_empty() and meta != defaults)


func _on_action(arguments: Array) -> void:
	if arguments.is_empty() or _busy or _loading or _action_pending: return
	var parsed: Variant = JSON.parse_string(String(arguments[0]))
	if parsed is Dictionary:
		_action_pending = true
		publish()
		await _action(Dictionary(parsed))
		_action_pending = false
		publish()


func _action(command: Dictionary) -> void:
	var action: String = String(command.get("id", ""))
	match action:
		"retry":
			_epoch += 1
			_transition(_epoch, account_id)
		"cloud": await _claim_and_load(state == "conflict", true, _epoch)
		"takeover":
			var epoch: int = _epoch
			var latest: Dictionary = await request("GET", "/api/cloud/save")
			if epoch != _epoch: return
			if latest.has("error"): return
			remote = latest
			var dirty: bool = SaveManager.active_profile == account_id and bool(SaveManager.profile_meta.get("dirty", false))
			if dirty and int(SaveManager.profile_meta.get("revision", 0)) != int(remote["revision"]):
				state = "conflict"
				publish()
			else: await _claim_and_load(true, not dirty, epoch)
		"local":
			if not SaveManager.archive_profile(account_id): return
			await _claim_and_load(true, false, _epoch)
		"import", "new":
			if action == "import" and not SaveManager.archive_profile("guest", "before-import"): return
			var payload: Dictionary = SaveManager.read_profile("guest") if action == "import" else SaveData.new().to_dict()
			# Guest data never grants ownership of another account's Ranked journal.
			if not payload.get("current_run", {}).get("ranking", {}).is_empty(): payload["current_run"] = {}
			payload.get("suspended_runs", {}).erase("ranked")
			payload.get("settings", {}).erase("_cloud_meta")
			var epoch: int = _epoch
			var claim: Dictionary = await request("POST", "/api/cloud/claim", {"writer_id": _writer, "takeover": false})
			if epoch != _epoch: return
			if claim.has("error") or int(claim["revision"]) != int(remote.get("revision", 0)):
				state = "device_busy" if claim.get("error", "") == "device_busy" else "conflict"
				if not claim.has("error"): remote = claim
				publish()
				return
			if not SaveManager.archive_profile(account_id): return
			if not _switch_local(account_id, payload): return
			SaveManager.profile_meta = {"revision": int(remote.get("revision", 0)), "guest_import_pending": action == "import"}
			state = "ready"
			SaveManager.save_game("hub")
			await sync_now()
			_refresh_hub()
		"sync": await sync_now()
		"history":
			var response: Dictionary = await request("GET", "/api/cloud/history")
			history = Array(response.get("history", []))
			publish()
		"restore":
			var epoch: int = _epoch
			var response: Dictionary = await request("POST", "/api/cloud/restore", {"writer_id": _writer, "base_revision": int(SaveManager.profile_meta.get("revision", 0)), "request_id": _uuid(), "revision": int(command.get("revision", -1))})
			if epoch != _epoch: return
			if response.has("error"):
				_last_error = String(response["error"])
				state = "conflict"
				publish()
			else:
				remote = response
				await _claim_and_load(false, true, epoch)
		"logout", "logout_anyway":
			if action == "logout" and bool(SaveManager.profile_meta.get("dirty", false)) and SaveManager.active_profile == account_id:
				if not await sync_now():
					state = "logout_pending"
					publish()
					return
			var old: String = account_id
			var epoch: int = _epoch
			await request("POST", "/api/cloud/release", {"writer_id": _writer})
			if epoch != _epoch: return
			var response: Dictionary = await request("POST", "/api/account/logout", {}, old)
			if epoch != _epoch: return
			if response.has("error"):
				_last_error = String(response["error"])
				publish()
				return
			_target = ""
			_epoch += 1
			_transition(_epoch, "")
			if bool(command.get("clear_cache", false)): SaveManager.forget_cached_profile(old)
			AccountSession.refresh()


func publish() -> void:
	var blocked: bool = state in ["loading", "load_error", "import_choice", "guest_choice", "conflict", "device_busy", "local_save_error", "logout_pending"]
	if initialized: get_tree().paused = blocked
	if _bridge != null:
		_bridge.publish(JSON.stringify({"state": state, "blocked": blocked, "busy": _busy or _loading or _action_pending, "profile": SaveManager.active_profile, "account_id": account_id, "revision": int(SaveManager.profile_meta.get("revision", 0)), "updated_at": remote.get("updated_at", ""), "dirty": bool(SaveManager.profile_meta.get("dirty", false)), "error": _last_error, "local": _summary(SaveManager.read_profile(account_id) if account_id != "" else {}), "cloud": _summary(Dictionary(remote["payload"]) if remote.get("payload") is Dictionary else {}), "guest": _summary(SaveManager.read_profile("guest")), "history": history}))
	changed.emit()


func _summary(data: Dictionary) -> Dictionary:
	var meta: Dictionary = Dictionary(data.get("meta_progress", {}))
	return {"points": int(meta.get("points", 0)), "unlocks": Array(meta.get("unlocked_cards", [])).size() + Array(meta.get("unlocked_relics", [])).size(), "runs": Dictionary(data.get("suspended_runs", {})).size() + (0 if Dictionary(data.get("current_run", {})).is_empty() else 1)}
