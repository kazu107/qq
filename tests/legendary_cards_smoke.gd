extends Node

const EXPECTED_LEGENDARY_IDS: Array[String] = [
	"solar_verdict",
	"citadel_prime",
	"epoch_breaker",
	"phoenix_circuit",
	"atlas_protocol",
	"worldline_collapse",
	"seraph_array",
	"ragnarok_engine",
	"absolute_zero",
	"quantum_exchange",
	"crown_of_thorns",
	"infinity_arsenal",
	"omega_sanctuary",
	"event_horizon",
	"deus_ex_machina",
	"golden_ratio",
	"tempest_choir",
	"last_bastion",
	"dominion_pulse",
	"chronicle_sovereign",
]
const KNOWN_EFFECT_TYPES: Array[String] = [
	"consume_shield",
	"deal_damage",
	"gain_shield",
	"heal",
	"apply_status",
	"remove_status",
	"delay_enemy_active_card",
	"haste_own_active_card",
	"reduce_recast",
	"interrupt_card",
	"modify_attack",
	"modify_speed",
	"empower_card",
	"auto_queue_card",
	"timeline_flow",
]


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	call_deferred("_run")


func _run() -> void:
	if not _test_definitions_and_grades():
		return
	if not _test_runtime_resolution():
		return
	if not _test_progression_and_prices():
		return
	if not _test_reward_and_arena_pools():
		return
	if not await _test_library_filter():
		return
	print("Legendary card smoke passed: 20 cards, grades, battle resolution, pools, prices, and library filter.")
	get_tree().quit()


func _test_definitions_and_grades() -> bool:
	var legendary_ids: Array[String] = Database.get_card_ids_by_rarity("legendary")
	legendary_ids.sort()
	var expected_ids: Array[String] = EXPECTED_LEGENDARY_IDS.duplicate()
	expected_ids.sort()
	if legendary_ids != expected_ids:
		_fail("Legendary card smoke failed: legendary id set does not match the expected 20 cards")
		return false

	for card_id: String in EXPECTED_LEGENDARY_IDS:
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null or card_def.rarity != "legendary":
			_fail("Legendary card smoke failed: invalid rarity for %s" % card_id)
			return false
		if card_def.loadout_cost != 5 or card_def.active_slot_cost < 1 or card_def.active_slot_cost > 3:
			_fail("Legendary card smoke failed: invalid cost or slot data for %s" % card_id)
			return false
		if card_def.effects.is_empty():
			_fail("Legendary card smoke failed: %s has no effects" % card_id)
			return false
		for raw_effect: Dictionary in card_def.effects:
			var effect_type: String = String(raw_effect.get("type", ""))
			if not KNOWN_EFFECT_TYPES.has(effect_type):
				_fail("Legendary card smoke failed: unknown effect %s on %s" % [effect_type, card_id])
				return false
			if effect_type == "auto_queue_card":
				var queued_card_id: String = String(raw_effect.get("card_id", "self"))
				if queued_card_id != "self" and Database.get_card(queued_card_id) == null:
					_fail("Legendary card smoke failed: %s queues missing card %s" % [card_id, queued_card_id])
					return false

		for raw_profile_key: Variant in card_def.upgrade_profile.keys():
			var profile_key: String = String(raw_profile_key)
			var values: Array = Array(card_def.upgrade_profile.get(profile_key, []))
			if values.size() < CardUpgradeResolver.MAX_TIER + 1:
				_fail("Legendary card smoke failed: %s profile %s lacks all grades" % [card_id, profile_key])
				return false

		for tier: int in range(CardUpgradeResolver.MAX_TIER + 1):
			var tier_card: CardDef = CardUpgradeResolver.build_card_at_tier(card_id, tier)
			if tier_card == null or tier_card.rarity != "legendary":
				_fail("Legendary card smoke failed: could not build %s grade %d" % [card_id, tier])
				return false
			var summary: String = CardInfoFormatter.build_effect_summary(tier_card)
			if summary.is_empty() or summary.find("Unknown effect") >= 0:
				_fail("Legendary card smoke failed: effect tooltip failed for %s grade %d" % [card_id, tier])
				return false
	return true


func _test_runtime_resolution() -> bool:
	for card_id: String in EXPECTED_LEGENDARY_IDS:
		Game.start_new_run("balanced")
		Game.current_run.player_cards = [card_id]
		Game.current_run.equipped_cards = [card_id]
		Game.current_run.loadout_limit = 40

		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
		engine.setup(Game.current_run, "scout")
		engine.battle_state.player.max_hp = 500
		engine.battle_state.player.hp = 500
		engine.battle_state.player.shield = 100
		engine.battle_state.enemy.max_hp = 10000
		engine.battle_state.enemy.hp = 10000

		var runtime_id: String = ""
		for runtime_state: CardRuntimeState in engine.battle_state.player.card_runtime_states:
			if runtime_state.card_id == card_id:
				runtime_id = runtime_state.runtime_id
				break
		if runtime_id.is_empty() or not engine.request_use_card("player", runtime_id):
			_fail("Legendary card smoke failed: could not queue %s in battle" % card_id)
			return false

		var resolved: bool = false
		for _step: int in range(240):
			engine.update(0.1)
			for event_value: Variant in engine.battle_state.battle_events:
				var event_data: Dictionary = Dictionary(event_value)
				if String(event_data.get("event_type", "")) == "resolve_card" and String(event_data.get("card_id", "")) == card_id:
					resolved = true
					break
			if resolved:
				break
		if not resolved:
			_fail("Legendary card smoke failed: %s did not resolve in battle" % card_id)
			return false
	return true


func _test_progression_and_prices() -> bool:
	var meta_service: MetaProgressService = MetaProgressService.new()
	var default_cards: Array[String] = meta_service.get_default_unlocked_card_ids()
	for card_id: String in EXPECTED_LEGENDARY_IDS:
		if default_cards.has(card_id):
			_fail("Legendary card smoke failed: legendary card is unlocked by default: %s" % card_id)
			return false
		if meta_service.get_card_unlock_cost(card_id) != 4:
			_fail("Legendary card smoke failed: invalid unlock cost for %s" % card_id)
			return false
		if ShopService.new().get_price(card_id) != 82:
			_fail("Legendary card smoke failed: invalid shop price for %s" % card_id)
			return false

	var isolated_meta: Dictionary = {"points": 4}
	meta_service.ensure_defaults(isolated_meta)
	if not meta_service.unlock_card(isolated_meta, EXPECTED_LEGENDARY_IDS[0]):
		_fail("Legendary card smoke failed: a legendary card could not be unlocked for 4 points")
		return false
	if int(isolated_meta.get("points", -1)) != 0:
		_fail("Legendary card smoke failed: legendary unlock did not spend 4 points")
		return false
	return true


func _test_reward_and_arena_pools() -> bool:
	var normal_rewards: Dictionary = Dictionary(Database.rewards.get("normal", {}))
	var rarity_by_area: Dictionary = Dictionary(normal_rewards.get("rarity_pool_by_area", {}))
	for area: int in [4, 5, 6]:
		if not Array(rarity_by_area.get(str(area), [])).has("legendary"):
			_fail("Legendary card smoke failed: normal area %d cannot roll legendary cards" % area)
			return false

	var reward_resolver: RewardResolver = RewardResolver.new()
	var bundle: Dictionary = reward_resolver.build_reward_bundle(
		"normal",
		normal_rewards,
		6,
		[],
		EXPECTED_LEGENDARY_IDS
	)
	var options: Array = Array(bundle.get("options", []))
	if options.size() != int(normal_rewards.get("option_count", 3)):
		_fail("Legendary card smoke failed: late-run legendary reward options were not generated")
		return false
	for option_value: Variant in options:
		if not EXPECTED_LEGENDARY_IDS.has(String(option_value)):
			_fail("Legendary card smoke failed: restricted reward pool leaked a non-legendary card")
			return false

	var arena_service: ArenaService = ArenaService.new()
	if not arena_service._get_card_rarity_pool(7).has("legendary"):
		_fail("Legendary card smoke failed: high-win arena pool lacks legendary cards")
		return false
	return true


func _test_library_filter() -> bool:
	var library_scene: Control = load("res://scenes/library/CardLibrary.tscn").instantiate() as Control
	add_child(library_scene)
	for _frame: int in range(180):
		await get_tree().process_frame
		if bool(library_scene.call("is_content_ready")):
			break
	if not bool(library_scene.call("is_content_ready")):
		_fail("Legendary card smoke failed: card library did not finish building")
		return false

	var rarity_filter: OptionButton = library_scene.find_child("LibraryRarityFilter", true, false) as OptionButton
	var legendary_row: Control = library_scene.find_child("LibraryRow_solar_verdict", true, false) as Control
	var common_row: Control = library_scene.find_child("LibraryRow_guard", true, false) as Control
	if rarity_filter == null or legendary_row == null or common_row == null:
		_fail("Legendary card smoke failed: library widgets are missing")
		return false

	var legendary_index: int = -1
	for index: int in rarity_filter.item_count:
		if String(rarity_filter.get_item_metadata(index)) == "legendary":
			legendary_index = index
			break
	if legendary_index < 0:
		_fail("Legendary card smoke failed: library filter lacks legendary")
		return false
	rarity_filter.select(legendary_index)
	rarity_filter.emit_signal("item_selected", legendary_index)
	await get_tree().process_frame
	if not legendary_row.visible or common_row.visible:
		_fail("Legendary card smoke failed: legendary library filter did not isolate the new rarity")
		return false
	library_scene.queue_free()
	return true


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
