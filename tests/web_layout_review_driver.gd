extends Node

var _window: JavaScriptObject
var _bridge: JavaScriptObject
var _sequence: int = 0
var _pending_frames: int = 0
var _tutorial_samples: Array[Dictionary] = []
var _feedback_samples: Array[Dictionary] = []
var _feedback_started_ms: int = -1
var _feedback_initial_audio: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_window = JavaScriptBridge.get_interface("window")
	_bridge = JavaScriptBridge.create_callback(_command)
	_window.qqLayoutCommand = _bridge
	call_deferred("_start_boot")


func _start_boot() -> void:
	var previous: Node = get_tree().current_scene
	get_tree().current_scene = null
	reparent(SceneRouter)
	var boot: Control = load("res://scenes/boot/Boot.tscn").instantiate() as Control
	get_tree().root.add_child(boot)
	get_tree().current_scene = boot
	if previous != null and previous != self:
		previous.queue_free()


func _command(arguments: Array) -> void:
	var payload: Dictionary = JSON.parse_string(String(arguments[0]))
	_sequence = int(payload.get("sequence", 0))
	if String(payload.get("action", "")) == "guest_snapshot":
		_window.qqGuestSnapshot = JSON.stringify(SaveManager.read_profile("guest"))
	elif String(payload.get("action", "")) == "legacy_guest_pending_fixture":
		var owner: String = String(AccountSession.snapshot["user"]["id"])
		SaveManager.activate_profile("guest", SaveData.new().to_dict())
		Game.meta_progress["points"] = 321
		SaveManager.save_game("hub")
		_window.qqLegacyGuest = JSON.stringify(SaveManager.guest_identity())
		SaveManager.activate_profile(owner)
		SaveManager.profile_meta["guest_import_pending"] = true
		SaveManager.save_game("hub")
		CloudSession._epoch += 1
		CloudSession._transition(CloudSession._epoch, owner)
	elif String(payload.get("action", "")) == "guest_restore_fixture":
		SaveManager.activate_profile("guest", Dictionary(payload["snapshot"]))
		SaveManager.save_game("hub")
		SceneRouter.go_to_hub()
	elif String(payload.get("action", "")) == "cloud_fixture":
		if payload.has("points"): Game.meta_progress["points"] = int(payload["points"])
		if bool(payload.get("run", false)):
			Game.start_new_run("balanced", 426)
			Game.stash_active_run_for_hub()
		SaveManager.save_game(Game.current_screen_hint)
		if bool(payload.get("sync", false)): CloudSession.sync_now()
	elif String(payload.get("action", "")) == "screen":
		_open_screen(String(payload.get("screen", "hub")))
	elif String(payload.get("action", "")) == "balance_open":
		Game.settings["developer_mode"] = true
		SceneRouter.go_to_balance_lab()
	elif String(payload.get("action", "")) == "balance_focus":
		var lab: Control = get_tree().current_scene as Control
		var field: Control = lab.find_child("BalanceValue_" + String(payload["path"]).replace(".", "_"), true, false) as Control
		if field != null: (lab.find_child("BalanceEditorScroll", true, false) as ScrollContainer).ensure_control_visible(field)
	elif String(payload.get("action", "")) == "permission_fixture":
		AccountSession.enforce_web_permissions = true
		Game.settings["developer_mode"] = bool(payload.get("enabled", false))
		_open_screen(String(payload.get("screen", "settings")))
	elif String(payload.get("action", "")) == "ranked_replay":
		var smoke: Node = load("res://tests/RankedRunSmoke.tscn").instantiate()
		smoke.quit_when_done = false
		smoke.completed.connect(func(data: Dictionary) -> void: _window.qqRankedReplay = JSON.stringify(data))
		add_child(smoke)
	elif String(payload.get("action", "")) == "ranked_resume_fixture":
		RankedSession.verifying = false
		RankedSession.initialize(Dictionary(payload["ticket"]))
		var commands: Array = Array(payload["commands"]).duplicate(true)
		commands[0] = {"kind": "game", "method": "developer_add_gold", "args": [99999]}
		Game.current_run.ranking["commands"] = commands
		Game.stash_active_run_for_hub()
		SceneRouter.go_to_hub()
	elif String(payload.get("action", "")) == "content_fixture":
		var language: String = String(payload.get("language", Localization.get_language()))
		if language != Localization.get_language():
			Game.set_language(language)
		Game.current_run = null
		Game.suspended_runs.clear()
		Game.meta_progress = Database.meta_progress_template.duplicate(true)
		Game.ensure_meta_initialized()
		MetaProgressService.new().add_unlock_xp(Game.meta_progress, int(payload.get("xp", 0)))
		_open_screen(String(payload.get("screen", "library")))
	elif String(payload.get("action", "")) == "encounter_growth_fixture":
		Game.start_new_run("balanced", 4242)
		var infinite: bool = bool(payload.get("infinite", true))
		var index: int = int(payload.get("step", 29)) - 1
		var generator: MapGenerator = MapGenerator.new()
		Game.current_run.infinite_mode = infinite
		Game.current_run.map_state = generator.generate_infinite_run(4242) if infinite else generator.generate_run(4242, 4)
		while Array(Game.current_run.map_state["steps"]).size() <= index:
			generator.append_infinite_cycle(Game.current_run.map_state, 4242)
		var steps: Array = Game.current_run.map_state["steps"]
		Game.current_run.map_state["current_step"] = index
		var previous: Dictionary = steps[index - 1]["nodes"][0]
		previous["status"] = "completed"
		previous["next_ids"] = steps[index]["nodes"].map(func(node: Dictionary) -> String: return String(node["id"]))
		MapRouteGraph.unlock(Game.current_run.map_state, index)
		if infinite: InfiniteScoreResolver.new().start_fresh(Game.current_run)
		Game.settings["developer_mode"] = false
		Game.set_language("ja")
		SceneRouter.go_to_map()
	elif String(payload.get("action", "")) == "encounter_fixture":
		Game.set_language(String(payload.get("language", "ja")))
		Game.start_new_run("balanced", 4242)
		Game.settings["developer_mode"] = true
		var node_id: String = Game.developer_prepare_encounter_chain(bool(payload.get("hazard", false)))
		if bool(payload.get("single", false)):
			var location: Dictionary = Game._find_node_location(node_id)
			var node: Dictionary = Game._get_node(int(location["step_index"]), int(location["node_index"]))
			node.erase("encounter_queue")
			Game._set_node(int(location["step_index"]), int(location["node_index"]), node)
		if bool(payload.get("infinite", false)):
			Game.current_run.infinite_mode = true
			InfiniteScoreResolver.new().start_fresh(Game.current_run)
		Game.settings["developer_mode"] = false
		SceneRouter.go_to_map()
	elif String(payload.get("action", "")) == "encounter_win":
		var screen: Control = get_tree().current_scene as Control
		if screen.scene_file_path == SceneRouter.BATTLE_SCENE:
			screen.set_process(false)
			var engine: RealtimeBattleEngine = screen.get("_engine") as RealtimeBattleEngine
			engine.battle_state.winner = "player"
			engine.battle_state.battle_time = 30.0
			Game.complete_battle(engine.build_summary())
			SceneRouter.go_to_reward()
	elif String(payload.get("action", "")) == "stat_upgrade_fixture":
		Game.current_run = null
		Game.suspended_runs.clear()
		Game.meta_progress = Database.meta_progress_template.duplicate(true)
		Game.meta_progress["points"] = int(payload.get("points", 0))
		Game.ensure_meta_initialized()
		Game.meta_progress["permanent_upgrade_levels"].merge(Dictionary(payload.get("levels", {})), true)
		Game.meta_progress["permanent_bonuses"].merge(Dictionary(payload.get("awards", {})), true)
		Game.set_language(String(payload.get("language", "ja")))
		_open_screen("meta")
	elif String(payload.get("action", "")) == "achievement_fixture":
		Game.current_run = null
		Game.suspended_runs.clear()
		Game.meta_progress = Database.meta_progress_template.duplicate(true)
		Game.ensure_meta_initialized()
		Game.set_language(String(payload.get("language", "ja")))
		Game.meta_progress["achievement_stats"].merge(Dictionary(payload.get("stats", {})), true)
		Game.meta_progress["achievement_claim_counts"] = Dictionary(payload.get("claims", {})).duplicate(true)
		_open_screen("meta")
	elif String(payload.get("action", "")) == "achievement_focus":
		var screen: Control = get_tree().current_scene as Control
		var row: Control = screen.find_child("MetaAchievementFrame_" + String(payload.get("id", "")), true, false) as Control
		if row != null:
			(screen.find_child("MetaContentScroll", true, false) as ScrollContainer).ensure_control_visible(row)
	elif String(payload.get("action", "")) == "gold_spending_fixture":
		Game.current_run = null
		Game.meta_progress = Database.meta_progress_template.duplicate(true)
		Game.ensure_meta_initialized()
		Game.meta_progress["achievement_stats"]["gold_spent"] = int(payload.get("spent", 0))
		Game.meta_progress["achievement_claim_counts"]["big_spender"] = int(payload.get("claimed", 0))
		if int(payload.get("claimed", 0)) >= 4:
			Game.meta_progress["claimed_achievements"].append("big_spender")
		_open_screen("meta")
	elif String(payload.get("action", "")) == "gold_spending_focus":
		var screen: Control = get_tree().current_scene as Control
		var row: Control = screen.find_child("MetaAchievementFrame_big_spender", true, false) as Control
		var scroll: ScrollContainer = screen.find_child("MetaContentScroll", true, false) as ScrollContainer
		if row != null:
			scroll.ensure_control_visible(row)
	elif String(payload.get("action", "")) == "meta_top":
		var screen: Control = get_tree().current_scene as Control
		(screen.find_child("MetaContentScroll", true, false) as ScrollContainer).scroll_vertical = 0
	elif String(payload.get("action", "")) == "battle_simulate":
		_simulate_battle_result()
	elif String(payload.get("action", "")) == "timekeeper_advance":
		_advance_timekeeper(float(payload.get("seconds", 0.0)))
	elif String(payload.get("action", "")) == "feedback_damage":
		var battle: Control = get_tree().current_scene as Control
		battle.set_process(false)
		var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
		engine.set_audio_enabled(false)
		var stage: BattleStage3D = battle.get("_battle_stage") as BattleStage3D
		stage.configure_combatants("player", engine.battle_state.enemy.unit_id)
		engine.battle_state.player.hp = engine.battle_state.player.max_hp
		battle.call("_refresh_ui", 1.0)
		_feedback_samples.clear()
		_feedback_started_ms = Time.get_ticks_msec()
		engine.battle_state.player.hp = int(engine.battle_state.player.max_hp / 2.0)
		stage.play_battle_event({"event_type": "battle_start"})
		AudioManager.clear_play_history()
		stage.play_battle_event({"event_type": "resolve_card", "actor_id": "player", "target_id": engine.battle_state.enemy.unit_id,
			"card_id": "strike", "result": {"fully_blocked": false}})
		_feedback_initial_audio = AudioManager.get_play_history()
		battle.call("_refresh_ui", 1.0)
		_sample_feedback(battle)
	elif String(payload.get("action", "")) == "map_advance":
		var was_developer: bool = Game.is_developer_mode_enabled()
		Game.settings["developer_mode"] = true
		Game.developer_advance_map_route(String(payload.get("node_id", "")))
		Game.settings["developer_mode"] = was_developer
		var screen: Control = get_tree().current_scene as Control
		screen.set("_chapter_start", -1)
		screen.call("_refresh_ui")
	elif String(payload.get("action", "")) == "map_focus":
		var screen: Control = get_tree().current_scene as Control
		var scroll: ScrollContainer = screen.get("_steps_scroll") as ScrollContainer
		scroll.scroll_vertical = int(payload.get("scroll", 0))
	elif String(payload.get("action", "")) == "finish_score":
		get_tree().current_scene.call("_finish_score_animation")
	elif String(payload.get("action", "")) == "status_icons":
		var battle: Control = get_tree().current_scene as Control
		var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
		for id: String in ["bleed", "weak", "slow", "vulnerable"]:
			engine.battle_state.player.add_status(id, 30.0)
		battle.call("_refresh_ui", 1.0)
	elif String(payload.get("action", "")) == "bleed_fixture":
		Game.set_language(String(payload.get("language", "ja")))
		Game.settings["developer_mode"] = true
		Game.start_new_run("balanced", 4242)
		Game.developer_open_battle("scout")
		SceneRouter.go_to_battle()
	elif String(payload.get("action", "")) == "echo_fixture":
		Game.set_language(String(payload.get("language", "ja"))); Game.settings["developer_mode"] = true
		var cards: Array[String] = ["heavy_swing", "echo_cast", "quick_slash", "guard"]
		Game.developer_open_custom_battle("guardian", "balanced", cards)
		SceneRouter.go_to_battle()
	elif String(payload.get("action", "")) == "echo_control":
		var battle: Control = get_tree().current_scene as Control
		var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
		battle.set_process(false); engine.set_enemy_ai_enabled(false)
		if bool(payload.get("setup", false)): engine.battle_state.enemy.hp = 500; engine.battle_state.enemy.max_hp = 500
		if payload.has("delay"): engine.delay_active_cards("player", float(payload["delay"]), "single")
		if payload.has("seconds"): engine.update(float(payload["seconds"]))
		battle.call("_refresh_ui", 1.0)
	elif String(payload.get("action", "")) == "bleed_advance":
		var battle: Control = get_tree().current_scene as Control
		var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
		battle.set_process(false)
		if bool(payload.get("keep_alive", false)): engine.battle_state.enemy.max_hp = 500; engine.battle_state.enemy.hp = 500
		engine.start_battle()
		engine.update(float(payload.get("seconds", 6.0)))
		battle.call("_refresh_ui", 1.0)
	elif String(payload.get("action", "")) == "tutorial_start":
		_tutorial_samples.clear()
		SceneRouter.start_battle_tutorial(String(payload.get("tutorial", "battle_basics")))
	elif String(payload.get("action", "")) == "tutorial_seek":
		_seek_tutorial(String(payload.get("key", "")))
	elif String(payload.get("action", "")) == "art_preview":
		var screen: Control = get_tree().current_scene as Control
		if screen != null and screen.scene_file_path == SceneRouter.ART_LAB_SCENE:
			for entry: Dictionary in ArtCatalog.get_entries():
				if String(entry.get("asset_id", "")) == String(payload.get("asset_id", "")):
					screen.call("_open_preview", entry)
					break
	_pending_frames = 8


func _advance_timekeeper(seconds: float) -> void:
	var battle: Control = get_tree().current_scene as Control
	if battle == null or battle.scene_file_path != SceneRouter.BATTLE_SCENE:
		return
	var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
	if engine.battle_state.enemy.unit_id != "boss_timekeeper":
		return
	battle.set_process(false)
	engine.set_audio_enabled(false)
	engine.start_battle()
	var target: float = clampf(seconds, engine.battle_state.battle_time, 55.0)
	while engine.battle_state.battle_time < target - 0.001 and engine.battle_state.winner == "":
		engine.update(minf(0.05, target - engine.battle_state.battle_time))
	battle.call("_refresh_ui", 1.0)


func _seek_tutorial(key: String) -> void:
	var battle: Control = get_tree().current_scene as Control
	if battle == null or not battle.has_method("is_tutorial_mode") or not bool(battle.call("is_tutorial_mode")):
		return
	var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
	for _iteration: int in 1200:
		var step: Dictionary = battle.call("get_tutorial_step_data")
		if String(step.get("key", "")) == key:
			return
		match String(step.get("mode", "")):
			"continue": battle.call("debug_tutorial_continue")
			"queue_card":
				for runtime: CardRuntimeState in engine.battle_state.player.card_runtime_states:
					if runtime.card_id == String(step.get("card_id", "")) and runtime.can_use():
						battle.call("_on_card_requested", runtime.runtime_id)
						break
			"complete", "free_battle": return
			_: battle.call("_process_tutorial_battle", 0.1)


func _simulate_battle_result() -> void:
	var screen: Control = get_tree().current_scene as Control
	if screen == null or screen.scene_file_path != "res://scenes/battle/Battle.tscn":
		return
	var engine: RealtimeBattleEngine = screen.get("_engine")
	engine.set_audio_enabled(false)
	var bot: EnemyAI = EnemyAI.new()
	bot.side = "player"
	engine.start_battle()
	for index: int in range(5000):
		bot.update(engine, 0.05)
		engine.update(0.05)
		if engine.battle_state.winner != "":
			break


func _open_screen(screen: String) -> void:
	Game.clear_battle_tutorial()
	if screen not in ["online_bots", "online_arena"]:
		NetworkManager._clear_session(false)
	Game.settings["developer_mode"] = false
	Game.meta_progress["infinite_mode_unlocked"] = screen == "hub_infinite"
	match screen:
		"hub": SceneRouter.go_to_hub()
		"hub_continue":
			Game.start_new_run("balanced", 4242)
			Game.stash_active_run_for_hub()
			Game.start_arena_run("balanced")
			Game.stash_active_run_for_hub()
			SceneRouter.go_to_hub()
		"hub_developer":
			Game.settings["developer_mode"] = true
			SceneRouter.go_to_hub()
		"art_lab":
			Game.settings["developer_mode"] = true
			SceneRouter.go_to_art_lab()
		"balance":
			Game.start_new_run("balanced", 4242)
			Game.settings["developer_mode"] = true
			SceneRouter.go_to_balance_lab()
		"hub_infinite": SceneRouter.go_to_hub()
		"settings": SceneRouter.go_to_settings()
		"setup": SceneRouter.go_to_run_setup()
		"arena_setup": SceneRouter.go_to_run_setup(Game.RUN_SETUP_MODE_ARENA)
		"meta": SceneRouter.go_to_meta_progress()
		"library": SceneRouter.go_to_card_library()
		"tutorials": SceneRouter.go_to_battle_tutorial()
		"online": SceneRouter.go_to_online_lobby()
		"online_bots":
			NetworkManager._clear_session(false)
			NetworkManager._is_host = true
			NetworkManager._session_scope = NetworkManager.SESSION_SCOPE_ONLINE
			NetworkManager._peer = OfflineMultiplayerPeer.new()
			NetworkManager.multiplayer.multiplayer_peer = NetworkManager._peer
			NetworkManager._state = NetworkManager.ConnectionState.HOSTING
			NetworkManager._online_room_code = "BOTS04"
			NetworkManager._online_max_players = 4
			NetworkManager._profiles_by_peer[1] = NetworkManager.configure_local_player("Player", "balanced")
			NetworkManager._on_web_bots_updated([
				{"id": 1000000001, "name": "BOT 1", "starterId": "tempo"},
				{"id": 1000000002, "name": "BOT 2", "starterId": "fortress"},
				{"id": 1000000003, "name": "BOT 3", "starterId": "balanced"},
			], true, "")
			SceneRouter.go_to_online_lobby()
		"map", "map_extended":
			Game.start_new_run("balanced", 4242)
			if screen == "map_extended": Game.current_run.map_state = MapGenerator.new().generate_run(4242, 4)
			SceneRouter.go_to_map()
		"event_later", "event_saved_empty", "event_fallback":
			_open_later_event(screen)
		"online_arena":
			NetworkManager._clear_session(false)
			NetworkManager._is_host = true
			NetworkManager._session_scope = NetworkManager.SESSION_SCOPE_ONLINE
			NetworkManager._peer = OfflineMultiplayerPeer.new()
			NetworkManager.multiplayer.multiplayer_peer = NetworkManager._peer
			NetworkManager._arena_session_active = true
			NetworkManager._arena_phase = "preparation"
			NetworkManager._online_target_wins = 3
			var profiles: Dictionary = {}
			var runs: Dictionary = {}
			for id: int in [1, 2, 3, 4]:
				profiles[id] = LanProtocol.build_profile("Player %d" % id, "balanced")
				var run: RunState = LanArenaCoordinator.new().create_run(profiles[id], 4242 + id)
				run.arena_wins = id % 3
				run.arena_losses = id % 2
				runs[id] = run
			NetworkManager._profiles_by_peer = profiles
			NetworkManager._arena_runs_by_peer = runs
			NetworkManager._arena_player_peer_ids = [1, 2, 3, 4]
			NetworkManager._arena_standings = ArenaTournamentCoordinator.build_standings([1, 2, 3, 4], profiles, runs)
			NetworkManager._arena_ready_by_peer = {"1": false, "2": true, "3": false, "4": true}
			SceneRouter.go_to_arena()
		"arena":
			Game.start_arena_run("balanced")
			SceneRouter.go_to_arena()
		"battle":
			Game.start_new_run("balanced", 4242)
			Game.developer_open_battle("scout")
			SceneRouter.go_to_battle()
		"timekeeper":
			Game.settings["developer_mode"] = true
			Game.start_new_run("balanced", 4242)
			Game.current_run.max_hp = 500
			Game.current_run.player_hp = 500
			Game.developer_open_battle("boss_timekeeper")
			SceneRouter.go_to_battle()
		"reward":
			Game.start_new_run("balanced", 4242)
			Game.developer_open_reward()
			SceneRouter.go_to_reward()
		"event":
			Game.start_new_run("balanced", 4242)
			Game.developer_open_event("salvage_cache")
			SceneRouter.go_to_facility()
		"forge", "shop":
			Game.start_new_run("balanced", 4242)
			var node: Dictionary = Game._get_node(0, 0)
			node["type"] = screen
			if screen == "forge":
				node["forge_options"] = ["quick_slash", "guard", "strike"]
				Game.current_run.card_upgrades["quick_slash"] = 1
				Game.current_run.temporary_card_modifiers["quick_slash"] = {"damage": 2}
			Game._set_node(0, 0, node)
			Game.select_map_node(String(node["id"]))
			SceneRouter.go_to_facility()
		"result":
			Game.start_new_run("balanced", 4242)
			Game.developer_open_result()
			SceneRouter.go_to_result()
		"result_infinite", "result_infinite_record", "result_infinite_empty":
			Game.meta_progress["infinite_mode_unlocked"] = true
			Game.meta_progress["infinite_record"] = {"version": 1, "high_score": 0, "best_reached_step": 0}
			Game.current_run = InfiniteScoreResolver.new().build_preview_run(0 if screen == "result_infinite_empty" else 35)
			if screen != "result_infinite":
				Game.current_run.infinite_score.erase("preview")
			SceneRouter.go_to_result()
		"result_partial":
			Game.start_new_run("balanced", 4242)
			Game.current_run.run_complete = true
			Game.current_run.defeated = true
			Game.current_run.player_hp = 0
			Game.current_run.battle_history = [{"enemy_id": "scout", "node_type": "normal_battle", "battle_time": 32.0}]
			Game.current_run.map_state["current_step"] = 1
			SceneRouter.go_to_result()


func _open_later_event(mode: String) -> void:
	Database.load_all()
	Game.start_new_run("balanced", 4242)
	Game.current_run.map_state = MapGenerator.new().generate_run(4242, 4)
	var was_developer: bool = Game.is_developer_mode_enabled()
	Game.settings["developer_mode"] = true
	for index: int in 8: Game.developer_advance_map_route()
	Game.settings["developer_mode"] = was_developer
	for node: Dictionary in Game.get_current_step_data()["nodes"]:
		if node["type"] == "event" and node["status"] == "available":
			Game.select_map_node(node["id"])
			break
	if mode != "event_later":
		var node: Dictionary = Game.get_active_map_node().duplicate(true)
		node["event_id"] = ""
		node["event_choices"] = []
		var location: Dictionary = Game._get_active_node_location()
		Game._set_node(location["step_index"], location["node_index"], node)
		Game.apply_loaded_save(SaveData.from_dict(Game.build_save_data("facility").to_dict()))
		if mode == "event_fallback": Database.events.clear()
	SceneRouter.go_to_facility()


func _process(_delta: float) -> void:
	var current: Node = get_tree().current_scene
	if current != null and current.scene_file_path == SceneRouter.BATTLE_SCENE and not current.is_processing():
		current.call("_refresh_ui", 1.0)
		if _feedback_started_ms >= 0 and Time.get_ticks_msec() - _feedback_started_ms <= 450:
			call_deferred("_sample_feedback", current)
	if current != null and current.has_method("is_tutorial_mode") and bool(current.call("is_tutorial_mode")):
		var panel: TimelinePanel = current.get("_timeline_panel") as TimelinePanel
		var director: BattleTutorialDirector = current.get("_tutorial_director") as BattleTutorialDirector
		var engine: RealtimeBattleEngine = current.get("_engine") as RealtimeBattleEngine
		_tutorial_samples.append({"key": director.get_current_step_data().get("key", ""), "sliding": panel.has_pending_delay_animation(),
			"paused": director.is_time_paused(), "time": engine.battle_state.battle_time})
		if _tutorial_samples.size() > 240:
			_tutorial_samples.pop_front()
	if _pending_frames <= 0:
		return
	var cover: Control = SceneRouter.get("_transition_cover") as Control
	var scene: CanvasItem = get_tree().current_scene as CanvasItem
	if scene == null or not scene.is_inside_tree() or not scene.visible or (cover != null and cover.visible):
		return
	_pending_frames -= 1
	if _pending_frames == 0:
		_window.qqLayoutState = JSON.stringify(_inspect())


func _sample_feedback(battle: Node) -> void:
	var stage: BattleStage3D = battle.get("_battle_stage") as BattleStage3D
	var plate: BattleUnitStatus3D = stage.get_player_status_model()
	_feedback_samples.append({"ms": Time.get_ticks_msec() - _feedback_started_ms,
		"target": plate.get_hp_ratio(), "displayed": plate.get_displayed_hp_ratio(), "text": plate.get_hp_text()})


func _inspect() -> Dictionary:
	var screen: Control = get_tree().current_scene as Control
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var controls: Array[Dictionary] = []
	var result: Dictionary = {}
	if not _feedback_samples.is_empty():
		result["feedback"] = {"samples": _feedback_samples, "immediate_audio": _feedback_initial_audio, "audio": AudioManager.get_play_history()}
	if screen != null:
		if screen.scene_file_path.get_file().get_basename() == "Battle":
			var bleed_engine: RealtimeBattleEngine = screen.get("_engine") as RealtimeBattleEngine
			if bleed_engine != null and bleed_engine.battle_state != null:
				var enemy: UnitState = bleed_engine.battle_state.enemy
				var stage: BattleStage3D = screen.get("_battle_stage") as BattleStage3D
				var regions: Array[Dictionary] = []
				for region: Dictionary in stage.get_enemy_status_model().get_status_regions():
					if region["id"] != "bleed": continue
					var points: Array[Array] = []
					for point: Vector3 in region["corners"]: points.append(_point_values(stage.global_position + stage.project_world_position(point)))
					regions.append({"points": points, "tooltip": region["tooltip"]})
				var stack: Label3D = stage.get_enemy_status_model().find_child("StatusStacks3D_bleed", true, false) as Label3D
				var tip: Label = screen.find_child("WorldStatusTooltipText", true, false) as Label
				result["bleed"] = {"enemy_hp": enemy.hp, "state": enemy.get_display_statuses().get("bleed", {}), "regions": regions,
					"badge": stack.text if stack != null and stack.visible else "", "tooltip": tip.text if tip != null and tip.is_visible_in_tree() else ""}
				var hand: CardHandPanel = screen.get("_card_hand_panel") as CardHandPanel
				var hand_cards: Array[Dictionary] = []
				for runtime: CardRuntimeState in bleed_engine.battle_state.player.card_runtime_states:
					var button: CardButton = hand.get_button_for_runtime_id(runtime.runtime_id)
					if button != null: hand_cards.append({"id": runtime.card_id, "runtime": runtime.runtime_id, "rect": _rect_values(button.get_global_rect())})
				var timeline: TimelinePanel = screen.get("_timeline_panel") as TimelinePanel
				var timeline_cards: Array[Dictionary] = []
				for button: CardButton in timeline._cards:
					if button.visible: timeline_cards.append({"runtime": button.runtime_id, "repeat": button._repeat_badge.visible, "rect": _rect_values(button.get_global_rect())})
				var echo_regions: Array[Dictionary] = []
				for region: Dictionary in stage.get_player_status_model().get_status_regions():
					if region["id"] != "echo_ready": continue
					var points: Array[Array] = []
					for point: Vector3 in region["corners"]: points.append(_point_values(stage.global_position + stage.project_world_position(point)))
					echo_regions.append({"points": points, "tooltip": region["tooltip"]})
				result["echo"] = {"charges": bleed_engine.battle_state.player.repeat_charges, "hand": hand_cards, "timeline": timeline_cards,
					"enemy_hp": enemy.hp, "status_regions": echo_regions, "tooltip": tip.text if tip != null and tip.is_visible_in_tree() else "",
					"numbers": stage.get_floating_combat_text_values()}
		if screen.scene_file_path.get_file().get_basename() == "Hub":
			var history: RichTextLabel = screen.find_child("VersionHistoryContent", true, false) as RichTextLabel
			result["history"] = {"open": (screen.find_child("VersionHistoryOverlay", true, false) as Control).visible,
				"bbcode": history.text, "parsed": history.get_parsed_text(), "rect": _rect_values(history.get_global_rect()), "lines": history.get_line_count()}
		if screen.scene_file_path.get_file().get_basename() in ["MetaProgress", "CardLibrary"]:
			result["content_progress"] = Game.get_content_progress()
			result["content_pool"] = ContentPoolService.build_snapshot(Game.meta_progress)
		if screen.scene_file_path.get_file().get_basename() == "CardLibrary":
			var tabs: TabContainer = screen.get("_tabs") as TabContainer
			var bar: TabBar = tabs.get_tab_bar()
			var tab_rects: Array[Array] = []
			for index: int in tabs.get_tab_count():
				tab_rects.append(_rect_values(bar.get_global_transform() * bar.get_tab_rect(index)))
			var panel: RelicLibraryPanel = screen.get("_relics_page") as RelicLibraryPanel
			var relic_rows: Array[Dictionary] = []
			for raw_id: Variant in Dictionary(panel.get("_widgets")):
				var id: String = String(raw_id)
				var widgets: Dictionary = Dictionary(panel.get("_widgets"))[id]
				var row: Control = widgets["row"]
				var icon: RelicIcon = widgets["icon"]
				relic_rows.append({"id": id, "instance": row.get_instance_id(), "rect": _rect_values(row.get_global_rect()),
					"icon": _rect_values(icon.get_global_rect()), "tooltip": icon.tooltip_text,
					"rarity": Database.get_relic(id).rarity, "tags": Database.get_relic(id).tags})
			var card_rows: Array[Dictionary] = []
			for raw_id: Variant in Dictionary(screen.get("_card_widgets")):
				var widgets: Dictionary = Dictionary(screen.get("_card_widgets"))[raw_id]
				card_rows.append({"id": String(raw_id), "instance": (widgets["row"] as Control).get_instance_id()})
			var popup: Control = get_tree().root.find_child("RelicTooltipPopup", true, false) as Control
			result["library"] = {"active": tabs.current_tab, "tabs": tab_rects, "titles": [tabs.get_tab_title(0), tabs.get_tab_title(1)],
				"ready": screen.call("is_content_ready"), "card_rows": card_rows, "relics": relic_rows,
				"card_rarity": screen.get("_selected_rarity"), "card_search": screen.get("_search_text"),
				"relic_rarity": panel.get("_rarity"), "relic_tag": panel.get("_tag"), "relic_search": panel.get("_search"),
				"relic_matching": Array(panel.get("_filtered_entries")).size(), "relic_empty": (panel.get("_empty_label") as Label).visible,
				"relic_scroll": _rect_values((panel.get("_scroll") as Control).get_global_rect()),
				"tooltip_visible": popup != null and popup.is_visible_in_tree(),
				"relic_h_scroll": ((panel.get("_scroll") as ScrollContainer).get_h_scroll_bar()).visible}
			for option: OptionButton in [screen.get("_rarity_filter"), screen.get("_tag_filter"), panel.get("_rarity_filter"), panel.get("_tag_filter")]:
				var menu: PopupMenu = option.get_popup()
				if menu.visible:
					result["library"]["option_menu"] = {"name": String(option.name), "focus": menu.get_focused_item(), "count": menu.item_count}
		if screen.scene_file_path.get_file().get_basename() == "BalanceLab":
			var draft: BalanceDraft = screen.get("draft") as BalanceDraft
			var fields: Dictionary = {}
			for path: String in Dictionary(screen.get("_field_widgets")):
				var spin: SpinBox = Dictionary(screen.get("_field_widgets"))[path] as SpinBox
				fields[path] = {"value": spin.value, "rect": _rect_values(spin.get_global_rect()), "edit_rect": _rect_values(spin.get_line_edit().get_global_rect()), "text": spin.get_line_edit().text}
			var entries: Array[Dictionary] = []
			for widget: Dictionary in Dictionary(screen.get("_catalog_widgets")).values():
				var button: Button = widget["button"] as Button
				if button.visible: entries.append({"kind": widget["kind"], "id": widget["id"], "rect": _rect_values(button.get_global_rect())})
			var run: RunState = Game.current_run
			var trial: BalanceTrialRunner = screen.get("runner") as BalanceTrialRunner
			result["balance"] = {"ready": screen.call("is_content_ready"), "kind": screen.get("_kind"), "selected": screen.get("_selected"), "fields": fields, "entries": entries,
				"config": screen.call("_config"),
				"document": draft.document(), "reports": trial.reports, "running": trial.running, "progress": trial.progress(),
				"game_hash": JSON.stringify({"run": run.to_dict() if run != null else {}, "meta": Game.meta_progress}).sha256_text(),
				"published_damage": Database.get_card("quick_slash").effects[0]["amount"], "relics": screen.get("_test_relics")}
			var grade_tabs: TabBar = screen.find_child("BalanceGradeTabs", true, false) as TabBar
			var tab_rects: Array[Dictionary] = []
			for tier: int in grade_tabs.tab_count: tab_rects.append({"tier": tier, "rect": _rect_values(grade_tabs.get_global_transform() * grade_tabs.get_tab_rect(tier))})
			var grade_previews: Dictionary = {}
			for tier: int in range(CardUpgradeResolver.MAX_TIER + 1):
				var text: RichTextLabel = screen.find_child("BalancePreviewGrade%d" % tier, true, false) as RichTextLabel
				if text != null: grade_previews[str(tier)] = text.get_parsed_text()
			result["balance"]["grade_tabs"] = tab_rects
			result["balance"]["editor_grade"] = grade_tabs.current_tab
			result["balance"]["grade_previews"] = grade_previews
			var manual: BalanceBattlePreview = screen.get("_manual") as BalanceBattlePreview
			var bulk: OptionButton = screen.find_child("BalanceBulkField", true, false) as OptionButton
			if bulk != null:
				var focused: int = bulk.get_popup().get_focused_item()
				result["balance"]["bulk"] = {"path": bulk.get_selected_metadata(), "amount": (screen.find_child("BalanceBulkAmount", true, false) as SpinBox).value,
					"focused_path": bulk.get_item_metadata(focused) if focused >= 0 else ""}
				var targets: Array[Dictionary] = []
				for target: Node in screen.find_children("BalanceBulkTarget_*", "CheckBox", true, false):
					var checkbox: CheckBox = target as CheckBox
					targets.append({"id": checkbox.get_meta("target_id"), "selected": checkbox.button_pressed, "disabled": checkbox.disabled, "visible": checkbox.is_visible_in_tree(), "rect": _rect_values(checkbox.get_global_rect())})
				var count: Label = screen.find_child("BalanceBulkTargetCount", true, false) as Label
				result["balance"]["bulk"].merge({"targets": targets, "selected": count.get_meta("selected_count"), "eligible": count.get_meta("eligible_count"),
					"preview": (screen.find_child("BalanceBulkPreview", true, false) as TextEdit).text,
					"apply_disabled": (screen.find_child("BalanceBulkApply", true, false) as Button).disabled})
			if manual != null and manual.engine != null:
				result["balance"]["manual"] = {"time": manual.engine.battle_state.battle_time, "shield": manual.engine.battle_state.player.shield,
					"damage": manual.engine._get_card_def("player", "quick_slash").effects[0]["amount"], "sandbox": manual.engine.build_summary(false).get("balance_sandbox", false)}
		if screen.scene_file_path.get_file().get_basename() == "MetaProgress":
			var upgrades: Array[Dictionary] = []
			for entry: Dictionary in Game.get_meta_stat_upgrade_entries():
				var widgets: Dictionary = Dictionary(screen.get("_upgrade_widgets")).get(entry["id"], {})
				if widgets.is_empty(): continue
				var item: Dictionary = entry.duplicate()
				for part: String in ["frame", "level", "total", "bar", "button"]:
					item[part + "_rect"] = _rect_values((widgets[part] as Control).get_global_rect())
				item["instance"] = (widgets["frame"] as Control).get_instance_id()
				item["text"] = (widgets["button"] as Button).text
				item["level_text"] = (widgets["level"] as Label).text
				item["disabled"] = (widgets["button"] as Button).disabled
				upgrades.append(item)
			result["stat_upgrades"] = {"points": Game.get_meta_points(), "cards": upgrades, "gold_spent": Game.meta_progress["achievement_stats"]["gold_spent"]}
			var grid: GridContainer = screen.find_child("MetaAchievementBox", true, false) as GridContainer
			var cards: Array[Dictionary] = []
			for frame: Control in grid.get_children():
				var id: String = String(frame.name).trim_prefix("MetaAchievementFrame_")
				var widgets: Dictionary = Dictionary(screen.get("_achievement_widgets")).get(id, {})
				var parts: Dictionary = {}
				for key: String in ["icon", "name", "description", "reward", "progress", "progress_bar", "button"]:
					parts[key] = _rect_values((widgets[key] as Control).get_global_rect())
				var icon: TextureRect = widgets["icon"] as TextureRect
				cards.append({"id": id, "instance": frame.get_instance_id(), "rect": _rect_values(frame.get_global_rect()), "parts": parts,
					"icon_path": icon.texture.resource_path if icon.texture != null else ""})
			result["achievements"] = {"columns": grid.columns, "cards": cards}
			var progress_entries: Dictionary = {}
			for entry: Dictionary in Game.get_meta_achievement_entries():
				var id: String = String(entry["id"])
				var widgets: Dictionary = Dictionary(screen.get("_achievement_widgets")).get(id, {})
				if widgets.is_empty(): continue
				progress_entries[id] = {"progress": (widgets["progress"] as Label).text, "stage": (widgets["stage"] as Label).text,
					"name": entry["name"], "target": entry["target"], "current": entry["current"], "count": entry["claimed_count"], "tiers": entry["tier_count"],
					"disabled": (widgets["button"] as Button).disabled, "points": Game.meta_progress["points"]}
			result["achievement_progress"] = progress_entries
			var name_label: Label = screen.find_child("AchievementName_big_spender", true, false) as Label
			if name_label != null:
				var progress: Label = screen.find_child("AchievementProgress_big_spender", true, false) as Label
				var bar: ProgressBar = screen.find_child("AchievementProgressBar_big_spender", true, false) as ProgressBar
				var button: Button = screen.find_child("ClaimAchievement_big_spender", true, false) as Button
				result["gold_spending"] = {"name": name_label.text, "progress": progress.text, "progress_rect": _rect_values(progress.get_global_rect()),
					"bar_rect": _rect_values(bar.get_global_rect()), "button_rect": _rect_values(button.get_global_rect()), "disabled": button.disabled,
					"value": bar.value, "max": bar.max_value, "claimed": Game.meta_progress["achievement_claim_counts"].get("big_spender", 0)}
		if screen.scene_file_path.get_file().get_basename() == "Facility":
			var event_data: Dictionary = Game.get_active_event_data()
			var previews: Array[Dictionary] = []
			for preview: Node in screen.find_children("ChoiceCardPreview_*", "", true, false):
				var card: CardButton = preview as CardButton
				previews.append({"id": String(card.name), "rect": _rect_values(card.get_global_rect()),
					"text": card._simple_tooltip_text, "bbcode": card._simple_tooltip_bbcode})
			var tooltip: RichTextLabel = get_tree().root.find_child("CardTooltipText", true, false) as RichTextLabel
			result["facility"] = {"area": Game.get_active_map_node().get("area", 0), "step": Game.get_current_step_index(),
				"choices": event_data.get("choices", []), "id": event_data.get("id", ""),
				"previews": previews, "type": Game.get_active_facility_type(),
				"tooltip": tooltip.get_parsed_text() if tooltip != null and tooltip.is_visible_in_tree() else "",
				"gold": Game.current_run.gold, "hp": Game.current_run.player_hp,
				"cards": Game.current_run.player_cards.duplicate(), "relics": Game.current_run.relics.duplicate()}
		if screen.scene_file_path.get_file().get_basename() == "Map":
			var canvas: MapRouteCanvas = screen.get("_route_canvas") as MapRouteCanvas
			var map_nodes: Array[Dictionary] = []
			for step: Dictionary in canvas._steps:
				for node: Dictionary in step.get("nodes", []):
					var button: MapNodeButton = canvas._buttons[String(node["id"])]
					map_nodes.append({"id": node["id"], "status": node["status"], "type": node["type"], "next": node["next_ids"],
						"rect": _rect_values(button.get_global_transform() * Rect2(Vector2.ZERO, button.size)), "disabled": button.disabled, "name": button._name_label.text})
			var map_scroll: ScrollContainer = screen.get("_steps_scroll") as ScrollContainer
			result["map"] = {"nodes": map_nodes, "edges": canvas._edges.size(), "chapter": screen.get("_chapter_start"),
				"step": Game.get_current_step_index(), "scroll": map_scroll.scroll_vertical, "scroll_rect": _rect_values(map_scroll.get_global_rect()),
				"traveling": canvas._traveling, "current": canvas._current_id,
				"history": (screen.get("_history_overlay") as Control).visible, "drawer": (screen.get("_loadout_button") as Button).visible,
				"loadout_open": (screen.get("_loadout_overlay") as Control).visible}
		_collect_controls(screen, controls, false)
		var captions: Array[String] = []
		_collect_captions(screen, captions)
		result["captions"] = captions
		var intel: EnemyEncounterDialog = screen.find_child("EnemyEncounterDialog", true, false) as EnemyEncounterDialog
		if intel != null and intel.visible:
			var data: Dictionary = intel.preview_data
			var unit: UnitState = data["unit"] as UnitState
			var cards: Array[Dictionary] = []
			for card: CardButton in intel._card_buttons:
				if card.visible: cards.append({"rect": _rect_values(card.get_global_rect()), "tooltip": card.tooltip_text})
			result["encounter"] = {"index": data["index"], "total": data["total"], "enemy": data["enemy_id"],
				"type": data["node_type"], "hp": unit.hp, "attack": unit.attack, "speed": unit.speed,
				"counter": intel._counter.text, "name": intel._enemy_name.text,
				"rect": _rect_values(intel._frame.get_global_rect()), "model_rect": _rect_values(intel._model.get_global_rect()),
				"model_ready": intel._model.is_preview_ready(), "model_id": intel._model.get_selected_starter_id(),
				"cards": cards}
		if Game.current_run != null:
			result["encounter_progress"] = {"step": Game.get_current_step_index(), "active": Game.current_run.map_state.get("active_node_id", ""),
				"cleared": EncounterSeries.cleared(Game.get_active_map_node()), "hint": Game.current_screen_hint, "pending": Game.pending_enemy_id}
	result.merge({
		"sequence": _sequence,
		"screen": screen.scene_file_path.get_file().get_basename() if screen != null else "",
		"viewport": [viewport_rect.size.x, viewport_rect.size.y],
		"window": [get_window().size.x, get_window().size.y],
		"aspect": get_window().content_scale_aspect,
		"controls": controls,
		"developer_allowed": AccountSession.can_use_developer_mode(),
		"developer_enabled": Game.is_developer_mode_enabled(),
		"ranked_active": RankedSession.active(),
		"cloud_state": CloudSession.state,
		"cloud_profile": SaveManager.active_profile,
		"cloud_points": Game.get_meta_points(),
		"cloud_dirty": bool(SaveManager.profile_meta.get("dirty", false)),
		"cloud_revision": int(SaveManager.profile_meta.get("revision", 0)),
		"ranked_score": int(InfiniteScoreResolver.new().calculate(Game.current_run).get("total_score", 0)) if RankedSession.active() else 0,
	})
	if screen != null:
		if screen.has_method("is_tutorial_mode") and bool(screen.call("is_tutorial_mode")):
			var director: BattleTutorialDirector = screen.get("_tutorial_director") as BattleTutorialDirector
			var overlay: BattleTutorialOverlay = screen.get("_tutorial_overlay") as BattleTutorialOverlay
			var timeline: TimelinePanel = screen.get("_timeline_panel") as TimelinePanel
			result["tutorial"] = {"step": director.get_current_step_data(), "paused": director.is_time_paused(),
				"focus": _rect_values(overlay.get("_target_rect") as Rect2), "dim": overlay.get("_dim_background"),
				"sliding": timeline.has_pending_delay_animation(), "samples": _tutorial_samples.duplicate(true)}
		var deck: CardHandPanel = screen.find_child("EquippedDeck", true, false) as CardHandPanel
		if deck == null:
			deck = screen.find_child("ArenaEquippedDeck", true, false) as CardHandPanel
		if deck != null:
			var cards: Array[Dictionary] = []
			for card: CardButton in deck._buttons:
				if not card.visible:
					continue
				var remove: Button = card.get_node_or_null("DeckUnequipButton") as Button
				cards.append({"id": card.runtime_id, "rect": _rect_values(card.get_global_rect()), "close": remove.visible if remove != null else false,
					"close_rect": _rect_values(remove.get_global_rect()) if remove != null else [], "disabled": remove.disabled if remove != null else true})
			var rows: Array[Dictionary] = []
			var inventory: LoadoutInventoryGrid = screen.get("_inventory_box") as LoadoutInventoryGrid
			for frame: Control in inventory.get_children():
				var actions: HBoxContainer = frame.find_child("*LoadoutActions*", true, false) as HBoxContainer
				if actions != null:
					var slot: Control = frame.find_child("HoverActionsSlot", true, false) as Control
					var preview: CardButton = frame.find_child("*LoadoutPreview*", true, false) as CardButton
					rows.append({"name": String(frame.name), "rect": _rect_values(frame.get_global_rect()), "actions": actions.visible,
						"buttons": actions.get_child_count(), "equip_rect": _rect_values((actions.get_child(0) as Control).get_global_rect()),
						"minimum": _point_values(frame.get_combined_minimum_size()), "actions_minimum": _point_values(actions.get_combined_minimum_size()),
						"slot_minimum": _point_values(slot.custom_minimum_size) if slot != null else [],
						"preview_rect": _rect_values(preview.get_global_rect()) if preview != null else []})
			var inventory_scroll: ScrollContainer = inventory.get_parent() as ScrollContainer
			result["loadout"] = {"cards": cards, "rows": rows, "columns": inventory.columns,
				"inventory_rect": _rect_values(inventory.get_global_rect()), "scroll_rect": _rect_values(inventory_scroll.get_global_rect()),
				"horizontal_bar": inventory_scroll.get_h_scroll_bar().visible, "scroll_x": inventory_scroll.scroll_horizontal}
		if screen.scene_file_path.get_file().get_basename() == "CardLibrary":
			var search: LineEdit = screen.find_child("LibrarySearch", true, false) as LineEdit
			var empty: Label = screen.find_child("LibraryEmptyNotice", true, false) as Label
			var library_data: Dictionary = Dictionary(result.get("library", {}))
			library_data.merge({"cards": Dictionary(screen.get("_card_widgets")).keys(), "search": search.text, "empty": empty.visible})
			result["library"] = library_data
		elif screen.scene_file_path.get_file().get_basename() == "OnlineLobby":
			result["lobby"] = {"connected": NetworkManager.is_session_connected(), "capacity": NetworkManager.get_player_capacity()}
		elif screen.scene_file_path.get_file().get_basename() == "ArtLab":
			var art_grid: GridContainer = screen.find_child("ArtLabGrid", true, false) as GridContainer
			result["art"] = {"catalog": Array(screen.get("_catalog")).size(), "tiles": art_grid.get_child_count(), "columns": art_grid.columns,
				"preview": screen.find_child("ArtPreviewOverlay", true, false) != null}
		elif screen.scene_file_path.get_file().get_basename() == "RunResult":
			result["score"] = screen.get("_summary_data")
			var bars: Array[Dictionary] = []
			for row: Dictionary in Array(screen.get("_category_rows")):
				var bar: ProgressBar = row["bar"]
				bars.append({"id": row["id"], "value": bar.value, "max": bar.max_value, "label": (row["score_label"] as Label).text})
			var record: Label = screen.find_child("ResultInfiniteRecord", true, false) as Label
			result["score_ui"] = {"total": (screen.find_child("ResultTotalScore", true, false) as Label).text,
				"reach": (screen.find_child("ResultRankLabel", true, false) as Label).text, "bars": bars,
				"record": record.text if record != null else ""}
		var stage: BattleStage3D = screen.find_child("BattleStage3D", true, false) as BattleStage3D
		if stage != null:
			var status_regions: Array[Dictionary] = []
			for region: Dictionary in stage.get_player_status_model().get_status_regions():
				var bounds: Rect2 = Rect2()
				var first: bool = true
				for corner: Vector3 in region["corners"]:
					var point: Vector2 = stage.global_position + stage.project_world_position(corner)
					bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
					first = false
				status_regions.append({"id": region["id"], "rect": _rect_values(bounds)})
			var popup: Control = stage.find_child("WorldStatusTooltip", true, false) as Control
			var popup_label: Label = stage.find_child("WorldStatusTooltipText", true, false) as Label
			result["status_icons"] = {"regions": status_regions, "tooltip_visible": popup != null and popup.visible,
				"tooltip_text": popup_label.text if popup_label != null else ""}
			var player_status: BattleUnitStatus3D = stage.get_player_status_model()
			var enemy_status: BattleUnitStatus3D = stage.get_enemy_status_model()
			result["battle"] = {
				"authored_field": stage.is_using_authored_field(),
				"authored_player": stage.get_combat_actor("player").is_using_authored_model(),
				"authored_enemy": stage.get_combat_actor("enemy").is_using_authored_model(),
				"detail_counts": stage.get_environment_detail_counts(),
				"field": _rect_values(stage.get_global_rect()),
				"player_status": _point_values(stage.project_world_position(player_status.global_position)),
				"enemy_status": _point_values(stage.project_world_position(enemy_status.global_position)),
				"status_corners": _project_status_corners(stage, player_status) + _project_status_corners(stage, enemy_status),
			}
			var engine: RealtimeBattleEngine = screen.get("_engine") as RealtimeBattleEngine
			result["battle_control"] = {"receipt": engine._control_receipt_id, "metrics": engine.analysis.timeline_control.duplicate(true),
				"stats": Dictionary(Game.meta_progress["achievement_stats"]).duplicate()}
			if engine.battle_state.enemy.unit_id == "boss_timekeeper":
				var panel: TimelinePanel = screen.get("_timeline_panel") as TimelinePanel
				var forecast: Label = panel.find_child("TimekeeperForecast", true, false) as Label
				var charge_regions: Array[Dictionary] = []
				for region: Dictionary in enemy_status.get_status_regions():
					var bounds: Rect2 = Rect2()
					var first: bool = true
					for corner: Vector3 in region["corners"]:
						var point: Vector2 = stage.global_position + stage.project_world_position(corner)
						bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
						first = false
					charge_regions.append({"id": region["id"], "rect": _rect_values(bounds)})
				var cards: Array[Dictionary] = []
				for card: CardButton in panel._cards:
					if card.visible:
						cards.append({"id": card._art_rect.texture.resource_path.get_file().get_basename(),
							"rect": _rect_values(card.get_global_transform() * Rect2(Vector2.ZERO, card.size)), "z": card.z_index, "scale": card.scale.x,
							"seconds": card._meta_label.text})
				result["timekeeper"] = {"time": engine.battle_state.battle_time,
					"multiplier": engine.battle_state.enemy.next_attack_multiplier, "hp": engine.battle_state.player.hp,
					"vulnerable": engine.battle_state.player.has_status("vulnerable"),
					"forecast": forecast.text, "forecast_visible": forecast.visible, "forecast_rect": _rect_values(forecast.get_global_rect()),
					"regions": charge_regions, "cards": cards,
					"horizon": panel._rendered_scale_horizon,
					"ticks": panel._scale_row.get_children().map(func(label: Label) -> String: return label.text),
					"art": [CardButton._load_card_texture("timekeeper_final_strike").resource_path, CardButton._load_card_texture("timekeeper_amplify").resource_path, CardButton._load_card_texture("timekeeper_time_mark").resource_path]}
			var outcome: BattleResultAnalysisPanel = screen.find_child("BattleResultAnalysisPanel", true, false) as BattleResultAnalysisPanel
			if outcome != null:
				result["outcome"] = {"visible": outcome.visible, "details": outcome._details_modal.visible, "title": outcome._title.text,
					"finished": stage.has_battle_end_presentation_finished(), "samples": outcome._hp_chart._samples.size()}
	return result


func _project_status_corners(stage: BattleStage3D, status: BattleUnitStatus3D) -> Array[Array]:
	var corners: Array[Array] = []
	for x_sign: float in [-1.0, 1.0]:
		for y_sign: float in [-1.0, 1.0]:
			var world: Vector3 = status.to_global(Vector3(BattleUnitStatus3D.PANEL_SIZE.x * x_sign * 0.5, BattleUnitStatus3D.PANEL_SIZE.y * y_sign * 0.5, 0.0))
			corners.append(_point_values(stage.global_position + stage.project_world_position(world)))
	return corners


func _collect_captions(node: Node, captions: Array[String]) -> void:
	if node is Control and (not node.is_visible_in_tree() or node.get_viewport() != get_viewport()): return
	if node is Label: captions.append(node.text)
	elif node is RichTextLabel: captions.append(node.get_parsed_text())
	for child: Node in node.get_children(): _collect_captions(child, captions)


func _collect_controls(node: Node, controls: Array[Dictionary], in_scroll: bool) -> void:
	var control: Control = node as Control
	if control != null and (not control.is_visible_in_tree() or control.get_viewport() != get_viewport()):
		return
	var scrolling: bool = in_scroll or node is ScrollContainer
	if control != null and (control is Container or control is BaseButton or control is LineEdit or control is SpinBox or control is ProgressBar):
		controls.append({
			"name": String(control.name), "class": control.get_class(), "icon": control.get_meta("semantic_icon", ""),
			"rect": _rect_values(control.get_global_rect()), "scroll": scrolling,
		})
	for child: Node in node.get_children():
		_collect_controls(child, controls, scrolling)


func _rect_values(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _point_values(point: Vector2) -> Array[float]:
	return [point.x, point.y]
