extends Node


func _ready() -> void:
	if not _check(String(ProjectSettings.get_setting("application/config/name")) == "QueueQuest", "game title is incorrect"):
		return
	if OS.get_name() in ["Windows", "macOS", "Linux"]:
		var legacy_relative_path: String = "godot/app_userdata/qq" if OS.get_name() == "Linux" else "Godot/app_userdata/qq"
		var expected_save_path: String = OS.get_data_dir().path_join(legacy_relative_path).simplify_path()
		if not _check(OS.get_user_data_dir().simplify_path() == expected_save_path, "renaming the game changed its save directory"):
			return
	var logo: Texture2D = load("res://assets/branding/queuequest-logo.svg") as Texture2D
	var icon: Texture2D = load("res://assets/branding/queuequest-mark.svg") as Texture2D
	if not _check(logo != null and logo.get_size() == Vector2(900, 240), "wordmark could not be imported"):
		return
	if not _check(icon != null and icon.get_size() == Vector2(256, 256), "icon could not be imported"):
		return
	var boot: Control = load("res://scenes/boot/Boot.tscn").instantiate() as Control
	boot.call("_build_loading_screen")
	var boot_logo: TextureRect = boot.find_child("BootLoadingLogo", true, false) as TextureRect
	var logo_present: bool = boot_logo != null and boot_logo.texture == logo
	boot.free()
	if not _check(logo_present, "native Boot screen did not use the logo"):
		return
	print("BRANDING_SMOKE_OK QueueQuest SVGs and legacy save directory")
	get_tree().quit()


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("Branding smoke failed: %s" % message)
	get_tree().quit(1)
	return false
