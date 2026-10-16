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
	if String(payload.get("action", "")) == "screen":
		_open_screen(String(payload.get("screen", "hub")))
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
		if screen.scene_file_path.get_file().get_basename() == "MetaProgress":
			var grid: GridContainer = screen.find_child("MetaAchievementBox", true, false) as GridContainer
			var cards: Array[Dictionary] = []
			for frame: Control in grid.get_children():
				var id: String = String(frame.name).trim_prefix("MetaAchievementFrame_")
				var widgets: Dictionary = Dictionary(screen.get("_achievement_widgets")).get(id, {})
				var parts: Dictionary = {}
				for key: String in ["name", "description", "reward", "progress", "progress_bar", "button"]:
					parts[key] = _rect_values((widgets[key] as Control).get_global_rect())
				cards.append({"id": id, "instance": frame.get_instance_id(), "rect": _rect_values(frame.get_global_rect()), "parts": parts})
			result["achievements"] = {"columns": grid.columns, "cards": cards}
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
			result["facility"] = {"area": Game.get_active_map_node().get("area", 0), "step": Game.get_current_step_index(),
				"choices": event_data.get("choices", []), "id": event_data.get("id", ""),
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
	result.merge({
		"sequence": _sequence,
		"screen": screen.scene_file_path.get_file().get_basename() if screen != null else "",
		"viewport": [viewport_rect.size.x, viewport_rect.size.y],
		"window": [get_window().size.x, get_window().size.y],
		"aspect": get_window().content_scale_aspect,
		"controls": controls,
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
