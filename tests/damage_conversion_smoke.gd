extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized(); Game.set_language("en")
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value: push_error("Conversion: " + message); get_tree().quit(1); assert(value, message)


func _engine(enemy_relics: Array[String] = []) -> RealtimeBattleEngine:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.equipped_cards = ["life_conversion", "barrier_conversion", "strike", "guard"]; run.max_hp = 500; run.player_hp = 250
	var foe: RunState = RunState.from_dict(run.to_dict()); foe.relics = enemy_relics
	var e: RealtimeBattleEngine = RealtimeBattleEngine.new(); e.set_audio_enabled(false); e.setup_pvp(run, foe); e.start_battle()
	return e


func _cast(e: RealtimeBattleEngine, side: String, id: String) -> void:
	for runtime: CardRuntimeState in e.battle_state.get_unit(side).card_runtime_states:
		if runtime.card_id != id: continue
		_check(e.request_use_card(side, runtime.runtime_id), "queue " + id)
		var cast: ActiveCardInstance = e.battle_state.get_active_instances_for_side(side)[0]
		e.update(cast.get_remaining(e.battle_state.battle_time) + 0.0001); return
	_check(false, "runtime " + id)


func _run() -> void:
	for id: String in DamageConversionRules.CARD_IDS:
		for grade: int in 6:
			var card: CardDef = CardUpgradeResolver.build_card_at_tier(id, grade)
			_check(is_equal_approx(card.effects[0]["ratio"], .25 + .1 * grade) and card.effects[0]["duration"] == 4 and card.cast_time == 1.2 and card.recast_time == 30, "grade matrix")
			_check(not CardFaceSummaryResolver.build_summaries(card).is_empty() and CardInfoFormatter.build_effect_summary(card).contains("fatigue"), "card info")
			for side: String in ["player", "enemy"]:
				var e: RealtimeBattleEngine = _engine(); e.add_battle_card_modifier(side, id, "grade", grade)
				var unit: UnitState = e.battle_state.get_unit(side); var attacker: UnitState = e.battle_state.get_opponent(side)
				unit.shield = 30; _cast(e, side, id)
				var before: int = unit.shield
				var result: Dictionary = DamageResolver.apply_damage(attacker, unit, 17)
				var amount: int = floori(20 * (.25 + .1 * grade) + .0000001)
				_check(result["hp_damage"] == 0 and result["shield_absorb"] == 0 and result["damage_prevented"] == 20, "damage was not nullified")
				_check(unit.hp == 250 + (amount if id == "life_conversion" else 0) and unit.shield == before + (amount if id == "barrier_conversion" else 0), "conversion amount/shield preservation")
				_check(attacker.combat_totals["damage"] == 0 and attacker.combat_totals["absorbed"] == 0, "attacker credited prevented damage")
				e._flush_conversion_metrics()
				_check(e.analysis.rows[side + ":" + id]["prevented"] == 20 and e.analysis.rows[side + ":" + id]["casts"] == 1, "card statistics/cast count")
				e.dispose()
	_test_fraction_and_lifetime()
	_test_sources()
	_test_codec_and_combo()
	await _test_ui()
	print("DAMAGE_CONVERSION_SMOKE_OK checks=%d cards=2 grades=0..5 both_sides/fractions/window/rearm/bleed/recoil/relic/fatigue/codec/UI" % _checks)
	get_tree().quit()


func _test_fraction_and_lifetime() -> void:
	var e: RealtimeBattleEngine = _engine(); var unit: UnitState = e.battle_state.player
	_check(DamageConversionRules.arm(unit, "heal", 4, .25, 4, "life_conversion"), "arm")
	for i: int in 10: DamageResolver.apply_fixed_damage(unit, 1)
	_check(unit.hp == 252 and is_equal_approx(unit.statuses["damage_conversion"]["fraction"], .5), "fractional hits lost conversion")
	unit.hp = 500; DamageResolver.apply_fixed_damage(unit, 100)
	_check(unit.hp == 500 and unit.combat_totals["heal"] == 2, "overheal credited")
	unit.hp -= 5; _check(unit.hp == 495, "HP payment unexpectedly intercepted")
	e.update(1); DamageConversionRules.arm(unit, "shield", 4, .75, 4, "barrier_conversion")
	_check(is_equal_approx(unit.statuses["damage_conversion"]["duration"], 3) and unit.statuses["damage_conversion"]["fraction"] == 0, "mode switch extended duration or transferred fraction")
	e.update(3)
	_check(not unit.has_status("damage_conversion") and unit.has_status("conversion_lockout") and not DamageConversionRules.arm(unit, "heal", 4, .75, 4, "life_conversion"), "expiry/rearm")
	var before: int = unit.hp; DamageResolver.apply_fixed_damage(unit, 10)
	_check(unit.hp == before - 10, "lockout still blocked damage")
	e.update(4); _check(DamageConversionRules.arm(unit, "heal", 4, .75, 4, "life_conversion"), "rearm never ended")
	e.dispose(); e = _engine(); unit = e.battle_state.player; unit.hp = 0
	_check(not DamageConversionRules.arm(unit, "heal", 4, .75, 4, "life_conversion"), "revived a dead unit")
	e.dispose()
	e = _engine(); unit = e.battle_state.player
	DamageConversionRules.arm(unit, "heal", 4, .5, 4, "life_conversion"); unit.add_status("vulnerable", 12)
	var bonus_hit: Dictionary = DamageResolver.apply_damage(e.battle_state.enemy, unit, 17)
	_check(bonus_hit["damage_prevented"] == 23 and unit.hp == 261, "conversion ignored incoming vulnerability")
	e.dispose()
	e = _engine(); unit = e.battle_state.player
	DamageConversionRules.arm(unit, "heal", 4, .25, 4, "life_conversion")
	unit.add_status("weak", .0000001); unit.statuses["weak"]["suspended"] = 6
	e.update(3)
	_check(unit.has_status("damage_conversion") and is_equal_approx(unit.statuses["weak"]["suspended"], 3), "paused tiny status caused excessive splitting")
	e.dispose()


func _test_sources() -> void:
	for fine: bool in [false, true]:
		var e: RealtimeBattleEngine = _engine(); var unit: UnitState = e.battle_state.player
		DamageConversionRules.arm(unit, "heal", 4, .5, 4, "life_conversion")
		unit.add_status("bleed", 12, 8, "enemy"); unit.statuses["bleed"]["tick_accumulator"] = 4
		if fine:
			for i: int in 120: e.update(.05)
		else: e.update(6)
		_check(unit.hp == 254 and not unit.has_status("damage_conversion") and absf(unit.statuses["conversion_lockout"]["duration"] - 2) < .001, "bleed temporal partition")
		e.dispose()
	var e: RealtimeBattleEngine = _engine(); var unit: UnitState = e.battle_state.player
	DamageConversionRules.arm(unit, "heal", 4, .5, 4, "life_conversion")
	unit.add_status("bleed", 12, 8, "enemy"); unit.statuses["bleed"]["tick_accumulator"] = 2
	e.update(4); _check(unit.hp == 242, "endpoint should be outside the protection window")
	e.dispose(); e = _engine(); unit = e.battle_state.player
	DamageConversionRules.arm(unit, "shield", 4, .5, 4, "barrier_conversion")
	var fatigue: ActiveCardInstance = ActiveCardInstance.new(); fatigue.owner_side = FatigueRules.SIDE; fatigue.card_id = FatigueRules.CARD_ID; fatigue.fatigue_damage = 10
	e.battle_state.active_instances.append(fatigue); e._resolve_fatigue(fatigue)
	_check(unit.has_status("damage_conversion") and unit.hp == 240 and unit.shield == 0 and unit.combat_totals["prevented"] == 0, "fatigue must bypass an active conversion field")
	e.dispose(); e = _engine(); unit = e.battle_state.player
	DamageConversionRules.arm(unit, "heal", 4, .5, 4, "life_conversion")
	ReservedCardRules.grant(unit, Database.get_card("reserve_recoil").effects[0], "enemy")
	_cast(e, "player", "guard")
	_check(unit.hp == 253 and unit.shield == 8, "recoil was not converted before shield")
	e.dispose(); e = _engine(["critical_pathology_meter"]); unit = e.battle_state.player
	DamageConversionRules.arm(unit, "heal", 4, .5, 4, "life_conversion"); unit.add_status("bleed", 1, 6, "enemy")
	e.update(1); _check(unit.hp == 253 and unit.combat_totals["prevented"] == 6, "relic expiry damage bypassed protection")
	e.dispose()


func _test_codec_and_combo() -> void:
	var e: RealtimeBattleEngine = _engine(); var unit: UnitState = e.battle_state.player
	unit.grant_repeat_charges(1); _cast(e, "player", "life_conversion")
	_check(unit.statuses["damage_conversion"]["duration"] == 4 and unit.statuses["damage_conversion"]["ratio"] == .25, "Echo extended the field or multiplied its ratio")
	DamageResolver.apply_fixed_damage(unit, 2)
	var decoded: BattleState = BattleStateCodec.decode(BattleStateCodec.encode(e.battle_state, true, true))
	_check(decoded.player.statuses["damage_conversion"] == unit.statuses["damage_conversion"], "snapshot lost conversion/fraction")
	e.update(.25)
	_check(BattleStateCodec._decode_unit(BattleRecording.frame_at(e.recording.frames, e.battle_state.battle_time)["player"]).statuses.has("damage_conversion"), "visual replay lost field")
	var draft: BalanceDraft = BalanceDraft.new()
	_check(draft.set_value("card", "life_conversion", "grade_overrides.5.effects.0.ratio", .8) and not draft.set_value("card", "life_conversion", "effects.0.lockout_duration", 0), "lab ratios/rearm bounds")
	e.dispose()


func _test_ui() -> void:
	var e: RealtimeBattleEngine = _engine(); _cast(e, "player", "life_conversion")
	_cast(e, "enemy", "strike")
	var event: Dictionary = e.battle_state.battle_events[-1]
	_check(event["result"]["fully_blocked"] and event["result"]["damage_prevented"] == 9, "blocked feedback flag")
	var compact: Dictionary = BattleStateCodec.encode(e.battle_state, true, true)
	_check(compact["battle_events"][-1]["result"]["damage_prevented"] == 9, "compact event dropped prevention")
	var stage: BattleStage3D = BattleStage3D.new(); add_child(stage); stage.configure_combatants("player", "enemy"); await get_tree().process_frame
	stage.play_battle_event(event); stage._apply_pending_resolution_visuals()
	_check(stage.get_floating_combat_text_values().has("+2") and not stage.get_floating_combat_text_values().has("-9"), "fake damage shown for converted hit")
	_check(StatusInfoFormatter.tooltip("damage_conversion", 4, 1, e.battle_state.player.statuses["damage_conversion"]).contains("25%"), "status details")
	stage._clear_floating_combat_texts()
	stage.play_battle_event({"event_type": "status_damage", "target_id": "player", "hp_delta": 3, "result": {"amount": 6, "damage_prevented": 6, "converted_heal": 3}})
	_check(stage.get_floating_combat_text_values().has("+3") and not stage.get_floating_combat_text_values().has("-6"), "converted bleed displayed damage")
	stage.queue_free(); e.dispose(); await get_tree().process_frame
