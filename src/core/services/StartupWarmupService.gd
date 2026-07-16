extends RefCounted
class_name StartupWarmupService

const CARD_ICON_DIR := "res://assets/icons/cards"
const RELIC_ICON_DIR := "res://assets/icons/relics"
const PORTRAIT_DIR := "res://assets/portraits"
const STATUS_ICON_DIR := "res://assets/icons/status"


class WarmupData:
	extends RefCounted

	var card_ids: Array[String] = []
	var relic_ids: Array[String] = []
	var portrait_ids: Array[String] = []
	var status_ids: Array[String] = []
	var summary: Dictionary = {}


static func warm_all() -> Dictionary:
	var data: WarmupData = _collect_warmup_data()

	SceneRouter.warm_scene_cache()
	var unit_counts: Dictionary = {}
	var card_count: int = 0
	var card_picker_count: int = 0
	var card_picker_popup_count: int = 0
	var relic_count: int = 0
	if not Game.is_web_build():
		unit_counts = UnitPanel.warm_visual_cache(data.portrait_ids, data.status_ids)
		card_count = CardButton.warm_texture_cache(data.card_ids)
		card_picker_count = CardIconPicker.warm_button_icon_cache(data.card_ids)
		card_picker_popup_count = CardIconPicker.get_cached_popup_icon_count()
		relic_count = RelicIcon.warm_texture_cache(data.relic_ids)
	var stat_icon_count: int = StatIconFactory.warm_cache()
	var map_icon_count: int = MapNodeButton.warm_icon_cache()

	return {
		"scenes": SceneRouter.get_cached_scene_count(),
		"sfx": AudioManager.warm_sfx_cache(),
		"cards": card_count,
		"card_picker_icons": card_picker_count,
		"card_picker_popup_icons": card_picker_popup_count,
		"relics": relic_count,
		"portraits": int(unit_counts.get("portraits", 0)),
		"status_icons": int(unit_counts.get("statuses", 0)),
		"stat_icons": stat_icon_count,
		"map_icons": map_icon_count,
		"network_hash": LanProtocol.build_content_hash().left(12),
	}


static func warm_all_async(progress_callback: Callable = Callable()) -> Dictionary:
	var data: WarmupData = _collect_warmup_data()
	var use_lightweight_cache: bool = Game.is_web_build()
	_report_progress(progress_callback, "boot.caching_scenes", 0.58)
	await _next_frame()
	SceneRouter.warm_scene_cache()
	data.summary["scenes"] = SceneRouter.get_cached_scene_count()

	_report_progress(progress_callback, "boot.caching_audio", 0.64)
	await _next_frame()
	data.summary["sfx"] = AudioManager.warm_sfx_cache()

	_report_progress(progress_callback, "boot.caching_cards", 0.70)
	await _next_frame()
	data.summary["cards"] = 0 if use_lightweight_cache else CardButton.warm_texture_cache(data.card_ids)

	_report_progress(progress_callback, "boot.caching_card_picker", 0.78)
	await _next_frame()
	data.summary["card_picker_icons"] = 0 if use_lightweight_cache else CardIconPicker.warm_button_icon_cache(data.card_ids)
	data.summary["card_picker_popup_icons"] = 0 if use_lightweight_cache else CardIconPicker.get_cached_popup_icon_count()

	_report_progress(progress_callback, "boot.caching_relics", 0.84)
	await _next_frame()
	data.summary["relics"] = 0 if use_lightweight_cache else RelicIcon.warm_texture_cache(data.relic_ids)

	_report_progress(progress_callback, "boot.caching_units", 0.90)
	await _next_frame()
	var unit_counts: Dictionary = {} if use_lightweight_cache else UnitPanel.warm_visual_cache(data.portrait_ids, data.status_ids)
	data.summary["portraits"] = int(unit_counts.get("portraits", 0))
	data.summary["status_icons"] = int(unit_counts.get("statuses", 0))

	_report_progress(progress_callback, "boot.caching_ui", 0.96)
	await _next_frame()
	data.summary["stat_icons"] = StatIconFactory.warm_cache()
	data.summary["map_icons"] = MapNodeButton.warm_icon_cache()

	_report_progress(progress_callback, "boot.caching_network", 0.99)
	await _next_frame()
	data.summary["network_hash"] = LanProtocol.build_content_hash().left(12)

	_report_progress(progress_callback, "boot.ready", 1.0)
	await _next_frame()
	return data.summary


static func _collect_warmup_data() -> WarmupData:
	var data: WarmupData = WarmupData.new()
	data.card_ids = _collect_card_ids()
	data.relic_ids = _collect_relic_ids()
	data.portrait_ids = _collect_portrait_ids()
	data.status_ids = _collect_status_ids()
	return data


static func _report_progress(progress_callback: Callable, text_key: String, progress: float) -> void:
	if not progress_callback.is_valid():
		return
	progress_callback.call(Localization.get_text(text_key, text_key), progress)


static func _next_frame() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	await tree.process_frame


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
