extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.settings["developer_mode"] = true
	Game.set_language("ja")
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("Grade five: " + message)
		get_tree().quit(1)
		assert(value, message)


func _run() -> void:
	var ids: Array[String] = Database.get_all_card_ids()
	for id: String in Database.boss_cards: ids.append(id)
	_check(ids.size() == 96, "card catalog incomplete")
	for id: String in ids:
		var base: CardDef = Database.get_card(id)
		_check(not base.upgrade_profile.is_empty(), "missing grade values: " + id)
		for numbers: Array in base.upgrade_profile.values(): _check(numbers.size() == 6, "grade table must have six entries: " + id)
		for tier: int in range(6):
			var card: CardDef = CardUpgradeResolver.build_card_at_tier(id, tier)
			_check(card != null and card.cast_time >= 0 and card.recast_time >= 0, "invalid grade timing: " + id)
			_check(card.name == base.name if tier == 0 else card.name.ends_with("+%d" % tier), "grade label mismatch: " + id)
	_check(CardUpgradeResolver.build_card_at_tier("quick_slash", 5).effects[0]["amount"] == 9, "quick slash grade 5 value")
	_check(CardUpgradeResolver.build_card_at_tier("guard", 5).effects[0]["amount"] == 28, "guard grade 5 value")
	_check(is_equal_approx(CardUpgradeResolver.build_card_at_tier("timekeeper_amplify", 5).recast_time, 6.4), "boss grade 5 value")
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.card_upgrades["quick_slash"] = 3
	var forge: ForgeService = ForgeService.new()
	_check(forge.upgrade_card(run, "quick_slash") == 3 and not forge.get_upgradable_cards(run).has("quick_slash"), "forge crossed its grade 3 cap")
	var state: String = JSON.stringify(run.to_dict())
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.setup(run, "scout")
	_check(engine.empower_cards("player", "quick_slash", {"stat": "grade", "amount": 2, "scope": "self"}) == 1, "battle grade increase did not apply")
	_check(engine._get_card_def("player", "quick_slash").name.ends_with("+5") and engine._get_card_def("player", "quick_slash").effects[0]["amount"] == 9, "battle grade 5 card is not effective")
	var tooltip: Dictionary = CardTooltipResolver.build_context("quick_slash", run, engine.battle_state.player)
	_check((tooltip["card"] as CardDef).effects[0]["amount"] == 9 + engine.battle_state.player.get_attack_value(), "tooltip ignored runtime grade")
	_check(engine.empower_cards("player", "quick_slash", {"stat": "grade", "amount": 100, "scope": "self"}) == 0, "grade cap counted a false upgrade")
	engine.add_battle_card_modifier("player", "quick_slash", "grade", -1)
	_check(engine._get_card_def("player", "quick_slash").name.ends_with("+4"), "capped stacks hid grade reductions")
	engine.add_battle_card_modifier("enemy", "quick_slash", "grade", 5)
	tooltip = CardTooltipResolver.build_context("quick_slash", null, engine.battle_state.enemy)
	_check((tooltip["card"] as CardDef).name.ends_with("+5"), "enemy tooltip ignored battle-only grades")
	_check(JSON.stringify(run.to_dict()) == state, "battle grades leaked into the run save")
	engine.dispose(); engine = RealtimeBattleEngine.new(); engine.setup(run, "scout")
	_check(engine._get_card_def("player", "quick_slash").name.ends_with("+3"), "runtime grade survived a new battle")
	engine.dispose()
	var draft: BalanceDraft = BalanceDraft.new()
	draft.set_value("card", "quick_slash", "effects.0.amount", 10)
	_check(draft.card("quick_slash", 4).effects[0]["amount"] == 14, "common base values did not feed high grades")
	_check(draft.set_value("card", "quick_slash", "grade_overrides.4.effects.0.amount", 20), "grade-specific field missing")
	_check(draft.card("quick_slash", 4).effects[0]["amount"] == 20 and draft.card("quick_slash", 5).effects[0]["amount"] == 15, "grade edit changed another grade")
	_check(draft.set_value("card", "quick_slash", "grade_overrides.4.effects.0.amount", 8) and draft.card("quick_slash", 4).effects[0]["amount"] == 8, "explicit baseline value failed to override a changed base")
	draft.reset_grade("quick_slash", 4)
	_check(draft.card("quick_slash", 4).effects[0]["amount"] == 14 and draft.card("quick_slash", 0).effects[0]["amount"] == 10, "grade reset erased the common base")
	var restored: BalanceDraft = BalanceDraft.new()
	_check(restored.import_document(JSON.parse_string(JSON.stringify(draft.document()))), "grade diff roundtrip failed")
	var legacy: Dictionary = {"format": "queuequest-balance-diff-v1", "source_hash": "legacy-source", "changes": [{"kind": "card", "id": "quick_slash", "path": "effects.0.amount", "before": 4, "after": 8}]}
	var legacy_file: FileAccess = FileAccess.open(BalanceDraft.DRAFT_PATH, FileAccess.WRITE); legacy_file.store_string(JSON.stringify(legacy)); legacy_file.close()
	var migrated: BalanceDraft = BalanceDraft.new()
	_check(migrated.load_draft() and migrated.card("quick_slash").effects[0]["amount"] == 8, "legacy draft was not safely migrated")
	Game.start_new_run("balanced", 4242)
	var screen: Control = load("res://scenes/debug/BalanceLab.tscn").instantiate() as Control; add_child(screen)
	for frame: int in 180:
		if screen.call("is_content_ready"): break
		await get_tree().process_frame
	var tabs: TabBar = screen.find_child("BalanceGradeTabs", true, false) as TabBar
	_check(tabs != null and tabs.tab_count == 6, "six grade tabs missing")
	tabs.current_tab = 5
	var spin: SpinBox = screen.find_child("BalanceValue_grade_overrides_5_effects_0_amount", true, false) as SpinBox
	_check(spin != null, "grade 5 editor missing")
	spin.get_line_edit().text = "33"
	spin.get_line_edit().text_changed.emit("33")
	_check((screen.get("draft") as BalanceDraft).card("quick_slash", 5).effects[0]["amount"] == 33, "grade tab editor did not apply its value")
	var limit: SpinBox = screen.find_child("BalanceTimeLimit", true, false) as SpinBox
	var previous_limit: float = limit.value
	limit.get_line_edit().text = "1"; limit.get_line_edit().text_changed.emit("1")
	_check(limit.value == previous_limit and limit.get_line_edit().text == "1", "partial text was clamped while typing")
	limit.get_line_edit().text = "10"; limit.get_line_edit().text_changed.emit("10")
	_check(limit.value == 10 and limit.get_line_edit().text == "10", "minimum value did not apply live")
	_check(screen.find_child("BalancePreviewGrade5", true, false) != null, "grade 5 preview missing")
	_check((screen.find_child("BalanceGrade", true, false) as SpinBox).value == 5, "simulation grade did not follow the tab")
	screen.queue_free(); await get_tree().process_frame
	print("GRADE_FIVE_SMOKE_OK checks=%d" % _checks)
	get_tree().quit()
