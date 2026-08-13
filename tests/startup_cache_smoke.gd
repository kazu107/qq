extends Node

const STARTUP_WARMUP_SERVICE: GDScript = preload("res://src/core/services/StartupWarmupService.gd")

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	call_deferred("_run")


func _run() -> void:
	var summary: Dictionary = STARTUP_WARMUP_SERVICE.warm_all()
	if _failed:
		return

	var expected_card_icons: int = _count_png_files("res://assets/icons/cards")
	var expected_relic_icons: int = _count_png_files("res://assets/icons/relics")
	var expected_portraits: int = _count_png_files("res://assets/portraits")
	var expected_status_icons: int = _count_png_files("res://assets/icons/status")
	var expected_sfx: int = AudioManager.get_available_sfx_ids().size()

	if int(summary.get("scenes", 0)) < 12:
		_fail("Startup cache smoke failed: scene cache did not include all major screens")
		return
	if CardButton.get_cached_texture_count() < expected_card_icons:
		_fail("Startup cache smoke failed: card textures were not fully cached")
		return
	if CardIconPicker.get_cached_button_icon_count() < expected_card_icons:
		_fail("Startup cache smoke failed: card picker icons were not fully cached")
		return
	if CardIconPicker.get_cached_popup_icon_count() < expected_card_icons:
		_fail("Startup cache smoke failed: card picker popup icons were not fully cached")
		return
	if RelicIcon.get_cached_texture_count() < expected_relic_icons:
		_fail("Startup cache smoke failed: relic textures were not fully cached")
		return
	if UnitPanel.get_cached_portrait_count() < expected_portraits:
		_fail("Startup cache smoke failed: portraits were not fully cached")
		return
	if UnitPanel.get_cached_status_icon_count() < expected_status_icons:
		_fail("Startup cache smoke failed: status icons were not fully cached")
		return
	if AudioManager.get_cached_sfx_count() < expected_sfx:
		_fail("Startup cache smoke failed: SFX streams were not fully cached")
		return
	if StatIconFactory.get_cached_icon_count() < 12:
		_fail("Startup cache smoke failed: generated stat icons were not cached")
		return
	if MapNodeButton.get_cached_type_icon_count() < 8 or not MapNodeButton.has_cached_lock_icon():
		_fail("Startup cache smoke failed: map node icons were not cached")
		return
	if int(summary.get("battle_3d_meshes", 0)) < 20 or CommonBattleHumanoid3D.get_cached_mesh_count() < 20:
		_fail("Startup cache smoke failed: 3D battle model meshes were not cached")
		return
	if not _boot_loading_screen_has_progress_ui():
		return

	print("Startup cache smoke passed: %s" % JSON.stringify(summary))
	get_tree().quit()


func _boot_loading_screen_has_progress_ui() -> bool:
	var boot_source: String = FileAccess.get_file_as_string("res://src/ui/screens/BootScreen.gd")
	if not boot_source.contains("SceneRouter.go_to_hub()") or boot_source.contains("SceneRouter.go_to_title()"):
		_fail("Startup cache smoke failed: boot should transition directly to Hub")
		return false
	var boot_scene: PackedScene = load("res://scenes/boot/Boot.tscn") as PackedScene
	if boot_scene == null:
		_fail("Startup cache smoke failed: boot scene could not be loaded")
		return false
	var boot_screen: Control = boot_scene.instantiate() as Control
	if boot_screen == null:
		_fail("Startup cache smoke failed: boot scene is not a Control")
		return false
	boot_screen.call("_build_loading_screen")
	var progress_bar: ProgressBar = boot_screen.find_child("BootLoadingProgress", true, false) as ProgressBar
	var detail_label: Label = boot_screen.find_child("BootLoadingDetail", true, false) as Label
	boot_screen.queue_free()
	if progress_bar == null or detail_label == null:
		_fail("Startup cache smoke failed: boot loading screen progress UI was missing")
		return false
	return true


func _count_png_files(directory_path: String) -> int:
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return 0
	var count: int = 0
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".png"):
			count += 1
		file_name = directory.get_next()
	directory.list_dir_end()
	return count


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
