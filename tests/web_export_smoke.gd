extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var project_text: String = _read_text("res://project.godot")
	if project_text == "":
		return
	if project_text.find('config/features=PackedStringArray("4.6", "GL Compatibility")') == -1:
		_fail("Web export smoke failed: project does not use GL Compatibility")
		return
	if project_text.find('renderer/rendering_method="gl_compatibility"') == -1:
		_fail("Web export smoke failed: Compatibility renderer is not configured")
		return

	var preset_text: String = _read_text("res://export_presets.cfg")
	if preset_text == "":
		return
	if preset_text.find('platform="Web"') == -1 or preset_text.find('export_path="build/web/index.html"') == -1:
		_fail("Web export smoke failed: Web export preset is incomplete")
		return
	if preset_text.find('exclude_filter="addons/gd-eos/*,build/*') == -1 or not FileAccess.file_exists("res://build/.gdignore"):
		_fail("Web export smoke failed: generated Web artifacts are not excluded from imports")
		return
	if preset_text.find('variant/thread_support=false') == -1 or preset_text.find('variant/extensions_support=false') == -1:
		_fail("Web export smoke failed: single-thread dependency-free options are missing")
		return
	if preset_text.find('vram_texture_compression/for_mobile=false') == -1:
		_fail("Web export smoke failed: mobile texture compression would require an ETC2/ASTC reimport")
		return
	if preset_text.find('html/custom_html_shell="res://web/custom_shell.html"') == -1:
		_fail("Web export smoke failed: the R2-aware custom HTML shell is not configured")
		return
	var shell_text: String = _read_text("res://web/custom_shell.html")
	if shell_text == "":
		return
	if (
		shell_text.find("https://qq.kazu107.xyz/releases/current.json") == -1
		or shell_text.find("engine.preloadFile(pack.source, LOCAL_PACK_PATH)") == -1
		or shell_text.find("'localhost', '127.0.0.1'") == -1
	):
		_fail("Web export smoke failed: R2 loading or the local PCK fallback is incomplete")
		return
	if (
		not FileAccess.file_exists("res://tools/prepare_r2_release.mjs")
		or not FileAccess.file_exists("res://.github/workflows/publish-web-r2.yml")
	):
		_fail("Web export smoke failed: the R2 publishing workflow is missing")
		return

	if not Game.WEB_MULTIPLAYER_ENABLED or Game.supports_lan_multiplayer():
		_fail("Web export smoke failed: Web multiplayer did not replace LAN multiplayer")
		return
	var hub_scene: PackedScene = load("res://scenes/hub/Hub.tscn") as PackedScene
	var title_scene: PackedScene = load("res://scenes/title/Title.tscn") as PackedScene
	if hub_scene == null or title_scene == null:
		_fail("Web export smoke failed: title or hub scene could not be loaded")
		return

	var hub: Control = hub_scene.instantiate() as Control
	var title: Control = title_scene.instantiate() as Control
	add_child(hub)
	add_child(title)
	await get_tree().process_frame
	if hub.find_child("WebMultiplayerButton", true, false) == null:
		_fail("Web export smoke failed: hub is missing the Web multiplayer entry")
		return
	if hub.find_child("HubTopActions", true, false) == null or hub.find_child("VersionHistoryButton", true, false) == null:
		_fail("Web export smoke failed: Hub version controls are missing")
		return
	if hub.find_child("LanMultiplayerButton", true, false) != null:
		_fail("Web export smoke failed: hub still exposes LAN multiplayer")
		return
	if not FileAccess.file_exists("res://package.json") or not FileAccess.file_exists("res://Procfile"):
		_fail("Web export smoke failed: Heroku process files are missing")
		return

	hub.queue_free()
	title.queue_free()
	print("WEB_EXPORT_SMOKE_OK Compatibility preset, R2 PCK, and Heroku host validated")
	get_tree().quit()


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Web export smoke failed: could not read %s" % path)
		return ""
	return file.get_as_text()


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
