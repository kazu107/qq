extends RefCounted
class_name StartupWarmupService

const CARD_ICON_DIR := "res://assets/icons/cards"
const RELIC_ICON_DIR := "res://assets/icons/relics"
const PORTRAIT_DIR := "res://assets/portraits"
const STATUS_ICON_DIR := "res://assets/icons/status"


static func warm_all() -> Dictionary:
	var card_ids: Array[String] = _collect_card_ids()
	var relic_ids: Array[String] = _collect_relic_ids()
	var portrait_ids: Array[String] = _collect_portrait_ids()
	var status_ids: Array[String] = _collect_status_ids()

	SceneRouter.warm_scene_cache()
	var unit_counts: Dictionary = UnitPanel.warm_visual_cache(portrait_ids, status_ids)
	var stat_icon_count: int = StatIconFactory.warm_cache()
	var map_icon_count: int = MapNodeButton.warm_icon_cache()

	return {
		"scenes": SceneRouter.get_cached_scene_count(),
		"sfx": AudioManager.warm_sfx_cache(),
		"cards": CardButton.warm_texture_cache(card_ids),
		"card_picker_icons": CardIconPicker.warm_button_icon_cache(card_ids),
		"card_picker_popup_icons": CardIconPicker.get_cached_popup_icon_count(),
		"relics": RelicIcon.warm_texture_cache(relic_ids),
		"portraits": int(unit_counts.get("portraits", 0)),
		"status_icons": int(unit_counts.get("statuses", 0)),
		"stat_icons": stat_icon_count,
		"map_icons": map_icon_count,
	}


static func _collect_card_ids() -> Array[String]:
	var ids: Array[String] = Database.get_all_card_ids()
	_append_unique_many(ids, _collect_png_ids(CARD_ICON_DIR))
	ids.sort()
	return ids


static func _collect_relic_ids() -> Array[String]:
	var ids: Array[String] = Database.get_all_relic_ids()
	_append_unique_many(ids, _collect_png_ids(RELIC_ICON_DIR))
	ids.sort()
	return ids


static func _collect_portrait_ids() -> Array[String]:
	var ids: Array[String] = []
	for starter_data in Database.starters:
		_append_unique(ids, String(starter_data.get("id", "")))
	for raw_enemy_id in Database.enemies.keys():
		_append_unique(ids, String(raw_enemy_id))
	_append_unique_many(ids, _collect_png_ids(PORTRAIT_DIR))
	ids.sort()
	return ids


static func _collect_status_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_status_id in UnitPanel.STATUS_FALLBACK_DURATIONS.keys():
		_append_unique(ids, String(raw_status_id))
	for raw_card_id in Database.cards.keys():
		var card_def: CardDef = Database.get_card(String(raw_card_id))
		if card_def == null:
			continue
		for effect_data in card_def.effects:
			var effect_type: String = String(effect_data.get("type", ""))
			if effect_type == "apply_status" or effect_type == "remove_status":
				_append_unique(ids, String(effect_data.get("status", "")))
	_append_unique_many(ids, _collect_png_ids(STATUS_ICON_DIR))
	ids.sort()
	return ids


static func _collect_png_ids(directory_path: String) -> Array[String]:
	var ids: Array[String] = []
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return ids
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".png"):
			_append_unique(ids, file_name.get_basename())
		file_name = directory.get_next()
	directory.list_dir_end()
	return ids


static func _append_unique_many(target: Array[String], values: Array[String]) -> void:
	for value in values:
		_append_unique(target, value)


static func _append_unique(target: Array[String], value: String) -> void:
	if value == "" or target.has(value):
		return
	target.append(value)
