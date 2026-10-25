extends Node

const FIXTURE := "res://tests/fixtures/published_balance.json"
var _checks: int = 0


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("Published balance: " + message)
		get_tree().quit(1)
		assert(value, message)


func _run() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var draft: BalanceDraft = BalanceDraft.new()
	if OS.get_cmdline_user_args().has("--validate-import"):
		if not draft.import_document(document) or draft.changes().size() != document["changes"].size():
			push_error("Balance import source hash, original values or requested fields do not match")
			get_tree().quit(1)
			return
		print("BALANCE_IMPORT_VALIDATION_OK changes=%d source=%s" % [document["changes"].size(), document["source_hash"]])
		get_tree().quit()
		return
	var ids: Array[String] = []
	for change: Dictionary in document["changes"]:
		_check(change["kind"] == "card", "unexpected publication kind")
		var id: String = change["id"]
		if not ids.has(id): ids.append(id)
		var path: String = change["path"]
		var parts: PackedStringArray = path.split(".")
		var tier: int = int(parts[1]) if path.begins_with("grade_overrides.") else 0
		var resolved_path: String = ".".join(parts.slice(2)) if tier > 0 else path
		var card: CardDef = CardUpgradeResolver.build_card_at_tier(id, tier)
		_check(is_equal_approx(float(BalanceDraft.read(card.to_dict(), resolved_path)), float(change["after"])), "published value differs: %s / %s" % [id, path])
		_check(is_equal_approx(draft.value("card", id, path), float(change["after"])), "lab baseline differs: %s / %s" % [id, path])
	_check(ids.size() == 8 and document["changes"].size() == 91, "publication scope changed")
	_check(not draft.import_document(document), "an already-published old-source diff was accepted again")
	for tier: int in range(6):
		var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
		run.equipped_cards = ids.duplicate()
		for id: String in ids: run.card_upgrades[id] = tier
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); engine.setup(run, "scout")
		for id: String in ids:
			engine.battle_state.enemy.temporary_card_modifiers[id] = {"tier": tier}
			var expected: CardDef = draft.card(id, tier)
			for side: String in ["player", "enemy"]:
				var actual: CardDef = engine._get_card_def(side, id)
				_check(actual.effects == expected.effects and is_equal_approx(actual.cast_time, expected.cast_time) and is_equal_approx(actual.recast_time, expected.recast_time), "combat ignored published grade: %s / %s / %d" % [side, id, tier])
		engine.dispose()
	var forge_run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	forge_run.card_upgrades["guard"] = 3
	_check(ForgeService.new().upgrade_card(forge_run, "guard") == 3, "forge grade cap changed")
	_check(CardUpgradeResolver.build_card_at_tier("guard", 5).effects[0]["amount"] == 28, "grade 5 shield value")
	_check(CardUpgradeResolver.build_card_at_tier("heavy_swing", 5).effects[0]["amount"] == 49, "grade 5 attack value")
	_test_resolutions()
	print("PUBLISHED_BALANCE_SMOKE_OK checks=%d changes=91 cards=8 grades=0..5 player/enemy/lab" % _checks)
	get_tree().quit()


func _test_resolutions() -> void:
	for tier: int in range(6):
		var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
		run.equipped_cards = ["guard", "heavy_swing"]
		run.card_upgrades = {"guard": tier, "heavy_swing": tier}
		var opponent: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
		opponent.max_hp = 200; opponent.player_hp = 200
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
		engine.set_audio_enabled(false)
		engine.setup_pvp(run, opponent)
		engine.start_battle()
		for runtime: CardRuntimeState in engine.battle_state.player.get_sorted_runtime_states():
			var card: CardDef = engine._get_card_def("player", runtime.card_id)
			var duration: float = card.cast_time * engine.battle_state.player.get_cast_time_multiplier()
			var hp_before: int = engine.battle_state.enemy.hp
			_check(engine.request_use_card("player", runtime.runtime_id), "published card could not be queued")
			var instance: ActiveCardInstance = engine.battle_state.get_active_instances_for_side("player")[0]
			_check(is_equal_approx(instance.scheduled_time - engine.battle_state.battle_time, duration), "queued cast time differs")
			engine.update(duration + 0.001)
			_check(is_equal_approx(runtime.cooldown_remaining, card.recast_time), "resolved recast time differs")
			if runtime.card_id == "guard":
				_check(engine.battle_state.player.shield == int(card.effects[0]["amount"]), "shield resolution differs")
			else:
				_check(hp_before - engine.battle_state.enemy.hp == int(card.effects[0]["amount"]) + engine.battle_state.player.get_attack_value(), "attack resolution differs")
		engine.dispose()
