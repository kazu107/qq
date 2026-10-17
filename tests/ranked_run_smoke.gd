extends Node

const TICKET := {"id": "11111111-1111-4111-8111-111111111111", "user_id": "22222222-2222-4222-8222-222222222222", "seed": 426042, "starter_id": "balanced", "ruleset": "infinite-1", "season_id": "test"}


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.settings["developer_mode"] = false
	Game.settings["replay_auto_export"] = false
	call_deferred("_run")


func _run() -> void:
	RankedSession.initialize(TICKET)
	assert(Game.current_run.max_hp == 78)
	assert(Game.current_run.attack == 5)
	assert(Game.current_run.content_pool["cards"].size() == Database.get_all_card_ids().size())
	var node_id: String = MapRouteGraph.allowed_ids(Game.current_run.map_state, 0)[0]
	assert(Game.select_map_node(node_id) == "battle")
	var enemy: String = Game.prepare_next_battle()
	var battle: RealtimeBattleEngine = RealtimeBattleEngine.new()
	battle.set_audio_enabled(false)
	battle.record_visuals = false
	battle.setup(Game.current_run, enemy)
	battle.start_battle()
	for _tick: int in 120: battle.update(RankedSession.STEP)
	var before_time: float = battle.battle_state.battle_time
	Game.stash_active_run_for_hub()
	battle.dispose()
	assert(Game.has_suspended_run("ranked"))
	Game.resume_suspended_run("ranked")
	assert(not bool(Game.current_run.ranking.get("disqualified", false)))
	battle = RankedSession.engine
	assert(is_equal_approx(battle.battle_state.battle_time, before_time))
	for tick: int in 18000:
		if battle.battle_state.winner != "": break
		if tick % 12 == 0:
			for card: CardRuntimeState in battle.battle_state.player.card_runtime_states:
				if card.cooldown_remaining <= 0.0: battle.request_use_card("player", card.runtime_id)
		battle.update(RankedSession.STEP)
	assert(battle.battle_state.winner != "")
	Game.complete_battle(battle.build_summary())
	battle.dispose()
	if Game.current_screen_hint == "reward": Game.skip_reward()
	var expected: Dictionary = InfiniteScoreResolver.new().calculate(Game.current_run)
	var commands: Array = Array(Game.current_run.ranking["commands"]).duplicate(true)
	var response: Dictionary = RankedSession.replay(TICKET, commands)
	assert(not response.has("error"), JSON.stringify(response))
	assert(int(response["result"]["total_score"]) == int(expected["total_score"]), JSON.stringify(response))
	if not OS.has_feature("web"):
		var fixture: FileAccess = FileAccess.open("res://build/ranked-fixture.json", FileAccess.WRITE)
		fixture.store_string(JSON.stringify({"ticket": TICKET, "commands": commands, "expected_score": expected["total_score"]}))
		fixture.close()
	commands.append({"kind": "game", "method": "developer_add_gold", "args": [999]})
	var tampered: Dictionary = RankedSession.replay(TICKET, commands)
	assert(tampered.has("error"))
	print("RANKED_RUN_SMOKE_OK ", JSON.stringify({"score": expected["total_score"], "commands": commands.size(), "resumed": true, "tamper_rejected": true}))
	get_tree().quit()
