extends Node

const SFX_PATH_TEMPLATE := "res://assets/audio/sfx/%s.wav"
const SFX_CATALOG_PATH := "res://data/sfx_catalog.json"
const PLAYER_POOL_SIZE := 12
const MAX_HISTORY := 96
const SFX_VOLUME_OFFSETS_DB: Dictionary = {
	"run_start": -3.0,
	"run_resume": -3.0,
}

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var _players: Array[AudioStreamPlayer] = []
var _stream_cache: Dictionary = {}
var _play_history: Array[String] = []
var _last_sfx_id: String = ""
var _catalog_cache: Array[Dictionary] = []
var _last_relic_play_msec: Dictionary = {}


func _ready() -> void:
	if not _is_headless():
		_ensure_players()
	if not Localization.language_changed.is_connected(_on_language_changed):
		Localization.language_changed.connect(_on_language_changed)
	_apply_master_volume()


func _exit_tree() -> void:
	if Localization.language_changed.is_connected(_on_language_changed):
		Localization.language_changed.disconnect(_on_language_changed)
	for player in _players:
		player.stop()
		player.stream = null
	_play_history.clear()
	_stream_cache.clear()
	_catalog_cache.clear()
	_last_relic_play_msec.clear()
	_players.clear()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_master_volume()


func get_master_volume() -> float:
	return master_volume


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)


func get_sfx_volume() -> float:
	return sfx_volume


func apply_settings(settings: Dictionary) -> void:
	set_master_volume(float(settings.get("master_volume", 1.0)))
	set_sfx_volume(float(settings.get("sfx_volume", 1.0)))


func warm_sfx_cache() -> int:
	var warmed_count: int = 0
	for sfx_id in get_available_sfx_ids():
		if _get_sfx_stream(sfx_id) != null:
			warmed_count += 1
	return warmed_count


func get_available_sfx_ids() -> Array[String]:
	var ids: Array[String] = []
	var directory: DirAccess = DirAccess.open("res://assets/audio/sfx")
	if directory == null:
		return ids
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".wav"):
			ids.append(file_name.get_basename())
		file_name = directory.get_next()
	directory.list_dir_end()
	ids.sort()
	return ids


func get_sfx_catalog() -> Array[Dictionary]:
	if _catalog_cache.is_empty():
		_catalog_cache = _build_sfx_catalog()
	return _catalog_cache.duplicate(true)


func get_cached_sfx_count() -> int:
	return _stream_cache.size()


func has_sfx(sfx_id: String) -> bool:
	return sfx_id != "" and ResourceLoader.exists(SFX_PATH_TEMPLATE % sfx_id)


func play_sfx(sfx_id: String, pitch_scale: float = 1.0, volume_boost_db: float = 0.0) -> bool:
	if sfx_id == "":
		return false

	var stream: AudioStream = _get_sfx_stream(sfx_id)
	if stream == null:
		return false

	_last_sfx_id = sfx_id
	_play_history.append(sfx_id)
	while _play_history.size() > MAX_HISTORY:
		_play_history.remove_at(0)

	if sfx_volume <= 0.0001:
		return true
	if _is_headless():
		return true

	_ensure_players()
	var player: AudioStreamPlayer = _get_available_player()
	if player == null:
		return false

	player.stream = stream
	player.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
	player.volume_db = _resolve_sfx_volume_db(volume_boost_db + get_sfx_volume_offset_db(sfx_id))
	player.play()
	return true


func stop_all_sfx() -> void:
	for player in _players:
		player.stop()
		player.stream = null


func play_card_resolution(card_def: CardDef, fully_blocked_by_shield: bool = false) -> bool:
	if card_def == null:
		return false
	if fully_blocked_by_shield:
		return play_sfx("battle_full_block", 0.92)
	var card_sfx_id: String = "card_%s" % card_def.id
	if has_sfx(card_sfx_id):
		return play_sfx(card_sfx_id)
	return play_sfx(_resolve_card_resolution_sfx(card_def))


func play_relic_proc(relic_id: String, pitch_scale: float = 1.0) -> bool:
	if not _is_headless():
		var now_msec: int = Time.get_ticks_msec()
		var last_msec: int = int(_last_relic_play_msec.get(relic_id, -1000))
		if now_msec - last_msec < 90:
			return true
		_last_relic_play_msec[relic_id] = now_msec
	var relic_sfx_id: String = "relic_%s" % relic_id
	if has_sfx(relic_sfx_id):
		return play_sfx(relic_sfx_id, pitch_scale)
	return play_sfx("relic_proc", pitch_scale)


func play_battle_outcome(winner: String) -> bool:
	match winner:
		"player":
			return play_sfx("battle_victory")
		"enemy":
			return play_sfx("battle_defeat")
		_:
			return play_sfx("battle_tick")


func get_last_sfx_id() -> String:
	return _last_sfx_id


func get_play_history() -> Array[String]:
	return _play_history.duplicate()


func clear_play_history() -> void:
	_play_history.clear()
	_last_sfx_id = ""


func get_sfx_volume_offset_db(sfx_id: String) -> float:
	return float(SFX_VOLUME_OFFSETS_DB.get(sfx_id, 0.0))


func has_played_sfx(sfx_id: String) -> bool:
	return _play_history.has(sfx_id)


func _ensure_players() -> void:
	if _is_headless():
		return
	while _players.size() < PLAYER_POOL_SIZE:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)


func _get_available_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	if _players.is_empty():
		return null
	var fallback: AudioStreamPlayer = _players[0]
	fallback.stop()
	return fallback


func _resolve_sfx_volume_db(volume_boost_db: float) -> float:
	if sfx_volume <= 0.0001:
		return -80.0
	return linear_to_db(sfx_volume) + volume_boost_db


func _get_sfx_stream(sfx_id: String) -> AudioStream:
	if _stream_cache.has(sfx_id):
		return _stream_cache[sfx_id] as AudioStream

	var path: String = SFX_PATH_TEMPLATE % sfx_id
	if not ResourceLoader.exists(path):
		push_error("Missing SFX asset: %s" % path)
		return null

	var resource: Resource = load(path)
	var stream: AudioStream = resource as AudioStream
	if stream == null:
		push_error("Failed to load SFX stream: %s" % path)
		return null

	_stream_cache[sfx_id] = stream
	return stream


func _build_sfx_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog_file: FileAccess = FileAccess.open(SFX_CATALOG_PATH, FileAccess.READ)
	if catalog_file != null:
		var parsed: Variant = JSON.parse_string(catalog_file.get_as_text())
		if parsed is Array:
			for raw_entry: Variant in parsed:
				if not raw_entry is Dictionary:
					continue
				var entry: Dictionary = Dictionary(raw_entry).duplicate(true)
				var sfx_id: String = String(entry.get("id", ""))
				if sfx_id == "":
					continue
				entry["sfx_id"] = sfx_id
				entry["kind"] = "shared"
				entry["available"] = has_sfx(sfx_id)
				result.append(entry)

	var card_ids: Array[String] = Database.get_all_card_ids()
	card_ids.sort()
	for card_id: String in card_ids:
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null:
			continue
		var card_sfx_id: String = "card_%s" % card_id
		result.append({
			"id": card_sfx_id,
			"sfx_id": card_sfx_id,
			"category": "card",
			"kind": "card",
			"source_id": card_id,
			"name_ja": card_def.name,
			"name_en": card_def.name,
			"available": has_sfx(card_sfx_id),
		})

	var relic_ids: Array[String] = Database.get_all_relic_ids()
	relic_ids.sort()
	for relic_id: String in relic_ids:
		var relic_def: RelicDef = Database.get_relic(relic_id)
		if relic_def == null:
			continue
		var relic_sfx_id: String = "relic_%s" % relic_id
		result.append({
			"id": relic_sfx_id,
			"sfx_id": relic_sfx_id,
			"category": "relic",
			"kind": "relic",
			"source_id": relic_id,
			"name_ja": relic_def.name,
			"name_en": relic_def.name,
			"available": has_sfx(relic_sfx_id),
		})
	return result


func _on_language_changed(_language_code: String) -> void:
	_catalog_cache.clear()


func _resolve_card_resolution_sfx(card_def: CardDef) -> String:
	var has_damage: bool = false
	var has_shield: bool = false
	var has_heal: bool = false
	var has_timeline: bool = false
	var has_interrupt: bool = false
	var has_status: bool = false

	for raw_effect in card_def.effects:
		var effect_data: Dictionary = Dictionary(raw_effect)
		var effect_type: String = String(effect_data.get("type", ""))
		match effect_type:
			"deal_damage":
				has_damage = true
			"gain_shield":
				has_shield = true
			"heal":
				has_heal = true
			"delay_enemy_active_card", "haste_own_active_card", "reduce_recast", "auto_queue_card", "timeline_flow":
				has_timeline = true
			"interrupt_card":
				has_interrupt = true
			"apply_status", "remove_status", "modify_attack", "modify_speed", "empower_card":
				has_status = true

	if has_interrupt:
		return "battle_interrupt"
	if has_damage:
		return "battle_attack"
	if has_heal:
		return "battle_heal"
	if has_shield:
		return "battle_guard"
	if has_timeline:
		return "battle_time"
	if has_status:
		return "battle_status"
	return "card_commit"


func _apply_master_volume() -> void:
	if AudioServer.get_bus_count() <= 0:
		return
	if master_volume <= 0.0001:
		AudioServer.set_bus_volume_db(0, -80.0)
		return
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
