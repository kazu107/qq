extends MenuScreenDialog
class_name BattleTutorialDialog

const TUTORIAL_SCENE: PackedScene = preload("res://scenes/tutorial/BattleTutorial.tscn")


func _init() -> void:
	dialog_prefix = "BattleTutorial"
	maximum_size = Vector2(1680, 900)


func _create_content() -> Control:
	return TUTORIAL_SCENE.instantiate() as Control
