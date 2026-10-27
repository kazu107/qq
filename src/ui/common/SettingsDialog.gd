extends MenuScreenDialog
class_name SettingsDialog

const SETTINGS_SCENE: PackedScene = preload("res://scenes/settings/Settings.tscn")


func _init() -> void:
	dialog_prefix = "Settings"


func _create_content() -> Control:
	return SETTINGS_SCENE.instantiate() as Control
