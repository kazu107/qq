extends Node

var _checks: int = 0


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.settings["developer_mode"] = true
	Game.set_language("ja")
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		push_error("Balance lab: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _fingerprint() -> String:
	var records: Array = []
	for kind: String in ["card", "relic"]:
		for id: String in BalanceDraft.ids(kind): records.append(Database.get_card(id).to_dict() if kind == "card" else Database.get_relic(id).to_dict())
	return JSON.stringify(records).sha256_text()


func _state() -> String:
	return JSON.stringify({"run": Game.current_run.to_dict(), "meta": Game.meta_progress, "hint": Game.current_screen_hint})


func _run() -> void:
	BalanceDraft.warm_catalog()
	_check(BalanceDraft.ids("card").size() >= 93 and BalanceDraft.ids("relic").size() == 86, "catalog is incomplete")
	var database_hash: String = _fingerprint()
	var draft: BalanceDraft = BalanceDraft.new()
	for id: String in BalanceDraft.ids("relic"):
		var original_run: RunState = RunState.from_starter(Database.get_starter("balanced"), 99)
		var sandbox_run: RunState = RunState.from_starter(Database.get_starter("balanced"), 99)
		RelicService.new().grant_relic(original_run, id)
		RelicService.new().grant_relic(sandbox_run, id, draft)
		for key: String in ["max_hp", "player_hp", "attack", "speed", "loadout_limit", "gold", "relic_state"]:
			_check(original_run.get(key) == sandbox_run.get(key), "unmodified pickup parity: " + id + "/" + key)
		var original_engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); original_engine.setup(original_run, "scout")
		var sandbox_engine: RealtimeBattleEngine = RealtimeBattleEngine.new(); sandbox_engine.setup_sandbox(sandbox_run, "scout", draft)
		for key: String in ["max_hp", "hp", "attack", "speed", "shield", "active_slot_max", "cast_time_modifier", "shield_decay_interval"]:
			_check(original_engine.battle_state.player.get(key) == sandbox_engine.battle_state.player.get(key), "unmodified combat parity: " + id + "/" + key)
		original_engine.dispose(); sandbox_engine.dispose()
	for kind: String in ["card", "relic"]:
		for id: String in BalanceDraft.ids(kind):
			_check(not BalanceDraft.fields(kind, id).is_empty(), "no numerical fields for " + id)
			for field: Dictionary in BalanceDraft.fields(kind, id):
				_check(draft.set_value(kind, id, field["path"], field["before"]), "invalid original field: " + id + "/" + field["path"] + "=" + str(field["before"]))
	_check(draft.changes().is_empty(), "writing original values must not dirty the draft")
	_check(draft.set_value("card", "quick_slash", "effects.0.amount", 9), "card damage edit failed")
	_check(draft.set_value("card", "quick_slash", "recast_time", 2.5), "fractional timing edit failed")
	_check(draft.card("quick_slash", 3).effects[0]["amount"] == 12, "grade preview does not combine base and grade edits")
	_check(not draft.set_value("card", "quick_slash", "cast_time", -1), "negative cast accepted")
	_check(not draft.set_value("card", "quick_slash", "cast_time", NAN), "NaN accepted")
	_check(not draft.set_value("card", "quick_slash", "name", 123), "unregistered path accepted")
	_check(not draft.set_value("card", "quick_slash", "active_slot_cost", 1.5), "fractional slot count accepted")
	var copy: BalanceDraft = BalanceDraft.new()
	_check(copy.import_document(JSON.parse_string(JSON.stringify(draft.document()))), "valid diff could not be imported")
	var tampered: Dictionary = draft.document(); tampered["changes"][0]["before"] = -999
	_check(not copy.import_document(tampered), "baseline tampering accepted")
	tampered = draft.document(); tampered["source_hash"] = "old"
	_check(not copy.import_document(tampered), "stale source hash accepted")
	_check(draft.save_draft(), "draft save failed")
	_check(draft.save_draft(), "atomic overwrite failed")
	var restored: BalanceDraft = BalanceDraft.new()
	_check(restored.load_draft() and restored.changes() == draft.changes(), "device draft persistence failed")
	var targets: Array[String] = ["quick_slash", "strike"]
	var bulk: BalanceDraft = draft.batch_candidate("card", targets, "recast_time", 0, 0.5)
	_check(bulk.card("quick_slash").recast_time == 1.25 and bulk.card("strike").recast_time == 6.0, "bulk timing edits failed")
	_check(draft.card("quick_slash").recast_time == 2.5, "bulk preview mutated current draft")
	Game.start_new_run("balanced", 4242)
	var game_snapshot: String = _state()
	var config: Dictionary = {"starter": "balanced", "enemy": "scout", "hp": 60, "attack": 3, "speed": 5, "cards": ["quick_slash", "strike", "guard"], "relics": ["reactive_barrier"], "count": 1, "limit": 30, "seed": 12345}
	_check(draft.set_value("relic", "reactive_barrier", "parameters.starting_shield", 42), "legacy relic edit failed")
	var run: RunState = BalanceTrialRunner.make_run(config, draft)
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	_check(engine.setup_sandbox(run, "scout", draft), "sandbox setup failed")
	_check(engine.battle_state.player.shield == 42 and engine._get_card_def("player", "quick_slash").effects[0]["amount"] == 9, "draft not applied to combat")
	_check(engine._get_card_def("enemy", "quick_slash").effects[0]["amount"] == 9, "card changes must affect both sides")
	draft.set_value("relic", "reactive_barrier", "parameters.starting_shield", 43)
	_check(engine.balance_sandbox.relic_value("reactive_barrier", "starting_shield", 6) == 42, "active sandbox did not freeze its draft")
	Game.complete_battle(engine.build_summary())
	_check(_state() == game_snapshot, "sandbox result changed live run/meta")
	engine.dispose()
	var normal: RealtimeBattleEngine = RealtimeBattleEngine.new(); normal.setup(run, "scout")
	_check(normal.battle_state.player.shield == 6 and normal._get_card_def("player", "quick_slash").effects[0]["amount"] == 4, "draft leaked into normal engine")
	normal.dispose()
	var relay: BalanceDraft = BalanceDraft.new(); relay.set_value("relic", "triplet_relay", "effects.0.amount", 7)
	var relay_config: Dictionary = config.duplicate(true); relay_config["relics"] = ["triplet_relay"]
	engine = RealtimeBattleEngine.new(); engine.setup_sandbox(BalanceTrialRunner.make_run(relay_config, relay), "scout", relay)
	engine.battle_state.player.card_runtime_states[1].begin_cooldown(10)
	engine.battle_state.relic_runtime_state["player"]["manual_resolves"] = 3
	var instance: ActiveCardInstance = ActiveCardInstance.new(); instance.runtime_id = "player_0"
	engine._relic_controller._handle_manual_sequences("player", instance, relay.card("quick_slash"))
	_check(is_equal_approx(engine.battle_state.player.card_runtime_states[1].cooldown_remaining, 3), "modern relic parameter did not reach its real proc")
	engine.dispose()
	var conditional: BalanceDraft = BalanceDraft.new()
	conditional.set_value("relic", "silent_three_second_timer", "effects.0.cast_multiplier", 0.4)
	var conditional_config: Dictionary = config.duplicate(true); conditional_config["relics"] = ["silent_three_second_timer"]
	engine = RealtimeBattleEngine.new(); engine.setup_sandbox(BalanceTrialRunner.make_run(conditional_config, conditional), "scout", conditional)
	_check(engine.battle_state.player.cast_time_modifier == 1.0, "conditional multiplier leaked into unconditional setup")
	engine.battle_state.relic_runtime_state["player"]["empty_timeline_seconds"] = 4.0
	var profile: Dictionary = engine._relic_controller.build_commit_profile("player", conditional.card("strike"))
	_check(is_equal_approx(profile["cast_time"], maxf(0.45, conditional.card("strike").cast_time * engine.battle_state.player.get_cast_time_multiplier() * 0.4)), "conditional relic used its multiplier twice")
	engine.dispose()
	var runner: BalanceTrialRunner = BalanceTrialRunner.new()
	_check(runner.begin(config, BalanceDraft.new()), "comparison setup failed")
	for iteration: int in 1000:
		if not runner.running: break
		runner.advance(50000)
	_check(not runner.running and runner.reports[0]["completed"] == 1 and runner.reports[1]["completed"] == 1, "comparison did not complete both variants")
	for metric: String in ["wins", "time", "damage", "shield", "heal"]:
		_check(runner.reports[0][metric] == runner.reports[1][metric], "unmodified A/B is not deterministic: " + metric)
	_check(_state() == game_snapshot and _fingerprint() == database_hash, "simulation changed global data or progression")
	var loop_draft: BalanceDraft = BalanceDraft.new()
	loop_draft.set_value("card", "auto_turret", "cast_time", 0)
	loop_draft.set_value("card", "auto_turret", "effects.0.amount", 0)
	loop_draft.set_value("card", "auto_turret", "effects.1.delay", 0)
	var loop_config: Dictionary = config.duplicate(true); loop_config["cards"] = ["auto_turret"]; loop_config["attack"] = 0
	engine = RealtimeBattleEngine.new(); engine.record_visuals = false
	engine.setup_sandbox(BalanceTrialRunner.make_run(loop_config, loop_draft), "scout", loop_draft)
	engine.battle_state.enemy.hp = 100000; engine.battle_state.enemy.max_hp = 100000
	engine.start_battle(); var accepted: bool = engine.request_use_card("player", "player_0")
	_check(accepted, "safety test card was not accepted")
	for step: int in 20:
		engine.update(0.05)
		if engine.balance_limit_reached: break
	_check(engine.balance_limit_reached, "zero-cast unlimited chain did not hit the sandbox-only guard")
	engine.dispose()
	Game.settings["developer_mode"] = false
	engine = RealtimeBattleEngine.new(); _check(not engine.setup_sandbox(run, "scout", draft), "non-developer can use sandbox")
	Game.settings["developer_mode"] = true
	await _test_ui()
	_check(_fingerprint() == database_hash and _state() == game_snapshot, "UI changed real content or progression")
	print("BALANCE_LAB_SMOKE_OK checks=%d" % _checks)
	get_tree().quit()


func _test_ui() -> void:
	var screen: Control = load("res://scenes/debug/BalanceLab.tscn").instantiate() as Control
	add_child(screen)
	for frame: int in 180:
		if screen.call("is_content_ready"): break
		await get_tree().process_frame
	_check(screen.call("is_content_ready"), "catalog not ready")
	_check((screen.get("_catalog_widgets") as Dictionary).size() == BalanceDraft.ids("card").size() + BalanceDraft.ids("relic").size(), "UI omitted catalog entries")
	screen.call("_select", "card", "quick_slash")
	var spin: SpinBox = screen.find_child("BalanceValue_recast_time", true, false) as SpinBox
	_check(spin != null, "timing editor missing")
	spin.value = 3.25
	_check((screen.get("draft") as BalanceDraft).card("quick_slash").recast_time == 3.25, "UI edit did not update the draft")
	_check(screen.find_child("BalancePreviewGrade3", true, false) != null, "all-grade preview missing")
	screen.call("_select", "relic", "reactive_barrier")
	spin = screen.find_child("BalanceValue_parameters_starting_shield", true, false) as SpinBox
	spin.value = 20
	_check((screen.get("_test_relics") as Array).has("reactive_barrier"), "edited relic was not added to test setup")
	screen.call("_open_manual", true)
	await get_tree().process_frame
	var manual: BalanceBattlePreview = screen.get("_manual") as BalanceBattlePreview
	_check(manual != null and manual.engine.battle_state.player.shield == 20, "manual battle did not use the draft")
	screen.call("_close_modal")
	(screen.find_child("BalanceMatches", true, false) as SpinBox).value = 1
	(screen.find_child("BalanceTimeLimit", true, false) as SpinBox).value = 10
	screen.call("_compare")
	_check((screen.get("runner") as BalanceTrialRunner).running, "UI cancelled comparison as it opened")
	screen.call("_close_modal")
	screen.queue_free()
	await get_tree().process_frame
