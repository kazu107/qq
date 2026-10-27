extends MenuScreenDialog
class_name MetaProgressDialog


func _init() -> void:
	dialog_prefix = "MetaProgress"
	maximum_size = Vector2(1680, 960)


func _create_content() -> Control:
	return SceneRouter.take_meta_progress_content()
