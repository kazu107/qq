extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.set_language("en")
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("Bleed rework: " + message)
		get_tree().quit(1)
		assert(value, message)


func _events(events: Array, type: String) -> Array:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


func _damage(events: Array) -> int:
	var total: int = 0
	for event: Dictionary in events:
		if event["type"] == "status_damage": total += int(event["amount"])
	return total


func _engine(relics: Array[String] = [], enemy_relics: Array[String] = []) -> RealtimeBattleEngine:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.relics = relics; run.max_hp = 500; run.player_hp = 500
	var foe: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	foe.relics = enemy_relics; foe.max_hp = 500; foe.player_hp = 500
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false)
	engine.setup_pvp(run, foe); engine.start_battle()
	return engine


func _run() -> void:
	_test_layers()
	_test_boundaries()
	_test_cards()
	_test_combat()
	_test_relics()
	_test_codec()
	await _test_ui()
	print("BLEED_REWORK_SMOKE_OK checks=%d grades/layers/snapshot/expiry/cleansing/relics/codec/UI" % _checks)
	get_tree().quit()


func _test_layers() -> void:
	var unit: UnitState = UnitState.new()
	unit.add_status("bleed", 12, 2, "player")
	_check(unit.tick_statuses(2).is_empty(), "first tick occurred early")
	unit.add_status("bleed", 18, 3, "player")
	var events: Array = unit.tick_statuses(4)
	_check(_damage(events) == 5 and _events(events, "status_damage").size() == 1, "layers must share one tick event")
	unit.add_status("bleed", 6, 4, "player")
	unit.add_status("bleed", 24, 9, "player")
	_check(unit.statuses["bleed"]["stacks"] == 3 and unit.statuses["bleed"]["damage"] == 16, "cap must replace the shortest remaining layer")
	events = unit.tick_statuses(6)
	_check(_damage(events) == 16 and _events(events, "status_expired").is_empty(), "an expiring layer lost its boundary tick or ended the whole status")
	_check(unit.statuses["bleed"]["stacks"] == 2 and unit.statuses["bleed"]["damage"] == 12, "independent layer did not expire")
	events = unit.tick_statuses(18)
	_check(_damage(events) == 30 and _events(events, "status_expired").size() == 1 and not unit.has_status("bleed"), "last layer/final tick did not expire exactly once")
	_check(int(_events(events, "status_expired")[0]["last_tick_power"]) == 9, "natural expiry lost final power")
	unit.add_status("slow", 10); unit.tick_statuses(2); unit.add_status("slow", 3)
	_check(unit.statuses["slow"]["duration"] == 8 and not unit.statuses["slow"].has("layers"), "other statuses changed their refresh rules")
	unit.add_status("bleed", 12, 3); unit.add_status("bleed", 18, 5)
	unit.adjust_status_duration("bleed", -6)
	_check(unit.statuses["bleed"]["layers"][0]["duration"] == 6 and unit.statuses["bleed"]["layers"][1]["duration"] == 12, "duration consumption ignored layers")
	unit.remove_status("bleed"); _check(not unit.statuses.has("bleed"), "cleanse did not remove all layers")
	unit.add_status("bleed", 0, 9); _check(not unit.statuses.has("bleed"), "zero duration created a ghost layer")


func _test_boundaries() -> void:
	var a: UnitState = UnitState.new(); var b: UnitState = UnitState.new()
	for unit: UnitState in [a, b]:
		unit.add_status("bleed", 36, 1, "player"); unit.add_status("bleed", 18, 4, "player"); unit.add_status("bleed", 7, 2, "enemy")
	var whole: Array = a.tick_statuses(36)
	var fine: Array = []
	for step: int in 720: fine.append_array(b.tick_statuses(0.05))
	_check(_damage(whole) == 20 and _damage(whole) == _damage(fine), "frame partition changed damage")
	_check(_events(whole, "status_damage").size() == 6 and _events(fine, "status_damage").size() == 6, "lost or duplicated final tick")
	_check(_events(whole, "status_expired").size() == 1 and _events(fine, "status_expired").size() == 1, "expiry depends on frame rate")
	a.statuses["bleed"] = {"duration": 12.0, "tick_accumulator": 2.0, "source_side": "player"}
	_check(_damage(a.tick_statuses(4)) == 1 and a.statuses["bleed"]["stacks"] == 1, "legacy state did not migrate")
	a.remove_status("bleed"); a.add_status("bleed", 12, 5, "player"); a.statuses["bleed"]["suspended"] = 3
	_check(a.tick_statuses(5).is_empty() and a.statuses["bleed"]["duration"] == 10, "suspension overshoot discarded active time")
	_check(_damage(a.tick_statuses(4)) == 5 and _damage(a.tick_statuses(6)) == 5 and not a.has_status("bleed"), "suspension changed final damage")


func _test_cards() -> void:
	for id: String in ["bleed_cut", "rupture_mark", "blood_moon_protocol", "crown_of_thorns"]:
		for grade: int in 6:
			var card: CardDef = CardUpgradeResolver.build_card_at_tier(id, grade)
			var effect: Dictionary = card.effects.filter(func(row: Dictionary) -> bool: return row.get("type") == "apply_status" and row.get("status") == "bleed")[0]
			var powers: Array = [1, 2, 3, 4, 5, 6] if id == "bleed_cut" else [1, 1, 2, 2, 3, 4]
			_check(effect["bleed_power"] == powers[grade], "grade power: " + id)
	_check(BleedRules.resolve_power({"bleed_power": 2}, 12) == 5, "attack scaling example")
	_check(BleedRules.resolve_power({"bleed_power": 2, "_bleed_damage_bonus": 8}, 12) == 7, "card additive damage scaling")
	_check(BleedRules.resolve_power({"bleed_power": 2, "_bleed_damage_bonus": -99}, 0) == 1, "damage floor")
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242); run.card_upgrades["bleed_cut"] = 3; run.attack = 12
	var unit: UnitState = UnitState.new(); unit.attack = 12
	var context: Dictionary = CardTooltipResolver.build_context("bleed_cut", run, unit)
	_check(context["card"].effects[1]["bleed_power"] == 7, "tooltip did not show scaled power")
	var rich: String = "\n".join(CardInfoFormatter.build_effect_lines(context["card"], context["comparison"], true))
	_check(rich.contains("7[color=") and rich.contains("3 layers"), "tooltip power delta or layer cap missing")
	var chips: Array = CardFaceSummaryResolver.build_summaries(context["card"], context["comparison"])
	_check(chips.any(func(chip: Dictionary) -> bool: return chip.get("icon_id") == "status:bleed" and chip.get("value_text") == "7/6s"), "card chip did not show tick power")
	var legacy: CardDef = CardDef.from_dict(Database.get_card("bleed_cut").to_dict()); legacy.effects[1].erase("bleed_power")
	_check(CardFaceSummaryResolver.build_summaries(legacy).any(func(chip: Dictionary) -> bool: return chip.get("value_text") == "1/6s"), "legacy card chip has the wrong default power")
	unit.add_status("weak", 12)
	context = CardTooltipResolver.build_context("bleed_cut", run, unit)
	_check(context["card"].effects[1]["bleed_power"] == 6, "weak did not reduce new applications")
	_check("\n".join(CardInfoFormatter.build_effect_lines(context["card"], context["comparison"], true)).contains("6[color=#ff6868](-1)"), "weakened bleed power lacks its red delta")
	var draft: BalanceDraft = BalanceDraft.new()
	_check(draft.set_value("card", "bleed_cut", "grade_overrides.3.effects.1.bleed_power", 9) and draft.card("bleed_cut", 3).effects[1]["bleed_power"] == 9, "lab cannot edit grade power")
	_check(not draft.set_value("card", "bleed_cut", "effects.1.bleed_power", 0), "lab accepted a zero tick power")
	var config: Dictionary = {"starter": "balanced", "cards": ["bleed_cut"], "hp": 500, "attack": 12, "speed": 5, "grade": 3}
	var was_developer: bool = Game.is_developer_mode_enabled(); Game.settings["developer_mode"] = true
	var sandbox: RealtimeBattleEngine = RealtimeBattleEngine.new(); sandbox.set_audio_enabled(false)
	_check(sandbox.setup_sandbox(BalanceTrialRunner.make_run(config, draft), "scout", draft), "bleed sandbox setup failed")
	sandbox.start_battle(); sandbox.request_use_card("player", sandbox.battle_state.player.card_runtime_states[0].runtime_id); sandbox.update(4.3)
	_check(sandbox.battle_state.enemy.statuses["bleed"]["damage"] == 12 and Database.get_card("bleed_cut").effects[1]["bleed_power"] == 1, "lab power did not reach combat or changed the database")
	sandbox.dispose()
	Game.settings["developer_mode"] = was_developer


func _test_combat() -> void:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.equipped_cards = ["bleed_cut"]; run.card_upgrades["bleed_cut"] = 3; run.attack = 12; run.temporary_card_modifiers["bleed_cut"] = {"damage": 8}
	var foe: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242); foe.max_hp = 500; foe.player_hp = 500
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false); engine.setup_pvp(run, foe); engine.start_battle()
	engine.battle_state.player.charge_next_attack(4)
	var runtime: CardRuntimeState = engine.battle_state.player.card_runtime_states[0]
	_check(engine.request_use_card("player", runtime.runtime_id), "bleed card could not be queued")
	engine.update(4.3)
	var enemy: UnitState = engine.battle_state.enemy
	_check(enemy.statuses["bleed"]["damage"] == 9 and engine.battle_state.player.next_attack_multiplier == 1, "snapshot power used attack charge or ignored modifiers")
	engine.battle_state.player.attack = 0; engine.add_card_modifier("player", "bleed_cut", "damage", 100)
	enemy.shield = 80
	var hp: int = enemy.hp
	engine.update(6)
	_check(enemy.hp == hp - 9 and enemy.shield == 74 and enemy.statuses["bleed"]["damage"] == 9, "existing bleed changed power or consumed shield beyond normal decay")
	engine.dispose()
	engine = _engine(); engine.battle_state.enemy.hp = 5
	engine.apply_status_from_card("player", "enemy", "bleed", 6, 10); engine.apply_status_from_card("enemy", "enemy", "bleed", 6, 5)
	engine.update(6)
	_check(engine.battle_state.enemy.combat_totals["damage_taken"] == 5 and engine.battle_state.player.combat_totals["damage"] == 3, "overkill source attribution was not proportional")
	engine.dispose()


func _test_relics() -> void:
	_check(String(BalanceDraft.LABELS["bleed_final_ticks"]).contains("回数"), "lab must distinguish extra tick count from fixed damage")
	var engine: RealtimeBattleEngine = _engine([], ["quarantine_buffer"])
	engine.apply_status_from_card("player", "enemy", "bleed", 12, 5); engine.apply_status_from_card("player", "enemy", "bleed", 18, 3)
	engine.update(6)
	_check(engine.battle_state.enemy.hp == 500 and engine.battle_state.enemy.statuses["bleed"]["stacks"] == 2, "quarantine lost layers or damaged during pause")
	engine.update(6); _check(engine.battle_state.enemy.hp == 492, "quarantine did not resume combined tick")
	engine.dispose(); engine = _engine(["symptom_transfer_paper"])
	engine.apply_status_from_card("enemy", "player", "bleed", 30, 5); engine.apply_status_from_card("enemy", "player", "bleed", 18, 4)
	engine.remove_status_from_card("player", "player", "bleed")
	_check(not engine.battle_state.player.has_status("bleed") and engine.battle_state.enemy.statuses["bleed"]["damage"] == 9, "transfer lost layer power")
	_check(engine.battle_state.enemy.statuses["bleed"]["duration"] == 12 and engine.battle_state.relic_runtime_state["player"]["symptom_transfers"] == 1, "transfer ratio or event count changed")
	engine.dispose(); engine = _engine(["four_symptom_seal"])
	engine.apply_status_from_card("player", "enemy", "bleed", 18, 2); engine.apply_status_from_card("player", "enemy", "bleed", 24, 3)
	for id: String in ["weak", "slow", "vulnerable"]: engine.apply_status_from_card("player", "enemy", id, 12)
	var layers: Array = engine.battle_state.enemy.statuses["bleed"]["layers"]
	_check(layers[0]["duration"] == 12 and layers[1]["duration"] == 18, "symptom consumption changed only the aggregate timer")
	engine.dispose(); engine = _engine(["bleed_pulsator"])
	engine.battle_state.player.card_runtime_states[0].begin_cooldown(20)
	for index: int in 3: engine.apply_status_from_card("enemy", "player", "bleed", 6, 5)
	engine.update(6)
	_check(engine.battle_state.player.hp == 485 and engine.battle_state.relic_runtime_state["player"]["bleeding_pulses"] == 1, "pulsator fired once per layer")
	_check(is_equal_approx(engine.battle_state.player.card_runtime_states[0].cooldown_remaining, 13.2), "pulsator accelerated more than once per tick")
	engine.dispose(); engine = _engine(["critical_pathology_meter"])
	engine.apply_status_from_card("player", "enemy", "bleed", 6, 2); engine.apply_status_from_card("player", "enemy", "bleed", 12, 5)
	engine.update(6)
	_check(engine.battle_state.enemy.hp == 493 and not engine.battle_state.relic_runtime_state["player"].has("cd_critical_pathology_meter"), "partial expiry triggered pathology")
	engine.update(6); _check(engine.battle_state.enemy.hp == 483, "natural expiry did not use the final power once")
	engine.dispose()


func _test_codec() -> void:
	var engine: RealtimeBattleEngine = _engine()
	engine.apply_status_from_card("player", "enemy", "bleed", 18, 2); engine.apply_status_from_card("player", "enemy", "bleed", 24, 5)
	engine.update(2.5)
	var replay: ReplayData = ReplayData.from_dict(JSON.parse_string(JSON.stringify(ReplayData.from_summary(engine.build_summary()).to_dict())))
	var frame: Dictionary = BattleRecording.frame_at(replay.summary["visual_replay"]["frames"], 2.5)
	var replay_unit: UnitState = BattleStateCodec._decode_unit(frame["enemy"])
	_check(replay_unit.statuses == engine.battle_state.enemy.statuses, "visual replay lost layer data")
	for compact: bool in [false, true]:
		var decoded: BattleState = BattleStateCodec.decode(JSON.parse_string(JSON.stringify(BattleStateCodec.encode(engine.battle_state, true, compact))))
		_check(decoded.enemy.statuses == engine.battle_state.enemy.statuses, "snapshot lost independent timers/power/phase")
		var expected: UnitState = UnitState.new(); expected.statuses = engine.battle_state.enemy.statuses.duplicate(true)
		_check(decoded.enemy.tick_statuses(15.5) == expected.tick_statuses(15.5), "decoded status changed future ticks")
	engine.dispose()


func _test_ui() -> void:
	var unit: UnitState = UnitState.new(); unit.hp = 60; unit.max_hp = 60
	unit.add_status("bleed", 18, 2); unit.add_status("bleed", 12, 4); unit.add_status("bleed", 6, 7)
	var panel: UnitPanel = UnitPanel.new(); add_child(panel); panel.refresh_unit(unit)
	var plate: BattleUnitStatus3D = BattleUnitStatus3D.new(); plate.configure(true); add_child(plate); plate.refresh_unit(unit)
	await get_tree().process_frame
	var icon: TextureRect = panel.find_child("StatusIcon_bleed", true, false) as TextureRect
	_check((icon.find_child("StatusStacks", true, false) as Label).text == "x3", "2D stack badge missing")
	_check((plate.find_child("StatusStacks3D_bleed", true, false) as Label3D).text == "x3", "3D stack badge missing")
	plate.rotation.y = 0.2
	_check(is_equal_approx((plate.find_child("StatusStacks3D_bleed", true, false) as Label3D).global_rotation.y, 0.2), "stack label does not follow plate yaw")
	var tooltip: String = plate.get_status_regions()[0]["tooltip"]
	_check(tooltip.contains("13 damage") and tooltip.contains("Layer 3") and tooltip.contains("6.0s"), "live tooltip missing power/layers/next tick")
	unit.tick_statuses(6); panel.refresh_unit(unit); plate.refresh_unit(unit)
	_check((icon.find_child("StatusStacks", true, false) as Label).text == "x2" and plate.get_status_regions()[0]["tooltip"].contains("6 damage"), "layer expiry did not update badges/tooltips")
	panel.queue_free(); plate.queue_free(); await get_tree().process_frame
	Game.settings["developer_mode"] = true; Game.start_new_run("balanced", 4242); Game.developer_open_battle("scout")
	var battle: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control; add_child(battle)
	await get_tree().process_frame
	var apply: Button = battle.find_child("DevBleedEnemy", true, false) as Button
	_check(apply != null and not apply.disabled, "developer bleed preset missing")
	apply.pressed.emit()
	var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
	_check(engine.battle_state.enemy.statuses["bleed"]["stacks"] == 3 and engine.battle_state.enemy.statuses["bleed"]["damage"] == 12, "developer preset did not apply test layers")
	(battle.find_child("DevBleedClear", true, false) as Button).pressed.emit()
	_check(not engine.battle_state.enemy.has_status("bleed"), "developer cleanse failed")
	battle.set("_lan_mode", true); battle.call("_on_dev_bleed", false)
	_check(not engine.battle_state.enemy.has_status("bleed"), "developer preset was allowed online")
	battle.set("_lan_mode", false); battle.queue_free(); await get_tree().process_frame
