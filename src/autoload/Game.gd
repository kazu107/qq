extends Node

const NON_BATTLE_NODE_TYPES := ["shop", "forge", "heal", "event", "hazard"]
const DEVELOPER_META_RESET_POINTS := 10
const DEBUG_EVENT_NODE_ID := "__debug_event__"
const DEFAULT_RESOLUTION := "1920x1080"
const AVAILABLE_RESOLUTION_CODES := ["1280x720", "1600x900", "1920x1080", "2560x1440"]
const REWARD_REROLL_COST: int = 10

var current_run: RunState
var meta_progress: Dictionary = {}
var settings: Dictionary = {
	"master_volume": 1.0,
	"sfx_volume": 1.0,
	"language": Localization.DEFAULT_LANGUAGE,
	"resolution": DEFAULT_RESOLUTION,
	"developer_mode": false,
	"replay_auto_export": true,
	"settings_return_hint": "title",
	"replay_view_path": "",
	"replay_view_return_hint": "result",
	"last_run_starter_id": "",
	"last_run_seed": 0,
}
var pending_enemy_id: String = ""
var reward_options: Array[String] = []
var last_battle_summary: Dictionary = {}
var last_reward_bundle: Dictionary = {}
var last_replay_export_path: String = ""
var current_screen_hint: String = "title"
var _map_generator: MapGenerator = MapGenerator.new()
var _reward_resolver: RewardResolver = RewardResolver.new()
var _shop_service: ShopService = ShopService.new()
var _forge_service: ForgeService = ForgeService.new()
var _relic_service: RelicService = RelicService.new()
var _event_service: EventService = EventService.new()
var _meta_progress_service: MetaProgressService = MetaProgressService.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _applied_resolution: String = ""


func _ready() -> void:
	_rng.randomize()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		persist_settings_for_shutdown()


func persist_settings_for_shutdown() -> bool:
	ensure_meta_initialized()
	return SaveManager.save_game(current_screen_hint)


func ensure_meta_initialized() -> void:
	if meta_progress.is_empty():
		meta_progress = Database.meta_progress_template.duplicate(true)
	if settings.is_empty():
		settings = {
			"master_volume": 1.0,
			"sfx_volume": 1.0,
			"language": Localization.DEFAULT_LANGUAGE,
			"resolution": DEFAULT_RESOLUTION,
			"developer_mode": false,
			"replay_auto_export": true,
			"settings_return_hint": "title",
			"replay_view_path": "",
			"replay_view_return_hint": "result",
			"last_run_starter_id": "",
			"last_run_seed": 0,
		}
	if not settings.has("master_volume"):
		settings["master_volume"] = 1.0
	if not settings.has("sfx_volume"):
		settings["sfx_volume"] = 1.0
	if not settings.has("language"):
		settings["language"] = Localization.DEFAULT_LANGUAGE
	if not settings.has("resolution"):
		settings["resolution"] = DEFAULT_RESOLUTION
	settings["resolution"] = _normalize_resolution_code(String(settings.get("resolution", DEFAULT_RESOLUTION)))
	if not settings.has("developer_mode"):
		settings["developer_mode"] = false
	if not settings.has("replay_auto_export"):
		settings["replay_auto_export"] = true
	if not settings.has("settings_return_hint"):
		settings["settings_return_hint"] = "title"
	if not settings.has("last_replay_export_path"):
		settings["last_replay_export_path"] = ""
	if not settings.has("replay_view_path"):
		settings["replay_view_path"] = ""
	if not settings.has("replay_view_return_hint"):
		settings["replay_view_return_hint"] = "result"
	if not settings.has("last_run_starter_id"):
		settings["last_run_starter_id"] = ""
	if not settings.has("last_run_seed"):
		settings["last_run_seed"] = 0
	last_replay_export_path = String(settings.get("last_replay_export_path", last_replay_export_path))
	_meta_progress_service.ensure_defaults(meta_progress)
	AudioManager.apply_settings(settings)
	_apply_resolution_from_settings()


func apply_loaded_save(save_data: SaveData) -> void:
	meta_progress = save_data.meta_progress.duplicate(true)
	settings = save_data.settings.duplicate(true)
	current_screen_hint = String(settings.get("screen_hint", "title"))
	pending_enemy_id = String(settings.get("pending_enemy_id", ""))
	reward_options = _to_string_array(settings.get("reward_options", []))
	last_battle_summary = Dictionary(settings.get("last_battle_summary", {}))
	last_reward_bundle = Dictionary(settings.get("last_reward_bundle", {}))
	last_replay_export_path = String(settings.get("last_replay_export_path", ""))

	if save_data.current_run.is_empty():
		current_run = null
	else:
		current_run = RunState.from_dict(save_data.current_run)
	ensure_meta_initialized()
	_sync_language_from_settings(false)


func build_save_data(scene_hint: String) -> SaveData:
	current_screen_hint = scene_hint
	ensure_meta_initialized()

	var save_data: SaveData = SaveData.new()
	if current_run != null:
		save_data.current_run = current_run.to_dict()
	else:
		save_data.current_run = {}
	save_data.meta_progress = meta_progress.duplicate(true)
	save_data.settings = settings.duplicate(true)
	save_data.settings["screen_hint"] = current_screen_hint
	save_data.settings["pending_enemy_id"] = pending_enemy_id
	save_data.settings["reward_options"] = reward_options.duplicate()
	save_data.settings["last_battle_summary"] = last_battle_summary.duplicate(true)
	save_data.settings["last_reward_bundle"] = last_reward_bundle.duplicate(true)
	save_data.settings["last_replay_export_path"] = last_replay_export_path
	return save_data


func get_unlocked_starters() -> Array[Dictionary]:
	ensure_meta_initialized()
	var result: Array[Dictionary] = []
	var unlocked_ids: Array[String] = _meta_progress_service.get_unlocked_starters(meta_progress)
	for starter in Database.starters:
		if unlocked_ids.has(String(starter.get("id", ""))):
			result.append(starter)
	return result


func start_new_run(starter_id: String, seed_override: int = 0) -> void:
	ensure_meta_initialized()
	var starter: Dictionary = Database.get_starter(starter_id)
	if starter.is_empty():
		return
	current_run = RunState.from_starter(starter, seed_override)
	_apply_permanent_bonuses_to_run(current_run)
	current_run.map_state = _map_generator.generate_run(current_run.seed)
	pending_enemy_id = ""
	reward_options.clear()
	last_battle_summary.clear()
	last_reward_bundle.clear()
	_meta_progress_service.increment_achievement_stat(meta_progress, "runs_started")
	settings["last_run_starter_id"] = current_run.starter_id
	settings["last_run_seed"] = current_run.seed
	current_screen_hint = "map"
	AudioManager.play_sfx("run_start")
	SaveManager.save_game(current_screen_hint)


func prepare_next_battle() -> String:
	if current_run == null:
		return ""
	_ensure_map_state()
	if pending_enemy_id == "":
		var active_node: Dictionary = get_active_map_node()
		if not active_node.is_empty():
			pending_enemy_id = String(active_node.get("enemy_id", ""))
		if pending_enemy_id == "":
			pending_enemy_id = _roll_enemy_id()
	current_screen_hint = "battle"
	SaveManager.save_game(current_screen_hint)
	return pending_enemy_id


func complete_battle(summary: Dictionary) -> void:
	if current_run == null:
		return
	ensure_meta_initialized()

	last_battle_summary = summary.duplicate(true)
	current_run.player_hp = int(summary.get("player_hp", current_run.player_hp))
	AudioManager.play_battle_outcome(String(summary.get("winner", "")))
	last_battle_summary["starter_id"] = current_run.starter_id
	last_battle_summary["run_seed"] = current_run.seed
	last_battle_summary["encounters_cleared_before_reward"] = current_run.encounters_cleared + (1 if String(summary.get("winner", "")) == "player" else 0)
	last_battle_summary["area"] = int(get_active_map_node().get("area", current_run.current_area))
	last_replay_export_path = ""

	var active_node: Dictionary = get_active_map_node()
	var node_type: String = String(active_node.get("type", ""))
	pending_enemy_id = ""

	if is_replay_auto_export_enabled():
		export_last_battle_replay()

	if String(summary.get("winner", "")) != "player":
		current_run.defeated = true
		current_run.run_complete = true
		reward_options.clear()
		last_reward_bundle.clear()
		current_screen_hint = "result"
		SaveManager.save_game(current_screen_hint)
		return

	_meta_progress_service.increment_achievement_stat(meta_progress, "victories")
	if node_type == "boss" or String(summary.get("enemy_id", "")) == "boss_timekeeper":
		_meta_progress_service.increment_achievement_stat(meta_progress, "boss_wins")

	current_run.encounters_cleared += 1
	if not active_node.is_empty():
		current_run.current_area = int(active_node.get("area", current_run.current_area))
	else:
		current_run.current_area = min(3, current_run.encounters_cleared + 1)

	var relic_bonuses: Dictionary = _relic_service.apply_victory_bonuses(current_run)
	var relic_bonus_parts: Array[String] = []
	var relic_bonus_gold: int = int(relic_bonuses.get("gold", 0))
	var relic_bonus_heal: int = int(relic_bonuses.get("heal", 0))
	if relic_bonus_gold > 0:
		relic_bonus_parts.append("+%d gold from relics" % relic_bonus_gold)
	if relic_bonus_heal > 0:
		relic_bonus_parts.append("+%d HP from relics" % relic_bonus_heal)
	if not relic_bonus_parts.is_empty():
		last_battle_summary["relic_bonus_text"] = ", ".join(relic_bonus_parts)
	else:
		last_battle_summary.erase("relic_bonus_text")

	match node_type:
		"boss":
			_handle_battle_reward("boss", true)
		"elite_battle":
			_handle_battle_reward("elite")
		"hazard":
			_handle_hazard_victory()
		_:
			_handle_battle_reward("normal")

	SaveManager.save_game(current_screen_hint)


func choose_reward(card_id: String) -> void:
	if current_run == null:
		return
	if card_id != "":
		current_run.player_cards.append(card_id)
		_auto_equip_card_if_room(card_id)
		AudioManager.play_sfx("reward_pick")
	reward_options.clear()
	last_reward_bundle.clear()
	_complete_active_map_node_and_advance()
	current_screen_hint = _get_post_progress_scene_hint()
	SaveManager.save_game(current_screen_hint)


func skip_reward() -> void:
	AudioManager.play_sfx("reward_skip")
	reward_options.clear()
	last_reward_bundle.clear()
	_complete_active_map_node_and_advance()
	current_screen_hint = _get_post_progress_scene_hint()
	SaveManager.save_game(current_screen_hint)


func get_reward_reroll_cost() -> int:
	return REWARD_REROLL_COST


func can_reroll_rewards() -> bool:
	if current_run == null or reward_options.is_empty():
		return false
	return current_run.gold >= REWARD_REROLL_COST


func reroll_rewards_for_gold() -> bool:
	if current_run == null or reward_options.is_empty():
		AudioManager.play_sfx("ui_error")
		return false
	if current_run.gold < REWARD_REROLL_COST:
		AudioManager.play_sfx("ui_error")
		return false

	var rerolled_options: Array[String] = _reroll_reward_options()
	if rerolled_options.is_empty():
		AudioManager.play_sfx("ui_error")
		return false

	current_run.gold = max(0, current_run.gold - REWARD_REROLL_COST)
	AudioManager.play_sfx("shop_buy")
	SaveManager.save_game(current_screen_hint)
	return true


func get_run_summary() -> Dictionary:
	if current_run == null:
		return {}
	return RunSummaryResolver.new().summarize(current_run, last_battle_summary)


func abandon_run_to_hub() -> void:
	current_run = null
	pending_enemy_id = ""
	reward_options.clear()
	last_battle_summary.clear()
	last_reward_bundle.clear()
	current_screen_hint = "hub"
	SaveManager.save_game(current_screen_hint)


func has_active_run() -> bool:
	return current_run != null and not current_run.run_complete


func get_meta_points() -> int:
	ensure_meta_initialized()
	return int(meta_progress.get("points", 0))


func get_best_clear() -> int:
	ensure_meta_initialized()
	return int(meta_progress.get("best_clear", 0))


func get_unlocked_card_ids() -> Array[String]:
	ensure_meta_initialized()
	return _meta_progress_service.get_unlocked_cards(meta_progress)


func get_unlocked_relic_ids() -> Array[String]:
	ensure_meta_initialized()
	return _meta_progress_service.get_unlocked_relics(meta_progress)


func is_card_meta_unlocked(card_id: String) -> bool:
	ensure_meta_initialized()
	return _meta_progress_service.is_card_unlocked(meta_progress, card_id)


func is_relic_meta_unlocked(relic_id: String) -> bool:
	ensure_meta_initialized()
	return _meta_progress_service.is_relic_unlocked(meta_progress, relic_id)


func get_meta_summary() -> Dictionary:
	var starter_entries: Array[Dictionary] = get_meta_starter_entries()
	var card_entries: Array[Dictionary] = get_meta_card_entries()
	var relic_entries: Array[Dictionary] = get_meta_relic_entries()
	var achievement_entries: Array[Dictionary] = get_meta_achievement_entries()
	var unlocked_card_count: int = 0
	var unlocked_relic_count: int = 0
	var claimed_achievement_count: int = 0
	var claimable_achievement_count: int = 0
	for entry in card_entries:
		if bool(entry.get("unlocked", false)):
			unlocked_card_count += 1
	for entry in relic_entries:
		if bool(entry.get("unlocked", false)):
			unlocked_relic_count += 1
	for entry in achievement_entries:
		if bool(entry.get("claimed", false)):
			claimed_achievement_count += 1
		elif bool(entry.get("claimable", false)):
			claimable_achievement_count += 1
	return {
		"points": get_meta_points(),
		"best_clear": get_best_clear(),
		"starter_unlocked": get_unlocked_starters().size(),
		"starter_total": starter_entries.size(),
		"card_unlocked": unlocked_card_count,
		"card_total": card_entries.size(),
		"relic_unlocked": unlocked_relic_count,
		"relic_total": relic_entries.size(),
		"achievement_claimed": claimed_achievement_count,
		"achievement_total": achievement_entries.size(),
		"achievement_claimable": claimable_achievement_count,
		"permanent_bonus_text": get_permanent_bonus_summary(),
	}


func get_meta_starter_entries() -> Array[Dictionary]:
	ensure_meta_initialized()
	return _meta_progress_service.build_starter_entries(meta_progress)


func get_meta_card_entries() -> Array[Dictionary]:
	ensure_meta_initialized()
	return _meta_progress_service.build_card_entries(meta_progress)


func get_meta_relic_entries() -> Array[Dictionary]:
	ensure_meta_initialized()
	return _meta_progress_service.build_relic_entries(meta_progress)


func get_meta_achievement_entries() -> Array[Dictionary]:
	ensure_meta_initialized()
	return _meta_progress_service.build_achievement_entries(meta_progress)


func get_permanent_bonuses() -> Dictionary:
	ensure_meta_initialized()
	return _meta_progress_service.get_permanent_bonuses(meta_progress)


func get_permanent_bonus_summary() -> String:
	var bonuses: Dictionary = get_permanent_bonuses()
	var parts: Array[String] = []
	var max_hp_bonus: int = int(bonuses.get("max_hp", 0))
	var attack_bonus: int = int(bonuses.get("attack", 0))
	var speed_bonus: int = int(bonuses.get("speed", 0))
	var loadout_bonus: int = int(bonuses.get("loadout_limit", 0))
	if max_hp_bonus != 0:
		parts.append(Localization.get_textf("stat.summary.max_hp", "HP +{amount}", {"amount": max_hp_bonus}))
	if attack_bonus != 0:
		parts.append(Localization.get_textf("stat.summary.attack", "Attack +{amount}", {"amount": attack_bonus}))
	if speed_bonus != 0:
		parts.append(Localization.get_textf("stat.summary.speed", "Speed +{amount}", {"amount": speed_bonus}))
	if loadout_bonus != 0:
		parts.append(Localization.get_textf("stat.summary.loadout", "Loadout +{amount}", {"amount": loadout_bonus}))
	if parts.is_empty():
		return Localization.get_text("meta.bonus_none", "None")
	return ", ".join(parts)


func unlock_meta_starter(starter_id: String) -> bool:
	ensure_meta_initialized()
	var unlocked: bool = _meta_progress_service.unlock_starter(meta_progress, starter_id)
	if unlocked:
		AudioManager.play_sfx("meta_unlock")
		SaveManager.save_game(current_screen_hint)
	return unlocked


func unlock_meta_card(card_id: String) -> bool:
	ensure_meta_initialized()
	var unlocked: bool = _meta_progress_service.unlock_card(meta_progress, card_id)
	if unlocked:
		AudioManager.play_sfx("meta_unlock")
		SaveManager.save_game(current_screen_hint)
	return unlocked


func unlock_meta_relic(relic_id: String) -> bool:
	ensure_meta_initialized()
	var unlocked: bool = _meta_progress_service.unlock_relic(meta_progress, relic_id)
	if unlocked:
		AudioManager.play_sfx("meta_unlock")
		SaveManager.save_game(current_screen_hint)
	return unlocked


func claim_meta_achievement(achievement_id: String) -> bool:
	ensure_meta_initialized()
	var claimed: bool = _meta_progress_service.claim_achievement(meta_progress, achievement_id)
	if claimed:
		AudioManager.play_sfx("meta_unlock")
		SaveManager.save_game(current_screen_hint)
	return claimed


func get_card_library_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for card_id in Database.get_all_card_ids():
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null:
			continue
		entries.append({
			"card_id": card_id,
			"unlocked": is_card_meta_unlocked(card_id),
			"rarity": card_def.rarity,
			"name": card_def.name,
			"description": card_def.description,
		})
	return entries


func get_master_volume() -> float:
	ensure_meta_initialized()
	return float(settings.get("master_volume", 1.0))


func get_sfx_volume() -> float:
	ensure_meta_initialized()
	return float(settings.get("sfx_volume", 1.0))


func get_language() -> String:
	ensure_meta_initialized()
	return String(settings.get("language", Localization.DEFAULT_LANGUAGE))


func get_available_languages() -> Array[Dictionary]:
	return Localization.get_supported_languages()


func get_resolution() -> String:
	ensure_meta_initialized()
	return String(settings.get("resolution", DEFAULT_RESOLUTION))


func get_available_resolutions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_resolution_code in AVAILABLE_RESOLUTION_CODES:
		var resolution_code: String = String(raw_resolution_code)
		var resolution_size: Vector2i = _parse_resolution_code(resolution_code)
		result.append({
			"code": resolution_code,
			"label": "%d x %d" % [resolution_size.x, resolution_size.y],
			"width": resolution_size.x,
			"height": resolution_size.y,
		})
	return result


func set_master_volume(value: float) -> void:
	ensure_meta_initialized()
	settings["master_volume"] = clampf(value, 0.0, 1.0)
	AudioManager.apply_settings(settings)
	SaveManager.save_game(current_screen_hint)


func set_sfx_volume(value: float) -> void:
	ensure_meta_initialized()
	settings["sfx_volume"] = clampf(value, 0.0, 1.0)
	AudioManager.apply_settings(settings)
	SaveManager.save_game(current_screen_hint)


func set_language(language_code: String) -> void:
	ensure_meta_initialized()
	settings["language"] = Localization.normalize_language_code(language_code)
	_sync_language_from_settings(true)
	SaveManager.save_game(current_screen_hint)


func set_resolution(resolution_code: String) -> void:
	ensure_meta_initialized()
	settings["resolution"] = _normalize_resolution_code(resolution_code)
	_apply_resolution_from_settings(true)
	SaveManager.save_game(current_screen_hint)


func is_replay_auto_export_enabled() -> bool:
	ensure_meta_initialized()
	return bool(settings.get("replay_auto_export", true))


func set_replay_auto_export_enabled(enabled: bool) -> void:
	ensure_meta_initialized()
	settings["replay_auto_export"] = enabled
	SaveManager.save_game(current_screen_hint)


func get_last_replay_export_path() -> String:
	return last_replay_export_path


func get_replay_view_path() -> String:
	ensure_meta_initialized()
	return String(settings.get("replay_view_path", ""))


func get_replay_view_return_hint() -> String:
	ensure_meta_initialized()
	return String(settings.get("replay_view_return_hint", "result"))


func get_replay_view_data() -> Dictionary:
	var replay_path: String = get_replay_view_path()
	if replay_path == "":
		return {}
	return _load_json_dictionary_file(replay_path)


func get_last_reward_bundle() -> Dictionary:
	return last_reward_bundle.duplicate(true)


func open_settings(return_hint: String) -> void:
	ensure_meta_initialized()
	settings["settings_return_hint"] = return_hint
	current_screen_hint = "settings"
	SaveManager.save_game("settings")


func get_settings_return_hint() -> String:
	ensure_meta_initialized()
	return String(settings.get("settings_return_hint", "title"))


func reset_settings_to_defaults() -> void:
	var developer_mode: bool = is_developer_mode_enabled()
	settings = {
		"master_volume": 1.0,
		"sfx_volume": 1.0,
		"language": get_language(),
		"resolution": DEFAULT_RESOLUTION,
		"developer_mode": developer_mode,
		"replay_auto_export": true,
		"settings_return_hint": get_settings_return_hint(),
		"last_replay_export_path": last_replay_export_path,
		"replay_view_path": get_replay_view_path(),
		"replay_view_return_hint": get_replay_view_return_hint(),
		"last_run_starter_id": String(settings.get("last_run_starter_id", "")),
		"last_run_seed": int(settings.get("last_run_seed", 0)),
	}
	AudioManager.apply_settings(settings)
	_apply_resolution_from_settings(true)
	SaveManager.save_game(current_screen_hint)


func export_last_battle_replay() -> String:
	if last_battle_summary.is_empty():
		return ""
	var replay_data: ReplayData = ReplayData.from_summary(last_battle_summary)
	var battle_id: String = String(last_battle_summary.get("battle_id", ""))
	last_replay_export_path = SaveManager.export_replay(replay_data, battle_id)
	settings["last_replay_export_path"] = last_replay_export_path
	SaveManager.save_game(current_screen_hint)
	return last_replay_export_path


func open_last_replay_view(return_hint: String = "result") -> bool:
	return open_replay_view(last_replay_export_path, return_hint)


func open_replay_view(replay_path: String, return_hint: String = "result") -> bool:
	if replay_path == "":
		return false
	var replay_data: Dictionary = _load_json_dictionary_file(replay_path)
	if replay_data.is_empty():
		return false
	settings["replay_view_path"] = replay_path
	settings["replay_view_return_hint"] = return_hint
	current_screen_hint = "replay"
	SaveManager.save_game(current_screen_hint)
	return true


func can_retry_last_seed_run() -> bool:
	ensure_meta_initialized()
	return String(settings.get("last_run_starter_id", "")) != "" and int(settings.get("last_run_seed", 0)) > 0


func retry_last_seed_run() -> bool:
	if current_run != null and current_run.starter_id != "" and current_run.seed > 0:
		start_new_run(current_run.starter_id, current_run.seed)
		return true
	ensure_meta_initialized()
	var starter_id: String = String(settings.get("last_run_starter_id", ""))
	var seed_value: int = int(settings.get("last_run_seed", 0))
	if starter_id == "" or seed_value <= 0:
		return false
	start_new_run(starter_id, seed_value)
	return true


func is_developer_mode_enabled() -> bool:
	ensure_meta_initialized()
	return bool(settings.get("developer_mode", false))


func set_developer_mode_enabled(enabled: bool) -> void:
	ensure_meta_initialized()
	settings["developer_mode"] = enabled
	SaveManager.save_game(current_screen_hint)


func toggle_developer_mode() -> bool:
	var enabled: bool = not is_developer_mode_enabled()
	set_developer_mode_enabled(enabled)
	return enabled


func developer_start_run(starter_id: String = "balanced") -> void:
	start_new_run(starter_id)


func developer_open_battle(enemy_id: String = "scout", starter_id: String = "balanced") -> void:
	if current_run == null or current_run.run_complete:
		start_new_run(starter_id)
	pending_enemy_id = enemy_id
	reward_options.clear()
	last_battle_summary.clear()
	last_reward_bundle.clear()
	current_screen_hint = "battle"
	SaveManager.save_game(current_screen_hint)


func developer_open_custom_battle(enemy_id: String, starter_id: String, card_ids: Array[String], card_tiers: Dictionary = {}) -> void:
	var resolved_enemy_id: String = enemy_id
	if Database.get_enemy(resolved_enemy_id) == null:
		resolved_enemy_id = "scout"

	var resolved_starter_id: String = starter_id
	if Database.get_starter(resolved_starter_id).is_empty():
		resolved_starter_id = "balanced"

	start_new_run(resolved_starter_id)
	var valid_card_ids: Array[String] = _filter_valid_card_ids(card_ids)
	if not valid_card_ids.is_empty():
		current_run.player_cards = valid_card_ids.duplicate()
		current_run.loadout_limit = maxi(current_run.loadout_limit, RunState.get_total_loadout_cost(valid_card_ids))
		current_run.equipped_cards = valid_card_ids.duplicate()
		current_run.card_upgrades.clear()
		for card_id in valid_card_ids:
			var tier: int = clampi(int(card_tiers.get(card_id, 0)), 0, CardUpgradeResolver.MAX_TIER)
			if tier > 0:
				current_run.card_upgrades[card_id] = tier

	pending_enemy_id = resolved_enemy_id
	reward_options.clear()
	last_battle_summary.clear()
	last_reward_bundle.clear()
	current_screen_hint = "battle"
	SaveManager.save_game(current_screen_hint)


func developer_open_reward(starter_id: String = "balanced") -> void:
	if current_run == null or current_run.run_complete:
		start_new_run(starter_id)
	pending_enemy_id = ""
	current_screen_hint = "reward"
	last_battle_summary = {
		"enemy_name": Localization.get_text("game.debug_target", "Debug Target"),
		"winner": "player",
		"bonus_text": Localization.get_text("game.dev_reward_preview_base", "Developer reward preview"),
	}
	developer_open_reward_preview("normal", current_run.current_area)
	SaveManager.save_game(current_screen_hint)


func developer_open_event(event_id: String, area: int = -1, starter_id: String = "balanced") -> void:
	if current_run == null or current_run.run_complete:
		start_new_run(starter_id)

	_ensure_map_state()
	var resolved_area: int = area
	if resolved_area < 1:
		resolved_area = current_run.current_area
	var debug_node: Dictionary = _event_service.build_specific_event_node(
		event_id,
		resolved_area,
		current_run,
		get_unlocked_card_ids(),
		get_unlocked_relic_ids()
	)
	if debug_node.is_empty():
		return

	debug_node["id"] = DEBUG_EVENT_NODE_ID
	debug_node["type"] = "event"
	debug_node["label"] = Localization.get_text("game.debug_event", "Debug Event")
	debug_node["area"] = resolved_area
	debug_node["status"] = "selected"
	current_run.map_state["debug_active_node"] = debug_node
	current_run.map_state["active_node_id"] = DEBUG_EVENT_NODE_ID
	pending_enemy_id = ""
	reward_options.clear()
	last_reward_bundle.clear()
	current_screen_hint = "facility"
	SaveManager.save_game(current_screen_hint)


func developer_open_result(starter_id: String = "balanced") -> void:
	if current_run == null:
		start_new_run(starter_id)
	current_run.run_complete = true
	current_run.defeated = false
	current_run.current_area = max(current_run.current_area, 3)
	current_run.encounters_cleared = max(current_run.encounters_cleared, 4)
	pending_enemy_id = ""
	reward_options.clear()
	last_battle_summary = {
		"enemy_name": Localization.get_text("game.debug_target", "Debug Target"),
		"winner": "player",
	}
	last_reward_bundle.clear()
	current_screen_hint = "result"
	SaveManager.save_game(current_screen_hint)


func developer_add_gold(amount: int = 50) -> int:
	if current_run == null:
		return 0
	current_run.gold += amount
	AudioManager.play_sfx("gold_gain")
	SaveManager.save_game(current_screen_hint)
	return current_run.gold


func developer_add_points(amount: int = 5) -> int:
	ensure_meta_initialized()
	meta_progress["points"] = int(meta_progress.get("points", 0)) + amount
	AudioManager.play_sfx("meta_points")
	SaveManager.save_game(current_screen_hint)
	return int(meta_progress.get("points", 0))


func developer_add_achievement_stat(stat_id: String, amount: int = 1) -> int:
	ensure_meta_initialized()
	var next_value: int = _meta_progress_service.increment_achievement_stat(meta_progress, stat_id, amount)
	SaveManager.save_game(current_screen_hint)
	return next_value


func developer_restore_hp() -> int:
	if current_run == null:
		return 0
	current_run.player_hp = current_run.max_hp
	AudioManager.play_sfx("heal_use")
	SaveManager.save_game(current_screen_hint)
	return current_run.player_hp


func developer_grant_random_relic() -> String:
	if current_run == null:
		return ""
	var relic_id: String = _relic_service.roll_random_relic(current_run.relics, get_unlocked_relic_ids())
	if relic_id == "" or not _relic_service.grant_relic(current_run, relic_id):
		return ""
	AudioManager.play_sfx("relic_gain")
	SaveManager.save_game(current_screen_hint)
	var relic_def: RelicDef = Database.get_relic(relic_id)
	if relic_def == null:
		return relic_id
	return relic_def.name


func developer_reroll_rewards() -> Array[String]:
	if current_run == null:
		return []
	var rerolled_options: Array[String] = _reroll_reward_options()
	if rerolled_options.is_empty():
		AudioManager.play_sfx("ui_error")
		return []
	AudioManager.play_sfx("ui_toggle")
	SaveManager.save_game(current_screen_hint)
	return rerolled_options


func developer_open_reward_preview(reward_key: String, area: int = -1) -> Dictionary:
	if current_run == null or current_run.run_complete:
		start_new_run("balanced")
	var resolved_area: int = area
	if resolved_area < 1:
		resolved_area = current_run.current_area
	last_reward_bundle = preview_reward_package(reward_key, resolved_area)
	reward_options = _to_string_array(last_reward_bundle.get("options", []))
	last_battle_summary["bonus_text"] = Localization.get_textf(
		"game.dev_reward_preview",
		"Developer {reward_name} reward preview",
		{"reward_name": Localization.get_reward_name(reward_key)}
	)
	current_screen_hint = "reward"
	SaveManager.save_game(current_screen_hint)
	return last_reward_bundle.duplicate(true)


func developer_unlock_all_meta() -> void:
	ensure_meta_initialized()
	_meta_progress_service.unlock_all(meta_progress)
	AudioManager.play_sfx("meta_unlock")
	SaveManager.save_game(current_screen_hint)


func developer_reset_meta_progress() -> void:
	meta_progress = _meta_progress_service.reset({}, Database.meta_progress_template)
	meta_progress["points"] = DEVELOPER_META_RESET_POINTS
	AudioManager.play_sfx("meta_points")
	SaveManager.save_game(current_screen_hint)


func developer_select_available_node(node_type: String) -> String:
	if current_run == null:
		return ""
	var current_step: Dictionary = get_current_step_data()
	var nodes: Array = Array(current_step.get("nodes", []))
	for raw_node in nodes:
		var node_data: Dictionary = Dictionary(raw_node)
		if String(node_data.get("type", "")) != node_type:
			continue
		if String(node_data.get("status", "")) != "available":
			continue
		return select_map_node(String(node_data.get("id", "")))
	return ""


func get_available_event_debug_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for event_id in Database.get_all_event_ids():
		entries.append({
			"id": event_id,
			"title": _event_service.get_event_title(event_id),
		})
	return entries


func get_debug_battle_enemy_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for raw_enemy_id in Database.enemies.keys():
		var enemy_id: String = String(raw_enemy_id)
		var enemy_def: EnemyDef = Database.get_enemy(enemy_id)
		if enemy_def == null:
			continue
		entries.append({
			"id": enemy_id,
			"name": enemy_def.name,
		})
	return entries


func get_debug_battle_starter_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for starter in Database.starters:
		var starter_id: String = String(starter.get("id", ""))
		if starter_id == "":
			continue
		entries.append({
			"id": starter_id,
			"name": String(starter.get("name", starter_id)),
		})
	return entries


func get_debug_battle_card_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for card_id in Database.get_all_card_ids():
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null:
			continue
		entries.append({
			"id": card_id,
			"name": card_def.name,
			"rarity": card_def.rarity,
			"loadout_cost": card_def.loadout_cost,
		})
	return entries


func get_map_steps() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if current_run == null:
		return result
	_ensure_map_state()
	var steps: Array = Array(current_run.map_state.get("steps", []))
	for raw_step in steps:
		result.append(Dictionary(raw_step))
	return result


func get_current_step_index() -> int:
	if current_run == null:
		return 0
	_ensure_map_state()
	return int(current_run.map_state.get("current_step", 0))


func get_map_step_count() -> int:
	return get_map_steps().size()


func get_current_step_data() -> Dictionary:
	var steps: Array[Dictionary] = get_map_steps()
	var step_index: int = get_current_step_index()
	if step_index < 0 or step_index >= steps.size():
		return {}
	return steps[step_index]


func get_active_map_node() -> Dictionary:
	if current_run == null:
		return {}
	_ensure_map_state()
	var active_node_id: String = String(current_run.map_state.get("active_node_id", ""))
	if active_node_id == "":
		return {}
	if active_node_id == DEBUG_EVENT_NODE_ID:
		return Dictionary(current_run.map_state.get("debug_active_node", {})).duplicate(true)

	var location: Dictionary = _find_node_location(active_node_id)
	if location.is_empty():
		return {}
	return _get_node(
		int(location.get("step_index", -1)),
		int(location.get("node_index", -1))
	)


func get_active_facility_type() -> String:
	var active_node: Dictionary = get_active_map_node()
	if active_node.is_empty():
		return ""
	var node_type: String = String(active_node.get("type", ""))
	if NON_BATTLE_NODE_TYPES.has(node_type):
		return node_type
	return ""


func get_shop_offers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var active_node: Dictionary = get_active_map_node()
	if String(active_node.get("type", "")) != "shop":
		return result
	var offers: Array = Array(active_node.get("shop_offers", []))
	for raw_offer in offers:
		result.append(Dictionary(raw_offer))
	return result


func get_forge_options() -> Array[String]:
	var active_node: Dictionary = get_active_map_node()
	if String(active_node.get("type", "")) != "forge":
		return []
	return _to_string_array(active_node.get("forge_options", []))


func get_active_event_data() -> Dictionary:
	var active_node: Dictionary = get_active_map_node()
	if String(active_node.get("type", "")) != "event":
		return {}
	return {
		"id": String(active_node.get("event_id", "")),
		"title": String(active_node.get("event_title", "Event")),
		"description": String(active_node.get("event_description", "")),
		"choices": Array(active_node.get("event_choices", [])),
	}


func get_hazard_status() -> Dictionary:
	var active_node: Dictionary = get_active_map_node()
	if String(active_node.get("type", "")) != "hazard":
		return {}
	var queue: Array[String] = _to_string_array(active_node.get("hazard_queue", []))
	var cleared_waves: int = int(active_node.get("hazard_cleared_waves", 0))
	return {
		"title": Localization.get_text("hazard.title", String(active_node.get("hazard_title", "Hazard Zone"))),
		"description": Localization.get_text("hazard.description", String(active_node.get("hazard_description", ""))),
		"waves_total": queue.size(),
		"waves_cleared": cleared_waves,
		"next_enemy": _hazard_next_enemy_name(queue, cleared_waves),
		"wave_gold": int(active_node.get("hazard_wave_gold", 0)),
		"wave_heal": int(active_node.get("hazard_wave_heal", 0)),
	}


func get_last_battle_enemy_name() -> String:
	var enemy_id: String = String(last_battle_summary.get("enemy_id", ""))
	return Localization.get_enemy_name(enemy_id, String(last_battle_summary.get("enemy_name", "")))


func get_last_battle_winner_name() -> String:
	return Localization.get_winner_name(String(last_battle_summary.get("winner", "")))


func get_equipped_cards() -> Array[String]:
	if current_run == null:
		return []
	return current_run.equipped_cards.duplicate()


func get_current_loadout_cost() -> int:
	if current_run == null:
		return 0
	return RunState.get_total_loadout_cost(current_run.equipped_cards)


func get_loadout_limit() -> int:
	if current_run == null:
		return 0
	return current_run.loadout_limit


func get_loadout_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if current_run == null:
		return result

	var seen: Dictionary = {}
	var current_cost: int = get_current_loadout_cost()
	for card_id in current_run.player_cards:
		if seen.has(card_id):
			continue
		seen[card_id] = true
		var card_def: CardDef = Database.get_card(card_id)
		var owned_count: int = _count_card_occurrences(current_run.player_cards, card_id)
		var equipped_count: int = _count_card_occurrences(current_run.equipped_cards, card_id)
		var loadout_cost: int = 0
		if card_def != null:
			loadout_cost = card_def.loadout_cost
		result.append({
			"card_id": card_id,
			"owned_count": owned_count,
			"equipped_count": equipped_count,
			"loadout_cost": loadout_cost,
			"can_equip": equipped_count < owned_count and current_cost + loadout_cost <= current_run.loadout_limit,
			"can_unequip": equipped_count > 0 and current_run.equipped_cards.size() > 1,
		})
	return result


func get_relic_names() -> Array[String]:
	if current_run == null:
		return []
	return _relic_service.get_relic_names(current_run.relics)


func equip_card(card_id: String) -> bool:
	if current_run == null:
		return false
	if _count_card_occurrences(current_run.equipped_cards, card_id) >= _count_card_occurrences(current_run.player_cards, card_id):
		return false
	var card_def: CardDef = Database.get_card(card_id)
	if card_def == null:
		return false
	if get_current_loadout_cost() + card_def.loadout_cost > current_run.loadout_limit:
		return false
	current_run.equipped_cards.append(card_id)
	AudioManager.play_sfx("loadout_equip")
	SaveManager.save_game(current_screen_hint)
	return true


func unequip_card(card_id: String) -> bool:
	if current_run == null or current_run.equipped_cards.size() <= 1:
		return false
	for index in range(current_run.equipped_cards.size() - 1, -1, -1):
		if current_run.equipped_cards[index] == card_id:
			current_run.equipped_cards.remove_at(index)
			AudioManager.play_sfx("loadout_unequip")
			SaveManager.save_game(current_screen_hint)
			return true
	return false


func select_map_node(node_id: String) -> String:
	if current_run == null or node_id == "":
		return ""
	_ensure_map_state()

	var location: Dictionary = _find_node_location(node_id)
	if location.is_empty():
		return ""

	var step_index: int = int(location.get("step_index", -1))
	var node_index: int = int(location.get("node_index", -1))
	var node_data: Dictionary = _get_node(step_index, node_index)
	if String(node_data.get("status", "")) != "available":
		return ""

	var node_type: String = String(node_data.get("type", ""))
	if not NON_BATTLE_NODE_TYPES.has(node_type) and not _has_valid_loadout():
		return ""

	node_data["status"] = "selected"
	_set_node(step_index, node_index, node_data)
	current_run.map_state["current_step"] = step_index
	current_run.map_state["active_node_id"] = node_id
	pending_enemy_id = String(node_data.get("enemy_id", ""))

	if NON_BATTLE_NODE_TYPES.has(node_type):
		_prepare_non_battle_node(step_index, node_index)
		current_screen_hint = "facility"
	else:
		current_screen_hint = "battle"
	AudioManager.play_sfx("map_select")
	SaveManager.save_game(current_screen_hint)
	return current_screen_hint


func buy_shop_offer(offer_index: int) -> bool:
	if current_run == null:
		return false

	var location: Dictionary = _get_active_node_location()
	if location.is_empty():
		return false

	var step_index: int = int(location.get("step_index", -1))
	var node_index: int = int(location.get("node_index", -1))
	var node_data: Dictionary = _get_node(step_index, node_index)
	if String(node_data.get("type", "")) != "shop":
		return false

	var offers: Array = Array(node_data.get("shop_offers", []))
	if offer_index < 0 or offer_index >= offers.size():
		return false

	var offer_data: Dictionary = Dictionary(offers[offer_index])
	if bool(offer_data.get("bought", false)):
		return false

	var card_id: String = String(offer_data.get("card_id", ""))
	var price: int = int(offer_data.get("price", 0))
	if not _shop_service.buy_card(current_run, card_id, price):
		return false

	offer_data["bought"] = true
	offers[offer_index] = offer_data
	node_data["shop_offers"] = offers
	_set_node(step_index, node_index, node_data)
	_auto_equip_card_if_room(card_id)
	AudioManager.play_sfx("shop_buy")
	SaveManager.save_game(current_screen_hint)
	return true


func upgrade_forge_card(card_id: String) -> int:
	if current_run == null:
		return 0

	var location: Dictionary = _get_active_node_location()
	if location.is_empty():
		return 0

	var step_index: int = int(location.get("step_index", -1))
	var node_index: int = int(location.get("node_index", -1))
	var node_data: Dictionary = _get_node(step_index, node_index)
	if String(node_data.get("type", "")) != "forge":
		return CardUpgradeResolver.get_tier(current_run, card_id)
	if bool(node_data.get("forge_used", false)):
		return CardUpgradeResolver.get_tier(current_run, card_id)

	var options: Array[String] = _to_string_array(node_data.get("forge_options", []))
	if not options.has(card_id):
		return CardUpgradeResolver.get_tier(current_run, card_id)

	var new_tier: int = _forge_service.upgrade_card(current_run, card_id)
	node_data["forge_used"] = true
	_set_node(step_index, node_index, node_data)
	AudioManager.play_sfx("forge_upgrade")
	SaveManager.save_game(current_screen_hint)
	return new_tier


func use_heal_node() -> int:
	if current_run == null:
		return 0
	var active_node: Dictionary = get_active_map_node()
	if String(active_node.get("type", "")) != "heal":
		return 0
	var heal_amount: int = int(active_node.get("heal_amount", 0))
	var before_hp: int = current_run.player_hp
	current_run.player_hp = min(current_run.max_hp, current_run.player_hp + heal_amount)
	_complete_active_map_node_and_advance()
	current_screen_hint = _get_post_progress_scene_hint()
	AudioManager.play_sfx("heal_use")
	SaveManager.save_game(current_screen_hint)
	return current_run.player_hp - before_hp


func resolve_event_choice(choice_id: String) -> String:
	if current_run == null:
		return ""
	var active_node: Dictionary = get_active_map_node()
	if String(active_node.get("type", "")) != "event":
		return ""

	var resolved_choice: Dictionary = _get_event_choice(active_node, choice_id)
	if resolved_choice.is_empty() or not bool(resolved_choice.get("enabled", true)):
		return ""
	var result_text: String = _apply_event_choice(resolved_choice)
	if result_text == "":
		return ""

	_complete_active_map_node_and_advance()
	current_screen_hint = _get_post_progress_scene_hint()
	AudioManager.play_sfx("event_resolve")
	SaveManager.save_game(current_screen_hint)
	return result_text


func continue_hazard() -> bool:
	if current_run == null:
		return false
	var location: Dictionary = _get_active_node_location()
	if location.is_empty():
		return false

	var step_index: int = int(location.get("step_index", -1))
	var node_index: int = int(location.get("node_index", -1))
	var node_data: Dictionary = _get_node(step_index, node_index)
	if String(node_data.get("type", "")) != "hazard":
		return false

	var queue: Array[String] = _to_string_array(node_data.get("hazard_queue", []))
	var cleared_waves: int = int(node_data.get("hazard_cleared_waves", 0))
	if cleared_waves >= queue.size():
		return false

	pending_enemy_id = queue[cleared_waves]
	node_data["hazard_started"] = true
	_set_node(step_index, node_index, node_data)
	current_screen_hint = "battle"
	AudioManager.play_sfx("hazard_enter")
	SaveManager.save_game(current_screen_hint)
	return true


func withdraw_hazard() -> void:
	if current_run == null:
		return
	_complete_active_map_node_and_advance()
	current_screen_hint = _get_post_progress_scene_hint()
	AudioManager.play_sfx("hazard_withdraw")
	SaveManager.save_game(current_screen_hint)


func leave_facility() -> void:
	if current_run == null:
		return
	if get_active_facility_type() == "hazard":
		withdraw_hazard()
		return
	_complete_active_map_node_and_advance()
	current_screen_hint = _get_post_progress_scene_hint()
	SaveManager.save_game(current_screen_hint)


func _apply_permanent_bonuses_to_run(run_state: RunState) -> void:
	if run_state == null:
		return
	var bonuses: Dictionary = _meta_progress_service.get_permanent_bonuses(meta_progress)
	var max_hp_bonus: int = int(bonuses.get("max_hp", 0))
	var attack_bonus: int = int(bonuses.get("attack", 0))
	var speed_bonus: int = int(bonuses.get("speed", 0))
	var loadout_bonus: int = int(bonuses.get("loadout_limit", 0))
	if max_hp_bonus != 0:
		run_state.max_hp = max(1, run_state.max_hp + max_hp_bonus)
		run_state.player_hp = run_state.max_hp
	if attack_bonus != 0:
		run_state.attack += attack_bonus
	if speed_bonus != 0:
		run_state.speed += speed_bonus
	if loadout_bonus != 0:
		run_state.loadout_limit = max(1, run_state.loadout_limit + loadout_bonus)
		run_state.equipped_cards = RunState.build_default_equipped_cards(run_state.player_cards, run_state.loadout_limit)


func _filter_valid_card_ids(card_ids: Array[String]) -> Array[String]:
	var valid_card_ids: Array[String] = []
	for card_id in card_ids:
		if Database.get_card(card_id) != null:
			valid_card_ids.append(card_id)
	return valid_card_ids


func _ensure_map_state() -> void:
	if current_run == null:
		return
	if current_run.map_state.is_empty():
		current_run.map_state = _map_generator.generate_run(current_run.seed)


func _prepare_non_battle_node(step_index: int, node_index: int) -> void:
	var node_data: Dictionary = _get_node(step_index, node_index)
	var area: int = int(node_data.get("area", current_run.current_area))
	var node_type: String = String(node_data.get("type", ""))

	match node_type:
		"shop":
			var offers: Array = Array(node_data.get("shop_offers", []))
			if offers.is_empty():
				node_data["shop_offers"] = _shop_service.roll_inventory(
					3,
					_get_shop_rarity_pool(area),
					current_run.player_cards,
					get_unlocked_card_ids()
				)
		"forge":
			var options: Array[String] = _to_string_array(node_data.get("forge_options", []))
			if options.is_empty():
				node_data["forge_options"] = _forge_service.roll_candidates(current_run, 3)
			if not node_data.has("forge_used"):
				node_data["forge_used"] = false
		"heal":
			if not node_data.has("heal_amount"):
				node_data["heal_amount"] = 10 + area * 4
		"event":
			if not node_data.has("event_id"):
				var event_data: Dictionary = _event_service.build_event_node(
					area,
					current_run,
					_get_used_event_ids(),
					get_unlocked_card_ids(),
					get_unlocked_relic_ids()
				)
				for key in event_data.keys():
					node_data[key] = event_data[key]
		"hazard":
			if not node_data.has("hazard_queue"):
				var hazard_data: Dictionary = _build_hazard_node(area)
				for key in hazard_data.keys():
					node_data[key] = hazard_data[key]

	_set_node(step_index, node_index, node_data)
	pending_enemy_id = ""


func _handle_battle_reward(reward_key: String, finish_run: bool = false) -> void:
	last_reward_bundle = preview_reward_package(reward_key, current_run.current_area)
	_apply_reward_bundle(last_reward_bundle)

	var reward_note: String = ""
	if reward_key == "elite":
		reward_note = _grant_random_relic_note()
	elif reward_key == "boss":
		current_run.run_complete = true
		_add_clear_rewards()

	if reward_note != "":
		last_battle_summary["bonus_text"] = reward_note
	else:
		last_battle_summary.erase("bonus_text")

	if finish_run:
		_complete_active_map_node_and_advance()
		reward_options.clear()
		last_reward_bundle.clear()
		current_screen_hint = "result"
		return

	reward_options = _to_string_array(last_reward_bundle.get("options", []))
	current_screen_hint = "reward"


func _handle_hazard_victory() -> void:
	var location: Dictionary = _get_active_node_location()
	if location.is_empty():
		_handle_battle_reward("normal")
		return

	var step_index: int = int(location.get("step_index", -1))
	var node_index: int = int(location.get("node_index", -1))
	var node_data: Dictionary = _get_node(step_index, node_index)
	var queue: Array[String] = _to_string_array(node_data.get("hazard_queue", []))
	var cleared_waves: int = int(node_data.get("hazard_cleared_waves", 0)) + 1
	node_data["hazard_cleared_waves"] = cleared_waves
	_set_node(step_index, node_index, node_data)

	current_run.gold += int(node_data.get("hazard_wave_gold", 0))
	current_run.player_hp = min(current_run.max_hp, current_run.player_hp + int(node_data.get("hazard_wave_heal", 0)))

	if cleared_waves < queue.size():
		last_battle_summary["bonus_text"] = Localization.get_textf(
			"game.hazard_wave_cleared",
			"Hazard wave {current} / {total} cleared. Continue or withdraw.",
			{
				"current": cleared_waves,
				"total": queue.size(),
			}
		)
		reward_options.clear()
		last_reward_bundle.clear()
		current_screen_hint = "facility"
		return

	last_reward_bundle = preview_reward_package("hazard", current_run.current_area)
	_apply_reward_bundle(last_reward_bundle)
	var reward_note: String = _grant_random_relic_note()
	if reward_note != "":
		last_battle_summary["bonus_text"] = reward_note

	reward_options = _to_string_array(last_reward_bundle.get("options", []))
	current_screen_hint = "reward"


func _apply_reward_bundle(reward_bundle: Dictionary) -> void:
	current_run.gold += int(reward_bundle.get("gold", 0))
	current_run.player_hp = min(current_run.max_hp, current_run.player_hp + int(reward_bundle.get("heal", 0)))
	last_battle_summary["reward_gold"] = int(reward_bundle.get("gold", 0))
	last_battle_summary["reward_heal"] = int(reward_bundle.get("heal", 0))
	last_battle_summary["reward_key"] = String(reward_bundle.get("reward_key", ""))
	last_battle_summary["reward_area"] = int(reward_bundle.get("area", current_run.current_area))
	last_battle_summary["reward_options"] = _to_string_array(reward_bundle.get("options", []))


func _grant_random_relic_note() -> String:
	last_battle_summary.erase("bonus_relic_id")
	var relic_id: String = _relic_service.roll_random_relic(current_run.relics, get_unlocked_relic_ids())
	if relic_id == "":
		return ""
	if not _relic_service.grant_relic(current_run, relic_id):
		return ""
	last_battle_summary["bonus_relic_id"] = relic_id
	var relic_def: RelicDef = Database.get_relic(relic_id)
	if relic_def == null:
		return Localization.get_relic_gained_text(relic_id)
	return Localization.get_relic_gained_text(relic_def.name)


func _get_event_choice(active_node: Dictionary, choice_id: String) -> Dictionary:
	var choices: Array = Array(active_node.get("event_choices", []))
	for raw_choice in choices:
		var choice_data: Dictionary = Dictionary(raw_choice)
		if String(choice_data.get("id", "")) == choice_id:
			return choice_data
	return {}


func _apply_event_choice(choice_data: Dictionary) -> String:
	var effects: Array = Array(choice_data.get("effects", []))
	for raw_effect in effects:
		if not _apply_event_effect(Dictionary(raw_effect)):
			return ""

	var result_text: String = String(choice_data.get("result", ""))
	if result_text != "":
		return result_text
	return String(choice_data.get("label", ""))


func _apply_event_effect(effect_data: Dictionary) -> bool:
	var effect_type: String = String(effect_data.get("type", ""))
	match effect_type:
		"grant_gold":
			current_run.gold += int(effect_data.get("amount", 0))
		"lose_gold":
			var gold_cost: int = int(effect_data.get("amount", 0))
			if current_run.gold < gold_cost:
				return false
			current_run.gold -= gold_cost
		"heal":
			current_run.player_hp = min(current_run.max_hp, current_run.player_hp + int(effect_data.get("amount", 0)))
		"lose_hp":
			current_run.player_hp = max(1, current_run.player_hp - int(effect_data.get("amount", 0)))
		"modify_attack":
			current_run.attack += int(effect_data.get("amount", 0))
		"modify_speed":
			current_run.speed += int(effect_data.get("amount", 0))
		"modify_max_hp":
			var hp_delta: int = int(effect_data.get("amount", 0))
			current_run.max_hp = max(1, current_run.max_hp + hp_delta)
			current_run.player_hp = clampi(current_run.player_hp + max(0, hp_delta), 1, current_run.max_hp)
		"modify_loadout_limit":
			current_run.loadout_limit = max(1, current_run.loadout_limit + int(effect_data.get("amount", 0)))
		"grant_random_card":
			var card_id: String = String(effect_data.get("card_id", ""))
			if card_id == "":
				return false
			current_run.player_cards.append(card_id)
			_auto_equip_card_if_room(card_id)
		"grant_random_relic":
			var relic_id: String = String(effect_data.get("relic_id", ""))
			if relic_id == "":
				return false
			if not _relic_service.grant_relic(current_run, relic_id):
				return false
		"upgrade_random_card":
			var upgrade_card_id: String = String(effect_data.get("card_id", ""))
			if upgrade_card_id == "":
				return false
			if not current_run.player_cards.has(upgrade_card_id):
				return false
			_forge_service.upgrade_card(current_run, upgrade_card_id)
		_:
			return false
	return true


func _build_hazard_node(area: int) -> Dictionary:
	var queue: Array[String] = []
	if area <= 2:
		queue = ["raider", "guardian"]
	else:
		queue = ["chronoguard", "disruptor", "brute"]
	return {
		"hazard_title": Localization.get_text("hazard.title", "Hazard Zone"),
		"hazard_description": Localization.get_text("hazard.description", "Push through chained battles. Each cleared wave pays immediately."),
		"hazard_queue": queue,
		"hazard_cleared_waves": 0,
		"hazard_wave_gold": 14 + area * 4,
		"hazard_wave_heal": 2,
		"hazard_started": false,
	}


func _get_used_event_ids() -> Array[String]:
	var used_ids: Array[String] = []
	if current_run == null:
		return used_ids
	var steps: Array = Array(current_run.map_state.get("steps", []))
	for raw_step in steps:
		var step_data: Dictionary = Dictionary(raw_step)
		var nodes: Array = Array(step_data.get("nodes", []))
		for raw_node in nodes:
			var node_data: Dictionary = Dictionary(raw_node)
			var event_id: String = String(node_data.get("event_id", ""))
			if event_id == "" or used_ids.has(event_id):
				continue
			used_ids.append(event_id)
	return used_ids


func _get_shop_rarity_pool(area: int) -> Array[String]:
	match area:
		1:
			return ["common", "common", "rare"]
		2:
			return ["common", "rare", "rare"]
		_:
			return ["rare", "rare", "epic"]


func _complete_active_map_node_and_advance() -> void:
	if current_run == null:
		return
	_ensure_map_state()

	var active_node_id: String = String(current_run.map_state.get("active_node_id", ""))
	if active_node_id == "":
		return
	if active_node_id == DEBUG_EVENT_NODE_ID:
		current_run.map_state.erase("debug_active_node")
		current_run.map_state["active_node_id"] = ""
		return

	var location: Dictionary = _find_node_location(active_node_id)
	if location.is_empty():
		current_run.map_state["active_node_id"] = ""
		return

	var step_index: int = int(location.get("step_index", -1))
	var node_index: int = int(location.get("node_index", -1))
	var steps: Array = Array(current_run.map_state.get("steps", []))
	if step_index < 0 or step_index >= steps.size():
		current_run.map_state["active_node_id"] = ""
		return

	var step_data: Dictionary = Dictionary(steps[step_index])
	var nodes: Array = Array(step_data.get("nodes", []))
	for index in range(nodes.size()):
		var node_data: Dictionary = Dictionary(nodes[index])
		if index == node_index:
			node_data["status"] = "completed"
		elif String(node_data.get("status", "")) != "completed":
			node_data["status"] = "skipped"
		nodes[index] = node_data

	step_data["nodes"] = nodes
	steps[step_index] = step_data
	current_run.map_state["steps"] = steps
	current_run.map_state["active_node_id"] = ""

	var next_step: int = step_index + 1
	current_run.map_state["current_step"] = next_step
	if next_step < steps.size():
		_unlock_step_nodes(next_step)
		var next_step_data: Dictionary = _get_step(next_step)
		current_run.current_area = int(next_step_data.get("area", current_run.current_area))
	else:
		current_run.run_complete = true


func _unlock_step_nodes(step_index: int) -> void:
	var steps: Array = Array(current_run.map_state.get("steps", []))
	if step_index < 0 or step_index >= steps.size():
		return

	var step_data: Dictionary = Dictionary(steps[step_index])
	var nodes: Array = Array(step_data.get("nodes", []))
	for index in range(nodes.size()):
		var node_data: Dictionary = Dictionary(nodes[index])
		if String(node_data.get("status", "locked")) == "locked":
			node_data["status"] = "available"
		nodes[index] = node_data
	step_data["nodes"] = nodes
	steps[step_index] = step_data
	current_run.map_state["steps"] = steps


func _get_step(step_index: int) -> Dictionary:
	var steps: Array = Array(current_run.map_state.get("steps", []))
	if step_index < 0 or step_index >= steps.size():
		return {}
	return Dictionary(steps[step_index])


func _get_node(step_index: int, node_index: int) -> Dictionary:
	var step_data: Dictionary = _get_step(step_index)
	var nodes: Array = Array(step_data.get("nodes", []))
	if node_index < 0 or node_index >= nodes.size():
		return {}
	return Dictionary(nodes[node_index])


func _set_node(step_index: int, node_index: int, node_data: Dictionary) -> void:
	var steps: Array = Array(current_run.map_state.get("steps", []))
	if step_index < 0 or step_index >= steps.size():
		return

	var step_data: Dictionary = Dictionary(steps[step_index])
	var nodes: Array = Array(step_data.get("nodes", []))
	if node_index < 0 or node_index >= nodes.size():
		return

	nodes[node_index] = node_data
	step_data["nodes"] = nodes
	steps[step_index] = step_data
	current_run.map_state["steps"] = steps


func _find_node_location(node_id: String) -> Dictionary:
	var steps: Array = Array(current_run.map_state.get("steps", []))
	for step_index in range(steps.size()):
		var step_data: Dictionary = Dictionary(steps[step_index])
		var nodes: Array = Array(step_data.get("nodes", []))
		for node_index in range(nodes.size()):
			var node_data: Dictionary = Dictionary(nodes[node_index])
			if String(node_data.get("id", "")) == node_id:
				return {
					"step_index": step_index,
					"node_index": node_index,
				}
	return {}


func _get_active_node_location() -> Dictionary:
	if current_run == null:
		return {}
	var active_node_id: String = String(current_run.map_state.get("active_node_id", ""))
	if active_node_id == "":
		return {}
	if active_node_id == DEBUG_EVENT_NODE_ID:
		return {}
	return _find_node_location(active_node_id)


func _get_post_progress_scene_hint() -> String:
	if current_run != null and current_run.run_complete:
		return "result"
	return "map"


func _reroll_reward_options() -> Array[String]:
	if current_run == null:
		return []

	var reward_key: String = String(last_reward_bundle.get("reward_key", "normal"))
	var area: int = int(last_reward_bundle.get("area", current_run.current_area))
	var preview_bundle: Dictionary = preview_reward_package(reward_key, area)
	var next_options: Array[String] = _to_string_array(preview_bundle.get("options", []))
	if next_options.is_empty():
		return []

	reward_options = next_options
	last_reward_bundle = preview_bundle
	last_battle_summary["reward_options"] = reward_options.duplicate()
	return reward_options.duplicate()


func preview_reward_package(reward_key: String, area: int = -1) -> Dictionary:
	var resolved_area: int = area
	if resolved_area < 1:
		if current_run != null:
			resolved_area = current_run.current_area
		else:
			resolved_area = 1

	var reward_table: Dictionary = Dictionary(Database.rewards.get(reward_key, {}))
	var owned_cards: Array[String] = []
	if current_run != null:
		owned_cards = current_run.player_cards
	return _reward_resolver.build_reward_bundle(
		reward_key,
		reward_table,
		resolved_area,
		owned_cards,
		get_unlocked_card_ids()
	)


func _has_valid_loadout() -> bool:
	if current_run == null:
		return false
	return not current_run.equipped_cards.is_empty() and get_current_loadout_cost() <= current_run.loadout_limit


func _auto_equip_card_if_room(card_id: String) -> void:
	if current_run == null:
		return
	if _count_card_occurrences(current_run.equipped_cards, card_id) >= _count_card_occurrences(current_run.player_cards, card_id):
		return
	var card_def: CardDef = Database.get_card(card_id)
	if card_def == null:
		return
	if get_current_loadout_cost() + card_def.loadout_cost > current_run.loadout_limit:
		return
	current_run.equipped_cards.append(card_id)


func _count_card_occurrences(card_ids: Array[String], card_id: String) -> int:
	var count: int = 0
	for candidate in card_ids:
		if candidate == card_id:
			count += 1
	return count


func _hazard_next_enemy_name(queue: Array[String], cleared_waves: int) -> String:
	if cleared_waves < 0 or cleared_waves >= queue.size():
		return "Cleared"
	var enemy_def: EnemyDef = Database.get_enemy(queue[cleared_waves])
	if enemy_def == null:
		return queue[cleared_waves]
	return enemy_def.name


func _roll_enemy_id() -> String:
	if current_run.encounters_cleared >= 2:
		return "boss_timekeeper"

	var pool: Array[String] = []
	if current_run.encounters_cleared == 0:
		pool = ["scout", "brute", "raider", "medic_drone"]
	else:
		pool = ["brute", "guardian", "chronoguard", "disruptor"]
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _add_clear_rewards() -> void:
	ensure_meta_initialized()
	meta_progress["points"] = int(meta_progress.get("points", 0)) + 1
	meta_progress["best_clear"] = max(int(meta_progress.get("best_clear", 0)), current_run.encounters_cleared)


func _normalize_resolution_code(resolution_code: String) -> String:
	if AVAILABLE_RESOLUTION_CODES.has(resolution_code):
		return resolution_code
	return DEFAULT_RESOLUTION


func _parse_resolution_code(resolution_code: String) -> Vector2i:
	var normalized_code: String = _normalize_resolution_code(resolution_code)
	var parts: PackedStringArray = normalized_code.split("x", false)
	if parts.size() != 2:
		return Vector2i(1920, 1080)
	return Vector2i(int(parts[0]), int(parts[1]))


func _apply_resolution_from_settings(center_window: bool = false) -> void:
	var resolution_code: String = _normalize_resolution_code(String(settings.get("resolution", DEFAULT_RESOLUTION)))
	settings["resolution"] = resolution_code
	if _applied_resolution == resolution_code:
		return
	_applied_resolution = resolution_code
	if DisplayServer.get_name() == "headless":
		return

	var window_size: Vector2i = _parse_resolution_code(resolution_code)
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(window_size)
	if center_window:
		_center_game_window(window_size)


func _center_game_window(window_size: Vector2i) -> void:
	var screen_id: int = DisplayServer.window_get_current_screen()
	var screen_position: Vector2i = DisplayServer.screen_get_position(screen_id)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_id)
	var offset_x: int = maxi(0, int((screen_size.x - window_size.x) / 2))
	var offset_y: int = maxi(0, int((screen_size.y - window_size.y) / 2))
	DisplayServer.window_set_position(screen_position + Vector2i(offset_x, offset_y))


func _sync_language_from_settings(emit_signal: bool) -> void:
	var language_code: String = String(settings.get("language", Localization.DEFAULT_LANGUAGE))
	var changed: bool = Localization.set_language(language_code, false)
	if changed:
		Database.load_all()
	if changed and emit_signal:
		Localization.language_changed.emit(Localization.get_language())


func _load_json_dictionary_file(file_path: String) -> Dictionary:
	if file_path == "":
		return {}
	if not FileAccess.file_exists(file_path):
		return {}
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return Dictionary(json.data)


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(String(item))
	return result
