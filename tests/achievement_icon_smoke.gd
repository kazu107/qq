extends Node

var _checks: int = 0
var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error("Achievement icons: " + message)


func _run() -> void:
	var ids: Array[String] = Database.get_all_achievement_ids()
	_check(AchievementIconCatalog.warm_cache() == ids.size(), "all achievement textures must be cached")
	_check(AchievementIconCatalog.get_icon("unknown") == null, "unknown ID should not reuse unrelated artwork")
	var hashes: Dictionary = {}
	for id: String in ids:
		var texture: Texture2D = AchievementIconCatalog.get_icon(id)
		_check(texture != null and texture.get_size() == Vector2(128, 128), "missing/wrong-sized artwork: " + id)
		_check(texture == AchievementIconCatalog.get_icon(id), "texture cache identity changed")
		var image: Image = texture.get_image()
		if image.is_compressed(): image.decompress()
		_check(image.get_pixel(0, 0).a == 0.0 and image.get_pixel(127, 127).a == 0.0, "non-transparent corners: " + id)
		var hash: String = image.get_data().hex_encode().sha256_text()
		_check(not hashes.has(hash), "achievement images must be unique: " + id)
		hashes[hash] = true
	var meta: Dictionary = Database.meta_progress_template.duplicate(true)
	Game.meta_progress = meta
	Game.settings["developer_mode"] = false
	var scene: Control = load("res://scenes/meta/MetaProgress.tscn").instantiate() as Control
	add_child(scene)
	for frame: int in 180:
		if scene.call("is_content_ready"): break
		await get_tree().process_frame
	for frame: int in 6: await get_tree().process_frame
	for id: String in ids:
		var icon: TextureRect = scene.find_child("AchievementIcon_" + id, true, false) as TextureRect
		var label: Label = scene.find_child("AchievementName_" + id, true, false) as Label
		var reward: Label = scene.find_child("AchievementReward_" + id, true, false) as Label
		var bar: ProgressBar = scene.find_child("AchievementProgressBar_" + id, true, false) as ProgressBar
		_check(icon != null and icon.texture == AchievementIconCatalog.get_icon(id), "wrong icon binding: " + id)
		_check(icon.size.is_equal_approx(Vector2(88, 88)), "icon must stay square and not expand with text")
		_check(icon.get_global_rect().end.x < label.get_global_rect().position.x, "icon is not left of upper text")
		_check(absf(icon.global_position.y - label.global_position.y) <= 1.0, "icon not aligned with top text row")
		_check(bar.global_position.y >= maxf(icon.get_global_rect().end.y, reward.get_global_rect().end.y), "bar overlaps upper icon/text")
		_check(is_equal_approx(bar.global_position.x, icon.global_position.x), "bar must remain full-width below upper row")
	var first_icon: TextureRect = scene.find_child("AchievementIcon_victory_milestones", true, false) as TextureRect
	var identity: int = first_icon.get_instance_id()
	Game.developer_add_achievement_stat("victories", 1)
	scene.call("_refresh_ui")
	Game.claim_meta_achievement("victory_milestones")
	scene.call("_refresh_ui")
	_check((scene.find_child("AchievementIcon_victory_milestones", true, false) as TextureRect).get_instance_id() == identity, "claim rebuilt the icon")
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/art_provenance.json"))
	var registered: int = 0
	for entry: Dictionary in provenance["assets"]:
		if entry.get("category", "") == "achievement":
			registered += 1
			_check(FileAccess.file_exists("res://" + String(entry["source_path"])), "editable Blender source missing")
	_check(registered == ids.size(), "achievement art provenance incomplete")
	scene.queue_free()
	await get_tree().process_frame
	Game.settings["developer_mode"] = true
	var lab: Control = load(SceneRouter.ART_LAB_SCENE).instantiate() as Control
	add_child(lab)
	var category: OptionButton = lab.find_child("ArtLabCategory", true, false) as OptionButton
	var found_category: bool = false
	for index: int in category.item_count:
		if String(category.get_item_metadata(index)) == "achievement":
			category.select(index)
			found_category = true
	_check(found_category, "developer Art Lab achievement filter missing")
	lab.call("_apply_filter")
	_check(Array(lab.get("_filtered")).size() == ids.size(), "Art Lab does not show all achievement images")
	for entry: Dictionary in lab.get("_filtered"):
		_check(lab.call("_asset_name", entry) == Database.get_achievement(String(entry["visual_id"]))["name"], "Art Lab achievement name is not localized")
	lab.queue_free()
	await get_tree().process_frame
	if _failed: get_tree().quit(1)
	else:
		print("ACHIEVEMENT_ICON_SMOKE_OK checks=%d" % _checks)
		get_tree().quit()
