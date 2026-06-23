extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.developer_reset_meta_progress()
	call_deferred("_run")


func _run() -> void:
	_test_new_content_database()
	if _failed:
		return
	_test_enemy_hp_balance()
	if _failed:
		return
	_test_new_relic_effects()
	if _failed:
		return
	_test_new_enemy_battles()
	if _failed:
		return
	_test_base_rank_and_unlock()
	if _failed:
		return
	await _test_extended_midboss_and_final_rank()
	if _failed:
		return
	await _test_rift_midboss_and_final_rank()
	if _failed:
		return
	await _test_eternity_midboss_and_final_rank()
	if _failed:
		return
	Game.developer_reset_meta_progress()
	print("Progression tier smoke passed: rank achievements, Steps 8-28, midboss flow, infinite unlock, and new content")
	get_tree().quit(0)


func _test_enemy_hp_balance() -> void:
	var expected_hp: Dictionary = {
		"scout": 21,
		"brute": 33,
		"disruptor": 25,
		"guardian": 39,
		"raider": 28,
		"medic_drone": 30,
		"chronoguard": 35,
		"boss_timekeeper": 77,
		"phase_stalker": 47,
		"void_bastion": 67,
		"echo_revenant": 54,
		"boss_paradox_core": 132,
		"rift_predator": 71,
		"entropy_colossus": 99,
		"boss_axiom_breaker": 192,
		"omega_seraph": 105,
		"grave_architect": 147,
		"boss_eternity_zero": 276,
	}
	if Database.enemies.size() != expected_hp.size():
		_fail("Progression tier smoke failed: enemy HP balance table does not cover every enemy")
		return
	for enemy_id: String in expected_hp:
		var enemy_def: EnemyDef = Database.get_enemy(enemy_id)
		if enemy_def == null or enemy_def.max_hp != int(expected_hp[enemy_id]):
			_fail("Progression tier smoke failed: unexpected max HP for %s" % enemy_id)
			return


func _test_new_content_database() -> void:
	for enemy_id: String in [
		"phase_stalker", "void_bastion", "echo_revenant", "boss_paradox_core",
		"rift_predator", "entropy_colossus", "boss_axiom_breaker",
		"omega_seraph", "grave_architect", "boss_eternity_zero",
	]:
		if Database.get_enemy(enemy_id) == null:
			_fail("Progression tier smoke failed: missing enemy %s" % enemy_id)
			return
		if not ResourceLoader.exists("res://assets/portraits/%s.png" % enemy_id):
			_fail("Progression tier smoke failed: missing portrait for %s" % enemy_id)
			return
	for card_id: String in [
		"phase_lance", "mirror_aegis", "null_cascade", "paradox_loop",
		"rift_volley", "entropy_armor", "axiom_sever",
		"omega_ray", "grave_protocol", "zero_hour",
		"aegis_ram", "barrier_overdrive", "bulwark_cannon",
	]:
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null or card_def.effects.is_empty():
			_fail("Progression tier smoke failed: missing functional card %s" % card_id)
			return
		if not ResourceLoader.exists("res://assets/icons/cards/%s.png" % card_id):
			_fail("Progression tier smoke failed: missing card art for %s" % card_id)
			return
	for relic_id: String in [
		"phase_capacitor", "echo_coil", "paradox_prism",
		"rift_compass", "entropy_battery", "omega_crown", "eternity_engine",
	]:
		if Database.get_relic(relic_id) == null:
			_fail("Progression tier smoke failed: missing relic %s" % relic_id)
			return
		if not ResourceLoader.exists("res://assets/icons/relics/%s.png" % relic_id):
			_fail("Progression tier smoke failed: missing relic art for %s" % relic_id)
			return


func _test_new_enemy_battles() -> void:
	for enemy_id: String in [
		"phase_stalker", "void_bastion", "echo_revenant", "boss_paradox_core",
		"rift_predator", "entropy_colossus", "boss_axiom_breaker",
		"omega_seraph", "grave_architect", "boss_eternity_zero",
	]:
		Game.start_new_run("balanced", 43003)
		Game.current_run.attack += 40
		Game.current_run.max_hp += 500
		Game.current_run.player_hp = Game.current_run.max_hp
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
		engine.setup(Game.current_run, enemy_id)
		var elapsed: float = 0.0
		while engine.battle_state.winner == "" and elapsed < 300.0:
			_request_first_available_player_card(engine)
			engine.update(0.1)
			elapsed += 0.1
		if engine.battle_state.winner != "player":
			_fail("Progression tier smoke failed: boosted simulation did not defeat %s" % enemy_id)
			return


func _test_new_relic_effects() -> void:
	Game.start_new_run("balanced", 45005)
	for relic_id: String in ["rift_compass", "entropy_battery", "omega_crown", "eternity_engine"]:
		if not Game._relic_service.grant_relic(Game.current_run, relic_id):
			_fail("Progression tier smoke failed: could not grant relic %s" % relic_id)
			return
	Game.current_run.player_hp = Game.current_run.max_hp - 20
	var hp_before: int = Game.current_run.player_hp
	var victory_bonus: Dictionary = Game._relic_service.apply_victory_bonuses(Game.current_run)
	if int(victory_bonus.get("heal", 0)) != 8 or Game.current_run.player_hp != hp_before + 8:
		_fail("Progression tier smoke failed: Entropy Battery did not heal 8 HP")
		return
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.setup(Game.current_run, "scout")
	var player: UnitState = engine.battle_state.player
	if player.speed != Game.current_run.speed + 2:
		_fail("Progression tier smoke failed: Rift Compass did not grant 2 speed")
		return
	if player.attack != Game.current_run.attack + 3:
		_fail("Progression tier smoke failed: Omega Crown did not grant 3 attack")
		return
	if player.shield != 10 or not is_equal_approx(player.cast_time_modifier, 0.85):
		_fail("Progression tier smoke failed: Eternity Engine modifiers were not applied")


func _request_first_available_player_card(engine: RealtimeBattleEngine) -> void:
	for runtime_state: CardRuntimeState in engine.battle_state.player.get_sorted_runtime_states():
		if not runtime_state.can_use():
			continue
		var card_def: CardDef = CardUpgradeResolver.build_effective_card(runtime_state.card_id, Game.current_run)
		if card_def == null:
			continue
		if engine.battle_state.player.active_slots_used + card_def.active_slot_cost > engine.battle_state.player.active_slot_max:
			continue
		engine.request_use_card("player", runtime_state.runtime_id)
		return


func _test_base_rank_and_unlock() -> void:
	Game.start_new_run("balanced", 41001)
	if Game.get_map_step_count() != 7:
		_fail("Progression tier smoke failed: default progression should generate 7 steps")
		return
	_prepare_boss_step(6)
	Game.complete_battle(_build_victory_summary("boss_timekeeper", 80.0))
	if not Game.current_run.run_complete:
		_fail("Progression tier smoke failed: Step 7 boss should finish the base run")
		return
	var stats: Dictionary = Game._meta_progress_service.get_achievement_stats(Game.meta_progress)
	for stat_id: String in ["rank_b_tier_1", "rank_a_tier_1", "rank_s_tier_1"]:
		if int(stats.get(stat_id, 0)) != 1:
			_fail("Progression tier smoke failed: base S clear did not advance %s" % stat_id)
			return
	if not Game.claim_meta_achievement("rank_s_tier_1"):
		_fail("Progression tier smoke failed: base S achievement was not claimable")
		return
	if Game.get_unlocked_step_tier() != 2:
		_fail("Progression tier smoke failed: base S reward did not unlock Steps 8-14")


func _test_extended_midboss_and_final_rank() -> void:
	Game.start_new_run("balanced", 42002)
	if Game.get_map_step_count() != 14:
		_fail("Progression tier smoke failed: tier 2 progression should generate 14 steps")
		return
	var map_scene: Control = load("res://scenes/map/Map.tscn").instantiate() as Control
	add_child(map_scene)
	await get_tree().process_frame
	if map_scene.find_child("MapStep_13", true, false) == null:
		_fail("Progression tier smoke failed: map UI did not render Step 14")
		return
	map_scene.queue_free()
	await get_tree().process_frame
	var steps: Array = Array(Game.current_run.map_state.get("steps", []))
	var final_step: Dictionary = Dictionary(steps[13])
	var final_nodes: Array = Array(final_step.get("nodes", []))
	if final_nodes.is_empty() or String(Dictionary(final_nodes[0]).get("enemy_id", "")) != "boss_paradox_core":
		_fail("Progression tier smoke failed: Step 14 should contain Paradox Core")
		return

	_prepare_boss_step(6)
	Game.complete_battle(_build_victory_summary("boss_timekeeper", 80.0))
	if Game.current_run.run_complete or Game.current_screen_hint != "reward" or Game.reward_options.is_empty():
		_fail("Progression tier smoke failed: Step 7 should become a rewarded midboss in a 14-step run")
		return
	Game.skip_reward()
	if Game.get_current_step_index() != 7 or Game.current_screen_hint != "map":
		_fail("Progression tier smoke failed: midboss reward did not advance to Step 8")
		return

	_prepare_boss_step(13)
	Game.complete_battle(_build_victory_summary("boss_paradox_core", 145.0))
	if not Game.current_run.run_complete or Game.current_screen_hint != "result":
		_fail("Progression tier smoke failed: Step 14 boss did not finish the extended run")
		return
	var summary: Dictionary = Game.get_run_summary()
	if String(summary.get("rank", "")) != "S":
		_fail("Progression tier smoke failed: calibrated extended clear should produce S rank")
		return
	var stats: Dictionary = Game._meta_progress_service.get_achievement_stats(Game.meta_progress)
	for stat_id: String in ["rank_b_tier_2", "rank_a_tier_2", "rank_s_tier_2"]:
		if int(stats.get(stat_id, 0)) != 1:
			_fail("Progression tier smoke failed: extended S clear did not advance %s" % stat_id)
			return
	if not Game.claim_meta_achievement("rank_s_tier_2"):
		_fail("Progression tier smoke failed: extended S achievement was not claimable")
		return
	if Game.get_unlocked_step_tier() != 3:
		_fail("Progression tier smoke failed: tier 2 S reward did not unlock Steps 15-21")


func _test_rift_midboss_and_final_rank() -> void:
	Game.start_new_run("balanced", 43003)
	if Game.get_map_step_count() != 21:
		_fail("Progression tier smoke failed: tier 3 progression should generate 21 steps")
		return
	await _assert_map_renders_step("MapStep_20", "Step 21")
	if _failed:
		return
	if not _assert_step_boss(20, "boss_axiom_breaker", "Step 21"):
		return

	_prepare_boss_step(13)
	Game.complete_battle(_build_victory_summary("boss_paradox_core", 145.0))
	if Game.current_run.run_complete or Game.current_screen_hint != "reward" or Game.reward_options.is_empty():
		_fail("Progression tier smoke failed: Step 14 should become a rewarded midboss in a 21-step run")
		return
	Game.skip_reward()
	if Game.get_current_step_index() != 14 or Game.current_screen_hint != "map":
		_fail("Progression tier smoke failed: Step 14 midboss reward did not advance to Step 15")
		return

	_prepare_boss_step(20)
	Game.complete_battle(_build_victory_summary("boss_axiom_breaker", 190.0))
	if not _assert_final_s_rank(3, "Step 21"):
		return
	if not Game.claim_meta_achievement("rank_s_tier_3"):
		_fail("Progression tier smoke failed: tier 3 S achievement was not claimable")
		return
	if Game.get_unlocked_step_tier() != 4:
		_fail("Progression tier smoke failed: tier 3 S reward did not unlock Steps 22-28")


func _test_eternity_midboss_and_final_rank() -> void:
	Game.start_new_run("balanced", 44004)
	if Game.get_map_step_count() != 28:
		_fail("Progression tier smoke failed: tier 4 progression should generate 28 steps")
		return
	await _assert_map_renders_step("MapStep_27", "Step 28")
	if _failed:
		return
	if not _assert_step_boss(27, "boss_eternity_zero", "Step 28"):
		return

	_prepare_boss_step(20)
	Game.complete_battle(_build_victory_summary("boss_axiom_breaker", 190.0))
	if Game.current_run.run_complete or Game.current_screen_hint != "reward" or Game.reward_options.is_empty():
		_fail("Progression tier smoke failed: Step 21 should become a rewarded midboss in a 28-step run")
		return
	Game.skip_reward()
	if Game.get_current_step_index() != 21 or Game.current_screen_hint != "map":
		_fail("Progression tier smoke failed: Step 21 midboss reward did not advance to Step 22")
		return

	_prepare_boss_step(27)
	Game.complete_battle(_build_victory_summary("boss_eternity_zero", 240.0))
	if not _assert_final_s_rank(4, "Step 28"):
		return
	if not Game.claim_meta_achievement("rank_s_tier_4"):
		_fail("Progression tier smoke failed: tier 4 S achievement was not claimable")
		return
	if not Game.is_infinite_mode_unlocked():
		_fail("Progression tier smoke failed: tier 4 S reward did not unlock Infinite Mode")


func _assert_map_renders_step(node_name: String, label: String) -> void:
	var map_scene: Control = load("res://scenes/map/Map.tscn").instantiate() as Control
	add_child(map_scene)
	await get_tree().process_frame
	if map_scene.find_child(node_name, true, false) == null:
		_fail("Progression tier smoke failed: map UI did not render %s" % label)
	map_scene.queue_free()
	await get_tree().process_frame


func _assert_step_boss(step_index: int, enemy_id: String, label: String) -> bool:
	var steps: Array = Array(Game.current_run.map_state.get("steps", []))
	var step_data: Dictionary = Dictionary(steps[step_index])
	var nodes: Array = Array(step_data.get("nodes", []))
	if nodes.is_empty() or String(Dictionary(nodes[0]).get("enemy_id", "")) != enemy_id:
		_fail("Progression tier smoke failed: %s should contain %s" % [label, enemy_id])
		return false
	return true


func _assert_final_s_rank(tier: int, label: String) -> bool:
	if not Game.current_run.run_complete or Game.current_screen_hint != "result":
		_fail("Progression tier smoke failed: %s boss did not finish the run" % label)
		return false
	var summary: Dictionary = Game.get_run_summary()
	if String(summary.get("rank", "")) != "S":
		_fail("Progression tier smoke failed: calibrated tier %d clear should produce S rank" % tier)
		return false
	var stats: Dictionary = Game._meta_progress_service.get_achievement_stats(Game.meta_progress)
	for rank_letter: String in ["b", "a", "s"]:
		var stat_id: String = "rank_%s_tier_%d" % [rank_letter, tier]
		if int(stats.get(stat_id, 0)) != 1:
			_fail("Progression tier smoke failed: tier %d S clear did not advance %s" % [tier, stat_id])
			return false
	return true


func _prepare_boss_step(step_index: int) -> void:
	var steps: Array = Array(Game.current_run.map_state.get("steps", []))
	var step_data: Dictionary = Dictionary(steps[step_index])
	var nodes: Array = Array(step_data.get("nodes", []))
	var boss_node: Dictionary = Dictionary(nodes[0])
	boss_node["status"] = "available"
	nodes[0] = boss_node
	step_data["nodes"] = nodes
	steps[step_index] = step_data
	Game.current_run.map_state["steps"] = steps
	Game.current_run.map_state["current_step"] = step_index
	Game.select_map_node(String(boss_node.get("id", "")))


func _build_victory_summary(enemy_id: String, battle_time: float) -> Dictionary:
	var enemy_def: EnemyDef = Database.get_enemy(enemy_id)
	return {
		"winner": "player",
		"enemy_id": enemy_id,
		"enemy_name": enemy_def.name if enemy_def != null else enemy_id,
		"player_hp": Game.current_run.max_hp,
		"battle_time": battle_time,
		"battle_events": [],
	}


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
