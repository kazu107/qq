extends Node

const UI_IDS: Array[String] = ["attack", "speed", "shield", "hp", "gold", "step", "time", "relic", "card_owned", "card_equipped", "settings", "version_history", "card"]
const EFFECT_IDS: Array[String] = ["shield_spend", "delay", "haste", "recast", "interrupt", "cleanse", "empower", "auto_queue", "timeline_stop", "timeline_reverse", "status", "effect"]
const MAP_IDS: Array[String] = ["normal_battle", "elite_battle", "boss", "shop", "forge", "heal", "event", "hazard", "lock"]
var _failures: Array[String] = []
var _paths: Dictionary = {}


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _require_image(path: String, extent: int = 0) -> void:
	_check(_paths.has(path), "Not registered as Blender artwork: " + path)
	var texture: Texture2D = ArtCatalog.get_texture(path)
	_check(texture != null, "Could not import " + path)
	if texture != null and extent > 0:
		_check(texture.get_size() == Vector2.ONE * extent, "Invalid dimensions: " + path)


func _run() -> void:
	for entry: Dictionary in ArtCatalog.get_entries():
		_paths[String(entry.get("runtime_path", ""))] = entry
	for id: String in Database.get_all_card_ids():
		_require_image("assets/icons/cards/%s.png" % id, 512)
	for id: String in Database.get_all_relic_ids():
		_require_image("assets/icons/relics/%s.png" % id, 512)
	_require_image("assets/icons/cards/environment_fatigue.png", 512)
	_check(FatigueRules.ART_PATH.ends_with(".png"), "Fatigue still uses the old SVG")
	for profile: Dictionary in Database.get_all_battle_visual_profiles():
		var id: String = String(profile.get("id", ""))
		if id.is_empty() or id.begins_with("default_"):
			continue
		var path: String = String(profile.get("model_scene", ""))
		_check(not path.is_empty() and _paths.has(path.trim_prefix("res://")), "Missing Blender model " + id)
	for id: String in _character_ids():
		_require_image("assets/portraits/%s.png" % id, 1024)
		var profile: Dictionary = Database.get_battle_visual_profile(id)
		var model: PackedScene = ResourceLoader.load(String(profile.get("model_scene", ""))) as PackedScene
		_check(model != null, "Could not import model " + id)
		if model == null:
			continue
		var root: Node = model.instantiate()
		var skeleton: Skeleton3D = _find_skeleton(root)
		_check(skeleton != null and skeleton.get_bone_count() == 18, "Incompatible rig " + id)
		root.free()
		await get_tree().process_frame
	for id: String in ["bleed", "slow", "weak", "vulnerable"]:
		_require_image("assets/icons/status/%s.png" % id, 96)
	for id: String in UI_IDS:
		var path: String = "assets/icons/ui/%s.png" % id
		_require_image(path, 64)
		_check(StatIconFactory.get_icon(id).resource_path == "res://" + path, "UI icon fell back: " + id)
	for id: String in EFFECT_IDS:
		var path: String = "assets/icons/effects/%s.png" % id
		_require_image(path, 64)
		_check(CardEffectIconFactory.get_icon(id).resource_path == "res://" + path, "Effect icon fell back: " + id)
	for id: String in MAP_IDS:
		_require_image("assets/icons/map/%s.png" % id, 96)
	_require_image("assets/backgrounds/hub.png")
	_require_image("assets/backgrounds/run_result.png")
	_check(BattleEnvironmentArt.warm_cache() == 1, "Field was not cached")
	var field: Node3D = BattleEnvironmentArt.instantiate_field()
	_check(field != null, "No authored field instance")
	if field != null:
		_check(field.find_child("BattleGrass*", true, false) != null, "Authored field has no grass")
		field.free()
	var stage: BattleStage3D = BattleStage3D.new()
	add_child(stage)
	_check(stage.is_using_authored_field(), "Stage fell back to procedural terrain")
	stage.queue_free()
	await get_tree().process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("Blender full art smoke: " + failure)
		get_tree().quit(1)
		return
	print("BLENDER_FULL_ART_SMOKE_OK all cards/relics, 25 rigs/portraits, icons, field and backgrounds")
	get_tree().quit()


func _character_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw: Variant in Database.starters:
		ids.append(String(Dictionary(raw).get("id", "")))
	for id: String in Database.enemies:
		ids.append(id)
	return ids


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child: Node in root.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null
