extends Node


func _ready() -> void:
	Database.load_all(); Game.ensure_meta_initialized(); Game.set_developer_mode_enabled(false)
	call_deferred("_run")


func _stats(values: Array[float]) -> Dictionary:
	var sorted: Array[float] = values.duplicate(); sorted.sort()
	var total: float = 0
	for value: float in values: total += value
	return {"mean_ms": snappedf(total / max(1, values.size()), .001), "p95_ms": sorted[mini(sorted.size() - 1, floori(sorted.size() * .95))], "max_ms": sorted[-1]}


func _run() -> void:
	for count: int in [0, 30]:
		Game.start_new_run("balanced", 4242)
		Game.current_run.max_hp = 10000; Game.current_run.player_hp = 10000
		Game.current_run.relics.assign(Database.get_all_relic_ids().slice(0, count))
		Game.pending_enemy_id = "scout"
		var battle: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control
		add_child(battle); battle.set_process(false)
		var engine: RealtimeBattleEngine = battle.get("_engine") as RealtimeBattleEngine
		engine.set_audio_enabled(false); engine.set_enemy_ai_enabled(false)
		for frame: int in 5: await get_tree().process_frame
		var times: Dictionary = {"ui": [], "banner": [], "hand": [], "timeline": [], "status": []}
		for frame: int in 90:
			var state: BattleState = engine.battle_state
			state.battle_time = frame / 60.0
			var start: int = Time.get_ticks_usec(); battle.call("_refresh_ui", 1.0)
			times["ui"].append((Time.get_ticks_usec() - start) / 1000.0)
			start = Time.get_ticks_usec(); (battle.get("_run_info_banner") as RunInfoBanner).refresh(state.player.hp, state.player.max_hp)
			times["banner"].append((Time.get_ticks_usec() - start) / 1000.0)
			start = Time.get_ticks_usec(); (battle.get("_card_hand_panel") as CardHandPanel).refresh_cards(state.player, Game.current_run)
			times["hand"].append((Time.get_ticks_usec() - start) / 1000.0)
			start = Time.get_ticks_usec(); (battle.get("_timeline_panel") as TimelinePanel).refresh_timeline(state.timeline, state.battle_time, Game.current_run, null, null, "player", null, state.player, state.enemy)
			times["timeline"].append((Time.get_ticks_usec() - start) / 1000.0)
			start = Time.get_ticks_usec(); (battle.get("_battle_stage") as BattleStage3D).refresh_unit_status(state.player, state.enemy)
			times["status"].append((Time.get_ticks_usec() - start) / 1000.0)
			await get_tree().process_frame
		var report: Dictionary = {"relics": count}
		for key: String in times:
			var values: Array[float] = []; values.assign(times[key]); report[key] = _stats(values)
		print("BATTLE_FRAME_PROFILE " + JSON.stringify(report))
		battle.queue_free(); await get_tree().process_frame
	get_tree().quit()
