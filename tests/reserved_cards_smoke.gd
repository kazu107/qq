extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized(); Game.set_language("en")
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value: push_error("Reserved cards: " + message); get_tree().quit(1); assert(value, message)


func _engine(cards: Array[String] = ["strike", "guard", "heavy_swing", "bleed_cut", "repair_burst"]) -> RealtimeBattleEngine:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.equipped_cards = cards; run.max_hp = 1000; run.player_hp = 1000
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false); engine.setup_pvp(run, run); engine.start_battle()
	return engine


func _runtime(e: RealtimeBattleEngine, side: String, id: String) -> CardRuntimeState:
	for runtime: CardRuntimeState in e.battle_state.get_unit(side).card_runtime_states:
		if runtime.card_id == id: return runtime
	return null


func _queue(e: RealtimeBattleEngine, side: String, id: String) -> void:
	_check(e.request_use_card(side, _runtime(e, side, id).runtime_id), "queue " + id)


func _resolve(e: RealtimeBattleEngine, side: String, id: String) -> void:
	for instance: ActiveCardInstance in e.battle_state.active_instances:
		if instance.owner_side == side and instance.card_id == id:
			e.update(maxf(0.0001, instance.scheduled_time - e.battle_state.battle_time) + 0.0001); return
	_check(false, "missing cast " + id)


func _grant(e: RealtimeBattleEngine, side: String, kind: String) -> void:
	_check(ReservedCardRules.grant(e.battle_state.get_unit(side), Database.get_card("reserve_" + kind).effects[0], side), "grant " + kind)


func _run() -> void:
	for kind: String in ReservedCardRules.NAMES:
		var id: String = "reserve_" + kind
		for grade: int in 6:
			var card: CardDef = CardUpgradeResolver.build_card_at_tier(id, grade)
			_check(card != null and card.effects[0]["type"] == "reserve_next_card" and card.effects[0]["amount"] > 0, "grade content " + id)
			_check(not CardInfoFormatter.build_effect_summary(card).contains("unknown") and not CardFaceSummaryResolver.build_summaries(card).is_empty(), "formatters " + id)
			var e: RealtimeBattleEngine = _engine([id, "strike"])
			e.add_battle_card_modifier("player", id, "grade", grade)
			_queue(e, "player", id); _resolve(e, "player", id)
			var target: UnitState = e.battle_state.enemy if card.target_type == "enemy" else e.battle_state.player
			_check(target.card_reservations.size() == 1 and is_equal_approx(target.card_reservations[0]["amount"], card.effects[0]["amount"]), "actual grant " + id)
			e.dispose()
	for side: String in ["player", "enemy"]: _test_effects(side)
	_test_limits_and_interrupt()
	_test_echo_and_commit()
	_test_codec()
	_test_edges()
	await _test_ui()
	print("RESERVED_CARDS_SMOKE_OK checks=%d cards=18 grades=0..5 sides/effects/commit/echo/limits/interruption/codec/UI" % _checks)
	get_tree().quit()


func _test_effects(side: String) -> void:
	var other: String = "enemy" if side == "player" else "player"
	for kind: String in ReservedCardRules.NAMES:
		if ReservedCardRules.COMMIT_KINDS.has(kind): continue
		var e: RealtimeBattleEngine = _engine()
		var unit: UnitState = e.battle_state.get_unit(side)
		var foe: UnitState = e.battle_state.get_unit(other)
		_grant(e, side, kind)
		var id: String = "strike"
		if kind in ["shield", "shield_jam", "mirror", "recoil", "tempo", "time_mine"]: id = "guard"
		if kind == "status": id = "bleed_cut"
		if kind == "heal_jam": id = "repair_burst"
		if kind == "siphon": unit.hp = 900
		if kind == "heal_jam": unit.hp = 900; foe.hp = 900
		var before_schedule: float = 0
		if kind in ["tempo", "time_mine"]:
			_queue(e, other if kind == "tempo" else side, "heavy_swing")
			before_schedule = e.battle_state.active_instances[0].scheduled_time
		_queue(e, side, id); _resolve(e, side, id)
		_check(unit.card_reservations.is_empty(), "stock not consumed " + kind)
		match kind:
			"focus": _check(foe.hp == 983, "focus amount")
			"shield": _check(unit.shield == 12, "shield scale")
			"siphon": _check(unit.hp == 904, "actual HP lifesteal")
			"reload": _check(_runtime(e, side, id).cooldown_remaining == 6, "recast half")
			"status": _check(foe.statuses["bleed"]["damage"] == 3 and foe.statuses["bleed"]["duration"] == 42, "status duration/power")
			"chain": _check(e.battle_state.active_instances.size() == 1 and e.battle_state.active_instances[0].is_auto_queued and e.battle_state.active_instances[0].card_id == "guard", "guard chain")
			"growth": _check(e._get_card_def(side, id).effects[0]["amount"] == 8 and foe.hp == 991, "growth must apply after the current hit")
			"tempo", "time_mine": _check(is_equal_approx(e.battle_state.active_instances[0].scheduled_time, before_schedule + (1.5 if kind == "tempo" else 2)), "post-card delay " + kind)
			"weaken": _check(foe.hp == 995, "attack scale includes attack")
			"shield_jam": _check(unit.shield == 4, "shield jam")
			"heal_jam": _check(unit.hp == 900 + roundi(float(Database.get_card(id).effects[0]["amount"]) * .5) and foe.hp == 904, "heal corruption")
			"recast_jam": _check(_runtime(e, side, id).cooldown_remaining == 18, "recast jammer")
			"recoil": _check(unit.hp == 1000 and unit.shield == 2, "recoil must use shield")
			"wear": _check(_runtime(e, side, id).cooldown_remaining == 13 and e._get_card_def(side, id).recast_time == 13, "wear current/future cooldown")
			"mirror": _check(unit.shield == 8 and foe.shield == 4, "mirror actual gain")
		e.dispose()


func _test_limits_and_interrupt() -> void:
	var e: RealtimeBattleEngine = _engine()
	for i: int in 3: _grant(e, "player", "focus")
	_check(not ReservedCardRules.grant(e.battle_state.player, Database.get_card("reserve_focus").effects[0], "player"), "same-kind cap")
	_queue(e, "player", "guard"); _resolve(e, "player", "guard")
	_check(e.battle_state.player.card_reservations.size() == 3, "nonmatching card consumed stock")
	_queue(e, "player", "strike"); _resolve(e, "player", "strike")
	_check(e.battle_state.enemy.hp == 983 and e.battle_state.player.card_reservations.size() == 2, "stacking must be targets, not multiplied amounts")
	_queue(e, "player", "heavy_swing")
	_check(e.interrupt_active_card("player", "single_interruptible") == 1 and e.battle_state.player.card_reservations.size() == 2, "interruption consumed stock")
	var setup: CardDef = Database.get_card("reserve_focus")
	_check(ReservedCardRules.select(e.battle_state.player.card_reservations, setup).is_empty(), "setup card consumed stock")
	for kind: String in ["shield", "siphon", "reload", "status", "chain", "growth"]: _grant(e, "player", kind)
	_check(e.battle_state.player.card_reservations.size() == 8 and not ReservedCardRules.grant(e.battle_state.player, Database.get_card("reserve_wear").effects[0], "enemy"), "total cap")
	e.dispose()


func _test_echo_and_commit() -> void:
	var e: RealtimeBattleEngine = _engine()
	_grant(e, "player", "focus"); e.battle_state.player.grant_repeat_charges(1); e.battle_state.player.charge_next_attack(2)
	_queue(e, "player", "strike"); _resolve(e, "player", "strike")
	_check(e.battle_state.enemy.hp == 932 and e.battle_state.player.card_reservations.is_empty(), "Echo/attack-charge/focus combination")
	var preview: CardDef = CardTooltipResolver.build_context("strike", null, e.battle_state.player)["card"]
	preview.effects[0]["amount"] = 18
	var entries: Array[Dictionary] = [{"reservation": "focus", "amount": 8}]
	_check(ReservedCardRules.preview_card(preview, entries, 2).effects[0]["amount"] == 34, "boost preview applied outside the attack multiplier")
	e.dispose(); e = _engine()
	_grant(e, "player", "swift_commit")
	_queue(e, "player", "strike")
	_check(is_equal_approx(e.battle_state.active_instances[0].scheduled_time, 1.8) and e.battle_state.player.card_reservations.is_empty(), "next-registration cast")
	e.dispose(); e = _engine()
	_grant(e, "player", "heavy_commit"); _queue(e, "player", "heavy_swing")
	_check(e.battle_state.player.active_slots_used == 3, "next-registration slot cost")
	e.interrupt_active_card("player", "single_interruptible")
	_check(e.battle_state.player.active_slots_used == 0 and e.battle_state.player.card_reservations.is_empty(), "slot cleanup/commit stock")
	e.dispose(); e = _engine()
	_queue(e, "player", "heavy_swing"); _grant(e, "player", "heavy_commit")
	_check(not e.request_use_card("player", _runtime(e, "player", "guard").runtime_id) and e.battle_state.player.card_reservations.size() == 1, "failed registration consumed stock")
	e.dispose()
	e = _engine(["meteor_crash"]); _grant(e, "player", "heavy_commit"); _queue(e, "player", "meteor_crash")
	_check(e.battle_state.player.active_slots_used == 3, "slot jammer hard-locked a maximum-slot card")
	e.dispose()
	var combo: Array[Dictionary] = [{"reservation": "reload", "amount": .5}, {"reservation": "recast_jam", "amount": 6}]
	_check(ReservedCardRules.recast_duration(12, combo) == 12, "recast combination")
	combo.reverse(); _check(ReservedCardRules.recast_duration(12, combo) == 12, "recast order changed result")


func _test_codec() -> void:
	var e: RealtimeBattleEngine = _engine()
	_grant(e, "player", "focus"); _grant(e, "enemy", "time_mine")
	var encoded: Dictionary = BattleStateCodec.encode(e.battle_state, true, true)
	var decoded: BattleState = BattleStateCodec.decode(encoded)
	_check(decoded.player.card_reservations == e.battle_state.player.card_reservations and decoded.enemy.card_reservations == e.battle_state.enemy.card_reservations, "network pending stock")
	encoded["player"].erase("card_reservations")
	_check(BattleStateCodec.decode(encoded).player.card_reservations.is_empty(), "legacy snapshot")
	_check(JSON.stringify(BattleStateCodec.encode(e.battle_state, true, true)).length() < 32768, "bounded pending snapshot")
	_check(EnemyAI.new()._score_reservation(e, Database.get_card("reserve_heal_jam").effects[0], e.battle_state.player) > 0, "AI ignored a valid conditional reservation")
	var empty: UnitState = UnitState.new()
	_check(EnemyAI.new()._score_reservation(e, Database.get_card("reserve_heal_jam").effects[0], empty) < 0, "AI targeted an impossible heal condition")
	e.dispose()


func _test_ui() -> void:
	var unit: UnitState = UnitState.new()
	ReservedCardRules.grant(unit, Database.get_card("reserve_focus").effects[0], "player")
	ReservedCardRules.grant(unit, Database.get_card("reserve_time_mine").effects[0], "enemy")
	var statuses: Dictionary = unit.get_display_statuses()
	_check(statuses.has("reservation_boost") and statuses.has("reservation_hex"), "separate boost/hex displays")
	_check(not StatusInfoFormatter.tooltip("reservation_boost", 0, 1, statuses["reservation_boost"]).contains("0.0s"), "fake duration")
	var button: CardButton = CardButton.new(); add_child(button)
	button.set_reservations(unit.card_reservations)
	_check(button.get_node("ReservationBadge").visible, "timeline reservation badge")
	button.set_reservations([])
	_check(not button.get_node("ReservationBadge").visible, "pooled badge reset")
	button.queue_free(); await get_tree().process_frame


func _test_edges() -> void:
	var e: RealtimeBattleEngine = _engine()
	_grant(e, "player", "siphon"); e.battle_state.player.hp = 900; e.battle_state.enemy.shield = 100
	_queue(e, "player", "strike"); _resolve(e, "player", "strike")
	_check(e.battle_state.player.hp == 900, "lifesteal included absorbed damage")
	e.dispose(); e = _engine()
	_grant(e, "player", "focus")
	var source: ActiveCardInstance = ActiveCardInstance.new(); source.owner_side = "player"; source.card_id = "strike"; source.runtime_id = _runtime(e, "player", "strike").runtime_id
	_check(e.auto_queue_card("player", source, {"card_id": "strike", "delay": 0.1, "max_depth": 1}) == 1, "auto fixture")
	e.update(4)
	_check(e.battle_state.player.card_reservations.size() == 1 and e.battle_state.enemy.hp == 991, "auto card consumed reservation")
	e.debug_schedule_fatigue(); e.update(2)
	_check(e.battle_state.player.card_reservations.size() == 1, "fatigue consumed reservation")
	e.dispose(); e = _engine()
	_grant(e, "player", "chain"); e.battle_state.player.grant_repeat_charges(1)
	_queue(e, "player", "strike"); _resolve(e, "player", "strike")
	_check(e.battle_state.active_instances.size() == 1 and e.battle_state.active_instances[0].card_id == "guard", "Echo duplicated the post-trigger")
	e.dispose(); e = _engine()
	_grant(e, "player", "wear"); _queue(e, "player", "strike"); _resolve(e, "player", "strike")
	_check(e.get_run_for_side("player").temporary_card_modifiers.is_empty(), "battle-only wear leaked into run save")
	e.dispose()
	var draft: BalanceDraft = BalanceDraft.new()
	_check(draft.set_value("card", "reserve_time_mine", "effects.0.amount", 2.3), "lab treated seconds as integers")
	_check(not draft.set_value("card", "reserve_reload", "effects.0.amount", 0) and not draft.set_value("card", "reserve_chain", "effects.0.amount", 2), "lab accepted unsupported reservation values")
