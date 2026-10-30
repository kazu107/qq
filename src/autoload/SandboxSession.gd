extends Node

var active: bool = false
var draft: Dictionary = {}
var config: Dictionary = {}
var owner_profile: String = ""


func _ready() -> void:
	CloudSession.changed.connect(_check_owner)
	AccountSession.changed.connect(_check_owner)


func _check_owner() -> void:
	if owner_profile != "" and owner_profile != SaveManager.active_profile:
		active = false; draft.clear(); config.clear(); owner_profile = ""
		var scene: Node = get_tree().current_scene
		if scene != null and (scene.scene_file_path == SceneRouter.SANDBOX_SCENE or (scene.scene_file_path == SceneRouter.BATTLE_SCENE and scene.get("_sandbox_mode") == true)): SceneRouter.go_to_hub()


func get_draft() -> Dictionary:
	_check_owner()
	owner_profile = SaveManager.active_profile
	if draft.is_empty():
		var saved: Variant = Game.settings.get("sandbox_last_config",{})
		draft = SandboxConfig.normalize(saved) if saved is Dictionary and not saved.is_empty() else SandboxConfig.defaults()
	return draft.duplicate(true)


func begin(raw: Dictionary) -> bool:
	if owner_profile!="" and owner_profile!=SaveManager.active_profile:return false
	if NetworkManager.is_session_connected(): return false
	config = SandboxConfig.normalize(raw)
	if not SandboxConfig.errors(config).is_empty(): return false
	draft = config.duplicate(true); owner_profile = SaveManager.active_profile
	active = true
	return true


func save_last(raw: Dictionary) -> void:
	if owner_profile!="" and owner_profile!=SaveManager.active_profile:return
	owner_profile = SaveManager.active_profile
	draft = SandboxConfig.normalize(raw)
	Game.settings["sandbox_last_config"] = draft.duplicate(true)
	SaveManager.request_save(Game.current_screen_hint)


func presets() -> Dictionary:
	var value: Variant = Game.settings.get("sandbox_presets",{})
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


func save_preset(name_text: String, raw: Dictionary) -> bool:
	if owner_profile!="" and owner_profile!=SaveManager.active_profile:return false
	var title: String = name_text.strip_edges().left(40)
	var saved: Dictionary = presets()
	if title == "" or (saved.size() >= 20 and not saved.has(title)): return false
	saved[title] = SandboxConfig.normalize(raw)
	Game.settings["sandbox_presets"] = saved
	save_last(raw)
	return true


func delete_preset(title: String) -> void:
	if owner_profile!="" and owner_profile!=SaveManager.active_profile:return
	var saved: Dictionary = presets(); saved.erase(title)
	Game.settings["sandbox_presets"] = saved
	SaveManager.request_save(Game.current_screen_hint)
