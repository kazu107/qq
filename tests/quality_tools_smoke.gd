extends Node

var _failures: Array[String] = []


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	_test_preset_persistence()
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 123)
	var original: Array[String] = run.equipped_cards.duplicate()
	_check(DeckPresetService.apply(run, original), "Owned starter preset rejected")
	_check(not DeckPresetService.apply(run, ["not_a_card"]), "Invalid card accepted")
	_check(not DeckPresetService.apply(run, []), "Empty deck accepted")
	_check(not DeckPresetService.apply(run, ["quick_slash", "quick_slash", "quick_slash"]), "Missing copies accepted")
	_check(run.equipped_cards == original, "Rejected preset partially changed loadout")
	var arena: LanArenaCoordinator = LanArenaCoordinator.new()
	_check(bool(arena.apply_action(run, "apply_deck", {"cards": original}).get("accepted", false)), "Network preset rejected")
	_check(not bool(arena.apply_action(run, "apply_deck", {"cards": "bad"}).get("accepted", false)), "Network malformed preset accepted")
	var old_limit: int = run.loadout_limit
	run.loadout_limit = 0
	_check(not DeckPresetService.apply(run, original), "Over-budget preset accepted")
	run.loadout_limit = old_limit
	var diag: NetworkDiagnostics = NetworkDiagnostics.new()
	diag.received({"match_id": "A", "sequence": 1}, true)
	diag.received({"match_id": "A", "sequence": 4}, true)
	diag.received({"match_id": "A", "sequence": 3}, false)
	diag.received({"match_id": "B", "sequence": 1}, true)
	var stats: Dictionary = diag.snapshot()
	_check(int(stats["gaps"]) == 2 and int(stats["stale"]) == 1, "Diagnostics sequence accounting")
	for i in range(2200):
		diag.sent({"i": i})
	_check(diag.samples.size() <= NetworkDiagnostics.MAX_SAMPLES, "Diagnostics grows unbounded")
	var simulation: BattleSimulation = BattleSimulation.new()
	simulation.setup(run, "scout", 180.0, 0.25)
	while not simulation.finished:
		simulation.advance(100)
	var summary: Dictionary = simulation.result()
	_check(float(summary["battle_time"]) > 0 and not bool(summary["unresolved"]), "Simulation never finished")
	_check(not Array(summary["analysis"]["cards"]).is_empty(), "No per-card analysis")
	var before_hp: int = run.player_hp
	_check(run.equipped_cards == original and before_hp == run.max_hp, "Simulation changed live run")
	var replay: Dictionary = ReplayData.from_summary(summary).to_dict()
	_check(int(replay["format_version"]) == 2 and not replay["summary"].has("battle_events"), "Replay duplicated event stream")
	_check(ReplayData.from_dict(replay).to_dict() == replay, "Replay transfer round trip changed data")
	_check(not Array(summary["visual_replay"]["frames"]).is_empty(), "No visual frames")
	var saved_summary: Dictionary = Game.last_battle_summary
	Game.last_battle_summary = summary
	_check(not Dictionary(Game.build_save_data("hub").settings["last_battle_summary"]).has("visual_replay"), "Replay frames inflate normal autosaves")
	Game.last_battle_summary = saved_summary
	_check(float(BattleRecording.frame_at(summary["visual_replay"]["frames"], 0.0)["time"]) == 0, "Missing initial frame")
	_check(not Array(summary["visual_replay"]["frames"][0]["player"].get("runtime_states", [])).is_empty(), "Initial loadout lost after first queued card")
	_check(not BattleStateCodec.encode_match_summary(summary).has("visual_replay"), "Visual frames leaked into live network packets")
	_check(BattleStateCodec.encode_match_summary(summary).has("analysis"), "Network final summary loses analytics")
	var again: BattleSimulation = BattleSimulation.new()
	again.setup(run, "scout", 180.0, 0.25, false)
	while not again.finished:
		again.advance(100)
	_check(again.engine.battle_state.winner == String(summary["winner"]) and is_equal_approx(again.engine.battle_state.battle_time, float(summary["battle_time"])), "Simulation is not reproducible")
	again.dispose()
	var capped: BattleSimulation = BattleSimulation.new()
	capped.setup(run, "guardian", 1.0)
	capped.advance(100)
	_check(capped.finished and bool(capped.result()["unresolved"]) and capped.engine.battle_state.winner == "", "Simulation cap changes victory rules")
	capped.dispose()
	var visual: ReplayVisualPlayer = ReplayVisualPlayer.new()
	add_child(visual)
	visual.load_replay(replay)
	visual.seek(1.0)
	visual.step_resolution()
	_check(visual._time > 1.0 and not visual._playing, "Replay stepping failed")
	visual.seek(0.0)
	_check(visual._stage.get_pending_event_count() == 0, "Seeking retained stale effects")
	visual.load_replay({"summary": {}, "battle_events": []})
	_check(visual._play_button.disabled, "Legacy replay should show fallback")
	visual.queue_free()
	var analysis_panel: BattleResultAnalysisPanel = BattleResultAnalysisPanel.new()
	add_child(analysis_panel)
	analysis_panel.show_result(summary, "player", false, true)
	_check(analysis_panel.visible, "Battle result analysis panel did not open")
	analysis_panel.queue_free()
	var tutorial_scene: PackedScene = load("res://scenes/tutorial/BattleTutorial.tscn") as PackedScene
	_check(tutorial_scene != null, "Battle tutorial scene is missing")
	if tutorial_scene != null:
		var tutorial: Node = tutorial_scene.instantiate()
		add_child(tutorial)
		_check(tutorial.get_node_or_null("BattleTutorialButton") == null, "Tutorial scene instantiated invalid hub state")
		tutorial.queue_free()
	for id: String in ["guardian", "boss_timekeeper", "boss_paradox_core", "boss_axiom_breaker", "boss_eternity_zero"]:
		var profile: Dictionary = Database.get_battle_visual_profile(id)
		_check(ResourceLoader.exists(String(profile.get("model_scene", ""))), "Missing enemy model " + id)
		var model: PackedScene = load(String(profile["model_scene"])) as PackedScene
		var instance: Node = model.instantiate()
		var skeleton: Skeleton3D = instance.find_child("*Skeleton*", true, false) as Skeleton3D
		_check(skeleton != null and skeleton.get_bone_count() == 18, "Invalid enemy skeleton " + id)
		instance.free()
		var actor: BattleActor3D = BattleActor3D.new()
		actor.configure("enemy", id, profile)
		add_child(actor)
		actor.set_process(false)
		_check(actor.is_using_authored_model(), "Enemy fell back to procedural model " + id)
		var source: Skeleton3D = actor.get_skeleton()
		var target: Skeleton3D = actor.get_authored_skeleton()
		var tree: AnimationTree = actor.get_animation_tree()
		var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		for clip: String in BattleAnimationCatalog.get_clip_ids():
			for sample: float in [0.0, 0.33, 0.66, 1.0]:
				playback.start(StringName(clip), true)
				tree.advance(BattleAnimationCatalog.get_clip_duration(clip) * sample)
				source.force_update_all_bone_transforms()
				actor.call("_sync_authored_pose")
				for bone in range(source.get_bone_count()):
					var target_bone: int = target.find_bone(source.get_bone_name(bone))
					_check(target_bone >= 0 and source.get_bone_global_pose(bone).is_equal_approx(target.get_bone_global_pose(target_bone)), "Enemy pose mismatch: " + id + "/" + clip)
		actor.free()
	simulation.dispose()
	await get_tree().process_frame
	if _failures.is_empty():
		print("QUALITY_TOOLS_SMOKE_OK presets, atomic network validation, bounded diagnostics, simulation, analysis, replay, 5 enemy rigs")
	else:
		for failure in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_preset_persistence() -> void:
	var existed: bool = FileAccess.file_exists(SaveManager.SAVE_PATH)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH) if existed else PackedByteArray()
	var settings: Dictionary = Game.settings.duplicate(true)
	Game.settings["deck_presets"] = []
	_check(DeckPresetService.save_preset("Test", ["quick_slash"]), "Preset save failed")
	_check(DeckPresetService.save_preset("Test", ["guard"]), "Preset replacement failed")
	_check(DeckPresetService.list_presets().size() == 1, "Same-name preset was duplicated")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.SAVE_PATH))
	_check(saved["settings"]["deck_presets"][0]["cards"] == ["guard"], "Preset composition not serialized")
	for i in range(1, DeckPresetService.MAX_PRESETS):
		_check(DeckPresetService.save_preset("Test%d" % i, ["guard"]), "Preset capacity reached too early")
	_check(not DeckPresetService.save_preset("Overflow", ["guard"]), "Preset limit not enforced")
	DeckPresetService.delete_preset("Test")
	_check(DeckPresetService.list_presets().size() == 19, "Preset deletion failed")
	Game.settings = settings
	if existed:
		FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE).store_buffer(bytes)
	else:
		DirAccess.remove_absolute(SaveManager.SAVE_PATH)
