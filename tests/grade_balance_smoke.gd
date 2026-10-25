extends Node

const FIXTURE := "res://tests/fixtures/grade_balance_0_52_2.json"
const IDS: Array[String] = ["assault", "barrier_deploy", "bleed_cut", "reload", "time_buy"]
const EXPECTED: Dictionary = {
	"assault": {"cast": [4.8, 4.8, 4.8, 4.8, 4.8, 4.8], "recast": [16.8, 16.4, 16, 15.6, 15.2, 14.8], "amount": [10, 14, 18, 22, 26, 40]},
	"barrier_deploy": {"cast": [9, 8.9, 8.8, 6.8, 6.25, 5.85], "recast": [25.2, 24.8, 22, 21.6, 20.2, 18.9], "amount": [18, 24, 26, 28, 31, 34]},
	"bleed_cut": {"cast": [4.2, 4.2, 4.2, 4.2, 4.2, 4.2], "recast": [20, 20, 20, 20, 20, 20], "amount": [4, 5, 6, 7, 8, 9], "bleed": [1, 2, 3, 4, 5, 6]},
	"reload": {"cast": [3, 3, 3, 3, 3, 3], "recast": [28, 26, 24, 22, 20, 18], "amount": [6, 9, 12, 15, 18, 21]},
	"time_buy": {"cast": [4.2, 4.2, 4.2, 4.2, 4.2, 4.2], "recast": [22.4, 21.4, 20.4, 19.4, 18.4, 17.4], "amount": [3.3, 4.3, 5.3, 6.3, 7.3, 8.3]},
}
var _checks: int = 0


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized()
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("Grade balance: " + message)
		get_tree().quit(1); assert(value, message)


func _run() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var draft: BalanceDraft = BalanceDraft.new()
	if OS.get_cmdline_user_args().has("--validate-import"):
		_check(draft.import_document(document), "source hash or original values differ")
		_check(draft.changes().size() == 46, "import scope differs")
		print("GRADE_BALANCE_IMPORT_OK changes=46 source=" + document["source_hash"])
		get_tree().quit(); return
	_check(document["changes"].size() == 46, "publication scope changed")
	for change: Dictionary in document["changes"]:
		_check(change["kind"] == "card" and IDS.has(change["id"]), "unexpected change")
		_check(is_equal_approx(draft.value("card", change["id"], change["path"]), float(change["after"])), "lab field differs: %s / %s" % [change["id"], change["path"]])
	_check(not draft.import_document(document), "published old-source diff was applied again")
	for grade: int in 6:
		var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
		run.equipped_cards = IDS.duplicate(); run.max_hp = 500; run.player_hp = 500
		for id: String in IDS: run.card_upgrades[id] = grade
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false); engine.setup_pvp(run, run)
		for id: String in IDS:
			var expected: CardDef = draft.card(id, grade)
			_check(is_equal_approx(expected.cast_time, EXPECTED[id]["cast"][grade]) and is_equal_approx(expected.recast_time, EXPECTED[id]["recast"][grade]), "grade timing differs: %s / %d" % [id, grade])
			_check(is_equal_approx(expected.effects[0]["amount"], EXPECTED[id]["amount"][grade]), "grade amount differs: %s / %d" % [id, grade])
			if id == "bleed_cut": _check(expected.effects[1]["bleed_power"] == EXPECTED[id]["bleed"][grade] and expected.effects[1]["duration"] == 36, "bleed grade/duration differs")
			for side: String in ["player", "enemy"]:
				var actual: CardDef = engine._get_card_def(side, id)
				_check(is_equal_approx(actual.cast_time, expected.cast_time) and is_equal_approx(actual.recast_time, expected.recast_time) and actual.effects == expected.effects, "combat grade differs: %s / %s / %d" % [id, side, grade])
		engine.dispose()
		for side: String in ["player", "enemy"]: _test_resolution(run, side)
	var forge_run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	forge_run.card_upgrades["assault"] = 3
	_check(ForgeService.new().upgrade_card(forge_run, "assault") == 3, "forge crossed grade 3")
	print("GRADE_BALANCE_SMOKE_OK checks=%d fields=46 cards=5 grades=0..5 lab/player/enemy/damage/shield/bleed/recast/delay" % _checks)
	get_tree().quit()


func _test_resolution(run: RunState, side: String) -> void:
	for id: String in IDS:
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false); engine.setup_pvp(run, run); engine.start_battle()
		var unit: UnitState = engine.battle_state.get_unit(side)
		var target: UnitState = engine.battle_state.get_opponent(side)
		var card: CardDef = engine._get_card_def(side, id)
		var runtime: CardRuntimeState = null
		for candidate: CardRuntimeState in unit.get_sorted_runtime_states():
			if candidate.card_id == id: runtime = candidate
		var duration: float = card.cast_time * unit.get_cast_time_multiplier()
		var reload_target: CardRuntimeState = null
		var delayed: ActiveCardInstance = null
		var before_cooldown: float = 100
		if id == "reload":
			for candidate: CardRuntimeState in unit.get_sorted_runtime_states():
				if candidate.card_id == "assault": reload_target = candidate
			reload_target.begin_cooldown(before_cooldown)
		if id == "time_buy":
			var other_side: String = "enemy" if side == "player" else "player"
			for candidate: CardRuntimeState in target.get_sorted_runtime_states():
				if candidate.card_id == "barrier_deploy":
					_check(engine.request_use_card(other_side, candidate.runtime_id), "cannot queue delay target")
					delayed = engine.battle_state.get_active_instances_for_side(other_side)[0]
					delayed.scheduled_time = 100
		_check(runtime != null and engine.request_use_card(side, runtime.runtime_id), "cannot queue " + id)
		engine.update(duration + 0.0001)
		_check(is_equal_approx(runtime.cooldown_remaining, card.recast_time), "resolved cooldown differs: " + id)
		match id:
			"assault", "bleed_cut":
				_check(target.hp == 500 - int(card.effects[0]["amount"]) - unit.get_attack_value(), "resolved damage differs: " + id)
				if id == "bleed_cut":
					var power: int = BleedRules.resolve_power(card.effects[1], unit.get_attack_value())
					_check(target.statuses["bleed"]["damage"] == power, "resolved bleed differs")
					var before: int = target.hp
					engine.update(6)
					_check(before - target.hp == power, "first bleed tick differs")
			"barrier_deploy": _check(unit.shield == card.effects[0]["amount"], "resolved shield differs")
			"reload": _check(absf(reload_target.cooldown_remaining - (before_cooldown - duration - float(card.effects[0]["amount"]))) < 0.001, "resolved cooldown reduction differs")
			"time_buy": _check(is_equal_approx(delayed.scheduled_time, 100 + float(card.effects[0]["amount"])), "resolved delay differs")
		engine.dispose()
