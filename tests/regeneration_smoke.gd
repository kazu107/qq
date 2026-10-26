extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized(); Game.set_language("en")
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value: push_error("Regeneration: " + message); get_tree().quit(1); assert(value, message)


func _engine(cards: Array[String] = ["regen_patch"]) -> RealtimeBattleEngine:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.equipped_cards = cards; run.max_hp = 1000; run.player_hp = 500
	var e: RealtimeBattleEngine = RealtimeBattleEngine.new(); e.set_audio_enabled(false); e.setup_pvp(run, run); e.start_battle()
	return e


func _cast(e: RealtimeBattleEngine, side: String, id: String) -> void:
	for runtime: CardRuntimeState in e.battle_state.get_unit(side).card_runtime_states:
		if runtime.card_id != id: continue
		_check(e.request_use_card(side, runtime.runtime_id), "queue " + id)
		var instance: ActiveCardInstance = e.battle_state.get_active_instances_for_side(side)[0]
		e.update(instance.scheduled_time - e.battle_state.battle_time + 0.0001); return
	_check(false, "missing runtime " + id)


func _heal(events: Array) -> int:
	var total: int = 0
	for event: Dictionary in events:
		if event["type"] == "status_heal": total += int(event["amount"])
	return total


func _run() -> void:
	_test_rules()
	_test_cards()
	_test_mixed_statuses()
	_test_interactions()
	_test_codec_and_metrics()
	await _test_ui()
	print("REGENERATION_SMOKE_OK checks=%d cards=8 grades=0..5 layers/partition/boundary/mixed/echo/reservations/stats/codec/UI" % _checks)
	get_tree().quit()


func _test_rules() -> void:
	var unit: UnitState = UnitState.new(); unit.add_regeneration(12, 2, "player", "regen_patch")
	_check(unit.tick_statuses(2.99).is_empty(), "early tick")
	_check(_heal(unit.tick_statuses(.01)) == 2, "first tick")
	_check(_heal(unit.tick_statuses(9)) == 6 and not unit.has_status("regen"), "final boundary tick")
	var a: UnitState = UnitState.new(); var b: UnitState = UnitState.new()
	for target: UnitState in [a, b]:
		target.add_regeneration(12, 2, "player", "regen_patch"); target.add_regeneration(18, 3, "player", "regen_tank")
	_check(_heal(a.tick_statuses(18)) == 26, "layer totals")
	var total: int = 0
	for i: int in 360: total += _heal(b.tick_statuses(.05))
	_check(total == 26 and b.statuses.is_empty(), "frame partition")
	unit.add_regeneration(12, 2, "player", "regen_patch"); unit.tick_statuses(2)
	unit.add_regeneration(6, 5, "player", "regen_burst")
	_check(_heal(unit.tick_statuses(1)) == 7, "application reset the shared clock")
	unit.add_regeneration(30, 1, "player", "regen_tank"); unit.add_regeneration(15, 4, "player", "regen_emergency")
	_check(unit.statuses["regen"]["stacks"] == 3 and unit.statuses["regen"]["power"] == 7, "fourth layer must replace shortest duration")
	unit.adjust_status_duration("regen", -30); _check(not unit.has_status("regen"), "duration adjustment")
	unit.add_regeneration(6, 3, "player", "regen_patch"); unit.statuses["regen"]["suspended"] = 2
	_check(_heal(unit.tick_statuses(4)) == 0 and _heal(unit.tick_statuses(1)) == 3, "suspended overshoot")
	unit.remove_status("regen"); unit.add_regeneration(0, 9, "player", "regen_patch")
	_check(not unit.has_status("regen"), "zero-duration ghost")


func _test_cards() -> void:
	var draft: BalanceDraft = BalanceDraft.new()
	for id: String in RegenerationRules.CARD_IDS:
		for grade: int in 6:
			var expected: CardDef = CardUpgradeResolver.build_card_at_tier(id, grade)
			_check(not CardInfoFormatter.build_effect_summary(expected).contains("unknown") and not CardFaceSummaryResolver.build_summaries(expected).is_empty(), "card summary " + id)
			_check(draft.card(id, grade).effects == expected.effects, "lab grade " + id)
			for side: String in ["player", "enemy"]:
				var e: RealtimeBattleEngine = _engine([id]); e.add_battle_card_modifier(side, id, "grade", grade)
				var unit: UnitState = e.battle_state.get_unit(side)
				if id == "regen_emergency": unit.hp = 400
				if id == "regen_spring": unit.add_status("bleed", 30, 1)
				_cast(e, side, id)
				var effect: Dictionary = expected.effects[-1]
				var power: int = int(effect["regen_power"]) + floori(unit.max_hp * float(effect.get("regen_max_hp_ratio", 0)))
				if id == "regen_emergency": power += int(effect["bonus_power"])
				_check(unit.statuses["regen"]["power"] == power and is_equal_approx(unit.statuses["regen"]["duration"], effect["duration"]), "applied grade " + id)
				if id == "regen_spring": _check(not unit.has_status("bleed"), "spring did not cleanse")
				var before: int = unit.hp; e.update(3)
				_check(unit.hp - before == power, "tick grade " + id)
				e.dispose()
	_check(draft.set_value("card", "regen_tank", "effects.0.regen_max_hp_ratio", .025), "fractional max-HP ratio")
	_check(not draft.set_value("card", "regen_patch", "effects.0.regen_power", 0), "zero power accepted")


func _test_mixed_statuses() -> void:
	for reversed_order: bool in [false, true]:
		for fine: bool in [false, true]:
			var e: RealtimeBattleEngine = _engine()
			var unit: UnitState = e.battle_state.player; unit.hp = 1; unit.max_hp = 10
			if reversed_order: unit.add_regeneration(6, 3, "player", "regen_patch")
			unit.add_status("bleed", 6, 2, "enemy")
			if not reversed_order: unit.add_regeneration(6, 3, "player", "regen_patch")
			if fine:
				for i: int in 120: e.update(.05)
			else: e.update(6)
			_check(unit.hp == 5, "mixed chronology/insertion order/partition")
			e.dispose()
	var e: RealtimeBattleEngine = _engine(); var unit: UnitState = e.battle_state.player
	unit.hp = 1; unit.max_hp = 10; unit.add_status("bleed", 6, 5, "enemy"); unit.add_regeneration(6, 3, "player", "regen_patch")
	e.update(6); _check(unit.hp == 0, "same-boundary damage must precede heal, never revive")
	e.dispose(); e = _engine(); e.battle_state.player.hp = 1000
	e.apply_status_from_card("player", "player", "regen", 6, 4, "regen_patch"); e.update(6)
	_check(e.battle_state.player.hp == 1000 and e.battle_state.player.combat_totals["heal"] == 0, "overheal credited")
	e.dispose()


func _test_interactions() -> void:
	var e: RealtimeBattleEngine = _engine()
	e.battle_state.player.grant_repeat_charges(1); e.battle_state.player.charge_next_attack(2)
	_cast(e, "player", "regen_patch")
	_check(e.battle_state.player.statuses["regen"]["stacks"] == 2 and e.battle_state.player.next_attack_multiplier == 2, "Echo/attack charge interaction")
	e.update(3); _check(e.battle_state.player.hp == 504, "Echo doubled regen layers")
	e.dispose(); e = _engine()
	ReservedCardRules.grant(e.battle_state.player, Database.get_card("reserve_heal_jam").effects[0], "enemy")
	_cast(e, "player", "regen_patch")
	_check(e.battle_state.player.card_reservations.is_empty() and e.battle_state.enemy.hp == 504 and e.battle_state.player.statuses["regen"]["power"] == 1, "healing corruption snapshot")
	e.dispose(); e = _engine()
	ReservedCardRules.grant(e.battle_state.player, Database.get_card("reserve_mirror").effects[0], "enemy")
	_cast(e, "player", "regen_patch")
	_check(e.battle_state.enemy.statuses["regen"]["power"] == 1 and e.battle_state.enemy.statuses["regen"]["duration"] == 12, "mirror did not copy regen")
	e.update(3); _check(e.battle_state.enemy.hp == 501 and e.analysis.rows["enemy:reserve_mirror"]["heal"] == 1, "mirror tick credit")
	e.dispose(); e = _engine()
	ReservedCardRules.grant(e.battle_state.player, Database.get_card("reserve_status").effects[0], "player")
	_cast(e, "player", "regen_patch")
	_check(e.battle_state.player.statuses["regen"]["duration"] == 18 and e.battle_state.player.statuses["regen"]["power"] == 2, "status booster changed unrelated power")
	e.dispose(); e = _engine(["regen_emergency"]); e.battle_state.player.hp = 400
	var context: Dictionary = CardTooltipResolver.build_context("regen_emergency", e.get_run_for_side("player"), e.battle_state.player)
	_check(context["card"].effects[0]["regen_power"] == 4 and "\n".join(CardInfoFormatter.build_effect_lines(context["card"], context["comparison"], true)).contains("#72d36f"), "live low-HP tooltip")
	_cast(e, "player", "regen_emergency"); e.battle_state.player.hp = 900; e.battle_state.player.attack = 100; e.update(3)
	_check(e.battle_state.player.hp == 904, "snapshot power changed after application")
	e.dispose()


func _test_codec_and_metrics() -> void:
	var e: RealtimeBattleEngine = _engine(); var unit: UnitState = e.battle_state.player
	unit.hp = 999; unit.add_regeneration(6, 2, "player", "regen_patch"); unit.add_regeneration(6, 3, "player", "regen_tank")
	e.update(3)
	_check(unit.combat_totals["heal"] == 1 and e.analysis.rows["player:regen_patch"]["heal"] == 1, "actual-heal attribution")
	var event: Dictionary = e.battle_state.battle_events[-1]
	_check(event["event_type"] == "status_heal" and event["hp_delta"] == 1, "heal event")
	var payload: Dictionary = BattleStateCodec.encode(e.battle_state, true, true)
	var decoded: BattleState = BattleStateCodec.decode(payload)
	_check(decoded.player.statuses["regen"] == unit.statuses["regen"], "snapshot timer/source layers")
	_check(BattleStateCodec._decode_unit(BattleRecording.frame_at(e.recording.frames, e.battle_state.battle_time)["player"]).statuses["regen"] == unit.statuses["regen"], "replay lost regen")
	e.dispose()


func _test_ui() -> void:
	var unit: UnitState = UnitState.new(); unit.unit_id = "player"; unit.add_regeneration(12, 2, "player", "regen_patch"); unit.add_regeneration(15, 3, "player", "regen_tank")
	var text: String = StatusInfoFormatter.tooltip("regen", 15, 1, unit.statuses["regen"])
	_check(text.contains("5") and text.contains("2/3") and text.contains("3.0"), "regen tooltip")
	var card_button: CardButton = CardButton.new()
	_check(card_button._get_status_detail_text("regen", Database.get_card("regen_patch")).contains("Heals 2") and not StatusInfoFormatter.tooltip("regen", 0).contains("0/3"), "card status supplement/generic context")
	card_button.free()
	var stage: BattleStage3D = BattleStage3D.new(); add_child(stage); stage.configure_combatants("player", "enemy"); await get_tree().process_frame
	stage.refresh_unit_status(unit, unit)
	_check(stage._build_card_profile(Database.get_card("regen_patch")).get("self_status", false), "regen application effect targets the wrong actor")
	_check(stage.get_player_status_model().get_status_regions().any(func(region: Dictionary) -> bool: return region["id"] == "regen"), "3D status icon")
	stage.play_battle_event({"event_type": "status_heal", "target_id": unit.unit_id, "hp_delta": 2, "result": {"amount": 2}})
	_check(stage.get_floating_combat_text_values().has("+2"), "3D heal number")
	stage.queue_free(); await get_tree().process_frame
	var panel: DeveloperPanel = DeveloperPanel.new(); add_child(panel)
	var actions: Array = []
	for i: int in 20: actions.append({"id": "ScrollTest%d" % i, "label": "Test"})
	panel.configure("Test", actions); panel.pin_top_right(); panel.set_collapsed(false, false)
	await get_tree().process_frame; await get_tree().process_frame
	var wheel: InputEventMouseButton = InputEventMouseButton.new(); wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true
	panel._on_action_gui_input(wheel)
	_check(panel._scroll.scroll_vertical > 0 and panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "developer wheel/click-through regression")
	panel.queue_free(); await get_tree().process_frame
