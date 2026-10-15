extends Node

var _checks: int = 0
var _meta: MetaProgressService = MetaProgressService.new()


func _ready() -> void:
	Database.load_all()
	Game.settings["replay_auto_export"] = false
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		push_error("Content progression: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _run() -> void:
	_check_catalog()
	_check_progression()
	_check_seal_limits()
	_check_migration_and_resume()
	_check_random_sources()
	_check_victory_and_modes()
	await _check_ui()
	print("CONTENT_PROGRESSION_SMOKE_OK %d checks: catalog, auto unlocks, one-time credit, pools, empty pools, seals, resume, modes, UI" % _checks)
	get_tree().quit()


func _check_catalog() -> void:
	_check(Database.load_errors.is_empty(), "Catalog load failed")
	var cards: Array[String] = _meta.get_default_unlocked_card_ids()
	var relics: Array[String] = _meta.get_default_unlocked_relic_ids()
	var previous: int = 0
	for raw: Variant in Database.content_progression["stages"]:
		var stage: Dictionary = Dictionary(raw)
		_check(int(stage["xp"]) > previous, "XP thresholds must increase")
		previous = int(stage["xp"])
		for kind: String in ["cards", "relics"]:
			var seen: Array[String] = cards if kind == "cards" else relics
			var ids: Array[String] = ContentPoolService.valid_ids(stage[kind], kind)
			_check(ids.size() == Array(stage[kind]).size(), "Invalid or duplicate IDs in " + kind)
			for id: String in ids:
				_check(not seen.has(id), "Content assigned twice: " + id)
				seen.append(id)
	_check(cards.size() == Database.cards.size(), "Unlock schedule does not cover all collectible cards")
	_check(relics.size() == Database.relics.size(), "Unlock schedule does not cover all relics")
	_check(not cards.has("timekeeper_final_strike"), "Boss-only card entered progression")


func _fresh() -> Dictionary:
	var result: Dictionary = Database.meta_progress_template.duplicate(true)
	_meta.ensure_defaults(result)
	return result


func _check_progression() -> void:
	var progress: Dictionary = _fresh()
	var initial: int = Array(progress["unlocked_cards"]).size()
	var points: int = int(progress["points"])
	_check(not _meta.unlock_card(progress, "assault"), "Manual card purchase remains possible")
	_check(not _meta.unlock_relic(progress, "chrono_shard"), "Manual relic purchase remains possible")
	_meta.add_unlock_xp(progress, 2)
	_check(Array(progress["unlocked_cards"]).size() == initial, "Content unlocked before threshold")
	var unlocks: Dictionary = _meta.add_unlock_xp(progress, 1)
	_check(Array(unlocks["cards"]).has("assault") and Array(unlocks["relics"]).has("chrono_shard"), "First stage not automatically granted")
	_check(int(progress["points"]) == points, "Automatic unlock spent points")
	var saved: Dictionary = progress.duplicate(true)
	_meta.ensure_defaults(progress)
	_meta.ensure_defaults(progress)
	_check(progress == saved, "Repeated normalization changed unlocks")
	_check(Array(_meta.add_unlock_xp(progress, 0)["cards"]).is_empty(), "Unlock notification was duplicated")
	_meta.add_unlock_xp(progress, 1000)
	_check(Array(progress["unlocked_cards"]).size() == Database.cards.size(), "XP jump did not unlock every eligible stage")
	_check(Array(progress["unlocked_relics"]).size() == Database.relics.size(), "XP jump missed relics")


func _check_seal_limits() -> void:
	var progress: Dictionary = _fresh()
	_check(not _meta.set_content_sealed(progress, "cards", "assault", true), "Locked card can be sealed")
	_check(not _meta.set_content_sealed(progress, "relics", "iron_plating", true), "Starting relic pool can be emptied")
	_check(not _meta.set_content_sealed(progress, "cards", "missing", true), "Invalid card can be sealed")
	_check(not _meta.set_content_sealed(progress, "other", "strike", true), "Invalid seal category was accepted")
	_meta.add_unlock_xp(progress, 125)
	var commons: Array[String] = _meta.get_default_unlocked_card_ids()
	for index: int in range(5):
		_check(_meta.set_content_sealed(progress, "cards", commons[index], true), "Valid card seal was rejected")
	_check(not _meta.set_content_sealed(progress, "cards", commons[5], true), "Card seal limit exceeded")
	_check(_meta.set_content_sealed(progress, "cards", commons[0], false), "Unseal rejected at full capacity")
	_check(_meta.set_content_sealed(progress, "cards", commons[5], true), "Freed seal slot was unusable")
	_check(_meta.set_content_sealed(progress, "relics", "iron_plating", true), "Relic seal rejected")
	_check(_meta.set_content_sealed(progress, "relics", "reactive_barrier", true), "Second relic seal rejected")
	_check(not _meta.set_content_sealed(progress, "relics", "chrono_shard", true), "Relic seal limit exceeded")
	var limited: Dictionary = _fresh()
	limited["unlocked_cards"].append("assault")
	_check(not _meta.set_content_sealed(limited, "cards", "assault", true), "Last card in a rarity can be sealed")
	limited["sealed_cards"] = ["assault", "missing", "strike", "strike", "guard"]
	_meta.ensure_defaults(limited)
	_check(not Array(limited["sealed_cards"]).has("assault") and not Array(limited["sealed_cards"]).has("missing"), "Invalid saved seals survived validation")
	var minimal: Dictionary = {"unlocked_cards": ["strike", "guard", "assault"], "unlocked_relics": ["iron_plating", "reactive_barrier", "chrono_shard"], "sealed_cards": [], "sealed_relics": []}
	_check(not _meta._can_seal(minimal, "relics", "chrono_shard"), "25 percent limit was rounded upward")
	_check(not _meta._can_seal(minimal, "cards", "strike"), "Minimum card count was ignored")


func _check_migration_and_resume() -> void:
	var old_meta: Dictionary = {
		"points": 7, "unlocked_cards": ["strike", "guard", "assault", "solar_verdict"],
		"unlocked_relics": ["iron_plating", "reactive_barrier", "chrono_shard"],
		"achievement_stats": {"victories": 8, "arena_victories": 3},
	}
	var old_run: RunState = RunState.from_starter(Database.get_starter("balanced"), 881)
	old_run.map_state = {"pending_offers": [{"card_id": "assault", "bought": true}]}
	var old_data: Dictionary = old_run.to_dict()
	old_data.erase("content_pool")
	var save: SaveData = SaveData.from_dict({
		"meta_progress": old_meta, "current_run": old_data,
		"suspended_runs": {"normal": {"run": old_data.duplicate(true), "reward_options": ["guard"]}},
		"settings": {"screen_hint": "reward", "language": "en", "replay_auto_export": false, "reward_options": ["assault"], "last_reward_bundle": {"options": ["assault"]}},
	})
	Game.apply_loaded_save(save)
	_check(Game.get_meta_points() == 13, "Legacy credit should be 1 + 4 card points and 1 relic point")
	_check(int(Game.get_content_progress()["xp"]) == 8, "Arena wins were double-counted in legacy XP")
	_check(Game.get_unlocked_card_ids().has("solar_verdict"), "Previously unlocked card was relocked")
	_check(Game.get_unlocked_card_ids().has("execution"), "Legacy victories did not unlock eligible stages")
	_check(Game.get_run_card_pool_ids() == ContentPoolService.valid_ids(old_meta["unlocked_cards"], "cards"), "Old run received new progression content")
	_check(Game.current_run.content_pool["mode"] == "legacy", "Old run was not marked legacy")
	_check(Game.current_run.map_state == old_run.map_state and Game.reward_options == ["assault"], "Pending offers or rewards changed on migration")
	var frozen: Dictionary = Game.current_run.content_pool.duplicate(true)
	var roundtrip: SaveData = SaveData.from_dict(JSON.parse_string(JSON.stringify(Game.build_save_data("reward").to_dict())))
	Game.apply_loaded_save(roundtrip)
	_check(Game.get_meta_points() == 13, "Legacy credit was granted twice")
	_check(Game.current_run.content_pool == frozen, "Pool changed across save/reload")
	Game.resume_suspended_run("normal")
	_check(Game.current_run.content_pool == frozen, "Suspended legacy run was not frozen")
	_check(Game.reward_options == ["guard"], "Suspended reward was rerolled")
	Game.set_content_sealed("cards", "assault", true)
	_check(Game.get_run_card_pool_ids().has("assault"), "Seals changed a legacy run in progress")


func _check_random_sources() -> void:
	Game.developer_reset_meta_progress()
	Game.developer_unlock_all_meta()
	Game.set_content_sealed("cards", "strike", true)
	Game.set_content_sealed("cards", "assault", true)
	Game.set_content_sealed("relics", "iron_plating", true)
	Game.start_new_run("balanced", 993)
	_check(Game.current_run.player_cards.has("strike"), "Seal removed a starting card")
	var frozen: Dictionary = Game.current_run.content_pool.duplicate(true)
	Game.set_content_sealed("cards", "strike", false)
	_meta.add_unlock_xp(Game.meta_progress, 3)
	_check(Game.current_run.content_pool == frozen, "Account settings changed the active pool")
	var cards: Array[String] = Game.get_run_card_pool_ids()
	var relics: Array[String] = Game.get_run_relic_pool_ids()
	var reward: RewardResolver = RewardResolver.new()
	var shop: ShopService = ShopService.new()
	var relic: RelicService = RelicService.new()
	var events: EventService = EventService.new()
	var rarities: Array[String] = ["common", "common", "rare", "epic", "legendary"]
	var owned: Array[String] = []
	var none: Array[String] = []
	_check(reward.roll_card_rewards(3, rarities, owned, none, true).is_empty(), "Empty reward pool fell back to all cards")
	_check(shop.roll_inventory(3, rarities, owned, none).is_empty(), "Empty shop pool fell back to all cards")
	_check(relic.roll_random_relic(none, none) == "", "Empty relic pool fell back to all relics")
	_check(ContentPoolService.weighted_cards(rarities, ["missing"]).is_empty(), "Invalid pool expanded to all cards")
	_check(not reward.roll_card_rewards(3, rarities, owned).is_empty(), "Omitted pool no longer permits all cards")
	var singleton: Array[String] = ["guard"]
	var rare_only: Array[String] = ["legendary"]
	_check(reward.roll_card_rewards(3, rare_only, owned, singleton) == singleton, "Rarity fallback escaped its allowed pool")
	_check(ArenaService.new()._build_card_pool(none, rarities).is_empty(), "Arena empty pool expanded")
	for _sample: int in range(600):
		for id: String in reward.roll_card_rewards(3, rarities, Game.current_run.player_cards, cards, true):
			_check(cards.has(id) and id != "strike" and id != "assault", "Sealed card leaked into reward or guarantee")
		for offer: Dictionary in shop.roll_inventory(3, rarities, Game.current_run.player_cards, cards):
			_check(cards.has(String(offer["card_id"])), "Sealed card leaked into shop")
		var id: String = relic.roll_random_relic(owned, relics)
		_check(relics.has(id) and id != "iron_plating", "Sealed relic leaked into random grant")
	for event_id: String in Database.get_all_event_ids():
		var data: Dictionary = events.build_specific_event_node(event_id, 3, Game.current_run, cards, relics)
		for choice: Dictionary in data.get("event_choices", []):
			for effect: Dictionary in choice.get("effects", []):
				if effect.get("type", "") == "grant_random_card" and effect.get("card_id", "") != "":
					_check(cards.has(String(effect["card_id"])), "Sealed card leaked into event")
				if effect.get("type", "") == "grant_random_relic" and effect.get("relic_id", "") != "":
					_check(relics.has(String(effect["relic_id"])), "Sealed relic leaked into event")
	_check(relic.roll_random_relic(relics, relics) == "", "Exhausted relic pool resurrected held relics")
	var saved: SaveData = Game.build_save_data("map")
	Game.apply_loaded_save(SaveData.from_dict(JSON.parse_string(JSON.stringify(saved.to_dict()))))
	_check(Game.current_run.content_pool == frozen, "New-run snapshot was not serialized")
	Game.stash_active_run_for_hub()
	Game.resume_suspended_run("normal")
	_check(Game.current_run.content_pool == frozen, "New-run snapshot changed on suspend/resume")


func _check_victory_and_modes() -> void:
	Game.developer_reset_meta_progress()
	Game.start_new_run("balanced", 441)
	var pool: Dictionary = Game.current_run.content_pool.duplicate(true)
	for _victory: int in range(3):
		Game.complete_battle({"winner": "player", "enemy_id": "scout", "battle_time": 10.0, "player_hp": 60})
	_check(int(Game.get_content_progress()["xp"]) == 3, "Victory did not award exactly one XP")
	_check(Game.get_unlocked_card_ids().has("assault"), "Victory did not unlock stage automatically")
	_check(Game.current_run.content_pool == pool, "Mid-run unlock changed the pool")
	_check(Game.get_last_content_unlock_text() != "", "New unlock notice is missing")
	Game.apply_loaded_save(SaveData.from_dict(Game.build_save_data("reward").to_dict()))
	_check(int(Game.get_content_progress()["xp"]) == 3, "Continue duplicated XP")
	Game.complete_battle({"winner": "enemy", "enemy_id": "scout", "player_hp": 0})
	_check(int(Game.get_content_progress()["xp"]) == 3, "Loss awarded XP")
	Game.developer_unlock_all_meta()
	Game.set_content_sealed("cards", "assault", true)
	Game.set_content_sealed("relics", "iron_plating", true)
	_check(Game.start_infinite_run("balanced", 442), "Infinite run failed to start")
	_check(not Game.get_run_card_pool_ids().has("assault") and not Game.get_run_relic_pool_ids().has("iron_plating"), "Infinite run ignored seals")
	_check(Game.start_arena_run("balanced", 443), "Arena failed to start")
	_check(Game.get_run_card_pool_ids().size() == Database.cards.size(), "Arena used account card seals")
	_check(Game.get_run_relic_pool_ids().size() == Database.relics.size(), "Arena used account relic seals")
	var xp: int = int(Game.get_content_progress()["xp"])
	Game.complete_battle({"winner": "player", "enemy_id": "scout", "battle_time": 10.0, "player_hp": 60})
	_check(int(Game.get_content_progress()["xp"]) == xp + 1, "Arena win did not award exactly one XP")


func _check_ui() -> void:
	Game.developer_reset_meta_progress()
	Game.developer_unlock_all_meta()
	var library: Control = load("res://scenes/library/CardLibrary.tscn").instantiate() as Control
	add_child(library)
	for _frame: int in range(180):
		await get_tree().process_frame
		if library.is_content_ready():
			break
	_check(library.is_content_ready(), "Library did not finish building")
	var seal: CheckButton = library.find_child("SealCard_strike", true, false) as CheckButton
	_check(seal != null and seal.visible and not seal.disabled, "Library seal control missing")
	seal.button_pressed = true
	_check(Array(Game.meta_progress["sealed_cards"]).has("strike"), "Library control did not save seal")
	_check(SaveManager.has_pending_save(), "Seal did not request save")
	seal.button_pressed = false
	_check(not Array(Game.meta_progress["sealed_cards"]).has("strike"), "Library control did not unseal")
	_check(library.find_child("UnlockCard_strike", true, false) == null, "Manual unlock button remains")
	library.queue_free()
	await get_tree().process_frame
	var meta: Control = load("res://scenes/meta/MetaProgress.tscn").instantiate() as Control
	add_child(meta)
	for _frame: int in range(180):
		await get_tree().process_frame
		if meta.is_content_ready():
			break
	_check(meta.is_content_ready(), "Meta screen did not finish building")
	var relic_seal: CheckButton = meta.find_child("SealRelic_iron_plating", true, false) as CheckButton
	_check(relic_seal != null and relic_seal.visible and not relic_seal.disabled, "Relic seal control missing")
	relic_seal.button_pressed = true
	_check(Array(Game.meta_progress["sealed_relics"]).has("iron_plating"), "Relic control did not save seal")
	_check(meta.find_child("MetaContentProgressBar", true, false) != null, "Unlock progress not displayed")
	meta.queue_free()
	await get_tree().process_frame
