extends Node

const FIXTURE := "res://tests/fixtures/balance_0_55_1.json"
var _checks: int = 0


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized(); call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value: push_error("Balance publication: " + message); get_tree().quit(1); assert(value, message)


func _run() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var draft: BalanceDraft = BalanceDraft.new()
	if OS.get_cmdline_user_args().has("--validate-import"):
		_check(draft.import_document(document), "source hash/original fields differ")
		_check(draft.changes().size() == 94, "import scope differs")
		print("BALANCE_PUBLICATION_IMPORT_OK fields=94 source=" + document["source_hash"])
		get_tree().quit(); return
	var ids: Array[String] = []
	for change: Dictionary in document["changes"]:
		_check(change["kind"] == "card", "unexpected kind")
		var id: String = change["id"]; var path: String = change["path"]
		if not ids.has(id): ids.append(id)
		_check(is_equal_approx(draft.value("card", id, path), float(change["after"])), "lab differs: %s / %s" % [id, path])
		var parts: PackedStringArray = path.split(".")
		var tier: int = int(parts[1]) if path.begins_with("grade_overrides.") else 0
		var resolved: String = ".".join(parts.slice(2)) if tier > 0 else path
		_check(is_equal_approx(float(BalanceDraft.read(CardUpgradeResolver.build_card_at_tier(id, tier).to_dict(), resolved)), change["after"]), "resolved value differs: %s / %s" % [id, path])
	_check(ids.size() == 10 and document["changes"].size() == 94, "publication scope")
	_check(not draft.import_document(document), "old-source publication was accepted again")
	for grade: int in 6:
		var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
		run.equipped_cards = ids.duplicate()
		for id: String in ids: run.card_upgrades[id] = grade
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false); engine.setup_pvp(run, run)
		for id: String in ids:
			var expected: CardDef = draft.card(id, grade)
			for side: String in ["player", "enemy"]:
				var actual: CardDef = engine._get_card_def(side, id)
				_check(actual.effects == expected.effects and actual.cast_time == expected.cast_time and actual.recast_time == expected.recast_time, "combat grade differs: %s / %s / %d" % [id, side, grade])
		engine.dispose()
		for side: String in ["player", "enemy"]: _test_resolution(grade, side)
	print("BALANCE_PUBLICATION_SMOKE_OK checks=%d fields=94 cards=10 grades=0..5 lab/both_sides/effects/conditional_bonuses/cooldowns" % _checks)
	get_tree().quit()


func _test_resolution(grade: int, side: String) -> void:
	for id: String in ["bastion_drive", "fortify", "repair_burst", "over_reload", "execution", "blood_chain", "rupture_strike", "tripwire"]:
		var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
		run.equipped_cards = [id, "heavy_swing"]; run.card_upgrades[id] = grade; run.max_hp = 1000; run.player_hp = 500
		var e: RealtimeBattleEngine = RealtimeBattleEngine.new(); e.set_audio_enabled(false); e.setup_pvp(run, run); e.start_battle()
		var unit: UnitState = e.battle_state.get_unit(side); var target: UnitState = e.battle_state.get_opponent(side)
		var card: CardDef = e._get_card_def(side, id)
		var runtime: CardRuntimeState = null; var cooling: CardRuntimeState = null
		for candidate: CardRuntimeState in unit.card_runtime_states:
			if candidate.card_id == id: runtime = candidate
			else: cooling = candidate
		if id == "over_reload": cooling.begin_cooldown(100)
		if id in ["blood_chain", "rupture_strike"]: target.add_status("bleed", 30, 1, side)
		if id == "execution": target.hp = 300
		_check(e.request_use_card(side, runtime.runtime_id), "cannot queue " + id)
		var instance: ActiveCardInstance = e.battle_state.get_active_instances_for_side(side)[0]
		var elapsed: float = instance.get_remaining(e.battle_state.battle_time) + .0001
		e.update(elapsed)
		_check(is_equal_approx(runtime.cooldown_remaining, maxf(4, card.recast_time)), "cooldown differs " + id)
		if id in ["bastion_drive", "fortify"]: _check(unit.shield == int(card.effects[0]["amount"]), "shield differs " + id)
		if id == "repair_burst":
			_check(unit.hp == 500 + int(card.effects[0]["amount"]) and unit.shield == int(card.effects[1]["amount"]), "heal/shield differs")
		if id == "over_reload": _check(absf(cooling.cooldown_remaining - (100 - elapsed - float(card.effects[0]["amount"]))) < .001, "global cooldown reduction differs")
		if id in ["execution", "blood_chain", "rupture_strike"]:
			var result: Dictionary = e.battle_state.battle_events[-1]["result"]
			_check(int(result["metrics"]["damage"]) == int(card.effects[0]["amount"]) + int(card.effects[0]["bonus_amount"]) + unit.get_attack_value(), "conditional damage differs " + id)
		e.dispose()
