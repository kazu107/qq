extends Control

var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text = Localization.get_text("boot.loading", "Loading data...")
	add_child(_label)
	call_deferred("_boot")


func _boot() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	var save_data := SaveManager.load_save()
	Game.apply_loaded_save(save_data)
	SceneRouter.warm_scene_cache()
	_label.text = Localization.get_textf("boot.loaded", "Loaded {cards} cards / {enemies} enemies", {
		"cards": Database.cards.size(),
		"enemies": Database.enemies.size(),
	})
	await get_tree().create_timer(0.2).timeout
	SceneRouter.go_to_title()
