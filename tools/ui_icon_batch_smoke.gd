extends Node

const MANIFEST_PATH: String = "res://art_src/blender/ui/qq_small_icons.manifest.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)) as Dictionary
	var assets: Array = manifest.get("assets", []) as Array
	if not _check(assets.size() == 46, "Expected all 46 UI-batch outputs"):
		return
	var seen: Dictionary = {}
	for raw_asset: Variant in assets:
		var asset: Dictionary = raw_asset as Dictionary
		var asset_id: String = String(asset.get("id", ""))
		var visual_id: String = String(asset.get("visual_id", ""))
		var path: String = "res://" + String(asset.get("runtime_path", ""))
		var texture: Texture2D = ResourceLoader.load(path) as Texture2D
		var dimensions: Array = asset.get("size", []) as Array
		if not _check(not seen.has(asset_id) and texture != null, "Missing/duplicate texture: " + asset_id):
			return
		seen[asset_id] = true
		if not _check(texture.get_width() == int(dimensions[0]) and texture.get_height() == int(dimensions[1]), "Texture size changed: " + asset_id):
			return
		var cached: Texture2D
		match String(asset.get("category", "")):
			"status":
				cached = CardEffectIconFactory.get_icon("status:" + visual_id)
			"ui":
				cached = StatIconFactory.get_icon(visual_id)
			"effect":
				cached = CardEffectIconFactory.get_icon(visual_id)
			"map":
				cached = MapNodeButton._load_lock_icon_texture() if visual_id == "lock" else MapNodeButton._load_type_icon_texture(visual_id)
			"control":
				cached = UiTheme._load_authored_control(visual_id)
		if not _check(cached == texture, "Authored texture was not loaded/cached: " + asset_id):
			return
	var theme: Theme = UiTheme.get_game_theme()
	for theme_type: String in ["CheckBox", "CheckButton"]:
		var prefix: String = "checkbox" if theme_type == "CheckBox" else "switch"
		for state: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
			var is_on: bool = state.begins_with("checked")
			var icon_id: String = "%s_%s%s" % [prefix, "on" if is_on else "off", "_disabled" if state.ends_with("disabled") else ""]
			var path: String = "res://assets/icons/controls/%s.png" % icon_id
			if not _check(theme.get_icon(state, theme_type).resource_path == path, "Wrong theme state: " + theme_type + " " + state):
				return
		var pressed_hover: StyleBoxFlat = theme.get_stylebox("hover_pressed", theme_type) as StyleBoxFlat
		if not _check(pressed_hover != null and pressed_hover.bg_color.a > 0.8, "Checked hover style disappeared"):
			return
	for state: String in ["grabber", "grabber_highlight"]:
		if not _check(theme.get_icon(state, "HSlider").get_size() == Vector2(22, 22), "Slider layout changed"):
			return
	if not _check(MapNodeButton.warm_icon_cache() == 9 and MapNodeButton.get_cached_type_icon_count() == 8, "Map cache incomplete"):
		return
	var old_count: int = CardEffectIconFactory.get_cached_icon_count()
	CardEffectIconFactory.warm_cache(["slow", "vulnerable", "weak", "bleed"])
	var warmed_count: int = CardEffectIconFactory.get_cached_icon_count()
	CardEffectIconFactory.warm_cache(["slow", "vulnerable", "weak", "bleed"])
	if not _check(warmed_count >= old_count and warmed_count == CardEffectIconFactory.get_cached_icon_count(), "Effect cache duplicates on repeated warmup"):
		return
	if not _check(CardEffectIconFactory.get_icon("__missing_effect__") != null and MapNodeButton._load_type_icon_texture("__missing_node__") != null, "Fallback icons stopped working"):
		return
	print("UI_ICON_BATCH_SMOKE_OK 46 textures, authored loaders, caches, control states, hover styles, fallbacks")
	get_tree().quit()


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		get_tree().quit(1)
	return condition
