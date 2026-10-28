extends Node

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value: _failures.append(message)


func _run() -> void:
	Game.start_new_run("balanced", 7317)
	var progress: Dictionary = Game.build_save_data("map").to_dict().duplicate(true)
	progress.erase("settings")
	for language: String in ["ja", "en"]:
		Game.set_language(language)
		for delta: float in [0.05, 0.23]:
			for id: String in AdvancedCardTutorials.IDS:
				await _lesson(id, delta)
		Game.clear_battle_tutorial()
		# Language is a user setting, not a gameplay mutation.
		var after: Dictionary = Game.build_save_data("map").to_dict()
		after.erase("settings")
		for key: String in progress:
			_check(after[key] == progress[key], "Tutorial changed progress section " + key + ": " + JSON.stringify(after[key]).left(180))
	await _verify_recovery()
	if not _failures.is_empty():
		for message: String in _failures: push_error(message)
		get_tree().quit(1)
		return
	print("ADVANCED_CARD_TUTORIAL_SMOKE_OK: 16 full runs, %d checks; both languages, varied frame deltas, real effects and save isolation" % _checks)
	get_tree().quit()


func _verify_recovery() -> void:
	Game.begin_battle_tutorial("prepared_combos")
	var battle: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control
	add_child(battle)
	for frame: int in 2: await get_tree().process_frame
	battle.set_process(false)
	var director: BattleTutorialDirector = battle.get("_tutorial_director") as BattleTutorialDirector
	director.call("_enter_step", 2)
	director.process(46.0)
	_check(director.get("_failed") and director.is_time_paused(), "Missing effect should offer retry instead of waiting forever")
	_check(director.get_target_kind() == "" and (battle.call("_get_tutorial_target_rect") as Rect2).size == Vector2.ZERO, "Retry kept an unrelated highlight")
	var button: Button = battle.find_child("TutorialContinueButton", true, false) as Button
	_check(button.visible and button.text != "", "Retry action is unavailable")
	director.restart_requested.disconnect(battle._restart_tutorial)
	var calls: Array[int] = [0]
	director.restart_requested.connect(func() -> void: calls[0] += 1)
	button.pressed.emit()
	_check(calls[0] == 1, "Retry button did not request a fresh lesson")
	battle.queue_free()
	await get_tree().process_frame
	Game.clear_battle_tutorial()


func _lesson(id: String, delta: float) -> void:
	_check(Game.begin_battle_tutorial(id), "Cannot start " + id)
	var battle: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control
	add_child(battle)
	for frame: int in 2: await get_tree().process_frame
	battle.set_process(false)
	var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
	engine.set_audio_enabled(false)
	var snapshots: Dictionary = {}
	var complete: bool = false
	for iteration: int in 2400:
		var step: Dictionary = battle.call("get_tutorial_step_data")
		var key: String = String(step.get("key", ""))
		var mode: String = String(step.get("mode", ""))
		if not snapshots.has(key): snapshots[key] = BattleStateCodec.encode(engine.battle_state, engine.has_battle_started())
		_check(not bool((battle.get("_tutorial_director") as BattleTutorialDirector).get("_failed")), "Lesson entered retry: %s/%s dt=%.2f" % [id,key,delta])
		if _failures.size() > 8: break
		if mode == "complete": complete = true; break
		if mode in ["continue", "queue_card"]:
			var time: float = engine.battle_state.battle_time
			var statuses: String = JSON.stringify(engine.battle_state.player.statuses)
			battle.call("_process_tutorial_battle", 2.0)
			_check(is_equal_approx(time, engine.battle_state.battle_time) and statuses == JSON.stringify(engine.battle_state.player.statuses), "Reading a prompt advanced time or expired a status: " + key)
			_check(not (battle.get("_tutorial_director") as BattleTutorialDirector).allows_card("not_a_lesson_card"), "Unrelated card allowed")
			if mode == "continue":
				(battle.find_child("TutorialContinueButton", true, false) as Button).pressed.emit()
			else:
				var queued: bool = false
				for runtime: CardRuntimeState in engine.battle_state.player.card_runtime_states:
					if runtime.card_id == String(step.get("card_id", "")) and runtime.can_use():
						battle.call("_on_card_requested", runtime.runtime_id)
						queued = true
						break
				_check(queued, "Expected card unavailable: " + key)
		else:
			battle.call("_process_tutorial_battle", delta)
		_check(engine.battle_state.player.hp > 0 and engine.battle_state.enemy.hp > 0, "Training combatant died")
	_check(complete, "%s stalled at %s with delta %.2f" % [id, str(battle.call("get_tutorial_step_data")), delta])
	if complete:
		_check(battle.call("is_tutorial_time_paused"), "Completion is not paused")
		_check((battle.call("_get_tutorial_target_rect") as Rect2).size == Vector2.ZERO, "Completion points at an empty target")
		_validate(id, engine, snapshots)
	battle.queue_free()
	await get_tree().process_frame
	Game.clear_battle_tutorial()


func _events(engine: RealtimeBattleEngine, type: String, card: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in engine.battle_state.battle_events:
		if event.get("event_type") == type and (card == "" or event.get("card_id") == card): result.append(event)
	return result


func _validate(id: String, engine: RealtimeBattleEngine, snapshots: Dictionary) -> void:
	match id:
		"prepared_combos":
			_check(snapshots["prepared_kept"]["player"]["card_reservations"].size() == 1, "Guard consumed the attack-only boost")
			_check(snapshots["prepared_both"]["player"]["card_reservations"].size() == 1 and snapshots["prepared_both"]["player"]["repeat_charges"] == 1, "Setup card consumed a preparation")
			var events: Array[Dictionary] = _events(engine, "resolve_card", "quick_slash")
			_check(events.size() == 1, "Echo registered/resolved an extra full card")
			if events.size() == 1:
				var result: Dictionary = events[0]["result"]
				var effects: Array = result["effect_resolutions"]
				_check(effects.size() == 2 and result["effect_repeats"] == 2, "Echo did not repeat effects")
				if effects.size() == 2:
					var one: int = effects[0]["metrics"]["damage"]
					_check(one > 0 and one == int(effects[1]["metrics"]["damage"]), "The boost did not apply to both hits")
					_check(int(result["metrics"]["damage"]) == one*2, "Combined damage was not two actual hits")
			_check(engine.battle_state.player.repeat_charges == 0 and engine.battle_state.player.card_reservations.is_empty(), "Preparations were not consumed")
			_check(_events(engine, "prepare_card", "quick_slash").size() == 1 and engine.battle_state.player.active_slots_used == 0, "Echo incorrectly duplicated registration/slot cost")
		"hostile_reservations":
			_check(snapshots["hostile_armed"]["enemy"]["card_reservations"].size() == 2, "Missing hostile reservations")
			_check(snapshots["hostile_result"]["enemy"]["card_reservations"].is_empty(), "Hostile reservations were not consumed")
			var attacks: Array[Dictionary] = _events(engine, "resolve_card", "quick_slash")
			_check(attacks.size() == 2, "Expected affected and unaffected copies")
			if attacks.size() == 2:
				_check(int(attacks[0]["result"]["metrics"]["damage"]) < int(attacks[1]["result"]["metrics"]["damage"]), "Weakening did not reduce actual HP damage")
			var cooldown: float = 0.0
			for raw: Dictionary in snapshots["hostile_result"]["enemy"]["runtime_states"]:
				if raw["card_id"] == "quick_slash": cooldown = maxf(cooldown, float(raw["cooldown_remaining"]))
			_check(cooldown > Database.get_card("quick_slash").recast_time + 1.0, "Recast Jammer did not lengthen the actual cooldown")
		"regeneration":
			_check(snapshots["regeneration_status"]["player"]["hp"] == 20, "Regeneration healed immediately instead of waiting for its tick")
			var regen: Dictionary = snapshots["regeneration_layers"]["player"]["statuses"]["regen"]
			_check(regen["layers"].size() == 3, "The three real layers did not overlap")
			var heals: Array[Dictionary] = _events(engine, "status_heal")
			_check(heals.size() >= 3, "Periodic healing was not observed")
			var largest: int = 0
			for event: Dictionary in heals: largest = maxi(largest, int(event["result"]["amount"]))
			_check(largest == int(regen["power"]), "The combined tick did not sum all three powers")
			_check(not engine.battle_state.player.has_status("regen") and engine.battle_state.player.hp > 20, "Regeneration did not heal then expire")
		"damage_conversion":
			var attacks: Array[Dictionary] = _events(engine, "resolve_card", "quick_slash")
			_check(attacks.size() == 2, "Conversion demonstration missed an enemy attack")
			if attacks.size() == 2:
				_check(int(attacks[0]["result"]["damage_prevented"]) > 0 and int(attacks[0]["hp_delta"]) > 0, "Life conversion did not actually prevent damage and heal")
				_check(int(attacks[1]["result"]["damage_prevented"]) > 0 and int(attacks[1]["shield_delta"]) > 0, "Barrier conversion did not actually gain shield")
			var fatigue: Array[Dictionary] = _events(engine, "fatigue_card")
			_check(fatigue.size() == 1, "Fatigue exception was not demonstrated exactly once")
			if fatigue.size() == 1:
				var result: Dictionary = fatigue[0]["result"]
				_check(result["player_before"]["statuses"].has("damage_conversion"), "Fatigue resolved after conversion had already expired")
				_check(int(result["player_after"]["hp"]) < int(result["player_before"]["hp"]), "Fatigue was prevented/converted or shield masked the exception")
				_check(result["player_after"]["statuses"].has("damage_conversion"), "Conversion was not still active after fatigue")
			_check(_events(engine, "resolve_card", "life_conversion").size() == 2, "Second practice copy was not used")
