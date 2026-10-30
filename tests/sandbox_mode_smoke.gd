extends Node

var checks: int = 0


func check(value: bool, message: String) -> void:
	checks+=1
	if not value:push_error("Sandbox: "+message);get_tree().quit(1);assert(value,message)


func _ready() -> void:
	Database.load_all();Game.ensure_meta_initialized();Game.settings["developer_mode"]=false;Game.clear_battle_tutorial()
	call_deferred("_run")


func progress() -> Dictionary:
	return {"run":Game.current_run.to_dict() if Game.current_run!=null else {},"suspended":Game.suspended_runs.duplicate(true),"meta":Game.meta_progress.duplicate(true),"hint":Game.current_screen_hint,"pending":Game.pending_enemy_id,"rewards":Game.reward_options.duplicate()}


func _run() -> void:
	Game.start_new_run("balanced",4242)
	var original: Dictionary=progress()
	var definitions: String=JSON.stringify(Database.get_card("quick_slash").to_dict())
	var config: Dictionary=SandboxConfig.defaults()
	config["player"].merge({"max_hp":100,"hp":37,"attack":12,"speed":8,"shield":17,"slots":5,"cards":[{"id":"quick_slash","tier":0},{"id":"quick_slash","tier":5}]},true)
	config["enemy"].merge({"max_hp":500,"hp":500,"attack":4,"speed":6,"shield":0,"slots":7},true)
	config["rules"]["fatigue"]=false;config["rules"]["enemy_ai"]=false
	var before: String=JSON.stringify(config)
	var engine: RealtimeBattleEngine=RealtimeBattleEngine.new();engine.set_audio_enabled(false)
	check(engine.setup_playground(config),"setup requires developer privileges or failed")
	check(JSON.stringify(config)==before and progress()==original,"setup mutated its input or real progress")
	check(engine.battle_state.player.hp==37 and engine.battle_state.player.attack==12 and engine.battle_state.player.shield==17 and engine.battle_state.player.active_slot_max==5,"player stats were not applied")
	check(engine.battle_state.enemy.max_hp==500 and engine.battle_state.enemy.attack==4 and engine.battle_state.enemy.active_slot_max==7,"enemy stats were not applied")
	check(engine._get_card_def("player","quick_slash","player_0").name==Database.get_card("quick_slash").name,"base copy grade changed")
	check(engine._get_card_def("player","quick_slash","player_1").name.ends_with("+5"),"separate copy lost its grade")
	var context: Dictionary=CardTooltipResolver.build_context("quick_slash",engine.get_run_for_side("player"),engine.battle_state.player,"player_1")
	check((context["card"] as CardDef).name.ends_with("+5") and int((context["card"] as CardDef).effects[0]["amount"])==21,"live tooltip ignored per-copy grade or attack")
	check(engine.request_use_card("player","player_0") and engine.request_use_card("player","player_1"),"duplicates could not be registered")
	engine.update(4.0)
	var damages: Array[int]=[]
	for event: Dictionary in engine.battle_state.battle_events:
		if event.get("event_type")=="resolve_card":damages.append(int(event["result"]["metrics"]["damage"]))
	damages.sort();check(damages==[16,21],"two copies did not resolve at distinct grades: "+str(damages))
	engine.update(100.0)
	check(engine.battle_state.fatigue_waves==0,"fatigue-off still queued neutral cards")
	engine.battle_state.winner="player"
	var summary: Dictionary=engine.build_summary()
	check(summary["sandbox"] and not summary["achievement_eligible"],"sandbox result was eligible")
	Game.complete_battle(summary)
	check(progress()==original,"sandbox result changed a normal run, rewards or achievements")
	check(JSON.stringify(Database.get_card("quick_slash").to_dict())==definitions,"shared card definition was changed")
	engine.dispose()
	var malformed: Dictionary=SandboxConfig.defaults();malformed["player"]["max_hp"]=INF;malformed["player"]["cards"]=[{"id":"unknown","tier":9},{"id":"quick_slash","tier":{}}];malformed["rules"]["power"]={}
	var safe: Dictionary=SandboxConfig.normalize(malformed)
	check(safe["player"]["max_hp"]>0 and safe["player"]["cards"].size()==1 and safe["player"]["cards"][0]["tier"]==0 and safe["rules"]["power"]==0,"malformed preset was not normalized")
	var limited: Dictionary=SandboxConfig.defaults();limited["rules"]["ignore_cost"]=false;limited["player"]["loadout_limit"]=1
	check(not engine.setup_playground(limited),"loadout limit was silently ignored")
	config=SandboxConfig.defaults();config["rules"]["enemy_ai"]=false;config["rules"]["fatigue"]=false
	config["player"]["cards"]=[{"id":"timekeeper_amplify","tier":4},{"id":"auto_turret","tier":5}]
	config["enemy"]["max_hp"]=10000;config["enemy"]["hp"]=10000
	check(engine.setup_playground(config) and engine.request_use_card("player","player_0"),"boss-exclusive card unavailable in sandbox")
	engine.update(4.0)
	check(engine.request_use_card("player","player_1"),"turret not usable")
	for index: int in 30:engine.update(1.0)
	var automatic: Array[ActiveCardInstance]=engine.battle_state.get_active_instances_for_side("player")
	check(automatic.size()>0 and engine._get_card_def("player","auto_turret",automatic[0].runtime_id).name.ends_with("+5"),"recursive self copies lost their grade")
	check(engine.battle_state.player.sandbox_card_tiers.size()<=2+automatic.size(),"completed automatic grades leaked indefinitely")
	engine.dispose()
	_boundaries(original)
	SandboxSession.get_draft()
	check(SandboxSession.save_preset("test preset",config),"preset save failed")
	SaveManager.flush_requested_save()
	check(SandboxSession.presets().has("test preset") and progress()==original,"saving setup changed real progress")
	await _ui(config,original)
	SandboxSession.active=false
	check(SandboxSession.save_preset("test preset",SandboxConfig.defaults()),"preset overwrite failed")
	SandboxSession.delete_preset("test preset")
	check(not SandboxSession.presets().has("test preset"),"preset deletion failed")
	var saved_settings: Dictionary=Game.settings.duplicate(true)
	SandboxSession.owner_profile="another-profile"
	check(not SandboxSession.begin(config) and not SandboxSession.save_preset("wrong owner",config),"stale account could start or save")
	SandboxSession.save_last(config);SandboxSession.delete_preset("missing")
	check(Game.settings==saved_settings,"stale account changed settings")
	SandboxSession._check_owner()
	check(not SandboxSession.active and SandboxSession.draft.is_empty() and SandboxSession.owner_profile=="","profile transition retained private data")
	print("SANDBOX_MODE_SMOKE_OK checks=%d private sessions/stats/per-copy-grade/tooltips/exclusive/recursion/presets/UI/save isolation"%checks)
	get_tree().quit()


func _boundaries(original: Dictionary) -> void:
	var config: Dictionary=SandboxConfig.defaults()
	config["rules"].merge({"enemy_ai":false,"fatigue":false},true)
	config["player"]["cards"]=[{"id":"quick_slash","tier":0},{"id":"quick_slash","tier":5}]
	config["player"]["relics"]=["fourth_reserve_rack"]
	config["enemy"]["relics"]=["fourth_reserve_rack"]
	var engine: RealtimeBattleEngine=RealtimeBattleEngine.new();engine.set_audio_enabled(false)
	check(engine.setup_playground(config),"boundary setup failed")
	check(engine.battle_state.player.active_slot_max==4 and engine.battle_state.enemy.active_slot_max==4,"relic slots missing or applied twice")
	engine.add_battle_card_modifier("player","quick_slash","grade",1)
	check(engine._get_card_def("player","quick_slash","player_0").name.ends_with("+1") and engine._get_card_def("player","quick_slash","player_1").name.ends_with("+5"),"battle growth ignored per-copy bases")
	config["player"]["cards"]=[{"id":"quick_slash","tier":5}]
	engine.setup_playground(config)
	check(engine.empower_cards("player","quick_slash",{"stat":"grade","amount":1,"scope":"self"})==0,"max-grade card reported growth")
	config["player"]["relics"]=["grade_staircase"]
	config["player"]["cards"]=[{"id":"quick_slash","tier":0},{"id":"quick_slash","tier":1},{"id":"quick_slash","tier":2},{"id":"quick_slash","tier":3}]
	config["enemy"].merge({"max_hp":10000,"hp":10000},true)
	engine.setup_playground(config)
	for index: int in 4:
		check(engine.request_use_card("player","player_"+str(index)),"grade sequence commit failed")
		engine.update(4)
	check(engine.battle_state.relic_runtime_state["player"].get("grade_staircase_used",false),"grade-based relic ignored instance grades")
	config["rules"]["power"]=3
	engine.setup_playground(config)
	check(engine.battle_state.enemy.max_hp>10000 and engine.battle_state.enemy.attack>int(config["enemy"]["attack"]),"infinite strength not applied")
	config["rules"].merge({"power":0,"immortal_enemy":true},true)
	config["enemy"].merge({"max_hp":1,"hp":1,"relics":[]},true)
	engine.setup_playground(config);engine.request_use_card("player","player_0");engine.update(4)
	check(engine.battle_state.winner=="" and engine.battle_state.enemy.hp==1,"immortal target ended battle")
	config["enemy_id"]="boss_timekeeper";config["rules"]["enemy_ai"]=true
	config["enemy"]["cards"]=[{"id":"quick_slash","tier":2}]
	engine.setup_playground(config);engine.start_battle();engine.update(.1)
	check(engine.battle_state.get_active_instances_for_side("enemy").size()==1,"boss AI with custom deck did not fall back")
	engine.setup(Game.current_run,"scout")
	check(not engine.public_sandbox and engine.battle_state.player.sandbox_card_tiers.is_empty(),"normal battle retained sandbox state")
	check(not engine.request_use_card("player","timekeeper_amplify"),"boss-exclusive privilege escaped")
	check(progress()==original,"boundaries mutated normal progression")
	engine.dispose()


func _ui(config: Dictionary, original: Dictionary) -> void:
	var setup: Control=load(SceneRouter.SANDBOX_SCENE).instantiate() as Control;add_child(setup)
	for frame: int in 8:await get_tree().process_frame
	check(setup.find_child("SandboxStart",true,false)!=null and setup.find_children("SandboxModel_*","SubViewportContainer",true,false).size()==2,"setup missing full editors/model previews")
	var spin: SpinBox=setup.find_child("SandboxStat_player_attack",true,false) as SpinBox
	spin.get_line_edit().text="17";spin.get_line_edit().text_changed.emit("17")
	check(setup.get("data")["player"]["attack"]==17,"typing did not update setup immediately")
	setup.call("_open_catalog","player","card")
	for frame: int in 16:await get_tree().process_frame
	var search: LineEdit=setup.find_child("SandboxCatalogSearch",true,false) as LineEdit
	search.text="echo_cast";search.text_changed.emit("echo_cast")
	for frame: int in 4:await get_tree().process_frame
	var pick: CardButton=setup.find_child("SandboxPick_echo_cast",true,false) as CardButton
	check(pick!=null,"filtered icon catalog missing card")
	var count: int=setup.get("data")["player"]["cards"].size();pick.card_requested.emit("echo_cast")
	check(setup.get("data")["player"]["cards"].size()==count+1,"catalog card input did not append a copy")
	setup.call("_close_catalog");setup.queue_free()
	await get_tree().process_frame
	config=SandboxConfig.defaults();config["player"]["cards"]=[{"id":"quick_slash","tier":0},{"id":"quick_slash","tier":5}];config["rules"]["enemy_ai"]=false;config["rules"]["fatigue"]=false;config["rules"]["field"]="rift_gallery"
	check(SandboxSession.begin(config),"session begin failed")
	var battle: Control=load(SceneRouter.BATTLE_SCENE).instantiate() as Control;add_child(battle)
	for frame: int in 5:await get_tree().process_frame
	battle.set_process(false)
	check(battle.get("_sandbox_mode") and battle.find_child("SandboxBattleDock",true,false)!=null,"normal battle UI did not enter sandbox")
	var engine: RealtimeBattleEngine=battle.get("_engine") as RealtimeBattleEngine
	var dock: SandboxBattleDock=battle.get("_sandbox_dock") as SandboxBattleDock
	engine.sandbox_options["player_ai"]=true
	dock.process_battle(.1)
	check(engine.battle_state.battle_time==0 and engine.battle_state.active_instances.is_empty(),"player AI started before the start button or card input")
	engine.sandbox_options["player_ai"]=false
	dock.advance(.1)
	var time: float=engine.battle_state.battle_time;dock.process_battle(1.0)
	check(is_equal_approx(engine.battle_state.battle_time,time),"pause did not stop battle time")
	check((battle.get("_battle_stage") as BattleStage3D).get_environment_context()["id"]=="rift_gallery","selected environment ignored")
	check(progress()==original,"battle UI queried or overwrote normal progress")
	battle.queue_free();await get_tree().process_frame
