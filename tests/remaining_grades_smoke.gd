extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized(); call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value: push_error("Remaining grades: " + message); get_tree().quit(1); assert(value, message)


func _run() -> void:
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/remaining_grades_0_56_0.json"))
	_check(audit["cards"].size() == 70 and audit["protected_cards"].size() == 52, "scope")
	_check(CardUpgradeResolver.MAX_TIER == 5 and CardUpgradeResolver.MAX_RUN_TIER == 3, "grade/forge limits")
	var draft: BalanceDraft = BalanceDraft.new()
	for grade: int in 6:
		var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
		run.equipped_cards.clear()
		for entry: Dictionary in audit["cards"]:
			run.equipped_cards.append(entry["id"]); run.card_upgrades[entry["id"]] = grade
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false); engine.setup_pvp(run, run)
		for entry: Dictionary in audit["cards"]:
			var id: String = entry["id"]
			var expected_source: CardDef = CardDef.from_dict(entry["before"])
			expected_source.upgrade_profile = {}; expected_source.grade_overrides = entry["grades"]
			var expected: CardDef = CardUpgradeResolver.build_card_at_tier(id, grade, expected_source)
			var actual: CardDef = draft.card(id, grade)
			_check(actual.effects == expected.effects and actual.cast_time == expected.cast_time and actual.recast_time == expected.recast_time, "lab values " + id + "/" + str(grade))
			if grade > 0:
				var previous: CardDef = draft.card(id, grade - 1)
				_check(actual.cast_time > 0 and actual.cast_time <= previous.cast_time and actual.recast_time >= 4 and actual.recast_time <= previous.recast_time, "monotonic timings " + id)
			for side: String in ["player", "enemy"]:
				var resolved: CardDef = engine._get_card_def(side, id)
				_check(resolved.effects == actual.effects and resolved.cast_time == actual.cast_time and resolved.recast_time == actual.recast_time, "combat values " + id)
		engine.dispose()
		for entry: Dictionary in audit["cards"]:
			for side: String in ["player", "enemy"]: _test_resolution(entry["id"], grade, side)
	print("REMAINING_GRADES_SMOKE_OK checks=%d cards=70 grades=0..5 lab/both_sides/resolution/cooldowns forge-cap=3" % _checks)
	get_tree().quit()


func _test_resolution(id: String, grade: int, side: String) -> void:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.equipped_cards = [id]; run.card_upgrades[id] = grade; run.max_hp = 10000; run.player_hp = 5000
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false); engine.setup_pvp(run, run); engine.start_battle()
	var unit: UnitState = engine.battle_state.get_unit(side); unit.shield = 200
	var runtime: CardRuntimeState = unit.get_sorted_runtime_states()[0]
	var card: CardDef = engine._get_card_def(side, id)
	_check(engine.request_use_card(side, runtime.runtime_id), "queue " + id)
	var instance: ActiveCardInstance = engine.battle_state.get_active_instances_for_side(side)[0]
	engine.update(instance.get_remaining(engine.battle_state.battle_time) + .0001)
	_check(is_equal_approx(runtime.cooldown_remaining, maxf(4, card.recast_time)), "resolved cooldown " + id + "/" + str(grade))
	_check(not engine.battle_state.battle_events.is_empty(), "resolution event " + id)
	engine.dispose()
