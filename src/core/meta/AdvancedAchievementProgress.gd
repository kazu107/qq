extends RefCounted
class_name AdvancedAchievementProgress

const DEFAULT_STATS: Dictionary = {
	"reservation_uses":0, "echo_uses":0, "max_reservation_kinds":0, "regen_healing":0,
	"converted_damage":0, "max_auto_resolutions":0, "statuses_cleansed":0, "max_hit_damage":0,
	"flawless_wins":0, "comeback_wins":0, "clutch_interrupts":0, "hazards_completed":0,
	"actual_damage_total":0, "shield_blocked_total":0, "card_types_used":0,
	"starters_cleared":0, "infinite_best_step":0, "arena_best_streak":0,
}


static func eligible(run: RunState) -> bool:
	return run != null and not bool(run.achievement_state.get("excluded", false)) and not bool(run.infinite_score.get("preview", false))


static func _once(run: RunState, bucket: String, receipt: String) -> bool:
	if receipt == "": return false
	var receipts: Array = Array(run.achievement_state.get(bucket, []))
	if receipts.has(receipt): return false
	receipts.append(receipt)
	if receipts.size() > 512: receipts.pop_front()
	run.achievement_state[bucket] = receipts
	return true


static func record_battle(meta: Dictionary, run: RunState, summary: Dictionary, side: String = "player", online_participant: bool = false) -> bool:
	if side not in ["player", "enemy"] or not eligible(run) or not bool(summary.get("achievement_eligible", false)) or (bool(summary.get("pvp", false)) and not online_participant) or bool(summary.get("simulation", false)) or bool(summary.get("balance_sandbox", false)): return false
	if String(summary.get("winner", "")) not in ["player", "enemy", "draw"]: return false
	var analysis: Dictionary = Dictionary(summary.get("analysis", {}))
	var all_metrics: Dictionary = Dictionary(analysis.get("achievement_metrics", {}))
	if not all_metrics.has(side) or not _once(run, "battle_receipts", String(summary.get("control_receipt_id", ""))): return false
	var stats: Dictionary = meta["achievement_stats"]
	var values: Dictionary = Dictionary(all_metrics[side])
	var totals: Dictionary = Dictionary(Dictionary(analysis.get("totals", {})).get(side, {}))
	for key: String in ["reservation_uses", "echo_uses", "regen_healing", "clutch_interrupts"]:
		stats[key] = int(stats.get(key, 0)) + maxi(0, int(values.get(key, 0)))
	for pair: Array in [["converted_damage","prevented"], ["actual_damage_total","damage"], ["shield_blocked_total","blocked"]]:
		stats[pair[0]] = int(stats.get(pair[0], 0)) + maxi(0, int(totals.get(pair[1], 0)))
	stats["statuses_cleansed"] = int(stats.get("statuses_cleansed", 0)) + maxi(0, int(values.get("cleanses", 0)))
	for pair: Array in [["max_reservation_kinds","max_reservation_kinds"], ["max_auto_resolutions","auto_resolutions"], ["max_hit_damage","max_hit"]]:
		stats[pair[0]] = maxi(int(stats.get(pair[0], 0)), int(values.get(pair[1], 0)))
	var cards: Array = Array(meta.get("achievement_used_cards", []))
	for id: String in Array(values.get("card_ids", [])):
		var card: CardDef = Database.get_card(id)
		if card != null and not card.boss_only and not card.enemy_only and not cards.has(id): cards.append(id)
	meta["achievement_used_cards"] = cards
	stats["card_types_used"] = maxi(int(stats.get("card_types_used",0)),cards.size())
	var won: bool = summary["winner"] == side and not bool(summary.get("forced_hazard_withdraw", false))
	if won and int(values.get("hp_lost", -1)) == 0: stats["flawless_wins"] = int(stats.get("flawless_wins", 0)) + 1
	if won and float(values.get("lowest_hp_ratio", 1)) <= 0.2000001: stats["comeback_wins"] = int(stats.get("comeback_wins", 0)) + 1
	if run.arena_mode and not online_participant:
		var streak: int = int(run.achievement_state.get("arena_streak", 0)) + 1 if won else 0
		run.achievement_state["arena_streak"] = streak
		stats["arena_best_streak"] = maxi(int(stats.get("arena_best_streak", 0)), streak)
	return true


static func record_hazard(meta: Dictionary, run: RunState, node: Dictionary) -> bool:
	if not eligible(run) or run.arena_mode or not bool(run.achievement_state.get("last_battle_eligible", false)): return false
	var queue: Array = Array(node.get("hazard_queue", []))
	if queue.is_empty() or int(node.get("hazard_cleared_waves", 0)) < queue.size() or not _once(run, "hazard_receipts", String(node.get("id", ""))): return false
	var stats: Dictionary = meta["achievement_stats"]
	stats["hazards_completed"] = int(stats.get("hazards_completed", 0)) + 1
	return true


static func record_clear(meta: Dictionary, run: RunState) -> bool:
	if not eligible(run) or not bool(run.achievement_state.get("last_battle_eligible", false)) or run.arena_mode or run.infinite_mode or run.defeated or not run.run_complete or bool(run.achievement_state.get("clear_recorded", false)): return false
	run.achievement_state["clear_recorded"] = true
	var starters: Array = Array(meta.get("achievement_cleared_starters", []))
	if Database.get_starter(run.starter_id).is_empty(): return false
	if not starters.has(run.starter_id): starters.append(run.starter_id)
	meta["achievement_cleared_starters"] = starters
	meta["achievement_stats"]["starters_cleared"] = maxi(int(meta["achievement_stats"].get("starters_cleared",0)),starters.size())
	return true


static func record_infinite_step(meta: Dictionary, run: RunState, cleared_steps: int) -> void:
	if not eligible(run) or not run.infinite_mode or run.arena_mode: return
	meta["achievement_stats"]["infinite_best_step"] = maxi(int(meta["achievement_stats"].get("infinite_best_step", 0)), maxi(0, cleared_steps))
