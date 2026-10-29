extends Node

var checks: int = 0
var service: MetaProgressService = MetaProgressService.new()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error(message)
		get_tree().quit(1)
		assert(value,message)


func fresh_meta() -> Dictionary:
	var meta: Dictionary = Database.meta_progress_template.duplicate(true)
	service.ensure_defaults(meta)
	return meta


func run_with(cards: Array[String], hp: int = 60) -> RunState:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"),4242)
	run.player_cards=cards.duplicate();run.equipped_cards=cards.duplicate();run.loadout_limit=100
	run.player_hp=hp
	return run


func engine_for(run: RunState, enemy: String = "scout") -> RealtimeBattleEngine:
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.setup(run,enemy);engine.set_enemy_ai_enabled(false);engine.set_audio_enabled(false)
	engine.battle_state.enemy.max_hp=10000;engine.battle_state.enemy.hp=10000
	return engine


func play(engine: RealtimeBattleEngine, id: String) -> void:
	var selected: CardRuntimeState
	for runtime: CardRuntimeState in engine.battle_state.player.card_runtime_states:
		if runtime.card_id==id and runtime.can_use():selected=runtime;break
	check(selected!=null,"Card not ready: "+id)
	check(engine.request_use_card("player",selected.runtime_id),"Registration failed: "+id)
	for frame: int in 800:
		engine.update(.05)
		if selected.state==CardRuntimeState.CardState.COOLDOWN:return
	check(false,"Card never resolved: "+id)


func finish(engine: RealtimeBattleEngine) -> Dictionary:
	engine.battle_state.winner="player"
	return engine.build_summary()


func _ready() -> void:
	Database.load_all();Game.ensure_meta_initialized();Game.settings["developer_mode"]=false;Game.clear_battle_tutorial()
	call_deferred("test_all")


func test_all() -> void:
	check(Database.get_all_achievement_ids().size()==48,"Expected all 48 achievement groups")
	var tiers: int=0
	for id: String in Database.get_all_achievement_ids():
		var def: Dictionary=Database.get_achievement(id)
		if int(def.get("tracking_version",0))!=1:continue
		var meta: Dictionary=fresh_meta()
		for tier: Dictionary in def["tiers"]:
			tiers+=1
			var stat: String=tier["condition"]["stat"]
			meta["achievement_stats"][stat]=int(tier["condition"]["value"])-1
			check(not service.claim_achievement(meta,id),"Early claim: "+id)
			meta["achievement_stats"][stat]+=1
			var bonuses: Dictionary=meta["permanent_bonuses"].duplicate(true)
			var points: int=meta["points"]
			check(service.claim_achievement(meta,id),"Threshold claim failed: "+id)
			check(meta["points"]==points+int(tier["rewards"][0]["amount"]) and meta["permanent_bonuses"]==bonuses,"Reward mismatch or uncapped permanent bonus")
			check(not service.claim_achievement(meta,id),"Duplicate reward: "+id)
	check(tiers==58,"Expected 58 new reward tiers")
	var meta: Dictionary=fresh_meta()
	var run: RunState=run_with(["reserve_focus","guard","echo_cast","quick_slash"],10)
	var engine: RealtimeBattleEngine=engine_for(run)
	for id: String in ["reserve_focus","guard","echo_cast","quick_slash"]:play(engine,id)
	var summary: Dictionary=finish(engine)
	check(summary["achievement_eligible"],"A normal battle was excluded")
	check(AdvancedAchievementProgress.record_battle(meta,run,summary),"Battle not credited")
	var stats: Dictionary=meta["achievement_stats"]
	check(stats["reservation_uses"]==1 and stats["echo_uses"]==1,"Preparation grants were mistaken for actual activations")
	check(stats["actual_damage_total"]==30 and stats["max_hit_damage"]==15,"Echo hits were combined or overkill inflated damage")
	check(stats["card_types_used"]==4 and stats["flawless_wins"]==1 and stats["comeback_wins"]==1,"Card variety or win conditions incorrect")
	var saved: Dictionary=RunState.from_dict(run.to_dict()).achievement_state
	var loaded: RunState=RunState.from_dict(run.to_dict())
	var before: String=JSON.stringify(meta)
	check(not AdvancedAchievementProgress.record_battle(meta,loaded,summary) and JSON.stringify(meta)==before,"Duplicate after save/reload was credited")
	check(saved==run.achievement_state,"Achievement run state did not serialize")
	engine.dispose()
	# A temporary loss of HP still disqualifies flawless, even if fully healed later.
	run=run_with(["regen_burst","life_conversion","barrier_conversion","field_medic"],59)
	engine=engine_for(run);play(engine,"regen_burst");engine.update(6.1)
	summary=engine.build_summary()
	check(summary["analysis"]["achievement_metrics"]["player"]["regen_healing"]==1,"Overhealing counted as actual regeneration")
	engine.battle_state.player.hp=30
	play(engine,"life_conversion")
	DamageResolver.apply_fixed_damage(engine.battle_state.player,40)
	engine.update(8.1)
	play(engine,"barrier_conversion")
	DamageResolver.apply_fixed_damage(engine.battle_state.player,40)
	engine.apply_status_from_card("enemy","player","weak",10)
	engine.apply_status_from_card("enemy","player","slow",10)
	for id: String in ["weak","slow","weak"]:engine.remove_status_from_card("player","player",id)
	engine.battle_state.player.heal(999)
	summary=finish(engine)
	check(summary["analysis"]["achievement_metrics"]["player"]["cleanses"]==2,"Empty cleanse counted")
	check(AdvancedAchievementProgress.record_battle(meta,run,summary),"Second battle not credited")
	check(stats["converted_damage"]==80 and stats["statuses_cleansed"]==2 and stats["flawless_wins"]==1,"Conversion/cleanse/loss observation incorrect")
	var unit: UnitState=UnitState.new();unit.max_hp=60;unit.hp=60;unit.reset_achievement_observation();unit.shield=100
	unit.tick_shield_decay(10)
	check(unit.combat_totals["blocked"]==0,"Shield decay counted as defense")
	DamageResolver.apply_fixed_damage(unit,15)
	check(unit.combat_totals["blocked"]==15,"Actual shield block was not recorded")
	engine.dispose()
	Game.settings["developer_mode"]=true
	var readonly_run: RunState=run_with(["quick_slash"])
	var original: String=JSON.stringify(readonly_run.to_dict())
	engine=engine_for(readonly_run)
	check(JSON.stringify(readonly_run.to_dict())==original,"Private battle initialization mutated its caller's run")
	Game.settings["developer_mode"]=false
	check(not engine.build_summary()["achievement_eligible"],"Disabling developer mode made an already-started debug battle eligible")
	engine.dispose()
	Game.current_run=readonly_run
	Game.settings["developer_mode"]=true
	Game.set_developer_mode_enabled(false)
	check(bool(readonly_run.achievement_state.get("excluded",false)),"A legacy developer run became eligible after turning the mode off")
	test_remaining_metrics(meta)
	test_progression(meta)
	test_game_result_wiring()
	print("ADVANCED_ACHIEVEMENTS_SMOKE_OK checks=%d groups=18 tiers=58 real effects/eligibility/dedup/save/progression"%checks)
	get_tree().quit()


func test_game_result_wiring() -> void:
	Game.meta_progress=fresh_meta();Game.settings["developer_mode"]=false
	Game.start_new_run("balanced",4242)
	var run: RunState=Game.current_run
	run.player_cards.assign(["echo_cast","quick_slash"]);run.equipped_cards.assign(run.player_cards)
	var engine: RealtimeBattleEngine=engine_for(run)
	play(engine,"echo_cast");play(engine,"quick_slash")
	var summary: Dictionary=finish(engine)
	Game.complete_battle(summary)
	check(Game.meta_progress["achievement_stats"]["echo_uses"]==1,"Game result flow did not persist actual battle metrics")
	var stats: Dictionary=Game.meta_progress["achievement_stats"].duplicate(true)
	var gold: int=run.gold
	Game.complete_battle(summary)
	check(Game.meta_progress["achievement_stats"]==stats and run.gold==gold,"Repeated game result awarded stats or gold again")
	var saved: SaveData=Game.build_save_data("reward")
	var restored: SaveData=SaveData.from_dict(saved.to_dict().duplicate(true))
	check(restored.meta_progress["achievement_stats"]==stats and not restored.current_run["achievement_state"]["battle_receipts"].is_empty(),"Full save lost advanced metrics or result receipts")
	engine.dispose()


func test_remaining_metrics(meta: Dictionary) -> void:
	var run: RunState=run_with(["reserve_focus","reserve_siphon","reserve_reload","quick_slash","auto_turret"])
	var engine: RealtimeBattleEngine=engine_for(run)
	for id: String in ["reserve_focus","reserve_siphon","reserve_reload","quick_slash","auto_turret"]:play(engine,id)
	for index: int in 300:engine.update(.1)
	var summary: Dictionary=finish(engine)
	var values: Dictionary=summary["analysis"]["achievement_metrics"]["player"]
	check(values["max_reservation_kinds"]==3,"Distinct matching reservation kinds were not combined")
	check(values["reservation_uses"]==3,"Wrong reservation attribution or per-hit duplication")
	check(values["auto_resolutions"]>=5,"Real recursive turret resolutions were not recorded")
	check(AdvancedAchievementProgress.record_battle(meta,run,summary),"Automatic battle not credited")
	check(meta["achievement_stats"]["max_auto_resolutions"]==values["auto_resolutions"],"Automatic casts were summed across battles rather than taking the best")
	engine.dispose()
	for remaining: float in [1.25,.75]:
		run=run_with(["interrupt_shot"]);engine=engine_for(run,"brute")
		for runtime: CardRuntimeState in engine.battle_state.enemy.card_runtime_states:
			if runtime.card_id=="heavy_swing":engine.request_use_card("enemy",runtime.runtime_id);break
		var target: ActiveCardInstance=engine.battle_state.get_active_instances_for_side("enemy")[0]
		engine.update(target.get_remaining(engine.battle_state.battle_time)-remaining)
		check(engine.interrupt_instance(target),"Real cast interruption failed")
		var expected: int=1 if remaining<=1.0 else 0
		check(int(engine.build_summary()["analysis"]["achievement_metrics"]["player"]["clutch_interrupts"])==expected,"Late-interrupt threshold/failed-attempt accounting incorrect")
		engine.dispose()
	run=run_with(["quick_slash"]);engine=engine_for(run)
	engine.battle_state.enemy.hp=10
	DamageResolver.apply_damage(engine.battle_state.player,engine.battle_state.enemy,99999)
	check(engine.battle_state.player.achievement_max_hit==10,"Overkill inflated the single-hit record")
	engine.dispose()
	var p1: RunState=run_with(["quick_slash"]);var p2: RunState=run_with(["quick_slash"])
	p1.arena_mode=true;p2.arena_mode=true
	engine=RealtimeBattleEngine.new();engine.setup_pvp(p1,p2);engine.set_audio_enabled(false);engine.start_battle()
	var runtime: CardRuntimeState=engine.battle_state.enemy.card_runtime_states[0]
	check(engine.request_use_card("enemy",runtime.runtime_id),"Guest-side PvP card registration failed")
	for index: int in 100:engine.update(.05)
	engine.battle_state.winner="enemy";summary=BattleStateCodec.encode_match_summary(engine.build_summary())
	check(summary.get("achievement_eligible",false),"Network result codec discarded eligibility")
	summary["control_receipt_id"]="web:test-authoritative-result"
	var online_meta: Dictionary=fresh_meta()
	check(not AdvancedAchievementProgress.record_battle(online_meta,p2,summary),"Unauthenticated PvP summary was accepted as solo")
	check(AdvancedAchievementProgress.record_battle(online_meta,p2,summary,"enemy",true),"Authenticated guest was not credited")
	check(online_meta["achievement_stats"]["actual_damage_total"]==7 and online_meta["achievement_stats"]["card_types_used"]==1,"Guest received the host's metrics")
	check(online_meta["achievement_stats"]["arena_best_streak"]==0,"Online results counted toward solo Arena streak")
	engine.dispose()


func test_progression(meta: Dictionary) -> void:
	var run: RunState=run_with(["quick_slash"])
	run.arena_mode=true
	for index: int in 4:
		var engine: RealtimeBattleEngine=engine_for(run)
		var summary: Dictionary=finish(engine)
		if index==2:summary["winner"]="draw"
		check(AdvancedAchievementProgress.record_battle(meta,run,summary),"Arena credit failed")
		engine.dispose()
	check(meta["achievement_stats"]["arena_best_streak"]==2 and run.achievement_state["arena_streak"]==1,"Arena streak did not reset on a draw")
	var engine: RealtimeBattleEngine=engine_for(run)
	var summary: Dictionary=finish(engine)
	for flag: String in ["pvp","simulation","balance_sandbox"]:
		var excluded: Dictionary=summary.duplicate(true);excluded[flag]=true
		check(not AdvancedAchievementProgress.record_battle(meta,run,excluded),"Excluded mode credited: "+flag)
	run.achievement_state["excluded"]=true
	check(not AdvancedAchievementProgress.record_battle(meta,run,summary),"Debug run credited")
	engine.dispose()
	run=run_with(["quick_slash"]);run.achievement_state["last_battle_eligible"]=true
	var node: Dictionary={"id":"hazard_test","hazard_queue":["scout","guardian"],"hazard_cleared_waves":1}
	check(not AdvancedAchievementProgress.record_hazard(meta,run,node),"Partial/withdrawn hazard credited")
	node["hazard_cleared_waves"]=2
	check(AdvancedAchievementProgress.record_hazard(meta,run,node) and not AdvancedAchievementProgress.record_hazard(meta,RunState.from_dict(run.to_dict()),node),"Hazard completion/dedup failed")
	run.run_complete=true
	check(AdvancedAchievementProgress.record_clear(meta,run) and not AdvancedAchievementProgress.record_clear(meta,run),"Normal clear credited twice")
	check(meta["achievement_stats"]["starters_cleared"]==1,"Unique starter clear not stored")
	run=run_with(["quick_slash"]);run.infinite_mode=true
	AdvancedAchievementProgress.record_infinite_step(meta,run,56);AdvancedAchievementProgress.record_infinite_step(meta,run,28)
	check(meta["achievement_stats"]["infinite_best_step"]==56,"Infinite progress was summed instead of taking the best")
	Game.begin_battle_tutorial("battle_basics")
	engine=engine_for(run);summary=finish(engine);Game.clear_battle_tutorial()
	check(not summary["achievement_eligible"] and not AdvancedAchievementProgress.record_battle(meta,run,summary),"Tutorial became eligible after leaving it")
	engine.dispose()
