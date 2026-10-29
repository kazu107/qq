extends Node

const NEW_IDS: Array[String] = ["infinite_score_collector", "timeline_delayer", "timeline_accelerator", "cast_breaker"]
const FINITE_IDS: Array[String] = ["deep_push", "deck_expander", "relic_archivist", "starter_collector"]
var _checks: int = 0
var _service: MetaProgressService = MetaProgressService.new()
var _engines: Array[RealtimeBattleEngine] = []
var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _exit_tree() -> void:
	for engine: RealtimeBattleEngine in _engines: engine.dispose()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error("Achievement expansion: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _fresh() -> Dictionary:
	var meta: Dictionary = Database.meta_progress_template.duplicate(true)
	_service.ensure_defaults(meta)
	return meta


func _entry(meta: Dictionary, id: String) -> Dictionary:
	for entry: Dictionary in _service.build_achievement_entries(meta):
		if entry["id"] == id: return entry
	return {}


func _engine(relics: Array[String] = []) -> RealtimeBattleEngine:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.relics = relics
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.set_audio_enabled(false)
	engine.setup(run, "scout")
	engine.set_enemy_ai_enabled(false)
	_engines.append(engine)
	return engine


func _fixture_summary(receipt: String) -> Dictionary:
	return {"control_receipt_id": receipt, "winner": "player", "analysis": {"timeline_control": {
		"player": {"delay_seconds": 10.125, "advance_seconds": 0.375, "interrupts": 2},
		"enemy": {"delay_seconds": 1.5, "advance_seconds": 2.5, "interrupts": 3}}}}


func _run() -> void:
	_test_tiers()
	_test_control()
	_test_recording()
	_test_infinite()
	await _test_ui()
	if _failed:
		get_tree().quit(1)
		return
	print("ACHIEVEMENT_EXPANSION_SMOKE_OK checks=%d" % _checks)
	get_tree().quit()


func _test_tiers() -> void:
	_check(Database.get_all_achievement_ids().size() == 48, "achievement groups missing")
	var stages: int = 0
	for id: String in Database.get_all_achievement_ids():
		var definition: Dictionary = Database.get_achievement(id)
		var tiers: Array = definition["tiers"]
		stages += tiers.size()
		if NEW_IDS.has(id):
			_check(tiers.size() == 12, "new achievements require twelve tiers")
		elif not FINITE_IDS.has(id) and int(definition.get("tracking_version", 0)) != 1:
			var original_count: int = tiers.size() - (8 if id == "victory_milestones" else 6)
			_check(original_count >= 4, "existing achievement extension missing")
			var legacy: Dictionary = _fresh()
			legacy["claimed_achievements"] = [id]
			legacy["achievement_claim_counts"] = {id: original_count}
			_service.ensure_defaults(legacy)
			var entry: Dictionary = _entry(legacy, id)
			_check(entry["claimed_count"] == original_count and not entry["claimed"], "completed old tiers hid new tiers: " + id)
			legacy["achievement_stats"][entry["stat"]] = entry["target"]
			var bonuses: Dictionary = legacy["permanent_bonuses"].duplicate()
			_check(_service.claim_achievement(legacy, id), "new tier cannot be claimed: " + id)
			_check(legacy["permanent_bonuses"] == bonuses and _entry(legacy, id)["claimed_count"] == original_count + 1, "old permanent reward was regranted: " + id)
			legacy["achievement_claim_counts"] = {}
			_service.ensure_defaults(legacy)
			_check(_entry(legacy, id)["claimed_count"] == definition["legacy_claim_tier_count"], "very old claim marker migration failed: " + id)
		for index: int in tiers.size():
			var tier: Dictionary = tiers[index]
			_check(int(tier["condition"]["value"]) > 0 and not Array(tier["rewards"]).is_empty(), "invalid tier target/reward")
			if index > 0 and tiers[index - 1]["condition"]["stat"] == tier["condition"]["stat"]:
				_check(int(tier["condition"]["value"]) > int(tiers[index - 1]["condition"]["value"]), "thresholds must grow")
	_check(stages == 354, "total stage count is incorrect")
	for id: String in NEW_IDS:
		var meta: Dictionary = _fresh()
		for tier: Dictionary in Database.get_achievement(id)["tiers"]:
			meta["achievement_stats"][tier["condition"]["stat"]] = int(tier["condition"]["value"]) - 1
			_check(not _service.claim_achievement(meta, id), "early claim accepted")
			_service.increment_achievement_stat(meta, String(tier["condition"]["stat"]))
			_check(_service.claim_achievement(meta, id), "threshold claim failed")
			_check(not _service.claim_achievement(meta, id), "duplicate/new tier claim accepted too early")
		_check(_entry(meta, id)["claimed"], "last tier did not complete")


func _test_control() -> void:
	var engine: RealtimeBattleEngine = _engine()
	_check(engine.request_use_card("player", "player_0"), "cannot prepare player card")
	_check(engine.request_use_card("enemy", "enemy_0") and engine.request_use_card("enemy", "enemy_1"), "cannot prepare two enemy cards")
	var own: ActiveCardInstance = engine.battle_state.get_active_instances_for_side("player")[0]
	own.scheduled_time = 0.375
	_check(engine.haste_active_cards("player", 20.0, "all") == 1, "haste target missing")
	engine.haste_active_cards("player", 20.0, "all")
	_check(is_equal_approx(float(engine.analysis.timeline_control["player"]["advance_seconds"]), 0.375), "haste counted configured rather than actual time")
	engine.delay_active_cards("enemy", 0.125, "all", "player")
	_check(is_equal_approx(float(engine.analysis.timeline_control["player"]["delay_seconds"]), 0.25), "multi-target delay seconds not summed")
	engine.delay_active_cards("player", 0.75, "single", "enemy")
	_check(is_equal_approx(float(engine.analysis.timeline_control["enemy"]["delay_seconds"]), 0.75), "enemy delay was credited to player")
	var enemy_cards: Array[ActiveCardInstance] = engine.battle_state.get_active_instances_for_side("enemy")
	enemy_cards[0].interruptible = true
	enemy_cards[1].interruptible = false
	_check(engine.interrupt_active_card("enemy", "all_interruptible") == 1, "successful interrupt missing")
	_check(not engine.interrupt_instance(enemy_cards[0]), "removed instance interrupted twice")
	_check(engine.interrupt_active_card("enemy", "all_interruptible") == 0 and int(engine.analysis.timeline_control["player"]["interrupts"]) == 1, "failed interrupts were counted")
	for mode: String in ["stop", "reverse"]:
		var before: float = float(engine.analysis.timeline_control["player"]["delay_seconds"])
		var scheduled: float = enemy_cards[1].scheduled_time
		engine.apply_timeline_flow("player", {"mode": mode, "target_side": "enemy", "duration": 0.5, "speed": 1.0})
		for frame: int in 50: engine._tick_timeline_flows(0.01)
		_check(is_equal_approx(float(engine.analysis.timeline_control["player"]["delay_seconds"]) - before, enemy_cards[1].scheduled_time - scheduled), "continuous flow tracking mismatch")
	var no_source: float = float(engine.analysis.timeline_control["player"]["delay_seconds"])
	engine.delay_active_cards("enemy", 10.0, "single")
	_check(is_equal_approx(no_source, float(engine.analysis.timeline_control["player"]["delay_seconds"])), "unattributed developer shift was credited")
	var relic_engine: RealtimeBattleEngine = _engine(["terminal_bell"])
	relic_engine.request_use_card("enemy", "enemy_0")
	relic_engine.battle_state.get_active_instances_for_side("enemy")[0].interruptible = true
	for hit: int in 3: relic_engine.delay_active_cards("enemy", 0.1, "single", "player")
	_check(int(relic_engine.analysis.timeline_control["player"]["interrupts"]) == 1, "relic interrupt missing")
	engine.battle_state.winner = "enemy"
	var summary: Dictionary = engine.build_summary(false)
	_check(BattleStateCodec.encode_match_summary(summary)["analysis"]["timeline_control"] == engine.analysis.timeline_control, "Web result lost control metrics")
	_check(ReplayData.from_summary(summary).to_dict()["summary"]["analysis"]["timeline_control"] == engine.analysis.timeline_control, "replay lost metrics")
	_check(summary["control_receipt_id"] != relic_engine.build_summary(false)["control_receipt_id"], "battle receipt IDs must be unique")


func _test_recording() -> void:
	var meta: Dictionary = _fresh()
	var summary: Dictionary = _fixture_summary("offline-test")
	_check(_service.record_battle_control(meta, summary), "finished control progress not recorded")
	_check(meta["achievement_stats"]["timeline_delay_ms"] == 10125 and meta["achievement_stats"]["timeline_advance_ms"] == 375 and meta["achievement_stats"]["cards_interrupted"] == 2, "fractional progress lost or wrong side")
	_check(not _service.record_battle_control(meta, summary), "result duplicated")
	_check(not _service.record_battle_control(meta, summary, "spectator", "spectator"), "spectator credited")
	_check(not _service.record_battle_control(meta, {"analysis": summary["analysis"]}, "player", "unfinished"), "unfinished battle credited")
	_check(_service.record_battle_control(meta, summary, "enemy", "guest-result"), "guest perspective rejected")
	_check(meta["achievement_stats"]["timeline_delay_ms"] == 11625 and meta["achievement_stats"]["cards_interrupted"] == 5, "guest counted other player's progress")
	Game.meta_progress = meta
	var save: SaveData = SaveData.from_dict(Game.build_save_data("hub").to_dict())
	Game.meta_progress = _fresh()
	Game.apply_loaded_save(save)
	_check(not _service.record_battle_control(Game.meta_progress, summary), "save/load lost duplicate protection")
	NetworkManager._clear_session(false)
	NetworkManager._local_participant_role = LanProtocol.ROLE_PLAYER
	var network_result: Dictionary = _fixture_summary("network")
	network_result.merge({"match_id": "metrics-host", "player_peer_id": 1, "enemy_peer_id": 2})
	var before: int = int(Game.meta_progress["achievement_stats"]["timeline_delay_ms"])
	NetworkManager._apply_match_finished(network_result)
	NetworkManager._apply_match_finished(network_result)
	_check(Game.meta_progress["achievement_stats"]["timeline_delay_ms"] == before + 10125, "host/duplicate acknowledgement credit incorrect")
	network_result["match_id"] = "metrics-guest"
	network_result["player_peer_id"] = 2
	network_result["enemy_peer_id"] = 1
	NetworkManager._apply_match_finished(network_result)
	_check(Game.meta_progress["achievement_stats"]["timeline_delay_ms"] == before + 11625, "guest orientation credit incorrect")
	NetworkManager._local_participant_role = LanProtocol.ROLE_SPECTATOR
	network_result["match_id"] = "metrics-spectator"
	NetworkManager._apply_match_finished(network_result)
	NetworkManager._local_participant_role = LanProtocol.ROLE_PLAYER
	network_result["match_id"] = "metrics-other-pair"
	network_result["enemy_peer_id"] = 3
	NetworkManager._apply_match_finished(network_result)
	_check(Game.meta_progress["achievement_stats"]["timeline_delay_ms"] == before + 11625, "spectator or other pair credited")
	NetworkManager._clear_session(false)


func _test_infinite() -> void:
	Game.meta_progress = _fresh()
	Game.meta_progress["infinite_mode_unlocked"] = true
	_check(Game.start_infinite_run("balanced", 4242), "infinite fixture failed")
	var node: Dictionary = Game.get_current_step_data()["nodes"][0]
	Game.select_map_node(String(node["id"]))
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	_engines.append(engine)
	engine.setup(Game.current_run, Game.pending_enemy_id)
	engine.battle_state.winner = "player"
	engine.battle_state.battle_time = 1.0
	Game.complete_battle(engine.build_summary(false))
	_check(Game.meta_progress["achievement_stats"]["infinite_score_total"] == 100, "efficiency points not credited when earned")
	Game.skip_reward()
	_check(Game.meta_progress["achievement_stats"]["infinite_score_total"] == 1100, "step points not credited")
	_check(not _service.record_infinite_score(Game.meta_progress, Game.current_run), "score was credited twice")
	Game.stash_active_run_for_hub()
	Game.resume_suspended_run(Game.RUN_SETUP_MODE_NORMAL)
	_check(Game.meta_progress["achievement_stats"]["infinite_score_total"] == 1100, "resume duplicated infinite score")
	var save: SaveData = SaveData.from_dict(Game.build_save_data("map").to_dict())
	Game.apply_loaded_save(save)
	_check(Game.meta_progress["achievement_stats"]["infinite_score_total"] == 1100, "load duplicated infinite score")
	Game.start_infinite_run("balanced", 4242)
	InfiniteScoreResolver.new().record_step(Game.current_run, {"id": "new-run-step", "type": "event"}, 0)
	_service.record_infinite_score(Game.meta_progress, Game.current_run)
	_check(Game.meta_progress["achievement_stats"]["infinite_score_total"] == 2100, "scores did not accumulate across same-seed runs")
	Game.current_run.infinite_score["preview"] = true
	InfiniteScoreResolver.new().record_step(Game.current_run, {"id": "preview", "type": "event"}, 1)
	_check(not _service.record_infinite_score(Game.meta_progress, Game.current_run) and Game.meta_progress["achievement_stats"]["infinite_score_total"] == 2100, "developer preview credited")


func _test_ui() -> void:
	Game.current_run = null
	Game.meta_progress = _fresh()
	Game.settings["developer_mode"] = true
	Game.set_language("ja")
	Game.meta_progress["achievement_stats"]["timeline_delay_ms"] = 10125
	var scene: Control = load("res://scenes/meta/MetaProgress.tscn").instantiate() as Control
	add_child(scene)
	for frame: int in 180:
		if scene.call("is_content_ready"): break
		await get_tree().process_frame
	var label: Label = scene.find_child("AchievementProgress_timeline_delayer", true, false) as Label
	_check(label != null and label.text == "10.1秒 / 10秒", "progress must display seconds, not milliseconds")
	_check(MetaProgressService.format_achievement_progress({"progress_unit": "seconds", "current": 9999, "target": 10000}) == "9.9秒 / 10秒", "rounding must not imply an unreached threshold is complete")
	for id: String in NEW_IDS:
		_check(scene.find_child("ClaimAchievement_" + id, true, false) != null, "new achievement UI missing")
	var button: Button = scene.find_child("DevMetaAdvanceSeconds", true, false) as Button
	_check(button != null, "developer progress action missing")
	button.pressed.emit()
	_check(Game.meta_progress["achievement_stats"]["timeline_advance_ms"] == 10000, "developer progress action failed")
	_check(SaveManager.has_pending_save(), "progress changes were not scheduled for save")
