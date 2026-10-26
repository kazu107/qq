extends Node


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		push_error("Timekeeper: " + message)
		get_tree().quit(1)
		assert(value, message)


func _engine() -> RealtimeBattleEngine:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.max_hp = 1000
	run.player_hp = 1000
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.set_audio_enabled(false)
	engine.setup(run, "boss_timekeeper")
	return engine


func _advance(engine: RealtimeBattleEngine, until: float) -> void:
	while engine.battle_state.battle_time < until and engine.battle_state.winner == "":
		engine.update(0.05)


func _active(engine: RealtimeBattleEngine, id: String) -> ActiveCardInstance:
	for instance: ActiveCardInstance in engine.battle_state.active_instances:
		if instance.card_id == id:
			return instance
	return null


func _run() -> void:
	_check(Database.get_all_card_ids().size() == 120 and Database.get_boss_card_ids().size() == 3, "Collectible catalog changed")
	for id: String in Database.get_boss_card_ids():
		_check(not Database.get_card_ids_by_rarity("legendary").has(id), "Boss card leaked into rewards")
		_check(not DeckPresetService.valid_cards([id]), "Player preset accepted a boss card")
		var profile: Dictionary = LanProtocol.build_profile("Player", "balanced")
		profile["deck"] = [id]
		_check(not bool(LanProtocol.validate_profile(profile)["valid"]), "Forged online profile accepted a boss card")
	var engine: RealtimeBattleEngine = _engine()
	_check(engine.battle_state.active_instances.is_empty(), "Boss started during preparation")
	engine.start_battle()
	_check(_active(engine, "timekeeper_final_strike") != null, "Opening strike missing")
	_check(engine.battle_state.enemy.active_slots_used == 2, "Opening strike did not reserve two slots")
	_check(is_equal_approx(_active(engine, "timekeeper_final_strike").scheduled_time, 40), "Opening cast was not 40s")
	_advance(engine, 9.2)
	_check(engine.battle_state.enemy.next_attack_multiplier == 2.0, "Amplifier did not resolve at the planned time")
	var context: Dictionary = CardTooltipResolver.build_context("timekeeper_final_strike", null, engine.battle_state.enemy)
	_check(int((context["card"] as CardDef).effects[0]["amount"]) == 62, "Live tooltip did not show attack-inclusive double damage")
	_advance(engine, 20.3)
	_check(engine.battle_state.enemy.next_attack_multiplier == 4.0, "Second amplifier did not stack to x4")
	context = CardTooltipResolver.build_context("timekeeper_final_strike", null, engine.battle_state.enemy)
	_check(int((context["card"] as CardDef).effects[0]["amount"]) == 124, "Live tooltip did not update to x4")
	var restored: BattleState = BattleStateCodec.decode(BattleStateCodec.encode(engine.battle_state, true))
	_check(restored.enemy.next_attack_multiplier == 4.0, "Snapshot clamped a stacked charge")
	var charged_frame: Dictionary = BattleRecording.frame_at(engine.recording.frames, 20.3)
	_check(BattleStateCodec._decode_unit(Dictionary(charged_frame["enemy"])).next_attack_multiplier == 4.0, "Visual replay lost stacked charge")
	var old_snapshot: Dictionary = BattleStateCodec.encode(engine.battle_state, true)
	Dictionary(old_snapshot["enemy"]).erase("next_attack_multiplier")
	_check(BattleStateCodec.decode(old_snapshot).enemy.next_attack_multiplier == 1.0, "Old snapshot did not default to an uncharged attack")
	_check(engine.battle_state.enemy.get_display_statuses().has("attack_charge"), "Charge display absent")
	_advance(engine, 31.4)
	_check(engine.battle_state.enemy.next_attack_multiplier == 8.0, "Third amplifier did not stack to x8")
	context = CardTooltipResolver.build_context("timekeeper_final_strike", null, engine.battle_state.enemy)
	_check(int((context["card"] as CardDef).effects[0]["amount"]) == 248, "Live tooltip did not update to x8")
	_advance(engine, 39.8)
	_check(engine.battle_state.player.has_status("vulnerable"), "Mark did not prepare the target")
	_advance(engine, 40.2)
	_check(engine.battle_state.player.hp == 501, "Expected four amplifiers: (25 + 6) * 16 + 3 = 499 damage")
	_check(engine.battle_state.enemy.next_attack_multiplier == 1.0, "Charge did not consume exactly once")
	_check(BattleStateCodec._decode_unit(Dictionary(engine.recording.frames.back()["enemy"])).next_attack_multiplier == 1.0, "Visual replay retained a consumed charge")
	_advance(engine, 48.3)
	_check(_active(engine, "timekeeper_final_strike") != null, "Boss did not begin its second cycle")
	_advance(engine, 57.5)
	_check(engine.battle_state.enemy.next_attack_multiplier == 2.0, "Second cycle did not re-arm the amplifier")
	engine.dispose()
	engine = _engine()
	engine.start_battle()
	_advance(engine, 7.0)
	_check(engine.interrupt_active_card("enemy", "single_interruptible") == 1, "Amplifier could not be interrupted")
	_check(engine.interrupt_active_card("enemy", "all_interruptible") == 0, "Uninterruptible strike was cancelled")
	_advance(engine, 8.0)
	_check(_active(engine, "timekeeper_amplify") == null, "Interrupted amplifier retried without its cooldown")
	_advance(engine, 40.2)
	_check(engine.battle_state.player.hp == 749, "Interrupting one amplifier should leave x8, not x16")
	engine.dispose()
	engine = _engine()
	engine.start_battle()
	engine.delay_active_cards("enemy", 12, "single")
	_advance(engine, 42.5)
	_check(engine.battle_state.enemy.next_attack_multiplier == 16.0, "Delayed strike did not allow a fourth amplifier")
	_check(BattleStateCodec.decode(BattleStateCodec.encode(engine.battle_state, true)).enemy.next_attack_multiplier == 16.0, "Snapshot lost x16")
	_advance(engine, 48.5)
	_check(engine.battle_state.enemy.next_attack_multiplier == 32.0, "Shorter recast did not allow a fifth amplifier before the delayed strike")
	_advance(engine, 52.3)
	_check(engine.battle_state.player.hp == 5, "Delayed x32 strike should deal 995 damage")
	_check(engine.battle_state.enemy.next_attack_multiplier == 1.0, "Delayed strike retained its charge")
	engine.dispose()
	engine = _engine()
	engine.start_battle()
	_advance(engine, 36.0)
	_check(_active(engine, "timekeeper_time_mark") != null, "Expected a mark, not an amplifier, before interruption")
	_check(engine.interrupt_active_card("enemy", "single_interruptible") == 1, "Mark could not be interrupted")
	_advance(engine, 40.2)
	_check(engine.battle_state.player.hp == 504, "Interrupted mark was retried or late amplification changed x16")
	engine.dispose()
	engine = _engine()
	engine.start_battle()
	engine.set_enemy_ai_enabled(false)
	engine.delay_active_cards("enemy", 5, "single")
	engine.apply_timeline_flow("player", {"mode": "stop", "target_side": "enemy", "duration": 3.0})
	_advance(engine, 3.5)
	_check(absf(_active(engine, "timekeeper_final_strike").scheduled_time - 48.0) < 0.1, "Delay/stop did not affect the strike")
	engine.apply_timeline_flow("player", {"mode": "reverse", "target_side": "enemy", "duration": 2.0, "speed": 1.0})
	_advance(engine, 5.7)
	_check(absf(_active(engine, "timekeeper_final_strike").scheduled_time - 52.0) < 0.1, "Reverse did not affect the strike")
	var unit: UnitState = engine.battle_state.enemy
	unit.charge_next_attack(2)
	unit.charge_next_attack(2)
	DamageResolver.apply_fixed_damage(unit, 1)
	_check(unit.next_attack_multiplier == 4.0, "Charge did not stack or fixed damage consumed it")
	engine.debug_schedule_fatigue()
	_advance(engine, 7.0)
	_check(unit.next_attack_multiplier == 4.0, "Fatigue consumed charge")
	unit.add_status("bleed", 7.0)
	_advance(engine, 13.1)
	_check(unit.next_attack_multiplier == 4.0, "Bleed consumed charge")
	var support: CardDef = Database.get_card("timekeeper_amplify")
	var instance: ActiveCardInstance = ActiveCardInstance.new()
	instance.owner_side = "enemy"
	CardEffectResolver.resolve(engine, engine.battle_state, instance, support)
	_check(unit.next_attack_multiplier == 8.0, "Amplifier did not add another stack")
	var multi: CardDef = CardDef.new()
	multi.effects = [{"type": "deal_damage", "amount": 5}, {"type": "deal_damage", "amount": 7}]
	engine.battle_state.player.add_status("vulnerable", 10)
	var before: int = engine.battle_state.player.hp
	CardEffectResolver.resolve(engine, engine.battle_state, instance, multi)
	_check(before - engine.battle_state.player.hp == 198 and unit.next_attack_multiplier == 1, "Multi-hit card did not share stacked charge across every hit")
	unit.add_status("weak", 12.0)
	unit.charge_next_attack(2)
	var target: UnitState = engine.battle_state.player
	target.shield = 100
	before = target.hp
	CardEffectResolver.resolve(engine, engine.battle_state, instance, Database.get_card("timekeeper_final_strike"))
	_check(target.hp == before and target.shield == 39 and unit.next_attack_multiplier == 1.0, "Weak/shield did not apply to (25 + 4) * 2 + 3 or blocked attack kept its charge")
	engine.dispose()
	var stage: BattleStage3D = BattleStage3D.new()
	add_child(stage)
	await get_tree().process_frame
	var display_unit: UnitState = UnitState.new()
	display_unit.charge_next_attack(2)
	display_unit.charge_next_attack(2)
	for id: String in ["bleed", "weak", "slow", "vulnerable"]: display_unit.add_status(id, 12)
	stage.refresh_unit_status(display_unit, display_unit)
	_check(stage.get_enemy_status_model().get_status_regions().size() == 5, "Charge hid another status icon")
	var value: Label3D = stage.get_enemy_status_model().find_child("StatusTime3D_attack_charge", true, false) as Label3D
	_check(value != null and value.text == "x4", "3D charge label did not show its actual multiplier")
	var tooltip: String = String(stage.get_enemy_status_model().get_status_regions()[0]["tooltip"])
	_check(tooltip.contains("4") and not tooltip.contains("0.0s"), "Stacked charge tooltip used a fake timer")
	var panel: UnitPanel = UnitPanel.new()
	add_child(panel)
	panel.refresh_unit(display_unit)
	_check((panel._status_time_labels["attack_charge"] as Label).text == "x4", "2D fallback did not show x4")
	panel.queue_free()
	stage.queue_free()
	await get_tree().process_frame
	for starter: Dictionary in Database.starters:
		var starter_id: String = String(starter["id"])
		var run: RunState = RunState.from_starter(starter, 4242)
		var simulation: BattleSimulation = BattleSimulation.new()
		simulation.setup(run, "boss_timekeeper", 300.0, 0.0, false)
		while not simulation.finished:
			simulation.advance(100)
		var result: Dictionary = simulation.result()
		_check(not bool(result["unresolved"]), "Starter simulation never finished: " + starter_id)
		print("TIMEKEEPER_STARTER_RESULT %s winner=%s time=%.2f hp=%d" % [starter_id, result["winner"], result["battle_time"], result["player_hp"]])
		simulation.dispose()
	print("TIMEKEEPER_REWORK_SMOKE_OK repeat casts, x2/x4/x8/x16, live damage, consume, interrupt, delay/stop/reverse, ownership, snapshots, replay and 2D/3D status icons")
	get_tree().quit()
