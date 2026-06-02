extends Node

const EXPECTED_SFX_IDS: Array[String] = [
	"ui_confirm",
	"ui_page",
	"ui_toggle",
	"ui_error",
	"run_start",
	"map_select",
	"loadout_equip",
	"loadout_unequip",
	"reward_pick",
	"reward_skip",
	"shop_buy",
	"forge_upgrade",
	"heal_use",
	"event_resolve",
	"hazard_enter",
	"hazard_withdraw",
	"meta_unlock",
	"meta_points",
	"relic_gain",
	"gold_gain",
	"battle_start",
	"card_commit",
	"battle_attack",
	"battle_guard",
	"battle_heal",
	"battle_status",
	"battle_interrupt",
	"battle_time",
	"battle_tick",
	"battle_victory",
	"battle_defeat",
]

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.set_master_volume(1.0)
	Game.set_sfx_volume(1.0)
	AudioManager.clear_play_history()
	call_deferred("_run")


func _run() -> void:
	_assert_sfx_assets()
	if _failed:
		return

	_assert_sfx_playback()
	if _failed:
		return

	Game.start_new_run("balanced")
	_assert_last_sfx("run_start", "Audio smoke failed: start_new_run should play the run start SFX")
	if _failed:
		return

	Game.developer_add_gold(25)
	_assert_last_sfx("gold_gain", "Audio smoke failed: developer_add_gold should play the gold SFX")
	if _failed:
		return

	if not Game.unequip_card("guard"):
		_fail("Audio smoke failed: unequip_card did not succeed on a starter guard card")
		return
	_assert_last_sfx("loadout_unequip", "Audio smoke failed: unequip_card should play the unequip SFX")
	if _failed:
		return

	if not Game.equip_card("guard"):
		_fail("Audio smoke failed: equip_card did not succeed after freeing one slot")
		return
	_assert_last_sfx("loadout_equip", "Audio smoke failed: equip_card should play the equip SFX")
	if _failed:
		return

	var battle_node: Dictionary = _find_available_battle_node()
	if battle_node.is_empty():
		_fail("Audio smoke failed: no available battle node was found on a fresh run")
		return

	var destination: String = Game.select_map_node(String(battle_node.get("id", "")))
	if destination != "battle":
		_fail("Audio smoke failed: selecting the first battle node did not route to battle")
		return
	_assert_last_sfx("map_select", "Audio smoke failed: select_map_node should play the map select SFX")
	if _failed:
		return

	AudioManager.clear_play_history()
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.setup(Game.current_run, String(battle_node.get("enemy_id", "scout")))
	if not AudioManager.has_played_sfx("battle_start"):
		_fail("Audio smoke failed: battle setup should play the battle start SFX")
		return

	var requested: bool = _request_first_card(engine)
	if not requested:
		_fail("Audio smoke failed: could not request a player card for battle audio verification")
		return
	if not AudioManager.has_played_sfx("card_commit"):
		_fail("Audio smoke failed: request_use_card should play the card commit SFX")
		return

	var resolved: bool = await _wait_for_resolution_sfx(engine)
	if not resolved:
		_fail("Audio smoke failed: no battle resolution SFX played after committing a card")
		return

	var summary: Dictionary = engine.build_summary()
	summary["winner"] = "player"
	summary["player_hp"] = max(1, engine.battle_state.player.hp)
	Game.complete_battle(summary)
	_assert_last_sfx("battle_victory", "Audio smoke failed: player victory should play the victory SFX")
	if _failed:
		return

	if Game.reward_options.is_empty():
		Game.reward_options = ["guard"]
	Game.choose_reward(Game.reward_options[0])
	_assert_last_sfx("reward_pick", "Audio smoke failed: choosing a reward should play the reward pick SFX")
	if _failed:
		return

	var heal_node: Dictionary = _find_available_node_of_type("heal")
	if heal_node.is_empty():
		_fail("Audio smoke failed: no available heal node was found after the first battle")
		return
	if Game.select_map_node(String(heal_node.get("id", ""))) != "facility":
		_fail("Audio smoke failed: selecting the heal node did not route to facility")
		return
	Game.use_heal_node()
	_assert_last_sfx("heal_use", "Audio smoke failed: using a heal node should play the heal SFX")
	if _failed:
		return

	Game.developer_reset_meta_progress()
	_assert_last_sfx("meta_points", "Audio smoke failed: resetting meta should play the meta points SFX")
	if _failed:
		return

	var locked_card_id: String = _find_affordable_locked_card_id()
	if locked_card_id == "":
		_fail("Audio smoke failed: no affordable locked card was found for unlock verification")
		return
	if not Game.unlock_meta_card(locked_card_id):
		_fail("Audio smoke failed: unlock_meta_card did not unlock an affordable card")
		return
	_assert_last_sfx("meta_unlock", "Audio smoke failed: unlocking meta content should play the unlock SFX")
	if _failed:
		return

	var relic_name: String = Game.developer_grant_random_relic()
	if relic_name == "":
		_fail("Audio smoke failed: developer_grant_random_relic did not grant a relic")
		return
	_assert_last_sfx("relic_gain", "Audio smoke failed: granting a relic should play the relic SFX")
	if _failed:
		return

	print("Audio smoke passed")
	get_tree().quit()


func _assert_sfx_assets() -> void:
	for sfx_id in EXPECTED_SFX_IDS:
		if not ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % sfx_id):
			_fail("Audio smoke failed: missing SFX asset %s" % sfx_id)
			return


func _assert_sfx_playback() -> void:
	AudioManager.clear_play_history()
	for sfx_id in EXPECTED_SFX_IDS:
		if not AudioManager.play_sfx(sfx_id):
			_fail("Audio smoke failed: AudioManager could not play %s" % sfx_id)
			return
	if AudioManager.get_play_history().size() != EXPECTED_SFX_IDS.size():
		_fail("Audio smoke failed: AudioManager did not record all playback requests")
		return


func _find_available_battle_node() -> Dictionary:
	return _find_available_node_of_type("normal_battle")


func _find_available_node_of_type(node_type: String) -> Dictionary:
	var step_data: Dictionary = Game.get_current_step_data()
	var nodes: Array = Array(step_data.get("nodes", []))
	for raw_node in nodes:
		var node_data: Dictionary = Dictionary(raw_node)
		if String(node_data.get("type", "")) != node_type:
			continue
		if String(node_data.get("status", "")) != "available":
			continue
		return node_data
	return {}


func _request_first_card(engine: RealtimeBattleEngine) -> bool:
	if engine.battle_state == null:
		return false
	for runtime_state in engine.battle_state.player.get_sorted_runtime_states():
		if not runtime_state.can_use():
			continue
		var card_def: CardDef = Database.get_card(runtime_state.card_id)
		if card_def == null:
			continue
		if engine.battle_state.player.active_slots_used + card_def.active_slot_cost > engine.battle_state.player.active_slot_max:
			continue
		return engine.request_use_card("player", runtime_state.runtime_id)
	return false


func _wait_for_resolution_sfx(engine: RealtimeBattleEngine) -> bool:
	var timeout: float = 0.0
	var target_sfx: Array[String] = [
		"battle_attack",
		"battle_guard",
		"battle_heal",
		"battle_status",
		"battle_interrupt",
		"battle_time",
	]
	while timeout < 40.0:
		engine.update(0.2)
		for sfx_id in target_sfx:
			if AudioManager.has_played_sfx(sfx_id):
				return true
		timeout += 0.2
		await get_tree().process_frame
	return false


func _find_affordable_locked_card_id() -> String:
	for entry in Game.get_meta_card_entries():
		var entry_data: Dictionary = Dictionary(entry)
		if bool(entry_data.get("unlocked", false)):
			continue
		if int(entry_data.get("cost", 0)) > Game.get_meta_points():
			continue
		return String(entry_data.get("id", ""))
	return ""


func _assert_last_sfx(expected: String, message: String) -> void:
	if AudioManager.get_last_sfx_id() != expected:
		_fail(message + " | last=%s expected=%s" % [AudioManager.get_last_sfx_id(), expected])


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
