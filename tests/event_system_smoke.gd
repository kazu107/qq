extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.developer_unlock_all_meta()
	Game.start_new_run("balanced")
	call_deferred("_run")


func _run() -> void:
	if Database.get_all_event_ids().size() < 10:
		_fail("Event system smoke failed: expected expanded event database")
		return

	var base_step: int = Game.get_current_step_index()

	Game.current_run.gold = 200
	var cards_before: int = Game.current_run.player_cards.size()
	var gold_before: int = Game.current_run.gold
	_open_debug_event("black_market", 3)
	var buy_result: String = Game.resolve_event_choice("buy_card")
	if buy_result == "" or Game.current_run.player_cards.size() != cards_before + 1:
		_fail("Event system smoke failed: black market card purchase did not resolve")
		return
	if Game.current_run.gold >= gold_before:
		_fail("Event system smoke failed: black market purchase did not spend gold")
		return
	_assert_debug_event_closed(base_step)
	if _failed:
		return

	var tier_before: int = _get_total_upgrade_tiers()
	_open_debug_event("calibration_lab", 2)
	var upgrade_result: String = Game.resolve_event_choice("upgrade_card")
	if upgrade_result == "" or _get_total_upgrade_tiers() != tier_before + 1:
		_fail("Event system smoke failed: calibration lab did not upgrade a card")
		return
	_assert_debug_event_closed(base_step)
	if _failed:
		return

	Game.current_run.gold = 0
	_open_debug_event("signal_archive", 3)
	var archive_choices: Array = Array(Game.get_active_event_data().get("choices", []))
	var trace_choice: Dictionary = _find_choice(archive_choices, "trace_relic")
	if trace_choice.is_empty() or bool(trace_choice.get("enabled", true)):
		_fail("Event system smoke failed: archive relic trace should be disabled when gold is too low")
		return
	if Game.resolve_event_choice("trace_relic") != "":
		_fail("Event system smoke failed: disabled event choice should not resolve")
		return
	var decode_cards_before: int = Game.current_run.player_cards.size()
	var decode_result: String = Game.resolve_event_choice("decode_card")
	if decode_result == "" or Game.current_run.player_cards.size() != decode_cards_before + 1:
		_fail("Event system smoke failed: archive decode choice did not grant a card")
		return
	_assert_debug_event_closed(base_step)
	if _failed:
		return

	var relics_before: int = Game.current_run.relics.size()
	if not Game.current_run.relics.has("iron_plating"):
		RelicService.new().grant_relic(Game.current_run, "iron_plating")
		relics_before = Game.current_run.relics.size()
	var hp_before: int = Game.current_run.player_hp
	_open_debug_event("relic_shrine", 2)
	var shrine_result: String = Game.resolve_event_choice("take_relic")
	if shrine_result == "" or Game.current_run.relics.size() != relics_before + 1:
		_fail("Event system smoke failed: relic shrine did not grant a relic")
		return
	if Game.current_run.player_hp >= hp_before:
		_fail("Event system smoke failed: relic shrine did not pay the HP cost")
		return
	_assert_debug_event_closed(base_step)
	if _failed:
		return

	_assert_relic_and_enemy_content()
	if _failed:
		return

	print("Event system smoke passed")
	get_tree().quit()


func _open_debug_event(event_id: String, area: int) -> void:
	Game.developer_open_event(event_id, area)
	var event_data: Dictionary = Game.get_active_event_data()
	if String(event_data.get("id", "")) != event_id:
		_fail("Event system smoke failed: expected debug event %s to open" % event_id)


func _assert_debug_event_closed(expected_step: int) -> void:
	if Game.current_screen_hint != "map":
		_fail("Event system smoke failed: debug event should return to map")
		return
	if Game.get_current_step_index() != expected_step:
		_fail("Event system smoke failed: debug event should not advance map progression")
		return
	if not Game.get_active_map_node().is_empty():
		_fail("Event system smoke failed: debug event should clear the active node")


func _get_total_upgrade_tiers() -> int:
	var total: int = 0
	for card_id in Game.current_run.card_upgrades.keys():
		total += int(Game.current_run.card_upgrades[card_id])
	return total


func _assert_relic_and_enemy_content() -> void:
	var relic_service: RelicService = RelicService.new()
	var run_state: RunState = RunState.from_starter(Database.get_starter("balanced"))
	run_state.player_hp = max(1, run_state.max_hp - 10)
	relic_service.grant_relic(run_state, "war_banner")
	relic_service.grant_relic(run_state, "aegis_matrix")
	relic_service.grant_relic(run_state, "surge_gimbal")
	relic_service.grant_relic(run_state, "salvage_magnet")
	relic_service.grant_relic(run_state, "repair_nanites")

	var victory_bonus: Dictionary = relic_service.apply_victory_bonuses(run_state)
	if int(victory_bonus.get("gold", 0)) != 10 or int(victory_bonus.get("heal", 0)) != 5:
		_fail("Event system smoke failed: expanded relic victory bonuses did not apply")
		return

	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.setup(run_state, "chronoguard")
	var battle_state: BattleState = engine.battle_state
	if battle_state == null:
		_fail("Event system smoke failed: battle engine did not set up against chronoguard")
		return
	if battle_state.player.attack != run_state.attack + 2:
		_fail("Event system smoke failed: war banner did not apply attack bonus in battle")
		return
	if battle_state.player.defense != run_state.defense + 2:
		_fail("Event system smoke failed: aegis matrix did not apply defense bonus in battle")
		return
	if battle_state.player.speed != run_state.speed + 1:
		_fail("Event system smoke failed: surge gimbal did not apply speed bonus in battle")
		return
	if battle_state.enemy.display_name != "Chronoguard":
		_fail("Event system smoke failed: expanded enemy roster was not loaded")


func _find_choice(choices: Array, choice_id: String) -> Dictionary:
	for raw_choice in choices:
		var choice_data: Dictionary = Dictionary(raw_choice)
		if String(choice_data.get("id", "")) == choice_id:
			return choice_data
	return {}


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
