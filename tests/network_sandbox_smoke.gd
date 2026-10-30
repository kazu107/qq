extends Node

var checks: int = 0


func check(value: bool, message: String) -> void:
	checks+=1
	if not value:push_error(message);get_tree().quit(1);assert(value,message)


func progress() -> String:
	return JSON.stringify({"run":Game.current_run.to_dict() if Game.current_run!=null else {},"suspended":Game.suspended_runs,"meta":Game.meta_progress,"hint":Game.current_screen_hint})


func _ready() -> void:
	Database.load_all();Game.ensure_meta_initialized();Game.settings["developer_mode"]=false;Game.start_new_run("balanced",4242)
	call_deferred("_run")


func _run() -> void:
	var original: String=progress()
	var side: Dictionary=SandboxConfig.side_from_starter()
	side["cards"]=[{"id":"quick_slash","tier":0},{"id":"quick_slash","tier":5},{"id":"timekeeper_amplify","tier":5}]
	var config: Dictionary=NetworkSandboxConfig.match_config(side,side,{"fatigue":false})
	var engine: RealtimeBattleEngine=RealtimeBattleEngine.new();engine.set_audio_enabled(false)
	check(engine.setup_network_playground(config,"Alice","Bob"),"Network sandbox setup failed")
	check(engine.public_sandbox and engine.is_pvp_mode() and not engine.build_summary(false)["achievement_eligible"],"Mode or eligibility lost")
	check(engine.recording.frames[0]["player"]["display_name"]=="Alice" and engine.recording.frames[0]["player"]["sandbox_card_tiers"]["player_1"]==5,"Initial replay lost names or individual Grades")
	check(not engine.request_use_card("player","player_0"),"Card bypassed countdown")
	engine.start_battle()
	check(engine.request_use_card("player","player_2"),"Boss card blocked")
	engine.update(4)
	check(engine.recording.frames[-1]["player"]["sandbox_card_tiers"]["player_1"]==5,"Later replay frame lost individual Grades")
	var state: BattleState=BattleStateCodec.decode(BattleStateCodec.encode(engine.battle_state,true,true))
	check(state.player.sandbox_card_tiers["player_1"]==5,"Per-copy Grades not synchronized")
	check((CardTooltipResolver.build_context("quick_slash",engine.get_run_for_side("player"),state.player,"player_1")["card"] as CardDef).name.ends_with("+5"),"Guest tooltip grade wrong")
	var summary: Dictionary=BattleStateCodec.encode_match_summary(engine.build_summary(false))
	check(summary["sandbox"] and not summary["achievement_eligible"],"Network summary omitted exclusion")
	for index: int in NetworkSandboxConfig.MAX_ACTIVE:
		var entry: ActiveCardInstance=ActiveCardInstance.new();entry.instance_id=100+index;entry.owner_side="player";entry.card_id="quick_slash";entry.runtime_id="player_auto_"+str(index);entry.scheduled_time=1000;engine.battle_state.active_instances.append(entry)
	check(not NetworkSandboxConfig.advance(engine,.1),"Safety card limit did not stop simulation")
	check(var_to_bytes(BattleStateCodec.encode(engine.battle_state,true,true)).size()<60000,"Bounded sandbox snapshot exceeded packet budget")
	engine.battle_state.active_instances.clear()
	Game.complete_battle(summary);check(progress()==original,"Network result changed normal progress")
	var malformed: Dictionary=SandboxConfig.normalize({"enemy_id":{},"player":{"visual":[],"cards":[{"id":{}},{"id":"guard","tier":[]}],"relics":[{}]},"rules":{"field":{}}})
	check(malformed["player"]["cards"].size()==1,"Malformed IDs were not rejected")
	for i: int in 80:side["cards"].append({"id":"quick_slash","tier":99})
	check(NetworkSandboxConfig.side(side)["cards"].size()==16,"Online card cap lost")
	NetworkManager.set_process(false);NetworkManager._is_host=true;NetworkManager._online_game_mode="sandbox";NetworkManager._arena_session_active=true;NetworkManager._arena_session_id="sandbox-native";NetworkManager._arena_phase="preparation"
	NetworkManager._arena_player_peer_ids=[1,2,3,4];NetworkManager._sandbox_revision=1
	NetworkManager._sandbox_rules=NetworkSandboxConfig.rules({"fatigue":false})
	for id: int in [1,2,3,4]:
		NetworkManager._sandbox_configs[str(id)]=SandboxConfig.side_from_starter()
		NetworkManager._profiles_by_peer[id]=LanProtocol.build_profile("P"+str(id),"balanced")
		NetworkManager._arena_ready_by_peer[str(id)]=false
	var update: Dictionary={"target":2,"side":SandboxConfig.side_from_starter("turret"),"session_id":"sandbox-native","revision":1}
	check(not NetworkManager._apply_sandbox_setup_action(3,"sandbox_edit",update),"Guest edited another player")
	check(not NetworkManager._apply_sandbox_setup_action(1,"sandbox_edit",update),"Host ignored opponent-edit permission")
	update["target"]=1;update["rules"]={"edit_opponents":true,"fatigue":false}
	check(NetworkManager._apply_sandbox_setup_action(1,"sandbox_edit",update),"Host edit failed")
	check(NetworkManager._sandbox_revision==2,"Revision not advanced")
	check(not NetworkManager._apply_sandbox_setup_action(1,"set_ready",{"ready":true,"session_id":"sandbox-native","revision":1}),"Stale ready accepted")
	check(not NetworkManager._apply_sandbox_setup_action(1,"set_ready",{"ready":true,"session_id":"old-session","revision":2}),"Wrong session ready accepted")
	check(NetworkManager._apply_sandbox_setup_action(2,"set_ready",{"ready":true,"session_id":"sandbox-native","revision":2}),"Fresh ready rejected")
	update.merge({"target":2,"revision":2},true);update.erase("rules")
	check(NetworkManager._apply_sandbox_setup_action(1,"sandbox_edit",update),"Host permission not honored")
	check(not NetworkManager._arena_ready_by_peer["2"],"Edited player remained ready")
	NetworkManager._arena_phase="battle"
	NetworkManager._parallel_match_contexts={"a":{"match_id":"a","engine":engine,"countdown_finished":true,"viewer_peer_ids":[],"snapshot_elapsed":0.0,"payload":{"match_id":"a","player_name":"A","enemy_name":"B","sandbox_config":config},"finished":false}}
	check(NetworkManager.sandbox_match_control("pause","a",1),"Shared pause failed")
	var time: float=engine.battle_state.battle_time
	NetworkManager._process_parallel_matches(.5);check(is_equal_approx(time,engine.battle_state.battle_time),"Paused host battle advanced")
	check(NetworkManager.sandbox_match_control("step","a",.1),"Shared step failed")
	check(is_equal_approx(time+.1,engine.battle_state.battle_time),"Shared step did not advance exactly")
	NetworkManager._is_host=false
	check(not NetworkManager.sandbox_match_control("heal","a"),"Guest gained shared controls")
	NetworkManager._is_host=true
	var setup: Control=load(SceneRouter.NETWORK_SANDBOX_SCENE).instantiate() as Control;add_child(setup)
	for frame: int in 5:await get_tree().process_frame
	check(setup.find_child("SandboxViewOpponent",true,false)!=null and setup.find_child("SandboxReadyRoster",true,false)!=null,"Network editor missing roster/peer selection")
	setup.queue_free();await get_tree().process_frame
	check(progress()==original,"Network editor or controls modified real progress")
	NetworkManager._clear_session(false)
	check(NetworkManager.get_online_game_mode()=="arena" and NetworkManager._sandbox_configs.is_empty(),"Room cleanup leaked Sandbox state")
	print("NETWORK_SANDBOX_SMOKE_OK checks=%d"%checks);get_tree().quit()
