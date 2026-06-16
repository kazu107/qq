extends RefCounted
class_name RunSummaryResolver


func summarize(run_state: RunState, last_battle_summary: Dictionary) -> Dictionary:
	var starter_id: String = run_state.starter_id
	var starter_name: String = Localization.get_starter_name(starter_id)
	var enemy_id: String = String(last_battle_summary.get("enemy_id", ""))
	return {
		"starter_id": starter_id,
		"starter_name": starter_name,
		"seed": run_state.seed,
		"current_area": run_state.current_area,
		"encounters_cleared": run_state.encounters_cleared,
		"gold": run_state.gold,
		"remaining_hp": run_state.player_hp,
		"relic_count": run_state.relics.size(),
		"relic_ids": run_state.relics.duplicate(),
		"relic_names": RelicService.new().get_relic_names(run_state.relics),
		"defeated": run_state.defeated,
		"run_complete": run_state.run_complete,
		"last_enemy_id": enemy_id,
		"last_enemy": Localization.get_enemy_name(enemy_id, String(last_battle_summary.get("enemy_name", ""))),
		"last_winner": String(last_battle_summary.get("winner", "")),
	}
