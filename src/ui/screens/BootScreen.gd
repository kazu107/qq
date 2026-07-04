extends Control

const STARTUP_WARMUP_SERVICE: GDScript = preload("res://src/core/services/StartupWarmupService.gd")

var _label: Label
var _detail_label: Label
var _progress_bar: ProgressBar


func _ready() -> void:
	_build_loading_screen()
	call_deferred("_boot")


func _build_loading_screen() -> void:
	var background: ColorRect = ColorRect.new()
	background.name = "BootLoadingBackground"
	background.color = Color(0.006, 0.010, 0.016, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "BootLoadingMargin"
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 260.0
	margin.offset_top = 180.0
	margin.offset_right = -260.0
	margin.offset_bottom = -180.0
	add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	_label = Label.new()
	_label.name = "BootLoadingTitle"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 28)
	root.add_child(_label)

	_detail_label = Label.new()
	_detail_label.name = "BootLoadingDetail"
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_detail_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.name = "BootLoadingProgress"
	_progress_bar.custom_minimum_size = Vector2(520.0, 26.0)
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	root.add_child(_progress_bar)

	_set_loading_status(Localization.get_text("boot.loading", "Loading data..."), 0.0)


func _boot() -> void:
	_set_loading_status(Localization.get_text("boot.loading", "Loading data..."), 0.08)
	await get_tree().process_frame
	Database.load_all()
	_set_loading_status(Localization.get_text("boot.loading_save", "Loading save data..."), 0.28)
	await get_tree().process_frame
	Game.ensure_meta_initialized()
	var save_data: SaveData = SaveManager.load_save()
	Game.apply_loaded_save(save_data)
	_set_loading_status(Localization.get_text("boot.caching", "Caching assets..."), 0.52)
	await get_tree().process_frame
	var warmup_summary: Dictionary = await STARTUP_WARMUP_SERVICE.warm_all_async(Callable(self, "_set_loading_status"))
	_set_loading_status(Localization.get_text("boot.ready", "Ready"), 1.0)
	_label.text = Localization.get_textf("boot.loaded", "Loaded {cards} cards / {enemies} enemies", {
		"cards": Database.cards.size(),
		"enemies": Database.enemies.size(),
	})
	_detail_label.text = Localization.get_textf("boot.cache_loaded", "Cached {cards} cards / {scenes} scenes / {sfx} SFX", {
		"cards": int(warmup_summary.get("cards", 0)),
		"scenes": int(warmup_summary.get("scenes", 0)),
		"sfx": int(warmup_summary.get("sfx", 0)),
	})
	tooltip_text = "Startup cache: %s" % JSON.stringify(warmup_summary)
	await get_tree().create_timer(0.2).timeout
	SceneRouter.go_to_title()


func _set_loading_status(text: String, progress: float) -> void:
	if _label != null:
		_label.text = Localization.get_text("boot.title", "Loading")
	if _detail_label != null:
		_detail_label.text = text
	if _progress_bar != null:
		_progress_bar.value = clampf(progress, 0.0, 1.0)
