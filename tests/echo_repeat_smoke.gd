extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized(); Game.set_language("en")
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("Echo repeat: " + message); get_tree().quit(1); assert(value, message)


func _engine(cards: Array[String]) -> RealtimeBattleEngine:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.equipped_cards = cards; run.max_hp = 500; run.player_hp = 500
	var foe: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242); foe.max_hp = 500; foe.player_hp = 500
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false); engine.setup_pvp(run, foe); engine.start_battle()
	return engine


func _runtime(engine: RealtimeBattleEngine, id: String) -> CardRuntimeState:
	for runtime: CardRuntimeState in engine.battle_state.player.card_runtime_states:
		if runtime.card_id == id: return runtime
	return null


func _use(engine: RealtimeBattleEngine, id: String) -> void:
	_check(engine.request_use_card("player", _runtime(engine, id).runtime_id), "cannot queue " + id)


func _resolve(engine: RealtimeBattleEngine, id: String) -> void:
	for instance: ActiveCardInstance in engine.battle_state.active_instances:
		if instance.card_id == id and not instance.is_auto_queued:
			engine.update(maxf(0.0001, instance.scheduled_time - engine.battle_state.battle_time) + 0.0001)
			return
	_check(false, "no queued card " + id)


func _event(engine: RealtimeBattleEngine, id: String) -> Dictionary:
	for index: int in range(engine.battle_state.battle_events.size() - 1, -1, -1):
		var event: Dictionary = engine.battle_state.battle_events[index]
		if event["event_type"] == "resolve_card" and event["card_id"] == id: return event
	return {}


func _run() -> void:
	_test_card_and_long_cast()
	_test_effects()
	_test_exclusions()
	_test_conditions_and_lethal()
	_test_codec()
	await _test_timeline()
	await _test_visuals()
	print("ECHO_REPEAT_SMOKE_OK checks=%d costs/interrupt/auto/charge/relic/conditions/bleed/codec/timeline/visuals" % _checks)
	get_tree().quit()


func _test_card_and_long_cast() -> void:
	for grade: int in range(6):
		var card: CardDef = CardUpgradeResolver.build_card_at_tier("echo_cast", grade)
		_check(card.effects[0]["charges"] == 1 and is_equal_approx(card.cast_time, 2.4 - grade * 0.1) and card.recast_time == 32 - grade, "grade profile")
	var engine: RealtimeBattleEngine = _engine(["heavy_swing", "echo_cast"])
	_use(engine, "heavy_swing"); _use(engine, "echo_cast"); _resolve(engine, "echo_cast")
	_check(engine.battle_state.player.repeat_charges == 1 and engine.battle_state.player.active_slots_used == 2, "Echo did not arm an already-casting card")
	_resolve(engine, "heavy_swing")
	var result: Dictionary = _event(engine, "heavy_swing")["result"]
	_check(engine.battle_state.enemy.hp == 466 and result["effect_repeats"] == 2, "heavy effects did not resolve twice")
	_check(result["metrics"]["damage"] == 34 and result["effect_resolutions"][0]["metrics"]["damage"] == 17 and result["effect_resolutions"][1]["metrics"]["damage"] == 17, "per-pulse/total metrics")
	_check(engine.battle_state.player.repeat_charges == 0 and engine.battle_state.player.active_slots_used == 0, "charge/slot consumption")
	_check(_runtime(engine, "heavy_swing").cooldown_remaining == 26 and engine.battle_state.relic_runtime_state["player"]["manual_resolves"] == 2, "cooldown or card-use counter duplicated")
	engine.dispose()
	var progress: Dictionary = Database.meta_progress_template.duplicate(true)
	progress["unlock_xp"] = 8; MetaProgressService.new().ensure_defaults(progress)
	_check(progress["unlocked_cards"].has("echo_cast"), "existing XP8 profile did not unlock Echo")


func _test_effects() -> void:
	var engine: RealtimeBattleEngine = _engine(["guard"])
	engine.battle_state.player.grant_repeat_charges(1); engine.battle_state.player.charge_next_attack(2)
	_use(engine, "guard"); _resolve(engine, "guard")
	_check(engine.battle_state.player.shield == 16 and engine.battle_state.player.next_attack_multiplier == 2, "shield repeat consumed attack charge")
	_check(engine.battle_state.relic_runtime_state["player"]["manual_resolves"] == 1, "one repeated card counted twice")
	engine.dispose(); engine = _engine(["heavy_swing"])
	engine.battle_state.player.grant_repeat_charges(1); engine.battle_state.player.charge_next_attack(2)
	_use(engine, "heavy_swing"); _resolve(engine, "heavy_swing")
	_check(engine.battle_state.enemy.hp == 432 and engine.battle_state.player.next_attack_multiplier == 1, "attack charge must apply to both pulses and be consumed once")
	engine.dispose(); engine = _engine(["quick_slash"])
	engine.battle_state.enemy.shield = 9; engine.battle_state.player.grant_repeat_charges(1)
	_use(engine, "quick_slash"); _resolve(engine, "quick_slash")
	var parts: Array = _event(engine, "quick_slash")["result"]["effect_resolutions"]
	_check(engine.battle_state.enemy.hp == 494 and parts[0]["fully_blocked"] and not parts[1]["fully_blocked"], "hits must evaluate shield independently")
	_check(parts[0]["metrics"]["absorbed"] == 7 and parts[1]["metrics"]["absorbed"] == 1, "shield absorption metrics")
	engine.dispose(); engine = _engine(["repair_burst"])
	var amount: int = int(Database.get_card("repair_burst").effects[0]["amount"])
	engine.battle_state.player.hp = 500 - amount - 2; engine.battle_state.player.grant_repeat_charges(1)
	_use(engine, "repair_burst"); _resolve(engine, "repair_burst")
	_check(engine.battle_state.player.hp == 500 and _event(engine, "repair_burst")["result"]["metrics"]["heal"] == amount + 2, "healing must exclude overheal")
	engine.dispose(); engine = _engine(["bleed_cut"])
	engine.battle_state.player.grant_repeat_charges(1); _use(engine, "bleed_cut"); _resolve(engine, "bleed_cut")
	_check(engine.battle_state.enemy.statuses["bleed"]["stacks"] == 2 and engine.battle_state.enemy.statuses["bleed"]["damage"] == 2, "bleed repeat did not create two layers")
	engine.dispose(); engine = _engine(["aegis_ram"])
	engine.battle_state.player.shield = 20; engine.battle_state.player.grant_repeat_charges(1)
	_use(engine, "aegis_ram")
	_check(engine.battle_state.player.shield == 16, "shield cost was not paid at registration")
	_resolve(engine, "aegis_ram")
	_check(_event(engine, "aegis_ram")["result"]["messages"].filter(func(message: String) -> bool: return message.contains("consumed")).size() == 1, "shield cost repeated in logs")
	engine.dispose()


func _test_exclusions() -> void:
	var engine: RealtimeBattleEngine = _engine(["heavy_swing", "strike", "echo_cast"])
	engine.battle_state.player.grant_repeat_charges(1); _use(engine, "heavy_swing")
	_check(engine.interrupt_active_card("player", "single_interruptible") == 1 and engine.battle_state.player.repeat_charges == 1, "interrupt consumed Echo")
	_use(engine, "echo_cast"); _resolve(engine, "echo_cast")
	_check(engine.battle_state.player.repeat_charges == 2 and _event(engine, "echo_cast")["result"]["effect_repeats"] == 1, "Echo repeated itself")
	_use(engine, "strike"); _resolve(engine, "strike")
	_check(engine.battle_state.player.repeat_charges == 1 and _event(engine, "strike")["result"]["effect_repeats"] == 2, "stacked Echo multiplied repetitions instead of target count")
	_check(engine.battle_state.player.grant_repeat_charges(99) == 2 and engine.battle_state.player.repeat_charges == 3, "charge cap")
	engine.dispose(); engine = _engine(["quick_slash"])
	engine.battle_state.player.grant_repeat_charges(1)
	var source: ActiveCardInstance = ActiveCardInstance.new(); source.card_id = "quick_slash"; source.owner_side = "player"
	_check(engine.auto_queue_card("player", source, {"card_id": "quick_slash", "count": 1, "max_depth": 1, "use_cast_time": false}) == 1, "auto setup")
	engine.update(0.01)
	_check(engine.battle_state.enemy.hp == 493 and engine.battle_state.player.repeat_charges == 1, "auto card consumed Echo")
	_use(engine, "quick_slash"); _resolve(engine, "quick_slash")
	_check(engine.battle_state.enemy.hp == 479 and engine.battle_state.player.repeat_charges == 0, "manual card did not consume remaining Echo")
	engine.dispose()
	engine = _engine(["auto_turret"])
	engine.battle_state.player.grant_repeat_charges(1); _use(engine, "auto_turret"); _resolve(engine, "auto_turret")
	_check(engine.battle_state.active_instances.filter(func(instance: ActiveCardInstance) -> bool: return instance.is_auto_queued).size() == 2, "repeated auto-queue effect did not run twice")
	engine.battle_state.player.grant_repeat_charges(1)
	for generation: int in 3:
		var at: float = engine.battle_state.active_instances[0].scheduled_time
		engine.update(maxf(0.0001, at - engine.battle_state.battle_time) + 0.0001)
		_check(engine.battle_state.active_instances.size() == 2 and engine.battle_state.player.repeat_charges == 1, "auto-copy recursion consumed Echo or grew exponentially")
	engine.dispose()


func _test_conditions_and_lethal() -> void:
	var engine: RealtimeBattleEngine = _engine(["self_tuning_edge"])
	var base: int = int(Database.get_card("self_tuning_edge").effects[0]["amount"]) + 3
	engine.battle_state.player.grant_repeat_charges(1); _use(engine, "self_tuning_edge"); _resolve(engine, "self_tuning_edge")
	_check(_event(engine, "self_tuning_edge")["result"]["metrics"]["damage"] == base * 2 + 1, "second pulse ignored self empowerment")
	_check(engine.get_run_for_side("player").temporary_card_modifiers["self_tuning_edge"]["damage"] == 2, "empower effect did not happen twice")
	engine.dispose(); engine = _engine(["execution"])
	var effect: Dictionary = Database.get_card("execution").effects[0]
	var hit: int = int(effect["amount"]) + 3
	var threshold: int = floori(float(effect["bonus_if_target_hp_below_ratio"]) * 100)
	engine.battle_state.enemy.max_hp = 100; engine.battle_state.enemy.hp = threshold + hit
	engine.battle_state.player.grant_repeat_charges(1); _use(engine, "execution"); _resolve(engine, "execution")
	var parts: Array = _event(engine, "execution")["result"]["effect_resolutions"]
	_check(parts[0]["metrics"]["damage"] == hit and parts[1]["metrics"]["damage"] == mini(threshold, hit + int(effect["bonus_amount"])), "second pulse did not re-evaluate the HP condition")
	engine.dispose(); engine = _engine(["self_tuning_edge"])
	engine.battle_state.enemy.hp = 1; engine.battle_state.player.grant_repeat_charges(1)
	_use(engine, "self_tuning_edge"); _resolve(engine, "self_tuning_edge")
	_check(_event(engine, "self_tuning_edge")["result"]["effect_repeats"] == 1 and engine.battle_state.winner == "player", "second pulse ran after lethal")
	_check(engine.get_run_for_side("player").temporary_card_modifiers["self_tuning_edge"]["damage"] == 1, "post-lethal extra empowerment")
	engine.dispose()


func _test_codec() -> void:
	var engine: RealtimeBattleEngine = _engine(["quick_slash"])
	engine.battle_state.player.grant_repeat_charges(2); _use(engine, "quick_slash"); _resolve(engine, "quick_slash")
	for compact: bool in [false, true]:
		var decoded: BattleState = BattleStateCodec.decode(JSON.parse_string(JSON.stringify(BattleStateCodec.encode(engine.battle_state, true, compact))))
		_check(decoded.player.repeat_charges == 1, "codec lost remaining charges")
		var events: Array = decoded.battle_events.filter(func(event: Dictionary) -> bool: return event["event_type"] == "resolve_card")
		_check(events.back()["result"]["effect_resolutions"].size() == 2, "codec lost repeat visuals")
	var frame: Dictionary = BattleRecording.frame_at(engine.recording.frames, engine.battle_state.battle_time)
	_check(BattleStateCodec._decode_unit(frame["player"]).repeat_charges == 1, "visual replay lost charges")
	engine.dispose()


func _entry(id: String, instance: int, seconds: float, auto: bool = false) -> TimelineEntry:
	var entry: TimelineEntry = TimelineEntry.new(); entry.card_id = id; entry.card_name = id; entry.instance_id = instance; entry.owner_side = "player"; entry.runtime_id = str(instance); entry.scheduled_time = seconds; entry.is_auto_queued = auto
	return entry


func _test_timeline() -> void:
	var panel: TimelinePanel = TimelinePanel.new(); add_child(panel); panel.size = Vector2(1000, 350)
	var unit: UnitState = UnitState.new(); unit.grant_repeat_charges(1)
	var heavy: TimelineEntry = _entry("heavy_swing", 1, 5); var quick: TimelineEntry = _entry("quick_slash", 2, 7)
	var entries: Array[TimelineEntry] = [heavy, quick, _entry("echo_cast", 3, 1), _entry("quick_slash", 4, 2, true)]
	panel.refresh_timeline(entries, 0, null, null, null, "player", null, unit, null)
	await get_tree().process_frame
	_check(not panel._cards[0]._repeat_badge.visible and not panel._cards[1]._repeat_badge.visible and panel._cards[2]._repeat_badge.visible and not panel._cards[3]._repeat_badge.visible, "candidate included support or auto card")
	heavy.scheduled_time = 8
	panel.refresh_timeline(entries, 0, null, null, null, "player", null, unit, null)
	_check(panel._cards[2].runtime_id == quick.runtime_id and panel._cards[2]._repeat_badge.visible and not panel._cards[3]._repeat_badge.visible and panel._cards[2].tooltip_text.contains("Echo: effects repeat twice"), "delay did not move the candidate")
	heavy.scheduled_time = 7; heavy.priority_modifier = 0.3
	panel.refresh_timeline(entries, 0, null, null, null, "player", null, unit, null)
	_check(panel._cards[2].runtime_id == heavy.runtime_id and panel._cards[2]._repeat_badge.visible, "UI priority tie-break differs from resolution order")
	unit.repeat_charges = 2; panel.refresh_timeline(entries, 0, null, null, null, "player", null, unit, null)
	_check(panel._cards[2]._repeat_badge.visible and panel._cards[3]._repeat_badge.visible, "two charges did not mark two cards")
	unit.repeat_charges = 0
	panel.refresh_timeline(entries, 0, null, null, null, "player", null, unit, null)
	_check(panel._cards.all(func(card: CardButton) -> bool: return not card._repeat_badge.visible), "pooled card kept stale repeat badge")
	panel.queue_free(); await get_tree().process_frame
	var plate: BattleUnitStatus3D = BattleUnitStatus3D.new(); add_child(plate)
	unit.grant_repeat_charges(2); unit.charge_next_attack(2)
	for id: String in ["bleed", "weak", "slow", "vulnerable"]: unit.add_status(id, 18)
	plate.refresh_unit(unit)
	_check(plate.get_status_regions().size() == 6 and plate.get_status_text().contains("Echo"), "new buff hid an existing status or lacked a summary")
	_check((plate.find_child("StatusTime3D_echo_ready", true, false) as Label3D).text == "2", "Echo stock must not display a fake timer")
	plate.queue_free(); await get_tree().process_frame


func _test_visuals() -> void:
	var engine: RealtimeBattleEngine = _engine(["quick_slash"])
	engine.battle_state.player.grant_repeat_charges(1); _use(engine, "quick_slash"); _resolve(engine, "quick_slash")
	var event: Dictionary = _event(engine, "quick_slash")
	var stage: BattleStage3D = BattleStage3D.new(); add_child(stage); stage.configure_combatants("player", "enemy")
	await get_tree().process_frame
	stage.set("_cast_counts", {"player": 2})
	AudioManager.clear_play_history(); stage.play_battle_event(event)
	stage.call("_apply_pending_resolution_visuals"); stage.call("_update_event_queue", 0.2)
	_check(stage.get_floating_combat_text_values().count("-7") == 2 and not stage.get_floating_combat_text_values().has("-14"), "visuals merged two hits into one number")
	_check(AudioManager.get_play_history().size() == 1, "repeat visuals replayed card audio")
	_check(stage.get("_cast_counts")["player"] == 1, "second visual decremented another casting card")
	stage.queue_free(); engine.dispose(); await get_tree().process_frame
