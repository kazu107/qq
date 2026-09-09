extends Node

var _failures: Array[String] = []
var _engines: Array[RealtimeBattleEngine] = []


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Localization.set_language("ja", false)
	call_deferred("_run")


func _new_engine(start: bool = true) -> RealtimeBattleEngine:
	var run: RunState = RunState.new()
	run.starter_id = "balanced"
	run.player_hp = 1000
	run.max_hp = 1000
	run.attack = 400
	run.equipped_cards = ["quick_slash"]
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.set_audio_enabled(false)
	engine.setup_pvp(run, RunState.from_dict(run.to_dict()))
	if start:
		engine.start_battle()
	_engines.append(engine)
	return engine


func _run() -> void:
	_test_timing()
	_test_damage()
	_test_time_effects()
	_test_simultaneous_and_no_deadline()
	_test_independent_matches_and_score()
	await _test_network_and_ui()
	for engine: RealtimeBattleEngine in _engines:
		engine.dispose()
	if _failures.is_empty():
		print("FATIGUE_SMOKE_OK timing, shields, simultaneous death, stop/reverse, network, UI, 3D, cache")
		get_tree().quit()
	else:
		for failure: String in _failures:
			push_error(failure)
		get_tree().quit(1)


func _test_timing() -> void:
	var engine: RealtimeBattleEngine = _new_engine(false)
	var state: BattleState = engine.battle_state
	engine.update(200.0)
	_check(state.battle_time == 0.0 and state.fatigue_waves == 0, "Fatigue advanced before start")
	engine.start_battle()
	engine.update(89.0)
	_check(state.fatigue_waves == 0, "Fatigue queued early")
	engine.update(1.0)
	_check(state.fatigue_waves == 1 and state.active_instances.size() == 1, "First fatigue not queued at 90s")
	var entry: TimelineEntry = state.timeline[0]
	_check(entry.owner_side == FatigueRules.SIDE and entry.fatigue_damage == 10 and entry.scheduled_time == 95.0, "First fatigue payload invalid")
	_check(state.player.active_slots_used == 0 and state.enemy.active_slots_used == 0, "Fatigue consumed slots")
	_check(not engine.has_heavy_preparing_card("player") and state.get_active_instances_for_side("enemy").is_empty(), "Fatigue counted as a combatant card")
	engine.update(0.0)
	_check(state.battle_time == 90.0, "Paused simulation advanced")
	engine.update(5.0)
	_check(state.player.hp == 990 and state.enemy.hp == 990, "Fatigue received character attack bonus or did not resolve")
	engine.update(5.0)
	_check(state.fatigue_waves == 2 and state.timeline[0].fatigue_damage == 20, "Second fatigue did not escalate")
	engine.update(5.0)
	_check(state.player.hp == 970 and state.enemy.hp == 970, "Second fatigue damage mismatch")
	_check(Database.get_card(FatigueRules.CARD_ID) == null, "Environment card entered collectible database")
	var debug: RealtimeBattleEngine = _new_engine(false)
	_check(debug.debug_schedule_fatigue(), "Debug fatigue command failed")
	debug.update(2.0)
	_check(debug.battle_state.fatigue_waves == 0, "Debug command bypassed battle readiness")
	debug.start_battle()
	debug.update(1.0)
	_check(debug.battle_state.fatigue_waves == 1, "Debug fatigue not queued after one simulation second")
	_check(not NetworkManager.developer_schedule_local_fatigue(), "Offline client mutated a network match")


func _test_damage() -> void:
	var engine: RealtimeBattleEngine = _new_engine()
	engine.update(94.99)
	var state: BattleState = engine.battle_state
	state.player.shield = 20
	state.enemy.shield = 4
	state.enemy.add_status("vulnerable", 20.0)
	engine.update(0.02)
	_check(state.player.hp == 1000 and state.player.shield == 10, "Full shield absorption incorrect")
	_check(state.enemy.hp == 991 and state.enemy.shield == 0, "Partial shield or incoming vulnerability incorrect")
	var event: Dictionary = state.battle_events.back()
	_check(String(event.get("event_type")) == "fatigue_card", "Fatigue resolution event missing")
	_check(int(event.get("hp_delta")) == -9 and int(event.get("shield_delta")) == -14, "Fatigue event deltas incorrect")


func _test_time_effects() -> void:
	var engine: RealtimeBattleEngine = _new_engine()
	engine.update(89.0)
	engine.apply_timeline_flow("player", {"target_side": "all", "mode": "stop", "duration": 30.0})
	engine.update(2.0)
	var instance: ActiveCardInstance = engine.battle_state.active_instances[0]
	_check(is_equal_approx(instance.get_remaining(91.0), 5.0), "Spawn mid-tick was shifted before it existed")
	var remaining: float = instance.get_remaining(engine.battle_state.battle_time)
	engine.update(10.0)
	_check(is_equal_approx(instance.get_remaining(engine.battle_state.battle_time), remaining), "Whole timeline stop failed")
	_check(engine.battle_state.fatigue_waves == 2 and engine.battle_state.active_instances.size() == 2, "Stop blocked future waves")
	_check(engine.battle_state.timeline[1].fatigue_damage == 20, "Delayed fatigue did not escalate independently")
	var reverse: RealtimeBattleEngine = _new_engine()
	reverse.update(90.0)
	var reversed: ActiveCardInstance = reverse.battle_state.active_instances[0]
	reverse.apply_timeline_flow("enemy", {"target_side": "all", "mode": "reverse", "duration": 3.0, "speed": 1.0})
	reverse.update(2.0)
	_check(is_equal_approx(reversed.get_remaining(92.0), 7.0), "Reverse did not move fatigue right at constant speed")
	_check(is_equal_approx(reversed.continuous_shift_amount, 4.0), "Continuous reverse display metadata missing")
	var targeted: RealtimeBattleEngine = _new_engine()
	targeted.update(90.0)
	targeted.apply_timeline_flow("player", {"target_side": "enemy", "mode": "stop", "duration": 20.0})
	_check(targeted.delay_active_cards("enemy", 10.0, "all") == 0, "Enemy-only delay affected environment")
	targeted.update(5.0)
	_check(targeted.battle_state.player.hp == 990, "Enemy-only stop affected environment")


func _test_simultaneous_and_no_deadline() -> void:
	var engine: RealtimeBattleEngine = _new_engine()
	engine.battle_state.player.hp = 10
	engine.battle_state.enemy.hp = 10
	engine.update(95.0)
	_check(engine.battle_state.winner == "draw", "Simultaneous fatigue death favored a side")
	var end_time: float = engine.battle_state.battle_time
	engine.update(100.0)
	_check(engine.battle_state.battle_time == end_time, "Fatigue advanced after battle end")
	var long_battle: RealtimeBattleEngine = _new_engine()
	long_battle.battle_state.player.hp = 100000
	long_battle.battle_state.enemy.hp = 100000
	long_battle.update(200.0)
	_check(long_battle.battle_state.winner == "" and long_battle.battle_state.fatigue_waves == 12, "Unrequested hard deadline or missing catch-up waves")
	_check(long_battle.battle_state.timeline[0].fatigue_damage == 120, "Damage escalation capped")


func _test_independent_matches_and_score() -> void:
	var first: RealtimeBattleEngine = _new_engine()
	var second: RealtimeBattleEngine = _new_engine()
	first.update(90.0)
	second.update(40.0)
	_check(first.battle_state.fatigue_waves == 1 and second.battle_state.fatigue_waves == 0, "Parallel matches share fatigue state")
	first.update(5.0)
	_check(second.battle_state.player.hp == 1000, "Fatigue damaged another match")
	var saved_run: RunState = Game.current_run
	Game.current_run = RunState.new()
	Game.call("_record_run_battle", first.build_summary(), {})
	_check(Game.current_run.hp_damage_taken == 10, "Run score must count only the player's fatigue damage")
	Game.current_run = saved_run


func _test_network_and_ui() -> void:
	var engine: RealtimeBattleEngine = _new_engine()
	engine.update(90.0)
	var payload: Dictionary = BattleStateCodec.encode(engine.battle_state, true, true)
	# JSON round-trip exercises the actual Web number/container representation.
	var decoded: BattleState = BattleStateCodec.decode(JSON.parse_string(JSON.stringify(payload)))
	_check(decoded != null and decoded.fatigue_waves == 1 and decoded.fatigue_next_at == 100.0, "Fatigue state lost in Web snapshot")
	_check(decoded.active_instances[0].fatigue_damage == 10 and decoded.timeline[0].owner_side == FatigueRules.SIDE, "Environment identity/damage lost in Web snapshot")
	var guest: RealtimeBattleEngine = _new_engine(false)
	guest.apply_network_snapshot(decoded, true)
	_check(guest.battle_state.fatigue_waves == 1, "Guest snapshot lost fatigue state")
	var panel: TimelinePanel = TimelinePanel.new()
	panel.size = Vector2(1000, 322)
	add_child(panel)
	await get_tree().process_frame
	panel.set_fixed_horizon(FatigueRules.CAST_TIME)
	panel.refresh_timeline(decoded.timeline, 90.0, null, null, null, "enemy", null, decoded.enemy, decoded.player)
	var cards: Array[CardButton] = panel.get("_cards")
	_check(cards.size() == 1 and cards[0].visible, "Guest fatigue card invisible")
	var button: CardButton = cards[0]
	await get_tree().process_frame
	panel.refresh_timeline(decoded.timeline, 90.0)
	var scale: HBoxContainer = panel.get_node("TimelineScale") as HBoxContainer
	var zero: Label = scale.get_child(0) as Label
	var end: Label = scale.get_child(4) as Label
	var expected_center: float = lerpf(zero.global_position.x + zero.size.x / 2.0, end.global_position.x + end.size.x / 2.0, 5.0 / 8.0)
	_check(absf(button.global_position.x + 84.0 - expected_center) < 1.0, "5-second fatigue must align to the rounded 8-second scale")
	_check(button.tooltip_text.contains("10") and button.tooltip_text.contains("両者"), "Fatigue tooltip missing target/damage")
	_check(button.call("_get_active_border", FatigueRules.SIDE) == FatigueRules.BORDER_COLOR, "Environment border not distinct")
	_check(not bool(button.get("_cost_badge").visible), "Environment card shows slot cost badge")
	_check(button.get("_art_rect").texture.resource_path == FatigueRules.ART_PATH, "Fatigue art not loaded")
	var count: int = CardButton.get_cached_texture_count()
	for index in range(40):
		panel.refresh_timeline(decoded.timeline, 90.0 + index * 0.01)
	_check(CardButton.get_cached_texture_count() == count, "Fatigue art cache grows every frame")
	engine.update(5.0)
	var final_state: BattleState = BattleStateCodec.decode(BattleStateCodec.encode(engine.battle_state, true, true))
	var event: Dictionary = final_state.battle_events.back()
	_check(String(event.get("event_type")) == "fatigue_card" and int(event.get("result", {}).get("amount")) == 10, "Compact fatigue event lost")
	var stage: BattleStage3D = BattleStage3D.new()
	add_child(stage)
	await get_tree().process_frame
	stage.configure_combatants("enemy", "player", "enemy")
	stage.play_battle_event(event)
	_check(stage.get_floating_combat_text_count() == 2, "Fatigue must show damage on both 3D actors")
	_check(stage.get_active_effect_count() >= 2, "Fatigue impact effects missing")
	stage.queue_free()
	panel.queue_free()
	await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
