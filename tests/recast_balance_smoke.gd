extends Node

const FIXTURE := "res://tests/fixtures/recast_balance_0_52_1.json"
const FOLLOW_UP := "res://tests/fixtures/grade_balance_0_52_2.json"
const LATEST := "res://tests/fixtures/balance_0_55_1.json"
const EXCLUDED: Dictionary = {
	"quick_slash": 8, "strike": 12, "guard": 12, "heavy_swing": 26,
	"delay_step": 22, "haste_focus": 16, "weak_shot": 18, "bleed_cut": 20,
	"quick_guard": 16, "reload": 32,
}
var _checks: int = 0


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized()
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("Recast balance: " + message)
		get_tree().quit(1); assert(value, message)


func _run() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var draft: BalanceDraft = BalanceDraft.new()
	if OS.get_cmdline_user_args().has("--validate-import"):
		_check(draft.import_document(document), "source hash or original field values differ")
		_check(draft.changes().size() == 87, "imported change count differs")
		for change: Dictionary in document["changes"]:
			_check(is_equal_approx(draft.card(change["id"]).recast_time, change["after"]), "draft import differs: " + change["id"])
		print("RECAST_IMPORT_VALIDATION_OK changes=87 source=" + document["source_hash"])
		get_tree().quit(); return
	_check(document["changes"].size() == 87, "submission scope changed")
	var replacements: Dictionary = {}
	for fixture: String in [FOLLOW_UP, LATEST]:
		var follow_up: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
		for change: Dictionary in follow_up["changes"]: replacements[change["id"] + ":" + change["path"]] = change["after"]
	var ids: Array[String] = []
	for change: Dictionary in document["changes"]:
		var id: String = change["id"]
		_check(change["kind"] == "card" and change["path"] == "recast_time" and not ids.has(id), "unexpected/duplicate change")
		ids.append(id)
		_check(is_equal_approx(float(change["after"]), float(change["before"]) * 0.7), "not a 30 percent reduction: " + id)
		var latest_base: float = float(replacements.get(id + ":recast_time", change["after"]))
		_check(is_equal_approx(Database.get_card(id).recast_time, latest_base), "published value differs: " + id)
		_check(is_equal_approx(draft.value("card", id, "recast_time"), latest_base), "lab baseline differs: " + id)
	_check(not draft.import_document(document), "old-source diff was applied twice")
	# Later explicit requests supersede only these published fields.
	for id: String in EXCLUDED:
		_check(not ids.has(id) and Database.get_card(id).recast_time == float(replacements.get(id + ":recast_time", EXCLUDED[id])), "excluded card changed without a later request: " + id)
	_check(ids.size() + EXCLUDED.size() + ReservedCardRules.NAMES.size() + RegenerationRules.CARD_IDS.size() + DamageConversionRules.CARD_IDS.size() == Database.get_all_card_ids().size() + Database.get_boss_card_ids().size(), "catalog coverage differs")
	for tier: int in range(6):
		var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
		run.equipped_cards = ids.duplicate()
		for id: String in ids: run.card_upgrades[id] = tier
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false); engine.setup(run, "scout")
		for change: Dictionary in document["changes"]:
			var id: String = change["id"]
			engine.battle_state.enemy.temporary_card_modifiers[id] = {"tier": tier}
			var base: CardDef = Database.get_card(id)
			var previous: CardDef = CardDef.from_dict(base.to_dict()); previous.recast_time = change["before"]
			var old_grade: CardDef = CardUpgradeResolver.build_card_at_tier(id, tier, previous)
			var expected: CardDef = CardUpgradeResolver.build_card_at_tier(id, tier)
			var latest_base: float = float(replacements.get(id + ":recast_time", change["after"]))
			var recast: float = float(replacements.get("%s:grade_overrides.%d.recast_time" % [id, tier], maxf(0, old_grade.recast_time + latest_base - float(change["before"]))))
			_check(is_equal_approx(expected.recast_time, recast), "grade reduction changed: %s / %d" % [id, tier])
			_check(expected.cast_time == old_grade.cast_time and expected.effects == old_grade.effects, "cast/effects changed: " + id)
			_check(is_equal_approx(draft.card(id, tier).recast_time, expected.recast_time), "lab grade differs: " + id)
			for side: String in ["player", "enemy"]:
				_check(is_equal_approx(engine._get_card_def(side, id).recast_time, expected.recast_time), "combat grade differs: %s / %s / %d" % [id, side, tier])
		engine.dispose()
	_test_cooldowns()
	print("RECAST_BALANCE_SMOKE_OK checks=%d changes=87 excluded=10 grades=0..5 player/enemy/lab/cooldown" % _checks)
	get_tree().quit()


func _test_cooldowns() -> void:
	for tier: int in range(6):
		var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
		run.equipped_cards = ["echo_cast", "spark_jab"]
		for id: String in run.equipped_cards: run.card_upgrades[id] = tier
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false); engine.setup_pvp(run, run)
		engine.start_battle()
		for side: String in ["player", "enemy"]:
			for runtime: CardRuntimeState in engine.battle_state.get_unit(side).get_sorted_runtime_states():
				var card: CardDef = engine._get_card_def(side, runtime.card_id)
				_check(engine.request_use_card(side, runtime.runtime_id), "cannot queue " + runtime.card_id)
				var instance: ActiveCardInstance = engine.battle_state.get_active_instances_for_side(side)[0]
				engine.update(instance.scheduled_time - engine.battle_state.battle_time + 0.0001)
				_check(is_equal_approx(runtime.cooldown_remaining, maxf(4, card.recast_time)), "resolved cooldown differs: %s / %s / %d" % [side, runtime.card_id, tier])
		engine.dispose()
		engine = RealtimeBattleEngine.new(); engine.set_audio_enabled(false); engine.setup(run, "boss_timekeeper")
		engine.battle_state.enemy.temporary_card_modifiers["timekeeper_amplify"] = {"tier": tier}
		engine.start_battle(); engine.set_enemy_ai_enabled(false)
		for runtime: CardRuntimeState in engine.battle_state.enemy.get_sorted_runtime_states():
			if runtime.card_id != "timekeeper_amplify": continue
			var card: CardDef = engine._get_card_def("enemy", runtime.card_id)
			_check(engine.request_use_card("enemy", runtime.runtime_id), "cannot queue boss amplifier")
			for instance: ActiveCardInstance in engine.battle_state.get_active_instances_for_side("enemy"):
				if instance.runtime_id == runtime.runtime_id:
					engine.update(instance.scheduled_time - engine.battle_state.battle_time + 0.0001)
					break
			_check(is_equal_approx(runtime.cooldown_remaining, maxf(4, card.recast_time)), "boss cooldown differs at grade %d" % tier)
		engine.dispose()
